#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT"

CL=${SHEN_CL:-/Users/reuben/projects/urdr-shen-cl-41.2/bin/sbcl/shen}
GO=${SHEN_GO:-/Users/reuben/projects/shen-go/.bin/shen-go}
RUST=${SHEN_RUST:-/Users/reuben/projects/shen-rust/target/release/shen-rust}
LUA=${SHEN_LUA:-/Users/reuben/projects/shen-lua/bin/shen}
GOLDEN=shen/tests/world/golden.txt
CACHE=$ROOT/.shen-kernel-cache.bin

run_port() {
  name=$1
  shift
  output=$(mktemp "${TMPDIR:-/tmp}/urdr-world-output.XXXXXX")
  semantic=$(mktemp "${TMPDIR:-/tmp}/urdr-world-semantic.XXXXXX")
  trap 'rm -f "$output" "$semantic" "$CACHE"' EXIT HUP INT TERM

  if "$@" >"$output" &&
     /usr/bin/grep -E '^(WORLD-TRACE |WORLD TESTS: |ALL PASS$)' \
       "$output" >"$semantic" &&
     /usr/bin/cmp -s "$GOLDEN" "$semantic"; then
    printf '%s: PASS exact-golden\n' "$name"
  else
    printf '%s: FAIL\n' "$name" >&2
    /usr/bin/diff -u "$GOLDEN" "$semantic" >&2 || true
    exit 1
  fi

  rm -f "$output" "$semantic" "$CACHE"
  trap - EXIT HUP INT TERM
}

rm -f "$CACHE"
run_port shen-cl "$CL" script shen/tests/world/run-tests.shen
run_port shen-go "$GO" script shen/tests/world/run-tests.shen
run_port shen-rust "$RUST" script shen/tests/world/run-tests.shen
run_port shen-lua "$LUA" shen/tests/world/run-tests.shen
printf 'four-port world suite: ALL PASS\n'
