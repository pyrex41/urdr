import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import codec  # noqa: E402


class CodecTests(unittest.TestCase):
    def assert_error(self, code, function, *args):
        with self.assertRaises(codec.CodecError) as caught:
            function(*args)
        self.assertEqual(code, caught.exception.code)

    def test_shared_fixtures_and_every_split(self):
        output = codec.fixture_output(ROOT / "fixtures.tsv")
        self.assertEqual(42, len(output))
        self.assertTrue(output[0].startswith("valid|null|"))
        self.assertEqual("reject|frame-truncated|frame-truncated", output[-1])

    def test_multiple_frames_with_adversarial_chunks(self):
        first = codec.encode_frame(codec.Null())
        second = codec.encode_frame(codec.Text("λ".encode("utf-8")))
        wire = first + second
        for width in range(1, len(wire) + 1):
            chunks = (wire[pos : pos + width] for pos in range(0, len(wire), width))
            self.assertEqual(
                [codec.Null(), codec.Text("λ".encode("utf-8"))],
                codec.decode_chunks(chunks),
            )

    def test_stream_finish_rejects_partial_frame(self):
        decoder = codec.FrameDecoder()
        self.assertEqual([], decoder.feed(b"8:(4:"))
        self.assert_error("frame-truncated", decoder.finish)

    def test_encoder_rejects_python_float(self):
        self.assert_error("value-type", codec.encode_frame, 1.5)

    def test_software_integer_does_not_use_host_numeric_range(self):
        digits = b"9" * 255
        value = codec.Integer.parse(b"-" + digits)
        self.assertEqual(b"-" + digits, value.wire)
        self.assertEqual(value, codec.decode_frame(codec.encode_frame(value)))

    def test_encoder_revalidates_constructed_integer(self):
        value = codec.Integer(False, b"01")
        self.assert_error("integer-leading-zero", codec.encode_frame, value)

    def test_encoder_rejects_bad_utf8(self):
        self.assert_error("utf8-invalid", codec.encode_frame, codec.Text(b"\xc0\x80"))

    def test_encoder_rejects_unsorted_and_duplicate_records(self):
        null = codec.Null()
        self.assert_error(
            "record-order",
            codec.encode_frame,
            codec.Record(((b"z", null), (b"a", null))),
        )
        self.assert_error(
            "record-duplicate",
            codec.encode_frame,
            codec.Record(((b"a", null), (b"a", null))),
        )

    def test_limits_are_fail_closed(self):
        tiny = codec.Limits(max_frame=16, max_atom=4, max_depth=2, max_nodes=3)
        self.assert_error("atom-too-large", codec.encode_frame, codec.Text(b"12345"), tiny)
        self.assert_error(
            "depth-too-large",
            codec.encode_frame,
            codec.ListValue((codec.ListValue((codec.Null(),)),)),
            tiny,
        )


if __name__ == "__main__":
    unittest.main()
