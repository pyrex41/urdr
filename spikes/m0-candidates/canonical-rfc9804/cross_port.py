#!/usr/bin/env python3
"""Fail-closed Shen 41.2 cross-port fixture runner."""

from __future__ import annotations

import argparse
import hashlib
import os
import subprocess
import sys
from pathlib import Path

import codec


CANDIDATE = Path(__file__).resolve().parent
REPO = CANDIDATE.parents[2]
PROGRAM = "spikes/m0-candidates/canonical-rfc9804/run-tests.shen"
PORTS = {
    "cl": (Path("/Users/reuben/projects/urdr-shen-cl-41.2/bin/sbcl/shen"), "script"),
    "go": (Path("/Users/reuben/projects/shen-go/.bin/shen-go"), "script"),
    "rust": (Path("/Users/reuben/projects/shen-rust/target/release/shen-rust"), "script"),
    "lua": (Path("/Users/reuben/projects/shen-lua/bin/shen"), "file"),
}


def evidence_lines(stdout: str) -> list[str]:
    lines = []
    for line in stdout.splitlines():
        if line.startswith(("valid|", "reject|", "FAIL|")) or line == "ALL PASS":
            lines.append(line)
    return lines


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", choices=sorted(PORTS), action="append")
    args = parser.parse_args()
    expected = codec.fixture_output(CANDIDATE / "fixtures.tsv") + ["ALL PASS"]
    names = args.only or list(PORTS)
    failed = False
    for name in names:
        launcher, mode = PORTS[name]
        if not launcher.is_file():
            print(f"PORT FAIL {name} missing={launcher}")
            failed = True
            continue
        command = [str(launcher), "script", PROGRAM] if mode == "script" else [str(launcher), PROGRAM]
        environment = os.environ.copy()
        environment.update({"SHEN_KERNEL_CACHE": "off", "SHEN_FASL": "off"})
        try:
            run = subprocess.run(
                command,
                cwd=REPO,
                env=environment,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=120,
                check=False,
            )
        except subprocess.TimeoutExpired:
            print(f"PORT FAIL {name} timeout=120s")
            failed = True
            continue
        actual = evidence_lines(run.stdout)
        if run.returncode != 0 or actual != expected:
            print(f"PORT FAIL {name} exit={run.returncode}")
            if actual != expected:
                print(f"  evidence-lines={len(actual)} expected={len(expected)}")
                for index, (got, want) in enumerate(zip(actual, expected)):
                    if got != want:
                        print(f"  first-difference={index} got={got!r} expected={want!r}")
                        break
            print(run.stdout)
            failed = True
            continue
        blob = ("\n".join(actual) + "\n").encode("ascii")
        print(
            f"PORT PASS {name} lines={len(actual)} "
            f"sha256={hashlib.sha256(blob).hexdigest()}"
        )
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
