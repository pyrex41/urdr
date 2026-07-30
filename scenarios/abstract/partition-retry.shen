\* M1.5 reference scenario: partition-retry.

Three modeled processes (client, relay, server), a modeled network
process, and a partition-fault process over the declared topology
a->b, a->c, b->c, with a retry protocol and a schedule-dependent
partition that can violate a liveness deadline.

This module constructs the canonical scenario VALUE only — the
declaration. The reference models the roster binds (pr-client,
pr-fault, pr-net, pr-relay, pr-server) live with the driver in
shen/run/models/partition-retry.shen; the production path from this
declaration to a certificate is urdr.run.execute.

Roster note (ADR 0007 D3): every component is a `process` bound to a
reference model. fault-0 and net-0 do not bind the built-in fault/net
kinds because the built-in models' menus are not yet resolvable under
the driver's selection-delivery rule (the deferral run.shen records:
the fault model republishes its menu every step, and net/timer
alternatives need deliver-input/fire-input wrapping). The declared
fault domain (split: partition of {c}) still names the partition the
pr-fault model injects.

Routes (ADR 0007 D4) carry the whole protocol; nothing is
hand-scheduled:

  client  --request-->  net-0            (send, and each retry)
  fault-0 --partition-> net-0            (the injected mask)
  net-0   --deliver-->  server           (direct path a->c)
  net-0   --hop------>  relay            (relayed path a->b)
  relay   --deliver-->  server           (               b->c)
  server  --reply---->  net-0            (the answer)
  net-0   --respond-->  client           (answer crosses back)
  net-0   --timeout-->  client           (withheld crossing surfaces
                                          as the sender's timer)

Requires: shen/protocol/canonical.shen, shen/world/integer.shen,
shen/scenario/scenario.shen (loaded by the caller). *\

(define urdr.scenario.abstract.k
  Name -> (urdr.canonical.string-bytes Name))

(define urdr.scenario.abstract.s
  Name -> [symbol (urdr.scenario.abstract.k Name)])

(define urdr.scenario.abstract.big
  N -> (urdr.int.raw.from-small N))

(define urdr.scenario.abstract.node
  Address Id ->
    [record
      [[(urdr.scenario.abstract.k "address")
        (urdr.scenario.abstract.big Address)]
       [(urdr.scenario.abstract.k "id")
        (urdr.scenario.abstract.s Id)]]])

(define urdr.scenario.abstract.link
  From To ->
    [record
      [[(urdr.scenario.abstract.k "from") (urdr.scenario.abstract.s From)]
       [(urdr.scenario.abstract.k "to") (urdr.scenario.abstract.s To)]]])

\\ Every roster entry binds a model (keys ascend id < kind < model <
\\ node): the driver refuses an unbound process, and the whole roster
\\ is process-modeled here (see the roster note above).
(define urdr.scenario.abstract.component
  Id Kind Model Node ->
    [record
      [[(urdr.scenario.abstract.k "id") (urdr.scenario.abstract.s Id)]
       [(urdr.scenario.abstract.k "kind") (urdr.scenario.abstract.s Kind)]
       [(urdr.scenario.abstract.k "model")
        (urdr.scenario.abstract.s Model)]
       [(urdr.scenario.abstract.k "node")
        (urdr.scenario.abstract.s Node)]]])

(define urdr.scenario.abstract.field
  Field Values ->
    [record
      [[(urdr.scenario.abstract.k "field") (urdr.scenario.abstract.s Field)]
       [(urdr.scenario.abstract.k "values") [list Values]]]])

\\ Chosen so the driver's boundary exploration PASSES the first two
\\ attempts (fault resolves `never`) and discovers the liveness
\\ violation on attempt 2 — the loop demonstrably continues past
\\ passing schedules before it finds the failing one.
(define urdr.scenario.abstract.partition-retry.seed
  -> (urdr.scenario.abstract.k "partition-retry-v1"))

(define urdr.scenario.abstract.budget-value
  ->
    [record
      [[(urdr.scenario.abstract.k "max-events")
        (urdr.scenario.abstract.big 256)]
       [(urdr.scenario.abstract.k "max-runs")
        (urdr.scenario.abstract.big 32)]
       [(urdr.scenario.abstract.k "max-steps")
        (urdr.scenario.abstract.big 128)]]])

(define urdr.scenario.abstract.components-value
  ->
    [list
      [(urdr.scenario.abstract.component
         "client" "process" "pr-client" "a")
       (urdr.scenario.abstract.component
         "fault-0" "process" "pr-fault" "a")
       (urdr.scenario.abstract.component
         "net-0" "process" "pr-net" "a")
       (urdr.scenario.abstract.component
         "relay" "process" "pr-relay" "b")
       (urdr.scenario.abstract.component
         "server" "process" "pr-server" "c")]])

(define urdr.scenario.abstract.fault-record
  ->
    [record
      [[(urdr.scenario.abstract.k "id")
        (urdr.scenario.abstract.s "split")]
       [(urdr.scenario.abstract.k "kinds")
        [list [(urdr.scenario.abstract.s "partition")]]]
       [(urdr.scenario.abstract.k "members")
        [list [(urdr.scenario.abstract.s "c")]]]]])

(define urdr.scenario.abstract.faults-value
  -> [list [(urdr.scenario.abstract.fault-record)]])

(define urdr.scenario.abstract.vocab-value
  ->
    [list
      [(urdr.scenario.abstract.field "dst"
         [(urdr.scenario.abstract.big 1)
          (urdr.scenario.abstract.big 2)
          (urdr.scenario.abstract.big 3)])
       (urdr.scenario.abstract.field "src"
         [(urdr.scenario.abstract.big 1)
          (urdr.scenario.abstract.big 2)
          (urdr.scenario.abstract.big 3)])]])

(define urdr.scenario.abstract.observation-record
  ->
    [record
      [[(urdr.scenario.abstract.k "at")
        (urdr.scenario.abstract.big 8)]
       [(urdr.scenario.abstract.k "id")
        (urdr.scenario.abstract.s "ack-deadline")]]])

(define urdr.scenario.abstract.observations-value
  -> [list [(urdr.scenario.abstract.observation-record)]])

\\ Pattern per shen/properties/properties.shen section 3: a fact by
\\ NAME recorded by the SOURCE component, any value.
(define urdr.scenario.abstract.pattern-value
  Name Source ->
    [record
      [[(urdr.scenario.abstract.k "name")
        (urdr.scenario.abstract.s Name)]
       [(urdr.scenario.abstract.k "source")
        (urdr.scenario.abstract.s Source)]
       [(urdr.scenario.abstract.k "value")
        [null]]]])

(define urdr.scenario.abstract.spec-value
  ->
    [record
      [[(urdr.scenario.abstract.k "deadline")
        (urdr.scenario.abstract.big 8)]
       [(urdr.scenario.abstract.k "pattern")
        (urdr.scenario.abstract.pattern-value "ack" "client")]]])

(define urdr.scenario.abstract.property-record
  ->
    [record
      [[(urdr.scenario.abstract.k "class")
        (urdr.scenario.abstract.s "liveness")]
       [(urdr.scenario.abstract.k "id")
        (urdr.scenario.abstract.s "client-ack")]
       [(urdr.scenario.abstract.k "spec")
        (urdr.scenario.abstract.spec-value)]]])

\\ Every request the client sends is eventually answered by the
\\ network within the same window the ack deadline allows. Its FAIL
\\ witness is the first unanswered request (index, event id, time), so
\\ the failure signature pins a POSITIVE artifact of the discovered
\\ run: a shrink candidate must still send that request and still
\\ leave it unanswered — the liveness property alone (witness
\\ no-witness) would let the shrinker empty the transcript entirely.
(define urdr.scenario.abstract.served-record
  ->
    [record
      [[(urdr.scenario.abstract.k "class")
        (urdr.scenario.abstract.s "temporal")]
       [(urdr.scenario.abstract.k "id")
        (urdr.scenario.abstract.s "request-served")]
       [(urdr.scenario.abstract.k "spec")
        [record
          [[(urdr.scenario.abstract.k "args")
            [list
              [(urdr.scenario.abstract.pattern-value "request" "client")
               (urdr.scenario.abstract.pattern-value "respond" "net-0")
               (urdr.scenario.abstract.big 8)]]]
           [(urdr.scenario.abstract.k "form")
            (urdr.scenario.abstract.s "always-eventually")]]]]]])

(define urdr.scenario.abstract.properties-value
  -> [list [(urdr.scenario.abstract.property-record)
            (urdr.scenario.abstract.served-record)]])

(define urdr.scenario.abstract.route
  Fact From To ->
    [record
      [[(urdr.scenario.abstract.k "fact")
        (urdr.scenario.abstract.s Fact)]
       [(urdr.scenario.abstract.k "from")
        (urdr.scenario.abstract.s From)]
       [(urdr.scenario.abstract.k "to")
        (urdr.scenario.abstract.s To)]]])

(define urdr.scenario.abstract.routes-value
  ->
    [list
      [(urdr.scenario.abstract.route "request" "client" "net-0")
       (urdr.scenario.abstract.route "partition" "fault-0" "net-0")
       (urdr.scenario.abstract.route "deliver" "net-0" "server")
       (urdr.scenario.abstract.route "hop" "net-0" "relay")
       (urdr.scenario.abstract.route "deliver" "relay" "server")
       (urdr.scenario.abstract.route "reply" "server" "net-0")
       (urdr.scenario.abstract.route "respond" "net-0" "client")
       (urdr.scenario.abstract.route "timeout" "net-0" "client")]])

(define urdr.scenario.abstract.topology-value
  ->
    [record
      [[(urdr.scenario.abstract.k "links")
        [list
          [(urdr.scenario.abstract.link "a" "b")
           (urdr.scenario.abstract.link "a" "c")
           (urdr.scenario.abstract.link "b" "c")]]]
       [(urdr.scenario.abstract.k "nodes")
        [list
          [(urdr.scenario.abstract.node 1 "a")
           (urdr.scenario.abstract.node 2 "b")
           (urdr.scenario.abstract.node 3 "c")]]]]])

\\ The partition of {c} under fault domain "split" is schedule-
\\ dependent: the first request always opens the network's path choice
\\ before the fault menu resolves, so when the fault fires `early` the
\\ mask lands while the reply is in flight and the reply is withheld;
\\ the client's retries then meet the cut fabric and it gives up — no
\\ ack, both properties FAIL. When the fault resolves `never`, the
\\ reply crosses and the client acks — both properties PASS. Discovery
\\ is therefore the driver's, not the declaration's.
(define urdr.scenario.abstract.partition-retry.value
  ->
    [record
      [[(urdr.scenario.abstract.k "budget")
        (urdr.scenario.abstract.budget-value)]
       [(urdr.scenario.abstract.k "components")
        (urdr.scenario.abstract.components-value)]
       [(urdr.scenario.abstract.k "determinism")
        (urdr.scenario.abstract.s "modeled")]
       [(urdr.scenario.abstract.k "faults")
        (urdr.scenario.abstract.faults-value)]
       [(urdr.scenario.abstract.k "header-vocabulary")
        (urdr.scenario.abstract.vocab-value)]
       [(urdr.scenario.abstract.k "observations")
        (urdr.scenario.abstract.observations-value)]
       [(urdr.scenario.abstract.k "properties")
        (urdr.scenario.abstract.properties-value)]
       [(urdr.scenario.abstract.k "routes")
        (urdr.scenario.abstract.routes-value)]
       [(urdr.scenario.abstract.k "seed")
        [bytes (urdr.scenario.abstract.partition-retry.seed)]]
       [(urdr.scenario.abstract.k "topology")
        (urdr.scenario.abstract.topology-value)]
       [(urdr.scenario.abstract.k "version")
        (urdr.scenario.abstract.s "scenario/v1")]]])

(define urdr.scenario.abstract.partition-retry.validated
  -> (urdr.scenario.validate
       (urdr.scenario.abstract.partition-retry.value)))
