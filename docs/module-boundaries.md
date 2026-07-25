# Module boundaries

Status: Wave 0 repository contract

This document turns the authority rules in `SPEC.md` §6 and §27 into repository
ownership boundaries. Directory ownership does not transfer simulation policy:
the authoritative portable Shen world kernel is the only component that may
advance logical time or choose world behavior.

## Authority and dependency direction

Dependencies point inward toward stable data contracts:

```text
scenarios/properties/search
            |
            v
      Shen world kernel  <---- canonical values and protocol schemas
            |
            v
      UAP command boundary
            |
            v
native adapters / guest / gateway  ----> external systems
```

Observations travel back through UAP as facts. They become world state only
after the Shen reducer consumes them as events. A native completion, callback,
readiness notification, wall-clock timeout, map iteration, or thread schedule
must never directly order world events.

## Owned module roots

| Path | Responsibility | Must not own |
| --- | --- | --- |
| `shen/world/` | Canonical world, reducer, logical time, event ordering | I/O, host clocks, runtime-specific state |
| `shen/scenario/` | Scenario declarations and validation | Adapter effects |
| `shen/properties/` | Deterministic property verdicts | Host log interpretation |
| `shen/search/`, `shen/shrink/` | Explicit choices, replayable search and minimization | Ambient randomness |
| `shen/protocol/` | Portable UAP values and validation | Transport I/O |
| `protocol/` | Versioned byte-level UAP contract and fixtures | Simulation policy |
| `adapters/` | Effect execution and fact reporting | Time, ordering, random, profile, or certification decisions |
| `guest/` | Controlled kernel, devices, agent, image inputs | World-policy decisions |
| `openresty/` | Service transport and delegated pure models | Independent timers or event ordering |
| `scenarios/` | Versioned scenario inputs | Hidden mutable artifacts |
| `scripts/`, `Makefile` | Offline quality gates and explicit bootstrap | Product semantics |
| `build/locks/` | Reviewed schemas and immutable dependency pins | Floating versions or generated downloads |
| `docs/adr/` | Accepted architectural decisions | Unreviewed implementation overrides |

Tests live with, or in the declared test root for, the module whose contract
they exercise. Cross-module fixtures belong in `protocol/fixtures/` only when
they are part of the public byte contract.

## Boundary rules

1. Shen allocates request IDs, event IDs, choice IDs, logical time, and named
   random coordinates. Adapters may return only externally observed identifiers
   that the protocol explicitly classifies as facts.
2. Adapters do not retry, reorder, schedule, select profiles, downgrade
   capabilities, or turn host elapsed time into world state without a Shen
   command.
3. Canonical formats use integer and byte semantics fixed by accepted ADRs.
   Runtime maps, floating point, locale, exception prose, and object identity
   cannot cross a semantic boundary.
4. UAP transport implementations share one framing and validation contract.
   Invalid input fails before effects; in-process transport has no privileged
   semantics.
5. Generated files and downloaded dependencies stay in ignored output/cache
   paths. Checked-in fixtures, locks, and schemas are immutable inputs, not
   generated residue.
6. A new dependency edge or transfer of authority requires an ADR when it
   changes accepted design. Unsupported behavior lowers certification or aborts;
   it is never converted to a skip.

## Ownership verification

Each isolated contributor records an explicit path allowlist and runs
`scripts/check-owned-paths`. For example:

```text
scripts/check-owned-paths --base-ref main \
  --allow 'protocol/uap.md' --allow 'protocol/fixtures/v1/'
```

The check considers branch commits plus staged, unstaged, and untracked files.
Its foundation tests include both accepted and rejected path sets so that an
out-of-scope edit cannot silently pass. This is a review boundary check; the
architectural authority rules above remain mandatory within every allowed path.
