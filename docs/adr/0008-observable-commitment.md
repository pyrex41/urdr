# ADR 0008: Snapshots and certificates commit to observable output and model identity

Status: Accepted for M1.5

Date: 2026-07-30

Supersedes: None

Superseded by: None

Relates to: `SPEC.md` §4 and §4.1 (observable equivalence), §7.1, §20 and
§21; `docs/adr/0002-canonical-values-and-uap-framing.md`;
`docs/adr/0004-m1-abstract-world-algebraic-layers.md` Decision 1;
`docs/adr/0007-scenario-execution-and-fact-routing.md` D3 (which planned
this ADR); `docs/reviews/2026-07-29-deep-dive-persona-review.md` consensus
finding #4

## Context

The world snapshot (`urdr.world.snapshot-value`) is the value every state
hash in the evidence chain is computed over: the event log's `input-state`
and `output-state` fields, the recorded artifact's state root, and — through
field 3 of the run-id preimage — run identity itself. The deep-dive review's
consensus finding #4 identified two honesty gaps in what that value
committed to, both verified against the tree at the reviewed commit:

1. **Emitted facts were bound by COUNT only.** The snapshot carried
   `fact-count`, the length of the facts list. Two runs whose components
   emitted *different* facts from *identical* states — different names,
   different values, same number — produced byte-identical snapshots, so
   identical state roots, and (all else equal) identical certificates.
   Facts are the primary observable output of a modeled run: they are what
   properties evaluate over (`urdr.properties.trace-of-world`) and what
   SPEC.md §4.1's observable-equivalence classes are made of. A certified
   run therefore did not commit to its own observable output.

2. **Model identity was invisible.** ADR 0007 D3 gave every registry entry
   a validated META record binding the component's declared `model` and
   `node`, and deliberately deferred binding it into snapshots and
   certificates to this ADR (the deferral was recorded in a comment at
   `urdr.world.component-values`). Until now the snapshot bound each
   component's name and state digest only, so two registries differing
   only in *which model* ran a component were indistinguishable in every
   artifact — a certificate could not honestly answer "which model
   produced this evidence".

Fixed constraints: canonical values with strictly ascending record keys
(ADR 0002); the tagged-root discipline of `eventlog.shen` §4
(`root(TAG, [D0 ... Dn]) = SHA-256(TAG ++ D0 ++ ... ++ Dn)` over
fixed-width 32-octet digests); the m1-large canonical profile already used
by the component door and the snapshot's per-component state digests;
fail-closed behavior for anything unencodable; and the SPEC.md §4 run-id
definition, whose preimage is fixed in `certificate.shen` §1.

## Decision

### D1: The snapshot binds a facts root, not a fact count

`urdr.world.snapshot-value` replaces the `fact-count` binding with
`facts-root`: a tagged SHA-256 root over the ordered per-fact digests,

```text
facts-root = SHA-256("urdr-facts-root-v1" ++ D0 ++ ... ++ Dn)
Di         = SHA-256(m1-large canonical payload of fact record i)
```

- The domain tag `urdr-facts-root-v1` follows the eventlog root
  discipline: a facts root can never equal an event root or transcript
  root over the same digests. Every `Di` is exactly 32 octets, so the
  root is sensitive to order, insertion, truncation, and content.
- **Digest profile:** each fact record is encoded under the **m1-large**
  profile — the profile the component door proved the embedded event
  value canonical under (`urdr.component.canonical?`) and the profile the
  snapshot's state digests already use. Facts embed component-emitted
  values; the default m0 profile could refuse a large-but-legal fact,
  which would make snapshot construction fail on a run the reducer
  legally executed. (The eventlog digests *event payloads* under m0 and
  content-addresses what exceeds it; a snapshot has no content-address
  escape hatch, so the wider profile is the correct one here.)
- A fact that fails to encode yields the fail-closed marker
  `[symbol invalid-facts]` in place of the root — mirroring the existing
  `invalid-state` marker — never a skipped fact and never a partial root.
- The count is **not** kept beside the root. No consumer in the tree
  reads `fact-count`, the root distinguishes every length by
  construction, and a second binding would be a second, unvalidated copy
  of the same commitment. The snapshot's record keys remain strictly
  ascending: `components < facts-root < next-event-id`.

### D2: The snapshot binds each component's META; the certificate carries a `models` field

- `urdr.world.component-value` becomes
  `{meta: META, name, state-digest}` (keys ascending
  `meta < name < state-digest`), with META — the validated
  `{model, node}` record of ADR 0007 D3 — embedded verbatim. It is a
  two-field record validated at registration, so a digest would cost
  more octets than the value while hiding the binding from a snapshot
  diff (the same reasoning the routing slot records).
- `urdr.certificate.value` gains a `models` key: the model bindings of
  the **initial** world's registry, one
  `{component: [symbol ID], model: [symbol ...] | [null], node: [symbol ...] | [null]}`
  record per registered component, in registry order — the registry
  ascends strictly by component name, so the list is sorted ascending by
  component with no re-sort and no host iteration order in reach. The
  initial registry is the right authority: bindings never change during
  a run (`urdr.world.component-put` preserves META), and the initial
  world is what the run id's field 3 hashes.
- `models` slots between `markers` and `replay`; the full 18-key
  ordering was checked pairwise in unsigned ASCII
  (`markers < models` at octet 2, `109 = models < replay = 114` at
  octet 1), so the certificate remains canonical by construction.
- **Schema version bump:** the certificate `version` value moves from
  `urdr-certificate-v1` to `urdr-certificate-v2`. An 18-key certificate
  is a schema change; a v1 reader must fail on it rather than silently
  ignore a key it does not know.

### D3: Model identity enters run identity transitively — no new preimage field

The SPEC.md §4 run-id preimage is unchanged. Field 3 of the preimage is
the SHA-256 of the canonical payload of the **initial world snapshot
value** (verified: `urdr.certificate.run-id-initial` calls
`urdr.eventlog.state-digest Initial`, which hashes
`urdr.world.snapshot-value`). After D2 the snapshot commits to every
registry entry's META, so two runs differing only in a model binding
already have different run ids transitively. A dedicated preimage field
would be a second, unvalidated copy of the same fact — the exact
redundancy the certificate module's §1 forbids for the per-record run id,
and the mirror of the existing baseline-descriptor reasoning (§2): what
the initial snapshot already commits to is not hashed twice.

### Failure behavior

All existing fail-closed behavior is preserved: an unencodable component
state still yields `invalid-state`, an unencodable fact yields
`invalid-facts`, a snapshot that does not encode is still the eventlog's
`eventlog-state-encode` error, and a malformed registry still fails world
validation before any certificate is assembled.

## Alternatives considered

### Keep the count beside the root (`fact-count` + `facts-root`)

Rejected. No consumer reads the count, the root is length-sensitive by
construction (truncation changes the preimage), and carrying both invites
the classic divergence bug where a reader trusts the cheap copy. Had a
consumer needed the count cheaply it could have been retained; a survey of
the tree found none.

### Digest facts under the default m0 profile, content-addressing overflow

Rejected. That is the eventlog's rule for *payload slots*, where a record
can carry a content address instead. A snapshot binding has no
content-address form, so an m0 refusal of a large-but-legal fact would
make snapshot construction fail on a run the reducer legally executed.
Using the same m1-large profile as the component door and the state
digests means "legal to emit" implies "digestible here".

### Embed the facts list whole in the snapshot

Rejected. Facts grow linearly with the run; the snapshot is hashed once
per event by the eventlog, and an embedded list would blow the canonical
frame budget exactly the way the per-component state digests were
introduced to avoid. The routing slot is embedded whole because it is
declaration-sized; facts are run-sized.

### A new run-id preimage field for model bindings

Rejected (D3). Field 3 already covers the bindings transitively once the
snapshot binds META. A new field would change every existing run id for
runs whose model bindings the snapshot already distinguishes, and would
duplicate a commitment inside one hash — two encodings of one fact that
can drift.

### Digest META into the snapshot instead of embedding it

Rejected. META is a fixed two-field record; a 32-octet digest plus bytes
framing costs more than the value and makes a snapshot diff opaque for no
budget gain.

## Consequences

- Every artifact that embeds a snapshot digest moves: world trace goldens,
  the models suite's scenario-registry snapshot, every eventlog state
  hash, event root, recorded artifact, run id, and certificate digest, and
  the integration demo's certificate run-id line. Search and grammar
  goldens do not move: their pinned digests are transcript roots and
  choice-path digests, which commit to reducer inputs, not snapshots.
- The certificate schema is v2; v1 certificates remain readable as
  historical artifacts but are no longer produced. Nothing in the tree
  parses certificates by key count, so the only in-tree migration is
  golden re-pinning.
- Two runs whose components emit different facts from identical states now
  have different state roots at the first diverging event — divergence
  detection localizes fact divergence, not just state divergence.
- Cost: one additional SHA-256 per emitted fact per snapshot hash. Facts
  lists in M1 suites are short (≤ a handful per fixture); the 100-replay
  loop budget was re-measured green on shen-go.
- Deferred: surfacing the facts root in the CLI-grade certificate summary,
  and binding ACHIEVED model versions (as opposed to declared model
  names) — M2 material, when models gain versioned identities.

## Required verification

All executable, all in-tree, all four-port (run at least on `shen-go` for
this wave's evidence; the conformance gate runs the full pinned matrix):

- **World suite** (`shen/tests/world/run-tests.shen`):
  - `uwt.facts-divergence?` — two runs with byte-identical component
    states but different emitted facts produce different snapshot frames
    (the review's exact scenario, previously a silent collision), while
    their component states compare equal.
  - `uwt.meta-visible?` — the snapshot's components binding carries the
    entry's META verbatim: `{meta {model, node}, name, state-digest}`.
  - The pinned `WORLD-TRACE` / `WORLD-COMPONENT-TRACE` goldens embed the
    new snapshot shape (facts root and meta keys visible in the hex).
- **Replay/certificate suite** (`shen/tests/replay/run-tests.shen`):
  - `CERT|models|...` — a built certificate's `models` field equals the
    expected sorted binding list, pinned canonically in the golden.
  - `MUT|model-binding|BEFORE|AFTER` — two initial worlds differing ONLY
    in one registry entry's META model produce different run ids, with
    no change to the preimage schema: the transitivity argument of D3,
    executed.
  - All six existing `MUT|*` preimage mutation cases still flip.
  - `CERTF|minimal` pins the full v2 certificate payload, `models` key
    and `urdr-certificate-v2` version included.
- **Run suite** (`shen/tests/run/run-tests.shen`): `RUN|models|...` — the
  production driver's discovery certificate carries the scenario's
  declared bindings (`client:pinger@a,server:acker@b`), checked, not
  merely printed.
- **Acceptance:** `make quality` green; `make conformance
  REQUIRED_IMPLS=shen-go` ends `status PASS 13/13` with the re-pinned
  goldens and program digests in both `bifrost.suite.json` and
  `scripts/bifrost-gate`; every suite prints `ALL PASS` when run
  directly.

## References

- `shen/world/world.shen` — `urdr.world.facts-root-value`,
  `urdr.world.component-value`, `urdr.world.snapshot-value`
- `shen/world/certificate.shen` — §1 (preimage note), §5 (v2 schema),
  `urdr.certificate.models-value`
- `shen/world/eventlog.shen` §4 — the tagged-root discipline reused here
- `docs/reviews/2026-07-29-deep-dive-persona-review.md` §6, consensus
  finding #4
- `docs/adr/0007-scenario-execution-and-fact-routing.md` D3 — the
  recorded deferral this ADR discharges
