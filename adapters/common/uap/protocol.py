"""Production M0 UAP schemas, negotiation, and effect/idempotency boundary."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field as dataclass_field
import hashlib
import re
from typing import Any

from .codec import (
    Bool,
    CanonicalCodec,
    CodecError,
    Integer,
    ListValue,
    NULL,
    Null,
    Octets,
    Record,
    Symbol,
    Text,
    Value,
    field,
    record,
)


SCHEMA_VERSION = 1
NEGOTIATION_VERSION = 0
REQUEST_FINGERPRINT_DOMAIN = b"URDR-UAP-REQUEST\x00\x01"
_IDENTIFIER = re.compile(rb"^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$")
_STABLE_CODE = re.compile(rb"^[a-z][a-z0-9-]*$")


def integer(value: int) -> Integer:
    return Integer.from_int(value)


def symbol(name: str) -> Symbol:
    return Symbol.named(name)


class UAPError(Exception):
    """Stable protocol error without host exception prose."""

    def __init__(self, code: str, detail: Value = NULL) -> None:
        encoded = code.encode("ascii")
        if not _STABLE_CODE.fullmatch(encoded):
            raise ValueError(f"invalid stable UAP code: {code!r}")
        super().__init__(code)
        self.code = code
        self.detail = detail


class Operation(ABC):
    """Started effect observed only by a Shen-issued protocol request."""

    @abstractmethod
    def poll(self) -> Value | None:
        """Return the terminal fact, or None while pending."""


class EffectBackend(ABC):
    """Adapter-specific two-phase boundary."""

    @abstractmethod
    def validate(self, command: Value) -> Any:
        """Validate without effects."""

    @abstractmethod
    def start(self, validated_command: Any) -> Operation:
        """Perform one validated effect and return its observation handle."""


class ImmediateOperation(Operation):
    def __init__(self, result: Value) -> None:
        self.result = result

    def poll(self) -> Value:
        return self.result


@dataclass
class _CacheEntry:
    fingerprint: bytes
    operation: Operation | None
    terminal: Value | None = None
    reclaimed: bool = False


@dataclass
class _Session:
    version: int
    hello_request_id: bytes
    hello_digest: bytes
    selection: Record
    requests: dict[bytes, bytes] = dataclass_field(default_factory=dict)
    idempotency: dict[bytes, _CacheEntry] = dataclass_field(default_factory=dict)


@dataclass(frozen=True)
class _Context:
    protocol_version: int
    request_id: Text | Null
    session_id: Text | Null


class Endpoint:
    """Stateful endpoint used by every UAP byte transport."""

    DEFAULT_CAPABILITIES = record(
        explicit_collect=Bool(True),
        explicit_poll=Bool(True),
        idempotency_sha256=Bool(True),
        netstring_framing=Bool(True),
        rfc9804_values=Bool(True),
    )

    _SCHEMAS = {
        b"hello": (
            b"kind",
            b"request-id",
            b"required-capabilities",
            b"schema-version",
            b"session-id",
            b"versions",
        ),
        b"selection": (
            b"capabilities",
            b"codec",
            b"kind",
            b"protocol-version",
            b"request-id",
            b"schema-version",
            b"session-id",
        ),
        b"command": (
            b"command",
            b"idempotency-key",
            b"kind",
            b"protocol-version",
            b"request-id",
            b"schema-version",
            b"session-id",
        ),
        b"observation": (
            b"cached",
            b"kind",
            b"protocol-version",
            b"request-fingerprint",
            b"request-id",
            b"result",
            b"schema-version",
            b"session-id",
            b"status",
        ),
        b"error": (
            b"code",
            b"detail",
            b"kind",
            b"protocol-version",
            b"request-id",
            b"schema-version",
            b"session-id",
        ),
        b"poll": (
            b"idempotency-key",
            b"kind",
            b"protocol-version",
            b"request-id",
            b"schema-version",
            b"session-id",
        ),
        b"collect": (
            b"idempotency-key",
            b"kind",
            b"protocol-version",
            b"reclaim",
            b"request-id",
            b"schema-version",
            b"session-id",
        ),
    }

    def __init__(
        self,
        backend: EffectBackend,
        *,
        codec: CanonicalCodec | None = None,
        supported_versions: tuple[int, ...] = (1,),
        capabilities: Record | None = None,
    ) -> None:
        if (
            not supported_versions
            or len(set(supported_versions)) != len(supported_versions)
            or any(
                type(version) is not int or not 0 < version < 10_000
                for version in supported_versions
            )
        ):
            raise ValueError("supported versions must be distinct positive small integers")
        self.codec = codec or CanonicalCodec()
        self.backend = backend
        self.supported_versions = supported_versions
        self.capabilities = capabilities or self.DEFAULT_CAPABILITIES
        self.codec.encode_payload(self.capabilities)
        self.sessions: dict[bytes, _Session] = {}

    def handle(self, value: Value) -> Record:
        context = self._context(value)
        try:
            if not isinstance(value, Record):
                raise UAPError("invalid-schema")
            kind = field(value, "kind")
            if not isinstance(kind, Symbol):
                raise UAPError("invalid-schema")
            if kind.ascii == b"hello":
                return self._hello(value)
            if kind.ascii == b"command":
                return self._command(value)
            if kind.ascii == b"poll":
                return self._query(value, collect=False)
            if kind.ascii == b"collect":
                return self._query(value, collect=True)
            raise UAPError("unknown-message-kind")
        except (CodecError, UAPError) as error:
            if isinstance(error, CodecError):
                error = UAPError(error.code)
            return self.error_record(error, context)

    def error_record(self, error: UAPError, context: _Context | None = None) -> Record:
        current = context or _Context(NEGOTIATION_VERSION, NULL, NULL)
        return record(
            code=symbol(error.code),
            detail=error.detail,
            kind=symbol("error"),
            protocol_version=integer(current.protocol_version),
            request_id=current.request_id,
            schema_version=integer(SCHEMA_VERSION),
            session_id=current.session_id,
        )

    def _hello(self, message: Record) -> Record:
        self._require_schema(message, b"hello")
        self._require_schema_version(message)
        request_id = self._identifier(field(message, "request-id"), "invalid-request-id")
        session_id = self._identifier(field(message, "session-id"), "invalid-session-id")
        versions = field(message, "versions")
        required = field(message, "required-capabilities")
        if not isinstance(versions, ListValue) or not versions.values:
            raise UAPError("invalid-version-list")
        parsed_versions: list[int] = []
        for value in versions.values:
            if not isinstance(value, Integer):
                raise UAPError("invalid-version-list")
            try:
                version = value.small_nonnegative()
            except CodecError as error:
                raise UAPError("invalid-version-list") from error
            if version <= 0 or version in parsed_versions:
                raise UAPError("invalid-version-list")
            parsed_versions.append(version)
        if not isinstance(required, ListValue):
            raise UAPError("invalid-capability-list")
        required_names: list[bytes] = []
        capability_facts = dict(self.capabilities.fields)
        for value in required.values:
            if not isinstance(value, Symbol) or value.ascii in required_names:
                raise UAPError("invalid-capability-list")
            required_names.append(value.ascii)
            if capability_facts.get(value.ascii) != Bool(True):
                raise UAPError(
                    "required-capability-unavailable",
                    record(capability=value),
                )
        selected = next(
            (version for version in parsed_versions if version in self.supported_versions),
            None,
        )
        if selected is None:
            raise UAPError("version-mismatch")
        digest = hashlib.sha256(self.codec.encode_payload(message)).digest()
        existing = self.sessions.get(session_id)
        if existing is not None:
            if existing.hello_request_id != request_id or existing.hello_digest != digest:
                raise UAPError("conflicting-session")
            return existing.selection
        selection = record(
            capabilities=self.capabilities,
            codec=Symbol(self.codec.name),
            kind=symbol("selection"),
            protocol_version=integer(selected),
            request_id=Text(request_id),
            schema_version=integer(SCHEMA_VERSION),
            session_id=Text(session_id),
        )
        self.sessions[session_id] = _Session(
            version=selected,
            hello_request_id=request_id,
            hello_digest=digest,
            selection=selection,
            requests={request_id: digest},
        )
        return selection

    def _command(self, message: Record) -> Record:
        session, request_id, session_id = self._session_request(message, b"command")
        key = self._identifier(field(message, "idempotency-key"), "invalid-idempotency-key")
        command = field(message, "command")
        fingerprint = hashlib.sha256(
            REQUEST_FINGERPRINT_DOMAIN + self.codec.encode_payload(command)
        ).digest()
        entry = session.idempotency.get(key)
        if entry is not None:
            if entry.fingerprint != fingerprint:
                raise UAPError(
                    "idempotency-conflict",
                    record(idempotency_key=Text(key)),
                )
            if entry.reclaimed:
                raise UAPError(
                    "idempotency-result-reclaimed",
                    record(idempotency_key=Text(key)),
                )
            self._observe(entry)
            return self._observation(
                session.version,
                request_id,
                session_id,
                entry,
                cached=True,
                include_result=True,
            )
        try:
            validated = self.backend.validate(command)
        except UAPError:
            raise
        except Exception as error:
            raise UAPError("backend-validation-failed") from error
        try:
            operation = self.backend.start(validated)
        except Exception as error:
            raise UAPError("effect-start-failed") from error
        if not isinstance(operation, Operation):
            raise UAPError("invalid-backend-operation")
        entry = _CacheEntry(fingerprint=fingerprint, operation=operation)
        session.idempotency[key] = entry
        self._observe(entry)
        return self._observation(
            session.version,
            request_id,
            session_id,
            entry,
            cached=False,
            include_result=True,
        )

    def _query(self, message: Record, *, collect: bool) -> Record:
        expected = b"collect" if collect else b"poll"
        session, request_id, session_id = self._session_request(message, expected)
        key = self._identifier(field(message, "idempotency-key"), "invalid-idempotency-key")
        reclaim = Bool(False)
        if collect:
            reclaim_value = field(message, "reclaim")
            if not isinstance(reclaim_value, Bool):
                raise UAPError("invalid-reclaim")
            reclaim = reclaim_value
        entry = session.idempotency.get(key)
        if entry is None:
            raise UAPError("unknown-idempotency-key")
        if entry.reclaimed:
            raise UAPError(
                "idempotency-result-reclaimed",
                record(idempotency_key=Text(key)),
            )
        self._observe(entry)
        response = self._observation(
            session.version,
            request_id,
            session_id,
            entry,
            cached=True,
            include_result=collect,
        )
        if collect and reclaim.value and entry.terminal is not None:
            entry.operation = None
            entry.terminal = None
            entry.reclaimed = True
        return response

    def _session_request(
        self,
        message: Record,
        expected_kind: bytes,
    ) -> tuple[_Session, bytes, bytes]:
        self._require_schema(message, expected_kind)
        self._require_schema_version(message)
        request_id = self._identifier(field(message, "request-id"), "invalid-request-id")
        session_id = self._identifier(field(message, "session-id"), "invalid-session-id")
        session = self.sessions.get(session_id)
        if session is None:
            raise UAPError("unknown-session")
        version_value = field(message, "protocol-version")
        if not isinstance(version_value, Integer):
            raise UAPError("invalid-protocol-version")
        try:
            version = version_value.small_nonnegative()
        except CodecError as error:
            raise UAPError("invalid-protocol-version") from error
        if version != session.version:
            raise UAPError("protocol-version-mismatch")
        digest = hashlib.sha256(self.codec.encode_payload(message)).digest()
        previous = session.requests.get(request_id)
        if previous is not None and previous != digest:
            raise UAPError("conflicting-request")
        session.requests[request_id] = digest
        return session, request_id, session_id

    def _observe(self, entry: _CacheEntry) -> None:
        if entry.terminal is not None:
            return
        if entry.operation is None:
            raise UAPError("idempotency-result-reclaimed")
        try:
            result = entry.operation.poll()
        except Exception as error:
            raise UAPError("effect-observation-failed") from error
        if result is not None:
            self.codec.encode_payload(result)
            entry.terminal = result

    def _observation(
        self,
        version: int,
        request_id: bytes,
        session_id: bytes,
        entry: _CacheEntry,
        *,
        cached: bool,
        include_result: bool,
    ) -> Record:
        terminal = entry.terminal is not None
        return record(
            cached=Bool(cached),
            kind=symbol("observation"),
            protocol_version=integer(version),
            request_fingerprint=Octets(entry.fingerprint),
            request_id=Text(request_id),
            result=entry.terminal if terminal and include_result else NULL,
            schema_version=integer(SCHEMA_VERSION),
            session_id=Text(session_id),
            status=symbol("terminal" if terminal else "pending"),
        )

    def _require_schema(self, message: Record, kind: bytes) -> None:
        expected = self._SCHEMAS[kind]
        if tuple(key for key, _ in message.fields) != expected:
            raise UAPError("invalid-schema")
        actual = field(message, "kind")
        if not isinstance(actual, Symbol) or actual.ascii != kind:
            raise UAPError("invalid-schema")

    def _require_schema_version(self, message: Record) -> None:
        version = field(message, "schema-version")
        if version != integer(SCHEMA_VERSION):
            raise UAPError("schema-version-mismatch")

    def _identifier(self, value: Value, code: str) -> bytes:
        if not isinstance(value, Text) or not _IDENTIFIER.fullmatch(value.utf8):
            raise UAPError(code)
        return value.utf8

    def _context(self, value: Value) -> _Context:
        if not isinstance(value, Record):
            return _Context(NEGOTIATION_VERSION, NULL, NULL)
        values = dict(value.fields)
        request = values.get(b"request-id")
        session = values.get(b"session-id")
        version = values.get(b"protocol-version")
        protocol = NEGOTIATION_VERSION
        if isinstance(version, Integer):
            try:
                protocol = version.small_nonnegative()
            except CodecError:
                pass
        return _Context(
            protocol,
            request if isinstance(request, Text) else NULL,
            session if isinstance(session, Text) else NULL,
        )
