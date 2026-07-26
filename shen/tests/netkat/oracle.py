"""Independent oracle for the ADR 0004 history-free NetKAT fragment.

This file shares no code with the Shen implementation. It carries its own
canonical S-expression codec (ADR 0002 profile), its own validators with
the same stable error codes, and its own packet-set denotation, so that
agreement with `shen/world/netkat.shen` is evidence rather than a
tautology.

Usage:

    python3 oracle.py generate        rewrite the fixture corpus
    python3 oracle.py check           recompute every checked-in
                                      expectation from the fixture inputs
    python3 oracle.py emit            print the semantic lines the Shen
                                      suite must reproduce byte for byte

The fixture corpus lives in protocol/fixtures/v1/netkat/.
"""

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[3]
FIXTURES = ROOT / "protocol" / "fixtures" / "v1" / "netkat"

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

TAG_OF = {
    "drop": b"nk-drop",
    "id": b"nk-id",
    "test": b"nk-test",
    "set": b"nk-set",
    "union": b"nk-union",
    "seq": b"nk-seq",
    "star": b"nk-star",
    "neg": b"nk-neg",
}
KIND_OF = {tag: kind for kind, tag in TAG_OF.items()}
ARITY = {"drop": 0, "id": 0, "test": 2, "set": 2, "union": 2, "seq": 2, "star": 1, "neg": 1}
ATOMIC = ("test", "set")
BINARY = ("union", "seq")
UNARY = ("star", "neg")


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


def encode(value: tuple) -> bytes:
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
        return b"(" + atom(b"list") + b"".join(encode(item) for item in value[1]) + b")"
    if kind == "record":
        body = b""
        previous: bytes | None = None
        for key, item in value[1]:
            if len(key) > MAX_SYMBOL or not SYMBOL_RE.fullmatch(key):
                raise Reject("symbol-invalid")
            if previous is not None and key <= previous:
                raise Reject("record-order")
            previous = key
            body += b"(" + atom(key) + encode(item) + b")"
        return b"(" + atom(b"record") + body + b")"
    raise Reject("value-type")


def render_integer(number: int) -> bytes:
    if isinstance(number, bool) or not isinstance(number, int):
        raise Reject("value-type")
    return str(number).encode("ascii")


def encode_frame(value: tuple) -> bytes:
    payload = encode(value)
    if len(payload) > MAX_FRAME:
        raise Reject("frame-too-large")
    # ADR 0002 makes the decoder's node and depth budgets encoder budgets
    # too by reparsing the completed payload before returning it.
    frame = str(len(payload)).encode("ascii") + b":" + payload + b","
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
    """Generic RFC 9804 atom/list parse under the ADR 0002 budgets.

    Every atom and every list counts against MAX_NODES, and list nesting
    counts against MAX_DEPTH, exactly as the Shen parser does.
    """
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
            if previous is not None and key <= previous:
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
# NetKAT vocabulary, packets, terms
# ---------------------------------------------------------------


def validate_vocabulary(value: tuple) -> list[tuple[bytes, list[int]]]:
    if value[0] != "record":
        raise Reject("vocab-shape")
    entries = value[1]
    if not entries:
        raise Reject("vocab-empty")
    fields: list[tuple[bytes, list[int]]] = []
    previous: bytes | None = None
    space = 1
    for key, item in entries:
        if not SYMBOL_RE.fullmatch(key) or len(key) > MAX_SYMBOL:
            raise Reject("vocab-field-symbol")
        if previous is not None and not key > previous:
            raise Reject("vocab-field-order")
        previous = key
        if item[0] != "list":
            raise Reject("vocab-values-shape")
        values = validate_value_set(item[1])
        if len(fields) >= MAX_FIELDS:
            raise Reject("vocab-too-many-fields")
        space *= len(values)
        if space > MAX_SPACE:
            raise Reject("vocab-space-too-large")
        fields.append((key, values))
    return fields


def validate_value_set(items: list[tuple]) -> list[int]:
    values: list[int] = []
    previous: int | None = None
    for item in items:
        if item[0] != "int":
            raise Reject("vocab-value-integer")
        if previous is not None and not item[1] > previous:
            raise Reject("vocab-value-order")
        previous = item[1]
        if len(values) >= MAX_FIELD_VALUES:
            raise Reject("vocab-too-many-values")
        values.append(item[1])
    if not values:
        raise Reject("vocab-values-empty")
    return values


def validate_packet(fields: list[tuple[bytes, list[int]]], value: tuple) -> tuple:
    if value[0] != "record":
        raise Reject("packet-shape")
    entries = value[1]
    if len(entries) != len(fields):
        raise Reject("packet-field-mismatch")
    packet: list[tuple[bytes, int]] = []
    for (key, values), (name, item) in zip(fields, entries):
        if key != name:
            raise Reject("packet-field-mismatch")
        if item[0] != "int":
            raise Reject("packet-value-integer")
        if item[1] not in values:
            raise Reject("packet-value-unknown")
        packet.append((key, item[1]))
    return tuple(packet)


def decode_term(value: tuple) -> tuple:
    if value[0] != "list" or not value[1] or value[1][0][0] != "symbol":
        raise Reject("term-encoding")
    items = value[1]
    kind = KIND_OF.get(items[0][1])
    if kind is None:
        raise Reject("term-head")
    arguments = items[1:]
    if len(arguments) != ARITY[kind]:
        raise Reject("term-arity")
    if kind in ATOMIC:
        if arguments[0][0] != "symbol":
            raise Reject("term-field-shape")
        if arguments[1][0] != "int":
            raise Reject("term-value-integer")
        return (kind, arguments[0][1], arguments[1][1])
    return (kind, *[decode_term(argument) for argument in arguments])


def encode_term(term: tuple) -> tuple:
    kind = term[0]
    head = ("symbol", TAG_OF[kind])
    if kind in ATOMIC:
        return ("list", [head, ("symbol", term[1]), ("int", term[2])])
    return ("list", [head] + [encode_term(argument) for argument in term[1:]])


def is_predicate(term: tuple) -> bool:
    kind = term[0]
    if kind in ("drop", "id", "test"):
        return True
    if kind in BINARY:
        return is_predicate(term[1]) and is_predicate(term[2])
    if kind == "neg":
        return is_predicate(term[1])
    return False


def check_term(fields: list[tuple[bytes, list[int]]], term: tuple, nodes: int) -> int:
    if nodes >= MAX_TERM_NODES:
        raise Reject("term-too-large")
    nodes += 1
    kind = term[0]
    if kind in ("drop", "id"):
        return nodes
    if kind in ATOMIC:
        declared = dict(fields).get(term[1])
        if declared is None:
            raise Reject("term-field-unknown")
        if term[2] not in declared:
            raise Reject("term-value-unknown")
        return nodes
    if kind in BINARY:
        return check_term(fields, term[2], check_term(fields, term[1], nodes))
    nodes = check_term(fields, term[1], nodes)
    if kind == "neg" and not is_predicate(term[1]):
        raise Reject("term-neg-nonpredicate")
    return nodes


def read_term(fields: list[tuple[bytes, list[int]]], value: tuple) -> tuple:
    term = decode_term(value)
    check_term(fields, term, 0)
    return term


def read_predicate(fields: list[tuple[bytes, list[int]]], value: tuple) -> tuple:
    term = read_term(fields, value)
    if not is_predicate(term):
        raise Reject("term-nonpredicate")
    return term


# ---------------------------------------------------------------
# Denotation
# ---------------------------------------------------------------


def packet_put(packet: tuple, field: bytes, number: int) -> tuple:
    return tuple((key, number if key == field else value) for key, value in packet)


def packet_get(packet: tuple, field: bytes) -> int | None:
    for key, value in packet:
        if key == field:
            return value
    return None


def evaluate(term: tuple, packet: tuple) -> tuple:
    kind = term[0]
    if kind == "drop":
        return ()
    if kind == "id":
        return (packet,)
    if kind == "test":
        return (packet,) if packet_get(packet, term[1]) == term[2] else ()
    if kind == "set":
        return (packet_put(packet, term[1], term[2]),)
    if kind == "union":
        return union(evaluate(term[1], packet), evaluate(term[2], packet))
    if kind == "seq":
        return evaluate_set(term[2], evaluate(term[1], packet))
    if kind == "star":
        reached = {packet}
        frontier = {packet}
        while frontier:
            fresh = set(evaluate_set(term[1], tuple(sorted(frontier)))) - reached
            reached |= fresh
            frontier = fresh
        return tuple(sorted(reached))
    if kind == "neg":
        return (packet,) if not evaluate(term[1], packet) else ()
    raise Reject("term-head")


def evaluate_set(term: tuple, packets: Iterable[tuple]) -> tuple:
    result: set[tuple] = set()
    for packet in packets:
        result.update(evaluate(term, packet))
    return tuple(sorted(result))


def union(left: tuple, right: tuple) -> tuple:
    return tuple(sorted(set(left) | set(right)))


def header_space(fields: list[tuple[bytes, list[int]]]) -> list[tuple]:
    space: list[tuple] = [()]
    for key, values in reversed(fields):
        space = [((key, value), *suffix) for value in values for suffix in space]
    return space


def equivalence(fields: list[tuple[bytes, list[int]]], left: tuple, right: tuple) -> tuple:
    for packet in header_space(fields):
        result_left = evaluate(left, packet)
        result_right = evaluate(right, packet)
        if result_left != result_right:
            return ("differs", packet, result_left, result_right)
    return ("equivalent",)


def reachability(
    fields: list[tuple[bytes, list[int]]],
    ingress: tuple,
    policy: tuple,
    egress: tuple,
) -> tuple:
    term = ("seq", ingress, ("seq", policy, egress))
    for packet in header_space(fields):
        result = evaluate(term, packet)
        if result:
            return ("reachable", packet, result[0])
    return ("unreachable",)


# ---------------------------------------------------------------
# Canonical result values
# ---------------------------------------------------------------


def packet_value(packet: tuple) -> tuple:
    return ("record", [(key, ("int", value)) for key, value in packet])


def set_value(packets: Iterable[tuple]) -> tuple:
    return ("list", [packet_value(packet) for packet in packets])


def equivalence_value(verdict: tuple) -> tuple:
    if verdict[0] == "equivalent":
        return ("record", [(b"verdict", ("symbol", b"equivalent"))])
    return (
        "record",
        [
            (b"left-output", set_value(verdict[2])),
            (b"right-output", set_value(verdict[3])),
            (b"verdict", ("symbol", b"differs")),
            (b"witness-packet", packet_value(verdict[1])),
        ],
    )


def reachability_value(verdict: tuple) -> tuple:
    if verdict[0] == "unreachable":
        return ("record", [(b"verdict", ("symbol", b"unreachable"))])
    return (
        "record",
        [
            (b"egress-packet", packet_value(verdict[2])),
            (b"ingress-packet", packet_value(verdict[1])),
            (b"verdict", ("symbol", b"reachable")),
        ],
    )


# ---------------------------------------------------------------
# Case evaluation shared by generate/check/emit
# ---------------------------------------------------------------


def field(case: tuple, name: bytes) -> tuple:
    for key, value in case[1]:
        if key == name:
            return value
    raise Reject("case-field-missing")


def run_case(case: tuple) -> tuple[str, str, tuple | None]:
    """Return (outcome, payload, result-value) for one decoded case."""
    kind = field(case, b"kind")[1].decode("ascii")
    try:
        fields = validate_vocabulary(field(case, b"vocabulary"))
        if kind == "eval":
            term = read_term(fields, field(case, b"policy"))
            packet = validate_packet(fields, field(case, b"input"))
            return ("ok", "", set_value(evaluate(term, packet)))
        if kind == "equivalence":
            left = read_term(fields, field(case, b"left"))
            right = read_term(fields, field(case, b"right"))
            return ("ok", "", equivalence_value(equivalence(fields, left, right)))
        if kind == "reachability":
            ingress = read_predicate(fields, field(case, b"ingress"))
            policy = read_term(fields, field(case, b"policy"))
            egress = read_predicate(fields, field(case, b"egress"))
            return (
                "ok",
                "",
                reachability_value(reachability(fields, ingress, policy, egress)),
            )
        if kind == "invalid-vocabulary":
            raise Reject("case-not-rejected")
        if kind == "invalid-policy":
            read_term(fields, field(case, b"policy"))
            raise Reject("case-not-rejected")
        if kind == "invalid-packet":
            validate_packet(fields, field(case, b"input"))
            raise Reject("case-not-rejected")
        if kind == "invalid-reachability":
            read_predicate(fields, field(case, b"ingress"))
            read_term(fields, field(case, b"policy"))
            read_predicate(fields, field(case, b"egress"))
            raise Reject("case-not-rejected")
        raise Reject("case-kind-unknown")
    except Reject as rejection:
        return ("reject", rejection.code, None)


def verdict_word(result: tuple | None) -> str | None:
    if result is None or result[0] != "record":
        return None
    for key, value in result[1]:
        if key == b"verdict":
            return value[1].decode("ascii")
    return None


def case_lines(index: list[tuple[str, str, str]], frames: dict[str, bytes]) -> list[str]:
    lines: list[str] = []
    verdicts: dict[str, str | None] = {}
    count = 0
    for kind, left, right in index:
        if kind == "C":
            case = decode_frame(frames[right])
            outcome, code, result = run_case(case)
            expected = field(case, b"expect")
            if outcome == "ok":
                if result != expected:
                    raise SystemExit(f"oracle: {left}: checked-in expectation differs")
                lines.append(f"NETKAT-OK|{left}|{encode_frame(result).hex()}")
            else:
                if expected != ("symbol", code.encode("ascii")):
                    raise SystemExit(
                        f"oracle: {left}: expected {expected!r}, oracle rejected {code}"
                    )
                lines.append(f"NETKAT-REJECT|{left}|{code}")
            verdicts[left] = verdict_word(result)
            count += 1
        elif kind == "F":
            first = verdicts.get(left)
            second = verdicts.get(right)
            if first is None or second is None or first == second:
                raise SystemExit(f"oracle: mutation {left}/{right} did not flip a verdict")
            lines.append(f"NETKAT-FLIP|{left}|{right}")
        else:
            raise SystemExit(f"oracle: unknown index kind {kind!r}")
    lines.append(f"NETKAT CASES: {count}")
    return lines


# ---------------------------------------------------------------
# The fixture corpus
# ---------------------------------------------------------------


def symbol(name: str) -> tuple:
    return ("symbol", name.encode("ascii"))


def vocabulary_value(fields: list[tuple[str, list[int]]]) -> tuple:
    return (
        "record",
        [(name.encode("ascii"), ("list", [("int", v) for v in values])) for name, values in fields],
    )


def packet_of(fields: list[tuple[str, list[int]]], assignment: dict[str, int]) -> tuple:
    return ("record", [(name.encode("ascii"), ("int", assignment[name])) for name, _ in fields])


DROP = ("drop",)
ID = ("id",)


def test(name: str, number: int) -> tuple:
    return ("test", name.encode("ascii"), number)


def assign(name: str, number: int) -> tuple:
    return ("set", name.encode("ascii"), number)


def union_term(left: tuple, right: tuple) -> tuple:
    return ("union", left, right)


def seq(left: tuple, right: tuple) -> tuple:
    return ("seq", left, right)


def star(inner: tuple) -> tuple:
    return ("star", inner)


def neg(inner: tuple) -> tuple:
    return ("neg", inner)


V1 = [("dst", [1, 2]), ("src", [1, 2])]
V2 = [("dst", [0, 1, 2]), ("pt", [0, 1, 2]), ("src", [0, 1, 2])]
# A single-field space for the Kleene-algebra identities, whose two large
# terms would otherwise push a case frame past the ADR 0002 node budget.
V3 = [("pt", [0, 1, 2])]

# A three-port ring walked by the star cases: pt 0 -> 1 -> 2 -> 0.
RING = star(
    union_term(
        seq(test("pt", 0), assign("pt", 1)),
        union_term(
            seq(test("pt", 1), assign("pt", 2)),
            seq(test("pt", 2), assign("pt", 0)),
        ),
    )
)


def eval_case(name, fields, policy, assignment):
    return (
        name,
        "eval",
        {
            "vocabulary": vocabulary_value(fields),
            "policy": encode_term(policy),
            "input": packet_of(fields, assignment),
        },
    )


def equivalence_case(name, fields, left, right):
    return (
        name,
        "equivalence",
        {
            "vocabulary": vocabulary_value(fields),
            "left": encode_term(left),
            "right": encode_term(right),
        },
    )


def reachability_case(name, fields, ingress, policy, egress):
    return (
        name,
        "reachability",
        {
            "vocabulary": vocabulary_value(fields),
            "ingress": encode_term(ingress),
            "policy": encode_term(policy),
            "egress": encode_term(egress),
        },
    )


def corpus() -> list[tuple]:
    cases: list[tuple] = []
    add = cases.append

    p11 = {"dst": 1, "src": 1}
    p12 = {"dst": 1, "src": 2}
    origin = {"dst": 0, "pt": 0, "src": 0}

    add(eval_case("eval-drop", V1, DROP, p11))
    add(eval_case("eval-id", V1, ID, p11))
    add(eval_case("eval-test-hit", V1, test("dst", 1), p11))
    add(eval_case("eval-test-miss", V1, test("dst", 2), p11))
    add(eval_case("eval-set", V1, assign("dst", 2), p11))
    add(eval_case("eval-set-idempotent", V1, assign("dst", 1), p11))
    add(eval_case("eval-union", V1, union_term(assign("dst", 1), assign("dst", 2)), p12))
    add(eval_case("eval-union-drop", V1, union_term(DROP, ID), p11))
    add(eval_case("eval-seq", V1, seq(assign("dst", 2), test("dst", 2)), p11))
    add(eval_case("eval-seq-drop", V1, seq(test("dst", 2), assign("dst", 1)), p11))
    add(eval_case("eval-neg-hit", V1, neg(test("dst", 2)), p11))
    add(eval_case("eval-neg-miss", V1, neg(test("dst", 1)), p11))
    add(
        eval_case(
            "eval-neg-union",
            V1,
            neg(union_term(test("dst", 2), test("src", 2))),
            p11,
        )
    )
    add(eval_case("eval-neg-drop", V1, neg(DROP), p11))
    add(eval_case("eval-star-id", V1, star(ID), p11))
    add(eval_case("eval-star-drop", V1, star(DROP), p11))
    add(eval_case("eval-star-set", V2, star(assign("pt", 1)), origin))
    add(eval_case("eval-star-ring", V2, RING, origin))
    add(
        eval_case(
            "eval-star-fanout",
            V2,
            star(union_term(assign("dst", 1), assign("src", 1))),
            origin,
        )
    )
    add(eval_case("eval-star-nested", V2, star(RING), origin))

    add(
        equivalence_case(
            "equiv-union-idempotent",
            V1,
            union_term(test("dst", 1), test("dst", 1)),
            test("dst", 1),
        )
    )
    add(equivalence_case("equiv-drop-annihilates", V1, seq(DROP, assign("dst", 2)), DROP))
    add(equivalence_case("equiv-neg-involutive", V1, neg(neg(test("dst", 1))), test("dst", 1)))
    add(
        equivalence_case(
            "equiv-set-absorbs",
            V1,
            seq(assign("dst", 1), assign("dst", 2)),
            assign("dst", 2),
        )
    )
    add(
        equivalence_case(
            "equiv-test-then-set",
            V1,
            seq(test("dst", 1), assign("dst", 1)),
            test("dst", 1),
        )
    )
    add(
        equivalence_case(
            "equiv-de-morgan",
            V1,
            neg(union_term(test("dst", 1), test("src", 1))),
            seq(neg(test("dst", 1)), neg(test("src", 1))),
        )
    )
    hop = assign("pt", 1)
    add(
        equivalence_case(
            "equiv-star-unrolls",
            V3,
            star(hop),
            union_term(ID, seq(hop, star(hop))),
        )
    )
    add(equivalence_case("equiv-star-idempotent", V3, star(RING), RING))
    add(equivalence_case("equiv-star-absorbs-id", V3, star(union_term(ID, hop)), star(hop)))
    add(equivalence_case("equiv-differs-empty", V1, ID, DROP))

    # Mutation family: one operator, one field, or one value apart.
    base_left = seq(test("dst", 1), assign("src", 2))
    add(equivalence_case("mut-equiv-base", V1, base_left, base_left))
    add(
        equivalence_case(
            "mut-equiv-value", V1, base_left, seq(test("dst", 2), assign("src", 2))
        )
    )
    add(
        equivalence_case(
            "mut-equiv-field", V1, base_left, seq(test("src", 1), assign("src", 2))
        )
    )
    add(
        equivalence_case(
            "mut-equiv-operator",
            V1,
            base_left,
            union_term(test("dst", 1), assign("src", 2)),
        )
    )

    add(
        reachability_case(
            "reach-direct",
            V2,
            test("src", 1),
            seq(test("src", 1), assign("dst", 2)),
            test("dst", 2),
        )
    )
    add(
        reachability_case(
            "reach-blocked",
            V2,
            test("src", 1),
            seq(test("src", 1), assign("dst", 2)),
            test("dst", 1),
        )
    )
    add(reachability_case("reach-star-ring", V2, test("pt", 0), RING, test("pt", 2)))
    add(
        reachability_case(
            "reach-partitioned",
            V2,
            test("src", 1),
            seq(neg(test("src", 1)), assign("dst", 2)),
            test("dst", 2),
        )
    )
    add(reachability_case("reach-drop-policy", V2, ID, DROP, ID))

    base_policy = seq(test("src", 1), assign("dst", 2))
    add(reachability_case("mut-reach-base", V2, test("src", 1), base_policy, test("dst", 2)))
    add(reachability_case("mut-reach-value", V2, test("src", 1), base_policy, test("dst", 1)))
    add(reachability_case("mut-reach-field", V2, test("src", 1), base_policy, test("src", 2)))
    add(
        reachability_case(
            "mut-reach-policy",
            V2,
            test("src", 1),
            seq(test("src", 2), assign("dst", 2)),
            test("dst", 2),
        )
    )

    v1 = vocabulary_value(V1)
    add(("invalid-vocab-shape", "invalid-vocabulary", {"vocabulary": ("list", [])}))
    add(("invalid-vocab-empty", "invalid-vocabulary", {"vocabulary": ("record", [])}))
    add(
        (
            "invalid-vocab-values-shape",
            "invalid-vocabulary",
            {"vocabulary": ("record", [(b"dst", ("int", 1))])},
        )
    )
    add(
        (
            "invalid-vocab-values-empty",
            "invalid-vocabulary",
            {"vocabulary": ("record", [(b"dst", ("list", []))])},
        )
    )
    add(
        (
            "invalid-vocab-value-integer",
            "invalid-vocabulary",
            {"vocabulary": ("record", [(b"dst", ("list", [("text", b"1")]))])},
        )
    )
    add(
        (
            "invalid-vocab-value-order",
            "invalid-vocabulary",
            {"vocabulary": ("record", [(b"dst", ("list", [("int", 2), ("int", 1)]))])},
        )
    )
    add(
        (
            "invalid-vocab-value-duplicate",
            "invalid-vocabulary",
            {"vocabulary": ("record", [(b"dst", ("list", [("int", 1), ("int", 1)]))])},
        )
    )
    add(
        (
            "invalid-vocab-too-many-fields",
            "invalid-vocabulary",
            {
                "vocabulary": vocabulary_value(
                    [(chr(ord("a") + i) * 2, [0, 1]) for i in range(9)]
                )
            },
        )
    )
    add(
        (
            "invalid-vocab-too-many-values",
            "invalid-vocabulary",
            {"vocabulary": vocabulary_value([("dst", list(range(65)))])},
        )
    )
    add(
        (
            "invalid-vocab-space-too-large",
            "invalid-vocabulary",
            {
                "vocabulary": vocabulary_value(
                    [(name, list(range(8))) for name in ("aa", "bb", "cc", "dd")]
                )
            },
        )
    )

    add(("invalid-packet-shape", "invalid-packet", {"vocabulary": v1, "input": ("list", [])}))
    add(
        (
            "invalid-packet-missing-field",
            "invalid-packet",
            {"vocabulary": v1, "input": ("record", [(b"dst", ("int", 1))])},
        )
    )
    add(
        (
            "invalid-packet-extra-field",
            "invalid-packet",
            {
                "vocabulary": v1,
                "input": (
                    "record",
                    [(b"dst", ("int", 1)), (b"src", ("int", 1)), (b"ttl", ("int", 1))],
                ),
            },
        )
    )
    add(
        (
            "invalid-packet-wrong-field",
            "invalid-packet",
            {
                "vocabulary": v1,
                "input": ("record", [(b"dst", ("int", 1)), (b"ttl", ("int", 1))]),
            },
        )
    )
    add(
        (
            "invalid-packet-value-integer",
            "invalid-packet",
            {
                "vocabulary": v1,
                "input": ("record", [(b"dst", ("text", b"1")), (b"src", ("int", 1))]),
            },
        )
    )
    add(
        (
            "invalid-packet-value-unknown",
            "invalid-packet",
            {
                "vocabulary": v1,
                "input": ("record", [(b"dst", ("int", 9)), (b"src", ("int", 1))]),
            },
        )
    )

    add(("invalid-policy-encoding", "invalid-policy", {"vocabulary": v1, "policy": ("int", 1)}))
    add(
        (
            "invalid-policy-empty-list",
            "invalid-policy",
            {"vocabulary": v1, "policy": ("list", [])},
        )
    )
    add(
        (
            "invalid-policy-head",
            "invalid-policy",
            {"vocabulary": v1, "policy": ("list", [symbol("nk-frob")])},
        )
    )
    add(
        (
            "invalid-policy-arity-short",
            "invalid-policy",
            {"vocabulary": v1, "policy": ("list", [symbol("nk-test"), symbol("dst")])},
        )
    )
    add(
        (
            "invalid-policy-arity-long",
            "invalid-policy",
            {
                "vocabulary": v1,
                "policy": ("list", [symbol("nk-id"), ("int", 1)]),
            },
        )
    )
    add(
        (
            "invalid-policy-field-shape",
            "invalid-policy",
            {
                "vocabulary": v1,
                "policy": ("list", [symbol("nk-test"), ("int", 1), ("int", 1)]),
            },
        )
    )
    add(
        (
            "invalid-policy-value-integer",
            "invalid-policy",
            {
                "vocabulary": v1,
                "policy": ("list", [symbol("nk-set"), symbol("dst"), ("text", b"1")]),
            },
        )
    )
    add(
        (
            "invalid-policy-field-unknown",
            "invalid-policy",
            {"vocabulary": v1, "policy": encode_term(test("ttl", 1))},
        )
    )
    add(
        (
            "invalid-policy-value-unknown",
            "invalid-policy",
            {"vocabulary": v1, "policy": encode_term(assign("dst", 9))},
        )
    )
    add(
        (
            "invalid-policy-neg-set",
            "invalid-policy",
            {"vocabulary": v1, "policy": encode_term(neg(assign("dst", 1)))},
        )
    )
    add(
        (
            "invalid-policy-neg-star",
            "invalid-policy",
            {"vocabulary": v1, "policy": encode_term(neg(star(test("dst", 1))))},
        )
    )
    add(
        (
            "invalid-policy-neg-nested",
            "invalid-policy",
            {
                "vocabulary": v1,
                "policy": encode_term(neg(union_term(test("dst", 1), assign("src", 1)))),
            },
        )
    )
    add(
        (
            "invalid-reach-ingress",
            "invalid-reachability",
            {
                "vocabulary": v1,
                "ingress": encode_term(assign("dst", 1)),
                "policy": encode_term(ID),
                "egress": encode_term(ID),
            },
        )
    )
    add(
        (
            "invalid-reach-egress",
            "invalid-reachability",
            {
                "vocabulary": v1,
                "ingress": encode_term(ID),
                "policy": encode_term(ID),
                "egress": encode_term(star(ID)),
            },
        )
    )
    return cases


FLIPS = [
    ("mut-equiv-base", "mut-equiv-value"),
    ("mut-equiv-base", "mut-equiv-field"),
    ("mut-equiv-base", "mut-equiv-operator"),
    ("mut-reach-base", "mut-reach-value"),
    ("mut-reach-base", "mut-reach-field"),
    ("mut-reach-base", "mut-reach-policy"),
]


def build_case_frame(name: str, kind: str, parts: dict[str, tuple]) -> bytes:
    body = dict(parts)
    body["kind"] = symbol(kind)
    probe = ("record", sorted(((k.encode("ascii"), v) for k, v in body.items())))
    outcome, code, result = run_case(probe)
    if outcome == "ok":
        if not kind.startswith("invalid"):
            body["expect"] = result
        else:
            raise SystemExit(f"oracle: {name}: invalid case was accepted")
    else:
        if kind.startswith("invalid"):
            body["expect"] = ("symbol", code.encode("ascii"))
        else:
            raise SystemExit(f"oracle: {name}: valid case rejected with {code}")
    value = ("record", sorted(((k.encode("ascii"), v) for k, v in body.items())))
    return encode_frame(value)


def index_lines(cases: list[tuple]) -> list[str]:
    lines = ["# kind|name|value ; C = case frame, F = mutation flip"]
    for name, _, _ in cases:
        lines.append(f"C|{name}|cases/{name}.frame")
    for left, right in FLIPS:
        lines.append(f"F|{left}|{right}")
    return lines


def parse_index(text: str) -> list[tuple[str, str, str]]:
    entries: list[tuple[str, str, str]] = []
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        if len(parts) != 3:
            raise SystemExit(f"oracle: malformed index line {line!r}")
        entries.append((parts[0], parts[1], parts[2]))
    return entries


def load_frames(entries: list[tuple[str, str, str]]) -> dict[str, bytes]:
    frames: dict[str, bytes] = {}
    for kind, _, right in entries:
        if kind == "C":
            frames[right] = (FIXTURES / right).read_bytes()
    return frames


def generate() -> None:
    cases = corpus()
    (FIXTURES / "cases").mkdir(parents=True, exist_ok=True)
    written: dict[str, bytes] = {}
    for name, kind, parts in cases:
        data = build_case_frame(name, kind, parts)
        written[f"cases/{name}.frame"] = data
        (FIXTURES / "cases" / f"{name}.frame").write_bytes(data)
    index = "\n".join(index_lines(cases)) + "\n"
    (FIXTURES / "cases.tsv").write_text(index, encoding="ascii")
    written["cases.tsv"] = index.encode("ascii")
    manifest = "".join(
        f"{hashlib.sha256(data).hexdigest()}  {name}\n"
        for name, data in sorted(written.items())
    )
    (FIXTURES / "SHA256SUMS").write_text(manifest, encoding="ascii")
    stale = {
        path
        for path in (FIXTURES / "cases").iterdir()
        if f"cases/{path.name}" not in written
    }
    for path in stale:
        path.unlink()
    print(f"oracle: wrote {len(cases)} case frames and a {len(written)}-entry manifest")


def verify_manifest() -> None:
    manifest = (FIXTURES / "SHA256SUMS").read_text(encoding="ascii")
    for line in manifest.splitlines():
        digest, name = line[:64], line[66:]
        data = (FIXTURES / name).read_bytes()
        if hashlib.sha256(data).hexdigest() != digest:
            raise SystemExit(f"oracle: fixture digest mismatch for {name}")


def emitted_lines() -> list[str]:
    entries = parse_index((FIXTURES / "cases.tsv").read_text(encoding="ascii"))
    return case_lines(entries, load_frames(entries))


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
