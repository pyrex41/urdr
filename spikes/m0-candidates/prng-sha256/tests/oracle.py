#!/usr/bin/env python3
"""Independent Python stdlib oracle for the Shen bigint/PRNG candidate."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FIXTURE = ROOT / "fixtures" / "vectors.json"
DOMAIN = b"URDR-PRNG-SHA256\x00\x01"


def uvar(value: int) -> bytes:
    if value < 0:
        raise ValueError("uvar requires a nonnegative integer")
    digits = [value % 128]
    value //= 128
    while value:
        digits.append(value % 128)
        value //= 128
    digits.reverse()
    return bytes(
        digit | (0x80 if index + 1 < len(digits) else 0)
        for index, digit in enumerate(digits)
    )


def field(tag: int, payload: bytes) -> bytes:
    return bytes([tag]) + uvar(len(payload)) + payload


def coordinate(
    seed: bytes,
    subsystem: bytes,
    actor: bytes,
    purpose: bytes,
    counter: int,
    block_index: int,
) -> bytes:
    if counter < 0 or block_index < 0:
        raise ValueError("coordinates require nonnegative counters")
    payloads = (
        seed,
        subsystem,
        actor,
        purpose,
        str(counter).encode("ascii"),
        str(block_index).encode("ascii"),
    )
    return DOMAIN + b"".join(
        field(tag, payload) for tag, payload in enumerate(payloads, 1)
    )


def block(
    seed: bytes,
    subsystem: bytes,
    actor: bytes,
    purpose: bytes,
    counter: int,
    block_index: int = 0,
) -> bytes:
    return hashlib.sha256(
        coordinate(seed, subsystem, actor, purpose, counter, block_index)
    ).digest()


def sample(
    seed: bytes,
    subsystem: bytes,
    actor: bytes,
    purpose: bytes,
    counter: int,
    bound: int,
) -> tuple[int, int, list[dict[str, str]]]:
    if bound <= 0:
        raise ValueError("bound must be positive")
    space = 1 << 256
    limit = (space // bound) * bound
    transcript: list[dict[str, str]] = []
    while True:
        digest = block(seed, subsystem, actor, purpose, counter)
        transcript.append({"counter": str(counter), "block_index": "0"})
        value = int.from_bytes(digest, "big")
        counter += 1
        if value < limit:
            return value % bound, counter, transcript


def oracle_vectors() -> dict[str, Any]:
    a = int(
        "123456789012345678901234567890123456789012345678901234567890"
        "123456789012345678901234567890123456789012345678901234567890"
        "123456789012345678901234567890"
    )
    b = int(
        "987654321098765432109876543210987654321098765432109876543210"
        "987654321098765432109876543210987654321"
    )
    q, r = divmod(a, b)

    seed = b"seed"
    subsystem = b"scheduler"
    actor = b"vm-0"
    purpose = b"runnable"
    huge_counter = 10**180 + 123456789
    huge_block = 10**140 + 7

    rejection_bound = (1 << 255) + 1
    rejection_start = 0
    while True:
        _, _, transcript = sample(
            seed, subsystem, actor, purpose, rejection_start, rejection_bound
        )
        if len(transcript) >= 2:
            break
        rejection_start += 1
    rejection_value, rejection_next, rejection_transcript = sample(
        seed, subsystem, actor, purpose, rejection_start, rejection_bound
    )
    small_value, small_next, small_transcript = sample(
        seed, subsystem, actor, purpose, 42, 10
    )

    return {
        "format": "urdr-prng-sha256-candidate-v1",
        "sha256": [
            {
                "name": "nist-empty",
                "message_hex": "",
                "digest_hex": hashlib.sha256(b"").hexdigest(),
            },
            {
                "name": "nist-abc",
                "message_hex": b"abc".hex(),
                "digest_hex": hashlib.sha256(b"abc").hexdigest(),
            },
            {
                "name": "nist-long",
                "message_hex": (
                    b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
                ).hex(),
                "digest_hex": hashlib.sha256(
                    b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
                ).hexdigest(),
            },
        ],
        "bigint": {
            "a": str(a),
            "b": str(b),
            "sum": str(a + b),
            "difference": str(a - b),
            "product": str(a * b),
            "quotient": str(q),
            "remainder": str(r),
            "negative_sum": str(-a + b),
        },
        "coordinate": {
            "seed_hex": seed.hex(),
            "subsystem_hex": subsystem.hex(),
            "actor_hex": actor.hex(),
            "purpose_hex": purpose.hex(),
            "counter": str(huge_counter),
            "block_index": str(huge_block),
            "encoded_length": len(
                coordinate(
                    seed, subsystem, actor, purpose, huge_counter, huge_block
                )
            ),
            "digest_hex": block(
                seed, subsystem, actor, purpose, huge_counter, huge_block
            ).hex(),
        },
        "streams": {
            "scheduler_0": block(seed, subsystem, actor, purpose, 0).hex(),
            "scheduler_1": block(seed, subsystem, actor, purpose, 1).hex(),
            "network_0": block(
                seed, b"network", b"link-2", b"loss", 0
            ).hex(),
        },
        "sampling": {
            "small": {
                "bound": "10",
                "start_counter": "42",
                "value": str(small_value),
                "next_counter": str(small_next),
                "transcript": small_transcript,
            },
            "forced_rejection": {
                "bound": str(rejection_bound),
                "start_counter": str(rejection_start),
                "value": str(rejection_value),
                "next_counter": str(rejection_next),
                "transcript": rejection_transcript,
            },
        },
    }


def canonical_json(value: object) -> str:
    return json.dumps(value, indent=2, sort_keys=True) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--check", metavar="PATH", type=Path)
    action.add_argument("--write", metavar="PATH", type=Path)
    args = parser.parse_args()

    rendered = canonical_json(oracle_vectors())
    if args.write:
        args.write.parent.mkdir(parents=True, exist_ok=True)
        args.write.write_text(rendered, encoding="utf-8")
        print(f"wrote {args.write}")
        return 0

    expected = args.check.read_text(encoding="utf-8")
    if expected != rendered:
        print(f"oracle mismatch: regenerate {args.check}", flush=True)
        return 1
    print("python-oracle: vectors match")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
