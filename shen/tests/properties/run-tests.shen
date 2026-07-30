\* Wave D conformance suite: deterministic property evaluators and
   canonical verdicts (SPEC.md 18.1, shen/properties/properties.shen).

   Semantic output lines, in fixture order:

     PROP|NAME|RESULT|HEX     a verdict: PASS/FAIL plus the canonical
                              verdict frame in lowercase hex
     SLOT|NAME|HEX            the same verdict projected onto the world
                              verdicts slot and rendered by
                              urdr.world.verdict-value
     MUT|NAME|BEFORE|AFTER    a mutation flipped the verdict
     LOAD|NAME|CODE           a property declaration rejected at load
     TRACE|NAME|CODE          a trace rejected before any evaluation
     PROPERTIES CASES: N
     ALL PASS

   Any internal inconsistency prints a FAIL| line and suppresses the
   ALL PASS marker; shen/tests/properties/test.sh additionally compares
   every semantic line against the checked-in golden output on each of
   the four required ports. *\

(define upt.eval-forms
  [] -> loaded
  [[load _] | Forms] -> (upt.eval-forms Forms)
  [Form | Forms] ->
    (let Ignored (eval Form)
      (upt.eval-forms Forms)))

(define upt.quiet-load
  File -> (upt.eval-forms (read-file File)))

(upt.quiet-load "shen/protocol/canonical.shen")
(upt.quiet-load "shen/world/integer.shen")
(upt.quiet-load "shen/world/prng.shen")
(upt.quiet-load "shen/world/component.shen")
(upt.quiet-load "shen/world/world.shen")
(upt.quiet-load "shen/properties/properties.shen")

\\ ---------------------------------------------------------------
\\ Rendering helpers. Nothing here is semantics; it exists so that a
\\ divergence localises to one named line.
\\ ---------------------------------------------------------------

(define upt.string
  [] -> ""
  [B | Bs] -> (cn (n->string B) (upt.string Bs)))

(define upt.div16
  N Q -> Q where (< N 16)
  N Q -> (upt.div16 (- N 16) (+ Q 1)))

(define upt.mod16
  N -> N where (< N 16)
  N -> (upt.mod16 (- N 16)))

(define upt.hexdigit
  N -> (n->string (+ 48 N)) where (< N 10)
  N -> (n->string (+ 87 N)))

(define upt.hex
  [] -> ""
  [B | Bs] ->
    (cn (cn (upt.hexdigit (upt.div16 B 0)) (upt.hexdigit (upt.mod16 B)))
        (upt.hex Bs)))

(define upt.bytes
  S -> (urdr.canonical.string-bytes S))

(define upt.big
  N -> (hd (tl (urdr.int.from-small N))))

\\ ---------------------------------------------------------------
\\ Canonical constructors for the three spec schemas.
\\ ---------------------------------------------------------------

(define upt.node
  Op Args ->
    [record
      [[(urdr.properties.n.args) [list Args]]
       [(urdr.properties.n.op) [symbol Op]]]])

(define upt.t-this
  -> (upt.node (urdr.properties.n.this) []))

(define upt.t-const
  V -> (upt.node (urdr.properties.n.const) [V]))

(define upt.t-fact
  Name -> (upt.node (urdr.properties.n.fact) [[symbol (upt.bytes Name)]]))

(define upt.t-fact-of
  Name Source ->
    (upt.node (urdr.properties.n.fact-of)
              [[symbol (upt.bytes Name)] [symbol (upt.bytes Source)]]))

(define upt.t-project
  Term Index ->
    (upt.node (urdr.properties.n.project) [Term (upt.big Index)]))

(define upt.t-key
  Term Key ->
    (upt.node (urdr.properties.n.key)
              [Term [symbol (upt.bytes Key)]]))

(define upt.p-true
  -> (upt.node (urdr.properties.n.true) []))

(define upt.p-false
  -> (upt.node (urdr.properties.n.false) []))

(define upt.p-cmp
  Op A B -> (upt.node Op [A B]))

(define upt.p-defined
  T -> (upt.node (urdr.properties.n.defined) [T]))

(define upt.p-not
  P -> (upt.node (urdr.properties.n.not) [P]))

(define upt.p-and
  P Q -> (upt.node (urdr.properties.n.and) [P Q]))

(define upt.p-or
  P Q -> (upt.node (urdr.properties.n.or) [P Q]))

(define upt.pattern
  Name Source Value ->
    [record
      [[(urdr.properties.n.name) [symbol (upt.bytes Name)]]
       [(urdr.properties.n.source) Source]
       [(urdr.properties.n.value) Value]]])

(define upt.pat
  Name -> (upt.pattern Name [null] [null]))

(define upt.pat-of
  Name Source ->
    (upt.pattern Name [symbol (upt.bytes Source)] [null]))

(define upt.pat-val
  Name Pred -> (upt.pattern Name [null] Pred))

(define upt.inv-spec
  Points Pred ->
    [record
      [[(urdr.properties.n.points) [list (upt.symbols Points)]]
       [(urdr.properties.n.pred) Pred]]])

(define upt.symbols
  [] -> []
  [S | Ss] -> [[symbol (upt.bytes S)] | (upt.symbols Ss)])

(define upt.tmp-spec
  Form Args ->
    [record
      [[(urdr.properties.n.args) [list Args]]
       [(urdr.properties.n.form) [symbol (upt.bytes Form)]]]])

(define upt.live-spec
  Deadline Pattern ->
    [record
      [[(urdr.properties.n.deadline) (upt.big Deadline)]
       [(urdr.properties.n.pattern) Pattern]]])

(define upt.property
  Class Id Spec -> [property (upt.bytes Class) (upt.bytes Id) Spec])

(define upt.invariant
  Id Points Pred ->
    (upt.property "invariant" Id (upt.inv-spec Points Pred)))

(define upt.temporal
  Id Form Args ->
    (upt.property "temporal" Id (upt.tmp-spec Form Args)))

(define upt.liveness
  Id Deadline Pattern ->
    (upt.property "liveness" Id (upt.live-spec Deadline Pattern)))

\\ ---------------------------------------------------------------
\\ Hand-built canonical traces. Entry records are exactly the shape
\\ urdr.world.fact-value stamps, so a hand-built trace and a
\\ reducer-produced one are the same object.
\\ ---------------------------------------------------------------

(define upt.entry
  Id At Source Name Value ->
    [record
      [[(urdr.properties.n.component) [bytes (upt.bytes Source)]]
       [(urdr.properties.n.event-id) (upt.big Id)]
       [(urdr.properties.n.name) [symbol (upt.bytes Name)]]
       [(urdr.properties.n.time) (upt.big At)]
       [(urdr.properties.n.type) [symbol (urdr.properties.n.fact)]]
       [(urdr.properties.n.value) Value]]])

(define upt.state-value
  Phase Retries ->
    [record
      [[(upt.bytes "phase") [symbol (upt.bytes Phase)]]
       [(upt.bytes "retries") (upt.big Retries)]]])

\\ T0: the empty trace, for the empty-stream boundary cases.
(define upt.t0
  -> [trace []])

\\ T1: the main fixture. Entries 2 and 3 share one event id: a single
\\ component step emitting two facts, which is why trace order is
\\ non-decreasing rather than strictly increasing in (time, event-id).
\\
\\   idx id time source name   value
\\   0   1  1    net    sent   1
\\   1   2  2    net    drop   1
\\   2   3  4    net    queue  [10 20]
\\   3   3  4    net    recv   1
\\   4   4  4    proc   state  {phase ready, retries 0}
\\   5   5  7    proc   state  {phase done,  retries 2}
\\   6   6  9    net    sent   2
(define upt.t1
  -> [trace
       [(upt.entry 1 1 "net" "sent" (upt.big 1))
        (upt.entry 2 2 "net" "drop" (upt.big 1))
        (upt.entry 3 4 "net" "queue"
          [list [(upt.big 10) (upt.big 20)]])
        (upt.entry 3 4 "net" "recv" (upt.big 1))
        (upt.entry 4 4 "proc" "state" (upt.state-value "ready" 0))
        (upt.entry 5 7 "proc" "state" (upt.state-value "done" 2))
        (upt.entry 6 9 "net" "sent" (upt.big 2))]])

\\ T2: request/acknowledge pairs for the window cases.
\\
\\   idx id time source name value
\\   0   1  0    proc   req   1
\\   1   2  3    proc   ack   1
\\   2   3  5    proc   req   2
\\   3   4  8    proc   ack   2
\\   4   5  9    proc   req   3     <- obligation never discharged
(define upt.t2
  -> [trace
       [(upt.entry 1 0 "proc" "req" (upt.big 1))
        (upt.entry 2 3 "proc" "ack" (upt.big 1))
        (upt.entry 3 5 "proc" "req" (upt.big 2))
        (upt.entry 4 8 "proc" "ack" (upt.big 2))
        (upt.entry 5 9 "proc" "req" (upt.big 3))]])

\\ T3: T2 without the trailing unanswered request.
(define upt.t3
  -> [trace
       [(upt.entry 1 0 "proc" "req" (upt.big 1))
        (upt.entry 2 3 "proc" "ack" (upt.big 1))
        (upt.entry 3 5 "proc" "req" (upt.big 2))
        (upt.entry 4 8 "proc" "ack" (upt.big 2))]])

\\ Declared observation points, strictly ascending by id as the scenario
\\ DSL produces them. Their logical times are deliberately NOT ascending
\\ in that order, so the (at, id) evaluation order is load-bearing.
(define upt.obs
  -> [[observation (upt.big 2) (upt.bytes "p-early")]
      [observation (upt.big 9) (upt.bytes "p-late")]
      [observation (upt.big 4) (upt.bytes "p-mid")]])

\\ ---------------------------------------------------------------
\\ Case drivers.
\\ ---------------------------------------------------------------

(define upt.result-name
  pass -> "PASS"
  fail -> "FAIL")

(define upt.verdict-of
  Property Observations Trace ->
    (upt.verdict-of-h
      (urdr.properties.load Property Observations) Trace))

(define upt.verdict-of-h
  [error E] _ -> [error E]
  [ok Loaded] Trace -> (urdr.properties.evaluate Loaded Trace))

\\ Every case constructor returns a THUNK, and upt.run applies them one at
\\ a time. Building a list of already-evaluated calls would leave the
\\ printing order to the port: shen-lua evaluates list-literal elements
\\ right to left where the other three go left to right, which this suite
\\ caught on its first four-port run. Element evaluation order is not part
\\ of the portable subset, so no semantic output may depend on it.

\\ An evaluation case: the verdict must exist, and its canonical frame is
\\ pinned in full.
(define upt.case
  Name Property Observations Trace ->
    (/. Unit
      (upt.case-h Name (upt.verdict-of Property Observations Trace))))

(define upt.case-h
  Name [error E] ->
    (do (output "FAIL|~A|~A~%" Name E) false)
  Name [ok Verdict] ->
    (upt.case-frame
      Name
      Verdict
      (urdr.canonical.encode-frame
        (urdr.properties.verdict-value Verdict))))

(define upt.case-frame
  Name _ [error E] ->
    (do (output "FAIL|~A|encode|~A~%" Name E) false)
  Name Verdict [ok Bytes] ->
    (do
      (output "PROP|~A|~A|~A~%"
              Name
              (upt.result-name (urdr.properties.verdict-result Verdict))
              (upt.hex Bytes))
      true))

\\ The world verdicts slot projection, rendered by the world's own
\\ urdr.world.verdict-value so the compatibility is demonstrated rather
\\ than asserted.
(define upt.slot-case
  Name Property Observations Trace ->
    (/. Unit
      (upt.slot-h Name (upt.verdict-of Property Observations Trace))))

(define upt.slot-h
  Name [error E] ->
    (do (output "FAIL|~A|~A~%" Name E) false)
  Name [ok Verdict] ->
    (upt.slot-frame
      Name
      (urdr.canonical.encode-frame
        (urdr.world.verdict-value
          (urdr.properties.world-verdict Verdict)))))

(define upt.slot-frame
  Name [error E] ->
    (do (output "FAIL|~A|slot|~A~%" Name E) false)
  Name [ok Bytes] ->
    (do (output "SLOT|~A|~A~%" Name (upt.hex Bytes)) true))

\\ A mutation case: two specs differing in one field must not agree.
(define upt.mutation
  Name PropertyA PropertyB Observations Trace ->
    (/. Unit
      (upt.mutation-h
        Name
        (upt.verdict-of PropertyA Observations Trace)
        (upt.verdict-of PropertyB Observations Trace))))

(define upt.mutation-h
  Name [error E] _ -> (do (output "FAIL|~A|a|~A~%" Name E) false)
  Name _ [error E] -> (do (output "FAIL|~A|b|~A~%" Name E) false)
  Name [ok A] [ok B] ->
    (let RA (urdr.properties.verdict-result A)
         RB (urdr.properties.verdict-result B)
      (if (= RA RB)
          (do (output "FAIL|~A|did-not-flip|~A~%" Name
                      (upt.result-name RA))
              false)
          (do (output "MUT|~A|~A|~A~%"
                      Name (upt.result-name RA) (upt.result-name RB))
              true))))

\\ A load-rejection case: the declaration must fail closed with a stable
\\ code before any evaluation is attempted.
(define upt.reject
  Name Property Observations ->
    (/. Unit
      (upt.reject-h Name (urdr.properties.load Property Observations))))

(define upt.reject-h
  Name [error Code] ->
    (do (output "LOAD|~A|~A~%" Name Code) true)
  Name _ ->
    (do (output "FAIL|~A|unexpected-load-ok~%" Name) false))

(define upt.reject-all
  Name Properties Observations ->
    (/. Unit
      (upt.reject-h
        Name (urdr.properties.load-all Properties Observations))))

\\ A trace-rejection case.
(define upt.bad-trace
  Name Trace ->
    (/. Unit
      (upt.bad-trace-h Name (urdr.properties.check-trace Trace))))

(define upt.bad-trace-h
  Name [error Code] ->
    (do (output "TRACE|~A|~A~%" Name Code) true)
  Name _ ->
    (do (output "FAIL|~A|unexpected-trace-ok~%" Name) false))

\\ ---------------------------------------------------------------
\\ Invariant cases.
\\ ---------------------------------------------------------------

(define upt.retries-le
  N -> (upt.p-cmp (urdr.properties.n.le)
                  (upt.t-key (upt.t-fact "state") "retries")
                  (upt.t-const (upt.big N))))

(define upt.phase-is
  P -> (upt.p-cmp (urdr.properties.n.eq)
                  (upt.t-key (upt.t-fact "state") "phase")
                  (upt.t-const [symbol (upt.bytes P)])))

(define upt.invariant-cases
  -> [(upt.case "inv-true"
        (upt.invariant "i-true" ["p-mid"] (upt.p-true))
        (upt.obs) (upt.t1))
      (upt.case "inv-false"
        (upt.invariant "i-false" ["p-mid"] (upt.p-false))
        (upt.obs) (upt.t1))
      \\ p-early (t=2) has no state fact yet: the prefix decides.
      (upt.case "inv-retries-early-fail"
        (upt.invariant "i-r0" ["p-early" "p-late" "p-mid"]
          (upt.retries-le 3))
        (upt.obs) (upt.t1))
      \\ Points are evaluated in (at, id) order: p-mid (t=4) then
      \\ p-late (t=9), not in the order they are spelled.
      (upt.case "inv-retries-ok"
        (upt.invariant "i-r1" ["p-late" "p-mid"] (upt.retries-le 3))
        (upt.obs) (upt.t1))
      (upt.case "inv-retries-boundary"
        (upt.invariant "i-r2" ["p-late"] (upt.retries-le 2))
        (upt.obs) (upt.t1))
      (upt.case "inv-retries-over"
        (upt.invariant "i-r3" ["p-late"] (upt.retries-le 1))
        (upt.obs) (upt.t1))
      (upt.case "inv-phase-done"
        (upt.invariant "i-p0" ["p-late"] (upt.phase-is "done"))
        (upt.obs) (upt.t1))
      (upt.case "inv-phase-mid"
        (upt.invariant "i-p1" ["p-mid"] (upt.phase-is "done"))
        (upt.obs) (upt.t1))
      \\ Undefined is fail-closed on both polarities: eq and ne are both
      \\ false, so the conjunction of their negations holds.
      (upt.case "inv-undefined-both-false"
        (upt.invariant "i-u0" ["p-early"]
          (upt.p-and
            (upt.p-not (upt.p-cmp (urdr.properties.n.eq)
                                  (upt.t-fact "state")
                                  (upt.t-const (upt.big 0))))
            (upt.p-not (upt.p-cmp (urdr.properties.n.ne)
                                  (upt.t-fact "state")
                                  (upt.t-const (upt.big 0))))))
        (upt.obs) (upt.t1))
      (upt.case "inv-defined-absent"
        (upt.invariant "i-d0" ["p-early"]
          (upt.p-defined (upt.t-fact "state")))
        (upt.obs) (upt.t1))
      (upt.case "inv-defined-present"
        (upt.invariant "i-d1" ["p-mid"]
          (upt.p-defined (upt.t-fact "state")))
        (upt.obs) (upt.t1))
      (upt.case "inv-project"
        (upt.invariant "i-j0" ["p-mid"]
          (upt.p-cmp (urdr.properties.n.eq)
                     (upt.t-project (upt.t-fact "queue") 1)
                     (upt.t-const (upt.big 20))))
        (upt.obs) (upt.t1))
      (upt.case "inv-project-out-of-range"
        (upt.invariant "i-j1" ["p-mid"]
          (upt.p-cmp (urdr.properties.n.eq)
                     (upt.t-project (upt.t-fact "queue") 5)
                     (upt.t-const (upt.big 20))))
        (upt.obs) (upt.t1))
      (upt.case "inv-fact-of"
        (upt.invariant "i-f0" ["p-late"]
          (upt.p-cmp (urdr.properties.n.eq)
                     (upt.t-key (upt.t-fact-of "state" "proc") "phase")
                     (upt.t-const [symbol (upt.bytes "done")])))
        (upt.obs) (upt.t1))
      (upt.case "inv-fact-of-wrong-source"
        (upt.invariant "i-f1" ["p-late"]
          (upt.p-defined (upt.t-fact-of "state" "net")))
        (upt.obs) (upt.t1))
      (upt.case "inv-or-not"
        (upt.invariant "i-o0" ["p-mid"]
          (upt.p-or (upt.p-false) (upt.p-not (upt.p-false))))
        (upt.obs) (upt.t1))
      (upt.case "inv-gt-non-integer"
        (upt.invariant "i-g0" ["p-mid"]
          (upt.p-cmp (urdr.properties.n.gt)
                     (upt.t-fact "state")
                     (upt.t-const (upt.big 0))))
        (upt.obs) (upt.t1))
      \\ Boundary: the empty stream. A tautology still passes.
      (upt.case "inv-empty-true"
        (upt.invariant "i-e0" ["p-mid"] (upt.p-true))
        (upt.obs) (upt.t0))
      \\ Boundary: the empty stream. Any real invariant FAILS, with a
      \\ witness that names the point and carries [null] for the event
      \\ coordinates, because there is no entry to point at.
      (upt.case "inv-empty-comparison"
        (upt.invariant "i-e1" ["p-mid"]
          (upt.p-cmp (urdr.properties.n.eq)
                     (upt.t-fact "sent")
                     (upt.t-const (upt.big 1))))
        (upt.obs) (upt.t0))
      \\ `this` is undefined outside a pattern.
      (upt.case "inv-this-outside-pattern"
        (upt.invariant "i-t0" ["p-mid"]
          (upt.p-defined (upt.t-this)))
        (upt.obs) (upt.t1))])

\\ ---------------------------------------------------------------
\\ Temporal cases.
\\ ---------------------------------------------------------------

(define upt.temporal-cases
  -> [(upt.case "before-ok"
        (upt.temporal "t-b0" "before" [(upt.pat "sent") (upt.pat "recv")])
        (upt.obs) (upt.t1))
      (upt.case "before-wrong-order"
        (upt.temporal "t-b1" "before" [(upt.pat "recv") (upt.pat "sent")])
        (upt.obs) (upt.t1))
      \\ Strong `before`: a missing consequent is a FAIL, never a
      \\ vacuous pass.
      (upt.case "before-missing-b"
        (upt.temporal "t-b2" "before"
          [(upt.pat "sent") (upt.pat "nosuch")])
        (upt.obs) (upt.t1))
      (upt.case "before-missing-a"
        (upt.temporal "t-b3" "before"
          [(upt.pat "nosuch") (upt.pat "recv")])
        (upt.obs) (upt.t1))
      \\ One entry matching both patterns is not strictly before itself.
      (upt.case "before-same-entry"
        (upt.temporal "t-b4" "before"
          [(upt.pat-val "sent"
             (upt.p-cmp (urdr.properties.n.eq)
                        (upt.t-this) (upt.t-const (upt.big 1))))
           (upt.pat-val "sent"
             (upt.p-cmp (urdr.properties.n.eq)
                        (upt.t-this) (upt.t-const (upt.big 1))))])
        (upt.obs) (upt.t1))
      \\ Boundary: the empty stream.
      (upt.case "before-empty"
        (upt.temporal "t-b5" "before"
          [(upt.pat "sent") (upt.pat "recv")])
        (upt.obs) (upt.t0))
      \\ Window exactly met at both antecedents, then an obligation the
      \\ finite trace never discharges: FAIL on the last request.
      (upt.case "ae-window-3"
        (upt.temporal "t-a0" "always-eventually"
          [(upt.pat "req") (upt.pat "ack") (upt.big 3)])
        (upt.obs) (upt.t2))
      \\ Same trace, window one shorter: the first obligation already
      \\ fails.
      (upt.case "ae-window-2"
        (upt.temporal "t-a1" "always-eventually"
          [(upt.pat "req") (upt.pat "ack") (upt.big 2)])
        (upt.obs) (upt.t2))
      (upt.case "ae-window-0"
        (upt.temporal "t-a2" "always-eventually"
          [(upt.pat "req") (upt.pat "ack") (upt.big 0)])
        (upt.obs) (upt.t2))
      \\ Every obligation discharged: PASS with no witness.
      (upt.case "ae-all-discharged"
        (upt.temporal "t-a3" "always-eventually"
          [(upt.pat "req") (upt.pat "ack") (upt.big 3)])
        (upt.obs) (upt.t3))
      \\ Boundary: vacuous antecedent. PASS, marked `vacuous`.
      (upt.case "ae-vacuous"
        (upt.temporal "t-a4" "always-eventually"
          [(upt.pat "nosuch") (upt.pat "ack") (upt.big 3)])
        (upt.obs) (upt.t2))
      \\ Boundary: the empty stream is a vacuous antecedent too.
      (upt.case "ae-empty"
        (upt.temporal "t-a5" "always-eventually"
          [(upt.pat "req") (upt.pat "ack") (upt.big 3)])
        (upt.obs) (upt.t0))
      (upt.case "never-absent"
        (upt.temporal "t-n0" "never" [(upt.pat "nosuch")])
        (upt.obs) (upt.t1))
      (upt.case "never-present"
        (upt.temporal "t-n1" "never" [(upt.pat "drop")])
        (upt.obs) (upt.t1))
      \\ Boundary: the empty stream satisfies a safety property.
      (upt.case "never-empty"
        (upt.temporal "t-n2" "never" [(upt.pat "sent")])
        (upt.obs) (upt.t0))
      \\ Source filtering: `sent` is only ever emitted by net.
      (upt.case "never-wrong-source"
        (upt.temporal "t-n3" "never" [(upt.pat-of "sent" "proc")])
        (upt.obs) (upt.t1))
      (upt.case "never-right-source"
        (upt.temporal "t-n4" "never" [(upt.pat-of "sent" "net")])
        (upt.obs) (upt.t1))])

\\ ---------------------------------------------------------------
\\ Liveness cases.
\\ ---------------------------------------------------------------

(define upt.liveness-cases
  -> [\\ Boundary: the deadline is exactly met and the bound is
      \\ inclusive, so this PASSES.
      (upt.case "live-deadline-exact"
        (upt.liveness "l-0" 4 (upt.pat "recv"))
        (upt.obs) (upt.t1))
      \\ One less: the event happened, but late. FAIL, and the witness
      \\ still names the late event.
      (upt.case "live-deadline-missed"
        (upt.liveness "l-1" 3 (upt.pat "recv"))
        (upt.obs) (upt.t1))
      (upt.case "live-generous"
        (upt.liveness "l-2" 100 (upt.pat "recv"))
        (upt.obs) (upt.t1))
      \\ Nothing ever matched: FAIL with no witness, not with a late one.
      (upt.case "live-never-occurs"
        (upt.liveness "l-3" 100 (upt.pat "nosuch"))
        (upt.obs) (upt.t1))
      \\ Boundary: the empty stream.
      (upt.case "live-empty"
        (upt.liveness "l-4" 100 (upt.pat "recv"))
        (upt.obs) (upt.t0))
      \\ A value predicate selects the second `sent`, at time 9.
      (upt.case "live-value-exact"
        (upt.liveness "l-5" 9
          (upt.pat-val "sent"
            (upt.p-cmp (urdr.properties.n.eq)
                       (upt.t-this) (upt.t-const (upt.big 2)))))
        (upt.obs) (upt.t1))
      (upt.case "live-value-late"
        (upt.liveness "l-6" 8
          (upt.pat-val "sent"
            (upt.p-cmp (urdr.properties.n.eq)
                       (upt.t-this) (upt.t-const (upt.big 2)))))
        (upt.obs) (upt.t1))
      (upt.case "live-source-filtered"
        (upt.liveness "l-7" 100 (upt.pat-of "recv" "proc"))
        (upt.obs) (upt.t1))])

\\ ---------------------------------------------------------------
\\ Mutation cases: one changed field must flip the verdict.
\\ ---------------------------------------------------------------

(define upt.mutation-cases
  -> [(upt.mutation "mut-deadline"
        (upt.liveness "m-0" 4 (upt.pat "recv"))
        (upt.liveness "m-0" 3 (upt.pat "recv"))
        (upt.obs) (upt.t1))
      (upt.mutation "mut-window"
        (upt.temporal "m-1" "always-eventually"
          [(upt.pat "req") (upt.pat "ack") (upt.big 3)])
        (upt.temporal "m-1" "always-eventually"
          [(upt.pat "req") (upt.pat "ack") (upt.big 2)])
        (upt.obs) (upt.t3))
      (upt.mutation "mut-pattern-name"
        (upt.temporal "m-2" "never" [(upt.pat "nosuch")])
        (upt.temporal "m-2" "never" [(upt.pat "drop")])
        (upt.obs) (upt.t1))
      (upt.mutation "mut-pattern-source"
        (upt.temporal "m-3" "never" [(upt.pat-of "sent" "proc")])
        (upt.temporal "m-3" "never" [(upt.pat-of "sent" "net")])
        (upt.obs) (upt.t1))
      (upt.mutation "mut-pattern-value"
        (upt.liveness "m-4" 100
          (upt.pat-val "sent"
            (upt.p-cmp (urdr.properties.n.eq)
                       (upt.t-this) (upt.t-const (upt.big 2)))))
        (upt.liveness "m-4" 100
          (upt.pat-val "sent"
            (upt.p-cmp (urdr.properties.n.eq)
                       (upt.t-this) (upt.t-const (upt.big 3)))))
        (upt.obs) (upt.t1))
      (upt.mutation "mut-invariant-constant"
        (upt.invariant "m-5" ["p-late"] (upt.retries-le 2))
        (upt.invariant "m-5" ["p-late"] (upt.retries-le 1))
        (upt.obs) (upt.t1))
      (upt.mutation "mut-invariant-point"
        (upt.invariant "m-6" ["p-late"] (upt.phase-is "done"))
        (upt.invariant "m-6" ["p-mid"] (upt.phase-is "done"))
        (upt.obs) (upt.t1))
      (upt.mutation "mut-before-order"
        (upt.temporal "m-7" "before"
          [(upt.pat "sent") (upt.pat "recv")])
        (upt.temporal "m-7" "before"
          [(upt.pat "recv") (upt.pat "sent")])
        (upt.obs) (upt.t1))])

\\ ---------------------------------------------------------------
\\ World verdicts-slot projection.
\\ ---------------------------------------------------------------

(define upt.slot-cases
  -> [(upt.slot-case "slot-pass-with-witness"
        (upt.liveness "s-0" 4 (upt.pat "recv"))
        (upt.obs) (upt.t1))
      (upt.slot-case "slot-fail-no-witness"
        (upt.liveness "s-1" 100 (upt.pat "nosuch"))
        (upt.obs) (upt.t1))
      (upt.slot-case "slot-invariant-fail"
        (upt.invariant "s-2" ["p-mid"] (upt.phase-is "done"))
        (upt.obs) (upt.t1))
      (upt.batch-case "batch")])

\\ ---------------------------------------------------------------
\\ The batch surface a certificate consumes: one declaration set, one
\\ trace, one canonical verdict frame, plus the same verdicts projected
\\ onto the world verdicts slot.
\\ ---------------------------------------------------------------

(define upt.batch-properties
  -> [(upt.invariant "b-inv" ["p-late"] (upt.phase-is "done"))
      (upt.liveness "b-live" 3 (upt.pat "recv"))
      (upt.temporal "b-tmp" "never" [(upt.pat "drop")])])

(define upt.batch-case
  Name ->
    (/. Unit
      (upt.batch-h
        Name
        (urdr.properties.check
          (upt.batch-properties) (upt.obs) (upt.t1)))))

(define upt.batch-h
  Name [error E] ->
    (do (output "FAIL|~A|~A~%" Name E) false)
  Name [ok Verdicts] ->
    (upt.batch-frames
      Name
      (urdr.properties.frame Verdicts)
      (urdr.canonical.encode-frame
        [list (urdr.world.verdict-values
                (urdr.properties.world-verdicts Verdicts))])))

(define upt.batch-frames
  Name [ok Bytes] [ok SlotBytes] ->
    (do
      (output "PROP|~A|BATCH|~A~%" Name (upt.hex Bytes))
      (output "SLOT|~A|~A~%" Name (upt.hex SlotBytes))
      true)
  Name _ _ ->
    (do (output "FAIL|~A|encode~%" Name) false))

\\ ---------------------------------------------------------------
\\ Load rejections. Every M1 property-load error code appears here.
\\ ---------------------------------------------------------------

(define upt.bad-node
  -> [symbol (upt.bytes "not-a-node")])

(define upt.reject-cases
  -> [\\ Classes reserved for M3+ guests: defence in depth behind the
      \\ scenario DSL, which already rejects them at declaration.
      (upt.reject "class-crash"
        (upt.property "crash" "r-0" (upt.p-true)) (upt.obs))
      (upt.reject "class-log"
        (upt.property "log" "r-1" (upt.p-true)) (upt.obs))
      (upt.reject "class-metamorphic"
        (upt.property "metamorphic" "r-2" (upt.p-true)) (upt.obs))
      (upt.reject "class-unknown"
        (upt.property "chaotic" "r-3" (upt.p-true)) (upt.obs))
      (upt.reject "property-shape"
        [property (upt.bytes "invariant") (upt.bytes "r-4")] (upt.obs))
      (upt.reject "property-id"
        [property (upt.bytes "invariant") [57 98 97 100] (upt.p-true)]
        (upt.obs))
      (upt.reject "spec-noncanonical"
        [property (upt.bytes "invariant") (upt.bytes "r-5") [bogus]]
        (upt.obs))
      (upt.reject "invariant-spec-shape"
        (upt.property "invariant" "r-6" (upt.p-true)) (upt.obs))
      (upt.reject "invariant-points-shape"
        (upt.property "invariant" "r-7"
          [record
            [[(urdr.properties.n.points) [symbol (upt.bytes "p-mid")]]
             [(urdr.properties.n.pred) (upt.p-true)]]])
        (upt.obs))
      (upt.reject "invariant-points-empty"
        (upt.invariant "r-8" [] (upt.p-true)) (upt.obs))
      (upt.reject "invariant-point-type"
        (upt.property "invariant" "r-9"
          [record
            [[(urdr.properties.n.points) [list [(upt.big 1)]]]
             [(urdr.properties.n.pred) (upt.p-true)]]])
        (upt.obs))
      (upt.reject "invariant-point-unknown"
        (upt.invariant "r-10" ["p-nowhere"] (upt.p-true)) (upt.obs))
      (upt.reject "invariant-point-order"
        (upt.invariant "r-11" ["p-mid" "p-early"] (upt.p-true))
        (upt.obs))
      (upt.reject "invariant-point-duplicate"
        (upt.invariant "r-12" ["p-mid" "p-mid"] (upt.p-true)) (upt.obs))
      (upt.reject "predicate-shape"
        (upt.invariant "r-13" ["p-mid"] (upt.bad-node)) (upt.obs))
      (upt.reject "predicate-op-unknown"
        (upt.invariant "r-14" ["p-mid"]
          (upt.node (upt.bytes "sometimes") []))
        (upt.obs))
      (upt.reject "predicate-arity"
        (upt.invariant "r-15" ["p-mid"]
          (upt.node (urdr.properties.n.true) [(upt.p-true)]))
        (upt.obs))
      (upt.reject "term-shape"
        (upt.invariant "r-16" ["p-mid"]
          (upt.p-defined (upt.bad-node)))
        (upt.obs))
      (upt.reject "term-op-unknown"
        (upt.invariant "r-17" ["p-mid"]
          (upt.p-defined (upt.node (upt.bytes "lookup") [])))
        (upt.obs))
      (upt.reject "term-arity"
        (upt.invariant "r-18" ["p-mid"]
          (upt.p-defined (upt.node (urdr.properties.n.this)
                                   [(upt.big 1)])))
        (upt.obs))
      (upt.reject "term-name"
        (upt.invariant "r-19" ["p-mid"]
          (upt.p-defined (upt.node (urdr.properties.n.fact)
                                   [(upt.big 1)])))
        (upt.obs))
      (upt.reject "term-source"
        (upt.invariant "r-20" ["p-mid"]
          (upt.p-defined
            (upt.node (urdr.properties.n.fact-of)
                      [[symbol (upt.bytes "state")] (upt.big 1)])))
        (upt.obs))
      (upt.reject "term-index"
        (upt.invariant "r-21" ["p-mid"]
          (upt.p-defined
            (upt.node (urdr.properties.n.project)
                      [(upt.t-fact "queue") [symbol (upt.bytes "one")]])))
        (upt.obs))
      (upt.reject "term-key"
        (upt.invariant "r-22" ["p-mid"]
          (upt.p-defined
            (upt.node (urdr.properties.n.key)
                      [(upt.t-fact "state") (upt.big 1)])))
        (upt.obs))
      (upt.reject "temporal-spec-shape"
        (upt.property "temporal" "r-23" (upt.p-true)) (upt.obs))
      (upt.reject "temporal-form-unsupported"
        (upt.temporal "r-24" "until" [(upt.pat "sent") (upt.pat "recv")])
        (upt.obs))
      (upt.reject "temporal-args-before"
        (upt.temporal "r-25" "before" [(upt.pat "sent")]) (upt.obs))
      (upt.reject "temporal-args-never"
        (upt.temporal "r-26" "never" [(upt.pat "sent") (upt.pat "recv")])
        (upt.obs))
      (upt.reject "temporal-window"
        (upt.temporal "r-27" "always-eventually"
          [(upt.pat "req") (upt.pat "ack") [symbol (upt.bytes "soon")]])
        (upt.obs))
      (upt.reject "temporal-window-negative"
        (upt.temporal "r-28" "always-eventually"
          [(upt.pat "req") (upt.pat "ack") [big -1 [3]]])
        (upt.obs))
      (upt.reject "liveness-spec-shape"
        (upt.property "liveness" "r-29" (upt.p-true)) (upt.obs))
      (upt.reject "liveness-deadline"
        (upt.property "liveness" "r-30"
          [record
            [[(urdr.properties.n.deadline) [symbol (upt.bytes "soon")]]
             [(urdr.properties.n.pattern) (upt.pat "recv")]]])
        (upt.obs))
      (upt.reject "liveness-deadline-negative"
        (upt.property "liveness" "r-31"
          [record
            [[(urdr.properties.n.deadline) [big -1 [1]]]
             [(urdr.properties.n.pattern) (upt.pat "recv")]]])
        (upt.obs))
      (upt.reject "pattern-shape"
        (upt.temporal "r-32" "never" [(upt.bad-node)]) (upt.obs))
      (upt.reject "pattern-name"
        (upt.temporal "r-33" "never"
          [(upt.pattern-raw (upt.big 1) [null] [null])])
        (upt.obs))
      (upt.reject "pattern-source"
        (upt.temporal "r-34" "never"
          [(upt.pattern-raw [symbol (upt.bytes "sent")] (upt.big 1)
                            [null])])
        (upt.obs))
      (upt.reject "observations-shape"
        (upt.invariant "r-35" ["p-mid"] (upt.p-true))
        [not-an-observation])
      (upt.reject "observation-time"
        (upt.invariant "r-36" ["p-mid"] (upt.p-true))
        [[observation [big -1 [1]] (upt.bytes "p-mid")]])
      (upt.reject "observation-order"
        (upt.invariant "r-37" ["p-mid"] (upt.p-true))
        [[observation (upt.big 4) (upt.bytes "p-mid")]
         [observation (upt.big 2) (upt.bytes "p-early")]])
      (upt.reject-all "duplicate-property"
        [(upt.invariant "r-38" ["p-mid"] (upt.p-true))
         (upt.invariant "r-38" ["p-mid"] (upt.p-false))]
        (upt.obs))
      (upt.reject-all "property-order"
        [(upt.invariant "r-40" ["p-mid"] (upt.p-true))
         (upt.invariant "r-39" ["p-mid"] (upt.p-false))]
        (upt.obs))])

(define upt.pattern-raw
  Name Source Value ->
    [record
      [[(urdr.properties.n.name) Name]
       [(urdr.properties.n.source) Source]
       [(urdr.properties.n.value) Value]]])

\\ ---------------------------------------------------------------
\\ Trace rejections. A malformed trace never reaches an evaluator.
\\ ---------------------------------------------------------------

(define upt.raw-entry
  Component Id Name Time Type Value ->
    [record
      [[(urdr.properties.n.component) Component]
       [(urdr.properties.n.event-id) Id]
       [(urdr.properties.n.name) Name]
       [(urdr.properties.n.time) Time]
       [(urdr.properties.n.type) Type]
       [(urdr.properties.n.value) Value]]])

(define upt.trace-cases
  -> [(upt.bad-trace "trace-shape" [not-a-trace])
      (upt.bad-trace "trace-improper" [trace improper])
      (upt.bad-trace "entry-shape"
        [trace [[record [[(urdr.properties.n.name)
                          [symbol (upt.bytes "sent")]]]]]])
      (upt.bad-trace "entry-key-order"
        [trace [[record
                  [[(urdr.properties.n.event-id) (upt.big 1)]
                   [(urdr.properties.n.component)
                    [bytes (upt.bytes "net")]]
                   [(urdr.properties.n.name)
                    [symbol (upt.bytes "sent")]]
                   [(urdr.properties.n.time) (upt.big 1)]
                   [(urdr.properties.n.type)
                    [symbol (urdr.properties.n.fact)]]
                   [(urdr.properties.n.value) (upt.big 1)]]]]])
      (upt.bad-trace "entry-component"
        [trace [(upt.raw-entry
                  [symbol (upt.bytes "net")] (upt.big 1)
                  [symbol (upt.bytes "sent")] (upt.big 1)
                  [symbol (urdr.properties.n.fact)] (upt.big 1))]])
      (upt.bad-trace "entry-name"
        [trace [(upt.raw-entry
                  [bytes (upt.bytes "net")] (upt.big 1)
                  [bytes (upt.bytes "sent")] (upt.big 1)
                  [symbol (urdr.properties.n.fact)] (upt.big 1))]])
      \\ An event-record type is a deliberate later extension, not a
      \\ silent one.
      (upt.bad-trace "entry-type"
        [trace [(upt.raw-entry
                  [bytes (upt.bytes "net")] (upt.big 1)
                  [symbol (upt.bytes "sent")] (upt.big 1)
                  [symbol (upt.bytes "event")] (upt.big 1))]])
      (upt.bad-trace "entry-id"
        [trace [(upt.raw-entry
                  [bytes (upt.bytes "net")] [big -1 [1]]
                  [symbol (upt.bytes "sent")] (upt.big 1)
                  [symbol (urdr.properties.n.fact)] (upt.big 1))]])
      (upt.bad-trace "entry-time"
        [trace [(upt.raw-entry
                  [bytes (upt.bytes "net")] (upt.big 1)
                  [symbol (upt.bytes "sent")]
                  [symbol (upt.bytes "later")]
                  [symbol (urdr.properties.n.fact)] (upt.big 1))]])
      (upt.bad-trace "entry-value"
        [trace [(upt.raw-entry
                  [bytes (upt.bytes "net")] (upt.big 1)
                  [symbol (upt.bytes "sent")] (upt.big 1)
                  [symbol (urdr.properties.n.fact)] [bogus])]])
      (upt.bad-trace "trace-order-time"
        [trace [(upt.entry 1 5 "net" "sent" (upt.big 1))
                (upt.entry 2 4 "net" "recv" (upt.big 1))]])
      (upt.bad-trace "trace-order-id"
        [trace [(upt.entry 2 4 "net" "sent" (upt.big 1))
                (upt.entry 1 4 "net" "recv" (upt.big 1))]])])

\\ ---------------------------------------------------------------
\\ Integration with the merged world reducer: a fixture component emits
\\ facts, the reducer stamps them, and the resulting fact log IS the
\\ canonical trace. No translation and no host-log reading anywhere.
\\ ---------------------------------------------------------------

(define upt.tick-name
  -> [116 105 99 107])

(define upt.counter-handler
  State _ ->
    (let Next (urdr.int.raw.add State (urdr.int.one))
      [step Next [[fact (upt.tick-name) Next]] []]))

(define upt.registry
  -> [(urdr.component.entry
        [99 111 117 110 116 101 114]
        (/. S E (upt.counter-handler S E))
        (urdr.int.zero))])

(define upt.world-inputs
  -> [[schedule (upt.big 2) component
        [component-input [99 111 117 110 116 101 114] [null]]]
      [schedule (upt.big 5) component
        [component-input [99 111 117 110 116 101 114] [null]]]
      [advance-to-next-event]
      [advance-to-next-event]])

(define upt.world-trace
  -> (upt.world-trace-h
       (urdr.world.initial-with-components
         [117 114 100 114 45 112 114 111 112] (upt.registry))))

(define upt.world-trace-h
  [error E] -> [error E]
  [ok World] ->
    (upt.world-trace-replay
      (urdr.world.replay World (upt.world-inputs))))

(define upt.world-trace-replay
  [replay World _] -> (urdr.properties.trace-of-world World)
  Other -> [error replay-failed])

\\ tick=1 lands at logical time 2, tick=2 at logical time 5.
(define upt.world-cases
  -> (upt.world-cases-h (upt.world-trace)))

(define upt.world-cases-h
  [error E] ->
    [(/. Unit (do (output "FAIL|world-trace|~A~%" E) false))]
  [ok Trace] ->
    [(upt.case "world-live-exact"
       (upt.liveness "w-0" 5 (upt.pat-val "tick"
         (upt.p-cmp (urdr.properties.n.eq)
                    (upt.t-this) (upt.t-const (upt.big 2)))))
       (upt.obs) Trace)
     (upt.case "world-live-missed"
       (upt.liveness "w-1" 4 (upt.pat-val "tick"
         (upt.p-cmp (urdr.properties.n.eq)
                    (upt.t-this) (upt.t-const (upt.big 2)))))
       (upt.obs) Trace)
     (upt.case "world-invariant"
       (upt.invariant "w-2" ["p-mid"]
         (upt.p-cmp (urdr.properties.n.eq)
                    (upt.t-fact-of "tick" "counter")
                    (upt.t-const (upt.big 1))))
       (upt.obs) Trace)
     (upt.case "world-never"
       (upt.temporal "w-3" "never" [(upt.pat "tick")])
       (upt.obs) Trace)
     (upt.world-shape-guard)])

\\ A world value this module does not recognise fails closed rather than
\\ being reinterpreted.
(define upt.world-shape-guard
  -> (/. Unit
       (upt.world-shape-guard-h
         (urdr.properties.trace-of-world [world/v2]))))

(define upt.world-shape-guard-h
  [error Code] ->
    (do (output "TRACE|world-shape|~A~%" Code) true)
  _ ->
    (do (output "FAIL|world-shape|unexpected-ok~%") false))

\\ ---------------------------------------------------------------
\\ Driver.
\\ ---------------------------------------------------------------

(define upt.count
  [] -> 0
  [_ | Xs] -> (+ 1 (upt.count Xs)))

\\ Thunks are applied strictly in list order, so the semantic output is a
\\ function of this file alone.
(define upt.run-thunks
  [] Ok -> Ok
  [T | Ts] Ok ->
    (let R (T 0)
      (upt.run-thunks Ts (if R Ok false))))

(define upt.cases
  -> (append (upt.invariant-cases)
       (append (upt.temporal-cases)
         (append (upt.liveness-cases)
           (append (upt.mutation-cases)
             (append (upt.slot-cases)
               (append (upt.world-cases)
                 (append (upt.reject-cases)
                         (upt.trace-cases)))))))))

(define upt.run
  -> (let Cases (upt.cases)
          Ok (upt.run-thunks Cases true)
       (do
         (output "PROPERTIES CASES: ~A~%" (upt.count Cases))
         (if Ok
             (do (output "ALL PASS~%") true)
             (do (output "PROPERTIES: FAIL~%") false)))))

(upt.run)
