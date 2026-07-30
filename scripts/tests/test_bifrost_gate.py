"""Dependency-free mutation tests for the strict Bifrost gate."""

from __future__ import annotations

import copy
import hashlib
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import tempfile
import types
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
        "WORLD-COMPONENT-TRACE ef01",
        "WORLD TESTS: 22/22 PASS",
        "ALL PASS",
    ]
    scenario = [
        "profile|m0|4096|256|32",
        "accept|minimal",
        "reject|self-link|scenario-self-link",
        "urdr-scenario: 3/3 passed",
        "ALL PASS",
    ]
    netkat = [
        "NETKAT-OK|eval-drop",
        "NETKAT-REJECT|bad-arity|term-arity",
        "NETKAT CASES: 2",
        "ALL PASS",
    ]
    netpol = [
        "NETPOL-OK|default-deny",
        "NETPOL-TERM|default-deny|0",
        "NETPOL MARKER: spec-semantics-only",
        "NETPOL CASES: 1",
        "ALL PASS",
    ]
    models = [
        "MODELS-OK|net-send",
        "MODELS-DIGEST|net-send|ab12",
        "MODELS CASES: 1",
        "ALL PASS",
    ]
    properties = [
        "PROP|liveness-late|liveness|FAIL|witness",
        "PROP|invariant-empty|invariant|PASS|no-witness",
        "PROPERTIES CASES: 2",
        "ALL PASS",
    ]
    replay = [
        "EL|e2e|1a2b",
        "PROP|l-missing|FAIL|no-witness",
        "LOOP|100|feed",
        "REPLAY CASES: 3",
        "ALL PASS",
    ]
    explore = [
        "CHOICE|kind|fault",
        "EXPLORE|baseline|found|ab12",
        "SHRINK|minimize|14|1|true",
        "MUT|drop-fault|rejected",
        "EXPLORE-SHRINK CASES: 4",
        "ALL PASS",
    ]
    grammar = [
        "SEED|a|true|ab12",
        "REPLAY|withhold|replay-transcript-truncated",
        "MUT|empty-sizes|rejected",
        "GRAMMAR CASES: 3",
        "ALL PASS",
    ]
    integration = [
        "DEMO|1|explore|found|ab12|inject=true",
        "DEMO|2|shrink|before=14|after=1|persist=true",
        "DEMO|6|certificate|status=PASS|markers=modeled-world-only",
        "INTEGRATION CASES: 3",
        "ALL PASS",
    ]
    return {
        "canonical-values": ("\n".join(canonical) + "\n").encode("ascii"),
        "named-prng": ("\n".join(prng) + "\n").encode("ascii"),
        "world-reducer": ("\n".join(world) + "\n").encode("ascii"),
        "scenario-parse": ("\n".join(scenario) + "\n").encode("ascii"),
        "netkat-core": ("\n".join(netkat) + "\n").encode("ascii"),
        "netpol-compile": ("\n".join(netpol) + "\n").encode("ascii"),
        "models-conformance": ("\n".join(models) + "\n").encode("ascii"),
        "property-verdicts": ("\n".join(properties) + "\n").encode("ascii"),
        "replay-certificate": ("\n".join(replay) + "\n").encode("ascii"),
        "explore-shrink": ("\n".join(explore) + "\n").encode("ascii"),
        "scenario-grammar": ("\n".join(grammar) + "\n").encode("ascii"),
        "m1-integration": ("\n".join(integration) + "\n").encode("ascii"),
    }


def valid_execution(required: tuple[str, ...] | None = None):
    ports = required if required is not None else GATE.REQUIRED_IMPLS
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
                for name in ports
            },
        }
    return (
        list(ports),
        {},
        case_results,
        {name: GATE.KERNEL_VERSION for name in ports},
        lambda path: {
            "shen/tests/netkat/golden.txt": outputs["netkat-core"],
            "shen/tests/netpol/golden.txt": outputs["netpol-compile"],
            "shen/tests/models/golden.txt": outputs["models-conformance"],
            "shen/tests/properties/golden.txt": outputs["property-verdicts"],
            "shen/tests/replay/golden.txt": outputs["replay-certificate"],
            "shen/tests/search/golden.txt": outputs["explore-shrink"],
            "shen/tests/search/grammar/golden.txt": outputs["scenario-grammar"],
            "shen/tests/integration/golden.txt": outputs["m1-integration"],
        }.get(path, outputs["world-reducer"]),
        {
            name: hashlib.sha256(output).hexdigest()
            for name, output in outputs.items()
        },
        ports,
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


class LauncherProvenanceTests(unittest.TestCase):
    """A verified pin bound the source; the binary that ran was unchecked.

    `make bootstrap` updates a checkout in place and leaves build output alone,
    so a launcher built before a repin survived it. A four-port PASS was once
    recorded against a shen-go binary older than its own pin. Each of these
    cases must fail closed.
    """

    def setUp(self) -> None:
        self.checkout = Path(self.enterContext(tempfile.TemporaryDirectory()))
        subprocess.run(
            ["git", "init", "-q"], cwd=self.checkout, check=True
        )
        subprocess.run(
            ["git", "-c", "user.email=t@t", "-c", "user.name=t",
             "commit", "-q", "--allow-empty", "-m", "base"],
            cwd=self.checkout,
            check=True,
        )
        self.head = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=self.checkout,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        ).stdout.strip()
        self.stamp = self.checkout / GATE.BUILD_STAMP

    def test_stamp_matching_head_is_accepted(self) -> None:
        self.stamp.write_text(f"{self.head}\n", encoding="utf-8")
        self.assertEqual(
            GATE.verify_launcher_provenance("shen-go", self.checkout),
            self.head,
        )

    def test_stale_stamp_is_rejected(self) -> None:
        # The exact shape that went undetected: a real, older commit.
        self.stamp.write_text(f"{'a' * 40}\n", encoding="utf-8")
        with self.assertRaisesRegex(GATE.GateFailure, "was built from"):
            GATE.verify_launcher_provenance("shen-go", self.checkout)

    def test_missing_stamp_is_rejected(self) -> None:
        with self.assertRaisesRegex(GATE.GateFailure, "no build stamp"):
            GATE.verify_launcher_provenance("shen-go", self.checkout)

    def test_malformed_stamp_is_rejected(self) -> None:
        self.stamp.write_text("not-a-sha\n", encoding="utf-8")
        with self.assertRaisesRegex(GATE.GateFailure, "not a full commit sha"):
            GATE.verify_launcher_provenance("shen-go", self.checkout)


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
            "available matrix differs from required ports",
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

    def test_single_port_development_matrix_is_accepted(self) -> None:
        self.assertEqual(GATE.parse_required_impls("shen-cl"), ("shen-cl",))

    def test_subset_is_reordered_to_reviewed_port_order(self) -> None:
        self.assertEqual(
            GATE.parse_required_impls("shen-cl,shen-go"),
            ("shen-go", "shen-cl"),
        )

    def test_empty_matrix_is_rejected(self) -> None:
        with self.assertRaisesRegex(GATE.GateFailure, "empty"):
            GATE.parse_required_impls("")

    def test_duplicate_ports_are_rejected(self) -> None:
        with self.assertRaisesRegex(GATE.GateFailure, "duplicate"):
            GATE.parse_required_impls("shen-cl,shen-cl")

    def test_unknown_port_is_rejected(self) -> None:
        with self.assertRaisesRegex(GATE.GateFailure, "unknown required port"):
            GATE.parse_required_impls("shen-go,shen-lua,shen-cl,shenscript")

    def test_single_port_execution_validates_against_goldens(self) -> None:
        values = list(valid_execution(required=("shen-cl",)))
        evidence = GATE.validate_execution(*values)
        self.assertEqual(set(evidence["world-reducer"]["ports"]), {"shen-cl"})


def stub_bifrost() -> types.ModuleType:
    """A module that binds the heavy timeout exactly as pinned bifrost.py does.

    execute_cases takes heavy_timeout as a default argument evaluated at
    import, and run_suite calls it without passing one -- so rebinding
    TIMEOUT_HEAVY alone leaves the stock value in force.
    """
    module = types.ModuleType("stub_bifrost")
    source = (
        "TIMEOUT_HEAVY = 300\n"
        "def execute_cases(cases, available, suite, heavy_timeout=TIMEOUT_HEAVY,\n"
        "                  progress=True, shake=False):\n"
        "    return heavy_timeout\n"
        "def run_suite(suite, progress=False, shake=False):\n"
        "    return execute_cases([], {}, suite, progress=progress, shake=shake)\n"
    )
    exec(source, module.__dict__)
    return module


class HeavyTimeoutTests(unittest.TestCase):
    def setUp(self) -> None:
        self.env = os.environ.pop("URDR_BIFROST_HEAVY_TIMEOUT", None)

    def tearDown(self) -> None:
        os.environ.pop("URDR_BIFROST_HEAVY_TIMEOUT", None)
        if self.env is not None:
            os.environ["URDR_BIFROST_HEAVY_TIMEOUT"] = self.env

    def test_default_is_used_when_unset(self) -> None:
        self.assertEqual(GATE.resolve_heavy_timeout(), GATE.HEAVY_TIMEOUT_DEFAULT)

    def test_env_override_is_honoured(self) -> None:
        os.environ["URDR_BIFROST_HEAVY_TIMEOUT"] = "900"
        self.assertEqual(GATE.resolve_heavy_timeout(), 900)

    def test_non_integer_is_rejected(self) -> None:
        os.environ["URDR_BIFROST_HEAVY_TIMEOUT"] = "forever"
        with self.assertRaisesRegex(GATE.GateFailure, "must be an integer"):
            GATE.resolve_heavy_timeout()

    def test_below_floor_is_rejected(self) -> None:
        os.environ["URDR_BIFROST_HEAVY_TIMEOUT"] = str(GATE.HEAVY_TIMEOUT_MIN - 1)
        with self.assertRaisesRegex(GATE.GateFailure, "must be 300..7200"):
            GATE.resolve_heavy_timeout()

    def test_above_ceiling_is_rejected(self) -> None:
        os.environ["URDR_BIFROST_HEAVY_TIMEOUT"] = str(GATE.HEAVY_TIMEOUT_MAX + 1)
        with self.assertRaisesRegex(GATE.GateFailure, "must be 300..7200"):
            GATE.resolve_heavy_timeout()

    def test_stub_reproduces_the_stock_default_binding(self) -> None:
        module = stub_bifrost()
        module.TIMEOUT_HEAVY = 2400
        self.assertEqual(module.run_suite(None), 300)

    def test_override_reaches_the_cases_run_by_run_suite(self) -> None:
        module = stub_bifrost()
        GATE.apply_heavy_timeout(module, 2400)
        self.assertEqual(module.TIMEOUT_HEAVY, 2400)
        self.assertEqual(module.run_suite(None), 2400)


if __name__ == "__main__":
    unittest.main()
