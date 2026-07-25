# M0 adversarial verifier

This directory is an independent negative/mutation harness. It gives selected
M0 implementations hostile executable cases without importing production
modules or assigning production semantics to Python.

## Runnable now

From the repository root:

```text
PYTHONDONTWRITEBYTECODE=1 shen/tests/adversarial/run
PYTHONDONTWRITEBYTECODE=1 shen/tests/adversarial/run --probe-ports
```

The first command uses only Python's standard library and covers:

- exact integers above 2^53 and 2^64, plus 600-digit positive and negative
  values, with a float-coercion mutation;
- insertion/hash order, locale-like collation, and exception-prose leaks;
- malformed UTF-8, duplicate fields, truncation, over-limit declarations, no
  effect before validation, and every contiguous chunk split of short frames;
- reducer input purity, time rollback, implicit time advance, stale IDs, and
  deterministic tie ordering;
- PRNG path isolation, counters above 2^64, and rejection sampling at the
  modulo-bias tail;
- fake adapter omission, alteration, response reorder, profile downgrade, and
  invented facts;
- a mutation gate proving that one changed invalid fixture, required port,
  vector, or marker makes the gate fail.

`--probe-ports` additionally executes read-only version queries against
shen-go, shen-cl, and shen-rust, plus `(+ 1 1)` against shen-lua (whose
launcher has no version option). Environment variables
`URDR_SHEN_GO`, `URDR_SHEN_LUA`, `URDR_SHEN_CL`, and `URDR_SHEN_RUST` override
their paths. These are read-only availability probes, not semantic agreement.

## Pending selected APIs

No M0 production API exists on the `main` revision this branch started from.
The following bindings are therefore deliberately absent:

| Selected owner | Required integration seam |
| --- | --- |
| canonical values/text | Replace `parse_integer`, `render_integer`, field sorting, and stable rejection markers with calls through the selected Shen fixture entry point. Preserve exact large-number and runtime-leak attacks. |
| UAP v1 | Replace `PrototypeFrameDecoder`, provisional u32be framing, 1 MiB cap, and regex duplicate detector with the accepted byte parser and normative limits/error values. Run each invalid fixture at every chunk boundary and assert zero effects. |
| world reducer | Translate prototype world/events into selected constructors; compare canonical output bytes; assert input world/event hashes remain unchanged after rejection and success. Replace the provisional tie key with the accepted ordering key. |
| PRNG | Replace SHA-256 prototype coordinates/vector with the selected algorithm and published vectors. Retain independent paths, arbitrary-size counters, and an injectable tail source for bounded-draw rejection. |
| adapter validation | Map fake observations to selected UAP values and assert canonical fail-closed results for omission, alteration, reorder, downgrade, and invented facts. |
| Bifrost gate | Register selected positive and negative entry points. A run is acceptable only when all four required ports execute the same attacks and emit byte-identical canonical results. Missing launchers or fixtures must fail, not skip. |

The prototype vector in `gate-spec.json` guards this harness against a vacuous
gate. It is not a candidate production PRNG vector. Likewise, the prototype
event ordering and framing are attack vehicles, not architecture decisions.
