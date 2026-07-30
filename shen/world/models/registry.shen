\* Model composition glue: a validated scenario becomes a component
registry (plan Wave C, ADR 0004 Decision 1; ADR 0007 D3).

Requires shen/protocol/canonical.shen, shen/world/integer.shen,
shen/world/netkat.shen, shen/world/component.shen,
shen/scenario/scenario.shen, and the three models in
shen/world/models/ to be loaded by the caller.

This module owns exactly one decision: how the scenario's declarations
become the initial state of each model. It adds no policy of its own.

  - The header vocabulary of the scenario becomes the NetKAT vocabulary
    the network model validates every packet and term against. The
    scenario already requires `src` and `dst` and already requires every
    node address to lie inside both universes, so the network model's
    topology predicate is expressible by construction.
  - The topology's directed links become the network model's link set,
    each carrying the addresses of its endpoints. The scenario rejects
    self-links, so no link contributes a src = dst test.
  - The declared fault domains become the fault model's domains with an
    empty active set. Nothing is active until a choice activates it.
  - The roster's component kinds are the scenario DSL's pinned set
    {fault, net, process, timer}; a kind outside it cannot reach here
    because the scenario rejects it first.

Kind dispatch is data (ADR 0007 D3): an association list of
[KIND BUILDER] pairs, ascending strictly by kind name, where BUILDER is
a Shen function from a roster component record and a build context to
[ok ENTRY] or a fail-closed error. Builders are functions and functions
are not canonical values, so the table is plain Shen host data: it is
validated at boot by from-scenario and is never serialized, encoded,
compared, or hashed. The built-in kinds fault, net, and timer populate
the default table; urdr.model.registry.kind-table extends it with the
process kind around a caller-supplied default handler and initial
state, and urdr.model.registry.table-put lets a driver extend it
further.

Per-component model binding (ADR 0007 D3): a roster entry may carry an
optional `model` symbol. The driver-facing model table is an
association list of [MODEL [HANDLER INIT-BUILDER]] pairs, ascending
strictly by model name and host data exactly like the kind table. A
bound entry runs HANDLER inside the crash-aware process wrapper of
models/fault.shen — a modeled process stays crash-routable no matter
which model it runs — and INIT-BUILDER receives the full roster
component record (id, kind, node, model) plus the scenario baseline
value, so per-component initial state is expressible. A roster entry
without a model binding defaults to its kind's builder, preserving
existing scenarios. Two process components may therefore run different
models, or the same model with different initial state.

Every registry entry carries the validated META record of ADR 0007 D3,
built from the roster's id and node bindings, so the reducer can hand
each component its identity under the event's `self` key. The roster's
node binding is therefore no longer dropped here.

The baseline policy is supplied by the caller, not read from the
scenario: in M1 it is either nk-id (an unrestricted fabric) or the term
the NetworkPolicy compiler produces (Wave C2). The network model composes
it last, after topology admission and after the active fault masks.

Registry entries ascend strictly by component id, which the scenario
already guarantees for its roster. *\

(define urdr.model.registry.n.field
  -> (urdr.canonical.string-bytes "field"))

(define urdr.model.registry.n.values
  -> (urdr.canonical.string-bytes "values"))

\\ ---------------------------------------------------------------
\\ Header vocabulary: scenario shape to NetKAT shape. Malformed input
\\ fails closed; nothing is silently dropped.
\\ ---------------------------------------------------------------

(define urdr.model.registry.vocab-entries
  [] Acc -> [ok (urdr.model.common.rev Acc)]
  [[header-field Field Values] | Rest] Acc ->
    (urdr.model.registry.vocab-entries
      Rest [[Field [list Values]] | Acc])
  _ Acc -> (urdr.model.common.error "registry-vocab-shape"))

(define urdr.model.registry.vocab-value
  Vocabulary ->
    (urdr.model.registry.vocab-record
      (urdr.model.registry.vocab-entries Vocabulary [])))

(define urdr.model.registry.vocab-record
  [error E] -> [error E]
  [ok Entries] -> [ok [record Entries]])

\\ ---------------------------------------------------------------
\\ Topology
\\ ---------------------------------------------------------------

(define urdr.model.registry.address-of
  Id [] -> none
  Id [[node Address NodeId] | Rest] ->
    (if (urdr.model.common.same? Id NodeId)
        Address
        (urdr.model.registry.address-of Id Rest))
  Id _ -> none)

(define urdr.model.registry.links
  [] Nodes Acc -> [ok (urdr.model.common.rev Acc)]
  [[link From To] | Rest] Nodes Acc ->
    (urdr.model.registry.links-step
      (urdr.model.registry.address-of From Nodes)
      (urdr.model.registry.address-of To Nodes)
      From
      To
      Rest
      Nodes
      Acc)
  _ Nodes Acc -> (urdr.model.common.error "registry-links-shape"))

(define urdr.model.registry.links-step
  none Dst From To Rest Nodes Acc ->
    (urdr.model.common.error "registry-unknown-node")
  Src none From To Rest Nodes Acc ->
    (urdr.model.common.error "registry-unknown-node")
  Src Dst From To Rest Nodes Acc ->
    (urdr.model.registry.links
      Rest Nodes [[link From To Src Dst] | Acc]))

\\ ---------------------------------------------------------------
\\ Initial model states
\\ ---------------------------------------------------------------

(define urdr.model.registry.net-state
  Scenario BaselineValue ->
    (urdr.model.registry.net-vocab
      (urdr.model.registry.vocab-value
        (urdr.scenario.vocabulary-of Scenario))
      Scenario
      BaselineValue))

(define urdr.model.registry.net-vocab
  [error E] Scenario BaselineValue -> [error E]
  [error E Detail] Scenario BaselineValue -> [error E Detail]
  [ok VocabValue] Scenario BaselineValue ->
    (urdr.model.registry.net-links
      (urdr.model.registry.links
        (urdr.scenario.links-of (urdr.scenario.topology-of Scenario))
        (urdr.scenario.nodes-of (urdr.scenario.topology-of Scenario))
        [])
      VocabValue
      BaselineValue))

(define urdr.model.registry.net-links
  [error E] VocabValue BaselineValue -> [error E]
  [error E Detail] VocabValue BaselineValue -> [error E Detail]
  [ok Links] VocabValue BaselineValue ->
    [ok (urdr.model.net.state-value
          VocabValue
          BaselineValue
          Links
          []
          [])])

\\ Malformed fault declarations fail closed with their own stable code
\\ rather than becoming an empty domain list.
(define urdr.model.registry.domains
  [] Acc -> [ok (urdr.model.common.rev Acc)]
  [[fault Id Kinds Members] | Rest] Acc ->
    (urdr.model.registry.domains
      Rest [[domain Id Kinds Members []] | Acc])
  _ Acc -> (urdr.model.common.error "registry-domains-shape"))

(define urdr.model.registry.fault-state
  Scenario ->
    (urdr.model.registry.fault-domains
      (urdr.model.registry.domains
        (urdr.scenario.faults-of Scenario) [])
      Scenario))

(define urdr.model.registry.fault-domains
  [error E] Scenario -> [error E]
  [ok Domains] Scenario ->
    [ok (urdr.model.fault.state-value
          Domains
          (urdr.scenario.nodes-of
            (urdr.scenario.topology-of Scenario)))])

\\ ---------------------------------------------------------------
\\ Association tables: host data, ascending strictly by name, validated
\\ at boot and never serialized.
\\ ---------------------------------------------------------------

(define urdr.model.registry.table-get
  Kind [] -> none
  Kind [[K V] | Rest] ->
    (if (urdr.model.common.same? Kind K)
        V
        (urdr.model.registry.table-get Kind Rest))
  Kind _ -> none)

\\ Insert or replace, keeping the strict ascension the boot check
\\ requires, so a driver extending the default table cannot produce a
\\ table whose lookup order depends on insertion order.
(define urdr.model.registry.table-put
  Name Value [] -> [[Name Value]]
  Name Value [[K V] | Rest] ->
    (let Order (urdr.canonical.bytes-compare Name K)
      (if (= Order lt)
          [[Name Value] [K V] | Rest]
          (if (= Order eq)
              [[Name Value] | Rest]
              [[K V] |
               (urdr.model.registry.table-put Name Value Rest)]))))

(define urdr.model.registry.table-check
  [] _ -> [ok]
  [[Name _] | Rest] Previous ->
    (if (and (urdr.component.name-valid? Name)
             (urdr.component.after? Previous Name))
        (urdr.model.registry.table-check Rest Name)
        (urdr.model.common.error "registry-table-shape"))
  _ _ -> (urdr.model.common.error "registry-table-shape"))

\\ ---------------------------------------------------------------
\\ Entry builders. The build context carries the shared initial model
\\ states and the scenario baseline; every net component of one scenario
\\ starts from the same declared topology, and every fault component
\\ from the same declared domains.
\\ ---------------------------------------------------------------

(define urdr.model.registry.meta-of
  [component Id Kind Node Model] ->
    (urdr.component.meta Model Node))

(define urdr.model.registry.net-entry
  [component Id Kind Node Model] [context NetState FaultState Baseline] ->
    [ok [component Id
          (/. S E (urdr.model.net.step S E))
          NetState
          (urdr.model.registry.meta-of
            [component Id Kind Node Model])]])

(define urdr.model.registry.timer-entry
  [component Id Kind Node Model] Context ->
    [ok [component Id
          (/. S E (urdr.model.timer.step S E))
          (urdr.model.timer.initial)
          (urdr.model.registry.meta-of
            [component Id Kind Node Model])]])

(define urdr.model.registry.fault-entry
  [component Id Kind Node Model] [context NetState FaultState Baseline] ->
    [ok [component Id
          (/. S E (urdr.model.fault.step S E))
          FaultState
          (urdr.model.registry.meta-of
            [component Id Kind Node Model])]])

\\ A process entry always runs inside the crash-aware wrapper, whether
\\ its handler came from the kind table's default or from a model
\\ binding, so crash/restart routing (ADR 0007 D4) reaches every process
\\ the same way.
(define urdr.model.registry.process-entry-with
  Handler Init [component Id Kind Node Model] ->
    [ok [component Id
          (/. S E (urdr.model.fault.process Handler Init S E))
          (urdr.model.fault.process-initial Init)
          (urdr.model.registry.meta-of
            [component Id Kind Node Model])]])

(define urdr.model.registry.default-kinds
  -> [[(urdr.scenario.n.fault)
       (/. C Ctx (urdr.model.registry.fault-entry C Ctx))]
      [(urdr.scenario.n.net)
       (/. C Ctx (urdr.model.registry.net-entry C Ctx))]
      [(urdr.scenario.n.timer)
       (/. C Ctx (urdr.model.registry.timer-entry C Ctx))]])

\\ The default table plus a process builder closing over the caller's
\\ default handler and initial state: the M1 shape every existing
\\ scenario expects.
(define urdr.model.registry.kind-table
  Handler Init ->
    (urdr.model.registry.table-put
      (urdr.scenario.n.process)
      (/. C Ctx
        (urdr.model.registry.process-entry-with Handler Init C))
      (urdr.model.registry.default-kinds)))

\\ ---------------------------------------------------------------
\\ Model binding. INIT-BUILDER sees the whole roster record and the
\\ baseline, so a model's initial state can depend on who is running it
\\ and where it was declared.
\\ ---------------------------------------------------------------

(define urdr.model.registry.model-entry
  [Handler InitBuilder]
  [component Id Kind Node Model]
  [context NetState FaultState Baseline] ->
    (urdr.model.registry.process-entry-with
      Handler
      (InitBuilder [component Id Kind Node Model] Baseline)
      [component Id Kind Node Model])
  _ Component Context ->
    (urdr.model.common.error "registry-table-shape"))

\\ ---------------------------------------------------------------
\\ Registry construction
\\ ---------------------------------------------------------------

(define urdr.model.registry.entry
  [component Id Kind Node none] KindTable ModelTable Context ->
    (urdr.model.registry.kind-entry
      (urdr.model.registry.table-get Kind KindTable)
      [component Id Kind Node none]
      Context)
  [component Id Kind Node Model] KindTable ModelTable Context ->
    (urdr.model.registry.bound-entry
      (urdr.model.registry.table-get Model ModelTable)
      [component Id Kind Node Model]
      Context))

(define urdr.model.registry.kind-entry
  none Component Context ->
    (urdr.model.common.error "registry-unknown-kind")
  Builder Component Context -> (Builder Component Context))

(define urdr.model.registry.bound-entry
  none Component Context ->
    (urdr.model.common.error "registry-unknown-model")
  Binding Component Context ->
    (urdr.model.registry.model-entry Binding Component Context))

(define urdr.model.registry.loop
  [] KindTable ModelTable Context Acc ->
    [ok (urdr.model.common.rev Acc)]
  [[component Id Kind Node Model] | Rest] KindTable ModelTable Context
  Acc ->
    (urdr.model.registry.step
      (urdr.model.registry.entry
        [component Id Kind Node Model] KindTable ModelTable Context)
      Rest
      KindTable
      ModelTable
      Context
      Acc)
  _ KindTable ModelTable Context Acc ->
    (urdr.model.common.error "registry-roster-shape"))

(define urdr.model.registry.step
  [error E] Rest KindTable ModelTable Context Acc -> [error E]
  [error E Detail] Rest KindTable ModelTable Context Acc ->
    [error E Detail]
  [ok Entry] Rest KindTable ModelTable Context Acc ->
    (urdr.model.registry.loop
      Rest KindTable ModelTable Context [Entry | Acc]))

(define urdr.model.registry.from-scenario
  Scenario BaselineValue KindTable ModelTable ->
    (urdr.model.registry.checked-kinds
      (urdr.model.registry.table-check KindTable none)
      Scenario
      BaselineValue
      KindTable
      ModelTable))

(define urdr.model.registry.checked-kinds
  [error E] Scenario BaselineValue KindTable ModelTable -> [error E]
  [ok] Scenario BaselineValue KindTable ModelTable ->
    (urdr.model.registry.checked-models
      (urdr.model.registry.table-check ModelTable none)
      Scenario
      BaselineValue
      KindTable
      ModelTable))

(define urdr.model.registry.checked-models
  [error E] Scenario BaselineValue KindTable ModelTable -> [error E]
  [ok] Scenario BaselineValue KindTable ModelTable ->
    (urdr.model.registry.with-net
      (urdr.model.registry.net-state Scenario BaselineValue)
      Scenario
      BaselineValue
      KindTable
      ModelTable))

(define urdr.model.registry.with-net
  [error E] Scenario BaselineValue KindTable ModelTable -> [error E]
  [error E Detail] Scenario BaselineValue KindTable ModelTable ->
    [error E Detail]
  [ok NetState] Scenario BaselineValue KindTable ModelTable ->
    (urdr.model.registry.with-fault
      (urdr.model.registry.fault-state Scenario)
      NetState
      Scenario
      BaselineValue
      KindTable
      ModelTable))

(define urdr.model.registry.with-fault
  [error E] NetState Scenario BaselineValue KindTable ModelTable ->
    [error E]
  [ok FaultState] NetState Scenario BaselineValue KindTable ModelTable ->
    (urdr.model.registry.loop
      (urdr.scenario.components-of Scenario)
      KindTable
      ModelTable
      [context NetState FaultState BaselineValue]
      []))
