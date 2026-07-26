\\ SPEC.md 20 event records for abstract runs (M1 plan Wave E).
\\ Requires shen/protocol/canonical.shen, shen/world/integer.shen,
\\ shen/world/prng.shen, shen/world/component.shen, and
\\ shen/world/world.shen to be loaded by the caller.
\\
\\ Pure: no I/O, no host time, no host randomness, no floating point, no
\\ defprolog. An event log is a total function of (initial world,
\\ decision transcript) and of nothing else. Every operation returns
\\ [ok ...] or [error CODE DETAIL] and performs no work before
\\ validating.
\\
\\ NOT owned here: the reducer. This module calls urdr.world.reduce and
\\ nothing else that advances a world; it never invents an input and
\\ never repairs one. world.shen is unchanged.
\\
\\ =====================================================================
\\ 1. What an event record is
\\ =====================================================================
\\
\\ SPEC.md 20 lists the fields each event record carries. In an abstract
\\ run there are no adapters and no source locations, so the fields that
\\ name them are present and explicitly empty rather than dropped: a
\\ later milestone fills them without changing the schema.
\\
\\   [record [[actor          [bytes ACTOR]]
\\            [classification [symbol CLASS]]
\\            [event-id       INTEGER]
\\            [input-state    [bytes DIGEST]]
\\            [origin         INTEGER]
\\            [output-state   [bytes DIGEST]]
\\            [parents        [list INTEGER ...]]
\\            [payload        SLOT]
\\            [source         [null]]
\\            [subsystem      [symbol SUBSYSTEM]]
\\            [time           INTEGER]
\\            [type           [symbol TYPE]]]]
\\
\\ The twelve keys are in strictly ascending unsigned-ASCII order, so the
\\ record is canonical by construction (ADR 0002).
\\
\\ event-id     run-scoped, monotone, 0-based: the position of the input
\\              in the decision transcript. It is NOT the world's
\\              scheduling id, which is allocated when an event is queued
\\              and is therefore not monotone in processing order.
\\ origin       the world scheduling id this record allocated (a
\\              schedule) or dispatched (an advance). It is what ties a
\\              schedule record to the advance record that consumed it.
\\ parents      causal parent event-ids, in log id space. An advance
\\              names the schedule record that queued the world event it
\\              dispatches; a schedule has no causal parent, because in
\\              an abstract run a schedule comes from the transcript, not
\\              from a preceding reduction. The sequential chain is
\\              already carried by event-id and by the state hashes, so
\\              it is deliberately not repeated here.
\\ input-state  SHA-256 of the canonically encoded world snapshot value
\\ output-state (urdr.world.snapshot-value) before and after the
\\              reduction. Record i's input-state is record i-1's
\\              output-state by construction, so a break in that chain is
\\              a tampered log.
\\ source       [null] in M1. SPEC.md 20 says "source location when
\\              available"; in a modeled run it is not.
\\
\\ The run id is NOT repeated in every record. It is a hash over the
\\ whole transcript (SPEC.md 4) and so is only computable once the run
\\ has finished; a per-record copy would either be circular or be a
\\ second, unvalidated copy of the same fact. It is carried once, by the
\\ log header (urdr.eventlog.header-value), which binds it to the event
\\ root that commits to every record.
\\
\\ TYPE is STAGE-KIND, where STAGE is the reducer input form and KIND is
\\ the world event kind:
\\
\\   schedule-command    schedule-choice    schedule-component
\\   schedule-property   advance-command    advance-choice
\\   advance-component   advance-property
\\
\\ The kind names are deliberately not the bare reducer tags `command`
\\ and `choice`: those are reserved-authority names (component.shen), and
\\ nothing this module emits may put one in a structural position.
\\
\\ ACTOR / SUBSYSTEM:
\\
\\   schedule-*           actor `scenario`   subsystem `world`
\\   advance-command      actor `world`      subsystem `adapter`
\\   advance-property     actor `world`      subsystem `properties`
\\   advance-choice       actor = the choice's declared actor
\\                                           subsystem `prng`
\\   advance-component    actor = the component name
\\                                           subsystem `component`
\\
\\ actor is [bytes ...] because a PRNG actor is an arbitrary octet
\\ string, not necessarily a canonical symbol; subsystem is a symbol
\\ drawn from the fixed set above.
\\
\\ =====================================================================
\\ 2. Determinism classification (SPEC.md 20.1)
\\ =====================================================================
\\
\\ The representation admits all five classes -- pure, modeled,
\\ recorded, uncontrolled, forbidden -- so a later milestone extends the
\\ emitter, not the schema. M1 emits exactly two:
\\
\\   pure     a schedule. The input is an immutable transcript entry and
\\            the transcript is validated by hash (the run id commits to
\\            it), which is precisely SPEC.md 20.1's `pure`.
\\   modeled  an advance. Component steps, PRNG draws, property equality,
\\            and command emission are all generated by deterministic
\\            world policy.
\\
\\ urdr.eventlog.abstract-classification? is the predicate the
\\ certificate uses: any record outside {pure, modeled} voids a
\\ modeled-run claim.
\\
\\ =====================================================================
\\ 3. Content addressing (SPEC.md 20)
\\ =====================================================================
\\
\\ "Large payloads are content-addressed rather than duplicated." A
\\ payload is inlined when its canonical encoding is at most
\\ urdr.eventlog.max-inline-octets (1024) octets AND at most
\\ urdr.eventlog.max-inline-nodes (96) parsed nodes; otherwise the
\\ record carries
\\
\\   [record [[digest [bytes SHA-256]]
\\            [length INTEGER]
\\            [nodes  INTEGER]
\\            [type   [symbol content-address]]]]
\\
\\ Both bounds matter: the ADR 0002 m0 profile bounds a frame by octets
\\ AND by node count, and a record that inlined a 250-node payload would
\\ fail to encode even though it was small in octets. The thresholds sit
\\ strictly below the m0 limits (4096 octets, 256 nodes) with room for
\\ the twelve surrounding fields, so an event record always encodes.
\\
\\ This is safe precisely because every payload that reaches the reducer
\\ has already been encoded once: urdr.world.event-valid? refuses an
\\ event whose payload is not m0-canonical. A payload that cannot be
\\ encoded therefore cannot be in a transcript, and content addressing
\\ never has to hash something it cannot encode.
\\
\\ A list too large to encode as one value is content-addressed
\\ element-wise instead (urdr.eventlog.list-slot), because a monolithic
\\ encoding of it may not exist at all:
\\
\\   [record [[count INTEGER]
\\            [root  [bytes SHA-256]]
\\            [type  [symbol content-address-list]]]]
\\
\\ =====================================================================
\\ 4. Roots
\\ =====================================================================
\\
\\ A root commits to an ordered list of fixed-width digests under a
\\ domain tag:
\\
\\   root(TAG, [D0 ... Dn]) = SHA-256(TAG ++ D0 ++ ... ++ Dn)
\\
\\ Every Di is exactly 32 octets, so the concatenation is unambiguous and
\\ the root is sensitive to order, to insertion, and to truncation. The
\\ tag is what stops an event root from ever equalling a transcript root
\\ over the same digests.
\\
\\ The event root of a log is root(urdr-eventlog-root-v1, record
\\ digests), where a record digest is SHA-256 of the canonically encoded
\\ record value.
\\
\\ =====================================================================
\\ 5. Public entry points
\\ =====================================================================
\\
\\   of-run           INITIAL TRANSCRIPT -> [ok LOG] | [error CODE D]
\\   records          LOG -> [RECORD ...]
\\   digests          LOG -> [OCTETS ...]
\\   root             LOG -> OCTETS
\\   initial-state    LOG -> OCTETS
\\   state-root       LOG -> OCTETS
\\   final-world      LOG -> WORLD
\\   count            LOG -> host integer
\\   record-value     RECORD -> canonical record (section 1)
\\   record-values    [RECORD ...] -> [canonical record ...]
\\   header-value     LOG RUN-ID-VALUE -> canonical record
\\   counts-value     LOG -> canonical record of classification counts
\\   abstract?        LOG -> boolean
\\   slot / list-slot / value-digest / digest-of / root-of / nodes
\\   payload-value / payload-of / kind-name / kind-of-name  (shared with
\\                    shen/world/replay.shen)

\\ ---------------------------------------------------------------
\\ ASCII names as octet lists, so no host string model enters
\\ semantics (the discipline of world.shen and properties.shen). The
\\ k- / w- / t- selector prefixes follow netpol.shen: a bare selector
\\ such as `value`, `type`, `time`, or `length` is the name of a Shen
\\ primitive, and passing one as a literal symbol is exactly the
\\ function-symbol-as-value hazard the portability rules forbid.
\\ ---------------------------------------------------------------

(define urdr.eventlog.n
  k-actor ->
    [97 99 116 111 114]
  k-classification ->
    [99 108 97 115 115 105 102 105 99 97 116 105 111 110]
  k-event-id ->
    [101 118 101 110 116 45 105 100]
  k-input-state ->
    [105 110 112 117 116 45 115 116 97 116 101]
  k-origin ->
    [111 114 105 103 105 110]
  k-output-state ->
    [111 117 116 112 117 116 45 115 116 97 116 101]
  k-parents ->
    [112 97 114 101 110 116 115]
  k-payload ->
    [112 97 121 108 111 97 100]
  k-source ->
    [115 111 117 114 99 101]
  k-subsystem ->
    [115 117 98 115 121 115 116 101 109]
  k-time ->
    [116 105 109 101]
  k-type ->
    [116 121 112 101]
  k-digest ->
    [100 105 103 101 115 116]
  k-length ->
    [108 101 110 103 116 104]
  k-nodes ->
    [110 111 100 101 115]
  k-count ->
    [99 111 117 110 116]
  k-root ->
    [114 111 111 116]
  k-run-id ->
    [114 117 110 45 105 100]
  k-version ->
    [118 101 114 115 105 111 110]
  k-actual ->
    [97 99 116 117 97 108]
  k-expected ->
    [101 120 112 101 99 116 101 100]
  k-property ->
    [112 114 111 112 101 114 116 121]
  k-alternatives ->
    [97 108 116 101 114 110 97 116 105 118 101 115]
  k-purpose ->
    [112 117 114 112 111 115 101]
  k-name ->
    [110 97 109 101]
  k-value ->
    [118 97 108 117 101]
  w-content-address ->
    [99 111 110 116 101 110 116 45 97 100 100 114 101 115 115]
  w-content-address-list ->
    [99 111 110 116 101 110 116 45 97 100 100 114 101 115 115 45
     108 105 115 116]
  w-pure ->
    [112 117 114 101]
  w-modeled ->
    [109 111 100 101 108 101 100]
  w-recorded ->
    [114 101 99 111 114 100 101 100]
  w-uncontrolled ->
    [117 110 99 111 110 116 114 111 108 108 101 100]
  w-forbidden ->
    [102 111 114 98 105 100 100 101 110]
  w-world ->
    [119 111 114 108 100]
  w-component ->
    [99 111 109 112 111 110 101 110 116]
  w-prng ->
    [112 114 110 103]
  w-adapter ->
    [97 100 97 112 116 101 114]
  w-properties ->
    [112 114 111 112 101 114 116 105 101 115]
  w-scenario ->
    [115 99 101 110 97 114 105 111]
  w-schedule-command ->
    [115 99 104 101 100 117 108 101 45 99 111 109 109 97 110 100]
  w-schedule-choice ->
    [115 99 104 101 100 117 108 101 45 99 104 111 105 99 101]
  w-schedule-component ->
    [115 99 104 101 100 117 108 101 45 99 111 109 112 111 110 101
     110 116]
  w-schedule-property ->
    [115 99 104 101 100 117 108 101 45 112 114 111 112 101 114 116
     121]
  w-advance-command ->
    [97 100 118 97 110 99 101 45 99 111 109 109 97 110 100]
  w-advance-choice ->
    [97 100 118 97 110 99 101 45 99 104 111 105 99 101]
  w-advance-component ->
    [97 100 118 97 110 99 101 45 99 111 109 112 111 110 101 110
     116]
  w-advance-property ->
    [97 100 118 97 110 99 101 45 112 114 111 112 101 114 116 121]
  w-command-input ->
    [99 111 109 109 97 110 100 45 105 110 112 117 116]
  w-choice-input ->
    [99 104 111 105 99 101 45 105 110 112 117 116]
  w-component-input ->
    [99 111 109 112 111 110 101 110 116 45 105 110 112 117 116]
  w-property-input ->
    [112 114 111 112 101 114 116 121 45 105 110 112 117 116]
  w-eventlog-v1 ->
    [117 114 100 114 45 101 118 101 110 116 108 111 103 45 118 49]
  t-eventlog-root ->
    [117 114 100 114 45 101 118 101 110 116 108 111 103 45 114 111
     111 116 45 118 49])

\\ ---------------------------------------------------------------
\\ Resource thresholds for content addressing (section 3)
\\ ---------------------------------------------------------------

(define urdr.eventlog.max-inline-octets
  -> 1024)

(define urdr.eventlog.max-inline-nodes
  -> 96)

\\ ---------------------------------------------------------------
\\ Small list plumbing
\\ ---------------------------------------------------------------

(define urdr.eventlog.rev
  Values -> (urdr.canonical.rev Values))

(define urdr.eventlog.concat
  [] -> []
  [Bs | Rest] -> (append Bs (urdr.eventlog.concat Rest)))

(define urdr.eventlog.big
  N -> (urdr.int.raw.from-small N))

(define urdr.eventlog.member?
  _ [] -> false
  X [X | _] -> true
  X [_ | Rest] -> (urdr.eventlog.member? X Rest))

\\ ---------------------------------------------------------------
\\ Node counting, exactly as the canonical decoder counts nodes when it
\\ reparses an encoding (ADR 0002). An atom is one node and a list is one
\\ node plus its elements; the encoder writes every typed value as a list
\\ whose head is a tag atom, and every record field as a nested list
\\ whose head is the key atom.
\\ ---------------------------------------------------------------

(define urdr.eventlog.nodes
  [null] -> 2
  [bool _] -> 3
  [big _ _] -> 3
  [text _] -> 3
  [bytes _] -> 3
  [symbol _] -> 3
  [list Values] -> (+ 2 (urdr.eventlog.nodes-values Values 0))
  [record Fields] -> (+ 2 (urdr.eventlog.nodes-fields Fields 0))
  _ -> 0)

(define urdr.eventlog.nodes-values
  [] Acc -> Acc
  [Value | Rest] Acc ->
    (urdr.eventlog.nodes-values
      Rest (+ Acc (urdr.eventlog.nodes Value)))
  _ Acc -> Acc)

(define urdr.eventlog.nodes-fields
  [] Acc -> Acc
  [[_ Value] | Rest] Acc ->
    (urdr.eventlog.nodes-fields
      Rest (+ Acc (+ 2 (urdr.eventlog.nodes Value))))
  _ Acc -> Acc)

\\ ---------------------------------------------------------------
\\ Digests
\\ ---------------------------------------------------------------

(define urdr.eventlog.digest-of
  Octets ->
    (let Hashed (urdr.sha256 Octets)
      (if (= (hd Hashed) error)
          [error eventlog-digest-input [null]]
          [ok (hd (tl Hashed))])))

(define urdr.eventlog.value-digest
  Value ->
    (let Encoded (urdr.canonical.encode-payload Value)
      (if (= (hd Encoded) error)
          [error eventlog-encode [null]]
          (urdr.eventlog.digest-of (hd (tl Encoded))))))

\\ root(TAG, [D0 ... Dn]) = SHA-256(TAG ++ D0 ++ ... ++ Dn)
(define urdr.eventlog.root-of
  Tag Digests ->
    (urdr.eventlog.digest-of
      (append Tag (urdr.eventlog.concat Digests))))

\\ ---------------------------------------------------------------
\\ Payload slots (section 3)
\\ ---------------------------------------------------------------

(define urdr.eventlog.address-value
  Digest Octets Nodes ->
    [record
      [[(urdr.eventlog.n k-digest) [bytes Digest]]
       [(urdr.eventlog.n k-length) (urdr.eventlog.big Octets)]
       [(urdr.eventlog.n k-nodes) (urdr.eventlog.big Nodes)]
       [(urdr.eventlog.n k-type)
        [symbol (urdr.eventlog.n w-content-address)]]]])

(define urdr.eventlog.slot
  Value ->
    (let Encoded (urdr.canonical.encode-payload Value)
      (if (= (hd Encoded) error)
          [error eventlog-encode [null]]
          (urdr.eventlog.slot-sized
            Value
            (hd (tl Encoded))
            (length (hd (tl Encoded)))
            (urdr.eventlog.nodes Value)))))

(define urdr.eventlog.slot-sized
  Value Encoded Octets Nodes ->
    (if (and (<= Octets (urdr.eventlog.max-inline-octets))
             (<= Nodes (urdr.eventlog.max-inline-nodes)))
        [ok Value]
        (urdr.eventlog.slot-address
          (urdr.eventlog.digest-of Encoded) Octets Nodes)))

(define urdr.eventlog.slot-address
  [error Code Detail] _ _ -> [error Code Detail]
  [ok Digest] Octets Nodes ->
    [ok (urdr.eventlog.address-value Digest Octets Nodes)])

(define urdr.eventlog.address-list-value
  Root Count ->
    [record
      [[(urdr.eventlog.n k-count) (urdr.eventlog.big Count)]
       [(urdr.eventlog.n k-root) [bytes Root]]
       [(urdr.eventlog.n k-type)
        [symbol (urdr.eventlog.n w-content-address-list)]]]])

\\ A list slot inlines the whole list when it encodes within the same two
\\ thresholds, and otherwise commits to it element-wise. The
\\ element-wise form never needs an encoding of the whole list, which may
\\ not exist under the m0 profile at all.
(define urdr.eventlog.list-slot
  Tag Values ->
    (urdr.eventlog.list-slot-try
      Tag Values (urdr.canonical.encode-payload [list Values])))

(define urdr.eventlog.list-slot-try
  Tag Values [error _] ->
    (urdr.eventlog.list-slot-address Tag Values)
  Tag Values [ok Encoded] ->
    (if (and (<= (length Encoded) (urdr.eventlog.max-inline-octets))
             (<= (urdr.eventlog.nodes [list Values])
                 (urdr.eventlog.max-inline-nodes)))
        [ok [list Values]]
        (urdr.eventlog.list-slot-address Tag Values)))

(define urdr.eventlog.list-slot-address
  Tag Values ->
    (urdr.eventlog.list-slot-digests
      Tag (urdr.eventlog.value-digests Values []) (length Values)))

(define urdr.eventlog.list-slot-digests
  Tag [error Code Detail] _ -> [error Code Detail]
  Tag [ok Digests] Count ->
    (urdr.eventlog.list-slot-root
      (urdr.eventlog.root-of Tag Digests) Count))

(define urdr.eventlog.list-slot-root
  [error Code Detail] _ -> [error Code Detail]
  [ok Root] Count ->
    [ok (urdr.eventlog.address-list-value Root Count)])

(define urdr.eventlog.value-digests
  [] Acc -> [ok (urdr.eventlog.rev Acc)]
  [Value | Rest] Acc ->
    (urdr.eventlog.value-digests-step
      (urdr.eventlog.value-digest Value) Rest Acc)
  _ Acc -> [error eventlog-list-shape [null]])

(define urdr.eventlog.value-digests-step
  [error Code Detail] _ _ -> [error Code Detail]
  [ok Digest] Rest Acc ->
    (urdr.eventlog.value-digests Rest [Digest | Acc]))

\\ ---------------------------------------------------------------
\\ Classification (section 2)
\\ ---------------------------------------------------------------

\\ Ascending unsigned-ASCII order: this is the key order of the counts
\\ record, so the record is canonical by construction.
(define urdr.eventlog.classifications
  -> [(urdr.eventlog.n w-forbidden)
      (urdr.eventlog.n w-modeled)
      (urdr.eventlog.n w-pure)
      (urdr.eventlog.n w-recorded)
      (urdr.eventlog.n w-uncontrolled)])

(define urdr.eventlog.classification?
  Class -> (urdr.eventlog.member? Class (urdr.eventlog.classifications)))

(define urdr.eventlog.abstract-classification?
  Class ->
    (or (= Class (urdr.eventlog.n w-pure))
        (= Class (urdr.eventlog.n w-modeled))))

\\ ---------------------------------------------------------------
\\ Canonical projections of reducer event payloads. These are shared
\\ with shen/world/replay.shen, which reads them back: the projection and
\\ its inverse are defined together so a round trip cannot drift.
\\ ---------------------------------------------------------------

(define urdr.eventlog.payload-value
  command Payload -> [ok Payload]
  property-equals [property Id Actual Expected] ->
    [ok
      [record
        [[(urdr.eventlog.n k-actual) Actual]
         [(urdr.eventlog.n k-expected) Expected]
         [(urdr.eventlog.n k-property) Id]]]]
  choice [choice Subsystem Actor Purpose Alternatives] ->
    [ok
      [record
        [[(urdr.eventlog.n k-actor) [bytes Actor]]
         [(urdr.eventlog.n k-alternatives) [list Alternatives]]
         [(urdr.eventlog.n k-purpose) [bytes Purpose]]
         [(urdr.eventlog.n k-subsystem) [bytes Subsystem]]]]]
  component [component-input Name Value] ->
    [ok
      [record
        [[(urdr.eventlog.n k-name) [bytes Name]]
         [(urdr.eventlog.n k-value) Value]]]]
  _ _ -> [error eventlog-event-kind [null]])

\\ The inverse of payload-value. Key patterns are written as literal
\\ octets so the reader is a pattern match and not a search.
(define urdr.eventlog.payload-of
  command Value -> [ok Value]
  property-equals
  [record
    [[[97 99 116 117 97 108] Actual]
     [[101 120 112 101 99 116 101 100] Expected]
     [[112 114 111 112 101 114 116 121] Id]]] ->
    [ok [property Id Actual Expected]]
  choice
  [record
    [[[97 99 116 111 114] [bytes Actor]]
     [[97 108 116 101 114 110 97 116 105 118 101 115]
      [list Alternatives]]
     [[112 117 114 112 111 115 101] [bytes Purpose]]
     [[115 117 98 115 121 115 116 101 109] [bytes Subsystem]]]] ->
    [ok [choice Subsystem Actor Purpose Alternatives]]
  component
  [record
    [[[110 97 109 101] [bytes Name]]
     [[118 97 108 117 101] Value]]] ->
    [ok [component-input Name Value]]
  _ _ -> [error eventlog-payload-shape [null]])

\\ Kind names travel as canonical symbols that are not reserved
\\ authorities (component.shen), so `command` becomes `command-input`
\\ and `choice` becomes `choice-input`.
(define urdr.eventlog.kind-name
  command -> [ok (urdr.eventlog.n w-command-input)]
  choice -> [ok (urdr.eventlog.n w-choice-input)]
  component -> [ok (urdr.eventlog.n w-component-input)]
  property-equals -> [ok (urdr.eventlog.n w-property-input)]
  _ -> [error eventlog-event-kind [null]])

(define urdr.eventlog.kind-of-name
  [99 111 109 109 97 110 100 45 105 110 112 117 116] -> [ok command]
  [99 104 111 105 99 101 45 105 110 112 117 116] -> [ok choice]
  [99 111 109 112 111 110 101 110 116 45 105 110 112 117 116] ->
    [ok component]
  [112 114 111 112 101 114 116 121 45 105 110 112 117 116] ->
    [ok property-equals]
  _ -> [error eventlog-event-kind [null]])

\\ ---------------------------------------------------------------
\\ Per-kind actor, subsystem, and type
\\ ---------------------------------------------------------------

(define urdr.eventlog.schedule-type
  command -> [ok (urdr.eventlog.n w-schedule-command)]
  choice -> [ok (urdr.eventlog.n w-schedule-choice)]
  component -> [ok (urdr.eventlog.n w-schedule-component)]
  property-equals -> [ok (urdr.eventlog.n w-schedule-property)]
  _ -> [error eventlog-event-kind [null]])

(define urdr.eventlog.advance-type
  command -> [ok (urdr.eventlog.n w-advance-command)]
  choice -> [ok (urdr.eventlog.n w-advance-choice)]
  component -> [ok (urdr.eventlog.n w-advance-component)]
  property-equals -> [ok (urdr.eventlog.n w-advance-property)]
  _ -> [error eventlog-event-kind [null]])

(define urdr.eventlog.advance-subsystem
  command -> (urdr.eventlog.n w-adapter)
  choice -> (urdr.eventlog.n w-prng)
  component -> (urdr.eventlog.n w-component)
  property-equals -> (urdr.eventlog.n w-properties)
  _ -> (urdr.eventlog.n w-world))

(define urdr.eventlog.advance-actor
  choice [choice _ Actor _ _] -> Actor
  component [component-input Name _] -> Name
  _ _ -> (urdr.eventlog.n w-world))

\\ ---------------------------------------------------------------
\\ State hashes
\\ ---------------------------------------------------------------

\\ A state hash is over the canonically encoded world snapshot value, and
\\ a snapshot that does not encode under the m0 profile is a fail-closed
\\ run error with its own code -- not a skipped hash, and not the generic
\\ payload-encode code, because the two have different remedies (a
\\ smaller payload versus a run with fewer verdicts or components).
(define urdr.eventlog.state-digest
  World ->
    (if (urdr.world.valid? World)
        (urdr.eventlog.state-digest-of
          (urdr.canonical.encode-payload
            (urdr.world.snapshot-value World)))
        [error eventlog-invalid-world [null]]))

(define urdr.eventlog.state-digest-of
  [error _] -> [error eventlog-state-encode [null]]
  [ok Encoded] -> (urdr.eventlog.digest-of Encoded))

\\ ---------------------------------------------------------------
\\ Record construction and accessors
\\ ---------------------------------------------------------------

(define urdr.eventlog.record-value
  [erecord Actor Class Id InState Origin OutState Parents Payload
           Source Subsystem Time Type] ->
    [record
      [[(urdr.eventlog.n k-actor) [bytes Actor]]
       [(urdr.eventlog.n k-classification) [symbol Class]]
       [(urdr.eventlog.n k-event-id) Id]
       [(urdr.eventlog.n k-input-state) [bytes InState]]
       [(urdr.eventlog.n k-origin) Origin]
       [(urdr.eventlog.n k-output-state) [bytes OutState]]
       [(urdr.eventlog.n k-parents) [list Parents]]
       [(urdr.eventlog.n k-payload) Payload]
       [(urdr.eventlog.n k-source) Source]
       [(urdr.eventlog.n k-subsystem) [symbol Subsystem]]
       [(urdr.eventlog.n k-time) Time]
       [(urdr.eventlog.n k-type) [symbol Type]]]])

(define urdr.eventlog.record-values
  [] -> []
  [R | Rest] ->
    [(urdr.eventlog.record-value R) |
     (urdr.eventlog.record-values Rest)])

(define urdr.eventlog.record-classification
  [erecord _ Class _ _ _ _ _ _ _ _ _ _] -> Class)

(define urdr.eventlog.record-id
  [erecord _ _ Id _ _ _ _ _ _ _ _ _] -> Id)

(define urdr.eventlog.record-type
  [erecord _ _ _ _ _ _ _ _ _ _ _ Type] -> Type)

\\ ---------------------------------------------------------------
\\ Building a log from a run
\\ ---------------------------------------------------------------

(define urdr.eventlog.of-run
  Initial Transcript ->
    (if (urdr.world.valid? Initial)
        (urdr.eventlog.of-run-start
          Initial Transcript (urdr.eventlog.state-digest Initial))
        [error eventlog-invalid-world [null]]))

(define urdr.eventlog.of-run-start
  Initial Transcript [error Code Detail] -> [error Code Detail]
  Initial Transcript [ok InState] ->
    (urdr.eventlog.walk
      Initial Transcript 0 InState InState [] [] []))

\\ World, remaining inputs, next log id, the digest of the initial state,
\\ the digest of the current state, world-id -> log-id links, reversed
\\ records, reversed record digests.
(define urdr.eventlog.walk
  World [] _ Initial State Links Recs Digs ->
    (urdr.eventlog.finish
      World Initial State
      (urdr.eventlog.rev Recs)
      (urdr.eventlog.rev Digs))
  World [Input | Rest] Id Initial State Links Recs Digs ->
    (urdr.eventlog.plan-step
      (urdr.eventlog.plan World Input)
      World Rest Id Initial State Links Recs Digs)
  World _ _ _ _ _ _ _ -> [error eventlog-transcript-shape [null]])

(define urdr.eventlog.plan-step
  [error Code Detail] _ _ _ _ _ _ _ _ -> [error Code Detail]
  [ok Plan] World Rest Id Initial State Links Recs Digs ->
    (urdr.eventlog.reduce-step
      Plan World Rest Id Initial State Links Recs Digs))

\\ A plan is what the record will say, decided BEFORE the reduction,
\\ because the world event an advance dispatches is only visible in the
\\ pending queue beforehand.
(define urdr.eventlog.plan
  World [schedule At Kind Payload] ->
    (urdr.eventlog.plan-schedule
      (urdr.eventlog.schedule-type Kind)
      (urdr.eventlog.payload-value Kind Payload)
      (urdr.world.next-event-id World)
      [schedule At Kind Payload])
  World [advance-to-next-event] ->
    (urdr.eventlog.plan-advance (urdr.world.pending World))
  World _ -> [error eventlog-input-shape [null]])

(define urdr.eventlog.plan-schedule
  [error Code Detail] _ _ _ -> [error Code Detail]
  _ [error Code Detail] _ _ -> [error Code Detail]
  [ok Type] [ok Payload] Origin Input ->
    [ok
      [plan Input schedule Origin Type
        (urdr.eventlog.n w-scenario)
        (urdr.eventlog.n w-world)
        (urdr.eventlog.n w-pure)
        Payload
        []]])

(define urdr.eventlog.plan-advance
  [] -> [error eventlog-no-pending-event [null]]
  [[event Id _ Kind Payload] | _] ->
    (urdr.eventlog.plan-advance-kind
      (urdr.eventlog.advance-type Kind)
      (urdr.eventlog.payload-value Kind Payload)
      Id Kind Payload)
  _ -> [error eventlog-pending-shape [null]])

(define urdr.eventlog.plan-advance-kind
  [error Code Detail] _ _ _ _ -> [error Code Detail]
  _ [error Code Detail] _ _ _ -> [error Code Detail]
  [ok Type] [ok Payload] Origin Kind EventPayload ->
    [ok
      [plan [advance-to-next-event] advance Origin Type
        (urdr.eventlog.advance-actor Kind EventPayload)
        (urdr.eventlog.advance-subsystem Kind)
        (urdr.eventlog.n w-modeled)
        Payload
        [parent-of Origin]]])

(define urdr.eventlog.reduction-detail
  [reduction _ _ [error Detail]] -> Detail
  _ -> [null])

(define urdr.eventlog.reduce-step
  Plan World Rest Id Initial State Links Recs Digs ->
    (urdr.eventlog.reduce-result
      (urdr.world.reduce World (urdr.eventlog.plan-input Plan))
      Plan Rest Id Initial State Links Recs Digs))

(define urdr.eventlog.plan-input
  [plan Input _ _ _ _ _ _ _ _] -> Input)

(define urdr.eventlog.reduce-result
  Reduction Plan Rest Id Initial State Links Recs Digs ->
    (if (urdr.world.reduction-error? Reduction)
        [error eventlog-reduction-error
          (urdr.eventlog.reduction-detail Reduction)]
        (urdr.eventlog.commit-state
          Plan (urdr.world.reduction-world Reduction)
          Rest Id Initial State Links Recs Digs
          (urdr.eventlog.state-digest
            (urdr.world.reduction-world Reduction)))))

(define urdr.eventlog.commit-state
  _ _ _ _ _ _ _ _ _ [error Code Detail] -> [error Code Detail]
  Plan Next Rest Id Initial State Links Recs Digs [ok OutState] ->
    (urdr.eventlog.commit-slot
      Plan Next Rest Id Initial State Links Recs Digs OutState
      (urdr.eventlog.slot (urdr.eventlog.plan-payload Plan))))

(define urdr.eventlog.plan-payload
  [plan _ _ _ _ _ _ _ Payload _] -> Payload)

(define urdr.eventlog.commit-slot
  _ _ _ _ _ _ _ _ _ _ [error Code Detail] -> [error Code Detail]
  [plan _ Stage Origin Type Actor Subsystem Class _ Parents]
  Next Rest Id Initial State Links Recs Digs OutState [ok Slot] ->
    (urdr.eventlog.commit-record
      [erecord Actor Class (urdr.eventlog.big Id) State Origin
        OutState (urdr.eventlog.parents Parents Links) Slot [null]
        Subsystem (urdr.world.time Next) Type]
      Stage Origin Next Rest Id Initial OutState Links Recs Digs))

(define urdr.eventlog.commit-record
  Record Stage Origin Next Rest Id Initial OutState Links Recs Digs ->
    (urdr.eventlog.commit-digest
      (urdr.eventlog.value-digest (urdr.eventlog.record-value Record))
      Record Stage Origin Next Rest Id Initial OutState Links Recs
      Digs))

(define urdr.eventlog.commit-digest
  [error Code Detail] _ _ _ _ _ _ _ _ _ _ _ -> [error Code Detail]
  [ok Digest] Record Stage Origin Next Rest Id Initial OutState Links
  Recs Digs ->
    (urdr.eventlog.walk
      Next Rest (+ Id 1) Initial OutState
      (urdr.eventlog.link Stage Origin Id Links)
      [Record | Recs]
      [Digest | Digs]))

\\ Only a schedule allocates a world event id, so only a schedule adds a
\\ link. Ids are unique within a run, so the newest entry is prepended
\\ and the first match wins.
(define urdr.eventlog.link
  schedule Origin Id Links -> [[link Origin Id] | Links]
  _ _ _ Links -> Links)

(define urdr.eventlog.parents
  [] _ -> []
  [parent-of Origin] Links ->
    (urdr.eventlog.parent-lookup Origin Links)
  _ _ -> [])

(define urdr.eventlog.parent-lookup
  _ [] -> []
  Origin [[link Other Id] | Rest] ->
    (if (= (hd (tl (urdr.int.compare Origin Other))) 0)
        [(urdr.eventlog.big Id)]
        (urdr.eventlog.parent-lookup Origin Rest)))

(define urdr.eventlog.finish
  World Initial State Recs Digs ->
    (urdr.eventlog.finish-root
      (urdr.eventlog.root-of
        (urdr.eventlog.n t-eventlog-root) Digs)
      World Initial State Recs Digs))

(define urdr.eventlog.finish-root
  [error Code Detail] _ _ _ _ _ -> [error Code Detail]
  [ok Root] World Initial State Recs Digs ->
    [ok [eventlog Recs Digs Root Initial State World]])

\\ ---------------------------------------------------------------
\\ Log accessors
\\ ---------------------------------------------------------------

(define urdr.eventlog.records
  [eventlog Recs _ _ _ _ _] -> Recs)

(define urdr.eventlog.digests
  [eventlog _ Digs _ _ _ _] -> Digs)

(define urdr.eventlog.root
  [eventlog _ _ Root _ _ _] -> Root)

(define urdr.eventlog.initial-state
  [eventlog _ _ _ Initial _ _] -> Initial)

\\ The final semantic state root of SPEC.md 21: the digest of the
\\ canonically encoded snapshot of the world the run ended in.
(define urdr.eventlog.state-root
  [eventlog _ _ _ _ State _] -> State)

(define urdr.eventlog.final-world
  [eventlog _ _ _ _ _ World] -> World)

(define urdr.eventlog.count
  Log -> (length (urdr.eventlog.records Log)))

\\ ---------------------------------------------------------------
\\ Entropy-firewall counts (SPEC.md 20.1, 21)
\\ ---------------------------------------------------------------

(define urdr.eventlog.count-class
  _ [] Acc -> Acc
  Class [Record | Rest] Acc ->
    (urdr.eventlog.count-class
      Class Rest
      (if (= (urdr.eventlog.record-classification Record) Class)
          (+ Acc 1)
          Acc)))

(define urdr.eventlog.counts-entries
  _ [] -> []
  Records [Class | Rest] ->
    [[Class
      (urdr.eventlog.big
        (urdr.eventlog.count-class Class Records 0))] |
     (urdr.eventlog.counts-entries Records Rest)])

\\ Every class is reported, including the four that must be zero. A
\\ certificate that only listed the classes it saw could not distinguish
\\ "no uncontrolled events" from "uncontrolled events not counted".
(define urdr.eventlog.counts-value
  Log ->
    [record
      (urdr.eventlog.counts-entries
        (urdr.eventlog.records Log)
        (urdr.eventlog.classifications))])

(define urdr.eventlog.abstract-records?
  [] -> true
  [Record | Rest] ->
    (and (urdr.eventlog.abstract-classification?
           (urdr.eventlog.record-classification Record))
         (urdr.eventlog.abstract-records? Rest)))

(define urdr.eventlog.abstract?
  Log -> (urdr.eventlog.abstract-records? (urdr.eventlog.records Log)))

\\ ---------------------------------------------------------------
\\ Log header: the one place a run id is bound to an event root.
\\ ---------------------------------------------------------------

(define urdr.eventlog.header-value
  Log RunId ->
    [record
      [[(urdr.eventlog.n k-count)
        (urdr.eventlog.big (urdr.eventlog.count Log))]
       [(urdr.eventlog.n k-root) [bytes (urdr.eventlog.root Log)]]
       [(urdr.eventlog.n k-run-id) RunId]
       [(urdr.eventlog.n k-version)
        [symbol (urdr.eventlog.n w-eventlog-v1)]]]])
