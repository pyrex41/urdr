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

## Production seams

Framing attacks use the production ADR 0002 netstring decoder in
`adapters.common.uap`. Invalid fixtures under `protocol/fixtures/v1/invalid/`
are netstring wire bytes.

Other attack classes still use local pure oracles so they remain offline and
independent of Shen launchers. Cross-runtime agreement for positive semantics
is owned by `make conformance` / `scripts/bifrost-gate`, not this harness.

Milestone status and gate digests live in `docs/status/m0.md`.
