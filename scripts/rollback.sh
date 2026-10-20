#!/usr/bin/env bash
# ============================================================
#  rollback.sh — 回滚到上一个 tag
# ============================================================
#  用法：
#     bash scripts/rollback.sh                         # 用 scripts/.rollback
#     VERSION=v1.0.0 bash scripts/rollback.sh          # 手动指定
# ============================================================
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/load-env.sh"
source "$SCRIPT_DIR/ecs.sh"

if [[ -z "${VERSION:-}" ]]; then
  RB_FILE="$SCRIPT_DIR/.rollback"
  [[ -f "$RB_FILE" ]] || { echo "找不到 $RB_FILE 且未指定 VERSION" >&2; exit 1; }
  VERSION="$(cat $RB_FILE)"
fi
echo "回滚到版本：$VERSION"

# 用 release.sh 里那套拉取+重启逻辑（但跳过 push）
ecs_cmd "sed -i 's/^IMAGE_TAG=.*/IMAGE_TAG=${VERSION}/' /opt/xinya/.env && \
         grep '^IMAGE_TAG=' /opt/xinya/.env"
ecs_cmd "cd /opt/xinya/docker && \
         docker compose --env-file /opt/xinya/.env pull c-xinya-app xinya-web 2>&1 | tail -5 && \
         docker compose --env-file /opt/xinya/.env up -d c-xinya-app xinya-web 2>&1 | tail -8"
sleep 30
ecs_cmd "cd /opt/xinya/docker && docker compose --env-file /opt/xinya/.env ps"
echo
echo "✅ 回滚完成：${VERSION}"
echo "   数据未动（仅替换后端镜像）"
