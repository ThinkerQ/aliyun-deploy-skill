#!/usr/bin/env bash
# ============================================================
#  deploy-new.sh — 在一台全新 ECS 上做全量首次部署
# ============================================================
#  适用场景：
#    - 项目第一次上 ECS
#    - ECS 重建/迁移
#  假定：Docker / Compose 已装；SSH 已配；你已填好 .env.acr 与 .env.ecs
# ============================================================
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/load-env.sh"
source "$SCRIPT_DIR/ecs.sh"
source "$SCRIPT_DIR/compose-env.sh"

PROJECT_ROOT=$(cd "$(dirname "$XINYA_DOCKER_DIR")" && pwd)

echo "=== 1/9 检测预装 nginx（占 80 端口）==="
HAS_NGINX=$(ecs_cmd "systemctl is-active nginx 2>/dev/null || echo inactive" 2>/dev/null | head -1 || true)
if [[ "$HAS_NGINX" == "active" ]]; then
  read -rp "ECS 上有启用中的 nginx 占 80 端口，是否停掉？(Y/n) " YN
  [[ "${YN:-Y}" =~ ^[Yy]?$ ]] && ecs_cmd "systemctl stop nginx && systemctl disable nginx && echo disabled"
fi

echo "=== 2/9 创建目录骨架 ==="
ecs_cmd "mkdir -p /opt/xinya/{docker,scripts,backup,sql/01-schema,sql/02-init-data,uploadPath,logs} && \
         chmod 755 /opt/xinya && chmod 777 /opt/xinya/uploadPath"

echo "=== 3/9 上传 docker-compose.cloud.yml ==="
ecs_upload "$XINYA_DOCKER_DIR/docker-compose.cloud.yml" "/opt/xinya/docker/docker-compose.yml"

echo "=== 4/9 上传 backup.sh / xinya.service / sql 文件 ==="
ecs_upload "$XINYA_DOCKER_DIR/scripts/backup.sh"      "/opt/xinya/scripts/backup.sh"
# systemd unit 默认随 skill 携带（references/ 下）
SKILL_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
[[ -f "$SKILL_ROOT/references/xinya.service" ]] && \
  ecs_upload "$SKILL_ROOT/references/xinya.service" "/etc/systemd/system/xinya.service"
ecs_upload "$PROJECT_ROOT/sql/01-schema/01-xinya_hours_schema.sql"   "/opt/xinya/sql/01-schema/"
ecs_upload "$PROJECT_ROOT/sql/02-init-data/01-xinya_hours_data.sql"  "/opt/xinya/sql/02-init-data/"

echo "=== 5/9 写 .env ==="
# 配置通过标准输入传递，限制权限，不输出凭据。
: "${MYSQL_ROOT_PASSWORD:?请在 .env 中配置 MYSQL_ROOT_PASSWORD}"
: "${MYSQL_PASSWORD:?请在 .env 中配置 MYSQL_PASSWORD}"
: "${MYSQL_USER:?请在 .env 中配置 MYSQL_USER}"
: "${MYSQL_DATABASE:?请在 .env 中配置 MYSQL_DATABASE}"
deploymentEnv=$(
    compose_env_value ACR_REGISTRY "$ACR_REGISTRY"
    compose_env_value ACR_NAMESPACE "$ACR_NAMESPACE"
    compose_env_value IMAGE_TAG 'v1.0.0'
    compose_env_value MYSQL_ROOT_PASSWORD "$MYSQL_ROOT_PASSWORD"
    compose_env_value MYSQL_PASSWORD "$MYSQL_PASSWORD"
    compose_env_value MYSQL_USER "$MYSQL_USER"
    compose_env_value MYSQL_DATABASE "$MYSQL_DATABASE"
)
printf '%s\n' "$deploymentEnv" | ecs_cmd "umask 077; cat > /opt/xinya/.env && chmod 600 /opt/xinya/.env"
unset deploymentEnv

echo "=== 6/9 backup.sh +x，systemd daemon-reload ==="
ecs_cmd "chmod +x /opt/xinya/scripts/backup.sh ; \
         [[ -f /etc/systemd/system/xinya.service ]] && systemctl daemon-reload ; \
         echo ok"

echo "=== 7/9 安装每日备份 cron ==="
ecs_cmd "echo '0 3 * * * root /opt/xinya/scripts/backup.sh >> /var/log/xinya-backup.log 2>&1' \
         > /etc/cron.d/xinya-backup && chmod 644 /etc/cron.d/xinya-backup && \
         echo 'crontab installed'"

echo "=== 8/9 docker login ACR && 拉取镜像 ==="
printf '%s\n' "$ACR_PASSWORD" | ecs_cmd \
    "docker login $ACR_REGISTRY -u '$ACR_USER' --password-stdin"
ecs_cmd "cd /opt/xinya/docker && docker compose --env-file /opt/xinya/.env pull 2>&1 | tail -10"

echo "=== 9/9 启动 + 等 60s 健康检查 ==="
ecs_cmd "cd /opt/xinya/docker && docker compose --env-file /opt/xinya/.env up -d 2>&1 | tail -10"
sleep 60
ecs_cmd "cd /opt/xinya/docker && docker compose --env-file /opt/xinya/.env ps"

echo
echo "==== 健康检查 ===="
ecs_cmd "curl -sI http://127.0.0.1/ | head -3 && echo && \
         curl -s 'http://127.0.0.1/prod-api/captchaImage' | head -c 100"

# 启用开机自启（如上传过 unit）
ecs_cmd "[[ -f /etc/systemd/system/xinya.service ]] && \
         systemctl enable xinya.service || echo 'skip systemd enable (no unit)'"

echo
echo "✅ 全新部署完成"
echo "   访问： http://${ECS_HOST}/"
echo "   初始化账号信息见本地 .env；实际账号由初始化 SQL 决定"
