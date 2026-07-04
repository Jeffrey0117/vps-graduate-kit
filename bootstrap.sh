#!/usr/bin/env bash
# bootstrap.sh — 把一台全新的 Ubuntu VPS 變成「push→自動部署」的迷你 PaaS。
# 前置:① cp config.example.sh config.sh 填好 ② VPS_SSH_KEY 能 ssh root 進 VPS
#      ③ Cloudflare 加一筆 A 記錄 <DEPLOY_HOST> → <VPS_IP>(DNS only/grey)
# 用法: bash bootstrap.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/config.sh" ] || { echo "缺 config.sh"; exit 1; }
source "$HERE/config.sh"
SSH="ssh -i $VPS_SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new root@$VPS_IP"

echo "▶ 1) 裝 node / caddy / ufw / build tools"
$SSH "bash -s" <<'R'
set -e
export DEBIAN_FRONTEND=noninteractive
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
apt-get install -y nodejs build-essential python3 debian-keyring debian-archive-keyring apt-transport-https curl gnupg >/dev/null 2>&1
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list 2>/dev/null
apt-get update >/dev/null 2>&1 && apt-get install -y caddy >/dev/null 2>&1
ufw allow 22/tcp >/dev/null 2>&1; ufw allow 80/tcp >/dev/null 2>&1; ufw allow 443/tcp >/dev/null 2>&1; ufw --force enable >/dev/null 2>&1
echo "node $(node -v) / caddy $(caddy version | head -1)"
R

echo "▶ 2) 產 deploy secret(給 GitHub webhook)"
mkdir -p "$(dirname "$DEPLOY_SECRET_FILE")"
[ -s "$DEPLOY_SECRET_FILE" ] || openssl rand -hex 32 > "$DEPLOY_SECRET_FILE"
SECRET="$(cat "$DEPLOY_SECRET_FILE")"

echo "▶ 3) 部署 deployd 引擎"
$SSH "mkdir -p /opt/deployd"
scp -i "$VPS_SSH_KEY" -o BatchMode=yes "$HERE/deployd/deployd.js" root@"$VPS_IP":/opt/deployd/
$SSH "[ -f /opt/deployd/registry.json ] || echo '{}' > /opt/deployd/registry.json"
$SSH "bash -s" <<REMOTE
cat > /opt/deployd/.env <<ENV
PORT=4099
DEPLOY_SECRET=$SECRET
ENV
chmod 600 /opt/deployd/.env
cat > /etc/systemd/system/deployd.service <<'UNIT'
[Unit]
Description=deployd — VPS auto-deploy
After=network-online.target
Wants=network-online.target
[Service]
WorkingDirectory=/opt/deployd
EnvironmentFile=/opt/deployd/.env
ExecStart=/usr/bin/node deployd.js
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
UNIT
grep -q '$DEPLOY_HOST {' /etc/caddy/Caddyfile || printf '\n$DEPLOY_HOST {\n\treverse_proxy localhost:4099\n}\n' >> /etc/caddy/Caddyfile
systemctl daemon-reload && systemctl enable deployd >/dev/null 2>&1 && systemctl restart deployd && systemctl reload caddy
sleep 2; echo "deployd: \$(systemctl is-active deployd)  caddy: \$(systemctl is-active caddy)"
REMOTE

echo "▶ 完成。確認 https://$DEPLOY_HOST/health(等憑證~1分):"
echo "   curl https://$DEPLOY_HOST/health"
echo "   接著就能 bash graduate.sh <你的manifest.sh> 把專案一個個畢業上來。"
