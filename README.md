# 🎓 vps-graduate-kit

把一台便宜的 VPS 變成「**push 就自動部署**」的迷你 PaaS，並用**一行指令**把任何專案（任何語言）搬上去。

> 起源:我(Jeffrey0117)本來一堆 side project 擠在家用機(動態 IP、常掛)。把「紅了 / 要穩」的畢業上 VPS,做成這套可複用工具。搭配 [notes 的 vps-incubator-playbook](https://github.com/Jeffrey0117/notes) 服用。

## 它做什麼

- **一鍵畢業** `graduate.sh <manifest>`:clone → build → systemd(開機自動起/掛了自動重啟) → Caddy(自動 HTTPS 反代) → Cloudflare DNS(自動建 A 記錄) → 掛 GitHub webhook。
- **push 就部署**:`deployd` 收 GitHub push webhook → `git pull + build + restart`(build 失敗不重啟、保住舊版)。
- **語言無關**:node / python / ruby / php / 編譯後 binary 都行(靠約定:讀 `$PORT` + 有 health path)。
- **私有 repo**:自動產 per-repo read-only deploy key,不用把全帳號 token 放 VPS。

## 前置

- 一台 Ubuntu VPS(固定公網 IP)、能 `ssh root` 進去
- Cloudflare 管理你的網域 + 一把 **API Token(權限:Edit zone DNS)**
- 本機有 `gh`(GitHub CLI,已登入)、`curl`、`openssl`、`bash`

## 快速開始

```bash
cp config.example.sh config.sh      # 填 VPS_IP / SSH key / CF token 檔 / GITHUB_OWNER / DEPLOY_HOST
# Cloudflare 先加一筆 A: <DEPLOY_HOST> → <VPS_IP> (grey/DNS only)
bash bootstrap.sh                   # 一鍵把 VPS 裝好(node/caddy/ufw/deployd)
cp example.manifest.sh myapp.manifest.sh   # 改成你的專案
bash graduate.sh myapp.manifest.sh # 畢業!之後 push 就自動部署
```

## manifest 長怎樣

見 `example.manifest.sh`。核心欄位:`NAME REPO BRANCH PORT RUNTIME ENTRY BUILD DOMAINS HEALTH APP_ENV`。

## 檔案

| 檔 | 作用 |
|---|---|
| `config.example.sh` | 複製成 `config.sh` 填你的值(已 gitignore) |
| `bootstrap.sh` | 一次把新 VPS 裝好 + 部署 deployd |
| `graduate.sh` | 一鍵畢業一個專案 + 接上 auto-deploy |
| `deployd/deployd.js` | push→部署引擎(跑在 VPS) |
| `example.manifest.sh` | 專案 manifest 範本 |

## 約定(讓任何語言都能上)

你的 app 只要:① 從 `$PORT` 環境變數讀 port 來聽 ② 有個回 200 的 health path ③ 設定從 env 讀。Caddy + systemd 就不在乎它是什麼語言。

## 授權

MIT。自用/教學/魔改隨意。
