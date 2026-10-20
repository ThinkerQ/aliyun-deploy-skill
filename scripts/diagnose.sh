#!/usr/bin/env bash
# ============================================================
#  diagnose.sh — 一键诊断常见故障（80 端口冲突、容器重启、网络）
# ============================================================
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/load-env.sh"
source "$SCRIPT_DIR/ecs.sh"

echo "==== 1) ECS 80 端口占用方 ===="
ecs_cmd "ss -tlnp | grep ':80\\b'" || echo "  端口 80 空闲"

echo
echo "==== 2) 容器 Restarting / Unhealthy ===="
ecs_cmd "cd /opt/xinya/docker && \
         docker ps -a --format 'table {{.Names}}\t{{.Status}}' | grep -E 'Restarting|Unhealthy|dead' || echo '  全部 healthy'"

echo
echo "==== 3) web 容器是否仍在重启（host not found in upstream）==="
ecs_cmd "docker logs c-xinya-web --tail=30 2>&1 | grep -E 'host not found|emerg' | head -5 || echo '  没发现 upstream 解析问题'"

echo
echo "==== 4) 后端是否有未捕获异常 ===="
ecs_cmd "cd /opt/xinya/docker && \
         docker compose --env-file /opt/xinya/.env logs --tail=200 c-xinya-app 2>&1 | \
         grep -iE ' ERROR | Caused by:' | head -5 || echo '  没有 ERROR'"

echo
echo "==== 5) MySQL 是否真的 init 完成 ===="
ecs_mysql -e 'SELECT COUNT(*) AS total_tables FROM information_schema.tables
    WHERE TABLE_SCHEMA = DATABASE();' | tail -3

echo
echo "==== 诊断建议 ===="
echo "  • 若 80 端口被旧 nginx 占：systemctl stop nginx && systemctl disable nginx"
echo "  • 若 web 容器 'host not found in upstream xinya-app'：compose 文件用了 c-xinya-app 做 service 名；改回 xinya-app"
echo "  • 若 MySQL 表不存在：挂载 SQL 文件必须直接子文件 01-schema.sql，不能在子目录"
echo "  • 完整排错清单：cat ../references/troubleshooting.md"
