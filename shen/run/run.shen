\* The production scenario driver (ADR 0007 D1, D2 step loop, D5).

Requires shen/protocol/canonical.shen, shen/world/integer.shen,
shen/world/prng.shen, shen/world/netkat.shen,
shen/world/component.shen, shen/world/world.shen,
shen/scenario/scenario.shen, the models in shen/world/models/
(common, mask, net, timer, fault, registry),
shen/properties/properties.shen, shen/world/eventlog.shen,
shen/world/replay.shen, shen/world/certificate.shen, and
shen/search/search.shen to be loaded by the caller.

Pure: no I/O, no host time, no host randomness, no floating point, no
defprolog. The driver composes authorities that already exist — the
scenario validator, the registry builder, the world reducer, the
property engine, the search strategies, the certificate builder — and
adds no semantic authority of its own. It returns values; it never
prints.

  urdr.run.execute : SCENARIO-VALUE -> MODEL-TABLE
                   -> [ok RESULT] | [error CODE DETAIL]

SCENARIO-VALUE is the raw canonical scenario record (pre-validation);
MODEL-TABLE is the registry's [MODEL [HANDLER INIT-BUILDER]] table.
The scenario is the only source of run policy: seed and budget come
from its declarations and cannot be overridden by a caller (ADR 0007
D1). The strategy is the driver's own default (boundary — the
production bias toward fault and timing edges); urdr.run.execute-with
exposes the baseline strategy for tests without adding a policy knob
to the scenario surface.

RESULT ::= [discovered ATTEMPT SEED TRANSCRIPT VERDICTS CERTIFICATE]
         | [exhausted ATTEMPTS TRIED]
TRIED  ::= [tried ATTEMPTS DISTINCT [SIG ...] [ERROR-ENTRY ...]]
ERROR-ENTRY ::= [attempt-error ATTEMPT CODE]

ATTEMPT/ATTEMPTS/DISTINCT are software integers; SEED is the scenario
seed octets; TRANSCRIPT is the final world's reducer-input transcript;
VERDICTS are the canonical verdict records of
urdr.properties.verdict-values; CERTIFICATE is the value
urdr.certificate.build returned; SIG entries are failure-signature
octet lists in first-seen order; CODE is a stable-code octet list.

Driver phases, in order, all fail-closed BEFORE any world effect:

  1. urdr.scenario.validate — reject with the validator's code.
  2. urdr.properties.load-all — declarations are rejected before a
     run starts, not after one produced a trace.
  3. Roster pre-check: every `process` component must bind a model.
     The driver has no caller-supplied default process handler (the
     scenario is the whole program), so an unbound process is
     unrunnable and is refused with run-process-unbound rather than
     surfacing as a misleading unknown-kind error at registry build.
  4. World boot through the registry's world-from-scenario path with
     the routing cascade limit bound to the scenario budget's
     max-steps (D5); the network baseline is the unrestricted nk-id
     fabric — a policied baseline arrives with the NetworkPolicy
     integration wave, not through a driver back door.
  5. The attempt loop (below). Any error in phases 1-4 aborts the
     whole run; no attempt begins.

Boot rule: every roster component of kind `process` receives one boot
input — the canonical value [symbol boot] — scheduled at logical time
zero in canonical roster order, so models with initiative (clients,
timers-in-model form) can start emitting without a hand-plumbed
transcript. Only `process` components are booted: the built-in net,
timer, and fault models reject unknown inputs fail-closed by design
(net-unknown-input / timer-unknown-input / fault-input-shape), and in
the driver path every process component runs a model whose contract
includes tolerating boot. The crash-aware process wrapper passes boot
through to the inner model unchanged (boot carries no crash/restart
`kind` key).

The step loop (D2): repeatedly advance-to-next-event; after each
reduction, collect published component-choice records as open menus
(a reduction's choices list can also carry resolved `choice` records
— the echo of a selection this driver scheduled — which are decisions
already taken, not menus, and are not collected). When no pending
events remain and menus are open, hand every open menu to the
strategy in arrival order — reduction order, and within one reduction
the component's declared choice order — resolving each: the strategy
selects one alternative, the driver schedules the pinned SELECTED
choice form at the current logical time, then delivers the selected
alternative back to the publishing component as an ordinary component
input at the same time. Delivery-back is the production form of the
rule the timer model documents ("the kernel then schedules the
corresponding component input"): a decision that reached no component
would decide nothing, and the driver is the only authority with the
scheduling right to close that loop. Models driven by urdr.run must
therefore accept their own published alternatives as inputs; the
built-in net and timer models publish alternatives that need
model-specific wrapping (deliver-input / fire-input) and their
selection plumbing is deferred to the wave that integrates them under
the driver. Both scheduled entries land in the world transcript, so
replay re-derives the whole run from the transcript without
re-drawing (D2: the transcript, not the PRNG, is the authority).

Quiescence — no pending events and no open menus — ends the attempt:
the fact trace is lifted (urdr.properties.trace-of-world), the loaded
properties are evaluated, and the failure signature of the canonical
verdicts is compared against the empty-verdict signature (the
discovery gate urdr.search.explore pins). A distinct signature is a
discovery: the certificate is built from the initial world and the
final transcript and the run returns immediately.

Budgets (D5), all from the scenario's declared budget:

  max-runs    bounds attempts. Exhaustion is a RESULT, not an error:
              [ok [exhausted ...]] with the tried-summary.
  max-steps   bounds reducer inputs per attempt — every schedule and
              every advance is one step, so cost is proportional to
              reductions. Tripping aborts THE ATTEMPT with
              run-steps-exceeded; the attempt counts as explored and
              the loop continues.
  max-events  bounds event-id allocation per attempt: after every
              reduction the world's next-event-id may not exceed it.
              Tripping aborts the attempt with run-events-exceeded,
              same semantics as max-steps.

An attempt that errors mid-run (a reduction error such as
route-cascade-exceeded, a component rejection, an evaluation error)
is NOT silently swallowed: it is recorded as [attempt-error N CODE]
in the summary and the loop continues — one poisoned schedule must
not hide the others. If every attempt aborted and none completed an
evaluation, the run returns [error run-all-attempts-failed TRIED],
because a result claiming exhaustive exploration over zero completed
attempts would be information-free.

Per-attempt determinism: strategy draws happen in DRIVER space — the
named-stream subsystem "search" (the one subsystem ADR 0003 reserves
for strategies; no world stream can share it because driver runs
schedule only SELECTED choice forms, which never draw), actor = the
publishing component's name, purpose = the menu's purpose. Attempt
N's counters start at N * (max-steps + 1) and thread monotonically
through the attempt's selections. One selection consumes exactly one
counter (urdr.prng.sample advances the counter once per draw and
walks block-index for rejection retries), and an attempt cannot make
more than max-steps selections (each selection costs at least one
step), so distinct attempts' counter ranges cannot overlap: the
derivation is stride-safe and reproducible from (scenario seed, N)
alone, like urdr.search.explore-loop's Attempt * (1 + menu-count)
derivation.

Scope (this wave): urdr.run drives ONE exploration under the
scenario's own budget and returns canonical values. Shrink and replay
integration are the next wave; nothing here calls shrink. *\

\\ ---------------------------------------------------------------
\\ Names and stable codes
\\ ---------------------------------------------------------------

(define urdr.run.code
  Name -> (urdr.canonical.string-bytes Name))

\\ Codes cross this module from several owners in two spellings:
\\ octet lists (world, registry, search) and Shen symbols (scenario,
\\ properties). Summaries and error returns normalize to octets so a
\\ consumer compares one shape; the spelling is preserved exactly
\\ ((str SYM) renders the same characters), so the code is still the
\\ owner's code, passed through.
(define urdr.run.code-octets
  [] -> (urdr.run.code "run-unknown-code")
  [B | Bs] -> [B | Bs] where (number? B)
  Code -> (urdr.canonical.string-bytes (str Code)))

(define urdr.run.boot-input
  -> [symbol (urdr.run.code "boot")])

(define urdr.run.subsystem
  -> (urdr.search.n w-search))

(define urdr.run.engine
  -> (urdr.run.code "urdr-run-m1"))

\\ The unrestricted fabric: the same nk-id baseline the M1 fixtures
\\ boot, so a scenario without a compiled NetworkPolicy runs over an
\\ open network rather than failing to build.
(define urdr.run.baseline
  -> (urdr.netkat.term-encode [nk-id]))

\\ ---------------------------------------------------------------
\\ Budget accessors ([budget EVENTS RUNS STEPS], scenario.shen)
\\ ---------------------------------------------------------------

(define urdr.run.budget-events
  [budget Events _ _] -> Events)

(define urdr.run.budget-runs
  [budget _ Runs _] -> Runs)

(define urdr.run.budget-steps
  [budget _ _ Steps] -> Steps)

(define urdr.run.max-events
  Scenario -> (urdr.run.budget-events (urdr.scenario.budget-of Scenario)))

(define urdr.run.max-runs
  Scenario -> (urdr.run.budget-runs (urdr.scenario.budget-of Scenario)))

(define urdr.run.max-steps
  Scenario -> (urdr.run.budget-steps (urdr.scenario.budget-of Scenario)))

\\ ---------------------------------------------------------------
\\ Entry points
\\ ---------------------------------------------------------------

(define urdr.run.execute
  Value ModelTable -> (urdr.run.execute-with boundary Value ModelTable))

(define urdr.run.execute-with
  Strategy Value ModelTable ->
    (if (not (urdr.search.strategy? Strategy))
        [error (urdr.run.code "run-strategy") [null]]
        (urdr.run.validated
          (urdr.scenario.validate Value) Strategy ModelTable)))

(define urdr.run.validated
  [error E] _ _ -> [error (urdr.run.code-octets E) [null]]
  [ok Scenario] Strategy ModelTable ->
    (urdr.run.loaded
      (urdr.properties.load-all
        (urdr.scenario.properties-of Scenario)
        (urdr.scenario.observations-of Scenario))
      Scenario
      Strategy
      ModelTable))

(define urdr.run.loaded
  [error E] _ _ _ -> [error (urdr.run.code-octets E) [null]]
  [ok Loadeds] Scenario Strategy ModelTable ->
    (urdr.run.rostered
      (urdr.run.roster-check (urdr.scenario.components-of Scenario))
      Scenario
      Strategy
      ModelTable
      Loadeds))

\\ Phase 3 of the header: an unbound process is refused with its own
\\ code, before any registry or world exists.
(define urdr.run.roster-check
  [] -> [ok]
  [[component Id Kind Node none] | Rest] ->
    (if (urdr.model.common.same? Kind (urdr.scenario.n.process))
        [error (urdr.run.code "run-process-unbound") [symbol Id]]
        (urdr.run.roster-check Rest))
  [_ | Rest] -> (urdr.run.roster-check Rest)
  _ -> [error (urdr.run.code "run-roster-shape") [null]])

(define urdr.run.rostered
  [error Code Detail] _ _ _ _ -> [error Code Detail]
  [ok] Scenario Strategy ModelTable Loadeds ->
    (urdr.run.built
      (urdr.model.registry.world-from-scenario-limited
        (urdr.scenario.seed-of Scenario)
        Scenario
        (urdr.run.baseline)
        (urdr.model.registry.default-kinds)
        ModelTable
        (urdr.run.max-steps Scenario))
      Scenario
      Strategy
      Loadeds))

(define urdr.run.built
  [error E] _ _ _ -> [error (urdr.run.code-octets E) [null]]
  [error E Detail] _ _ _ -> [error (urdr.run.code-octets E) Detail]
  [ok World] Scenario Strategy Loadeds ->
    (urdr.run.attempts
      Scenario Strategy Loadeds World
      (urdr.int.zero)
      []
      []
      (urdr.int.zero)))

\\ ---------------------------------------------------------------
\\ The attempt loop. The initial world value is immutable and shared:
\\ every attempt starts from the same value, so attempts differ only
\\ through their PRNG counter base.
\\ ---------------------------------------------------------------

(define urdr.run.attempts
  Scenario Strategy Loadeds World Attempt Sigs Errors Completed ->
    (if (>= (urdr.int.raw.compare Attempt (urdr.run.max-runs Scenario)) 0)
        (urdr.run.exhausted Attempt Sigs Errors Completed)
        (urdr.run.attempt-result
          (urdr.run.attempt Scenario Strategy Loadeds World Attempt)
          Scenario Strategy Loadeds World Attempt Sigs Errors
          Completed)))

\\ The tried-summary is deliberately not information-free: it carries
\\ the attempt count, the distinct-signature count, the distinct
\\ signatures themselves (first-seen order), and every attempt-level
\\ abort — bounded by max-runs, which the scenario declared.
(define urdr.run.exhausted
  Attempts Sigs Errors Completed ->
    (urdr.run.exhausted-summary
      Attempts
      Completed
      [tried
        Attempts
        (urdr.world.list-count (urdr.canonical.rev Sigs))
        (urdr.canonical.rev Sigs)
        (urdr.canonical.rev Errors)]))

(define urdr.run.exhausted-summary
  Attempts Completed Summary ->
    (if (urdr.int.raw.zero? Completed)
        [error (urdr.run.code "run-all-attempts-failed") Summary]
        [ok [exhausted Attempts Summary]]))

(define urdr.run.attempt-result
  [found FinalWorld VerdictValues Sig]
  Scenario Strategy Loadeds World Attempt Sigs Errors Completed ->
    (urdr.run.discovered
      (urdr.run.certificate Scenario World FinalWorld VerdictValues)
      Scenario Attempt FinalWorld VerdictValues)
  [explored Sig]
  Scenario Strategy Loadeds World Attempt Sigs Errors Completed ->
    (urdr.run.attempts
      Scenario Strategy Loadeds World
      (urdr.int.raw.add Attempt (urdr.int.one))
      (urdr.run.sig-put Sig Sigs)
      Errors
      (urdr.int.raw.add Completed (urdr.int.one)))
  [aborted Code]
  Scenario Strategy Loadeds World Attempt Sigs Errors Completed ->
    (urdr.run.attempts
      Scenario Strategy Loadeds World
      (urdr.int.raw.add Attempt (urdr.int.one))
      Sigs
      [[attempt-error Attempt Code] | Errors]
      Completed))

(define urdr.run.sig-member?
  _ [] -> false
  Sig [S | Rest] ->
    (or (= Sig S) (urdr.run.sig-member? Sig Rest)))

(define urdr.run.sig-put
  Sig Sigs ->
    (if (urdr.run.sig-member? Sig Sigs)
        Sigs
        [Sig | Sigs]))

\\ ---------------------------------------------------------------
\\ Certificate (discovery only). The requested determinism profile is
\\ the scenario's declared one; the manifest is the empty artifact
\\ list an abstract run pins (certificate.shen section 1); the
\\ baseline-descriptor list is empty, so the certificate carries
\\ modeled-world-only and nothing it cannot prove.
\\
\\ The scenario travels into the certificate as a compact BINDING,
\\ not the full declaration: certificate digests use the default
\\ (m0) canonical profile, while a scenario/v1 declaration is an
\\ m1-large value (scenario.shen) that can exceed m0's node budget —
\\ the integration suite hit exactly this and hand-built a stand-in.
\\ The driver's binding is content-derived instead of hand-named:
\\ the SHA-256 of the scenario's canonical m1-large payload, wrapped
\\ in a two-field record that fits every profile. The certificate's
\\ scenario-digest field then commits to the full declaration
\\ transitively (a digest of a record carrying the digest), so two
\\ different scenarios can never share a certificate binding.
\\ ---------------------------------------------------------------

(define urdr.run.scenario-binding
  Scenario ->
    (urdr.run.scenario-binding-of
      (urdr.canonical.encode-payload-with-profile
        (urdr.scenario.profile)
        (urdr.scenario.value Scenario))))

(define urdr.run.scenario-binding-of
  [error E] -> [error E]
  [ok Octets] ->
    (urdr.run.scenario-binding-hash (urdr.sha256 Octets)))

(define urdr.run.scenario-binding-hash
  [error E] -> [error E]
  [ok Digest] ->
    [ok [record
          [[(urdr.run.code "scenario-digest") [bytes Digest]]
           [(urdr.run.code "version")
            [symbol (urdr.scenario.n.scenario.v1)]]]]])

(define urdr.run.certificate
  Scenario Initial FinalWorld VerdictValues ->
    (urdr.run.certificate-bound
      (urdr.run.scenario-binding Scenario)
      Scenario Initial FinalWorld VerdictValues))

(define urdr.run.certificate-bound
  [error E] _ _ _ _ -> [error (urdr.run.code-octets E) [null]]
  [ok Binding] Scenario Initial FinalWorld VerdictValues ->
    (urdr.certificate.build
      (urdr.certificate.spec
        (urdr.run.engine)
        Binding
        [list []]
        (urdr.scenario.determinism-of Scenario)
        Initial
        (urdr.world.transcript FinalWorld)
        VerdictValues
        [])))

(define urdr.run.discovered
  [error Code Detail] _ _ _ _ ->
    [error (urdr.run.code-octets Code) Detail]
  [ok Cert] Scenario Attempt FinalWorld VerdictValues ->
    [ok [discovered
          Attempt
          (urdr.scenario.seed-of Scenario)
          (urdr.world.transcript FinalWorld)
          VerdictValues
          Cert]])

\\ ---------------------------------------------------------------
\\ One attempt. State travels as [st WORLD STEPS COUNTER MENUS];
\\ attempt outcomes are [found FINAL VERDICTS SIG], [explored SIG],
\\ or [aborted CODE].
\\ ---------------------------------------------------------------

\\ Counter base derivation: see the header. Reproducible from
\\ (scenario seed, N) alone given the scenario's declared max-steps.
(define urdr.run.counter-base
  Scenario Attempt ->
    (urdr.int.raw.multiply
      Attempt
      (urdr.int.raw.add (urdr.run.max-steps Scenario) (urdr.int.one))))

(define urdr.run.attempt
  Scenario Strategy Loadeds World Attempt ->
    (urdr.run.boot
      (urdr.scenario.components-of Scenario)
      Scenario
      Strategy
      Loadeds
      [st World
          (urdr.int.zero)
          (urdr.run.counter-base Scenario Attempt)
          []]))

\\ Boot inputs in canonical roster order (the scenario roster ascends
\\ strictly by component id), process components only — see the boot
\\ rule in the header.
(define urdr.run.boot
  [] Scenario Strategy Loadeds St ->
    (urdr.run.loop Scenario Strategy Loadeds St)
  [[component Id Kind Node Model] | Rest] Scenario Strategy Loadeds St ->
    (if (urdr.model.common.same? Kind (urdr.scenario.n.process))
        (urdr.run.boot-step
          (urdr.run.apply
            [schedule (urdr.int.zero) component
              [component-input Id (urdr.run.boot-input)]]
            Scenario
            St)
          Rest Scenario Strategy Loadeds)
        (urdr.run.boot Rest Scenario Strategy Loadeds St))
  _ _ _ _ _ -> [aborted (urdr.run.code "run-roster-shape")])

(define urdr.run.boot-step
  [aborted Code] _ _ _ _ -> [aborted Code]
  St Rest Scenario Strategy Loadeds ->
    (urdr.run.boot Rest Scenario Strategy Loadeds St))

\\ Apply ONE reducer input, charging one step. Every schedule and
\\ every advance goes through here, so max-steps bounds reductions
\\ exactly and the selection count stays under the PRNG stride.
(define urdr.run.apply
  Input Scenario [st World Steps Counter Menus] ->
    (let Steps1 (urdr.int.raw.add Steps (urdr.int.one))
      (if (> (urdr.int.raw.compare
               Steps1 (urdr.run.max-steps Scenario)) 0)
          [aborted (urdr.run.code "run-steps-exceeded")]
          (urdr.run.applied
            (urdr.world.reduce World Input)
            Scenario Steps1 Counter Menus))))

(define urdr.run.applied
  Reduction Scenario Steps Counter Menus ->
    (if (urdr.world.reduction-error? Reduction)
        [aborted (urdr.run.reduction-code
                   (urdr.world.reduction-choices Reduction))]
        (urdr.run.events-checked
          (urdr.world.reduction-world Reduction)
          Scenario
          Steps
          Counter
          (urdr.run.menus-add
            Menus (urdr.world.reduction-choices Reduction)))))

(define urdr.run.events-checked
  World Scenario Steps Counter Menus ->
    (if (> (urdr.int.raw.compare
             (urdr.world.next-event-id World)
             (urdr.run.max-events Scenario))
           0)
        [aborted (urdr.run.code "run-events-exceeded")]
        [st World Steps Counter Menus]))

(define urdr.run.reduction-code
  [error Value] ->
    (urdr.run.symbol-code
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get Value (urdr.run.code "code"))))
  _ -> (urdr.run.code "run-reduction-error"))

(define urdr.run.symbol-code
  none -> (urdr.run.code "run-reduction-error")
  Bs -> Bs)

\\ Open menus are the component-choice records only; a resolved
\\ `choice` record in the same list is a decision already taken.
(define urdr.run.menus-add
  Menus [] -> Menus
  Menus [Choice | Rest] ->
    (urdr.run.menus-add
      (if (urdr.run.component-choice? Choice)
          (append Menus [Choice])
          Menus)
      Rest)
  Menus _ -> Menus)

(define urdr.run.component-choice?
  Value ->
    (= (urdr.model.common.get Value (urdr.run.code "type"))
       [symbol (urdr.run.code "component-choice")]))

\\ The step loop (D2). Tail recursive: every branch re-enters loop or
\\ returns an attempt outcome.
(define urdr.run.loop
  Scenario Strategy Loadeds [aborted Code] -> [aborted Code]
  Scenario Strategy Loadeds [st World Steps Counter Menus] ->
    (if (cons? (urdr.world.pending World))
        (urdr.run.loop
          Scenario Strategy Loadeds
          (urdr.run.apply
            [advance-to-next-event]
            Scenario
            [st World Steps Counter Menus]))
        (if (cons? Menus)
            (urdr.run.loop
              Scenario Strategy Loadeds
              (urdr.run.resolve-all
                Menus Scenario Strategy
                [st World Steps Counter []]))
            (urdr.run.evaluate Loadeds World))))

\\ ---------------------------------------------------------------
\\ Menu resolution: arrival order, one selection per menu.
\\ ---------------------------------------------------------------

(define urdr.run.resolve-all
  [] _ _ St -> St
  [Menu | Rest] Scenario Strategy St ->
    (urdr.run.resolve-step
      (urdr.run.resolve Menu Scenario Strategy St)
      Rest Scenario Strategy)
  _ _ _ _ -> [aborted (urdr.run.code "run-menu-shape")])

(define urdr.run.resolve-step
  [aborted Code] _ _ _ -> [aborted Code]
  St Rest Scenario Strategy ->
    (urdr.run.resolve-all Rest Scenario Strategy St))

(define urdr.run.bytes-of
  [bytes Bs] -> Bs
  _ -> none)

(define urdr.run.menu-owner
  Value ->
    (urdr.run.bytes-of
      (urdr.model.common.get Value (urdr.run.code "component"))))

(define urdr.run.menu-purpose
  Value ->
    (urdr.model.common.symbol-bytes
      (urdr.model.common.get Value (urdr.run.code "purpose"))))

(define urdr.run.menu-alternatives
  Value ->
    (urdr.model.common.items
      (urdr.model.common.get Value (urdr.run.code "alternatives"))))

(define urdr.run.menu-id
  Value -> (urdr.model.common.get Value (urdr.run.code "event-id")))

(define urdr.run.resolve
  MenuValue Scenario Strategy St ->
    (urdr.run.resolve-parts
      (urdr.run.menu-owner MenuValue)
      (urdr.run.menu-purpose MenuValue)
      (urdr.run.menu-alternatives MenuValue)
      (urdr.run.menu-id MenuValue)
      Scenario
      Strategy
      St))

\\ The menu the strategy sees is built at resolution time: id from
\\ the publishing event, time = the world's CURRENT logical time (the
\\ selection is scheduled now, not when the menu was published — the
\\ two coincide unless later same-queue events advanced the clock,
\\ and a selection may never be scheduled into the past), kind
\\ derived from the purpose symbol when it names a strategy bias
\\ class (urdr.search.tag-kind; anything else is `other`), and the
\\ driver-space stream path of the header.
(define urdr.run.resolve-parts
  none _ _ _ _ _ _ -> [aborted (urdr.run.code "run-menu-shape")]
  _ none _ _ _ _ _ -> [aborted (urdr.run.code "run-menu-shape")]
  _ _ none _ _ _ _ -> [aborted (urdr.run.code "run-menu-shape")]
  Owner Purpose Alts Id Scenario Strategy [st World Steps Counter Menus] ->
    (urdr.run.resolve-menu
      (urdr.search.menu
        Id
        (urdr.world.time World)
        (urdr.search.tag-kind Purpose)
        (urdr.run.subsystem)
        Owner
        Purpose
        Alts)
      Owner Purpose Scenario Strategy
      [st World Steps Counter Menus]))

(define urdr.run.resolve-menu
  [error Code Detail] _ _ _ _ _ -> [aborted (urdr.run.code-octets Code)]
  [ok Menu] Owner Purpose Scenario Strategy St ->
    (urdr.run.resolve-selected
      (urdr.search.select
        Strategy (urdr.scenario.seed-of Scenario) (urdr.run.st-counter St)
        Menu)
      Owner Purpose Scenario St))

(define urdr.run.st-counter
  [st _ _ Counter _] -> Counter)

\\ Selection: schedule the pinned SELECTED choice form (the recorded
\\ decision — menu, selected alternative, draw coordinates), then the
\\ delivery of the selected alternative to the publishing component,
\\ both at the current logical time. The choice event carries the
\\ same (subsystem, actor, purpose) path the draw used, so the
\\ recorded coordinates are literally the coordinates of the stream
\\ the event names.
(define urdr.run.resolve-selected
  [error Code Detail] _ _ _ _ -> [aborted (urdr.run.code-octets Code)]
  [ok [Record NextCounter]] Owner Purpose Scenario
  [st World Steps Counter Menus] ->
    (urdr.run.resolve-scheduled
      (urdr.run.apply
        (urdr.search.schedule-input
          Record (urdr.run.subsystem) Owner Purpose)
        Scenario
        [st World Steps NextCounter Menus])
      (urdr.search.choice-selected Record)
      Owner
      Scenario))

(define urdr.run.resolve-scheduled
  [aborted Code] _ _ _ -> [aborted Code]
  [st World Steps Counter Menus] Selected Owner Scenario ->
    (urdr.run.apply
      [schedule (urdr.world.time World) component
        [component-input Owner Selected]]
      Scenario
      [st World Steps Counter Menus]))

\\ ---------------------------------------------------------------
\\ Quiescence: trace, verdicts, discovery gate.
\\ ---------------------------------------------------------------

(define urdr.run.evaluate
  Loadeds World ->
    (urdr.run.trace-checked
      (urdr.properties.trace-of-world World) Loadeds World))

(define urdr.run.trace-checked
  [error E] _ _ -> [aborted (urdr.run.code-octets E)]
  [ok Trace] Loadeds World ->
    (urdr.run.verdicts-checked
      (urdr.properties.evaluate-all Loadeds Trace) World))

(define urdr.run.verdicts-checked
  [error E] _ -> [aborted (urdr.run.code-octets E)]
  [ok Pverdicts] World ->
    (urdr.run.signed
      (urdr.properties.verdict-values Pverdicts) World))

\\ The discovery gate is the one urdr.search.explore pins: a failure
\\ signature distinct from the empty-verdict signature is a discovery.
(define urdr.run.signed
  VerdictValues World ->
    (urdr.run.signed-h
      (urdr.certificate.failure-signature VerdictValues)
      VerdictValues
      World))

(define urdr.run.signed-h
  [error Code Detail] _ _ -> [aborted (urdr.run.code-octets Code)]
  [ok Sig] VerdictValues World ->
    (if (= Sig (urdr.search.empty-failure-sig))
        [explored Sig]
        [found World VerdictValues Sig]))
