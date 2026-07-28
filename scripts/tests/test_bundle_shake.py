"""Tests for the shake bundler: inlining must not change what runs."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LOADER = importlib.machinery.SourceFileLoader(
    "urdr_bundle_shake", str(ROOT / "scripts" / "bundle-shake-program")
)
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC is not None
BUNDLE = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(BUNDLE)

# One suite per loading style: canonical uses a plain top-level (load ...),
# replay uses the read-file + eval urt.quiet-load helper.
PLAIN_LOAD_SUITE = "shen/tests/canonical/run-tests.shen"
QUIET_LOAD_SUITE = "shen/tests/replay/run-tests.shen"


class LoadFormTests(unittest.TestCase):
    def test_plain_load_is_recognised(self) -> None:
        self.assertEqual(
            BUNDLE.program_load_target('(load "shen/world/prng.shen")'),
            "shen/world/prng.shen",
        )

    def test_any_suite_prefix_of_quiet_load_is_recognised(self) -> None:
        # Each suite names its own helper: urt./uwt./unt./uit. and friends.
        for prefix in ("urt", "uwt", "unt", "uit", "some.deep.ns"):
            self.assertEqual(
                BUNDLE.program_load_target(f'({prefix}.quiet-load "shen/a.shen")'),
                "shen/a.shen",
                prefix,
            )

    def test_unprefixed_quiet_load_is_recognised(self) -> None:
        self.assertEqual(
            BUNDLE.program_load_target('(quiet-load "shen/a.shen")'), "shen/a.shen"
        )

    def test_other_forms_are_left_alone(self) -> None:
        for line in ('(define f -> 1)', '  (load "indented.shen")',
                     '(load-something "x.shen")', '\\\\ (load "commented.shen")'):
            self.assertIsNone(BUNDLE.program_load_target(line), line)


class BundleTests(unittest.TestCase):
    def test_both_loading_styles_bundle(self) -> None:
        for suite in (PLAIN_LOAD_SUITE, QUIET_LOAD_SUITE):
            text = BUNDLE.bundle(suite)
            self.assertIn("AUTO-GENERATED", text, suite)
            self.assertGreater(len(text.splitlines()), 500, suite)

    def test_no_load_directive_survives_in_the_bundle(self) -> None:
        # Anything the shaker cannot follow must be commented out, or the
        # artifact would try to read source files that are not shipped.
        for suite in (PLAIN_LOAD_SUITE, QUIET_LOAD_SUITE):
            for line in BUNDLE.bundle(suite).splitlines():
                self.assertIsNone(BUNDLE.program_load_target(line), f"{suite}: {line}")

    def test_transitive_dependency_is_inlined_before_its_dependent(self) -> None:
        # prng.shen carries its own (load "integer.shen"); integer must appear
        # first or the dependency would be silently dropped.
        text = BUNDLE.bundle(QUIET_LOAD_SUITE)
        integer = text.find("\\\\ ---- shen/world/integer.shen ----")
        prng = text.find("\\\\ ---- shen/world/prng.shen ----")
        self.assertNotEqual(integer, -1)
        self.assertNotEqual(prng, -1)
        self.assertLess(integer, prng)

    def test_each_module_is_emitted_once(self) -> None:
        text = BUNDLE.bundle(QUIET_LOAD_SUITE)
        self.assertEqual(text.count("\\\\ ---- shen/world/integer.shen ----"), 1)

    def test_every_reviewed_case_program_bundles(self) -> None:
        import json

        manifest = json.loads((ROOT / "bifrost.suite.json").read_text(encoding="utf-8"))
        for case in manifest["cases"]:
            with self.subTest(case=case["name"]):
                self.assertGreater(len(BUNDLE.bundle(case["program"]).splitlines()), 0)


class FailureTests(unittest.TestCase):
    def test_missing_program_is_rejected(self) -> None:
        with self.assertRaisesRegex(BUNDLE.BundleError, "program not found"):
            BUNDLE.bundle("shen/tests/nope/run-tests.shen")

    def test_program_without_loads_is_rejected(self) -> None:
        with self.assertRaisesRegex(BUNDLE.BundleError, "no top-level"):
            BUNDLE.bundle("shen/world/integer.shen")

    def test_missing_module_is_rejected(self) -> None:
        with self.assertRaisesRegex(BUNDLE.BundleError, "module not found"):
            BUNDLE.emit_module("shen/world/nope.shen", [], [])

    def test_load_cycle_is_rejected_rather_than_hanging(self) -> None:
        with self.assertRaisesRegex(BUNDLE.BundleError, "load cycle"):
            BUNDLE.emit_module(
                "shen/world/prng.shen", [], [], ("shen/world/prng.shen",)
            )


if __name__ == "__main__":
    unittest.main()
