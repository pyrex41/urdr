# Handoff: Shen port performance vs shen-cl (M1 four-port work)

**Date:** 2026-07-27  
**Repo:** `pyrex41/urdr` (this tree)  
**Context:** Finishing M1 four-port evidence with Bifrost. Semantics are largely fine; **wall-clock is the blocker** for `make conformance` / `scripts/bifrost-gate`.

**Ask:** Measure, bisect, and **file upstream issues** on the slow ports with minimal reproducers. Do **not** block M1 semantics on fixing ports—document gaps and timeout policy if needed.

---

## TL;DR

Full wall-clock matrix (2026-07-27, sequential, `SHEN_KERNEL_CACHE=off`, timeout 600s except replay 900s):

| Suite | **shen-cl** | shen-go | shen-lua | shen-rust |
| --- | ---: | ---: | ---: | ---: |
| startup (tiny `(output "hi")`) | **~13 ms** | ~150 ms | **~1.2 s** | ~400 ms |
| world | **0.73 s** | 2.58 s (~3.5×) | 4.47 s (~6×) | 5.93 s (~8×) |
| search (Wave F) | **6.25 s** | 51.5 s (**~8×**) | 72.6 s (**~12×**) | 150.6 s (**~24×**) |
| grammar (Wave H) | **4.39 s** | 71.9 s (**~16×**) | 64.2 s (**~15×**) | 96.2 s (**~22×**) |
| integration (Wave I) | **3.09 s** | 20.0 s (~6.5×) | 41.0 s (~13×) | 48.4 s (~16×) |
| **replay** (LOOP 100 SHA) | **53.9 s** PASS | **746.6 s** PASS (~14×) | **>900 s TIMEOUT** | **>900 s TIMEOUT** |

All non-timeout rows above returned **ALL PASS** (semantics OK when they finish).

**Replay** is the killer: pure-Shen digests + **100 consecutive replays**. CL ~54s; go ~12.5 **minutes**; lua/rust **do not finish in 15 minutes**. Bifrost stock **heavy timeout = 300 s** → gate fails long before those finish.

**Dominant cost in Urdr suites:** portable software **SHA-256 + bigints** in pure Shen (`shen/world/prng.shen`, eventlog digests, certificates). See comment in `shen/tests/replay/run-tests.shen` (“SHA-256 in portable Shen is the dominant cost”).

---

## Environment (reproduce these numbers)

| Item | Value |
| --- | --- |
| Host | macOS Darwin, arm64 (user’s machine) |
| Kernel version (all ports) | **41.2** |
| Urdr | `/Users/reuben/projects/urdr` on `main` (plus local uncommitted gate fixes—see below) |
| shen-cl | `/Users/reuben/projects/urdr-shen-cl-41.2` @ `8df94be8365ab48561655673593c137f55f92cdb` (`pyrex41/shen-cl`) → `bin/sbcl/shen` |
| shen-go | `/Users/reuben/projects/shen-go` @ `8775fc366945bfe863f0cb0e0af2ada901ae1819` → `.bin/shen-go` |
| shen-lua | `/Users/reuben/projects/shen-lua` @ `c85ad7edc79e183918b67862b8a60fa17c7ac9b9` → `bin/shen` (needs **luajit** on PATH; brew: `luajit`) |
| shen-rust | `/Users/reuben/projects/shen-rust` @ `a529924d7f9c16d839397148cf60747f736dd7b1` → `target/release/shen-rust` + `SHEN_KERNEL_DIR=.../kernel/klambda` |
| Bifrost pin | `51d24d81f7c7a15d382f1c02238453693bb46158` under `.cache/urdr/dependencies/bifrost` |
| Locks | `build/locks/shen-ports.lock.json`, `build/locks/tools.lock.json` |

```bash
export PATH="/Users/reuben/.local/Homebrew/bin:$PATH"   # luajit
export SHEN_KERNEL_DIR=/Users/reuben/projects/shen-rust/kernel/klambda
export SHEN_KERNEL_CACHE=off SHEN_FASL=off
export SHEN_CL=/Users/reuben/projects/urdr-shen-cl-41.2/bin/sbcl/shen
export SHEN_GO=/Users/reuben/projects/shen-go/.bin/shen-go
export SHEN_LUA=/Users/reuben/projects/shen-lua/bin/shen
export SHEN_RUST=/Users/reuben/projects/shen-rust/target/release/shen-rust
cd /Users/reuben/projects/urdr
```

Invocation patterns (match suite `test.sh` / Bifrost adapters):

```text
shen-cl:   $SHEN_CL script PATH.shen
shen-go:   $SHEN_GO script PATH.shen
shen-rust: $SHEN_RUST script PATH.shen
shen-lua:  $SHEN_LUA PATH.shen          # no "script" subcommand
```

---

## What is *not* the problem

1. **Semantic disagreement on M1 new suites (when they finish):**  
   `explore-shrink`, `scenario-grammar`, `m1-integration` already passed **exact-golden on all four ports** earlier the same day.
2. **Wrong pins:** lock commits match the trees above.
3. **“CL is cheating with host crypto”:** Urdr SHA is pure Shen on every port; CL is just much faster at *interpreting/compiling* that pure Shen.
4. **Gate shape bug on world-reducer** is a separate urdr bug (fixed locally, uncommitted)—not a port perf issue. See “Local urdr patches” below.

---

## Hypotheses to test (ordered)

### H1 — Pure-Shen SHA / bigint is the tax; ratio is structural
- **Evidence:** M0 candidate PRNG suite already showed CL 0.36s vs Go 2.2s / Lua 3.7s / Rust 6.2s (`spikes/m0-candidates/prng-sha256/EVIDENCE.md`). Search suite amplifies that (~8× / 12× / 24×).
- **Test:** Isolate `urdr.prng` / SHA only (existing `shen/tests/prng/`) with `/usr/bin/time -lp` and allocation sampling.
- **Issue shape:** “Portable software SHA-256 is N× slower than shen-cl on workload W; profile points at …”

### H2 — shen-rust one-shot path is tree-walker; loaded Urdr code never AOT-overlays
- **Evidence:** `shen-rust/PERFORMANCE.md` — bare default is tree-walker; VM (`SHEN_RUST_VM=1` / `--served`) wins on *warm* workloads; AOT overlay is opt-in for known `.shen` files. Our suites **load many `.shen` modules once then thrash digests**—worst of both worlds if still tree-walking user defs.
- **Test:**  
  - Time `replay` with default vs `SHEN_RUST_VM=1`.  
  - Check whether AOT overlay can cover `shen/world/prng.shen` / `eventlog.shen`.  
  - Sample RSS during LOOP|100 (we saw multi-GB growth—GC off by default? `SHEN_RUST_GC=1`).
- **Issue:** rust#? “Urdr-scale pure-Shen SHA suite: 24× vs CL; tree-walker + no GC thrash”

### H3 — shen-lua startup + load echo / fasl cold path
- **Evidence:** tiny script ~1.2s (vs CL 13ms). Suite stdout on lua has **~100 load-echo lines** vs 4–17 on other ports (`out_lines=102` on world, `109` on search)—possible I/O tax; also first-boot KLambda compile.
- **Test:** `-q` / hush; warm fasl second run; compare with `luajit` vs plain `lua`.
- **Issue:** lua#? “Cold start ~100× CL for trivial script; load echo inflates suite wall time”

### H4 — shen-go leaves pure Shen on the VM; optional Go compile unused
- **Evidence:** README “compile hot files to Go” is optional; measured ~1.6–1.9× only on recursion bench vs its own VM, not vs CL.
- **Test:** Profile one SHA block; see if `urdr.prng` stays interpreted.
- **Issue:** go#? “Software SHA suite 8× CL; no path to native for hot pure-Shen modules”

### H5 — Bifrost 300s heavy timeout is wrong for Urdr, not “port broken”
- **Evidence:** `TIMEOUT_HEAVY = 300` in pinned `bifrost.py`; rust replay ≫ 300s → gate `FAIL` with empty case evidence.
- **Urdr fix (done locally, uncommitted):** raise via `URDR_BIFROST_HEAVY_TIMEOUT` (default 2400) after importing bifrost in `scripts/bifrost-gate`.
- **Do not file on ports** for pure timeout; file only if port is pathologically slow vs peers.

### H6 — Suite design amplifies cost (secondary)
- Replay LOOP 100 is intentional Wave E acceptance (“100 consecutive replays”).
- Explore/search does many digests + path digests.
- Optional: add a **fast smoke** subset for CI and keep LOOP 100 for nightly / CL-only—**product decision**, not a port bug.

---

## Minimal reproducers for issues

### R1 — Startup

```bash
printf '%s\n' '(output "hi~%")' > /tmp/tiny.shen
/usr/bin/time -lp $SHEN_CL script /tmp/tiny.shen
/usr/bin/time -lp $SHEN_GO script /tmp/tiny.shen
/usr/bin/time -lp $SHEN_LUA /tmp/tiny.shen
/usr/bin/time -lp env SHEN_KERNEL_DIR=... $SHEN_RUST script /tmp/tiny.shen
```

### R2 — Medium pure-world (already timed)

```bash
/usr/bin/time -lp $SHEN_CL script shen/tests/world/run-tests.shen
# same for go/lua/rust
```

### R3 — SHA-heavy (best for port issues)

```bash
/usr/bin/time -lp $SHEN_CL script shen/tests/prng/run-tests.shen
/usr/bin/time -lp $SHEN_CL script shen/tests/replay/run-tests.shen   # LOOP 100
```

### R4 — Search (M1 Wave F, good amplifier)

```bash
/usr/bin/time -lp $SHEN_CL script shen/tests/search/run-tests.shen
```

Capture: wall, user, max RSS (`time -lp` on macOS), `ALL PASS` yes/no, commit SHAs.

---

## Measured data dump (2026-07-27, this machine)

### Startup (3 warm-ish runs, wall seconds)

```text
cl:   0.013  0.012  0.013
go:   0.138  0.144  0.183
lua:  1.278  1.326  1.113
rust: 0.384  0.435  0.379
```

### Suites (complete matrix, wall seconds)

```text
world:        cl 0.73 | go 2.58 | lua 4.47 | rust 5.93      ALL PASS
search:       cl 6.25 | go 51.53 | lua 72.60 | rust 150.62  ALL PASS
grammar:      cl 4.39 | go 71.94 | lua 64.24 | rust 96.22   ALL PASS
integration:  cl 3.09 | go 20.00 | lua 41.01 | rust 48.40   ALL PASS
replay:       cl 53.86 PASS | go 746.62 PASS | lua TIMEOUT>900 | rust TIMEOUT>900
```

Note: lua suite runs print many load-echo lines (`out_lines` 67–159 vs 4–17 on other ports)—possible I/O tax; still ALL PASS when finished.

### Prior M0 PRNG candidate (same pins, 2026-07-24)

```text
cl 0.36s | go 2.24s | lua 3.71s | rust 6.21s   (29 tests)
```

### Gate failures seen (not all are port bugs)

| Symptom | Cause |
| --- | --- |
| `shen-lua live kernel-version probe failed` | `luajit` missing from PATH (`env: luajit: No such file`) |
| `world raw output or lowercase trace changed` | Gate still expected `WORLD TESTS: 11/11` and ignored `WORLD-COMPONENT-TRACE` (Wave A suite grew to 21/21) |
| `replay-certificate Bifrost verdict is 'FAIL'` | Almost certainly **timeout** (300s) on slow port, not golden mismatch |

---

## Local urdr patches (uncommitted on agent machine—land separately)

In `scripts/bifrost-gate` + `scripts/tests/test_bifrost_gate.py`:

1. Project `WORLD-COMPONENT-TRACE` and accept `WORLD TESTS: 21/21 PASS` (4 semantic lines).
2. Override `module.TIMEOUT_HEAVY` from env `URDR_BIFROST_HEAVY_TIMEOUT` (default **2400**).

Do **not** mix these into port issues. Commit as `build: fix world-reducer projection and heavy timeout for M1 suites`.

---

## Upstream issue filing plan

File **one issue per port** (or one per distinct bug class). Tag with host, commit, and R1–R4 numbers.

### pyrex41/shen-rust

**Title:** `Performance: pure-Shen SHA / Urdr search suite ~24× slower than shen-cl; multi-GB RSS on replay LOOP`

**Body outline:**

- Pins + machine
- Table: world / search / replay wall times vs shen-cl
- Note tree-walker default; ask whether AOT overlay or VM is recommended for multi-module load + digests
- RSS growth during `shen/tests/replay` LOOP 100; GC default off
- Repro R3/R4
- Expected: guidance + whether this is “known structural” vs regression

### pyrex41/shen-lua

**Title:** `Performance: cold start ~1.2s for trivial script (~100× shen-cl); Urdr search ~12× CL`

**Body outline:**

- Startup R1 numbers
- Suite load-echo line spam (`out_lines` 100+) vs hush/-q
- Search suite timing
- Confirm LuaJIT path; fasl warm second-run numbers if measured
- Ask for recommended flags for batch suite runners (Bifrost)

### pyrex41/shen-go

**Title:** `Performance: Urdr search suite ~8× shen-cl on pure-Shen SHA-heavy load`

**Body outline:**

- Search + world timings
- Whether optional Go compile of hot modules applies to loaded Urdr paths
- Profile ask: interpreter vs AOT share on software SHA loop

### pyrex41/shen-cl

**No perf bug**—reference only. Optional: thank-you note that SBCL remains the M1 merge-evidence port for a reason.

### pyrex41/bifrost (optional)

**Title:** `Heavy timeout 300s insufficient for project suites with pure-Shen crypto loops`

- Urdr replay on shen-rust needs >10 min
- Suggest env-overridable heavy timeout for suite mode (urdr already monkeypatches)

---

## Suggested agent workflow

1. **Reproduce** R1 + world + search on all four ports; record `time -lp` (wall + max RSS).  
2. **Profile rust** on `search` or one SHA loop (`sample` / Instruments / `RUST_LOG` if any). Confirm tree-walk vs VM.  
3. **Profile lua** cold vs warm fasl; `-q`.  
4. **File issues** with tables above + commit SHAs.  
5. **Recommend urdr policy:**  
   - Merge evidence: **shen-cl** (existing directive)  
   - Four-port exact-golden: nightly / long timeout  
   - Optional: `LOOP` parameter for smoke vs full  
6. **Do not** change Urdr semantics to “fix” ports unless an ADR says so.

---

## Related paths in urdr

| Path | Why |
| --- | --- |
| `shen/world/prng.shen` | Software SHA-256, named streams |
| `shen/world/eventlog.shen` / `certificate.shen` / `replay.shen` | Digest thrash |
| `shen/tests/replay/run-tests.shen` | LOOP 100; cost comments |
| `shen/tests/search/` | Wave F amplifier |
| `scripts/bifrost-gate` | Timeouts + semantic projection |
| `bifrost.suite.json` | All cases `"heavy": true` |
| `spikes/m0-candidates/prng-sha256/EVIDENCE.md` | Prior four-port timings |
| `docs/status/m1.md` | M1 claims / non-claims |

---

## Success criteria for this investigation

- [ ] Per-port issue URLs filed (rust, lua, go at minimum)  
- [ ] Repro scripts paste-clean in each issue  
- [ ] Written recommendation: expected ratios vs “actionable regression”  
- [ ] Optional: env flags that improve rust/lua without changing digests  
- [ ] Optional PR to urdr: gate timeout + world projection (if not already merged)

---

## Contact / continuity

This handoff was produced mid four-port sweep after M1 feature land (PR #66). Full `make conformance` was **not** green end-to-end due to timeouts/shape bugs; **semantic exact-golden for F/H/I on four ports was achieved** when suites were allowed to finish.

---

## Q&A (continued 2026-07-27): "fast mode" and batteries SHA

### 1. Why can't we just compile / run each port in "fast mode"?

We can turn on pieces of each port's fast path — but **none of them put loaded Urdr SHA on SBCL-class native unboxed arithmetic** without port-side build work. Details:

| Port | What "fast" means for *loaded* user code | Why flipping a flag is not enough for Urdr |
| --- | --- | --- |
| **shen-cl** | SBCL compiles every `defun` to native code | Already the baseline. No further flag. |
| **shen-rust** | (a) **Bytecode VM** — default for `script`/`eval` at pin `a529924` (opt out `SHEN_RUST_VM=0`); ~2.3× vs tree-walk on warm served work. (b) **AOT overlay** — offline `scripts/codegen-shen-aot.sh` → committed Rust module; after load, host swaps defuns if source+kernel hashes match (~3× over VM, ~11× over tree-walk on authz). (c) **`SHEN_RUST_GC=1`** — reclaim; mid-run safepoint exists in the **VM** dispatch loop, **not** in the tree-walker during a single `script` apply (depth never returns to 0). | **VM is already on for our suite path.** Measured ~24× search is therefore the *VM-boxed* cost, not tree-walk neglect. AOT overlay requires building/committing `prng.shen` (+ deps) *into the port* (or shipping overlay artifacts from urdr and wiring `install_overlay_if_match`). GC alone does not make SHA faster; it only bounds multi-GB grow-only RSS. Cranelift JIT does not see named loaded defuns. |
| **shen-go** | Optional **whole-file AOT → Go plugin** (`make precompile FILE=… OUT=hot.so` then `./shen -precompiled hot.so`). | Real but modest: **~1.6–1.9×** over the VM on recursion benches, still **~4× behind SBCL** because codegen keeps boxed `Obj` + trampoline. Compile latency ~1 s/fn; never auto-on `defun`. Would need a precompile step in Bifrost adapters for `prng.shen`/`eventlog.shen` and would not close the SHA wall. |
| **shen-lua** | Already **source-to-source compiles** load to Lua; LuaJIT traces. Warm **kernel bytecode cache** (~30 ms boot) + **user fasl** (skip re-read/typecheck). `-q` hushes load echo. | User code is already on the best engine this port has. Residual cost is boxed Shen arithmetic + GC pacing (~27% wall observed under hard churn), not "forgot to compile." Fasl helps *startup/load*, not per-op SHA. No host SHA primitive. |

**Structural takeaway:** "Fast mode" on the non-CL ports still means *a better interpreter or still-boxed native*, not unboxed fixnum SHA. The ratio that kills replay is millions of bit/byte list ops × interpreter tax. Closing that needs either (i) port AOT of hot modules into *unboxed* code, (ii) a host `sha256` primitive with byte-for-byte checks against pure Shen, or (iii) suite design that does not thrash software SHA 100× per gate.

**Practical urdr knobs (no digest change):**

```text
# already the shen-rust script default at current pin:
#   SHEN_RUST_VM unset → VM on for `script`/`eval`
SHEN_RUST_GC=1          # bounds RSS; use with VM (default script engine)
# shen-lua:
#   leave fasl ON for warm CI; use -q / hush to cut load-echo I/O
#   SHEN_FASL=off only for cold-path repros
# shen-go:
#   make precompile FILE=shen/world/prng.shen …  (experiment only; adapter work)
```

**Gate fix note (local, uncommitted on top of `ef1a17f`):** rebinding `TIMEOUT_HEAVY` alone does **not** reach Bifrost `run_suite` — `execute_cases(..., heavy_timeout=TIMEOUT_HEAVY)` binds the default at import. Working fix: `functools.partial(execute_cases, heavy_timeout=heavy)` after import. Unit tests in `scripts/tests/test_bifrost_gate.py` cover this (30 tests OK).

### 2. Why isn't SHA-256 a batteries-included / max-speed thing? (tizoc/shen-batteries)

**`https://github.com/tizoc/shen-batteries` has no crypto.** It is a general library collection (box, dict, iter, lazy, maybe, seq, …) last structured around 2019-era community libs. Forking it does **not** give you a fast SHA-256; there is nothing there to update.

Urdr already made an explicit M0 choice (**ADR 0003**):

- Pure, arithmetic-only SHA-256 over software integers is the **semantic oracle** so all four ports (including double-backed ones) agree bit-for-bit without host SHA, host bignums, or nonstandard bitwise ops.
- That deliberately trades data-path performance for portability and reviewability.
- ADR consequence: *"Native acceleration may be added only as a byte-for-byte verified optimization; portable Shen remains the semantic oracle."*

So the right design is **not** "replace pure Shen with batteries SHA," but:

1. **Keep** `shen/world/prng.shen` (and NIST/oracle vectors) as the authority.
2. **Optionally** add a verified fast path:
   - **Host primitive** per port (`sha256-octets` → OpenSSL / `crypto/sha256` / LuaJIT bit / Rust `sha2`) behind a feature flag, gated by the existing vector suite; or
   - **Port AOT** of `prng.shen` / digest helpers (rust overlay, go precompile) so the *same* pure Shen becomes less terrible without changing the algorithm.
3. If a shared pure-Shen library is desired for the ecosystem, a **new** module (urdr-extracted or a batteries PR adding `crypto/sha256`) can host the portable oracle — useful for other projects, **not** a free win for gate wall-clock.

Forking batteries for Urdr alone is low leverage: ownership, kernel-version drift, and still-slow pure Shen on non-CL engines. Prefer either (a) keep oracle in-tree as now, or (b) extract a tiny `urdr-sha256` / upstream-to-batteries portable module *plus* verified host acceleration.

### Updated recommendation (policy)

| Lane | Policy |
| --- | --- |
| Merge evidence | **shen-cl** (already directive); exact-golden when required |
| Four-port CI | Long `URDR_BIFROST_HEAVY_TIMEOUT` (default 2400 once partial-binding fix lands); expect multi-minute replay on go; 10–15+ min on lua/rust until acceleration |
| Port issues | File **structural perf + GC safepoint / fasl guidance**, not "broken semantics" |
| Product accel | ADR-compliant path: host SHA or AOT of `prng.shen`, vector-gated; do not drop portable oracle |
| Suite product | Optional smoke `LOOP` vs full 100 for nightly (Wave E acceptance stays full on CL / long jobs) |
