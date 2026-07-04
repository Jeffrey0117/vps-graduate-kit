#!/usr/bin/env bash
# graduate.sh — 一鍵把專案「畢業」上你的 VPS + 自動接上 push→部署。語言無關。
# 用法: bash graduate.sh <manifest.sh>   (先 cp config.example.sh config.sh 填好)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
[ -f "$HERE/config.sh" ] || { echo "缺 config.sh — 先 cp config.example.sh config.sh 填你的值"; exit 1; }
source "$HERE/config.sh"
CF_TOKEN="$(cat "$CF_TOKEN_FILE")"
DEPLOY_SECRET="$(cat "$DEPLOY_SECRET_FILE" 2>/dev/null || echo '')"
SSH="ssh -i $VPS_SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new root@$VPS_IP"

[ $# -ge 1 ] || { echo "用法: bash graduate.sh <manifest.sh>"; exit 1; }
set +e; source "$1"; set -e
: "${BRANCH:=main}" "${BUILD:=}" "${HEALTH:=/}" "${STOP_HOME_PM2:=}" "${APP_ENV:=}"
REPO_FULL="$(echo "$REPO" | sed -E 's#https?://github.com/##; s#\.git$##')"
echo "▶ 畢業: $NAME (port $PORT, $RUNTIME, $REPO_FULL) → $DOMAINS"

case "$RUNTIME" in
  node)   EXEC="/usr/bin/node $ENTRY"; APT="";;
  python) EXEC="/usr/bin/python3 $ENTRY"; APT="python3";;
  ruby)   EXEC="/usr/bin/ruby $ENTRY"; APT="ruby-full";;
  php)    EXEC="/usr/bin/php -S 0.0.0.0:$PORT $ENTRY"; APT="php-cli";;
  binary) EXEC="/opt/$NAME/$ENTRY"; APT="";;
  *) echo "未知 RUNTIME=$RUNTIME"; exit 1;;
esac

# Cloudflare zone id by domain suffix
cf() { curl -s -m 15 -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" "$@"; }
cfzone() {
  local d="$1"
  cf "https://api.cloudflare.com/client/v4/zones?per_page=50" \
    | grep -oE '"id":"[a-f0-9]{32}","name":"[^"]*"' \
    | while IFS= read -r line; do
        local zid="${line#*\"id\":\"}"; zid="${zid%%\"*}"
        local zn="${line##*\"name\":\"}"; zn="${zn%%\"*}"
        case "$d" in *".$zn"|"$zn") echo "$zid"; return;; esac
      done
}

# 0) 私有 repo → 自動 deploy key
IS_PRIVATE="$(gh api "repos/$REPO_FULL" --jq .private 2>/dev/null || echo false)"
CLONE_URL="$REPO"
if [ "$IS_PRIVATE" = "true" ]; then
  echo "  🔒 私有 → 設 read-only deploy key"
  PUB=$($SSH "[ -f /root/.ssh/${NAME}_deploy ] || ssh-keygen -t ed25519 -f /root/.ssh/${NAME}_deploy -N '' -C 'vps-${NAME}' >/dev/null 2>&1; cat /root/.ssh/${NAME}_deploy.pub")
  gh api -X POST "repos/$REPO_FULL/keys" -f title="vps-deployd" -f "key=$PUB" -F read_only=true >/dev/null 2>&1 || true
  $SSH "grep -q 'Host github-${NAME}' /root/.ssh/config 2>/dev/null || printf 'Host github-%s\n  HostName github.com\n  User git\n  IdentityFile /root/.ssh/%s_deploy\n  IdentitiesOnly yes\n  StrictHostKeyChecking accept-new\n' '$NAME' '$NAME' >> /root/.ssh/config"
  CLONE_URL="git@github-${NAME}:${REPO_FULL}.git"
fi

# 1) clone/build/env/systemd/start
$SSH "bash -s" <<REMOTE
set -e
[ -z "$APT" ] || { command -v ${APT%%-*} >/dev/null 2>&1 || { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y $APT >/dev/null 2>&1; }; }
cd /opt
[ -d "$NAME/.git" ] || git clone -q -b "$BRANCH" "$CLONE_URL" "$NAME"
cd "/opt/$NAME" && git pull -q 2>/dev/null || true
cat > "/opt/$NAME/.env" <<ENVEOF
$APP_ENV
ENVEOF
chmod 600 "/opt/$NAME/.env"
${BUILD:+$BUILD}
cat > "/etc/systemd/system/$NAME.service" <<UNITEOF
[Unit]
After=network-online.target
Wants=network-online.target
[Service]
WorkingDirectory=/opt/$NAME
EnvironmentFile=/opt/$NAME/.env
ExecStart=$EXEC
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
UNITEOF
systemctl daemon-reload; systemctl enable "$NAME" >/dev/null 2>&1; systemctl restart "$NAME"; sleep 3
echo "  服務: \$(systemctl is-active $NAME)"
curl -s -m 8 -o /dev/null -w "  健康 $HEALTH → %{http_code}\n" "http://127.0.0.1:$PORT$HEALTH" || true
REMOTE

# 2) Caddy
for D in $DOMAINS; do $SSH "grep -q '$D {' /etc/caddy/Caddyfile || printf '\n$D {\n\treverse_proxy localhost:$PORT\n}\n' >> /etc/caddy/Caddyfile"; done
$SSH "systemctl reload caddy"

# 3) Cloudflare DNS(A→VPS grey)
for D in $DOMAINS; do
  ZID=$(cfzone "$D"); [ -n "$ZID" ] || { echo "  ⚠ $D 找不到 CF zone,手動設"; continue; }
  RID=$(cf "https://api.cloudflare.com/client/v4/zones/$ZID/dns_records?name=$D" | grep -o '"id":"[a-f0-9]\{32\}"' | head -1 | cut -d'"' -f4 || true)
  BODY="{\"type\":\"A\",\"name\":\"$D\",\"content\":\"$VPS_IP\",\"proxied\":false,\"ttl\":1}"
  if [ -n "$RID" ]; then cf -X PUT "https://api.cloudflare.com/client/v4/zones/$ZID/dns_records/$RID" -d "$BODY" >/dev/null; else cf -X POST "https://api.cloudflare.com/client/v4/zones/$ZID/dns_records" -d "$BODY" >/dev/null; fi
  echo "  DNS $D → $VPS_IP"
done

# 4) auto-deploy: registry + webhook
if [ -n "$DEPLOY_SECRET" ]; then
  $SSH "NAME='$NAME' RF='$REPO_FULL' BR='$BRANCH' BUILD='$BUILD' node -e '
    const fs=require(\"fs\"),p=\"/opt/deployd/registry.json\";
    const r=JSON.parse(fs.readFileSync(p,\"utf8\"));
    r[process.env.RF]={dir:\"/opt/\"+process.env.NAME,service:process.env.NAME,branch:process.env.BR,build:process.env.BUILD};
    fs.writeFileSync(p,JSON.stringify(r,null,2));'"
  HAS=$(gh api "repos/$REPO_FULL/hooks" --jq '.[].config.url' 2>/dev/null | grep -c "$DEPLOY_HOST" || true)
  [ "${HAS:-0}" != "0" ] || gh api -X POST "repos/$REPO_FULL/hooks" -f name=web -F active=true -f "events[]=push" -f "config[url]=https://$DEPLOY_HOST/hook" -f "config[content_type]=json" -f "config[secret]=$DEPLOY_SECRET" >/dev/null 2>&1 || true
  echo "  ✅ auto-deploy 已接:push $REPO_FULL 自動部署"
fi

[ -z "$STOP_HOME_PM2" ] || pm2 stop "$STOP_HOME_PM2" >/dev/null 2>&1 || true
echo "▲ $NAME 畢業完成"
