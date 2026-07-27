#!/bin/sh
# M1 Wave I suite: abstract-world exit demonstration.
#
# Prefer shen-go for single-port Wave E+ development mode. Other ports
# are attempted when launchers exist; golden is generated from shen-go.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT"

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

if [ ! -x "$GO" ] && [ -x /Users/reuben/.local/bin/shen-go ]; then
  GO=/Users/reuben/.local/bin/shen-go
fi

PROGRAM=shen/tests/integration/run-tests.shen
GOLDEN=shen/tests/integration/golden.txt
CACHE=$ROOT/.shen-kernel-cache.bin

SEMANTIC='^(DEMO\||FAIL\||INTEGRATION CASES: |INTEGRATION: FAIL$|ALL PASS$)'

work=$(mktemp -d "${TMPDIR:-/tmp}/urdr-integration.XXXXXX")
trap 'rm -rf "$work" "$CACHE"' EXIT HUP INT TERM

SHEN_KERNEL_CACHE=off
SHEN_FASL=off
export SHEN_KERNEL_CACHE SHEN_FASL

ran=0

run_port() {
  name=$1
  shift
  if [ ! -x "$1" ]; then
    printf '%s: SKIP launcher not built at %s\n' "$name" "$1"
    return 0
  fi
  rm -f "$CACHE"
  if "$@" >"$work/out" 2>"$work/err" &&
     /usr/bin/grep -E "$SEMANTIC" "$work/out" >"$work/semantic" &&
     /usr/bin/grep -q '^ALL PASS$' "$work/semantic"; then
    if [ -f "$GOLDEN" ]; then
      if /usr/bin/cmp -s "$GOLDEN" "$work/semantic"; then
        printf '%s: PASS exact-golden\n' "$name"
        ran=$((ran + 1))
      else
        printf '%s: FAIL golden mismatch\n' "$name" >&2
        /usr/bin/diff -u "$GOLDEN" "$work/semantic" >&2 || true
        /bin/cat "$work/err" >&2 || true
        exit 1
      fi
    else
      if [ "$name" = "shen-go" ]; then
        /bin/cp "$work/semantic" "$GOLDEN"
        printf '%s: PASS generated golden\n' "$name"
        ran=$((ran + 1))
      else
        printf '%s: FAIL no golden.txt yet (run shen-go first)\n' "$name" >&2
        exit 1
      fi
    fi
  else
    printf '%s: FAIL\n' "$name" >&2
    /bin/cat "$work/out" >&2 || true
    /bin/cat "$work/err" >&2 || true
    exit 1
  fi
}

run_port shen-go "$GO" script "$PROGRAM"
run_port shen-cl "$CL" script "$PROGRAM"
run_port shen-rust "$RUST" script "$PROGRAM"
run_port shen-lua "$LUA" "$PROGRAM"

if [ -z "${GOLDEN_ONLY:-}" ] && [ "$ran" -eq 0 ]; then
  printf 'integration suite: BLOCKED no Shen port launcher was available\n' >&2
  exit 1
fi

cases=$(/usr/bin/grep -c '^DEMO|' "$GOLDEN" 2>/dev/null || printf '0')
printf 'integration suite: ALL PASS ports=%s lines=%s\n' "$ran" "$cases"
