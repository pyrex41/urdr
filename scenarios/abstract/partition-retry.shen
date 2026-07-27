\* M1 Wave I reference scenario: partition-retry.

Three modeled processes (client, relay, server) over a NetKAT-policied
abstract network with a retry protocol and a seeded partition fault that
violates a liveness deadline.

This module constructs the canonical scenario value and a few topology
helpers the integration suite uses. It does not drive explore/shrink;
that wiring lives under shen/tests/integration/.

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

(define urdr.scenario.abstract.component
  Id Kind Node ->
    [record
      [[(urdr.scenario.abstract.k "id") (urdr.scenario.abstract.s Id)]
       [(urdr.scenario.abstract.k "kind") (urdr.scenario.abstract.s Kind)]
       [(urdr.scenario.abstract.k "node") (urdr.scenario.abstract.s Node)]]])

(define urdr.scenario.abstract.field
  Field Values ->
    [record
      [[(urdr.scenario.abstract.k "field") (urdr.scenario.abstract.s Field)]
       [(urdr.scenario.abstract.k "values") [list Values]]]])

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
      [(urdr.scenario.abstract.component "client" "process" "a")
       (urdr.scenario.abstract.component "fault-0" "fault" "a")
       (urdr.scenario.abstract.component "net-0" "net" "a")
       (urdr.scenario.abstract.component "relay" "process" "b")
       (urdr.scenario.abstract.component "server" "process" "c")]])

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

(define urdr.scenario.abstract.spec-value
  ->
    [record
      [[(urdr.scenario.abstract.k "deadline")
        (urdr.scenario.abstract.big 8)]
       [(urdr.scenario.abstract.k "pattern")
        (urdr.scenario.abstract.s "ack")]]])

(define urdr.scenario.abstract.property-record
  ->
    [record
      [[(urdr.scenario.abstract.k "class")
        (urdr.scenario.abstract.s "liveness")]
       [(urdr.scenario.abstract.k "id")
        (urdr.scenario.abstract.s "client-ack")]
       [(urdr.scenario.abstract.k "spec")
        (urdr.scenario.abstract.spec-value)]]])

(define urdr.scenario.abstract.properties-value
  -> [list [(urdr.scenario.abstract.property-record)]])

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

\\ Seeded partition of {c} under fault domain "split" breaks
\\ client->server reachability (a->c). The client retries; the liveness
\\ property requires an ack by logical deadline 8, which the partition
\\ prevents.
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
       [(urdr.scenario.abstract.k "seed")
        [bytes (urdr.scenario.abstract.partition-retry.seed)]]
       [(urdr.scenario.abstract.k "topology")
        (urdr.scenario.abstract.topology-value)]
       [(urdr.scenario.abstract.k "version")
        (urdr.scenario.abstract.s "scenario/v1")]]])

(define urdr.scenario.abstract.partition-retry.validated
  -> (urdr.scenario.validate
       (urdr.scenario.abstract.partition-retry.value)))
