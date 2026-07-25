# Portable base-10,000 bigint and SHA-256 named streams

This executable M0 candidate is deliberately isolated from product modules. It
tests whether portable Shen can provide arbitrary integers and deterministic,
independent random streams without inheriting a host's integer width, bitwise
extensions, clock, or random source.

## Bigint representation

An integer is:

```text
[big SIGN LITTLE-ENDIAN-BASE-10000-DIGITS]
```

`SIGN` is `-1`, `0`, or `1`. Zero has the sole representation `[big 0 []]`.
Every nonzero value has a nonzero final limb. Public constructors normalize.
Limb multiplication plus carry is at most `99,990,000`, well below `2^53`;
all other host-number operations are smaller. Division never uses host `/`,
`floor`, remainder, floating point, or bitwise operations.

The prototype provides signed comparison, addition, subtraction,
multiplication, truncating signed division/remainder, decimal parsing and
formatting, and tagged nonnegative logical-time addition/subtraction.

## SHA-256 representation and primitive proof

A 32-bit SHA word is four bytes in big-endian order. Bytes are decomposed using
comparisons and subtraction against `[128 64 32 16 8 4 2 1]`; boolean word
operations and rotations operate on lists of `0`/`1`. Modular word addition
uses only addition, comparison, and bounded repeated subtraction by 256.

The implementation uses only Shen core forms and primitives: `define`, pattern
matching, lists, `if`, `let`, `and`, `or`, `not`, equality, integer
comparison/add/subtract/multiply, `cn`, `pos`, `tlstr`, `length`, `reverse`,
`append`, `hd`, `tl`, `output`, and `load`. These are Shen kernel facilities
used by all four required ports. It does not call a host SHA function or any
host/port extension. SHA message length is accumulated as a software bigint
and encoded as the required unsigned 64-bit bit length; an overlong message
returns a tagged error.

## Coordinate encoding

`prng.coordinate` accepts four arbitrary byte lists and two normalized
nonnegative bigints:

```text
(seed, subsystem, actor-id, purpose, counter, block-index)
```

The exact byte string hashed by counter mode is:

```text
ASCII("URDR-PRNG-SHA256") || 0x00 || 0x01 ||
field(1, seed) || field(2, subsystem) || field(3, actor-id) ||
field(4, purpose) || field(5, decimal(counter)) ||
field(6, decimal(block-index))

field(tag, payload) = byte(tag) || uvar(length(payload)) || payload
uvar(n) = unsigned big-endian base-128 with continuation bit on every
          non-final digit; zero is the single byte 0x00
```

Byte-list fields avoid implicit text encodings. Decimal counters are canonical
ASCII with no sign or leading zeroes. Tags and lengths prevent concatenation,
field-boundary, and type collisions. The versioned domain prefix prevents use
as an unkeyed generic SHA namespace.

`prng.block` is a pure function of all six coordinates. `prng.draw` returns a
block and a new immutable stream value; no global stream exists. Bounded
sampling interprets a block as an unsigned 256-bit bigint and accepts only
values below `floor(2^256 / bound) * bound`. Rejections advance only that
stream's local counter and are returned as exact transcript coordinates.

## Running

```text
python3 tests/oracle.py --check fixtures/vectors.json
sh test.sh
```

`test.sh` requires the four launchers selected by the fleet plan at their known
sibling-checkout paths. It records wall-clock execution time as measurement
only; timing never enters semantic output.

## Prototype limitations and risks

- The arithmetic-only SHA implementation is intentionally slow and allocates
  many short bit lists. It is useful portability evidence, not a selected
  production implementation.
- Shen runtimes still control recursion limits and allocation behavior.
- Byte lists are trusted to contain integers in `0..255`; production code
  needs deterministic tagged validation at its public boundary.
- SHA-256's standardized maximum message length is enforced, but constructing
  such a message is not practical in this prototype.
- Cryptographic security is not claimed. SHA-256 supplies reproducible
  diffusion and published vectors; deterministic laboratory credentials must
  not escape the laboratory.
