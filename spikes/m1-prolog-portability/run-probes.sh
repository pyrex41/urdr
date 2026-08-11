#!/bin/sh
# Wave G Prolog portability spike runner (ADR 0004 Decision 3).
#
# Runs spikes/m1-prolog-portability/probes/probe-all.shen on all four required
# Shen ports, projects each port's stdout onto the semantic PROBE| lines, and
# compares the four projections byte-for-byte.
#
# Status: ANALYSIS ONLY. A PASS here is spike evidence, not the admissibility
# gate; the gate is a Bifrost case under scripts/bifrost-gate.
#
# Launcher paths default to the pinned checkouts under
# .cache/urdr/dependencies and can be overridden with SHEN_GO, SHEN_LUA,
# SHEN_CL, SHEN_RUST.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SPIKE=$ROOT/spikes/m1-prolog-portability
# Dependencies live in the main checkout's .cache. When this runs from a git
# worktree, $ROOT has no .cache of its own, so fall back to the directory that
# owns the shared git dir.
DEPS=${URDR_DEPENDENCIES:-}
if [ -z "$DEPS" ]; then
  DEPS=$ROOT/.cache/urdr/dependencies
  if [ ! -d "$DEPS" ]; then
    common=$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    if [ -n "$common" ]; then
      DEPS=$(dirname -- "$common")/.cache/urdr/dependencies
    fi
  fi
fi
PROBES=${*:-$SPIKE/probes/probe-all.shen $SPIKE/probes/probe-stress.shen}

GO=${SHEN_GO:-$DEPS/shen-go/.bin/shen-go}
LUA=${SHEN_LUA:-$DEPS/shen-lua/bin/shen}
CL=${SHEN_CL:-$DEPS/shen-cl/bin/sbcl/shen}
RUST=${SHEN_RUST:-$DEPS/shen-rust/target/release/shen-rust}

OUT=$SPIKE/out
mkdir -p "$OUT"

# Per-probe wall clock. `timeout` is coreutils and is absent from a stock
# macOS; when it was invoked unconditionally every probe died with 127, every
# raw file came out empty, and four empty projections compared equal -- the
# script printed VERDICT: AGREEMENT having run nothing at all. Resolve it once,
# here, and fail closed rather than silently dropping the limit.
TIMEOUT=
for candidate in timeout gtimeout; do
  if command -v "$candidate" >/dev/null 2>&1; then
    TIMEOUT=$candidate
    break
  fi
done
if [ -z "$TIMEOUT" ]; then
  echo "run-probes: neither timeout nor gtimeout on PATH;" >&2
  echo "            install coreutils or set URDR_PROBE_NO_TIMEOUT=1 to run unbounded." >&2
  [ "${URDR_PROBE_NO_TIMEOUT:-}" = "1" ] || exit 2
fi

# Runs one probe under the resolved limit, or unbounded when explicitly allowed.
run_probe() {
  if [ -n "$TIMEOUT" ]; then
    "$TIMEOUT" 900 "$@"
  else
    "$@"
  fi
}

# Probe programs that load repository modules use repository-relative paths.
cd "$ROOT"

# shen-lua and shen-cl drop a kernel cache in the working directory. Leaving it
# behind would make scripts/check-clean-tree fail, so clear it on every exit.
# shen-lua names it per Lua build (.shen-kernel-cache.<hash>.bin; older builds
# wrote .shen-kernel-cache.bin), so clear every variant.
KERNEL_CACHE_PREFIX=$ROOT/.shen-kernel-cache
cleanup() { rm -f "$KERNEL_CACHE_PREFIX"*.bin; }
trap cleanup EXIT HUP INT TERM
cleanup

# Semantic projection: keep only the probe lines and the completion marker.
# Everything else (shen-lua's top-level value echo, timing lines, banners) is
# launcher chatter and is not part of the compared bytes.
project() {
  /usr/bin/grep -E '^(PROBE\|.*|PROBES COMPLETE)$' || true
}

# Runs every probe program on one port, concatenating the projections in a
# fixed order so the per-port file is a single comparable artifact.
run_port() {
  name=$1
  shift
  sem=$OUT/$name.txt
  : >"$sem"
  : >"$OUT/$name.err.txt"
  status=ok
  for program in $PROBES; do
    base=$(basename -- "$program" .shen)
    raw=$OUT/$name.$base.raw.txt
    # Capture $? from the command itself. `if ! cmd; then status=$?` reads the
    # status the `!` already inverted, so a failed probe reported exit=0.
    rc=0
    run_probe "$@" "$program" >"$raw" 2>>"$OUT/$name.err.txt" || rc=$?
    if [ "$rc" -ne 0 ]; then
      status="exit=$rc"
    fi
    printf '== %s ==\n' "$base" >>"$sem"
    project <"$raw" >>"$sem"
  done
  lines=$(/usr/bin/grep -c '^PROBE|' "$sem" || true)
  echo "$lines" >"$OUT/$name.count"
  printf '%-10s run=%-8s probe-lines=%s\n' "$name" "$status" "$lines"
}

echo "== port launchers =="
for pair in "shen-go:$GO" "shen-lua:$LUA" "shen-cl:$CL" "shen-rust:$RUST"; do
  n=${pair%%:*}
  p=${pair#*:}
  if [ -x "$p" ]; then
    printf '%-10s %s\n' "$n" "$p"
  else
    printf '%-10s MISSING (%s)\n' "$n" "$p"
  fi
done

echo
echo "== probe programs =="
for program in $PROBES; do echo "$program"; done

echo
echo "== runs =="
# Invocation differs per port: shen-go/shen-cl/shen-rust take a `script`
# subcommand, shen-lua takes the file directly.
[ -x "$GO" ] && run_port shen-go "$GO" script || echo "shen-go    SKIPPED"
[ -x "$LUA" ] && run_port shen-lua "$LUA" || echo "shen-lua   SKIPPED"
[ -x "$CL" ] && run_port shen-cl "$CL" script || echo "shen-cl    SKIPPED"
[ -x "$RUST" ] && run_port shen-rust "$RUST" script || echo "shen-rust  SKIPPED"

echo
echo "== four-port comparison =="
missing=0
for n in shen-go shen-lua shen-cl shen-rust; do
  # Emptiness alone is not enough: run_port writes a `== base ==` header per
  # probe before projecting, so the file is non-empty even when every probe
  # failed to launch. Count the semantic lines instead -- zero PROBE| lines is
  # no evidence, and four ports with zero lines each compare equal.
  if [ ! -s "$OUT/$n.txt" ]; then
    echo "$n produced no semantic output"
    missing=1
    continue
  fi
  count=$(cat "$OUT/$n.count" 2>/dev/null || echo 0)
  if [ "$count" -eq 0 ]; then
    echo "$n produced 0 PROBE| lines (ran nothing)"
    missing=1
  fi
done
if [ "$missing" -ne 0 ]; then
  echo "VERDICT: BLOCKED (fewer than four ports produced evidence)"
  exit 2
fi

ref=$OUT/shen-go.txt
diverged=0
for n in shen-lua shen-cl shen-rust; do
  if /usr/bin/cmp -s "$ref" "$OUT/$n.txt"; then
    printf '%-10s IDENTICAL to shen-go\n' "$n"
  else
    printf '%-10s DIVERGES from shen-go\n' "$n"
    /usr/bin/diff -u "$ref" "$OUT/$n.txt" || true
    diverged=1
  fi
done

echo
/usr/bin/shasum -a 256 "$ref" 2>/dev/null || /usr/bin/sha256sum "$ref"
if [ "$diverged" -eq 0 ]; then
  echo "VERDICT: AGREEMENT on all four ports (analysis-only evidence)"
else
  echo "VERDICT: DIVERGENCE"
  exit 1
fi
