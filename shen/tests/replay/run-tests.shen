\* Wave E conformance suite: SPEC.md 20 event records, decision
   transcript replay, and modeled-run certificates
   (shen/world/eventlog.shen, shen/world/replay.shen,
   shen/world/certificate.shen).

   Semantic output lines, in fixture order:

     NODES|N|COUNT|RESULT      the node counter against the canonical
                               codec at its exact m0 node boundary
     CA|NAME|KIND|HEX          a payload slot: inline or content-address
     EL|NAME|HEX               an event-stream root or record digest
     ELT|NAME|TYPES            the event types of a run, in order
     ELC|NAME|HEX              entropy-firewall counts, canonically
                               encoded, all five classes always present
     RT|NAME|RESULT            transcript writer/reader round trip
     E2E|NAME|VALUE            a root or artifact of the end-to-end run
     PROP|NAME|RESULT|WITNESS  a verdict feeding the certificate
     SIG|NAME|VALUE            the canonical failure signature a Wave F
                               shrinker compares to decide persistence
     DIV|NAME|CODE             a fail-closed divergence code
     DIVD|NAME|HEX             the divergence detail, canonically encoded
     MUT|NAME|BEFORE|AFTER     a preimage mutation moved the run id
     MARK|NAME|MARKERS         marker derivation from baselines
     CERT|NAME|STATUS|PROFILE|MARKERS|RUNID
     CERTS|NAME|HEX            the verdict summary, including the
                               vacuity count and the ids of the
                               properties that never fired
     CERTD|NAME|HEX            the certificate payload digest
     CERTF|NAME|HEX            the full certificate payload (schema pin)
     LOOP|N|HEX                N consecutive replays, identical roots
     REPLAY CASES: N
     ALL PASS

   Any internal inconsistency prints a FAIL| line and suppresses the
   ALL PASS marker; shen/tests/replay/test.sh additionally compares every
   semantic line against the checked-in golden output on each of the four
   required ports.

   Cost discipline: SHA-256 in portable Shen is the dominant cost of this
   suite, and every drive of a fixture hashes one world snapshot per
   event. Expensive artifacts are therefore computed ONCE and threaded
   through the cases as values; Shen does not memoise, so a helper called
   twice is a fixture driven twice. *\

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
(urt.quiet-load "shen/world/netpol.shen")
(urt.quiet-load "shen/properties/properties.shen")
(urt.quiet-load "shen/world/eventlog.shen")
(urt.quiet-load "shen/world/replay.shen")
(urt.quiet-load "shen/world/certificate.shen")

\\ ---------------------------------------------------------------
\\ Rendering. Nothing here is semantics; it exists so that a divergence
\\ localises to one named line.
\\ ---------------------------------------------------------------

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

(define urt.k
  Name -> (urdr.canonical.string-bytes Name))

(define urt.s
  Name -> [symbol (urdr.canonical.string-bytes Name)])

(define urt.big
  N -> (urdr.int.raw.from-small N))

(define urt.rep
  0 B Acc -> Acc
  N B Acc -> (urt.rep (- N 1) B [B | Acc]))

(define urt.nulls
  0 Acc -> Acc
  N Acc -> (urt.nulls (- N 1) [[null] | Acc]))

(define urt.count
  [] -> 0
  [_ | Xs] -> (+ 1 (urt.count Xs)))

\\ Every element is a pure list construction, so gathering the case
\\ groups through a flat concat is order-independent. Only the THUNKS
\\ inside them produce output, and urt.run-thunks applies those strictly
\\ in list order.
(define urt.concat
  [] -> []
  [Xs | Rest] -> (append Xs (urt.concat Rest)))

\\ Encoded-payload hex of a canonical value, or a stable marker when the
\\ value does not encode. A case that silently printed nothing for an
\\ unencodable value would pass while proving nothing.
(define urt.enc-hex
  Value -> (urt.enc-hex-of (urdr.canonical.encode-payload Value)))

(define urt.enc-hex-of
  [ok Bytes] -> (urt.hex Bytes)
  [error E] -> "unencodable")

\\ For entry points that return [ok CANONICAL-VALUE] rather than
\\ [ok OCTETS].
(define urt.result-enc-hex
  [ok Value] -> (urt.enc-hex Value)
  _ -> "unencodable")

(define urt.digest-hex
  Value -> (urt.digest-hex-of (urdr.eventlog.value-digest Value)))

(define urt.digest-hex-of
  [ok D] -> (urt.hex D)
  _ -> "undigestable")

(define urt.fail
  Name Why -> (do (output "FAIL|~A|~A~%" Name Why) false))

(define urt.both
  true B -> B
  false B -> false)

\\ ---------------------------------------------------------------
\\ Fixture A: the smallest world that still dispatches a component.
\\ One registered component keeps every snapshot to a single state
\\ digest, which is what makes the 100-replay loop affordable on the
\\ slower ports without weakening what it observes.
\\ ---------------------------------------------------------------

(define urt.a-name -> (urt.k "p-a"))

(define urt.counter-state
  Count -> [record [[(urt.k "count") Count]]])

(define urt.counter
  [record [[[99 111 117 110 116] Count]]] Event ->
    (let Next (hd (tl (urdr.int.add Count (urt.big 1))))
      [step
        (urt.counter-state Next)
        [[fact (urt.k "tick") (urt.counter-state Next)]]
        []])
  _ _ -> (urdr.model.common.error "counter-unknown-input"))

(define urt.a-registry
  -> [(urdr.component.entry
        (urt.a-name)
        (/. S E (urt.counter S E))
        (urt.counter-state (urdr.int.zero)))])

(define urt.world-of
  [ok World] -> World
  Other -> Other)

(define urt.a-world
  -> (urt.world-of
       (urdr.world.initial-with-components
         (urt.k "a-seed") (urt.a-registry))))

\\ A world that differs from urt.a-world only in its seed. Every event
\\ record binds a state hash, so the very first record of a run over this
\\ world differs from the corresponding record over urt.a-world.
(define urt.a-world-other
  -> (urt.world-of
       (urdr.world.initial-with-components
         (urt.k "b-seed") (urt.a-registry))))

\\ A world that differs from urt.a-world ONLY in one registry entry's
\\ META model binding (ADR 0008): same seed, same handler, same state.
\\ The snapshot binds META since ADR 0008, so this world's initial
\\ snapshot digest — and therefore, transitively through preimage
\\ field 3, its run id — must differ from urt.a-world's without any
\\ new run-id preimage field.
(define urt.a-registry-modeled
  -> [[component (urt.a-name)
        (/. S E (urt.counter S E))
        (urt.counter-state (urdr.int.zero))
        (urdr.component.meta (urt.k "m-alt") none)]])

(define urt.a-world-modeled
  -> (urt.world-of
       (urdr.world.initial-with-components
         (urt.k "a-seed") (urt.a-registry-modeled))))

(define urt.bump
  N -> [record [[(urt.k "kind") (urt.big N)]]])

(define urt.advance -> [advance-to-next-event])

(define urt.a-input
  N ->
    [schedule (urdr.int.zero) component
      [component-input (urt.a-name) (urt.bump N)]])

\\ Two inputs: one schedule (classified `pure`) and one advance
\\ (classified `modeled`), so the loop exercises both classes and a real
\\ component transition.
(define urt.loop-transcript
  -> [(urt.a-input 1) (urt.advance)])

\\ Four inputs, so that swapping the two schedules is a genuine
\\ permutation of the recorded entry multiset rather than a substitution.
(define urt.a-transcript
  -> [(urt.a-input 1) (urt.advance) (urt.a-input 2) (urt.advance)])

(define urt.a-truncated
  -> [(urt.a-input 1) (urt.advance) (urt.a-input 2)])

(define urt.a-extended
  -> [(urt.a-input 1) (urt.advance) (urt.a-input 2) (urt.advance)
      (urt.a-input 3)])

(define urt.a-reordered
  -> [(urt.a-input 2) (urt.advance) (urt.a-input 1) (urt.advance)])

(define urt.a-tampered
  -> [(urt.a-input 1) (urt.advance) (urt.a-input 9) (urt.advance)])

\\ ---------------------------------------------------------------
\\ Fixture A': a transcript carrying a pinned (selected) choice entry
\\ (ADR 0007 D2). The coordinates are one well-formed
\\ urdr-sha256-counter-v1 coordinate carried verbatim as evidence of
\\ the driver-space draw; the world embeds them in the emitted choice
\\ record without re-deriving them, so a hand-pinned coordinate is as
\\ replayable as a strategy-drawn one.
\\ ---------------------------------------------------------------

(define urt.sel-alts -> [(urt.big 1) (urt.big 2)])

(define urt.sel-coordinate
  -> [coordinate urdr-sha256-counter-v1
       (urt.k "a-seed") (urt.k "net") (urt.k "a") (urt.k "delivery")
       (urdr.int.zero) (urdr.int.zero)])

(define urt.sel-input
  Selected ->
    [schedule (urdr.int.zero) choice
      [choice (urt.k "net") (urt.k "a") (urt.k "delivery")
        (urt.sel-alts) Selected [(urt.sel-coordinate)]]])

(define urt.sel-transcript
  Selected -> [(urt.a-input 1) (urt.advance)
               (urt.sel-input Selected) (urt.advance)])

\\ A recorded artifact whose entry digests are recomputed over the
\\ candidate transcript while the recorded EVENT stream is kept. The
\\ transcript classification then passes, so verification must reach
\\ the re-drive and judge the event streams themselves -- which is how
\\ a selection tamper is exhibited as a divergence rather than as a
\\ tampered-transcript rejection. (World STATE does not depend on
\\ which alternative was selected -- the selection lives in the event
\\ stream, not the snapshot -- so the event digests, not the state
\\ root, are what catch it.)
(define urt.reentried
  Transcript [recorded _ _ Events ERoot SRoot] ->
    (urt.reentried-digests
      (urdr.replay.entry-digests Transcript) Events ERoot SRoot)
  _ _ -> [not-a-recorded-artifact])

(define urt.reentried-digests
  [ok Digests] Events ERoot SRoot ->
    (urt.reentried-root
      (urdr.eventlog.root-of
        (urdr.replay.n t-transcript-root) Digests)
      Digests Events ERoot SRoot)
  _ _ _ _ -> [not-a-recorded-artifact])

(define urt.reentried-root
  [ok Root] Digests Events ERoot SRoot ->
    [recorded Digests Root Events ERoot SRoot]
  _ _ _ _ _ -> [not-a-recorded-artifact])

\\ ---------------------------------------------------------------
\\ Fixture B: the end-to-end pipeline. A validated scenario becomes a
\\ component registry, the registry becomes a world, the world is driven
\\ through all four reducer event kinds, the facts become a trace, the
\\ trace becomes verdicts, and the verdicts become a certificate.
\\
\\ The scenario is the Wave C composition fixture -- two nodes, one link,
\\ a two-value header space, one partition domain -- with a roster of one
\\ process component. The roster is deliberately NOT all four kinds: a
\\ world snapshot hashes every registered component's state, the network
\\ model's state carries a vocabulary, a policy term, and a link set, and
\\ the certificate drives this fixture three times (once to record it and
\\ twice more inside its own replay verification). A four-kind roster
\\ costs several times the SHA-256 work per event for evidence that
\\ shen/tests/models/ already carries; what Wave E has to show is that
\\ the composition glue reaches the certificate at all, which one
\\ scenario-derived component shows exactly as well.
\\ ---------------------------------------------------------------

(define urt.b-seed -> (urt.k "e2e-seed"))

(define urt.node-value
  Address Id ->
    [record [[(urt.k "address") (urt.big Address)] [(urt.k "id") Id]]])

(define urt.link-value
  From To ->
    [record [[(urt.k "from") From] [(urt.k "to") To]]])

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
           [(urt.component-value (urt.s "proc-a") (urt.s "process")
              (urt.s "b"))]]]
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
        [(urt.k "seed") [bytes (urt.b-seed)]]
        [(urt.k "topology")
         [record
           [[(urt.k "links")
             [list [(urt.link-value (urt.s "a") (urt.s "b"))]]]
            [(urt.k "nodes")
             [list
               [(urt.node-value 1 (urt.s "a"))
                (urt.node-value 2 (urt.s "b"))]]]]]]
        [(urt.k "version") (urt.s "scenario/v1")]]])

(define urt.nk-baseline -> (urdr.netkat.term-encode [nk-id]))

(define urt.b-registry-of
  [ok Scenario] ->
    (urdr.model.registry.from-scenario
      Scenario
      (urt.nk-baseline)
      (urdr.model.registry.kind-table
        (/. S E (urt.counter S E))
        (urt.counter-state (urdr.int.zero)))
      [])
  Error -> Error)

(define urt.b-world-of
  [ok Registry] ->
    (urt.world-of
      (urdr.world.initial-with-components (urt.b-seed) Registry))
  Error -> Error)

(define urt.b-world
  -> (urt.b-world-of
       (urt.b-registry-of
         (urdr.scenario.validate (urt.scenario-value)))))

(define urt.proc-name -> (urt.k "proc-a"))

(define urt.b-component-input
  N ->
    [schedule (urdr.int.zero) component
      [component-input (urt.proc-name) (urt.bump N)]])

(define urt.b-choice-input
  -> [schedule (urdr.int.zero) choice
       [choice (urt.k "net") (urt.k "a") (urt.k "delivery")
         [(urt.big 1) (urt.big 2)]]])

(define urt.b-property-input
  -> [schedule (urdr.int.zero) property-equals
       [property (urt.s "p-eq") (urt.big 7) (urt.big 7)]])

(define urt.b-command-input
  -> [schedule (urdr.int.zero) command
       [record [[(urt.k "op") (urt.s "noop")]]]])

\\ All four reducer event kinds, each scheduled and then dispatched, so
\\ the log carries all eight event types.
(define urt.b-transcript
  -> [(urt.b-component-input 1) (urt.advance)
      (urt.b-choice-input) (urt.advance)
      (urt.b-property-input) (urt.advance)
      (urt.b-command-input) (urt.advance)])

\\ ---------------------------------------------------------------
\\ Properties over the fixture B trace. Three verdicts, chosen so the
\\ certificate has to surface all three shapes: a PASS that fired, a PASS
\\ that never fired (`vacuous`), and a FAIL.
\\ ---------------------------------------------------------------

(define urt.node
  Op Args ->
    [record
      [[(urdr.properties.n.args) [list Args]]
       [(urdr.properties.n.op) [symbol Op]]]])

(define urt.pattern
  Name ->
    [record
      [[(urdr.properties.n.name) [symbol Name]]
       [(urdr.properties.n.source) [null]]
       [(urdr.properties.n.value) [null]]]])

(define urt.observations
  -> [[observation (urdr.int.zero) (urt.k "p0")]])

\\ PASS that fired: at observation p0 a `tick` fact exists.
(define urt.prop-invariant
  -> [property (urdr.properties.n.invariant) (urt.k "i-tick")
       [record
         [[(urdr.properties.n.points) [list [(urt.s "p0")]]]
          [(urdr.properties.n.pred)
           (urt.node (urdr.properties.n.defined)
             [(urt.node (urdr.properties.n.fact)
                [[symbol (urt.k "tick")]])])]]]])

\\ PASS with `vacuous`: the antecedent never matches anywhere in the
\\ trace, so the universally quantified implication is true over an empty
\\ antecedent set and properties.shen marks it distinctly. A certificate
\\ that folded this into no-witness would be claiming evidence it does
\\ not have.
(define urt.prop-vacuous
  -> [property (urdr.properties.n.temporal) (urt.k "t-vacuous")
       [record
         [[(urdr.properties.n.args)
           [list
             [(urt.pattern (urt.k "never-emitted"))
              (urt.pattern (urt.k "tick"))
              (urt.big 5)]]]
          [(urdr.properties.n.form)
           [symbol (urdr.properties.n.always-eventually)]]]]])

\\ FAIL: nothing ever matches, so the deadline cannot be met.
(define urt.prop-liveness
  -> [property (urdr.properties.n.liveness) (urt.k "l-missing")
       [record
         [[(urdr.properties.n.deadline) (urt.big 3)]
          [(urdr.properties.n.pattern)
           (urt.pattern (urt.k "never-emitted"))]]]])

\\ properties.shen requires a strictly ascending property-id order, so
\\ the declaration order is i-tick, l-missing, t-vacuous.
(define urt.properties
  -> [(urt.prop-invariant) (urt.prop-liveness) (urt.prop-vacuous)])

\\ ---------------------------------------------------------------
\\ Baseline descriptors for marker propagation. A baseline descriptor is
\\ the canonical value that says where the run's network baseline came
\\ from; the certificate derives markers from it and never accepts a
\\ marker name directly.
\\ ---------------------------------------------------------------

(define urt.pod
  Name Address Role ->
    [record
      [[(urdr.netpol.key k-address) [text Address]]
       [(urdr.netpol.key k-labels)
        [record [[(urt.k "role") [text Role]]]]]
       [(urdr.netpol.key k-name) [text Name]]
       [(urdr.netpol.key k-namespace) [text (urt.k "default")]]]])

(define urt.netpol-universe
  -> [record
       [[(urdr.netpol.key k-namespaces)
         [list [[record [[(urdr.netpol.key k-name)
                          [text (urt.k "default")]]]]]]]
        [(urdr.netpol.key k-pods)
         [list
           [(urt.pod (urt.k "p0") (urt.k "10.0.0.0") (urt.k "v0"))
            (urt.pod (urt.k "p1") (urt.k "10.0.0.1") (urt.k "v1"))]]]
        [(urdr.netpol.key k-ports) [list [(urt.big 80)]]]
        [(urdr.netpol.key k-protocols)
         [list [[symbol (urdr.netpol.word w-tcp)]]]]]])

\\ A real compile, so the marker the certificate propagates is the
\\ compiler's own output and not a constant restated here.
(define urt.policy-baseline
  -> (urt.policy-baseline-of
       (urdr.netpol.check-compile (urt.netpol-universe) [list []])))

(define urt.policy-baseline-of
  [ok Compiled] -> (urdr.netpol.compiled-value Compiled)
  _ -> [null])

\\ The descriptor a run carries over an unrestricted fabric: the NetKAT
\\ identity term. It has no `marker` key, so it contributes no marker.
(define urt.open-baseline -> (urt.nk-baseline))

\\ ---------------------------------------------------------------
\\ Case group 1: the node counter against the canonical codec.
\\ ---------------------------------------------------------------

\\ [list N nulls] parses to 2 + 2N nodes. The m0 profile admits exactly
\\ 256, so N = 127 must encode and N = 128 must not. If
\\ urdr.eventlog.nodes ever disagreed with the decoder, content
\\ addressing would inline a payload that then failed to encode.
(define urt.node-case
  N Expected ->
    (/. Unit
      (urt.node-case-h N Expected
        (urdr.eventlog.nodes [list (urt.nulls N [])])
        (urdr.canonical.encode-payload [list (urt.nulls N [])]))))

(define urt.node-case-h
  N Expected Counted [ok _] ->
    (if (= Counted Expected)
        (do (output "NODES|~A|~A|ok~%" N Counted) true)
        (urt.fail "nodes" "counter-disagrees"))
  N Expected Counted [error E] ->
    (if (= Counted Expected)
        (do (output "NODES|~A|~A|~A~%" N Counted E) true)
        (urt.fail "nodes" "counter-disagrees")))

(define urt.node-cases
  -> [(urt.node-case 127 256) (urt.node-case 128 258)])

\\ ---------------------------------------------------------------
\\ Case group 2: content addressing.
\\ ---------------------------------------------------------------

(define urt.slot-kind
  Value ->
    (urt.slot-kind-of
      (urdr.certificate.field-of (urt.k "type") Value)))

(define urt.slot-kind-of
  [some [symbol [99 111 110 116 101 110 116 45 97 100 100 114 101
                 115 115]]] -> "address"
  [some [symbol [99 111 110 116 101 110 116 45 97 100 100 114 101
                 115 115 45 108 105 115 116]]] -> "address-list"
  _ -> "inline")

(define urt.slot-case
  Name Value Expected ->
    (/. Unit
      (urt.slot-case-h Name Expected (urdr.eventlog.slot Value))))

(define urt.slot-case-h
  Name Expected [ok Slot] ->
    (let Kind (urt.slot-kind Slot)
      (if (= Kind Expected)
          (do (output "CA|~A|~A|~A~%" Name Kind (urt.enc-hex Slot))
              true)
          (urt.fail Name (cn "slot-kind-" Kind))))
  Name Expected [error Code Detail] -> (urt.fail Name "slot-error"))

(define urt.list-slot-case
  Name Values Expected ->
    (/. Unit
      (urt.slot-case-h Name Expected
        (urdr.eventlog.list-slot (urt.k "urdr-test-list-v1") Values))))

\\ The ADR 0002 m0 profile caps a single atom at 256 octets, so a large
\\ payload is necessarily a composite. [bytes Bs] encodes to
\\ 10 + digits(|Bs|) + |Bs| octets and [list Vs] to 8 + sum, so a list of
\\ three 250-octet chunks plus a 214-octet chunk is exactly the
\\ 1024-octet inline threshold and a 215-octet last chunk is one over.
\\ [list N nulls] is 2 + 2N nodes and 8 + 8N octets, so 47 nulls is
\\ exactly the 96-node threshold and 48 is over it while staying far
\\ inside the octet bound: both thresholds are load-bearing and each is
\\ pinned in isolation.
(define urt.chunk
  -> [bytes (urt.rep 250 66 [])])

(define urt.chunks
  0 Acc -> Acc
  N Acc -> (urt.chunks (- N 1) [(urt.chunk) | Acc]))

(define urt.tail-chunk
  N -> [bytes (urt.rep N 67 [])])

(define urt.ca-cases
  -> [(urt.slot-case "inline-small" (urt.big 7) "inline")
      (urt.slot-case "inline-octet-boundary"
        [list (append (urt.chunks 3 []) [(urt.tail-chunk 214)])]
        "inline")
      (urt.slot-case "address-octet-boundary"
        [list (append (urt.chunks 3 []) [(urt.tail-chunk 215)])]
        "address")
      (urt.slot-case "inline-node-boundary"
        [list (urt.nulls 47 [])] "inline")
      (urt.slot-case "address-node-boundary"
        [list (urt.nulls 48 [])] "address")
      (urt.list-slot-case "list-inline"
        [(urt.big 1) (urt.big 2)] "inline")
      (urt.list-slot-case "list-address"
        (urt.nulls 60 []) "address-list")])

\\ ---------------------------------------------------------------
\\ Case group 3: event records.
\\ ---------------------------------------------------------------

(define urt.types-of
  [] -> ""
  [R] -> (urt.string (urdr.eventlog.record-type R))
  [R | Rest] ->
    (cn (cn (urt.string (urdr.eventlog.record-type R)) ",")
        (urt.types-of Rest)))

(define urt.log-lines
  Name Log ->
    (do
      (output "EL|~A|~A~%" Name (urt.hex (urdr.eventlog.root Log)))
      (output "ELT|~A|~A~%" Name
        (urt.types-of (urdr.eventlog.records Log)))
      (output "ELC|~A|~A~%" Name
        (urt.enc-hex (urdr.eventlog.counts-value Log)))
      (if (urdr.eventlog.abstract? Log)
          true
          (urt.fail Name "non-abstract-classification"))))

(define urt.log-case
  Name World Transcript ->
    (/. Unit
      (urt.log-case-h Name (urdr.eventlog.of-run World Transcript))))

(define urt.log-case-h
  Name [ok Log] -> (urt.log-lines Name Log)
  Name [error Code Detail] -> (urt.fail Name "log-error"))

\\ Every record's canonical form, pinned: this is the SPEC.md 20 schema
\\ itself, key order included.
(define urt.record-case
  Name World Transcript ->
    (/. Unit
      (urt.record-case-h Name
        (urdr.eventlog.of-run World Transcript))))

(define urt.record-case-h
  Name [ok Log] ->
    (urt.record-lines Name 0 (urdr.eventlog.records Log))
  Name _ -> (urt.fail Name "log-error"))

(define urt.record-lines
  Name _ [] -> true
  Name I [R | Rest] ->
    (do
      (output "EL|~A-~A|~A~%" Name I
        (urt.enc-hex (urdr.eventlog.record-value R)))
      (urt.record-lines Name (+ I 1) Rest)))

\\ Eight 250-octet chunks: 2112 encoded octets and 26 nodes. That is a
\\ valid m0 canonical value, so urdr.world.event-valid? accepts it and
\\ the reducer queues it, and it is twice the inline threshold, so the
\\ event record must carry a content address instead of the payload.
(define urt.big-transcript
  -> [[schedule (urdr.int.zero) command
        [list (urt.chunks 8 [])]]
      (urt.advance)])

(define urt.payload-of
  [some Value] -> Value
  _ -> [null])

(define urt.payload-kind
  Record ->
    (urt.slot-kind
      (urt.payload-of
        (urdr.certificate.field-of
          (urt.k "payload") (urdr.eventlog.record-value Record)))))

(define urt.big-payload-case
  -> (/. Unit
       (urt.big-payload-h
         (urdr.eventlog.of-run (urt.a-world) (urt.big-transcript)))))

(define urt.big-payload-h
  [ok Log] -> (urt.big-payload-records (urdr.eventlog.records Log))
  _ -> (urt.fail "big-payload" "log-error"))

(define urt.big-payload-records
  [Schedule | _] ->
    (let Kind (urt.payload-kind Schedule)
      (if (= Kind "address")
          (do
            (output "EL|content-addressed-payload|~A~%"
              (urt.enc-hex (urdr.eventlog.record-value Schedule)))
            true)
          (urt.fail "big-payload" (cn "payload-" Kind))))
  _ -> (urt.fail "big-payload" "no-records"))

\\ Fail-closed event-log construction. These never reach replay
\\ verification because they never produce a log at all.
(define urt.log-reject
  Name World Transcript Expected ->
    (/. Unit
      (urt.log-reject-h Name Expected
        (urdr.eventlog.of-run World Transcript))))

(define urt.log-reject-h
  Name Expected [error Code Detail] ->
    (if (= Code Expected)
        (do (output "DIV|~A|~A~%" Name Code) true)
        (urt.fail Name "wrong-code"))
  Name Expected _ -> (urt.fail Name "unexpected-ok"))

(define urt.log-cases
  -> [(urt.log-case "fixture-a" (urt.a-world) (urt.a-transcript))
      (urt.record-case "record" (urt.a-world) (urt.a-transcript))
      (urt.big-payload-case)
      (urt.log-reject "no-pending-event" (urt.a-world)
        [(urt.advance)] eventlog-no-pending-event)
      (urt.log-reject "input-shape" (urt.a-world)
        [[rollback [null]]] eventlog-input-shape)
      (urt.log-reject "invalid-world" [world/v2] []
        eventlog-invalid-world)
      (urt.log-reject "reduction-error" (urt.a-world)
        [[schedule (urdr.int.zero) component
           [component-input (urt.k "absent") (urt.bump 1)]]
         (urt.advance)]
        eventlog-reduction-error)])

\\ ---------------------------------------------------------------
\\ Case group 4: the transcript writer and reader.
\\ ---------------------------------------------------------------

(define urt.roundtrip-case
  Name Transcript ->
    (/. Unit
      (urt.roundtrip-h Name Transcript
        (urdr.replay.write Transcript))))

(define urt.roundtrip-h
  Name Transcript [ok Values] ->
    (if (= (urdr.replay.read Values) [ok Transcript])
        (do
          (output "RT|~A|~A~%" Name
            (urt.result-enc-hex
              (urdr.replay.transcript-value Transcript)))
          true)
        (urt.fail Name "round-trip"))
  Name Transcript [error Code Detail] -> (urt.fail Name "write-error"))

(define urt.roundtrip-reject
  Name Value ->
    (/. Unit
      (urt.roundtrip-reject-h Name (urdr.replay.entry-of Value))))

(define urt.roundtrip-reject-h
  Name [error Code Detail] ->
    (do (output "RT|~A|~A~%" Name Code) true)
  Name _ -> (urt.fail Name "unexpected-accept"))

(define urt.rt-cases
  -> [(urt.roundtrip-case "fixture-a" (urt.a-transcript))
      (urt.roundtrip-case "fixture-b" (urt.b-transcript))
      (urt.roundtrip-case "selected" (urt.sel-transcript (urt.big 2)))
      (urt.roundtrip-case "empty" [])
      (urt.roundtrip-reject "unknown-entry" [record []])
      (urt.roundtrip-reject "unknown-kind"
        [record
          [[(urt.k "at") (urdr.int.zero)]
           [(urt.k "kind") (urt.s "event-input")]
           [(urt.k "payload") [null]]
           [(urt.k "type") (urt.s "schedule")]]])
      \\ A selected entry whose coordinate record is not the PRNG's is
      \\ a shape error on read, never a silent repair.
      (urt.roundtrip-reject "selected-bad-coordinate"
        [record
          [[(urt.k "at") (urdr.int.zero)]
           [(urt.k "kind") (urt.s "choice-input")]
           [(urt.k "payload")
            [record
              [[(urt.k "actor") [bytes (urt.k "a")]]
               [(urt.k "alternatives") [list (urt.sel-alts)]]
               [(urt.k "coordinates") [list [[record []]]]]
               [(urt.k "purpose") [bytes (urt.k "delivery")]]
               [(urt.k "selected") (urt.big 2)]
               [(urt.k "subsystem") [bytes (urt.k "net")]]]]]
           [(urt.k "type") (urt.s "schedule")]]])])

\\ ---------------------------------------------------------------
\\ Case group 5: the end-to-end pipeline. Driven exactly once here; the
\\ certificate it builds re-drives twice more of its own accord, which is
\\ the point of the replay field.
\\ ---------------------------------------------------------------

(define urt.field-string
  [some [symbol Bs]] -> (urt.string Bs)
  _ -> "?")

(define urt.witness-kind-of
  [some [symbol Bs]] -> (urt.string Bs)
  [some [record _]] -> "record"
  _ -> "?")

(define urt.verdict-line
  Value ->
    (do
      (output "PROP|~A|~A|~A~%"
        (urt.field-string
          (urdr.certificate.field-of
            (urdr.properties.n.property) Value))
        (urt.field-string
          (urdr.certificate.field-of
            (urdr.properties.n.result) Value))
        (urt.witness-kind-of
          (urdr.certificate.field-of
            (urdr.properties.n.witness) Value)))
      true))

(define urt.verdict-lines
  [] -> true
  [V | Rest] ->
    (let Ok (urt.verdict-line V)
      (urt.verdict-lines Rest)))

\\ A property-layer refusal is surfaced by code, never folded into an
\\ empty verdict list: a certificate over zero verdicts would otherwise
\\ report PASS and the case would pass while proving nothing.
(define urt.verdicts-of
  [ok Trace] ->
    (urt.verdict-values-of
      (urdr.properties.check
        (urt.properties) (urt.observations) Trace))
  [error E] -> [verdicts-error E])

(define urt.verdict-values-of
  [ok Verdicts] -> (urdr.properties.verdict-values Verdicts)
  [error E] -> [verdicts-error E])

(define urt.e2e-case
  -> (/. Unit (urt.e2e-world (urt.b-world))))

(define urt.e2e-world
  World ->
    (urt.e2e-run World (urdr.replay.run World (urt.b-transcript))))

(define urt.e2e-run
  World [ok Run] ->
    (let Log (urdr.replay.run-log Run)
         Verdicts (urt.verdicts-of
                    (urdr.properties.trace-of-world
                      (urdr.eventlog.final-world Log)))
         A (urt.e2e-lines Run Log)
         B (urt.e2e-verdicts Verdicts)
         C (urt.signature-lines Verdicts)
         D (urt.cert-line "e2e" Verdicts [(urt.open-baseline)]
             World (urt.b-transcript) false)
      (urt.both A (urt.both B (urt.both C D))))
  World _ -> (urt.fail "e2e" "run-error"))

\\ The comparison the Wave F shrinker performs to decide whether a
\\ candidate transcript preserved the failure. Pinned here so the
\\ acceptance rule is a fixture, not a convention.
(define urt.sig-hex
  [ok D] -> (urt.hex D)
  _ -> "signature-error")

(define urt.signature-lines
  [verdicts-error E] -> (urt.fail "signature" E)
  Verdicts ->
    (let Sig (urdr.certificate.failure-signature Verdicts)
         Passes (urdr.certificate.failure-signature
                  (urt.passing-only Verdicts))
         Same (urdr.certificate.failure-signature
                (urt.failing-only Verdicts))
      (do
        (output "SIG|e2e|~A~%" (urt.sig-hex Sig))
        (output "SIG|no-failure|~A~%" (urt.sig-hex Passes))
        (output "SIG|persists|~A~%" (= Sig Same))
        (output "SIG|differs|~A~%"
          (not (= Sig
                  (urdr.certificate.failure-signature
                    (urt.relabelled Verdicts)))))
        (urt.both (not (= Sig Passes)) (= Sig Same)))))

\\ Dropping every FAIL leaves a different signature; keeping only the
\\ FAILs leaves the same one. Together those are the two directions a
\\ shrinker relies on.
(define urt.passing-only
  [] -> []
  [V | Rest] ->
    (if (= (urdr.certificate.verdict-result V)
           [some (urdr.properties.n.FAIL)])
        (urt.passing-only Rest)
        [V | (urt.passing-only Rest)]))

(define urt.failing-only
  [] -> []
  [V | Rest] ->
    (if (= (urdr.certificate.verdict-result V)
           [some (urdr.properties.n.FAIL)])
        [V | (urt.failing-only Rest)]
        (urt.failing-only Rest)))

\\ The same property failing under a different name is a different
\\ failure, so the signature must move.
(define urt.relabelled
  Verdicts -> (urt.relabel (urt.failing-only Verdicts)))

(define urt.relabel
  [] -> []
  [[record Fields] | Rest] ->
    [[record (urt.relabel-fields Fields)] | (urt.relabel Rest)]
  [V | Rest] -> [V | (urt.relabel Rest)])

(define urt.relabel-fields
  [] -> []
  [[Key Value] | Rest] ->
    (if (= Key (urdr.properties.n.property))
        [[Key (urt.s "l-other")] | (urt.relabel-fields Rest)]
        [[Key Value] | (urt.relabel-fields Rest)])
  _ -> [])

(define urt.e2e-lines
  Run Log ->
    (do
      (output "E2E|transcript-root|~A~%"
        (urt.hex (urdr.replay.run-transcript-root Run)))
      (output "E2E|count|~A~%" (urdr.replay.run-count Run))
      (output "E2E|recorded|~A~%"
        (urt.enc-hex
          (urdr.replay.recorded-value (urdr.replay.recorded Run))))
      (urt.log-lines "fixture-b" Log)))

(define urt.e2e-verdicts
  [verdicts-error E] -> (urt.fail "verdicts" E)
  Verdicts ->
    (if (= (urt.count Verdicts) 3)
        (urt.verdict-lines Verdicts)
        (urt.fail "verdicts" "unexpected-count")))

\\ ---------------------------------------------------------------
\\ Case group 6: the divergence taxonomy.
\\ ---------------------------------------------------------------

(define urt.recorded-of
  [ok Run] -> (urdr.replay.recorded Run)
  Other -> Other)

(define urt.div-case
  Name World Transcript Recorded Expected ->
    (/. Unit
      (urt.div-h Name Expected
        (urdr.replay.verify World Transcript Recorded))))

(define urt.div-h
  Name Expected [error Code Detail] ->
    (if (= Code Expected)
        (do
          (output "DIV|~A|~A~%" Name Code)
          (output "DIVD|~A|~A~%" Name
            (urt.enc-hex (urdr.replay.error-value Code Detail)))
          true)
        (urt.fail Name "wrong-code"))
  Name Expected [ok _] -> (urt.fail Name "unexpected-ok"))

(define urt.ok-case
  Name World Transcript Recorded ->
    (/. Unit
      (urt.ok-h Name (urdr.replay.verify World Transcript Recorded))))

(define urt.ok-h
  Name [ok Verified] ->
    (do
      (output "DIV|~A|~A~%" Name
        (urt.enc-hex (urdr.replay.verified-value Verified)))
      true)
  Name [error Code Detail] -> (urt.fail Name "unexpected-error"))

\\ A forged artifact with one extra event digest. The transcript still
\\ matches, so the guard on stream length is what has to catch it.
(define urt.forge-count
  [recorded Entries TRoot Events ERoot SRoot] ->
    [recorded Entries TRoot (append Events [(urt.rep 32 7 [])])
      ERoot SRoot]
  Other -> Other)

(define urt.div-cases
  ARecorded EmptyRecorded ->
    [(urt.ok-case "verified" (urt.a-world) (urt.a-transcript)
       ARecorded)
     (urt.div-case "truncated" (urt.a-world) (urt.a-truncated)
       ARecorded replay-transcript-truncated)
     (urt.div-case "extended" (urt.a-world) (urt.a-extended)
       ARecorded replay-transcript-extended)
     (urt.div-case "reordered" (urt.a-world) (urt.a-reordered)
       ARecorded replay-transcript-reordered)
     (urt.div-case "tampered" (urt.a-world) (urt.a-tampered)
       ARecorded replay-transcript-tampered)
     (urt.div-case "event-divergence" (urt.a-world-other)
       (urt.a-transcript) ARecorded replay-event-divergence)
     (urt.div-case "state-divergence" (urt.a-world-other) []
       EmptyRecorded replay-state-divergence)
     (urt.div-case "event-count" (urt.a-world) (urt.a-transcript)
       (urt.forge-count ARecorded) replay-event-count)
     (urt.div-case "recorded-shape" (urt.a-world) (urt.a-transcript)
       [not-a-recorded-artifact] replay-recorded-shape)
     (urt.div-case "entry-shape" (urt.a-world) [[rollback [null]]]
       ARecorded replay-entry-shape)])

\\ ---------------------------------------------------------------
\\ Case group 6b: pinned selections (ADR 0007 D2). (a) A run whose
\\ transcript pins a selection logs, verifies, and re-drives to the
\\ identical event stream; (b) the selection tampered to ANOTHER VALID
\\ member is caught twice over -- against the honest artifact as
\\ replay-transcript-tampered (entry digests moved), and against a
\\ re-entried artifact as replay-event-divergence (the event streams
\\ disagree; the state roots alone never would); (c) tampered to a
\\ NON-member, the world's membership door refuses the recorded
\\ decision during the re-drive and verification classifies it
\\ replay-selection-divergence (section 3 of replay.shen: the artifact
\\ matched, so the refusal is engine/artifact disagreement, DIVERGED
\\ family).
\\ ---------------------------------------------------------------

(define urt.selected-cases
  SelRecorded ->
    [(urt.log-case "selected" (urt.a-world)
       (urt.sel-transcript (urt.big 2)))
     (urt.ok-case "selected-verified" (urt.a-world)
       (urt.sel-transcript (urt.big 2)) SelRecorded)
     (urt.div-case "selected-tampered" (urt.a-world)
       (urt.sel-transcript (urt.big 1)) SelRecorded
       replay-transcript-tampered)
     (urt.div-case "selected-member-divergence" (urt.a-world)
       (urt.sel-transcript (urt.big 1))
       (urt.reentried (urt.sel-transcript (urt.big 1)) SelRecorded)
       replay-event-divergence)
     (urt.div-case "selected-not-member" (urt.a-world)
       (urt.sel-transcript (urt.big 3))
       (urt.reentried (urt.sel-transcript (urt.big 3)) SelRecorded)
       replay-selection-divergence)])

\\ ---------------------------------------------------------------
\\ Case group 7: run-id mutations. Every field of the SPEC.md 4 preimage
\\ must move the run id.
\\ ---------------------------------------------------------------

(define urt.root-of
  [ok Root] -> Root
  Other -> Other)

(define urt.engine -> (urt.k "urdr-m1"))
(define urt.profile -> (urt.k "modeled"))
(define urt.manifest -> [list []])

(define urt.mut-case
  Name Base Mutated ->
    (/. Unit (urt.mut-h Name Base Mutated)))

(define urt.mut-h
  Name [ok Base] [ok Other] ->
    (if (= Base Other)
        (urt.fail Name "run-id-unchanged")
        (do
          (output "MUT|~A|~A|~A~%" Name (urt.hex Base) (urt.hex Other))
          true))
  Name _ _ -> (urt.fail Name "run-id-error"))

(define urt.mut-cases
  Base ARoot TRoot ->
    [(urt.mut-case "engine-version" Base
       (urdr.certificate.run-id-of
         (urt.k "urdr-m1-forged") (urt.scenario-value) (urt.manifest)
         (urt.a-world) ARoot (urt.profile)))
     (urt.mut-case "scenario" Base
       (urdr.certificate.run-id-of
         (urt.engine) [list [(urt.big 1)]] (urt.manifest)
         (urt.a-world) ARoot (urt.profile)))
     (urt.mut-case "artifact-manifest" Base
       (urdr.certificate.run-id-of
         (urt.engine) (urt.scenario-value) [list [(urt.big 2)]]
         (urt.a-world) ARoot (urt.profile)))
     (urt.mut-case "initial-state" Base
       (urdr.certificate.run-id-of
         (urt.engine) (urt.scenario-value) (urt.manifest)
         (urt.a-world-other) ARoot (urt.profile)))
     (urt.mut-case "decision-transcript" Base
       (urdr.certificate.run-id-of
         (urt.engine) (urt.scenario-value) (urt.manifest)
         (urt.a-world) TRoot (urt.profile)))
     (urt.mut-case "requested-profile" Base
       (urdr.certificate.run-id-of
         (urt.engine) (urt.scenario-value) (urt.manifest)
         (urt.a-world) ARoot (urt.k "modeled-strict")))
     \\ ADR 0008 D3: a model binding is not a preimage field, yet it
     \\ must move the run id — transitively, because the initial
     \\ snapshot (field 3) binds every entry's META. This is the
     \\ executable form of the no-new-preimage-field argument.
     (urt.mut-case "model-binding" Base
       (urdr.certificate.run-id-of
         (urt.engine) (urt.scenario-value) (urt.manifest)
         (urt.a-world-modeled) ARoot (urt.profile)))])

\\ ---------------------------------------------------------------
\\ Case group 8: marker derivation and certificates.
\\ ---------------------------------------------------------------

(define urt.markers-string
  [] -> ""
  [M] -> (urt.string M)
  [M | Rest] -> (cn (cn (urt.string M) ",") (urt.markers-string Rest)))

(define urt.marker-case
  Name Baselines Expected ->
    (/. Unit
      (urt.marker-h Name Expected
        (urdr.certificate.markers-of-all Baselines))))

(define urt.marker-h
  Name Expected Markers ->
    (let Line (urt.markers-string Markers)
      (if (= Line Expected)
          (do (output "MARK|~A|~A~%" Name Line) true)
          (urt.fail Name (cn "markers-" Line)))))

(define urt.marker-cases
  Policy ->
    [(urt.marker-case "open-fabric" [(urt.open-baseline)] "")
     (urt.marker-case "compiled-policy" [Policy]
       "spec-semantics-only")
     (urt.marker-case "both" [(urt.open-baseline) Policy]
       "spec-semantics-only")
     (urt.marker-case "unrelated-value" [[record []]] "")])

(define urt.cert-line
  Name Verdicts Baselines World Transcript Full ->
    (urt.cert-h Name Full
      (urdr.certificate.build
        (urdr.certificate.spec
          (urt.engine) (urt.scenario-value) (urt.manifest)
          (urt.profile) World Transcript Verdicts Baselines))))

(define urt.cert-h
  Name Full [ok Cert] ->
    (do
      (output "CERT|~A|~A|~A|~A|~A~%" Name
        (urt.string (urdr.certificate.status Cert))
        (urt.string (urdr.certificate.achieved-profile Cert))
        (urt.markers-string (urdr.certificate.markers Cert))
        (urt.hex (urdr.certificate.run-id Cert)))
      (output "CERTS|~A|~A~%" Name
        (urt.enc-hex (urdr.certificate.verdict-summary Cert)))
      (output "CERTD|~A|~A~%" Name
        (urt.digest-hex (urdr.certificate.value Cert)))
      (urt.cert-full Name Full Cert))
  Name Full [error Code Detail] -> (urt.fail Name "certificate-error"))

(define urt.cert-full
  Name true Cert ->
    (do
      (output "CERTF|~A|~A~%" Name
        (urt.enc-hex (urdr.certificate.value Cert)))
      true)
  Name false Cert -> true)

(define urt.cert-case
  Name Verdicts Baselines World Transcript Full ->
    (/. Unit
      (urt.cert-line Name Verdicts Baselines World Transcript Full)))

(define urt.cert-reject
  Name Spec Expected ->
    (/. Unit
      (urt.cert-reject-h Name Expected (urdr.certificate.build Spec))))

(define urt.cert-reject-h
  Name Expected [error Code Detail] ->
    (if (= Code Expected)
        (do (output "CERT|~A|~A~%" Name Code) true)
        (urt.fail Name "wrong-code"))
  Name Expected _ -> (urt.fail Name "unexpected-ok"))

(define urt.bad-verdict
  -> [record [[(urt.k "property") (urt.s "x")]]])

\\ ADR 0008 D2: the certificate's `models` field is the sorted binding
\\ list of the INITIAL world's registry. Checked against the expected
\\ value (accessor and canonical field both), then pinned canonically
\\ in the golden — not merely printed. The empty transcript keeps the
\\ three drives this build performs cheap: the field comes from the
\\ initial registry, not from the run.
(define urt.expected-models
  -> [list [[record
              [[(urt.k "component") [symbol (urt.a-name)]]
               [(urt.k "model") [symbol (urt.k "m-alt")]]
               [(urt.k "node") [null]]]]]])

(define urt.models-case
  -> (/. Unit
       (urt.models-h
         (urdr.certificate.build
           (urdr.certificate.spec
             (urt.engine) (urt.scenario-value) (urt.manifest)
             (urt.profile) (urt.a-world-modeled) [] [] [])))))

(define urt.models-h
  [ok Cert] ->
    (if (and (= [list (urdr.certificate.models Cert)]
                (urt.expected-models))
             (= (urdr.certificate.field-of
                  (urt.k "models") (urdr.certificate.value Cert))
                [some (urt.expected-models)]))
        (do
          (output "CERT|models|~A~%" (urt.enc-hex (urt.expected-models)))
          true)
        (urt.fail "models" "field-mismatch"))
  _ -> (urt.fail "models" "certificate-error"))

(define urt.cert-cases
  Policy ->
    [(urt.cert-case "minimal" [] [(urt.open-baseline)]
       (urt.a-world) (urt.a-transcript) true)
     (urt.cert-case "policy-baseline" [] [Policy]
       (urt.a-world) (urt.a-transcript) false)
     (urt.cert-reject "reject-verdict-shape"
       (urdr.certificate.spec
         (urt.engine) (urt.scenario-value) (urt.manifest)
         (urt.profile) (urt.a-world) (urt.a-transcript)
         [(urt.bad-verdict)] [])
       certificate-verdict-shape)
     (urt.cert-reject "reject-engine-version"
       (urdr.certificate.spec
         [not-octets] (urt.scenario-value) (urt.manifest)
         (urt.profile) (urt.a-world) (urt.a-transcript) [] [])
       certificate-engine-version)
     (urt.cert-reject "reject-spec-shape" [not-a-spec]
       certificate-spec-shape)
     (urt.models-case)])

\\ ---------------------------------------------------------------
\\ Case group 9: 100 consecutive replays (plan Wave E acceptance).
\\ ---------------------------------------------------------------

(define urt.loop-roots
  Run ->
    (append (urdr.replay.run-event-root Run)
            (urdr.replay.run-state-root Run)))

(define urt.loop-drive
  -> (urdr.replay.run (urt.a-world) (urt.loop-transcript)))

(define urt.loop-first
  [ok Run] -> (urt.loop-rest 99 (urt.loop-roots Run))
  _ -> none)

(define urt.loop-rest
  0 Roots -> Roots
  N Roots -> (urt.loop-check N Roots (urt.loop-drive)))

(define urt.loop-check
  N Roots [ok Run] ->
    (if (= Roots (urt.loop-roots Run))
        (urt.loop-rest (- N 1) Roots)
        none)
  N Roots _ -> none)

(define urt.loop-case
  -> (/. Unit (urt.loop-h (urt.loop-first (urt.loop-drive)))))

(define urt.loop-h
  none -> (urt.fail "loop" "replay-not-identical")
  Roots -> (do (output "LOOP|100|~A~%" (urt.hex Roots)) true))

\\ ---------------------------------------------------------------
\\ Driver.
\\ ---------------------------------------------------------------

\\ Thunks are applied strictly in list order, so the semantic output is a
\\ function of this file alone and never of the host's evaluation order
\\ inside a list literal.
(define urt.run-thunks
  [] Ok -> Ok
  [T | Ts] Ok ->
    (let R (T 0)
      (urt.run-thunks Ts (if R Ok false))))

(define urt.cases
  -> (let ARecorded (urt.recorded-of
                      (urdr.replay.run (urt.a-world)
                        (urt.a-transcript)))
          SelRecorded (urt.recorded-of
                        (urdr.replay.run (urt.a-world)
                          (urt.sel-transcript (urt.big 2))))
          EmptyRecorded (urt.recorded-of
                          (urdr.replay.run (urt.a-world) []))
          ARoot (urt.root-of
                  (urdr.replay.transcript-root (urt.a-transcript)))
          TRoot (urt.root-of
                  (urdr.replay.transcript-root (urt.a-tampered)))
          Base (urdr.certificate.run-id-of
                 (urt.engine) (urt.scenario-value) (urt.manifest)
                 (urt.a-world) ARoot (urt.profile))
          Policy (urt.policy-baseline)
       (urt.concat
         [(urt.node-cases)
          (urt.ca-cases)
          (urt.log-cases)
          (urt.rt-cases)
          [(urt.e2e-case)]
          (urt.div-cases ARecorded EmptyRecorded)
          (urt.selected-cases SelRecorded)
          (urt.mut-cases Base ARoot TRoot)
          (urt.marker-cases Policy)
          (urt.cert-cases Policy)
          [(urt.loop-case)]])))

(define urt.run
  -> (let Cases (urt.cases)
          Ok (urt.run-thunks Cases true)
       (do
         (output "REPLAY CASES: ~A~%" (urt.count Cases))
         (if Ok
             (do (output "ALL PASS~%") true)
             (do (output "REPLAY: FAIL~%") false)))))

(urt.run)
