"""Dependency-free mutation tests for the strict Bifrost gate."""

from __future__ import annotations

import copy
import hashlib
import importlib.machinery
import importlib.util
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LOADER = importlib.machinery.SourceFileLoader(
    "urdr_bifrost_gate", str(ROOT / "scripts" / "bifrost-gate")
)
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC is not None
GATE = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(GATE)


def semantic_outputs() -> dict[str, bytes]:
    canonical = [
        *(f"valid|valid-{index}|{index:02x}" for index in range(20)),
        *(f"reject|reject-{index}|stable-error" for index in range(32)),
        "ALL PASS",
    ]
    prng = [
        "PASS integer",
        "PASS named-stream",
        "urdr-prng: 2/2 passed",
        "ALL PASS",
    ]
    world = [
        "WORLD-TRACE abcd",
        "WORLD TESTS: 11/11 PASS",
        "ALL PASS",
    ]
    return {
        "canonical-values": ("\n".join(canonical) + "\n").encode("ascii"),
        "named-prng": ("\n".join(prng) + "\n").encode("ascii"),
        "world-reducer": ("\n".join(world) + "\n").encode("ascii"),
    }


def valid_execution():
    outputs = semantic_outputs()
    case_results = {}
    for case_name, output in outputs.items():
        case_results[case_name] = {
            "verdict": "PASS",
            "detail": "",
            "per_impl": {
                name: {
                    "status": "PASS",
                    "timeout": False,
                    "rc": 0,
                    "norm": output.decode("ascii").strip(),
                    "raw": output.decode("ascii"),
                }
                for name in GATE.REQUIRED_IMPLS
            },
        }
    return (
        list(GATE.REQUIRED_IMPLS),
        {},
        case_results,
        {name: GATE.KERNEL_VERSION for name in GATE.REQUIRED_IMPLS},
        lambda path: outputs["world-reducer"],
        {
            name: hashlib.sha256(output).hexdigest()
            for name, output in outputs.items()
        },
    )


class PinContractTests(unittest.TestCase):
    def test_reviewed_exact_pins_are_loaded(self) -> None:
        entries = GATE.load_and_validate_locks()
        self.assertEqual(
            {name: entry["commit"] for name, entry in entries.items()},
            GATE.EXPECTED_PINS,
        )
        self.assertFalse(entries["shenscript"]["required"])

    def test_altered_checkout_commit_is_rejected(self) -> None:
        with self.assertRaisesRegex(GATE.GateFailure, "expected"):
            GATE.validate_checkout_commit("shen-go", "0" * 40)


class ManifestMutationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest = json.loads(
            (ROOT / "bifrost.suite.json").read_text(encoding="utf-8")
        )

    def assert_rejected(self, mutation, message: str) -> None:
        changed = copy.deepcopy(self.manifest)
        mutation(changed)
        with self.assertRaisesRegex(GATE.GateFailure, message):
            GATE.validate_manifest(changed)

    def test_reviewed_manifest_is_valid_and_has_no_substitute_case(self) -> None:
        cases = GATE.validate_manifest(self.manifest)
        self.assertEqual(
            [case["name"] for case in cases],
            list(GATE.CASE_ORDER),
        )
        self.assertNotIn("temporary", json.dumps(self.manifest).lower())

    def test_missing_marker_is_rejected(self) -> None:
        self.assert_rejected(
            lambda value: value["cases"][1].pop("marker"),
            "missing.*marker",
        )

    def test_changed_marker_is_rejected(self) -> None:
        self.assert_rejected(
            lambda value: value["cases"][0].__setitem__("marker", "PASS"),
            "marker changed",
        )

    def test_changed_program_fixture_sha_is_rejected(self) -> None:
        self.assert_rejected(
            lambda value: value["cases"][2].__setitem__(
                "program_sha256", "0" * 64
            ),
            "program_sha256 changed",
        )

    def test_removing_world_case_is_rejected(self) -> None:
        self.assert_rejected(
            lambda value: value["cases"].pop(),
            "canonical, PRNG, and world",
        )


class FixtureManifestMutationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = b"normative fixture\n"
        digest = hashlib.sha256(self.fixture).hexdigest()
        self.manifest = f"{digest}  fixture.bin\n".encode("ascii")
        self.manifest_digest = hashlib.sha256(self.manifest).hexdigest()

    def test_exact_fixture_manifest_is_accepted(self) -> None:
        entries = GATE.validate_sha_manifest_data(
            self.manifest,
            {"fixture.bin": self.fixture},
            self.manifest_digest,
        )
        self.assertEqual(entries, {"fixture.bin": hashlib.sha256(self.fixture).hexdigest()})

    def test_altered_fixture_is_rejected(self) -> None:
        with self.assertRaisesRegex(GATE.GateFailure, "fixture SHA-256 mismatch"):
            GATE.validate_sha_manifest_data(
                self.manifest,
                {"fixture.bin": self.fixture + b"changed"},
                self.manifest_digest,
            )

    def test_rehashed_manifest_is_rejected(self) -> None:
        changed_fixture = self.fixture + b"changed"
        changed_manifest = (
            f"{hashlib.sha256(changed_fixture).hexdigest()}  fixture.bin\n"
        ).encode("ascii")
        with self.assertRaisesRegex(GATE.GateFailure, "SHA256SUMS changed"):
            GATE.validate_sha_manifest_data(
                changed_manifest,
                {"fixture.bin": changed_fixture},
                self.manifest_digest,
            )


class MatrixMutationTests(unittest.TestCase):
    def assert_rejected(self, mutation, message: str) -> None:
        values = list(valid_execution())
        mutation(values)
        with self.assertRaisesRegex(GATE.GateFailure, message):
            GATE.validate_execution(*values)

    def test_reviewed_matrix_is_valid(self) -> None:
        evidence = GATE.validate_execution(*valid_execution())
        self.assertEqual(set(evidence), set(GATE.CASE_ORDER))
        for case in evidence.values():
            self.assertEqual(case["bifrost_verdict"], "PASS")

    def test_altered_port_matrix_is_rejected(self) -> None:
        self.assert_rejected(
            lambda values: values[0].pop(),
            "fewer than four",
        )

    def test_missing_port_is_rejected(self) -> None:
        self.assert_rejected(
            lambda values: values[1].__setitem__("shen-rust", "missing"),
            "skipped required ports",
        )

    def test_skip_is_rejected(self) -> None:
        self.assert_rejected(
            lambda values: values[2]["named-prng"]["per_impl"]["shen-lua"].__setitem__(
                "status", "SKIP"
            ),
            "reported SKIP",
        )

    def test_diverge_is_rejected(self) -> None:
        self.assert_rejected(
            lambda values: values[2]["canonical-values"].__setitem__(
                "verdict", "DIVERGE"
            ),
            "reported DIVERGE",
        )

    def test_wrong_live_kernel_version_is_rejected(self) -> None:
        self.assert_rejected(
            lambda values: values[3].__setitem__("shen-cl", "41.1"),
            "expected 41.2",
        )

    def test_missing_raw_marker_is_rejected(self) -> None:
        self.assert_rejected(
            lambda values: values[2]["named-prng"]["per_impl"]["shen-go"].__setitem__(
                "raw",
                values[2]["named-prng"]["per_impl"]["shen-go"]["raw"].replace(
                    "ALL PASS\n", ""
                ),
            ),
            "raw marker is missing",
        )

    def test_altered_raw_output_is_rejected(self) -> None:
        self.assert_rejected(
            lambda values: values[2]["world-reducer"]["per_impl"][
                "shen-rust"
            ].__setitem__(
                "raw",
                values[2]["world-reducer"]["per_impl"]["shen-rust"]["raw"].replace(
                    "abcd", "abce"
                ),
            ),
            "raw direct semantic outputs disagree",
        )

    def test_agreed_but_altered_output_is_rejected_by_golden_sha(self) -> None:
        values = list(valid_execution())
        for port in values[2]["world-reducer"]["per_impl"].values():
            port["raw"] = port["raw"].replace("abcd", "abce")
        with self.assertRaisesRegex(GATE.GateFailure, "differs from golden SHA"):
            GATE.validate_execution(*values)

    def test_changed_world_golden_is_rejected(self) -> None:
        values = list(valid_execution())
        values[4] = lambda path: b"changed golden\n"
        with self.assertRaisesRegex(GATE.GateFailure, "differs from golden"):
            GATE.validate_execution(*values)


class RequiredMatrixTests(unittest.TestCase):
    def test_exact_four_port_matrix_is_accepted(self) -> None:
        self.assertEqual(
            GATE.parse_required_impls(",".join(GATE.REQUIRED_IMPLS)),
            GATE.REQUIRED_IMPLS,
        )

    def test_fewer_than_four_requested_is_rejected(self) -> None:
        with self.assertRaisesRegex(GATE.GateFailure, "fewer than four"):
            GATE.parse_required_impls("shen-go,shen-lua,shen-cl")

    def test_optional_port_cannot_replace_required_port(self) -> None:
        with self.assertRaisesRegex(GATE.GateFailure, "exactly"):
            GATE.parse_required_impls("shen-go,shen-lua,shen-cl,shenscript")


if __name__ == "__main__":
    unittest.main()
