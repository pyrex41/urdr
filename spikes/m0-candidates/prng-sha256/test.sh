#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

CL=${SHEN_CL:-/Users/reuben/projects/urdr-shen-cl-41.2/bin/sbcl/shen}
GO=${SHEN_GO:-/Users/reuben/projects/shen-go/.bin/shen-go}
RUST=${SHEN_RUST:-/Users/reuben/projects/shen-rust/target/release/shen-rust}
LUA=${SHEN_LUA:-/Users/reuben/projects/shen-lua/bin/shen}
# shen-lua writes .shen-kernel-cache.<hash>.bin (older builds wrote
# .shen-kernel-cache.bin), so clear every variant.
CACHE_PREFIX=$ROOT/.shen-kernel-cache

rm -f "$CACHE_PREFIX"*.bin

python3 tests/oracle.py --check fixtures/vectors.json

run_port() {
  name=$1
  shift
  output=$(mktemp "${TMPDIR:-/tmp}/urdr-prng-sha256-output.XXXXXX")
  timing=$(mktemp "${TMPDIR:-/tmp}/urdr-prng-sha256-time.XXXXXX")
  trap 'rm -f "$output" "$timing" "$CACHE_PREFIX"*.bin' EXIT HUP INT TERM

  if /usr/bin/time -p "$@" >"$output" 2>"$timing" &&
     /usr/bin/grep -q '^ALL PASS$' "$output"; then
    tests=$(/usr/bin/grep -c '^PASS ' "$output")
    real=$(/usr/bin/awk '$1 == "real" { print $2 }' "$timing")
    printf '%s: PASS tests=%s real_seconds=%s\n' "$name" "$tests" "$real"
  else
    printf '%s: FAIL\n' "$name" >&2
    /bin/cat "$output" >&2
    /bin/cat "$timing" >&2
    exit 1
  fi

  rm -f "$output" "$timing" "$CACHE_PREFIX"*.bin
  trap - EXIT HUP INT TERM
}

run_port shen-cl "$CL" script tests/run-tests.shen
run_port shen-go "$GO" script tests/run-tests.shen
run_port shen-rust "$RUST" script tests/run-tests.shen
run_port shen-lua "$LUA" tests/run-tests.shen

printf 'four-port candidate suite: ALL PASS\n'
