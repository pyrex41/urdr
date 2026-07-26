# ADR 0004: M1 abstract world — transition interface, NetKAT fragment, and Prolog invariant layer

Status: Proposed

Date: 2026-07-25

Supersedes: None

Superseded by: None

Relates to: `SPEC.md` §4, §7, §12, §17, §18, §24 M1, architectural
invariants 1, 2, 3, 7, 8, and 9, ADR 0002, ADR 0003, and
`docs/module-boundaries.md`

## Context

M0 delivered the semantic nucleus: canonical values (ADR 0002), portable
integers and named PRNG streams (ADR 0003), and a pure world reducer proven
byte-identical on four Shen ports. M1 must deliver the abstract world:
scenario DSL, packet/timer/fault models without VMs, state and temporal
properties, event log, replay, certificates, seeded exploration, and basic
shrinking (`SPEC.md` §24 M1).

Design review raised four additions beyond the literal M1 list:

1. Making the reducer's implicit transition-system contract an explicit,
   named interface so modeled components (network, timer, fault, and later
   L7 service models) plug in uniformly.
2. Expressing the abstract network model's policy semantics as a
   history-free NetKAT fragment, giving a symbolic view of reachability and
   isolation over the same object the simulator executes, with symbolic
   counterexamples compiled into concrete replayable schedules.
3. Using Shen's integrated Prolog for invariant queries (reachability,
   inductive-invariant checking, counterexample search) over abstract
   models.
4. Compiling Kubernetes NetworkPolicy manifests to the NetKAT fragment in
   M1 rather than M4. The resource's semantics are fixed by the published
   `networking.k8s.io/v1` specification, so the compiler and its symbolic
   checks need no running cluster; only fidelity to a live CNI
   enforcement path does.

An earlier design discussion proposed external TLA+ tooling as the
design-level oracle and L-system rewriting as a generative layer. Neither is
adopted; the rejections are recorded below.

Fixed constraints: the world kernel portability contract (`SPEC.md` §7.1)
bans floating point, map iteration order, host time, and host randomness
from semantics; Bifrost agreement across required ports is the language
oracle (§7.2); no certified run may consume an unrecorded external
observation (§27 invariant 4); adapters and models execute policy but never
invent it (§27 invariant 3). All M1 semantics run on the M0 canonical-value
and software-integer substrate. Cross-port behavior of Shen's Prolog
(solution order, backtracking, cut) is an assumption until fixtures prove
it; it is treated as unverified below.

## Decision

### 1. Modeled-component transition interface

Every M1 modeled component is a pure Shen transition system with the fixed
contract:

```text
component-step : component-state -> event -> [step component-state' facts choices]
```

- `component-state`, `event`, `facts`, and `choices` are canonical values
  per ADR 0002.
- Only `urdr.world.reduce` (via its dispatch table) invokes
  `component-step`. Components never advance logical time, allocate event or
  choice IDs, draw randomness except through named-stream coordinates passed
  in the event, or emit events directly. Facts become world state only when
  the reducer consumes them.
- `choices` expose legal alternatives to the search engine in canonical
  order; the component never selects among them.
- A component step that cannot interpret its input returns a canonical
  error; the reducer converts it to a fail-closed run error. Silent
  self-repair is forbidden.

This names the contract the M0 reducer already implies and makes it the
single extension point for the M1 network, timer, and fault models and for
later delegated L7 models (`SPEC.md` §12.2).

### 2. History-free NetKAT fragment as the network policy algebra

The abstract network model's policy semantics are defined by a NetKAT
fragment with canonical term syntax:

```text
policy ::= [nk-drop] | [nk-id]
         | [nk-test  FIELD VALUE]
         | [nk-set   FIELD VALUE]
         | [nk-union POLICY POLICY]
         | [nk-seq   POLICY POLICY]
         | [nk-star  POLICY]
         | [nk-neg   PREDICATE]
```

- Fields are canonical symbols from a scenario-declared finite header
  vocabulary; values are software integers (ADR 0003). No floating point,
  no host-dependent representations.
- `dup` and packet-history observation are excluded. The fragment is the
  decidable history-free subset; equivalence and reachability are decided
  over the scenario's declared finite header space.
- Semantics are a pure function from a canonical packet record to a
  canonically ordered set of packet records. The abstract network component
  (Decision 1) must deliver exactly the packets this denotation permits;
  delivery order and timing remain world-kernel choices (`SPEC.md` §12.1).
- Partitions and reachability faults are expressed as named policy
  transformations selected by the fault model, so the symbolic and executed
  views cannot drift.
- Symbolic check results (reachability, isolation, policy equivalence) are
  certifying only when produced by the portable Shen decision procedure and
  covered by Bifrost fixtures. A symbolic counterexample is a set of header
  assignments; a compiler lowers it to a concrete scenario schedule whose
  replay must exhibit the violation, or the check result is reported as
  `unconfirmed` — never silently accepted.
- External NetKAT tools (KATch or others) may be used for development-time
  cross-checking only. Their output is never certification evidence and
  never enters a certified run.

### 3. Prolog invariant layer, gated on cross-port fixtures

Shen Prolog is adopted for invariant queries over abstract models —
reachability, inductive-invariant checking, and counterexample search —
under a hard admissibility gate:

- Before any Prolog-derived result may contribute to a certificate or
  Bifrost golden output, a dedicated fixture suite must pin solution order,
  backtracking behavior, cut semantics, and failure behavior byte-identically
  across all required ports, using the same strict gate as existing cases.
- Until that suite passes, every Prolog-derived output is labeled
  `analysis` and excluded from verdicts, certificates, and golden digests.
  There is no intermediate trust level.
- If the fixture suite reveals irreconcilable port divergence, the fallback
  is a small explicit-state query evaluator in plain Shen with the same
  query surface; the Prolog surface is then dropped rather than trusted
  partially.
- Prolog queries are pure with respect to world semantics: they read
  canonical model terms and produce canonical results. They never mutate
  world state, draw randomness, or advance time.

**Spike outcome (2026-07-25, `spikes/m1-prolog-portability/`, merged in
PR #12):** the gate FAILED. Of 112 byte-compared probes across the four
pinned ports, 10 diverged in three independent classes (`call/1` raises on
shen-lua only; `var?/1` crashes shen-lua's engine; `shen.*prolog-memory*`
query capacity differs four ways: 1000/1000/10000/ignored). Root cause:
shen-lua ships an independent native Lua Prolog reimplementation, enabled
by default, so agreement on the remaining 102 probes is coincidental
rather than kernel-constrained. Per this decision's own terms the fallback
was taken: `shen/properties/query.shen` provides the query surface in
plain Shen (24-probe self-check byte-identical on all four ports), all
Prolog output remains `analysis`-only, and no Prolog fixture suite exists.
This finding is also new information about the language oracle itself
(SPEC §7.2): per-port native subsystem reimplementations can coincide with
kernel behavior without being constrained by it.

### 4. Kubernetes NetworkPolicy compiler in M1

A compiler from Kubernetes NetworkPolicy manifests (`networking.k8s.io/v1`,
GA) to the Decision 2 NetKAT fragment is an M1 deliverable. Real clusters
are not required: the resource's semantics are fixed by the published API
specification, and scenarios declare the finite pod, namespace, label, IP,
and port universe the compiler resolves against.

Compiled semantics target **connection admission**: a canonical connection
attempt `(src, dst, protocol, dst-port)` is admitted iff the source's
egress side and the destination's ingress side both allow it. Stateful
reply traffic, which the API allows implicitly for admitted connections,
is out of the compiled object's scope and is stated as such; the compiler
models admission, not per-packet connection tracking.

Normative encoding rules, per the pinned specification:

- A pod is isolated for a direction iff at least one policy selects it and
  that policy's effective `policyTypes` includes the direction. An omitted
  `policyTypes` defaults to `Ingress`, plus `Egress` iff the policy has an
  egress section. Unselected directions compile to `nk-id` (allow-all).
- Allows are additive across selecting policies; rule order never matters.
- Within one peer element, `namespaceSelector` and `podSelector` conjoin;
  across elements of a `from`/`to` array, peers union. An empty or omitted
  `from`/`to` allows all peers for that rule; an empty `podSelector`
  selects every pod in the namespace.
- Selectors (`matchLabels` and the `In`, `NotIn`, `Exists`, `DoesNotExist`
  operators of `matchExpressions`) resolve at compile time to finite
  unions over the scenario-declared pod and namespace sets.
- `ipBlock` `cidr`/`except` compiles via software-integer CIDR containment
  over scenario-declared addresses; `except` subtracts using predicate
  negation.
- An omitted `ports` list allows all declared ports for the rule;
  `port`/`endPort` ranges (GA since Kubernetes v1.25) project onto the
  scenario-declared port vocabulary; named ports resolve against declared
  pod container-port maps.
- Fail-closed compile errors, never silent narrowing: a named port that no
  declared pod defines, a port or address outside the declared vocabulary,
  a `hostNetwork` pod named by a scenario that also declares policies, an
  unknown protocol, or any manifest field the compiler does not model.

The compiled policy participates in the Decision 2 symbolic checks and
witness bridge: an isolation claim about a manifest set is either
confirmed by a concrete replayable admission witness or reported
`unconfirmed`. Fidelity of the compiled semantics to a live CNI
enforcement path is a separate claim that only M4's real k3s environment
can test; M1 certifies agreement with the written specification and its
published conformance examples, and the compiler's output must carry a
`spec-semantics-only` marker until an M4 fidelity gate exists.

### 5. Grammar-based scenario generation; L-systems rejected

Scenario-family generation (topologies, workloads, fault schedules) may be
implemented as a search-strategy module that expands a plain generative
grammar, with every expansion choice drawn from named PRNG streams and
recorded in the decision transcript like any other choice (`SPEC.md` §17).
The same seed must reproduce the same generated scenario byte-for-byte.

L-system machinery (parallel rewriting, turtle interpretation, geometric
metrics) is rejected for Urdr: it has no load-bearing role in the
determinism laboratory, and its classic outputs require floating point,
which §7.1 bans from semantics.

## Alternatives considered

### External TLA+ toolchain (TLC, Apalache) as the design oracle

Rejected as a semantic dependency. Model/implementation drift between a
TLA+ spec and the Shen world would be unverifiable by Bifrost, the tools
are unavailable inside certified replay, and `SPEC.md` §18 already commits
properties to Shen. The valuable residue — model-guided exploration and
refinement checking of concrete traces against the abstract model — is kept,
expressed entirely in Shen (see the M1 plan).

### Full NetKAT with `dup` and packet histories

Rejected for M1. History semantics multiply the state space, the decision
procedures are substantially heavier, and no M1 property requires
per-packet history observation. The term syntax reserves room for a later
versioned extension.

### External solvers inside the certified loop

Rejected. A solver invocation during a certified run would be an
uncontrolled external observation (§27 invariant 4). If a future milestone
needs one, it must go through the §13 record/replay gateway like any other
external service; for M1, external tools remain development-time aids.

### Ungated adoption of Shen Prolog

Rejected. Prolog solution order is runtime-implemented behavior that no
current fixture pins. Admitting it before cross-port proof would risk
exactly the false-determinism failure `SPEC.md` §26.7 names as the top
product risk.

### L-system generative layer

Rejected as scope creep; see Decision 5. A plain seeded grammar achieves
the useful goal (reproducible scenario families) inside existing
transcript rules.

## Consequences

- The M1 network, timer, and fault models share one reviewed extension
  point, and later delegated L7 models reuse it unchanged.
- Network policy gains a symbolic query surface over the executed object
  itself, and symbolic findings are only ever reported alongside a concrete
  replayable witness or an explicit `unconfirmed` marker.
- The NetKAT decision procedure in portable Shen will be slow on large
  header spaces; scenarios declare finite vocabularies, and performance
  work may not change semantics (native acceleration only as byte-for-byte
  verified optimization, as with ADR 0003).
- The Prolog gate may delay or remove that surface entirely; the
  explicit-state fallback bounds the loss.
- New Bifrost cases increase gate runtime on all four ports.
- The NetworkPolicy compiler binds Urdr to a pinned upstream API
  semantics; spec revisions require a fixture re-pin, and the
  `spec-semantics-only` marker prevents overreading M1 results as CNI
  fidelity before the M4 gate exists.
- Deferred: probabilistic or history NetKAT extensions, symbolic
  state-space techniques, abstraction/symmetry reduction, and CNI
  fidelity validation of compiled NetworkPolicy semantics (M4, against
  the real k3s environment).

## Required verification

1. Component-interface conformance: fixture transition systems (including
   deliberately misbehaving ones) prove that time advancement, ID
   allocation, out-of-band randomness, and direct event emission by a
   component are rejected fail-closed, on all required ports.
2. NetKAT evaluation vectors: canonical term/packet fixtures with expected
   packet-set outputs, byte-identical across ports, including invalid-term
   rejection fixtures (unknown fields, non-integer values, malformed
   arities).
3. NetKAT equivalence/reachability vectors validated against an
   independent oracle implementation, with mutation tests proving a changed
   policy, field, or value flips the verdict.
4. Counterexample bridge: every symbolic violation fixture compiles to a
   schedule whose replay reproduces the violation; a deliberately
   non-reproducing counterexample yields `unconfirmed`, never a pass.
5. NetworkPolicy compiler vectors: canonical manifest fixtures — including
   the upstream documentation examples (multi-peer AND/OR combinations,
   `ipBlock` with `except`, `port`/`endPort` ranges, named ports,
   default-deny and allow-all forms, omitted `policyTypes` defaulting) —
   with expected compiled NetKAT terms and admission verdicts,
   byte-identical across ports; every fail-closed case in Decision 4
   rejects with a stable error; mutation tests prove a changed label,
   selector operator, CIDR, or port flips the affected admission verdict.
6. Prolog gate suite: solution-order, backtracking, cut, and failure
   fixtures run under the strict four-port gate; any disagreement keeps the
   `analysis`-only label in force. The gate's own mutation tests prove one
   changed fixture or port fails the suite.
7. Grammar generation: identical seeds reproduce identical scenarios
   byte-for-byte across ports; every expansion choice appears in the
   decision transcript; a withheld transcript entry fails replay.
8. All new cases are wired into `bifrost.suite.json` with pinned program
   and fixture digests; hosted-CI unavailability is reported as blocked,
   never as passing evidence.

## References

- `SPEC.md` §4, §7, §12, §17, §18, §24
- ADR 0002, ADR 0003, `docs/module-boundaries.md`, `docs/status/m0.md`
- Anderson et al., "NetKAT: Semantic Foundations for Networks", POPL 2014:
  <https://doi.org/10.1145/2535838.2535862>
- Foster et al., "A Coalgebraic Decision Procedure for NetKAT", POPL 2015:
  <https://doi.org/10.1145/2676726.2677011>
- Kubernetes NetworkPolicy concept documentation (`networking.k8s.io/v1`):
  <https://kubernetes.io/docs/concepts/services-networking/network-policies/>
- Kubernetes NetworkPolicy API reference (`policyTypes` defaulting,
  selector semantics, `endPort` GA in v1.25):
  <https://kubernetes.io/docs/reference/kubernetes-api/policy-resources/network-policy-v1/>
- The Shen kernel's Prolog subsystem (defprolog) as distributed with the
  pinned ports recorded in `docs/status/m0.md`
- Implementation sequencing: `docs/plans/m1-abstract-world.md`
