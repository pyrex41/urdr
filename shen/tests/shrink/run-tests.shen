\* Wave F conformance suite, part 2: failure shrinking
   (shen/shrink/shrink.shen) over the exploration artifact
   shen/tests/search/ pins.

   Semantic output lines, in fixture order:

     PLAN|NAME|RESULT          plan construction and its rejections
     SHARE|NAME|N              shared-prefix measurement (section 5)
     SIG|NAME|HEX              a canonical failure signature
     VERD|NAME|HEX             a verdict record feeding a signature
     SHR|NAME|ENTRIES|SWEEPS|EVALUATED|ACCEPTED|REUSED
     SHRL|NAME|LABELS          the minimised plan's labels
     SHRV|NAME|HEX             the shrink report, canonically encoded
     MIN|NAME|HEX              the minimised artifact replayed
                               independently: event root ++ state root
     MUT|NAME|RESULT           a mutation that must be refused
     SREJ|NAME|CODE            a fail-closed shrinker rejection
     SHRINK CASES: N
     ALL PASS

   Any internal inconsistency prints a FAIL| line and suppresses the
   ALL PASS marker; shen/tests/shrink/test.sh additionally compares every
   semantic line against the checked-in golden output.

   Cost discipline: shrinking re-drives a transcript once per candidate
   and every event hashes a three-component world snapshot, so the
   exploration and the minimisation each run ONCE and are threaded
   through the cases as values. *\

(define urt.eval-forms
  [] -> loaded
  [[load _] | Forms] -> (urt.eval-forms Forms)
  [Form | Forms] ->
    (let Ignored (eval Form)
      (urt.eval-forms Forms)))

(define urt.quiet-load
  File -> (urt.eval-forms (read-file File)))

(urt.quiet-load "shen/protocol/canonical.shen")
(urt.quiet-load "shen/world/integer.shen")
(urt.quiet-load "shen/world/prng.shen")
(urt.quiet-load "shen/world/netkat.shen")
(urt.quiet-load "shen/world/component.shen")
(urt.quiet-load "shen/world/world.shen")
(urt.quiet-load "shen/scenario/scenario.shen")
(urt.quiet-load "shen/world/models/common.shen")
(urt.quiet-load "shen/world/models/mask.shen")
(urt.quiet-load "shen/world/models/net.shen")
(urt.quiet-load "shen/world/models/timer.shen")
(urt.quiet-load "shen/world/models/fault.shen")
(urt.quiet-load "shen/world/models/registry.shen")
(urt.quiet-load "shen/properties/properties.shen")
(urt.quiet-load "shen/world/eventlog.shen")
(urt.quiet-load "shen/world/replay.shen")
(urt.quiet-load "shen/world/certificate.shen")
(urt.quiet-load "shen/search/choice.shen")
(urt.quiet-load "shen/search/strategy.shen")
(urt.quiet-load "shen/search/explore.shen")
(urt.quiet-load "shen/shrink/shrink.shen")

\\ ---------------------------------------------------------------
\\ Rendering.
\\ ---------------------------------------------------------------

(define urt.k
  Name -> (urdr.canonical.string-bytes Name))

(define urt.s
  Name -> [symbol (urdr.canonical.string-bytes Name)])

(define urt.big
  N -> (urdr.int.raw.from-small N))

(define urt.string
  [] -> ""
  [B | Bs] -> (cn (n->string B) (urt.string Bs)))

(define urt.div16
  N Q -> Q where (< N 16)
  N Q -> (urt.div16 (- N 16) (+ Q 1)))

(define urt.mod16
  N -> N where (< N 16)
  N -> (urt.mod16 (- N 16)))

(define urt.hexdigit
  N -> (n->string (+ 48 N)) where (< N 10)
  N -> (n->string (+ 87 N)))

(define urt.hex
  [] -> ""
  [B | Bs] ->
    (cn (cn (urt.hexdigit (urt.div16 B 0)) (urt.hexdigit (urt.mod16 B)))
        (urt.hex Bs)))

(define urt.enc-hex
  Value -> (urt.enc-hex-of (urdr.canonical.encode-payload Value)))

(define urt.enc-hex-of
  [ok Bytes] -> (urt.hex Bytes)
  [error E] -> "unencodable")

(define urt.count
  [] -> 0
  [_ | Xs] -> (+ 1 (urt.count Xs))
  _ -> 0)

(define urt.join
  [] -> ""
  [X] -> (urt.string X)
  [X | Xs] -> (cn (urt.string X) (cn "," (urt.join Xs)))
  _ -> "")

(define urt.fail
  Name Why -> (do (output "FAIL|~A|~A~%" Name Why) false))

(define urt.concat
  [] -> []
  [Xs | Rest] -> (append Xs (urt.concat Rest)))

(define urt.run-thunks
  [] Ok -> Ok
  [T | Ts] Ok ->
    (let R (T 0)
      (urt.run-thunks Ts (if R Ok false))))

\\ ---------------------------------------------------------------
\\ The fixture, identical to shen/tests/search/: a scenario-derived world
\\ with all three abstract models, one packet in flight, an armed
\\ deadline, and one fault domain.
\\ ---------------------------------------------------------------

(define urt.node-value
  Address Id ->
    [record [[(urt.k "address") (urt.big Address)] [(urt.k "id") Id]]])

(define urt.link-value
  From To -> [record [[(urt.k "from") From] [(urt.k "to") To]]])

(define urt.component-value
  Id Kind Node ->
    [record
      [[(urt.k "id") Id] [(urt.k "kind") Kind] [(urt.k "node") Node]]])

(define urt.field-value
  Field ->
    [record
      [[(urt.k "field") Field]
       [(urt.k "values") [list [(urt.big 1) (urt.big 2)]]]]])

(define urt.scenario-value
  -> [record
       [[(urt.k "budget")
         [record
           [[(urt.k "max-events") (urt.big 100)]
            [(urt.k "max-runs") (urt.big 4)]
            [(urt.k "max-steps") (urt.big 100)]]]]
        [(urt.k "components")
         [list
           [(urt.component-value (urt.s "f1") (urt.s "fault")
              (urt.s "b"))
            (urt.component-value (urt.s "n1") (urt.s "net") (urt.s "a"))
            (urt.component-value (urt.s "t1") (urt.s "timer")
              (urt.s "a"))]]]
        [(urt.k "determinism") (urt.s "modeled")]
        [(urt.k "faults")
         [list
           [[record
              [[(urt.k "id") (urt.s "d1")]
               [(urt.k "kinds") [list [(urt.s "partition")]]]
               [(urt.k "members") [list [(urt.s "b")]]]]]]]]
        [(urt.k "header-vocabulary")
         [list
           [(urt.field-value (urt.s "dst"))
            (urt.field-value (urt.s "src"))]]]
        [(urt.k "observations") [list []]]
        [(urt.k "properties") [list []]]
        [(urt.k "seed") [bytes (urt.k "e-seed")]]
        [(urt.k "topology")
         [record
           [[(urt.k "links")
             [list [(urt.link-value (urt.s "a") (urt.s "b"))]]]
            [(urt.k "nodes")
             [list
               [(urt.node-value 1 (urt.s "a"))
                (urt.node-value 2 (urt.s "b"))]]]]]]
        [(urt.k "version") (urt.s "scenario/v1")]]])

(define urt.world-of
  [ok World] -> World
  Other -> Other)

(define urt.registry-of
  [ok Scenario] ->
    (urdr.model.registry.from-scenario
      Scenario (urdr.netkat.term-encode [nk-id])
      (/. S E [step S [] []]) [null])
  Error -> Error)

(define urt.e-world-of
  [ok Registry] ->
    (urt.world-of
      (urdr.world.initial-with-components (urt.k "e-seed") Registry))
  Error -> Error)

(define urt.e-world
  -> (urt.e-world-of
       (urt.registry-of
         (urdr.scenario.validate (urt.scenario-value)))))

(define urt.packet
  S D ->
    [record [[(urt.k "dst") (urt.big D)] [(urt.k "src") (urt.big S)]]])

(define urt.sched
  Name Value ->
    [schedule (urdr.int.zero) component [component-input Name Value]])

(define urt.actions
  -> [(urt.sched (urt.k "n1")
        (urdr.model.net.send-input (urt.packet 1 2)
          (urt.k "a") (urt.k "b")))
      (urt.sched (urt.k "f1") (urdr.model.fault.poll-input))
      (urt.sched (urt.k "t1")
        (urdr.model.timer.set-input (urt.k "w") (urdr.int.zero)))])

(define urt.encoder
  Actor Kind Selected ->
    (if (= Kind (urt.k "delivery"))
        [ok [record
              [[(urt.k "kind") (urt.s "deliver")]
               [(urt.k "selection") Selected]]]]
        (if (= Kind (urt.k "fault-action"))
            [ok Selected]
            (if (= Kind (urt.k "timer-fire"))
                (urt.fire-input Selected)
                [none]))))

(define urt.fire-input
  [record [[[100 117 101] _] [[105 100] [symbol Id]]]] ->
    [ok (urdr.model.timer.fire-input Id)]
  _ -> [none])

(define urt.ladder
  -> [(urdr.int.zero) (urt.big 1) (urt.big 2)])

\\ ---------------------------------------------------------------
\\ Properties. Two, chosen so the suite can show BOTH shrinker hazards:
\\
\\   n-dropped  temporal never over the `dropped` fact. It is the one
\\              class that turns from PASS to FAIL part-way through a
\\              run, so it is what an exploration can stop on, and its
\\              FAIL witness names the offending entry -- which is what
\\              makes "the same failure" mean the same entry.
\\   l-fired    liveness over the `fired` fact with an inclusive
\\              deadline. On the truncation fixture below it PASSES on
\\              the full transcript and FAILS on a truncated one, which
\\              is the Wave D finite-trace hazard a shrinker must not
\\              mistake for persistence.
\\ ---------------------------------------------------------------

(define urt.pattern
  Name ->
    [record
      [[(urdr.properties.n.name) [symbol Name]]
       [(urdr.properties.n.source) [null]]
       [(urdr.properties.n.value) [null]]]])

(define urt.prop-never
  -> [property (urdr.properties.n.temporal) (urt.k "n-dropped")
       [record
         [[(urdr.properties.n.args)
           [list [(urt.pattern (urt.k "dropped"))]]]
          [(urdr.properties.n.form)
           [symbol (urdr.properties.n.never)]]]]])

(define urt.prop-fired
  -> [property (urdr.properties.n.liveness) (urt.k "l-fired")
       [record
         [[(urdr.properties.n.deadline) (urt.big 9)]
          [(urdr.properties.n.pattern)
           (urt.pattern (urt.k "fired"))]]]])

\\ properties.shen requires strictly ascending property ids.
(define urt.properties
  -> [(urt.prop-fired) (urt.prop-never)])

\\ The exploration detector reads only the `never` property: an
\\ exploration must stop when it has FOUND something, and the liveness
\\ property is unfulfilled from the first instant of every run.
(define urt.stop-properties
  -> [(urt.prop-never)])

(define urt.verdicts
  Properties World ->
    (urt.verdicts-trace Properties
      (urdr.properties.trace-of-world World)))

(define urt.verdicts-trace
  Properties [ok Trace] ->
    (urdr.properties.check Properties [] Trace)
  Properties [error E] -> [error E])

(define urt.failed?
  World -> (urt.failed-of (urt.verdicts (urt.stop-properties) World)))

(define urt.failed-of
  [ok Verdicts] ->
    [ok (urdr.certificate.any-fail?
          (urdr.properties.verdict-values Verdicts))]
  [error E] -> [error E [null]])

\\ The evaluator shrink.shen section 2 asks for, wired here and nowhere
\\ inside shen/shrink/.
(define urt.signature
  World -> (urt.signature-of (urt.verdicts (urt.properties) World)))

(define urt.signature-of
  [ok Verdicts] ->
    (urdr.certificate.failure-signature
      (urdr.properties.verdict-values Verdicts))
  [error E] -> [error E [null]])

\\ The same evaluator restricted to the `never` property, used to show
\\ that the liveness property is what makes truncation visible.
(define urt.never-signature
  World ->
    (urt.signature-of (urt.verdicts (urt.stop-properties) World)))

(define urt.evaluator
  -> (/. W (urt.signature W)))

(define urt.never-evaluator
  -> (/. W (urt.never-signature W)))

\\ ---------------------------------------------------------------
\\ The truncation fixture (shrink.shen section 2, plan Wave D).
\\
\\ A hand-built transcript, not an exploration, because the point is a
\\ SHAPE the search does not happen to produce: a run whose LAST
\\ dispatch discharges a liveness obligation. On the full transcript
\\ `l-fired` PASSES and only `n-dropped` FAILS; dropping the final
\\ advance keeps `n-dropped` failing at exactly the same witness and
\\ turns `l-fired` into a second FAIL.
\\
\\ A shrinker whose rule were "some failure persists" would accept that
\\ candidate. The rule is "the same failure", and the two evaluators
\\ below make the difference into two pinned lines: the full property
\\ set refuses the truncation, the never-only property set accepts it.
\\ ---------------------------------------------------------------

(define urt.advance
  -> [advance-to-next-event])

(define urt.t-inputs
  -> [(urt.sched (urt.k "n1")
        (urdr.model.net.send-input (urt.packet 1 2)
          (urt.k "a") (urt.k "b")))
      (urt.sched (urt.k "t1")
        (urdr.model.timer.set-input (urt.k "w") (urdr.int.zero)))
      (urt.advance)
      (urt.advance)
      (urt.sched (urt.k "n1")
        (urdr.model.net.deliver-input
          (urt.k "drop") 0 (urt.k "a") (urt.k "b")))
      (urt.advance)
      (urt.sched (urt.k "t1") (urdr.model.timer.fire-input (urt.k "w")))
      (urt.advance)])

(define urt.t-labels
  -> [(urdr.search.explore.label-action)
      (urdr.search.explore.label-action)
      (urdr.search.explore.label-advance)
      (urdr.search.explore.label-advance)
      (urdr.search.explore.label-network)
      (urdr.search.explore.label-advance)
      (urdr.search.explore.label-scheduling)
      (urdr.search.explore.label-advance)])

(define urt.t-plan
  -> (urt.value-of (urdr.shrink.plan (urt.t-labels) (urt.t-inputs))))

\\ ---------------------------------------------------------------
\\ The exploration under minimisation.
\\ ---------------------------------------------------------------

(define urt.spec
  -> (urdr.search.explore.spec
       (urt.k "s2") (urdr.search.strategy.baseline) (urt.big 8)
       (urt.ladder) (urt.actions)
       (/. A K S (urt.encoder A K S))
       (/. W (urt.failed? W))))

(define urt.exploration
  -> (urdr.search.explore.run (urt.e-world) (urt.spec)))

(define urt.value-of
  [ok V] -> V
  Other -> Other)

\\ The world a transcript ends in, which is what the evaluator reads.
(define urt.final-world
  Transcript ->
    (urt.final-world-of (urdr.replay.run (urt.e-world) Transcript)))

(define urt.final-world-of
  [ok Run] -> [ok (urdr.eventlog.final-world (urdr.replay.run-log Run))]
  [error Code Detail] -> [error Code Detail])

(define urt.world-signature
  Transcript ->
    (urt.world-signature-of (urt.final-world Transcript)))

(define urt.world-signature-of
  [ok World] -> (urt.signature World)
  [error Code Detail] -> [error Code Detail])

\\ ---------------------------------------------------------------
\\ Case group 1: plans
\\ ---------------------------------------------------------------

(define urt.plan-case
  Name Result Expected -> (/. Unit (urt.plan-line Name Result Expected)))

(define urt.plan-line
  Name [ok Plan] ok ->
    (do (output "PLAN|~A|entries=~A~%" Name (urdr.shrink.length Plan))
        true)
  Name [error Code _] Expected ->
    (if (= Code Expected)
        (do (output "PLAN|~A|~A~%" Name
              (urt.string (urdr.shrink.code-octets Code)))
            true)
        (urt.fail Name "wrong-code"))
  Name _ Expected -> (urt.fail Name "unexpected-shape"))

(define urt.share-case
  Name A B N -> (/. Unit (urt.share-line Name A B N)))

(define urt.share-line
  Name A B N ->
    (let Shared (urdr.shrink.shared-prefix A B)
      (if (= Shared N)
          (do (output "SHARE|~A|~A~%" Name Shared) true)
          (urt.fail Name "shared-prefix"))))

\\ ---------------------------------------------------------------
\\ Case group 2: signatures
\\ ---------------------------------------------------------------

(define urt.sig-case
  Name Result -> (/. Unit (urt.sig-line Name Result)))

(define urt.sig-line
  Name [ok Signature] ->
    (do (output "SIG|~A|~A~%" Name (urt.hex Signature)) true)
  Name _ -> (urt.fail Name "signature-error"))

(define urt.verd-case
  Name World -> (/. Unit (urt.verd-line Name World)))

(define urt.verd-line
  Name World -> (urt.verd-values Name (urt.verdicts (urt.properties) World)))

(define urt.verd-values
  Name [ok Verdicts] ->
    (urt.verd-loop Name (urdr.properties.verdict-values Verdicts))
  Name _ -> (urt.fail Name "verdict-error"))

(define urt.verd-loop
  _ [] -> true
  Name [V | Vs] ->
    (do (output "VERD|~A|~A~%" Name (urt.enc-hex V))
        (urt.verd-loop Name Vs)))

\\ ---------------------------------------------------------------
\\ Case group 3: minimisation
\\ ---------------------------------------------------------------

(define urt.shr-case
  Name Result Original ->
    (/. Unit (urt.shr-line Name Result Original)))

(define urt.shr-line
  Name [ok R] Original ->
    (do
      (output "SHR|~A|~A|~A|~A|~A|~A~%" Name
        (urdr.shrink.length (urdr.shrink.result-plan R))
        (urdr.shrink.result-sweeps R)
        (urdr.shrink.result-evaluated R)
        (urdr.shrink.result-accepted R)
        (urdr.shrink.result-reused R))
      (output "SHRL|~A|~A~%" Name
        (urt.join (urdr.shrink.labels (urdr.shrink.result-plan R))))
      (output "SHRV|~A|~A~%" Name (urt.enc-hex (urdr.shrink.value R)))
      (urt.shr-smaller Name R Original))
  Name [error Code Detail] Original -> (urt.fail Name "shrink-error"))

\\ SPEC.md 25 acceptance 11: at least one irrelevant choice is gone.
(define urt.shr-smaller
  Name R Original ->
    (if (< (urdr.shrink.length (urdr.shrink.result-plan R))
           (urdr.shrink.length Original))
        true
        (urt.fail Name "nothing-removed")))

\\ The minimised artifact must remain INDEPENDENTLY replayable: driven
\\ from the initial world by urdr.replay.run alone, with no knowledge of
\\ the search that produced it, it must reach the same failure.
(define urt.min-case
  Name Result Target -> (/. Unit (urt.min-line Name Result Target)))

(define urt.min-line
  Name [ok R] Target ->
    (urt.min-run Name
      (urdr.replay.run (urt.e-world)
        (urdr.shrink.transcript (urdr.shrink.result-plan R)))
      Target)
  Name _ Target -> (urt.fail Name "shrink-error"))

(define urt.min-run
  Name [ok Run] Target ->
    (urt.min-signature Name Run
      (urt.signature (urdr.eventlog.final-world
                       (urdr.replay.run-log Run)))
      Target)
  Name _ Target -> (urt.fail Name "replay-error"))

(define urt.min-signature
  Name Run [ok Signature] Target ->
    (if (= Signature Target)
        (do
          (output "MIN|~A|~A~%" Name
            (urt.hex
              (append (urdr.replay.run-event-root Run)
                      (urdr.replay.run-state-root Run))))
          true)
        (urt.fail Name "signature-differs"))
  Name Run _ Target -> (urt.fail Name "signature-error"))

\\ ---------------------------------------------------------------
\\ Case group 4: mutations that must be refused
\\ ---------------------------------------------------------------

(define urt.mut-case
  Name Accepted Expected ->
    (/. Unit (urt.mut-line Name Accepted Expected)))

(define urt.mut-line
  Name Accepted Expected ->
    (if (= Accepted Expected)
        (do (output "MUT|~A|~A~%" Name
              (if Accepted "accepted" "rejected"))
            true)
        (urt.fail Name "acceptance")))

(define urt.accepts?
  Plan Target Evaluator ->
    (urdr.shrink.accept? (urt.e-world) Plan Target Evaluator))

\\ Drop the step at INDEX, whatever it is: the raw transformation, used
\\ here to build candidates the shrinker itself would never propose.
(define urt.drop-at
  Index Plan -> (urdr.shrink.remove-solo Index Plan))

(define urt.drop-pair
  Index Plan -> (urdr.shrink.remove-paired Index Plan))

\\ A withheld transcript entry must fail REPLAY VERIFICATION against the
\\ recorded artifact, with the transcript-truncated code and not a
\\ divergence code: a shorter transcript is evidence about the artifact,
\\ not about the engine.
(define urt.withheld-case
  Name Plan -> (/. Unit (urt.withheld-line Name Plan)))

(define urt.withheld-line
  Name Plan ->
    (urt.withheld-recorded Name Plan
      (urdr.replay.run (urt.e-world) (urdr.shrink.transcript Plan))))

(define urt.withheld-recorded
  Name Plan [ok Run] ->
    (urt.withheld-verify Name
      (urdr.replay.verify (urt.e-world)
        (urdr.shrink.transcript (urt.drop-at 4 Plan))
        (urdr.replay.recorded Run)))
  Name Plan _ -> (urt.fail Name "replay-error"))

(define urt.withheld-verify
  Name [error replay-transcript-truncated _] ->
    (do (output "MUT|~A|replay-transcript-truncated~%" Name) true)
  Name _ -> (urt.fail Name "verify-accepted"))

\\ ---------------------------------------------------------------
\\ Case group 5: fail-closed shrinker rejections
\\ ---------------------------------------------------------------

(define urt.sreject-case
  Name Result Expected ->
    (/. Unit (urt.sreject-line Name Result Expected)))

(define urt.sreject-line
  Name [error Code _] Expected ->
    (if (= Code Expected)
        (do (output "SREJ|~A|~A~%" Name
              (urt.string (urdr.shrink.code-octets Code)))
            true)
        (urt.fail Name "wrong-code"))
  Name _ Expected -> (urt.fail Name "unexpected-ok"))

(define urt.zero-signature
  -> (urt.value-of (urdr.certificate.failure-signature [])))

\\ ---------------------------------------------------------------
\\ Case assembly.
\\ ---------------------------------------------------------------

(define urt.cases
  Exploration Plan Target Result ->
    (urt.concat
      [(urt.plan-cases Plan Exploration)
       (urt.sig-cases Exploration Plan Target)
       [(urt.shr-case "baseline-fail" Result Plan)
        (urt.min-case "baseline-fail" Result Target)]
       (urt.mut-cases Plan Target)
       (urt.trunc-cases)
       (urt.sreject-cases Plan Target)]))

(define urt.plan-cases
  Plan Exploration ->
    [(urt.plan-case "exploration" [ok Plan] ok)
     (urt.plan-case "reject-length"
       (urdr.shrink.plan [(urdr.search.explore.label-advance)]
         (urdr.search.explore.transcript Exploration))
       shrink-plan-length)
     (urt.plan-case "reject-shape" (urdr.shrink.plan 7 7)
       shrink-plan-shape)
     (urt.share-case "self" Plan Plan (urdr.shrink.length Plan))
     (urt.share-case "dropped-head" Plan (urt.drop-at 0 Plan) 0)
     (urt.share-case "dropped-fourth" Plan (urt.drop-at 4 Plan) 4)])

(define urt.sig-cases
  Exploration Plan Target ->
    [(urt.verd-case "exploration"
       (urdr.search.explore.world Exploration))
     (urt.sig-case "exploration" [ok Target])
     (urt.sig-case "empty-failure-set"
       (urdr.certificate.failure-signature []))
     (urt.sig-case "never-only"
       (urt.never-signature
         (urdr.search.explore.world Exploration)))])

\\ Four mutations, each one a way a careless shrinker could accept a
\\ candidate it must refuse.
(define urt.mut-cases
  Plan Target ->
    [(urt.mut-case "unmodified"
       (urt.accepts? Plan Target (urt.evaluator)) true)
     (urt.mut-case "non-persisting"
       (urt.accepts? (urt.drop-pair 4 Plan) Target (urt.evaluator))
       false)
     (urt.mut-case "changed-witness"
       (urt.accepts? (urt.drop-pair 1 Plan) Target (urt.evaluator))
       false)
     (urt.mut-case "truncated-tail"
       (urt.accepts?
         (urt.drop-at (- (urdr.shrink.length Plan) 1) Plan)
         Target (urt.evaluator))
       false)
     (urt.withheld-case "withheld-entry" Plan)])

\\ The truncation fixture (above): the same candidate, judged by the two
\\ rules. `same-failure` is the rule shrink.shen implements.
(define urt.trunc-cases
  -> (let TPlan (urt.t-plan)
          TWorld (urt.value-of
                   (urt.final-world (urdr.shrink.transcript TPlan)))
          Candidate (urt.drop-at 7 TPlan)
       [(urt.verd-case "truncation-full" TWorld)
        (urt.verd-case "truncation-candidate"
          (urt.value-of
            (urt.final-world (urdr.shrink.transcript Candidate))))
        (urt.sig-case "truncation-full" (urt.signature TWorld))
        (urt.sig-case "truncation-candidate"
          (urt.signature
            (urt.value-of
              (urt.final-world (urdr.shrink.transcript Candidate)))))
        (urt.mut-case "truncation-same-failure-rule"
          (urt.accepts? Candidate
            (urt.value-of (urt.signature TWorld)) (urt.evaluator))
          false)
        (urt.mut-case "truncation-any-failure-rule"
          (urt.accepts? Candidate
            (urt.value-of (urt.never-signature TWorld))
            (urt.never-evaluator))
          true)]))

(define urt.sreject-cases
  Plan Target ->
    [(urt.sreject-case "reject-initial"
       (urdr.shrink.minimize [not-a-world] Plan Target (urt.big 4)
         (urt.evaluator))
       shrink-initial)
     (urt.sreject-case "reject-target"
       (urdr.shrink.minimize (urt.e-world) Plan [1 2 3] (urt.big 4)
         (urt.evaluator))
       shrink-target)
     (urt.sreject-case "reject-original"
       (urdr.shrink.minimize (urt.e-world) Plan (urt.zero-signature)
         (urt.big 4) (urt.evaluator))
       shrink-original)
     (urt.sreject-case "reject-evaluator"
       (urdr.shrink.minimize (urt.e-world) Plan Target (urt.big 4)
         (/. W [garbage]))
       shrink-evaluator)
     (urt.sreject-case "reject-sweep-budget"
       (urdr.shrink.minimize (urt.e-world) Plan Target (urdr.int.zero)
         (urt.evaluator))
       shrink-sweep-budget)])

(define urt.run
  -> (let Exploration (urt.value-of (urt.exploration))
          Plan (urt.value-of (urdr.shrink.plan-of Exploration))
          Target (urt.value-of
                   (urt.signature
                     (urdr.search.explore.world Exploration)))
          Result (urdr.shrink.minimize
                   (urt.e-world) Plan Target (urt.big 6)
                   (urt.evaluator))
          Cases (urt.cases Exploration Plan Target Result)
          Ok (urt.run-thunks Cases true)
       (do
         (output "SHRINK CASES: ~A~%" (urt.count Cases))
         (if Ok
             (do (output "ALL PASS~%") true)
             (do (output "SHRINK: FAIL~%") false)))))

(urt.run)
