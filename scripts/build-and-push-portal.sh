#!/usr/bin/env bash
# ============================================================
#  build-and-push-portal.sh — 构建并推送官网主站（portal）镜像
# ============================================================
#  用法：
#     VERSION=v1.0.1 bash scripts/build-and-push-portal.sh
#  说明：
#     - 静态站点，无构建步骤：直接 COPY ruoyi-ui/public/portal/ 到 nginx:1.27-alpine
#     - 资源被复制到 nginx 容器内 /usr/share/nginx/html/portal/ 子目录
#       （不是根目录，详见 SKILL.md "为什么 portal 资源放子目录"）
#     - 不会改 ECS .env 的 IMAGE_TAG（portal 是独立镜像，IMAGE_TAG 控制 app/web）
#     - 默认打两个 tag：vX.Y.Z + latest
# ============================================================
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/load-env.sh"

: "${VERSION:?VERSION 未设置（例 VERSION=v1.0.1）}"

# portal 源码在 ruoyi-ui/，Dockerfile 在 ruoyi-ui/portal/Dockerfile
PROJECT_ROOT=$(dirname "$XINYA_DOCKER_DIR")
RUIYI_UI="$PROJECT_ROOT/ruoyi-ui"
[[ -d "$RUIYI_UI/public/portal" ]] || die "找不到 $RUIYI_UI/public/portal"

echo "=== 1/2 本地登录 ACR ==="
echo "$ACR_PASSWORD" | docker login "$ACR_REGISTRY" -u "$ACR_USER" --password-stdin

echo "=== 2/2 构建并推送 portal:${VERSION} ==="
cd "$RUIYI_UI"
docker buildx build \
  --platform linux/amd64 \
  -t "${ACR_REGISTRY}/${ACR_NAMESPACE}/portal:${VERSION}" \
  -t "${ACR_REGISTRY}/${ACR_NAMESPACE}/portal:latest" \
  --push \
  -f ./portal/Dockerfile \
  .

echo
echo "✅ portal 镜像已推送"
echo "   ${ACR_REGISTRY}/${ACR_NAMESPACE}/portal:${VERSION}"
echo "   ${ACR_REGISTRY}/${ACR_NAMESPACE}/portal:latest"
echo
echo "下一步（升级 ECS 容器）："
echo "   PORTAL_TAG=${VERSION} bash scripts/upgrade-portal.sh"
