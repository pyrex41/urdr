\* Run-driver conformance suite (shen/run/run.shen; ADR 0007 D1, D2,
   D5). Fixture models exercise the production step loop end to end at
   small scale: real scenarios, real routing, real properties — no
   marker oracles anywhere. Discovery below means the property engine
   failed a declared liveness property over the recorded fact trace of
   a driver-explored schedule.

   Semantic output lines, in fixture order:

     RUN|quiescent|...        exhausted run, budgets respected
     RUN|discovery|...        discovery attempt + failure signature
     RUN|verdict|...          verdict records driving the signature
     RUN|certificate|...      certificate status + achieved profile
     RUN|deterministic|...    same scenario + seed twice, same digests
     RUN|seed-divergence|...  different seed, different transcript root
     RUN|steps|...            max-steps trip surfaces per attempt
     RUN|cascade|...          cascade limit bound to max-steps (D5)
     RUN|events|...           max-events trip surfaces per attempt
     RUN|reject-property|...  unloadable property fails the whole run
     RUN|reject-model|...     unknown model fails the whole run
     RUN CASES: N
     ALL PASS

   Any internal inconsistency prints a FAIL| line and suppresses the
   ALL PASS marker; shen/tests/run/test.sh additionally compares every
   semantic line against the checked-in golden output. *\

(define urn.eval-forms
  [] -> loaded
  [[load _] | Forms] -> (urn.eval-forms Forms)
  [Form | Forms] ->
    (let Ignored (eval Form)
      (urn.eval-forms Forms)))

(define urn.quiet-load
  File -> (urn.eval-forms (read-file File)))

(urn.quiet-load "shen/protocol/canonical.shen")
(urn.quiet-load "shen/world/integer.shen")
(urn.quiet-load "shen/world/prng.shen")
(urn.quiet-load "shen/world/netkat.shen")
(urn.quiet-load "shen/world/component.shen")
(urn.quiet-load "shen/world/world.shen")
(urn.quiet-load "shen/scenario/scenario.shen")
(urn.quiet-load "shen/world/models/common.shen")
(urn.quiet-load "shen/world/models/mask.shen")
(urn.quiet-load "shen/world/models/net.shen")
(urn.quiet-load "shen/world/models/timer.shen")
(urn.quiet-load "shen/world/models/fault.shen")
(urn.quiet-load "shen/world/models/registry.shen")
(urn.quiet-load "shen/properties/properties.shen")
(urn.quiet-load "shen/world/eventlog.shen")
(urn.quiet-load "shen/world/replay.shen")
(urn.quiet-load "shen/world/certificate.shen")
(urn.quiet-load "shen/search/search.shen")
(urn.quiet-load "shen/run/run.shen")

\\ ---------------------------------------------------------------
\\ Rendering
\\ ---------------------------------------------------------------

(define urn.string
  [] -> ""
  [B | Bs] -> (cn (n->string B) (urn.string Bs)))

(define urn.div16
  N Q -> Q where (< N 16)
  N Q -> (urn.div16 (- N 16) (+ Q 1)))

(define urn.mod16
  N -> N where (< N 16)
  N -> (urn.mod16 (- N 16)))

(define urn.hexdigit
  N -> (n->string (+ 48 N)) where (< N 10)
  N -> (n->string (+ 87 N)))

(define urn.hex
  [] -> ""
  [B | Bs] ->
    (cn (cn (urn.hexdigit (urn.div16 B 0)) (urn.hexdigit (urn.mod16 B)))
        (urn.hex Bs)))

(define urn.k
  Name -> (urdr.canonical.string-bytes Name))

(define urn.s
  Name -> [symbol (urdr.canonical.string-bytes Name)])

(define urn.big
  N -> (urdr.int.raw.from-small N))

(define urn.small
  N -> (urn.small-of (urdr.int.small-of N)))

(define urn.small-of
  [ok N] -> N
  _ -> -1)

(define urn.count
  [] -> 0
  [_ | Xs] -> (+ 1 (urn.count Xs)))

(define urn.fail
  Name Detail ->
    (do (output "FAIL|~A|~A~%" Name Detail) false))

(define urn.both
  true true -> true
  _ _ -> false)

\\ ---------------------------------------------------------------
\\ Fixture models. Each runs inside the crash-aware process wrapper;
\\ each accepts the driver's boot input and its own published
\\ alternatives as inputs (the driver's selection-delivery rule).
\\ ---------------------------------------------------------------

(define urn.boot -> [symbol (urn.k "boot")])

(define urn.state
  Role -> [record [[(urn.k "role") (urn.s Role)]]])

(define urn.seqval
  -> [record [[(urn.k "seq") (urn.big 1)]]])

(define urn.tickval
  N -> [record [[(urn.k "n") (urn.big N)]]])

(define urn.mode
  Name -> [record [[(urn.k "mode") (urn.s Name)]]])

\\ pinger: emits one `ping` fact on boot; absorbs everything else
\\ (including a routed ack) without effect.
(define urn.pinger
  State Event ->
    (urn.pinger-h (urdr.model.common.event-input Event) State))

(define urn.pinger-h
  Input State ->
    (if (= Input (urn.boot))
        [step State [[fact (urn.k "ping") (urn.seqval)]] []]
        [step State [] []]))

\\ acker: on a routed ping it publishes a timing choice — answer now
\\ (`ack`) or give up (`drop`) — and acts on whichever alternative the
\\ driver delivers back. A dropped ack never reaches the trace, which
\\ is exactly what the declared liveness property fails on.
(define urn.acker
  State Event ->
    (urn.acker-h (urdr.model.common.event-input Event) State))

(define urn.acker-h
  Input State ->
    (if (not (= (urdr.model.common.get Input (urn.k "seq")) none))
        [step State []
          (urdr.model.common.choice
            (urn.k "timing")
            [(urn.mode "ack") (urn.mode "drop")])]
        (urn.acker-mode
          (urdr.model.common.symbol-bytes
            (urdr.model.common.get Input (urn.k "mode")))
          State)))

(define urn.acker-mode
  none State -> [step State [] []]
  Bs State ->
    (if (urdr.model.common.same? Bs (urn.k "ack"))
        [step State [[fact (urn.k "ack") (urn.seqval)]] []]
        [step State [[fact (urn.k "gave-up") (urn.mode "drop")]] []]))

\\ echo: re-emits a `tick` fact on boot and on every routed tick, so a
\\ tick->self route recurses one delivery per step until a budget
\\ stops it.
(define urn.echo
  State Event ->
    (urn.echo-h (urdr.model.common.event-input Event) State))

(define urn.echo-h
  Input State ->
    (if (or (= Input (urn.boot))
            (not (= (urdr.model.common.get Input (urn.k "n")) none)))
        [step State [[fact (urn.k "tick") (urn.tickval 1)]] []]
        [step State [] []]))

\\ spammer: emits five routed facts in ONE commit, so the routing
\\ cascade budget trips inside a single step while the step budget
\\ still has room — that separates route-cascade-exceeded from
\\ run-steps-exceeded and proves D5 bound the limit to max-steps
\\ (five deliveries are far below the old fixed 64).
(define urn.spammer
  State Event ->
    (urn.spammer-h (urdr.model.common.event-input Event) State))

(define urn.spammer-h
  Input State ->
    (if (= Input (urn.boot))
        [step State
          [[fact (urn.k "tick") (urn.tickval 1)]
           [fact (urn.k "tick") (urn.tickval 2)]
           [fact (urn.k "tick") (urn.tickval 3)]
           [fact (urn.k "tick") (urn.tickval 4)]
           [fact (urn.k "tick") (urn.tickval 5)]]
          []]
        [step State [] []]))

\\ Model table: ascending strictly by model name.
(define urn.models
  -> [[(urn.k "acker")
       [(/. S E (urn.acker S E)) (/. C B (urn.state "acker"))]]
      [(urn.k "echo")
       [(/. S E (urn.echo S E)) (/. C B (urn.state "echo"))]]
      [(urn.k "pinger")
       [(/. S E (urn.pinger S E)) (/. C B (urn.state "pinger"))]]
      [(urn.k "spammer")
       [(/. S E (urn.spammer S E)) (/. C B (urn.state "spammer"))]]])

\\ ---------------------------------------------------------------
\\ Scenario construction (canonical values; keys ascend).
\\ ---------------------------------------------------------------

(define urn.field
  Name ->
    [record
      [[(urn.k "field") (urn.s Name)]
       [(urn.k "values") [list [(urn.big 1) (urn.big 2)]]]]])

(define urn.vocab
  -> [list [(urn.field "dst") (urn.field "src")]])

(define urn.node
  Address Id ->
    [record
      [[(urn.k "address") (urn.big Address)]
       [(urn.k "id") (urn.s Id)]]])

(define urn.link
  From To ->
    [record
      [[(urn.k "from") (urn.s From)]
       [(urn.k "to") (urn.s To)]]])

(define urn.topo
  -> [record
       [[(urn.k "links") [list [(urn.link "a" "b")]]]
        [(urn.k "nodes") [list [(urn.node 1 "a") (urn.node 2 "b")]]]]])

(define urn.budget
  Events Runs Steps ->
    [record
      [[(urn.k "max-events") (urn.big Events)]
       [(urn.k "max-runs") (urn.big Runs)]
       [(urn.k "max-steps") (urn.big Steps)]]])

(define urn.comp
  Id Model Node ->
    [record
      [[(urn.k "id") (urn.s Id)]
       [(urn.k "kind") (urn.s "process")]
       [(urn.k "model") (urn.s Model)]
       [(urn.k "node") (urn.s Node)]]])

(define urn.route
  Fact From To ->
    [record
      [[(urn.k "fact") (urn.s Fact)]
       [(urn.k "from") (urn.s From)]
       [(urn.k "to") (urn.s To)]]])

(define urn.pattern
  Name Source ->
    [record
      [[(urn.k "name") (urn.s Name)]
       [(urn.k "source") (urn.s Source)]
       [(urn.k "value") [null]]]])

(define urn.liveness
  Id Deadline Pattern ->
    [record
      [[(urn.k "class") (urn.s "liveness")]
       [(urn.k "id") (urn.s Id)]
       [(urn.k "spec")
        [record
          [[(urn.k "deadline") (urn.big Deadline)]
           [(urn.k "pattern") Pattern]]]]]])

(define urn.scn
  Seed Budget Components Routes Properties ->
    [record
      [[(urn.k "budget") Budget]
       [(urn.k "components") [list Components]]
       [(urn.k "determinism") (urn.s "modeled")]
       [(urn.k "faults") [list []]]
       [(urn.k "header-vocabulary") (urn.vocab)]
       [(urn.k "observations") [list []]]
       [(urn.k "properties") [list Properties]]
       [(urn.k "routes") [list Routes]]
       [(urn.k "seed") [bytes Seed]]
       [(urn.k "topology") (urn.topo)]
       [(urn.k "version") (urn.s "scenario/v1")]]])

\\ Chosen so the primary seed discovers at attempt 1 — attempt 0
\\ explores a schedule that answers the ping (PASS, empty signature)
\\ and the loop demonstrably continues — while the second seed
\\ discovers on a different attempt down a different path.
(define urn.seed1 -> (urn.k "run-driver-seed-3"))
(define urn.seed2 -> (urn.k "run-driver-seed-2"))

(define urn.quiescent-scenario
  -> (urn.scn (urn.k "run-quiescent") (urn.budget 4 2 4)
       [(urn.comp "solo" "pinger" "a")]
       []
       []))

\\ The discovery fixture: client boots, emits `ping`; the kernel
\\ routes it to the server; the server publishes the timing choice;
\\ the driver's strategy schedules one alternative; `ack` (routed
\\ back) or `gave-up` lands in the trace; the declared liveness
\\ property (ack from server by logical time 5) passes or fails.
(define urn.disc-scenario
  Seed ->
    (urn.scn Seed (urn.budget 12 6 16)
      [(urn.comp "client" "pinger" "a")
       (urn.comp "server" "acker" "b")]
      [(urn.route "ping" "client" "server")
       (urn.route "ack" "server" "client")]
      [(urn.liveness "ack-on-time" 5 (urn.pattern "ack" "server"))]))

(define urn.steps-scenario
  -> (urn.scn (urn.k "run-steps") (urn.budget 8 2 3)
       [(urn.comp "looper" "echo" "a")]
       [(urn.route "tick" "looper" "looper")]
       []))

(define urn.cascade-scenario
  -> (urn.scn (urn.k "run-cascade") (urn.budget 16 2 4)
       [(urn.comp "storm" "spammer" "a")]
       [(urn.route "tick" "storm" "storm")]
       []))

(define urn.events-scenario
  -> (urn.scn (urn.k "run-events") (urn.budget 2 2 10)
       [(urn.comp "pa" "pinger" "a")
        (urn.comp "pb" "pinger" "a")
        (urn.comp "pc" "pinger" "a")]
       []
       []))

(define urn.bad-property-scenario
  -> (urn.scn (urn.k "run-bad-prop") (urn.budget 4 2 4)
       [(urn.comp "solo" "pinger" "a")]
       []
       [[record
          [[(urn.k "class") (urn.s "liveness")]
           [(urn.k "id") (urn.s "broken")]
           [(urn.k "spec") [record [[(urn.k "wrong") [null]]]]]]]]))

(define urn.ghost-scenario
  -> (urn.scn (urn.k "run-ghost") (urn.budget 4 2 4)
       [(urn.comp "solo" "ghost" "a")]
       []
       []))

\\ ---------------------------------------------------------------
\\ Result helpers
\\ ---------------------------------------------------------------

(define urn.sig-hex
  Verdicts -> (urn.sig-hex-of (urdr.certificate.failure-signature Verdicts)))

(define urn.sig-hex-of
  [ok Sig] -> (urn.hex Sig)
  _ -> "sig-error")

(define urn.codes-string
  [] -> ""
  [[attempt-error _ Code]] -> (urn.string Code)
  [[attempt-error _ Code] | Rest] ->
    (cn (urn.string Code) (cn "," (urn.codes-string Rest)))
  _ -> "codes-shape")

(define urn.root-hex
  Cert -> (urn.hex (urdr.replay.run-transcript-root
                     (urdr.certificate.run Cert))))

(define urn.triple
  [ok [discovered Attempt _ _ Verdicts Cert]] ->
    [triple (urn.small Attempt)
            (urn.sig-hex Verdicts)
            (urn.root-hex Cert)]
  _ -> [triple -1 "err" "err"])

\\ ---------------------------------------------------------------
\\ Case 1: trivial quiescent scenario — exhausted, zero discoveries,
\\ budgets respected, and the tried-summary is not information-free.
\\ ---------------------------------------------------------------

(define urn.quiescent-case
  -> (/. Unit
       (urn.quiescent-h
         (urdr.run.execute (urn.quiescent-scenario) (urn.models)))))

(define urn.quiescent-h
  [ok [exhausted Attempts [tried A2 Distinct Sigs Errors]]] ->
    (do
      (output "RUN|quiescent|exhausted|attempts=~A|distinct=~A|errors=~A|sig=~A~%"
        (urn.small Attempts)
        (urn.small Distinct)
        (urn.count Errors)
        (urn.hex (hd Sigs)))
      (if (and (= (urn.small Attempts) 2)
               (and (= (urn.small Distinct) 1)
                    (= (urn.count Errors) 0)))
          true
          (urn.fail "quiescent" "summary-values")))
  _ -> (urn.fail "quiescent" "unexpected-shape"))

\\ ---------------------------------------------------------------
\\ Case 2: genuine discovery via the property engine.
\\ ---------------------------------------------------------------

(define urn.field-string
  [some [symbol Bs]] -> (urn.string Bs)
  _ -> "?")

(define urn.witness-kind
  [some [symbol Bs]] -> (urn.string Bs)
  [some [record _]] -> "record"
  _ -> "?")

(define urn.verdict-line
  Value ->
    (do
      (output "RUN|verdict|~A|~A|~A~%"
        (urn.field-string
          (urdr.certificate.field-of (urdr.properties.n.property) Value))
        (urn.field-string
          (urdr.certificate.field-of (urdr.properties.n.result) Value))
        (urn.witness-kind
          (urdr.certificate.field-of (urdr.properties.n.witness) Value)))
      true))

(define urn.verdict-lines
  [] -> true
  [V | Rest] ->
    (let Ok (urn.verdict-line V)
      (urn.verdict-lines Rest)))

(define urn.disc-case
  -> (/. Unit
       (urn.disc-h
         (urdr.run.execute (urn.disc-scenario (urn.seed1)) (urn.models)))))

(define urn.disc-h
  [ok [discovered Attempt Seed Transcript Verdicts Cert]] ->
    (let A (output "RUN|discovery|attempt=~A|sig=~A~%"
             (urn.small Attempt) (urn.sig-hex Verdicts))
         B (urn.verdict-lines Verdicts)
         Status (urn.string (urdr.certificate.status Cert))
         Profile (urn.string (urdr.certificate.achieved-profile Cert))
         C (output "RUN|certificate|status=~A|profile=~A~%" Status Profile)
      (if (and (= Status "FAIL") (= Profile "modeled-d1-analog"))
          true
          (urn.fail "discovery" "certificate-status")))
  [error Code Detail] -> (urn.fail "discovery" (urn.string Code))
  _ -> (urn.fail "discovery" "unexpected-shape"))

\\ ---------------------------------------------------------------
\\ Case 3-4: determinism. Same scenario + seed twice must reproduce
\\ the discovery digests exactly; a different seed must produce a
\\ different transcript (the recorded draw coordinates embed the
\\ seed, so equality would mean the transcript did not witness the
\\ run).
\\ ---------------------------------------------------------------

(define urn.det-case
  -> (/. Unit
       (urn.det-h
         (urn.triple
           (urdr.run.execute (urn.disc-scenario (urn.seed1)) (urn.models)))
         (urn.triple
           (urdr.run.execute (urn.disc-scenario (urn.seed1)) (urn.models))))))

(define urn.det-h
  [triple A S R] [triple A2 S2 R2] ->
    (let Match (and (= A A2) (and (= S S2) (= R R2)))
      (do
        (output "RUN|deterministic|match=~A|root=~A~%" Match R)
        (if (and Match (not (= R "err")))
            true
            (urn.fail "deterministic" "mismatch")))))

(define urn.seed-case
  -> (/. Unit
       (urn.seed-h
         (urn.triple
           (urdr.run.execute (urn.disc-scenario (urn.seed1)) (urn.models)))
         (urn.triple
           (urdr.run.execute (urn.disc-scenario (urn.seed2)) (urn.models))))))

(define urn.seed-h
  [triple _ _ R1] [triple _ _ R2] ->
    (let Differs (not (= R1 R2))
      (do
        (output "RUN|seed-divergence|differs=~A~%" Differs)
        (if (and Differs
                 (and (not (= R1 "err")) (not (= R2 "err"))))
            true
            (urn.fail "seed-divergence" "identical-or-error")))))

\\ ---------------------------------------------------------------
\\ Cases 5-7: budget trips. Every attempt aborts, so the run reports
\\ run-all-attempts-failed with the per-attempt codes in the summary
\\ — a budget trip fails the attempt, never crashes the driver.
\\ ---------------------------------------------------------------

(define urn.budget-case
  Name Scenario Expected ->
    (/. Unit
      (urn.budget-h
        Name Expected (urdr.run.execute Scenario (urn.models)))))

(define urn.budget-h
  Name Expected [error Code [tried Attempts Distinct Sigs Errors]] ->
    (let Codes (urn.codes-string Errors)
      (do
        (output "RUN|~A|~A|attempts=~A|codes=~A~%"
          Name (urn.string Code) (urn.small Attempts) Codes)
        (if (and (= (urn.string Code) "run-all-attempts-failed")
                 (= Codes (cn Expected (cn "," Expected))))
            true
            (urn.fail Name "wrong-codes"))))
  Name Expected _ -> (urn.fail Name "unexpected-shape"))

\\ ---------------------------------------------------------------
\\ Cases 8-9: driver rejections before any reduction. The error
\\ return carries the loading stage's own code and a [null] detail —
\\ no tried-summary, because no attempt ever started.
\\ ---------------------------------------------------------------

(define urn.reject-case
  Name Scenario Expected ->
    (/. Unit
      (urn.reject-h
        Name Expected (urdr.run.execute Scenario (urn.models)))))

(define urn.reject-h
  Name Expected [error Code [null]] ->
    (do
      (output "RUN|~A|rejected|~A~%" Name (urn.string Code))
      (if (= (urn.string Code) Expected)
          true
          (urn.fail Name "wrong-code")))
  Name Expected _ -> (urn.fail Name "unexpected-shape"))

\\ ---------------------------------------------------------------
\\ Driver
\\ ---------------------------------------------------------------

(define urn.run-thunks
  [] Ok -> Ok
  [T | Ts] Ok ->
    (let R (T 0)
      (urn.run-thunks Ts (if R Ok false))))

(define urn.cases
  -> [(urn.quiescent-case)
      (urn.disc-case)
      (urn.det-case)
      (urn.seed-case)
      (urn.budget-case "steps" (urn.steps-scenario)
        "run-steps-exceeded")
      (urn.budget-case "cascade" (urn.cascade-scenario)
        "route-cascade-exceeded")
      (urn.budget-case "events" (urn.events-scenario)
        "run-events-exceeded")
      (urn.reject-case "reject-property" (urn.bad-property-scenario)
        "properties-liveness-spec-shape")
      (urn.reject-case "reject-model" (urn.ghost-scenario)
        "registry-unknown-model")])

(define urn.run
  -> (let Cases (urn.cases)
          Ok (urn.run-thunks Cases true)
       (do
         (output "RUN CASES: ~A~%" (urn.count Cases))
         (if Ok
             (do (output "ALL PASS~%") true)
             (do (output "RUN: FAIL~%") false)))))

(urn.run)
