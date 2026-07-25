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
        else:
            raise GateFailure(f"{relative}: unsupported fixture expectation")
