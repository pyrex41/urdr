\* Wave F conformance suite, part 1: explicit choices, search strategies,
   and the seeded exploration driver (shen/search/choice.shen,
   shen/search/strategy.shen, shen/search/explore.shen).

   Semantic output lines, in fixture order:

     CHOICE|NAME|HEX           a choice record, canonically encoded
     CID|NAME|HEX              a stable choice id
     CIDS|NAME|RESULT          two ids that must (not) agree
     CACC|NAME|VALUE           a choice accessor: counter, path, or the
                               number of recorded sample rejections
     CREJ|NAME|CODE            a fail-closed choice rejection
     CLASS|KIND|NAME|CLASS     the boundary-biased classifier's verdict
     DESC|NAME|HEX             a strategy's canonical descriptor
     SEL|NAME|SELECTED|REASON  one selection on a named stream
     DIST|NAME|COUNTS          selections over 24 consecutive counters,
                               which is where the bias is visible
     SREJ|NAME|CODE            a fail-closed strategy rejection
     EXPL|NAME|STOP|STEPS|ENTRIES|CHOICES
     ELAB|NAME|LABELS          the label the driver wrote per entry
     EKIND|NAME|KINDS          the choice kinds, in decision order
     EROOT|NAME|HEX            the root over an exploration's decisions
     EXPR|NAME|HEX             the exploration summary record
     RPL|NAME|HEX              event root ++ state root of replaying an
                               exploration's transcript
     DET|NAME|RESULT           determinism: same seed, other seed
     EREJ|NAME|CODE            a fail-closed exploration rejection
     SEARCH CASES: N
     ALL PASS

   Any internal inconsistency prints a FAIL| line and suppresses the
   ALL PASS marker; shen/tests/search/test.sh additionally compares every
   semantic line against the checked-in golden output.

   Cost discipline: SHA-256 in portable Shen dominates. Every exploration
   hashes one world snapshot per event over a three-component registry,
   so each fixture run is computed ONCE and threaded through the cases as
   a value. *\

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

\\ ---------------------------------------------------------------
\\ Rendering. Nothing here is semantics; it exists so that a divergence
\\ localises to one named line.
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

\\ Thunks are applied strictly in list order, so the semantic output is a
\\ function of this file alone and never of the host's evaluation order
\\ inside a list literal.
(define urt.concat
  [] -> []
  [Xs | Rest] -> (append Xs (urt.concat Rest)))

(define urt.run-thunks
  [] Ok -> Ok
  [T | Ts] Ok ->
    (let R (T 0)
      (urt.run-thunks Ts (if R Ok false))))

\\ ---------------------------------------------------------------
\\ Real PRNG coordinates. A choice record is only evidence if the
\\ coordinates in it are the ones a draw actually produced, so the
\\ fixtures below take theirs from urdr.prng.sample rather than writing
\\ plausible-looking ones by hand.
\\ ---------------------------------------------------------------

(define urt.stream
  Purpose Counter ->
    (urt.stream-of
      (urdr.prng.stream
        (urt.k "c-seed") (urt.k "search") (urt.k "baseline-random")
        Purpose Counter)))

(define urt.stream-of
  [ok Stream] -> Stream
  Error -> Error)

(define urt.sample
  Purpose Counter Bound ->
    (urdr.prng.sample (urt.stream Purpose Counter) Bound))

(define urt.coordinates
  Purpose Counter Bound ->
    (urt.coordinates-of (urt.sample Purpose Counter Bound)))

(define urt.coordinates-of
  [ok [sample _ _ Coordinates]] -> Coordinates
  _ -> [])

(define urt.sample-index
  Purpose Counter Bound ->
    (urt.sample-index-of (urt.sample Purpose Counter Bound)))

(define urt.sample-index-of
  [ok [sample Index _ _]] -> Index
  _ -> (urdr.int.zero))

\\ ---------------------------------------------------------------
\\ Alternatives. The delivery triple is the network model's own, built
\\ through the model's constructor and sorted by the same helper the
\\ model uses, so the fixture cannot drift from what a component would
\\ actually publish.
\\ ---------------------------------------------------------------

\\ INDEX is a host integer here because urdr.model.net.alternative
\\ converts it itself; handing it a software integer would build a
\\ different record than the model publishes.
(define urt.alt
  Action Index ->
    (urdr.model.net.alternative
      (urdr.canonical.string-bytes Action) Index
      (urt.k "a") (urt.k "b")))

(define urt.delivery-alts
  -> (urdr.model.common.sort
       [(urt.alt "deliver" 0) (urt.alt "drop" 0)
        (urt.alt "duplicate" 0)]))

(define urt.reorder-alts
  -> (urdr.model.common.sort
       [(urt.alt "deliver" 0) (urt.alt "deliver" 1)]))

(define urt.timer-alt
  Due -> (urdr.model.timer.entry-value [deadline (urt.big Due) (urt.k "w")]))

(define urt.fault-alt
  Operation ->
    (urdr.model.fault.alternative
      (urt.k "d1") (urt.k "partition")
      (urdr.canonical.string-bytes Operation)))

(define urt.ladder
  -> [(urdr.int.zero) (urt.big 1) (urt.big 2)])

\\ ---------------------------------------------------------------
\\ Case group 1: choice records (choice.shen)
\\ ---------------------------------------------------------------

(define urt.make
  Seq Time Kind Alternatives Selected Reason Coordinates ->
    (urdr.search.choice.make
      Seq (urt.big Time) (urt.k "n1") Kind Alternatives Selected
      Reason Coordinates))

(define urt.basic-choice
  -> (urt.make 0 0 (urt.k "delivery") (urt.delivery-alts)
       (hd (urt.delivery-alts))
       (urdr.search.choice.reason-uniform)
       (urt.coordinates (urt.k "delivery") (urdr.int.zero)
         (urt.big 3))))

(define urt.choice-case
  Name Made ->
    (/. Unit (urt.choice-line Name Made)))

(define urt.choice-line
  Name [ok Choice] ->
    (do
      (output "CHOICE|~A|~A~%" Name
        (urt.enc-hex (urdr.search.choice.value Choice)))
      (urt.choice-selfcheck Name Choice))
  Name [error Code Detail] -> (urt.fail Name "make-error"))

\\ A record that `make` produced must also pass `check`, or construction
\\ and validation have drifted apart.
(define urt.choice-selfcheck
  Name Choice ->
    (if (= (urdr.search.choice.check Choice) [ok])
        true
        (urt.fail Name "check-disagrees")))

(define urt.id-case
  Name Made -> (/. Unit (urt.id-line Name Made)))

(define urt.id-line
  Name [ok Choice] ->
    (do
      (output "CID|~A|~A~%" Name
        (urt.hex (urdr.search.choice.id Choice)))
      true)
  Name _ -> (urt.fail Name "make-error"))

(define urt.ids-case
  Name A B Same -> (/. Unit (urt.ids-line Name A B Same)))

(define urt.ids-line
  Name [ok X] [ok Y] Same ->
    (if (= (= (urdr.search.choice.id X) (urdr.search.choice.id Y)) Same)
        (do (output "CIDS|~A|~A~%" Name
              (if Same "identical" "distinct"))
            true)
        (urt.fail Name "id-stability"))
  Name _ _ _ -> (urt.fail Name "make-error"))

(define urt.acc-case
  Name Made -> (/. Unit (urt.acc-line Name Made)))

(define urt.acc-line
  Name [ok Choice] ->
    (do
      (output "CACC|~A|counter=~A|rejections=~A|path=~A~%" Name
        (urt.enc-hex (urdr.search.choice.counter Choice))
        (urt.count (urdr.search.choice.rejections Choice))
        (urt.path-string (urdr.search.choice.path Choice)))
      true)
  Name _ -> (urt.fail Name "make-error"))

(define urt.path-string
  [path Sub Actor Purpose _] ->
    (cn (urt.string Sub)
        (cn "/" (cn (urt.string Actor)
                    (cn "/" (urt.string Purpose))))))

(define urt.creject-case
  Name Made Expected -> (/. Unit (urt.creject-line Name Made Expected)))

(define urt.creject-line
  Name [error Code _] Expected ->
    (if (= Code Expected)
        (do (output "CREJ|~A|~A~%" Name
              (urt.string (urdr.search.choice.code-octets Code)))
            true)
        (urt.fail Name "wrong-code"))
  Name _ Expected -> (urt.fail Name "unexpected-ok"))

(define urt.ccheck-case
  Name Choice Expected ->
    (/. Unit (urt.creject-line Name (urdr.search.choice.check Choice)
               Expected)))

\\ Coordinates that no bounded sample could have produced: one that does
\\ not start at block 0, and one whose block indices skip.
(define urt.coord
  Counter Block ->
    (urdr.prng.transcript-coordinate
      (urt.k "c-seed") (urt.k "search") (urt.k "baseline-random")
      (urt.k "delivery") (urt.big Counter) (urt.big Block)))

(define urt.choice-cases
  -> (let Basic (urt.basic-choice)
          Alts (urt.delivery-alts)
          Coords (urt.coordinates (urt.k "delivery") (urdr.int.zero)
                   (urt.big 3))
       [(urt.choice-case "delivery" Basic)
        (urt.id-case "delivery" Basic)
        (urt.acc-case "delivery" Basic)
        (urt.ids-case "same-inputs" Basic (urt.basic-choice) true)
        (urt.ids-case "other-sequence" Basic
          (urt.make 1 0 (urt.k "delivery") Alts (hd Alts)
            (urdr.search.choice.reason-uniform) Coords)
          false)
        (urt.ids-case "other-time" Basic
          (urt.make 0 1 (urt.k "delivery") Alts (hd Alts)
            (urdr.search.choice.reason-uniform) Coords)
          false)
        (urt.ids-case "other-kind" Basic
          (urt.make 0 0 (urt.k "timer-fire") Alts (hd Alts)
            (urdr.search.choice.reason-uniform) Coords)
          false)
        (urt.ids-case "other-selection" Basic
          (urt.make 0 0 (urt.k "delivery") Alts (hd (tl Alts))
            (urdr.search.choice.reason-uniform) Coords)
          true)
        (urt.creject-case "reject-time"
          (urdr.search.choice.make 0 [big -1 [1]] (urt.k "n1")
            (urt.k "delivery") Alts (hd Alts)
            (urdr.search.choice.reason-uniform) Coords)
          search-choice-time)
        (urt.creject-case "reject-actor"
          (urdr.search.choice.make 0 (urdr.int.zero) [not-octets]
            (urt.k "delivery") Alts (hd Alts)
            (urdr.search.choice.reason-uniform) Coords)
          search-choice-actor)
        (urt.creject-case "reject-kind"
          (urdr.search.choice.make 0 (urdr.int.zero) (urt.k "n1")
            [] Alts (hd Alts)
            (urdr.search.choice.reason-uniform) Coords)
          search-choice-kind)
        (urt.creject-case "reject-no-alternatives"
          (urt.make 0 0 (urt.k "delivery") [] [null]
            (urdr.search.choice.reason-uniform) Coords)
          search-choice-alternatives)
        (urt.creject-case "reject-alternative-order"
          (urt.make 0 0 (urt.k "delivery")
            [(hd (tl Alts)) (hd Alts)] (hd Alts)
            (urdr.search.choice.reason-uniform) Coords)
          search-choice-alternative-order)
        (urt.creject-case "reject-selected"
          (urt.make 0 0 (urt.k "delivery") Alts (urt.big 99)
            (urdr.search.choice.reason-uniform) Coords)
          search-choice-selected)
        (urt.creject-case "reject-reason"
          (urt.make 0 0 (urt.k "delivery") Alts (hd Alts)
            (urt.k "because") Coords)
          search-choice-reason)
        (urt.creject-case "reject-no-coordinates"
          (urt.make 0 0 (urt.k "delivery") Alts (hd Alts)
            (urdr.search.choice.reason-uniform) [])
          search-choice-coordinates)
        (urt.creject-case "reject-coordinate-start"
          (urt.make 0 0 (urt.k "delivery") Alts (hd Alts)
            (urdr.search.choice.reason-uniform)
            [(urt.coord 0 1)])
          search-choice-coordinates)
        (urt.creject-case "reject-coordinate-gap"
          (urt.make 0 0 (urt.k "delivery") Alts (hd Alts)
            (urdr.search.choice.reason-uniform)
            [(urt.coord 0 0) (urt.coord 0 2)])
          search-choice-coordinates)
        (urt.creject-case "reject-coordinate-counter"
          (urt.make 0 0 (urt.k "delivery") Alts (hd Alts)
            (urdr.search.choice.reason-uniform)
            [(urt.coord 0 0) (urt.coord 1 1)])
          search-choice-coordinates)
        (urt.ccheck-case "reject-shape" [not-a-choice]
          search-choice-shape)
        (urt.ccheck-case "reject-id"
          [schoice [1 2 3] (urdr.int.zero) (urt.k "n1")
            (urt.k "delivery") Alts (hd Alts)
            (urdr.search.choice.reason-uniform) Coords]
          search-choice-id)]))

\\ ---------------------------------------------------------------
\\ Case group 2: strategies (strategy.shen)
\\ ---------------------------------------------------------------

(define urt.class-case
  Kind Name Time Alternatives Alternative ->
    (/. Unit
      (do
        (output "CLASS|~A|~A|~A~%" (urt.string Kind) Name
          (urt.string
            (urdr.search.strategy.classify
              Kind (urt.big Time) Alternatives Alternative)))
        true)))

(define urt.class-cases
  -> (let Delivery (urt.delivery-alts)
          Reorder (urt.reorder-alts)
          Ladder (urt.ladder)
       [(urt.class-case (urt.k "timer-fire") "due-now" 0
          [(urt.timer-alt 0)] (urt.timer-alt 0))
        (urt.class-case (urt.k "timer-fire") "due-past" 3
          [(urt.timer-alt 0)] (urt.timer-alt 0))
        (urt.class-case (urt.k "delivery") "deliver-head" 0
          Delivery (urt.alt "deliver" 0))
        (urt.class-case (urt.k "delivery") "deliver-reorder" 0
          Reorder (urt.alt "deliver" 1))
        (urt.class-case (urt.k "delivery") "duplicate" 0
          Delivery (urt.alt "duplicate" 0))
        (urt.class-case (urt.k "delivery") "drop" 0
          Delivery (urt.alt "drop" 0))
        (urt.class-case (urt.k "fault-action") "activate" 0
          [(urt.fault-alt "activate")] (urt.fault-alt "activate"))
        (urt.class-case (urt.k "fault-action") "deactivate" 0
          [(urt.fault-alt "deactivate")] (urt.fault-alt "deactivate"))
        (urt.class-case (urt.k "schedule-delay") "least" 0
          Ladder (urdr.int.zero))
        (urt.class-case (urt.k "schedule-delay") "interior" 0
          Ladder (urt.big 1))
        (urt.class-case (urt.k "schedule-delay") "greatest" 0
          Ladder (urt.big 2))
        (urt.class-case (urt.k "unknown-kind") "anything" 0
          Delivery (urt.alt "drop" 0))]))

(define urt.desc-case
  Name Strategy ->
    (/. Unit
      (do
        (output "DESC|~A|~A~%" Name
          (urt.enc-hex
            (urdr.search.strategy.descriptor-value Strategy)))
        true)))

(define urt.sel-case
  Name Strategy Kind Alternatives Counter ->
    (/. Unit
      (urt.sel-line Name
        (urdr.search.strategy.select
          Strategy
          (urdr.search.strategy.context
            (urt.k "n1") Kind (urdr.int.zero) Alternatives)
          (urt.stream Kind (urt.big Counter))))))

(define urt.sel-line
  Name [ok [selection Selected Reason _ _]] ->
    (do
      (output "SEL|~A|~A|~A~%" Name (urt.brief Selected)
        (urt.string Reason))
      true)
  Name [error Code Detail] -> (urt.fail Name "select-error"))

\\ The action or operation symbol inside an alternative, which is what
\\ makes a selection line readable without printing a whole record.
(define urt.brief
  [record Fields] -> (urt.brief-fields Fields)
  [big Sign Magnitude] -> (urt.enc-hex [big Sign Magnitude])
  _ -> "?")

(define urt.brief-fields
  [] -> "?"
  [[_ [symbol Bs]] | _] -> (urt.string Bs)
  [_ | Rest] -> (urt.brief-fields Rest)
  _ -> "?")

\\ 24 consecutive counters on one stream. The counts are the visible
\\ difference between the two strategies: uniform is flat, weighted is
\\ not, and both are a pure function of the seed.
(define urt.dist-case
  Name Strategy Kind Alternatives ->
    (/. Unit
      (do
        (output "DIST|~A|~A~%" Name
          (urt.tally-string
            (urt.dist-loop Strategy Kind Alternatives 24 [])
            Alternatives))
        true)))

(define urt.dist-loop
  _ _ _ 0 Acc -> Acc
  Strategy Kind Alternatives N Acc ->
    (urt.dist-loop Strategy Kind Alternatives (- N 1)
      [(urt.dist-one Strategy Kind Alternatives (- N 1)) | Acc]))

(define urt.dist-one
  Strategy Kind Alternatives Counter ->
    (urt.dist-selected
      (urdr.search.strategy.select
        Strategy
        (urdr.search.strategy.context
          (urt.k "n1") Kind (urdr.int.zero) Alternatives)
        (urt.stream Kind (urt.big Counter)))))

(define urt.dist-selected
  [ok [selection Selected _ _ _]] -> Selected
  _ -> [null])

(define urt.tally-string
  _ [] -> ""
  Chosen [A] -> (urt.tally-one Chosen A)
  Chosen [A | As] ->
    (cn (urt.tally-one Chosen A) (cn "," (urt.tally-string Chosen As))))

(define urt.tally-one
  Chosen A ->
    (cn (urt.brief A)
        (cn "=" (str (urt.tally-count Chosen A 0)))))

(define urt.tally-count
  [] _ N -> N
  [C | Cs] A N ->
    (urt.tally-count Cs A (if (= C A) (+ N 1) N)))

(define urt.sreject-case
  Name Result Expected ->
    (/. Unit (urt.sreject-line Name Result Expected)))

(define urt.sreject-line
  Name [error Code _] Expected ->
    (if (= Code Expected)
        (do (output "SREJ|~A|~A~%" Name
              (urt.string (urdr.search.strategy.code-octets Code)))
            true)
        (urt.fail Name "wrong-code"))
  Name _ Expected -> (urt.fail Name "unexpected-ok"))

(define urt.weights
  -> (urdr.search.strategy.default-weights))

(define urt.strategy-cases
  -> (let Delivery (urt.delivery-alts)
       [(urt.desc-case "baseline" (urdr.search.strategy.baseline))
        (urt.desc-case "boundary" (urdr.search.strategy.boundary))
        (urt.sel-case "baseline-delivery"
          (urdr.search.strategy.baseline) (urt.k "delivery") Delivery 0)
        (urt.sel-case "boundary-delivery"
          (urdr.search.strategy.boundary) (urt.k "delivery") Delivery 0)
        (urt.sel-case "baseline-forced"
          (urdr.search.strategy.baseline) (urt.k "fault-action")
          [(urt.fault-alt "activate")] 0)
        (urt.sel-case "boundary-forced"
          (urdr.search.strategy.boundary) (urt.k "fault-action")
          [(urt.fault-alt "activate")] 0)
        (urt.dist-case "baseline-delivery"
          (urdr.search.strategy.baseline) (urt.k "delivery") Delivery)
        (urt.dist-case "boundary-delivery"
          (urdr.search.strategy.boundary) (urt.k "delivery") Delivery)
        (urt.sreject-case "reject-strategy-shape"
          (urdr.search.strategy.check [not-a-strategy])
          search-strategy-shape)
        (urt.sreject-case "reject-strategy-name"
          (urdr.search.strategy.check [strategy (urt.k "greedy") []])
          search-strategy-name)
        (urt.sreject-case "reject-baseline-weights"
          (urdr.search.strategy.check
            [strategy (urt.k "baseline-random") (urt.weights)])
          search-strategy-weights)
        (urt.sreject-case "reject-partial-weights"
          (urdr.search.strategy.boundary-with [(hd (urt.weights))])
          search-strategy-weights)
        (urt.sreject-case "reject-zero-weight"
          (urdr.search.strategy.boundary-with
            (urt.zeroed (urt.weights)))
          search-strategy-weight)
        (urt.sreject-case "reject-context"
          (urdr.search.strategy.select
            (urdr.search.strategy.baseline) [not-a-context]
            (urt.stream (urt.k "delivery") (urdr.int.zero)))
          search-strategy-context)
        (urt.sreject-case "reject-empty-alternatives"
          (urdr.search.strategy.select
            (urdr.search.strategy.baseline)
            (urdr.search.strategy.context
              (urt.k "n1") (urt.k "delivery") (urdr.int.zero) [])
            (urt.stream (urt.k "delivery") (urdr.int.zero)))
          search-strategy-context)]))

(define urt.zeroed
  [[weight Class _] | Rest] -> [[weight Class (urdr.int.zero)] | Rest])

\\ ---------------------------------------------------------------
\\ The exploration fixture: a scenario-derived world with all three
\\ abstract models, a packet in flight, an armable deadline, and a fault
\\ domain that can be turned on. Every choice the driver faces is one of
\\ the four kinds the classifier knows about.
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

\\ Three scenario actions: put one packet on the wire, wake the fault
\\ model so it publishes its domain, and arm a deadline that logical time
\\ has already reached, so the timer's first offer is the exactly-at-the-
\\ deadline boundary case.
(define urt.actions
  -> [(urt.sched (urt.k "n1")
        (urdr.model.net.send-input (urt.packet 1 2)
          (urt.k "a") (urt.k "b")))
      (urt.sched (urt.k "f1") (urdr.model.fault.poll-input))
      (urt.sched (urt.k "t1")
        (urdr.model.timer.set-input (urt.k "w") (urdr.int.zero)))])

\\ The encoder: model knowledge, supplied by the caller exactly as
\\ explore.shen section 3 requires. Three shapes, one per model.
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

\\ The detector: the property layer, wired in from outside, exactly as
\\ explore.shen section 5 describes. `never dropped` is the one property
\\ class that turns from PASS to FAIL part-way through a run, so it is
\\ the one that lets an exploration stop at the moment it finds
\\ something.
(define urt.pattern
  Name ->
    [record
      [[(urdr.properties.n.name) [symbol Name]]
       [(urdr.properties.n.source) [null]]
       [(urdr.properties.n.value) [null]]]])

(define urt.properties
  -> [[property (urdr.properties.n.temporal) (urt.k "n-dropped")
        [record
          [[(urdr.properties.n.args)
            [list [(urt.pattern (urt.k "dropped"))]]]
           [(urdr.properties.n.form)
            [symbol (urdr.properties.n.never)]]]]]])

(define urt.verdicts-of
  World -> (urt.verdicts-trace (urdr.properties.trace-of-world World)))

(define urt.verdicts-trace
  [ok Trace] -> (urdr.properties.check (urt.properties) [] Trace)
  [error E] -> [error E])

(define urt.failed?
  World -> (urt.failed-of (urt.verdicts-of World)))

(define urt.failed-of
  [ok Verdicts] ->
    [ok (urdr.certificate.any-fail?
          (urdr.properties.verdict-values Verdicts))]
  [error E] -> [error E [null]])

(define urt.spec
  Seed Strategy ->
    (urdr.search.explore.spec
      Seed Strategy (urt.big 8) (urt.ladder) (urt.actions)
      (/. A K S (urt.encoder A K S))
      (/. W (urt.failed? W))))

(define urt.explore
  Seed Strategy ->
    (urdr.search.explore.run (urt.e-world)
      (urt.spec (urt.k Seed) Strategy)))

\\ ---------------------------------------------------------------
\\ Case group 3: the exploration driver (explore.shen)
\\ ---------------------------------------------------------------

(define urt.expl-case
  Name Result Strategy -> (/. Unit (urt.expl-line Name Result Strategy)))

(define urt.expl-line
  Name [ok E] Strategy ->
    (do
      (output "EXPL|~A|~A|~A|~A|~A~%" Name
        (urt.string (urdr.search.explore.stop E))
        (urdr.search.explore.steps E)
        (urt.count (urdr.search.explore.transcript E))
        (urt.count (urdr.search.explore.choices E)))
      (output "ELAB|~A|~A~%" Name
        (urt.join (urdr.search.explore.labels E)))
      (output "EKIND|~A|~A~%" Name
        (urt.join (urt.kinds (urdr.search.explore.choices E))))
      (urt.expl-roots Name E Strategy))
  Name [error Code Detail] Strategy -> (urt.fail Name "explore-error"))

(define urt.kinds
  [] -> []
  [C | Cs] -> [(urdr.search.choice.kind C) | (urt.kinds Cs)])

(define urt.expl-roots
  Name E Strategy ->
    (urt.expl-root-line Name
      (urdr.search.choice.root (urdr.search.explore.choices E))
      (urdr.replay.transcript-root
        (urdr.search.explore.transcript E))
      E Strategy))

(define urt.expl-root-line
  Name [ok Root] [ok TRoot] E Strategy ->
    (do
      (output "EROOT|~A|~A~%" Name (urt.hex Root))
      (output "EXPR|~A|~A~%" Name
        (urt.result-enc-hex
          (urdr.search.explore.value E Strategy TRoot)))
      (urt.checks-line Name (urdr.search.explore.choices E)))
  Name _ _ E Strategy -> (urt.fail Name "root-error"))

(define urt.result-enc-hex
  [ok Value] -> (urt.enc-hex Value)
  _ -> "unencodable")

\\ Every choice an exploration recorded must independently validate. A
\\ driver that could emit a record its own module would reject would be
\\ producing a transcript nothing else could read.
(define urt.checks-line
  Name [] -> true
  Name [C | Cs] ->
    (if (= (urdr.search.choice.check C) [ok])
        (urt.checks-line Name Cs)
        (urt.fail Name "choice-invalid")))

\\ Replaying an exploration's transcript is the contract that makes the
\\ search output an artifact rather than a log.
(define urt.rpl-case
  Name Result -> (/. Unit (urt.rpl-line Name Result)))

(define urt.rpl-line
  Name [ok E] ->
    (urt.rpl-run Name
      (urdr.replay.run (urt.e-world)
        (urdr.search.explore.transcript E)))
  Name _ -> (urt.fail Name "explore-error"))

(define urt.rpl-run
  Name [ok Run] ->
    (do
      (output "RPL|~A|~A~%" Name
        (urt.hex
          (append (urdr.replay.run-event-root Run)
                  (urdr.replay.run-state-root Run))))
      true)
  Name _ -> (urt.fail Name "replay-error"))

\\ Determinism: same seed, byte-identical decisions; other seed, a
\\ different decision sequence. Both directions are pinned, because only
\\ one of them is evidence of a seeded search.
(define urt.det-case
  Name A B Same -> (/. Unit (urt.det-line Name A B Same)))

(define urt.det-line
  Name [ok X] [ok Y] Same ->
    (urt.det-roots Name
      (urdr.search.choice.root (urdr.search.explore.choices X))
      (urdr.search.choice.root (urdr.search.explore.choices Y))
      Same)
  Name _ _ _ -> (urt.fail Name "explore-error"))

(define urt.det-roots
  Name [ok A] [ok B] Same ->
    (if (= (= A B) Same)
        (do (output "DET|~A|~A~%" Name
              (if Same "identical" "distinct"))
            true)
        (urt.fail Name "determinism"))
  Name _ _ _ -> (urt.fail Name "root-error"))

(define urt.ereject-case
  Name Result Expected ->
    (/. Unit (urt.ereject-line Name Result Expected)))

(define urt.ereject-line
  Name [error Code _] Expected ->
    (if (= Code Expected)
        (do (output "EREJ|~A|~A~%" Name
              (urt.string (urdr.search.explore.code-octets Code)))
            true)
        (urt.fail Name "wrong-code"))
  Name _ Expected -> (urt.fail Name "unexpected-ok"))

(define urt.bad-spec
  Seed Steps Ladder Actions Encoder Detector ->
    (urdr.search.explore.run (urt.e-world)
      (urdr.search.explore.spec
        Seed (urdr.search.strategy.baseline) Steps Ladder Actions
        Encoder Detector)))

(define urt.ok-encoder
  -> (/. A K S (urt.encoder A K S)))

(define urt.ok-detector
  -> (/. W (urt.failed? W)))

(define urt.explore-cases
  BaselineFail BoundaryFail BaselinePass ->
    [(urt.expl-case "baseline-fail" BaselineFail
       (urdr.search.strategy.baseline))
     (urt.expl-case "boundary-fail" BoundaryFail
       (urdr.search.strategy.boundary))
     (urt.expl-case "baseline-budget" BaselinePass
       (urdr.search.strategy.baseline))
     (urt.rpl-case "baseline-fail" BaselineFail)
     (urt.rpl-case "baseline-budget" BaselinePass)
     (urt.det-case "same-seed" BaselineFail
       (urt.explore "s2" (urdr.search.strategy.baseline)) true)
     (urt.det-case "other-seed" BaselineFail BaselinePass false)
     (urt.det-case "other-strategy" BaselineFail BoundaryFail false)
     (urt.ereject-case "reject-spec"
       (urdr.search.explore.run (urt.e-world) [not-a-spec])
       search-explore-spec)
     (urt.ereject-case "reject-world"
       (urdr.search.explore.run [not-a-world]
         (urt.spec (urt.k "s2") (urdr.search.strategy.baseline)))
       search-explore-world)
     (urt.ereject-case "reject-seed"
       (urt.bad-spec [not-octets] (urt.big 4) (urt.ladder)
         (urt.actions) (urt.ok-encoder) (urt.ok-detector))
       search-explore-spec)
     (urt.ereject-case "reject-budget"
       (urt.bad-spec (urt.k "s2") [big -1 [1]] (urt.ladder)
         (urt.actions) (urt.ok-encoder) (urt.ok-detector))
       search-explore-budget)
     (urt.ereject-case "reject-empty-ladder"
       (urt.bad-spec (urt.k "s2") (urt.big 4) []
         (urt.actions) (urt.ok-encoder) (urt.ok-detector))
       search-explore-ladder)
     (urt.ereject-case "reject-negative-ladder"
       (urt.bad-spec (urt.k "s2") (urt.big 4) [[big -1 [1]]]
         (urt.actions) (urt.ok-encoder) (urt.ok-detector))
       search-explore-ladder)
     (urt.ereject-case "reject-actions"
       (urt.bad-spec (urt.k "s2") (urt.big 4) (urt.ladder)
         [[rollback]] (urt.ok-encoder) (urt.ok-detector))
       search-explore-actions)
     (urt.ereject-case "reject-stale-action"
       (urt.bad-spec (urt.k "s2") (urt.big 4) (urt.ladder)
         [[schedule (urt.big 5) component
            [component-input (urt.k "n1")
              (urdr.model.net.poll-input)]]
          [advance-to-next-event]
          [schedule (urdr.int.zero) component
            [component-input (urt.k "n1")
              (urdr.model.net.poll-input)]]]
         (urt.ok-encoder) (urt.ok-detector))
       search-explore-reduction)
     (urt.ereject-case "reject-encoder"
       (urt.bad-spec (urt.k "s2") (urt.big 4) (urt.ladder)
         (urt.actions) (/. A K S [garbage]) (urt.ok-detector))
       search-explore-encoder)
     (urt.ereject-case "reject-detector"
       (urt.bad-spec (urt.k "s2") (urt.big 4) (urt.ladder)
         (urt.actions) (urt.ok-encoder) (/. W [garbage]))
       search-explore-detector)])

\\ ---------------------------------------------------------------
\\ Driver.
\\ ---------------------------------------------------------------

(define urt.cases
  -> (let BaselineFail (urt.explore "s2" (urdr.search.strategy.baseline))
          BoundaryFail (urt.explore "s2" (urdr.search.strategy.boundary))
          BaselinePass (urt.explore "s0" (urdr.search.strategy.baseline))
       (urt.concat
         [(urt.choice-cases)
          (urt.class-cases)
          (urt.strategy-cases)
          (urt.explore-cases
            BaselineFail BoundaryFail BaselinePass)])))

(define urt.run
  -> (let Cases (urt.cases)
          Ok (urt.run-thunks Cases true)
       (do
         (output "SEARCH CASES: ~A~%" (urt.count Cases))
         (if Ok
             (do (output "ALL PASS~%") true)
             (do (output "SEARCH: FAIL~%") false)))))

(urt.run)
