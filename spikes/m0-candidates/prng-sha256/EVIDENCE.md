# Candidate evidence

Recorded 2026-07-24 on Darwin 25.5.0. Commands ran from this directory without
modifying any Shen-port checkout.

## Oracle

```text
$ python3 tests/oracle.py --check fixtures/vectors.json
python-oracle: vectors match
```

The oracle uses Python's arbitrary integers and `hashlib.sha256`. The committed
fixture includes three NIST SHA-256 vectors, hundreds-digit arithmetic,
arbitrary-size coordinate counters, named-stream blocks, and both accepted and
three-attempt rejection-sampling cases.

## Four-port run

Command: `sh test.sh`

```text
python-oracle: vectors match
shen-cl: PASS tests=29 real_seconds=0.36
shen-go: PASS tests=29 real_seconds=2.24
shen-rust: PASS tests=29 real_seconds=6.21
shen-lua: PASS tests=29 real_seconds=3.71
four-port candidate suite: ALL PASS
```

These are single sequential `/usr/bin/time -p` measurements with a warm
filesystem, not a benchmark. They include startup, source loading, bigint
vectors, ten SHA/stream blocks, and bounded sampling. Relative to Shen CL in
this one run: Go 6.22x, Rust 17.25x, Lua 10.31x.

## Runtime identity

| Port | Shen/runtime version | Checkout commit |
| --- | --- | --- |
| Shen CL | 41.2; Common Lisp port 3.0.3; SBCL 2.6.5-85913ede1 | `8df94be8365ab48561655673593c137f55f92cdb` |
| Shen Go | 41.2; Go port 1.0.0-rc1; go1.26.5 | `8775fc366945bfe863f0cb0e0af2ada901ae1819` |
| Shen Rust | 41.2; Rust port 0.1.0 | `a529924d7f9c16d839397148cf60747f736dd7b1` |
| Shen Lua | 41.2 | `c85ad7edc79e183918b67862b8a60fa17c7ac9b9` |

## Scope and claims

The suite proves candidate-level cross-port output against checked-in,
independently generated values. It does not claim a whole-system D0, D1, D2,
or D3 profile. The primary selection risk is the arithmetic-only SHA
implementation's allocation and runtime cost.
