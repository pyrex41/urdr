#!/bin/sh
# M1 Wave F suite: seeded exploration and transcript shrinking.
#
# Every available Shen port must reproduce the checked-in golden semantic
# output byte for byte. Exploration paths and shrink decisions are pure
# functions of seed + menus + oracle, so any per-port disagreement is a
# semantic bug.
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

PROGRAM=shen/tests/search/run-tests.shen
GOLDEN=shen/tests/search/golden.txt
CACHE=$ROOT/.shen-kernel-cache.bin

# Golden fixtures are source inputs (CONTRIBUTING.md): this script never
# generates one. A missing golden is a hard failure, not permission to
# bless whatever the current build prints.
if [ ! -f "$GOLDEN" ]; then
  printf 'search suite: FAIL missing %s\n' "$GOLDEN" >&2
  printf 'Create and commit the golden deliberately (review the semantic\n' >&2
  printf 'projection by hand); this script will not generate it.\n' >&2
  exit 1
fi

SEMANTIC='^(CHOICE\||STRAT\||EXPLORE\||SHRINK\||MUT\||REPLAY\||SEED\||FAIL\||EXPLORE-SHRINK CASES: |EXPLORE-SHRINK: FAIL$|ALL PASS$)'

work=$(mktemp -d "${TMPDIR:-/tmp}/urdr-search.XXXXXX")
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

if [ "$ran" -eq 0 ]; then
  printf 'search suite: BLOCKED no Shen port launcher was available\n' >&2
  exit 1
fi

cases=$(/usr/bin/grep -c \
  '^\(CHOICE\|STRAT\|EXPLORE\|SHRINK\|MUT\|REPLAY\|SEED\)|' "$GOLDEN" \
  2>/dev/null || printf '0')
printf 'search suite: ALL PASS ports=%s lines=%s\n' "$ran" "$cases"
