# Urdr deep-dive review: four persona lenses, gaps, and a generalization roadmap

Date: 2026-07-29
Reviewed at: `dfb03cb` (clean tree)
Scope: everything in-tree — `shen/` (36 modules, ~1.4 MB), `adapters/common/uap/`,
`protocol/`, `scenarios/`, `scripts/`, `build/`, `bifrost.suite.json`, all six
ADRs, plans, status docs, and the last ~40 commits of history.

This review uses four *persona lenses* — review perspectives written in the
spirit of well-known engineers (Linus Torvalds, Rich Hickey, Kyle Kingsbury,
Leslie Lamport). They are rhetorical devices for covering the design space from
four different value systems, not statements by, or attributed to, the real
people.

---

## 1. What Urdr actually is today

The honest inventory, before any opinions:

**Built and gated (M0 + M1):**

- A portable semantic nucleus: canonical values (ADR 0002), base-10,000
  software integers and coordinate-addressed SHA-256 PRNG streams (ADR 0003),
  netstring framing, all cross-checked against independent Python oracles and
  byte-identical across four Shen ports at the gate.
- An abstract world kernel: a pure reducer over a 9-slot world value with
  two-phase logical time (`schedule` / `advance-to-next-event`), four
  hardcoded event kinds, and a component contract
  (`state -> event -> [step state' facts choices]`) with structural
  reserved-authority enforcement.
- Abstract models: network (NetKAT-audited delivery), timer, fault; a
  history-free NetKAT fragment with exhaustive finite-space
  equivalence/reachability; a Kubernetes NetworkPolicy compiler
  (`spec-semantics-only`); a symbolic-to-concrete witness bridge.
- Testing machinery: seeded exploration with two strategies, transcript
  shrinking gated on a failure-signature digest, replay with a five-way
  divergence taxonomy, a property engine (invariant / temporal / liveness)
  with rigorous finite-trace semantics, and modeled-run certificates.
- Evidence infrastructure: a fail-closed Bifrost gate with two-key pinning,
  launcher provenance stamps, a shake lane, offline-by-construction
  conformance, and an 87-test adversarial suite.

**Specified but not built (M2–M7):** everything involving a real system —
Firecracker, custom guest kernel, packet broker, record/replay gateway, k3s,
the CLI (`urdr run/explore/replay/shrink/...` does not exist), snapshots,
coverage-guided search, snapshot-aware shrinking.

**The single most important finding of this review**, which every lens below
converges on independently:

> **There is no path in the repository where a seeded search discovers a real
> property violation.** The flagship integration demo explores a no-op counter
> world with a marker-grep oracle and hand-written verdict records
> (`shen/tests/integration/run-tests.shen:121-133, 184-196, 225-229`). The
> reference scenario `scenarios/abstract/partition-retry.shen` is validated
> but never executed — and its only property cannot even be loaded: its
> `pattern` is a bare symbol where the engine requires a
> `{name, source, value}` record, so `urdr.properties.load` returns
> `[error properties-pattern-shape]`
> (`partition-retry.shen:112-113` vs `properties.shen:209-211, 1019-1039`).
> Every layer is individually excellent and individually golden-pinned; the
> composition `scenario -> world -> search -> trace -> properties -> shrink ->
> certificate` exists only as hand-wired fragments in test files.

---

## 2. Persona lens: Linus Torvalds — "show me the code that runs"

*Values: pragmatism, working code over designs, taste, hostility to
unnecessary complexity and to claims not backed by execution.*

**Verdict: impressive discipline wrapped around a system that has never done
its job even once. Fix that before writing another line of specification.**

What this lens respects:

- The fail-open archaeology in the commit history is real engineering taste.
  `9d8fe1d` catching a four-port PASS that ran a stale binary — "the absence
  of work read as agreement" — and fixing it with build stamps that refused a
  bad run one commit later (`dfb03cb`) is exactly how you build trust in a
  gate. Most projects never notice this class of bug; this one has caught four
  of them and documented each.
- `make conformance` failing closed on a missing port, a skipped launcher, a
  dirty tree, a wrong kernel version, or a single changed byte
  (`scripts/bifrost-gate:799-877`) is the right kind of paranoia.
- The UAP Python reference (`adapters/common/uap/`) is clean, boring code with
  the invariants enforced where they can be violated
  (`transport.py:160`: "Move bytes only; readiness never orders world
  observations") and a unit test that mechanically bans time/random imports.

What this lens would tear into:

1. **The demo is a stub and the docs half-admit it.** A testing framework's
   only proof of life is finding a bug. The exit demonstration's "oracle" is
   `(if (uit.has-inject? Transcript) fail-verdicts pass-verdicts)` — a string
   grep for a marker the test itself planted. That's a test of the test. The
   partition-retry story in the plan ("client retries, ack deadline missed")
   does not exist as code anywhere in the tree. Until
   `explore` finds a real liveness violation in a real modeled system and
   `shrink` minimizes it, the framework is unproven, full stop.
2. **Performance is an in-tree algorithmic choice being blamed on the ports.**
   `urdr.int.small.divmod` is repeated subtraction (`integer.shen:3-9`); a
   single 256-bit divmod — one PRNG sample — costs on the order of 10^7 host
   operations, and `docs/status/m1-port-perf-handoff.md` shows replay timing
   out at >900 s on two of four ports. The SHA half was fixed the right way
   (verified host dispatch, 58×, `f1f3aa4`); the bigint half has an idiomatic
   in-tree fix (the descending-weights decomposition already used at
   `canonical.shen:72-78`) and should not be filed as an upstream port issue.
3. **Copy-paste that will bite.** The 9-field world tuple is written out
   longhand five times inside `urdr.world.schedule` alone
   (`world.shen:177-222`); there are two independent decimal↔limb codecs
   (`canonical.shen:426-465` vs `integer.shen:371-412`) with no
   cross-agreement test; two error vocabularies bridged by `(str E)` on a
   symbol, which the project's own ADR 0006 says is a cross-port gamble.
4. **The most load-bearing byte in the format comes from the one primitive
   declared non-portable.** Every atom's length prefix is produced by
   `(str N)` on a host number (`canonical.shen:696-697`), the same week ADR
   0006 was written to say host number rendering is not portable. It's safe
   today only because frames are capped at 65,536 octets. Make the length
   renderer use the software-integer path and delete the coincidence.
5. **CI has never run.** Every green result is one laptop's word. The 180-minute
   nightly workflow is the most load-bearing unexecuted code in the tree.
   And the 87-test adversarial suite is wired into *nothing* — not
   `make quality`, not `make ci`, not either workflow.
6. **The M2+ ambitions are a maintenance sinkhole being casually signed up
   for.** A custom Linux kernel with a paravirtual clocksource, a maintained
   Firecracker fork for device determinism, a QEMU TCG oracle lane — each of
   these is a multi-person, multi-year maintenance commitment. The spec treats
   them as milestones. Prove the abstract layer earns its keep first; it
   hasn't yet.

**Linus-lens priority:** wire one real end-to-end bug hunt (scenario in,
minimized failing artifact out), fix the divmod, wire the adversarial suite
into the gate, and stop speccing until the demo is real.

---

## 3. Persona lens: Rich Hickey — values, decomplecting, and the inert DSL

*Values: immutable values over places, data over code, decomplecting,
semantics before convenience.*

**Verdict: the value discipline is the best I've seen in a system like this —
and the architecture still complects the two things it most needs to separate:
declaration and execution.**

What this lens celebrates:

- **Everything observable is a value.** Canonical octets with one encoding,
  no host strings, no host numbers, no map iteration order; encoders that
  reparse their own output so budgets bind both directions
  (`canonical.shen:899-924`); records with strictly ascending keys enforced
  on encode *and* decode. Scalar identity is semantic identity — no locale,
  no NFC. This is place-free, epochal semantics done properly.
- **Randomness as coordinates, not state.** A draw is a pure function of
  `(seed, subsystem, actor, purpose, counter, block-index)`
  (`prng.shen:500-513`); rejection retries advance only the block index and
  land in the transcript. Streams cannot perturb each other *structurally*.
  This is the difference between "we were careful" and "interference is
  inexpressible."
- **The reserved-authority scan** (`component.shen:25-33, 62-98`): authority
  separation enforced on returned *data*, not by convention. A component that
  tries to smuggle `time` or `event-id` into its output is rejected wholesale.
- The property engine's refusal to conflate: `ne` is not `not eq` under
  undefinedness (`properties.shen:113-118`); vacuous passes are a distinct
  witness kind pinned into certificates; "PASS that fired" and "PASS that
  never fired" are different values.

What this lens would push back on:

1. **The scenario is data that nothing interprets.** A scenario declares
   `budget`, `seed`, `observations`, `properties` — and every one of them is
   inert: validated, then read by no production module
   (`scenario.shen:1207-1229`; `search.shen:525-534` takes its own budget).
   The declaration and the machine that could run it are two artifacts joined
   only in test files. That is incidental complexity of the worst kind: the
   *interface* exists, the *semantics* of the interface don't. Either the
   scenario drives the run or it is documentation.
2. **Behavior is opaque code where it should be data or named.** A component
   handler is an unhashed Shen closure living inside world state, "never
   encoded, compared, or hashed" (`component.shen:254-257`). Consequences: a
   world is not serializable, replay needs out-of-band registry
   reconstruction, and *no certificate can say which model produced a run*.
   The system's one identity gap is exactly where behavior hides from the
   value system. Name handlers (registry of symbols → functions, hash the
   symbol and a version), and the certificate can finally commit to the model.
3. **Facts — the primary observable — are not committed to.** Snapshots hash
   full verdicts but only a *count* of facts (`world.shen:598-619`), so two
   runs emitting different facts from identical states have identical
   digests, identical event-record state hashes, identical replay verdicts.
   A certified run does not commit to its own observable output. This
   contradicts the project's own definition of observable equivalence
   (SPEC §4.1) and should be treated as a correctness bug, not a TODO.
4. **Two vocabularies for one concept.** Errors are octet-literal codes in
   `world.shen`, bare symbols in `integer.shen`/`prng.shen`, bridged with
   `(str E)` (`common.shen:43-44`). One error representation, one place.
5. **Simplicity debt in the small:** whole-world literals instead of
   functional setters; `encoding-of` swallowing encode failures into
   sort-as-empty (`common.shen:81-88`); a silent state wipe in
   `fault.shen:401-409`; O(n²) re-encoding inside comparison sorts
   (`common.shen:95-107`). None fatal; all the kind of complecting that
   compounds.

**Hickey-lens priority:** make the scenario *the* program (one driver
consuming seed/budget/properties), name and hash handlers, commit facts to
the snapshot digest, unify errors. The value substrate deserves an
architecture as honest as it is.

---

## 4. Persona lens: Kyle Kingsbury — will it find bugs in real systems?

*Values: empirical failure-finding, fault-model breadth, honesty about what a
test can and cannot conclude; a decade of watching real databases fail under
partitions.*

**Verdict: this is the most rigorous replay substrate I've reviewed, attached
to a fault-finder that has never found a fault. The gap between "can replay a
failure deterministically" and "can produce a failure worth replaying" is the
whole product, and it's open.**

What this lens admires — genuinely, because Jepsen-style testing lacks it:

- **Deterministic replay with a principled divergence taxonomy.**
  Truncated / extended / reordered / tampered / event-divergence /
  state-divergence, each with a stable code, partitioned by whether they are
  evidence about the *engine* or the *artifact*
  (`replay.shen:70-104`, `certificate.shen:614-630`). Jepsen reruns and
  hopes; this replays and *knows*. If the M2+ story lands, that's a
  capability nemesis-style testing has never had on real binaries outside
  FoundationDB-style bespoke harnesses and Antithesis.
- **The failure signature as shrink oracle** — digest of the whole FAIL
  record including witness, so shrinking cannot drift onto a different bug
  (`certificate.shen:572-608`). Correct, and better than most PBT shrinkers.
- **The witness bridge**: a symbolic "unreachable" claim must be reproduced
  by the concrete model or it is reported `unconfirmed`, never upgraded
  (`netkat-witness.shen:22-46`). That is the exact discipline that separates
  a checker from a rumor mill.
- Finite-trace property semantics that refuse the benefit of the doubt at end
  of trace, with vacuity surfaced (`properties.shen:225-263`). Liveness
  handled honestly on finite traces is rare.

What this lens would say is missing before it finds a single real bug:

1. **The search has no memory and the demos have no system.** Exploration is
   uniform or statically-weighted sampling over menus; there is no coverage
   map, no visited-path set, no event-pair novelty — the entire inter-attempt
   state is one integer (`search.shen:536-546`). Budget counts attempts, not
   evaluations, doesn't dedupe paths, and `exhausted` returns nothing about
   what was covered (`search.shen:539`). EVAL errors are silently swallowed
   and loop (`search.shen:583-585`) — an always-crashing oracle reads as
   "no bug found." For finding rare interleavings, memoryless sampling over
   a handful of menus is far below the state of the art (PCT, coverage-guided
   fuzzing, partial-order-aware exploration).
2. **The property language cannot express the properties that matter.** No
   linearizability or serializability checkers, no quantifiers, no arithmetic
   over observations, no nested temporal operators — the implemented classes
   are invariant/temporal-pattern/liveness-deadline over exact-match facts.
   You cannot state "reads observe the most recent acknowledged write" today.
   Jepsen's checkers (Knossos, Elle) are the bar for finding *consistency*
   bugs; Urdr's property layer currently finds *protocol-shape* bugs. That's
   a fine start but the class of bug that motivates a lab like this is the
   former. (The module-boundary design — verdicts as opaque canonical values —
   means checkers can be added without touching certificates. Good.)
3. **Fault-model breadth is narrow and half-plumbed.** Five fault kinds
   (crash/delay/drop/partition/restart), node-scoped; no asymmetric
   partitions as first-class scenarios yet (the mask algebra could express
   them), no clock skew (single logical clock), no storage faults (SPEC §17
   lists them; no weight class, no model), no gray failures / slow nodes. And
   the documented fault routing — kernel delivers `crash`/`restart` facts to
   the target process — *does not exist*; tests hand-schedule the mask fact
   into the net component (`fault.shen:612-618` vs
   `tests/models/run-tests.shen:888-892`).
4. **Selected alternatives are not pinned in the replayable transcript.** A
   schedule entry records the *menu*, and the world re-draws on replay
   (`search.shen:352-360`). Same seed → same draw, so it's deterministic —
   but it couples a minimized artifact to the PRNG rather than to the
   decision, makes transcripts fragile under any strategy change, and forced
   the integration test to invent a parallel `command` marker to carry the
   selection. Record the decision; derive nothing on replay that was already
   decided.
5. **The nemesis analogy that matters:** Jepsen ships because a new system
   costs days: write a client, pick checkers, reuse the nemeses. Urdr's
   current cost for a new modeled system is weeks (see §7), and for a *real*
   system is "wait for M2–M5." The single highest-leverage move toward the
   stated goal — diverse complicated systems, small configuration — is
   making the modeled path cheap *now*, because that's also the test-bed the
   real-system adapters will need.

**Kingsbury-lens priority:** one real modeled system with a real injected bug
found by search (not planted by marker); pin selections into transcripts;
then a linearizability checker over facts; then fault-model breadth.

---

## 5. Persona lens: Leslie Lamport — specification, refinement, and what the
math actually says

*Values: precise specification, state machines, invariants and refinement
mappings, suspicion of testing claims not grounded in a spec.*

**Verdict: the kernel is a legitimate state-machine specification with an
execution engine — unusual and commendable. But the framework confuses two
different objects (the model and the system), has no stated refinement
relation between them, and its temporal fragment is too weak to say what its
own reference scenario means.**

What this lens approves of:

- The world is honestly `(world', commands, choices) = reduce(world, event)`,
  time advances only by explicit transition, rollback is refused with a named
  code, and history is a first-class value (transcript, event log with causal
  parents and state hashes). This is a state machine you could reason about,
  not a pile of callbacks.
- Determinism is treated as a *theorem obligation*, not a vibe: profiles
  D0–D3 with capability requirements, an entropy firewall that classifies
  every boundary observation, certificates that report the achieved profile
  and refuse to claim what wasn't demonstrated
  (`certificate.shen:632-636`: an M1 run can never be read as a D1 claim).
  The run-id preimage discussion — hashing the *requested* profile but not
  the *achieved* one, "a run must not change identity because it failed to
  reach the profile it asked for" — is exactly right.
- ADR 0006 is a model of specification honesty: measured divergence tables,
  a decision that a class of agreement is "coincidence, not a constraint,"
  and open questions left open rather than settled by fiat.

What this lens would object to:

1. **No refinement story connects the abstract world to the real system.**
   M1 models a network; M4 runs k3s. What is the claimed relation between
   them? The spec never says. If the abstract model's partition behavior is
   supposed to predict the real cluster's, that is a refinement mapping and
   it needs to be stated — which observations correspond, which abstract
   transitions abstract which concrete ones, and what a modeled-world PASS
   licenses you to believe about the deployed system (possibly: nothing).
   The `spec-semantics-only` marker on NetworkPolicy shows the team knows how
   to bound a claim; the same construction is needed one level up, for the
   entire modeled world. Without it, the two halves of the project are two
   projects.
2. **Randomized exploration is not verification and the vocabulary should
   keep them apart.** With a ≤1024-element header space the NetKAT layer does
   *exhaustive* checking — a genuine decision procedure. The world-level
   search, by contrast, samples: it can find violations, never establish
   invariants. The certificate machinery correctly reports verdicts, but
   nothing in the artifact distinguishes "property holds on all schedules in
   this finite model" from "property held on 32 sampled schedules." For small
   modeled state spaces, an exhaustive mode (the model *is* finite; the
   `query.shen` BFS is nearly this already) would turn some PASSes into
   theorems. Say which kind each PASS is.
3. **The temporal language is too weak for its own examples.** Three fixed
   temporal schemas over exact-match patterns; no nesting, no quantification
   over actors ("every request is eventually acknowledged" requires one
   property per request id today), no past-time operators, no arithmetic. The
   reference scenario's intent — "client retries until ack or deadline" — is
   not expressible as anything but a single deadline pattern. The finite-trace
   semantics that *are* implemented are rigorous (strong `before`, safety
   passes empty, liveness fails closed at trace end, vacuity distinguished);
   the foundation deserves a fragment worth the rigor: parameterized
   properties (quantify over a declared finite domain — consistent with the
   everything-finite design) and nested operators first.
4. **Two unsoundness seams in an otherwise careful boundary.** The kernel
   enforces canonical ordering on component-*published* choice alternatives
   but not on *scheduled* choice events, and selects by positional index
   (`world.shen:118-133` vs `component.shen:122-126`) — two permutations of
   the same alternative set are different worlds under the same seed. And
   snapshots do not commit to emitted facts (`world.shen:598-619`), so the
   induction hypothesis every replay verdict rests on ("same state hash ⟹
   same observable behavior") is false as stated. Both are one-file fixes;
   both should be treated as specification defects.
5. **A machine-checked core would repay itself.** The reducer, the component
   contract, and the PRNG coordinate scheme are small, total, and
   first-order — a TLA+ (or even property-based) specification of the
   kernel's own invariants (time monotonicity, transcript determinism,
   stream isolation, snapshot completeness) would catch exactly the class of
   seam above, and the project's canonical-value discipline makes state
   spaces enumerable.

**Lamport-lens priority:** state the refinement claim (even if it is "none
yet"); commit facts to state digests; enforce ordering at both doors; add an
exhaustive mode for finite models; grow the temporal fragment by
parameterization, not ad hoc schemas.

---

## 6. Consensus findings, ranked

Where all four lenses independently landed:

| # | Finding | Evidence | Severity |
|---|---|---|---|
| 1 | No end-to-end path: search has never found a real property violation; demos use a planted-marker oracle over a no-op world; the reference scenario's property doesn't load | `integration/run-tests.shen:121-229`; `partition-retry.shen:112` vs `properties.shen:1019-1039` | Critical (product) |
| 2 | Scenario declarations are inert (`budget`/`seed`/`observations`/`properties` consumed by nothing); no scenario→run driver; `from-scenario` has zero production callers | `scenario.shen:1207-1229`, `registry.shen:177` | Critical (product) |
| 3 | Component layer can't express heterogeneous systems: one handler+init for all `process` components, components don't know their own names, kernel fact-routing documented but absent, component kinds pinned in two core files | `registry.shen:132-183`, `world.shen:349-356`, `fault.shen:612-618`, `scenario.shen:233-237` | Critical (generalization) |
| 4 | Snapshots/certificates don't commit to emitted facts or handler identity — a certified run doesn't commit to its observable output or to which model produced it | `world.shen:598-619`, `component.shen:254-257` | High (correctness) |
| 5 | Selected alternatives not pinned in transcripts; replay re-draws from PRNG | `search.shen:352-360` | High (architecture) |
| 6 | Search is memoryless (no coverage guidance — M6-deferred, but also no path dedupe, no error surfacing, info-free `exhausted`); shrinker is greedy single-pass deletion (no ddmin, no value shrinking, no cross-class fixpoint) | `search.shen:536-596`, `shrink.shen:300-350` | High (capability) |
| 7 | Performance: repeated-subtraction divmod makes one PRNG sample ~10^7 host ops; two ports time out; O(n²) re-encoding in choice sorts | `integer.shen:3-9`, `common.shen:95-107`, `m1-port-perf-handoff.md` | High (usability) |
| 8 | Evidence infrastructure gaps: adversarial suite wired to nothing; CI never executed; status docs carry stale pins/digests; some `test.sh` self-bless goldens; hardcoded personal launcher paths | `Makefile:24-26`, `m1.md:105-146` vs `build/locks/`, `grammar/test.sh:81-82`, `adversarial/run:16-37` | High (trust) |
| 9 | Property language can't express consistency properties (no linearizability, no quantifiers, no nesting); crash/log/metamorphic classes rejected | `properties.shen:209-211, 1335-1337` | Medium (capability) |
| 10 | Latent correctness seams: choice-event ordering unenforced at one door; limb-endianness bug in `search.shen`/`grammar.shen` `small-of` (silent wrong answer ≥10000); grammar ids break octet ordering at N≥11; duplicated decimal codecs untested against each other; `(str N)` renders every atom length | `world.shen:118-133`, `search.shen:249-251`, `grammar.shen:268-289`, `canonical.shen:426-465, 696-697` | Medium (latent) |

And the consensus strengths, equally real:

- The **canonical-value / software-integer / coordinate-PRNG substrate** is
  byte-identical across four runtimes with independent oracles — the hard,
  boring foundation most projects skip, done properly.
- The **replay/divergence/certificate machinery** is the best-engineered part
  of the tree and is *system-agnostic already*.
- **Fail-closed is a practiced culture**, not a slogan: reserved-authority
  scans, witness `unconfirmed`, `spec-semantics-only` markers, entropy
  firewall reporting all five classes, gates that refuse absence as
  agreement, ADRs that record open defects.
- The **process discipline** (ADRs, non-claim tables, path-ownership
  enforcement, commit messages as engineering documents) is well above
  industry norm and is itself a transferable asset.

---

## 7. Generalization: testing diverse systems with small configuration

The stated ambition: *"with a relatively small amount of configuration we
could test really diverse, somewhat complicated systems."* Assessment: the
architecture was shaped for this and the substrate supports it, but today the
configuration surface is an illusion — the DSL validates and drives nothing,
and the parts that would make a second system cheap are the parts that don't
exist.

### 7.1 What already generalizes (don't rebuild these)

- **The kernel contract.** Any system expressible as
  `state -> event -> [step state' facts choices]` over canonical values plugs
  into the reducer with no core edits — `netkat-witness.shen:198-200` proves
  it from outside `models/`. Reserved-authority scanning, choice canonicality,
  and fail-closed error conversion apply to user components for free.
- **The entire evidence spine.** Transcripts, replay taxonomy, failure
  signatures, shrinking, certificates, PRNG coordinates, canonical
  serialization — none of it knows what a "network" is. This is the moat:
  a new system inherits deterministic replay and certified minimization
  *by construction*.
- **UAP as the native boundary.** The contract (Shen-allocated IDs,
  idempotency fingerprints before effects, no adapter-side policy, stable
  error codes) is the right shape for arbitrary native adapters. It needs
  size/concurrency/lifecycle extensions, but the authority split is correct
  and already mechanically enforced on the Python side.

### 7.2 What blocks "small configuration" (the gap cluster)

A competent engineer modeling a 5-node job queue today needs: 9 concept
areas (two ADR value systems, the component contract, the property node
language, the search closures, Shen itself, octet-list conventions), 6–8
artifacts, hand-patching of `registry.shen` or abandoning the DSL, manual
fault-fact plumbing per activation, and hand-assembly of the
explore/properties/certificate pipeline — realistically **2–4 weeks**, with
the only complete worked example being a stub counter. The cost driver is not
the DSL's strictness (well-designed, well-fixtured); it is the **missing
driver and the missing component ergonomics**.

### 7.3 Roadmap: three phases to a configurable laboratory

**Phase 1 — close the composition gaps (makes the existing promise true; ~all
in-tree, no new subsystems):**

1. *Scenario→run driver.* One production function:
   `urdr.run : scenario -> handler-table -> [certificate artifact]` that
   consumes the declared seed, budget, components, faults, properties, and
   observation points, assembles the registry, runs explore (or a single
   schedule), evaluates properties over the fact trace, and emits the
   certificate. This retires findings #1 and #2 in one move and gives the
   CLI (`urdr run/explore/shrink`) something to call.
2. *Registry as data.* Kind → (handler, init-builder) association table;
   per-component handler binding and per-component initial state in the
   roster; pass the component its own name in the event record. Three
   contained changes (`registry.shen:132-183`, `world.shen:349-356`) that
   unlock heterogeneous systems.
3. *Kernel fact router.* The missing authority: a scenario-declared routing
   relation (which component's facts, matching what pattern, become whose
   inputs, at what delivery choice). Do it as a kernel-owned component so
   ordering stays a world choice and the authority rule is preserved. This
   makes fault→process and process→process composition real instead of
   hand-wired transcripts, and it is a prerequisite for any protocol model.
4. *Pin decisions into transcripts* (record selected alternatives, not just
   menus) and *commit facts + named-handler identity into snapshot digests
   and certificates*. Both are honesty fixes the evidence machinery deserves.

**Phase 2 — make authoring cheap (turns weeks into days):**

5. *Two worked reference systems that are not networks* — a job queue with a
   lease-expiry invariant and a leader-election protocol with an
   agreement invariant — each as: one component module, one scenario file,
   properties, a golden suite, and a Bifrost case. These prove genericity,
   force the Phase-1 APIs to be real, and become the templates users copy.
   Acceptance bar per system: *search finds an injected bug from a seed,
   shrink minimizes it, replay reproduces it, certificate says so* — the M1
   exit demonstration, but earned.
6. *An authoring front-end.* Hand-writing canonical octet trees is the single
   biggest ergonomic tax. A small compiler from a friendly notation (EDN/JSON
   /sexpr with symbols and ordinary integers) to validated canonical frames —
   the generalization of `scripts/netpol-to-canonical` — plus a scenario
   schema reference doc. The strict core stays the semantic truth; the
   front-end is development convenience, exactly as netpol already frames it.
7. *Property library growth by parameterization*: quantified patterns over
   declared finite domains ("for every request-id: eventually ack"), then a
   linearizability checker consuming fact traces (verdicts are already opaque
   values to the certificate, so checkers bolt on without core changes).
8. *Search/shrink upgrades where they pay:* path dedupe + covered-set
   reporting in `exhausted`, surfaced EVAL errors, ddmin-style chunk deletion
   and value shrinking. Exhaustive-mode exploration for small finite models
   (the NetKAT layer already demonstrates the pattern) so some PASSes become
   theorems rather than samples.

**Phase 3 — real systems through the adapter boundary (the SPEC's M2+ path,
resequenced for generality):**

9. *Second UAP adapter first, microVM later.* Before Firecracker, ship a
   process-level adapter: run a real single-process system (an embedded KV
   store, a Raft library's binary) under the packet-broker pattern — SUT
   traffic through a world-controlled socket proxy, SUT clock via injected
   library/LD_PRELOAD or a protocol-level fake, storage completions gated by
   the adapter. This gets a *real* system under deterministic-ish test at D0
   ("captured") with honest classification of uncontrolled residuals — which
   the entropy firewall and certificate machinery are already built to
   report. The determinism profile system is precisely what lets Urdr be
   useful *before* full VM control exists: D0/D1-with-residuals on arbitrary
   systems now, D1-certified on the reference guest later.
10. *Then Firecracker*, scoped by ADR 0001's profile discipline, with the
    abstract model of each system kept alongside its real deployment and an
    explicit statement of the refinement relation (or its absence) between
    modeled and captured runs — the Lamport-lens requirement, and ultimately
    the honest answer to "what does a modeled PASS tell you about
    production?"

### 7.4 The configuration contract to aim at

The end-state worth steering toward, stated as the user-visible contract: a
new system costs exactly three artifacts —

```text
1. a component module   (its state machine, in Shen — or a UAP adapter
                         wrapping the real binary)
2. a scenario file      (roster, topology, routing, faults, budget, seed,
                         observation points — in the friendly notation)
3. a property set       (invariants / temporal / liveness / checkers)
```

— and everything else (exploration, shrinking, replay, divergence diagnosis,
certification, cross-runtime agreement) is inherited. Phase 1 makes that
contract true for modeled systems; Phase 2 makes it cheap; Phase 3 extends it
to real ones. The substrate below that line is already built, already
byte-identical on four runtimes, and already fail-closed — which is why this
is a completion problem, not a rescue.

---

## 8. Immediate punch list (independent of the roadmap)

Small, high-value, mostly one-file:

1. Fix `partition-retry.shen`'s property to the loadable
   `{name, source, value}` pattern shape — the flagship example should
   compile.
2. Wire `shen/tests/adversarial/run` into `make quality`/CI; resolve its
   hardcoded personal launcher paths against the pinned checkouts (the
   `1af5c27` pattern).
3. Delete the golden self-blessing branches in
   `shen/tests/{search,integration,search/grammar}/test.sh`.
4. Regenerate the stale pin/digest tables in `docs/status/m{0,1}.md` from
   gate evidence (or script them so they can't drift).
5. Replace repeated-subtraction `small.divmod` with descending-weights
   division; re-pin goldens (values are unchanged; only speed changes —
   verify byte-identity as with the SHA host dispatch).
6. Enforce alternative ordering on scheduled `choice` events
   (`world.shen:118-133`) to match the component door.
7. Fix the `small-of` limb-endianness bug in `search.shen:249-251` /
   `grammar.shen:607-609` and add a cross-test between the two decimal
   codecs.
8. Route atom-length rendering through the software-integer renderer instead
   of `(str N)` (`canonical.shen:696-697`).
9. Grammar: emit zero-padded or otherwise octet-order-stable ids so
   generated fragments stay valid at N≥11.
10. Commit facts (root, not count) into `snapshot-value`.

---

## 9. Closing assessment

Urdr's foundation — the portable semantic nucleus, the evidence spine, and
the engineering culture around them — is genuinely rare: most projects claim
determinism; this one has built the machinery to *earn* it and the discipline
to refuse it when unearned. The critical risk is inversion of effort: the
specification reaches M7 while the product has not yet executed its own M1
story end-to-end, and the generalization goal is blocked not by hard research
problems but by a small cluster of missing composition code (driver, routing,
per-component binding) plus authoring ergonomics. Close that cluster, prove
two diverse modeled systems, and the "small configuration, diverse systems"
ambition stops being aspiration and becomes the default workflow the
substrate was always shaped for.
