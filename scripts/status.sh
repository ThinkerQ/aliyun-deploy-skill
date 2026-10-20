#!/usr/bin/env bash
# ============================================================
#  status.sh — 一键综合状态报告
# ============================================================
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/load-env.sh"
source "$SCRIPT_DIR/ecs.sh"

echo "================================================"
echo "  Xinya ECS 部署状态"
echo "  主机: $ECS_USER@$ECS_HOST   镜像来源: $ACR_REGISTRY/$ACR_NAMESPACE"
echo "================================================"

echo
echo "【1】容器状态"
ecs_cmd "cd /opt/xinya/docker && docker compose --env-file /opt/xinya/.env ps 2>&1" \
  | tail -8

echo
echo "【2】公网端到端测试"
ecs_cmd "curl -sI http://127.0.0.1/ 2>&1 | head -3 ; \
          echo ; \
          curl -s http://127.0.0.1/prod-api/captchaImage 2>&1 | head -c 100 ; \
          echo" 2>&1

echo
echo "【3】资源占用"
ecs_cmd "docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}'" \
  | head -6

echo
echo "【4】磁盘与上传目录"
ecs_cmd "df -h / /opt/xinya /opt/xinya/backup 2>&1 | head -5 ; \
          echo ; \
          echo '--- 上传目录 ---' ; \
          du -sh /opt/xinya/uploadPath 2>/dev/null ; \
          echo '--- 备份 (14 天滚动) ---' ; \
          ls -lh /opt/xinya/backup/ | tail -8" 2>&1

echo
echo "【5】开机自启 + 定时备份"
ecs_cmd "echo '-- systemd xinya --' ; systemctl is-enabled xinya.service ; \
          echo '-- systemd crond --' ; systemctl is-active crond ; \
          echo '-- cron 配置 --' ; cat /etc/cron.d/xinya-backup" 2>&1

echo
echo "【6】最近 ERROR / 启动异常"
ecs_cmd "cd /opt/xinya/docker && \
          docker compose --env-file /opt/xinya/.env logs --tail=200 2>&1 | \
          grep -iE ' ERROR | Caused by:' | head -3" 2>&1 || true

echo
echo "================================================"
echo "  报告完成"
echo "================================================"
