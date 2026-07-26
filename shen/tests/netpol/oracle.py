"""Independent oracle for the ADR 0004 Decision 4 NetworkPolicy compiler.

This file shares no code with `shen/world/netpol.shen`. It carries its own
canonical S-expression codec (ADR 0002 profile), its own manifest and
universe validators with the same stable error codes, its own selector
resolution, CIDR arithmetic, and NetKAT term builder, and its own
predicate denotation over the compiled header space. Agreement with the
Shen compiler is therefore evidence rather than a tautology.

Usage:

    python3 oracle.py generate        rewrite the fixture corpus
    python3 oracle.py check           recompute every checked-in
                                      expectation from the fixture inputs
    python3 oracle.py emit            print the semantic lines the Shen
                                      suite must reproduce byte for byte

The fixture corpus lives in protocol/fixtures/v1/netpol/.

Nothing here claims CNI fidelity: every compiled result carries the
`spec-semantics-only` marker required by ADR 0004 Decision 4.
"""

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
FIXTURES = ROOT / "protocol" / "fixtures" / "v1" / "netpol"

# ADR 0002 resource profile, re-stated here rather than imported.
MAX_FRAME = 4096
MAX_ATOM = 256
MAX_DEPTH = 32
MAX_NODES = 256
MAX_SYMBOL = 64

# ADR 0004 Decision 2 profile, re-stated here rather than imported.
MAX_FIELDS = 8
MAX_FIELD_VALUES = 64
MAX_SPACE = 1024
MAX_TERM_NODES = 1024

SYMBOL_RE = re.compile(rb"[A-Za-z][A-Za-z0-9._/-]*\Z")
INTEGER_RE = re.compile(rb"0|-?[1-9][0-9]*\Z")

MARKER = b"spec-semantics-only"
CHUNK = 64


class Reject(Exception):
    """A stable rejection code, deliberately independent of prose."""

    def __init__(self, code: str) -> None:
        self.code = code
        super().__init__(code)


# ---------------------------------------------------------------
# Canonical values (ADR 0002 typed profile)
# ---------------------------------------------------------------
#   ("null",) ("bool", bool) ("int", int) ("text", bytes)
#   ("bytes", bytes) ("symbol", bytes) ("list", [value])
#   ("record", [(bytes, value)])


def atom(payload: bytes) -> bytes:
    if len(payload) > MAX_ATOM:
        raise Reject("atom-too-large")
    return str(len(payload)).encode("ascii") + b":" + payload


def encode(value: tuple, ordered: bool = True) -> bytes:
    kind = value[0]
    if kind == "null":
        return b"(" + atom(b"null") + b")"
    if kind == "bool":
        return b"(" + atom(b"bool") + atom(b"true" if value[1] else b"false") + b")"
    if kind == "int":
        return b"(" + atom(b"int") + atom(render_integer(value[1])) + b")"
    if kind in ("text", "bytes"):
        return b"(" + atom(kind.encode("ascii")) + atom(value[1]) + b")"
    if kind == "symbol":
        if len(value[1]) > MAX_SYMBOL or not SYMBOL_RE.fullmatch(value[1]):
            raise Reject("symbol-invalid")
        return b"(" + atom(b"symbol") + atom(value[1]) + b")"
    if kind == "list":
        body = b"".join(encode(item, ordered) for item in value[1])
        return b"(" + atom(b"list") + body + b")"
    if kind == "record":
        body = b""
        previous: bytes | None = None
        for key, item in value[1]:
            if len(key) > MAX_SYMBOL or not SYMBOL_RE.fullmatch(key):
                raise Reject("symbol-invalid")
            if ordered and previous is not None:
                if key == previous:
                    raise Reject("record-duplicate")
                if key < previous:
                    raise Reject("record-order")
            previous = key
            body += b"(" + atom(key) + encode(item, ordered) + b")"
        return b"(" + atom(b"record") + body + b")"
    raise Reject("value-type")


def render_integer(number: int) -> bytes:
    if isinstance(number, bool) or not isinstance(number, int):
        raise Reject("value-type")
    return str(number).encode("ascii")


def encode_frame(value: tuple, ordered: bool = True) -> bytes:
    payload = encode(value, ordered)
    if len(payload) > MAX_FRAME:
        raise Reject("frame-too-large")
    frame = str(len(payload)).encode("ascii") + b":" + payload + b","
    if ordered:
        # ADR 0002 makes the decoder's node and depth budgets encoder
        # budgets too by reparsing the completed payload before return.
        decode_frame(frame)
    return frame


class Reader:
    def __init__(self, data: bytes) -> None:
        self.data = data
        self.at = 0

    def take(self, count: int) -> bytes:
        if self.at + count > len(self.data):
            raise Reject("truncated")
        chunk = self.data[self.at : self.at + count]
        self.at += count
        return chunk

    def peek(self) -> int:
        if self.at >= len(self.data):
            raise Reject("truncated")
        return self.data[self.at]

    def length(self, limit: int) -> int:
        digits = b""
        while self.peek() != 0x3A:
            byte = self.take(1)
            if not byte.isdigit():
                raise Reject("length-invalid")
            digits += byte
        self.take(1)
        if not digits or (digits[0:1] == b"0" and digits != b"0"):
            raise Reject("length-leading-zero")
        size = int(digits)
        if size > limit:
            raise Reject("atom-too-large")
        return size

    def atom(self) -> bytes:
        return self.take(self.length(MAX_ATOM))


def parse_node(reader: Reader, depth: int, nodes: int) -> tuple[tuple, int]:
    if reader.peek() == 0x28:
        if depth > MAX_DEPTH:
            raise Reject("depth-too-large")
        if nodes >= MAX_NODES:
            raise Reject("nodes-too-many")
        reader.take(1)
        nodes += 1
        items = []
        while reader.peek() != 0x29:
            item, nodes = parse_node(reader, depth + 1, nodes)
            items.append(item)
        reader.take(1)
        return (("list-node", items), nodes)
    if nodes >= MAX_NODES:
        raise Reject("nodes-too-many")
    return (("atom-node", reader.atom()), nodes + 1)


def typed(node: tuple) -> tuple:
    if node[0] != "list-node" or not node[1] or node[1][0][0] != "atom-node":
        raise Reject("typed-list")
    tag = node[1][0][1]
    arguments = node[1][1:]
    if tag in (b"null", b"bool", b"int", b"text", b"bytes", b"symbol"):
        if tag == b"null":
            if arguments:
                raise Reject("typed-arity")
            return ("null",)
        if len(arguments) != 1 or arguments[0][0] != "atom-node":
            raise Reject("typed-arity")
        raw = arguments[0][1]
        if tag == b"bool":
            if raw not in (b"true", b"false"):
                raise Reject("bool-value")
            return ("bool", raw == b"true")
        if tag == b"int":
            if not INTEGER_RE.fullmatch(raw):
                raise Reject("integer-invalid")
            return ("int", int(raw))
        if tag == b"symbol":
            if len(raw) > MAX_SYMBOL or not SYMBOL_RE.fullmatch(raw):
                raise Reject("symbol-invalid")
            return ("symbol", raw)
        return (tag.decode("ascii"), raw)
    if tag == b"list":
        return ("list", [typed(item) for item in arguments])
    if tag == b"record":
        fields: list[tuple[bytes, tuple]] = []
        previous: bytes | None = None
        for entry in arguments:
            if (
                entry[0] != "list-node"
                or len(entry[1]) != 2
                or entry[1][0][0] != "atom-node"
            ):
                raise Reject("record-entry")
            key = entry[1][0][1]
            if len(key) > MAX_SYMBOL or not SYMBOL_RE.fullmatch(key):
                raise Reject("symbol-invalid")
            if previous is not None:
                if key == previous:
                    raise Reject("record-duplicate")
                if key < previous:
                    raise Reject("record-order")
            previous = key
            fields.append((key, typed(entry[1][1])))
        return ("record", fields)
    raise Reject("typed-tag")


def decode_frame(data: bytes) -> tuple:
    reader = Reader(data)
    size = reader.length(MAX_FRAME)
    payload = reader.take(size)
    if reader.take(1) != b",":
        raise Reject("frame-comma")
    if reader.at != len(data):
        raise Reject("frame-trailing")
    inner = Reader(payload)
    node, _ = parse_node(inner, 1, 0)
    if inner.at != len(payload):
        raise Reject("payload-trailing")
    return typed(node)


# ---------------------------------------------------------------
# NetKAT terms (the predicate fragment the compiler emits)
# ---------------------------------------------------------------

DROP = ("drop",)
ID = ("id",)

DST_POD = b"dst-pod"
DST_PORT = b"dst-port"
PROTOCOL = b"protocol"
SRC_POD = b"src-pod"
VOCAB_FIELDS = (DST_POD, DST_PORT, PROTOCOL, SRC_POD)


def test_term(field: bytes, number: int) -> tuple:
    return ("test", field, number)


def mk_union(left: tuple, right: tuple) -> tuple:
    """Union of two predicates, with the identities the compiler relies on.

    Sound only for predicates: a predicate's output is either the input
    packet or nothing, so `p + 1 = 1` holds.
    """
    if left == DROP:
        return right
    if right == DROP:
        return left
    if left == ID or right == ID:
        return ID
    if left == right:
        return left
    return ("union", left, right)


def mk_seq(left: tuple, right: tuple) -> tuple:
    if left == DROP or right == DROP:
        return DROP
    if left == ID:
        return right
    if right == ID:
        return left
    if left == right:
        return left
    return ("seq", left, right)


def mk_neg(inner: tuple) -> tuple:
    if inner == DROP:
        return ID
    if inner == ID:
        return DROP
    return ("neg", inner)


def union_all(terms: list[tuple]) -> tuple:
    result = DROP
    for term in reversed(terms):
        result = mk_union(term, result)
    return result


def value_set_predicate(field: bytes, chosen: list[int], declared: list[int]) -> tuple:
    """`field in chosen`, collapsed to id/drop at the vocabulary edges."""
    picked = [value for value in declared if value in chosen]
    if not picked:
        return DROP
    if len(picked) == len(declared):
        return ID
    return union_all([test_term(field, value) for value in picked])


def term_nodes(term: tuple) -> int:
    kind = term[0]
    if kind in ("drop", "id", "test"):
        return 1
    if kind in ("union", "seq"):
        return 1 + term_nodes(term[1]) + term_nodes(term[2])
    return 1 + term_nodes(term[1])


def render_term(term: tuple) -> bytes:
    kind = term[0]
    if kind == "drop":
        return b"0"
    if kind == "id":
        return b"1"
    if kind == "test":
        return b"(?" + term[1] + b"=" + str(term[2]).encode("ascii") + b")"
    if kind == "union":
        return b"(+" + render_term(term[1]) + render_term(term[2]) + b")"
    if kind == "seq":
        return b"(;" + render_term(term[1]) + render_term(term[2]) + b")"
    if kind == "neg":
        return b"(~" + render_term(term[1]) + b")"
    raise Reject("term-head")


def holds(term: tuple, packet: dict[bytes, int]) -> bool:
    kind = term[0]
    if kind == "drop":
        return False
    if kind == "id":
        return True
    if kind == "test":
        return packet[term[1]] == term[2]
    if kind == "union":
        return holds(term[1], packet) or holds(term[2], packet)
    if kind == "seq":
        return holds(term[1], packet) and holds(term[2], packet)
    if kind == "neg":
        return not holds(term[1], packet)
    raise Reject("term-head")


def check_vocabulary(fields: list[tuple[bytes, list[int]]]) -> int:
    """The Decision 2 vocabulary budget, re-checked on compiler output."""
    if not fields:
        raise Reject("vocab-empty")
    space = 1
    previous: bytes | None = None
    for index, (key, values) in enumerate(fields):
        if previous is not None and not key > previous:
            raise Reject("vocab-field-order")
        previous = key
        if not values:
            raise Reject("vocab-values-empty")
        if len(values) > MAX_FIELD_VALUES:
            raise Reject("vocab-too-many-values")
        if index >= MAX_FIELDS:
            raise Reject("vocab-too-many-fields")
        space *= len(values)
        if space > MAX_SPACE:
            raise Reject("vocab-space-too-large")
    return space


def check_term(fields: list[tuple[bytes, list[int]]], term: tuple, nodes: int) -> int:
    if nodes >= MAX_TERM_NODES:
        raise Reject("term-too-large")
    nodes += 1
    kind = term[0]
    if kind in ("drop", "id"):
        return nodes
    if kind == "test":
        declared = dict(fields).get(term[1])
        if declared is None:
            raise Reject("term-field-unknown")
        if term[2] not in declared:
            raise Reject("term-value-unknown")
        return nodes
    if kind in ("union", "seq"):
        return check_term(fields, term[2], check_term(fields, term[1], nodes))
    return check_term(fields, term[1], nodes)


def header_space(fields: list[tuple[bytes, list[int]]]) -> list[dict[bytes, int]]:
    space: list[dict[bytes, int]] = [{}]
    for key, values in reversed(fields):
        space = [{key: value, **suffix} for value in values for suffix in space]
    return space


# ---------------------------------------------------------------
# Canonical accessors
# ---------------------------------------------------------------


def as_record(value: tuple, code: str) -> list[tuple[bytes, tuple]]:
    if value[0] != "record":
        raise Reject(code)
    return value[1]


def as_list(value: tuple, code: str) -> list[tuple]:
    if value[0] != "list":
        raise Reject(code)
    return value[1]


def as_text(value: tuple, code: str) -> bytes:
    if value[0] != "text":
        raise Reject(code)
    return value[1]


def as_int(value: tuple, code: str) -> int:
    if value[0] != "int":
        raise Reject(code)
    return value[1]


def as_symbol(value: tuple, code: str) -> bytes:
    if value[0] != "symbol":
        raise Reject(code)
    return value[1]


def as_bool(value: tuple, code: str) -> bool:
    if value[0] != "bool":
        raise Reject(code)
    return value[1]


def fields_of(
    entries: list[tuple[bytes, tuple]],
    allowed: set[bytes],
    required: set[bytes],
    unmodeled: str,
    missing: str,
) -> dict[bytes, tuple]:
    table: dict[bytes, tuple] = {}
    for key, value in entries:
        if key not in allowed:
            raise Reject(unmodeled)
        table[key] = value
    for key in sorted(required):
        if key not in table:
            raise Reject(missing)
    return table


# ---------------------------------------------------------------
# IPv4 addresses and CIDR containment
# ---------------------------------------------------------------

OCTET_RE = re.compile(rb"0|[1-9][0-9]{0,2}\Z")
SHIFT = {0: 1, 1: 2, 2: 4, 3: 8, 4: 16, 5: 32, 6: 64, 7: 128}


def parse_address(raw: bytes) -> tuple[int, int, int, int]:
    if b":" in raw:
        raise Reject("address-unmodeled")
    parts = raw.split(b".")
    if len(parts) != 4:
        raise Reject("address-malformed")
    octets = []
    for part in parts:
        if not OCTET_RE.fullmatch(part):
            raise Reject("address-malformed")
        number = int(part)
        if number > 255:
            raise Reject("address-malformed")
        octets.append(number)
    return tuple(octets)


def parse_cidr(raw: bytes) -> tuple[tuple[int, int, int, int], int]:
    if b":" in raw:
        raise Reject("address-unmodeled")
    parts = raw.split(b"/")
    if len(parts) != 2:
        raise Reject("cidr-malformed")
    if not OCTET_RE.fullmatch(parts[1]):
        raise Reject("cidr-malformed")
    length = int(parts[1])
    if length > 32:
        raise Reject("cidr-malformed")
    try:
        network = parse_address(parts[0])
    except Reject as rejection:
        if rejection.code == "address-unmodeled":
            raise
        raise Reject("cidr-malformed") from rejection
    return (network, length)


def contained(address: tuple[int, ...], network: tuple[int, ...], length: int) -> bool:
    """First `length` bits of `address` equal those of `network`.

    Only octet-sized values and a fixed shift table are used, so no host
    integer wider than a byte ever participates.
    """
    full = length // 8
    rest = length - full * 8
    for index in range(full):
        if address[index] != network[index]:
            return False
    if rest == 0:
        return True
    divisor = SHIFT[8 - rest]
    return address[full] // divisor == network[full] // divisor


# ---------------------------------------------------------------
# The declared universe
# ---------------------------------------------------------------

PROTOCOL_CODE = {b"TCP": 6, b"UDP": 17, b"SCTP": 132}
LABEL_RE = re.compile(rb"[A-Za-z0-9]([A-Za-z0-9._/-]{0,61}[A-Za-z0-9])?\Z")
PORT_NAME_RE = re.compile(rb"[a-z0-9]([a-z0-9-]{0,13}[a-z0-9])?\Z")

UNIVERSE_KEYS = {b"externals", b"namespaces", b"pods", b"ports", b"protocols"}
UNIVERSE_REQUIRED = {b"namespaces", b"pods", b"ports", b"protocols"}
NAMESPACE_KEYS = {b"labels", b"name"}
POD_KEYS = {b"address", b"host-network", b"labels", b"name", b"namespace", b"ports"}
EXTERNAL_KEYS = {b"address", b"name"}


def read_labels(value: tuple) -> dict[bytes, bytes]:
    labels: dict[bytes, bytes] = {}
    for key, item in as_record(value, "universe-shape"):
        if not LABEL_RE.fullmatch(key):
            raise Reject("label-invalid")
        text = as_text(item, "universe-shape")
        if not LABEL_RE.fullmatch(text):
            raise Reject("label-invalid")
        labels[key] = text
    return labels


class Endpoint:
    def __init__(
        self,
        index: int,
        name: bytes,
        namespace: bytes | None,
        address: tuple[int, ...],
        labels: dict[bytes, bytes],
        ports: dict[bytes, int],
        host_network: bool,
    ) -> None:
        self.index = index
        self.name = name
        self.namespace = namespace
        self.address = address
        self.labels = labels
        self.ports = ports
        self.host_network = host_network

    @property
    def is_pod(self) -> bool:
        return self.namespace is not None


class Universe:
    def __init__(self, value: tuple) -> None:
        table = fields_of(
            as_record(value, "universe-shape"),
            UNIVERSE_KEYS,
            UNIVERSE_REQUIRED,
            "universe-unmodeled-field",
            "universe-missing-field",
        )
        self.ports = self._read_ports(table[b"ports"])
        self.protocols = self._read_protocols(table[b"protocols"])
        self.namespaces = self._read_namespaces(table[b"namespaces"])
        self.endpoints: list[Endpoint] = []
        self._read_pods(table[b"pods"])
        if b"externals" in table:
            self._read_externals(table[b"externals"])
        if not self.endpoints:
            raise Reject("universe-endpoints-empty")
        seen: set[tuple[int, ...]] = set()
        for endpoint in self.endpoints:
            if endpoint.address in seen:
                raise Reject("universe-address-duplicate")
            seen.add(endpoint.address)
        self.named_ports: set[bytes] = set()
        for endpoint in self.endpoints:
            self.named_ports |= set(endpoint.ports)

    def _read_ports(self, value: tuple) -> list[int]:
        ports: list[int] = []
        previous: int | None = None
        for item in as_list(value, "universe-shape"):
            number = as_int(item, "universe-shape")
            if number < 1 or number > 65535:
                raise Reject("universe-port-range")
            if previous is not None and number <= previous:
                raise Reject("universe-port-order")
            previous = number
            ports.append(number)
        if not ports:
            raise Reject("universe-ports-empty")
        return ports

    def _read_protocols(self, value: tuple) -> list[int]:
        codes: list[int] = []
        previous: int | None = None
        for item in as_list(value, "universe-shape"):
            name = as_symbol(item, "universe-shape")
            if name not in PROTOCOL_CODE:
                raise Reject("protocol-unknown")
            code = PROTOCOL_CODE[name]
            if previous is not None and code <= previous:
                raise Reject("universe-protocol-order")
            previous = code
            codes.append(code)
        if not codes:
            raise Reject("universe-protocols-empty")
        return codes

    def _read_namespaces(self, value: tuple) -> dict[bytes, dict[bytes, bytes]]:
        namespaces: dict[bytes, dict[bytes, bytes]] = {}
        previous: bytes | None = None
        for item in as_list(value, "universe-shape"):
            table = fields_of(
                as_record(item, "universe-shape"),
                NAMESPACE_KEYS,
                {b"name"},
                "universe-unmodeled-field",
                "universe-missing-field",
            )
            name = as_text(table[b"name"], "universe-shape")
            if not LABEL_RE.fullmatch(name):
                raise Reject("universe-shape")
            if previous is not None and name <= previous:
                raise Reject("universe-namespace-order")
            previous = name
            labels = read_labels(table[b"labels"]) if b"labels" in table else {}
            namespaces[name] = labels
        if not namespaces:
            raise Reject("universe-namespaces-empty")
        return namespaces

    def _read_pods(self, value: tuple) -> None:
        previous: tuple[bytes, bytes] | None = None
        for item in as_list(value, "universe-shape"):
            table = fields_of(
                as_record(item, "universe-shape"),
                POD_KEYS,
                {b"address", b"name", b"namespace"},
                "universe-unmodeled-field",
                "universe-missing-field",
            )
            name = as_text(table[b"name"], "universe-shape")
            namespace = as_text(table[b"namespace"], "universe-shape")
            if not LABEL_RE.fullmatch(name) or not LABEL_RE.fullmatch(namespace):
                raise Reject("universe-shape")
            if namespace not in self.namespaces:
                raise Reject("universe-namespace-unknown")
            key = (namespace, name)
            if previous is not None and key <= previous:
                raise Reject("universe-pod-order")
            previous = key
            labels = read_labels(table[b"labels"]) if b"labels" in table else {}
            ports = self._read_container_ports(table.get(b"ports"))
            host = (
                as_bool(table[b"host-network"], "universe-shape")
                if b"host-network" in table
                else False
            )
            self.endpoints.append(
                Endpoint(
                    len(self.endpoints),
                    name,
                    namespace,
                    parse_address(as_text(table[b"address"], "universe-shape")),
                    labels,
                    ports,
                    host,
                )
            )

    def _read_container_ports(self, value: tuple | None) -> dict[bytes, int]:
        if value is None:
            return {}
        ports: dict[bytes, int] = {}
        for key, item in as_record(value, "universe-shape"):
            if not PORT_NAME_RE.fullmatch(key):
                raise Reject("container-port-invalid")
            number = as_int(item, "universe-shape")
            if number not in self.ports:
                raise Reject("container-port-invalid")
            ports[key] = number
        return ports

    def _read_externals(self, value: tuple) -> None:
        previous: bytes | None = None
        for item in as_list(value, "universe-shape"):
            table = fields_of(
                as_record(item, "universe-shape"),
                EXTERNAL_KEYS,
                {b"address", b"name"},
                "universe-unmodeled-field",
                "universe-missing-field",
            )
            name = as_text(table[b"name"], "universe-shape")
            if not LABEL_RE.fullmatch(name):
                raise Reject("universe-shape")
            if previous is not None and name <= previous:
                raise Reject("universe-external-order")
            previous = name
            self.endpoints.append(
                Endpoint(
                    len(self.endpoints),
                    name,
                    None,
                    parse_address(as_text(table[b"address"], "universe-shape")),
                    {},
                    {},
                    False,
                )
            )

    def vocabulary(self) -> list[tuple[bytes, list[int]]]:
        indices = list(range(len(self.endpoints)))
        return [
            (DST_POD, indices),
            (DST_PORT, list(self.ports)),
            (PROTOCOL, list(self.protocols)),
            (SRC_POD, indices),
        ]


# ---------------------------------------------------------------
# Selectors
# ---------------------------------------------------------------

SELECTOR_KEYS = {b"match-expressions", b"match-labels"}
EXPRESSION_KEYS = {b"key", b"operator", b"values"}
OPERATORS = {b"In", b"NotIn", b"Exists", b"DoesNotExist"}


class Selector:
    def __init__(self, value: tuple) -> None:
        table = fields_of(
            as_record(value, "manifest-shape"),
            SELECTOR_KEYS,
            set(),
            "manifest-unmodeled-field",
            "manifest-missing-field",
        )
        self.labels: dict[bytes, bytes] = {}
        if b"match-labels" in table:
            for key, item in as_record(table[b"match-labels"], "manifest-shape"):
                if not LABEL_RE.fullmatch(key):
                    raise Reject("label-invalid")
                text = as_text(item, "manifest-shape")
                if not LABEL_RE.fullmatch(text):
                    raise Reject("label-invalid")
                self.labels[key] = text
        self.expressions: list[tuple[bytes, bytes, list[bytes]]] = []
        if b"match-expressions" in table:
            for item in as_list(table[b"match-expressions"], "manifest-shape"):
                self.expressions.append(self._read_expression(item))

    def _read_expression(self, value: tuple) -> tuple[bytes, bytes, list[bytes]]:
        table = fields_of(
            as_record(value, "manifest-shape"),
            EXPRESSION_KEYS,
            {b"key", b"operator"},
            "manifest-unmodeled-field",
            "manifest-missing-field",
        )
        key = as_text(table[b"key"], "manifest-shape")
        if not LABEL_RE.fullmatch(key):
            raise Reject("label-invalid")
        operator = as_symbol(table[b"operator"], "manifest-shape")
        if operator not in OPERATORS:
            raise Reject("selector-operator-unknown")
        values: list[bytes] = []
        previous: bytes | None = None
        if b"values" in table:
            for item in as_list(table[b"values"], "manifest-shape"):
                text = as_text(item, "manifest-shape")
                if not LABEL_RE.fullmatch(text):
                    raise Reject("label-invalid")
                if previous is not None and text <= previous:
                    raise Reject("selector-values-order")
                previous = text
                values.append(text)
        if operator in (b"In", b"NotIn") and not values:
            raise Reject("selector-values-missing")
        if operator in (b"Exists", b"DoesNotExist") and values:
            raise Reject("selector-values-forbidden")
        return (key, operator, values)

    def matches(self, labels: dict[bytes, bytes]) -> bool:
        for key, value in self.labels.items():
            if labels.get(key) != value:
                return False
        for key, operator, values in self.expressions:
            present = key in labels
            if operator == b"In":
                if not present or labels[key] not in values:
                    return False
            elif operator == b"NotIn":
                if present and labels[key] in values:
                    return False
            elif operator == b"Exists":
                if not present:
                    return False
            else:
                if present:
                    return False
        return True


# ---------------------------------------------------------------
# Manifests
# ---------------------------------------------------------------

POLICY_KEYS = {
    b"egress",
    b"ingress",
    b"name",
    b"namespace",
    b"pod-selector",
    b"policy-types",
}
INGRESS_RULE_KEYS = {b"from", b"ports"}
EGRESS_RULE_KEYS = {b"ports", b"to"}
PEER_KEYS = {b"ip-block", b"namespace-selector", b"pod-selector"}
IPBLOCK_KEYS = {b"cidr", b"except"}
PORT_KEYS = {b"end-port", b"port", b"protocol"}


class IPBlock:
    def __init__(self, value: tuple) -> None:
        table = fields_of(
            as_record(value, "manifest-shape"),
            IPBLOCK_KEYS,
            {b"cidr"},
            "manifest-unmodeled-field",
            "manifest-missing-field",
        )
        self.network, self.length = parse_cidr(
            as_text(table[b"cidr"], "manifest-shape")
        )
        self.excepts: list[tuple[tuple[int, ...], int]] = []
        previous: bytes | None = None
        if b"except" in table:
            for item in as_list(table[b"except"], "manifest-shape"):
                raw = as_text(item, "manifest-shape")
                if previous is not None and raw <= previous:
                    raise Reject("ipblock-except-order")
                previous = raw
                network, length = parse_cidr(raw)
                if length < self.length or not contained(
                    network, self.network, self.length
                ):
                    raise Reject("ipblock-except-outside-cidr")
                self.excepts.append((network, length))


class Peer:
    def __init__(self, value: tuple) -> None:
        table = fields_of(
            as_record(value, "manifest-shape"),
            PEER_KEYS,
            set(),
            "manifest-unmodeled-field",
            "manifest-missing-field",
        )
        if not table:
            raise Reject("peer-empty")
        self.ip_block: IPBlock | None = None
        self.namespace_selector: Selector | None = None
        self.pod_selector: Selector | None = None
        if b"ip-block" in table:
            if b"namespace-selector" in table or b"pod-selector" in table:
                raise Reject("peer-ipblock-exclusive")
            self.ip_block = IPBlock(table[b"ip-block"])
            return
        if b"namespace-selector" in table:
            self.namespace_selector = Selector(table[b"namespace-selector"])
        if b"pod-selector" in table:
            self.pod_selector = Selector(table[b"pod-selector"])


class PortEntry:
    def __init__(self, value: tuple, universe: Universe) -> None:
        table = fields_of(
            as_record(value, "manifest-shape"),
            PORT_KEYS,
            set(),
            "manifest-unmodeled-field",
            "manifest-missing-field",
        )
        name = (
            as_symbol(table[b"protocol"], "manifest-shape")
            if b"protocol" in table
            else b"TCP"
        )
        if name not in PROTOCOL_CODE:
            raise Reject("protocol-unknown")
        self.protocol = PROTOCOL_CODE[name]
        if self.protocol not in universe.protocols:
            raise Reject("protocol-out-of-vocabulary")
        self.named: bytes | None = None
        self.low: int | None = None
        self.high: int | None = None
        port = table.get(b"port")
        if port is not None and port[0] == "text":
            self.named = port[1]
            if not PORT_NAME_RE.fullmatch(self.named):
                raise Reject("named-port-invalid")
            if self.named not in universe.named_ports:
                raise Reject("named-port-unresolved")
        elif port is not None:
            number = as_int(port, "manifest-shape")
            if number < 1 or number > 65535:
                raise Reject("port-range")
            self.low = number
            self.high = number
        if b"end-port" in table:
            end = as_int(table[b"end-port"], "manifest-shape")
            if self.named is not None:
                raise Reject("end-port-named-port")
            if self.low is None:
                raise Reject("end-port-without-port")
            if end < 1 or end > 65535:
                raise Reject("port-range")
            if end < self.low:
                raise Reject("end-port-range")
            self.high = end
        elif self.low is not None and self.named is None:
            if self.low not in universe.ports:
                raise Reject("port-out-of-vocabulary")

    def ports_for(self, universe: Universe, destination: Endpoint | None) -> list[int]:
        if self.named is not None:
            if destination is None:
                raise Reject("named-port-unresolved")
            number = destination.ports.get(self.named)
            return [] if number is None else [number]
        if self.low is None:
            return list(universe.ports)
        return [p for p in universe.ports if self.low <= p <= self.high]

    @property
    def destination_dependent(self) -> bool:
        return self.named is not None


class Rule:
    def __init__(self, value: tuple, universe: Universe, egress: bool) -> None:
        table = fields_of(
            as_record(value, "manifest-shape"),
            EGRESS_RULE_KEYS if egress else INGRESS_RULE_KEYS,
            set(),
            "manifest-unmodeled-field",
            "manifest-missing-field",
        )
        peers = table.get(b"to" if egress else b"from")
        # ADR 0004 Decision 4: an empty or omitted from/to allows all peers.
        self.all_peers = peers is None or not as_list(peers, "manifest-shape")
        self.peers = (
            []
            if self.all_peers
            else [Peer(item) for item in as_list(peers, "manifest-shape")]
        )
        ports = table.get(b"ports")
        # Upstream: an empty or omitted ports list allows all ports.
        self.all_ports = ports is None or not as_list(ports, "manifest-shape")
        self.ports = (
            []
            if self.all_ports
            else [PortEntry(item, universe) for item in as_list(ports, "manifest-shape")]
        )


class Policy:
    def __init__(self, value: tuple, universe: Universe) -> None:
        table = fields_of(
            as_record(value, "manifest-shape"),
            POLICY_KEYS,
            {b"name", b"namespace", b"pod-selector"},
            "manifest-unmodeled-field",
            "manifest-missing-field",
        )
        self.name = as_text(table[b"name"], "manifest-shape")
        self.namespace = as_text(table[b"namespace"], "manifest-shape")
        if not LABEL_RE.fullmatch(self.name) or not LABEL_RE.fullmatch(self.namespace):
            raise Reject("manifest-shape")
        if self.namespace not in universe.namespaces:
            raise Reject("policy-namespace-unknown")
        self.selector = Selector(table[b"pod-selector"])
        self.has_ingress = b"ingress" in table
        self.has_egress = b"egress" in table
        self.ingress = [
            Rule(item, universe, False)
            for item in as_list(table.get(b"ingress", ("list", [])), "manifest-shape")
        ]
        self.egress = [
            Rule(item, universe, True)
            for item in as_list(table.get(b"egress", ("list", [])), "manifest-shape")
        ]
        self.types = self._read_types(table.get(b"policy-types"))

    def _read_types(self, value: tuple | None) -> set[bytes]:
        if value is None:
            # ADR 0004 Decision 4 / upstream defaulting: every policy is
            # assumed to affect ingress; egress only when it has an
            # egress section.
            return {b"Ingress"} | ({b"Egress"} if self.has_egress else set())
        types: list[bytes] = []
        previous: bytes | None = None
        for item in as_list(value, "manifest-shape"):
            name = as_symbol(item, "manifest-shape")
            if name not in (b"Egress", b"Ingress"):
                raise Reject("policy-type-unknown")
            if previous is not None and name <= previous:
                raise Reject("policy-type-order")
            previous = name
            types.append(name)
        return set(types)


def read_policies(value: tuple, universe: Universe) -> list[Policy]:
    policies: list[Policy] = []
    previous: tuple[bytes, bytes] | None = None
    for item in as_list(value, "policies-shape"):
        policy = Policy(item, universe)
        key = (policy.namespace, policy.name)
        if previous is not None and key <= previous:
            raise Reject("policy-order")
        previous = key
        policies.append(policy)
    return policies


# ---------------------------------------------------------------
# Compilation
# ---------------------------------------------------------------


class Compilation:
    def __init__(self, universe: Universe, policies: list[Policy]) -> None:
        self.universe = universe
        self.policies = policies
        if policies:
            for endpoint in universe.endpoints:
                if endpoint.host_network:
                    raise Reject("host-network-pod-under-policy")
        self.fields = universe.vocabulary()
        self.space = check_vocabulary(self.fields)
        self.indices = list(range(len(universe.endpoints)))
        self.isolation = [
            (self.isolated(pod, b"Ingress"), self.isolated(pod, b"Egress"))
            for pod in universe.endpoints
        ]
        self.ingress_side = self.side(b"Ingress")
        self.egress_side = self.side(b"Egress")
        self.term = mk_seq(self.egress_side, self.ingress_side)
        check_term(self.fields, self.term, 0)

    # -- selection ------------------------------------------------

    def selects(self, policy: Policy, endpoint: Endpoint) -> bool:
        return (
            endpoint.is_pod
            and endpoint.namespace == policy.namespace
            and policy.selector.matches(endpoint.labels)
        )

    def isolated(self, endpoint: Endpoint, direction: bytes) -> bool:
        return any(
            direction in policy.types and self.selects(policy, endpoint)
            for policy in self.policies
        )

    # -- peers ----------------------------------------------------

    def peer_term(self, peer: Peer, field: bytes, namespace: bytes) -> tuple:
        if peer.ip_block is not None:
            block = peer.ip_block
            inside = [
                endpoint.index
                for endpoint in self.universe.endpoints
                if contained(endpoint.address, block.network, block.length)
            ]
            excluded = [
                endpoint.index
                for endpoint in self.universe.endpoints
                if any(
                    contained(endpoint.address, network, length)
                    for network, length in block.excepts
                )
            ]
            # ADR 0004: `except` subtracts using predicate negation.
            return mk_seq(
                value_set_predicate(field, inside, self.indices),
                mk_neg(value_set_predicate(field, excluded, self.indices)),
            )
        # AND within one peer element: the namespace side first, then the
        # pod side, exactly as ADR 0004 Decision 4 requires. An omitted
        # namespaceSelector means the policy's own namespace.
        if peer.namespace_selector is None:
            namespaces = [namespace]
        else:
            namespaces = [
                name
                for name, labels in self.universe.namespaces.items()
                if peer.namespace_selector.matches(labels)
            ]
        chosen = [
            endpoint.index
            for endpoint in self.universe.endpoints
            if endpoint.is_pod
            and endpoint.namespace in namespaces
            and (
                peer.pod_selector is None or peer.pod_selector.matches(endpoint.labels)
            )
        ]
        return value_set_predicate(field, chosen, self.indices)

    def peers_term(self, rule: Rule, field: bytes, namespace: bytes) -> tuple:
        if rule.all_peers:
            return ID
        return union_all(
            [self.peer_term(peer, field, namespace) for peer in rule.peers]
        )

    # -- ports ----------------------------------------------------

    def entry_term(self, entry: PortEntry, destination: Endpoint | None) -> tuple:
        chosen = entry.ports_for(self.universe, destination)
        return mk_seq(
            test_term(PROTOCOL, entry.protocol),
            value_set_predicate(DST_PORT, chosen, self.universe.ports),
        )

    def ports_term(self, rule: Rule, destination: Endpoint | None) -> tuple:
        if rule.all_ports:
            return ID
        if destination is not None:
            return union_all(
                [self.entry_term(entry, destination) for entry in rule.ports]
            )
        if not any(entry.destination_dependent for entry in rule.ports):
            return union_all([self.entry_term(entry, None) for entry in rule.ports])
        # Named ports resolve against the destination pod, so the port
        # predicate is distributed over the declared destinations.
        return union_all(
            [
                mk_seq(
                    test_term(DST_POD, endpoint.index),
                    union_all(
                        [self.entry_term(entry, endpoint) for entry in rule.ports]
                    ),
                )
                for endpoint in self.universe.endpoints
            ]
        )

    # -- directions ----------------------------------------------

    def rule_term(self, rule: Rule, policy: Policy, endpoint: Endpoint, direction: bytes) -> tuple:
        if direction == b"Ingress":
            return mk_seq(
                self.peers_term(rule, SRC_POD, policy.namespace),
                self.ports_term(rule, endpoint),
            )
        return mk_seq(
            self.peers_term(rule, DST_POD, policy.namespace),
            self.ports_term(rule, None),
        )

    def allow_term(self, endpoint: Endpoint, direction: bytes) -> tuple:
        if not self.isolated(endpoint, direction):
            return ID
        terms: list[tuple] = []
        for policy in self.policies:
            if direction not in policy.types or not self.selects(policy, endpoint):
                continue
            rules = policy.ingress if direction == b"Ingress" else policy.egress
            for rule in rules:
                terms.append(self.rule_term(rule, policy, endpoint, direction))
        return union_all(terms)

    def side(self, direction: bytes) -> tuple:
        field = DST_POD if direction == b"Ingress" else SRC_POD
        allows = [
            self.allow_term(endpoint, direction)
            for endpoint in self.universe.endpoints
        ]
        if all(allow == ID for allow in allows):
            return ID
        return union_all(
            [
                mk_seq(test_term(field, endpoint.index), allow)
                for endpoint, allow in zip(self.universe.endpoints, allows)
            ]
        )

    # -- results --------------------------------------------------

    def isolation_text(self) -> bytes:
        out = bytearray()
        for ingress, egress in self.isolation:
            out += b"I" if ingress else b"-"
            out += b"E" if egress else b"-"
        return bytes(out)

    def admitted_text(self) -> bytes:
        return bytes(
            b"a"[0] if holds(self.term, packet) else b"."[0]
            for packet in header_space(self.fields)
        )

    def value(self) -> tuple:
        admitted = self.admitted_text()
        chunks = [
            ("text", admitted[at : at + CHUNK]) for at in range(0, len(admitted), CHUNK)
        ]
        return (
            "record",
            [
                (b"admitted", ("list", chunks)),
                (b"isolation", ("text", self.isolation_text())),
                (b"marker", ("symbol", MARKER)),
                (b"space", ("int", self.space)),
            ],
        )


def compile_case(universe_value: tuple, policies_value: tuple) -> Compilation:
    universe = Universe(universe_value)
    policies = read_policies(policies_value, universe)
    return Compilation(universe, policies)


# ---------------------------------------------------------------
# Case running
# ---------------------------------------------------------------


def run_case(universe_frame: bytes, policies_frame: bytes) -> tuple[str, str, tuple | None, bytes]:
    """Return (outcome, code, result-value, rendered-term)."""
    try:
        universe_value = decode_frame(universe_frame)
        policies_value = decode_frame(policies_frame)
        compilation = compile_case(universe_value, policies_value)
        return ("ok", "", compilation.value(), render_term(compilation.term))
    except Reject as rejection:
        return ("reject", rejection.code, None, b"")


def error_value(code: str) -> tuple:
    return ("record", [(b"error", ("symbol", code.encode("ascii")))])


def expected_code(value: tuple) -> str | None:
    if value[0] != "record":
        return None
    for key, item in value[1]:
        if key == b"error":
            return item[1].decode("ascii")
    return None


def admitted_of(value: tuple) -> bytes | None:
    if value is None or value[0] != "record":
        return None
    for key, item in value[1]:
        if key == b"admitted":
            return b"".join(chunk[1] for chunk in item[1])
    return None


# ---------------------------------------------------------------
# The fixture corpus
# ---------------------------------------------------------------


def T(text: str) -> tuple:
    return ("text", text.encode("ascii"))


def S(name: str) -> tuple:
    return ("symbol", name.encode("ascii"))


def N(number: int) -> tuple:
    return ("int", number)


def L(items: list[tuple]) -> tuple:
    return ("list", items)


def R(entries: dict[str, tuple]) -> tuple:
    return (
        "record",
        sorted((key.encode("ascii"), value) for key, value in entries.items()),
    )


def selector(
    match: dict[str, str] | None = None,
    expressions: list[tuple] | None = None,
) -> tuple:
    body: dict[str, tuple] = {}
    if match is not None:
        body["match-labels"] = R({key: T(value) for key, value in match.items()})
    if expressions is not None:
        body["match-expressions"] = L(list(expressions))
    return R(body)


def expression(key: str, operator: str, values: list[str] | None = None) -> tuple:
    body: dict[str, tuple] = {"key": T(key), "operator": S(operator)}
    if values is not None:
        body["values"] = L([T(value) for value in values])
    return R(body)


def ip_block(cidr: str, excepts: list[str] | None = None) -> tuple:
    body: dict[str, tuple] = {"cidr": T(cidr)}
    if excepts is not None:
        body["except"] = L([T(item) for item in excepts])
    return R({"ip-block": R(body)})


def port_entry(
    number: int | None = None,
    named: str | None = None,
    protocol: str | None = None,
    end_port: int | None = None,
) -> tuple:
    body: dict[str, tuple] = {}
    if number is not None:
        body["port"] = N(number)
    if named is not None:
        body["port"] = T(named)
    if protocol is not None:
        body["protocol"] = S(protocol)
    if end_port is not None:
        body["end-port"] = N(end_port)
    return R(body)


def rule(
    peers: list[tuple] | None = None,
    ports: list[tuple] | None = None,
    egress: bool = False,
) -> tuple:
    body: dict[str, tuple] = {}
    if peers is not None:
        body["to" if egress else "from"] = L(peers)
    if ports is not None:
        body["ports"] = L(ports)
    return R(body)


def policy(
    name: str,
    namespace: str,
    pod_selector: tuple,
    types: list[str] | None = None,
    ingress: list[tuple] | None = None,
    egress: list[tuple] | None = None,
) -> tuple:
    body: dict[str, tuple] = {
        "name": T(name),
        "namespace": T(namespace),
        "pod-selector": pod_selector,
    }
    if types is not None:
        body["policy-types"] = L([S(item) for item in types])
    if ingress is not None:
        body["ingress"] = L(ingress)
    if egress is not None:
        body["egress"] = L(egress)
    return R(body)


def namespace_of(name: str, match: dict[str, str] | None = None) -> tuple:
    body: dict[str, tuple] = {"name": T(name)}
    if match is not None:
        body["labels"] = R({key: T(value) for key, value in match.items()})
    return R(body)


def pod_of(
    name: str,
    ns: str,
    address: str,
    match: dict[str, str] | None = None,
    ports: dict[str, int] | None = None,
    host_network: bool = False,
) -> tuple:
    body: dict[str, tuple] = {
        "address": T(address),
        "name": T(name),
        "namespace": T(ns),
    }
    if match is not None:
        body["labels"] = R({key: T(value) for key, value in match.items()})
    if ports is not None:
        body["ports"] = R({key: N(value) for key, value in ports.items()})
    if host_network:
        body["host-network"] = ("bool", True)
    return R(body)


def external_of(name: str, address: str) -> tuple:
    return R({"address": T(address), "name": T(name)})


def universe_of(
    namespaces: list[tuple],
    pods: list[tuple],
    ports: list[int],
    protocols: list[str],
    externals: list[tuple] | None = None,
) -> tuple:
    body: dict[str, tuple] = {
        "namespaces": L(namespaces),
        "pods": L(pods),
        "ports": L([N(item) for item in ports]),
        "protocols": L([S(item) for item in protocols]),
    }
    if externals is not None:
        body["externals"] = L(externals)
    return R(body)


# The declared universe the documentation examples are adapted to.
#   endpoint 0  default/client    10.0.0.10  role=client
#   endpoint 1  default/db        10.0.0.20  role=db        redis->6379
#   endpoint 2  default/web       10.0.0.30  role=frontend  http->80
#   endpoint 3  myproject/probe   10.1.0.10  role=client
#   endpoint 4  external gw       172.17.0.5
U1 = universe_of(
    namespaces=[
        namespace_of("default"),
        namespace_of("myproject", {"project": "myproject"}),
    ],
    pods=[
        pod_of("client", "default", "10.0.0.10", {"role": "client"}),
        pod_of("db", "default", "10.0.0.20", {"role": "db"}, {"redis": 6379}),
        pod_of("web", "default", "10.0.0.30", {"role": "frontend"}, {"http": 80}),
        pod_of("probe", "myproject", "10.1.0.10", {"role": "client"}),
    ],
    ports=[80, 6379, 8080, 9000],
    protocols=["TCP", "UDP"],
    externals=[external_of("gw", "172.17.0.5")],
)

U_HOST = universe_of(
    namespaces=[namespace_of("default")],
    pods=[
        pod_of("host", "default", "10.0.0.9", {"role": "host"}, host_network=True),
        pod_of("web", "default", "10.0.0.30", {"role": "frontend"}),
    ],
    ports=[80],
    protocols=["TCP"],
)

U_POD_ORDER = universe_of(
    namespaces=[namespace_of("default")],
    pods=[
        pod_of("web", "default", "10.0.0.30", {"role": "frontend"}),
        pod_of("client", "default", "10.0.0.10", {"role": "client"}),
    ],
    ports=[80],
    protocols=["TCP"],
)

U_NS_UNKNOWN = universe_of(
    namespaces=[namespace_of("default")],
    pods=[pod_of("web", "other", "10.0.0.30", {"role": "frontend"})],
    ports=[80],
    protocols=["TCP"],
)

U_PORT_ORDER = universe_of(
    namespaces=[namespace_of("default")],
    pods=[pod_of("web", "default", "10.0.0.30")],
    ports=[8080, 80],
    protocols=["TCP"],
)

U_ADDRESS_DUPLICATE = universe_of(
    namespaces=[namespace_of("default")],
    pods=[
        pod_of("client", "default", "10.0.0.10"),
        pod_of("web", "default", "10.0.0.10"),
    ],
    ports=[80],
    protocols=["TCP"],
)

U_ADDRESS_UNMODELED = universe_of(
    namespaces=[namespace_of("default")],
    pods=[pod_of("web", "default", "fd00::1")],
    ports=[80],
    protocols=["TCP"],
)

U_CONTAINER_PORT = universe_of(
    namespaces=[namespace_of("default")],
    pods=[pod_of("web", "default", "10.0.0.30", ports={"http": 8081})],
    ports=[80],
    protocols=["TCP"],
)

U_PROTOCOL_ORDER = universe_of(
    namespaces=[namespace_of("default")],
    pods=[pod_of("web", "default", "10.0.0.30")],
    ports=[80],
    protocols=["UDP", "TCP"],
)

U_UNMODELED = (
    "record",
    sorted([
        (b"namespaces", L([namespace_of("default")])),
        (b"pods", L([pod_of("web", "default", "10.0.0.30")])),
        (b"ports", L([N(80)])),
        (b"protocols", L([S("TCP")])),
        (b"regions", L([])),
    ]),
)

UNIVERSES: dict[str, tuple] = {
    "u1": U1,
    "u-address-duplicate": U_ADDRESS_DUPLICATE,
    "u-address-unmodeled": U_ADDRESS_UNMODELED,
    "u-container-port": U_CONTAINER_PORT,
    "u-host": U_HOST,
    "u-namespace-unknown": U_NS_UNKNOWN,
    "u-pod-order": U_POD_ORDER,
    "u-port-order": U_PORT_ORDER,
    "u-protocol-order": U_PROTOCOL_ORDER,
    "u-shape": L([]),
    "u-unmodeled": U_UNMODELED,
}

NO_POLICIES = L([])
ANY_POLICY = L([policy("p", "default", selector({}), ["Ingress"])])

FRONTEND = R({"pod-selector": selector({"role": "frontend"})})
CLIENT = R({"pod-selector": selector({"role": "client"})})
MYPROJECT = R({"namespace-selector": selector({"project": "myproject"})})
DB = selector({"role": "db"})


def db_ingress(peers: list[tuple], ports: list[tuple] | None = None) -> tuple:
    return L([
        policy(
            "p",
            "default",
            DB,
            ["Ingress"],
            ingress=[rule(peers=peers, ports=ports)],
        )
    ])


def corpus() -> list[tuple[str, str, tuple, bool]]:
    """(name, universe key, policies value, ordered-encoding)."""
    cases: list[tuple[str, str, tuple, bool]] = []

    def add(name: str, policies: tuple, key: str = "u1", ordered: bool = True) -> None:
        cases.append((name, key, policies, ordered))

    # -- the upstream documentation examples ----------------------

    add(
        "doc-test-network-policy",
        L([
            policy(
                "test-network-policy",
                "default",
                DB,
                ["Egress", "Ingress"],
                ingress=[
                    rule(
                        peers=[
                            ip_block("172.17.0.0/16", ["172.17.1.0/24"]),
                            MYPROJECT,
                            FRONTEND,
                        ],
                        ports=[port_entry(number=6379, protocol="TCP")],
                    )
                ],
                egress=[
                    rule(
                        peers=[ip_block("10.0.0.0/24")],
                        ports=[port_entry(number=9000, protocol="TCP")],
                        egress=True,
                    )
                ],
            )
        ]),
    )
    add(
        "default-deny-ingress",
        L([policy("default-deny-ingress", "default", selector({}), ["Ingress"])]),
    )
    add(
        "default-deny-egress",
        L([policy("default-deny-egress", "default", selector({}), ["Egress"])]),
    )
    add(
        "default-deny-all",
        L([policy("default-deny-all", "default", selector({}), ["Egress", "Ingress"])]),
    )
    add(
        "allow-all-ingress",
        L([
            policy(
                "allow-all-ingress",
                "default",
                selector({}),
                ["Ingress"],
                ingress=[rule()],
            )
        ]),
    )
    add(
        "allow-all-egress",
        L([
            policy(
                "allow-all-egress",
                "default",
                selector({}),
                ["Egress"],
                egress=[rule(egress=True)],
            )
        ]),
    )
    add("no-policies", NO_POLICIES)

    # -- policyTypes defaulting -----------------------------------

    add(
        "policytypes-omitted-ingress-only",
        L([policy("p", "default", DB, ingress=[rule(peers=[FRONTEND])])]),
    )
    add(
        "policytypes-omitted-with-egress",
        L([policy("p", "default", DB, egress=[rule(peers=[FRONTEND], egress=True)])]),
    )
    add("policytypes-omitted-no-sections", L([policy("p", "default", DB)]))
    add("policytypes-empty", L([policy("p", "default", DB, [])]))

    # -- empty / omitted from and ports ---------------------------

    add(
        "omitted-from-allows-all",
        L([
            policy(
                "p",
                "default",
                DB,
                ["Ingress"],
                ingress=[rule(ports=[port_entry(number=6379, protocol="TCP")])],
            )
        ]),
    )
    add(
        "empty-from-allows-all",
        L([
            policy(
                "p",
                "default",
                DB,
                ["Ingress"],
                ingress=[
                    rule(peers=[], ports=[port_entry(number=6379, protocol="TCP")])
                ],
            )
        ]),
    )
    add(
        "omitted-ports-allows-all",
        L([policy("p", "default", DB, ["Ingress"], ingress=[rule(peers=[FRONTEND])])]),
    )
    add(
        "empty-ports-allows-all",
        L([
            policy(
                "p",
                "default",
                DB,
                ["Ingress"],
                ingress=[rule(peers=[FRONTEND], ports=[])],
            )
        ]),
    )
    add("empty-rule-list-denies", L([policy("p", "default", DB, ["Ingress"], ingress=[])]))

    # -- peers: AND within one element, OR across elements --------

    add(
        "peer-and-within",
        L([
            policy(
                "p",
                "default",
                DB,
                ["Ingress"],
                ingress=[
                    rule(
                        peers=[
                            R({
                                "namespace-selector": selector(
                                    {"project": "myproject"}
                                ),
                                "pod-selector": selector({"role": "client"}),
                            })
                        ]
                    )
                ],
            )
        ]),
    )
    add(
        "peer-or-across",
        L([
            policy(
                "p",
                "default",
                DB,
                ["Ingress"],
                ingress=[rule(peers=[MYPROJECT, FRONTEND])],
            )
        ]),
    )
    add(
        "peer-namespace-selector-empty",
        L([
            policy(
                "p",
                "default",
                DB,
                ["Ingress"],
                ingress=[rule(peers=[R({"namespace-selector": selector({})})])],
            )
        ]),
    )
    add(
        "peer-pod-selector-empty",
        L([
            policy(
                "p",
                "default",
                DB,
                ["Ingress"],
                ingress=[rule(peers=[R({"pod-selector": selector({})})])],
            )
        ]),
    )
    add(
        "additive-allows",
        L([
            policy(
                "a-web",
                "default",
                DB,
                ["Ingress"],
                ingress=[
                    rule(
                        peers=[FRONTEND],
                        ports=[port_entry(number=6379, protocol="TCP")],
                    )
                ],
            ),
            policy(
                "b-client",
                "default",
                DB,
                ["Ingress"],
                ingress=[
                    rule(
                        peers=[CLIENT],
                        ports=[port_entry(number=8080, protocol="TCP")],
                    )
                ],
            ),
        ]),
    )
    add(
        "namespace-scope",
        L([
            policy(
                "p",
                "myproject",
                selector({"role": "client"}),
                ["Ingress"],
                ingress=[rule(peers=[FRONTEND])],
            )
        ]),
    )

    # -- selector operators ---------------------------------------

    for name, operator, values in [
        ("selector-in", "In", ["frontend"]),
        ("selector-notin", "NotIn", ["frontend"]),
        ("selector-exists", "Exists", None),
        ("selector-doesnotexist", "DoesNotExist", None),
    ]:
        add(
            name,
            db_ingress([
                R({
                    "pod-selector": selector(
                        expressions=[expression("role", operator, values)]
                    )
                })
            ]),
        )

    # -- ipBlock ---------------------------------------------------

    add("ipblock-cidr", db_ingress([ip_block("10.0.0.0/24")]))
    add("ipblock-except", db_ingress([ip_block("10.0.0.0/24", ["10.0.0.30/32"])]))
    add("ipblock-external", db_ingress([ip_block("172.17.0.0/16")]))
    add("ipblock-prefix-28", db_ingress([ip_block("10.0.0.16/28")]))

    # -- ports ------------------------------------------------------

    add(
        "port-endport-range",
        db_ingress(
            [FRONTEND], [port_entry(number=6000, protocol="TCP", end_port=9000)]
        ),
    )
    add("port-protocol-default-tcp", db_ingress([FRONTEND], [port_entry(number=6379)]))
    add(
        "port-protocol-udp",
        db_ingress([FRONTEND], [port_entry(number=6379, protocol="UDP")]),
    )
    add("named-port-ingress", db_ingress([FRONTEND], [port_entry(named="redis")]))
    add(
        "named-port-egress",
        L([
            policy(
                "p",
                "default",
                selector({"role": "client"}),
                ["Egress"],
                egress=[rule(ports=[port_entry(named="http")], egress=True)],
            )
        ]),
    )

    # -- mutation family -------------------------------------------

    add(
        "mut-label-base",
        db_ingress([R({"pod-selector": selector({"role": "frontend"})})]),
    )
    add(
        "mut-label-changed",
        db_ingress([R({"pod-selector": selector({"role": "client"})})]),
    )
    add(
        "mut-operator-base",
        db_ingress([
            R({
                "pod-selector": selector(
                    expressions=[expression("role", "In", ["frontend"])]
                )
            })
        ]),
    )
    add(
        "mut-operator-changed",
        db_ingress([
            R({
                "pod-selector": selector(
                    expressions=[expression("role", "NotIn", ["frontend"])]
                )
            })
        ]),
    )
    add("mut-cidr-base", db_ingress([ip_block("10.0.0.30/32")]))
    add("mut-cidr-changed", db_ingress([ip_block("10.0.0.10/32")]))
    add(
        "mut-port-base",
        db_ingress([FRONTEND], [port_entry(number=6379, protocol="TCP")]),
    )
    add(
        "mut-port-changed",
        db_ingress([FRONTEND], [port_entry(number=8080, protocol="TCP")]),
    )

    # -- fail-closed rejections ------------------------------------

    add("reject-named-port-unresolved", db_ingress([FRONTEND], [port_entry(named="grpc")]))
    add(
        "reject-port-out-of-vocabulary",
        db_ingress([FRONTEND], [port_entry(number=443, protocol="TCP")]),
    )
    add(
        "reject-protocol-unknown",
        db_ingress([FRONTEND], [port_entry(number=80, protocol="ICMP")]),
    )
    add(
        "reject-protocol-out-of-vocabulary",
        db_ingress([FRONTEND], [port_entry(number=80, protocol="SCTP")]),
    )
    add("reject-host-network", ANY_POLICY, "u-host")
    add(
        "reject-unmodeled-field",
        L([
            (
                "record",
                sorted([
                    (b"name", T("p")),
                    (b"namespace", T("default")),
                    (b"pod-selector", DB),
                    (b"replicas", N(3)),
                ]),
            )
        ]),
    )
    add(
        "reject-selector-operator-unknown",
        db_ingress([
            R({
                "pod-selector": selector(
                    expressions=[expression("role", "Maybe", ["x"])]
                )
            })
        ]),
    )
    add(
        "reject-selector-values-missing",
        db_ingress([
            R({"pod-selector": selector(expressions=[expression("role", "In")])})
        ]),
    )
    add(
        "reject-selector-values-forbidden",
        db_ingress([
            R({
                "pod-selector": selector(
                    expressions=[expression("role", "Exists", ["frontend"])]
                )
            })
        ]),
    )
    add(
        "reject-selector-values-order",
        db_ingress([
            R({
                "pod-selector": selector(
                    expressions=[expression("role", "In", ["frontend", "client"])]
                )
            })
        ]),
    )
    add("reject-peer-empty", db_ingress([R({})]))
    add(
        "reject-peer-ipblock-exclusive",
        db_ingress([
            R({
                "ip-block": R({"cidr": T("10.0.0.0/24")}),
                "pod-selector": selector({"role": "frontend"}),
            })
        ]),
    )
    add("reject-cidr-malformed", db_ingress([ip_block("10.0.0.0/33")]))
    add("reject-cidr-no-prefix", db_ingress([ip_block("10.0.0.0")]))
    add("reject-address-unmodeled", db_ingress([ip_block("fd00::/64")]))
    add(
        "reject-ipblock-except-outside-cidr",
        db_ingress([ip_block("10.0.0.0/24", ["10.1.0.0/24"])]),
    )
    add(
        "reject-ipblock-except-order",
        db_ingress([ip_block("10.0.0.0/24", ["10.0.0.30/32", "10.0.0.10/32"])]),
    )
    add(
        "reject-end-port-without-port",
        db_ingress([FRONTEND], [port_entry(protocol="TCP", end_port=9000)]),
    )
    add(
        "reject-end-port-named-port",
        db_ingress([FRONTEND], [port_entry(named="redis", end_port=9000)]),
    )
    add(
        "reject-end-port-range",
        db_ingress([FRONTEND], [port_entry(number=9000, protocol="TCP", end_port=80)]),
    )
    add("reject-policy-namespace-unknown", L([policy("p", "nowhere", DB, ["Ingress"])]))
    add("reject-policy-type-unknown", L([policy("p", "default", DB, ["Sideways"])]))
    add(
        "reject-policy-type-order",
        L([policy("p", "default", DB, ["Ingress", "Egress"])]),
    )
    add(
        "reject-policy-missing-field",
        L([("record", sorted([(b"name", T("p")), (b"namespace", T("default"))]))]),
    )
    add(
        "reject-policy-order",
        L([
            policy("b", "default", DB, ["Ingress"]),
            policy("a", "default", DB, ["Ingress"]),
        ]),
    )
    add(
        "reject-policy-duplicate",
        L([
            policy("a", "default", DB, ["Ingress"]),
            policy("a", "default", DB, ["Ingress"]),
        ]),
    )
    add(
        "reject-rule-unmodeled-field",
        L([
            policy(
                "p",
                "default",
                DB,
                ["Ingress"],
                ingress=[("record", [(b"sources", L([]))])],
            )
        ]),
    )
    add("reject-policies-shape", R({}))
    add(
        "reject-record-order",
        L([
            (
                "record",
                [
                    (b"pod-selector", DB),
                    (b"name", T("p")),
                    (b"namespace", T("default")),
                ],
            )
        ]),
        "u1",
        False,
    )
    add(
        "reject-record-duplicate",
        L([
            (
                "record",
                [
                    (b"name", T("p")),
                    (b"name", T("q")),
                    (b"namespace", T("default")),
                    (b"pod-selector", DB),
                ],
            )
        ]),
        "u1",
        False,
    )

    # -- universe rejections ---------------------------------------

    add("reject-universe-shape", NO_POLICIES, "u-shape")
    add("reject-universe-unmodeled-field", NO_POLICIES, "u-unmodeled")
    add("reject-universe-pod-order", NO_POLICIES, "u-pod-order")
    add("reject-universe-namespace-unknown", NO_POLICIES, "u-namespace-unknown")
    add("reject-universe-port-order", NO_POLICIES, "u-port-order")
    add("reject-universe-protocol-order", NO_POLICIES, "u-protocol-order")
    add("reject-universe-address-duplicate", NO_POLICIES, "u-address-duplicate")
    add("reject-universe-address-unmodeled", NO_POLICIES, "u-address-unmodeled")
    add("reject-universe-container-port", NO_POLICIES, "u-container-port")

    return cases


FLIPS = [
    ("mut-label-base", "mut-label-changed"),
    ("mut-operator-base", "mut-operator-changed"),
    ("mut-cidr-base", "mut-cidr-changed"),
    ("mut-port-base", "mut-port-changed"),
    ("policytypes-omitted-ingress-only", "policytypes-omitted-with-egress"),
    ("default-deny-ingress", "allow-all-ingress"),
]


# ---------------------------------------------------------------
# generate / check / emit
# ---------------------------------------------------------------


def index_lines(cases: list[tuple[str, str, tuple, bool]]) -> list[str]:
    lines = [
        "# kind|name|universe|policies|expect"
        " ; C = compile case, F = mutation flip"
    ]
    for name, key, _, _ in cases:
        lines.append(
            f"C|{name}|universes/{key}.frame"
            f"|policies/{name}.frame|expect/{name}.frame"
        )
    for left, right in FLIPS:
        lines.append(f"F|{left}|{right}")
    return lines


def parse_index(text: str) -> list[list[str]]:
    entries: list[list[str]] = []
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        if len(parts) not in (3, 5):
            raise SystemExit(f"oracle: malformed index line {line!r}")
        entries.append(parts)
    return entries


def emitted_lines() -> list[str]:
    entries = parse_index((FIXTURES / "cases.tsv").read_text(encoding="ascii"))
    lines: list[str] = []
    admitted: dict[str, bytes | None] = {}
    count = 0
    for parts in entries:
        if parts[0] == "C":
            name = parts[1]
            universe_frame = (FIXTURES / parts[2]).read_bytes()
            policies_frame = (FIXTURES / parts[3]).read_bytes()
            expect = decode_frame((FIXTURES / parts[4]).read_bytes())
            outcome, code, result, rendered = run_case(universe_frame, policies_frame)
            if outcome == "ok":
                if expect != result:
                    raise SystemExit(f"oracle: {name}: checked-in expectation differs")
                lines.append(f"NETPOL-OK|{name}|{encode_frame(result).hex()}")
                lines.append(f"NETPOL-TERM|{name}|{rendered.decode('ascii')}")
            else:
                if expected_code(expect) != code:
                    raise SystemExit(
                        f"oracle: {name}: expected {expected_code(expect)},"
                        f" oracle rejected {code}"
                    )
                lines.append(f"NETPOL-REJECT|{name}|{code}")
            admitted[name] = admitted_of(result)
            count += 1
        else:
            left, right = parts[1], parts[2]
            first = admitted.get(left)
            second = admitted.get(right)
            if first is None or second is None or first == second:
                raise SystemExit(
                    f"oracle: mutation {left}/{right} did not flip an admission"
                )
            lines.append(f"NETPOL-FLIP|{left}|{right}")
    lines.append(f"NETPOL CASES: {count}")
    return lines


def generate() -> None:
    cases = corpus()
    written: dict[str, bytes] = {}
    for key, value in sorted(UNIVERSES.items()):
        written[f"universes/{key}.frame"] = encode_frame(value)
    for name, key, policies, ordered in cases:
        data = encode_frame(policies, ordered)
        written[f"policies/{name}.frame"] = data
        outcome, code, result, _ = run_case(written[f"universes/{key}.frame"], data)
        if outcome == "ok":
            if name.startswith("reject-"):
                raise SystemExit(f"oracle: {name}: rejection case was accepted")
            expect = result
        else:
            if not name.startswith("reject-"):
                raise SystemExit(f"oracle: {name}: valid case rejected with {code}")
            expect = error_value(code)
        written[f"expect/{name}.frame"] = encode_frame(expect)
    index = "\n".join(index_lines(cases)) + "\n"
    written["cases.tsv"] = index.encode("ascii")
    for name, data in written.items():
        path = FIXTURES / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    manifest = "".join(
        f"{hashlib.sha256(data).hexdigest()}  {name}\n"
        for name, data in sorted(written.items())
    )
    (FIXTURES / "SHA256SUMS").write_text(manifest, encoding="ascii")
    for folder in ("universes", "policies", "expect"):
        for path in (FIXTURES / folder).iterdir():
            if f"{folder}/{path.name}" not in written:
                path.unlink()
    print(f"oracle: wrote {len(cases)} cases and a {len(written)}-entry manifest")


def verify_manifest() -> None:
    manifest = (FIXTURES / "SHA256SUMS").read_text(encoding="ascii")
    for line in manifest.splitlines():
        digest, name = line[:64], line[66:]
        data = (FIXTURES / name).read_bytes()
        if hashlib.sha256(data).hexdigest() != digest:
            raise SystemExit(f"oracle: fixture digest mismatch for {name}")


def main(argv: list[str]) -> int:
    command = argv[1] if len(argv) > 1 else "emit"
    if command == "generate":
        generate()
        return 0
    if command == "check":
        verify_manifest()
        emitted_lines()
        print("oracle: fixture digests and expectations agree with the oracle")
        return 0
    if command == "emit":
        for line in emitted_lines():
            print(line)
        return 0
    print(f"usage: {argv[0]} [generate|check|emit]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
