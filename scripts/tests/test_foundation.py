"""Offline tests for the Wave 0 repository foundation."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FULL_SHA = re.compile(r"^[0-9a-f]{40}$")


def run(*arguments: str, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(arguments),
        cwd=ROOT,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


class MakeContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.makefile = (ROOT / "Makefile").read_text(encoding="utf-8")

    def test_required_targets_exist(self) -> None:
        for target in ["bootstrap", "fmt-check", "test", "conformance", "ci"]:
            self.assertRegex(self.makefile, rf"(?m)^{re.escape(target)}:")

    def test_only_bootstrap_enables_networked_bootstrap(self) -> None:
        self.assertEqual(self.makefile.count("URDR_BOOTSTRAP_NETWORK=1"), 1)
        bootstrap = self.makefile.split("bootstrap:", 1)[1].split("\n\n", 1)[0]
        self.assertIn("URDR_BOOTSTRAP_NETWORK=1", bootstrap)
        for target in ["fmt-check", "test", "conformance"]:
            recipe = self.makefile.split(f"{target}:", 1)[1].split("\n\n", 1)[0]
            self.assertIn("URDR_OFFLINE=1", recipe)
            self.assertNotIn("bootstrap", recipe)

    def test_full_ci_includes_strict_conformance(self) -> None:
        recipe = self.makefile.split("ci:", 1)[1].split("\n\n", 1)[0]
        self.assertIn("fmt-check test conformance", recipe)
        self.assertIn("check-clean-tree", recipe)


class GeneratedFileTests(unittest.TestCase):
    def test_representative_generated_files_are_ignored(self) -> None:
        ignored = [
            ".cache/urdr/dependencies/tool/.git/HEAD",
            "scripts/__pycache__/quality.pyc",
            ".pytest_cache/state",
            "build/downloads/archive.tar",
            "build/out/urdr",
            "dist/package",
            "artifacts/run/log.json",
        ]
        for path in ignored:
            result = run("git", "check-ignore", "--no-index", "--quiet", path)
            self.assertEqual(result.returncode, 0, msg=f"{path}: {result.stderr}")

    def test_lock_schemas_are_source_not_ignored(self) -> None:
        path = "build/locks/schemas/tools-lock.schema.json"
        result = run("git", "check-ignore", "--no-index", "--quiet", path)
        self.assertNotEqual(result.returncode, 0)

    def test_no_generated_file_is_tracked(self) -> None:
        tracked = run("git", "ls-files", "-z")
        self.assertEqual(tracked.returncode, 0, tracked.stderr)
        names = tracked.stdout.split("\0")
        forbidden = re.compile(
            r"(^|/)(__pycache__|\.cache|dist|out|tmp|artifacts)(/|$)|\.py[co]$"
        )
        self.assertEqual([name for name in names if forbidden.search(name)], [])

    def test_clean_tree_wrapper_detects_noop_as_pure(self) -> None:
        result = run(
            sys.executable,
            "scripts/check-clean-tree",
            "--",
            sys.executable,
            "-c",
            "pass",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("state unchanged", result.stdout)

    def test_generated_cache_output_does_not_dirty_tree(self) -> None:
        probe = ROOT / ".cache" / f"foundation-test-{os.getpid()}" / "generated.txt"
        shutil.rmtree(probe.parent, ignore_errors=True)
        command = (
            "from pathlib import Path; "
            f"p = Path({str(probe)!r}); p.parent.mkdir(parents=True); "
            "p.write_text('generated\\n', encoding='utf-8')"
        )
        try:
            result = run(
                sys.executable,
                "scripts/check-clean-tree",
                "--",
                sys.executable,
                "-c",
                command,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(probe.is_file())
            self.assertIn("state unchanged", result.stdout)
        finally:
            shutil.rmtree(probe.parent, ignore_errors=True)

    def test_clean_tree_wrapper_rejects_visible_output(self) -> None:
        probe = ROOT / f"foundation-dirty-probe-{os.getpid()}"
        probe.unlink(missing_ok=True)
        command = (
            "from pathlib import Path; "
            f"Path({str(probe)!r}).write_text('dirty\\n', encoding='utf-8')"
        )
        try:
            result = run(
                sys.executable,
                "scripts/check-clean-tree",
                "--",
                sys.executable,
                "-c",
                command,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("changed Git-visible repository state", result.stderr)
        finally:
            probe.unlink(missing_ok=True)


class OwnershipBoundaryTests(unittest.TestCase):
    def check_paths(self, paths: str, *rules: str) -> subprocess.CompletedProcess[str]:
        arguments = [
            sys.executable,
            "scripts/check-owned-paths",
            "--paths-from",
            "-",
        ]
        for rule in rules:
            arguments.extend(["--allow", rule])
        return run(*arguments, input_text=paths)

    def test_owned_files_and_directory_are_accepted(self) -> None:
        result = self.check_paths(
            "protocol/uap.md\nprotocol/fixtures/v1/frame.hex\n",
            "protocol/uap.md",
            "protocol/fixtures/v1/",
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_cross_module_edit_is_rejected(self) -> None:
        result = self.check_paths(
            "shen/world/reduce.shen\nadapters/network/scheduler.go\n",
            "shen/world/",
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("adapters/network/scheduler.go", result.stderr)

    def test_parent_traversal_is_rejected(self) -> None:
        result = self.check_paths("../bifrost/file\n", "shen/world/")
        self.assertEqual(result.returncode, 2)
        self.assertIn("unsafe changed path", result.stderr)


class LockSchemaTests(unittest.TestCase):
    def load(self, name: str) -> dict[str, object]:
        path = ROOT / "build" / "locks" / "schemas" / name
        return json.loads(path.read_text(encoding="utf-8"))

    def test_schemas_are_closed_and_versioned(self) -> None:
        for name in ["tools-lock.schema.json", "shen-ports-lock.schema.json"]:
            schema = self.load(name)
            self.assertEqual(schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
            self.assertFalse(schema["additionalProperties"])
            version = schema["properties"]["schema_version"]  # type: ignore[index]
            self.assertEqual(version["const"], 1)  # type: ignore[index]

    def test_shen_schema_requires_all_four_ports_and_kernel(self) -> None:
        schema = self.load("shen-ports-lock.schema.json")
        properties = schema["properties"]  # type: ignore[assignment]
        self.assertEqual(properties["kernel_version"]["const"], "41.2")  # type: ignore[index]
        encoded = json.dumps(schema, sort_keys=True)
        for name in ["shen-go", "shen-lua", "shen-cl", "shen-rust"]:
            self.assertIn(f'"const": "{name}"', encoded)
        self.assertRegex(encoded, r"\^\[0-9a-f\]\{40\}\$")


class WorkflowTests(unittest.TestCase):
    def test_actions_are_commit_pinned(self) -> None:
        workflow_dir = ROOT / ".github" / "workflows"
        workflows = list(workflow_dir.glob("*.yml")) + list(workflow_dir.glob("*.yaml"))
        self.assertTrue(workflows)
        for path in workflows:
            for line in path.read_text(encoding="utf-8").splitlines():
                match = re.match(r"^\s*uses:\s*([^#\s]+)", line)
                if match and not match.group(1).startswith("./"):
                    reference = match.group(1).rsplit("@", 1)
                    self.assertEqual(len(reference), 2)
                    self.assertRegex(reference[1], FULL_SHA)

    def test_foundation_workflow_is_offline_and_clean(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "quality.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn("make quality", workflow)
        self.assertNotIn("make bootstrap", workflow)
        self.assertNotRegex(workflow, r"\b(curl|wget|pip install|apt-get)\b")


if __name__ == "__main__":
    unittest.main()
