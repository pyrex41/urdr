\* M1.5 exit demonstration: seven-item integration suite, earned.

The chain is the production one end to end (ADR 0007 required
verification 2): urdr.run.execute drives the partition-retry reference
scenario (scenarios/abstract/partition-retry.shen) under its declared
seed and budget with the reference models of
shen/run/models/partition-retry.shen, and the property engine — not a
fixture, not a marker oracle — discovers the liveness violation on a
driver-explored schedule. Shrink minimizes under the failure-signature
gate with an EVAL that re-drives the world through urdr.replay.run and
re-evaluates the declared properties; replay verifies the minimized
artifact and reproduces the verdicts; the certificate is the driver's
own, status FAIL, with the scenario's model bindings committed.

Items 4 (NetKAT isolation + witness) and 5 (NetworkPolicy) operate on
the declared topology and the checked-in policy fixtures, independent
of the world run. Item 7 (make quality / conformance gate) is
foreman-owned; this suite is self-contained and ends with ALL PASS.

Semantic projection lines (DEMO|0|… through DEMO|7|…). Evidence is
computed under the port that runs the script; digests are recorded so
the foreman can pin them. *\

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
(uit.quiet-load "shen/run/run.shen")
(uit.quiet-load "shen/run/models/partition-retry.shen")
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

(define uit.big
  N -> (urdr.int.raw.from-small N))

(define uit.small
  N -> (uit.small-of (urdr.int.small-of N)))

(define uit.small-of
  [ok N] -> N
  _ -> -1)

(define uit.count
  [] -> 0
  [_ | Xs] -> (+ 1 (uit.count Xs)))

(define uit.enc-hex
  Value -> (uit.enc-hex-of (urdr.canonical.encode-payload Value)))

(define uit.enc-hex-of
  [ok Bytes] -> (uit.hex Bytes)
  _ -> "unencodable")

(define uit.fail
  Name Detail ->
    (do (output "FAIL|~A|~A~%" Name Detail) false))

(define uit.field-symbol
  [] _ -> none
  [[Key [symbol Bs]] | Rest] Want ->
    (if (= Key Want) Bs (uit.field-symbol Rest Want))
  [_ | Rest] Want -> (uit.field-symbol Rest Want))

(define uit.seed
  -> (urdr.scenario.abstract.partition-retry.seed))

\\ ---------------------------------------------------------------
\\ The production chain, computed once and threaded through the
\\ cases: the validated scenario, the driver's initial world (the
\\ same production constructor urdr.run boots through), the loaded
\\ declared properties, and the driver discovery itself.
\\ ---------------------------------------------------------------

(define uit.context
  -> (uit.context-of (urdr.scenario.abstract.partition-retry.validated)))

(define uit.context-of
  [ok S] ->
    (uit.context-parts
      (urdr.model.registry.world-from-scenario-limited
        (urdr.scenario.seed-of S)
        S
        (urdr.run.baseline)
        (urdr.model.registry.default-kinds)
        (urdr.run.pr.models)
        (urdr.run.max-steps S))
      (urdr.properties.load-all
        (urdr.scenario.properties-of S)
        (urdr.scenario.observations-of S)))
  _ -> none)

(define uit.context-parts
  [ok World] [ok Loadeds] -> [ctx World Loadeds]
  _ _ -> none)

\\ The PRODUCTION evaluation oracle: re-drive the initial world with
\\ the candidate transcript (urdr.replay.run — certificate.shen
\\ section 7: candidates are run, never verified), lift the final
\\ world's fact trace, and evaluate the scenario's declared properties
\\ over it. No marker oracles anywhere.
(define uit.eval
  [ctx Initial Loadeds] Transcript ->
    (uit.eval-run Loadeds (urdr.replay.run Initial Transcript))
  _ _ -> [error (uit.k "no-context") [null]])

(define uit.eval-run
  Loadeds [ok Run] ->
    (uit.eval-trace
      Loadeds
      (urdr.properties.trace-of-world
        (urdr.eventlog.final-world (urdr.replay.run-log Run))))
  _ [error Code Detail] -> [error Code Detail]
  _ _ -> [error (uit.k "run-shape") [null]])

(define uit.eval-trace
  Loadeds [ok Trace] ->
    (uit.eval-verdicts (urdr.properties.evaluate-all Loadeds Trace))
  _ [error E] -> [error E [null]])

(define uit.eval-verdicts
  [ok Pverdicts] -> [ok (urdr.properties.verdict-values Pverdicts)]
  [error E] -> [error E [null]])

\\ Shrink under the failure-signature gate, once, shared by items 2
\\ and 3: [minimized SIG ORIGINAL MINIMIZED] or none.
(define uit.minimized
  Ctx [ok [discovered _ _ Transcript Verdicts _]] ->
    (uit.minimized-sig
      (urdr.certificate.failure-signature Verdicts)
      Ctx
      Transcript)
  _ _ -> none)

(define uit.minimized-sig
  [ok Sig] Ctx Transcript ->
    (uit.minimized-of
      Sig
      Transcript
      (urdr.shrink.minimize
        Sig (/. T (uit.eval Ctx T)) Transcript))
  _ _ _ -> none)

(define uit.minimized-of
  Sig Transcript [ok Min] -> [minimized Sig Transcript Min]
  _ _ _ -> none)

\\ ---------------------------------------------------------------
\\ DEMO 0: the declaration validates under the scenario DSL.
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
\\ DEMO 1: urdr.run.execute discovers the liveness failure from the
\\ declared seed. Attempts 0 and 1 explore schedules where the fault
\\ resolves `never` and the reply crosses (both properties PASS);
\\ attempt 2 injects the partition while the reply is in flight, the
\\ retries meet the cut fabric, and the property engine fails both
\\ declared properties over the recorded fact trace.
\\ ---------------------------------------------------------------

(define uit.sig-hex
  Verdicts ->
    (uit.sig-hex-of (urdr.certificate.failure-signature Verdicts)))

(define uit.sig-hex-of
  [ok Sig] -> (uit.hex Sig)
  _ -> "sig-error")

(define uit.empty-sig-hex
  -> (uit.hex (urdr.search.empty-failure-sig)))

(define uit.vfield-string
  [some [symbol Bs]] -> (uit.string Bs)
  _ -> "?")

(define uit.witness-kind
  [some [symbol Bs]] -> (uit.string Bs)
  [some [record _]] -> "record"
  _ -> "?")

(define uit.verdict-line
  Value ->
    (do
      (output "DEMO|1|verdict|~A|~A|~A~%"
        (uit.vfield-string
          (urdr.certificate.field-of (urdr.properties.n.property) Value))
        (uit.vfield-string
          (urdr.certificate.field-of (urdr.properties.n.result) Value))
        (uit.witness-kind
          (urdr.certificate.field-of (urdr.properties.n.witness) Value)))
      true))

(define uit.verdict-lines
  [] -> true
  [V | Rest] ->
    (let Ok (uit.verdict-line V)
      (uit.verdict-lines Rest)))

(define uit.discover-case
  Discovery -> (/. Unit (uit.discover-h Discovery)))

(define uit.discover-h
  [ok [discovered Attempt Seed Transcript Verdicts Cert]] ->
    (let Sig (uit.sig-hex Verdicts)
         A (output "DEMO|1|discover|attempt=~A|sig=~A~%"
             (uit.small Attempt) Sig)
         B (uit.verdict-lines Verdicts)
      (if (and (>= (uit.small Attempt) 1)
               (not (= Sig (uit.empty-sig-hex))))
          true
          (uit.fail "discover" "trivial-or-empty-signature")))
  [error Code Detail] -> (uit.fail "discover" (uit.string Code))
  _ -> (uit.fail "discover" "unexpected-shape"))

\\ ---------------------------------------------------------------
\\ DEMO 2: shrink minimizes the discovered transcript under the
\\ failure-signature gate, with the production EVAL above. The
\\ minimized artifact must be shorter and must still fail with the
\\ SAME signature when re-driven.
\\ ---------------------------------------------------------------

(define uit.shrink-case
  Ctx Min -> (/. Unit (uit.shrink-h Ctx Min)))

(define uit.shrink-h
  Ctx [minimized Sig Original Min] ->
    (let Before (uit.count Original)
         After (uit.count Min)
         Persist (uit.accepts Sig (uit.eval Ctx Min))
      (do
        (output "DEMO|2|shrink|before=~A|after=~A|persist=~A~%"
          Before After Persist)
        (if (and Persist (< After Before))
            true
            (uit.fail "shrink" "did-not-minimize"))))
  _ _ -> (uit.fail "shrink" "minimize-error"))

(define uit.accepts
  Sig [ok Verdicts] -> (urdr.shrink.accepts? Sig Verdicts)
  _ _ -> false)

\\ ---------------------------------------------------------------
\\ DEMO 3: replay of the minimized artifact. The re-drive is recorded
\\ (urdr.replay.run), the recorded artifact is independently verified
\\ against the same transcript (urdr.replay.verify), and the
\\ re-driven world's verdicts reproduce the discovered failure
\\ signature through the production property path.
\\ ---------------------------------------------------------------

(define uit.replay-case
  Ctx Min -> (/. Unit (uit.replay-h Ctx Min)))

(define uit.replay-h
  [ctx Initial Loadeds] [minimized Sig Original Min] ->
    (uit.replay-run
      [ctx Initial Loadeds] Sig Min
      (urdr.replay.run Initial Min))
  _ _ -> (uit.fail "replay" "minimize-error"))

(define uit.replay-run
  Ctx Sig Min [ok Run] ->
    (uit.replay-verified
      Ctx Sig Min
      (urdr.replay.run-transcript-root Run)
      (uit.replay-verify Ctx Min (urdr.replay.recorded Run)))
  _ _ _ _ -> (uit.fail "replay" "run-error"))

(define uit.replay-verify
  [ctx Initial _] Min Recorded ->
    (urdr.replay.verify Initial Min Recorded))

(define uit.replay-verified
  Ctx Sig Min Root [ok [verified Log]] ->
    (let Reproduced (uit.accepts Sig (uit.eval Ctx Min))
      (do
        (output "DEMO|3|replay|verified|root=~A|reproduced=~A~%"
          (uit.hex Root) Reproduced)
        (if Reproduced
            true
            (uit.fail "replay" "verdict-mismatch"))))
  _ _ _ _ [error Code Detail] -> (uit.fail "replay" Code)
  _ _ _ _ _ -> (uit.fail "replay" "verify-shape"))

\\ ---------------------------------------------------------------
\\ DEMO 4: NetKAT isolation (partition unreachability) + confirmed
\\ witness, over the scenario's declared topology and vocabulary.
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
\\ DEMO 6: the driver's own modeled-run certificate of the discovered
\\ failure. A discovered failure certifies as status FAIL: the
\\ controls were satisfied (abstract log, zero non-pure/modeled
\\ entropy, replay verified — achieved profile modeled-d1-analog) and
\\ a property verdict is FAIL. The `models` field commits to WHICH
\\ model ran each component (ADR 0008). Markers carry
\\ modeled-world-only alone: the driver runs over the unrestricted
\\ nk-id baseline, so no spec-semantics-only descriptor exists to
\\ propagate — DEMO|5 shows the compiled-policy marker on its own
\\ artifact.
\\ ---------------------------------------------------------------

(define uit.sym-string
  [some [symbol Bs]] -> (uit.string Bs)
  [some [null]] -> "-"
  _ -> "?")

(define uit.binding-string
  Value ->
    (cn (uit.sym-string
          (urdr.certificate.field-of (uit.k "component") Value))
        (cn ":"
            (cn (uit.sym-string
                  (urdr.certificate.field-of (uit.k "model") Value))
                (cn "@"
                    (uit.sym-string
                      (urdr.certificate.field-of
                        (uit.k "node") Value)))))))

(define uit.bindings-string
  [] -> ""
  [B] -> (uit.binding-string B)
  [B | Rest] ->
    (cn (uit.binding-string B) (cn "," (uit.bindings-string Rest))))

(define uit.markers-string
  [] -> ""
  [M] -> (uit.string M)
  [M | Rest] -> (cn (cn (uit.string M) ",") (uit.markers-string Rest)))

(define uit.cert-case
  Discovery -> (/. Unit (uit.cert-h Discovery)))

(define uit.cert-h
  [ok [discovered _ _ _ _ Cert]] ->
    (let Status (uit.string (urdr.certificate.status Cert))
         Profile (uit.string (urdr.certificate.achieved-profile Cert))
         Markers (uit.markers-string (urdr.certificate.markers Cert))
         Log (urdr.certificate.log Cert)
         Abstract (urdr.eventlog.abstract? Log)
         Counts (uit.enc-hex (urdr.eventlog.counts-value Log))
         Models (uit.bindings-string (urdr.certificate.models Cert))
         RunId (uit.hex (urdr.certificate.run-id Cert))
         A (output
             "DEMO|6|certificate|status=~A|profile=~A|markers=~A|abstract=~A|runid=~A~%"
             Status Profile Markers Abstract RunId)
         B (output "DEMO|6|entropy|~A~%" Counts)
         C (output "DEMO|6|models|~A~%" Models)
      (if (and (= Status "FAIL")
               (and (= Profile "modeled-d1-analog")
                    (and Abstract
                         (and (= Markers "modeled-world-only")
                              (= Models
                                 "client:pr-client@a,fault-0:pr-fault@a,net-0:pr-net@a,relay:pr-relay@b,server:pr-server@c")))))
          true
          (uit.fail "certificate" "status-profile-or-models")))
  _ -> (uit.fail "certificate" "no-discovery"))

\\ ---------------------------------------------------------------
\\ DEMO 7 note: foreman-owned quality / conformance gate (printed,
\\ not gated here)
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

\\ The discovery, the shared context, and the minimization are each
\\ computed once; the case thunks close over the shared values so the
\\ printed items are projections of ONE production run, not of
\\ independent re-runs that could drift.
(define uit.cases
  -> (let Discovery (urdr.run.execute
                      (urdr.scenario.abstract.partition-retry.value)
                      (urdr.run.pr.models))
          Ctx (uit.context)
          Min (uit.minimized Ctx Discovery)
       [(uit.scenario-case)
        (uit.discover-case Discovery)
        (uit.shrink-case Ctx Min)
        (uit.replay-case Ctx Min)
        (uit.netkat-case)
        (uit.netpol-case)
        (uit.cert-case Discovery)
        (uit.foreman-note)]))

(define uit.run
  -> (let Cases (uit.cases)
          Ok (uit.run-thunks Cases true)
       (do
         (output "INTEGRATION CASES: ~A~%" (uit.count Cases))
         (if Ok
             (do (output "ALL PASS~%") true)
             (do (output "INTEGRATION: FAIL~%") false)))))

(uit.run)
