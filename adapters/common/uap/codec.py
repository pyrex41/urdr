"""Exact ADR 0002 canonical values and M0 netstring framing."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TypeAlias


@dataclass(frozen=True)
class Limits:
    max_frame: int = 4_096
    max_atom: int = 256
    max_depth: int = 32
    max_nodes: int = 256
    max_integer_digits: int = 255
    max_symbol: int = 64


M0_LIMITS = Limits()


class CodecError(ValueError):
    """Canonical or framing failure identified only by a stable code."""

    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


@dataclass(frozen=True)
class Null:
    pass


NULL = Null()


@dataclass(frozen=True)
class Bool:
    value: bool

    def __post_init__(self) -> None:
        if type(self.value) is not bool:
            raise CodecError("bool-value")


@dataclass(frozen=True)
class Integer:
    """ADR 0003 sign plus little-endian base-10,000 limbs."""

    sign: int
    limbs: tuple[int, ...]

    @classmethod
    def from_int(cls, value: int) -> "Integer":
        if type(value) is not int:
            raise CodecError("integer-representation")
        if value == 0:
            return cls(0, ())
        sign = -1 if value < 0 else 1
        magnitude = abs(value)
        limbs = []
        while magnitude:
            magnitude, limb = divmod(magnitude, 10_000)
            limbs.append(limb)
        return cls(sign, tuple(limbs))

    @classmethod
    def parse(cls, raw: bytes, limits: Limits = M0_LIMITS) -> "Integer":
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

    def render(self, limits: Limits = M0_LIMITS) -> bytes:
        if type(self.sign) is not int or not isinstance(self.limbs, tuple):
            raise CodecError("integer-representation")
        if self.sign == 0:
            if self.limbs:
                raise CodecError("integer-representation")
            return b"0"
        if self.sign not in (-1, 1) or not self.limbs:
            raise CodecError("integer-representation")
        if (
            self.limbs[-1] == 0
            or any(type(limb) is not int or not 0 <= limb <= 9_999 for limb in self.limbs)
        ):
            raise CodecError("integer-representation")
        magnitude = str(self.limbs[-1]) + "".join(
            f"{limb:04d}" for limb in reversed(self.limbs[:-1])
        )
        if len(magnitude) > limits.max_integer_digits:
            raise CodecError("integer-too-large")
        return (b"-" if self.sign < 0 else b"") + magnitude.encode("ascii")

    def small_nonnegative(self) -> int:
        if self.sign == 0 and not self.limbs:
            return 0
        if self.sign != 1 or len(self.limbs) != 1:
            raise CodecError("integer-range")
        return self.limbs[0]


@dataclass(frozen=True)
class Text:
    utf8: bytes


@dataclass(frozen=True)
class Octets:
    data: bytes


@dataclass(frozen=True)
class Symbol:
    ascii: bytes

    @classmethod
    def named(cls, name: str) -> "Symbol":
        try:
            raw = name.encode("ascii")
        except UnicodeEncodeError as error:
            raise CodecError("symbol-invalid") from error
        return cls(raw)


@dataclass(frozen=True)
class ListValue:
    values: tuple["Value", ...]


@dataclass(frozen=True)
class Record:
    fields: tuple[tuple[bytes, "Value"], ...]


Value: TypeAlias = Null | Bool | Integer | Text | Octets | Symbol | ListValue | Record
Node: TypeAlias = bytes | tuple["Node", ...]


def text(value: str) -> Text:
    return Text(value.encode("utf-8"))


def record(**fields: Value) -> Record:
    """Build a record sorted by the fixed unsigned-ASCII key order."""

    return Record(tuple(sorted((key.replace("_", "-").encode("ascii"), value) for key, value in fields.items())))


def field(value: Record, name: str) -> Value:
    raw = name.encode("ascii")
    for key, item in value.fields:
        if key == raw:
            return item
    raise CodecError("schema-field")


def _check_utf8(raw: bytes) -> bytes:
    if not isinstance(raw, bytes):
        raise CodecError("value-type")
    try:
        raw.decode("utf-8", "strict")
    except UnicodeDecodeError as error:
        raise CodecError("utf8-invalid") from error
    return raw


def _check_symbol(raw: bytes, limits: Limits) -> bytes:
    if not isinstance(raw, bytes):
        raise CodecError("value-type")
    if len(raw) > limits.max_symbol:
        raise CodecError("symbol-too-large")
    if (
        not raw
        or not (65 <= raw[0] <= 90 or 97 <= raw[0] <= 122)
        or any(
            not (
                65 <= byte <= 90
                or 97 <= byte <= 122
                or 48 <= byte <= 57
                or byte in b"._/-"
            )
            for byte in raw[1:]
        )
    ):
        raise CodecError("symbol-invalid")
    return raw


def _atom(raw: bytes, limits: Limits) -> bytes:
    if not isinstance(raw, bytes):
        raise CodecError("value-type")
    if len(raw) > limits.max_atom:
        raise CodecError("atom-too-large")
    return str(len(raw)).encode("ascii") + b":" + raw


class _Parser:
    def __init__(self, payload: bytes, limits: Limits) -> None:
        self.payload = payload
        self.limits = limits
        self.position = 0
        self.nodes = 0

    def parse(self) -> Node:
        node = self._node(1)
        if self.position != len(self.payload):
            raise CodecError("payload-trailing")
        return node

    def _node(self, depth: int) -> Node:
        self.nodes += 1
        if self.nodes > self.limits.max_nodes:
            raise CodecError("nodes-too-many")
        if self.position >= len(self.payload):
            raise CodecError("csexp-truncated")
        first = self.payload[self.position]
        if first == 40:
            if depth > self.limits.max_depth:
                raise CodecError("depth-too-large")
            self.position += 1
            items: list[Node] = []
            while True:
                if self.position >= len(self.payload):
                    raise CodecError("list-unclosed")
                if self.payload[self.position] == 41:
                    self.position += 1
                    return tuple(items)
                items.append(self._node(depth + 1))
        if 48 <= first <= 57:
            return self._parse_atom()
        raise CodecError("csexp-token")

    def _parse_atom(self) -> bytes:
        start = self.position
        while self.position < len(self.payload) and 48 <= self.payload[self.position] <= 57:
            self.position += 1
        digits = self.payload[start : self.position]
        if len(digits) > 1 and digits[0] == 48:
            raise CodecError("length-leading-zero")
        if self.position >= len(self.payload) or self.payload[self.position] != 58:
            raise CodecError("length-colon")
        length = 0
        for digit in digits:
            length = length * 10 + digit - 48
            if length > self.limits.max_atom:
                raise CodecError("atom-too-large")
        self.position += 1
        end = self.position + length
        if end > len(self.payload):
            raise CodecError("atom-truncated")
        raw = self.payload[self.position : end]
        self.position = end
        return raw


def _typed(node: Node, limits: Limits) -> Value:
    if not isinstance(node, tuple) or not node or not isinstance(node[0], bytes):
        raise CodecError("typed-list")
    tag = node[0]
    if tag == b"null":
        if len(node) != 1:
            raise CodecError("typed-arity")
        return NULL
    if tag == b"bool":
        if len(node) != 2 or not isinstance(node[1], bytes):
            raise CodecError("typed-arity")
        if node[1] == b"true":
            return Bool(True)
        if node[1] == b"false":
            return Bool(False)
        raise CodecError("bool-value")
    if tag == b"int":
        if len(node) != 2 or not isinstance(node[1], bytes):
            raise CodecError("typed-arity")
        return Integer.parse(node[1], limits)
    if tag == b"text":
        if len(node) != 2 or not isinstance(node[1], bytes):
            raise CodecError("typed-arity")
        return Text(_check_utf8(node[1]))
    if tag == b"bytes":
        if len(node) != 2 or not isinstance(node[1], bytes):
            raise CodecError("typed-arity")
        return Octets(node[1])
    if tag == b"symbol":
        if len(node) != 2 or not isinstance(node[1], bytes):
            raise CodecError("typed-arity")
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
                raise CodecError("record-entry")
            key = _check_symbol(entry[0], limits)
            if previous is not None:
                if key == previous:
                    raise CodecError("record-duplicate")
                if key < previous:
                    raise CodecError("record-order")
            previous = key
            fields.append((key, _typed(entry[1], limits)))
        return Record(tuple(fields))
    raise CodecError("typed-tag")


class CanonicalCodec:
    """The single accepted M0 codec; no per-connection codec negotiation."""

    name = b"urdr-rfc9804-v1"

    def __init__(self, limits: Limits = M0_LIMITS) -> None:
        self.limits = limits

    def decode_payload(self, payload: bytes) -> Value:
        if len(payload) > self.limits.max_frame:
            raise CodecError("frame-too-large")
        return _typed(_Parser(payload, self.limits).parse(), self.limits)

    def encode_payload(self, value: Value) -> bytes:
        def encode(current: Value, depth: int) -> bytes:
            if depth > self.limits.max_depth:
                raise CodecError("depth-too-large")
            if isinstance(current, Null):
                return b"(" + _atom(b"null", self.limits) + b")"
            if isinstance(current, Bool):
                return (
                    b"("
                    + _atom(b"bool", self.limits)
                    + _atom(b"true" if current.value else b"false", self.limits)
                    + b")"
                )
            if isinstance(current, Integer):
                return (
                    b"("
                    + _atom(b"int", self.limits)
                    + _atom(current.render(self.limits), self.limits)
                    + b")"
                )
            if isinstance(current, Text):
                return (
                    b"("
                    + _atom(b"text", self.limits)
                    + _atom(_check_utf8(current.utf8), self.limits)
                    + b")"
                )
            if isinstance(current, Octets):
                if not isinstance(current.data, bytes):
                    raise CodecError("value-type")
                return b"(" + _atom(b"bytes", self.limits) + _atom(current.data, self.limits) + b")"
            if isinstance(current, Symbol):
                return (
                    b"("
                    + _atom(b"symbol", self.limits)
                    + _atom(_check_symbol(current.ascii, self.limits), self.limits)
                    + b")"
                )
            if isinstance(current, ListValue):
                if not isinstance(current.values, tuple):
                    raise CodecError("value-type")
                return (
                    b"("
                    + _atom(b"list", self.limits)
                    + b"".join(encode(item, depth + 1) for item in current.values)
                    + b")"
                )
            if isinstance(current, Record):
                if not isinstance(current.fields, tuple) or any(
                    not isinstance(entry, tuple) or len(entry) != 2
                    for entry in current.fields
                ):
                    raise CodecError("record-entry")
                output = [b"(", _atom(b"record", self.limits)]
                previous: bytes | None = None
                for key, item in current.fields:
                    key = _check_symbol(key, self.limits)
                    if previous is not None:
                        if key == previous:
                            raise CodecError("record-duplicate")
                        if key < previous:
                            raise CodecError("record-order")
                    previous = key
                    output.extend((b"(", _atom(key, self.limits), encode(item, depth + 1), b")"))
                output.append(b")")
                return b"".join(output)
            raise CodecError("value-type")

        payload = encode(value, 1)
        if len(payload) > self.limits.max_frame:
            raise CodecError("frame-too-large")
        _Parser(payload, self.limits).parse()
        return payload

    def encode_frame(self, value: Value) -> bytes:
        payload = self.encode_payload(value)
        return str(len(payload)).encode("ascii") + b":" + payload + b","

    def decode_frame(self, data: bytes) -> Value:
        if not isinstance(data, bytes):
            raise CodecError("value-type")
        if not data:
            raise CodecError("frame-truncated")
        if not 48 <= data[0] <= 57:
            raise CodecError("frame-length")
        colon = data.find(b":")
        if colon < 0:
            if (
                len(data) > len(str(self.limits.max_frame))
                or any(byte < 48 or byte > 57 for byte in data)
            ):
                raise CodecError("frame-length")
            raise CodecError("frame-truncated")
        digits = data[:colon]
        if not digits or any(byte < 48 or byte > 57 for byte in digits):
            raise CodecError("frame-length")
        if len(digits) > 1 and digits[0] == 48:
            raise CodecError("frame-leading-zero")
        length = 0
        for digit in digits:
            length = length * 10 + digit - 48
            if length > self.limits.max_frame:
                raise CodecError("frame-too-large")
        payload_start = colon + 1
        comma = payload_start + length
        if len(data) <= comma:
            raise CodecError("frame-truncated")
        if data[comma] != 44:
            raise CodecError("frame-comma")
        if len(data) != comma + 1:
            raise CodecError("frame-trailing")
        return self.decode_payload(data[payload_start:comma])
