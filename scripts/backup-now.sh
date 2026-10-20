#!/usr/bin/env bash
# ============================================================
#  backup-now.sh — 立即跑一次 MySQL 备份
# ============================================================
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/load-env.sh"
source "$SCRIPT_DIR/ecs.sh"

ecs_cmd "bash /opt/xinya/scripts/backup.sh"
echo
echo "==== 最近 5 个备份 ===="
ecs_cmd "ls -lh /opt/xinya/backup/ | tail -6"
