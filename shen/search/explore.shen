\* The seeded exploration driver (SPEC.md 17, M1 plan Wave F).

Requires shen/protocol/canonical.shen, shen/world/integer.shen,
shen/world/prng.shen, shen/world/component.shen, shen/world/world.shen,
shen/world/eventlog.shen, shen/search/choice.shen, and
shen/search/strategy.shen to be loaded by the caller.

Pure: no I/O, no host time, no host randomness, no floating point, no
defprolog. An exploration is a total function of (initial world, spec).
The same spec over the same world produces the same transcript, the same
choice records, and the same roots, on every run and on every port.

NOT owned here (docs/module-boundaries.md): ambient randomness, the
meaning of any alternative, and property evaluation. Everything this
driver decides, it decides by asking a strategy, and every strategy draw
comes from a named ADR 0003 stream keyed by the spec's seed. Whether a
run has failed a property is asked of a caller-supplied detector, so that
shen/search/ carries no code dependency on shen/properties/ -- the same
discipline certificate.shen applies to the same module (section 5).

=====================================================================
1. What the driver produces
=====================================================================

  [exploration WORLD TRANSCRIPT LABELS CHOICES STOP STEPS]

TRANSCRIPT is a list of reducer inputs, exactly the shape
urdr.replay.run consumes, so an exploration's output is replayable
without translation. LABELS is a parallel list, one label per transcript
entry, recording WHY the driver wrote that entry; it is what makes the
SPEC.md 17.1 reduction order expressible over a flat transcript
(shrink.shen). CHOICES is the decision sequence: one
urdr.search.choice record per decision, in the order they were made.

A run that cannot proceed is an error, never a short exploration with a
quiet stop reason. The three stop reasons are all normal endings:

  budget-exhausted  the step budget ran out
  quiescent         no pending event remained
  property-failed   the detector reported a failure

=====================================================================
2. The loop
=====================================================================

Each step:

  1. Ask the detector whether the current world has already failed a
     property. If so, stop.
  2. If the step budget is spent, stop. If nothing is pending, stop.
  3. Reduce [advance-to-next-event]. This dispatches the earliest
     pending event and is the only way logical time advances.
  4. Collect the reduction's OFFERED choices: the records the component
     interface publishes with type `component-choice`. A record with any
     other type -- notably the kernel's own `choice` selection record --
     is not an offer and is skipped.
  5. For each offer, in the order the reduction published it (which is
     ascending by purpose, because urdr.component.check-choices requires
     it), ask the strategy to select, record the choice, and schedule the
     selection.

The detector runs at the top of every iteration, so it also runs once
after the final step, and a failure introduced by the last thing the
driver did is seen.

=====================================================================
3. Scheduling a selection, and the delay ladder
=====================================================================

A selected alternative becomes a component input through the spec's
ENCODER, a caller-supplied pure function

  ENCODER ACTOR KIND SELECTED -> [ok VALUE] | [none] | [error C D]

VALUE is the value of a [component-input ACTOR VALUE] event. `[none]`
means the selection is not actionable and nothing is scheduled -- the
choice is still recorded, because a decision that was made is part of the
decision transcript whether or not it moved the world.

The encoder is caller-supplied on purpose. The mapping from an
alternative to an input is model knowledge: the fault model's alternative
IS its input, the network model's alternative is carried under the
`selection` key of a `deliver` input, and the timer's alternative names a
deadline that a `fire` input refers to by id. Wiring those three shapes
into shen/search/ would put a copy of every model's input schema in the
search engine, and the copy would rot.

WHEN to schedule is the driver's own decision, and it is an explicit
choice rather than a constant. The spec carries a delay LADDER: a
non-empty, strictly ascending list of non-negative delays. Before each
scheduled input the driver makes a second choice, of kind
`schedule-delay`, whose alternatives are the ladder, and schedules at
(current logical time + the chosen delay). With the default one-rung
ladder [0] the choice is forced and every input is scheduled at the
current instant; with a longer ladder the driver is choosing artificial
delays, which is what SPEC.md 17.1 item 3 asks a shrinker to minimise.

=====================================================================
4. Named streams (ADR 0003)
=====================================================================

Every draw is made on

  (SEED, subsystem `search`, actor-id the STRATEGY NAME, purpose the
   CHOICE KIND, counter)

with one counter per (actor, purpose) pair, held in the driver's own
stream table and advanced only by the draws made through it. Two choice
kinds therefore never perturb one another, which is the ADR 0003
guarantee that makes a fixture stable while a neighbouring model grows a
new alternative.

The actor is the strategy name, not the component name, because the
stream belongs to the SEARCH: swapping strategies must reseed the search,
and it does.

SEED is the spec's, not the world's. An exploration is an experiment run
against a world, and two experiments with different search seeds over one
world are the normal case; taking the seed from the world would make them
inexpressible.

=====================================================================
5. Detecting failure without depending on shen/properties/
=====================================================================

  DETECTOR WORLD -> [ok true] | [ok false] | [error CODE DETAIL]

The M1 wiring, which shen/tests/search/ pins and Wave I is expected to
reuse verbatim, is

  (/. World
    (urdr.properties.check PROPERTIES OBSERVATIONS
      (urdr.properties.trace-of-world World)))

folded to a boolean by "any verdict whose result is FAIL". Keeping that
outside this module means the world kernel and the search engine both
stay independent of the property layer, and a scenario that evaluates
its properties differently does not need a different driver.

=====================================================================
6. Labels
=====================================================================

One per transcript entry, from a closed set:

  action      an entry from the spec's ACTIONS: a scenario action
  advance     an [advance-to-next-event]
  fault       a scheduled input from a `fault-action` choice
  network     a scheduled input from a `delivery` choice
  scheduling  a scheduled input from any other choice

The mapping is by CHOICE KIND, not by component name, so a second network
model or a differently named fault domain lands in the right §17.1
category without a table of component names.

=====================================================================
7. Public entry points
=====================================================================

  spec        SEED STRATEGY MAXSTEPS LADDER ACTIONS ENCODER DETECTOR
                -> SPEC
  run         INITIAL SPEC -> [ok EXPLORATION] | [error CODE DETAIL]
  world / transcript / labels / choices / stop / steps
              EXPLORATION -> the field
  value       EXPLORATION STRATEGY TRANSCRIPT-ROOT
                -> [ok canonical record] | [error CODE DETAIL]
  label-action / label-advance / label-fault / label-network /
  label-scheduling -> LABEL octets
  stop-budget / stop-quiescent / stop-failed -> STOP octets
  error-value CODE DETAIL -> canonical record
  code-octets CODE -> OCTETS *\

\\ ---------------------------------------------------------------
\\ ASCII names (k- keys, w- words, l- labels, s- stop reasons,
\\ c- error codes).
\\ ---------------------------------------------------------------

(define urdr.search.explore.n
  k-alternatives -> (urdr.canonical.string-bytes "alternatives")
  k-choice-root -> (urdr.canonical.string-bytes "choice-root")
  k-choices -> (urdr.canonical.string-bytes "choices")
  k-code -> (urdr.canonical.string-bytes "code")
  k-component -> (urdr.canonical.string-bytes "component")
  k-detail -> (urdr.canonical.string-bytes "detail")
  k-entries -> (urdr.canonical.string-bytes "entries")
  k-purpose -> (urdr.canonical.string-bytes "purpose")
  k-steps -> (urdr.canonical.string-bytes "steps")
  k-stop -> (urdr.canonical.string-bytes "stop")
  k-strategy -> (urdr.canonical.string-bytes "strategy")
  k-time -> (urdr.canonical.string-bytes "time")
  k-transcript-root ->
    (urdr.canonical.string-bytes "transcript-root")
  k-type -> (urdr.canonical.string-bytes "type")
  w-component-choice ->
    (urdr.canonical.string-bytes "component-choice")
  w-search -> (urdr.canonical.string-bytes "search")
  w-schedule-delay -> (urdr.canonical.string-bytes "schedule-delay")
  w-delivery -> (urdr.canonical.string-bytes "delivery")
  w-fault-action -> (urdr.canonical.string-bytes "fault-action")
  l-action -> (urdr.canonical.string-bytes "action")
  l-advance -> (urdr.canonical.string-bytes "advance")
  l-fault -> (urdr.canonical.string-bytes "fault")
  l-network -> (urdr.canonical.string-bytes "network")
  l-scheduling -> (urdr.canonical.string-bytes "scheduling")
  s-budget -> (urdr.canonical.string-bytes "budget-exhausted")
  s-quiescent -> (urdr.canonical.string-bytes "quiescent")
  s-failed -> (urdr.canonical.string-bytes "property-failed")
  c-spec -> (urdr.canonical.string-bytes "search-explore-spec")
  c-world -> (urdr.canonical.string-bytes "search-explore-world")
  c-budget -> (urdr.canonical.string-bytes "search-explore-budget")
  c-ladder -> (urdr.canonical.string-bytes "search-explore-ladder")
  c-actions -> (urdr.canonical.string-bytes "search-explore-actions")
  c-reduction ->
    (urdr.canonical.string-bytes "search-explore-reduction")
  c-encoder -> (urdr.canonical.string-bytes "search-explore-encoder")
  c-detector -> (urdr.canonical.string-bytes "search-explore-detector")
  c-offer -> (urdr.canonical.string-bytes "search-explore-offer")
  c-stream -> (urdr.canonical.string-bytes "search-explore-stream")
  c-unmapped -> (urdr.canonical.string-bytes "search-unmapped-code"))

(define urdr.search.explore.code-octets
  search-explore-spec -> (urdr.search.explore.n c-spec)
  search-explore-world -> (urdr.search.explore.n c-world)
  search-explore-budget -> (urdr.search.explore.n c-budget)
  search-explore-ladder -> (urdr.search.explore.n c-ladder)
  search-explore-actions -> (urdr.search.explore.n c-actions)
  search-explore-reduction -> (urdr.search.explore.n c-reduction)
  search-explore-encoder -> (urdr.search.explore.n c-encoder)
  search-explore-detector -> (urdr.search.explore.n c-detector)
  search-explore-offer -> (urdr.search.explore.n c-offer)
  search-explore-stream -> (urdr.search.explore.n c-stream)
  _ -> (urdr.search.explore.n c-unmapped))

(define urdr.search.explore.error-value
  Code Detail ->
    [record
      [[(urdr.search.explore.n k-code)
        [symbol (urdr.search.explore.code-octets Code)]]
       [(urdr.search.explore.n k-detail) Detail]]])

\\ ---------------------------------------------------------------
\\ Labels and stop reasons
\\ ---------------------------------------------------------------

(define urdr.search.explore.label-action
  -> (urdr.search.explore.n l-action))

(define urdr.search.explore.label-advance
  -> (urdr.search.explore.n l-advance))

(define urdr.search.explore.label-fault
  -> (urdr.search.explore.n l-fault))

(define urdr.search.explore.label-network
  -> (urdr.search.explore.n l-network))

(define urdr.search.explore.label-scheduling
  -> (urdr.search.explore.n l-scheduling))

(define urdr.search.explore.stop-budget
  -> (urdr.search.explore.n s-budget))

(define urdr.search.explore.stop-quiescent
  -> (urdr.search.explore.n s-quiescent))

(define urdr.search.explore.stop-failed
  -> (urdr.search.explore.n s-failed))

\\ A choice kind becomes a SPEC.md 17.1 category (section 6).
(define urdr.search.explore.label-of
  Kind ->
    (if (= Kind (urdr.search.explore.n w-fault-action))
        (urdr.search.explore.n l-fault)
        (if (= Kind (urdr.search.explore.n w-delivery))
            (urdr.search.explore.n l-network)
            (urdr.search.explore.n l-scheduling))))

\\ ---------------------------------------------------------------
\\ The spec
\\ ---------------------------------------------------------------

(define urdr.search.explore.spec
  Seed Strategy MaxSteps Ladder Actions Encoder Detector ->
    [explore-spec Seed Strategy MaxSteps Ladder Actions Encoder
      Detector])

(define urdr.search.explore.check-spec
  Seed Strategy MaxSteps Ladder Actions ->
    (if (= (hd (urdr.prng.octets.check Seed)) error)
        [error search-explore-spec [null]]
        (urdr.search.explore.check-budget
          (urdr.search.strategy.check Strategy)
          MaxSteps Ladder Actions)))

(define urdr.search.explore.check-budget
  [error Code Detail] _ _ _ -> [error Code Detail]
  [ok] MaxSteps Ladder Actions ->
    (if (not (urdr.int.valid? MaxSteps))
        [error search-explore-budget [null]]
        (if (urdr.int.raw.negative? MaxSteps)
            [error search-explore-budget [null]]
            (urdr.search.explore.check-ladder Ladder Actions))))

\\ The ladder is a choice's alternative list, so it must satisfy exactly
\\ what a choice record demands of one, and every rung must additionally
\\ be a non-negative software integer: a negative delay would schedule
\\ into the past, which the reducer refuses as a stale event.
(define urdr.search.explore.check-ladder
  Ladder Actions ->
    (urdr.search.explore.check-ladder-shape
      (urdr.search.choice.check-alternatives Ladder) Ladder Actions))

(define urdr.search.explore.check-ladder-shape
  [error _ _] _ _ -> [error search-explore-ladder [null]]
  [ok] Ladder Actions ->
    (if (urdr.search.explore.delays? Ladder)
        (urdr.search.explore.check-actions Actions)
        [error search-explore-ladder [null]]))

(define urdr.search.explore.delays?
  [] -> true
  [Delay | Rest] ->
    (if (urdr.int.valid? Delay)
        (if (urdr.int.raw.negative? Delay)
            false
            (urdr.search.explore.delays? Rest))
        false)
  _ -> false)

(define urdr.search.explore.check-actions
  [] -> [ok]
  [[schedule _ _ _] | Rest] -> (urdr.search.explore.check-actions Rest)
  [[advance-to-next-event] | Rest] ->
    (urdr.search.explore.check-actions Rest)
  _ -> [error search-explore-actions [null]])

\\ ---------------------------------------------------------------
\\ Stream table (section 4)
\\ ---------------------------------------------------------------

(define urdr.search.explore.subsystem
  -> (urdr.search.explore.n w-search))

(define urdr.search.explore.stream-of
  Seed Actor Purpose Streams ->
    (urdr.prng.stream
      Seed (urdr.search.explore.subsystem) Actor Purpose
      (urdr.world.path-counter
        [path (urdr.search.explore.subsystem) Actor Purpose
          (urdr.int.zero)]
        Streams)))

(define urdr.search.explore.stream-counter
  [stream urdr-sha256-counter-v1 _ _ _ _ Counter] -> [some Counter]
  _ -> none)

(define urdr.search.explore.streams-put
  Actor Purpose Stream Streams ->
    (urdr.search.explore.streams-put-of
      (urdr.search.explore.stream-counter Stream)
      Actor Purpose Streams))

(define urdr.search.explore.streams-put-of
  none _ _ Streams -> Streams
  [some Counter] Actor Purpose Streams ->
    (urdr.world.stream-put
      [path (urdr.search.explore.subsystem) Actor Purpose Counter]
      Streams))

\\ ---------------------------------------------------------------
\\ Reading an offer
\\ ---------------------------------------------------------------

(define urdr.search.explore.offer-of
  Value ->
    (urdr.search.explore.offer-parts
      (urdr.search.strategy.field
        Value (urdr.search.explore.n k-type))
      (urdr.search.strategy.field
        Value (urdr.search.explore.n k-component))
      (urdr.search.strategy.field
        Value (urdr.search.explore.n k-purpose))
      (urdr.search.strategy.field
        Value (urdr.search.explore.n k-alternatives))))

(define urdr.search.explore.offer-parts
  [some [symbol Type]] [some [bytes Actor]] [some [symbol Purpose]]
  [some [list Alternatives]] ->
    (if (= Type (urdr.search.explore.n w-component-choice))
        [some [offer Actor Purpose Alternatives]]
        none)
  _ _ _ _ -> none)

(define urdr.search.explore.offers
  [] Acc -> (urdr.canonical.rev Acc)
  [Value | Rest] Acc ->
    (urdr.search.explore.offers-step
      (urdr.search.explore.offer-of Value) Rest Acc)
  _ Acc -> (urdr.canonical.rev Acc))

(define urdr.search.explore.offers-step
  none Rest Acc -> (urdr.search.explore.offers Rest Acc)
  [some Offer] Rest Acc ->
    (urdr.search.explore.offers Rest [Offer | Acc]))

\\ ---------------------------------------------------------------
\\ Driver state
\\ ---------------------------------------------------------------
\\
\\ [estate WORLD RTRANSCRIPT RLABELS RCHOICES STREAMS SEQ]
\\ with the three lists held reversed and reversed once at the end.

(define urdr.search.explore.state-world
  [estate World _ _ _ _ _] -> World)

(define urdr.search.explore.state-seq
  [estate _ _ _ _ _ Seq] -> Seq)

(define urdr.search.explore.finish
  [estate World RT RL RC _ _] Stop Steps ->
    [ok [exploration World
          (urdr.canonical.rev RT)
          (urdr.canonical.rev RL)
          (urdr.canonical.rev RC)
          Stop
          Steps]])

\\ Fold one reducer input into the state under a label. A reducer error
\\ during exploration is a run error: the driver only ever schedules
\\ inputs it constructed itself, so a refusal means the driver built
\\ something the world does not accept, and continuing would be inventing
\\ a run.
(define urdr.search.explore.apply
  [estate World RT RL RC Streams Seq] Input Label ->
    (urdr.search.explore.apply-result
      (urdr.world.reduce World Input)
      Input Label RT RL RC Streams Seq))

(define urdr.search.explore.apply-result
  [reduction _ _ [error Detail]] _ _ _ _ _ _ _ ->
    [error search-explore-reduction Detail]
  Reduction Input Label RT RL RC Streams Seq ->
    [ok [step-result
          [estate (urdr.world.reduction-world Reduction)
            [Input | RT] [Label | RL] RC Streams Seq]
          (urdr.world.reduction-choices Reduction)]])

\\ ---------------------------------------------------------------
\\ One decision
\\ ---------------------------------------------------------------

\\ Ask the strategy, build the choice record, and hand back the updated
\\ state together with the selected alternative.
(define urdr.search.explore.decide
  Seed Strategy [estate World RT RL RC Streams Seq] Actor Kind Time
  Alternatives ->
    (urdr.search.explore.decide-stream
      (urdr.search.explore.stream-of
        Seed (urdr.search.strategy.name Strategy) Kind Streams)
      Seed Strategy [estate World RT RL RC Streams Seq] Actor Kind Time
      Alternatives))

(define urdr.search.explore.decide-stream
  [error _] _ _ _ _ _ _ _ -> [error search-explore-stream [null]]
  [ok Stream] Seed Strategy State Actor Kind Time Alternatives ->
    (urdr.search.explore.decide-selection
      (urdr.search.strategy.select
        Strategy
        (urdr.search.strategy.context Actor Kind Time Alternatives)
        Stream)
      Strategy State Actor Kind Time Alternatives))

(define urdr.search.explore.decide-selection
  [error Code Detail] _ _ _ _ _ _ -> [error Code Detail]
  [ok [selection Selected Reason Next Coordinates]]
  Strategy [estate World RT RL RC Streams Seq] Actor Kind Time
  Alternatives ->
    (urdr.search.explore.decide-choice
      (urdr.search.choice.make
        Seq Time Actor Kind Alternatives Selected Reason Coordinates)
      Strategy
      [estate World RT RL RC
        (urdr.search.explore.streams-put
          (urdr.search.strategy.name Strategy) Kind Next Streams)
        Seq]
      Selected))

(define urdr.search.explore.decide-choice
  [error Code Detail] _ _ _ -> [error Code Detail]
  [ok Choice] Strategy [estate World RT RL RC Streams Seq] Selected ->
    [ok [decision
          [estate World RT RL [Choice | RC] Streams
            (+ Seq 1)]
          Selected]])

\\ ---------------------------------------------------------------
\\ Handling one offer
\\ ---------------------------------------------------------------

(define urdr.search.explore.offer
  Spec State [offer Actor Purpose Alternatives] ->
    (urdr.search.explore.offer-decided
      (urdr.search.explore.decide
        (urdr.search.explore.spec-seed Spec)
        (urdr.search.explore.spec-strategy Spec)
        State Actor Purpose
        (urdr.world.time (urdr.search.explore.state-world State))
        Alternatives)
      Spec Actor Purpose))

(define urdr.search.explore.spec-seed
  [explore-spec Seed _ _ _ _ _ _] -> Seed)

(define urdr.search.explore.spec-strategy
  [explore-spec _ Strategy _ _ _ _ _] -> Strategy)

(define urdr.search.explore.spec-ladder
  [explore-spec _ _ _ Ladder _ _ _] -> Ladder)

(define urdr.search.explore.offer-decided
  [error Code Detail] _ _ _ -> [error Code Detail]
  [ok [decision State Selected]] Spec Actor Purpose ->
    (urdr.search.explore.offer-encoded
      (urdr.search.explore.encode Spec Actor Purpose Selected)
      Spec State Actor Purpose))

\\ The encoder is applied as a lambda, never bound to a function symbol.
(define urdr.search.explore.encode
  [explore-spec _ _ _ _ _ Encoder _] Actor Purpose Selected ->
    (Encoder Actor Purpose Selected))

(define urdr.search.explore.offer-encoded
  [error Code Detail] _ _ _ _ -> [error Code Detail]
  [none] _ State _ _ -> [ok State]
  [ok Value] Spec State Actor Purpose ->
    (urdr.search.explore.offer-delay
      (urdr.search.explore.decide
        (urdr.search.explore.spec-seed Spec)
        (urdr.search.explore.spec-strategy Spec)
        State Actor (urdr.search.explore.n w-schedule-delay)
        (urdr.world.time (urdr.search.explore.state-world State))
        (urdr.search.explore.spec-ladder Spec))
      State Actor Purpose Value)
  _ _ _ _ _ -> [error search-explore-encoder [null]])

(define urdr.search.explore.offer-delay
  [error Code Detail] _ _ _ _ -> [error Code Detail]
  [ok [decision State Delay]] _ Actor Purpose Value ->
    (urdr.search.explore.offer-schedule State Actor Purpose Value Delay))

(define urdr.search.explore.offer-schedule
  State Actor Purpose Value Delay ->
    (urdr.search.explore.offer-applied
      (urdr.search.explore.apply
        State
        [schedule
          (urdr.int.raw.add
            (urdr.world.time (urdr.search.explore.state-world State))
            Delay)
          component
          [component-input Actor Value]]
        (urdr.search.explore.label-of Purpose))))

(define urdr.search.explore.offer-applied
  [error Code Detail] -> [error Code Detail]
  [ok [step-result State _]] -> [ok State])

(define urdr.search.explore.offer-loop
  _ State [] -> [ok State]
  Spec State [Offer | Rest] ->
    (urdr.search.explore.offer-loop-step
      (urdr.search.explore.offer Spec State Offer) Spec Rest)
  _ State _ -> [ok State])

(define urdr.search.explore.offer-loop-step
  [error Code Detail] _ _ -> [error Code Detail]
  [ok State] Spec Rest ->
    (urdr.search.explore.offer-loop Spec State Rest))

\\ ---------------------------------------------------------------
\\ The loop (section 2)
\\ ---------------------------------------------------------------

(define urdr.search.explore.detect
  [explore-spec _ _ _ _ _ _ Detector] World -> (Detector World))

(define urdr.search.explore.loop
  Spec State Steps Taken ->
    (urdr.search.explore.loop-detected
      (urdr.search.explore.detect
        Spec (urdr.search.explore.state-world State))
      Spec State Steps Taken))

(define urdr.search.explore.loop-detected
  [ok true] _ State _ Taken ->
    (urdr.search.explore.finish
      State (urdr.search.explore.stop-failed) Taken)
  [ok false] Spec State Steps Taken ->
    (urdr.search.explore.loop-budget Spec State Steps Taken)
  [error Code Detail] _ _ _ _ -> [error Code Detail]
  _ _ _ _ _ -> [error search-explore-detector [null]])

(define urdr.search.explore.loop-budget
  Spec State Steps Taken ->
    (if (urdr.int.raw.zero? Steps)
        (urdr.search.explore.finish
          State (urdr.search.explore.stop-budget) Taken)
        (if (urdr.search.explore.quiescent? State)
            (urdr.search.explore.finish
              State (urdr.search.explore.stop-quiescent) Taken)
            (urdr.search.explore.loop-step Spec State Steps Taken))))

(define urdr.search.explore.quiescent?
  State ->
    (urdr.search.explore.empty?
      (urdr.world.pending (urdr.search.explore.state-world State))))

(define urdr.search.explore.empty?
  [] -> true
  _ -> false)

(define urdr.search.explore.loop-step
  Spec State Steps Taken ->
    (urdr.search.explore.loop-advanced
      (urdr.search.explore.apply
        State [advance-to-next-event]
        (urdr.search.explore.label-advance))
      Spec Steps Taken))

(define urdr.search.explore.loop-advanced
  [error Code Detail] _ _ _ -> [error Code Detail]
  [ok [step-result State Choices]] Spec Steps Taken ->
    (urdr.search.explore.loop-offers
      (urdr.search.explore.offer-loop
        Spec State (urdr.search.explore.offers Choices []))
      Spec Steps Taken))

(define urdr.search.explore.loop-offers
  [error Code Detail] _ _ _ -> [error Code Detail]
  [ok State] Spec Steps Taken ->
    (urdr.search.explore.loop
      Spec State
      (urdr.int.raw.subtract Steps (urdr.int.one))
      (+ Taken 1)))

\\ ---------------------------------------------------------------
\\ Entry point
\\ ---------------------------------------------------------------

(define urdr.search.explore.run
  Initial [explore-spec Seed Strategy MaxSteps Ladder Actions Encoder
            Detector] ->
    (if (urdr.world.valid? Initial)
        (urdr.search.explore.run-checked
          (urdr.search.explore.check-spec
            Seed Strategy MaxSteps Ladder Actions)
          Initial
          [explore-spec Seed Strategy MaxSteps Ladder Actions Encoder
            Detector])
        [error search-explore-world [null]])
  Initial _ -> [error search-explore-spec [null]])

(define urdr.search.explore.run-checked
  [error Code Detail] _ _ -> [error Code Detail]
  [ok] Initial Spec ->
    (urdr.search.explore.run-actions
      Spec
      [estate Initial [] [] [] [] 0]
      (urdr.search.explore.spec-actions Spec)))

(define urdr.search.explore.spec-actions
  [explore-spec _ _ _ _ Actions _ _] -> Actions)

(define urdr.search.explore.spec-steps
  [explore-spec _ _ MaxSteps _ _ _ _] -> MaxSteps)

(define urdr.search.explore.run-actions
  Spec State [] ->
    (urdr.search.explore.loop
      Spec State (urdr.search.explore.spec-steps Spec) 0)
  Spec State [Action | Rest] ->
    (urdr.search.explore.run-action
      (urdr.search.explore.apply
        State Action (urdr.search.explore.label-action))
      Spec Rest))

(define urdr.search.explore.run-action
  [error Code Detail] _ _ -> [error Code Detail]
  [ok [step-result State _]] Spec Rest ->
    (urdr.search.explore.run-actions Spec State Rest))

\\ ---------------------------------------------------------------
\\ Accessors and canonical rendering
\\ ---------------------------------------------------------------

(define urdr.search.explore.world
  [exploration World _ _ _ _ _] -> World)

(define urdr.search.explore.transcript
  [exploration _ Transcript _ _ _ _] -> Transcript)

(define urdr.search.explore.labels
  [exploration _ _ Labels _ _ _] -> Labels)

(define urdr.search.explore.choices
  [exploration _ _ _ Choices _ _] -> Choices)

(define urdr.search.explore.stop
  [exploration _ _ _ _ Stop _] -> Stop)

(define urdr.search.explore.steps
  [exploration _ _ _ _ _ Steps] -> Steps)

(define urdr.search.explore.count
  [] Acc -> Acc
  [_ | Rest] Acc -> (urdr.search.explore.count Rest (+ Acc 1))
  _ Acc -> Acc)

\\ The canonical summary of an exploration. The TRANSCRIPT ROOT is a
\\ parameter rather than something computed here: the artifact-grade
\\ identity of a transcript is urdr.replay.transcript-root, and a second
\\ spelling of it inside the search engine would be a second thing to
\\ keep in step with the reducer's own input vocabulary. The caller that
\\ already holds the replay layer passes its root in; the search engine
\\ commits to the DECISIONS, which are its own.
(define urdr.search.explore.value
  Exploration Strategy TranscriptRoot ->
    (urdr.search.explore.value-roots
      (urdr.search.choice.root
        (urdr.search.explore.choices Exploration))
      Exploration Strategy TranscriptRoot))

(define urdr.search.explore.value-roots
  [error Code Detail] _ _ _ -> [error Code Detail]
  [ok CRoot] Exploration Strategy TRoot ->
    [ok
      [record
        [[(urdr.search.explore.n k-choice-root) [bytes CRoot]]
         [(urdr.search.explore.n k-choices)
          (urdr.int.raw.from-small
            (urdr.search.explore.count
              (urdr.search.explore.choices Exploration) 0))]
         [(urdr.search.explore.n k-entries)
          (urdr.int.raw.from-small
            (urdr.search.explore.count
              (urdr.search.explore.transcript Exploration) 0))]
         [(urdr.search.explore.n k-steps)
          (urdr.int.raw.from-small
            (urdr.search.explore.steps Exploration))]
         [(urdr.search.explore.n k-stop)
          [symbol (urdr.search.explore.stop Exploration)]]
         [(urdr.search.explore.n k-strategy)
          (urdr.search.strategy.descriptor-value Strategy)]
         [(urdr.search.explore.n k-transcript-root) [bytes TRoot]]]]])
