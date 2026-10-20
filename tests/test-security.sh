#!/usr/bin/env bash
set -euo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SKILL_DIR=$(cd -- "$TEST_DIR/.." && pwd)
source "$TEST_DIR/testlib.sh"

# 旧目录中 status-and-heal.sh 实际是 systemd 单元，只检查有 Bash shebang 的文件。
for script in "$SKILL_DIR"/scripts/*.sh; do
    if head -1 "$script" | grep -q '^#!/usr/bin/env bash'; then
        bash -n "$script"
    fi
done
pass "Bash scripts pass syntax checks"

new_test_env
source "$SKILL_DIR/scripts/load-env.sh"
assert_eq "test-user" "$ACR_USER" "legacy config must load"
pass "legacy env files remain supported"

cat > "$XINYA_TEST_ROOT/private.env" <<'EOF'
ACR_USER=override-user
MYSQL_USER=fixture-user
MYSQL_DATABASE=fixture_database
MYSQL_PASSWORD='fixture $dollar "quote" back\slash'
EOF
XINYA_ENV_FILE="$XINYA_TEST_ROOT/private.env"
source "$SKILL_DIR/scripts/load-env.sh"
assert_eq "override-user" "$ACR_USER" "unified env must override legacy config"
assert_eq 'fixture $dollar "quote" back\slash' "$MYSQL_PASSWORD"
MYSQL_PASSWORD+=" 'single-quote'"
source "$SKILL_DIR/scripts/ecs.sh"

# Mock SSH completely: run only the generated command with a mocked Docker function.
docker() {
    assert_eq "$EXPECTED_MYSQL_PASSWORD" "$MYSQL_PWD"
    assert_eq "exec" "$1"
    assert_eq "-i" "$2"
    assert_eq "-e" "$3"
    assert_eq "MYSQL_PWD" "$4"
    assert_eq "--user=fixture-user" "$7"
    assert_eq "--database=fixture_database" "$8"
    assert_eq "-e" "$9"
    assert_eq "SELECT 'fixture';" "${10}"
}
export -f docker assert_eq fail
export EXPECTED_MYSQL_PASSWORD="$MYSQL_PASSWORD"
ssh() {
    local remoteCommand="${@: -1}"
    assert_not_contains "$remoteCommand" "$MYSQL_PASSWORD" "password must not enter SSH arguments"
    bash -c "$remoteCommand"
}
ecs_mysql -e "SELECT 'fixture';"
pass "special-character database password reaches mocked Docker without entering SSH arguments"

if (MYSQL_PASSWORD=$'invalid\npassword'; ecs_mysql -e 'SELECT 1') >/dev/null 2>&1; then
    fail "multiline password must be rejected"
fi
pass "multiline passwords are rejected"

git init -q "$XINYA_TEST_ROOT/git-fixture"
cp "$SKILL_DIR/.gitignore" "$XINYA_TEST_ROOT/git-fixture/.gitignore"
git -C "$XINYA_TEST_ROOT/git-fixture" check-ignore -q .env
git -C "$XINYA_TEST_ROOT/git-fixture" check-ignore -q secret.pem
if git -C "$XINYA_TEST_ROOT/git-fixture" check-ignore -q .env.example; then
    fail ".env.example must remain committable"
fi
pass "Git ignores credentials and permits the example"

if command -v docker >/dev/null 2>&1; then
    # Only docker compose config is invoked: no daemon, containers or network.
    unset -f docker
    source "$SKILL_DIR/scripts/compose-env.sh"
    compose_env_value TEST_PASSWORD "$MYSQL_PASSWORD" > "$XINYA_TEST_ROOT/compose.env"
    cat > "$XINYA_TEST_ROOT/compose.yml" <<'EOF'
services:
  fixture:
    image: scratch
    environment:
      TEST_PASSWORD: ${TEST_PASSWORD}
EOF
    command docker compose --env-file "$XINYA_TEST_ROOT/compose.env" \
        -f "$XINYA_TEST_ROOT/compose.yml" config --environment > "$XINYA_TEST_ROOT/compose.json"
    TEST_COMPOSE_JSON="$XINYA_TEST_ROOT/compose.json" python -c \
        'import os; lines = open(os.environ["TEST_COMPOSE_JSON"], encoding="utf-8").read().splitlines(); actual = next(line.split("=", 1)[1] for line in lines if line.startswith("TEST_PASSWORD=")); assert actual == os.environ["EXPECTED_MYSQL_PASSWORD"]'
    pass "Compose preserves special-character passwords"
fi
