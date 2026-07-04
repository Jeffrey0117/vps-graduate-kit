---
name: vps-graduate
description: Use when the user wants to move/graduate a project onto their own VPS and get "git push → auto-deploy", or to turn a fresh VPS into a mini-PaaS. Covers one-command graduation (clone→build→systemd→Caddy TLS→Cloudflare DNS→GitHub webhook), the deployd push-to-deploy engine, private-repo deploy keys, and the language-agnostic $PORT/health contract. Triggers on "搬去 VPS"、"畢業上 VPS"、"push 自動部署"、"self-host"、"graduate.sh"、"deployd".
---

# VPS 畢業 / push→自動部署 Playbook

前提:使用者已 `cp config.example.sh config.sh` 填好(VPS_IP / SSH key / CF token / GITHUB_OWNER / DEPLOY_HOST)。

## 決策
- 全新 VPS → 先 `bash bootstrap.sh`(裝 node/caddy/ufw + deployd)。前置:Cloudflare 加 `DEPLOY_HOST → VPS_IP`(grey)。
- 搬一個專案 → 寫 manifest → `bash graduate.sh <manifest>`(全自動:clone/build/systemd/Caddy/DNS/webhook)。

## manifest 必填
`NAME REPO BRANCH PORT RUNTIME(node|python|ruby|php|binary) ENTRY BUILD DOMAINS HEALTH APP_ENV`。挑沒被佔的 PORT。

## 驗證與除錯(鐵則)
1. `--resolve <域名>:443:<VPS_IP>` 直打 VPS Caddy → 確認 VPS 本身好(繞過 DNS/CF,零風險)。
2. 切 DNS 後的 308/000/526 多是 **CF edge 傳播雜訊**,耐心等數分鐘會收斂;**別反覆翻 DNS、別急著撤**。
3. HEALTH 路徑要對(可能是 /health、/api/health)。build 失敗別重啟。

## 語言無關
app 讀 `$PORT` + 有 health path + env 設定 → 什麼語言都能上。相依很髒才考慮 Docker(且只在 Linux VPS 上、一次一個容器)。

## 適合 / 不適合搬
- 適合:無狀態 / 外部DB(或把共用 DB、mailer 等原件也放 VPS 同 port)/ 純檔案狀態(scp 過去)。
- 要小心:多租戶共用 DB(不能拆半)、本地 SQLite(要搬 db 檔)、跑瀏覽器/影片/ML(吃 RAM)、Next 大專案(先看 RAM 或升級機器)。

詳見 README.md 與 CLAUDE.md。
