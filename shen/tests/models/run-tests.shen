\\ Plan Wave C (components) conformance suite: the abstract network,
\\ timer, and fault models on the ADR 0004 Decision 1 component
\\ interface, their composition glue, and the NetKAT counterexample
\\ witness bridge. Every semantic line is projected by
\\ shen/tests/models/test.sh and compared against the checked-in golden on
\\ each required port.

(define umt.eval-forms
  [] -> loaded
  [[load _] | Forms] -> (umt.eval-forms Forms)
  [Form | Forms] ->
    (let Ignored (eval Form)
      (umt.eval-forms Forms)))

(define umt.quiet-load
  File -> (umt.eval-forms (read-file File)))

(umt.quiet-load "shen/protocol/canonical.shen")
(umt.quiet-load "shen/world/integer.shen")
(umt.quiet-load "shen/world/prng.shen")
(umt.quiet-load "shen/world/netkat.shen")
(umt.quiet-load "shen/world/component.shen")
(umt.quiet-load "shen/world/world.shen")
(umt.quiet-load "shen/scenario/scenario.shen")
(umt.quiet-load "shen/world/models/common.shen")
(umt.quiet-load "shen/world/models/mask.shen")
(umt.quiet-load "shen/world/models/net.shen")
(umt.quiet-load "shen/world/models/timer.shen")
(umt.quiet-load "shen/world/models/fault.shen")
(umt.quiet-load "shen/world/models/registry.shen")
(umt.quiet-load "shen/world/netkat-witness.shen")

\\ ---------------------------------------------------------------
\\ Reporting
\\ ---------------------------------------------------------------

(define umt.string
  [] -> ""
  [B | Bs] -> (cn (n->string B) (umt.string Bs)))

(define umt.hex
  Bs -> (hd (tl (urdr.bytes.hex Bs))))

(define umt.big
  N -> (hd (tl (urdr.int.from-small N))))

\\ Cases are built as data and printed by one explicit left-to-right fold.
\\ The four pinned ports do NOT agree on the evaluation order of the
\\ elements of a list literal -- shen-lua evaluates them right to left and
\\ the other three left to right -- so a suite that printed as a side
\\ effect of building its case list would report the same verdicts in two
\\ different orders. Host evaluation order may not reach a compared byte:
\\ the same rule the world kernel lives by (SPEC.md 7.1) applies to the
\\ harness that checks it.
(define umt.ok
  Name Value -> [case-ok Name Value])

(define umt.digest
  Name Values -> [case-digest Name Values])

(define umt.token
  Name Token -> [case-token Name Token])

(define umt.reject
  Name Result Expected -> [case-reject Name Result Expected])

(define umt.emit
  [case-ok Name Value] ->
    (umt.emit-value Name (urdr.canonical.encode-frame Value))
  [case-digest Name Values] ->
    (umt.emit-digest Name (umt.frames Values []))
  [case-token Name Token] ->
    (do (output "MODELS-DIRECT|~A|~A~%" Name Token) [ok])
  [case-reject Name Result Expected] ->
    (umt.reject-code Name (umt.error-code Result) Expected))

(define umt.emit-all
  [] Acc -> (urdr.model.common.rev Acc)
  [Case | Rest] Acc ->
    (let Result (umt.emit Case)
      (umt.emit-all Rest [Result | Acc]))
  _ Acc -> (urdr.model.common.rev Acc))

\\ A small canonical projection is printed in full so a golden diff names
\\ the differing octet; a whole-run trace is printed as its SHA-256 so the
\\ line stays inside the ADR 0002 frame profile.
(define umt.emit-value
  Name [error E] -> [error encode-failed]
  Name [ok Bytes] ->
    (do (output "MODELS-OK|~A|~A~%" Name (umt.hex Bytes)) [ok]))

(define umt.emit-digest
  Name [error E] -> [error encode-failed]
  Name [ok Bytes] ->
    (do (output "MODELS-DIGEST|~A|~A~%"
          Name (umt.hex (hd (tl (urdr.sha256 Bytes)))))
        [ok]))

\\ A whole-run projection is a *sequence* of canonical values, each framed
\\ on its own and the frames concatenated before hashing. Canonical frames
\\ are length-prefixed, so the concatenation is unambiguous, and no single
\\ frame has to hold a trace larger than the ADR 0002 resource profile
\\ allows.
(define umt.frames
  [] Acc -> [ok Acc]
  [Value | Rest] Acc ->
    (umt.frames-step (urdr.canonical.encode-frame Value) Rest Acc)
  _ Acc -> [error trace-shape])

(define umt.frames-step
  [error E] Rest Acc -> [error E]
  [ok Bytes] Rest Acc ->
    (umt.frames Rest (urdr.model.common.append Acc Bytes)))

(define umt.reject-code
  Name none Expected -> [error not-rejected]
  Name Code Expected ->
    (if (urdr.model.common.same? Code (urdr.model.common.code Expected))
        (do (output "MODELS-REJECT|~A|~A~%" Name Expected) [ok])
        [error wrong-code]))

\\ A component's own error, a reducer run error, and a witness
\\ `unconfirmed` all carry a stable code; the suite reads all three
\\ through one accessor so no path can report a rejection it did not get.
(define umt.error-code
  [error Code] -> (umt.code-of Code)
  [error Code _] -> (umt.code-of Code)
  [replay-error _ _ Choices] -> (umt.error-code Choices)
  [unconfirmed Reason] -> (urdr.canonical.string-bytes (str Reason))
  _ -> none)

(define umt.code-of
  [record Fields] ->
    (urdr.model.common.symbol-bytes
      (urdr.model.common.entries-get
        Fields (urdr.canonical.string-bytes "code")))
  Code ->
    (if (urdr.canonical.byte-list? Code)
        Code
        (urdr.canonical.string-bytes (str Code))))

(define umt.all-ok?
  [] -> true
  [[ok] | Rest] -> (umt.all-ok? Rest)
  _ -> false)

(define umt.count
  [] N -> N
  [_ | Rest] N -> (umt.count Rest (+ N 1)))

\\ ---------------------------------------------------------------
\\ Fixture vocabulary and topology
\\
\\   nodes a=1, b=2, c=3;  links a->b, a->c, b->c
\\   header space |src| * |dst| = 9 packets, far under the NetKAT
\\   1,024-packet ceiling.
\\ ---------------------------------------------------------------

(define umt.dst -> [100 115 116])
(define umt.src -> [115 114 99])
(define umt.a -> [97])
(define umt.b -> [98])
(define umt.c -> [99])

(define umt.addresses
  -> [list [(umt.big 1) (umt.big 2) (umt.big 3)]])

(define umt.vocab
  -> [record [[(umt.dst) (umt.addresses)] [(umt.src) (umt.addresses)]]])

(define umt.baseline -> (urdr.netkat.term-encode [nk-id]))

(define umt.links
  -> [[link (umt.a) (umt.b) (umt.big 1) (umt.big 2)]
      [link (umt.a) (umt.c) (umt.big 1) (umt.big 3)]
      [link (umt.b) (umt.c) (umt.big 2) (umt.big 3)]])

(define umt.net-state
  -> (urdr.model.net.state-value
       (umt.vocab) (umt.baseline) (umt.links) [] []))

(define umt.packet
  S D -> [record [[(umt.dst) (umt.big D)] [(umt.src) (umt.big S)]]])

(define umt.net-name -> [110 101 116 45 97])
(define umt.fault-name -> [102 97 117 108 116 45 97])
(define umt.timer-name -> [116 105 109 101 114 45 97])
(define umt.process-name -> [112 114 111 99 45 97])
(define umt.seed -> [109 111 100 101 108 45 115 101 101 100])

\\ ---------------------------------------------------------------
\\ World plumbing
\\ ---------------------------------------------------------------

(define umt.world
  Registry ->
    (umt.world-of
      (urdr.world.initial-with-components (umt.seed) Registry)))

(define umt.world-of
  [ok World] -> World
  Error -> Error)

(define umt.net-world
  -> (umt.world
       [(urdr.component.entry
          (umt.net-name)
          (/. S E (urdr.model.net.step S E))
          (umt.net-state))]))

(define umt.input
  Name Value ->
    [schedule (urdr.int.zero) component [component-input Name Value]])

(define umt.input-at
  At Name Value ->
    [schedule At component [component-input Name Value]])

(define umt.advance -> [advance-to-next-event])

(define umt.drive
  World Inputs -> (urdr.world.replay World Inputs))

(define umt.final
  [replay World _] -> World
  Other -> Other)

\\ The projection of a run: every fact the models asserted, then every
\\ alternative they published, in order. Nothing about host identity,
\\ handler code, or wall-clock cost enters it.
(define umt.trace
  Replay ->
    (urdr.model.common.append
      (urdr.world.facts (umt.final Replay))
      (umt.choices (urdr.world.replay-reductions Replay) [])))

(define umt.choices
  [] Acc -> Acc
  [Reduction | Rest] Acc ->
    (umt.choices
      Rest
      (urdr.model.common.append
        Acc (urdr.world.reduction-choices Reduction))))

\\ Fact-log readers. These are exactly what the world kernel's routing
\\ layer will do with a model's facts: read the value and schedule it.
(define umt.fact-named
  Name [] -> none
  Name [Fact | Rest] ->
    (if (urdr.model.common.same?
          Name
          (urdr.model.common.symbol-bytes
            (urdr.model.common.get
              Fact (urdr.canonical.string-bytes "name"))))
        (urdr.model.common.get
          Fact (urdr.canonical.string-bytes "value"))
        (umt.fact-named Name Rest))
  Name _ -> none)

(define umt.delivered-packets
  [] Acc -> (urdr.model.common.rev Acc)
  [Fact | Rest] Acc ->
    (if (urdr.model.common.same?
          (urdr.model.net.n.delivered)
          (urdr.model.common.symbol-bytes
            (urdr.model.common.get
              Fact (urdr.canonical.string-bytes "name"))))
        (umt.delivered-packets
          Rest
          [(urdr.model.common.get
             (urdr.model.common.get
               Fact (urdr.canonical.string-bytes "value"))
             (urdr.model.net.n.packet)) | Acc])
        (umt.delivered-packets Rest Acc))
  _ Acc -> (urdr.model.common.rev Acc))

\\ ---------------------------------------------------------------
\\ Case 1: a well-behaved flow. send -> choices -> deliver -> facts.
\\ ---------------------------------------------------------------

(define umt.send-inputs
  S D From To ->
    [(umt.input (umt.net-name)
       (urdr.model.net.send-input (umt.packet S D) From To))
     (umt.advance)])

(define umt.deliver-inputs
  Action Index From To ->
    [(umt.input (umt.net-name)
       (urdr.model.net.deliver-input Action Index From To))
     (umt.advance)])

(define umt.flow-inputs
  -> (urdr.model.common.append
       (umt.send-inputs 1 2 (umt.a) (umt.b))
       (umt.deliver-inputs
         (urdr.model.net.n.deliver) 0 (umt.a) (umt.b))))

(define umt.flow
  -> (umt.drive (umt.net-world) (umt.flow-inputs)))

\\ Case 2: duplicate delivers without dequeuing, so the packet is still
\\ pending afterwards and a second delivery is still offered.
(define umt.duplicate-inputs
  -> (urdr.model.common.append
       (umt.send-inputs 1 2 (umt.a) (umt.b))
       (urdr.model.common.append
         (umt.deliver-inputs
           (urdr.model.net.n.duplicate) 0 (umt.a) (umt.b))
         (umt.deliver-inputs
           (urdr.model.net.n.drop) 0 (umt.a) (umt.b)))))

(define umt.duplicate-flow
  -> (umt.drive (umt.net-world) (umt.duplicate-inputs)))

\\ Reordering: with two packets queued on one link the model publishes a
\\ deliver alternative at index 1 as well as index 0, and taking index 1
\\ delivers the second packet first. The model neither chose that nor
\\ preferred it; it only made it legal.
(define umt.reorder-inputs
  -> (urdr.model.common.append
       (umt.send-inputs 1 2 (umt.a) (umt.b))
       (urdr.model.common.append
         (umt.send-inputs 2 3 (umt.a) (umt.b))
         (umt.deliver-inputs
           (urdr.model.net.n.deliver) 1 (umt.a) (umt.b)))))

(define umt.reorder-flow
  -> (umt.drive (umt.net-world) (umt.reorder-inputs)))

(define umt.reorder-effect
  -> [list (umt.delivered-packets
             (urdr.world.facts (umt.final (umt.reorder-flow))) [])])

\\ ---------------------------------------------------------------
\\ Case 3: fault activation changes the deliverable set.
\\
\\ The fault model activates a partition over {c}; its `mask` fact value
\\ *is* the network model's mask input, and the same packet that was
\\ delivered before the mask is blocked after it.
\\ ---------------------------------------------------------------

(define umt.domain
  -> [domain
       [100 49]
       [(urdr.model.fault.n.partition)]
       [(umt.c)]
       []])

(define umt.nodes
  -> [[node (umt.big 1) (umt.a)]
      [node (umt.big 2) (umt.b)]
      [node (umt.big 3) (umt.c)]])

(define umt.fault-state
  -> (urdr.model.fault.state-value [(umt.domain)] (umt.nodes)))

(define umt.pair-world
  -> (umt.world
       [(urdr.component.entry
          (umt.fault-name)
          (/. S E (urdr.model.fault.step S E))
          (umt.fault-state))
        (urdr.component.entry
          (umt.net-name)
          (/. S E (urdr.model.net.step S E))
          (umt.net-state))]))

(define umt.activate-inputs
  Kind Operation ->
    [(umt.input (umt.fault-name)
       (urdr.model.fault.input [100 49] Kind Operation))
     (umt.advance)])

(define umt.unmasked-run
  -> (umt.drive
       (umt.pair-world)
       (urdr.model.common.append
         (umt.send-inputs 1 3 (umt.a) (umt.c))
         (umt.deliver-inputs
           (urdr.model.net.n.deliver) 0 (umt.a) (umt.c)))))

(define umt.activation
  -> (umt.drive
       (umt.pair-world)
       (umt.activate-inputs
         (urdr.model.fault.n.partition)
         (urdr.model.fault.n.activate))))

(define umt.mask-value
  Replay ->
    (umt.fact-named
      (urdr.model.fault.n.mask) (urdr.world.facts (umt.final Replay))))

(define umt.masked-inputs
  -> (urdr.model.common.append
       (umt.activate-inputs
         (urdr.model.fault.n.partition)
         (urdr.model.fault.n.activate))
       (urdr.model.common.append
         [(umt.input (umt.net-name) (umt.mask-value (umt.activation)))
          (umt.advance)]
         (urdr.model.common.append
           (umt.send-inputs 1 3 (umt.a) (umt.c))
           (umt.deliver-inputs
             (urdr.model.net.n.deliver) 0 (umt.a) (umt.c))))))

(define umt.masked-run
  -> (umt.drive (umt.pair-world) (umt.masked-inputs)))

\\ The semantic claim, projected as a value rather than a digest: the
\\ same send is delivered before the partition and delivered nowhere
\\ after it.
(define umt.partition-effect
  -> [record
       [[[97 102 116 101 114]
         [list (umt.delivered-packets
                 (urdr.world.facts (umt.final (umt.masked-run))) [])]]
        [[98 101 102 111 114 101]
         [list (umt.delivered-packets
                 (urdr.world.facts (umt.final (umt.unmasked-run))) [])]]]])

\\ A partition is a boundary, not a blackout: traffic wholly inside the
\\ complement of the domain is untouched by the mask.
(define umt.inside-inputs
  -> (urdr.model.common.append
       (umt.activate-inputs
         (urdr.model.fault.n.partition)
         (urdr.model.fault.n.activate))
       (urdr.model.common.append
         [(umt.input (umt.net-name) (umt.mask-value (umt.activation)))
          (umt.advance)]
         (urdr.model.common.append
           (umt.send-inputs 1 2 (umt.a) (umt.b))
           (umt.deliver-inputs
             (urdr.model.net.n.deliver) 0 (umt.a) (umt.b))))))

(define umt.inside-run
  -> (umt.drive (umt.pair-world) (umt.inside-inputs)))

(define umt.inside-effect
  -> [list (umt.delivered-packets
             (urdr.world.facts (umt.final (umt.inside-run))) [])])

\\ ---------------------------------------------------------------
\\ Case 4: the denotation audit.
\\
\\ A `delivered` fact can only be built from urdr.netkat.eval applied to
\\ the packet the same fact records as sent, and the step audits its own
\\ output before returning. The misbehaviour fixture below forges a fact
\\ the model itself cannot produce; the auditor rejects it, which is the
\\ property a future edit would have to keep.
\\ ---------------------------------------------------------------

(define umt.honest-facts
  -> [[fact (urdr.model.net.n.delivered)
        (urdr.model.net.delivered-value
          (umt.packet 1 2) (umt.packet 1 2) (umt.a) (umt.b))]])

(define umt.forged-facts
  -> [[fact (urdr.model.net.n.delivered)
        (urdr.model.net.delivered-value
          (umt.packet 3 1) (umt.packet 1 2) (umt.a) (umt.b))]])

(define umt.audit
  Facts ->
    (umt.audit-policy
      (urdr.model.net.active-policy (umt.net-state)) Facts))

(define umt.audit-policy
  [ok Active] Facts -> (urdr.model.net.audit-facts Active Facts)
  Error Facts -> Error)

\\ The misbehaviour fixture, run as a real component. It is a legal
\\ component by the ADR 0004 Decision 1 contract -- canonical state, no
\\ reserved authority, ordered choices -- so the reducer accepts it: the
\\ component interface knows nothing about denotations. What refuses it is
\\ the network model's own auditor, applied to the fact log the run
\\ produced. That is where "never invents a packet" is enforceable from
\\ outside the model, and the honest model calls the same auditor on its
\\ own output before returning.
(define umt.forger
  State Event ->
    [step
      State
      [[fact (urdr.model.net.n.delivered)
         (urdr.model.net.delivered-value
           (umt.packet 3 1) (umt.packet 1 2) (umt.a) (umt.b))]]
      []])

(define umt.forger-world
  -> (umt.world
       [(urdr.component.entry
          (umt.net-name) (/. S E (umt.forger S E)) (umt.net-state))]))

(define umt.forger-run
  -> (umt.drive
       (umt.forger-world)
       [(umt.input (umt.net-name)
          (urdr.model.net.send-input (umt.packet 1 2) (umt.a) (umt.b)))
        (umt.advance)]))

\\ World facts carry the reducer's own envelope; the auditor reads the
\\ model-level facts, so the run's log is projected back to [fact NAME
\\ VALUE] pairs first.
(define umt.model-facts
  [] Acc -> (urdr.model.common.rev Acc)
  [Fact | Rest] Acc ->
    (umt.model-facts
      Rest
      [[fact
         (urdr.model.common.symbol-bytes
           (urdr.model.common.get
             Fact (urdr.canonical.string-bytes "name")))
         (urdr.model.common.get
           Fact (urdr.canonical.string-bytes "value"))] | Acc])
  _ Acc -> (urdr.model.common.rev Acc))

(define umt.forger-audit
  -> (umt.audit
       (umt.model-facts
         (urdr.world.facts (umt.final (umt.forger-run))) [])))

(define umt.honest-audit
  -> (umt.audit
       (umt.model-facts
         (urdr.world.facts (umt.final (umt.flow))) [])))

\\ ---------------------------------------------------------------
\\ Case 5: resource caps.
\\ ---------------------------------------------------------------

(define umt.range
  0 Acc -> Acc
  N Acc -> (umt.range (- N 1) [(umt.big N) | Acc]))

(define umt.checked-vocab
  -> (hd (tl (urdr.netkat.vocabulary (umt.vocab)))))

\\ A vocabulary at the largest header space the NetKAT profile allows,
\\ 32 * 32 = 1,024 packets, and partition masks over all 32 addresses of
\\ one field. One such mask composes; four of them do not, because the
\\ composed term passes the 1,024-node ceiling.
(define umt.wide-vocab-value
  -> [record
       [[(umt.dst) [list (umt.range 32 [])]]
        [(umt.src) [list (umt.range 32 [])]]]])

(define umt.wide-checked-vocab
  -> (hd (tl (urdr.netkat.vocabulary (umt.wide-vocab-value)))))

(define umt.wide-links
  -> [[link (umt.a) (umt.b) (umt.big 1) (umt.big 2)]])

(define umt.wide-mask
  Id -> [mask Id (urdr.model.mask.n.partition) (umt.range 32 [])])

(define umt.one-mask
  -> (urdr.model.net.active
       (umt.wide-checked-vocab)
       (umt.wide-links)
       [(umt.wide-mask [109 49])]
       (umt.baseline)))

(define umt.composition-caps
  -> (urdr.model.net.active
       (umt.wide-checked-vocab)
       (umt.wide-links)
       [(umt.wide-mask [109 49])
        (umt.wide-mask [109 50])
        (umt.wide-mask [109 51])
        (umt.wide-mask [109 52])]
       (umt.baseline)))

(define umt.single-mask-ok?
  -> (= (hd (umt.one-mask)) ok))

\\ The ADR 0002 canonical profile binds before the NetKAT ceiling on
\\ anything that travels as a value: an oversized mask never reaches the
\\ algebra because the reducer refuses the event that carries it.
(define umt.oversize-event
  -> (urdr.world.reduce
       (umt.net-world)
       (umt.input (umt.net-name)
         (urdr.model.net.mask-input
           [109 49]
           (urdr.model.mask.n.partition)
           (umt.range 300 [])))))

(define umt.oversize-rejected?
  -> (= (urdr.world.reduction-choices (umt.oversize-event))
        [error (urdr.world.error-value
                 [105 110 118 97 108 105 100 45 101 118 101 110 116]
                 [null])]))

(define umt.wide-vocab
  -> (urdr.netkat.vocabulary
       [record
         [[(umt.dst) [list (umt.range 33 [])]]
          [(umt.src) [list (umt.range 33 [])]]]]))

\\ ---------------------------------------------------------------
\\ Case 6: the timer.
\\ ---------------------------------------------------------------

(define umt.timer-world
  -> (umt.world
       [(urdr.component.entry
          (umt.timer-name)
          (/. S E (urdr.model.timer.step S E))
          (urdr.model.timer.initial))]))

(define umt.timer-input
  At Value -> (umt.input-at At (umt.timer-name) Value))

(define umt.t1 -> [116 49])
(define umt.t2 -> [116 50])

(define umt.timer-inputs
  -> [(umt.timer-input (urdr.int.zero)
        (urdr.model.timer.set-input (umt.t1) (umt.big 5)))
      (umt.advance)
      (umt.timer-input (urdr.int.zero)
        (urdr.model.timer.set-input (umt.t2) (umt.big 2)))
      (umt.advance)
      (umt.timer-input (umt.big 2) (urdr.model.timer.poll-input))
      (umt.advance)
      (umt.timer-input (umt.big 2)
        (urdr.model.timer.fire-input (umt.t2)))
      (umt.advance)
      (umt.timer-input (umt.big 2)
        (urdr.model.timer.cancel-input (umt.t1)))
      (umt.advance)])

(define umt.timer-run
  -> (umt.drive (umt.timer-world) (umt.timer-inputs)))

(define umt.timer-reject
  Inputs -> (umt.drive (umt.timer-world) Inputs))

(define umt.timer-not-due
  -> (umt.timer-reject
       [(umt.timer-input (urdr.int.zero)
          (urdr.model.timer.set-input (umt.t1) (umt.big 5)))
        (umt.advance)
        (umt.timer-input (urdr.int.zero)
          (urdr.model.timer.fire-input (umt.t1)))
        (umt.advance)]))

(define umt.timer-duplicate
  -> (umt.timer-reject
       [(umt.timer-input (urdr.int.zero)
          (urdr.model.timer.set-input (umt.t1) (umt.big 5)))
        (umt.advance)
        (umt.timer-input (urdr.int.zero)
          (urdr.model.timer.set-input (umt.t1) (umt.big 6)))
        (umt.advance)]))

(define umt.timer-unknown
  -> (umt.timer-reject
       [(umt.timer-input (urdr.int.zero)
          (urdr.model.timer.cancel-input (umt.t1)))
        (umt.advance)]))

(define umt.timer-stale
  -> (umt.timer-reject
       [(umt.timer-input (umt.big 4)
          (urdr.model.timer.set-input (umt.t1) (umt.big 1)))
        (umt.advance)]))

\\ ---------------------------------------------------------------
\\ Case 7: fault-model rejections and the crash-aware process wrapper.
\\ ---------------------------------------------------------------

(define umt.fault-world
  -> (umt.world
       [(urdr.component.entry
          (umt.fault-name)
          (/. S E (urdr.model.fault.step S E))
          (umt.fault-state))]))

(define umt.fault-drive
  Inputs -> (umt.drive (umt.fault-world) Inputs))

(define umt.fault-twice
  -> (umt.fault-drive
       (urdr.model.common.append
         (umt.activate-inputs
           (urdr.model.fault.n.partition)
           (urdr.model.fault.n.activate))
         (umt.activate-inputs
           (urdr.model.fault.n.partition)
           (urdr.model.fault.n.activate)))))

(define umt.fault-undeclared
  -> (umt.fault-drive
       (umt.activate-inputs
         (urdr.model.fault.n.crash)
         (urdr.model.fault.n.activate))))

(define umt.fault-unknown-domain
  -> (umt.fault-drive
       [(umt.input (umt.fault-name)
          (urdr.model.fault.input
            [100 57]
            (urdr.model.fault.n.partition)
            (urdr.model.fault.n.activate)))
        (umt.advance)]))

(define umt.fault-cycle
  -> (umt.fault-drive
       (urdr.model.common.append
         (umt.activate-inputs
           (urdr.model.fault.n.partition)
           (urdr.model.fault.n.activate))
         (umt.activate-inputs
           (urdr.model.fault.n.partition)
           (urdr.model.fault.n.deactivate)))))

\\ A trivial inner process: it counts the inputs it is given. The wrapper
\\ under test is the crash latch around it.
(define umt.counter-state
  Count -> [record [[[99 111 117 110 116] Count]]])

(define umt.counter
  [record [[[99 111 117 110 116] Count]]] Event ->
    (let Next (hd (tl (urdr.int.add Count (umt.big 1))))
      [step
        (umt.counter-state Next)
        [[fact [116 105 99 107] (umt.counter-state Next)]]
        []])
  _ _ -> (urdr.model.common.error "counter-unknown-input"))

(define umt.process-world
  -> (umt.world
       [(urdr.component.entry
          (umt.process-name)
          (/. S E
            (urdr.model.fault.process
              (/. IS IE (umt.counter IS IE))
              (umt.counter-state (urdr.int.zero))
              S
              E))
          (urdr.model.fault.process-initial
            (umt.counter-state (urdr.int.zero))))]))

(define umt.bump
  -> [record [[[107 105 110 100] [symbol [98 117 109 112]]]]])

(define umt.process-inputs
  -> [(umt.input (umt.process-name) (umt.bump))
      (umt.advance)
      (umt.input (umt.process-name) (urdr.model.fault.crash-input))
      (umt.advance)
      (umt.input (umt.process-name) (umt.bump))
      (umt.advance)
      (umt.input (umt.process-name) (umt.bump))
      (umt.advance)
      (umt.input (umt.process-name) (urdr.model.fault.restart-input))
      (umt.advance)
      (umt.input (umt.process-name) (umt.bump))
      (umt.advance)])

(define umt.process-run
  -> (umt.drive (umt.process-world) (umt.process-inputs)))

\\ ---------------------------------------------------------------
\\ Case 8: composition glue from a validated scenario.
\\ ---------------------------------------------------------------

(define umt.k
  Name -> (urdr.canonical.string-bytes Name))

(define umt.s
  Name -> [symbol (urdr.canonical.string-bytes Name)])

(define umt.node-value
  Address Id ->
    [record [[(umt.k "address") (umt.big Address)] [(umt.k "id") Id]]])

(define umt.link-value
  From To ->
    [record [[(umt.k "from") From] [(umt.k "to") To]]])

(define umt.component-value
  Id Kind Node ->
    [record
      [[(umt.k "id") Id] [(umt.k "kind") Kind] [(umt.k "node") Node]]])

(define umt.field-value
  Field ->
    [record
      [[(umt.k "field") Field]
       [(umt.k "values") [list [(umt.big 1) (umt.big 2)]]]]])

\\ Two nodes, one link, a two-value header space, and one partition
\\ domain over {b}. This is smaller than the network fixture above on
\\ purpose: a scenario is one canonical value under the ADR 0002 M0
\\ resource profile, and a fully populated roster of all four component
\\ kinds is already most of the 256-node budget. The M1 plan's own
\\ measurement (ADR 0005) found the same ceiling from the other side.
(define umt.scenario-with
  Components ->
    [record
      [[(umt.k "budget")
         [record
           [[(umt.k "max-events") (umt.big 100)]
            [(umt.k "max-runs") (umt.big 4)]
            [(umt.k "max-steps") (umt.big 100)]]]]
        [(umt.k "components") [list Components]]
        [(umt.k "determinism") (umt.s "modeled")]
        [(umt.k "faults")
         [list
           [[record
              [[(umt.k "id") (umt.s "d1")]
               [(umt.k "kinds") [list [(umt.s "partition")]]]
               [(umt.k "members") [list [(umt.s "b")]]]]]]]]
        [(umt.k "header-vocabulary")
         [list
           [(umt.field-value (umt.s "dst"))
            (umt.field-value (umt.s "src"))]]]
        [(umt.k "observations") [list []]]
        [(umt.k "properties") [list []]]
        [(umt.k "seed") [bytes (umt.seed)]]
        [(umt.k "topology")
         [record
           [[(umt.k "links")
             [list [(umt.link-value (umt.s "a") (umt.s "b"))]]]
            [(umt.k "nodes")
             [list
               [(umt.node-value 1 (umt.s "a"))
                (umt.node-value 2 (umt.s "b"))]]]]]]
        [(umt.k "version") (umt.s "scenario/v1")]]])

(define umt.scenario-value
  -> (umt.scenario-with
       [(umt.component-value (umt.s "fault-a") (umt.s "fault")
          (umt.s "a"))
        (umt.component-value (umt.s "net-a") (umt.s "net")
          (umt.s "a"))
        (umt.component-value (umt.s "proc-a") (umt.s "process")
          (umt.s "b"))
        (umt.component-value (umt.s "timer-a") (umt.s "timer")
          (umt.s "a"))]))

(define umt.scenario
  -> (urdr.scenario.validate (umt.scenario-value)))

(define umt.registry
  -> (umt.registry-of (umt.scenario)))

(define umt.default-kind-table
  -> (urdr.model.registry.kind-table
       (/. S E (umt.counter S E))
       (umt.counter-state (urdr.int.zero))))

(define umt.registry-of
  [ok Scenario] ->
    (urdr.model.registry.from-scenario
      Scenario
      (umt.baseline)
      (umt.default-kind-table)
      [])
  Error -> Error)

(define umt.registry-world
  -> (umt.registry-world-of (umt.registry)))

(define umt.registry-world-of
  [ok Registry] ->
    (urdr.world.initial-with-components (umt.seed) Registry)
  Error -> Error)

(define umt.registry-snapshot
  -> (umt.registry-snapshot-of (umt.registry-world)))

(define umt.registry-snapshot-of
  [ok World] -> (urdr.world.snapshot-value World)
  Error -> [symbol [98 97 100]])

\\ Both stages are asserted explicitly, because a validation failure
\\ upstream would otherwise be projected as a perfectly stable digest of
\\ the word "bad" and the case would pass while proving nothing.
(define umt.built?
  -> (and (= (hd (umt.scenario)) ok)
          (and (= (hd (umt.registry)) ok)
               (= (hd (umt.registry-world)) ok))))

\\ The glue is exercised, not just constructed: the scenario-built world
\\ runs the same partition-then-send-then-deliver flow end to end, with
\\ the component names, topology, vocabulary, and fault domain all taken
\\ from the declaration rather than hand-built here.
(define umt.registry-world-value
  -> (umt.registry-value-of (umt.registry-world)))

(define umt.registry-value-of
  [ok World] -> World
  Error -> Error)

(define umt.registry-activation
  -> (umt.drive
       (umt.registry-world-value)
       (umt.activate-inputs
         (urdr.model.fault.n.partition)
         (urdr.model.fault.n.activate))))

(define umt.registry-inputs
  -> (urdr.model.common.append
       (umt.activate-inputs
         (urdr.model.fault.n.partition)
         (urdr.model.fault.n.activate))
       (urdr.model.common.append
         [(umt.input (umt.net-name)
            (umt.mask-value (umt.registry-activation)))
          (umt.advance)]
         (urdr.model.common.append
           (umt.send-inputs 1 2 (umt.a) (umt.b))
           (umt.deliver-inputs
             (urdr.model.net.n.deliver) 0 (umt.a) (umt.b))))))

(define umt.registry-run
  -> (umt.drive (umt.registry-world-value) (umt.registry-inputs)))

(define umt.registry-open-run
  -> (umt.drive
       (umt.registry-world-value)
       (urdr.model.common.append
         (umt.send-inputs 1 2 (umt.a) (umt.b))
         (umt.deliver-inputs
           (urdr.model.net.n.deliver) 0 (umt.a) (umt.b)))))

(define umt.registry-delivered
  Replay ->
    [list (umt.delivered-packets
            (urdr.world.facts (umt.final Replay)) [])])

\\ ---------------------------------------------------------------
\\ Case 8b: per-component model binding and component identity
\\ (ADR 0007 D3).
\\
\\ Two process components in one scenario are bound to DIFFERENT models
\\ through the driver-facing model table; each model's init-builder
\\ reads the roster record it was built for, so the two start from
\\ different initial states; and each handler reads its own id and node
\\ under the event's `self` key and emits them in a fact, proving the
\\ reducer delivers identity per component. The registry fail-closed
\\ paths — unknown model, malformed vocabulary, malformed fault
\\ domains — are exercised alongside.
\\ ---------------------------------------------------------------

(define umt.component-model-value
  Id Kind Model Node ->
    [record
      [[(umt.k "id") Id]
       [(umt.k "kind") Kind]
       [(umt.k "model") Model]
       [(umt.k "node") Node]]])

(define umt.model-scenario-value
  -> (umt.scenario-with
       [(umt.component-model-value (umt.s "proc-a") (umt.s "process")
          (umt.s "left") (umt.s "a"))
        (umt.component-model-value (umt.s "proc-b") (umt.s "process")
          (umt.s "right") (umt.s "b"))]))

\\ The handler reads its identity from the event and asserts it as a
\\ fact. The fact value never uses the reserved name `self` as a key or
\\ symbol; identity is re-asserted under `who`.
(define umt.ident-handler
  Tag State Event ->
    [step
      State
      [[fact (urdr.canonical.string-bytes "ident")
         [record
           [[(umt.k "tag") (umt.s Tag)]
            [(umt.k "who") (urdr.model.common.event-self Event)]]]]]
      []])

\\ Init-builders receive the full roster record plus the baseline, so
\\ the initial state can name the component it belongs to.
(define umt.model-init
  N [component Id Kind Node Model] Baseline ->
    [record
      [[(umt.k "me") [symbol Id]]
       [(umt.k "n") (umt.big N)]]])

(define umt.model-table
  -> [[(urdr.canonical.string-bytes "left")
       [(/. S E (umt.ident-handler "left" S E))
        (/. C B (umt.model-init 1 C B))]]
      [(urdr.canonical.string-bytes "right")
       [(/. S E (umt.ident-handler "right" S E))
        (/. C B (umt.model-init 2 C B))]]])

(define umt.model-registry-of
  [ok Scenario] ->
    (urdr.model.registry.from-scenario
      Scenario
      (umt.baseline)
      (umt.default-kind-table)
      (umt.model-table))
  Error -> Error)

(define umt.model-registry
  -> (umt.model-registry-of
       (urdr.scenario.validate (umt.model-scenario-value))))

(define umt.model-world-result
  -> (umt.model-world-result-of (umt.model-registry)))

(define umt.model-world-result-of
  [ok Registry] ->
    (urdr.world.initial-with-components (umt.seed) Registry)
  Error -> Error)

(define umt.model-world
  -> (umt.world-of (umt.model-world-result)))

(define umt.model-built?
  -> (and (= (hd (umt.model-registry)) ok)
          (= (hd (umt.model-world-result)) ok)))

(define umt.entry-states
  [] -> []
  [[component _ _ State _] | Rest] ->
    [State | (umt.entry-states Rest)]
  _ -> [])

(define umt.model-initial-states
  -> (umt.model-states-of (umt.model-registry)))

(define umt.model-states-of
  [ok Registry] -> [list (umt.entry-states Registry)]
  Error -> [symbol [98 97 100]])

(define umt.model-run
  -> (umt.drive
       (umt.model-world)
       [(umt.input (urdr.canonical.string-bytes "proc-a") (umt.bump))
        (umt.advance)
        (umt.input (urdr.canonical.string-bytes "proc-b") (umt.bump))
        (umt.advance)]))

(define umt.model-facts-log
  -> (urdr.world.facts (umt.final (umt.model-run))))

(define umt.ident-who
  Fact ->
    (urdr.model.common.get
      (urdr.model.common.get
        Fact (urdr.canonical.string-bytes "value"))
      (umt.k "who")))

(define umt.ident-whos
  [] -> []
  [Fact | Rest] ->
    [(umt.ident-who Fact) | (umt.ident-whos Rest)]
  _ -> [])

(define umt.self-record
  Id Node ->
    [record
      [[(umt.k "id") (umt.s Id)]
       [(umt.k "node") (umt.s Node)]]])

\\ Each component observed exactly its own declared id and node.
(define umt.identities-delivered?
  -> (= (umt.ident-whos (umt.model-facts-log))
        [(umt.self-record "proc-a" "a")
         (umt.self-record "proc-b" "b")]))

\\ Fail-closed registry paths.
(define umt.unknown-model
  -> (umt.unknown-model-of
       (urdr.scenario.validate (umt.model-scenario-value))))

(define umt.unknown-model-of
  [ok Scenario] ->
    (urdr.model.registry.from-scenario
      Scenario (umt.baseline) (umt.default-kind-table) [])
  Error -> Error)

(define umt.broken-vocab
  -> (umt.broken-vocab-of (umt.scenario)))

(define umt.broken-vocab-of
  [ok [scenario/v1 B C D F V O P S T]] ->
    (urdr.model.registry.from-scenario
      [scenario/v1 B C D F [[bogus]] O P S T]
      (umt.baseline)
      (umt.default-kind-table)
      [])
  Error -> Error)

(define umt.broken-domains
  -> (umt.broken-domains-of (umt.scenario)))

(define umt.broken-domains-of
  [ok [scenario/v1 B C D F V O P S T]] ->
    (urdr.model.registry.from-scenario
      [scenario/v1 B C D [[bogus]] V O P S T]
      (umt.baseline)
      (umt.default-kind-table)
      [])
  Error -> Error)

\\ ---------------------------------------------------------------
\\ Case 9: the witness bridge.
\\ ---------------------------------------------------------------

(define umt.reachability
  Ingress Egress Policy ->
    (urdr.netkat.check-reachability
      (umt.vocab) Ingress Policy Egress))

(define umt.verdict-value
  [ok Verdict] -> (urdr.netkat.reachability-value Verdict)
  Error -> [symbol [98 97 100]])

\\ A genuine reachability witness over the unmasked network: a-to-b is
\\ permitted, and the compiled schedule delivers exactly that packet.
(define umt.reach-witness
  -> (umt.verdict-value
       (umt.reachability
         (urdr.netkat.term-encode
           [nk-seq
             [nk-test [symbol (umt.src)] (umt.big 1)]
             [nk-test [symbol (umt.dst)] (umt.big 2)]])
         (urdr.netkat.term-encode [nk-id])
         (urdr.netkat.term-encode [nk-id]))))

(define umt.confirmed
  -> (urdr.netkat.witness.confirm
       (umt.seed) (umt.net-name) (umt.net-state) (umt.reach-witness)))

\\ A witness the concrete model does not reproduce: it claims a-to-c is
\\ reachable, but the network under test carries the partition mask that
\\ blocks exactly that pair. The bridge must report `unconfirmed`, never
\\ a pass.
(define umt.masked-net-state
  -> (umt.masked-net-of (umt.mask-value (umt.activation))))

(define umt.masked-net-of
  none -> [symbol [98 97 100]]
  Value ->
    (umt.masked-net-result
      (urdr.model.net.step
        (umt.net-state)
        (urdr.world.component-event
          (urdr.int.zero)
          Value
          (umt.net-name)
          (urdr.component.meta-empty)))))

(define umt.masked-net-result
  [step State _ _] -> State
  Error -> [symbol [98 97 100]])

(define umt.unreproducible-witness
  -> (umt.verdict-value
       (umt.reachability
         (urdr.netkat.term-encode
           [nk-seq
             [nk-test [symbol (umt.src)] (umt.big 1)]
             [nk-test [symbol (umt.dst)] (umt.big 3)]])
         (urdr.netkat.term-encode [nk-id])
         (urdr.netkat.term-encode [nk-id]))))

(define umt.unconfirmed
  -> (urdr.netkat.witness.confirm
       (umt.seed)
       (umt.net-name)
       (umt.masked-net-state)
       (umt.unreproducible-witness)))

\\ An `unreachable` verdict has no violation to reproduce; reporting one
\\ would be a fabrication, so the bridge refuses rather than passing.
(define umt.nonviolating-witness
  -> (umt.verdict-value
       (umt.reachability
         (urdr.netkat.term-encode [nk-id])
         (urdr.netkat.term-encode [nk-drop])
         (urdr.netkat.term-encode [nk-id]))))

(define umt.nonviolating
  -> (urdr.netkat.witness.confirm
       (umt.seed)
       (umt.net-name)
       (umt.net-state)
       (umt.nonviolating-witness)))

\\ A witness whose (src, dst) pair no declared link carries: c-to-a is a
\\ header assignment the topology cannot realize.
(define umt.unlinked-witness
  -> (umt.verdict-value
       (umt.reachability
         (urdr.netkat.term-encode
           [nk-seq
             [nk-test [symbol (umt.src)] (umt.big 3)]
             [nk-test [symbol (umt.dst)] (umt.big 1)]])
         (urdr.netkat.term-encode [nk-id])
         (urdr.netkat.term-encode [nk-id]))))

(define umt.unlinked
  -> (urdr.netkat.witness.confirm
       (umt.seed)
       (umt.net-name)
       (umt.net-state)
       (umt.unlinked-witness)))

\\ The equivalence side of the bridge. Two baselines that the algebra says
\\ differ are given the same compiled schedule; the violation is exhibited
\\ when the two runs deliver different packet sets.
(define umt.right-baseline
  -> (urdr.netkat.term-encode
       [nk-neg [nk-test [symbol (umt.dst)] (umt.big 2)]]))

(define umt.right-net-state
  -> (urdr.model.net.state-value
       (umt.vocab) (umt.right-baseline) (umt.links) [] []))

(define umt.differs-witness
  -> (umt.equivalence-value
       (urdr.netkat.check-equivalence
         (umt.vocab) (umt.baseline) (umt.right-baseline))))

(define umt.equivalence-value
  [ok Verdict] -> (urdr.netkat.equivalence-value Verdict)
  Error -> [symbol [98 97 100]])

(define umt.difference-confirmed
  -> (urdr.netkat.witness.confirm-difference
       (umt.seed)
       (umt.net-name)
       (umt.net-state)
       (umt.right-net-state)
       (umt.differs-witness)))

\\ The same symbolic verdict against two networks that behave alike
\\ concretely: nothing is exhibited, so nothing is claimed.
(define umt.difference-unconfirmed
  -> (urdr.netkat.witness.confirm-difference
       (umt.seed)
       (umt.net-name)
       (umt.net-state)
       (umt.net-state)
       (umt.differs-witness)))

\\ ---------------------------------------------------------------
\\ Case list
\\ ---------------------------------------------------------------

(define umt.net-cases
  -> [(umt.digest "net-send-deliver" (umt.trace (umt.flow)))
      (umt.digest "net-duplicate" (umt.trace (umt.duplicate-flow)))
      (umt.ok "net-partition-effect" (umt.partition-effect))
      (umt.ok "net-partition-inside" (umt.inside-effect))
      (umt.digest "net-fault-masked-trace"
        (umt.trace (umt.masked-run)))
      (umt.digest "net-reorder" (umt.trace (umt.reorder-flow)))
      (umt.ok "net-reorder-effect" (umt.reorder-effect))
      (umt.token "net-audit-honest"
        (if (= (umt.audit (umt.honest-facts)) [ok]) "ok" "FAILED"))
      (umt.reject "net-audit-forged"
        (umt.audit (umt.forged-facts)) "net-denotation-violation")
      (umt.token "net-audit-honest-run"
        (if (= (umt.honest-audit) [ok]) "ok" "FAILED"))
      (umt.reject "net-audit-forger-component"
        (umt.forger-audit) "net-denotation-violation")
      (umt.reject "net-unknown-link"
        (umt.drive (umt.net-world)
          (umt.send-inputs 3 1 (umt.c) (umt.a)))
        "net-unknown-link")
      (umt.reject "net-empty-link"
        (umt.drive (umt.net-world)
          (umt.deliver-inputs
            (urdr.model.net.n.deliver) 0 (umt.a) (umt.b)))
        "net-unknown-link")
      (umt.reject "net-index-range"
        (umt.drive (umt.net-world)
          (urdr.model.common.append
            (umt.send-inputs 1 2 (umt.a) (umt.b))
            (umt.deliver-inputs
              (urdr.model.net.n.deliver) 1 (umt.a) (umt.b))))
        "net-index-range")
      (umt.reject "net-unknown-action"
        (umt.drive (umt.net-world)
          (urdr.model.common.append
            (umt.send-inputs 1 2 (umt.a) (umt.b))
            (umt.deliver-inputs
              (urdr.canonical.string-bytes "teleport")
              0 (umt.a) (umt.b))))
        "net-unknown-action")
      (umt.reject "net-unknown-input"
        (umt.drive (umt.net-world)
          [(umt.input (umt.net-name)
             [record [[[107 105 110 100] [symbol [98 111 103 117 115]]]]])
           (umt.advance)])
        "net-unknown-input")
      (umt.reject "net-mask-unknown"
        (umt.drive (umt.net-world)
          [(umt.input (umt.net-name)
             (urdr.model.net.unmask-input [109 49]))
           (umt.advance)])
        "net-mask-unknown")])

(define umt.caps-cases
  -> [(umt.token "net-mask-alone-valid"
        (if (umt.single-mask-ok?) "ok" "FAILED"))
      (umt.reject "net-composition-caps"
        (umt.composition-caps) "term-too-large")
      (umt.token "net-mask-oversize-frame"
        (if (umt.oversize-rejected?) "invalid-event" "FAILED"))
      (umt.reject "net-vocabulary-space"
        (umt.wide-vocab) "vocab-space-too-large")])

(define umt.timer-cases
  -> [(umt.digest "timer-flow" (umt.trace (umt.timer-run)))
      (umt.reject "timer-not-due" (umt.timer-not-due) "timer-not-due")
      (umt.reject "timer-duplicate"
        (umt.timer-duplicate) "timer-duplicate")
      (umt.reject "timer-unknown" (umt.timer-unknown) "timer-unknown")
      (umt.reject "timer-deadline-stale"
        (umt.timer-stale) "timer-deadline-stale")])

(define umt.fault-cases
  -> [(umt.digest "fault-activate" (umt.trace (umt.activation)))
      (umt.digest "fault-cycle" (umt.trace (umt.fault-cycle)))
      (umt.reject "fault-already-active"
        (umt.fault-twice) "fault-already-active")
      (umt.reject "fault-kind-undeclared"
        (umt.fault-undeclared) "fault-kind-undeclared")
      (umt.reject "fault-unknown-domain"
        (umt.fault-unknown-domain) "fault-unknown-domain")
      (umt.digest "process-crash-restart"
        (umt.trace (umt.process-run)))])

(define umt.glue-cases
  -> [(umt.token "registry-built"
        (if (umt.built?) "ok" "FAILED"))
      (umt.digest "registry-from-scenario" [(umt.registry-snapshot)])
      (umt.digest "registry-run" (umt.trace (umt.registry-run)))
      (umt.ok "registry-open"
        (umt.registry-delivered (umt.registry-open-run)))
      (umt.ok "registry-blocked"
        (umt.registry-delivered (umt.registry-run)))])

(define umt.model-cases
  -> [(umt.token "model-table-built"
        (if (umt.model-built?) "ok" "FAILED"))
      (umt.ok "model-initial-states" (umt.model-initial-states))
      (umt.digest "model-identity-facts" (umt.model-facts-log))
      (umt.token "model-identity-delivered"
        (if (umt.identities-delivered?) "ok" "FAILED"))
      (umt.reject "registry-unknown-model"
        (umt.unknown-model) "registry-unknown-model")
      (umt.reject "registry-vocab-shape"
        (umt.broken-vocab) "registry-vocab-shape")
      (umt.reject "registry-domains-shape"
        (umt.broken-domains) "registry-domains-shape")])

(define umt.witness-cases
  -> [(umt.ok "witness-confirmed"
        (urdr.netkat.witness.value (umt.confirmed)))
      (umt.ok "witness-unconfirmed"
        (urdr.netkat.witness.value (umt.unconfirmed)))
      (umt.ok "witness-nonviolating"
        (urdr.netkat.witness.value (umt.nonviolating)))
      (umt.ok "witness-unlinked"
        (urdr.netkat.witness.value (umt.unlinked)))
      (umt.reject "witness-unconfirmed-reason"
        (umt.unconfirmed) "witness-not-exhibited")
      (umt.reject "witness-nonviolating-reason"
        (umt.nonviolating) "witness-verdict-nonviolating")
      (umt.reject "witness-unlinked-reason"
        (umt.unlinked) "witness-link-unknown")
      (umt.ok "witness-difference-confirmed"
        (urdr.netkat.witness.value (umt.difference-confirmed)))
      (umt.ok "witness-difference-unconfirmed"
        (urdr.netkat.witness.value (umt.difference-unconfirmed)))
      (umt.reject "witness-difference-reason"
        (umt.difference-unconfirmed) "witness-not-exhibited")])

(define umt.cases
  -> (urdr.model.common.append
       (umt.net-cases)
       (urdr.model.common.append
         (umt.caps-cases)
         (urdr.model.common.append
           (umt.timer-cases)
           (urdr.model.common.append
             (umt.fault-cases)
             (urdr.model.common.append
               (umt.glue-cases)
               (urdr.model.common.append
                 (umt.model-cases) (umt.witness-cases))))))))

(define umt.run
  -> (let Results (umt.emit-all (umt.cases) [])
       (if (umt.all-ok? Results)
           (do (output "MODELS CASES: ~A~%" (umt.count Results 0))
               (output "ALL PASS~%")
               done)
           (do (output "MODELS FAILED~%") failed))))

(umt.run)
