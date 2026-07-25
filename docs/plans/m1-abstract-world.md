# M1 implementation plan: abstract world

Status: Draft plan for the `SPEC.md` §24 M1 milestone, incorporating
ADR 0004 (Proposed)

Date: 2026-07-25

Prerequisites: M0 semantic gate PASS (`docs/status/m0.md`), ADR 0002,
ADR 0003, `docs/module-boundaries.md`

## Goal

Deliver the abstract world: a modeled distributed scenario — no VMs, no
native adapters beyond test fakes — that explores, fails, shrinks, and
replays identically across the four required Shen runtimes. This
implements the M1 exit criterion in `SPEC.md` §24 plus the ADR 0004
deliverables (component interface, NetKAT fragment, NetworkPolicy
compiler, gated Prolog layer, grammar-based generation).

## Non-goals

- Any Firecracker, guest, TAP, or UAP-transport work (M2/M3).
- Whole-system determinism claims. M1 produces certificates for *modeled*
  runs only, and the certificate must say so.
- Full NetKAT (`dup`/histories), symbolic model checking, abstraction, or
  probabilistic extensions (ADR 0004 deferrals).
- CNI fidelity validation of compiled NetworkPolicy semantics. The
  compiler itself is in scope (Wave C2); checking its output against a
  live enforcement path requires the M4 k3s environment.

## Ordering constraints

Waves A–C are sequential foundations. C2 depends on C only. D and E
depend on C. F depends on D and E. G runs in parallel from the start (it
gates a surface, not the milestone). H depends on F. Integration (I)
closes the milestone and depends on C2.

Every wave lands with: unit tests in the owning module's test root, any
cross-port case wired into `bifrost.suite.json` with pinned digests,
`make quality` and the four-port `make conformance` gate green, and
adversarial coverage extended under `shen/tests/adversarial/` where the
wave adds a fail-closed surface. Path ownership follows
`docs/module-boundaries.md`; new files stay inside the module roots named
below.

## Wave A: modeled-component transition interface

Deliverables:

- `shen/world/component.shen`: the `component-step` contract of ADR 0004
  Decision 1 — canonical `[step State' Facts Choices]` results, canonical
  error returns, validation of component outputs (no time, no IDs, no
  out-of-band randomness, no direct events).
- Reducer dispatch extension in `shen/world/world.shen` routing events to
  registered components and folding facts/choices into the existing
  reduction result, preserving current golden traces for existing cases.
- Fixture components under `shen/tests/world/`: a well-behaved counter
  component and misbehaving variants (emits an event directly, invents an
  ID, returns non-canonical state, claims a time advance).

Acceptance:

- Misbehaving components produce fail-closed run errors on all four ports.
- Existing `world-reducer` golden digest changes only if the trace format
  legitimately extends; any change is re-pinned deliberately in the same
  change with the reason recorded in the commit.

## Wave B: scenario DSL

Deliverables:

- `shen/scenario/scenario.shen`: canonical scenario representation and
  strict validation for the M1 subset of `SPEC.md` §18 declarations —
  seed, determinism profile (modeled-only), abstract topology, component
  roster, fault domains, search budget, observation points, properties,
  header vocabulary for the NetKAT fragment.
- Canonical parse/reject fixtures under `protocol/fixtures/v1/scenario/`
  with a `SHA256SUMS` manifest, mirroring the canonical-values fixture
  discipline (valid frames, plus invalids: unknown keys, unordered
  records, non-integer values, missing vocabulary).
- Bifrost case `scenario-parse` (marker + golden digest).

Acceptance: byte-identical accept/reject behavior across ports; every
invalid fixture rejects before any world effect.

## Wave C: abstract network, timer, and fault models

Deliverables:

- `shen/world/netkat.shen`: term validation, the pure packet-set
  denotation, and the history-free equivalence/reachability decision
  procedure over scenario-declared finite header spaces (ADR 0004
  Decision 2).
- `shen/world/models/net.shen`: the network component. Holds pending
  packets; on delivery events, emits exactly the denotation-permitted
  packets as facts; exposes delivery-order/drop/duplicate alternatives as
  choices. Never orders deliveries itself.
- `shen/world/models/timer.shen`: logical timer queue as a component
  (deadlines are software integers; firing is a world choice).
- `shen/world/models/fault.shen`: named fault states expressed as policy
  transformations (partition = policy meet with a reachability mask),
  plus crash/restart faults for modeled processes.
- Fixtures under `protocol/fixtures/v1/netkat/`: evaluation vectors,
  equivalence/reachability vectors with independent-oracle expected
  results, invalid-term rejections.
- Bifrost case `netkat-core`.
- Counterexample bridge: `shen/world/netkat-witness.shen` compiling a
  violating header assignment into a concrete schedule prefix; replay of
  the compiled schedule must exhibit the violation or the result is
  reported `unconfirmed` (ADR 0004 verification 4).

Acceptance: ADR 0004 verifications 2–4 pass on all four ports; mutation
tests flip verdicts when a policy, field, or value changes.

## Wave C2: Kubernetes NetworkPolicy compiler

Deliverables:

- `shen/world/netpol.shen`: canonical NetworkPolicy manifest
  representation, strict validation, and the compiler to a NetKAT
  connection-admission policy per ADR 0004 Decision 4 — isolation
  detection with `policyTypes` defaulting, additive allows, AND-within-
  peer / OR-across-peers combination, compile-time selector resolution
  (`matchLabels` and all four `matchExpressions` operators) against the
  scenario-declared pod/namespace universe, software-integer CIDR
  containment for `ipBlock`/`except`, `port`/`endPort` projection onto
  the declared port vocabulary, and named-port resolution against
  declared container-port maps.
- Every unsupported or unresolvable construct is a fail-closed compile
  error with a stable code: unresolvable named port, out-of-vocabulary
  port or address, `hostNetwork` pod under policy, unknown protocol,
  unmodeled field.
- `scripts/netpol-to-canonical`: offline YAML-to-canonical-frame
  converter for authoring fixtures. Development convenience only; the
  checked-in canonical frames are the semantic inputs, per the
  module-boundary rule that generated residue is never semantics.
- Fixtures under `protocol/fixtures/v1/netpol/` with a `SHA256SUMS`
  manifest: the upstream documentation examples (the `test-network-policy`
  multi-peer example, default-deny-all ingress/egress, allow-all forms,
  omitted `policyTypes`, `endPort` ranges, named ports) as canonical
  manifests with expected compiled terms and admission verdicts, plus the
  full fail-closed rejection set.
- Bifrost case `netpol-compile` (marker + golden digest).
- Compiled outputs carry the `spec-semantics-only` marker; nothing in
  this wave claims CNI fidelity.

Acceptance: ADR 0004 verification 5 passes on all four ports — compiled
terms and admission verdicts byte-identical, mutation tests flip the
affected verdict when a label, operator, CIDR, or port changes, and the
compiled policies participate in the Wave C symbolic checks and witness
bridge unchanged.

## Wave D: properties and verdicts

Deliverables:

- `shen/properties/`: deterministic evaluators for the M1 property
  classes — state invariants at observation points, temporal ordering and
  eventuality over event streams, liveness deadlines in logical time
  (`SPEC.md` §18.1). Crash and log predicates arrive with real guests
  (M3+); the representation reserves their tags now.
- Canonical verdict values integrated with the existing
  `urdr.world.verdicts` slot.
- Bifrost case `property-verdicts` with golden digests over fixture
  traces, including boundary cases (deadline exactly met, empty stream,
  vacuous temporal antecedent — each pinned explicitly).

Acceptance: verdicts byte-identical across ports; property evaluation is
a pure function of the canonical trace; no host log text is accepted as
input.

## Wave E: event log, replay, and modeled-run certificates

Deliverables:

- Event records per `SPEC.md` §20 (IDs, logical time, causal parents,
  state hashes) for abstract runs, content-addressing large payloads.
- Replay: `shen/world/replay.shen` consuming a decision transcript and
  reproducing the reduction sequence exactly; divergence between transcript
  and reduction is a fail-closed error naming the first differing event.
- Modeled-run certificate: run ID per §4, entropy-firewall counts (all
  events in an abstract run must classify as `pure` or `modeled`; anything
  else voids the certificate), property verdicts, and an explicit
  `modeled-world-only` scope marker so no whole-system profile can be
  misread from an M1 artifact.
- Bifrost case `replay-certificate`.

Acceptance: 100 consecutive replays of a fixture run produce identical
canonical roots on each port and identical digests across ports.

## Wave F: seeded exploration and shrinking

Deliverables:

- `shen/search/`: choice records per `SPEC.md` §17 (stable choice ID,
  logical time, kind, canonically ordered alternatives, selection reason,
  PRNG coordinates); a baseline seeded-random strategy and a
  boundary-biased strategy (timing edges, reorderings, retry/timeout
  edges, fault activations), both drawing only from named streams.
- `shen/shrink/`: transcript minimization over the §17.1 reduction order
  (faults, perturbations, delays, scheduling choices, scenario actions),
  accepting a candidate only when the same canonical property failure
  persists; snapshot-awareness in M1 is transcript-prefix reuse, not VM
  snapshots.
- Bifrost case `explore-shrink` over a fixture scenario with a seeded
  injected failure.

Acceptance: same seed → same exploration path and same minimized
transcript, byte-identical across ports; the minimized artifact replays
independently; shrinker mutation tests prove a non-persisting failure is
rejected.

## Wave G (parallel, gating a surface): Prolog admissibility

Deliverables:

- Spike first: `spikes/m1-prolog-portability/` running solution-order,
  backtracking, cut, and failure probes on the four pinned ports, with
  results recorded in the spike README.
- If the spike is clean: fixture suite under
  `protocol/fixtures/v1/prolog/` plus Bifrost case `prolog-semantics`
  under the strict gate, then `shen/properties/prolog.shen` exposing
  reachability and inductive-invariant queries over component transition
  relations (ADR 0004 Decision 3).
- If the spike shows divergence: record the failure, keep all
  Prolog-derived output labeled `analysis`, and implement the
  explicit-state fallback evaluator with the same query surface instead.

Acceptance: no Prolog-derived value reaches a verdict, certificate, or
golden digest unless `prolog-semantics` passes on all four ports. The M1
milestone does not block on this wave.

## Wave H: grammar-based scenario generation

Deliverables:

- `shen/search/grammar.shen`: a seeded generative grammar expanding
  scenario families (topology size, workload shape, fault schedule),
  every expansion drawn from named streams and recorded as ordinary
  transcript choices (ADR 0004 Decision 5).
- Reproducibility tests: same seed → byte-identical generated scenario on
  all ports; withheld transcript entries fail replay.

## Wave I: integration and milestone exit

Reference scenario `scenarios/abstract/partition-retry.shen` (new
`scenarios/abstract/` root): three modeled processes over a NetKAT-policied
network with a retry protocol and a seeded partition fault that violates a
liveness deadline.

Exit demonstration, all on the four required ports:

1. `explore` discovers the injected failure from a seed.
2. `shrink` removes at least one irrelevant choice; the failure persists.
3. `replay` of the minimized artifact reproduces the identical canonical
   failure and verdicts.
4. The NetKAT isolation check finds the partition-induced unreachability
   symbolically, and the compiled witness schedule reproduces it
   concretely (or reports `unconfirmed` — the demo requires the confirmed
   path).
5. A fixture NetworkPolicy set (the upstream multi-peer example plus a
   default-deny) compiles, an isolation claim over it is checked
   symbolically, and a deliberately over-permissive manifest variant
   yields a confirmed concrete admission witness for the unintended flow.
6. The modeled-run certificate shows zero non-`pure`/`modeled` events and
   carries the `modeled-world-only` scope marker; compiled-policy results
   carry `spec-semantics-only`.
7. `make quality` and `make conformance
   REQUIRED_IMPLS=shen-go,shen-lua,shen-cl,shen-rust` pass with all new
   Bifrost cases pinned.

Milestone status is then recorded in `docs/status/m1.md` following the M0
status format, including pinned commits, golden digests, and explicit
non-claims (no D0–D3 whole-system profile).

## Risks

- **Prolog port divergence** (highest likelihood): contained by Wave G's
  gate and fallback; the milestone does not depend on it.
- **NetKAT decision-procedure cost in portable Shen**: contained by
  scenario-declared finite header vocabularies and fixture-sized policies;
  optimization is deferred and may never change semantics.
- **Golden-trace churn** as the reducer trace format extends (Waves A, D,
  E): every re-pin is deliberate, reviewed, and explained in the change
  that makes it; the adversarial gate-mutation tests must keep failing on
  unexplained digest changes.
- **Upstream spec drift**: the NetworkPolicy compiler pins
  `networking.k8s.io/v1` semantics as of the referenced documentation; a
  future upstream change requires a deliberate fixture re-pin, and the
  `spec-semantics-only` marker keeps M1 claims honest until the M4 CNI
  fidelity gate exists.
- **Scope pull toward M2**: nothing in M1 may touch UAP transports,
  Firecracker, or guest paths; the module-boundary check
  (`scripts/check-owned-paths`) enforces the allowlist per wave.
