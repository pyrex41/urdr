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
    M1_MARKER,
    MODELED_WORLD_ONLY,
    SPEC_SEMANTICS_ONLY,
    AdapterCommand,
    GateFailure,
    NetpolPortRef,
    Reject,
    TranscriptEntry,
    all_chunkings,
    assert_modeled_world_only,
    bounded_draw,
    canonical_event_order,
    canonical_fields,
    certificate_entropy_clean,
    certificate_markers,
    certificate_profile,
    certificate_status,
    classify_transcript_attack,
    component_check_step,
    evaluate_property_declaration,
    expected_observation,
    forge_host_log_verdict,
    load_scenario_cases,
    nk_drop,
    nk_equivalent,
    nk_id,
    nk_reachable,
    nk_seq,
    nk_set,
    nk_test,
    nk_union,
    parse_integer,
    prng_word,
    reduce_prototype,
    reject_host_network_pod,
    reject_netpol_unmodeled,
    reject_non_abstract_certification,
    rejection_marker,
    render_integer,
    resolve_netpol_ports,
    scenario_effect_guard,
    validate_adapter_exchange,
    validate_scenario_keys,
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


def reject_code(callable_, *arguments, **kwargs) -> str:
    with unittest.TestCase().assertRaises(Reject) as caught:
        callable_(*arguments, **kwargs)
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

    def test_one_changed_m1_fixture_digest_fails(self) -> None:
        relative = "protocol/fixtures/v1/scenario/invalid/unknown-field.frame"
        mutated_bytes = (ROOT / relative).read_bytes() + b"\x00"
        with self.assertRaises(GateFailure):
            verify_gate(ROOT, fixture_override={relative: mutated_bytes})

    def test_one_changed_m1_marker_fails(self) -> None:
        mutated = copy.deepcopy(self.spec)
        mutated["m1_marker"] = M1_MARKER + "-MUTATED"
        self.assert_gate_mutation_fails(mutated)

    def test_one_changed_netpol_reject_fixture_fails(self) -> None:
        relative = (
            "protocol/fixtures/v1/netpol/expect/reject-named-port-unresolved.frame"
        )
        with self.assertRaises(GateFailure):
            verify_gate(ROOT, fixture_override={relative: b"0:()," })


# ---------------------------------------------------------------------------
# M1 attack surfaces (already-merged scenario / NetKAT / netpol / properties
# / replay / certificate / component). Fail-closed only; never skip.
# ---------------------------------------------------------------------------


class ScenarioAttacks(unittest.TestCase):
    """Invalid scenario frames reject before any world effect."""

    def setUp(self) -> None:
        self.valid_keys = [
            "budget",
            "components",
            "determinism",
            "faults",
            "header-vocabulary",
            "observations",
            "properties",
            "seed",
            "topology",
            "version",
        ]

    def test_valid_key_set_is_accepted(self) -> None:
        validate_scenario_keys(self.valid_keys)

    def test_unknown_key_is_rejected(self) -> None:
        # `workloads` is the high-value unknown used by the fixture corpus.
        keys = self.valid_keys + ["workloads"]
        keys = sorted(keys, key=lambda item: item.encode("utf-8"))
        self.assertEqual(reject_code(validate_scenario_keys, keys), "scenario-unknown-field")

    def test_missing_required_key_is_rejected(self) -> None:
        keys = [key for key in self.valid_keys if key != "seed"]
        self.assertEqual(
            reject_code(validate_scenario_keys, keys), "scenario-missing-field"
        )

    def test_reordered_keys_are_rejected(self) -> None:
        keys = list(self.valid_keys)
        # Swap two keys so the sequence is not ascending by UTF-8.
        version_index = keys.index("version")
        seed_index = keys.index("seed")
        keys[version_index], keys[seed_index] = keys[seed_index], keys[version_index]
        self.assertEqual(reject_code(validate_scenario_keys, keys), "record-order")

    def test_duplicate_key_is_rejected(self) -> None:
        keys = list(self.valid_keys) + ["seed"]
        keys = sorted(keys, key=lambda item: item.encode("utf-8"))
        self.assertEqual(reject_code(validate_scenario_keys, keys), "record-duplicate")

    def test_rejection_happens_before_world_effect(self) -> None:
        effects: list[str] = []

        def effect() -> None:
            effects.append("applied")

        scenario_effect_guard(["version"], effect)  # missing keys → reject
        self.assertEqual(effects, [])
        scenario_effect_guard(self.valid_keys, effect)
        self.assertEqual(effects, ["applied"])

    def test_fixture_corpus_pins_stable_reject_codes(self) -> None:
        """Every X row in cases.tsv names a stable code; frames exist on disk."""

        rows = load_scenario_cases(ROOT)
        invalid = [row for row in rows if row[0] == "X"]
        self.assertGreaterEqual(len(invalid), 20)
        for kind, name, relative, code in invalid:
            with self.subTest(name=name):
                self.assertEqual(kind, "X")
                self.assertTrue(code, msg=f"{name}: missing stable code")
                path = ROOT / "protocol/fixtures/v1/scenario" / relative
                self.assertTrue(path.is_file(), msg=f"{name}: missing {relative}")
                self.assertGreater(path.stat().st_size, 0)

    def test_high_value_invalid_fixtures_decode_or_frame_reject(self) -> None:
        """Record-order/duplicate fail at the codec; unknown/missing decode
        as records that the scenario oracle must still refuse."""

        from adapters.common.uap.codec import CanonicalCodec, CodecError, Record

        codec = CanonicalCodec()
        order = (
            ROOT / "protocol/fixtures/v1/scenario/invalid/record-order.frame"
        ).read_bytes()
        with self.assertRaises(CodecError) as caught:
            codec.decode_frame(order)
        self.assertEqual(caught.exception.code, "record-order")

        unknown = (
            ROOT / "protocol/fixtures/v1/scenario/invalid/unknown-field.frame"
        ).read_bytes()
        value = codec.decode_frame(unknown)
        self.assertIsInstance(value, Record)
        keys = [key.decode("ascii") for key, _ in value.fields]
        self.assertEqual(
            reject_code(validate_scenario_keys, keys), "scenario-unknown-field"
        )

        missing = (
            ROOT / "protocol/fixtures/v1/scenario/invalid/missing-field.frame"
        ).read_bytes()
        value = codec.decode_frame(missing)
        keys = [key.decode("ascii") for key, _ in value.fields]
        self.assertEqual(
            reject_code(validate_scenario_keys, keys), "scenario-missing-field"
        )


class NetkatAttacks(unittest.TestCase):
    """Policy/field/value mutations flip decision oracles; invalids reject."""

    def setUp(self) -> None:
        self.fields = {"dst": (1, 2), "src": (1, 2)}

    def test_equivalent_policies_agree(self) -> None:
        left = nk_seq(nk_test("dst", 1), nk_set("src", 2))
        self.assertTrue(nk_equivalent(self.fields, left, left))

    def test_value_mutation_flips_equivalence(self) -> None:
        base = nk_seq(nk_test("dst", 1), nk_set("src", 2))
        mutated = nk_seq(nk_test("dst", 2), nk_set("src", 2))
        self.assertTrue(nk_equivalent(self.fields, base, base))
        self.assertFalse(nk_equivalent(self.fields, base, mutated))

    def test_field_mutation_flips_equivalence(self) -> None:
        base = nk_seq(nk_test("dst", 1), nk_set("src", 2))
        mutated = nk_seq(nk_test("src", 1), nk_set("src", 2))
        self.assertFalse(nk_equivalent(self.fields, base, mutated))

    def test_operator_mutation_flips_equivalence(self) -> None:
        base = nk_seq(nk_test("dst", 1), nk_set("src", 2))
        mutated = nk_union(nk_test("dst", 1), nk_set("src", 2))
        self.assertFalse(nk_equivalent(self.fields, base, mutated))

    def test_reachability_value_mutation_flips_verdict(self) -> None:
        policy = nk_seq(nk_test("src", 1), nk_set("dst", 2))
        ingress = {"dst": 1, "src": 1}
        self.assertTrue(nk_reachable(self.fields, ingress, policy, {"dst": 2, "src": 1}))
        self.assertFalse(
            nk_reachable(self.fields, ingress, policy, {"dst": 1, "src": 1})
        )

    def test_reachability_policy_mutation_flips_verdict(self) -> None:
        open_policy = nk_id()
        closed_policy = nk_drop()
        packet = {"dst": 1, "src": 1}
        self.assertTrue(nk_reachable(self.fields, packet, open_policy, packet))
        self.assertFalse(nk_reachable(self.fields, packet, closed_policy, packet))

    def test_unknown_field_in_policy_is_rejected(self) -> None:
        from oracles import nk_check_term

        term = nk_test("ttl", 1)
        self.assertEqual(
            reject_code(nk_check_term, self.fields, term), "term-field-unknown"
        )

    def test_unknown_value_in_policy_is_rejected(self) -> None:
        from oracles import nk_check_term

        term = nk_test("dst", 99)
        self.assertEqual(
            reject_code(nk_check_term, self.fields, term), "term-value-unknown"
        )

    def test_unknown_term_head_is_rejected(self) -> None:
        from oracles import nk_check_term

        self.assertEqual(
            reject_code(nk_check_term, self.fields, ("frob",)), "term-head"
        )

    def test_neg_of_set_is_rejected(self) -> None:
        from oracles import nk_check_term, nk_neg

        term = nk_neg(nk_set("dst", 1))
        self.assertEqual(
            reject_code(nk_check_term, self.fields, term), "term-neg-nonpredicate"
        )

    def test_invalid_policy_fixture_pins_term_head(self) -> None:
        from adapters.common.uap.codec import CanonicalCodec, Symbol

        frame = (
            ROOT / "protocol/fixtures/v1/netkat/cases/invalid-policy-head.frame"
        ).read_bytes()
        value = CanonicalCodec().decode_frame(frame)
        fields = {key.decode("ascii"): val for key, val in value.fields}
        self.assertEqual(fields["expect"], Symbol(ascii=b"term-head"))
        self.assertEqual(fields["kind"], Symbol(ascii=b"invalid-policy"))


class NetpolAttacks(unittest.TestCase):
    """Unresolvable named ports and out-of-vocab constructs fail closed."""

    def setUp(self) -> None:
        self.declared_ports = (80, 443, 6379)
        self.named_ports = {"http": 80, "https": 443, "redis": 6379}

    def test_named_port_resolves_when_declared(self) -> None:
        ports = resolve_netpol_ports(
            NetpolPortRef(named="redis"),
            declared_ports=self.declared_ports,
            named_ports=self.named_ports,
        )
        self.assertEqual(ports, (6379,))

    def test_unresolved_named_port_is_rejected(self) -> None:
        self.assertEqual(
            reject_code(
                resolve_netpol_ports,
                NetpolPortRef(named="grpc"),
                declared_ports=self.declared_ports,
                named_ports=self.named_ports,
            ),
            "named-port-unresolved",
        )

    def test_port_out_of_vocabulary_is_rejected(self) -> None:
        self.assertEqual(
            reject_code(
                resolve_netpol_ports,
                NetpolPortRef(port=22),
                declared_ports=self.declared_ports,
                named_ports=self.named_ports,
            ),
            "port-out-of-vocabulary",
        )

    def test_unknown_protocol_is_rejected(self) -> None:
        self.assertEqual(
            reject_code(
                resolve_netpol_ports,
                NetpolPortRef(protocol="ESP", port=80),
                declared_ports=self.declared_ports,
                named_ports=self.named_ports,
            ),
            "protocol-unknown",
        )

    def test_end_port_range_inverted_is_rejected(self) -> None:
        self.assertEqual(
            reject_code(
                resolve_netpol_ports,
                NetpolPortRef(port=443, end_port=80),
                declared_ports=self.declared_ports,
                named_ports=self.named_ports,
            ),
            "end-port-range",
        )

    def test_unmodeled_manifest_field_is_rejected(self) -> None:
        self.assertEqual(
            reject_code(
                reject_netpol_unmodeled,
                ["apiVersion", "kind", "spec", "status"],
                ["apiVersion", "kind", "metadata", "spec"],
            ),
            "manifest-unmodeled-field",
        )

    def test_host_network_pod_under_policy_is_rejected(self) -> None:
        self.assertEqual(
            reject_code(reject_host_network_pod, True, True),
            "host-network-pod-under-policy",
        )
        reject_host_network_pod(False, True)
        reject_host_network_pod(True, False)

    def test_expect_fixtures_pin_stable_error_symbols(self) -> None:
        from adapters.common.uap.codec import CanonicalCodec, Symbol

        codec = CanonicalCodec()
        cases = {
            "reject-named-port-unresolved": "named-port-unresolved",
            "reject-port-out-of-vocabulary": "port-out-of-vocabulary",
            "reject-unmodeled-field": "manifest-unmodeled-field",
            "reject-host-network": "host-network-pod-under-policy",
        }
        for name, code in cases.items():
            with self.subTest(name=name):
                frame = (
                    ROOT / f"protocol/fixtures/v1/netpol/expect/{name}.frame"
                ).read_bytes()
                value = codec.decode_frame(frame)
                fields = dict(value.fields)
                self.assertEqual(fields[b"error"], Symbol(ascii=code.encode("ascii")))


class PropertyAttacks(unittest.TestCase):
    """Verdict tampering / host-log input rejected; vacuous/empty pinned."""

    def test_host_log_prose_is_rejected(self) -> None:
        self.assertEqual(
            reject_code(forge_host_log_verdict, "kernel panic at 0xdead"),
            "properties-host-log-forbidden",
        )

    def test_trace_with_host_log_field_is_rejected(self) -> None:
        trace = [{"id": 1, "time": 0, "kind": "fact", "host_log": "boom"}]
        self.assertEqual(
            reject_code(
                evaluate_property_declaration,
                "temporal",
                "p0",
                trace=trace,
                kind="never",
            ),
            "properties-host-log-forbidden",
        )

    def test_m3_log_class_is_rejected_in_m1(self) -> None:
        self.assertEqual(
            reject_code(
                evaluate_property_declaration,
                "log",
                "p-log",
                trace=[],
                kind="never",
            ),
            "properties-class-unsupported-in-m1",
        )

    def test_crash_class_is_rejected_in_m1(self) -> None:
        self.assertEqual(
            reject_code(
                evaluate_property_declaration,
                "crash",
                "p-crash",
                trace=[],
                kind="never",
            ),
            "properties-class-unsupported-in-m1",
        )

    def test_empty_stream_never_passes(self) -> None:
        verdict = evaluate_property_declaration(
            "temporal", "t-never", trace=[], kind="never"
        )
        self.assertEqual((verdict.result, verdict.witness), ("PASS", "no-witness"))

    def test_empty_stream_liveness_fails(self) -> None:
        verdict = evaluate_property_declaration(
            "liveness", "l-empty", trace=[], kind="liveness"
        )
        self.assertEqual((verdict.result, verdict.witness), ("FAIL", "no-witness"))

    def test_vacuous_antecedent_is_pinned(self) -> None:
        trace = [
            {"id": 0, "time": 0, "kind": "fact", "name": "noise"},
            {"id": 1, "time": 1, "kind": "fact", "name": "noise"},
        ]
        verdict = evaluate_property_declaration(
            "temporal", "t-vacuous", trace=trace, kind="always-eventually"
        )
        self.assertEqual((verdict.result, verdict.witness), ("PASS", "vacuous"))

    def test_non_vacuous_antecedent_without_consequent_fails(self) -> None:
        trace = [{"id": 0, "time": 0, "kind": "fact", "name": "A"}]
        verdict = evaluate_property_declaration(
            "temporal", "t-ae", trace=trace, kind="always-eventually"
        )
        self.assertEqual(verdict.result, "FAIL")


class ReplayCertificateAttacks(unittest.TestCase):
    """Transcript attacks name divergence codes; entropy firewall holds."""

    def setUp(self) -> None:
        self.recorded = [
            TranscriptEntry(digest=b"\x01" * 32, sequence=0),
            TranscriptEntry(digest=b"\x02" * 32, sequence=1),
            TranscriptEntry(digest=b"\x03" * 32, sequence=2),
            TranscriptEntry(digest=b"\x04" * 32, sequence=3),
        ]

    def test_exact_transcript_verifies(self) -> None:
        self.assertEqual(
            classify_transcript_attack(self.recorded, list(self.recorded)), "verified"
        )

    def test_withholding_is_truncated(self) -> None:
        actual = self.recorded[:-1]
        self.assertEqual(
            classify_transcript_attack(self.recorded, actual),
            "replay-transcript-truncated",
        )

    def test_extension_is_extended(self) -> None:
        actual = list(self.recorded) + [
            TranscriptEntry(digest=b"\xff" * 32, sequence=4)
        ]
        self.assertEqual(
            classify_transcript_attack(self.recorded, actual),
            "replay-transcript-extended",
        )

    def test_reorder_is_reordered_not_tampered(self) -> None:
        actual = list(reversed(self.recorded))
        self.assertEqual(
            classify_transcript_attack(self.recorded, actual),
            "replay-transcript-reordered",
        )

    def test_tamper_is_tampered_not_reordered(self) -> None:
        actual = list(self.recorded)
        actual[2] = TranscriptEntry(digest=b"\xab" * 32, sequence=2)
        self.assertEqual(
            classify_transcript_attack(self.recorded, actual),
            "replay-transcript-tampered",
        )

    def test_modeled_world_only_is_unconditional(self) -> None:
        markers = certificate_markers([])
        self.assertEqual(markers, (MODELED_WORLD_ONLY,))
        assert_modeled_world_only(markers)

    def test_spec_semantics_only_is_derived_from_baseline(self) -> None:
        markers = certificate_markers([{"marker": SPEC_SEMANTICS_ONLY}])
        self.assertEqual(markers, (MODELED_WORLD_ONLY, SPEC_SEMANTICS_ONLY))

    def test_missing_modeled_world_only_is_rejected(self) -> None:
        self.assertEqual(
            reject_code(assert_modeled_world_only, (SPEC_SEMANTICS_ONLY,)),
            "certificate-missing-modeled-world-only",
        )

    def test_non_abstract_entropy_voids_certificate(self) -> None:
        clean = {"pure": 2, "modeled": 2, "recorded": 0, "uncontrolled": 0, "forbidden": 0}
        self.assertTrue(certificate_entropy_clean(clean))
        dirty = dict(clean)
        dirty["uncontrolled"] = 1
        self.assertFalse(certificate_entropy_clean(dirty))
        self.assertEqual(
            reject_code(reject_non_abstract_certification, dirty),
            "certificate-entropy-firewall",
        )

    def test_forbidden_entropy_class_cannot_certify(self) -> None:
        counts = {"pure": 0, "modeled": 0, "forbidden": 1}
        self.assertEqual(
            reject_code(reject_non_abstract_certification, counts),
            "certificate-entropy-firewall",
        )
        self.assertEqual(
            certificate_profile(verified=True, clean=False), "uncertified"
        )

    def test_status_precedence_diverged_over_uncertified(self) -> None:
        self.assertEqual(
            certificate_status(
                verified=False,
                clean=True,
                divergence_code="replay-event-divergence",
                any_fail=False,
            ),
            "DIVERGED",
        )
        self.assertEqual(
            certificate_status(
                verified=False,
                clean=True,
                divergence_code="replay-transcript-tampered",
                any_fail=False,
            ),
            "UNCERTIFIED",
        )
        self.assertEqual(
            certificate_status(
                verified=True, clean=True, divergence_code=None, any_fail=True
            ),
            "FAIL",
        )
        self.assertEqual(
            certificate_status(
                verified=True, clean=True, divergence_code=None, any_fail=False
            ),
            "PASS",
        )


class ComponentInterfaceAttacks(unittest.TestCase):
    """Misbehaving component patterns still fail closed."""

    def test_well_behaved_step_is_accepted(self) -> None:
        component_check_step(
            {"count": 1},
            [{"name": "tick", "value": {"count": 1}}],
            [{"purpose": "delay", "alternatives": ["fast", "slow"]}],
        )

    def test_emitting_event_authority_is_rejected(self) -> None:
        self.assertEqual(
            reject_code(
                component_check_step,
                {"count": 1},
                [{"name": "tick", "value": {"event": {"payload": 1}}}],
                [],
            ),
            "component-fact-authority",
        )

    def test_inventing_event_id_in_state_is_rejected(self) -> None:
        self.assertEqual(
            reject_code(
                component_check_step,
                {"event-id": 99, "count": 1},
                [],
                [],
            ),
            "component-state-authority",
        )

    def test_claiming_time_advance_is_rejected(self) -> None:
        self.assertEqual(
            reject_code(
                component_check_step,
                {"count": 1, "time": 100},
                [],
                [],
            ),
            "component-state-authority",
        )

    def test_reserved_choice_purpose_is_rejected(self) -> None:
        self.assertEqual(
            reject_code(
                component_check_step,
                {"count": 0},
                [],
                [{"purpose": "seed", "alternatives": ["a"]}],
            ),
            "component-choice-purpose",
        )

    def test_unordered_choices_are_rejected(self) -> None:
        self.assertEqual(
            reject_code(
                component_check_step,
                {"count": 0},
                [],
                [
                    {"purpose": "zeta", "alternatives": ["a"]},
                    {"purpose": "alpha", "alternatives": ["b"]},
                ],
            ),
            "component-choice-order",
        )

    def test_empty_alternatives_are_rejected(self) -> None:
        self.assertEqual(
            reject_code(
                component_check_step,
                {"count": 0},
                [],
                [{"purpose": "delay", "alternatives": []}],
            ),
            "component-choice-empty",
        )


if __name__ == "__main__":
    unittest.main()
