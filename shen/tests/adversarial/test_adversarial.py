"""Executable negative and mutation tests for the M0 semantic nucleus."""

from __future__ import annotations

import copy
import itertools
import json
import sys
import unittest
from pathlib import Path

from oracles import (
    MARKER,
    AdapterCommand,
    GateFailure,
    Reject,
    all_chunkings,
    bounded_draw,
    canonical_event_order,
    canonical_fields,
    expected_observation,
    parse_integer,
    prng_word,
    reduce_prototype,
    rejection_marker,
    render_integer,
    validate_adapter_exchange,
    verify_gate,
)

ROOT = Path(__file__).resolve().parents[3]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from adapters.common.uap.codec import CanonicalCodec, CodecError  # noqa: E402
from adapters.common.uap.transport import FrameDecoder  # noqa: E402

INVALID = ROOT / "protocol/fixtures/v1/invalid"


def fixture_bytes(name: str) -> bytes:
    return bytes.fromhex((INVALID / name).read_text(encoding="ascii").strip())


def reject_code(callable_, *arguments) -> str:
    with unittest.TestCase().assertRaises(Reject) as caught:
        callable_(*arguments)
    return caught.exception.code


class BigIntegerAttacks(unittest.TestCase):
    def test_exact_values_beyond_common_native_boundaries(self) -> None:
        values = [
            2**53 + 1,
            2**64 + 1,
            int("9" * 600),
            -int("8" * 600),
        ]
        for value in values:
            with self.subTest(digits=len(str(abs(value)))):
                self.assertEqual(parse_integer(render_integer(value)), value)

    def test_noncanonical_integer_spellings_fail(self) -> None:
        for text in ["+1", "01", "-0", "1.0", "1e3", " 1", "1 ", ""]:
            with self.subTest(text=text):
                self.assertEqual(reject_code(parse_integer, text), "invalid-integer")

    def test_float_cast_mutation_loses_above_2_to_53(self) -> None:
        text = str(2**53 + 1)
        self.assertNotEqual(int(float(text)), parse_integer(text))


class RuntimeLeakAttacks(unittest.TestCase):
    def test_field_order_is_independent_of_hash_insertion_order(self) -> None:
        expected = (("a", 2), ("z", 1), ("ä", 3))
        fields = [("z", 1), ("ä", 3), ("a", 2)]
        for permutation in itertools.permutations(fields):
            self.assertEqual(canonical_fields(permutation), expected)

    def test_case_or_locale_like_sort_mutation_is_detected(self) -> None:
        fields = [("Z", 1), ("a", 2)]
        canonical = canonical_fields(fields)
        locale_like_mutant = tuple(sorted(fields, key=lambda item: item[0].lower()))
        self.assertNotEqual(locale_like_mutant, canonical)

    def test_exception_prose_cannot_enter_rejection_marker(self) -> None:
        first = Reject("invalid-integer")
        second = Reject("invalid-integer")
        first.args = ("runtime A says nope",)
        second.args = ("runtime B says invalid literal at 0x123",)
        self.assertEqual(rejection_marker(first), rejection_marker(second))
        self.assertNotIn("runtime", json.dumps(rejection_marker(first)))


class FramingAttacks(unittest.TestCase):
    """Hostile framing against the production ADR 0002 netstring decoder."""

    def test_every_chunk_split_of_valid_frame_is_equivalent(self) -> None:
        from adapters.common.uap.codec import NULL

        wire = CanonicalCodec().encode_frame(NULL)
        self.assertEqual(wire, b"8:(4:null),")
        self.assertEqual(sum(1 for _ in all_chunkings(wire)), 2 ** (len(wire) - 1))
        for chunks in all_chunkings(wire):
            decoder = FrameDecoder()
            values = []
            for chunk in chunks:
                values.extend(decoder.feed(chunk))
            decoder.finish()
            self.assertEqual(len(values), 1)

    def assert_rejected_without_effect(self, wire: bytes, codes: set[str]) -> None:
        chunkings = [(wire,)] + [
            (wire[:split], wire[split:]) for split in range(1, len(wire))
        ]
        for chunks in chunkings:
            effects: list[object] = []
            decoder = FrameDecoder()
            with self.assertRaises(CodecError) as caught:
                for chunk in chunks:
                    values = decoder.feed(chunk)
                    effects.extend(values)
                decoder.finish()
            self.assertIn(caught.exception.code, codes)
            self.assertEqual(effects, [])

    def test_malformed_utf8_fails_for_every_chunk_split(self) -> None:
        self.assert_rejected_without_effect(
            fixture_bytes("malformed-utf8.hex"), {"utf8-invalid"}
        )

    def test_duplicate_fields_fail_before_effect(self) -> None:
        self.assert_rejected_without_effect(
            fixture_bytes("duplicate-fields.hex"), {"record-duplicate"}
        )

    def test_truncated_prefix_fails(self) -> None:
        self.assert_rejected_without_effect(
            fixture_bytes("truncated-prefix.hex"), {"frame-truncated"}
        )

    def test_truncated_payload_fails_for_every_chunk_split(self) -> None:
        self.assert_rejected_without_effect(
            fixture_bytes("truncated-payload.hex"), {"frame-truncated"}
        )

    def test_over_limit_fails_as_soon_as_prefix_completes(self) -> None:
        self.assert_rejected_without_effect(
            fixture_bytes("over-limit.hex"), {"frame-too-large"}
        )


class ReducerAttacks(unittest.TestCase):
    def setUp(self) -> None:
        self.world = {"time": 10, "last_event_id": 7, "events": ()}

    def test_reduction_does_not_mutate_world_or_event(self) -> None:
        event = {"id": 8, "time": 10, "kind": "observation", "actor": "vm-0"}
        before_world = copy.deepcopy(self.world)
        before_event = copy.deepcopy(event)
        result = reduce_prototype(self.world, event)
        self.assertEqual(self.world, before_world)
        self.assertEqual(event, before_event)
        self.assertIsNot(result, self.world)

    def test_time_rollback_is_rejected(self) -> None:
        event = {"id": 8, "time": 9, "kind": "advance", "actor": "world"}
        self.assertEqual(reject_code(reduce_prototype, self.world, event), "time-rollback")

    def test_non_advance_event_cannot_advance_time(self) -> None:
        event = {"id": 8, "time": 11, "kind": "observation", "actor": "vm-0"}
        self.assertEqual(
            reject_code(reduce_prototype, self.world, event), "implicit-time-advance"
        )

    def test_stale_and_duplicate_ids_are_rejected(self) -> None:
        for event_id in [7, 6, -1]:
            event = {
                "id": event_id,
                "time": 10,
                "kind": "observation",
                "actor": "vm-0",
            }
            self.assertEqual(
                reject_code(reduce_prototype, self.world, event), "stale-event-id"
            )

    def test_ties_have_canonical_order_not_arrival_order(self) -> None:
        events = [
            {"id": 9, "time": 10, "kind": "packet", "actor": "z"},
            {"id": 8, "time": 10, "kind": "packet", "actor": "a"},
            {"id": 10, "time": 10, "kind": "block", "actor": "a"},
        ]
        expected = (10, 8, 9)
        for permutation in itertools.permutations(events):
            self.assertEqual(
                tuple(event["id"] for event in canonical_event_order(permutation)),
                expected,
            )
        self.assertNotEqual(tuple(event["id"] for event in events), expected)


class PrngAttacks(unittest.TestCase):
    def test_path_isolation_survives_unrelated_draws(self) -> None:
        seed = 123456789012345678901234567890
        path_a = ("scheduler", "vm-0", "runnable")
        path_b = ("network", "link-2", "loss")
        before = prng_word(seed, path_b, 0)
        for counter in range(100):
            prng_word(seed, path_a, counter)
        self.assertEqual(prng_word(seed, path_b, 0), before)
        self.assertNotEqual(prng_word(seed, path_a, 0), before)

    def test_counter_is_not_truncated_at_64_bits(self) -> None:
        path = ("guest", "vm-0", "entropy")
        self.assertNotEqual(prng_word(1, path, 1), prng_word(1, path, 2**64 + 1))

    def test_rejection_sampling_avoids_modulo_bias_tail(self) -> None:
        maximum = (1 << 256) - 1
        words = [maximum.to_bytes(32, "big"), (7).to_bytes(32, "big")]
        value, next_counter = bounded_draw(10, 50, lambda counter: words[counter - 50])
        self.assertEqual((value, next_counter), (7, 52))
        self.assertNotEqual(maximum % 10, value)


class FakeAdapterAttacks(unittest.TestCase):
    def setUp(self) -> None:
        self.commands = [
            AdapterCommand(101, 1, ("cpuid-readback", "xcr0-readback"), "D1"),
            AdapterCommand(102, 2, ("clock-control",), "D1"),
        ]
        self.valid = [expected_observation(command) for command in self.commands]

    def assert_mutation_rejected(self, observations, expected_code: str) -> None:
        self.assertEqual(
            reject_code(validate_adapter_exchange, self.commands, observations),
            expected_code,
        )

    def test_exact_fake_adapter_observations_pass(self) -> None:
        validate_adapter_exchange(self.commands, self.valid)

    def test_omitted_capability_is_rejected(self) -> None:
        mutated = copy.deepcopy(self.valid)
        mutated[0]["capabilities"].pop()
        self.assert_mutation_rejected(mutated, "adapter-capabilities")

    def test_altered_request_id_is_rejected(self) -> None:
        mutated = copy.deepcopy(self.valid)
        mutated[0]["request_id"] = 999
        self.assert_mutation_rejected(mutated, "adapter-request-id")

    def test_reordered_observations_are_rejected(self) -> None:
        self.assert_mutation_rejected(list(reversed(self.valid)), "adapter-reordered")

    def test_profile_downgrade_is_rejected(self) -> None:
        mutated = copy.deepcopy(self.valid)
        mutated[0]["achieved_profile"] = "D0"
        self.assert_mutation_rejected(mutated, "adapter-profile-downgrade")

    def test_invented_fact_is_rejected(self) -> None:
        mutated = copy.deepcopy(self.valid)
        mutated[0]["host_timestamp"] = 123
        self.assert_mutation_rejected(mutated, "adapter-fact-shape")


class GateMutationAttacks(unittest.TestCase):
    def setUp(self) -> None:
        self.spec_path = ROOT / "shen/tests/adversarial/gate-spec.json"
        self.spec = json.loads(self.spec_path.read_text(encoding="utf-8"))

    def assert_gate_mutation_fails(self, spec) -> None:
        with self.assertRaises(GateFailure):
            verify_gate(ROOT, spec_override=spec)

    def test_unmodified_gate_inputs_pass(self) -> None:
        verify_gate(ROOT)

    def test_one_changed_fixture_fails(self) -> None:
        relative = "protocol/fixtures/v1/invalid/malformed-utf8.hex"
        with self.assertRaises(GateFailure):
            verify_gate(ROOT, fixture_override={relative: b"c329\n"})

    def test_one_changed_port_fails(self) -> None:
        mutated = copy.deepcopy(self.spec)
        mutated["required_ports"][0] = "shen-js"
        self.assert_gate_mutation_fails(mutated)

    def test_one_changed_vector_fails(self) -> None:
        mutated = copy.deepcopy(self.spec)
        output = mutated["prng_vector"]["output_hex"]
        mutated["prng_vector"]["output_hex"] = ("0" if output[0] != "0" else "1") + output[1:]
        self.assert_gate_mutation_fails(mutated)

    def test_one_changed_marker_fails(self) -> None:
        mutated = copy.deepcopy(self.spec)
        mutated["marker"] = MARKER + "-MUTATED"
        self.assert_gate_mutation_fails(mutated)


if __name__ == "__main__":
    unittest.main()
