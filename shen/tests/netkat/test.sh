#!/bin/sh
# ADR 0004 Decision 2 suite: every port must reproduce the checked-in
# golden semantic output, and the case subset of that output must agree
# byte for byte with the independent Python oracle.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT"

DEPS=$ROOT/.cache/urdr/dependencies
CL=${SHEN_CL:-$DEPS/shen-cl/bin/sbcl/shen}
GO=${SHEN_GO:-$DEPS/shen-go/.bin/shen-go}
RUST=${SHEN_RUST:-$DEPS/shen-rust/target/release/shen-rust}
LUA=${SHEN_LUA:-$DEPS/shen-lua/bin/shen}
GOLDEN=shen/tests/netkat/golden.txt
CACHE=$ROOT/.shen-kernel-cache.bin

SEMANTIC='^(NETKAT-OK\||NETKAT-REJECT\||NETKAT-FLIP\||NETKAT-DIRECT\||NETKAT CASES: |NETKAT DIRECT: |ALL PASS$)'
SHARED='^(NETKAT-OK\||NETKAT-REJECT\||NETKAT-FLIP\||NETKAT CASES: )'

work=$(mktemp -d "${TMPDIR:-/tmp}/urdr-netkat.XXXXXX")
trap 'rm -rf "$work" "$CACHE"' EXIT HUP INT TERM

PYTHONDONTWRITEBYTECODE=1 python3 shen/tests/netkat/oracle.py check
PYTHONDONTWRITEBYTECODE=1 python3 shen/tests/netkat/oracle.py emit >"$work/oracle"

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

run_port shen-lua "$LUA" shen/tests/netkat/run-tests.shen
run_port shen-go "$GO" script shen/tests/netkat/run-tests.shen
run_port shen-rust "$RUST" script shen/tests/netkat/run-tests.shen
run_port shen-cl "$CL" script shen/tests/netkat/run-tests.shen

if [ "$ran" -eq 0 ]; then
  printf 'netkat suite: BLOCKED no Shen port launcher was available\n' >&2
  exit 1
fi

printf 'netkat suite: ALL PASS ports=%s\n' "$ran"
