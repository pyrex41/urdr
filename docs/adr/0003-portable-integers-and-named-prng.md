# ADR 0003: Portable integers and named PRNG streams

Status: Accepted for M0

Date: 2026-07-24

Supersedes: None

Superseded by: None

Relates to: `SPEC.md` §7.1, §8, §16, §17, §24 M0, and architectural
invariants 1, 2, 7, 8, 9, and 10

## Context

Urdr requires arbitrary-precision integers and isolated deterministic random
streams, while Shen deliberately leaves native numeric precision
implementation-dependent. Shen-Lua and other ports may represent host numbers
with IEEE-754 doubles. Using host integers for time, counters, serialization,
or PRNG words would therefore make M0 runtime-dependent.

Two executable candidates were tested on Shen-CL, Shen-Go, Shen-Rust, and
Shen-Lua:

1. Base-10,000 software integers with arithmetic-only SHA-256 counter streams.
2. Base-65,536 software integers with arithmetic-only Philox4x32-10 and a
   custom variable-length coordinate compressor.

Both passed cross-runtime vectors. The SHA-256 candidate was selected because
its coordinate framing is directly length-delimited, its core has standard
published vectors, and it avoids making an unreviewed custom compressor part
of permanent world semantics. M0 favors a smaller semantic risk over data-path
performance.

## Decision

### Portable software integers

An integer is:

```text
[big SIGN LITTLE-ENDIAN-BASE-10000-LIMBS]
```

`SIGN` is `-1`, `0`, or `1`. Zero is exactly `[big 0 []]`. A nonzero value has
a nonzero final limb. All public constructors validate and normalize.

The implementation supplies:

- validation and normalization;
- signed comparison, addition, subtraction, and multiplication;
- truncating signed division and remainder;
- strict decimal parsing and rendering;
- nonnegative logical-time comparison, addition, subtraction, and successor;
- conversion between canonical decimal octets and software values.

Division truncates toward zero and satisfies `a = q*b + r`; the remainder has
the dividend's sign. No operation uses host `/`, remainder, floor, floating
point, nonstandard bitwise primitives, or host bignums.

Limb multiplication plus carry is at most 99,990,000. Every host-number
intermediate must remain below this reviewed bound. Software values themselves
are limited only by deterministic resource limits, not by a runtime's native
integer width.

World logical time, event and request counters, PRNG counters, sizes that enter
world semantics, and canonical integer values use this representation.

### Named SHA-256 counter streams

The algorithm identifier is `urdr-sha256-counter-v1`.

The pure block function consumes:

```text
(seed, subsystem, actor-id, purpose, local-counter, block-index)
```

`seed`, `subsystem`, `actor-id`, and `purpose` are canonical octet strings.
The counters are normalized nonnegative software integers rendered as
canonical decimal ASCII.

The exact hashed message is:

```text
ASCII("URDR-PRNG-SHA256") || 0x00 || 0x01 ||
field(1, seed) || field(2, subsystem) || field(3, actor-id) ||
field(4, purpose) || field(5, decimal(local-counter)) ||
field(6, decimal(block-index))
```

where:

```text
field(tag, payload) = byte(tag) || uvar(length(payload)) || payload
uvar(0) = 0x00
```

For nonzero lengths, `uvar` is minimal unsigned big-endian base-128 with the
continuation bit set on every nonfinal digit. Tags, minimal lengths, and fixed
field order make the coordinate encoding injective before hashing.

SHA-256 words are represented as four big-endian byte values. Bit operations
are implemented arithmetically over bounded byte/bit lists; no host SHA or
bitwise extension is semantic authority. The block result is the 32 digest
octets.

`draw` is a pure function that returns the block and a new immutable stream
coordinate. There is no global stream. Snapshots and transcripts record the
algorithm ID, semantic path, local counter, block indices, and rejection
coordinates.

### Bias-free bounded sampling

For a positive software-integer bound, interpret a block as an unsigned
256-bit software integer. Let:

```text
limit = floor(2^256 / bound) * bound
```

Accept candidates below `limit` and return the candidate remainder modulo the
bound. A rejected candidate advances only that draw's block index and is
included in the decision transcript. It never consumes another named stream's
coordinate.

### Security boundary

Cryptographic security is not claimed. SHA-256 supplies standardized,
portable diffusion and vectors. Deterministic entropy and credentials produced
by Urdr must never be used outside the laboratory.

## Alternatives considered

### Native Shen numbers

Rejected because precision and overflow behavior are implementation-dependent.
Values above `2^53` already exceed the exact integer range of double-backed
ports.

### Philox4x32-10

The counter core is established and its candidate passed a published Random123
vector. The candidate's variable-length coordinate compressor was
Urdr-specific and unreviewed, so selecting it would make that compressor a
permanent collision and statistical-quality assumption.

### Shared mutable PRNG state

Rejected because a new draw in one subsystem would perturb unrelated choices,
violating named-stream isolation and making transcripts fragile.

## Consequences

- Time, counters, and randomness agree independently of host numeric width.
- Random access by semantic coordinate makes stream isolation structural.
- Arithmetic-only SHA-256 allocates many short lists and is slower than native
  hashing. Native acceleration may be added only as a byte-for-byte verified
  optimization; portable Shen remains the semantic oracle.
- Public byte-list boundaries require deterministic validation before product
  use.

## Required verification

1. Integers beyond `2^53`, `2^64`, and hundreds of decimal digits pass all
   arithmetic and canonicalization tests on four required ports.
2. NIST SHA-256 vectors and independent-oracle Urdr coordinate vectors agree
   byte-for-byte on all four ports.
3. Same coordinates repeat exactly; changed semantic paths change only that
   stream's result.
4. Adding or rejecting a draw on one stream does not perturb another stream.
5. Bounded sampling matches an independent oracle and records every rejected
   coordinate without modulo bias.
6. Invalid signs, limbs, byte values, counters, bounds, and nonminimal
   encodings fail with stable errors.
7. Tests and static review prove no host time, randomness, globals, floating
   point, host SHA, or nonstandard bitwise operation enters semantics.

## References

- FIPS PUB 180-4, Secure Hash Standard:
  <https://doi.org/10.6028/NIST.FIPS.180-4>
- Shen number portability:
  <https://shenlanguage.org/SD/Numbers.html>
- Executable selected candidate:
  `spikes/m0-candidates/prng-sha256/`
