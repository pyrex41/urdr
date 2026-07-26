# ADR 0005: Per-surface canonical frame profiles for M1

Status: Proposed

Date: 2026-07-25

Supersedes: None

Superseded by: None

Relates to: ADR 0002 (canonical values and framing), ADR 0004, `SPEC.md`
§7.1, §18, and `docs/plans/m1-abstract-world.md` Waves B, C2, and I

## Context

ADR 0002 fixed one canonical resource profile for M0: 4,096 payload
octets, 256 parsed nodes, depth 32. Wave B (PR #13) delivered the
`scenario/v1` frame as a single canonical value under that profile and
measured the consequence: a modest fully-populated scenario fixture
consumes 245 of 256 nodes, and the Wave I reference scenario
(`partition-retry`: three processes, policies, faults, properties) cannot
fit. The NetworkPolicy compiler (Wave C2) faces the same ceiling for
compiled-term and manifest fixtures: the merged NetKAT core permits terms
up to 1,024 nodes, but a 256-node frame cannot carry them.

Oversize input currently fails closed with stable ADR 0002 codes
(`nodes-too-many`, `frame-too-large`, `depth-too-large`). That is correct
behavior and must not change. The problem is capacity, not enforcement.

A global limit increase was considered and rejected: the M0 boundary
fixtures (for example `canonical/invalid/nodes-too-large.frame` class)
pin the M0 limits byte-for-byte, and flipping their verdicts would
invalidate certified M0 evidence and force a cascade of golden re-pins
across all three accepted cases.

## Decision

`urdr.canonical` gains explicit, named resource profiles. A profile is a
canonical record of limits; every parse/encode entry point is
parameterized by exactly one profile. There is no ambient or default
mutable profile state.

Defined profiles:

- `canonical-profile/m0`: 4,096 payload octets, 256 nodes, depth 32 —
  byte-for-byte the ADR 0002 limits. All existing public entry points
  keep this profile so that every M0 fixture, digest, and UAP boundary is
  unchanged.
- `canonical-profile/m1-large`: 65,536 payload octets, 8,192 nodes,
  depth 64. Atom, symbol, and integer-digit limits are unchanged from
  ADR 0002.

Surface assignments (each surface names its profile statically in code
and in its fixture documentation; profiles are never selected by input
content):

- `scenario/v1` frames: `canonical-profile/m1-large`.
- NetworkPolicy manifest and compiled-term fixture frames (Wave C2):
  `canonical-profile/m1-large`.
- UAP v1, the M0 conformance cases, and every other existing surface:
  `canonical-profile/m0`, unchanged.
- Future surfaces must declare a profile in their owning ADR or plan
  wave; an undeclared surface defaults to `canonical-profile/m0`.

Enforcement remains fail-closed with the existing stable error codes; the
codes are unchanged, only the bound values differ per profile. A frame
valid under `m1-large` but presented to an `m0` surface is rejected
exactly as today.

## Alternatives considered

### Globally raising the ADR 0002 limits

Rejected: flips the verdicts of pinned M0 boundary fixtures, invalidating
existing four-port evidence and forcing golden re-pins in all accepted
cases for a change that only new surfaces need.

### Segmented or content-addressed scenario representation

Splitting scenarios across multiple frames linked by hashes was rejected
for M1: it introduces a second composition layer (partial-frame validity,
cross-frame ordering, hash indirection) into the scenario boundary that
every port must reimplement identically, for less capacity benefit than a
profile. It remains open for genuinely large artifacts (transcripts,
event logs) in later milestones.

### Unbounded or host-dependent limits

Rejected outright: bounded, reviewed limits are what make oversize a
deterministic rejection rather than a per-port resource failure.

## Consequences

- Wave I is unblocked; agent 20's reference scenario has ~32x node
  headroom.
- The canonical codec's internal budget threading changes on a
  semantics-bearing M0 module (`shen/protocol/canonical.shen`). The M0
  cases must still pass byte-identically on all four ports after the
  refactor — this is the primary regression risk and the reason the
  change ships with the full M0 suite re-run, not just new fixtures.
- Scenario fixtures merged in PR #13 remain valid; Wave B's suite gains
  boundary fixtures at the new limits.
- Larger frames imply larger parse costs on slow ports; 65,536 octets is
  still small in absolute terms.

## Required verification

1. All existing M0 canonical, PRNG, world, scenario, and NetKAT suites
   pass byte-identically on all four ports with zero fixture or golden
   changes (proving the refactor is behavior-preserving on `m0`
   surfaces).
2. New boundary fixtures for `m1-large`: accepted frames at exactly
   65,536 payload octets, 8,192 nodes, depth 64; rejected frames one unit
   over each bound, with the existing stable codes — byte-identical
   across the four ports.
3. Mutation check: presenting an `m1-large`-sized frame to an `m0`
   surface still rejects.
4. `make quality` and the adversarial harness pass unchanged.

## References

- ADR 0002, ADR 0004
- PR #13 (Wave B) — the 245/256-node measurement and the escalation
- `shen/world/netkat.shen` term-node budget (PR #11)
