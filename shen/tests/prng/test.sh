#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT"

CL=${SHEN_CL:-/Users/reuben/projects/urdr-shen-cl-41.2/bin/sbcl/shen}
GO=${SHEN_GO:-/Users/reuben/projects/shen-go/.bin/shen-go}
RUST=${SHEN_RUST:-/Users/reuben/projects/shen-rust/target/release/shen-rust}
LUA=${SHEN_LUA:-/Users/reuben/projects/shen-lua/bin/shen}
CACHE=$ROOT/.shen-kernel-cache.bin

rm -f "$CACHE"
PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/test_prng_vectors.py

run_port() {
  name=$1
  shift
  output=$(mktemp "${TMPDIR:-/tmp}/urdr-prng-output.XXXXXX")
  timing=$(mktemp "${TMPDIR:-/tmp}/urdr-prng-time.XXXXXX")
  trap 'rm -f "$output" "$timing" "$CACHE"' EXIT HUP INT TERM

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

  rm -f "$output" "$timing" "$CACHE"
  trap - EXIT HUP INT TERM
}

run_port shen-cl "$CL" script shen/tests/prng/run-tests.shen
run_port shen-go "$GO" script shen/tests/prng/run-tests.shen
run_port shen-rust "$RUST" script shen/tests/prng/run-tests.shen
run_port shen-lua "$LUA" shen/tests/prng/run-tests.shen

printf 'four-port product PRNG suite: ALL PASS\n'
