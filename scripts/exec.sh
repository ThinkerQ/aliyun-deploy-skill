#!/usr/bin/env bash
# ============================================================
#  exec.sh — 进入 ECS 上的容器调试
# ============================================================
#  容器凭据由 ecs.sh 集中管理，本脚本不接触任何密码
# ============================================================
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/load-env.sh"
source "$SCRIPT_DIR/ecs.sh"

usage() {
  cat <<'USAGE'
用法:
  bash scripts/exec.sh mysql            # 进 mysql CLI
  bash scripts/exec.sh mysql 'SQL语句'   # 执行一条 SQL 后退出
  bash scripts/exec.sh redis 'INFO'     # 跑 redis-cli 命令
  bash scripts/exec.sh app bash         # 进 app 容器 shell
  bash scripts/exec.sh app 'cat app.jar | head'   # 在 app 容器跑命令
  bash scripts/exec.sh portal sh        # 进 portal 容器 shell（看 /usr/share/nginx/html/portal/）
USAGE
  exit 1
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" || -z "${1:-}" ]] && usage

TARGET="$1"; shift || true

case "$TARGET" in
    mysql)
        if [[ "$#" -eq 1 && "$1" != -* ]]; then
            ecs_mysql -e "$1"
        else
            ecs_mysql "$@"
        fi
        ;;
  redis)  ecs_cmd "docker exec -it c-xinya-redis redis-cli $*";;
  app)    ecs_cmd "docker exec -it c-xinya-app $*";;
  web)    ecs_cmd "docker exec -it c-xinya-web $*";;
  portal) ecs_cmd "docker exec -it c-xinya-portal $*";;
  *)      echo "未知目标：$TARGET（支持 mysql / redis / app / web / portal）" >&2; usage;;
esac
