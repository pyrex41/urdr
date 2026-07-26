\* Model composition glue: a validated scenario becomes a component
registry (plan Wave C, ADR 0004 Decision 1).

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
\\ Header vocabulary: scenario shape to NetKAT shape
\\ ---------------------------------------------------------------

(define urdr.model.registry.vocab-entries
  [] -> []
  [[header-field Field Values] | Rest] ->
    [[Field [list Values]] |
     (urdr.model.registry.vocab-entries Rest)]
  _ -> [])

(define urdr.model.registry.vocab-value
  Vocabulary ->
    [record (urdr.model.registry.vocab-entries Vocabulary)])

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
    (urdr.model.registry.net-links
      (urdr.model.registry.links
        (urdr.scenario.links-of (urdr.scenario.topology-of Scenario))
        (urdr.scenario.nodes-of (urdr.scenario.topology-of Scenario))
        [])
      Scenario
      BaselineValue))

(define urdr.model.registry.net-links
  [error E] Scenario BaselineValue -> [error E]
  [error E Detail] Scenario BaselineValue -> [error E Detail]
  [ok Links] Scenario BaselineValue ->
    [ok (urdr.model.net.state-value
          (urdr.model.registry.vocab-value
            (urdr.scenario.vocabulary-of Scenario))
          BaselineValue
          Links
          []
          [])])

(define urdr.model.registry.domains
  [] -> []
  [[fault Id Kinds Members] | Rest] ->
    [[domain Id Kinds Members []] |
     (urdr.model.registry.domains Rest)]
  _ -> [])

(define urdr.model.registry.fault-state
  Scenario ->
    (urdr.model.fault.state-value
      (urdr.model.registry.domains (urdr.scenario.faults-of Scenario))
      (urdr.scenario.nodes-of (urdr.scenario.topology-of Scenario))))

\\ ---------------------------------------------------------------
\\ Registry construction
\\ ---------------------------------------------------------------

(define urdr.model.registry.entry
  Id Kind NetState FaultState Handler Init ->
    (if (urdr.model.common.same? Kind (urdr.scenario.n.net))
        [ok [component Id (/. S E (urdr.model.net.step S E)) NetState]]
        (if (urdr.model.common.same? Kind (urdr.scenario.n.timer))
            [ok [component Id
                  (/. S E (urdr.model.timer.step S E))
                  (urdr.model.timer.initial)]]
            (if (urdr.model.common.same? Kind (urdr.scenario.n.fault))
                [ok [component Id
                      (/. S E (urdr.model.fault.step S E))
                      FaultState]]
                (if (urdr.model.common.same?
                      Kind (urdr.scenario.n.process))
                    [ok [component Id
                          (/. S E
                            (urdr.model.fault.process Handler Init S E))
                          (urdr.model.fault.process-initial Init)]]
                    (urdr.model.common.error
                      "registry-unknown-kind"))))))

(define urdr.model.registry.loop
  [] NetState FaultState Handler Init Acc ->
    [ok (urdr.model.common.rev Acc)]
  [[component Id Kind Node] | Rest] NetState FaultState Handler Init Acc ->
    (urdr.model.registry.step
      (urdr.model.registry.entry
        Id Kind NetState FaultState Handler Init)
      Rest
      NetState
      FaultState
      Handler
      Init
      Acc)
  _ NetState FaultState Handler Init Acc ->
    (urdr.model.common.error "registry-roster-shape"))

(define urdr.model.registry.step
  [error E] Rest NetState FaultState Handler Init Acc -> [error E]
  [error E Detail] Rest NetState FaultState Handler Init Acc ->
    [error E Detail]
  [ok Entry] Rest NetState FaultState Handler Init Acc ->
    (urdr.model.registry.loop
      Rest NetState FaultState Handler Init [Entry | Acc]))

(define urdr.model.registry.from-scenario
  Scenario BaselineValue Handler Init ->
    (urdr.model.registry.with-net
      (urdr.model.registry.net-state Scenario BaselineValue)
      Scenario
      Handler
      Init))

(define urdr.model.registry.with-net
  [error E] Scenario Handler Init -> [error E]
  [error E Detail] Scenario Handler Init -> [error E Detail]
  [ok NetState] Scenario Handler Init ->
    (urdr.model.registry.loop
      (urdr.scenario.components-of Scenario)
      NetState
      (urdr.model.registry.fault-state Scenario)
      Handler
      Init
      []))
