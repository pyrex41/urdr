\* Wave H conformance suite: seeded generative grammar for scenario
   families (shen/search/grammar.shen; ADR 0004 Decision 5).

   Semantic output lines, in fixture order:

     SEED|NAME|MATCH|HEX        same seed => identical digests
     MUT|NAME|DIFFERENT         different seeds diverge (optional)
     REPLAY|NAME|CODE           withheld entry fails with divergence
     MUT|small-of|OK            software-integer field decoding
     FAIL|NAME|DETAIL           internal self-check failure
     GRAMMAR CASES: N
     ALL PASS

   Any internal inconsistency prints a FAIL| line and suppresses the
   ALL PASS marker; shen/tests/search/grammar/test.sh additionally
   compares every semantic line against the checked-in golden output. *\

(define ug.eval-forms
  [] -> loaded
  [[load _] | Forms] -> (ug.eval-forms Forms)
  [Form | Forms] ->
    (let Ignored (eval Form)
      (ug.eval-forms Forms)))

(define ug.quiet-load
  File -> (ug.eval-forms (read-file File)))

(ug.quiet-load "shen/protocol/canonical.shen")
(ug.quiet-load "shen/world/integer.shen")
(ug.quiet-load "shen/world/prng.shen")
(ug.quiet-load "shen/world/component.shen")
(ug.quiet-load "shen/world/world.shen")
(ug.quiet-load "shen/world/eventlog.shen")
(ug.quiet-load "shen/world/replay.shen")
(ug.quiet-load "shen/search/search.shen")
(ug.quiet-load "shen/search/grammar.shen")

\\ ---------------------------------------------------------------
\\ Rendering
\\ ---------------------------------------------------------------

(define ug.string
  [] -> ""
  [B | Bs] -> (cn (n->string B) (ug.string Bs)))

(define ug.div16
  N Q -> Q where (< N 16)
  N Q -> (ug.div16 (- N 16) (+ Q 1)))

(define ug.mod16
  N -> N where (< N 16)
  N -> (ug.mod16 (- N 16)))

(define ug.hexdigit
  N -> (n->string (+ 48 N)) where (< N 10)
  N -> (n->string (+ 87 N)))

(define ug.hex
  [] -> ""
  [B | Bs] ->
    (cn (cn (ug.hexdigit (ug.div16 B 0)) (ug.hexdigit (ug.mod16 B)))
        (ug.hex Bs)))

(define ug.k
  Name -> (urdr.canonical.string-bytes Name))

(define ug.count
  [] -> 0
  [_ | Xs] -> (+ 1 (ug.count Xs)))

(define ug.concat
  [] -> []
  [Xs | Rest] -> (append Xs (ug.concat Rest)))

(define ug.digest-hex
  Value -> (ug.digest-hex-of (urdr.eventlog.value-digest Value)))

(define ug.digest-hex-of
  [ok D] -> (ug.hex D)
  _ -> "digest-error")

(define ug.path-hex
  [ok D] -> (ug.hex D)
  _ -> "path-error")

(define ug.frag-hex
  [ok D] -> (ug.hex D)
  _ -> "frag-error")

(define ug.fail
  Name Detail ->
    (do (output "FAIL|~A|~A~%" Name Detail) false))

\\ ---------------------------------------------------------------
\\ Fixture family and seeds
\\ ---------------------------------------------------------------

(define ug.seed-a -> (ug.k "grammar-seed-1"))
(define ug.seed-b -> (ug.k "grammar-seed-2"))

\\ Small discrete family: topology sizes {2,3}, line/star, processes
\\ {1,2}, burst/steady, fault counts {0,1}, partition/crash, front/back.
(define ug.family
  -> (hd (tl (urdr.grammar.family-spec
               [2 3]
               [line star]
               [1 2]
               [burst steady]
               [0 1]
               [partition crash]
               [front back]))))

\\ ---------------------------------------------------------------
\\ Fixture world for transcript replay (minimal counter component).
\\ Grammar schedule-input entries are ordinary choice menus; the
\\ reducer accepts them and the counter ignores payloads.
\\ ---------------------------------------------------------------

(define ug.comp-name -> (ug.k "proc"))

(define ug.counter-state
  N -> [record [[(ug.k "n") (urdr.int.raw.from-small N)]]])

(define ug.counter
  State Event -> [step State [] []])

(define ug.world
  -> (let R (urdr.world.initial-with-components
              (ug.k "grammar-world")
              [[component (ug.comp-name)
                 (/. S E (ug.counter S E))
                 (ug.counter-state 0)]])
       (if (= (hd R) ok) (hd (tl R)) R)))

\\ Drop the last transcript entry (withhold).
(define ug.truncate
  [] -> []
  [X] -> []
  [X | Xs] -> [X | (ug.truncate Xs)])

\\ ---------------------------------------------------------------
\\ Case group 1: same seed => byte-identical digests
\\ ---------------------------------------------------------------

(define ug.seed-case
  Name Seed ->
    (/. Unit
      (let A (urdr.grammar.expand Seed (ug.family))
           B (urdr.grammar.expand Seed (ug.family))
        (ug.seed-h Name A B))))

(define ug.seed-h
  Name [ok Ra] [ok Rb] ->
    (let Fa (urdr.grammar.fragment-digest
              (urdr.grammar.result-fragment Ra))
         Fb (urdr.grammar.fragment-digest
              (urdr.grammar.result-fragment Rb))
         Pa (urdr.grammar.path-digest
              (urdr.grammar.result-choices Ra))
         Pb (urdr.grammar.path-digest
              (urdr.grammar.result-choices Rb))
         Match (and (= Fa Fb) (= Pa Pb))
      (do
        (output "SEED|~A|~A|~A~%"
          Name Match (ug.frag-hex Fa))
        (output "SEED|~A-path|~A|~A~%"
          Name Match (ug.path-hex Pa))
        (if Match true (ug.fail Name "diverged"))))
  Name _ _ -> (ug.fail Name "expand-error"))

\\ ---------------------------------------------------------------
\\ Case group 2: different seeds => different digests
\\ ---------------------------------------------------------------

(define ug.mut-case
  -> (/. Unit
       (let A (urdr.grammar.expand (ug.seed-a) (ug.family))
            B (urdr.grammar.expand (ug.seed-b) (ug.family))
         (ug.mut-h A B))))

(define ug.mut-h
  [ok Ra] [ok Rb] ->
    (let Fa (urdr.grammar.fragment-digest
              (urdr.grammar.result-fragment Ra))
         Fb (urdr.grammar.fragment-digest
              (urdr.grammar.result-fragment Rb))
         Diff (not (= Fa Fb))
      (do
        (output "MUT|seeds|~A~%" Diff)
        (if Diff true (ug.fail "mut" "same-digest"))))
  _ _ -> (ug.fail "mut" "expand-error"))

\\ ---------------------------------------------------------------
\\ Case group 3: fail-closed family-spec validation
\\ ---------------------------------------------------------------

(define ug.reject-case
  Name SpecResult ->
    (/. Unit (ug.reject-h Name SpecResult)))

(define ug.reject-h
  Name [error _ _] ->
    (do (output "MUT|~A|rejected~%" Name) true)
  Name [ok _] -> (ug.fail Name "accepted-invalid")
  Name _ -> (ug.fail Name "unexpected"))

(define ug.reject-cases
  -> [(ug.reject-case "empty-sizes"
        (urdr.grammar.family-spec
          [] [line] [1] [burst] [0] [crash] [front]))
      (ug.reject-case "bad-mode"
        (urdr.grammar.family-spec
          [2] [ring] [1] [burst] [0] [crash] [front]))
      (ug.reject-case "no-fit"
        (urdr.grammar.family-spec
          [2] [line] [5 6] [burst] [0] [crash] [front]))])

\\ ---------------------------------------------------------------
\\ Case group 4: withheld transcript entry fails replay
\\ ---------------------------------------------------------------

(define ug.replay-case
  -> (/. Unit
       (let R (urdr.grammar.expand (ug.seed-a) (ug.family))
         (ug.replay-h R))))

(define ug.replay-h
  [ok Exp] ->
    (let T (urdr.grammar.result-transcript Exp)
         Run (urdr.replay.run (ug.world) T)
      (ug.replay-run T Run))
  [error Code _] -> (ug.fail "replay" Code)
  _ -> (ug.fail "replay" "expand-error"))

(define ug.replay-run
  T [ok Run] ->
    (let Rec (urdr.replay.recorded Run)
         Trunc (ug.truncate T)
         V (urdr.replay.verify (ug.world) Trunc Rec)
      (ug.replay-verify V))
  T [error Code _] -> (ug.fail "replay-run" Code)
  T _ -> (ug.fail "replay-run" "run-error"))

(define ug.replay-verify
  [error Code Detail] ->
    (if (= Code replay-transcript-truncated)
        (do
          (output "REPLAY|withhold|~A~%" Code)
          true)
        (ug.fail "replay-withhold" Code))
  [ok _] -> (ug.fail "replay-withhold" "unexpected-ok")
  _ -> (ug.fail "replay-withhold" "unexpected"))

\\ Full transcript also replays cleanly (positive control).
(define ug.replay-ok-case
  -> (/. Unit
       (let R (urdr.grammar.expand (ug.seed-a) (ug.family))
         (ug.replay-ok-h R))))

(define ug.replay-ok-h
  [ok Exp] ->
    (let T (urdr.grammar.result-transcript Exp)
         Run (urdr.replay.run (ug.world) T)
      (ug.replay-ok-run Run))
  _ -> (ug.fail "replay-ok" "expand-error"))

(define ug.replay-ok-run
  [ok Run] ->
    (do
      (output "REPLAY|full|ok|~A~%"
        (ug.hex (urdr.replay.run-transcript-root Run)))
      true)
  [error Code _] -> (ug.fail "replay-ok" Code)
  _ -> (ug.fail "replay-ok" "run-error"))

\\ ---------------------------------------------------------------
\\ Case group 5: fragment is a canonical record
\\ ---------------------------------------------------------------

(define ug.frag-case
  -> (/. Unit
       (let R (urdr.grammar.expand (ug.seed-a) (ug.family))
         (ug.frag-h R))))

(define ug.frag-h
  [ok Exp] ->
    (let V (urdr.grammar.fragment-value
             (urdr.grammar.result-fragment Exp))
         Enc (urdr.canonical.encode-payload V)
      (do
        (output "SEED|fragment|true|~A~%" (ug.digest-hex V))
        (if (= (hd Enc) ok)
            true
            (ug.fail "fragment" "unencodable"))))
  _ -> (ug.fail "fragment" "expand-error"))

\\ ---------------------------------------------------------------
\\ Case group 6: field decoding of software integers (regression:
\\ ADR 0003 limbs are little-endian, so [big 1 [5000 1]] is 15000,
\\ not 50000001; sizes >= 10000 must survive the decode).
\\ ---------------------------------------------------------------

(define ug.small-of-case
  -> (/. Unit
       (let Topo (urdr.grammar.read-topo
                   [record
                     [[(ug.k "size") (urdr.grammar.big 15000)]
                      [(ug.k "link-mode") [symbol (ug.k "line")]]]])
            OkTopo (= Topo [topo 15000 line])
            OkRaw (= (urdr.grammar.small-of [big 1 [5000 1]]) 15000)
            Ok (and OkTopo OkRaw)
         (do
           (output "MUT|small-of|~A~%" Ok)
           (if Ok true (ug.fail "small-of" "wrong-decode"))))))

\\ ---------------------------------------------------------------
\\ Driver
\\ ---------------------------------------------------------------

(define ug.run-thunks
  [] Ok -> Ok
  [T | Ts] Ok ->
    (let R (T 0)
      (ug.run-thunks Ts (if R Ok false))))

(define ug.cases
  -> (ug.concat
       [[(ug.seed-case "a" (ug.seed-a))
         (ug.seed-case "b" (ug.seed-b))
         (ug.mut-case)
         (ug.frag-case)
         (ug.replay-ok-case)
         (ug.replay-case)]
        (ug.reject-cases)
        [(ug.small-of-case)]]))

(define ug.run
  -> (let Cases (ug.cases)
          Ok (ug.run-thunks Cases true)
       (do
         (output "GRAMMAR CASES: ~A~%" (ug.count Cases))
         (if Ok
             (do (output "ALL PASS~%") true)
             (do (output "GRAMMAR: FAIL~%") false)))))

(ug.run)
