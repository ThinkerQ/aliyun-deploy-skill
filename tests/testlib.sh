#!/usr/bin/env bash

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  return 1
}

pass() {
  printf 'PASS: %s\n' "$*"
}

assert_contains() {
  local haystack="$1" needle="$2" message="${3:-expected output to contain: $2}"
  [[ "$haystack" == *"$needle"* ]] || fail "$message"
}

assert_not_contains() {
  local haystack="$1" needle="$2" message="${3:-expected output not to contain: $2}"
  [[ "$haystack" != *"$needle"* ]] || fail "$message"
}

assert_eq() {
  local expected="$1" actual="$2" message="${3:-expected '$1', got '$2'}"
  [[ "$expected" == "$actual" ]] || fail "$message"
}

new_test_env() {
  XINYA_TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/xinya-skill-test.XXXXXX")
  export XINYA_TEST_ROOT
  trap 'rm -rf "${XINYA_TEST_ROOT:-}"' EXIT

  mkdir -p "$XINYA_TEST_ROOT/docker"
  printf '%s\n' 'fixture private key for offline tests only' > "$XINYA_TEST_ROOT/fixture.pem"
  chmod 600 "$XINYA_TEST_ROOT/fixture.pem"

  cat > "$XINYA_TEST_ROOT/docker/.env.acr" <<EOF
ACR_REGISTRY=registry.example.test
ACR_NAMESPACE=xinya
ACR_USER=test-user
ACR_PASSWORD=offline-fixture-password
EOF

  cat > "$XINYA_TEST_ROOT/docker/.env.ecs" <<EOF
ECS_HOST=203.0.113.10
ECS_USER=root
ECS_SSH_KEY=$XINYA_TEST_ROOT/fixture.pem
EOF

  XINYA_DOCKER_DIR="$XINYA_TEST_ROOT/docker"
  XINYA_ENV_FILE="$XINYA_TEST_ROOT/absent.env"
  XINYA_TEST_LOG="$XINYA_TEST_ROOT/test.log"
  : > "$XINYA_TEST_LOG"
  export XINYA_DOCKER_DIR XINYA_ENV_FILE XINYA_TEST_LOG
}
