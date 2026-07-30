# M2 plan: close the loop

Date: 2026-07-29

Status: **Proposed.** Nothing here is committed until the kill criteria in
§8 are agreed.

Relates to: `SPEC.md` §17, §21, §24, §25, §26.7; ADR 0003, ADR 0004
Decision 3, ADR 0006; `docs/status/m1.md`

## 0. What changed, and why this plan exists

M1 delivered every component of a deterministic laboratory and connected
none of them to each other. That is the finding, and it is not visible from
any single file — only from asking what happens end to end.

- `shen/tests/integration/run-tests.shen` is the M1 exit demonstration. Its
  system under test is `uit.counter` (`:121-122`), a component that ignores
  every input and never changes state. Its oracle is `uit.eval-transcript`
  (`:225-229`), a string search for `inject` over the transcript the test
  just built. The verdicts are hand-written records (`:192-196`).
  `urdr.properties.*` — 1,914 lines of finite-trace property evaluator — is
  never called by it.
- `urdr.world.reduction-choices` (`world.shen:77`) publishes the enabled
  transitions a scheduler should explore. `urdr.model.net`
  (`net.shen:632-661`) publishes exactly the right alternatives per pending
  packet: deliver-at-head, deliver-at-N (reordering), duplicate. Grep finds
  **zero callers outside `world.shen` itself and test files**. Nothing
  consumes either.
- `urdr.search.explore` (`search.shen:525-596`) samples from a
  caller-supplied static list of menus. The world's own menus are not that
  list.
- `urdr.search.schedule-input` (`search.shen:356-360`) writes the choice
  *menu* into the transcript, not the selected alternative. Its own comment
  says the consequence: "the world will re-draw from its own streams on
  reduce." Search draws from subsystem `search`; the world redraws from
  `partition-retry`. Independent draws over the same set. The transcript
  does not pin the decision, which is what `SPEC.md` §17 requires it to do.
- `scenarios/abstract/partition-retry.shen` declares three `process`
  components, and `registry.shen:148-153` hands every `process` the same
  caller-supplied handler. There is no client, no server, no relay. The
  strings `ack` and `retry` appear in this repository only as property and
  observation *identifiers*; no component emits an `ack` fact. The declared
  liveness property `client-ack` is never evaluated. Were it evaluated it
  would FAIL with `no-witness` — the correct fail-closed answer, and no
  evidence whatsoever about partitions.

So M1's headline — "a modeled distributed scenario explores, fails, shrinks,
and replays" — is a test of the search and shrink *machinery* against a
synthetic predicate. As machinery tests those are legitimate and they pass.
As a demonstration of the thing named, they are a wiring diagram with the
wires drawn in.

Second finding, independent of the first: **the determinism certificate
cannot fail.** `eventlog.shen` defines three entropy classes (`:255-261`) and
accepts two (`:506-507`). The only two producers hardcode their answers:
`plan-schedule:728` always emits `w-pure`, `plan-advance-kind:749` always
emits `w-modeled`. Nothing anywhere emits `w-uncontrolled`. Therefore
`urdr.eventlog.abstract?` is `true` for every well-formed log by
construction, `Clean` in `certificate.shen:747` is always true, and
`achieved-profile: modeled-d1-analog` means exactly "the replay verified" —
one bit wearing a five-class summary as a hat. `SPEC.md` §26.7 names false
determinism claims as the greatest product risk; §25 criterion 14 requires
that a deliberately unsupported entropy source produce UNCERTIFIED. That
criterion is currently protected by a function with one reachable answer.

This plan closes both. It borrows its shape from
`downstream-model-harness/docs/design/PLAN.md`, which solved the same
credibility problem for a live production target and whose two organising
devices — a rung ladder you must state rather than oversell, and per-phase
kill criteria — are what M1 lacked.

## 1. Design stance

**Close the loop before widening it.** Every phase below connects existing
components. No phase adds a new subsystem. If a phase requires a new module,
that is a signal the phase is wrong.

**One scenario, end to end, beats twelve suites in isolation.** The
deliverable of M2 is a single scenario in which two components exchange a
message, one of them fails, a property is evaluated against the resulting
trace, and the failure shrinks and replays. That does not exist today at any
size.

**The certificate must be able to say no.** A verdict machine that cannot
return a negative is not evidence, however carefully the positive is
computed.

### Standing hard-stops

- **No Firecracker, no guest, no k3s, no packet broker in M2.** `SPEC.md`
  §9–§15 stays unbuilt and unpromised. See §9.
- **No new port work as a prerequisite.** The four ports agree today; keep
  them that way, but M2 does not block on port fixes.
- **No widening of the Prolog surface.** ADR 0004 Decision 3 stands. The
  2026-07-29 fixes removed the cases where coincidental agreement had
  broken; they did not make the agreement structural. `query.shen` remains
  the supported path.
- **No host numbers in any verdict, certificate, golden, or fixture.** ADR
  0006. This is load-bearing, not stylistic.
- **No golden regenerated to match new output without a human reading the
  diff.** A golden regenerated from wrong output locks the bug in
  permanently, and cross-port agreement does not protect against it when the
  change is in shared Shen.

## 2. The rung ladder — what urdr certifies today

State the rung. Do not oversell it.

`SPEC.md` §4 defines D0–D3 for the whole-system laboratory. Those rungs
describe a machine that does not exist. urdr needs a second, smaller ladder
for the modeled world, because that is what it actually runs — and today it
has no vocabulary for it at all, which is how `modeled-d1-analog` came to
mean "the replay verified."

| Rung | Property | Today |
| --- | --- | --- |
| A0 | Same seed → same choice sequence from a fixed menu list | **Yes**, and tested |
| A1 | Same transcript → one execution order, one final state | **Yes** — `world.shen:224-242` pops the head of a `(time, event-id)`-ordered queue; `rollback` is an error; 100 consecutive replays produce identical roots |
| A2 | Same transcript → the *recorded decision* is the decision executed | **No.** `search.shen:356-360` records the menu; the world redraws. P1 fixes this. |
| A3 | The menus explored are the menus the world publishes | **No.** `reduction-choices` has no consumer. P2 fixes this. |
| A4 | A property is evaluated against the trace the run produced | **No.** The oracle is a string search. P3 fixes this. |
| A5 | An uncontrolled entropy source yields UNCERTIFIED | **No.** Structurally unreachable. P0 fixes this. |
| B0–B3 | Anything about a real VM, guest, or cluster | **No**, and not attempted. See §9. |

M2 targets **A5, A2, A3, A4 in that order** — cheapest-and-most-damaging
first. It makes no B-rung claim.

Cross-implementation byte-identity is a *separate* property that no rung
names, and it is the one urdr genuinely has today. It should be stated as
its own claim rather than folded into a determinism rung, because it is
about the executors, not about the world.

## 3. P0 — Make the certificate able to fail (1 week)

The smallest phase and the one that changes what every later result means.

1. Introduce a reducer input that classifies as `w-uncontrolled`. The
   natural candidate is an explicit `[schedule At host-entropy ...]` form
   that exists **only** so the firewall has something to reject — a probe,
   not a feature. It must be impossible to reach from a valid scenario.
2. Assert the consequence end to end: a log containing it makes
   `urdr.eventlog.abstract?` false, which makes `Clean` false, which makes
   the certificate UNCERTIFIED and drops the achieved profile.
3. Add the negative to the `replay-certificate` golden so the four-port gate
   pins it.
4. Only then is `SPEC.md` §25 criterion 14 testable. Record in the M1 status
   doc that it was untestable before.

**Kill criterion:** if introducing a rejectable class requires changing the
certificate's public shape, stop and reconsider — that would mean the
five-class summary was never derivable and should be replaced by the one bit
it actually carries.

## 4. P1 — Record the decision, not the menu (1 week)

`SPEC.md` §17 requires the selected alternative in the choice record.

1. Change `urdr.search.schedule-input` to write the selected alternative
   into the transcript entry that `urdr.replay.run` consumes. Keep the menu
   in the search's own decision-level audit record, where it is genuinely
   useful.
2. Make `urdr.world.reduce` execute the recorded selection rather than
   drawing from its own stream when the transcript pins one.
3. Prove it: a replay of a transcript must reproduce the run's choices with
   the world's PRNG *seeded differently*. If it still passes, the transcript
   pins the decision. This is the test that A2 exists.

**Kill criterion:** if the world cannot accept an externally-pinned choice
without abandoning its own stream discipline, the seeded-redraw design is
load-bearing in a way this plan misjudged — stop and write an ADR before
touching `search.shen` further.

## 5. P2 — Close the generator loop (2 weeks)

1. Feed `urdr.search.explore` the menus `urdr.world.reduction-choices`
   publishes, replacing the static list. The shapes already match; this is
   plumbing, not design.
2. Give `partition-retry` real handlers: a client that sends and retries, a
   server that acks, wired through `urdr.model.net` so its
   deliver/reorder/duplicate alternatives are the ones explored. Replace the
   `Handler`/`Init` passthrough at `registry.shen:148-153` with per-component
   handlers.
3. Emit `ack` facts. Today no component emits one, which is why the declared
   property is unevaluable.

**Kill criterion:** if the net model's published alternatives turn out not to
be reachable from `reduction-choices` without a translation layer, that layer
is a new subsystem and violates §1 — stop and reconsider the scenario rather
than building an adapter.

## 6. P3 — Make the oracle real (2 weeks)

1. Replace `uit.eval-transcript`'s string search with
   `urdr.properties.check` over `urdr.properties.trace-of-world`, so the
   `client-ack` liveness deadline is evaluated against the fact log the run
   actually produced.
2. Make the shrinker's acceptance oracle a property signature rather than a
   marker string. The shrinker is already correct — it accepts only on
   failure-signature equality, and `MUT|drop-fault|rejected` proves the
   negative direction. It has simply never been given a real signature.
3. Add the dual check the net model is missing: `delivered ⊆
   denotation(active, sent)` (`net.shen:696-713`) is safety-only, and a
   network that delivered *nothing* passes it cleanly. That is exactly the
   bug class that hides in a partition model. Add an under-delivery
   obligation.
4. Extend `urdr.scenario.validate` to reject a property whose pattern names
   a fact no declared component can emit. `client-ack` validating `ok` today
   is a vacuity the validator should catch.

**Kill criterion — this is the real gate.** Run the closed loop with no
fault injected and measure how often a property fails. If the false-positive
rate is not near zero, stop: fault injection on a noisy oracle does not find
bugs, it finds nothing, loudly. This is the lesson `downstream-model-harness`'s PLAN §0 paid
for — downstream-behavior-spec's delta-presence oracle sat at a 77% noise floor on
unperturbed traffic, and their conclusion, *"the floor is the project,"*
applies here before any exploration work is worth doing.

## 7. P4 — Wire the evidence that already exists (1 week)

Cheap, and disproportionate to its cost.

1. Put `shen/tests/netkat/test.sh`, `shen/tests/netpol/test.sh`, and the
   adversarial harness into the Makefile and CI. 5,309 lines of independent
   Python differential oracle currently run from nothing — `make test`
   discovers only `scripts/tests/*.py`. The two most semantically ambitious
   modules in the repository are checked by the gate only for "four ports
   produce identical bytes matching a checked-in file," which is change
   management, not correctness.
2. Commit the executed case×port matrix into the gate's evidence root, so a
   proof attests to *completeness* rather than only to violations. This is
   the one mechanism `cross-validate` has that urdr does not
   (`pkg/audit/proof.go:36`), and it is the structural fix for the fail-open
   class that produced four separate silent greens here.
3. Mechanize the known-divergence registry. ADR 0006 lists two open port
   defects by hand. Following `downstream-model-harness` PLAN §3.2, make them data, where a
   known divergence that *stops* reproducing also reddens the gate — a
   silently-fixed divergence is as much a change as a new one.

## 8. Kill criteria for M2 as a whole

Stop and reassess if any of these hold at the end of P3:

- The false-positive rate on an unperturbed closed loop is not near zero
  (§6).
- Closing the loop requires a new subsystem rather than connecting existing
  ones (§1).
- The four-port gate cannot stay green across the loop closure — that would
  mean the connected system depends on something the ports do not agree on,
  which is a finding worth more than the milestone.
- CI still has not executed. Every result in this repository traces to one
  laptop; 120 of 120 workflow runs have failed in seconds on a billing
  block, and the `make ports` step added on 2026-07-29 has never run on a
  runner. A conformance gate that has never executed anywhere but its
  author's machine is not yet a gate. **This is a prerequisite for M2 exit,
  not a nice-to-have.**

## 9. What M2 is not

- Not Firecracker, not a guest kernel, not k3s, not a packet broker, not
  snapshots, not the `urdr` CLI. `SPEC.md` §9–§15 and §19 remain zero lines,
  and this plan does not start them.
- Not a claim about real distributed systems. The modeled world is a model.
  Proving four Shen implementations agree on it says nothing about whether
  it resembles anything.
- Not a performance project. `integer.shen:3-6` divides by repeated
  subtraction and `integer.shen:275` uses it to halve a binary-search
  midpoint, so a single `prng.sample` costs on the order of 10^6 loop
  iterations, and `canonical.shen:911-924` re-parses its own output on every
  call. Both sit under every world choice and will bite when the loop closes
  and the PRNG runs orders of magnitude more often. Fix them **when P2 makes
  them hurt**, measured, not before — and note the perf handoff doc's
  hypothesis H1 pointed at SHA and never at `divmod`.
- Not a rename. Whether the README should stop describing a Firecracker
  laboratory is a real question and a separate decision. It is raised in
  §10, not settled here.

## 10. The first three things

1. **P0's rejectable entropy class.** One reducer input, one golden line.
   Until the certificate can say no, every green result in this repository
   means less than it appears to.
2. **The A-rung table into `docs/status/m1.md`.** One paragraph stating that
   M1 is A0–A1 plus cross-implementation byte-identity, and that A2–A5 and
   all B rungs are unclaimed. The non-claims tables are already honest; what
   is missing is a positive statement of what *is* claimed, in vocabulary
   that distinguishes it from the SPEC's aspiration.
3. **Unblock CI.** Not an engineering task, and the highest-leverage item in
   this document.
