#!/usr/bin/env bash
# ============================================================
#  ecs.sh — SSH/SCP 封装：让 Windows + Git Bash 也能非交互登录 ECS
# ============================================================
#  用法：
#     source scripts/load-env.sh
#     source scripts/ecs.sh
#     ecs_cmd "docker ps"          # 远程执行单条命令
#     ecs_upload local.txt /tmp/   # 本地 → ECS
#
#  关键技巧：Windows OpenSSH 客户端 8.0+ 支持 SSH_ASKPASS 取密码
# ============================================================

# 校验 sshpass 不可用，但我们用 OpenSSH 自带的 SSH_ASKPASS
ssh_base_args=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15)

# 选择认证方式
if [[ -n "${ECS_SSH_KEY:-}" ]]; then
  ssh_auth_args=(-i "$ECS_SSH_KEY")
  scp_auth_args=(-i "$ECS_SSH_KEY")
else
  # 临时脚本只引用环境变量，不将实际密码写入文件。
  ASKPASS_FILE=$(mktemp -t xinya_askpass.XXXX.sh)
  cat > "$ASKPASS_FILE" <<'EOF'
#!/bin/bash
printf '%s\n' "$ECS_PASSWORD"
EOF
  chmod 700 "$ASKPASS_FILE"
  export SSH_ASKPASS="$ASKPASS_FILE"
  export SSH_ASKPASS_REQUIRE=force
  ssh_auth_args=()
  scp_auth_args=()
  trap 'rm -f "$ASKPASS_FILE"' EXIT
fi

ecs_cmd() {
  ssh "${ssh_auth_args[@]}" "${ssh_base_args[@]}" "${ECS_USER}@${ECS_HOST}" "$*"
}

ecs_upload() {
  local src="$1" dst="$2"
  scp "${scp_auth_args[@]}" "${ssh_base_args[@]}" -P 22 "$src" "${ECS_USER}@${ECS_HOST}:${dst}"
}

ecs_download() {
  local remote="$1" local="$2"
  scp "${scp_auth_args[@]}" "${ssh_base_args[@]}" -P 22 "${ECS_USER}@${ECS_HOST}:${remote}" "$local"
}

# 密码通过 SSH 标准输入传递，不进入远程命令参数。
ecs_mysql() {
    : "${MYSQL_USER:?请在 .env 中配置 MYSQL_USER}"
    : "${MYSQL_PASSWORD:?请在 .env 中配置 MYSQL_PASSWORD}"
    : "${MYSQL_DATABASE:?请在 .env 中配置 MYSQL_DATABASE}"
    if [[ "$MYSQL_PASSWORD" == *$'\n'* || "$MYSQL_PASSWORD" == *$'\r'* ]]; then
        echo 'MYSQL_PASSWORD 不能包含换行符' >&2
        return 1
    fi
    local mysqlArgs
    printf -v mysqlArgs '%q ' "--user=$MYSQL_USER" "--database=$MYSQL_DATABASE" "$@"
    printf '%s\n' "$MYSQL_PASSWORD" | ecs_cmd \
        "IFS= read -r MYSQL_PWD && export MYSQL_PWD && docker exec -i -e MYSQL_PWD c-xinya-mysql mysql $mysqlArgs"
}
