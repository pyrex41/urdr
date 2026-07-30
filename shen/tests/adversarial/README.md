# Adversarial verifier (M0 + M1)

This directory is an independent negative/mutation harness. It gives selected
M0 and merged M1 implementations hostile executable cases without importing
production Shen modules or assigning production semantics to Python.

## Runnable now

From the repository root:

```text
PYTHONDONTWRITEBYTECODE=1 shen/tests/adversarial/run
PYTHONDONTWRITEBYTECODE=1 shen/tests/adversarial/run --probe-ports
```

The offline test suite also runs as part of `make test` (and therefore
`make quality` and `make ci`) via a second unittest discovery root;
`make adversarial` runs it together with the launcher probes.

The first command uses only Python's standard library (plus the production
ADR 0002 netstring codec for framing/scenario frame decode) and covers:

### M0

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

### M1 (merged surfaces only; not Wave F search/shrink)

- **Scenario**: unknown keys, missing required keys, reordered/duplicate
  records rejected before any world effect; fixture corpus stable codes
  pinned; high-value invalid frames exercised via the production codec.
- **NetKAT**: policy/field/value/operator mutations flip equivalence and
  reachability oracles; unknown field/value/head and non-predicate `neg`
  reject with stable codes; invalid-policy fixtures pin `term-head`.
- **Netpol**: unresolvable named port, out-of-vocabulary port, unknown
  protocol, inverted `endPort`, unmodeled manifest fields, and
  `hostNetwork` under policy fail closed; expect fixtures pin error symbols.
- **Properties**: host-log prose and host-log-shaped trace fields rejected;
  M3+ `log`/`crash` classes rejected in M1; empty-stream `never` PASS and
  liveness FAIL pinned; vacuous temporal antecedent pinned as `vacuous`.
- **Replay/certificate**: transcript withhold/extend/reorder/tamper map to
  documented divergence codes; `modeled-world-only` is unconditional;
  `spec-semantics-only` is baseline-derived; non-`{pure,modeled}` entropy
  voids certification; status precedence DIVERGED > UNCERTIFIED > FAIL/PASS.
- **Component interface**: reserved authorities (`event`, `event-id`,
  `time`, `seed`, …) in state/facts/choices fail closed; unordered choices
  and empty alternatives rejected.
- **Gate mutations**: one changed M1 fixture digest or `m1_marker` fails
  the gate (sha256-pinned scenario/NetKAT/netpol fixtures in
  `gate-spec.json`).

`--probe-ports` additionally executes read-only version queries against
shen-go, shen-cl, and shen-rust, plus `(+ 1 1)` against shen-lua (whose
launcher has no version option). Launchers default to the pinned checkouts
under `.cache/urdr/dependencies` (see `scripts/build-ports`);
`URDR_DEPENDENCIES` overrides that tree, and `URDR_SHEN_GO`,
`URDR_SHEN_LUA`, `URDR_SHEN_CL`, and `URDR_SHEN_RUST` override individual
paths. These are read-only availability probes, not semantic agreement.

## Production seams

Framing attacks use the production ADR 0002 netstring decoder in
`adapters.common.uap`. Invalid fixtures under `protocol/fixtures/v1/invalid/`
are netstring wire bytes. Scenario and netpol expect frames are decoded with
the same codec to exercise hostile structure without importing Shen.

Other attack classes still use local pure oracles so they remain offline and
independent of Shen launchers. Cross-runtime agreement for positive semantics
is owned by `make conformance` / `scripts/bifrost-gate`, not this harness.

Milestone status and gate digests live in `docs/status/m0.md`. M1 surfaces
covered here are those already merged on main (scenario, NetKAT, netpol,
properties, replay/certificate, component interface).
