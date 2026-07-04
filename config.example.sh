# 複製成 config.sh 填你自己的值(config.sh 已 gitignore,不會外流)。
#   cp config.example.sh config.sh && 編輯

VPS_IP="1.2.3.4"                               # 你的 VPS 公網固定 IP
VPS_SSH_KEY="$HOME/.vps/ssh_key"               # 連 VPS 的 SSH 私鑰路徑
CF_TOKEN_FILE="$HOME/.cloudflare-token"        # Cloudflare API Token(權限:Edit zone DNS)存這個檔
DEPLOY_SECRET_FILE="$HOME/.vps/deploy_secret"  # deployd 的 GitHub webhook 密鑰(bootstrap 會產)
GITHUB_OWNER="YourGithubUser"                  # 你的 GitHub 帳號(repo owner)
DEPLOY_HOST="deploy.yourdomain.com"            # deployd 對外網域(webhook 打這裡)
