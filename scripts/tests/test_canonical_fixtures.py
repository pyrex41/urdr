"""Strict ADR 0002 fixture, oracle, and four-port conformance tests."""

from __future__ import annotations

import argparse
import hashlib
import os
import subprocess
import sys
import unittest
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, TypeAlias


ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = ROOT / "protocol/fixtures/v1/canonical"
CASES_PATH = FIXTURE_ROOT / "cases.tsv"
SHA_PATH = FIXTURE_ROOT / "SHA256SUMS"
SHEN_PROGRAM = "shen/tests/canonical/run-tests.shen"

# Updated only when the reviewed normative fixture set intentionally changes.
EXPECTED_SHA256SUMS_SHA256 = (
    "c7ff013c101199571544c254495c2a9b67c3ee9f1383a0bc0c10c33aaa1e9e6c"
)

PORTS = {
    "cl": (
        Path("/Users/reuben/projects/urdr-shen-cl-41.2/bin/sbcl/shen"),
        "script",
    ),
    "go": (Path("/Users/reuben/projects/shen-go/.bin/shen-go"), "script"),
    "rust": (
        Path("/Users/reuben/projects/shen-rust/target/release/shen-rust"),
        "script",
    ),
    "lua": (Path("/Users/reuben/projects/shen-lua/bin/shen"), "file"),
}


class CodecError(ValueError):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


@dataclass(frozen=True)
class Limits:
    max_frame: int = 4096
    max_atom: int = 256
    max_depth: int = 32
    max_nodes: int = 256
    max_integer_digits: int = 255
    max_symbol: int = 64


@dataclass(frozen=True)
class Null:
    pass


@dataclass(frozen=True)
class Bool:
    value: bool


@dataclass(frozen=True)
class Integer:
    sign: int
    limbs: tuple[int, ...]

    @classmethod
    def parse(cls, raw: bytes, limits: Limits = Limits()) -> "Integer":
        if not raw:
            raise CodecError("integer-empty")
        if raw[0] == 43:
            raise CodecError("integer-plus")
        negative = raw[0] == 45
        digits = raw[1:] if negative else raw
        if not digits:
            raise CodecError("integer-empty")
        if len(digits) > limits.max_integer_digits:
            raise CodecError("integer-too-large")
        if any(byte < 48 or byte > 57 for byte in digits):
            raise CodecError("integer-digit")
        if len(digits) > 1 and digits[0] == 48:
            raise CodecError("integer-leading-zero")
        if negative and digits == b"0":
            raise CodecError("integer-negative-zero")
        magnitude = int(digits)
        if magnitude == 0:
            return cls(0, ())
        limbs = []
        while magnitude:
            magnitude, limb = divmod(magnitude, 10_000)
            limbs.append(limb)
        return cls(-1 if negative else 1, tuple(limbs))

    def render(self, limits: Limits = Limits()) -> bytes:
        if self.sign == 0:
            if self.limbs:
                raise CodecError("integer-representation")
            return b"0"
        if self.sign not in (-1, 1) or not self.limbs:
            raise CodecError("integer-representation")
        if (
            self.limbs[-1] == 0
            or any(type(limb) is not int or not 0 <= limb <= 9999 for limb in self.limbs)
        ):
            raise CodecError("integer-representation")
        magnitude = str(self.limbs[-1]) + "".join(
            f"{limb:04d}" for limb in reversed(self.limbs[:-1])
        )
        if len(magnitude) > limits.max_integer_digits:
            raise CodecError("integer-too-large")
        return (b"-" if self.sign < 0 else b"") + magnitude.encode("ascii")


@dataclass(frozen=True)
class Text:
    utf8: bytes


@dataclass(frozen=True)
class Octets:
    data: bytes


@dataclass(frozen=True)
class Symbol:
    ascii: bytes


@dataclass(frozen=True)
class ListValue:
    values: tuple["Value", ...]


@dataclass(frozen=True)
class Record:
    fields: tuple[tuple[bytes, "Value"], ...]


Value: TypeAlias = Null | Bool | Integer | Text | Octets | Symbol | ListValue | Record
Node: TypeAlias = bytes | tuple["Node", ...]


def fail(code: str) -> None:
    raise CodecError(code)


def check_utf8(raw: bytes) -> bytes:
    try:
        raw.decode("utf-8", "strict")
    except UnicodeDecodeError:
        fail("utf8-invalid")
    return raw


def is_symbol(raw: bytes, limits: Limits) -> bool:
    if not raw or len(raw) > limits.max_symbol:
        return False
    if not (65 <= raw[0] <= 90 or 97 <= raw[0] <= 122):
        return False
    return all(
        65 <= byte <= 90
        or 97 <= byte <= 122
        or 48 <= byte <= 57
        or byte in b"._/-"
        for byte in raw[1:]
    )


def check_symbol(raw: bytes, limits: Limits) -> bytes:
    if len(raw) > limits.max_symbol:
        fail("symbol-too-large")
    if not is_symbol(raw, limits):
        fail("symbol-invalid")
    return raw


def atom(raw: bytes, limits: Limits) -> bytes:
    if len(raw) > limits.max_atom:
        fail("atom-too-large")
    return str(len(raw)).encode("ascii") + b":" + raw


class Parser:
    def __init__(self, payload: bytes, limits: Limits):
        self.payload = payload
        self.limits = limits
        self.position = 0
        self.nodes = 0

    def parse(self) -> Node:
        node = self.node(1)
        if self.position != len(self.payload):
            fail("payload-trailing")
        return node

    def node(self, depth: int) -> Node:
        self.nodes += 1
        if self.nodes > self.limits.max_nodes:
            fail("nodes-too-many")
        if self.position >= len(self.payload):
            fail("csexp-truncated")
        first = self.payload[self.position]
        if first == 40:
            if depth > self.limits.max_depth:
                fail("depth-too-large")
            self.position += 1
            items: list[Node] = []
            while True:
                if self.position >= len(self.payload):
                    fail("list-unclosed")
                if self.payload[self.position] == 41:
                    self.position += 1
                    return tuple(items)
                items.append(self.node(depth + 1))
        if 48 <= first <= 57:
            return self.parse_atom()
        fail("csexp-token")

    def parse_atom(self) -> bytes:
        start = self.position
        while (
            self.position < len(self.payload)
            and 48 <= self.payload[self.position] <= 57
        ):
            self.position += 1
        digits = self.payload[start : self.position]
        if len(digits) > 1 and digits[0] == 48:
            fail("length-leading-zero")
        if self.position >= len(self.payload) or self.payload[self.position] != 58:
            fail("length-colon")
        length = 0
        for digit in digits:
            length = length * 10 + digit - 48
            if length > self.limits.max_atom:
                fail("atom-too-large")
        self.position += 1
        end = self.position + length
        if end > len(self.payload):
            fail("atom-truncated")
        raw = self.payload[self.position : end]
        self.position = end
        return raw


def typed(node: Node, limits: Limits) -> Value:
    if not isinstance(node, tuple) or not node or not isinstance(node[0], bytes):
        fail("typed-list")
    tag = node[0]
    if tag == b"null":
        if len(node) != 1:
            fail("typed-arity")
        return Null()
    if tag == b"bool":
        if len(node) != 2 or not isinstance(node[1], bytes):
            fail("typed-arity")
        if node[1] == b"true":
            return Bool(True)
        if node[1] == b"false":
            return Bool(False)
        fail("bool-value")
    if tag == b"int":
        if len(node) != 2 or not isinstance(node[1], bytes):
            fail("typed-arity")
        return Integer.parse(node[1], limits)
    if tag == b"text":
        if len(node) != 2 or not isinstance(node[1], bytes):
            fail("typed-arity")
        return Text(check_utf8(node[1]))
    if tag == b"bytes":
        if len(node) != 2 or not isinstance(node[1], bytes):
            fail("typed-arity")
        return Octets(node[1])
    if tag == b"symbol":
        if len(node) != 2 or not isinstance(node[1], bytes):
            fail("typed-arity")
        return Symbol(check_symbol(node[1], limits))
    if tag == b"list":
        return ListValue(tuple(typed(item, limits) for item in node[1:]))
    if tag == b"record":
        fields = []
        previous: bytes | None = None
        for entry in node[1:]:
            if (
                not isinstance(entry, tuple)
                or len(entry) != 2
                or not isinstance(entry[0], bytes)
            ):
                fail("record-entry")
            key = check_symbol(entry[0], limits)
            if previous is not None:
                if key == previous:
                    fail("record-duplicate")
                if key < previous:
                    fail("record-order")
            previous = key
            fields.append((key, typed(entry[1], limits)))
        return Record(tuple(fields))
    fail("typed-tag")


def decode_payload(payload: bytes, limits: Limits = Limits()) -> Value:
    if len(payload) > limits.max_frame:
        fail("frame-too-large")
    return typed(Parser(payload, limits).parse(), limits)


def encode_payload(value: Value, limits: Limits = Limits()) -> bytes:
    def encode(current: Value, depth: int) -> bytes:
        if depth > limits.max_depth:
            fail("depth-too-large")
        if isinstance(current, Null):
            return b"(" + atom(b"null", limits) + b")"
        if isinstance(current, Bool):
            return (
                b"("
                + atom(b"bool", limits)
                + atom(b"true" if current.value else b"false", limits)
                + b")"
            )
        if isinstance(current, Integer):
            return b"(" + atom(b"int", limits) + atom(current.render(limits), limits) + b")"
        if isinstance(current, Text):
            return b"(" + atom(b"text", limits) + atom(check_utf8(current.utf8), limits) + b")"
        if isinstance(current, Octets):
            return b"(" + atom(b"bytes", limits) + atom(current.data, limits) + b")"
        if isinstance(current, Symbol):
            return (
                b"("
                + atom(b"symbol", limits)
                + atom(check_symbol(current.ascii, limits), limits)
                + b")"
            )
        if isinstance(current, ListValue):
            return (
                b"("
                + atom(b"list", limits)
                + b"".join(encode(item, depth + 1) for item in current.values)
                + b")"
            )
        if isinstance(current, Record):
            result = [b"(", atom(b"record", limits)]
            previous: bytes | None = None
            for key, item in current.fields:
                key = check_symbol(key, limits)
                if previous is not None:
                    if key == previous:
                        fail("record-duplicate")
                    if key < previous:
                        fail("record-order")
                previous = key
                result.extend((b"(", atom(key, limits), encode(item, depth + 1), b")"))
            result.append(b")")
            return b"".join(result)
        fail("value-type")

    payload = encode(value, 1)
    if len(payload) > limits.max_frame:
        fail("frame-too-large")
    # Enforce the exact parser node/list-depth budget on encoder output.
    Parser(payload, limits).parse()
    return payload


def encode_frame(value: Value, limits: Limits = Limits()) -> bytes:
    payload = encode_payload(value, limits)
    return str(len(payload)).encode("ascii") + b":" + payload + b","


def frame_prefix(data: bytes, limits: Limits) -> tuple[int, int] | None:
    if not data:
        return None
    if not 48 <= data[0] <= 57:
        fail("frame-length")
    colon = data.find(b":")
    if colon < 0:
        if len(data) > len(str(limits.max_frame)):
            fail("frame-length")
        if any(byte < 48 or byte > 57 for byte in data):
            fail("frame-length")
        return None
    digits = data[:colon]
    if not digits or any(byte < 48 or byte > 57 for byte in digits):
        fail("frame-length")
    if len(digits) > 1 and digits[0] == 48:
        fail("frame-leading-zero")
    length = 0
    for digit in digits:
        length = length * 10 + digit - 48
        if length > limits.max_frame:
            fail("frame-too-large")
    return colon + 1, length


def take_frame(data: bytes, limits: Limits) -> tuple[Value, bytes] | None:
    prefix = frame_prefix(data, limits)
    if prefix is None:
        return None
    body_start, length = prefix
    comma = body_start + length
    if len(data) <= comma:
        return None
    if data[comma] != 44:
        fail("frame-comma")
    return decode_payload(data[body_start:comma], limits), data[comma + 1 :]


def decode_frame(data: bytes, limits: Limits = Limits()) -> Value:
    result = take_frame(data, limits)
    if result is None:
        fail("frame-truncated")
    value, rest = result
    if rest:
        fail("frame-trailing")
    return value


class FrameDecoder:
    def __init__(self, limits: Limits = Limits()):
        self.limits = limits
        self.buffer = b""

    def feed(self, chunk: bytes) -> list[Value]:
        if not isinstance(chunk, bytes):
            fail("chunk-type")
        self.buffer += chunk
        values = []
        while True:
            result = take_frame(self.buffer, self.limits)
            if result is None:
                return values
            value, self.buffer = result
            values.append(value)

    def finish(self) -> None:
        if self.buffer:
            fail("frame-truncated")


def decode_chunks(chunks: Iterable[bytes], limits: Limits = Limits()) -> list[Value]:
    decoder = FrameDecoder(limits)
    values = []
    for chunk in chunks:
        values.extend(decoder.feed(chunk))
    decoder.finish()
    return values


BASE_ROWS = """\
V|null|383a28343a6e756c6c292c
V|false|31353a28343a626f6f6c353a66616c7365292c
V|true|31343a28343a626f6f6c343a74727565292c
V|zero|31303a28333a696e74313a30292c
V|negative|34313a28333a696e7433313a2d313233343536373839303132333435363738393031323334353637383930292c
V|text-ascii|31353a28343a74657874353a68656c6c6f292c
V|text-unicode|31373a28343a74657874373a62c3b662e298ba292c
V|bytes|31363a28353a6279746573353a00292c3aff292c
V|symbol|33373a28363a73796d626f6c32343a616c7068612d312f626574612e67616d6d615f64656c7461292c
V|empty-list|383a28343a6c697374292c
V|list|34313a28343a6c69737428343a6e756c6c2928343a626f6f6c343a747275652928333a696e74323a343229292c
V|empty-record|31303a28363a7265636f7264292c
V|record|34333a28363a7265636f726428313a6128333a696e74313a31292928313a7a28343a74657874333a656e642929292c
V|nested|36333a28343a6c69737428363a7265636f726428353a6974656d7328343a6c69737428343a626f6f6c353a66616c73652928353a6279746573323a787929292929292c
X|float-tag|31343a28353a666c6f6174333a312e30292c|typed-tag
X|record-duplicate|33363a28363a7265636f726428313a6128343a6e756c6c292928313a6128343a6e756c6c2929292c|record-duplicate
X|record-order|33363a28363a7265636f726428313a7a28343a6e756c6c292928313a6128343a6e756c6c2929292c|record-order
X|utf8-continuation|31313a28343a74657874313a80292c|utf8-invalid
X|utf8-overlong|31323a28343a74657874323ac080292c|utf8-invalid
X|utf8-surrogate|31333a28343a74657874333aeda080292c|utf8-invalid
X|utf8-truncated|31323a28343a74657874323ae298292c|utf8-invalid
X|improper-list|31373a28343a6c69737428343a6e756c6c292e292c|csexp-token
X|integer-plus|31313a28333a696e74323a2b31292c|integer-plus
X|integer-leading-zero|31313a28333a696e74323a3031292c|integer-leading-zero
X|integer-negative-zero|31313a28333a696e74323a2d30292c|integer-negative-zero
X|comment|31313a3b780a28343a6e756c6c292c|csexp-token
X|whitespace|393a28343a6e756c6c20292c|csexp-token
X|payload-trailing|31363a28343a6e756c6c2928343a6e756c6c292c|payload-trailing
X|frame-trailing|383a28343a6e756c6c292c78|frame-trailing
X|length-leading-zero|393a2830343a6e756c6c292c|length-leading-zero
X|frame-leading-zero|30383a28343a6e756c6c292c|frame-leading-zero
X|frame-too-large|343039373a|frame-too-large
X|atom-too-large|31323a28343a746578743235373a292c|atom-too-large
X|depth-too-large|3236343a28343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c69737428343a6c6973742929292929292929292929292929292929292929292929292929292929292929292c|depth-too-large
X|bool-value|31333a28343a626f6f6c333a796573292c|bool-value
X|symbol-invalid|31353a28363a73796d626f6c333a612062292c|symbol-invalid
X|record-entry|31333a28363a7265636f7264313a61292c|record-entry
X|typed-arity|31313a28343a6e756c6c313a78292c|typed-arity
X|typed-list|363a343a6e756c6c2c|typed-list
X|frame-comma|383a28343a6e756c6c293b|frame-comma
X|prefix-too-long|3131313131|frame-length
X|frame-truncated|383a28343a6e756c6c29|frame-truncated
"""


def frame(payload: bytes) -> bytes:
    return str(len(payload)).encode("ascii") + b":" + payload + b","


def fixture_specs() -> list[tuple[str, str, bytes, str | None]]:
    specs = []
    for row in BASE_ROWS.splitlines():
        parts = row.split("|")
        specs.append(
            (
                parts[0],
                parts[1],
                bytes.fromhex(parts[2]),
                parts[3] if len(parts) == 4 else None,
            )
        )
    integer_max = frame(b"(3:int255:" + b"9" * 255 + b")")
    integer_too_large = frame(b"(3:int256:" + b"9" * 256 + b")")
    symbol_max = frame(b"(6:symbol64:" + b"a" + b"z" * 63 + b")")
    symbol_too_large = frame(b"(6:symbol65:" + b"a" + b"z" * 64 + b")")
    depth_max = frame(b"(4:list" * 32 + b")" * 32)
    nodes_max = frame(b"(4:list" + b"(4:null)" * 127 + b")")
    nodes_too_many = frame(b"(4:list" + b"(4:null)" * 128 + b")")
    atom_max = frame(b"(5:bytes256:" + bytes(range(256)) + b")")
    payload_max_body = (
        b"(4:list"
        + (b"(5:bytes256:" + bytes(range(256)) + b")") * 15
        + b"(5:bytes41:"
        + bytes(range(41))
        + b"))"
    )
    assert len(payload_max_body) == 4096
    specs.extend(
        [
            ("V", "integer-max", integer_max, None),
            ("X", "integer-too-large", integer_too_large, "integer-too-large"),
            ("V", "symbol-max", symbol_max, None),
            ("X", "symbol-too-large", symbol_too_large, "symbol-too-large"),
            ("V", "depth-max", depth_max, None),
            ("V", "nodes-max", nodes_max, None),
            ("X", "nodes-too-many", nodes_too_many, "nodes-too-many"),
            ("V", "atom-max", atom_max, None),
            ("V", "payload-max", frame(payload_max_body), None),
            ("X", "empty-payload", b"0:,", "csexp-truncated"),
        ]
    )
    return specs


def fixture_relative(kind: str, name: str) -> str:
    directory = "valid" if kind == "V" else "invalid"
    return f"{directory}/{name}.frame"


def write_fixtures() -> str:
    FIXTURE_ROOT.mkdir(parents=True, exist_ok=True)
    rows = ["# kind|name|relative-frame-path|stable-error (X only)"]
    expected_paths = set()
    for kind, name, raw, error in fixture_specs():
        relative = fixture_relative(kind, name)
        path = FIXTURE_ROOT / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)
        expected_paths.add(path)
        fields = [kind, name, relative]
        if error is not None:
            fields.append(error)
        rows.append("|".join(fields))
    CASES_PATH.write_text("\n".join(rows) + "\n", encoding="ascii")
    expected_paths.add(CASES_PATH)
    for directory in (FIXTURE_ROOT / "valid", FIXTURE_ROOT / "invalid"):
        for path in directory.glob("*.frame"):
            if path not in expected_paths:
                path.unlink()
    manifest = []
    for path in sorted(expected_paths):
        relative = path.relative_to(FIXTURE_ROOT).as_posix()
        manifest.append(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {relative}")
    SHA_PATH.write_text("\n".join(manifest) + "\n", encoding="ascii")
    return hashlib.sha256(SHA_PATH.read_bytes()).hexdigest()


def load_cases() -> list[tuple[str, str, Path, str | None]]:
    cases = []
    for number, line in enumerate(CASES_PATH.read_text("ascii").splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        if len(parts) not in (3, 4) or parts[0] not in ("V", "X"):
            raise AssertionError(f"bad cases.tsv line {number}")
        kind, name, relative = parts[:3]
        error = parts[3] if len(parts) == 4 else None
        if kind == "V" and error is not None:
            raise AssertionError(f"valid fixture has error on line {number}")
        if kind == "X" and not error:
            raise AssertionError(f"invalid fixture lacks error on line {number}")
        path = FIXTURE_ROOT / relative
        if path.parent.parent != FIXTURE_ROOT or path.suffix != ".frame":
            raise AssertionError(f"unsafe fixture path on line {number}")
        cases.append((kind, name, path, error))
    return cases


def verify_manifest() -> None:
    digest = hashlib.sha256(SHA_PATH.read_bytes()).hexdigest()
    if digest != EXPECTED_SHA256SUMS_SHA256:
        raise AssertionError(
            f"SHA256SUMS digest changed: expected {EXPECTED_SHA256SUMS_SHA256}, got {digest}"
        )
    entries = {}
    lines = SHA_PATH.read_text("ascii").splitlines()
    relatives = []
    for line in lines:
        if len(line) < 67 or line[64:66] != "  ":
            raise AssertionError(f"malformed SHA256SUMS line: {line!r}")
        expected, relative = line[:64], line[66:]
        if any(char not in "0123456789abcdef" for char in expected):
            raise AssertionError(f"noncanonical digest: {expected!r}")
        path = FIXTURE_ROOT / relative
        if path.parent not in (
            FIXTURE_ROOT,
            FIXTURE_ROOT / "valid",
            FIXTURE_ROOT / "invalid",
        ):
            raise AssertionError(f"unsafe manifest path: {relative!r}")
        relatives.append(relative)
        entries[path] = expected
    if relatives != sorted(relatives):
        raise AssertionError("SHA256SUMS paths are not sorted")
    expected_paths = {CASES_PATH} | {case[2] for case in load_cases()}
    if set(entries) != expected_paths:
        raise AssertionError("SHA256SUMS path set differs from cases.tsv")
    for path, expected in entries.items():
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected:
            raise AssertionError(f"{path.relative_to(ROOT)}: SHA-256 mismatch")


def fixture_output() -> list[str]:
    output = []
    for kind, name, path, expected in load_cases():
        wire = path.read_bytes()
        if kind == "V":
            value = decode_frame(wire)
            if encode_frame(value) != wire:
                raise AssertionError(f"{name}: re-encode mismatch")
            for split in range(len(wire) + 1):
                if decode_chunks((wire[:split], wire[split:])) != [value]:
                    raise AssertionError(f"{name}: split {split}")
            if decode_chunks(bytes([byte]) for byte in wire) != [value]:
                raise AssertionError(f"{name}: byte chunks")
            output.append(f"valid|{name}|{wire.hex()}")
        else:
            try:
                decode_frame(wire)
            except CodecError as error:
                if error.code != expected:
                    raise AssertionError(
                        f"{name}: expected {expected}, got {error.code}"
                    )
            else:
                raise AssertionError(f"{name}: unexpectedly accepted")
            output.append(f"reject|{name}|{expected}")
    return output


def evidence_lines(stdout: str) -> list[str]:
    return [
        line
        for line in stdout.splitlines()
        if line.startswith(("valid|", "reject|", "FAIL|")) or line == "ALL PASS"
    ]


def run_port(name: str, expected: list[str]) -> str:
    launcher, mode = PORTS[name]
    if not launcher.is_file():
        raise AssertionError(f"required {name} launcher missing: {launcher}")
    command = (
        [str(launcher), "script", SHEN_PROGRAM]
        if mode == "script"
        else [str(launcher), SHEN_PROGRAM]
    )
    environment = os.environ.copy()
    environment.update(
        {
            "SHEN_KERNEL_CACHE": "off",
            "SHEN_FASL": "off",
            "PYTHONDONTWRITEBYTECODE": "1",
        }
    )
    try:
        result = subprocess.run(
            command,
            cwd=ROOT,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=300,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise AssertionError(f"{name} timed out after 300 seconds") from error
    actual = evidence_lines(result.stdout)
    if result.returncode != 0 or actual != expected:
        raise AssertionError(
            f"{name}: exit={result.returncode}, evidence={actual!r}\n{result.stdout}"
        )
    blob = ("\n".join(actual) + "\n").encode("ascii")
    return hashlib.sha256(blob).hexdigest()


class CanonicalFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        verify_manifest()
        cls.expected = fixture_output() + ["ALL PASS"]

    def test_normative_fixture_count(self) -> None:
        cases = load_cases()
        self.assertEqual(52, len(cases))
        self.assertEqual(20, sum(kind == "V" for kind, *_ in cases))
        self.assertEqual(32, sum(kind == "X" for kind, *_ in cases))

    def test_adr_0003_integer_ast(self) -> None:
        negative = decode_frame(
            bytes.fromhex(
                "34313a28333a696e7433313a2d313233343536373839303132333435363738393031323334353637383930292c"
            )
        )
        self.assertEqual(
            Integer(-1, (7890, 3456, 9012, 5678, 1234, 7890, 3456, 12)),
            negative,
        )
        self.assertEqual(Integer(0, ()), decode_frame(bytes.fromhex("31303a28333a696e74313a30292c")))

    def test_encoder_rejects_noncanonical_values(self) -> None:
        with self.assertRaisesRegex(CodecError, "integer-representation"):
            encode_frame(Integer(0, (1,)))
        with self.assertRaisesRegex(CodecError, "integer-representation"):
            encode_frame(Integer(1, (1, 0)))
        with self.assertRaisesRegex(CodecError, "value-type"):
            encode_frame(1.5)  # type: ignore[arg-type]
        with self.assertRaisesRegex(CodecError, "record-order"):
            encode_frame(Record(((b"z", Null()), (b"a", Null()))))

    def test_concatenated_stream_all_chunk_widths(self) -> None:
        wire = encode_frame(Null()) + encode_frame(Text("λ".encode("utf-8")))
        expected = [Null(), Text("λ".encode("utf-8"))]
        for width in range(1, len(wire) + 1):
            chunks = (wire[index : index + width] for index in range(0, len(wire), width))
            self.assertEqual(expected, decode_chunks(chunks))

    def assert_all_required_shen_ports(self) -> None:
        """Explicit conformance helper; ordinary unit tests remain dependency-free."""
        hashes = {}
        for name in PORTS:
            with self.subTest(port=name):
                hashes[name] = run_port(name, self.expected)
        self.assertEqual(1, len(set(hashes.values())), hashes)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--ports", action="store_true")
    args = parser.parse_args(argv)
    if args.write:
        print(write_fixtures())
        return 0
    verify_manifest()
    expected = fixture_output() + ["ALL PASS"]
    if args.ports:
        for name in PORTS:
            digest = run_port(name, expected)
            print(f"PORT PASS {name} lines={len(expected)} sha256={digest}")
        return 0
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(CanonicalFixtureTests)
    return int(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())


if __name__ == "__main__":
    sys.exit(main())
