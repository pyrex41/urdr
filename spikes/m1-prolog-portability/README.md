# M1 Prolog portability spike (Wave G)

Status: **ANALYSIS**. Nothing in this directory certifies anything. Per
ADR 0004 Decision 3, no Prolog-derived value may reach a verdict,
certificate, or golden digest unless a four-port fixture suite pins its
behaviour, and that suite does not exist.

## Verdict, as first recorded (Wave G)

**DIVERGENCE.** Shen's integrated Prolog did *not* behave identically
across the four required ports. Of 112 probes run on all four ports,
**102 agreed byte-for-byte and 10 diverged**, in three independent classes.

## Update (2026-07-29): the divergences are fixed; the conclusion is not

All three classes were surface bugs in shen-lua's independent native Prolog
engine, and all three are fixed upstream in shen-lua `dfa7950`. At the
current pins the run is **112 of 112 identical on all four ports**.

Two corrections to the evidence above, both measured rather than read:

- The historical count of 10 was **8**. `results/shen-cl.txt` was stale;
  shen-cl reports `J1-prolog-memory|1000` and errors on the capacity ladder,
  agreeing with shen-go and shen-rust, so D-3 always had a three-port
  majority and shen-lua's reported value was already correct.
- `run-probes.sh` was **silently green**. It invoked `timeout`, which is
  absent from a stock macOS, so every probe died with 127, every raw file
  came out empty, and four empty projections compared equal — the script
  printed `VERDICT: AGREEMENT` with `probe-lines=0`. A second bug captured
  `$?` after `if !` had already inverted it, reporting `exit=0` for a run
  that never happened. Both are fixed, and the script now refuses to compare
  zero probe lines. Any AGREEMENT recorded before that fix is worthless;
  re-run before citing it.

**ADR 0004 Decision 3 still stands and the fallback is not revisited.**
Nothing in the Shen kernel constrains a port's Prolog reimplementation, so
agreement across the remaining 104 probes is *coincidental rather than
structural* — a future shen-lua release can break it again with no test in
this repository objecting. This update removes the cases where the
coincidence had already broken; it is not evidence that the Prolog surface
is portable. `shen/properties/query.shen` remains the supported path.

Per ADR 0004 Decision 3 — "If the fixture suite reveals irreconcilable port
divergence, the fallback is a small explicit-state query evaluator in plain
Shen with the same query surface; the Prolog surface is then dropped rather
than trusted partially" — Phase 2 took the **fallback** path:

- No `protocol/fixtures/v1/prolog/`, no `shen/tests/prolog/`, no Bifrost
  `prolog-semantics` case, and no `shen/properties/prolog.shen` were
  created. Creating them would encode partial trust, which the ADR forbids.
- `shen/properties/query.shen` implements the fallback: an explicit-state
  reachability / invariant / inductive-invariant / counterexample evaluator
  in plain Shen. Its self-check (`probes/query-selfcheck.shen`) is
  **byte-identical on all four ports**.

This is a real result, not a sandbox limitation: every port built and ran
every probe. `BLOCKED` would not be an honest verdict here.

## The three divergence classes

### D-1 — `call/1` (generic goal invocation): shen-lua errors

| Probe | shen-go | shen-lua | shen-cl | shen-rust |
| --- | --- | --- | --- | --- |
| `C9-naf-generic-true` | `failed` | `<error>` | `failed` | `failed` |
| `C10-naf-generic-false` | `holds` | `<error>` | `holds` | `holds` |

Negation-as-failure over a goal passed as a term:

```shen
(defprolog unot
  G <-- (call G) ! (when false);
  _ <--;)
```

shen-lua raises, verbatim:

```text
...dependencies/shen-lua/prolog_compile.lua:984: native call: goal is not a structure
```

The other three ports evaluate it correctly. This removes generic
higher-order goal invocation — the natural way to write `\+`, `forall`, and
any parameterised query driver — from the portable subset.

### D-2 — `var?/1` (varhood test): shen-lua errors

| Probe | shen-go | shen-lua | shen-cl | shen-rust |
| --- | --- | --- | --- | --- |
| `E1-var-unbound` | `unbound` | `<error>` | `unbound` | `unbound` |
| `E7-fresh-var-in-result` | `unbound` | `<error>` | `unbound` | `unbound` |

shen-lua raises, verbatim:

```text
h is undefined (Lua: ...dependencies/shen-lua/prolog_engine.lua:197: attempt to call local 'h' (a nil value))
```

This is a Lua-level internal error (a nil local being called), not a clean
Shen-level failure, so the port is not merely rejecting the predicate — it
is crashing inside its engine.

### D-3 — query capacity: all four ports differ, three distinct behaviours

| Probe | shen-go | shen-lua | shen-cl | shen-rust |
| --- | --- | --- | --- | --- |
| `G4-depth-100` | `done` | `done` | `done` | `done` |
| `G4b-depth-500` | `done` | `done` | `done` | `done` |
| `G4c-depth-1000` | `<error>` | `done` | `done` | `<error>` |
| `G4d-depth-1500` | `<error>` | `done` | `done` | `<error>` |
| `G5-depth-2000` | `<error>` | `done` | `done` | `<error>` |
| `G5b-depth-5000` | `<error>` | `<error>` | `done` | `<error>` |
| `G5c-depth-20000` | `<error>` | `<error>` | `<error>` | `<error>` |
| `J1-prolog-memory` | `1000` | `1000` | `10000` | `1000` |
| `J3-over-smallest-ceiling` | `<error>` | `done` | `done` | `<error>` |

The mechanism is `shen.*prolog-memory*`, the size of the bindings vector
that the kernel's `call-prolog` allocates **per query**. It is a hard
ceiling on how many Prolog variables one query may allocate, and it is a
per-port constant that the pinned kernel version (41.2) does not fix:

| Port | `shen.*prolog-memory*` | Observed ceiling | Failure text |
| --- | --- | --- | --- |
| shen-go | `1000` | between 500 and 1000 | `runtime error: index out of range [1000] with length 1000` |
| shen-rust | `1000` | between 500 and 1000 | same class as shen-go |
| shen-lua | `1000` (ignored) | between 2000 and 5000 | native engine, growable arrays |
| shen-cl | `10000` | between 5000 and 20000 | `Invalid index 10000 for (SIMPLE-VECTOR 10000), should be a non-negative integer below 10000.` |

Two points make this worse than an ordinary resource limit:

1. It is *observable in the compared bytes*. One fixed query returns a
   result on some ports and raises on others, so byte-identical agreement is
   impossible for any query near a ceiling — and the ceilings are 10x apart.
2. It bounds exactly the thing ADR 0004 wants Prolog for. Decision 3 adopts
   Prolog for "reachability, inductive-invariant checking, and
   counterexample search" over abstract models. Search depth is precisely
   the quantity that varies with model size, so the unportable ceiling sits
   on the critical path, not at the periphery.

`shen.*prolog-memory*` is settable at run time via `(shen.prolog-vector-size N)`,
so a future design *could* pin it explicitly on every port. That is a real
mitigation and is recorded as an open question below — but it does not
rescue D-1 or D-2, and pinning a value only masks the deeper finding:

### Root cause: shen-lua does not run the Shen kernel's Prolog at all

shen-lua ships an **independent native Lua reimplementation** of Prolog:

- `.cache/urdr/dependencies/shen-lua/prolog_engine.lua` — a "native soa32
  Prolog / type-inference substrate", self-described in its header as "the
  execution engine that **replaces** the compiled-KL CPS Prolog machinery
  (klambda/prolog.kl runtime + the t-star.kl driver's allocation profile)".
- `.cache/urdr/dependencies/shen-lua/prolog_compile.lua` — its clause
  compiler.

It is selected by default and can be switched off:

```text
SHEN_PROLOG_ENGINE=legacy
```

**With `SHEN_PROLOG_ENGINE=legacy`, shen-lua's probe output becomes
byte-identical to shen-go.** That was verified directly and is the decisive
evidence for the root cause.

This matters more than the individual divergences. Where the four ports
agree on the other 102 probes, three of them agree because they run the
*same* kernel Prolog, and the fourth agrees because an independently written
Lua engine happens to match. Agreement of that kind is **coincidental, not
structural**: it is a property of shen-lua's current implementation effort,
not of the Shen language definition, and nothing in the pinned kernel
version constrains it. A fixture suite pinned today would be pinning a
coincidence, and every future shen-lua release could break it. That is the
strongest argument against admitting the Prolog surface, and it is
independent of whether D-1, D-2, and D-3 could each be worked around.

## What agrees (102 of 112 probes)

Recorded for completeness; it is *not* an argument for partial admission.

- **Solution enumeration order** (probes `A1`–`A12`): first solutions, fact
  order, recursive rules, `findall` order, overlapping clause heads, path
  enumeration in a branching graph. `findall` collects in **reverse**
  enumeration order on every port (the kernel's `overbind` prepends), e.g.
  `(findall X (umember X [a b c]) L)` gives `[c b a]`.
- **Backtracking and re-satisfaction** (`B1`–`B6`): nested generators,
  re-satisfaction after mid-conjunction failure, dead ends, binding unwind
  through deeper recursive calls, `append/3` splitting.
- **Cut** (`C1`–`C8`, `C11`): clause-local cut, cut inside a conjunction,
  cut mid-conjunction with goals still backtracking to its right, cut
  transparency (a cut inside a called predicate stays local to it),
  first-match recursion, and negation-as-failure written with cut against a
  concrete relation.
- **Failure** (`D1`–`D11`): failing queries return `false`, `findall` over a
  failing goal returns `[]`, head mismatch, mid-conjunction failure, deep
  failure, `when` guards, unification clash.
- **Variables and unification** (`E2`–`E6`, `E8`–`E16`): aliasing, absence
  of variable capture across recursive calls, repeat-query determinism, and
  occurs check.
- **Shen values as Prolog terms** (`F1`–`F16`): symbols with dots and
  dashes, nested and improper lists, `[]` as a term, negative and large
  integers, strings, and the ADR 0003 software-integer representation
  `[big SIGN LIMBS]` — unified, destructured in clause heads, and filtered
  through `findall`.
- **Deep search, modes, dynamic clauses** (`G`, `H`, `I`): permutation
  order, naive reverse, nested `findall`, cut under `findall`, `mode` `+`/`-`
  head arguments, `bind`, `assert`/`retract` ordering.

### Occurs check: a portable-but-surprising finding

All four ports agree, but the behaviour is not what a Prolog user expects,
so it is recorded here:

- A directly written `(is X Y)` literal **never** occurs-checks on any port
  (`E16`).
- The occurs check only reaches the guard the kernel generates when it
  linearises a clause head containing a repeated variable
  (`prolog.shen`: `[where [= X Y] B] -> [[(if (value *occurs*) is! is) X Y] | ...]`).
- The `is`/`is!` choice is made when `defprolog` **compiles** the clause, not
  when the query runs. Toggling `(occurs-check -)` after a predicate is
  defined does not change that predicate (`E15`); the flag must be off at
  definition time (`E13`).
- Default is occurs-check **on** (`declarations.shen`: `(set *occurs* true)`).

### `assert`/`retract` need an explicit clause terminator

`(assertz [[p a] <--])` fails on **every** port with `Prolog syntax error
here:`. The kernel splices the asserted clause straight into a generated
`defprolog`, whose grammar requires a `;` terminator, so the working form is:

```shen
(assertz [[p a] <-- ;])
```

Uniform across all four ports, so not a divergence — but undocumented and
worth knowing. ADR 0004 Decision 3 requires Prolog queries to be pure, so
this surface is out of the intended usage anyway.

## Reproducing

```text
./spikes/m1-prolog-portability/run-probes.sh
```

Exit status: `0` agreement, `1` divergence, `2` fewer than four ports
produced evidence. Per-port projections land in `out/` (gitignored); the
committed snapshots are in `results/`.

To check the fallback evaluator instead:

```text
./spikes/m1-prolog-portability/run-probes.sh spikes/m1-prolog-portability/probes/query-selfcheck.shen
```

Launcher paths default to the pinned checkouts and are overridable with
`SHEN_GO`, `SHEN_LUA`, `SHEN_CL`, `SHEN_RUST`.

### Probe design rules

These are the rules that make the comparison trustworthy; reuse them for any
cross-port semantic probe.

- **Every probe prints one line**, `PROBE|<id>|<value>`, so a diff localises
  a divergence to a single named probe.
- **Results are rendered by a printer defined inside the probe file**, never
  by a port's own value writer. Runtime variable naming, gensym counters, and
  print formatting therefore cannot leak into the compared bytes.
- **Results are ground.** Where a probe is *about* an unbound variable, it
  reports a classification (`unbound` / `bound`) obtained with `var?`, not
  the variable itself.
- **Every probe is wrapped in `trap-error`** and renders failures as the
  fixed token `<error>`. Error *message* text is port-specific prose and is
  deliberately excluded from the comparison; one port erroring where another
  succeeds is still caught, because `<error>` differs from the value.
- **Probe files are self-contained** — no `(load)` — so `load` semantics are
  not a variable in the experiment.
- **Output is projected** onto `PROBE|` lines before comparison, which drops
  launcher chatter (shen-lua echoes every top-level form's value and prints a
  run time).

## Port build and invocation reference

Useful to every M1 agent, not just Wave G. Pinned commits are in
`docs/status/m0.md`; checkouts live in `.cache/urdr/dependencies/` and are
placed there by `make bootstrap` (the only network entry point). **Bootstrap
clones but does not build** — the build steps below are manual.

| Port | Build | Launcher | Script invocation |
| --- | --- | --- | --- |
| shen-go | `go build -o .bin/shen-go ./cmd/shen` | `.bin/shen-go` | `shen-go script FILE` |
| shen-lua | `bin/shen -e "(version)"` (warms the KL cache) | `bin/shen` | `shen FILE` |
| shen-cl | `make precompile SHEN=<a working Shen> && make build-sbcl` | `bin/sbcl/shen` | `shen script FILE` |
| shen-rust | `cargo build --release --bin shen-rust` | `target/release/shen-rust` | `shen-rust script FILE` |

Notes learned the hard way:

- **shen-lua takes the file directly**; the other three take a `script`
  subcommand. `scripts/bifrost-gate`'s `LAUNCHERS` map records the launcher
  paths, and the pinned Bifrost checkout's `adapters.json` records the full
  per-port `eval` / `script` / `version` argv templates. Read `adapters.json`
  before inventing an invocation.
- **shen-cl needs a bootstrap chicken-and-egg step.** A fresh clone has no
  `compiled/` tree, and precompiling the kernel requires an *already working*
  Shen. Build shen-go first and point `SHEN=` at it. `make fetch` downloads
  the kernel and is **not** needed here — the pinned checkout already ships
  `kernel/`, and the sandbox has no general network access.
- **shen-lua and shen-cl write `.shen-kernel-cache.bin`** into the working
  directory. `scripts/check-clean-tree` fails if it is left behind, so remove
  it after every run (`run-probes.sh` traps on exit and does this).
- **The dependency cache lives in the main checkout.** A git worktree has no
  `.cache/` of its own; resolve it from `git rev-parse --git-common-dir`.
  `run-probes.sh` does this.
- **shen-go's build takes seconds; shen-rust's takes ~7 minutes**, and the
  `target/` lock is shared if sibling agents build concurrently. shen-cl is
  the fastest port to *run*.
- **`(prolog? ...)` is the query entry point**; `(return X)` yields a value
  and `(findall In Goal Out)` collects solutions (in reverse enumeration
  order). Kernel Prolog builtins live in
  `.cache/urdr/dependencies/shen-cl/kernel/sources/prolog.shen`.

## The fallback: `shen/properties/query.shen`

Same query surface as the dropped Prolog layer, in plain Shen, labelled
`analysis`:

```text
urdr.query.reachable      Model Init Goal Bound
urdr.query.invariant      Model Init Inv  Bound
urdr.query.counterexample Model Init Goal Bound
urdr.query.inductive      Model Inits Inv
```

Models are explicit and finite; predicates are canonical *terms*, not Shen
functions, so a query is data that can be serialised, compared, and pinned:

```text
model ::= [model [STATE ...] [[edge STATE STATE] ...]]
pred  ::= [p-true] | [p-false] | [p-is TERM] | [p-at N TERM]
        | [p-holds TERM] | [p-not P] | [p-and P P] | [p-or P P]
```

Results are canonical terms: `[reached [STATE ...]]`, `[unreached]`,
`[bound-exceeded]`, `[holds]`, `[violated [STATE ...]]`, `[inductive]`,
`[not-inductive STATE STATE]`, `[error REASON]`.

Why it is portable where Prolog is not: it uses only structural equality
over canonical values, explicit list order, and plain integers. No engine
state, no per-port capacity constant, no floating point, no absvectors, no
gensym, no host time or randomness. Search is breadth-first over the edge
list in declaration order with an explicit expansion `Bound`, so exhaustion
is an explicit `[bound-exceeded]` result rather than a hang or a per-port
overflow — the exact failure mode that sank D-3. Reachability is byte-
reproducible **by construction**, not because four engines happen to agree.

Evidence: `results/query-selfcheck-all-ports.txt`, 24 probes, identical on
all four ports (`sha256 91239ce7dc16feb36f2497dee45defb87473d868fda33983a304472f7c7eb83d`).

This is a sketch, deliberately minimal per the Wave G brief. It is not
optimised, has no symbolic representation, and enumerates states explicitly.

## Files

| Path | Role |
| --- | --- |
| `probes/probe-all.shen` | The four ADR 0004 gate criteria: enumeration order (A), backtracking (B), cut (C), failure (D), plus variables (E) and Shen values as terms (F) |
| `probes/probe-stress.shen` | Deep/large search (G), dynamic clauses (H), modes and remaining builtins (I), engine capacity (J) |
| `probes/query-selfcheck.shen` | Four-port self-check of the fallback evaluator |
| `run-probes.sh` | Builds the per-port projections and does the byte comparison |
| `results/shen-*.txt` | Committed per-port snapshots of the Prolog probe runs |
| `results/query-selfcheck-all-ports.txt` | Committed fallback result (all four ports identical) |
| `out/` | Scratch output, gitignored |

## Open questions

1. **Would pinning `(shen.prolog-vector-size N)` close D-3?** Setting it
   explicitly at start-up on every port would equalise the ceiling. This was
   not attempted. It would not touch D-1 or D-2, and it needs a portable
   answer for what happens when a query legitimately exceeds the pinned
   ceiling — the ports raise different, non-portable errors rather than
   returning a clean exhaustion result.
2. **Should the gate require `SHEN_PROLOG_ENGINE=legacy` on shen-lua?** It
   makes all four agree today. It is rejected here because the gate must run
   the ports as the pinned launchers are actually invoked, and because
   depending on a port's non-default engine switch is a fragile contract that
   `docs/status/m0.md` does not pin. Worth an explicit decision rather than
   an implicit one.
3. **Is `shen.*prolog-memory*` reachable portably?** The probes read it as a
   package-internal symbol, which worked on all four ports, but
   `shen.*size-prolog-vector*` was unbound on shen-go and shen-lua. The
   kernel's internal symbol surface is not itself a portability contract.
4. **Does the fallback need a symbolic layer?** The explicit-state evaluator
   enumerates states, so it will not scale to the NetKAT-sized header spaces
   of ADR 0004 Decision 2. Whether the invariant layer needs the symbolic
   treatment that Decision 2 already gives the network policy algebra is a
   Wave-level design question this spike does not answer.
5. **Should ADR 0004 Decision 3 be amended?** The decision anticipated this
   outcome and named the fallback, so no ADR change is strictly required.
   But the finding that shen-lua reimplements Prolog independently is new
   information about the *language oracle* itself (`SPEC.md` §7.2) and may
   deserve recording beyond this spike.
