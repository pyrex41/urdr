# ADR 0002: Canonical values and UAP framing

Status: Accepted for M0

Date: 2026-07-24

Supersedes: None

Superseded by: None

Relates to: `SPEC.md` §7.1, §7.3, §20, §24 M0, and architectural
invariants 2, 3, 8, 9, and 10

## Context

M0 requires byte-identical values and traces across Shen implementations.
Portable Shen does not guarantee a common Unicode string model, native
arbitrary-precision integers, printer spelling, or map order. Bifrost also
normalizes launcher output, so visually equal output is insufficient evidence
of equal wire bytes.

Two executable candidates were tested on Shen-CL, Shen-Go, Shen-Rust, and
Shen-Lua:

1. RFC 9804-style counted atoms and lists inside a netstring frame.
2. Whitespace-free textual S-expressions inside a 32-bit binary length frame.

Both agreed across all four ports. The counted-atom candidate avoids string
escaping in the semantic grammar, makes atom boundaries byte-explicit, and
uses one ASCII framing rule that portable Shen can parse without host binary
integer conversions.

## Decision

### Canonical S-expression profile

Urdr canonical values use the following subset of RFC 9804 canonical
S-expressions:

```text
atom = decimal-octet-count ":" exact-octets
list = "(" *value ")"
```

Lengths use `0` or a nonzero decimal digit followed by decimal digits. Leading
zeroes, signs, whitespace, comments, display hints, base64 forms, and trailing
input are invalid.

The typed vocabulary is:

```text
null       (4:null)
boolean    (4:bool4:true) | (4:bool5:false)
integer    (3:int <canonical-decimal-atom>)
text       (4:text <strict-UTF-8-atom>)
bytes      (5:bytes <arbitrary-octet-atom>)
symbol     (6:symbol <restricted-ASCII-atom>)
list       (4:list <typed-value>*)
record     (6:record (<key-atom> <typed-value>)*)
```

Spaces above are explanatory only. Symbols and record keys match
`[A-Za-z][A-Za-z0-9._/-]*`. Record keys are strictly increasing by unsigned
ASCII octet order; this also rejects duplicates.

Integers on the wire use `0` or `-?[1-9][0-9]*`. `+`, leading zeroes, `-0`,
fractional forms, and exponents are invalid. Decoding produces the software
integer defined by ADR 0003 rather than a host number.

Text atoms must be shortest-form UTF-8 encoding Unicode scalar values.
Overlong encodings, surrogates, and values above U+10FFFF are invalid. Urdr
performs no NFC, NFD, or locale normalization: scalar identity is semantic
identity. Portable Shen stores text as validated octets, not host strings.
Bytes remain arbitrary octets.

Unknown tags, improper encoder values, unordered records, duplicate fields,
and invalid nested values fail with stable error codes before effects.

### Stream framing

Each UAP transport frame is one byte-counted netstring:

```text
decimal-payload-octet-count ":" canonical-payload ","
```

The count covers the canonical payload only. It has no leading zeroes except
for zero. A frame contains exactly one canonical value. Truncation, excess
bytes, missing comma, or noncanonical length is a transport error and closes
the stream before dispatch.

In-process and Unix-socket adapters consume and produce these exact frame
bytes through the same codec. Neither transport receives privileged semantic
behavior.

### M0 resource profile

The executable M0 profile limits:

- payload: 4,096 octets;
- atom: 256 octets;
- nesting: 32 lists;
- parsed nodes: 256;
- integer magnitude: 255 decimal digits;
- symbol: 64 octets.

These are deterministic protocol limits, not claims about RFC 9804. A later
version may raise them only after an iterative/chunked implementation passes
the same split-input and resource-exhaustion tests. Large data crosses UAP by
content-addressed blob reference rather than by silently bypassing limits.

### Evidence representation

Golden frame files contain exact bytes and a checked-in SHA-256 manifest.
Bifrost entrypoints print lowercase hexadecimal encodings of those bytes.
The strict conformance wrapper compares all four required ports with the
independent oracle and the checked-in golden; normalized text agreement alone
does not pass M0.

## Alternatives considered

### Textual S-expressions with a binary length

This candidate passed its prototype suite and had a smaller implementation.
It was not selected because escaping text and bytes expands the canonical
grammar and a binary length requires a second host-independent integer codec
at the transport boundary.

### Runtime printer/read syntax

Rejected because printer spelling, Unicode behavior, map order, exception
text, whitespace, and integer range are runtime-dependent.

### JSON, MessagePack, or CBOR

Rejected for M0 because the accepted specification requires canonical UTF-8
S-expressions. Adopting another family would require a specification-level
architecture change.

## Consequences

- Canonical semantics operate on octets and software integers, independent of
  host string and number behavior.
- Frames are self-delimiting twice: the transport netstring delimits a message
  and counted atoms delimit values inside it.
- The selected prototype reparses immutable buffers for incremental input and
  can be quadratic for byte-at-a-time delivery. The low M0 frame limit bounds
  this cost; production limits require a chunk deque and iterative parser.
- The tagged Urdr vocabulary is an application profile layered on RFC 9804,
  and therefore remains versioned Urdr protocol semantics.

## Required verification

1. Every valid fixture decodes and re-encodes to identical bytes.
2. Shen-CL, Shen-Go, Shen-Rust, and Shen-Lua emit identical fixture hex and
   stable verdicts.
3. An independent standard-library codec agrees on ASTs, bytes, and errors.
4. Every two-chunk split, byte-at-a-time input, and concatenated frame stream
   produces the same result.
5. Invalid UTF-8, lengths, integers, records, tags, truncation, limits, and
   trailing input fail before adapter effects.
6. A changed golden, digest, required runtime, or output byte fails the strict
   M0 gate.

## References

- RFC 9804, Canonical S-Expressions:
  <https://www.rfc-editor.org/rfc/rfc9804.html>
- RFC 3629, UTF-8:
  <https://www.rfc-editor.org/rfc/rfc3629.html>
- Executable selected candidate:
  `spikes/m0-candidates/canonical-rfc9804/`
