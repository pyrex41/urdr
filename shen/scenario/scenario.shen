\\ Urdr scenario declarations and strict validation (SPEC.md 18, M1 subset).
\\ Requires canonical.shen (ADR 0002) and integer.shen (ADR 0003) to be
\\ loaded by the caller. Pure: no I/O, no host time, no host randomness,
\\ no floating point. Every public operation returns [ok ...] or
\\ [error stable-code] and performs no effect before validating.
\\
\\ A scenario is one canonical record whose keys are exactly, in strictly
\\ increasing unsigned ASCII order:
\\
\\   budget header-vocabulary components determinism faults
\\   observations properties seed topology version
\\
\\ (spelled in sorted order below). The M1 subset deliberately omits the
\\ SPEC.md 18 declarations that require real guests or external systems:
\\ artifact and guest-image manifests, cluster manifests and OCI
\\ workloads, external transcripts, and artifact-retention policy. A
\\ scenario that names them is rejected as an unknown field rather than
\\ silently ignored.
\\
\\ Size: a scenario is exactly one canonical value, so the ADR 0002 M0
\\ resource profile applies unchanged (4,096 payload octets, 256 parsed
\\ nodes, 32 nested lists, 256-octet atoms). A larger declaration is
\\ rejected with the ADR 0002 code (frame-too-large, nodes-too-many,
\\ depth-too-large) rather than silently accepted; raising the ceiling
\\ is an ADR 0002 amendment, not a scenario-module decision.

(set *urdr.scenario.max-seed* 64)

\\ ---------------------------------------------------------------------
\\ ASCII names. Spelled as octet lists so no host string model enters
\\ semantics (the discipline of shen/world/world.shen).
\\ ---------------------------------------------------------------------

(define urdr.scenario.n.address
  -> [97 100 100 114 101 115 115])

(define urdr.scenario.n.at
  -> [97 116])

(define urdr.scenario.n.budget
  -> [98 117 100 103 101 116])

(define urdr.scenario.n.class
  -> [99 108 97 115 115])

(define urdr.scenario.n.components
  -> [99 111 109 112 111 110 101 110 116 115])

(define urdr.scenario.n.crash
  -> [99 114 97 115 104])

(define urdr.scenario.n.delay
  -> [100 101 108 97 121])

(define urdr.scenario.n.determinism
  -> [100 101 116 101 114 109 105 110 105 115 109])

(define urdr.scenario.n.drop
  -> [100 114 111 112])

(define urdr.scenario.n.dst
  -> [100 115 116])

(define urdr.scenario.n.fault
  -> [102 97 117 108 116])

(define urdr.scenario.n.faults
  -> [102 97 117 108 116 115])

(define urdr.scenario.n.field
  -> [102 105 101 108 100])

(define urdr.scenario.n.from
  -> [102 114 111 109])

(define urdr.scenario.n.header-vocabulary
  -> [104 101 97 100 101 114 45 118 111 99 97 98 117 108 97
      114 121])

(define urdr.scenario.n.id
  -> [105 100])

(define urdr.scenario.n.invariant
  -> [105 110 118 97 114 105 97 110 116])

(define urdr.scenario.n.kind
  -> [107 105 110 100])

(define urdr.scenario.n.kinds
  -> [107 105 110 100 115])

(define urdr.scenario.n.links
  -> [108 105 110 107 115])

(define urdr.scenario.n.liveness
  -> [108 105 118 101 110 101 115 115])

(define urdr.scenario.n.max-events
  -> [109 97 120 45 101 118 101 110 116 115])

(define urdr.scenario.n.max-runs
  -> [109 97 120 45 114 117 110 115])

(define urdr.scenario.n.max-steps
  -> [109 97 120 45 115 116 101 112 115])

(define urdr.scenario.n.members
  -> [109 101 109 98 101 114 115])

(define urdr.scenario.n.modeled
  -> [109 111 100 101 108 101 100])

(define urdr.scenario.n.net
  -> [110 101 116])

(define urdr.scenario.n.node
  -> [110 111 100 101])

(define urdr.scenario.n.nodes
  -> [110 111 100 101 115])

(define urdr.scenario.n.observations
  -> [111 98 115 101 114 118 97 116 105 111 110 115])

(define urdr.scenario.n.partition
  -> [112 97 114 116 105 116 105 111 110])

(define urdr.scenario.n.process
  -> [112 114 111 99 101 115 115])

(define urdr.scenario.n.properties
  -> [112 114 111 112 101 114 116 105 101 115])

(define urdr.scenario.n.restart
  -> [114 101 115 116 97 114 116])

(define urdr.scenario.n.scenario.v1
  -> [115 99 101 110 97 114 105 111 47 118 49])

(define urdr.scenario.n.seed
  -> [115 101 101 100])

(define urdr.scenario.n.spec
  -> [115 112 101 99])

(define urdr.scenario.n.src
  -> [115 114 99])

(define urdr.scenario.n.temporal
  -> [116 101 109 112 111 114 97 108])

(define urdr.scenario.n.timer
  -> [116 105 109 101 114])

(define urdr.scenario.n.to
  -> [116 111])

(define urdr.scenario.n.topology
  -> [116 111 112 111 108 111 103 121])

(define urdr.scenario.n.values
  -> [118 97 108 117 101 115])

(define urdr.scenario.n.version
  -> [118 101 114 115 105 111 110])

\\ ---------------------------------------------------------------------
\\ Declared vocabularies. Anything outside them is a fail-closed error;
\\ nothing is narrowed, defaulted, or ignored.
\\ ---------------------------------------------------------------------

(define urdr.scenario.scenario-keys
  -> [(urdr.scenario.n.budget)
      (urdr.scenario.n.components)
      (urdr.scenario.n.determinism)
      (urdr.scenario.n.faults)
      (urdr.scenario.n.header-vocabulary)
      (urdr.scenario.n.observations)
      (urdr.scenario.n.properties)
      (urdr.scenario.n.seed)
      (urdr.scenario.n.topology)
      (urdr.scenario.n.version)])

(define urdr.scenario.budget-keys
  -> [(urdr.scenario.n.max-events)
      (urdr.scenario.n.max-runs)
      (urdr.scenario.n.max-steps)])

(define urdr.scenario.topology-keys
  -> [(urdr.scenario.n.links) (urdr.scenario.n.nodes)])

(define urdr.scenario.node-keys
  -> [(urdr.scenario.n.address) (urdr.scenario.n.id)])

(define urdr.scenario.link-keys
  -> [(urdr.scenario.n.from) (urdr.scenario.n.to)])

(define urdr.scenario.component-keys
  -> [(urdr.scenario.n.id)
      (urdr.scenario.n.kind)
      (urdr.scenario.n.node)])

(define urdr.scenario.fault-keys
  -> [(urdr.scenario.n.id)
      (urdr.scenario.n.kinds)
      (urdr.scenario.n.members)])

(define urdr.scenario.header-keys
  -> [(urdr.scenario.n.field) (urdr.scenario.n.values)])

(define urdr.scenario.observation-keys
  -> [(urdr.scenario.n.at) (urdr.scenario.n.id)])

(define urdr.scenario.property-keys
  -> [(urdr.scenario.n.class)
      (urdr.scenario.n.id)
      (urdr.scenario.n.spec)])

\\ M1 modeled-component kinds (plan Wave C: net, timer, fault models,
\\ plus modeled processes). L7 and guest-backed kinds are M2+.
(define urdr.scenario.component-kinds
  -> [(urdr.scenario.n.fault)
      (urdr.scenario.n.net)
      (urdr.scenario.n.process)
      (urdr.scenario.n.timer)])

\\ M1 fault types expressible over the abstract world.
(define urdr.scenario.fault-kinds
  -> [(urdr.scenario.n.crash)
      (urdr.scenario.n.delay)
      (urdr.scenario.n.drop)
      (urdr.scenario.n.partition)
      (urdr.scenario.n.restart)])

\\ M1 property classes (SPEC.md 18.1). Crash, log, and metamorphic
\\ predicates need real guests and are rejected rather than reserved
\\ silently.
(define urdr.scenario.property-classes
  -> [(urdr.scenario.n.invariant)
      (urdr.scenario.n.liveness)
      (urdr.scenario.n.temporal)])

\\ Header fields the M1 NetKAT fragment needs to express reachability.
(define urdr.scenario.required-header-fields
  -> [(urdr.scenario.n.dst) (urdr.scenario.n.src)])

\\ ---------------------------------------------------------------------
\\ Generic helpers.
\\ ---------------------------------------------------------------------

(define urdr.scenario.rev
  Xs -> (urdr.canonical.rev Xs))

(define urdr.scenario.member?
  Bs [] -> false
  Bs [X | Xs] ->
    (if (= (urdr.canonical.bytes-compare Bs X) eq)
        true
        (urdr.scenario.member? Bs Xs)))

\\ Every value that reaches validation must be an ADR 0002 canonical
\\ value. This single gate rejects floats, improper lists, unordered or
\\ duplicated record keys, non-normalized software integers, invalid
\\ UTF-8, oversized atoms, and anything above the M0 resource profile,
\\ with the ADR 0002 stable code, before any scenario field is read.
(define urdr.scenario.canonical
  Value ->
    (let Encoded (urdr.canonical.encode-payload Value)
      (if (= (hd Encoded) error)
          Encoded
          [ok])))

(define urdr.scenario.record
  [record Fields] Code -> [ok Fields]
  _ Code -> [error Code])

(define urdr.scenario.items
  [list Items] Code -> [ok Items]
  _ Code -> [error Code])

\\ Exact field-set match against a sorted expected key list. Canonical
\\ records are already strictly key-ordered, so an actual key that
\\ matches a later expected key proves the skipped keys are missing and
\\ an actual key matching no expected key is unknown.
(define urdr.scenario.fields
  [] [] Acc -> [ok (urdr.scenario.rev Acc)]
  [] [_ | _] Acc -> [error scenario-missing-field]
  [_ | _] [] Acc -> [error scenario-unknown-field]
  [[Key Value] | Fields] [Expected | Keys] Acc ->
    (if (= (urdr.canonical.bytes-compare Key Expected) eq)
        (urdr.scenario.fields Fields Keys [Value | Acc])
        (if (urdr.scenario.member? Key Keys)
            [error scenario-missing-field]
            [error scenario-unknown-field]))
  _ _ Acc -> [error scenario-unknown-field])

(define urdr.scenario.record-fields
  Value Keys Code ->
    (urdr.scenario.record-fields-of
      (urdr.scenario.record Value Code) Keys))

(define urdr.scenario.record-fields-of
  [error E] Keys -> [error E]
  [ok Fields] Keys -> (urdr.scenario.fields Fields Keys []))

(define urdr.scenario.symbol
  [symbol Bs] Code -> [ok Bs]
  _ Code -> [error Code])

(define urdr.scenario.octets
  [bytes Bs] Code -> [ok Bs]
  _ Code -> [error Code])

(define urdr.scenario.integer
  [big Sign Limbs] Code ->
    (if (urdr.int.valid? [big Sign Limbs])
        [ok [big Sign Limbs]]
        [error Code])
  _ Code -> [error Code])

(define urdr.scenario.negative?
  N -> (< (urdr.int.raw.compare N (urdr.int.zero)) 0))

(define urdr.scenario.positive?
  N -> (> (urdr.int.raw.compare N (urdr.int.zero)) 0))

\\ Strict ascending order over octet keys.
\\ Previous is [] before the first item (no key sorts before it because
\\ canonical symbols are nonempty).
(define urdr.scenario.ascending
  none Current DuplicateCode OrderCode -> [ok]
  Previous Current DuplicateCode OrderCode ->
    (let Order (urdr.canonical.bytes-compare Previous Current)
      (if (= Order eq)
          [error DuplicateCode]
          (if (= Order gt)
              [error OrderCode]
              [ok]))))

\\ Strict ascending order over software integers.
(define urdr.scenario.ascending-int
  none Current DuplicateCode OrderCode -> [ok]
  Previous Current DuplicateCode OrderCode ->
    (let Order (urdr.int.raw.compare Previous Current)
      (if (= Order 0)
          [error DuplicateCode]
          (if (> Order 0)
              [error OrderCode]
              [ok]))))

\\ ---------------------------------------------------------------------
\\ version, seed, determinism.
\\ ---------------------------------------------------------------------

(define urdr.scenario.version
  Value ->
    (urdr.scenario.version-symbol
      (urdr.scenario.symbol Value scenario-version)))

(define urdr.scenario.version-symbol
  [error E] -> [error E]
  [ok Bs] ->
    (if (= (urdr.canonical.bytes-compare
             Bs (urdr.scenario.n.scenario.v1))
           eq)
        [ok Bs]
        [error scenario-version]))

(define urdr.scenario.seed
  Value ->
    (urdr.scenario.seed-octets
      (urdr.scenario.octets Value scenario-seed-type)))

(define urdr.scenario.seed-octets
  [error E] -> [error E]
  [ok []] -> [error scenario-seed-empty]
  [ok Bs] ->
    (if (> (length Bs) (value *urdr.scenario.max-seed*))
        [error scenario-seed-too-large]
        [ok Bs]))

(define urdr.scenario.determinism
  Value ->
    (urdr.scenario.determinism-symbol
      (urdr.scenario.symbol Value scenario-determinism-type)))

(define urdr.scenario.determinism-symbol
  [error E] -> [error E]
  [ok Bs] ->
    (if (= (urdr.canonical.bytes-compare
             Bs (urdr.scenario.n.modeled))
           eq)
        [ok Bs]
        [error scenario-determinism-unsupported]))

\\ ---------------------------------------------------------------------
\\ budget.
\\ ---------------------------------------------------------------------

(define urdr.scenario.budget
  Value ->
    (urdr.scenario.budget-fields
      (urdr.scenario.record-fields
        Value (urdr.scenario.budget-keys) scenario-budget-type)))

(define urdr.scenario.budget-fields
  [error E] -> [error E]
  [ok [Events Runs Steps]] ->
    (urdr.scenario.budget-values
      (urdr.scenario.budget-count Events)
      (urdr.scenario.budget-count Runs)
      (urdr.scenario.budget-count Steps)))

(define urdr.scenario.budget-count
  Value ->
    (urdr.scenario.budget-positive
      (urdr.scenario.integer Value scenario-budget-type)))

(define urdr.scenario.budget-positive
  [error E] -> [error E]
  [ok N] ->
    (if (urdr.scenario.positive? N)
        [ok N]
        [error scenario-budget-range]))

(define urdr.scenario.budget-values
  [error E] Runs Steps -> [error E]
  Events [error E] Steps -> [error E]
  Events Runs [error E] -> [error E]
  [ok Events] [ok Runs] [ok Steps] ->
    [ok [budget Events Runs Steps]])

\\ ---------------------------------------------------------------------
\\ header-vocabulary: field symbols with finite software-integer value
\\ universes (ADR 0004 Decision 2).
\\ ---------------------------------------------------------------------

(define urdr.scenario.vocabulary
  Value ->
    (urdr.scenario.vocabulary-items
      (urdr.scenario.items
        Value scenario-header-vocabulary-type)))

(define urdr.scenario.vocabulary-items
  [error E] -> [error E]
  [ok []] -> [error scenario-header-vocabulary-empty]
  [ok Items] ->
    (urdr.scenario.vocabulary-required
      (urdr.scenario.vocabulary-loop Items none [])))

(define urdr.scenario.vocabulary-loop
  [] Previous Acc -> [ok (urdr.scenario.rev Acc)]
  [Item | Items] Previous Acc ->
    (urdr.scenario.vocabulary-step
      (urdr.scenario.header-field Item) Items Previous Acc)
  _ Previous Acc -> [error scenario-header-vocabulary-type])

(define urdr.scenario.vocabulary-step
  [error E] Items Previous Acc -> [error E]
  [ok [header-field Field Values]] Items Previous Acc ->
    (let Order
      (urdr.scenario.ascending
        Previous
        Field
        scenario-duplicate-header-field
        scenario-header-field-order)
      (if (= (hd Order) error)
          Order
          (urdr.scenario.vocabulary-loop
            Items Field [[header-field Field Values] | Acc]))))

(define urdr.scenario.header-field
  Item ->
    (urdr.scenario.header-field-fields
      (urdr.scenario.record-fields
        Item
        (urdr.scenario.header-keys)
        scenario-header-field-type)))

(define urdr.scenario.header-field-fields
  [error E] -> [error E]
  [ok [Field Values]] ->
    (urdr.scenario.header-field-name
      (urdr.scenario.symbol Field scenario-header-field-type)
      Values))

(define urdr.scenario.header-field-name
  [error E] Values -> [error E]
  [ok Field] Values ->
    (urdr.scenario.header-field-values
      Field (urdr.scenario.header-values Values)))

(define urdr.scenario.header-field-values
  Field [error E] -> [error E]
  Field [ok Values] -> [ok [header-field Field Values]])

(define urdr.scenario.header-values
  Value ->
    (urdr.scenario.header-values-items
      (urdr.scenario.items Value scenario-header-values-type)))

(define urdr.scenario.header-values-items
  [error E] -> [error E]
  [ok []] -> [error scenario-header-values-empty]
  [ok Items] -> (urdr.scenario.header-values-loop Items none []))

(define urdr.scenario.header-values-loop
  [] Previous Acc -> [ok (urdr.scenario.rev Acc)]
  [Item | Items] Previous Acc ->
    (urdr.scenario.header-values-step
      (urdr.scenario.integer Item scenario-header-value-type)
      Items
      Previous
      Acc)
  _ Previous Acc -> [error scenario-header-values-type])

(define urdr.scenario.header-values-step
  [error E] Items Previous Acc -> [error E]
  [ok N] Items Previous Acc ->
    (let Order
      (urdr.scenario.ascending-int
        Previous
        N
        scenario-duplicate-header-value
        scenario-header-values-order)
      (if (= (hd Order) error)
          Order
          (urdr.scenario.header-values-loop Items N [N | Acc]))))

(define urdr.scenario.vocabulary-required
  [error E] -> [error E]
  [ok Vocabulary] ->
    (if (urdr.scenario.has-fields?
          (urdr.scenario.required-header-fields) Vocabulary)
        [ok Vocabulary]
        [error scenario-header-vocabulary-missing]))

(define urdr.scenario.has-fields?
  [] Vocabulary -> true
  [Field | Fields] Vocabulary ->
    (and (cons? (urdr.scenario.field-values Field Vocabulary))
         (urdr.scenario.has-fields? Fields Vocabulary)))

\\ [] when the field is undeclared; the value universe is never empty.
(define urdr.scenario.field-values
  Field [] -> []
  Field [[header-field Name Values] | Rest] ->
    (if (= (urdr.canonical.bytes-compare Field Name) eq)
        Values
        (urdr.scenario.field-values Field Rest)))

(define urdr.scenario.value-declared?
  N [] -> false
  N [V | Vs] ->
    (if (= (urdr.int.raw.compare N V) 0)
        true
        (urdr.scenario.value-declared? N Vs)))

\\ ---------------------------------------------------------------------
\\ topology: addressed nodes and directed links.
\\ ---------------------------------------------------------------------

(define urdr.scenario.topology
  Value Vocabulary ->
    (urdr.scenario.topology-fields
      (urdr.scenario.record-fields
        Value (urdr.scenario.topology-keys) scenario-topology-type)
      Vocabulary))

(define urdr.scenario.topology-fields
  [error E] Vocabulary -> [error E]
  [ok [Links Nodes]] Vocabulary ->
    (urdr.scenario.topology-nodes-checked
      (urdr.scenario.nodes Nodes Vocabulary) Links))

(define urdr.scenario.topology-nodes-checked
  [error E] Links -> [error E]
  [ok Nodes] Links ->
    (urdr.scenario.topology-links-checked
      (urdr.scenario.links Links (urdr.scenario.node-ids Nodes))
      Nodes))

(define urdr.scenario.topology-links-checked
  [error E] Nodes -> [error E]
  [ok Links] Nodes -> [ok [topology Links Nodes]])

(define urdr.scenario.node-ids
  [] -> []
  [[node Address Id] | Nodes] ->
    [Id | (urdr.scenario.node-ids Nodes)])

(define urdr.scenario.nodes
  Value Vocabulary ->
    (urdr.scenario.nodes-items
      (urdr.scenario.items Value scenario-nodes-type) Vocabulary))

(define urdr.scenario.nodes-items
  [error E] Vocabulary -> [error E]
  [ok []] Vocabulary -> [error scenario-topology-empty]
  [ok Items] Vocabulary ->
    (urdr.scenario.nodes-loop Items Vocabulary none [] []))

(define urdr.scenario.nodes-loop
  [] Vocabulary Previous Addresses Acc ->
    [ok (urdr.scenario.rev Acc)]
  [Item | Items] Vocabulary Previous Addresses Acc ->
    (urdr.scenario.nodes-step
      (urdr.scenario.node Item Vocabulary)
      Items
      Vocabulary
      Previous
      Addresses
      Acc)
  _ Vocabulary Previous Addresses Acc -> [error scenario-nodes-type])

(define urdr.scenario.nodes-step
  [error E] Items Vocabulary Previous Addresses Acc -> [error E]
  [ok [node Address Id]] Items Vocabulary Previous Addresses Acc ->
    (let Order
      (urdr.scenario.ascending
        Previous Id scenario-duplicate-node scenario-node-order)
      (if (= (hd Order) error)
          Order
          (if (urdr.scenario.value-declared? Address Addresses)
              [error scenario-duplicate-address]
              (urdr.scenario.nodes-loop
                Items
                Vocabulary
                Id
                [Address | Addresses]
                [[node Address Id] | Acc])))))

(define urdr.scenario.node
  Item Vocabulary ->
    (urdr.scenario.node-fields
      (urdr.scenario.record-fields
        Item (urdr.scenario.node-keys) scenario-node-type)
      Vocabulary))

(define urdr.scenario.node-fields
  [error E] Vocabulary -> [error E]
  [ok [Address Id]] Vocabulary ->
    (urdr.scenario.node-address
      (urdr.scenario.integer
        Address scenario-node-address-type)
      Id
      Vocabulary))

(define urdr.scenario.node-address
  [error E] Id Vocabulary -> [error E]
  [ok Address] Id Vocabulary ->
    (if (urdr.scenario.negative? Address)
        [error scenario-node-address-range]
        (if (urdr.scenario.address-declared? Address Vocabulary)
            (urdr.scenario.node-id
              Address
              (urdr.scenario.symbol Id scenario-node-id-type))
            [error scenario-address-out-of-vocabulary])))

\\ A node address must belong to every required header field's declared
\\ value universe; otherwise the NetKAT fragment cannot name the node.
(define urdr.scenario.address-declared?
  Address Vocabulary ->
    (urdr.scenario.address-declared-loop
      Address (urdr.scenario.required-header-fields) Vocabulary))

(define urdr.scenario.address-declared-loop
  Address [] Vocabulary -> true
  Address [Field | Fields] Vocabulary ->
    (and (urdr.scenario.value-declared?
           Address (urdr.scenario.field-values Field Vocabulary))
         (urdr.scenario.address-declared-loop
           Address Fields Vocabulary)))

(define urdr.scenario.node-id
  Address [error E] -> [error E]
  Address [ok Id] -> [ok [node Address Id]])

(define urdr.scenario.links
  Value Nodes ->
    (urdr.scenario.links-items
      (urdr.scenario.items Value scenario-links-type) Nodes))

(define urdr.scenario.links-items
  [error E] Nodes -> [error E]
  [ok Items] Nodes ->
    (urdr.scenario.links-loop Items Nodes none none []))

(define urdr.scenario.links-loop
  [] Nodes PreviousFrom PreviousTo Acc ->
    [ok (urdr.scenario.rev Acc)]
  [Item | Items] Nodes PreviousFrom PreviousTo Acc ->
    (urdr.scenario.links-step
      (urdr.scenario.link Item Nodes)
      Items
      Nodes
      PreviousFrom
      PreviousTo
      Acc)
  _ Nodes PreviousFrom PreviousTo Acc -> [error scenario-links-type])

(define urdr.scenario.links-step
  [error E] Items Nodes PreviousFrom PreviousTo Acc -> [error E]
  [ok [link From To]] Items Nodes PreviousFrom PreviousTo Acc ->
    (let Order (urdr.scenario.link-order PreviousFrom PreviousTo From To)
      (if (= (hd Order) error)
          Order
          (urdr.scenario.links-loop
            Items Nodes From To [[link From To] | Acc]))))

(define urdr.scenario.link-order
  none PreviousTo From To -> [ok]
  PreviousFrom PreviousTo From To ->
    (let Order (urdr.canonical.bytes-compare PreviousFrom From)
      (if (= Order gt)
          [error scenario-link-order]
          (if (= Order lt)
              [ok]
              (urdr.scenario.ascending
                PreviousTo
                To
                scenario-duplicate-link
                scenario-link-order)))))

(define urdr.scenario.link
  Item Nodes ->
    (urdr.scenario.link-fields
      (urdr.scenario.record-fields
        Item (urdr.scenario.link-keys) scenario-link-type)
      Nodes))

(define urdr.scenario.link-fields
  [error E] Nodes -> [error E]
  [ok [From To]] Nodes ->
    (urdr.scenario.link-endpoints
      (urdr.scenario.symbol From scenario-link-endpoint-type)
      (urdr.scenario.symbol To scenario-link-endpoint-type)
      Nodes))

(define urdr.scenario.link-endpoints
  [error E] To Nodes -> [error E]
  From [error E] Nodes -> [error E]
  [ok From] [ok To] Nodes ->
    (if (and (urdr.scenario.member? From Nodes)
             (urdr.scenario.member? To Nodes))
        (if (= (urdr.canonical.bytes-compare From To) eq)
            [error scenario-self-link]
            [ok [link From To]])
        [error scenario-unknown-node]))

\\ ---------------------------------------------------------------------
\\ components: the modeled-component roster (ADR 0004 Decision 1).
\\ ---------------------------------------------------------------------

(define urdr.scenario.components
  Value Nodes ->
    (urdr.scenario.components-items
      (urdr.scenario.items Value scenario-components-type) Nodes))

(define urdr.scenario.components-items
  [error E] Nodes -> [error E]
  [ok Items] Nodes ->
    (urdr.scenario.components-loop Items Nodes none []))

(define urdr.scenario.components-loop
  [] Nodes Previous Acc -> [ok (urdr.scenario.rev Acc)]
  [Item | Items] Nodes Previous Acc ->
    (urdr.scenario.components-step
      (urdr.scenario.component Item Nodes) Items Nodes Previous Acc)
  _ Nodes Previous Acc -> [error scenario-components-type])

(define urdr.scenario.components-step
  [error E] Items Nodes Previous Acc -> [error E]
  [ok [component Id Kind Node]] Items Nodes Previous Acc ->
    (let Order
      (urdr.scenario.ascending
        Previous
        Id
        scenario-duplicate-component
        scenario-component-order)
      (if (= (hd Order) error)
          Order
          (urdr.scenario.components-loop
            Items Nodes Id [[component Id Kind Node] | Acc]))))

(define urdr.scenario.component
  Item Nodes ->
    (urdr.scenario.component-fields
      (urdr.scenario.record-fields
        Item (urdr.scenario.component-keys) scenario-component-type)
      Nodes))

(define urdr.scenario.component-fields
  [error E] Nodes -> [error E]
  [ok [Id Kind Node]] Nodes ->
    (urdr.scenario.component-parts
      (urdr.scenario.symbol Id scenario-component-id-type)
      (urdr.scenario.symbol Kind scenario-component-kind-type)
      (urdr.scenario.symbol Node scenario-component-node-type)
      Nodes))

(define urdr.scenario.component-parts
  [error E] Kind Node Nodes -> [error E]
  Id [error E] Node Nodes -> [error E]
  Id Kind [error E] Nodes -> [error E]
  [ok Id] [ok Kind] [ok Node] Nodes ->
    (if (not (urdr.scenario.member?
               Kind (urdr.scenario.component-kinds)))
        [error scenario-component-kind-unsupported]
        (if (urdr.scenario.member? Node Nodes)
            [ok [component Id Kind Node]]
            [error scenario-unknown-node])))

\\ ---------------------------------------------------------------------
\\ faults: named fault domains over declared nodes.
\\ ---------------------------------------------------------------------

(define urdr.scenario.faults
  Value Nodes ->
    (urdr.scenario.faults-items
      (urdr.scenario.items Value scenario-faults-type) Nodes))

(define urdr.scenario.faults-items
  [error E] Nodes -> [error E]
  [ok Items] Nodes ->
    (urdr.scenario.faults-loop Items Nodes none []))

(define urdr.scenario.faults-loop
  [] Nodes Previous Acc -> [ok (urdr.scenario.rev Acc)]
  [Item | Items] Nodes Previous Acc ->
    (urdr.scenario.faults-step
      (urdr.scenario.fault Item Nodes) Items Nodes Previous Acc)
  _ Nodes Previous Acc -> [error scenario-faults-type])

(define urdr.scenario.faults-step
  [error E] Items Nodes Previous Acc -> [error E]
  [ok [fault Id Kinds Members]] Items Nodes Previous Acc ->
    (let Order
      (urdr.scenario.ascending
        Previous Id scenario-duplicate-fault scenario-fault-order)
      (if (= (hd Order) error)
          Order
          (urdr.scenario.faults-loop
            Items Nodes Id [[fault Id Kinds Members] | Acc]))))

(define urdr.scenario.fault
  Item Nodes ->
    (urdr.scenario.fault-fields
      (urdr.scenario.record-fields
        Item (urdr.scenario.fault-keys) scenario-fault-type)
      Nodes))

(define urdr.scenario.fault-fields
  [error E] Nodes -> [error E]
  [ok [Id Kinds Members]] Nodes ->
    (urdr.scenario.fault-parts
      (urdr.scenario.symbol Id scenario-fault-id-type)
      (urdr.scenario.fault-kind-list Kinds)
      (urdr.scenario.fault-member-list Members Nodes)))

(define urdr.scenario.fault-parts
  [error E] Kinds Members -> [error E]
  Id [error E] Members -> [error E]
  Id Kinds [error E] -> [error E]
  [ok Id] [ok Kinds] [ok Members] -> [ok [fault Id Kinds Members]])

(define urdr.scenario.fault-kind-list
  Value ->
    (urdr.scenario.fault-kind-items
      (urdr.scenario.items Value scenario-fault-kinds-type)))

(define urdr.scenario.fault-kind-items
  [error E] -> [error E]
  [ok []] -> [error scenario-fault-kinds-empty]
  [ok Items] -> (urdr.scenario.fault-kind-loop Items none []))

(define urdr.scenario.fault-kind-loop
  [] Previous Acc -> [ok (urdr.scenario.rev Acc)]
  [Item | Items] Previous Acc ->
    (urdr.scenario.fault-kind-step
      (urdr.scenario.symbol Item scenario-fault-kinds-type)
      Items
      Previous
      Acc)
  _ Previous Acc -> [error scenario-fault-kinds-type])

(define urdr.scenario.fault-kind-step
  [error E] Items Previous Acc -> [error E]
  [ok Kind] Items Previous Acc ->
    (if (not (urdr.scenario.member?
               Kind (urdr.scenario.fault-kinds)))
        [error scenario-fault-kind-unsupported]
        (let Order
          (urdr.scenario.ascending
            Previous
            Kind
            scenario-duplicate-fault-kind
            scenario-fault-kinds-order)
          (if (= (hd Order) error)
              Order
              (urdr.scenario.fault-kind-loop
                Items Kind [Kind | Acc])))))

(define urdr.scenario.fault-member-list
  Value Nodes ->
    (urdr.scenario.fault-member-items
      (urdr.scenario.items Value scenario-fault-members-type)
      Nodes))

(define urdr.scenario.fault-member-items
  [error E] Nodes -> [error E]
  [ok []] Nodes -> [error scenario-fault-members-empty]
  [ok Items] Nodes ->
    (urdr.scenario.fault-member-loop Items Nodes none []))

(define urdr.scenario.fault-member-loop
  [] Nodes Previous Acc -> [ok (urdr.scenario.rev Acc)]
  [Item | Items] Nodes Previous Acc ->
    (urdr.scenario.fault-member-step
      (urdr.scenario.symbol Item scenario-fault-members-type)
      Items
      Nodes
      Previous
      Acc)
  _ Nodes Previous Acc -> [error scenario-fault-members-type])

(define urdr.scenario.fault-member-step
  [error E] Items Nodes Previous Acc -> [error E]
  [ok Member] Items Nodes Previous Acc ->
    (if (not (urdr.scenario.member? Member Nodes))
        [error scenario-unknown-node]
        (let Order
          (urdr.scenario.ascending
            Previous
            Member
            scenario-duplicate-fault-member
            scenario-fault-members-order)
          (if (= (hd Order) error)
              Order
              (urdr.scenario.fault-member-loop
                Items Nodes Member [Member | Acc])))))

\\ ---------------------------------------------------------------------
\\ observations: named points in logical time (SPEC.md 8, 18).
\\ ---------------------------------------------------------------------

(define urdr.scenario.observations
  Value ->
    (urdr.scenario.observations-items
      (urdr.scenario.items Value scenario-observations-type)))

(define urdr.scenario.observations-items
  [error E] -> [error E]
  [ok Items] -> (urdr.scenario.observations-loop Items none []))

(define urdr.scenario.observations-loop
  [] Previous Acc -> [ok (urdr.scenario.rev Acc)]
  [Item | Items] Previous Acc ->
    (urdr.scenario.observations-step
      (urdr.scenario.observation Item) Items Previous Acc)
  _ Previous Acc -> [error scenario-observations-type])

(define urdr.scenario.observations-step
  [error E] Items Previous Acc -> [error E]
  [ok [observation At Id]] Items Previous Acc ->
    (let Order
      (urdr.scenario.ascending
        Previous
        Id
        scenario-duplicate-observation
        scenario-observation-order)
      (if (= (hd Order) error)
          Order
          (urdr.scenario.observations-loop
            Items Id [[observation At Id] | Acc]))))

(define urdr.scenario.observation
  Item ->
    (urdr.scenario.observation-fields
      (urdr.scenario.record-fields
        Item
        (urdr.scenario.observation-keys)
        scenario-observation-type)))

(define urdr.scenario.observation-fields
  [error E] -> [error E]
  [ok [At Id]] ->
    (urdr.scenario.observation-at
      (urdr.scenario.integer At scenario-observation-at-type) Id))

(define urdr.scenario.observation-at
  [error E] Id -> [error E]
  [ok At] Id ->
    (if (urdr.scenario.negative? At)
        [error scenario-observation-time]
        (urdr.scenario.observation-id
          At
          (urdr.scenario.symbol Id scenario-observation-id-type))))

(define urdr.scenario.observation-id
  At [error E] -> [error E]
  At [ok Id] -> [ok [observation At Id]])

\\ ---------------------------------------------------------------------
\\ properties: representation only. The spec payload is an opaque
\\ canonical value; its interpretation belongs to shen/properties/.
\\ ---------------------------------------------------------------------

(define urdr.scenario.properties
  Value ->
    (urdr.scenario.properties-items
      (urdr.scenario.items Value scenario-properties-type)))

(define urdr.scenario.properties-items
  [error E] -> [error E]
  [ok Items] -> (urdr.scenario.properties-loop Items none []))

(define urdr.scenario.properties-loop
  [] Previous Acc -> [ok (urdr.scenario.rev Acc)]
  [Item | Items] Previous Acc ->
    (urdr.scenario.properties-step
      (urdr.scenario.property Item) Items Previous Acc)
  _ Previous Acc -> [error scenario-properties-type])

(define urdr.scenario.properties-step
  [error E] Items Previous Acc -> [error E]
  [ok [property Class Id Spec]] Items Previous Acc ->
    (let Order
      (urdr.scenario.ascending
        Previous
        Id
        scenario-duplicate-property
        scenario-property-order)
      (if (= (hd Order) error)
          Order
          (urdr.scenario.properties-loop
            Items Id [[property Class Id Spec] | Acc]))))

(define urdr.scenario.property
  Item ->
    (urdr.scenario.property-fields
      (urdr.scenario.record-fields
        Item
        (urdr.scenario.property-keys)
        scenario-property-type)))

(define urdr.scenario.property-fields
  [error E] -> [error E]
  [ok [Class Id Spec]] ->
    (urdr.scenario.property-class
      (urdr.scenario.symbol Class scenario-property-class-type)
      Id
      Spec))

(define urdr.scenario.property-class
  [error E] Id Spec -> [error E]
  [ok Class] Id Spec ->
    (if (urdr.scenario.member?
          Class (urdr.scenario.property-classes))
        (urdr.scenario.property-id
          Class
          (urdr.scenario.symbol Id scenario-property-id-type)
          Spec)
        [error scenario-property-class-unsupported]))

(define urdr.scenario.property-id
  Class [error E] Spec -> [error E]
  Class [ok Id] Spec -> [ok [property Class Id Spec]])

\\ ---------------------------------------------------------------------
\\ Top-level validation.
\\ ---------------------------------------------------------------------

(define urdr.scenario.validate
  Value ->
    (let Canonical (urdr.scenario.canonical Value)
      (if (= (hd Canonical) error)
          Canonical
          (urdr.scenario.validate-fields
            (urdr.scenario.record-fields
              Value
              (urdr.scenario.scenario-keys)
              scenario-type)))))

(define urdr.scenario.validate-fields
  [error E] -> [error E]
  [ok [Budget Components Determinism Faults Vocabulary
       Observations Properties Seed Topology Version]] ->
    (urdr.scenario.validate-version
      (urdr.scenario.version Version)
      [Budget Components Determinism Faults Vocabulary
       Observations Properties Seed Topology]))

(define urdr.scenario.validate-version
  [error E] Rest -> [error E]
  [ok Version]
  [Budget Components Determinism Faults Vocabulary
   Observations Properties Seed Topology] ->
    (urdr.scenario.validate-vocabulary
      (urdr.scenario.vocabulary Vocabulary)
      Version
      [Budget Components Determinism Faults
       Observations Properties Seed Topology]))

(define urdr.scenario.validate-vocabulary
  [error E] Version Rest -> [error E]
  [ok Vocabulary]
  Version
  [Budget Components Determinism Faults
   Observations Properties Seed Topology] ->
    (urdr.scenario.validate-topology
      (urdr.scenario.topology Topology Vocabulary)
      Version
      Vocabulary
      [Budget Components Determinism Faults
       Observations Properties Seed]))

(define urdr.scenario.validate-topology
  [error E] Version Vocabulary Rest -> [error E]
  [ok [topology Links Nodes]]
  Version
  Vocabulary
  [Budget Components Determinism Faults
   Observations Properties Seed] ->
    (urdr.scenario.assemble
      Version
      Vocabulary
      [topology Links Nodes]
      (urdr.scenario.budget Budget)
      (urdr.scenario.components
        Components (urdr.scenario.node-ids Nodes))
      (urdr.scenario.determinism Determinism)
      (urdr.scenario.faults Faults (urdr.scenario.node-ids Nodes))
      (urdr.scenario.observations Observations)
      (urdr.scenario.properties Properties)
      (urdr.scenario.seed Seed)))

(define urdr.scenario.assemble
  Version Vocabulary Topology
  [error E] Components Determinism Faults Observations Properties Seed
    -> [error E]
  Version Vocabulary Topology
  Budget [error E] Determinism Faults Observations Properties Seed
    -> [error E]
  Version Vocabulary Topology
  Budget Components [error E] Faults Observations Properties Seed
    -> [error E]
  Version Vocabulary Topology
  Budget Components Determinism [error E] Observations Properties Seed
    -> [error E]
  Version Vocabulary Topology
  Budget Components Determinism Faults [error E] Properties Seed
    -> [error E]
  Version Vocabulary Topology
  Budget Components Determinism Faults Observations [error E] Seed
    -> [error E]
  Version Vocabulary Topology
  Budget Components Determinism Faults Observations Properties [error E]
    -> [error E]
  Version Vocabulary Topology
  [ok Budget] [ok Components] [ok Determinism] [ok Faults]
  [ok Observations] [ok Properties] [ok Seed] ->
    [ok [scenario/v1
          Budget
          Components
          Determinism
          Faults
          Vocabulary
          Observations
          Properties
          Seed
          Topology]])

(define urdr.scenario.parse-frame
  Octets ->
    (urdr.scenario.parse-decoded
      (urdr.canonical.decode-frame Octets)))

(define urdr.scenario.parse-decoded
  [error E] -> [error E]
  [ok Value] -> (urdr.scenario.validate Value))

\\ ---------------------------------------------------------------------
\\ Accessors.
\\ ---------------------------------------------------------------------

(define urdr.scenario.valid?
  [scenario/v1 _ _ _ _ _ _ _ _ _] -> true
  _ -> false)

(define urdr.scenario.budget-of
  [scenario/v1 Budget _ _ _ _ _ _ _ _] -> Budget)

(define urdr.scenario.components-of
  [scenario/v1 _ Components _ _ _ _ _ _ _] -> Components)

(define urdr.scenario.determinism-of
  [scenario/v1 _ _ Determinism _ _ _ _ _ _] -> Determinism)

(define urdr.scenario.faults-of
  [scenario/v1 _ _ _ Faults _ _ _ _ _] -> Faults)

(define urdr.scenario.vocabulary-of
  [scenario/v1 _ _ _ _ Vocabulary _ _ _ _] -> Vocabulary)

(define urdr.scenario.observations-of
  [scenario/v1 _ _ _ _ _ Observations _ _ _] -> Observations)

(define urdr.scenario.properties-of
  [scenario/v1 _ _ _ _ _ _ Properties _ _] -> Properties)

(define urdr.scenario.seed-of
  [scenario/v1 _ _ _ _ _ _ _ Seed _] -> Seed)

(define urdr.scenario.topology-of
  [scenario/v1 _ _ _ _ _ _ _ _ Topology] -> Topology)

(define urdr.scenario.nodes-of
  [topology _ Nodes] -> Nodes)

(define urdr.scenario.links-of
  [topology Links _] -> Links)

\\ ---------------------------------------------------------------------
\\ Rendering back to canonical values. Validation is lossless, so
\\ encode(value(validate(decode(frame)))) reproduces the frame bytes.
\\ ---------------------------------------------------------------------

(define urdr.scenario.symbols-value
  [] -> []
  [Bs | Rest] ->
    [[symbol Bs] | (urdr.scenario.symbols-value Rest)])

(define urdr.scenario.integers-value
  [] -> []
  [N | Rest] -> [N | (urdr.scenario.integers-value Rest)])

(define urdr.scenario.budget-value
  [budget Events Runs Steps] ->
    [record
      [[(urdr.scenario.n.max-events) Events]
       [(urdr.scenario.n.max-runs) Runs]
       [(urdr.scenario.n.max-steps) Steps]]])

(define urdr.scenario.components-value
  [] -> []
  [[component Id Kind Node] | Rest] ->
    [[record
       [[(urdr.scenario.n.id) [symbol Id]]
        [(urdr.scenario.n.kind) [symbol Kind]]
        [(urdr.scenario.n.node) [symbol Node]]]]
     | (urdr.scenario.components-value Rest)])

(define urdr.scenario.faults-value
  [] -> []
  [[fault Id Kinds Members] | Rest] ->
    [[record
       [[(urdr.scenario.n.id) [symbol Id]]
        [(urdr.scenario.n.kinds)
         [list (urdr.scenario.symbols-value Kinds)]]
        [(urdr.scenario.n.members)
         [list (urdr.scenario.symbols-value Members)]]]]
     | (urdr.scenario.faults-value Rest)])

(define urdr.scenario.vocabulary-value
  [] -> []
  [[header-field Field Values] | Rest] ->
    [[record
       [[(urdr.scenario.n.field) [symbol Field]]
        [(urdr.scenario.n.values)
         [list (urdr.scenario.integers-value Values)]]]]
     | (urdr.scenario.vocabulary-value Rest)])

(define urdr.scenario.observations-value
  [] -> []
  [[observation At Id] | Rest] ->
    [[record
       [[(urdr.scenario.n.at) At]
        [(urdr.scenario.n.id) [symbol Id]]]]
     | (urdr.scenario.observations-value Rest)])

(define urdr.scenario.properties-value
  [] -> []
  [[property Class Id Spec] | Rest] ->
    [[record
       [[(urdr.scenario.n.class) [symbol Class]]
        [(urdr.scenario.n.id) [symbol Id]]
        [(urdr.scenario.n.spec) Spec]]]
     | (urdr.scenario.properties-value Rest)])

(define urdr.scenario.nodes-value
  [] -> []
  [[node Address Id] | Rest] ->
    [[record
       [[(urdr.scenario.n.address) Address]
        [(urdr.scenario.n.id) [symbol Id]]]]
     | (urdr.scenario.nodes-value Rest)])

(define urdr.scenario.links-value
  [] -> []
  [[link From To] | Rest] ->
    [[record
       [[(urdr.scenario.n.from) [symbol From]]
        [(urdr.scenario.n.to) [symbol To]]]]
     | (urdr.scenario.links-value Rest)])

(define urdr.scenario.topology-value
  [topology Links Nodes] ->
    [record
      [[(urdr.scenario.n.links)
        [list (urdr.scenario.links-value Links)]]
       [(urdr.scenario.n.nodes)
        [list (urdr.scenario.nodes-value Nodes)]]]])

(define urdr.scenario.value
  [scenario/v1 Budget Components Determinism Faults Vocabulary
               Observations Properties Seed Topology] ->
    [record
      [[(urdr.scenario.n.budget)
        (urdr.scenario.budget-value Budget)]
       [(urdr.scenario.n.components)
        [list (urdr.scenario.components-value Components)]]
       [(urdr.scenario.n.determinism) [symbol Determinism]]
       [(urdr.scenario.n.faults)
        [list (urdr.scenario.faults-value Faults)]]
       [(urdr.scenario.n.header-vocabulary)
        [list (urdr.scenario.vocabulary-value Vocabulary)]]
       [(urdr.scenario.n.observations)
        [list (urdr.scenario.observations-value Observations)]]
       [(urdr.scenario.n.properties)
        [list (urdr.scenario.properties-value Properties)]]
       [(urdr.scenario.n.seed) [bytes Seed]]
       [(urdr.scenario.n.topology)
        (urdr.scenario.topology-value Topology)]
       [(urdr.scenario.n.version)
        [symbol (urdr.scenario.n.scenario.v1)]]]])

(define urdr.scenario.encode-frame
  Scenario ->
    (if (urdr.scenario.valid? Scenario)
        (urdr.canonical.encode-frame (urdr.scenario.value Scenario))
        [error scenario-type]))
