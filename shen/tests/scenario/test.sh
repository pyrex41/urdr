#!/bin/sh
# Cross-port scenario-DSL suite. Each port must emit byte-identical
# semantic output; the shared digest is the cross-port evidence.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT"

DEPS=${URDR_DEPENDENCIES:-$ROOT/.cache/urdr/dependencies}
# In a linked worktree the dependency cache lives beside the main
# checkout, so fall back to the common git directory's parent.
if [ ! -d "$DEPS" ]; then
  COMMON=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
  if [ -n "$COMMON" ]; then
    MAIN=$(CDPATH= cd -- "$COMMON/.." && pwd)
    if [ -d "$MAIN/.cache/urdr/dependencies" ]; then
      DEPS=$MAIN/.cache/urdr/dependencies
    fi
  fi
fi
CL=${SHEN_CL:-$DEPS/shen-cl/bin/sbcl/shen}
GO=${SHEN_GO:-$DEPS/shen-go/.bin/shen-go}
RUST=${SHEN_RUST:-$DEPS/shen-rust/target/release/shen-rust}
LUA=${SHEN_LUA:-$DEPS/shen-lua/bin/shen}
PROGRAM=shen/tests/scenario/run-tests.shen
# shen-lua writes .shen-kernel-cache.<hash>.bin (older builds wrote
# .shen-kernel-cache.bin), so clear every variant.
CACHE_PREFIX=$ROOT/.shen-kernel-cache
AGREED=

SHEN_KERNEL_CACHE=off
SHEN_FASL=off
export SHEN_KERNEL_CACHE SHEN_FASL

run_port() {
  name=$1
  shift
  output=$(mktemp "${TMPDIR:-/tmp}/urdr-scenario-output.XXXXXX")
  semantic=$(mktemp "${TMPDIR:-/tmp}/urdr-scenario-semantic.XXXXXX")
  trap 'rm -f "$output" "$semantic" "$CACHE_PREFIX"*.bin' EXIT HUP INT TERM

  if ! "$@" >"$output" 2>&1; then
    printf '%s: FAIL launcher\n' "$name" >&2
    cat "$output" >&2
    exit 1
  fi
  grep -E \
    '^(profile\||accept\||large\||reject\||FAIL\||urdr-scenario: |ALL PASS$)' \
    "$output" >"$semantic" || true
  if ! grep -q '^ALL PASS$' "$semantic"; then
    printf '%s: FAIL marker\n' "$name" >&2
    cat "$semantic" >&2
    exit 1
  fi
  digest=$(sha256sum "$semantic" | cut -d' ' -f1)
  cases=$(grep -c '^\(accept\|large\|reject\)|' "$semantic")
  if [ -z "$AGREED" ]; then
    AGREED=$digest
  elif [ "$AGREED" != "$digest" ]; then
    printf '%s: FAIL semantic digest %s differs from %s\n' \
      "$name" "$digest" "$AGREED" >&2
    exit 1
  fi
  printf '%s: PASS cases=%s sha256=%s\n' "$name" "$cases" "$digest"

  rm -f "$output" "$semantic" "$CACHE_PREFIX"*.bin
  trap - EXIT HUP INT TERM
}

rm -f "$CACHE_PREFIX"*.bin
run_port shen-cl "$CL" script "$PROGRAM"
run_port shen-go "$GO" script "$PROGRAM"
run_port shen-rust "$RUST" script "$PROGRAM"
run_port shen-lua "$LUA" "$PROGRAM"

printf 'four-port scenario suite: ALL PASS sha256=%s\n' "$AGREED"
