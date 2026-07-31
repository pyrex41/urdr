# M1.5 handoff: port codegen defects, and the shared root cause

Date: 2026-07-31

Relates to: `docs/status/m1-5.md`, ADR 0007, ADR 0003,
`docs/status/m1-port-perf-handoff.md`

## 0. Why this document exists

Reviewing PR #71 found one fail-open in urdr. It also found that
`make conformance` was already red, and that led somewhere larger:
**three pre-existing code-generation defects in the Shen ports**, two in
shen-lua and two in shen-cl (one shared cause, two distinct symptoms
each). None were caused by PR #71. It was simply the first change deep
enough to trip them.

All three are fixed and merged upstream. The **root cause is shared
across all four ports and is still unfixed**, which is the part worth
carrying forward.

## 1. State at handoff

| repo | branch | head | PR |
|---|---|---|---|
| urdr | `main` | `4516100` | #71 |
| shen-lua | `main` | `4e3b43a` | #53 |
| shen-cl | `master` | `e48776d` | #12 |

Pins advanced in both places that carry them —
`build/locks/shen-ports.lock.json` and `scripts/bifrost-gate`
`EXPECTED_PINS` — with launchers rebuilt and re-stamped via
`make ports` before the gate ran.

Final gate on the merged tree: `make conformance` **PASS**, 13 cases x
4 ports, 0 skips, 0 errors, tree pure. `make fmt-check` and `make test`
(90 + 87) green.

## 2. The shared root cause, still unfixed

All four ports carry a **byte-identical `core.kl`**
(sha256 `7a0e84f3d3440b304fb9e941083084f3aeee3dadd39e5d1583a9f794606e18c0`),
which contains `shen.shendef->kldef`. The KL *output* is identical too:
the same source expands to **3457 nodes, depth 435** on all four ports,
verified by running the pattern compiler on each.

The kernel's pattern compiler re-derives the full `hd`/`tl` accessor
spine per pattern element. Every port therefore receives the same
pathological KL, and they differed only in host tolerance:

- shen-go grows stacks, so it never noticed.
- shen-rust and shen-cl had headroom for depth 435 in the abstract, but
  shen-cl's compiler allocated proportionally to code size.
- LuaJIT has a fixed ~65500-slot stack and a ~200-level parser nesting
  limit, and hit both.

Both port fixes are **coping mechanisms in the backends**. Fixing
`core.kl` would fix all four at once but means changing vendored
upstream kernel code, which was out of scope. If a future wave writes
deeper patterns, expect the ports to diverge again in tolerance rather
than in semantics.

Lineage note: shen-go, shen-lua, and shen-rust share all 19 KLambda
files. **shen-cl differs in 2 of 19** — `compiler.kl` + `stlib.kl` where
the others carry `backend.kl` +
`extension-programmable-pattern-matching.kl`. That is the Tarver vs
community split described in `docs/status/m1-port-perf-handoff.md`. It
does not affect this defect; `core.kl` is on the identical side.

## 3. The defects

### shen-lua: pattern-match codegen exceeded LuaJIT's parser limits

`compiler.lua`. `ctail`'s `if`/`and` handlers emitted one nested Lua
`if` per pattern test **and** re-derived every accessor from the root at
each level, so nesting depth and chunk size both grew with pattern size.
A 7-key record pattern produced `chunk has too many syntax levels`
(LuaJIT `LJ_MAX_XLEVEL`).

Fixed by flat guard emission — only the shallower branch nests, and
every `ctail` branch already ends in `return`/`goto tco` so
fall-through is impossible — plus hd/tl common-subexpression
elimination binding each accessor step once, guarded by a purity flag
and disabled inside deferred bodies (lambda/freeze/trap-error).

### shen-lua: the reader overflowed the Lua stack on large block comments

`klambda/reader.kl`. `shen.<longnatter>` recurses once per block-comment
*character* in a non-tail position (~9 LuaJIT stack slots each) against
a fixed stack. Ceiling ~7.2KB.

The symptom was misleading: `read-file`'s `trap-error` catches any
error, including the stack overflow, and calls `shen.reader-error`,
rebranding it `reader error near here:` with empty context.

Real trigger: **`shen/run/run.shen`'s header comment is 8092 bytes.**
This is a live constraint on this repository's own house style — long
`\* ... *\` module headers are the norm here, and one crossed the line.

Fixed with native iterative scanners for `shen.<singleline>` and
`shen.<multiline>` in `prims.lua` via the existing
`install_native_stdlib` mechanism; kernel KL untouched.
`<longnatter>`'s grammar backtracks (a nested `\*` whose continuation
fails is re-read as plain text), so a nesting counter would be wrong —
it is implemented as a right-to-left dynamic program reproducing the
KL's ordered choice with zero recursion.

### shen-cl: accessor chains rebuilt per conditional level

SBCL consed **802 MB** compiling a single defun — fatal in the 1 GB
image. New CL->CL pass `shen-cl.bind-accessor-chains` in
`src/primitives.lsp`, applied only in `|eval-kl|`: each `CAR`/`CDR` step
is computed once via inline `SETQ` at first occurrence, reused only
along guaranteed-evaluated paths, never across COND clauses / IF
branches / OR alternatives / trap-error, and never inside closure
bodies. `compiled/*.lsp` stays byte-identical.

802 MB / 0.9 s becomes **10.5 MB / 0.01 s**. A 64-field record — 8-16x
past the old death point — now compiles in the default image.

No heap bump was taken. Note `boot.lsp` saves with
`:save-runtime-options t`, which freezes the 1 GB default and blocks
runtime `--dynamic-space-size` overrides, so a bump would be a
deliberate separate change.

### shen-cl: factorise-cases spliced its fallthrough twice, exponentially

`src/overwrite.lsp`. `factored-remaining` was spliced into both the
inner `true` fallthrough and the outer clause list. That is shared
structure in memory, but `compile-expression` walks the tree
recursively, so each factorisation level expanded the next level's
*two* splices: generated code grew **2^groups**.

Measured, where groups are consecutive 2-clause runs sharing a first
test — the shape any plain dispatch table produces:

| groups | CL nodes |
|---|---|
| 8 | 8,173 |
| 12 | 131,053 |
| 16 | 2,097,133 |
| 18 | 8,388,589 |

from KL input growing a flat 24 nodes per group. End to end, a
**33-clause function was fatal**: heap exhaustion after 446 s and
938 MB peak.

Fixed by emitting the remaining clauses **once**, as the label body of a
`%%let-label` join that both fallthrough paths `%%goto-label` to
(compiles to `TAGBODY`/`GO`). This is the mechanism the kernel's
original `factorise-defun` extension used, whose machinery
`src/compiler.shen` had retained unused. Clause order, evaluation
order, and fallthrough are unchanged; zero runtime cost. Growth is now
linear (~48 nodes/group): the fatal 16-group case compiles in 0.03 s /
47 MB, and a 401-clause function in 0.04 s.

Also fixed: `shen-cl.acc-walk` skipped `TAGBODY` wholesale, which would
have silently disabled the accessor-chain pass inside factored dispatch
code.

**This one had nothing to do with urdr.** Any moderately large dispatch
table would have hit it. It simply had not been written yet.

## 4. Verification

Per port, before and after, with byte-identical report lines:

- shen-lua: `make certify` 134/0, `make test` 859/0.
- shen-cl: kernel suite 134/134; port runtime suite 131/131 before,
  136/136 after (+5 regression assertions).

Semantics were checked against sibling ports rather than only against
each port's own baseline: shen-lua's comment corpus and shen-cl's
dispatch probes both produced byte-identical output to shen-rust and
shen-go.

Headroom was demonstrated rather than merely raised — 400-level
patterns, a 1MB block comment (~137x the old ceiling), 5000-deep nested
comments, a 64-field record, a 401-clause function.

## 5. The urdr fail-open this review found

`urdr.model.registry.entry` dispatched on the *presence of a model*
before consulting the kind:

```text
[component Id Kind Node none]  -> kind table
[component Id Kind Node Model] -> model table   \\ Kind never consulted
```

A component declaring `kind: net` with a `model` binding validated
cleanly and built as a crash-aware **process**, discarding the declared
kind. `urdr.run.roster-check` did not catch it either — it only rejects
a `process` with no model — and the certificate's `models` field records
model and node but not kind, so the substitution left no trace in the
evidence. Confirmed empirically on shen-go.

Fixed at the scenario-validation door with the stable code
`scenario-component-model-kind`, plus an invalid protocol fixture. The
registry is untouched: validated scenarios can no longer reach it with
the poisoned shape.

## 6. ADR 0007 corrections

Status `Proposed` -> `Accepted for M1.5`, matching ADR 0008 which
depends on it. D4's route shape corrected to
`[route FACT-NAME FROM-COMPONENT TARGET]` — the code was right
everywhere (validator, kernel, rendering) and the ADR text was wrong.
D3 tightened to say `model` binds to `process` components only.

- **Item 2 is Met.** `1969f74` landed mid-review earning it: real
  partition-retry models, discovery at attempt 2, shrink 28 -> 5,
  replay reproducing the verdicts, a v2 certificate reporting FAIL. An
  earlier revision of this note said "Deferred at acceptance", which was
  true when written and false an hour later.
- **Item 5 remains deferred.** `urdr.run.execute-with` has no caller
  configuring `baseline`, so nothing demonstrates a
  `boundary`-discovered transcript replaying unchanged under another
  strategy. It is recorded as a standalone debt; it previously pointed
  at item 2's wave, which landed without supplying it.

A deferral note that outlives its deferral is the same defect as an
unearned claim, in the opposite direction.

## 7. Open items

- ADR 0007 verification item 5 — strategy independence, open debt.
- The shared `core.kl` accessor-spine expansion (section 2).
- shen-lua's reader has the same per-character-recursion shape in other
  productions (`<sym>`, `<str>`); a multi-KB atom or string literal
  would hit it. Nothing currently triggers it.
- `urdr.world.routing` accessor is dead code.
- `urdr.model.registry.model-entry` passes the init-builder's result
  through unchecked — the one door in the registry path that cannot
  fail closed.
- **GitHub Actions is failing for billing reasons on every repo**: jobs
  die in ~2 s with "The job was not started because recent account
  payments have failed or your spending limit needs to be increased."
  All three merges in this session rest on local gate runs. Until this
  is fixed, CI provides no signal and `make conformance` must be run by
  hand before every merge.

## 8. Method notes

Two process points worth repeating, both learned the hard way here.

**Do not pipe a gate run through `head` or `tail`.** Doing so let
SIGPIPE truncate a `make certify` run mid-way, which read as a
suite that silently stopped early. Redirect to a file and parse the
whole thing.

**Do not hand-write a `.urdr-build-stamp`.** During an override run the
gate correctly refused a launcher with no stamp. A stamp asserts "this
binary was built from this commit"; forging one is precisely the
fail-open `verify_launcher_provenance` exists to close. The right moves
are either a real `make ports` rebuild, or verification through each
suite's own exact-golden comparison — both were used here, in that
order.
