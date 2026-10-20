#!/usr/bin/env bash
set -euo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

for test_script in "$TEST_DIR"/test-*.sh; do
  printf '==> %s\n' "$(basename "$test_script")"
  bash "$test_script"
done
