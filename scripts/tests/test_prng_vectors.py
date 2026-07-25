#!/usr/bin/env python3
"""Independent ADR 0003 oracle and normative fixture verification."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
FIXTURE_DIR = ROOT / "protocol" / "fixtures" / "v1" / "prng"
VECTORS = FIXTURE_DIR / "vectors.json"
SUMS = FIXTURE_DIR / "SHA256SUMS"
DOMAIN = b"URDR-PRNG-SHA256\x00\x01"
ALGORITHM = "urdr-sha256-counter-v1"


def uvar(value: int) -> bytes:
    if value < 0:
        raise ValueError("negative-uvar")
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
    if counter < 0:
        raise ValueError("negative-counter")
    if block_index < 0:
        raise ValueError("negative-block-index")
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
    block_index: int,
) -> bytes:
    return hashlib.sha256(
        coordinate(
            seed,
            subsystem,
            actor,
            purpose,
            counter,
            block_index,
        )
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
        raise ValueError("invalid-bound")
    space = 1 << 256
    if bound > space:
        raise ValueError("bound-too-large")
    limit = (space // bound) * bound
    transcript: list[dict[str, str]] = []
    block_index = 0
    while True:
        digest = block(
            seed,
            subsystem,
            actor,
            purpose,
            counter,
            block_index,
        )
        transcript.append(
            {"counter": str(counter), "block_index": str(block_index)}
        )
        candidate = int.from_bytes(digest, "big")
        if candidate < limit:
            return candidate % bound, counter + 1, transcript
        block_index += 1


def oracle_vectors() -> dict[str, object]:
    a = int(
        "123456789012345678901234567890123456789012345678901234567890"
        "123456789012345678901234567890123456789012345678901234567890"
        "123456789012345678901234567890"
    )
    b = int(
        "987654321098765432109876543210987654321098765432109876543210"
        "987654321098765432109876543210987654321"
    )
    quotient, remainder = divmod(a, b)

    seed = b"seed"
    subsystem = b"scheduler"
    actor = b"vm-0"
    purpose = b"runnable"
    small_coordinate = coordinate(
        seed, subsystem, actor, purpose, 42, 3
    )
    huge_counter = 10**180 + 123456789
    huge_block = 10**140 + 7
    huge_coordinate = coordinate(
        seed,
        subsystem,
        actor,
        purpose,
        huge_counter,
        huge_block,
    )

    rejection_bound = (1 << 255) + 1
    rejection_counter = 0
    while True:
        _, _, transcript = sample(
            seed,
            subsystem,
            actor,
            purpose,
            rejection_counter,
            rejection_bound,
        )
        if len(transcript) >= 2:
            break
        rejection_counter += 1
    rejection_value, rejection_next, rejection_transcript = sample(
        seed,
        subsystem,
        actor,
        purpose,
        rejection_counter,
        rejection_bound,
    )
    small_value, small_next, small_transcript = sample(
        seed, subsystem, actor, purpose, 42, 10
    )

    return {
        "algorithm": ALGORITHM,
        "format": "urdr-prng-v1",
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
            "quotient": str(quotient),
            "remainder": str(remainder),
            "negative_sum": str(-a + b),
        },
        "coordinate": {
            "seed_hex": seed.hex(),
            "subsystem_hex": subsystem.hex(),
            "actor_hex": actor.hex(),
            "purpose_hex": purpose.hex(),
            "counter": "42",
            "block_index": "3",
            "encoded_hex": small_coordinate.hex(),
            "digest_hex": hashlib.sha256(small_coordinate).hexdigest(),
        },
        "huge_coordinate": {
            "counter": str(huge_counter),
            "block_index": str(huge_block),
            "encoded_length": len(huge_coordinate),
            "digest_hex": hashlib.sha256(huge_coordinate).hexdigest(),
        },
        "streams": {
            "scheduler_0_0": block(
                seed, subsystem, actor, purpose, 0, 0
            ).hex(),
            "scheduler_1_0": block(
                seed, subsystem, actor, purpose, 1, 0
            ).hex(),
            "network_0_0": block(
                seed, b"network", b"link-2", b"loss", 0, 0
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
                "start_counter": str(rejection_counter),
                "value": str(rejection_value),
                "next_counter": str(rejection_next),
                "transcript": rejection_transcript,
            },
        },
        "stable_errors": {
            "invalid_sign": "invalid-sign",
            "invalid_limb": "invalid-limb",
            "improper_limbs": "improper-limbs",
            "invalid_octet": "invalid-octet",
            "improper_octets": "improper-octets",
            "noncanonical_decimal": "noncanonical-decimal",
            "nonminimal_uvar": "nonminimal-uvar",
            "truncated_uvar": "truncated-uvar",
            "negative_counter": "negative-counter",
            "negative_block_index": "negative-block-index",
            "invalid_bound": "invalid-bound",
            "bound_too_large": "bound-too-large",
        },
    }


def canonical_json(value: object) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


class PrngVectorTests(unittest.TestCase):
    def test_normative_vectors_match_independent_oracle(self) -> None:
        self.assertEqual(VECTORS.read_bytes(), canonical_json(oracle_vectors()))

    def test_sha256sums_is_exact_and_current(self) -> None:
        expected = hashlib.sha256(VECTORS.read_bytes()).hexdigest()
        self.assertEqual(SUMS.read_text(), f"{expected}  vectors.json\n")

    def test_coordinate_framing_is_field_injective(self) -> None:
        left = coordinate(b"a", b"bc", b"", b"", 0, 0)
        right = coordinate(b"ab", b"c", b"", b"", 0, 0)
        self.assertNotEqual(left, right)

    def test_rejection_advances_block_not_stream_counter(self) -> None:
        vector = oracle_vectors()["sampling"]["forced_rejection"]
        transcript = vector["transcript"]
        counters = {entry["counter"] for entry in transcript}
        blocks = [int(entry["block_index"]) for entry in transcript]
        self.assertEqual(counters, {vector["start_counter"]})
        self.assertEqual(blocks, list(range(len(blocks))))
        self.assertEqual(
            int(vector["next_counter"]),
            int(vector["start_counter"]) + 1,
        )


if __name__ == "__main__":
    unittest.main()
