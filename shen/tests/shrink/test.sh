#!/bin/sh
# M1 Wave F suite, part 2: SPEC.md 17.1 failure shrinking.
#
# Every required Shen port must reproduce the checked-in golden semantic
# output byte for byte. A failure signature, a candidate's acceptance,
# and the minimised transcript are pure functions of their declared
# inputs, so any per-port disagreement is a semantic bug, not a
# formatting one, and the exact-golden comparison is what says so. The
# MIN line additionally asserts WITHIN each port that the minimised
# artifact, replayed from the initial world with no knowledge of the
# search, reproduces the SAME failure signature; the golden comparison
# asserts the minimised artifact itself agrees ACROSS ports.
#
# Launcher paths default to the pinned checkouts under
# .cache/urdr/dependencies and are overridable with SHEN_GO, SHEN_LUA,
# SHEN_CL, SHEN_RUST (or URDR_DEPENDENCIES for the whole tree).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT"

# Dependencies live in the main checkout's .cache. When this runs from a
# git worktree $ROOT has no .cache of its own, so fall back to the
# directory that owns the shared git dir.
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

PROGRAM=shen/tests/shrink/run-tests.shen
GOLDEN=shen/tests/shrink/golden.txt
CACHE=$ROOT/.shen-kernel-cache.bin

# FAIL| is part of the projection on purpose: a self-check failure must
# appear in the diff rather than vanishing from the compared bytes.
SEMANTIC='^(PLAN\||SHARE\||SIG\||VERD\||SHR\||SHRL\||SHRV\||MIN\||MUT\||SREJ\||FAIL\||SHRINK CASES: |SHRINK: FAIL$|ALL PASS$)'

work=$(mktemp -d "${TMPDIR:-/tmp}/urdr-shrink.XXXXXX")
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
     /usr/bin/grep -q '^ALL PASS$' "$work/semantic" &&
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

# shen-lua takes the file directly; the other three take a `script`
# subcommand (spikes/m1-prolog-portability/README.md).
run_port shen-cl "$CL" script "$PROGRAM"
run_port shen-go "$GO" script "$PROGRAM"
run_port shen-rust "$RUST" script "$PROGRAM"
run_port shen-lua "$LUA" "$PROGRAM"

if [ "$ran" -eq 0 ]; then
  printf 'shrink suite: BLOCKED no Shen port launcher was available\n' >&2
  exit 1
fi

cases=$(/usr/bin/grep -c \
  '^\(PLAN\|SHARE\|SIG\|SHR\|MIN\|MUT\|SREJ\)|' "$GOLDEN")
printf 'shrink suite: ALL PASS ports=%s lines=%s\n' "$ran" "$cases"
