#!/bin/sh
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(CDPATH= cd -- "$here/../../.." && pwd)

cd "$repo"
python3 -m unittest discover \
  -s "spikes/m0-candidates/canonical-rfc9804/tests" \
  -p "test_*.py" -v
python3 "spikes/m0-candidates/canonical-rfc9804/codec.py" fixtures
python3 "spikes/m0-candidates/canonical-rfc9804/cross_port.py"
