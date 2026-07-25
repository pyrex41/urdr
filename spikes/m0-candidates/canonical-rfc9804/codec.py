#!/usr/bin/env python3
"""Independent stdlib reference codec for the canonical RFC 9804 candidate."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence, TypeAlias


class CodecError(ValueError):
    """A stable, implementation-independent rejection."""

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
    """Software integer representation: sign plus canonical decimal digits."""

    negative: bool
    digits: bytes

    @classmethod
    def parse(cls, raw: bytes, limits: Limits = Limits()) -> "Integer":
        if not raw:
            raise CodecError("integer-empty")
        if len(raw) > limits.max_integer_digits + 1:
            raise CodecError("integer-too-large")
        negative = raw[0] == 45
        digits = raw[1:] if negative else raw
        if raw[0] == 43:
            raise CodecError("integer-plus")
        if not digits:
            raise CodecError("integer-empty")
        if len(digits) > limits.max_integer_digits:
            raise CodecError("integer-too-large")
        if any(b < 48 or b > 57 for b in digits):
            raise CodecError("integer-digit")
        if len(digits) > 1 and digits[0] == 48:
            raise CodecError("integer-leading-zero")
        if negative and digits == b"0":
            raise CodecError("integer-negative-zero")
        return cls(negative, digits)

    def render(self, limits: Limits = Limits()) -> bytes:
        # Revalidate so callers cannot construct a noncanonical instance.
        raw = (b"-" if self.negative else b"") + self.digits
        return Integer.parse(raw, limits).wire

    @property
    def wire(self) -> bytes:
        return (b"-" if self.negative else b"") + self.digits


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


def _fail(code: str) -> None:
    raise CodecError(code)


def _is_symbol(raw: bytes, limits: Limits) -> bool:
    if not raw or len(raw) > limits.max_symbol:
        return False
    first = raw[0]
    if not (65 <= first <= 90 or 97 <= first <= 122):
        return False
    return all(
        65 <= b <= 90
        or 97 <= b <= 122
        or 48 <= b <= 57
        or b in b"._/-"
        for b in raw[1:]
    )


def _check_symbol(raw: bytes, limits: Limits) -> bytes:
    if len(raw) > limits.max_symbol:
        _fail("symbol-too-large")
    if not _is_symbol(raw, limits):
        _fail("symbol-invalid")
    return raw


def _check_utf8(raw: bytes) -> bytes:
    try:
        raw.decode("utf-8", "strict")
    except UnicodeDecodeError:
        _fail("utf8-invalid")
    return raw


def _atom(raw: bytes, limits: Limits) -> bytes:
    if len(raw) > limits.max_atom:
        _fail("atom-too-large")
    return str(len(raw)).encode("ascii") + b":" + raw


def encode_payload(value: Value, limits: Limits = Limits()) -> bytes:
    """Encode one typed value as an RFC 9804 canonical S-expression."""

    nodes = 0

    def enc(current: Value, depth: int) -> bytes:
        nonlocal nodes
        nodes += 1
        if nodes > limits.max_nodes:
            _fail("nodes-too-many")
        if depth > limits.max_depth:
            _fail("depth-too-large")
        if isinstance(current, Null):
            return b"(" + _atom(b"null", limits) + b")"
        if isinstance(current, Bool):
            return (
                b"("
                + _atom(b"bool", limits)
                + _atom(b"true" if current.value else b"false", limits)
                + b")"
            )
        if isinstance(current, Integer):
            return b"(" + _atom(b"int", limits) + _atom(current.render(limits), limits) + b")"
        if isinstance(current, Text):
            return b"(" + _atom(b"text", limits) + _atom(_check_utf8(current.utf8), limits) + b")"
        if isinstance(current, Octets):
            return b"(" + _atom(b"bytes", limits) + _atom(current.data, limits) + b")"
        if isinstance(current, Symbol):
            return b"(" + _atom(b"symbol", limits) + _atom(_check_symbol(current.ascii, limits), limits) + b")"
        if isinstance(current, ListValue):
            return b"(" + _atom(b"list", limits) + b"".join(
                enc(item, depth + 1) for item in current.values
            ) + b")"
        if isinstance(current, Record):
            out = [b"(", _atom(b"record", limits)]
            previous: bytes | None = None
            for key, item in current.fields:
                key = _check_symbol(key, limits)
                if previous is not None:
                    if key == previous:
                        _fail("record-duplicate")
                    if key < previous:
                        _fail("record-order")
                previous = key
                out.extend((b"(", _atom(key, limits), enc(item, depth + 1), b")"))
            out.append(b")")
            return b"".join(out)
        # bool is deliberately not accepted as an integer, nor are floats.
        _fail("value-type")

    payload = enc(value, 1)
    if len(payload) > limits.max_frame:
        _fail("frame-too-large")
    return payload


def encode_frame(value: Value, limits: Limits = Limits()) -> bytes:
    payload = encode_payload(value, limits)
    return str(len(payload)).encode("ascii") + b":" + payload + b","


class _Parser:
    def __init__(self, payload: bytes, limits: Limits):
        self.payload = payload
        self.limits = limits
        self.pos = 0
        self.nodes = 0

    def parse(self) -> Node:
        node = self._node(1)
        if self.pos != len(self.payload):
            _fail("payload-trailing")
        return node

    def _node(self, depth: int) -> Node:
        self.nodes += 1
        if self.nodes > self.limits.max_nodes:
            _fail("nodes-too-many")
        if self.pos >= len(self.payload):
            _fail("csexp-truncated")
        first = self.payload[self.pos]
        if first == 40:
            if depth > self.limits.max_depth:
                _fail("depth-too-large")
            self.pos += 1
            items: list[Node] = []
            while True:
                if self.pos >= len(self.payload):
                    _fail("list-unclosed")
                if self.payload[self.pos] == 41:
                    self.pos += 1
                    return tuple(items)
                items.append(self._node(depth + 1))
        if 48 <= first <= 57:
            return self._atom()
        # Includes whitespace, comments, display hints and unmatched ')'.
        _fail("csexp-token")

    def _atom(self) -> bytes:
        start = self.pos
        while self.pos < len(self.payload) and 48 <= self.payload[self.pos] <= 57:
            self.pos += 1
        digits = self.payload[start : self.pos]
        if len(digits) > 1 and digits[0] == 48:
            _fail("length-leading-zero")
        if self.pos >= len(self.payload) or self.payload[self.pos] != 58:
            _fail("length-colon")
        length = 0
        for digit in digits:
            length = length * 10 + digit - 48
            if length > self.limits.max_atom:
                _fail("atom-too-large")
        self.pos += 1
        end = self.pos + length
        if end > len(self.payload):
            _fail("atom-truncated")
        raw = self.payload[self.pos : end]
        self.pos = end
        return raw


def _typed(node: Node, limits: Limits) -> Value:
    if not isinstance(node, tuple) or not node or not isinstance(node[0], bytes):
        _fail("typed-list")
    tag = node[0]
    if tag == b"null":
        if len(node) != 1:
            _fail("typed-arity")
        return Null()
    if tag == b"bool":
        if len(node) != 2 or not isinstance(node[1], bytes):
            _fail("typed-arity")
        if node[1] == b"true":
            return Bool(True)
        if node[1] == b"false":
            return Bool(False)
        _fail("bool-value")
    if tag == b"int":
        if len(node) != 2 or not isinstance(node[1], bytes):
            _fail("typed-arity")
        return Integer.parse(node[1], limits)
    if tag == b"text":
        if len(node) != 2 or not isinstance(node[1], bytes):
            _fail("typed-arity")
        return Text(_check_utf8(node[1]))
    if tag == b"bytes":
        if len(node) != 2 or not isinstance(node[1], bytes):
            _fail("typed-arity")
        return Octets(node[1])
    if tag == b"symbol":
        if len(node) != 2 or not isinstance(node[1], bytes):
            _fail("typed-arity")
        return Symbol(_check_symbol(node[1], limits))
    if tag == b"list":
        return ListValue(tuple(_typed(item, limits) for item in node[1:]))
    if tag == b"record":
        fields: list[tuple[bytes, Value]] = []
        previous: bytes | None = None
        for entry in node[1:]:
            if (
                not isinstance(entry, tuple)
                or len(entry) != 2
                or not isinstance(entry[0], bytes)
            ):
                _fail("record-entry")
            key = _check_symbol(entry[0], limits)
            if previous is not None:
                if key == previous:
                    _fail("record-duplicate")
                if key < previous:
                    _fail("record-order")
            previous = key
            fields.append((key, _typed(entry[1], limits)))
        return Record(tuple(fields))
    _fail("typed-tag")


def decode_payload(payload: bytes, limits: Limits = Limits()) -> Value:
    if len(payload) > limits.max_frame:
        _fail("frame-too-large")
    return _typed(_Parser(payload, limits).parse(), limits)


def _frame_prefix(data: bytes, limits: Limits) -> tuple[int, int] | None:
    if not data:
        return None
    if not 48 <= data[0] <= 57:
        _fail("frame-length")
    colon = data.find(b":")
    if colon < 0:
        if len(data) > len(str(limits.max_frame)):
            _fail("frame-length")
        if any(b < 48 or b > 57 for b in data):
            _fail("frame-length")
        return None
    digits = data[:colon]
    if not digits or any(b < 48 or b > 57 for b in digits):
        _fail("frame-length")
    if len(digits) > 1 and digits[0] == 48:
        _fail("frame-leading-zero")
    length = 0
    for digit in digits:
        length = length * 10 + digit - 48
        if length > limits.max_frame:
            _fail("frame-too-large")
    return colon + 1, length


def _take_frame(data: bytes, limits: Limits) -> tuple[Value, bytes] | None:
    prefix = _frame_prefix(data, limits)
    if prefix is None:
        return None
    body_start, length = prefix
    comma = body_start + length
    if len(data) <= comma:
        return None
    if data[comma] != 44:
        _fail("frame-comma")
    return decode_payload(data[body_start:comma], limits), data[comma + 1 :]


def decode_frame(data: bytes, limits: Limits = Limits()) -> Value:
    result = _take_frame(data, limits)
    if result is None:
        _fail("frame-truncated")
    value, rest = result
    if rest:
        _fail("frame-trailing")
    return value


class FrameDecoder:
    """Incremental outer decoder; feed accepts any input chunking."""

    def __init__(self, limits: Limits = Limits()):
        self.limits = limits
        self.buffer = b""

    def feed(self, chunk: bytes) -> list[Value]:
        if not isinstance(chunk, bytes):
            _fail("chunk-type")
        self.buffer += chunk
        values: list[Value] = []
        while True:
            result = _take_frame(self.buffer, self.limits)
            if result is None:
                return values
            value, self.buffer = result
            values.append(value)

    def finish(self) -> None:
        if self.buffer:
            _fail("frame-truncated")


def decode_chunks(chunks: Iterable[bytes], limits: Limits = Limits()) -> list[Value]:
    decoder = FrameDecoder(limits)
    values: list[Value] = []
    for chunk in chunks:
        values.extend(decoder.feed(chunk))
    decoder.finish()
    return values


def load_fixtures(path: Path) -> list[tuple[str, str, bytes, str | None]]:
    fixtures = []
    for number, line in enumerate(path.read_text("ascii").splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        if len(parts) not in (3, 4) or parts[0] not in ("V", "X"):
            raise RuntimeError(f"bad fixture line {number}")
        kind, name, raw_hex = parts[:3]
        expected = parts[3] if len(parts) == 4 else None
        if kind == "V" and expected is not None:
            raise RuntimeError(f"valid fixture has error on line {number}")
        if kind == "X" and not expected:
            raise RuntimeError(f"invalid fixture lacks error on line {number}")
        try:
            raw = bytes.fromhex(raw_hex)
        except ValueError as exc:
            raise RuntimeError(f"bad fixture hex on line {number}") from exc
        if raw.hex() != raw_hex:
            raise RuntimeError(f"fixture hex is not lowercase canonical on line {number}")
        fixtures.append((kind, name, raw, expected))
    return fixtures


def fixture_output(path: Path) -> list[str]:
    output = []
    for kind, name, wire, expected in load_fixtures(path):
        if kind == "V":
            value = decode_frame(wire)
            if encode_frame(value) != wire:
                raise AssertionError(f"{name}: re-encode mismatch")
            # Exhaust every possible two-chunk boundary, including empty chunks.
            for split in range(len(wire) + 1):
                if decode_chunks((wire[:split], wire[split:])) != [value]:
                    raise AssertionError(f"{name}: split {split}")
            if decode_chunks(bytes([b]) for b in wire) != [value]:
                raise AssertionError(f"{name}: byte chunks")
            output.append(f"valid|{name}|{wire.hex()}")
        else:
            try:
                decode_frame(wire)
            except CodecError as exc:
                if exc.code != expected:
                    raise AssertionError(f"{name}: expected {expected}, got {exc.code}")
            else:
                raise AssertionError(f"{name}: unexpectedly accepted")
            output.append(f"reject|{name}|{expected}")
    return output


def _from_json(data: object, limits: Limits) -> Value:
    if data is None:
        return Null()
    if isinstance(data, bool):
        return Bool(data)
    if isinstance(data, int):
        return Integer.parse(str(data).encode("ascii"), limits)
    if isinstance(data, float):
        _fail("value-type")
    if isinstance(data, str):
        return Text(data.encode("utf-8", "strict"))
    if isinstance(data, list):
        return ListValue(tuple(_from_json(item, limits) for item in data))
    if isinstance(data, dict) and list(data) == ["$bytes"] and isinstance(data["$bytes"], str):
        try:
            return Octets(bytes.fromhex(data["$bytes"]))
        except ValueError:
            _fail("json-bytes")
    if isinstance(data, dict) and list(data) == ["$symbol"] and isinstance(data["$symbol"], str):
        return Symbol(data["$symbol"].encode("ascii", "strict"))
    if isinstance(data, dict) and list(data) == ["$int"] and isinstance(data["$int"], str):
        return Integer.parse(data["$int"].encode("ascii", "strict"), limits)
    if isinstance(data, dict) and list(data) == ["$record"] and isinstance(data["$record"], list):
        fields = []
        for field in data["$record"]:
            if not isinstance(field, list) or len(field) != 2 or not isinstance(field[0], str):
                _fail("json-record")
            fields.append((field[0].encode("ascii", "strict"), _from_json(field[1], limits)))
        return Record(tuple(fields))
    _fail("json-value")


def _to_json(value: Value) -> object:
    if isinstance(value, Null):
        return None
    if isinstance(value, Bool):
        return value.value
    if isinstance(value, Integer):
        return {"$int": value.wire.decode("ascii")}
    if isinstance(value, Text):
        return value.utf8.decode("utf-8")
    if isinstance(value, Octets):
        return {"$bytes": value.data.hex()}
    if isinstance(value, Symbol):
        return {"$symbol": value.ascii.decode("ascii")}
    if isinstance(value, ListValue):
        return [_to_json(item) for item in value.values]
    if isinstance(value, Record):
        return {"$record": [[key.decode("ascii"), _to_json(item)] for key, item in value.fields]}
    raise AssertionError(value)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    decode = sub.add_parser("decode", help="decode one lowercase/uppercase hex frame")
    decode.add_argument("hex")
    encode = sub.add_parser("encode", help="encode one tagged JSON value")
    encode.add_argument("json")
    fixtures = sub.add_parser("fixtures", help="run and print shared fixture evidence")
    fixtures.add_argument("path", nargs="?", type=Path, default=Path(__file__).with_name("fixtures.tsv"))
    args = parser.parse_args(argv)
    try:
        if args.command == "decode":
            value = decode_frame(bytes.fromhex(args.hex))
            print(json.dumps(_to_json(value), ensure_ascii=False, separators=(",", ":")))
        elif args.command == "encode":
            value = _from_json(json.loads(args.json), Limits())
            print(encode_frame(value).hex())
        else:
            for line in fixture_output(args.path):
                print(line)
            print("ALL PASS")
    except (CodecError, UnicodeError, ValueError, json.JSONDecodeError) as exc:
        code = exc.code if isinstance(exc, CodecError) else "input-invalid"
        print(f"ERROR {code}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
