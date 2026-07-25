import importlib.util
import json
from pathlib import Path
import unittest


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("oracle", HERE / "oracle.py")
assert SPEC and SPEC.loader
oracle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(oracle)


class OracleTests(unittest.TestCase):
    def test_published_vectors_are_current(self):
        actual = json.loads((HERE / "vectors.json").read_text(encoding="utf-8"))
        self.assertEqual(actual, oracle.vectors())

    def test_random123_published_zero_vector(self):
        self.assertEqual(
            oracle.philox4x32_10((0, 0, 0, 0), (0, 0)),
            (0x6627E8D5, 0xE169C58D, 0xBC57AC4C, 0x9B00DBD8),
        )

    def test_field_boundaries_are_injective_in_frame(self):
        left = oracle.coordinate_frame(7, b"a", b"bc", b"", 9, 2)
        right = oracle.coordinate_frame(7, b"ab", b"c", b"", 9, 2)
        self.assertNotEqual(left, right)

    def test_random_access_has_no_shared_stream_state(self):
        args = (42, b"network", b"link-2", b"loss", 3)
        before = oracle.prng_block(*args, 0)
        oracle.prng_block(*args, 999)
        self.assertEqual(oracle.prng_block(*args, 0), before)

    def test_rejection_transcript_has_exact_subcoordinates(self):
        value, transcript = oracle.sample_bounded(
            1, b"tests", b"actor", b"reject", 1, 32769
        )
        self.assertEqual(value, 30510)
        self.assertEqual(
            transcript,
            [
                {
                    "attempt": "0",
                    "block_indices": ["0"],
                    "candidate": "59350",
                    "verdict": "reject",
                },
                {
                    "attempt": "1",
                    "block_indices": ["1"],
                    "candidate": "30510",
                    "verdict": "accept",
                },
            ],
        )


if __name__ == "__main__":
    unittest.main()
