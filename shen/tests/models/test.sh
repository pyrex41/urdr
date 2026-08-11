#!/bin/sh
# Plan Wave C (components) suite: the abstract network, timer, and fault
# models, the scenario-to-registry composition glue, and the NetKAT
# counterexample witness bridge. Every required port must reproduce the
# checked-in golden semantic projection byte for byte.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT"

# A git worktree has no .cache/ of its own; the dependency cache lives in
# the main checkout next to the common git directory. URDR_DEPENDENCIES
# overrides the whole tree, matching scripts/build-ports.
DEPS=${URDR_DEPENDENCIES:-}
if [ -z "$DEPS" ]; then
  DEPS=$ROOT/.cache/urdr/dependencies
  if [ ! -d "$DEPS" ]; then
    COMMON=$(git rev-parse --git-common-dir 2>/dev/null || printf '')
    if [ -n "$COMMON" ]; then
      MAIN=$(CDPATH= cd -- "$COMMON/.." && pwd)
      if [ -d "$MAIN/.cache/urdr/dependencies" ]; then
        DEPS=$MAIN/.cache/urdr/dependencies
      fi
    fi
  fi
fi

CL=${SHEN_CL:-$DEPS/shen-cl/bin/sbcl/shen}
GO=${SHEN_GO:-$DEPS/shen-go/.bin/shen-go}
RUST=${SHEN_RUST:-$DEPS/shen-rust/target/release/shen-rust}
LUA=${SHEN_LUA:-$DEPS/shen-lua/bin/shen}
GOLDEN=shen/tests/models/golden.txt
# shen-lua writes .shen-kernel-cache.<hash>.bin (older builds wrote
# .shen-kernel-cache.bin), so clear every variant.
CACHE_PREFIX=$ROOT/.shen-kernel-cache

SEMANTIC='^(MODELS-OK\||MODELS-DIGEST\||MODELS-REJECT\||MODELS-DIRECT\||MODELS CASES: |ALL PASS$)'

work=$(mktemp -d "${TMPDIR:-/tmp}/urdr-models.XXXXXX")
trap 'rm -rf "$work" "$CACHE_PREFIX"*.bin' EXIT HUP INT TERM

ran=0

run_port() {
  name=$1
  shift
  if [ ! -x "$1" ]; then
    printf '%s: SKIP launcher not built at %s\n' "$name" "$1"
    return 0
  fi
  rm -f "$CACHE_PREFIX"*.bin
  if "$@" >"$work/out" 2>"$work/err" &&
     /usr/bin/grep -E "$SEMANTIC" "$work/out" >"$work/semantic" &&
     /usr/bin/cmp -s "$GOLDEN" "$work/semantic"; then
    printf '%s: PASS exact-golden\n' "$name"
    ran=$((ran + 1))
  else
    printf '%s: FAIL\n' "$name" >&2
    /usr/bin/diff -u "$GOLDEN" "$work/semantic" >&2 || true
    /bin/cat "$work/err" >&2 || true
    exit 1
  fi
}

run_port shen-cl "$CL" script shen/tests/models/run-tests.shen
run_port shen-go "$GO" script shen/tests/models/run-tests.shen
run_port shen-rust "$RUST" script shen/tests/models/run-tests.shen
run_port shen-lua "$LUA" shen/tests/models/run-tests.shen

if [ "$ran" -eq 0 ]; then
  printf 'models suite: BLOCKED no Shen port launcher was available\n' >&2
  exit 1
fi

printf 'models suite: ALL PASS ports=%s\n' "$ran"
