# Arithmetic bigint/PRNG candidate

Status: executable best-of-N candidate, not an accepted Urdr wire contract.

This subtree tests a portable signed base-65,536 integer and a pure random-access
PRNG named `URDR-PHILOX-FRAMED-v1`. It is designed for the Shen world kernel:
there are no globals, mutable streams, host clocks, host entropy, floating-point
operations, host bitwise extensions, maps, or runtime identities.

## Software integer contract

An integer is `[sign | magnitude]`. Magnitude limbs are little-endian integers
in `0..65535`.

- zero is exactly `[0]`;
- positive values are `[1 d0 ... dn]`;
- negative values are `[-1 d0 ... dn]`;
- a nonzero value has at least one limb and its highest limb is nonzero.

`bigint.shen` supplies validation and normalization, signed comparison,
addition, subtraction, multiplication, truncating signed division/remainder,
strict decimal parsing/printing, and nonnegative logical-time operations.
Division truncates toward zero and its remainder has the dividend's sign, so
`a = q*b + r`. Decimal input rejects empty text, `+`, leading zeroes, and `-0`.

No expression uses Shen `/` or `mod`. Exact small division is implemented by
binary multiples and subtraction. A 16-by-16 limb product is decomposed into
8-bit products. The largest intentional host-side intermediate is below
33,554,432 (while dividing a limb stream by 256), well inside exact signed
32-bit and IEEE-754 integer ranges. Software values themselves are unbounded by
host integer width and are tested at hundreds of decimal digits.

## Philox core

The core is Random123 Philox4x32-10. A 32-bit word is two 16-bit limbs,
little-endian. A counter is four words and a key is two words. Each round is:

```text
p0 = 0xd2511f53 * c0
p1 = 0xcd9e8d57 * c2
c' = [high(p1) xor c1 xor k0, low(p1),
      high(p0) xor c3 xor k1, low(p0)]
k' = [k0 + 0x9e3779b9, k1 + 0xbb67ae85] mod 2^32
```

Ten rounds are applied. Multiplication, addition, and XOR are all software
operations over 16-bit limbs. `vectors.json` includes the published Random123
zero vector:

```text
counter = 00000000 00000000 00000000 00000000
key     = 00000000 00000000
output  = 6627e8d5 e169c58d bc57ac4c 9b00dbd8
```

## Collision-safe coordinate framing

The block API takes:

```text
(seed, subsystem-octets, actor-octets, purpose-octets,
 local-counter, block-index)
```

The seed is a signed software integer. Both counters are arbitrary nonnegative
software integers. The three names are explicit octet lists; UTF-8 validation
and text-to-octet canonicalization belong at the canonical-value boundary, not
inside this PRNG.

The exact frame is:

```text
ASCII("URDR-PHILOX-FRAME-v1")
field(1, signed(seed))
field(2, subsystem)
field(3, actor)
field(4, purpose)
field(5, natural(local-counter))
field(6, natural(block-index))
```

`field(tag, payload) = tag || E(payload) || 00`. For every payload octet `b`,
`E` emits `(floor(b/16)+1, b mod 16+1)`, so encoded payload values are `1..16`
and zero is an unambiguous terminator. The fixed tags and terminators make the
frame injective: empty values, field boundaries, signs, and leading-zero
ambiguities cannot collide.

`signed(0)=00`; a positive or negative seed is respectively `01` or `02`
followed by its minimal big-endian magnitude. A natural is its minimal
big-endian magnitude, with zero encoded as empty.

The injective frame is compressed to 128 bits, so the finite digest can of
course collide; the claim is that coordinate *encoding* has no structural
collision.

## Framed block derivation

Append `80`, then zero octets to a 16-byte boundary. Decode each 16-byte block
as four little-endian 32-bit words. Start with:

```text
state = 243f6a88 85a308d3 13198a2e 03707344
```

For every block:

```text
key   = [state0 xor state2, state1 xor state3]
out   = Philox4x32-10(state xor block, key)
state = out xor state xor block
```

Finalize with `Philox4x32-10(state, [state0 xor state2, state1 xor state3])`.
The four output words are the random-access 128-bit block. Every call derives
only from its arguments; requesting another coordinate cannot perturb it.

This framing compressor is Urdr-specific and has not received cryptographic
review. Philox's core has strong published statistical evidence, but that does
not prove this custom variable-length derivation. Simulated entropy does not
need cryptographic security; production credentials must never use it.

## Bias-free bounded sampling

For positive bound `n`, let `k` be its base-65,536 limb count, `R=65536^k`, and
`limit=R-(R mod n)`. Generate a uniform `x` in `[0,R)`. Accept only when
`x < limit`, returning `x mod n`; otherwise retry. This is exact rejection
sampling and introduces no modulo bias.

An attempt may need several 128-bit blocks. Its sub-coordinate is the Cantor
pair:

```text
pair(attempt, chunk) = (attempt+chunk)(attempt+chunk+1)/2 + chunk
```

used as `block-index`; the caller's local counter remains unchanged. The result
contains an ordered transcript of every accepted/rejected candidate and every
full block coordinate. A rejection in one draw therefore cannot consume or
shift another draw's coordinate.

## Reproduction

Generate or verify vectors with only Python's standard library:

```text
python3 oracle.py --write vectors.json
python3 oracle.py --check vectors.json
python3 -m unittest test_oracle.py
```

Run `run-tests.shen` as a script from the repository root. The included Bifrost
manifest requires byte agreement and `ALL PASS`; launcher paths are supplied by
the environment and no Shen checkout is modified.

## Candidate assessment

Strengths:

- normalized arbitrary signed integers and exact logical-time arithmetic;
- established counter-based Philox core with a published external vector;
- explicit octet framing for all semantic coordinates;
- stateless stream isolation and transcript-addressed rejection;
- no host bitwise or wide-integer semantic dependency.

Risks:

- the variable-length Philox compressor is a custom, non-cryptographic design;
- software XOR, multiplication, and long division are substantially slower
  than native integer/bitwise primitives;
- recursive list arithmetic allocates heavily and may limit practical value
  sizes despite semantic unboundedness;
- callers must allocate stable semantic local counters and canonical octets;
- a future accepted contract would need an ADR, broader statistical testing,
  and adversarial cross-port fixtures before replacing this spike.
