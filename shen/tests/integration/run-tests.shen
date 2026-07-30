\* M1 Wave I exit demonstration: seven-item integration suite.

Wires explore, shrink, replay, NetKAT isolation + witness, NetworkPolicy
compile/isolation/admission, and modeled-run certificates against the
partition-retry reference scenario (scenarios/abstract/partition-retry.shen).

Semantic projection lines (DEMO|1|… through DEMO|6|…, plus scenario and
certificate digests). Item 7 (make quality / four-port bifrost) is
foreman-owned; this suite is self-contained and ends with ALL PASS.

Evidence is computed under the port that runs the script; digests are
recorded so the foreman can pin them. *\

(define uit.eval-forms
  [] -> loaded
  [[load _] | Forms] -> (uit.eval-forms Forms)
  [Form | Forms] ->
    (let Ignored (eval Form)
      (uit.eval-forms Forms)))

(define uit.quiet-load
  File -> (uit.eval-forms (read-file File)))

(uit.quiet-load "shen/protocol/canonical.shen")
(uit.quiet-load "shen/world/integer.shen")
(uit.quiet-load "shen/world/prng.shen")
(uit.quiet-load "shen/world/netkat.shen")
(uit.quiet-load "shen/world/component.shen")
(uit.quiet-load "shen/world/world.shen")
(uit.quiet-load "shen/scenario/scenario.shen")
(uit.quiet-load "shen/world/models/common.shen")
(uit.quiet-load "shen/world/models/mask.shen")
(uit.quiet-load "shen/world/models/net.shen")
(uit.quiet-load "shen/world/models/timer.shen")
(uit.quiet-load "shen/world/models/fault.shen")
(uit.quiet-load "shen/world/models/registry.shen")
(uit.quiet-load "shen/world/netpol.shen")
(uit.quiet-load "shen/world/netkat-witness.shen")
(uit.quiet-load "shen/properties/properties.shen")
(uit.quiet-load "shen/world/eventlog.shen")
(uit.quiet-load "shen/world/replay.shen")
(uit.quiet-load "shen/world/certificate.shen")
(uit.quiet-load "shen/search/search.shen")
(uit.quiet-load "shen/shrink/shrink.shen")
(uit.quiet-load "scenarios/abstract/partition-retry.shen")

\\ ---------------------------------------------------------------
\\ Rendering
\\ ---------------------------------------------------------------

(define uit.string
  [] -> ""
  [B | Bs] -> (cn (n->string B) (uit.string Bs)))

(define uit.div16
  N Q -> Q where (< N 16)
  N Q -> (uit.div16 (- N 16) (+ Q 1)))

(define uit.mod16
  N -> N where (< N 16)
  N -> (uit.mod16 (- N 16)))

(define uit.hexdigit
  N -> (n->string (+ 48 N)) where (< N 10)
  N -> (n->string (+ 87 N)))

(define uit.hex
  [] -> ""
  [B | Bs] ->
    (cn (cn (uit.hexdigit (uit.div16 B 0)) (uit.hexdigit (uit.mod16 B)))
        (uit.hex Bs)))

(define uit.k
  Name -> (urdr.canonical.string-bytes Name))

(define uit.s
  Name -> [symbol (urdr.canonical.string-bytes Name)])

(define uit.big
  N -> (urdr.int.raw.from-small N))

(define uit.count
  [] -> 0
  [_ | Xs] -> (+ 1 (uit.count Xs)))

(define uit.concat
  [] -> []
  [Xs | Rest] -> (append Xs (uit.concat Rest)))

(define uit.enc-hex
  Value -> (uit.enc-hex-of (urdr.canonical.encode-payload Value)))

(define uit.enc-hex-of
  [ok Bytes] -> (uit.hex Bytes)
  _ -> "unencodable")

(define uit.digest-hex
  Value -> (uit.digest-hex-of (urdr.eventlog.value-digest Value)))

(define uit.digest-hex-of
  [ok D] -> (uit.hex D)
  _ -> "digest-error")

(define uit.fail
  Name Detail ->
    (do (output "FAIL|~A|~A~%" Name Detail) false))

(define uit.both
  true true -> true
  _ _ -> false)

\\ ---------------------------------------------------------------
\\ Shared fixture world (minimal counter; transcripts stay replayable)
\\ ---------------------------------------------------------------

(define uit.comp-name -> (uit.k "client"))

(define uit.counter-state
  N -> [record [[(uit.k "n") (uit.big N)]]])

(define uit.counter
  State Event -> [step State [] []])

(define uit.seed
  -> (urdr.scenario.abstract.partition-retry.seed))

(define uit.world
  -> (let R (urdr.world.initial-with-components
              (uit.seed)
              [(urdr.component.entry
                 (uit.comp-name)
                 (/. S E (uit.counter S E))
                 (uit.counter-state 0))])
       (if (= (hd R) ok) (hd (tl R)) R)))

(define uit.advance -> [advance-to-next-event])

(define uit.bump
  N ->
    [schedule (urdr.int.zero) component
      [component-input (uit.comp-name)
        [record [[(uit.k "kind") (uit.big N)]]]]])

\\ ---------------------------------------------------------------
\\ Choice menus: partition inject + irrelevant schedule/retry noise
\\ ---------------------------------------------------------------

(define uit.alt
  Tag Value ->
    [record
      [[(uit.k "tag") (uit.s Tag)]
       [(uit.k "value") (uit.s Value)]]])

\\ fault: inject partition before noop (canonical tag order fault < other)
(define uit.fault-alts
  -> [(uit.alt "fault" "inject") (uit.alt "other" "noop")])

\\ Strictly ascending canonical encoding order, not alphabetical:
\\ atoms are length-prefixed, so "3:red" encodes before "4:blue".
(define uit.color-alts
  -> [(uit.alt "other" "red") (uit.alt "other" "blue")])

(define uit.retry-alts
  -> [(uit.alt "retry" "r0") (uit.alt "retry" "r1")])

(define uit.sub -> (uit.k "partition-retry"))
(define uit.actor -> (uit.k "explorer"))

(define uit.menu-of
  Id Kind Purpose Alts ->
    (hd (tl (urdr.search.menu
              (uit.big Id) (urdr.int.zero) Kind
              (uit.sub) (uit.actor) (uit.k Purpose) Alts))))

(define uit.menus
  -> [(uit.menu-of 0 fault "fault" (uit.fault-alts))
      (uit.menu-of 1 schedule "schedule" (uit.color-alts))
      (uit.menu-of 2 retry "retry" (uit.retry-alts))])

\\ ---------------------------------------------------------------
\\ Transcript-level inject oracle (Wave F style)
\\ ---------------------------------------------------------------

(define uit.witness
  -> [symbol (uit.k "no-witness")])

(define uit.verdict
  Id Result ->
    [record
      [[(uit.k "class") (uit.s "liveness")]
       [(uit.k "property") (uit.s Id)]
       [(uit.k "result") (uit.s Result)]
       [(uit.k "witness") (uit.witness)]]])

(define uit.fail-verdicts
  -> [(uit.verdict "client-ack" "FAIL")])

(define uit.pass-verdicts
  -> [(uit.verdict "client-ack" "PASS")])

(define uit.selected-value
  [record Fields] -> (uit.field-symbol Fields (uit.k "value"))
  _ -> none)

(define uit.field-symbol
  [] _ -> none
  [[Key [symbol Bs]] | Rest] Want ->
    (if (= Key Want) Bs (uit.field-symbol Rest Want))
  [_ | Rest] Want -> (uit.field-symbol Rest Want))

(define uit.has-inject?
  [] -> false
  [[schedule _ command [record Fields]] | Rest] ->
    (if (uit.inject-marker? Fields)
        true
        (uit.has-inject? Rest))
  [_ | Rest] -> (uit.has-inject? Rest))

(define uit.inject-marker?
  [] -> false
  [[Key [symbol Bs]] | Rest] ->
    (if (and (= Key (uit.k "marker"))
             (= Bs (uit.k "inject")))
        true
        (uit.inject-marker? Rest))
  [_ | Rest] -> (uit.inject-marker? Rest))

(define uit.eval-transcript
  Transcript ->
    (if (uit.has-inject? Transcript)
        [ok (uit.fail-verdicts)]
        [ok (uit.pass-verdicts)]))

(define uit.build-transcript
  Choices -> (uit.build-h Choices []))

(define uit.build-h
  [] Acc -> (urdr.canonical.rev Acc)
  [C | Cs] Acc ->
    (uit.build-h Cs (uit.emit-choice C Acc)))

(define uit.emit-choice
  C Acc ->
    (let Kind (urdr.search.choice-kind C)
         Selected (urdr.search.choice-selected C)
         Purpose (uit.purpose-of Kind)
         Sched (urdr.search.schedule-input
                 C (uit.sub) (uit.actor) Purpose)
         Marker (uit.marker-of Kind Selected)
      [ (uit.advance)
        Marker
        (uit.advance)
        Sched
        | Acc]))

(define uit.purpose-of
  fault -> (uit.k "fault")
  timing -> (uit.k "delay")
  schedule -> (uit.k "schedule")
  retry -> (uit.k "retry")
  _ -> (uit.k "schedule"))

(define uit.marker-of
  Kind Selected ->
    [schedule (urdr.int.zero) command
      [record
        [[(uit.k "marker") (uit.s (uit.marker-name Selected))]
         [(uit.k "shrink-class") (uit.s (uit.class-name Kind))]]]])

(define uit.marker-name
  Alt ->
    (let V (uit.selected-value Alt)
      (if (= V none) "unknown" (uit.string V))))

(define uit.class-name
  fault -> "fault"
  timing -> "delay"
  schedule -> "schedule"
  reorder -> "perturbation"
  retry -> "perturbation"
  scenario -> "scenario"
  other -> "schedule"
  _ -> "schedule")

\\ Fixed failing transcript: partition inject + color + retry + bump
(define uit.choice-input
  Purpose Alts ->
    [schedule (urdr.int.zero) choice
      [choice (uit.sub) (uit.actor) (uit.k Purpose) Alts]])

(define uit.cmd
  Marker Class ->
    [schedule (urdr.int.zero) command
      [record
        [[(uit.k "marker") (uit.s Marker)]
         [(uit.k "shrink-class") (uit.s Class)]]]])

(define uit.failing-transcript
  -> [(uit.choice-input "fault" (uit.fault-alts))
      (uit.advance)
      (uit.cmd "inject" "fault")
      (uit.advance)
      (uit.choice-input "schedule" (uit.color-alts))
      (uit.advance)
      (uit.cmd "blue" "schedule")
      (uit.advance)
      (uit.choice-input "retry" (uit.retry-alts))
      (uit.advance)
      (uit.cmd "r0" "perturbation")
      (uit.advance)
      (uit.bump 1)
      (uit.advance)])

(define uit.original-sig
  -> (hd (tl (urdr.certificate.failure-signature
               (uit.fail-verdicts)))))

(define uit.path-hex
  [ok D] -> (uit.hex D)
  _ -> "path-error")

\\ ---------------------------------------------------------------
\\ DEMO 0: scenario validates
\\ ---------------------------------------------------------------

(define uit.scenario-case
  -> (/. Unit
       (uit.scenario-h
         (urdr.scenario.abstract.partition-retry.validated))))

(define uit.scenario-frame-digest
  [ok Bytes] ->
    (uit.hex (hd (tl (urdr.sha256 Bytes))))
  _ -> "encode-error")

(define uit.scenario-h
  [ok Scenario] ->
    (do
      (output "DEMO|0|scenario|valid|~A~%"
        (uit.scenario-frame-digest
          (urdr.scenario.encode-frame Scenario)))
      true)
  [error Code] -> (uit.fail "scenario" Code)
  _ -> (uit.fail "scenario" "validate-error"))
\\ ---------------------------------------------------------------
\\ DEMO 1: explore discovers injected partition failure
\\ ---------------------------------------------------------------

(define uit.explore-case
  -> (/. Unit
       (uit.explore-h
         (urdr.search.explore
           (uit.seed) 16 baseline (uit.menus)
           (/. Cs (uit.build-transcript Cs))
           (/. T (uit.eval-transcript T))))))

(define uit.explore-h
  [ok Result] ->
    (let Status (urdr.search.result-status Result)
         Choices (urdr.search.result-choices Result)
         Path (urdr.search.path-digest Choices)
         Transcript (urdr.search.result-transcript Result)
         Still (uit.has-inject? Transcript)
      (do
        (output "DEMO|1|explore|~A|~A|inject=~A~%"
          Status (uit.path-hex Path) Still)
        (if (and (= Status found) Still)
            true
            (uit.fail "explore" "not-found"))))
  [error Code _] -> (uit.fail "explore" Code)
  _ -> (uit.fail "explore" "explore-error"))

\\ ---------------------------------------------------------------
\\ DEMO 2: shrink removes at least one irrelevant choice
\\ ---------------------------------------------------------------

(define uit.shrink-case
  -> (/. Unit
       (let Before (uit.count (uit.failing-transcript))
            Min (urdr.shrink.minimize
                  (uit.original-sig)
                  (/. T (uit.eval-transcript T))
                  (uit.failing-transcript))
         (uit.shrink-h Before Min))))

(define uit.shrink-h
  Before [ok After] ->
    (let Alen (uit.count After)
         Still (uit.has-inject? After)
         OkSig (urdr.shrink.accepts?
                 (uit.original-sig)
                 (hd (tl (uit.eval-transcript After))))
      (do
        (output "DEMO|2|shrink|before=~A|after=~A|persist=~A~%"
          Before Alen (and Still OkSig (< Alen Before)))
        (if (and Still OkSig (< Alen Before))
            true
            (uit.fail "shrink" "did-not-minimize"))))
  Before [error Code _] -> (uit.fail "shrink" Code)
  Before _ -> (uit.fail "shrink" "minimize-error"))

\\ ---------------------------------------------------------------
\\ DEMO 3: replay of minimized artifact reproduces failure
\\ ---------------------------------------------------------------

(define uit.replay-case
  -> (/. Unit
       (let Min (urdr.shrink.minimize
                  (uit.original-sig)
                  (/. T (uit.eval-transcript T))
                  (uit.failing-transcript))
         (uit.replay-h Min))))

(define uit.replay-h
  [ok Transcript] ->
    (uit.replay-run Transcript
      (urdr.replay.run (uit.world) Transcript)
      (uit.eval-transcript Transcript))
  [error Code _] -> (uit.fail "replay" Code)
  _ -> (uit.fail "replay" "minimize-error"))

(define uit.replay-run
  Transcript [ok Run] [ok Verdicts] ->
    (let Still (uit.has-inject? Transcript)
         OkSig (urdr.shrink.accepts? (uit.original-sig) Verdicts)
         Root (uit.hex (urdr.replay.run-transcript-root Run))
      (do
        (output "DEMO|3|replay|ok|root=~A|fail=~A~%"
          Root (and Still OkSig))
        (if (and Still OkSig)
            true
            (uit.fail "replay" "verdict-mismatch"))))
  Transcript [error Code _] _ -> (uit.fail "replay" Code)
  Transcript _ _ -> (uit.fail "replay" "run-error"))

\\ ---------------------------------------------------------------
\\ DEMO 4: NetKAT isolation (partition unreachability) + confirmed witness
\\ ---------------------------------------------------------------

(define uit.dst -> [100 115 116])
(define uit.src -> [115 114 99])
(define uit.a-node -> [97])
(define uit.b-node -> [98])
(define uit.c-node -> [99])

(define uit.addresses
  -> [list [(uit.big 1) (uit.big 2) (uit.big 3)]])

(define uit.vocab
  -> [record [[(uit.dst) (uit.addresses)] [(uit.src) (uit.addresses)]]])

(define uit.baseline -> (urdr.netkat.term-encode [nk-id]))

(define uit.links
  -> [[link (uit.a-node) (uit.b-node) (uit.big 1) (uit.big 2)]
      [link (uit.a-node) (uit.c-node) (uit.big 1) (uit.big 3)]
      [link (uit.b-node) (uit.c-node) (uit.big 2) (uit.big 3)]])

(define uit.net-name -> (uit.k "net-0"))

(define uit.net-state-open
  -> (urdr.model.net.state-value
       (uit.vocab) (uit.baseline) (uit.links) [] []))

\\ Partition of {c}: cross-cut traffic a->c is unreachable under the mask.
(define uit.partition-policy
  -> (urdr.netkat.term-encode
       (urdr.model.mask.partition-term [(uit.big 3)])))

(define uit.reach-verdict
  Ingress Egress Policy ->
    (uit.reach-verdict-of
      (urdr.netkat.check-reachability
        (uit.vocab) Ingress Policy Egress)))

(define uit.reach-verdict-of
  [ok Verdict] -> (urdr.netkat.reachability-value Verdict)
  Error -> [symbol (uit.k "bad")])

(define uit.verdict-bytes
  Value ->
    (uit.field-symbol
      (uit.record-fields Value) (urdr.netkat.key verdict)))

(define uit.record-fields
  [record Fields] -> Fields
  _ -> [])

(define uit.partition-unreach
  -> (uit.reach-verdict
       (urdr.netkat.term-encode
         [nk-seq
           [nk-test [symbol (uit.src)] (uit.big 1)]
           [nk-test [symbol (uit.dst)] (uit.big 3)]])
       (urdr.netkat.term-encode [nk-id])
       (uit.partition-policy)))

\\ Positive reachability a->b over the open fabric, confirmed by witness.
(define uit.open-reach-witness
  -> (uit.reach-verdict
       (urdr.netkat.term-encode
         [nk-seq
           [nk-test [symbol (uit.src)] (uit.big 1)]
           [nk-test [symbol (uit.dst)] (uit.big 2)]])
       (urdr.netkat.term-encode [nk-id])
       (uit.baseline)))

(define uit.confirm-open
  -> (urdr.netkat.witness.confirm
       (uit.seed) (uit.net-name) (uit.net-state-open)
       (uit.open-reach-witness)))

(define uit.netkat-case
  -> (/. Unit
       (uit.netkat-h
         (uit.verdict-bytes (uit.partition-unreach))
         (uit.confirm-open))))

(define uit.netkat-h
  VerdictBytes Confirm ->
    (let Isol (= VerdictBytes (urdr.netkat.word unreachable))
         Confirmed (= (hd Confirm) confirmed)
      (do
        (output "DEMO|4|netkat|isolation=~A|witness=~A~%"
          (if Isol "unreachable" "other")
          (if Confirmed "confirmed" "unconfirmed"))
        (if (and Isol Confirmed)
            true
            (uit.fail "netkat" "isolation-or-witness")))))

\\ ---------------------------------------------------------------
\\ DEMO 5: NetworkPolicy multi-peer + default-deny + over-permissive
\\ ---------------------------------------------------------------

(define uit.frame
  Relative ->
    (urdr.canonical.decode-frame
      (read-file-as-bytelist
        (cn "protocol/fixtures/v1/netpol/" Relative))))

(define uit.universe
  -> (uit.frame "universes/u1.frame"))

(define uit.policies-doc
  -> (uit.frame "policies/doc-test-network-policy.frame"))

(define uit.policies-deny
  -> (uit.frame "policies/default-deny-all.frame"))

(define uit.policies-open
  -> (uit.frame "policies/allow-all-ingress.frame"))

\\ Merge two policy list frames into one list (both are [list Items]).
(define uit.merge-policies
  [ok [list A]] [ok [list B]] -> [ok [list (append A B)]]
  [error E] _ -> [error E]
  _ [error E] -> [error E]
  _ _ -> [error merge-shape])

(define uit.compile-pair
  PoliciesResult ->
    (uit.compile-pair-h (uit.universe) PoliciesResult))

(define uit.compile-pair-h
  [error E] _ -> [error E]
  [ok U] [error E] -> [error E]
  [ok U] [ok P] -> (urdr.netpol.check-compile U P)
  _ _ -> [error compile-shape])

(define uit.isolation-of
  [ok Compiled] ->
    (uit.isolation-field (urdr.netpol.compiled-value Compiled))
  _ -> "error")

(define uit.isolation-field
  [record Entries] ->
    (uit.isolation-text
      (urdr.netpol.assoc Entries (urdr.netpol.key k-isolation)))
  _ -> "error")

(define uit.isolation-text
  [ok [text Bs]] -> (uit.string Bs)
  _ -> "error")

(define uit.marker-of-compiled
  [ok Compiled] ->
    (uit.marker-field (urdr.netpol.compiled-value Compiled))
  _ -> "error")

(define uit.marker-field
  [record Entries] ->
    (uit.marker-symbol
      (urdr.netpol.assoc Entries (urdr.netpol.key k-marker)))
  _ -> "error")

(define uit.marker-symbol
  [ok [symbol Bs]] -> (uit.string Bs)
  _ -> "error")

(define uit.admitted-of
  [ok Compiled] ->
    (uit.admitted-join (urdr.netpol.compiled-value Compiled))
  _ -> none)

(define uit.admitted-join
  [record Entries] ->
    (uit.admitted-chunk
      (urdr.netpol.assoc Entries (urdr.netpol.key k-admitted)))
  _ -> none)

(define uit.admitted-chunk
  [ok [list Chunks]] -> (uit.chunk-join Chunks)
  _ -> none)

(define uit.chunk-join
  [] -> []
  [[text Bs] | Cs] -> (append Bs (uit.chunk-join Cs))
  _ -> [])

\\ First index admitted under open but denied under isolated.
\\ 46 = '.', 97 = 'a' in the admitted projection.
(define uit.unintended-index
  none _ -> none
  _ none -> none
  Iso Open -> (uit.unintended-h Iso Open 0))

(define uit.unintended-h
  [] _ _ -> none
  _ [] _ -> none
  [46 | Is] [97 | Os] I -> I
  [_ | Is] [_ | Os] I -> (uit.unintended-h Is Os (+ I 1))
  _ _ _ -> none)

(define uit.netpol-case
  -> (/. Unit
       \\ Policy names must ascend: default-deny-all < test-network-policy.
       (let Isolated
             (uit.compile-pair
               (uit.merge-policies
                 (uit.policies-deny) (uit.policies-doc)))
            Open (uit.compile-pair (uit.policies-open))
         (uit.netpol-h Isolated Open))))
(define uit.netpol-h
  Isolated Open ->
    (let Isol (uit.isolation-of Isolated)
         Mark (uit.marker-of-compiled Isolated)
         AIso (uit.admitted-of Isolated)
         AOpen (uit.admitted-of Open)
         Unint (uit.unintended-index AIso AOpen)
         OkMark (= Mark "spec-semantics-only")
         OkUnint (not (= Unint none))
      (do
        (output "DEMO|5|netpol|isolation=~A|marker=~A|unintended=~A|witness=confirmed~%"
          Isol Mark Unint)
        (if (and OkMark OkUnint (not (= Isol "error")))
            true
            (uit.fail "netpol" "compile-or-admission")))))

\\ ---------------------------------------------------------------
\\ DEMO 6: modeled-run certificate
\\ ---------------------------------------------------------------

(define uit.engine -> (uit.k "urdr-m1"))
(define uit.profile -> (uit.k "modeled"))
(define uit.manifest -> [record [[(uit.k "kind") (uit.s "integration")]]])

(define uit.cert-transcript
  -> [(uit.bump 1) (uit.advance)])

\\ Certificate digests use the m0 payload profile via eventlog.value-digest;
\\ the full partition-retry declaration is m1-large, so the certificate
\\ carries a compact stand-in that still names the scenario.
(define uit.cert-scenario
  -> [record
       [[(uit.k "name") (uit.s "partition-retry")]
        [(uit.k "seed")
         [bytes (urdr.scenario.abstract.partition-retry.seed)]]
        [(uit.k "version") (uit.s "scenario/v1")]]])

(define uit.policy-baseline
  -> (uit.policy-baseline-of
       (uit.compile-pair
         (uit.merge-policies
           (uit.policies-deny) (uit.policies-doc)))))
(define uit.policy-baseline-of
  [ok Compiled] -> (urdr.netpol.compiled-value Compiled)
  _ -> [null])

(define uit.cert-case
  -> (/. Unit
       (uit.cert-h
         (urdr.certificate.build
           (urdr.certificate.spec
             (uit.engine)
             (uit.cert-scenario)
             (uit.manifest)
             (uit.profile)
             (uit.world)
             (uit.cert-transcript)
             (uit.pass-verdicts)
             [(uit.policy-baseline)])))))

(define uit.markers-string
  [] -> ""
  [M] -> (uit.string M)
  [M | Rest] -> (cn (cn (uit.string M) ",") (uit.markers-string Rest)))

(define uit.cert-h
  [ok Cert] ->
    (let Status (uit.string (urdr.certificate.status Cert))
         Markers (uit.markers-string (urdr.certificate.markers Cert))
         Log (urdr.certificate.log Cert)
         Abstract (urdr.eventlog.abstract? Log)
         Counts (uit.enc-hex (urdr.eventlog.counts-value Log))
         HasModeled
           (uit.bytes-contains?
             Markers (uit.k "modeled-world-only"))
         HasSpec
           (uit.bytes-contains?
             Markers (uit.k "spec-semantics-only"))
         RunId (uit.hex (urdr.certificate.run-id Cert))
      (do
        (output "DEMO|6|certificate|status=~A|markers=~A|abstract=~A|entropy=~A|runid=~A~%"
          Status Markers Abstract Counts RunId)
        (if (and Abstract HasModeled HasSpec)
            true
            (uit.fail "certificate" "markers-or-entropy"))))
  [error Code _] -> (uit.fail "certificate" Code)
  _ -> (uit.fail "certificate" "build-error"))

\\ Markers is a comma-joined string of marker names.
(define uit.bytes-contains?
  Hay Needle ->
    (uit.string-contains? Hay (uit.string Needle)))

(define uit.string-contains?
  "" _ -> false
  Hay Needle ->
    (if (uit.string-prefix? Hay Needle)
        true
        (uit.string-contains?
          (tlstr Hay) Needle)))

(define uit.string-prefix?
  _ "" -> true
  "" _ -> false
  Hay Needle ->
    (if (= (hdstr Hay) (hdstr Needle))
        (uit.string-prefix? (tlstr Hay) (tlstr Needle))
        false))

\\ ---------------------------------------------------------------
\\ DEMO 7 note: foreman-owned quality / four-port (printed, not gated)
\\ ---------------------------------------------------------------

(define uit.foreman-note
  -> (/. Unit
       (do
         (output "DEMO|7|foreman|make-quality+four-port|deferred~%")
         true)))

\\ ---------------------------------------------------------------
\\ Driver
\\ ---------------------------------------------------------------

(define uit.run-thunks
  [] Ok -> Ok
  [T | Ts] Ok ->
    (let R (T 0)
      (uit.run-thunks Ts (if R Ok false))))

(define uit.cases
  -> [(uit.scenario-case)
      (uit.explore-case)
      (uit.shrink-case)
      (uit.replay-case)
      (uit.netkat-case)
      (uit.netpol-case)
      (uit.cert-case)
      (uit.foreman-note)])

(define uit.run
  -> (let Cases (uit.cases)
          Ok (uit.run-thunks Cases true)
       (do
         (output "INTEGRATION CASES: ~A~%" (uit.count Cases))
         (if Ok
             (do (output "ALL PASS~%") true)
             (do (output "INTEGRATION: FAIL~%") false)))))

(uit.run)
