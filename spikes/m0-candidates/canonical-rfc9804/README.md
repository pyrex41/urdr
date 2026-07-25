# Candidate: canonical RFC 9804 S-expressions

This executable M0 spike uses RFC 9804 canonical S-expressions for the typed
value and a byte-counted netstring for the outer stream. It is deliberately an
application profile, not an implementation of RFC 9804's advanced, base64, or
display-hint forms.

## Wire contract

An RFC 9804 atom is `decimal-byte-count ":" octets`; a list is `"(" elements
")"`. Counts have no leading zero (except `0`), and canonical payloads contain
no whitespace or comments. One transport frame is:

```text
decimal-payload-byte-count ":" canonical-payload ","
```

The typed payload vocabulary is:

```text
null       (4:null)
bool       (4:bool4:true) | (4:bool5:false)
integer    (3:int <canonical-decimal-atom>)
text       (4:text <strict-UTF-8-atom>)
bytes      (5:bytes <arbitrary-octet-atom>)
symbol     (6:symbol <restricted-ASCII-atom>)
list       (4:list <typed-value>*)
record     (6:record (<key-atom> <typed-value>)*)
```

Spaces above are explanatory and are absent on the wire. Symbols and record
keys match `[A-Za-z][A-Za-z0-9._/-]*`. Record keys are strictly increasing by
unsigned ASCII octet order, which simultaneously rejects duplicates.

Integers are represented in Shen as `[int positive Digits]` or
`[int negative Digits]`, where `Digits` is a list of ASCII octets. The
`cr-int-parse`/`cr-int-render` interface never converts them to a host number.
Wire integers are `0` or `-?[1-9][0-9]*`; `+`, leading zero, and `-0` fail.

Decoded Shen values are `[null]`, `[bool B]`, `[int Sign Digits]`,
`[text Octets]`, `[bytes Octets]`, `[symbol Octets]`, `[list Values]`, and
`[record [[Key Value] ...]]`. Public operations return `[ok ...]` or
`[error stable-code]`; host exception prose is not observable.

## Bounds and rejection

The prototype limits a payload to 4096 octets, an atom to 256 octets, nesting
to 32 lists, parsed S-expression nodes to 256, integer magnitude to 255 decimal
digits, and symbols to 64 octets. These are explicit candidate constants, not
RFC limits.

Both codecs reject floats/unknown tags, malformed or overlong UTF-8, surrogate
encodings, improper encoder lists, unordered or duplicate records,
noncanonical integers and lengths, comments, whitespace, trailing bytes,
truncated frames, and exceeded limits.

## Execute

```sh
spikes/m0-candidates/canonical-rfc9804/test.sh

# Reference CLI examples
python3 spikes/m0-candidates/canonical-rfc9804/codec.py encode \
  '{"$record":[["answer",{"$int":"42"}]]}'
python3 spikes/m0-candidates/canonical-rfc9804/codec.py decode HEX
```

`fixtures.tsv` is consumed independently by Shen and Python. Every valid
fixture is decoded, re-encoded byte-for-byte, emitted as lowercase raw-frame
hex, tested at every two-chunk split (including empty chunks), and tested one
octet per chunk. A concatenated two-frame stream is also tested. Invalid
fixtures assert stable rejection codes. `cross_port.py` requires all four
configured Shen 41.2 launchers and compares their 43 evidence lines exactly
with the Python oracle; a missing port is a failure, never a skip.

## Complexity and prototype risks

Complete-payload parsing is O(n) time and O(n) space. UTF-8, symbol, integer,
and record-order validation are linear in their input. Recursive nesting is
bounded to 32.

The portable Shen encoder uses immutable-list concatenation, and the simple
incremental decoder appends and reparses a bounded buffer. Worst-case
byte-at-a-time input is therefore O(n²), with O(n) live space. The Python
incremental reference also concatenates immutable `bytes`. The 4096-octet
frame bound makes this acceptable for a semantic spike, but a selected design
should use a chunk deque/rope and an iterative parser before raising limits.

Other selection risks are the custom typed vocabulary (RFC 9804 standardizes
the underlying atom/list syntax, not these tags), hard-coded resource limits,
and storing UTF-8 text as validated octets rather than host strings. The latter
is intentional for cross-port byte identity.
