#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT"

# Launcher paths default to the pinned checkouts under
# .cache/urdr/dependencies and are overridable with SHEN_GO, SHEN_LUA,
# SHEN_CL, SHEN_RUST (or URDR_DEPENDENCIES for the whole tree). In a
# linked worktree the dependency cache lives beside the main checkout,
# so fall back to the common git directory's parent.
DEPS=${URDR_DEPENDENCIES:-}
if [ -z "$DEPS" ]; then
  DEPS=$ROOT/.cache/urdr/dependencies
  if [ ! -d "$DEPS" ]; then
    common=$(git -C "$ROOT" rev-parse --path-format=absolute \
      --git-common-dir 2>/dev/null || true)
    if [ -n "$common" ]; then
      DEPS=$(dirname -- "$common")/.cache/urdr/dependencies
    fi
  fi
fi

CL=${SHEN_CL:-$DEPS/shen-cl/bin/sbcl/shen}
GO=${SHEN_GO:-$DEPS/shen-go/.bin/shen-go}
RUST=${SHEN_RUST:-$DEPS/shen-rust/target/release/shen-rust}
LUA=${SHEN_LUA:-$DEPS/shen-lua/bin/shen}
GOLDEN=shen/tests/world/golden.txt
CACHE=$ROOT/.shen-kernel-cache.bin

run_port() {
  name=$1
  shift
  output=$(mktemp "${TMPDIR:-/tmp}/urdr-world-output.XXXXXX")
  semantic=$(mktemp "${TMPDIR:-/tmp}/urdr-world-semantic.XXXXXX")
  trap 'rm -f "$output" "$semantic" "$CACHE"' EXIT HUP INT TERM

  if "$@" >"$output" &&
     /usr/bin/grep -E \
       '^(WORLD-CHOICE-DRAWN |WORLD-CHOICE-SELECTED |WORLD-TRACE |WORLD-COMPONENT-TRACE |WORLD TESTS: |ALL PASS$)' \
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
