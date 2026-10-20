#!/usr/bin/env bash
# ============================================================
#  upgrade-portal.sh — 在 ECS 上升级官网主站（portal）容器
# ============================================================
#  用法：
#     PORTAL_TAG=v1.0.1 bash scripts/upgrade-portal.sh
#  说明：
#     - portal 是独立镜像，**不会**改 ECS .env 的 IMAGE_TAG（IMAGE_TAG 控制 app/web）
#     - 改的是 /opt/xinya/docker/docker-compose.yml 里 xinya-portal 服务的 image 字段
#     - 然后 pull + 重建容器
#     - 注意：ECS 上实际生效的是 docker-compose.yml（不带 .cloud 后缀）
# ============================================================
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/load-env.sh"
source "$SCRIPT_DIR/ecs.sh"

: "${PORTAL_TAG:?PORTAL_TAG 未设置（例 PORTAL_TAG=v1.0.1）}"

: "${PUBLIC_BASE_URL:?请在 .env 中配置 PUBLIC_BASE_URL}"

echo "=== 1/3 预检查：ACR 上 portal:${PORTAL_TAG} 是否存在 ==="
if ! ecs_cmd "docker manifest inspect ${ACR_REGISTRY}/${ACR_NAMESPACE}/portal:${PORTAL_TAG} >/dev/null 2>&1"; then
  echo "❌ ACR 上 portal:${PORTAL_TAG} 不存在（先 bash scripts/build-and-push-portal.sh 推送？）"
  exit 1
fi
echo "✅ ACR 上 portal:${PORTAL_TAG} 存在"

echo "=== 2/3 改 ECS compose 文件的 portal 镜像 tag ==="
# 注意：ECS 上实际生效的是 docker-compose.yml（不带 .cloud 后缀）
ecs_cmd "sed -i 's|portal:v[0-9.]*|portal:${PORTAL_TAG}|' /opt/xinya/docker/docker-compose.yml && \
         grep -A 1 'xinya-portal' /opt/xinya/docker/docker-compose.yml | head -3"

echo "=== 3/3 pull + 重建 portal 容器 ==="
ecs_cmd "cd /opt/xinya/docker && \
         docker compose --env-file /opt/xinya/.env pull xinya-portal && \
         docker compose --env-file /opt/xinya/.env up -d xinya-portal"

sleep 3
echo
echo "=== 容器状态 ==="
ecs_cmd "docker ps -a | grep portal"

echo
echo "=== 健康检查（portal 容器本地） ==="
ecs_cmd "curl -sI http://127.0.0.1:8081/ | head -3"

echo
echo "=== 健康检查（外层 nginx → portal） ==="
ecs_cmd "curl -sI ${PUBLIC_BASE_URL}/ -k | head -3 && \
         echo && \
         curl -sI ${PUBLIC_BASE_URL}/styles.css -k | head -3"

echo
echo "✅ portal 升级完成：${PORTAL_TAG}"
echo "   镜像：${ACR_REGISTRY}/${ACR_NAMESPACE}/portal:${PORTAL_TAG}"
echo
echo "如果外层 nginx 把 / 兜底到 web 而非 portal，需要手动改 /etc/nginx/nginx.conf："
echo "   location = / { proxy_pass http://127.0.0.1:8081; }    # 精确 / → portal"
echo "   location /styles.css / main.js / /assets/ → 8081"
echo "   兜底 location / { proxy_pass http://127.0.0.1:8080; }  # 走 web SPA fallback"
