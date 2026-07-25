"""Mutation tests for the fail-closed Bifrost conformance gate."""

from __future__ import annotations

import copy
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


def valid_result() -> tuple[list[str], dict[str, str], dict[str, object], dict[str, str]]:
    per_impl = {
        name: {
            "status": "PASS",
            "timeout": False,
            "rc": 0,
            "norm": GATE.PAYLOAD,
            "raw": f"{GATE.PAYLOAD}\n0\n",
        }
        for name in GATE.REQUIRED_IMPLS
    }
    return (
        list(GATE.REQUIRED_IMPLS),
        {},
        {"verdict": "PASS", "detail": "", "per_impl": per_impl},
        {name: GATE.KERNEL_VERSION for name in GATE.REQUIRED_IMPLS},
    )


class PinContractTests(unittest.TestCase):
    def test_reviewed_exact_pins_are_loaded(self) -> None:
        entries = GATE.load_and_validate_locks()
        self.assertEqual(
            {name: entry["commit"] for name, entry in entries.items()},
            GATE.EXPECTED_PINS,
        )
        self.assertFalse(entries["shenscript"]["required"])


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

    def test_reviewed_manifest_is_valid(self) -> None:
        case = GATE.validate_manifest(self.manifest)
        self.assertEqual(case["raw_fixture_sha256"], GATE.FIXTURE_SHA256)
        self.assertRegex(case["golden"], r"^[0-9a-f]+$")

    def test_missing_marker_is_rejected(self) -> None:
        self.assert_rejected(
            lambda value: value["cases"][0].pop("marker"),
            "missing.*marker",
        )

    def test_changed_golden_is_rejected(self) -> None:
        self.assert_rejected(
            lambda value: value["cases"][0].__setitem__("golden", "00"),
            "golden changed",
        )

    def test_changed_raw_fixture_is_rejected_even_with_old_sha(self) -> None:
        self.assert_rejected(
            lambda value: value["cases"][0].__setitem__("expr", "(+ 1 1)"),
            "raw fixture SHA-256 changed",
        )

    def test_self_rehashed_fixture_is_still_rejected(self) -> None:
        changed = copy.deepcopy(self.manifest)
        changed["cases"][0]["expr"] = "(+ 1 1)"
        changed["cases"][0]["raw_fixture_sha256"] = GATE.sha256_text("(+ 1 1)")
        with self.assertRaisesRegex(GATE.GateFailure, "raw fixture SHA-256 changed"):
            GATE.validate_manifest(changed)


class MatrixMutationTests(unittest.TestCase):
    def assert_rejected(self, mutation, message: str) -> None:
        values = list(valid_result())
        mutation(values)
        with self.assertRaisesRegex(GATE.GateFailure, message):
            GATE.validate_execution(*values)

    def test_reviewed_four_port_result_is_valid(self) -> None:
        values = valid_result()
        evidence = GATE.validate_execution(*values)
        self.assertEqual(set(evidence), set(GATE.REQUIRED_IMPLS))
        self.assertTrue(
            all(item["raw_payload_sha256"] == GATE.PAYLOAD_SHA256 for item in evidence.values())
        )

    def test_fewer_than_four_available_is_rejected(self) -> None:
        self.assert_rejected(
            lambda values: values[0].pop(),
            "fewer than four",
        )

    def test_required_skip_is_rejected(self) -> None:
        def mutate(values) -> None:
            values[1]["shen-rust"] = "launcher not found"

        self.assert_rejected(mutate, "skipped required ports")

    def test_skip_status_is_rejected(self) -> None:
        self.assert_rejected(
            lambda values: values[2]["per_impl"]["shen-lua"].__setitem__(
                "status", "SKIP"
            ),
            "reported SKIP",
        )

    def test_diverge_verdict_is_rejected(self) -> None:
        self.assert_rejected(
            lambda values: values[2].__setitem__("verdict", "DIVERGE"),
            "reported DIVERGE",
        )

    def test_diverge_port_status_is_rejected(self) -> None:
        self.assert_rejected(
            lambda values: values[2]["per_impl"]["shen-go"].__setitem__(
                "status", "DIVERGE"
            ),
            "reported DIVERGE",
        )

    def test_wrong_kernel_version_is_rejected(self) -> None:
        self.assert_rejected(
            lambda values: values[3].__setitem__("shen-cl", "41.1"),
            "expected 41.2",
        )

    def test_nonzero_launcher_exit_is_rejected(self) -> None:
        self.assert_rejected(
            lambda values: values[2]["per_impl"]["shen-go"].__setitem__("rc", 1),
            "exited with",
        )

    def test_normalized_only_payload_is_insufficient(self) -> None:
        self.assert_rejected(
            lambda values: values[2]["per_impl"]["shen-lua"].__setitem__(
                "raw", f"{GATE.PAYLOAD.upper()}\n0\n"
            ),
            "raw output.*lowercase-hex",
        )

    def test_duplicate_raw_payload_is_rejected(self) -> None:
        self.assert_rejected(
            lambda values: values[2]["per_impl"]["shen-rust"].__setitem__(
                "raw", f"{GATE.PAYLOAD}\n{GATE.PAYLOAD}\n0\n"
            ),
            "exactly one",
        )


class RequiredMatrixTests(unittest.TestCase):
    def test_exact_four_port_matrix_is_accepted(self) -> None:
        self.assertEqual(
            GATE.parse_required_impls(",".join(GATE.REQUIRED_IMPLS)),
            GATE.REQUIRED_IMPLS,
        )

    def test_fewer_than_four_requested_is_rejected(self) -> None:
        with self.assertRaisesRegex(GATE.GateFailure, "fewer than four"):
            GATE.parse_required_impls("shen-go,shen-lua,shen-cl")

    def test_substituted_fourth_port_is_rejected(self) -> None:
        with self.assertRaisesRegex(GATE.GateFailure, "exactly"):
            GATE.parse_required_impls("shen-go,shen-lua,shen-cl,shenscript")


if __name__ == "__main__":
    unittest.main()
