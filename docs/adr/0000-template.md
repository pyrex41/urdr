# ADR NNNN: Short decision title

Status: Proposed

Date: YYYY-MM-DD

Supersedes: None

Superseded by: None

Relates to: `SPEC.md` sections and prior ADRs

## Context

Describe the problem, fixed constraints, evidence, and the determinism profiles
affected. Separate verified facts from assumptions. State how `SPEC.md` §27 and
existing accepted ADRs constrain the decision.

## Decision

State the normative decision precisely. Define canonical bytes, limits, failure
behavior, ownership, and compatibility rules where applicable. Name immutable
versions or digests rather than mutable labels.

Unsupported, missing, ambiguous, or uncontrolled behavior must have an explicit
fail-closed outcome. Do not claim a stronger determinism profile than automated
evidence demonstrates.

## Alternatives considered

### Alternative A

Describe the alternative and the concrete reason it was not selected.

### Alternative B

Describe the alternative and the concrete reason it was not selected.

## Consequences

List positive consequences, costs, compatibility limits, migration work, and
risks. Identify decisions deferred to later milestones.

## Required verification

List executable positive, negative, cross-runtime, and mutation tests. Define
the evidence artifact and exact acceptance criteria. Unavailable infrastructure
is a blocked or failing gate, never a passing skip.

## References

Link immutable source revisions, standards, measurements, and relevant
repository paths. Moving upstream documentation may provide context but is not
certification evidence.
