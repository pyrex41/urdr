# ADR 0007: Scenario execution, pinned decisions, and fact routing

Status: Accepted for M1.5

Date: 2026-07-30

Supersedes: None

Superseded by: None

Relates to: `SPEC.md` §17, §18, §19, ADR 0004 Decisions 1 and 5,
`docs/reviews/2026-07-29-deep-dive-persona-review.md` §6 findings 1-5,
and architectural invariants 1, 2, 3, and 7

## Context

M1 delivered every layer of the modeled laboratory — scenario DSL, component
contract, models, properties, search, shrink, replay, certificates — but no
production code composes them. Concretely, at the M1 exit state:

1. A validated scenario's `seed`, `budget`, `observations`, and `properties`
   fields are consumed by no production module. `urdr.search.explore` takes
   its own host-integer budget; properties are hand-loaded by tests.
2. `urdr.model.registry.from-scenario` threads one handler and one initial
   state through every `process` component, dispatches kinds through a
   hardcoded conditional, drops the roster's node binding, and has zero
   production callers. A component cannot learn its own identity from the
   event record the reducer hands it.
3. `models/fault.shen` documents that the kernel routes `crash`/`restart`
   facts to the named process as ordinary component inputs. No such code
   exists; tests hand-schedule the fault model's mask facts into the net
   component per activation.
4. `urdr.search.explore` walks a static, caller-supplied menu list, while a
   real run's choices are published dynamically by components during
   reduction. The transcript records choice menus but not the selected
   alternative; replay re-draws from the PRNG.
5. Consequently, no path exists in which a seeded search discovers a real
   property violation. The integration demonstration substitutes a synthetic
   marker oracle over a no-op component.

This ADR fixes the authority questions those gaps raise. It deliberately
changes no canonical value semantics, no PRNG semantics, and no property
semantics.

## Decision

### D1: One driver owns scenario execution

`urdr.run` (module root `shen/run/`) is the single production path from a
validated scenario to a certified result:

```text
urdr.run : scenario-value -> model-table -> run-options
         -> [ok RESULT] | [error CODE DETAIL]
```

The driver, in order: validates the scenario (existing `urdr.scenario`
surface, unchanged); builds the component registry from the roster and the
model table (D3); loads the declared properties (existing `urdr.properties`
surface, unchanged) and rejects before any world effect if any declaration is
unloadable; explores under the declared seed and budget (D2, D5); evaluates
properties over the recorded fact trace at the declared observation points;
and emits the modeled-run certificate with the existing
`urdr.certificate.build` machinery. Scenario declarations become the only
source of run policy: a caller cannot pass a seed or budget that bypasses the
scenario's declared values.

The driver adds no new semantic authority. It composes authorities that
already exist, and every intermediate artifact (transcript, trace, verdicts,
certificate) remains a canonical value produced by the module that owns it.

### D2: Exploration is a step loop over published choices, and selections
are pinned

`explore` is restructured from a static menu walk into a step loop:

1. Reduce until the world publishes pending choices or reaches quiescence.
2. Present the accumulated choice menus to the strategy; the strategy
   selects one alternative of one menu.
3. Record the decision as a transcript entry carrying the menu, the
   **selected alternative**, and the PRNG coordinates that produced the
   selection.
4. Schedule the selection and continue.

Replay consumes the recorded selection and verifies it is a member of the
re-derived menu; it does not re-draw. A recorded selection absent from the
re-derived menu is a divergence, reported with the existing replay taxonomy
(a new stable code in the `replay-` family). This decouples minimized
artifacts from strategy internals — a transcript survives a strategy change —
and gives the shrinker selection-level moves in addition to deletion.

Rationale for pinning: SPEC §17 already requires the choice record to carry
the selected alternative; M1 recorded it in the event log but not in the
replayable transcript, making the PRNG the de facto authority on replay.
The decision transcript, not the PRNG, is the authority invariant 2 names.

### D3: The registry is data; components have identity

- Kind dispatch is an association table `kind -> entry-builder`, not a
  conditional. Built-in kinds (`net`, `timer`, `fault`) populate the default
  table; the driver's model table may extend it.
- The scenario roster binds an optional `model` symbol per `process`
  component; a `model` binding on any other kind is rejected at scenario
  validation (the registry dispatches on the presence of a model before
  the kind, so validation is the only door that keeps a bound non-process
  entry from silently building as that model's process). The model table
  maps model symbols to `(handler, init-builder)` pairs. Two `process`
  components may therefore run different models, or the same model with
  different initial state. A roster entry without a `model` binding
  defaults to its kind's entry-builder, preserving existing scenarios.
- The event record handed to a component gains a `self` key carrying the
  component's declared id and node. `self` joins the reserved-authority
  list: a component may read its identity but never emit it as a claimed
  key. Init-builders receive the full roster record plus the scenario
  baseline, so per-component initial state is expressible.
- Model symbols are canonical values and therefore hashable. Snapshots and
  certificates may bind them (see ADR 0008, planned, for the certificate
  fields).

### D4: Fact routing is kernel-owned, declared, synchronous, and budgeted

A scenario may declare routes:

```text
[route FACT-NAME FROM-COMPONENT TARGET]
TARGET ::= component id | [node NODE-ID]
```

After a component step commits, the kernel matches the step's newly emitted
facts against the declared routes in declaration order and enqueues each
match as an ordinary `component` input to the target at the **current
logical time**, with fresh event ids, ordered by (route declaration order,
fact emission order). Facts matching no route remain observations, exactly
as today.

Authority rules:

1. Only the kernel turns a fact into an input, and only under a declared
   route. Components still cannot address each other.
2. Routed delivery is synchronous and deterministic; it introduces no new
   choice. Anything that should be asynchronous or reorderable is modeled
   through the net component, whose delivery order is already a world
   choice. The router is deliberately not a scheduler.
3. Cascades (routed input emits facts that route again) are bounded by the
   scenario budget's `max-steps`; exceeding the bound fails closed with
   `route-cascade-exceeded`.
4. A route naming an unknown component, unknown node, or reserved fact name
   is rejected at scenario validation, before any world effect.

This makes the fault model's documented `crash`/`restart` delivery real and
deletes the per-activation hand-plumbing from tests.

### D5: Declared budgets are enforced

`budget` fields bind as follows: `max-runs` bounds explore attempts;
`max-steps` bounds reductions per attempt and router cascade depth;
`max-events` bounds total event-id allocation per attempt. Each is checked
in the step loop and fails closed with a stable code naming the exhausted
budget. A scenario budget can no longer be validated and then ignored.

## Alternatives considered

### The router as a component

Rejected: routing requires observing all components' facts and scheduling
inputs — exactly the authorities the component contract structurally denies.
Granting them to a privileged component would hollow out the
reserved-authority scan that makes the contract enforceable.

### Sorting instead of rejecting unordered alternatives; PRNG-replay of
selections

Both rejected for the same reason: silent repair and derived-on-replay
values make the transcript a witness of less than the run. The component
door already rejects unordered alternatives rather than sorting; the
schedule door now matches it, and the transcript records what was decided
rather than trusting the PRNG to re-decide identically.

### Asynchronous routed delivery (router emits world choices)

Deferred, not rejected. It would make the router a second scheduler with
its own choice vocabulary before any scenario needs it. The net component
already models asynchronous delivery; a scenario that needs reorderable
fault delivery can route through a net-like component. Revisit with
evidence.

## Consequences

- The scenario becomes the program: declaration and execution are joined by
  one driver, and the M1 exit demonstration can be earned end-to-end
  (explore discovers a real property violation; shrink minimizes under the
  failure-signature gate; replay reproduces; the certificate commits).
- Transcript format changes (pinned selections) and event-record shape
  changes (`self`) re-pin the world, search, replay, and integration
  goldens. Each re-pin is deliberate and recorded with its change.
- The step loop makes explore's cost proportional to reductions rather than
  static menus; the divmod and small-of fixes (committed ahead of this ADR)
  keep that affordable on double-backed ports.
- `from-scenario` acquires production callers, and its silent-drop catch-alls
  become fail-closed as part of the same change.
- Replay of pre-existing recorded transcripts (menu-only, no selection) is
  not preserved; M1 shipped no persisted artifacts outside the test suites,
  which are re-pinned in the same changes.

## Required verification

1. A scenario whose budget, seed, or properties are removed or malformed is
   rejected by the driver before any reduction, with a stable code.
2. The partition-retry reference scenario, driven end-to-end by `urdr.run`
   with real retrying-client/acking-server models, fails its liveness
   property under a discovered schedule; shrink removes at least one
   irrelevant entry with the same failure signature; replay of the
   minimized artifact reproduces the verdicts; the certificate's verdicts
   come from `urdr.properties.check`, not fixtures.
   **Met.** `urdr.run.execute` on the partition-retry scenario discovers
   the liveness failure at attempt 2 (attempts 0-1 legitimately pass);
   shrink minimizes 28 entries to 5 under an EVAL that re-drives the
   world and re-evaluates properties; replay verifies the minimized
   artifact and reproduces the verdicts; the v2 certificate reports FAIL
   with verdicts from `urdr.properties.check`. The discovered failure is
   a real race — an early partition selection delivered while the first
   reply is in flight — not a planted marker. Two carriers remain
   unclaimed and are recorded in `docs/status/m1-5.md`: the built-in
   net/timer/fault models are not yet resolvable under the driver (the
   built-in fault republishes its menu every step, so a driver run would
   never quiesce), and liveness failures are the no-witness form until
   timer integration allows time-advancing schedules.
3. Two `process` components in one scenario run distinct models with
   distinct initial states; each observes its own id and node under the
   `self` key; a component claiming `self` in its output is rejected.
4. A routed fact reaches exactly its declared target at the current time in
   declaration order; an unrouted fact reaches no component; a cascade
   exceeding `max-steps` fails closed with `route-cascade-exceeded`; a
   route naming an unknown target is rejected at validation.
5. Replay verifies recorded selections by menu membership; a transcript
   whose selection is not in the re-derived menu reports the new stable
   divergence code; strategy-independence is demonstrated by replaying a
   `boundary`-discovered transcript with the `baseline` strategy configured.
   **Deferred at acceptance:** the strategy-independence demonstration.
   Membership verification and the divergence code
   (`replay-selection-divergence`) are met, but `urdr.run.execute-with` —
   the door that exposes the `baseline` strategy — still has no caller
   that configures `baseline`, so no run demonstrates that a
   `boundary`-discovered transcript replays unchanged under a different
   strategy. Item 2's shrink and replay integration, which this note
   previously named as the owing wave, has since landed without
   supplying it; the demonstration is a standalone debt, owed by
   whichever wave next touches strategy selection.
6. All changed suites pass `make conformance` on the available lane with
   re-pinned digests recorded in the same change, and `make quality` stays
   green.
