#!/usr/bin/env bash
# ============================================================
#  reset-data.sh — ⚠️ 危险操作：完全重置 MySQL/Redis 数据
# ============================================================
#  会做：docker compose down -v 删卷 → 用 dump 重新 init
#  不会动：/opt/xinya/uploadPath /opt/xinya/backup /opt/xinya/scripts
# ============================================================
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/load-env.sh"
source "$SCRIPT_DIR/ecs.sh"

cat <<'WARN'
========================================================================
  ⚠️ 危险操作确认

  此脚本将:
    1. 删除 MySQL 数据卷（全部数据库与表）
    2. 删除 Redis 数据卷（全部缓存）
    3. 重新用 docker-entrypoint-initdb.d/01-schema.sql +
       02-data.sql 重新初始化

  **不会影响：**
    - /opt/xinya/uploadPath/  （业务上传文件）
    - /opt/xinya/backup/       （备份文件）
    - ACR 镜像、ECS 系统盘其他目录
========================================================================
WARN

read -rp "确认输入 YES 继续（其他任何输入取消）： " CONFIRM
[[ "$CONFIRM" == "YES" ]] || { echo "已取消"; exit 0; }

echo
echo "=== 建议：先备份当前数据 ==="
read -rp "是否先跑一次 mysqldump？(Y/n) " BKP
[[ "${BKP:-Y}" =~ ^[Yy]?$ ]] && ecs_cmd "bash /opt/xinya/scripts/backup.sh"

echo "=== 重置数据 ==="
ecs_cmd "cd /opt/xinya/docker && \
         docker compose --env-file /opt/xinya/.env down -v 2>&1 | tail -5 ; \
         echo ; \
         docker compose --env-file /opt/xinya/.env up -d 2>&1 | tail -10"

echo "=== 等待 60s 让 MySQL init 跑完 ==="
sleep 60
ecs_mysql -e 'SELECT COUNT(*) AS total_tables FROM information_schema.tables
    WHERE TABLE_SCHEMA = DATABASE();' | tail -3

echo
echo "✅ 数据重置完成"
