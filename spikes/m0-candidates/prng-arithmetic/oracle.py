#!/usr/bin/env python3
"""Independent Python stdlib oracle for URDR-PHILOX-FRAMED-v1."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

MASK32 = (1 << 32) - 1
M0 = 0xD2511F53
M1 = 0xCD9E8D57
W0 = 0x9E3779B9
W1 = 0xBB67AE85
IV = (0x243F6A88, 0x85A308D3, 0x13198A2E, 0x03707344)
MAGIC = b"URDR-PHILOX-FRAME-v1"


def philox4x32_10(counter: tuple[int, ...], key: tuple[int, int]) -> tuple[int, ...]:
    c0, c1, c2, c3 = counter
    k0, k1 = key
    for _ in range(10):
        p0 = M0 * c0
        p1 = M1 * c2
        c0, c1, c2, c3 = (
            ((p1 >> 32) ^ c1 ^ k0) & MASK32,
            p1 & MASK32,
            ((p0 >> 32) ^ c3 ^ k1) & MASK32,
            p0 & MASK32,
        )
        k0 = (k0 + W0) & MASK32
        k1 = (k1 + W1) & MASK32
    return c0, c1, c2, c3


def unsigned_bytes(value: int) -> bytes:
    if value < 0:
        raise ValueError("natural coordinate is negative")
    if value == 0:
        return b""
    return value.to_bytes((value.bit_length() + 7) // 8, "big")


def signed_payload(value: int) -> bytes:
    if value == 0:
        return b"\x00"
    return bytes((1 if value > 0 else 2,)) + unsigned_bytes(abs(value))


def field(tag: int, payload: bytes) -> bytes:
    framed = bytearray((tag,))
    for octet in payload:
        framed.extend(((octet >> 4) + 1, (octet & 15) + 1))
    framed.append(0)
    return bytes(framed)


def coordinate_frame(
    seed: int,
    subsystem: bytes,
    actor: bytes,
    purpose: bytes,
    counter: int,
    block: int,
) -> bytes:
    return b"".join(
        (
            MAGIC,
            field(1, signed_payload(seed)),
            field(2, subsystem),
            field(3, actor),
            field(4, purpose),
            field(5, unsigned_bytes(counter)),
            field(6, unsigned_bytes(block)),
        )
    )


def words(block: bytes) -> tuple[int, int, int, int]:
    return tuple(int.from_bytes(block[i : i + 4], "little") for i in range(0, 16, 4))


def xor_words(a: tuple[int, ...], b: tuple[int, ...]) -> tuple[int, ...]:
    return tuple(x ^ y for x, y in zip(a, b))


def frame_digest(frame: bytes) -> tuple[int, ...]:
    padded = frame + b"\x80"
    padded += b"\x00" * (-len(padded) % 16)
    state = IV
    for offset in range(0, len(padded), 16):
        block = words(padded[offset : offset + 16])
        key = state[0] ^ state[2], state[1] ^ state[3]
        output = philox4x32_10(xor_words(state, block), key)
        state = xor_words(output, xor_words(state, block))
    return philox4x32_10(state, (state[0] ^ state[2], state[1] ^ state[3]))


def prng_block(
    seed: int,
    subsystem: bytes,
    actor: bytes,
    purpose: bytes,
    counter: int,
    block: int,
) -> tuple[int, ...]:
    return frame_digest(
        coordinate_frame(seed, subsystem, actor, purpose, counter, block)
    )


def pair_natural(a: int, b: int) -> int:
    total = a + b
    return total * (total + 1) // 2 + b


def block_limbs(block: tuple[int, ...]) -> list[int]:
    result = []
    for word in block:
        result.extend((word & 0xFFFF, word >> 16))
    return result


def sample_bounded(
    seed: int,
    subsystem: bytes,
    actor: bytes,
    purpose: bytes,
    counter: int,
    bound: int,
) -> tuple[int, list[dict[str, object]]]:
    if bound <= 0:
        raise ValueError("bound must be positive")
    limbs = max(1, (bound.bit_length() + 15) // 16)
    full_range = 1 << (16 * limbs)
    limit = full_range - full_range % bound
    transcript = []
    attempt = 0
    while True:
        generated: list[int] = []
        coordinates = []
        chunk = 0
        while len(generated) < limbs:
            paired = pair_natural(attempt, chunk)
            coordinates.append(paired)
            generated.extend(
                block_limbs(
                    prng_block(
                        seed, subsystem, actor, purpose, counter, paired
                    )
                )
            )
            chunk += 1
        value = sum(
            limb << (16 * index)
            for index, limb in enumerate(generated[:limbs])
        )
        accepted = value < limit
        transcript.append(
            {
                "attempt": str(attempt),
                "block_indices": [str(value) for value in coordinates],
                "candidate": str(value),
                "verdict": "accept" if accepted else "reject",
            }
        )
        if accepted:
            return value % bound, transcript
        attempt += 1


def word_hex(values: tuple[int, ...]) -> list[str]:
    return [f"{value:08x}" for value in values]


def coordinate_case(
    name: str,
    seed: int,
    subsystem: bytes,
    actor: bytes,
    purpose: bytes,
    counter: int,
    block: int,
) -> dict[str, object]:
    frame = coordinate_frame(seed, subsystem, actor, purpose, counter, block)
    output = prng_block(seed, subsystem, actor, purpose, counter, block)
    return {
        "name": name,
        "seed": str(seed),
        "subsystem_hex": subsystem.hex(),
        "actor_hex": actor.hex(),
        "purpose_hex": purpose.hex(),
        "counter": str(counter),
        "block": str(block),
        "frame_hex": frame.hex(),
        "output_words_hex": word_hex(output),
    }


def sample_case(
    name: str,
    seed: int,
    subsystem: bytes,
    actor: bytes,
    purpose: bytes,
    counter: int,
    bound: int,
) -> dict[str, object]:
    value, transcript = sample_bounded(
        seed, subsystem, actor, purpose, counter, bound
    )
    return {
        "name": name,
        "seed": str(seed),
        "subsystem_hex": subsystem.hex(),
        "actor_hex": actor.hex(),
        "purpose_hex": purpose.hex(),
        "counter": str(counter),
        "bound": str(bound),
        "value": str(value),
        "transcript": transcript,
    }


def vectors() -> dict[str, object]:
    huge_counter = 10**120 + 987654321
    huge_block = 2**521 + 17
    huge_bound = 10**200 - 123
    a = int("1234567890" * 30)
    b = -int("99887766554433221100" * 8)
    return {
        "schema": "urdr-prng-arithmetic-vectors-1",
        "algorithm": "URDR-PHILOX-FRAMED-v1",
        "philox": [
            {
                "name": "random123-zero",
                "counter_words_hex": ["00000000"] * 4,
                "key_words_hex": ["00000000"] * 2,
                "output_words_hex": [
                    "6627e8d5",
                    "e169c58d",
                    "bc57ac4c",
                    "9b00dbd8",
                ],
            }
        ],
        "bigint": [
            {
                "a": str(a),
                "b": str(b),
                "sum": str(a + b),
                "difference": str(a - b),
                "product": str(a * b),
                "quotient_trunc_zero": str(abs(a) // abs(b) * (-1)),
                "remainder_dividend_sign": str(a - (abs(a) // abs(b) * -1) * b),
            }
        ],
        "coordinates": [
            coordinate_case("all-empty-zero", 0, b"", b"", b"", 0, 0),
            coordinate_case(
                "arbitrary-integers",
                -123456789012345678901234567890,
                b"scheduler",
                b"vm-0",
                b"runnable",
                huge_counter,
                huge_block,
            ),
            coordinate_case("boundary-a-bc", 7, b"a", b"bc", b"", 9, 2),
            coordinate_case("boundary-ab-c", 7, b"ab", b"c", b"", 9, 2),
        ],
        "bounded": [
            sample_case("ten", 42, b"network", b"link-2", b"loss", 3, 10),
            sample_case(
                "forced-rejection", 1, b"tests", b"actor", b"reject", 1, 32769
            ),
            sample_case(
                "two-hundred-digits",
                -99,
                b"guest",
                b"vm-0",
                b"entropy",
                huge_counter,
                huge_bound,
            ),
        ],
    }


def canonical_json(data: object) -> str:
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", type=Path)
    parser.add_argument("--check", type=Path)
    args = parser.parse_args()
    rendered = canonical_json(vectors())
    if args.write:
        args.write.write_text(rendered, encoding="utf-8", newline="\n")
    elif args.check:
        if args.check.read_text(encoding="utf-8") != rendered:
            raise SystemExit(f"{args.check} differs from oracle output")
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
