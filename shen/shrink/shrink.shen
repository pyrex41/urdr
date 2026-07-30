\* Failure shrinking (SPEC.md 17.1, M1 plan Wave F).

Requires shen/protocol/canonical.shen, shen/world/integer.shen,
shen/world/prng.shen, shen/world/component.shen, shen/world/world.shen,
shen/world/eventlog.shen, shen/world/replay.shen,
shen/search/choice.shen, shen/search/strategy.shen, and
shen/search/explore.shen to be loaded by the caller.

Pure: no I/O, no host time, no host randomness, no floating point, no
defprolog. Minimisation is a total function of (initial world, labelled
transcript, target signature, evaluator).

NOT owned here (docs/module-boundaries.md): ambient randomness, and
property evaluation. There is no draw in this file: candidate generation
is a deterministic enumeration in a fixed order, because a shrinker that
searched randomly would need its own seed in the artifact to be
reproducible, and SPEC.md 17.1 asks for a minimum, not for a sample.

=====================================================================
1. What is being minimised
=====================================================================

  PLAN ::= [plan [[step LABEL INPUT] ...]]

one step per transcript entry, carrying the label the exploration driver
recorded for it (explore.shen section 6). The transcript itself is the
projection urdr.shrink.transcript, and it is what urdr.replay.run
consumes, so a minimised plan is replayable by anyone holding only the
initial world.

Labels exist because SPEC.md 17.1 orders the reduction by WHAT an entry
is, and a flat transcript of reducer inputs cannot say. The labels are
not re-derived here from the shape of an input; they are carried from
the search that made the decision, so a shrinker cannot disagree with
the searcher about what a given entry was.

=====================================================================
2. Accepting a candidate
=====================================================================

A candidate is a DIFFERENT transcript, so urdr.replay.verify is the
wrong tool: verify answers "is this the recorded run?", and for a
candidate the honest answer is always no. Following certificate.shen
section 7, a candidate is evaluated as

  urdr.replay.run INITIAL (transcript of the candidate)
    -> urdr.eventlog.final-world of the resulting log
    -> EVALUATOR
    -> a failure signature

and accepted only when that signature is IDENTICAL to the target. Not
"some failure persists" -- identical. Two reasons, and the second is the
one that bites:

  - urdr.certificate.failure-signature digests the whole FAIL verdict
    record, so the same property failing at a different witness is a
    DIFFERENT failure. A shrinker that accepted it would be minimising
    towards a bug nobody asked about.
  - properties.shen has finite-trace semantics, so truncating a trace
    can turn a PASS into a FAIL by cutting off an eventuality before its
    deadline. A candidate that removes the last few entries can
    therefore manufacture new failures. "Some failure persists" would
    accept it; "the same signature" does not.

Anything that is not an identical signature is a rejection, including a
replay error and an evaluator error. Rejection is never an exception and
never aborts the shrink.

  EVALUATOR WORLD -> [ok SIGNATURE] | [error CODE DETAIL]

is supplied by the caller so that shen/shrink/ carries no code
dependency on shen/properties/ or on shen/world/certificate.shen. The
M1 wiring, which shen/tests/shrink/ pins and Wave I is expected to reuse
verbatim, is

  (/. World
    (urdr.certificate.failure-signature
      (urdr.properties.verdict-values
        (verdicts of (urdr.properties.check PROPERTIES OBSERVATIONS
                       (urdr.properties.trace-of-world World))))))

A CONSEQUENCE worth stating plainly, because it bounds what any shrinker
built on this signature can do. Most FAIL witnesses name a trace INDEX
and an EVENT ID, and both are functions of the whole trace: removing any
earlier entry that emitted a fact renumbers the witness and therefore
changes the failure's identity. So a candidate that drops a genuinely
irrelevant entry BEFORE the witness is refused, correctly under the rule
and yet not because the entry mattered. What remains removable is
everything at or after the witness, and everything before it that emits
no fact at all. Minimisation under a witness-bearing failure is
consequently a suffix-and-silent-entries operation, not a free choice of
any subset, and a fixture that expects otherwise is expecting the rule
to be weaker than it is. Loosening the identity to make more candidates
acceptable is not a local decision: it would change what
urdr.certificate.failure-signature means, and that is certificate.shen's
contract, not this module's.

=====================================================================
3. The reduction order (SPEC.md 17.1)
=====================================================================

Six passes, always in this order:

  1. fault       injected faults
  2. network     network perturbations
  3. delay       artificial delays
  4. scheduling  scheduling choices
  5. external    external transcript entries
  6. action      scenario actions

Passes 1, 2, 4, 5, and 6 REMOVE; pass 3 SIMPLIFIES.

Removal of the step at index i has TWO candidates, tried in order:

  a. the step alone
  b. the step together with the first `advance` step after it

Both are needed, and which one works depends on where the run stopped.
A transcript that ends quiescent has drained every scheduled event, so
dropping a schedule without dropping an advance leaves an advance with
nothing to drain -- a fail-closed reducer error. A transcript that
stopped on a failed property usually has scheduled events still pending,
and there dropping an advance as well truncates the run by one dispatch
and can remove the very event the failure witnesses. Trying (a) first
prefers the candidate that changes the least.

An `advance` step is never a candidate in its own right: an advance
carries no decision, and removing one is a truncation, which section 2
explains is exactly the transformation that can manufacture a new
failure.

Pass 5 has no candidates in M1: an abstract run has no external inputs,
so no step ever carries the `external` label. The pass is run anyway and
reports zero candidates, because a reduction order with a silently
missing stage is a reduction order nobody can audit.

Pass 3 lowers the `at` of a schedule entry -- the artificial delay the
driver chose when it scheduled that input (explore.shen section 3).
Two candidates per entry, in order: `at := 0`, then `at := at - 1`. The
first is the whole reduction in one step when it is available; the
second makes progress when it is not. A candidate is only generated when
it differs from the entry it replaces, so the pass cannot spin.

=====================================================================
4. Termination
=====================================================================

Within a pass, an accepted removal leaves the cursor where it is (a new
step now occupies the index) and a rejected candidate advances it, so a
pass visits each index a bounded number of times. Across passes, every
acceptance strictly decreases the measure

  (number of steps, sum of the `at` fields)

under lexicographic order on non-negative integers, so a sweep that
accepts anything strictly decreases a well-founded measure. Shrinking
stops when a COMPLETE sweep of all six passes accepts nothing, which is
the SPEC.md 17.1 fixed point. MAX-SWEEPS is a fail-closed guard, not the
termination argument: hitting it is the error shrink-sweep-budget, not a
quietly truncated result.

=====================================================================
5. Transcript-prefix reuse
=====================================================================

M1 has no VM snapshots (plan Wave F), so "restores the nearest useful
snapshot" is, here, structural sharing over the transcript and nothing
more. urdr.shrink.shared-prefix reports how many leading steps a
candidate has in common with the previously evaluated one, and the
result carries the total across the run.

What this module deliberately does NOT do is skip work on the shared
prefix. A shared prefix of a TRANSCRIPT is not a shared prefix of a
REDUCTION unless the world after that prefix has been kept, and keeping
it is exactly the snapshot machinery M1 does not have. Re-driving is
therefore complete every time, and the sharing figure is reported as
what it is: a measurement of how much a resumable implementation would
have been able to reuse, pinned now so that M2 can be checked against
it rather than guessed at.

=====================================================================
6. Public entry points
=====================================================================

  plan            LABELS TRANSCRIPT -> [ok PLAN] | [error CODE DETAIL]
  plan-of         EXPLORATION -> [ok PLAN] | [error CODE DETAIL]
  transcript      PLAN -> [INPUT ...]
  labels          PLAN -> [LABEL ...]
  length          PLAN -> N
  shared-prefix   PLAN PLAN -> N
  signature-of    INITIAL PLAN EVALUATOR
                    -> [ok OCTETS] | [error CODE DETAIL]
  accept?         INITIAL PLAN TARGET EVALUATOR -> boolean
  remove-solo     INDEX PLAN -> PLAN
  remove-paired   INDEX PLAN -> PLAN
  minimize        INITIAL PLAN TARGET MAX-SWEEPS EVALUATOR
                    -> [ok RESULT] | [error CODE DETAIL]
  result-plan / result-sweeps / result-passes / result-evaluated /
  result-accepted / result-reused / result-signature
  value           RESULT -> canonical record
  error-value     CODE DETAIL -> canonical record
  code-octets     CODE -> OCTETS *\

\\ ---------------------------------------------------------------
\\ ASCII names (k- keys, w- words, c- error codes).
\\ ---------------------------------------------------------------

(define urdr.shrink.n
  k-accepted -> (urdr.canonical.string-bytes "accepted")
  k-candidates -> (urdr.canonical.string-bytes "candidates")
  k-code -> (urdr.canonical.string-bytes "code")
  k-detail -> (urdr.canonical.string-bytes "detail")
  k-entries -> (urdr.canonical.string-bytes "entries")
  k-evaluated -> (urdr.canonical.string-bytes "evaluated")
  k-label -> (urdr.canonical.string-bytes "label")
  k-passes -> (urdr.canonical.string-bytes "passes")
  k-reused -> (urdr.canonical.string-bytes "reused")
  k-signature -> (urdr.canonical.string-bytes "signature")
  k-sweeps -> (urdr.canonical.string-bytes "sweeps")
  w-external -> (urdr.canonical.string-bytes "external")
  w-delay -> (urdr.canonical.string-bytes "delay")
  c-plan-shape -> (urdr.canonical.string-bytes "shrink-plan-shape")
  c-plan-length -> (urdr.canonical.string-bytes "shrink-plan-length")
  c-initial -> (urdr.canonical.string-bytes "shrink-initial")
  c-target -> (urdr.canonical.string-bytes "shrink-target")
  c-original -> (urdr.canonical.string-bytes "shrink-original")
  c-evaluator -> (urdr.canonical.string-bytes "shrink-evaluator")
  c-replay -> (urdr.canonical.string-bytes "shrink-replay")
  c-sweep-budget -> (urdr.canonical.string-bytes "shrink-sweep-budget")
  c-unmapped -> (urdr.canonical.string-bytes "shrink-unmapped-code"))

(define urdr.shrink.code-octets
  shrink-plan-shape -> (urdr.shrink.n c-plan-shape)
  shrink-plan-length -> (urdr.shrink.n c-plan-length)
  shrink-initial -> (urdr.shrink.n c-initial)
  shrink-target -> (urdr.shrink.n c-target)
  shrink-original -> (urdr.shrink.n c-original)
  shrink-evaluator -> (urdr.shrink.n c-evaluator)
  shrink-replay -> (urdr.shrink.n c-replay)
  shrink-sweep-budget -> (urdr.shrink.n c-sweep-budget)
  _ -> (urdr.shrink.n c-unmapped))

(define urdr.shrink.error-value
  Code Detail ->
    [record
      [[(urdr.shrink.n k-code) [symbol (urdr.shrink.code-octets Code)]]
       [(urdr.shrink.n k-detail) Detail]]])

(define urdr.shrink.big
  N -> (urdr.int.raw.from-small N))

\\ ---------------------------------------------------------------
\\ Plans
\\ ---------------------------------------------------------------

(define urdr.shrink.plan
  Labels Transcript -> (urdr.shrink.plan-loop Labels Transcript []))

(define urdr.shrink.plan-loop
  [] [] Acc -> [ok [plan (urdr.canonical.rev Acc)]]
  [Label | Ls] [Input | Is] Acc ->
    (urdr.shrink.plan-loop Ls Is [[step Label Input] | Acc])
  [] _ _ -> [error shrink-plan-length [null]]
  _ [] _ -> [error shrink-plan-length [null]]
  _ _ _ -> [error shrink-plan-shape [null]])

(define urdr.shrink.plan-of
  Exploration ->
    (urdr.shrink.plan
      (urdr.search.explore.labels Exploration)
      (urdr.search.explore.transcript Exploration)))

(define urdr.shrink.steps
  [plan Steps] -> Steps
  _ -> [])

(define urdr.shrink.transcript
  [plan Steps] -> (urdr.shrink.inputs Steps)
  _ -> [])

(define urdr.shrink.inputs
  [] -> []
  [[step _ Input] | Rest] -> [Input | (urdr.shrink.inputs Rest)]
  _ -> [])

(define urdr.shrink.labels
  [plan Steps] -> (urdr.shrink.label-list Steps)
  _ -> [])

(define urdr.shrink.label-list
  [] -> []
  [[step Label _] | Rest] -> [Label | (urdr.shrink.label-list Rest)]
  _ -> [])

(define urdr.shrink.count
  [] Acc -> Acc
  [_ | Rest] Acc -> (urdr.shrink.count Rest (+ Acc 1))
  _ Acc -> Acc)

(define urdr.shrink.length
  Plan -> (urdr.shrink.count (urdr.shrink.steps Plan) 0))

\\ Structural equality over steps: a step is a label plus a reducer
\\ input, and both are built from lists, octets, and software integers,
\\ so Shen's own equality is the right comparison and needs no encoding.
(define urdr.shrink.shared-prefix
  A B ->
    (urdr.shrink.shared-loop
      (urdr.shrink.steps A) (urdr.shrink.steps B) 0))

(define urdr.shrink.shared-loop
  [] _ N -> N
  _ [] N -> N
  [A | As] [B | Bs] N ->
    (if (= A B)
        (urdr.shrink.shared-loop As Bs (+ N 1))
        N)
  _ _ N -> N)

\\ ---------------------------------------------------------------
\\ Candidate generation
\\ ---------------------------------------------------------------

(define urdr.shrink.nth-step
  0 [Step | _] -> [some Step]
  N [_ | Rest] -> (urdr.shrink.nth-step (- N 1) Rest)
  _ _ -> none)

(define urdr.shrink.step-label
  [step Label _] -> Label)

(define urdr.shrink.step-input
  [step _ Input] -> Input)

\\ Two removal candidates for the step at INDEX, in order (section 3):
\\ the step alone, then the step together with the first `advance` after
\\ it.
(define urdr.shrink.remove-candidates
  Index Plan ->
    [(urdr.shrink.remove-solo Index Plan)
     (urdr.shrink.remove-paired Index Plan)])

(define urdr.shrink.remove-solo
  Index Plan ->
    [plan (urdr.shrink.solo-loop Index (urdr.shrink.steps Plan) [])])

(define urdr.shrink.solo-loop
  0 [_ | Rest] Acc -> (append (urdr.canonical.rev Acc) Rest)
  N [Step | Rest] Acc ->
    (urdr.shrink.solo-loop (- N 1) Rest [Step | Acc])
  _ [] Acc -> (urdr.canonical.rev Acc))

(define urdr.shrink.remove-paired
  Index Plan ->
    [plan (urdr.shrink.remove-loop Index (urdr.shrink.steps Plan) [])])

(define urdr.shrink.remove-loop
  0 [_ | Rest] Acc ->
    (urdr.shrink.drop-advance Rest Acc)
  N [Step | Rest] Acc ->
    (urdr.shrink.remove-loop (- N 1) Rest [Step | Acc])
  _ [] Acc -> (urdr.canonical.rev Acc))

(define urdr.shrink.drop-advance
  [] Acc -> (urdr.canonical.rev Acc)
  [[step Label Input] | Rest] Acc ->
    (if (= Label (urdr.search.explore.label-advance))
        (append (urdr.canonical.rev Acc) Rest)
        (urdr.shrink.drop-advance Rest [[step Label Input] | Acc]))
  _ Acc -> (urdr.canonical.rev Acc))

(define urdr.shrink.replace-at
  Index Step Plan ->
    [plan
      (urdr.shrink.replace-loop
        Index Step (urdr.shrink.steps Plan) [])])

(define urdr.shrink.replace-loop
  0 New [_ | Rest] Acc -> (append (urdr.canonical.rev Acc) [New | Rest])
  N New [Step | Rest] Acc ->
    (urdr.shrink.replace-loop (- N 1) New Rest [Step | Acc])
  _ _ [] Acc -> (urdr.canonical.rev Acc))

\\ The two delay candidates for a schedule step, in order, skipping any
\\ that would not change the step.
(define urdr.shrink.delay-candidates
  [step Label [schedule At Kind Payload]] ->
    (if (urdr.int.raw.zero? At)
        []
        (urdr.shrink.delay-rungs Label Kind Payload At))
  _ -> [])

(define urdr.shrink.delay-rungs
  Label Kind Payload At ->
    (if (= (urdr.int.raw.compare At (urdr.int.one)) 0)
        [[step Label [schedule (urdr.int.zero) Kind Payload]]]
        [[step Label [schedule (urdr.int.zero) Kind Payload]]
         [step Label
           [schedule (urdr.int.raw.subtract At (urdr.int.one))
             Kind Payload]]]))

\\ ---------------------------------------------------------------
\\ Evaluation (section 2)
\\ ---------------------------------------------------------------

(define urdr.shrink.signature-of
  Initial Plan Evaluator ->
    (urdr.shrink.signature-run
      (urdr.replay.run Initial (urdr.shrink.transcript Plan))
      Evaluator))

(define urdr.shrink.signature-run
  [error Code Detail] _ -> [error shrink-replay [null]]
  [ok Run] Evaluator ->
    (urdr.shrink.signature-world
      (Evaluator
        (urdr.eventlog.final-world (urdr.replay.run-log Run))))
  _ _ -> [error shrink-replay [null]])

(define urdr.shrink.signature-world
  [ok Signature] -> [ok Signature]
  [error Code Detail] -> [error shrink-evaluator [null]]
  _ -> [error shrink-evaluator [null]])

\\ Candidate acceptance folds every failure -- replay refusal, evaluator
\\ refusal, a different signature -- into one answer: no.
(define urdr.shrink.accept?
  Initial Plan Target Evaluator ->
    (urdr.shrink.accept-of
      (urdr.shrink.signature-of Initial Plan Evaluator) Target))

(define urdr.shrink.accept-of
  [ok Signature] Target -> (= Signature Target)
  _ _ -> false)

\\ ---------------------------------------------------------------
\\ Bookkeeping
\\ ---------------------------------------------------------------
\\
\\ [sstate PLAN LAST EVALUATED ACCEPTED REUSED TALLY]
\\ TALLY is [[tally LABEL CANDIDATES ACCEPTED] ...] in pass order.

(define urdr.shrink.state-plan
  [sstate Plan _ _ _ _ _] -> Plan)

(define urdr.shrink.tally-bump
  [] _ _ _ -> []
  [[tally Label C A] | Rest] Label Candidates Accepted ->
    [[tally Label (+ C Candidates) (+ A Accepted)] | Rest]
  [Entry | Rest] Label Candidates Accepted ->
    [Entry | (urdr.shrink.tally-bump Rest Label Candidates Accepted)]
  _ _ _ _ -> [])

\\ One candidate evaluation, threading the sharing measurement and the
\\ per-label tally through the state.
(define urdr.shrink.try
  Initial [sstate Plan Last Evaluated Accepted Reused Tally] Label
  Candidate Target Evaluator ->
    (urdr.shrink.try-result
      (urdr.shrink.accept? Initial Candidate Target Evaluator)
      [sstate Plan Last (+ Evaluated 1) Accepted
        (+ Reused (urdr.shrink.shared-prefix Last Candidate))
        (urdr.shrink.tally-bump Tally Label 1 0)]
      Label Candidate))

(define urdr.shrink.try-result
  false [sstate Plan _ Evaluated Accepted Reused Tally] _ Candidate ->
    [rejected [sstate Plan Candidate Evaluated Accepted Reused Tally]]
  true [sstate _ _ Evaluated Accepted Reused Tally] Label Candidate ->
    [accepted
      [sstate Candidate Candidate Evaluated (+ Accepted 1) Reused
        (urdr.shrink.tally-bump Tally Label 0 1)]])

\\ ---------------------------------------------------------------
\\ Passes (section 3)
\\ ---------------------------------------------------------------

(define urdr.shrink.pass-labels
  -> [(urdr.search.explore.label-fault)
      (urdr.search.explore.label-network)
      (urdr.shrink.n w-delay)
      (urdr.search.explore.label-scheduling)
      (urdr.shrink.n w-external)
      (urdr.search.explore.label-action)])

(define urdr.shrink.empty-tally
  -> (urdr.shrink.tally-of (urdr.shrink.pass-labels)))

(define urdr.shrink.tally-of
  [] -> []
  [Label | Rest] ->
    [[tally Label 0 0] | (urdr.shrink.tally-of Rest)])

\\ One pass is a walk over the plan's indices. At each index the pass
\\ offers a list of candidate plans, in preference order; the first
\\ accepted one replaces the plan and the cursor stays where it is,
\\ because a new step now occupies that index. An index with no
\\ candidates, and an index whose candidates are all rejected, advances
\\ the cursor.
(define urdr.shrink.pass
  Initial State Label Target Evaluator Index ->
    (urdr.shrink.pass-at
      (urdr.shrink.nth-step
        Index (urdr.shrink.steps (urdr.shrink.state-plan State)))
      Initial State Label Target Evaluator Index))

(define urdr.shrink.pass-at
  none _ State _ _ _ _ -> State
  [some Step] Initial State Label Target Evaluator Index ->
    (urdr.shrink.pass-loop
      (urdr.shrink.candidates
        Label Step Index (urdr.shrink.state-plan State))
      Initial State Label Target Evaluator Index))

(define urdr.shrink.pass-loop
  [] Initial State Label Target Evaluator Index ->
    (urdr.shrink.pass Initial State Label Target Evaluator (+ Index 1))
  [Candidate | Rest] Initial State Label Target Evaluator Index ->
    (urdr.shrink.pass-try
      (urdr.shrink.try Initial State Label Candidate Target Evaluator)
      Rest Initial Label Target Evaluator Index))

(define urdr.shrink.pass-try
  [accepted State] _ Initial Label Target Evaluator Index ->
    (urdr.shrink.pass Initial State Label Target Evaluator Index)
  [rejected State] Rest Initial Label Target Evaluator Index ->
    (urdr.shrink.pass-loop
      Rest Initial State Label Target Evaluator Index))

\\ The delay pass simplifies every schedule step whatever its label; the
\\ five removal passes remove only the steps carrying their own label.
(define urdr.shrink.candidates
  Label Step Index Plan ->
    (if (= Label (urdr.shrink.n w-delay))
        (urdr.shrink.delay-plans
          (urdr.shrink.delay-candidates Step) Index Plan)
        (if (= (urdr.shrink.step-label Step) Label)
            (urdr.shrink.remove-candidates Index Plan)
            [])))

(define urdr.shrink.delay-plans
  [] _ _ -> []
  [Step | Rest] Index Plan ->
    [(urdr.shrink.replace-at Index Step Plan) |
     (urdr.shrink.delay-plans Rest Index Plan)])

\\ One complete sweep, in SPEC.md 17.1 order.
(define urdr.shrink.sweep
  Initial State Target Evaluator ->
    (urdr.shrink.sweep-loop
      Initial State (urdr.shrink.pass-labels) Target Evaluator))

(define urdr.shrink.sweep-loop
  _ State [] _ _ -> State
  Initial State [Label | Rest] Target Evaluator ->
    (urdr.shrink.sweep-loop
      Initial
      (urdr.shrink.pass Initial State Label Target Evaluator 0)
      Rest Target Evaluator))

\\ ---------------------------------------------------------------
\\ Driving to a fixed point (section 4)
\\ ---------------------------------------------------------------

(define urdr.shrink.state-accepted
  [sstate _ _ _ Accepted _ _] -> Accepted)

(define urdr.shrink.fixpoint
  Initial State Target MaxSweeps Evaluator Sweeps ->
    (if (urdr.int.raw.zero? MaxSweeps)
        [error shrink-sweep-budget [null]]
        (urdr.shrink.fixpoint-swept
          (urdr.shrink.sweep Initial State Target Evaluator)
          Initial State Target MaxSweeps Evaluator (+ Sweeps 1))))

(define urdr.shrink.fixpoint-swept
  Next Initial Before Target MaxSweeps Evaluator Sweeps ->
    (if (= (urdr.shrink.state-accepted Next)
           (urdr.shrink.state-accepted Before))
        [ok [swept Next Sweeps]]
        (urdr.shrink.fixpoint
          Initial Next Target
          (urdr.int.raw.subtract MaxSweeps (urdr.int.one))
          Evaluator Sweeps)))

(define urdr.shrink.minimize
  Initial Plan Target MaxSweeps Evaluator ->
    (if (not (urdr.world.valid? Initial))
        [error shrink-initial [null]]
        (if (not (= (urdr.shrink.count Target 0) 32))
            [error shrink-target [null]]
            (if (not (urdr.int.valid? MaxSweeps))
                [error shrink-sweep-budget [null]]
                (urdr.shrink.minimize-original
                  (urdr.shrink.signature-of Initial Plan Evaluator)
                  Initial Plan Target MaxSweeps Evaluator)))))

\\ Refuse to shrink a failure that is not there. A shrinker handed a plan
\\ that does not reproduce the target signature would minimise towards
\\ nothing and report a "minimal" artifact for a failure it never saw.
(define urdr.shrink.minimize-original
  [error Code Detail] _ _ _ _ _ -> [error Code Detail]
  [ok Signature] Initial Plan Target MaxSweeps Evaluator ->
    (if (= Signature Target)
        (urdr.shrink.minimize-run
          Initial Plan Target MaxSweeps Evaluator)
        [error shrink-original [null]]))

(define urdr.shrink.minimize-run
  Initial Plan Target MaxSweeps Evaluator ->
    (urdr.shrink.minimize-swept
      (urdr.shrink.fixpoint
        Initial
        [sstate Plan Plan 0 0 0 (urdr.shrink.empty-tally)]
        Target MaxSweeps Evaluator 0)
      Target))

(define urdr.shrink.minimize-swept
  [error Code Detail] _ -> [error Code Detail]
  [ok [swept [sstate Plan _ Evaluated Accepted Reused Tally] Sweeps]]
  Target ->
    [ok [shrunk Plan Sweeps Tally Evaluated Accepted Reused Target]])

\\ ---------------------------------------------------------------
\\ Result
\\ ---------------------------------------------------------------

(define urdr.shrink.result-plan
  [shrunk Plan _ _ _ _ _ _] -> Plan)

(define urdr.shrink.result-sweeps
  [shrunk _ Sweeps _ _ _ _ _] -> Sweeps)

(define urdr.shrink.result-passes
  [shrunk _ _ Tally _ _ _ _] -> Tally)

(define urdr.shrink.result-evaluated
  [shrunk _ _ _ Evaluated _ _ _] -> Evaluated)

(define urdr.shrink.result-accepted
  [shrunk _ _ _ _ Accepted _ _] -> Accepted)

(define urdr.shrink.result-reused
  [shrunk _ _ _ _ _ Reused _] -> Reused)

(define urdr.shrink.result-signature
  [shrunk _ _ _ _ _ _ Signature] -> Signature)

(define urdr.shrink.pass-values
  [] -> []
  [[tally Label Candidates Accepted] | Rest] ->
    [[record
       [[(urdr.shrink.n k-accepted) (urdr.shrink.big Accepted)]
        [(urdr.shrink.n k-candidates) (urdr.shrink.big Candidates)]
        [(urdr.shrink.n k-label) [symbol Label]]]] |
     (urdr.shrink.pass-values Rest)]
  _ -> [])

(define urdr.shrink.value
  Result ->
    [record
      [[(urdr.shrink.n k-accepted)
        (urdr.shrink.big (urdr.shrink.result-accepted Result))]
       [(urdr.shrink.n k-entries)
        (urdr.shrink.big
          (urdr.shrink.length (urdr.shrink.result-plan Result)))]
       [(urdr.shrink.n k-evaluated)
        (urdr.shrink.big (urdr.shrink.result-evaluated Result))]
       [(urdr.shrink.n k-passes)
        [list (urdr.shrink.pass-values
                (urdr.shrink.result-passes Result))]]
       [(urdr.shrink.n k-reused)
        (urdr.shrink.big (urdr.shrink.result-reused Result))]
       [(urdr.shrink.n k-signature)
        [bytes (urdr.shrink.result-signature Result)]]
       [(urdr.shrink.n k-sweeps)
        (urdr.shrink.big (urdr.shrink.result-sweeps Result))]]])
