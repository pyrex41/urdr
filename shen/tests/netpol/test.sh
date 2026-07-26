#!/bin/sh
# ADR 0004 Decision 4 suite: every port must reproduce the checked-in
# golden semantic output, and the case subset of that output must agree
# byte for byte with the independent Python oracle.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT"

# In a linked worktree the dependency cache lives beside the main
# checkout, so fall back to the common git directory's parent.
DEPS=$ROOT/.cache/urdr/dependencies
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
GOLDEN=shen/tests/netpol/golden.txt
CACHE=$ROOT/.shen-kernel-cache.bin

SEMANTIC='^(NETPOL-OK\||NETPOL-TERM\||NETPOL-REJECT\||NETPOL-FLIP\||NETPOL-DIRECT\||NETPOL CASES: |NETPOL DIRECT: |NETPOL MARKER: |ALL PASS$)'
SHARED='^(NETPOL-OK\||NETPOL-TERM\||NETPOL-REJECT\||NETPOL-FLIP\||NETPOL CASES: )'

work=$(mktemp -d "${TMPDIR:-/tmp}/urdr-netpol.XXXXXX")
trap 'rm -rf "$work" "$CACHE"' EXIT HUP INT TERM

PYTHONDONTWRITEBYTECODE=1 python3 shen/tests/netpol/oracle.py check
PYTHONDONTWRITEBYTECODE=1 python3 shen/tests/netpol/oracle.py emit >"$work/oracle"

if ! /usr/bin/grep -E "$SHARED" "$GOLDEN" >"$work/golden-shared"; then
  printf 'golden: no shared lines\n' >&2
  exit 1
fi
if ! /usr/bin/cmp -s "$work/oracle" "$work/golden-shared"; then
  printf 'oracle: golden disagrees with the independent oracle\n' >&2
  /usr/bin/diff -u "$work/golden-shared" "$work/oracle" >&2 || true
  exit 1
fi

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

run_port shen-lua "$LUA" shen/tests/netpol/run-tests.shen
run_port shen-go "$GO" script shen/tests/netpol/run-tests.shen
run_port shen-rust "$RUST" script shen/tests/netpol/run-tests.shen
run_port shen-cl "$CL" script shen/tests/netpol/run-tests.shen

if [ "$ran" -eq 0 ]; then
  printf 'netpol suite: BLOCKED no Shen port launcher was available\n' >&2
  exit 1
fi

printf 'netpol suite: ALL PASS ports=%s\n' "$ran"
