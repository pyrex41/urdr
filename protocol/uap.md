# Urdr Adapter Protocol v1

Status: M0 production contract
Canonical values and framing: ADR 0002
Software integers and SHA semantics: ADR 0003

The Urdr Adapter Protocol (UAP) is the effect boundary between the
authoritative Shen world kernel and native adapters. Shen owns logical time,
randomness, ordering, request/session IDs, capability interpretation, profile
selection, and certification. Adapters validate and execute commands and
return facts.

## 1. Exact byte contract

UAP v1 uses only the typed canonical values accepted by ADR 0002:
`null`, `boolean`, ADR 0003 software `integer`, UTF-8 `text`, arbitrary
`bytes`, restricted-ASCII `symbol`, `list`, and ordered `record`.

Every message is one byte-counted netstring:

```text
decimal-payload-octet-count ":" canonical-RFC-9804-payload ","
```

The M0 limits are exact:

| Resource | Limit |
| --- | ---: |
| Payload | 4,096 octets |
| Atom | 256 octets |
| Nested lists | 32 |
| Parsed RFC nodes | 256 |
| Integer magnitude | 255 decimal digits |
| Symbol or record key | 64 octets |

No alternate codec, text normalization, binary frame prefix, per-connection
codec choice, float, map, host integer, or object identity is permitted.
Text is strict shortest-form UTF-8 without normalization. Record fields appear
in unsigned-ASCII key order.

Framing and canonical-value failures close the stream after one stable error.
Schema and command errors reject only that request. In-process and stream
socket dispatch both feed the same `FrameDecoder`, canonical codec, and
`Endpoint`; chunk boundaries cannot change bytes or effects.

## 2. Common scalar rules

- `schema-version` is software integer `1`.
- Negotiation has no `protocol-version`; error context uses version `0`.
- `protocol-version` is a positive software integer selected by negotiation.
- `session-id`, `request-id`, and `idempotency-key` are `text` allocated by
  Shen. They are 1-128 ASCII octets matching
  `[A-Za-z0-9][A-Za-z0-9._/-]*`.
- The adapter echoes Shen IDs. It never allocates a simulation ID.
- `kind`, status, capability names, codec names, and error codes are symbols.
- Every record has exactly the fields specified below. Missing, extra,
  duplicated, or reordered fields fail before effects.

Examples below use a readable record notation. Exact bytes are frozen under
`protocol/fixtures/v1/uap/`.

## 3. Hello and selection

Shen opens a session with:

```text
{
  kind: hello,
  request-id: text,
  required-capabilities: list(symbol),
  schema-version: 1,
  session-id: text,
  versions: nonempty-list(integer)
}
```

`versions` is duplicate-free and ordered by Shen preference. The adapter
selects the first item it supports. It does not sort or invent a preference.
No overlap is `version-mismatch`.

Capabilities are facts in an ordered record. A required capability succeeds
only when the corresponding adapter fact is exactly boolean true. Missing,
false, or non-boolean facts fail as `required-capability-unavailable`; no
session is created. The adapter does not choose a determinism profile or
silently downgrade a request.

The successful response is:

```text
{
  capabilities: record,
  codec: urdr-rfc9804-v1,
  kind: selection,
  protocol-version: integer,
  request-id: text,
  schema-version: 1,
  session-id: text
}
```

Repeating byte-identical hello semantics with the same IDs returns the same
selection. Reusing a session ID with another hello or request ID is
`conflicting-session`.

## 4. Command and request fingerprint

An effect request is:

```text
{
  command: canonical-value,
  idempotency-key: text,
  kind: command,
  protocol-version: integer,
  request-id: text,
  schema-version: 1,
  session-id: text
}
```

The v1 request fingerprint is exactly:

```text
SHA-256(
  ASCII("URDR-UAP-REQUEST") || 0x00 || 0x01 ||
  canonical-payload(command)
)
```

It is returned as exactly 32 `bytes`. The domain, revision octet, and command
payload are fixed. Framing, IDs, and the idempotency key are excluded so a Shen
retry has the same effect identity. Python `hashlib` is a native optimization;
fixtures freeze its bytes against the accepted SHA-256 semantics.

The common endpoint parses and validates the complete frame, value, fixed
schema, versions, IDs, request reuse, and idempotency state before calling an
adapter. The adapter backend then has two phases:

1. `validate(command)` performs no effects.
2. `start(validated-command)` performs the effect once.

Unexpected host exception prose is never serialized.

## 5. Observation, poll, and collect

Every command, poll, and collect success returns the same fixed observation:

```text
{
  cached: boolean,
  kind: observation,
  protocol-version: integer,
  request-fingerprint: bytes(32),
  request-id: text,
  result: canonical-value-or-null,
  schema-version: 1,
  session-id: text,
  status: pending-or-terminal
}
```

`cached` says the idempotency entry already existed; it is not a policy
verdict. A command and collect include the terminal fact in `result`. Poll
always uses `null` for `result`, even when status is terminal, so observation
and collection remain explicit. A genuine terminal null is distinguished by
`status: terminal`.

Poll is:

```text
{
  idempotency-key: text,
  kind: poll,
  protocol-version: integer,
  request-id: text,
  schema-version: 1,
  session-id: text
}
```

Collect is:

```text
{
  idempotency-key: text,
  kind: collect,
  protocol-version: integer,
  reclaim: boolean,
  request-id: text,
  schema-version: 1,
  session-id: text
}
```

Adapters do not push completions into world order. The operation is inspected
only while handling an explicit command, poll, or collect from Shen. No host
timestamp, elapsed duration, readiness ordering, retry, or timeout appears in
the message.

## 6. Idempotency lifetime and reclaim

The cache key is `(session-id, idempotency-key)`.

1. First use stores the 32-byte request fingerprint before observing
   completion and calls `start` once.
2. An exact fingerprint match returns the cached current pending/terminal fact
   without adapter validation or another effect.
3. A different fingerprint for the same key is `idempotency-conflict` before
   validation or effects.
4. Reusing a request ID for different canonical request bytes is
   `conflicting-request`.
5. Entries never expire by wall time, access count, socket disconnect, map
   pressure, or implementation iteration order.
6. `collect` with `reclaim: false` retains the terminal fact.
7. `collect` with `reclaim: true` returns a terminal fact once, then removes
   the operation and result while retaining a fingerprint tombstone.
8. A retry against a tombstone fails as `idempotency-result-reclaimed`; it
   never performs the effect again.
9. Pending entries cannot be reclaimed. A true reclaim on pending state
   returns pending and leaves the entry intact.
10. Entries and tombstones live until the endpoint session itself is
    deterministically discarded by its owner. Transport close alone does not
    mutate them.

Shen must not request reclaim until it has durably consumed the collect
observation. This gives bounded result retention without sacrificing
at-most-once effects.

## 7. Stable error record

All errors use exactly:

```text
{
  code: symbol,
  detail: canonical-value,
  kind: error,
  protocol-version: integer,
  request-id: text-or-null,
  schema-version: 1,
  session-id: text-or-null
}
```

Parsed IDs are echoed when available. Framing/canonical failures have null IDs
and protocol version `0`. Detail is null unless a fixed schema supplies a fact,
such as the unavailable capability or conflicting idempotency key.

ADR 0002 canonical/framing codes remain unchanged. UAP v1 additionally defines:

- schema/session: `invalid-schema`, `schema-version-mismatch`,
  `invalid-session-id`, `invalid-request-id`, `invalid-protocol-version`,
  `unknown-message-kind`, `unknown-session`, `protocol-version-mismatch`,
  `conflicting-session`, `conflicting-request`;
- negotiation: `invalid-version-list`, `version-mismatch`,
  `invalid-capability-list`, `required-capability-unavailable`;
- idempotency: `invalid-idempotency-key`, `idempotency-conflict`,
  `unknown-idempotency-key`, `idempotency-result-reclaimed`,
  `invalid-reclaim`;
- backend boundary: `invalid-command`, `backend-validation-failed`,
  `effect-start-failed`, `invalid-backend-operation`,
  `effect-observation-failed`.

Error codes are semantic. Host exception text, locale, timestamps, process
identity, and stack traces are not.

## 8. Native authority exclusions

The common UAP implementation contains no host time, random source, global
event sequencer, retry scheduler, capability downgrade, profile selection, or
certification decision. SHA-256 identifies request bytes; it is not a random
choice. Record sorting is canonical serialization, not world-event ordering.
Socket readiness only permits byte movement. Shen decides what every returned
fact means and when it enters world state.
