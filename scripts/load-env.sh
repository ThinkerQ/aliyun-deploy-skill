#!/usr/bin/env bash
# 从私有 .env 加载配置；兼容项目 docker/.env.acr 和 .env.ecs。
set +x

die() {
    echo "[load-env] $*" >&2
    exit 1
}

XINYA_SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
XINYA_ENV_FILE="${XINYA_ENV_FILE:-$XINYA_SKILL_DIR/.env}"
if [[ -f "$XINYA_ENV_FILE" ]]; then
    source "$XINYA_ENV_FILE"
fi
: "${XINYA_DOCKER_DIR:=D:/gitee/xinya_ry/docker}"
if command -v cygpath >/dev/null 2>&1; then
    XINYA_DOCKER_DIR=$(cygpath -u "$XINYA_DOCKER_DIR")
fi

# 旧配置提供尚未迁入统一 .env 的凭证；统一 .env 优先。
for legacyEnv in "$XINYA_DOCKER_DIR/.env.acr" "$XINYA_DOCKER_DIR/.env.ecs"; do
    if [[ -f "$legacyEnv" ]]; then
        source "$legacyEnv"
    fi
done
if [[ -f "$XINYA_ENV_FILE" ]]; then
    source "$XINYA_ENV_FILE"
fi
set +x
if command -v cygpath >/dev/null 2>&1; then
    XINYA_DOCKER_DIR=$(cygpath -u "$XINYA_DOCKER_DIR")
fi

: "${ACR_REGISTRY:?请在 .env 中配置 ACR_REGISTRY}"
: "${ACR_NAMESPACE:?请在 .env 中配置 ACR_NAMESPACE}"
: "${ACR_USER:?请在 .env 或 .env.acr 中配置 ACR_USER}"
: "${ACR_PASSWORD:?请在 .env 或 .env.acr 中配置 ACR_PASSWORD}"
: "${ECS_HOST:?请在 .env 中配置 ECS_HOST}"
: "${ECS_USER:=root}"
if [[ -z "${ECS_PASSWORD:-}" && -z "${ECS_SSH_KEY:-}" ]]; then
    die "请在 .env 或 .env.ecs 中配置 ECS_PASSWORD 或 ECS_SSH_KEY"
fi

export XINYA_DOCKER_DIR ACR_REGISTRY ACR_NAMESPACE ACR_USER ACR_PASSWORD ECS_HOST ECS_USER
export ECS_PASSWORD ECS_SSH_KEY
