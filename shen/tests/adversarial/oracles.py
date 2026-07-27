"""Self-contained adversarial oracles; none are production Urdr semantics."""

from __future__ import annotations

import copy
import hashlib
import json
import re
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Mapping, Sequence


MARKER = "URDR-ADVERSARIAL-V1"
REQUIRED_PORTS = ("shen-go", "shen-lua", "shen-cl", "shen-rust")
PROTOTYPE_MAX_FRAME = 1 << 20
INTEGER = re.compile(r"-?(?:0|[1-9][0-9]*)\Z", re.ASCII)
FIELD = re.compile(rb"\(([a-z][a-z0-9-]*)\s")


class Reject(ValueError):
    """A stable rejection code, deliberately independent of exception prose."""

    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def parse_integer(text: str) -> int:
    if not INTEGER.fullmatch(text) or text == "-0":
        raise Reject("invalid-integer")
    return int(text)


def render_integer(value: int) -> str:
    if isinstance(value, bool) or not isinstance(value, int):
        raise Reject("not-integer")
    return str(value)


def canonical_fields(items: Iterable[tuple[str, object]]) -> tuple[tuple[str, object], ...]:
    seen: set[str] = set()
    result: list[tuple[str, object]] = []
    for key, value in items:
        if key in seen:
            raise Reject("duplicate-field")
        seen.add(key)
        result.append((key, value))
    return tuple(sorted(result, key=lambda item: item[0].encode("utf-8")))


def rejection_marker(error: BaseException) -> tuple[str, str]:
    return ("reject", error.code if isinstance(error, Reject) else "internal")


def frame(payload: bytes) -> bytes:
    if len(payload) > PROTOTYPE_MAX_FRAME:
        raise Reject("frame-over-limit")
    return struct.pack(">I", len(payload)) + payload


def validate_prototype_record(payload: bytes) -> str:
    try:
        text = payload.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise Reject("malformed-utf8") from error
    names = FIELD.findall(payload)
    if len(names) != len(set(names)):
        raise Reject("duplicate-field")
    return text


class PrototypeFrameDecoder:
    """Prototype u32be decoder used only to exercise hostile chunking."""

    def __init__(self, effect: Callable[[str], None] | None = None):
        self.buffer = bytearray()
        self.expected: int | None = None
        self.effect = effect or (lambda _record: None)

    def feed(self, chunk: bytes) -> list[str]:
        self.buffer.extend(chunk)
        records: list[str] = []
        while True:
            if self.expected is None:
                if len(self.buffer) < 4:
                    break
                self.expected = struct.unpack(">I", self.buffer[:4])[0]
                del self.buffer[:4]
                if self.expected > PROTOTYPE_MAX_FRAME:
                    raise Reject("frame-over-limit")
            if len(self.buffer) < self.expected:
                break
            payload = bytes(self.buffer[: self.expected])
            del self.buffer[: self.expected]
            self.expected = None
            record = validate_prototype_record(payload)
            self.effect(record)
            records.append(record)
        return records

    def finish(self) -> None:
        if self.expected is not None:
            raise Reject("truncated-payload")
        if self.buffer:
            raise Reject("truncated-prefix")


def all_chunkings(data: bytes) -> Iterable[tuple[bytes, ...]]:
    """Yield every non-empty contiguous partition of a short byte string."""

    if not data:
        yield ()
        return
    for mask in range(1 << (len(data) - 1)):
        chunks: list[bytes] = []
        start = 0
        for index in range(len(data) - 1):
            if mask & (1 << index):
                chunks.append(data[start : index + 1])
                start = index + 1
        chunks.append(data[start:])
        yield tuple(chunks)


def reduce_prototype(
    world: Mapping[str, object], event: Mapping[str, object]
) -> dict[str, object]:
    """Pure reducer skeleton for invariant attacks, pending the selected API."""

    old = copy.deepcopy(dict(world))
    event_id = event["id"]
    event_time = event["time"]
    if not isinstance(event_id, int) or event_id <= old["last_event_id"]:
        raise Reject("stale-event-id")
    if not isinstance(event_time, int) or event_time < old["time"]:
        raise Reject("time-rollback")
    result = copy.deepcopy(old)
    if event["kind"] == "advance":
        result["time"] = event_time
    elif event_time != old["time"]:
        raise Reject("implicit-time-advance")
    result["last_event_id"] = event_id
    result["events"] = tuple(old["events"]) + (copy.deepcopy(dict(event)),)
    return result


def canonical_event_order(
    events: Iterable[Mapping[str, object]],
) -> tuple[Mapping[str, object], ...]:
    return tuple(
        sorted(
            events,
            key=lambda event: (
                event["time"],
                str(event["kind"]).encode("utf-8"),
                str(event["actor"]).encode("utf-8"),
                event["id"],
            ),
        )
    )


def _component(value: str) -> bytes:
    encoded = value.encode("utf-8")
    return len(encoded).to_bytes(4, "big") + encoded


def prng_word(seed: int, path: Sequence[str], counter: int) -> bytes:
    if seed < 0 or counter < 0:
        raise Reject("negative-prng-coordinate")
    material = bytearray(b"URDR-ADVERSARIAL-PRNG\x00")
    material.extend(_component(str(seed)))
    material.extend(len(path).to_bytes(4, "big"))
    for part in path:
        material.extend(_component(part))
    material.extend(_component(str(counter)))
    return hashlib.sha256(material).digest()


def bounded_draw(
    bound: int, counter: int, source: Callable[[int], bytes]
) -> tuple[int, int]:
    if bound <= 0 or bound > 1 << 256:
        raise Reject("invalid-bound")
    limit = (1 << 256) - ((1 << 256) % bound)
    current = counter
    while True:
        candidate = int.from_bytes(source(current), "big")
        current += 1
        if candidate < limit:
            return candidate % bound, current


@dataclass(frozen=True)
class AdapterCommand:
    request_id: int
    sequence: int
    capabilities: tuple[str, ...]
    requested_profile: str


def validate_adapter_exchange(
    commands: Sequence[AdapterCommand], observations: Sequence[Mapping[str, object]]
) -> None:
    if len(commands) != len(observations):
        raise Reject("adapter-observation-count")
    allowed = {
        "request_id",
        "sequence",
        "capabilities",
        "achieved_profile",
        "status",
    }
    for observation in observations:
        if set(observation) != allowed:
            raise Reject("adapter-fact-shape")
    expected_ids = [command.request_id for command in commands]
    actual_ids = [observation["request_id"] for observation in observations]
    if actual_ids != expected_ids:
        if sorted(actual_ids) == sorted(expected_ids):
            raise Reject("adapter-reordered")
        raise Reject("adapter-request-id")
    for command, observation in zip(commands, observations):
        if observation["request_id"] != command.request_id:
            raise Reject("adapter-request-id")
        if observation["sequence"] != command.sequence:
            raise Reject("adapter-reordered")
        if tuple(observation["capabilities"]) != command.capabilities:
            raise Reject("adapter-capabilities")
        if observation["achieved_profile"] != command.requested_profile:
            raise Reject("adapter-profile-downgrade")
        if observation["status"] != "ok":
            raise Reject("adapter-status")


def expected_observation(command: AdapterCommand) -> dict[str, object]:
    return {
        "request_id": command.request_id,
        "sequence": command.sequence,
        "capabilities": list(command.capabilities),
        "achieved_profile": command.requested_profile,
        "status": "ok",
    }


class GateFailure(AssertionError):
    pass


def verify_gate(
    root: Path,
    *,
    spec_override: Mapping[str, object] | None = None,
    fixture_override: Mapping[str, bytes] | None = None,
) -> None:
    spec_path = root / "shen/tests/adversarial/gate-spec.json"
    spec = dict(
        spec_override
        if spec_override is not None
        else json.loads(spec_path.read_text(encoding="utf-8"))
    )
    if spec.get("marker") != MARKER:
        raise GateFailure("marker changed")
    if tuple(spec.get("required_ports", ())) != REQUIRED_PORTS:
        raise GateFailure("required port set or order changed")

    vector = spec.get("prng_vector", {})
    if not isinstance(vector, dict):
        raise GateFailure("PRNG vector malformed")
    actual = prng_word(
        parse_integer(str(vector.get("seed"))),
        tuple(vector.get("path", ())),
        parse_integer(str(vector.get("counter"))),
    ).hex()
    if actual != vector.get("output_hex"):
        raise GateFailure("PRNG vector changed")

    fixture_override = fixture_override or {}
    fixtures = spec.get("invalid_fixtures", {})
    if not isinstance(fixtures, dict) or not fixtures:
        raise GateFailure("invalid fixture set missing")
    for relative, expected in fixtures.items():
        path = root / relative
        actual_bytes = fixture_override.get(relative, path.read_bytes())
        if not isinstance(expected, dict):
            raise GateFailure(f"{relative}: fixture expectation malformed")
        if "wire_hex" in expected:
            try:
                expected_bytes = bytes.fromhex(str(expected["wire_hex"]))
                represented_bytes = bytes.fromhex(actual_bytes.decode("ascii"))
            except (UnicodeError, ValueError) as error:
                raise GateFailure(f"{relative}: invalid hex fixture") from error
            if represented_bytes != expected_bytes:
                raise GateFailure(f"{relative}: fixture changed")
        elif "utf8" in expected:
            if actual_bytes != str(expected["utf8"]).encode("utf-8"):
                raise GateFailure(f"{relative}: fixture changed")
        elif "sha256" in expected:
            digest = hashlib.sha256(actual_bytes).hexdigest()
            if digest != str(expected["sha256"]):
                raise GateFailure(f"{relative}: fixture changed")
            if "stable_code" in expected:
                # Presence of a pinned stable code is gate metadata only;
                # byte identity is the fail-closed evidence.
                if not str(expected["stable_code"]):
                    raise GateFailure(f"{relative}: empty stable code")
        else:
            raise GateFailure(f"{relative}: unsupported fixture expectation")

    m1_marker = spec.get("m1_marker")
    if m1_marker is not None and m1_marker != M1_MARKER:
        raise GateFailure("m1 marker changed")


# ---------------------------------------------------------------------------
# M1 surfaces (scenario, NetKAT, netpol, properties, replay/certificate,
# component interface). Self-contained; not production Urdr semantics.
# ---------------------------------------------------------------------------

M1_MARKER = "URDR-ADVERSARIAL-M1"
MODELED_WORLD_ONLY = "modeled-world-only"
SPEC_SEMANTICS_ONLY = "spec-semantics-only"
ABSTRACT_ENTROPY = frozenset({"pure", "modeled"})
FORBIDDEN_ENTROPY = frozenset(
    {"recorded", "uncontrolled", "forbidden", "external", "host", "observed"}
)

# Closed top-level key set from urdr.scenario.scenario-keys (all required).
# Anything else (e.g. fixture `workloads`) is scenario-unknown-field.
SCENARIO_KEYS = (
    "budget",
    "components",
    "determinism",
    "faults",
    "header-vocabulary",
    "observations",
    "properties",
    "seed",
    "topology",
    "version",
)

NK_TAG = {
    "drop": "nk-drop",
    "id": "nk-id",
    "test": "nk-test",
    "set": "nk-set",
    "union": "nk-union",
    "seq": "nk-seq",
    "star": "nk-star",
    "neg": "nk-neg",
}
NK_KIND = {tag: kind for kind, tag in NK_TAG.items()}
NK_ARITY = {
    "drop": 0,
    "id": 0,
    "test": 2,
    "set": 2,
    "union": 2,
    "seq": 2,
    "star": 1,
    "neg": 1,
}
COMPONENT_RESERVED = frozenset(
    {
        "choice",
        "choice-id",
        "command",
        "coordinates",
        "event",
        "event-id",
        "seed",
        "time",
    }
)


def validate_scenario_keys(
    keys: Sequence[str], *, allowed: Sequence[str] = SCENARIO_KEYS
) -> None:
    """Reject unknown/missing/unordered scenario top-level keys fail-closed.

    Effects are not applied: this is pure structural validation. A world
    reducer must not see a frame that fails here. The closed key set matches
    urdr.scenario.scenario-keys.
    """

    allowed_set = set(allowed)
    required = set(SCENARIO_KEYS)
    seen: set[str] = set()
    previous: str | None = None
    for key in keys:
        if key not in allowed_set:
            raise Reject("scenario-unknown-field")
        if key in seen:
            raise Reject("record-duplicate")
        if previous is not None and key.encode("utf-8") < previous.encode("utf-8"):
            raise Reject("record-order")
        seen.add(key)
        previous = key
    missing = required - seen
    if missing:
        raise Reject("scenario-missing-field")


def scenario_effect_guard(keys: Sequence[str], effect: Callable[[], None]) -> None:
    """Ensure validation failure precedes any world effect callback."""

    try:
        validate_scenario_keys(keys)
    except Reject:
        return
    effect()


# ---- NetKAT fragment (history-free) ---------------------------------------


def nk_drop() -> tuple:
    return ("drop",)


def nk_id() -> tuple:
    return ("id",)


def nk_test(field: str, value: int) -> tuple:
    return ("test", field, value)


def nk_set(field: str, value: int) -> tuple:
    return ("set", field, value)


def nk_union(left: tuple, right: tuple) -> tuple:
    return ("union", left, right)


def nk_seq(left: tuple, right: tuple) -> tuple:
    return ("seq", left, right)


def nk_star(body: tuple) -> tuple:
    return ("star", body)


def nk_neg(body: tuple) -> tuple:
    return ("neg", body)


def nk_check_term(
    fields: Mapping[str, Sequence[int]], term: tuple, *, nodes: int = 0
) -> int:
    if nodes >= 1024:
        raise Reject("term-too-large")
    nodes += 1
    kind = term[0]
    if kind not in NK_ARITY:
        raise Reject("term-head")
    if kind in ("drop", "id"):
        if len(term) != 1:
            raise Reject("term-arity")
        return nodes
    if kind in ("test", "set"):
        if len(term) != 3:
            raise Reject("term-arity")
        field, value = term[1], term[2]
        if not isinstance(field, str):
            raise Reject("term-field-shape")
        if not isinstance(value, int) or isinstance(value, bool):
            raise Reject("term-value-integer")
        declared = fields.get(field)
        if declared is None:
            raise Reject("term-field-unknown")
        if value not in declared:
            raise Reject("term-value-unknown")
        return nodes
    if kind in ("union", "seq"):
        if len(term) != 3:
            raise Reject("term-arity")
        nodes = nk_check_term(fields, term[1], nodes=nodes)
        return nk_check_term(fields, term[2], nodes=nodes)
    if kind in ("star", "neg"):
        if len(term) != 2:
            raise Reject("term-arity")
        nodes = nk_check_term(fields, term[1], nodes=nodes)
        if kind == "neg" and not nk_is_predicate(term[1]):
            raise Reject("term-neg-nonpredicate")
        return nodes
    raise Reject("term-head")


def nk_is_predicate(term: tuple) -> bool:
    kind = term[0]
    if kind in ("drop", "id", "test"):
        return True
    if kind in ("union", "seq"):
        return nk_is_predicate(term[1]) and nk_is_predicate(term[2])
    if kind == "neg":
        return nk_is_predicate(term[1])
    return False


def nk_packet_get(packet: Mapping[str, int], field: str) -> int | None:
    return packet.get(field)


def nk_packet_put(packet: Mapping[str, int], field: str, value: int) -> dict[str, int]:
    result = dict(packet)
    result[field] = value
    return result


def nk_evaluate(term: tuple, packet: Mapping[str, int]) -> tuple[dict[str, int], ...]:
    kind = term[0]
    if kind == "drop":
        return ()
    if kind == "id":
        return (dict(packet),)
    if kind == "test":
        return (dict(packet),) if nk_packet_get(packet, term[1]) == term[2] else ()
    if kind == "set":
        return (nk_packet_put(packet, term[1], term[2]),)
    if kind == "union":
        left = nk_evaluate(term[1], packet)
        right = nk_evaluate(term[2], packet)
        return nk_union_packets(left, right)
    if kind == "seq":
        out: list[dict[str, int]] = []
        for intermediate in nk_evaluate(term[1], packet):
            out.extend(nk_evaluate(term[2], intermediate))
        return nk_union_packets(tuple(out), ())
    if kind == "star":
        reached = {tuple(sorted(packet.items())): dict(packet)}
        frontier = [dict(packet)]
        while frontier:
            current = frontier.pop()
            for nxt in nk_evaluate(term[1], current):
                key = tuple(sorted(nxt.items()))
                if key not in reached:
                    reached[key] = nxt
                    frontier.append(nxt)
        return tuple(reached[key] for key in sorted(reached))
    if kind == "neg":
        return (dict(packet),) if not nk_evaluate(term[1], packet) else ()
    raise Reject("term-head")


def nk_union_packets(
    left: Sequence[Mapping[str, int]], right: Sequence[Mapping[str, int]]
) -> tuple[dict[str, int], ...]:
    merged: dict[tuple[tuple[str, int], ...], dict[str, int]] = {}
    for packet in list(left) + list(right):
        key = tuple(sorted(packet.items()))
        merged[key] = dict(packet)
    return tuple(merged[key] for key in sorted(merged))


def nk_header_space(fields: Mapping[str, Sequence[int]]) -> list[dict[str, int]]:
    space: list[dict[str, int]] = [{}]
    for field in sorted(fields, reverse=True):
        values = fields[field]
        space = [{**suffix, field: value} for value in values for suffix in space]
    return space


def nk_equivalent(
    fields: Mapping[str, Sequence[int]], left: tuple, right: tuple
) -> bool:
    nk_check_term(fields, left)
    nk_check_term(fields, right)
    for packet in nk_header_space(fields):
        if nk_evaluate(left, packet) != nk_evaluate(right, packet):
            return False
    return True


def nk_reachable(
    fields: Mapping[str, Sequence[int]],
    ingress: Mapping[str, int],
    policy: tuple,
    egress: Mapping[str, int],
) -> bool:
    nk_check_term(fields, policy)
    outputs = nk_evaluate(policy, ingress)
    target = dict(egress)
    return any(packet == target for packet in outputs)


# ---- Netpol fail-closed named-port / vocabulary ---------------------------


@dataclass(frozen=True)
class NetpolPortRef:
    """A port entry: numeric and/or named against a container-port map."""

    protocol: str = "TCP"
    port: int | None = None
    end_port: int | None = None
    named: str | None = None


def resolve_netpol_ports(
    entry: NetpolPortRef,
    *,
    declared_ports: Sequence[int],
    named_ports: Mapping[str, int],
    known_protocols: Sequence[str] = ("TCP", "UDP", "SCTP"),
) -> tuple[int, ...]:
    """Resolve one port entry; unresolvable / OOV constructs fail closed."""

    if entry.protocol not in known_protocols:
        raise Reject("protocol-unknown")
    if entry.named is not None:
        if entry.port is not None or entry.end_port is not None:
            raise Reject("named-port-invalid")
        if entry.named not in named_ports:
            raise Reject("named-port-unresolved")
        number = named_ports[entry.named]
        if number not in declared_ports:
            raise Reject("port-out-of-vocabulary")
        return (number,)
    if entry.port is None:
        raise Reject("port-missing")
    if entry.end_port is not None:
        if entry.end_port < entry.port:
            raise Reject("end-port-range")
        chosen = list(range(entry.port, entry.end_port + 1))
    else:
        chosen = [entry.port]
    for number in chosen:
        if number not in declared_ports:
            raise Reject("port-out-of-vocabulary")
    return tuple(chosen)


def reject_netpol_unmodeled(fields: Sequence[str], allowed: Sequence[str]) -> None:
    for field in fields:
        if field not in allowed:
            raise Reject("manifest-unmodeled-field")


def reject_host_network_pod(host_network: bool, under_policy: bool) -> None:
    if host_network and under_policy:
        raise Reject("host-network-pod-under-policy")


# ---- Properties: host-log forgery and vacuous / empty pinning -------------

SUPPORTED_PROPERTY_CLASSES = frozenset({"invariant", "liveness", "temporal"})
UNSUPPORTED_PROPERTY_CLASSES = frozenset({"crash", "log", "metamorphic"})


@dataclass(frozen=True)
class PropertyVerdict:
    class_name: str
    property_id: str
    result: str  # PASS | FAIL
    witness: str  # no-witness | vacuous | event


def evaluate_property_declaration(
    class_name: str,
    property_id: str,
    *,
    trace: Sequence[Mapping[str, object]],
    kind: str,
) -> PropertyVerdict:
    """Pure verdict skeleton for adversarial boundary cases only.

    Rejects host-log-like inputs and M3+ classes. Pins empty-stream and
    vacuous-antecedent behavior for the M1 classes.
    """

    if class_name in UNSUPPORTED_PROPERTY_CLASSES:
        raise Reject("properties-class-unsupported-in-m1")
    if class_name not in SUPPORTED_PROPERTY_CLASSES:
        raise Reject("properties-class-unknown")
    if not property_id or not isinstance(property_id, str):
        raise Reject("properties-property-id")
    for entry in trace:
        if "host_log" in entry or "log_text" in entry or "stderr" in entry:
            raise Reject("properties-host-log-forbidden")
        if set(entry) - {"id", "time", "kind", "name", "source", "value"}:
            raise Reject("properties-trace-shape")

    empty = len(trace) == 0
    if kind == "never":
        # Safety: empty stream PASSes; any match FAILs.
        for entry in trace:
            if entry.get("name") == "forbidden":
                return PropertyVerdict(class_name, property_id, "FAIL", "event")
        return PropertyVerdict(class_name, property_id, "PASS", "no-witness")
    if kind == "liveness":
        if empty:
            return PropertyVerdict(class_name, property_id, "FAIL", "no-witness")
        for entry in trace:
            if entry.get("name") == "goal":
                return PropertyVerdict(class_name, property_id, "PASS", "event")
        return PropertyVerdict(class_name, property_id, "FAIL", "no-witness")
    if kind == "always-eventually":
        # Vacuous antecedent: no A-match anywhere → PASS with vacuous.
        antecedents = [entry for entry in trace if entry.get("name") == "A"]
        if not antecedents:
            return PropertyVerdict(class_name, property_id, "PASS", "vacuous")
        for entry in antecedents:
            later = [
                other
                for other in trace
                if other.get("name") == "B"
                and int(other["time"]) >= int(entry["time"])  # type: ignore[arg-type]
            ]
            if not later:
                return PropertyVerdict(class_name, property_id, "FAIL", "event")
        return PropertyVerdict(class_name, property_id, "PASS", "no-witness")
    if kind == "invariant":
        if empty:
            return PropertyVerdict(class_name, property_id, "PASS", "no-witness")
        for entry in trace:
            if entry.get("value") == "broken":
                return PropertyVerdict(class_name, property_id, "FAIL", "event")
        return PropertyVerdict(class_name, property_id, "PASS", "no-witness")
    raise Reject("properties-kind-unknown")


def forge_host_log_verdict(text: str) -> None:
    """Any attempt to feed host log prose as a property input is rejected."""

    raise Reject("properties-host-log-forbidden")


# ---- Replay transcript attacks --------------------------------------------


@dataclass(frozen=True)
class TranscriptEntry:
    digest: bytes
    sequence: int


def classify_transcript_attack(
    recorded: Sequence[TranscriptEntry], actual: Sequence[TranscriptEntry]
) -> str:
    """Name the divergence code for a candidate transcript vs recorded.

    Mirrors the taxonomy in replay.shen §3 without re-driving reduction.
    """

    if len(actual) < len(recorded):
        return "replay-transcript-truncated"
    if len(actual) > len(recorded):
        return "replay-transcript-extended"
    if [entry.digest for entry in actual] == [entry.digest for entry in recorded]:
        return "verified"
    actual_multi = sorted(entry.digest for entry in actual)
    recorded_multi = sorted(entry.digest for entry in recorded)
    if actual_multi == recorded_multi:
        return "replay-transcript-reordered"
    return "replay-transcript-tampered"


# ---- Certificate / entropy firewall ---------------------------------------


def certificate_markers(
    baselines: Sequence[Mapping[str, object]],
) -> tuple[str, ...]:
    """modeled-world-only is unconditional; spec-semantics-only is derived."""

    markers = {MODELED_WORLD_ONLY}
    for descriptor in baselines:
        marker = descriptor.get("marker")
        if marker == SPEC_SEMANTICS_ONLY:
            markers.add(SPEC_SEMANTICS_ONLY)
        elif marker is not None and marker != SPEC_SEMANTICS_ONLY:
            raise Reject("certificate-marker-shape")
    return tuple(sorted(markers))


def certificate_entropy_clean(counts: Mapping[str, int]) -> bool:
    """A single non-{pure,modeled} event voids the modeled-D1-analog claim."""

    for class_name, count in counts.items():
        if class_name in ABSTRACT_ENTROPY:
            continue
        if count > 0:
            return False
        if class_name not in FORBIDDEN_ENTROPY and class_name not in ABSTRACT_ENTROPY:
            # Unknown classification is itself unclean.
            return False
    return all(counts.get(name, 0) >= 0 for name in ABSTRACT_ENTROPY)


def certificate_status(
    *,
    verified: bool,
    clean: bool,
    divergence_code: str | None,
    any_fail: bool,
) -> str:
    if not verified and divergence_code in {
        "replay-event-divergence",
        "replay-state-divergence",
        "replay-event-count",
    }:
        return "DIVERGED"
    if not verified or not clean:
        return "UNCERTIFIED"
    if any_fail:
        return "FAIL"
    return "PASS"


def certificate_profile(*, verified: bool, clean: bool) -> str:
    if verified and clean:
        return "modeled-d1-analog"
    return "uncertified"


def assert_modeled_world_only(markers: Sequence[str]) -> None:
    if MODELED_WORLD_ONLY not in markers:
        raise Reject("certificate-missing-modeled-world-only")


def reject_non_abstract_certification(counts: Mapping[str, int]) -> None:
    """Certificate must not certify non-pure/non-modeled entropy classes."""

    if not certificate_entropy_clean(counts):
        raise Reject("certificate-entropy-firewall")


# ---- Component interface --------------------------------------------------


def component_check_value(value: object, *, invalid: str, authority: str) -> None:
    """Reject reserved kernel authorities claimed in component outputs."""

    claim = component_claim(value)
    if claim is not None:
        raise Reject(authority)


def component_claim(value: object) -> str | None:
    if isinstance(value, dict):
        for key, item in value.items():
            if key in COMPONENT_RESERVED:
                return str(key)
            nested = component_claim(item)
            if nested is not None:
                return nested
        return None
    if isinstance(value, (list, tuple)):
        for item in value:
            nested = component_claim(item)
            if nested is not None:
                return nested
        return None
    if isinstance(value, str) and value in COMPONENT_RESERVED:
        return value
    return None


def component_check_step(
    state: object,
    facts: Sequence[Mapping[str, object]],
    choices: Sequence[Mapping[str, object]],
) -> None:
    """Validate a component-step result; misbehavior is fail-closed."""

    claim = component_claim(state)
    if claim is not None:
        raise Reject("component-state-authority")
    for fact in facts:
        if set(fact) != {"name", "value"}:
            raise Reject("component-fact-shape")
        if fact["name"] in COMPONENT_RESERVED:
            raise Reject("component-fact-name")
        nested = component_claim(fact["value"])
        if nested is not None:
            raise Reject("component-fact-authority")
    previous_purpose: str | None = None
    for choice in choices:
        if set(choice) != {"purpose", "alternatives"}:
            raise Reject("component-choice-shape")
        purpose = str(choice["purpose"])
        if purpose in COMPONENT_RESERVED:
            raise Reject("component-choice-purpose")
        if previous_purpose is not None and purpose.encode("utf-8") < previous_purpose.encode(
            "utf-8"
        ):
            raise Reject("component-choice-order")
        alternatives = choice["alternatives"]
        if not isinstance(alternatives, (list, tuple)) or not alternatives:
            raise Reject("component-choice-empty")
        previous_purpose = purpose


def load_scenario_cases(root: Path) -> list[tuple[str, str, str, str | None]]:
    """Parse protocol/fixtures/v1/scenario/cases.tsv → (kind,name,path,code)."""

    path = root / "protocol/fixtures/v1/scenario/cases.tsv"
    rows: list[tuple[str, str, str, str | None]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        kind = parts[0]
        name = parts[1]
        relative = parts[2]
        code = parts[3] if len(parts) > 3 and parts[3] else None
        rows.append((kind, name, relative, code))
    return rows