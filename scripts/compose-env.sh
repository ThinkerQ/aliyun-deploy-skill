#!/usr/bin/env bash
# 为 Docker Compose 输出单引号值，保留美元符号、空格和引号的字面含义。
compose_env_value() {
    local configName="$1"
    local configValue="$2"
    if [[ "$configValue" == *$'\n'* || "$configValue" == *$'\r'* ]]; then
        echo 'Compose 配置值不能包含换行符' >&2
        return 1
    fi
    configValue="${configValue//\'/\\\'}"
    printf "%s='%s'\n" "$configName" "$configValue"
}
