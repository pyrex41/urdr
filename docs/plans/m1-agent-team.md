# M1 agent team scoping

Status: Team plan for executing `docs/plans/m1-abstract-world.md`

Date: 2026-07-25

Convention: continues the M0 numbered-agent-branch flow
(`agent/1-wave0-foundation` … `agent/9-adversarial-verifier`): one agent,
one branch `agent/N-short-name`, one PR, merged only with its acceptance
evidence recorded in the PR body.

## Ground rules

1. **Path allowlists are contracts.** Every agent records its allowlist and
   runs `scripts/check-owned-paths --base-ref main --allow ...` before
   pushing (`docs/module-boundaries.md`). An out-of-scope edit is a review
   rejection, not a judgment call.
2. **Single-writer hotspots.** `bifrost.suite.json`, golden-digest re-pins,
   and `shen/world/world.shen` are merge hotspots. The foreman is the only
   writer of the suite manifest and digest re-pins; `world.shen` is written
   only by agents 10 and 13, strictly in that order.
3. **Evidence, not assertion.** Every PR carries `make quality` output.
   The four-port `make conformance` gate requires the pinned shen-go,
   shen-lua, shen-cl, and shen-rust checkouts (`docs/status/m0.md`), which
   agent sandboxes may not be able to fetch; when unavailable, the agent
   states so and the foreman (or owner machine) runs the gate before merge.
   As with M0, hosted CI remains billing-blocked and never counts as
   evidence either way.
4. **Fail-closed drafting.** Any behavior an agent cannot pin across ports
   is surfaced as a question or an explicit error path — never silently
   chosen. ADR 0004's decisions are binding; deviations require amending
   the ADR first.
5. **Model tier.** All implementation and verification agents run Opus.
   The semantics-bearing agents (12, 13, 16, 17, 21) additionally warrant
   maximum reasoning effort: their output becomes permanent world
   semantics.

## Roster

### Foreman (this session)

Sequencing, PR review against ADR 0004 and the module boundaries, suite
wiring, golden-digest re-pins (each re-pin deliberate and explained),
conflict arbitration, and batch launches. Writes no feature code.

### agent/10-component-interface — Wave A

- Mission: `component-step` contract, reducer dispatch extension,
  well-behaved and misbehaving fixture components.
- Allowlist: `shen/world/component.shen`, `shen/world/world.shen`,
  `shen/tests/world/`.
- Depends on: nothing (M0 only). Blocks: 13, 15, 16.
- Acceptance: plan Wave A criteria; misbehavior fixtures fail closed on
  every port the agent can run; existing golden trace change, if any, is
  isolated and explained for the foreman's re-pin.

### agent/11-scenario-dsl — Wave B

- Mission: canonical scenario representation, strict validation, M1
  declaration subset, parse/reject fixtures, `scenario-parse` case script.
- Allowlist: `shen/scenario/`, `protocol/fixtures/v1/scenario/`,
  `shen/tests/scenario/`.
- Depends on: nothing (M0 canonical values only). Blocks: 13, 20.
- Acceptance: plan Wave B criteria; every invalid fixture rejects before
  any effect.

### agent/12-netkat-core — Wave C (algebra)

- Mission: NetKAT term validation, packet-set denotation, history-free
  equivalence/reachability decision procedure over declared finite header
  spaces; evaluation and decision fixtures with an independent oracle.
- Allowlist: `shen/world/netkat.shen`, `protocol/fixtures/v1/netkat/`,
  `shen/tests/netkat/`.
- Depends on: nothing (M0 integers/canonical). Blocks: 13, 14.
- Acceptance: ADR 0004 verifications 2–3; mutation tests flip verdicts.

### agent/13-abstract-models — Wave C (components)

- Mission: network, timer, and fault components on the agent-10 interface;
  fault states as policy transformations; the counterexample witness
  bridge (`netkat-witness.shen`).
- Allowlist: `shen/world/models/`, `shen/world/netkat-witness.shen`,
  `shen/tests/models/`, plus a foreman-approved dispatch registration in
  `shen/world/world.shen` after agent 10 merges.
- Depends on: 10, 12 merged. Blocks: 16, 17, 20.
- Acceptance: plan Wave C criteria; ADR 0004 verification 4
  (confirmed-or-`unconfirmed`, never silent).

### agent/14-netpol-compiler — Wave C2

- Mission: NetworkPolicy manifest representation, validation, and compiler
  per ADR 0004 Decision 4; upstream-example fixtures; fail-closed
  rejection set; offline YAML converter; `spec-semantics-only` marker.
- Allowlist: `shen/world/netpol.shen`, `protocol/fixtures/v1/netpol/`,
  `shen/tests/netpol/`, `scripts/netpol-to-canonical`.
- Depends on: 12 merged. Blocks: 20 (demo item 5 only).
- Acceptance: ADR 0004 verification 5 in full.

### agent/15-properties — Wave D

- Mission: state-invariant, temporal, and liveness evaluators; canonical
  verdicts in the existing verdict slot; boundary-case fixtures (deadline
  exactly met, empty stream, vacuous antecedent — each pinned explicitly).
- Allowlist: `shen/properties/`, `shen/tests/properties/`.
- Depends on: 10 merged (event vocabulary). Blocks: 16, 17.
- Acceptance: plan Wave D criteria; evaluation is a pure function of the
  canonical trace.

### agent/16-replay-certificates — Wave E

- Mission: §20 event records, transcript replay with first-divergence
  fail-closed errors, modeled-run certificates with entropy-firewall
  counts and the `modeled-world-only` marker.
- Allowlist: `shen/world/replay.shen`, `shen/world/certificate.shen`,
  `shen/tests/replay/`.
- Depends on: 10, 13, 15 merged. Blocks: 17, 20.
- Acceptance: plan Wave E criteria including the 100-replay identity run
  on every port the agent can execute.

### agent/17-explore-shrink — Wave F

- Mission: §17 choice records, baseline and boundary-biased seeded
  strategies, transcript-prefix-aware shrinker with persistence-checked
  candidate acceptance.
- Allowlist: `shen/search/`, `shen/shrink/`, `shen/tests/search/`,
  `shen/tests/shrink/`.
- Depends on: 15, 16 merged. Blocks: 19, 20.
- Acceptance: plan Wave F criteria; shrinker mutation tests reject
  non-persisting failures.

### agent/18-prolog-gate — Wave G (parallel, non-blocking)

- Mission: portability spike for solution order, backtracking, cut, and
  failure across the four pinned ports; then either the
  `prolog-semantics` fixture suite plus `shen/properties/prolog.shen`, or
  the recorded divergence report plus the explicit-state fallback
  evaluator.
- Allowlist: `spikes/m1-prolog-portability/`,
  `protocol/fixtures/v1/prolog/`, `shen/properties/prolog.shen` (or
  fallback module), `shen/tests/prolog/`.
- Depends on: nothing. Blocks: nothing — the milestone must not wait on
  this agent, and no output of this agent is certifying until its gate
  case passes all four ports.

### agent/19-scenario-grammar — Wave H

- Mission: seeded generative grammar for scenario families, every
  expansion a named-stream transcript choice; reproducibility and
  withheld-entry replay-failure tests.
- Allowlist: `shen/search/grammar.shen`, `shen/tests/search/grammar/`.
- Depends on: 17 merged.
- Acceptance: plan Wave H criteria.

### agent/20-m1-integration — Wave I

- Mission: `scenarios/abstract/partition-retry.shen`, the seven-item exit
  demonstration, and `docs/status/m1.md` in the M0 status format with
  explicit non-claims.
- Allowlist: `scenarios/abstract/`, `docs/status/m1.md`, plus
  demonstration scripts under `shen/tests/integration/`.
- Depends on: 10–17 merged (14 for demo item 5; 18 explicitly excluded).
- Acceptance: plan Wave I exit demonstration, with the four-port
  conformance run executed by the foreman/owner where the sandbox cannot.

### agent/21-adversarial-verifier-m1 — rolling red team

- Mission: continue the agent/9 discipline against M1 surfaces — attempt
  to break each merged wave (interface bypass, non-canonical smuggling,
  transcript withholding, verdict tampering, digest-gate mutations) and
  extend `shen/tests/adversarial/` so every found break becomes a
  permanent fail-closed test.
- Allowlist: `shen/tests/adversarial/`.
- Depends on: runs after each batch merges; findings are filed against the
  owning agent's surface and block the next batch until resolved or
  accepted by the foreman.

## Launch batches

```text
Batch 1 (parallel, launch now):   10, 11, 12, 18
Batch 2 (after 10 and 12 merge):  13, 14, 15
Batch 3 (after 13 and 15 merge):  16, then 17
Batch 4 (after 17 merges):        19, 20
Rolling (after each batch):       21
```

The critical path is 10 → 13 → 16 → 17 → 20. Agents 11, 12, 14, 18, 19,
and 21 hang off it in parallel; agent 18 can run the entire milestone
without ever joining the path.

## Failure handling

- An agent that cannot meet its acceptance gate reports the specific
  failing criterion; the foreman decides between rescoping, sequencing a
  fix agent, or amending ADR 0004 — never between "merge anyway" options.
- Two agents needing the same file is a scoping bug: stop, fix the
  allowlists here, then continue.
- Any cross-port disagreement found mid-wave is escalated immediately;
  it is a potential ADR-level fact, not a local workaround.
