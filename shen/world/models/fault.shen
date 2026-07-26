\* The fault model (plan Wave C, ADR 0004 Decisions 1 and 2).

Requires shen/protocol/canonical.shen, shen/world/integer.shen,
shen/world/netkat.shen, shen/world/component.shen,
shen/world/models/common.shen, shen/world/models/mask.shen, and
shen/world/models/net.shen to be loaded by the caller.

Faults are named states over the scenario's declared fault domains. A
reachability fault is not a second, private notion of connectivity: it is
a NetKAT predicate that the network model composes into its active
policy, so the symbolic view and the executed view are the same object.
Activating a partition emits a `mask` fact whose value is *literally* the
network model's mask input; the world kernel routes it, and nothing in
between can reinterpret it.

Kinds, per the scenario DSL's pinned set {crash, delay, drop, partition,
restart}:

  delay      latched, reachability fault. Emits a `mask` fact.
  drop       latched, reachability fault. Emits a `mask` fact.
  partition  latched, reachability fault. Emits a `mask` fact.
  crash      latched, targets process components. Emits a `crash` fact
             naming the member nodes; deactivating emits `restart`.
  restart    pulse, targets process components. Emits a `restart` fact and
             leaves the active set unchanged, so it can be pulsed again.

The three reachability kinds are named masks; what each one denotes as a
NetKAT predicate is defined once, in shen/world/models/mask.shen, and
this module never restates it. A latched kind refuses a second
activation (`fault-already-active`) so the active set cannot silently
absorb a repeat; a pulse kind has no deactivation.

State
-----

  [record [[domains [list DOMAIN ...]] [nodes [list NODE ...]]]]
  DOMAIN [record [[active  [list [symbol KIND] ...]]
                  [id      [symbol DOMAIN-ID]]
                  [kinds   [list [symbol KIND] ...]]
                  [members [list [symbol NODE-ID] ...]]]]
  NODE   [record [[address ADDRESS] [id [symbol NODE-ID]]]]

DOMAIN and NODE mirror the scenario DSL's own fault-domain and node
shapes so no translation layer can drift from the declaration.

Inputs
------

  [record [[domain [symbol DOMAIN-ID]] [kind [symbol KIND]]
           [operation [symbol activate | deactivate]]]]
  [record [[operation [symbol poll]]]]

Facts: mask, unmask, crash, restart, activated, deactivated.
Choices: purpose `fault-action`, one alternative per legal
(domain, kind, operation) triple. *\

\\ ---------------------------------------------------------------
\\ Names
\\ ---------------------------------------------------------------

(define urdr.model.fault.n.activate
  -> (urdr.canonical.string-bytes "activate"))

(define urdr.model.fault.n.activated
  -> (urdr.canonical.string-bytes "activated"))

(define urdr.model.fault.n.active
  -> (urdr.canonical.string-bytes "active"))

(define urdr.model.fault.n.address
  -> (urdr.canonical.string-bytes "address"))

(define urdr.model.fault.n.crash
  -> (urdr.canonical.string-bytes "crash"))

(define urdr.model.fault.n.deactivate
  -> (urdr.canonical.string-bytes "deactivate"))

(define urdr.model.fault.n.deactivated
  -> (urdr.canonical.string-bytes "deactivated"))

\\ The three reachability kinds keep one spelling, in mask.shen.
(define urdr.model.fault.n.delay
  -> (urdr.model.mask.n.delay))

(define urdr.model.fault.n.domain
  -> (urdr.canonical.string-bytes "domain"))

(define urdr.model.fault.n.domains
  -> (urdr.canonical.string-bytes "domains"))

(define urdr.model.fault.n.drop
  -> (urdr.model.mask.n.drop))

(define urdr.model.fault.n.id
  -> (urdr.canonical.string-bytes "id"))

(define urdr.model.fault.n.kind
  -> (urdr.canonical.string-bytes "kind"))

(define urdr.model.fault.n.kinds
  -> (urdr.canonical.string-bytes "kinds"))

(define urdr.model.fault.n.mask
  -> (urdr.canonical.string-bytes "mask"))

(define urdr.model.fault.n.members
  -> (urdr.canonical.string-bytes "members"))

(define urdr.model.fault.n.nodes
  -> (urdr.canonical.string-bytes "nodes"))

(define urdr.model.fault.n.operation
  -> (urdr.canonical.string-bytes "operation"))

(define urdr.model.fault.n.partition
  -> (urdr.model.mask.n.partition))

(define urdr.model.fault.n.poll
  -> (urdr.canonical.string-bytes "poll"))

(define urdr.model.fault.n.purpose
  -> (urdr.canonical.string-bytes "fault-action"))

(define urdr.model.fault.n.restart
  -> (urdr.canonical.string-bytes "restart"))

(define urdr.model.fault.n.unmask
  -> (urdr.canonical.string-bytes "unmask"))

\\ Process-wrapper names.
(define urdr.model.fault.n.absorbed
  -> (urdr.canonical.string-bytes "absorbed"))

(define urdr.model.fault.n.crashed
  -> (urdr.canonical.string-bytes "crashed"))

(define urdr.model.fault.n.inner
  -> (urdr.canonical.string-bytes "inner"))

(define urdr.model.fault.n.restarted
  -> (urdr.canonical.string-bytes "restarted"))

(define urdr.model.fault.n.running
  -> (urdr.canonical.string-bytes "running"))

(define urdr.model.fault.n.status
  -> (urdr.canonical.string-bytes "status"))

\\ ---------------------------------------------------------------
\\ State
\\ ---------------------------------------------------------------

(define urdr.model.fault.domain-value
  [domain Id Kinds Members Active] ->
    [record
      [[(urdr.model.fault.n.active)
        [list (urdr.model.common.symbols Active)]]
       [(urdr.model.fault.n.id) [symbol Id]]
       [(urdr.model.fault.n.kinds)
        [list (urdr.model.common.symbols Kinds)]]
       [(urdr.model.fault.n.members)
        [list (urdr.model.common.symbols Members)]]]])

(define urdr.model.fault.domains-value
  [] -> []
  [Domain | Rest] ->
    [(urdr.model.fault.domain-value Domain) |
     (urdr.model.fault.domains-value Rest)])

(define urdr.model.fault.node-value
  [node Address Id] ->
    [record
      [[(urdr.model.fault.n.address) Address]
       [(urdr.model.fault.n.id) [symbol Id]]]])

(define urdr.model.fault.nodes-value
  [] -> []
  [Node | Rest] ->
    [(urdr.model.fault.node-value Node) |
     (urdr.model.fault.nodes-value Rest)])

(define urdr.model.fault.state-value
  Domains Nodes ->
    [record
      [[(urdr.model.fault.n.domains)
        [list (urdr.model.fault.domains-value Domains)]]
       [(urdr.model.fault.n.nodes)
        [list (urdr.model.fault.nodes-value Nodes)]]]])

(define urdr.model.fault.domain-of
  Value ->
    (urdr.model.fault.domain-parts
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get Value (urdr.model.fault.n.id)))
      (urdr.model.fault.symbols-of
        (urdr.model.common.get Value (urdr.model.fault.n.kinds)))
      (urdr.model.fault.symbols-of
        (urdr.model.common.get Value (urdr.model.fault.n.members)))
      (urdr.model.fault.symbols-of
        (urdr.model.common.get Value (urdr.model.fault.n.active)))))

(define urdr.model.fault.symbols-of
  Value ->
    (urdr.model.fault.symbols-items (urdr.model.common.items Value)))

(define urdr.model.fault.symbols-items
  none -> none
  Items -> (urdr.model.fault.symbols-result
             (urdr.model.common.symbol-list Items [])))

(define urdr.model.fault.symbols-result
  none -> none
  [ok Bytes] -> Bytes)

(define urdr.model.fault.domain-parts
  none Kinds Members Active -> none
  Id none Members Active -> none
  Id Kinds none Active -> none
  Id Kinds Members none -> none
  Id Kinds Members Active -> [domain Id Kinds Members Active])

(define urdr.model.fault.node-of
  Value ->
    (urdr.model.fault.node-parts
      (urdr.model.common.integer
        (urdr.model.common.get Value (urdr.model.fault.n.address)))
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get Value (urdr.model.fault.n.id)))))

(define urdr.model.fault.node-parts
  none Id -> none
  Address none -> none
  Address Id -> [node Address Id])

(define urdr.model.fault.domains-loop
  [] Previous Acc -> [ok (urdr.model.common.rev Acc)]
  [Value | Rest] Previous Acc ->
    (urdr.model.fault.domains-step
      (urdr.model.fault.domain-of Value) Rest Previous Acc)
  _ Previous Acc -> (urdr.model.common.error "fault-state-shape"))

(define urdr.model.fault.domains-step
  none Rest Previous Acc -> (urdr.model.common.error "fault-domain-shape")
  [domain Id Kinds Members Active] Rest none Acc ->
    (urdr.model.fault.domains-loop
      Rest Id [[domain Id Kinds Members Active] | Acc])
  [domain Id Kinds Members Active] Rest Previous Acc ->
    (if (= (urdr.canonical.bytes-compare Previous Id) lt)
        (urdr.model.fault.domains-loop
          Rest Id [[domain Id Kinds Members Active] | Acc])
        (urdr.model.common.error "fault-domains-order")))

(define urdr.model.fault.nodes-loop
  [] Acc -> [ok (urdr.model.common.rev Acc)]
  [Value | Rest] Acc ->
    (urdr.model.fault.nodes-step (urdr.model.fault.node-of Value) Rest Acc)
  _ Acc -> (urdr.model.common.error "fault-state-shape"))

(define urdr.model.fault.nodes-step
  none Rest Acc -> (urdr.model.common.error "fault-node-shape")
  Node Rest Acc -> (urdr.model.fault.nodes-loop Rest [Node | Acc]))

(define urdr.model.fault.decode
  State ->
    (urdr.model.fault.decode-domains
      (urdr.model.fault.decode-items
        (urdr.model.common.items
          (urdr.model.common.get State (urdr.model.fault.n.domains))))
      State))

(define urdr.model.fault.decode-items
  none -> (urdr.model.common.error "fault-state-shape")
  Items -> (urdr.model.fault.domains-loop Items none []))

(define urdr.model.fault.decode-domains
  [error E] State -> [error E]
  [error E Detail] State -> [error E Detail]
  [ok Domains] State ->
    (urdr.model.fault.decode-nodes
      (urdr.model.fault.decode-nodes-items
        (urdr.model.common.items
          (urdr.model.common.get State (urdr.model.fault.n.nodes))))
      Domains))

(define urdr.model.fault.decode-nodes-items
  none -> (urdr.model.common.error "fault-state-shape")
  Items -> (urdr.model.fault.nodes-loop Items []))

(define urdr.model.fault.decode-nodes
  [error E] Domains -> [error E]
  [error E Detail] Domains -> [error E Detail]
  [ok Nodes] Domains -> [ok [faults Domains Nodes]])

\\ ---------------------------------------------------------------
\\ Mask terms
\\ ---------------------------------------------------------------

(define urdr.model.fault.address-of
  Id [] -> none
  Id [[node Address NodeId] | Rest] ->
    (if (urdr.model.common.same? Id NodeId)
        Address
        (urdr.model.fault.address-of Id Rest))
  Id _ -> none)

(define urdr.model.fault.addresses
  [] Nodes Acc -> [ok (urdr.model.common.rev Acc)]
  [Id | Rest] Nodes Acc ->
    (urdr.model.fault.addresses-step
      (urdr.model.fault.address-of Id Nodes) Rest Nodes Acc)
  _ Nodes Acc -> (urdr.model.common.error "fault-members-shape"))

(define urdr.model.fault.addresses-step
  none Rest Nodes Acc -> (urdr.model.common.error "fault-unknown-node")
  Address Rest Nodes Acc ->
    (urdr.model.fault.addresses Rest Nodes [Address | Acc]))

\\ A mask is named for the (domain, kind) pair it realizes, so one domain
\\ may hold several simultaneously active reachability faults without two
\\ masks colliding in the network model's ascending mask list.
(define urdr.model.fault.mask-id
  Id Kind ->
    (urdr.model.common.append Id [45 | Kind]))

\\ ---------------------------------------------------------------
\\ Kind classification
\\ ---------------------------------------------------------------

(define urdr.model.fault.pulse?
  Kind -> (urdr.model.common.same? Kind (urdr.model.fault.n.restart)))

(define urdr.model.fault.process?
  Kind ->
    (or (urdr.model.common.same? Kind (urdr.model.fault.n.crash))
        (urdr.model.common.same? Kind (urdr.model.fault.n.restart))))

\\ ---------------------------------------------------------------
\\ Choices
\\ ---------------------------------------------------------------

(define urdr.model.fault.alternative
  Id Kind Operation ->
    [record
      [[(urdr.model.fault.n.domain) [symbol Id]]
       [(urdr.model.fault.n.kind) [symbol Kind]]
       [(urdr.model.fault.n.operation) [symbol Operation]]]])

(define urdr.model.fault.kind-alternatives
  Id [] Active Acc -> Acc
  Id [Kind | Rest] Active Acc ->
    (urdr.model.fault.kind-alternatives
      Id
      Rest
      Active
      [(urdr.model.fault.alternative
         Id Kind (urdr.model.fault.operation-for Kind Active)) | Acc])
  Id _ Active Acc -> Acc)

(define urdr.model.fault.operation-for
  Kind Active ->
    (if (urdr.model.fault.pulse? Kind)
        (urdr.model.fault.n.activate)
        (if (urdr.model.common.member? Kind Active)
            (urdr.model.fault.n.deactivate)
            (urdr.model.fault.n.activate))))

(define urdr.model.fault.domain-alternatives
  [] Acc -> Acc
  [[domain Id Kinds Members Active] | Rest] Acc ->
    (urdr.model.fault.domain-alternatives
      Rest
      (urdr.model.fault.kind-alternatives Id Kinds Active Acc))
  _ Acc -> Acc)

(define urdr.model.fault.choices
  Domains ->
    (urdr.model.common.choice
      (urdr.model.fault.n.purpose)
      (urdr.model.fault.domain-alternatives Domains [])))

(define urdr.model.fault.result
  Domains Nodes Facts ->
    [step
      (urdr.model.fault.state-value Domains Nodes)
      Facts
      (urdr.model.fault.choices Domains)])

\\ ---------------------------------------------------------------
\\ Activation
\\ ---------------------------------------------------------------

(define urdr.model.fault.find
  Id [] -> none
  Id [[domain DomainId Kinds Members Active] | Rest] ->
    (if (urdr.model.common.same? Id DomainId)
        [domain DomainId Kinds Members Active]
        (urdr.model.fault.find Id Rest))
  Id _ -> none)

(define urdr.model.fault.replace
  [domain Id Kinds Members Active] [] -> []
  [domain Id Kinds Members Active] [[domain Id2 K2 M2 A2] | Rest] ->
    (if (urdr.model.common.same? Id Id2)
        [[domain Id Kinds Members Active] | Rest]
        [[domain Id2 K2 M2 A2] |
         (urdr.model.fault.replace
           [domain Id Kinds Members Active] Rest)])
  Domain _ -> [])

(define urdr.model.fault.add-kind
  Kind [] -> [Kind]
  Kind [K | Ks] ->
    (let Order (urdr.canonical.bytes-compare Kind K)
      (if (= Order lt)
          [Kind K | Ks]
          (if (= Order eq)
              [K | Ks]
              [K | (urdr.model.fault.add-kind Kind Ks)]))))

(define urdr.model.fault.drop-kind
  Kind [] -> []
  Kind [K | Ks] ->
    (if (urdr.model.common.same? Kind K)
        Ks
        [K | (urdr.model.fault.drop-kind Kind Ks)]))

(define urdr.model.fault.activate
  [domain Id Kinds Members Active] Domains Nodes Kind ->
    (if (not (urdr.model.common.member? Kind Kinds))
        (urdr.model.common.error "fault-kind-undeclared")
        (if (and (not (urdr.model.fault.pulse? Kind))
                 (urdr.model.common.member? Kind Active))
            (urdr.model.common.error "fault-already-active")
            (urdr.model.fault.activate-facts
              [domain Id Kinds Members Active] Domains Nodes Kind))))

(define urdr.model.fault.activate-facts
  [domain Id Kinds Members Active] Domains Nodes Kind ->
    (if (urdr.model.fault.process? Kind)
        (urdr.model.fault.activate-process
          [domain Id Kinds Members Active] Domains Nodes Kind)
        (urdr.model.fault.activate-mask
          (urdr.model.fault.addresses Members Nodes [])
          [domain Id Kinds Members Active]
          Domains
          Nodes
          Kind)))

(define urdr.model.fault.members-value
  Members ->
    [record
      [[(urdr.model.fault.n.members)
        [list (urdr.model.common.symbols Members)]]]])

\\ crash latches; restart is a pulse and leaves the active set alone.
(define urdr.model.fault.activate-process
  [domain Id Kinds Members Active] Domains Nodes Kind ->
    (let Name
         (if (urdr.model.fault.pulse? Kind)
             (urdr.model.fault.n.restart)
             (urdr.model.fault.n.crash))
         Next
         (if (urdr.model.fault.pulse? Kind)
             Active
             (urdr.model.fault.add-kind Kind Active))
      (urdr.model.fault.result
        (urdr.model.fault.replace
          [domain Id Kinds Members Next] Domains)
        Nodes
        [[fact Name (urdr.model.fault.members-value Members)]
         [fact (urdr.model.fault.n.activated)
           (urdr.model.fault.alternative
             Id Kind (urdr.model.fault.n.activate))]])))

\\ The `mask` fact's value is literally the network model's mask input, so
\\ the world kernel routes it without translating it, and the term it
\\ denotes is derived by urdr.model.mask.term on both sides.
(define urdr.model.fault.activate-mask
  [error E] Domain Domains Nodes Kind -> [error E]
  [error E Detail] Domain Domains Nodes Kind -> [error E Detail]
  [ok Addresses] [domain Id Kinds Members Active] Domains Nodes Kind ->
    (urdr.model.fault.activate-term
      (urdr.model.mask.term Kind Addresses)
      [domain Id Kinds Members Active]
      Domains
      Nodes
      Kind
      Addresses))

(define urdr.model.fault.activate-term
  [error E] Domain Domains Nodes Kind Addresses -> [error E]
  [error E Detail] Domain Domains Nodes Kind Addresses -> [error E Detail]
  [ok Term] [domain Id Kinds Members Active] Domains Nodes Kind
  Addresses ->
    (urdr.model.fault.result
      (urdr.model.fault.replace
        [domain Id Kinds Members
          (urdr.model.fault.add-kind Kind Active)]
        Domains)
      Nodes
      [[fact (urdr.model.fault.n.mask)
         (urdr.model.net.mask-input
           (urdr.model.fault.mask-id Id Kind) Kind Addresses)]
       [fact (urdr.model.fault.n.activated)
         (urdr.model.fault.alternative
           Id Kind (urdr.model.fault.n.activate))]]))

(define urdr.model.fault.deactivate
  [domain Id Kinds Members Active] Domains Nodes Kind ->
    (if (not (urdr.model.common.member? Kind Kinds))
        (urdr.model.common.error "fault-kind-undeclared")
        (if (urdr.model.fault.pulse? Kind)
            (urdr.model.common.error "fault-kind-pulse")
            (if (not (urdr.model.common.member? Kind Active))
                (urdr.model.common.error "fault-not-active")
                (urdr.model.fault.deactivate-facts
                  [domain Id Kinds Members Active] Domains Nodes Kind)))))

(define urdr.model.fault.deactivate-facts
  [domain Id Kinds Members Active] Domains Nodes Kind ->
    (let Next
         [domain Id Kinds Members
           (urdr.model.fault.drop-kind Kind Active)]
         Release
         (if (urdr.model.fault.process? Kind)
             [fact (urdr.model.fault.n.restart)
               (urdr.model.fault.members-value Members)]
             [fact (urdr.model.fault.n.unmask)
               (urdr.model.net.unmask-input
                 (urdr.model.fault.mask-id Id Kind))])
      (urdr.model.fault.result
        (urdr.model.fault.replace Next Domains)
        Nodes
        [Release
         [fact (urdr.model.fault.n.deactivated)
           (urdr.model.fault.alternative
             Id Kind (urdr.model.fault.n.deactivate))]])))

\\ ---------------------------------------------------------------
\\ The component-step entry point
\\ ---------------------------------------------------------------

(define urdr.model.fault.step
  State Event ->
    (urdr.model.fault.step-decoded
      (urdr.model.fault.decode State)
      (urdr.model.common.event-input Event)))

(define urdr.model.fault.step-decoded
  [error E] Input -> [error E]
  [error E Detail] Input -> [error E Detail]
  [ok Decoded] none -> (urdr.model.common.error "fault-input-shape")
  [ok [faults Domains Nodes]] Input ->
    (urdr.model.fault.dispatch
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get Input (urdr.model.fault.n.operation)))
      Domains
      Nodes
      Input))

(define urdr.model.fault.dispatch
  none Domains Nodes Input ->
    (urdr.model.common.error "fault-input-shape")
  Operation Domains Nodes Input ->
    (if (urdr.model.common.same? Operation (urdr.model.fault.n.poll))
        (urdr.model.fault.result Domains Nodes [])
        (urdr.model.fault.targeted
          Operation
          (urdr.model.common.symbol-bytes
            (urdr.model.common.get Input (urdr.model.fault.n.domain)))
          (urdr.model.common.symbol-bytes
            (urdr.model.common.get Input (urdr.model.fault.n.kind)))
          Domains
          Nodes)))

(define urdr.model.fault.targeted
  Operation none Kind Domains Nodes ->
    (urdr.model.common.error "fault-input-shape")
  Operation Id none Domains Nodes ->
    (urdr.model.common.error "fault-input-shape")
  Operation Id Kind Domains Nodes ->
    (urdr.model.fault.found
      (urdr.model.fault.find Id Domains) Operation Kind Domains Nodes))

(define urdr.model.fault.found
  none Operation Kind Domains Nodes ->
    (urdr.model.common.error "fault-unknown-domain")
  Domain Operation Kind Domains Nodes ->
    (if (urdr.model.common.same?
          Operation (urdr.model.fault.n.activate))
        (urdr.model.fault.activate Domain Domains Nodes Kind)
        (if (urdr.model.common.same?
              Operation (urdr.model.fault.n.deactivate))
            (urdr.model.fault.deactivate Domain Domains Nodes Kind)
            (urdr.model.common.error "fault-unknown-operation"))))

\\ ---------------------------------------------------------------
\\ Input construction
\\ ---------------------------------------------------------------

(define urdr.model.fault.input
  Id Kind Operation ->
    (urdr.model.fault.alternative Id Kind Operation))

(define urdr.model.fault.poll-input
  -> [record
       [[(urdr.model.fault.n.operation)
         [symbol (urdr.model.fault.n.poll)]]]])

\\ ---------------------------------------------------------------
\\ Crash-aware process wrapper.
\\
\\ Crash and restart faults target process components, and a component
\\ cannot address another component, so the world kernel routes the fault
\\ model's `crash` / `restart` facts to the named process as ordinary
\\ component inputs. This wrapper is what receives them. A crashed process
\\ does not silently swallow its inputs: each one produces a canonical
\\ `crashed` fact and increments a visible absorbed count, so absorption
\\ is evidence in the fact log rather than an absence of it.
\\ ---------------------------------------------------------------

(define urdr.model.fault.process-state
  Absorbed Inner Status ->
    [record
      [[(urdr.model.fault.n.absorbed) Absorbed]
       [(urdr.model.fault.n.inner) Inner]
       [(urdr.model.fault.n.status) [symbol Status]]]])

(define urdr.model.fault.process-initial
  Inner ->
    (urdr.model.fault.process-state
      (urdr.int.zero) Inner (urdr.model.fault.n.running)))

(define urdr.model.fault.crash-input
  -> [record
       [[(urdr.model.fault.n.kind)
         [symbol (urdr.model.fault.n.crash)]]]])

(define urdr.model.fault.restart-input
  -> [record
       [[(urdr.model.fault.n.kind)
         [symbol (urdr.model.fault.n.restart)]]]])

(define urdr.model.fault.crashed-value
  Absorbed ->
    [record
      [[(urdr.model.fault.n.absorbed) Absorbed]
       [(urdr.model.fault.n.status)
        [symbol (urdr.model.fault.n.crashed)]]]])

(define urdr.model.fault.process
  Handler Init State Event ->
    (urdr.model.fault.process-decoded
      (urdr.model.common.integer
        (urdr.model.common.get State (urdr.model.fault.n.absorbed)))
      (urdr.model.common.get State (urdr.model.fault.n.inner))
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get State (urdr.model.fault.n.status)))
      [wrap Handler Init Event]))

(define urdr.model.fault.process-decoded
  none Inner Status Context ->
    (urdr.model.common.error "process-state-shape")
  Absorbed none Status Context ->
    (urdr.model.common.error "process-state-shape")
  Absorbed Inner none Context ->
    (urdr.model.common.error "process-state-shape")
  Absorbed Inner Status [wrap Handler Init Event] ->
    (urdr.model.fault.process-control
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get
          (urdr.model.common.event-input Event)
          (urdr.model.fault.n.kind)))
      Absorbed
      Inner
      Status
      [wrap Handler Init Event]))

(define urdr.model.fault.process-control
  Kind Absorbed Inner Status [wrap Handler Init Event] ->
    (if (urdr.model.fault.control? Kind (urdr.model.fault.n.crash))
        [step
          (urdr.model.fault.process-state
            (urdr.int.zero) Inner (urdr.model.fault.n.crashed))
          [[fact (urdr.model.fault.n.crashed)
             (urdr.model.fault.crashed-value (urdr.int.zero))]]
          []]
        (if (urdr.model.fault.control? Kind (urdr.model.fault.n.restart))
            [step
              (urdr.model.fault.process-state
                (urdr.int.zero) Init (urdr.model.fault.n.running))
              [[fact (urdr.model.fault.n.restarted)
                 [record
                   [[(urdr.model.fault.n.status)
                     [symbol (urdr.model.fault.n.running)]]]]]]
              []]
            (urdr.model.fault.process-run
              Absorbed Inner Status [wrap Handler Init Event]))))

(define urdr.model.fault.control?
  none Name -> false
  Kind Name -> (urdr.model.common.same? Kind Name))

(define urdr.model.fault.process-run
  Absorbed Inner Status [wrap Handler Init Event] ->
    (if (urdr.model.common.same? Status (urdr.model.fault.n.crashed))
        (urdr.model.fault.absorb Absorbed Inner)
        (if (urdr.model.common.same?
              Status (urdr.model.fault.n.running))
            (urdr.model.fault.process-inner
              (Handler Inner Event) Absorbed)
            (urdr.model.common.error "process-state-shape"))))

(define urdr.model.fault.absorb
  Absorbed Inner ->
    (let Next (hd (tl (urdr.int.add Absorbed (urdr.int.one))))
      [step
        (urdr.model.fault.process-state
          Next Inner (urdr.model.fault.n.crashed))
        [[fact (urdr.model.fault.n.crashed)
           (urdr.model.fault.crashed-value Next)]]
        []]))

(define urdr.model.fault.process-inner
  [step Inner Facts Choices] Absorbed ->
    [step
      (urdr.model.fault.process-state
        Absorbed Inner (urdr.model.fault.n.running))
      Facts
      Choices]
  [error Code] Absorbed -> [error Code]
  [error Code Detail] Absorbed -> [error Code Detail]
  _ Absorbed -> (urdr.model.common.error "process-inner-shape"))
