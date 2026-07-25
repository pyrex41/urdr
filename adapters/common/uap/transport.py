"""Shared ADR 0002 byte parser for in-process and socket UAP dispatch."""

from __future__ import annotations

import socket
from typing import Iterable

from .codec import CanonicalCodec, CodecError, Value
from .protocol import Endpoint, UAPError


class _DecodedBeforeError(CodecError):
    def __init__(self, code: str, values: list[Value]) -> None:
        super().__init__(code)
        self.values = values


class FrameDecoder:
    """Incremental M0 netstring and canonical-value decoder."""

    def __init__(self, codec: CanonicalCodec | None = None) -> None:
        self.codec = codec or CanonicalCodec()
        self.buffer = bytearray()
        self.failed = False

    def feed(self, chunk: bytes) -> list[Value]:
        if self.failed:
            raise CodecError("framing-failed")
        if not isinstance(chunk, bytes):
            raise CodecError("chunk-type")
        self.buffer.extend(chunk)
        values: list[Value] = []
        try:
            while True:
                result = self._take()
                if result is None:
                    return values
                values.append(result)
        except CodecError as error:
            self.failed = True
            self.buffer.clear()
            if values:
                raise _DecodedBeforeError(error.code, values) from error
            raise

    def finish(self) -> None:
        if self.failed:
            return
        if self.buffer:
            self.failed = True
            self.buffer.clear()
            raise CodecError("frame-truncated")

    def _take(self) -> Value | None:
        if not self.buffer:
            return None
        if not 48 <= self.buffer[0] <= 57:
            raise CodecError("frame-length")
        colon = self.buffer.find(58)
        if colon < 0:
            if len(self.buffer) > len(str(self.codec.limits.max_frame)):
                raise CodecError("frame-length")
            if any(byte < 48 or byte > 57 for byte in self.buffer):
                raise CodecError("frame-length")
            return None
        digits = bytes(self.buffer[:colon])
        if not digits or any(byte < 48 or byte > 57 for byte in digits):
            raise CodecError("frame-length")
        if len(digits) > 1 and digits[0] == 48:
            raise CodecError("frame-leading-zero")
        length = 0
        for digit in digits:
            length = length * 10 + digit - 48
            if length > self.codec.limits.max_frame:
                raise CodecError("frame-too-large")
        payload_start = colon + 1
        comma = payload_start + length
        if len(self.buffer) <= comma:
            return None
        if self.buffer[comma] != 44:
            raise CodecError("frame-comma")
        payload = bytes(self.buffer[payload_start:comma])
        del self.buffer[: comma + 1]
        return self.codec.decode_payload(payload)


class FramedServer:
    """One dispatcher used unchanged by every byte transport."""

    def __init__(self, endpoint: Endpoint) -> None:
        self.endpoint = endpoint
        self.decoder = FrameDecoder(endpoint.codec)
        self.failed = False

    def feed(self, chunk: bytes) -> bytes:
        if self.failed:
            return b""
        try:
            values = self.decoder.feed(chunk)
        except _DecodedBeforeError as error:
            output = self._dispatch(error.values)
            self.failed = True
            return output + self._framing_error(error)
        except CodecError as error:
            self.failed = True
            return self._framing_error(error)
        return self._dispatch(values)

    def finish(self) -> bytes:
        if self.failed:
            return b""
        try:
            self.decoder.finish()
        except CodecError as error:
            self.failed = True
            return self._framing_error(error)
        return b""

    def _dispatch(self, values: list[Value]) -> bytes:
        return b"".join(
            self.endpoint.codec.encode_frame(self.endpoint.handle(value))
            for value in values
        )

    def _framing_error(self, error: CodecError) -> bytes:
        return self.endpoint.codec.encode_frame(
            self.endpoint.error_record(UAPError(error.code))
        )


class InProcessTransport:
    """In-process calls retain the exact stream-byte contract."""

    def __init__(self, endpoint: Endpoint) -> None:
        self.server = FramedServer(endpoint)

    def exchange(self, wire_bytes: bytes, chunks: Iterable[int] | None = None) -> bytes:
        if chunks is None:
            return self.server.feed(wire_bytes)
        output = bytearray()
        position = 0
        for size in chunks:
            if type(size) is not int or size <= 0:
                raise ValueError("chunk sizes must be positive integers")
            output.extend(self.server.feed(wire_bytes[position : position + size]))
            position += size
            if position >= len(wire_bytes):
                break
        if position < len(wire_bytes):
            output.extend(self.server.feed(wire_bytes[position:]))
        return bytes(output)


def serve_socket(
    connection: socket.socket,
    endpoint: Endpoint,
    *,
    receive_bytes: int = 65_536,
) -> None:
    """Move bytes only; readiness never orders world observations."""

    if type(receive_bytes) is not int or receive_bytes <= 0:
        raise ValueError("receive_bytes must be a positive integer")
    server = FramedServer(endpoint)
    try:
        while True:
            chunk = connection.recv(receive_bytes)
            if not chunk:
                trailing = server.finish()
                if trailing:
                    connection.sendall(trailing)
                return
            response = server.feed(chunk)
            if response:
                connection.sendall(response)
            if server.failed:
                return
    finally:
        connection.close()
