"""Offline production tests for UAP schemas, effects, and transports."""

from __future__ import annotations

import hashlib
from pathlib import Path
import socket
import threading
import unittest

from adapters.common.uap import (
    Bool,
    CanonicalCodec,
    CodecError,
    EffectBackend,
    Endpoint,
    FrameDecoder,
    FramedServer,
    ImmediateOperation,
    InProcessTransport,
    ListValue,
    NULL,
    Octets,
    Record,
    Symbol,
    Text,
    UAPError,
    field,
    integer,
    record,
    serve_socket,
    symbol,
    text,
)


ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = ROOT / "protocol" / "fixtures" / "v1" / "uap"
SHA_PATH = FIXTURE_ROOT / "SHA256SUMS"
EXPECTED_SHA256SUMS_SHA256 = (
    "8e86979819d5b3422ea8af9d9282384e18abf04d668040eecd7106371cac548b"
)
FIXTURE_NAMES = (
    "collect.frame",
    "command.frame",
    "error.frame",
    "hello.frame",
    "observation.frame",
    "poll.frame",
    "selection.frame",
)


def hello(
    *,
    request_id: str = "request-hello",
    required: tuple[str, ...] = ("explicit-collect", "explicit-poll"),
    versions: tuple[int, ...] = (1,),
) -> Record:
    return record(
        kind=symbol("hello"),
        request_id=text(request_id),
        required_capabilities=ListValue(tuple(symbol(item) for item in required)),
        schema_version=integer(1),
        session_id=text("session-test"),
        versions=ListValue(tuple(integer(version) for version in versions)),
    )


def command(
    request_id: str = "request-command",
    key: str = "effect-1",
    value: str = "one",
) -> Record:
    return record(
        command=record(name=symbol("echo"), value=text(value)),
        idempotency_key=text(key),
        kind=symbol("command"),
        protocol_version=integer(1),
        request_id=text(request_id),
        schema_version=integer(1),
        session_id=text("session-test"),
    )


def poll(request_id: str = "request-poll", key: str = "effect-1") -> Record:
    return record(
        idempotency_key=text(key),
        kind=symbol("poll"),
        protocol_version=integer(1),
        request_id=text(request_id),
        schema_version=integer(1),
        session_id=text("session-test"),
    )


def collect(
    request_id: str = "request-collect",
    key: str = "effect-1",
    *,
    reclaim: bool = False,
) -> Record:
    return record(
        idempotency_key=text(key),
        kind=symbol("collect"),
        protocol_version=integer(1),
        reclaim=Bool(reclaim),
        request_id=text(request_id),
        schema_version=integer(1),
        session_id=text("session-test"),
    )


class CountingBackend(EffectBackend):
    def __init__(self) -> None:
        self.validations = 0
        self.starts = 0
        self.polls = 0

    def validate(self, effect):
        self.validations += 1
        if not isinstance(effect, Record) or field(effect, "name") != symbol("echo"):
            raise UAPError("invalid-command")
        return effect

    def start(self, effect):
        self.starts += 1
        result = record(echoed=field(effect, "value"))
        backend = self

        class CountingOperation(ImmediateOperation):
            def poll(self):
                backend.polls += 1
                return super().poll()

        return CountingOperation(result)


def decode_frames(wire: bytes, codec: CanonicalCodec | None = None) -> list:
    decoder = FrameDecoder(codec)
    values = decoder.feed(wire)
    decoder.finish()
    return values


def response_code(wire: bytes) -> bytes:
    values = decode_frames(wire)
    assert len(values) == 1
    code = field(values[0], "code")
    assert isinstance(code, Symbol)
    return code.ascii


def negotiated_transport(
    *,
    backend: CountingBackend | None = None,
    endpoint: Endpoint | None = None,
) -> tuple[CountingBackend, Endpoint, InProcessTransport]:
    current_backend = backend or CountingBackend()
    current_endpoint = endpoint or Endpoint(current_backend)
    transport = InProcessTransport(current_endpoint)
    response = decode_frames(
        transport.exchange(current_endpoint.codec.encode_frame(hello())),
        current_endpoint.codec,
    )
    if field(response[0], "kind") != symbol("selection"):
        raise AssertionError(response)
    return current_backend, current_endpoint, transport


def exact_fixture_bytes() -> dict[str, bytes]:
    backend = CountingBackend()
    endpoint = Endpoint(backend)
    transport = InProcessTransport(endpoint)
    hello_frame = endpoint.codec.encode_frame(hello())
    selection_frame = transport.exchange(hello_frame)
    command_frame = endpoint.codec.encode_frame(command())
    observation_frame = transport.exchange(command_frame)
    error_frame = transport.exchange(
        endpoint.codec.encode_frame(command("request-conflict", "effect-1", "two"))
    )
    return {
        "collect.frame": endpoint.codec.encode_frame(collect()),
        "command.frame": command_frame,
        "error.frame": error_frame,
        "hello.frame": hello_frame,
        "observation.frame": observation_frame,
        "poll.frame": endpoint.codec.encode_frame(poll()),
        "selection.frame": selection_frame,
    }


def write_fixtures() -> str:
    FIXTURE_ROOT.mkdir(parents=True, exist_ok=True)
    fixtures = exact_fixture_bytes()
    for name, raw in fixtures.items():
        (FIXTURE_ROOT / name).write_bytes(raw)
    for path in FIXTURE_ROOT.glob("*.frame"):
        if path.name not in fixtures:
            path.unlink()
    lines = [
        f"{hashlib.sha256(fixtures[name]).hexdigest()}  {name}"
        for name in sorted(fixtures)
    ]
    SHA_PATH.write_text("\n".join(lines) + "\n", encoding="ascii")
    return hashlib.sha256(SHA_PATH.read_bytes()).hexdigest()


class FixtureTests(unittest.TestCase):
    def test_codec_matches_all_adr_0002_fixtures(self) -> None:
        codec = CanonicalCodec()
        canonical_root = ROOT / "protocol" / "fixtures" / "v1" / "canonical"
        for line in (canonical_root / "cases.tsv").read_text("ascii").splitlines():
            if not line or line.startswith("#"):
                continue
            kind, name, relative, *expected = line.split("|")
            raw = (canonical_root / relative).read_bytes()
            with self.subTest(name=name):
                if kind == "V":
                    value = codec.decode_frame(raw)
                    self.assertEqual(raw, codec.encode_frame(value))
                else:
                    with self.assertRaises(CodecError) as raised:
                        codec.decode_frame(raw)
                    self.assertEqual(expected[0], raised.exception.code)

    def test_exact_fixture_manifest(self) -> None:
        self.assertEqual(
            EXPECTED_SHA256SUMS_SHA256,
            hashlib.sha256(SHA_PATH.read_bytes()).hexdigest(),
        )
        entries = {}
        names = []
        for line in SHA_PATH.read_text("ascii").splitlines():
            self.assertEqual("  ", line[64:66])
            digest, name = line[:64], line[66:]
            self.assertRegex(digest, r"^[0-9a-f]{64}$")
            names.append(name)
            entries[name] = digest
        self.assertEqual(list(FIXTURE_NAMES), names)
        self.assertEqual(set(FIXTURE_NAMES), set(entries))
        codec = CanonicalCodec()
        for name, digest in entries.items():
            raw = (FIXTURE_ROOT / name).read_bytes()
            self.assertEqual(digest, hashlib.sha256(raw).hexdigest())
            (value,) = decode_frames(raw, codec)
            self.assertEqual(raw, codec.encode_frame(value))

    def test_fixture_kinds_and_fixed_fields(self) -> None:
        expected = {
            "collect.frame": b"collect",
            "command.frame": b"command",
            "error.frame": b"error",
            "hello.frame": b"hello",
            "observation.frame": b"observation",
            "poll.frame": b"poll",
            "selection.frame": b"selection",
        }
        for name, kind in expected.items():
            with self.subTest(name=name):
                (value,) = decode_frames((FIXTURE_ROOT / name).read_bytes())
                actual = field(value, "kind")
                self.assertEqual(Symbol(kind), actual)

    def test_request_fingerprint_vector(self) -> None:
        (observation,) = decode_frames(
            (FIXTURE_ROOT / "observation.frame").read_bytes()
        )
        fingerprint = field(observation, "request-fingerprint")
        self.assertIsInstance(fingerprint, Octets)
        self.assertEqual(
            "7968b0cb7914618f2b2c9a43b8684fab67a84050ed64e4d5ce69f64414dbaedb",
            fingerprint.data.hex(),
        )


class FramingTests(unittest.TestCase):
    def test_every_two_chunk_split_and_byte_chunks(self) -> None:
        codec = CanonicalCodec()
        wire = codec.encode_frame(hello()) + codec.encode_frame(command())
        for split in range(len(wire) + 1):
            backend = CountingBackend()
            server = FramedServer(Endpoint(backend))
            response = server.feed(wire[:split]) + server.feed(wire[split:])
            values = decode_frames(response, codec)
            self.assertEqual([b"selection", b"observation"], [
                field(value, "kind").ascii for value in values
            ])
            self.assertEqual(1, backend.starts)
        backend = CountingBackend()
        server = FramedServer(Endpoint(backend))
        response = b"".join(server.feed(bytes([byte])) for byte in wire)
        self.assertEqual(2, len(decode_frames(response, codec)))
        self.assertEqual(1, backend.starts)

    def test_malformed_and_oversize_frames_fail_before_effects(self) -> None:
        for malformed, code in [
            (b"01:x,", b"frame-leading-zero"),
            (b"4097:", b"frame-too-large"),
            (b"1:x;", b"frame-comma"),
        ]:
            with self.subTest(code=code):
                backend = CountingBackend()
                server = FramedServer(Endpoint(backend))
                self.assertEqual(code, response_code(server.feed(malformed)))
                self.assertEqual(0, backend.starts)
                self.assertTrue(server.failed)
        server = FramedServer(Endpoint(CountingBackend()))
        server.feed(b"10:(3:int1")
        self.assertEqual(b"frame-truncated", response_code(server.finish()))


class EndpointTests(unittest.TestCase):
    def test_counting_adapter_exact_duplicate_and_conflict(self) -> None:
        backend, endpoint, transport = negotiated_transport()
        first = decode_frames(transport.exchange(endpoint.codec.encode_frame(command())))[0]
        duplicate = decode_frames(
            transport.exchange(
                endpoint.codec.encode_frame(command("request-retry", "effect-1", "one"))
            )
        )[0]
        conflict = transport.exchange(
            endpoint.codec.encode_frame(command("request-conflict", "effect-1", "two"))
        )
        self.assertEqual(Bool(False), field(first, "cached"))
        self.assertEqual(Bool(True), field(duplicate, "cached"))
        self.assertEqual(field(first, "result"), field(duplicate, "result"))
        fingerprint = field(first, "request-fingerprint")
        self.assertIsInstance(fingerprint, Octets)
        self.assertEqual(32, len(fingerprint.data))
        self.assertEqual(b"idempotency-conflict", response_code(conflict))
        self.assertEqual(1, backend.validations)
        self.assertEqual(1, backend.starts)

    def test_cache_lifetime_is_session_not_transport(self) -> None:
        backend, endpoint, first_transport = negotiated_transport()
        first_transport.exchange(endpoint.codec.encode_frame(command()))
        replacement_transport = InProcessTransport(endpoint)
        duplicate = replacement_transport.exchange(
            endpoint.codec.encode_frame(
                command("request-after-disconnect", "effect-1", "one")
            )
        )
        (observation,) = decode_frames(duplicate)
        self.assertEqual(Bool(True), field(observation, "cached"))
        self.assertEqual(1, backend.starts)

    def test_poll_collect_and_explicit_reclaim(self) -> None:
        backend, endpoint, transport = negotiated_transport()
        transport.exchange(endpoint.codec.encode_frame(command()))
        polled = decode_frames(transport.exchange(endpoint.codec.encode_frame(poll())))[0]
        collected = decode_frames(
            transport.exchange(endpoint.codec.encode_frame(collect(reclaim=True)))
        )[0]
        after_reclaim = transport.exchange(
            endpoint.codec.encode_frame(command("request-after-reclaim"))
        )
        self.assertEqual(NULL, field(polled, "result"))
        self.assertNotEqual(NULL, field(collected, "result"))
        self.assertEqual(b"idempotency-result-reclaimed", response_code(after_reclaim))
        self.assertEqual(1, backend.starts)

    def test_invalid_collect_reclaim_fails_before_observation(self) -> None:
        backend, endpoint, transport = negotiated_transport()
        transport.exchange(endpoint.codec.encode_frame(command()))
        invalid = collect(request_id="request-invalid-reclaim")
        invalid = Record(
            tuple(
                (key, symbol("yes") if key == b"reclaim" else value)
                for key, value in invalid.fields
            )
        )
        polls_before = backend.polls
        response = transport.exchange(endpoint.codec.encode_frame(invalid))
        self.assertEqual(b"invalid-reclaim", response_code(response))
        self.assertEqual(polls_before, backend.polls)
        self.assertEqual(1, backend.starts)

    def test_invalid_schema_and_version_fail_before_effects(self) -> None:
        backend, endpoint, transport = negotiated_transport()
        invalid_schema = record(
            kind=symbol("command"),
            request_id=text("request-bad-schema"),
            schema_version=integer(1),
            session_id=text("session-test"),
        )
        wrong_version = command("request-bad-version")
        wrong_version = Record(
            tuple(
                (key, integer(2) if key == b"protocol-version" else value)
                for key, value in wrong_version.fields
            )
        )
        self.assertEqual(
            b"invalid-schema",
            response_code(transport.exchange(endpoint.codec.encode_frame(invalid_schema))),
        )
        self.assertEqual(
            b"protocol-version-mismatch",
            response_code(transport.exchange(endpoint.codec.encode_frame(wrong_version))),
        )
        self.assertEqual(0, backend.starts)

    def test_capability_downgrade_fails_handshake(self) -> None:
        backend = CountingBackend()
        endpoint = Endpoint(
            backend,
            capabilities=record(
                explicit_collect=Bool(False),
                explicit_poll=Bool(True),
            ),
        )
        response = InProcessTransport(endpoint).exchange(endpoint.codec.encode_frame(hello()))
        self.assertEqual(b"required-capability-unavailable", response_code(response))
        self.assertEqual({}, endpoint.sessions)
        self.assertEqual(0, backend.starts)

    def test_version_selection_follows_shen_order(self) -> None:
        backend = CountingBackend()
        endpoint = Endpoint(backend, supported_versions=(1, 2))
        response = InProcessTransport(endpoint).exchange(
            endpoint.codec.encode_frame(hello(required=(), versions=(3, 2, 1)))
        )
        (selection,) = decode_frames(response)
        self.assertEqual(integer(2), field(selection, "protocol-version"))


class TransportEquivalenceTests(unittest.TestCase):
    def test_socket_and_in_process_emit_identical_bytes(self) -> None:
        codec = CanonicalCodec()
        wire = codec.encode_frame(hello()) + codec.encode_frame(command())
        expected = InProcessTransport(Endpoint(CountingBackend())).exchange(
            wire,
            chunks=[1] * len(wire),
        )
        client, server = socket.socketpair()
        thread = threading.Thread(
            target=serve_socket,
            args=(server, Endpoint(CountingBackend())),
            kwargs={"receive_bytes": 3},
        )
        thread.start()
        try:
            client.sendall(wire)
            client.shutdown(socket.SHUT_WR)
            chunks = []
            while True:
                chunk = client.recv(7)
                if not chunk:
                    break
                chunks.append(chunk)
        finally:
            client.close()
            thread.join()
        self.assertEqual(expected, b"".join(chunks))


class AuthorityTests(unittest.TestCase):
    def test_native_uap_has_no_time_random_or_profile_policy_imports(self) -> None:
        module_root = ROOT / "adapters" / "common" / "uap"
        source = "\n".join(
            path.read_text("utf-8")
            for path in sorted(module_root.glob("*.py"))
        )
        for forbidden in ["import random", "import time", "import datetime"]:
            self.assertNotIn(forbidden, source)
        self.assertNotIn("determinism_profile", source)


if __name__ == "__main__":
    import sys

    if sys.argv[1:] == ["--write-fixtures"]:
        print(write_fixtures())
    else:
        unittest.main()
