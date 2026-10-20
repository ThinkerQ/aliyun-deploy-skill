#!/usr/bin/env bash
# ============================================================
#  logs.sh — 看指定服务最近日志（先打印 ERROR 行，方便定位）
# ============================================================
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/load-env.sh"
source "$SCRIPT_DIR/ecs.sh"

SERVICE="${SERVICE:-xinya-app}"           # 默认后端
TAIL="${TAIL:-100}"                        # 行数

# service 名 → container 名映射
declare -A container_for=(
  [xinya-app]="c-xinya-app"
  [xinya-web]="c-xinya-web"
  [xinya-mysql]="c-xinya-mysql"
  [xinya-redis]="c-xinya-redis"
  [app]="c-xinya-app"
  [web]="c-xinya-web"
  [mysql]="c-xinya-mysql"
  [redis]="c-xinya-redis"
)
CONTAINER="${container_for[$SERVICE]:-$SERVICE}"

echo "==== 服务 $SERVICE (容器 $CONTAINER) 最近 ERROR 行 ===="
ecs_cmd "docker logs $CONTAINER --tail=$TAIL 2>&1 | grep -iE ' ERROR | Caused by:|\\[emerg\\] | host not found' | head -10" || true
echo
echo "==== 最近 $TAIL 行日志 ===="
ecs_cmd "docker logs $CONTAINER --tail=$TAIL 2>&1 | tail -$TAIL"
