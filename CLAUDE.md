# CLAUDE.md — 給 AI 助手操作這套 kit 的說明

這個 repo 把一台 VPS 變成「push→自動部署」的迷你 PaaS。你(Claude)幫使用者操作時遵守：

## 環境 / 前置
- 使用者的值都在 `config.sh`(從 `config.example.sh` 複製):`VPS_IP`、`VPS_SSH_KEY`、`CF_TOKEN_FILE`、`DEPLOY_SECRET_FILE`、`GITHUB_OWNER`、`DEPLOY_HOST`。**secret/token 只在這些檔,別寫進任何 repo 或對話。**
- 需要 `gh`(已登入)、`curl`、`openssl`、能 ssh root 進 VPS。

## 兩個核心動作
1. **裝新 VPS**:`bash bootstrap.sh`(裝 node/caddy/ufw + 部署 deployd)。前提:Cloudflare 已加 `DEPLOY_HOST → VPS_IP`(grey)。
2. **畢業一個專案**:寫 `<name>.manifest.sh`(見 example) → `bash graduate.sh <name>.manifest.sh`。它會自動 clone/build/systemd/Caddy/DNS/webhook。

## 鐵則(血淚換來的)
- **切完 DNS 別 panic**:剛切 grey↔orange 時,CF edge 傳播中會有暫時的 308/000/526,**會自己好(數分鐘)**。先用 `curl --resolve <域名>:443:<VPS_IP> https://<域名>/` 直打 VPS Caddy 確認「VPS 本身」是好的,再耐心等 CF 收斂。**不要反覆翻 DNS**(越翻越慢)。
- **改 DNS 要抓對「該網域自己的 record id」**(每個子網域不同 id)。
- **HEALTH 路徑要對**(不是每個 app 的 `/` 都回 200;有的健康在 `/api/health`、`/health`)。
- **build 失敗不要重啟**(deployd 已這樣做,保住舊版活著)。
- **私有 repo** 走 per-repo read-only deploy key(graduate.sh 自動處理);別把全帳號 token 放 VPS。
- **同 port 搬家**:共用服務(DB、mailer 之類)放 VPS 用**跟舊機一樣的 port**,這樣 app 之間 `localhost:xxxx` 互叫在 VPS 上原樣可用,不用改碼。

## 語言無關的約定
app 只要:讀 `$PORT`、有 health path、設定從 env 讀。新語言(php/ruby/go…)照 `RUNTIME` 設 → systemd + Caddy 不在乎語言。編譯語言用 `RUNTIME=binary`。

## 新專案畢業後
graduate.sh 會自動:在 VPS `/opt/deployd/registry.json` 加一行 + 掛 GitHub webhook。之後 push 該 repo 就自動部署。確認 `https://<DEPLOY_HOST>/health` 活著。
