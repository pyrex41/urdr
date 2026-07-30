\* Wave F conformance suite: seeded exploration and transcript shrinking
   (shen/search/search.shen, shen/shrink/shrink.shen; SPEC.md 17).

   Semantic output lines, in fixture order:

     CHOICE|NAME|HEX            a choice-record canonical payload
     STRAT|NAME|SELECTED|REASON strategy selection
     EXPLORE|NAME|STATUS|HEX    explore path digest / status
     SHRINK|NAME|BEFORE|AFTER|OK shrink lengths and acceptance
     MUT|NAME|REJECTED          mutation that must be rejected
     REPLAY|NAME|OK|HEX         minimized transcript replays
     SEED|NAME|MATCH|HEX        same seed reproducibility
     CHOICE|small-of|OK         software-integer index decoding
     EXPLORE-SHRINK CASES: N
     ALL PASS

   Any internal inconsistency prints a FAIL| line and suppresses the
   ALL PASS marker; shen/tests/search/test.sh additionally compares
   every semantic line against the checked-in golden output. *\

(define ues.eval-forms
  [] -> loaded
  [[load _] | Forms] -> (ues.eval-forms Forms)
  [Form | Forms] ->
    (let Ignored (eval Form)
      (ues.eval-forms Forms)))

(define ues.quiet-load
  File -> (ues.eval-forms (read-file File)))

(ues.quiet-load "shen/protocol/canonical.shen")
(ues.quiet-load "shen/world/integer.shen")
(ues.quiet-load "shen/world/prng.shen")
(ues.quiet-load "shen/world/component.shen")
(ues.quiet-load "shen/world/world.shen")
(ues.quiet-load "shen/world/eventlog.shen")
(ues.quiet-load "shen/world/replay.shen")
(ues.quiet-load "shen/world/certificate.shen")
(ues.quiet-load "shen/search/search.shen")
(ues.quiet-load "shen/shrink/shrink.shen")

\\ ---------------------------------------------------------------
\\ Rendering
\\ ---------------------------------------------------------------

(define ues.string
  [] -> ""
  [B | Bs] -> (cn (n->string B) (ues.string Bs)))

(define ues.div16
  N Q -> Q where (< N 16)
  N Q -> (ues.div16 (- N 16) (+ Q 1)))

(define ues.mod16
  N -> N where (< N 16)
  N -> (ues.mod16 (- N 16)))

(define ues.hexdigit
  N -> (n->string (+ 48 N)) where (< N 10)
  N -> (n->string (+ 87 N)))

(define ues.hex
  [] -> ""
  [B | Bs] ->
    (cn (cn (ues.hexdigit (ues.div16 B 0)) (ues.hexdigit (ues.mod16 B)))
        (ues.hex Bs)))

(define ues.k
  Name -> (urdr.canonical.string-bytes Name))

(define ues.s
  Name -> [symbol (urdr.canonical.string-bytes Name)])

(define ues.big
  N -> (urdr.int.raw.from-small N))

(define ues.count
  [] -> 0
  [_ | Xs] -> (+ 1 (ues.count Xs)))

(define ues.concat
  [] -> []
  [Xs | Rest] -> (append Xs (ues.concat Rest)))

(define ues.enc-hex
  Value -> (ues.enc-hex-of (urdr.canonical.encode-payload Value)))

(define ues.enc-hex-of
  [ok Bytes] -> (ues.hex Bytes)
  _ -> "unencodable")

(define ues.digest-hex
  Value -> (ues.digest-hex-of (urdr.eventlog.value-digest Value)))

(define ues.digest-hex-of
  [ok D] -> (ues.hex D)
  _ -> "digest-error")

(define ues.fail
  Name Detail ->
    (do (output "FAIL|~A|~A~%" Name Detail) false))

(define ues.both
  true true -> true
  _ _ -> false)

\\ ---------------------------------------------------------------
\\ Fixture world: a minimal counter component so transcripts are
\\ independently replayable via urdr.replay.run.
\\ ---------------------------------------------------------------

(define ues.comp-name -> (ues.k "proc"))

(define ues.counter-state
  N -> [record [[(ues.k "n") (ues.big N)]]])

(define ues.counter
  State Event ->
    [step State [] []])

(define ues.seed -> (ues.k "explore-seed-1"))

(define ues.world
  -> (let R (urdr.world.initial-with-components
              (ues.seed)
              [[component (ues.comp-name)
                 (/. S E (ues.counter S E))
                 (ues.counter-state 0)]])
       (if (= (hd R) ok) (hd (tl R)) R)))

(define ues.advance -> [advance-to-next-event])

(define ues.bump
  N ->
    [schedule (urdr.int.zero) component
      [component-input (ues.comp-name)
        [record [[(ues.k "kind") (ues.big N)]]]]])

\\ ---------------------------------------------------------------
\\ Alternatives and menus
\\
\\ Alternatives are canonically ordered records with a bias `tag` and a
\\ `value`. Alphabetical tag/value order is fixed by construction.
\\ ---------------------------------------------------------------

(define ues.alt
  Tag Value ->
    [record
      [[(ues.k "tag") (ues.s Tag)]
       [(ues.k "value") (ues.s Value)]]])

\\ fault menu: inject (fault tag) before noop (other tag) — inject first
\\ by canonical order of the full record (tag fault < tag other).
(define ues.fault-alts
  -> [(ues.alt "fault" "inject") (ues.alt "other" "noop")])

(define ues.color-alts
  -> [(ues.alt "other" "blue") (ues.alt "other" "red")])

(define ues.delay-alts
  -> [(ues.alt "timing" "d0") (ues.alt "timing" "d1")])

(define ues.sub -> (ues.k "search-fixture"))
(define ues.actor -> (ues.k "explorer"))

(define ues.menu-of
  Id Kind Purpose Alts ->
    (hd (tl (urdr.search.menu
              (ues.big Id) (urdr.int.zero) Kind
              (ues.sub) (ues.actor) (ues.k Purpose) Alts))))

(define ues.menus
  -> [(ues.menu-of 0 fault "fault" (ues.fault-alts))
      (ues.menu-of 1 schedule "schedule" (ues.color-alts))
      (ues.menu-of 2 timing "delay" (ues.delay-alts))])

\\ ---------------------------------------------------------------
\\ Verdict oracle (property-shaped records for failure-signature)
\\
\\ Failure is present iff the transcript schedules a choice whose
\\ alternatives include the inject alternative AND the run is the
\\ "found" path: we detect inject by looking for a fault-purpose choice
\\ that was built when inject was selected. Because the decision
\\ transcript only carries the menu (not the selection), the explore
\\ BUILD function embeds the selection as a command record tagged with
\\ shrink-class, and the oracle reads that.
\\ ---------------------------------------------------------------

\\ Witness is the properties-layer canonical form: a bare symbol
\\ `no-witness` (or a witness record), never a [some ...] wrapper.
\\ certificate.field-of wraps the field value in [some ...]; the value
\\ itself must be encodable as a canonical atom/record.
(define ues.witness
  -> [symbol (ues.k "no-witness")])

(define ues.verdict
  Id Result ->
    [record
      [[(ues.k "class") (ues.s "liveness")]
       [(ues.k "property") (ues.s Id)]
       [(ues.k "result") (ues.s Result)]
       [(ues.k "witness") (ues.witness)]]])

(define ues.fail-verdicts
  -> [(ues.verdict "p-injected" "FAIL")])

(define ues.pass-verdicts
  -> [(ues.verdict "p-injected" "PASS")])

(define ues.selected-value
  [record Fields] -> (ues.field-symbol Fields (ues.k "value"))
  _ -> none)

(define ues.field-symbol
  [] _ -> none
  [[Key [symbol Bs]] | Rest] Want ->
    (if (= Key Want) Bs (ues.field-symbol Rest Want))
  [_ | Rest] Want -> (ues.field-symbol Rest Want))

(define ues.has-inject?
  [] -> false
  [[schedule _ command [record Fields]] | Rest] ->
    (if (ues.inject-marker? Fields)
        true
        (ues.has-inject? Rest))
  [_ | Rest] -> (ues.has-inject? Rest))

(define ues.inject-marker?
  [] -> false
  [[Key [symbol Bs]] | Rest] ->
    (if (and (= Key (ues.k "marker"))
             (= Bs (ues.k "inject")))
        true
        (ues.inject-marker? Rest))
  [_ | Rest] -> (ues.inject-marker? Rest))

(define ues.eval-transcript
  Transcript ->
    (if (ues.has-inject? Transcript)
        [ok (ues.fail-verdicts)]
        [ok (ues.pass-verdicts)]))

\\ BUILD: for each choice record, emit
\\   schedule choice (menu) + advance +
\\   schedule command marker of selected value + advance
\\ so the decision is both a real choice entry and an oracle-visible
\\ marker. Color/delay markers use shrink-class so shrink can classify.
(define ues.build-transcript
  Choices -> (ues.build-h Choices []))

(define ues.build-h
  [] Acc -> (urdr.canonical.rev Acc)
  [C | Cs] Acc ->
    (ues.build-h Cs
      (ues.emit-choice C Acc)))

(define ues.emit-choice
  C Acc ->
    (let Kind (urdr.search.choice-kind C)
         Selected (urdr.search.choice-selected C)
         Purpose (ues.purpose-of Kind)
         Sched (urdr.search.schedule-input
                 C (ues.sub) (ues.actor) Purpose)
         Marker (ues.marker-of Kind Selected)
      [ (ues.advance)
        Marker
        (ues.advance)
        Sched
        | Acc]))

(define ues.purpose-of
  fault -> (ues.k "fault")
  timing -> (ues.k "delay")
  schedule -> (ues.k "schedule")
  _ -> (ues.k "schedule"))

(define ues.marker-of
  Kind Selected ->
    [schedule (urdr.int.zero) command
      [record
        [[(ues.k "marker") (ues.s (ues.marker-name Selected))]
         [(ues.k "shrink-class") (ues.s (ues.class-name Kind))]]]])

(define ues.marker-name
  Alt ->
    (let V (ues.selected-value Alt)
      (if (= V none) "unknown" (ues.string V))))

(define ues.class-name
  fault -> "fault"
  timing -> "delay"
  schedule -> "schedule"
  reorder -> "perturbation"
  retry -> "perturbation"
  scenario -> "scenario"
  other -> "schedule"
  _ -> "schedule")

\\ Reverse emit order is fixed by cons onto Acc then rev at the end of
\\ build-h — but emit-choice conses advance/marker/advance/sched in
\\ reverse. Final order per choice: Sched, advance, Marker, advance.

\\ ---------------------------------------------------------------
\\ Fixed failing transcript for shrink (independent of explore)
\\ ---------------------------------------------------------------

(define ues.choice-input
  Purpose Alts ->
    [schedule (urdr.int.zero) choice
      [choice (ues.sub) (ues.actor) (ues.k Purpose) Alts]])

(define ues.cmd
  Marker Class ->
    [schedule (urdr.int.zero) command
      [record
        [[(ues.k "marker") (ues.s Marker)]
         [(ues.k "shrink-class") (ues.s Class)]]]])

\\ Original failing path: fault inject + irrelevant color + delay + bump.
(define ues.failing-transcript
  -> [(ues.choice-input "fault" (ues.fault-alts))
      (ues.advance)
      (ues.cmd "inject" "fault")
      (ues.advance)
      (ues.choice-input "schedule" (ues.color-alts))
      (ues.advance)
      (ues.cmd "blue" "schedule")
      (ues.advance)
      (ues.choice-input "delay" (ues.delay-alts))
      (ues.advance)
      (ues.cmd "d0" "delay")
      (ues.advance)
      (ues.bump 1)
      (ues.advance)])

(define ues.original-sig
  -> (hd (tl (urdr.certificate.failure-signature
               (ues.fail-verdicts)))))

\\ ---------------------------------------------------------------
\\ Case group 1: choice records
\\ ---------------------------------------------------------------

(define ues.choice-case
  -> (/. Unit
       (let M (hd (ues.menus))
            Sel (urdr.search.select baseline (ues.seed)
                  (urdr.int.zero) M)
         (ues.choice-case-h Sel))))

(define ues.choice-case-h
  [ok [Record _]] ->
    (let V (urdr.search.choice-value Record)
         OkEnc (= (hd (urdr.canonical.encode-payload V)) ok)
         Kind (urdr.search.choice-kind Record)
         Reason (urdr.search.choice-reason Record)
      (do
        (output "CHOICE|record|~A~%" (ues.enc-hex V))
        (output "CHOICE|kind|~A~%" Kind)
        (output "CHOICE|reason|~A~%" Reason)
        (if OkEnc true (ues.fail "choice" "unencodable"))))
  [error Code _] -> (ues.fail "choice" Code)
  _ -> (ues.fail "choice" "select-error"))

\\ ---------------------------------------------------------------
\\ Case group 2: strategies
\\ ---------------------------------------------------------------

(define ues.strat-case
  Name Strategy Menu ->
    (/. Unit
      (ues.strat-h Name
        (urdr.search.select Strategy (ues.seed)
          (urdr.int.zero) Menu))))

(define ues.strat-h
  Name [ok [Record _]] ->
    (do
      (output "STRAT|~A|~A|~A~%"
        Name
        (ues.marker-name (urdr.search.choice-selected Record))
        (urdr.search.choice-reason Record))
      true)
  Name [error Code _] -> (ues.fail Name Code)
  Name _ -> (ues.fail Name "select-error"))

(define ues.strat-cases
  -> [(ues.strat-case "baseline-fault" baseline
        (hd (ues.menus)))
      (ues.strat-case "boundary-fault" boundary
        (hd (ues.menus)))
      (ues.strat-case "baseline-color" baseline
        (hd (tl (ues.menus))))
      (ues.strat-case "boundary-delay" boundary
        (hd (tl (tl (ues.menus)))))])

\\ ---------------------------------------------------------------
\\ Case group 3: explore discovers the injected failure
\\ ---------------------------------------------------------------

(define ues.explore-case
  Name Strategy Budget ->
    (/. Unit
      (ues.explore-h Name
        (urdr.search.explore
          (ues.seed) Budget Strategy (ues.menus)
          (/. Cs (ues.build-transcript Cs))
          (/. T (ues.eval-transcript T))))))

(define ues.explore-h
  Name [ok Result] ->
    (let Status (urdr.search.result-status Result)
         Choices (urdr.search.result-choices Result)
         Path (urdr.search.path-digest Choices)
      (do
        (output "EXPLORE|~A|~A|~A~%"
          Name Status (ues.path-hex Path))
        (if (= Status found)
            true
            (ues.fail Name "not-found"))))
  Name [error Code _] -> (ues.fail Name Code)
  Name _ -> (ues.fail Name "explore-error"))

(define ues.path-hex
  [ok D] -> (ues.hex D)
  _ -> "path-error")

\\ Exhausted path with budget 0 is rejected by explore (budget < 1).
\\ A seed that cannot hit inject within a tiny budget is allowed only
\\ for the negative control when we force pass-only menus — skip that.
(define ues.explore-cases
  -> [(ues.explore-case "baseline" baseline 16)
      (ues.explore-case "boundary" boundary 16)])

\\ ---------------------------------------------------------------
\\ Case group 4: shrink removes irrelevant entries
\\ ---------------------------------------------------------------

(define ues.shrink-case
  -> (/. Unit
       (let Before (ues.count (ues.failing-transcript))
            Min (urdr.shrink.minimize
                  (ues.original-sig)
                  (/. T (ues.eval-transcript T))
                  (ues.failing-transcript))
         (ues.shrink-h Before Min))))

(define ues.shrink-h
  Before [ok After] ->
    (let Alen (ues.count After)
         Still (ues.has-inject? After)
         OkSig (urdr.shrink.accepts?
                 (ues.original-sig)
                 (hd (tl (ues.eval-transcript After))))
      (do
        (output "SHRINK|minimize|~A|~A|~A~%"
          Before Alen (and Still OkSig (< Alen Before)))
        (if (and Still OkSig (< Alen Before))
            true
            (ues.fail "shrink" "did-not-minimize"))))
  Before [error Code _] -> (ues.fail "shrink" Code)
  Before _ -> (ues.fail "shrink" "minimize-error"))

\\ ---------------------------------------------------------------
\\ Case group 5: mutation that drops the fault is rejected
\\ ---------------------------------------------------------------

(define ues.drop-fault
  [] -> []
  [[schedule _ command [record Fields]] | Rest] ->
    (if (ues.inject-marker? Fields)
        (ues.drop-fault Rest)
        [[schedule (urdr.int.zero) command [record Fields]] |
         (ues.drop-fault Rest)])
  [[schedule At choice
     [choice Sub Act Purpose Alts]] | Rest] ->
    (if (= Purpose (ues.k "fault"))
        (ues.drop-fault Rest)
        [[schedule At choice [choice Sub Act Purpose Alts]] |
         (ues.drop-fault Rest)])
  [X | Rest] -> [X | (ues.drop-fault Rest)])

(define ues.mut-case
  -> (/. Unit
       (let Mut (ues.drop-fault (ues.failing-transcript))
            Try (urdr.shrink.try-candidate
                  (ues.original-sig)
                  (/. T (ues.eval-transcript T))
                  Mut)
         (ues.mut-h Try))))

(define ues.mut-h
  [reject _] ->
    (do (output "MUT|drop-fault|rejected~%") true)
  [ok _] -> (ues.fail "mut" "accepted-non-persisting")
  _ -> (ues.fail "mut" "unexpected"))

\\ ---------------------------------------------------------------
\\ Case group 6: minimized artifact replays via urdr.replay.run
\\ ---------------------------------------------------------------

(define ues.replay-case
  -> (/. Unit
       (let Min (urdr.shrink.minimize
                  (ues.original-sig)
                  (/. T (ues.eval-transcript T))
                  (ues.failing-transcript))
         (ues.replay-h Min))))

(define ues.replay-h
  [ok Transcript] ->
    (ues.replay-run Transcript
      (urdr.replay.run (ues.world) Transcript))
  [error Code _] -> (ues.fail "replay" Code)
  _ -> (ues.fail "replay" "minimize-error"))

(define ues.replay-run
  Transcript [ok Run] ->
    (do
      (output "REPLAY|minimized|true|~A~%"
        (ues.hex (urdr.replay.run-transcript-root Run)))
      true)
  Transcript [error Code Detail] ->
    (ues.fail "replay" Code)
  Transcript _ -> (ues.fail "replay" "run-error"))

\\ Also pin that the original failing transcript replays.
(define ues.replay-orig-case
  -> (/. Unit
       (ues.replay-orig-h
         (urdr.replay.run (ues.world) (ues.failing-transcript)))))

(define ues.replay-orig-h
  [ok Run] ->
    (do
      (output "REPLAY|original|true|~A~%"
        (ues.hex (urdr.replay.run-transcript-root Run)))
      true)
  [error Code _] -> (ues.fail "replay-orig" Code)
  _ -> (ues.fail "replay-orig" "run-error"))

\\ ---------------------------------------------------------------
\\ Case group 7: same seed => same path
\\ ---------------------------------------------------------------

(define ues.seed-case
  -> (/. Unit
       (let A (urdr.search.explore
                (ues.seed) 16 baseline (ues.menus)
                (/. Cs (ues.build-transcript Cs))
                (/. T (ues.eval-transcript T)))
            B (urdr.search.explore
                (ues.seed) 16 baseline (ues.menus)
                (/. Cs (ues.build-transcript Cs))
                (/. T (ues.eval-transcript T)))
         (ues.seed-h A B))))

(define ues.seed-h
  [ok Ra] [ok Rb] ->
    (let Pa (urdr.search.path-digest
              (urdr.search.result-choices Ra))
         Pb (urdr.search.path-digest
              (urdr.search.result-choices Rb))
         Match (= Pa Pb)
      (do
        (output "SEED|baseline|~A|~A~%" Match (ues.path-hex Pa))
        (if Match true (ues.fail "seed" "diverged"))))
  _ _ -> (ues.fail "seed" "explore-error"))

\\ Boundary seed reproducibility too.
(define ues.seed-boundary-case
  -> (/. Unit
       (let A (urdr.search.explore
                (ues.seed) 16 boundary (ues.menus)
                (/. Cs (ues.build-transcript Cs))
                (/. T (ues.eval-transcript T)))
            B (urdr.search.explore
                (ues.seed) 16 boundary (ues.menus)
                (/. Cs (ues.build-transcript Cs))
                (/. T (ues.eval-transcript T)))
         (ues.seed-boundary-h A B))))

(define ues.seed-boundary-h
  [ok Ra] [ok Rb] ->
    (let Pa (urdr.search.path-digest
              (urdr.search.result-choices Ra))
         Pb (urdr.search.path-digest
              (urdr.search.result-choices Rb))
         Match (= Pa Pb)
      (do
        (output "SEED|boundary|~A|~A~%" Match (ues.path-hex Pa))
        (if Match true (ues.fail "seed-boundary" "diverged"))))
  _ _ -> (ues.fail "seed-boundary" "explore-error"))

\\ ---------------------------------------------------------------
\\ Case group 8: index decoding of software integers (regression:
\\ ADR 0003 limbs are little-endian, so [big 1 [5000 1]] is 15000,
\\ not 50000001; indices >= 10000 must survive the decode and
\\ anything past the host-safe window must fail closed).
\\ ---------------------------------------------------------------

(define ues.small-of-case
  -> (/. Unit
       (let Ok (ues.small-of-checks)
         (do
           (output "CHOICE|small-of|~A~%" Ok)
           (if Ok true (ues.fail "small-of" "wrong-decode"))))))

(define ues.small-of-checks
  -> (ues.both
       (ues.both
         (= (urdr.search.small-of (ues.big 15000)) 15000)
         (= (urdr.search.small-of [big 1 [5000 1]]) 15000))
       (ues.both
         (ues.both
           (= (urdr.search.small-of (ues.big 99990000)) 99990000)
           (= (urdr.search.small-of (urdr.int.zero)) 0))
         (ues.both
           (= (urdr.search.small-of 7) 7)
           (= (urdr.int.small-of [big 1 [0 0 1]])
              [error unsafe-host-integer])))))

\\ ---------------------------------------------------------------
\\ Driver
\\ ---------------------------------------------------------------

(define ues.run-thunks
  [] Ok -> Ok
  [T | Ts] Ok ->
    (let R (T 0)
      (ues.run-thunks Ts (if R Ok false))))

(define ues.cases
  -> (ues.concat
       [[(ues.choice-case)]
        (ues.strat-cases)
        (ues.explore-cases)
        [(ues.shrink-case)
         (ues.mut-case)
         (ues.replay-case)
         (ues.replay-orig-case)
         (ues.seed-case)
         (ues.seed-boundary-case)
         (ues.small-of-case)]]))

(define ues.run
  -> (let Cases (ues.cases)
          Ok (ues.run-thunks Cases true)
       (do
         (output "EXPLORE-SHRINK CASES: ~A~%" (ues.count Cases))
         (if Ok
             (do (output "ALL PASS~%") true)
             (do (output "EXPLORE-SHRINK: FAIL~%") false)))))

(ues.run)
