#!/usr/bin/env bash
# ============================================================
#  release.sh — 发版（本地构建推送 + ECS 拉取升级 + 自动记录回滚点）
# ============================================================
#  用法：
#     VERSION=v1.0.1 bash scripts/release.sh
#     SKIP_WEB=1 VERSION=v1.0.1 bash scripts/release.sh   # 只发后端，保留 web 容器
# ============================================================
#  修复：原先 ecs_cmd 内部用 ssh 调用，远程命令失败时 ssh 仍返回 0，
#       导致 `| tail -5` 吞掉错误，set -e 失效。现加 ecs_cmd_strict 显式
#       捕获远程退出码 + ACR 镜像预检查。
# ============================================================
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/load-env.sh"
source "$SCRIPT_DIR/ecs.sh"

# 替代 ecs_cmd，能传递远程命令退出码。
# 用法：ecs_cmd_strict "remote command"；远程命令非 0 退出时本函数也非 0。
ecs_cmd_strict() {
    local out last rc
    out=$(ecs_cmd "$*; echo __REMOTE_RC__=\$?")
    last=$(echo "$out" | tail -1)
    rc="${last#__REMOTE_RC__=}"
    printf '%s\n' "${out%$'\n'__REMOTE_RC__=*}" | sed '$d'
    if [[ "$rc" != "0" ]]; then
        return 1
    fi
}

: "${VERSION:?VERSION 未设置（例 VERSION=v1.0.1）}"
PROJECT_ROOT=$(dirname "$XINYA_DOCKER_DIR")
[[ -d "$PROJECT_ROOT/ruoyi-admin" ]] || PROJECT_ROOT="$XINYA_DOCKER_DIR/.."  # fallback

SKIP_WEB="${SKIP_WEB:-0}"
PULL_SVCS="xinya-app"
[[ "$SKIP_WEB" != "1" ]] && PULL_SVCS="$PULL_SVCS xinya-web"

echo "=== 1/5 本地登录 ACR ==="
echo "$ACR_PASSWORD" | docker login "$ACR_REGISTRY" -u "$ACR_USER" --password-stdin

echo "=== 2/5 构建并推送 app:${VERSION} ==="
cd "$PROJECT_ROOT"
docker buildx build \
  --platform linux/amd64 \
  -t "${ACR_REGISTRY}/${ACR_NAMESPACE}/app:${VERSION}" \
  -t "${ACR_REGISTRY}/${ACR_NAMESPACE}/app:latest" \
  --push \
  -f ruoyi-admin/Dockerfile \
  .

echo "✅ 镜像已推送 ${ACR_REGISTRY}/${ACR_NAMESPACE}/app:${VERSION}"

echo "=== 3/5 记录上一版本（便于 rollback）==="
PREV_TAG=$(ecs_cmd "grep '^IMAGE_TAG=' /opt/xinya/.env | cut -d= -f2" 2>/dev/null | head -1 || echo "")
if [[ -n "$PREV_TAG" && "$PREV_TAG" != "$VERSION" ]]; then
  echo "$PREV_TAG" > "$SCRIPT_DIR/.rollback"
  echo "📦 已记录上一版本：$PREV_TAG（写到 scripts/.rollback）"
fi

echo "=== 4/5 验证 ACR 镜像 + 更新 ECS .env ==="
# 预检查：先确认需要的镜像在 ACR 上存在，否则后面 pull 一定会失败
for svc in app; do
  if ! ecs_cmd "docker manifest inspect ${ACR_REGISTRY}/${ACR_NAMESPACE}/${svc}:${VERSION} >/dev/null 2>&1" 2>&1; then
    echo "❌ ACR 上 ${svc}:${VERSION} 不存在（push 失败？或 ACR 凭据过期？）"
    exit 1
  fi
  echo "✅ ACR 上 ${svc}:${VERSION} 存在"
done
if [[ "$SKIP_WEB" != "1" ]]; then
  if ! ecs_cmd "docker manifest inspect ${ACR_REGISTRY}/${ACR_NAMESPACE}/web:${VERSION} >/dev/null 2>&1" 2>&1; then
    echo "❌ ACR 上 web:${VERSION} 不存在（只发后端时设 SKIP_WEB=1）"
    exit 1
  fi
  echo "✅ ACR 上 web:${VERSION} 存在"
else
  echo "⏭️  SKIP_WEB=1，跳过 web 镜像预检查"
fi

# 更新 ECS .env
if ! ecs_cmd_strict "sed -i 's/^IMAGE_TAG=.*/IMAGE_TAG=${VERSION}/' /opt/xinya/.env && grep '^IMAGE_TAG=' /opt/xinya/.env"; then
  echo "❌ 更新 .env 失败"
  exit 1
fi

echo "=== 5/5 pull + up + 健康检查 ==="
PULL_OUT=$(ecs_cmd "cd /opt/xinya/docker && docker compose --env-file /opt/xinya/.env pull ${PULL_SVCS}" 2>&1) || PULL_RC=$? || true
PULL_RC="${PULL_RC:-0}"
echo "$PULL_OUT" | tail -8
if [[ "$PULL_RC" -ne 0 ]] || echo "$PULL_OUT" | grep -qE "(Error response from daemon|manifest unknown|context canceled|denied)"; then
  echo "❌ pull 失败（rc=$PULL_RC）"
  exit 1
fi

UP_OUT=$(ecs_cmd "cd /opt/xinya/docker && docker compose --env-file /opt/xinya/.env up -d ${PULL_SVCS}" 2>&1) || true
echo "$UP_OUT" | tail -8
if echo "$UP_OUT" | grep -qE "(Error response from daemon|context canceled|no such)"; then
  echo "❌ up -d 失败"
  exit 1
fi

echo "等待 30s 让容器健康..."
sleep 30
ecs_cmd "cd /opt/xinya/docker && docker compose --env-file /opt/xinya/.env ps"

echo
echo "==== 健康检查 ===="
ecs_cmd "curl -sI http://127.0.0.1/ | head -3 && \
         echo && \
         curl -s 'http://127.0.0.1/prod-api/captchaImage' | head -c 100"

echo
echo "✅ 发版完成：${VERSION}"
echo "   镜像：${ACR_REGISTRY}/${ACR_NAMESPACE}/app:${VERSION}"
echo "   回滚命令：bash scripts/rollback.sh"
