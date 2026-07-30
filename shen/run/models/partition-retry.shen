\* Reference models for the partition-retry scenario (ADR 0007
required verification 2 — the earned exit demonstration).

Requires shen/protocol/canonical.shen, shen/world/integer.shen, and
shen/world/models/common.shen to be loaded by the caller.

Ownership: this module lives under shen/run/ because it is DRIVER
material, not kernel material. shen/world/models/ holds the built-in
component kinds every scenario may bind (net, timer, fault);
scenarios/ holds declarations and may not hold executable behavior.
These handlers are the reference implementation OF one declaration —
scenarios/abstract/partition-retry.shen — packaged as the model table
urdr.run.execute consumes, so they sit beside the driver that runs
them (docs/module-boundaries.md: shen/run/ may depend on
shen/world/models/; nothing depends back on shen/run/).

Pure component-step functions of ADR 0004 Decision 1: no I/O, no host
time, no host randomness, no floating point. No model draws, allocates
ids, advances time, or selects among its own alternatives; every
nondeterministic edge is a published choice the driver resolves and
delivers back (run.shen's selection-delivery rule).

The modeled protocol, over the declared topology a->b, a->c, b->c:

  client  (process @ a)  boot: sends request seq 1 toward the server
                         through the network process. Retries on each
                         routed timeout notice up to 3 tries — the
                         retry counter is model state — then gives up.
                         On a routed respond it emits the `ack` fact
                         the declared liveness property watches.
  fault-0 (process @ a)  boot: publishes ONE choice (purpose `fault`):
                         partition {c} early, or never. On `early` it
                         emits a routed `partition` fact naming the
                         declared members {c}; on `never`, nothing.
                         One-shot by construction, so a driver run
                         quiesces (see the built-in-model note below).
  net-0   (process @ a)  the network effect, modeled directly: routed
                         requests either cross (publishing a `delivery`
                         path choice — direct a->c or via the relay
                         a->b->c) or, when the partition mask is set,
                         are withheld and surface to the sender as a
                         routed `timeout` — the observable shadow of
                         loss under a local timer, which is the net
                         model's to own (delay and loss are network
                         authorities; a client cannot observe the
                         difference). Replies cross the same gate, so
                         a partition that lands while a reply is in
                         flight withholds it: that race is the
                         schedule-dependent failure.
  relay   (process @ b)  forwards: a routed `hop` becomes a routed
                         `deliver` toward the server (the a->b->c
                         path the topology declares).
  server  (process @ c)  replies to every routed `deliver`.

Why fault-0 and net-0 run these reference models instead of the
built-in fault/net kinds: the built-in fault model republishes its
fault-action menu on EVERY step, and the driver resolves every open
menu, so a driver-run built-in fault toggles activate/deactivate until
max-steps aborts the attempt — its menus (like the net model's
deliver-input and the timer's fire-input wrapping) stay deferred until
the wave that integrates the built-in models under the driver. The
partition domain {c} baked into urdr.run.pr.fault-initial mirrors the
scenario's declared fault domain; init-builders receive the roster
record and the network baseline only (registry.shen), not the scenario
declaration, so the members cannot be threaded from the declaration
yet — recorded as deferred in docs/status/m1-5.md.

Message values are records dispatched on their `msg` key, because a
routed delivery carries the fact's VALUE only (the route, not the
value, names the fact). None of the names below touches the component
contract's reserved-authority list. *\

\\ ---------------------------------------------------------------
\\ Names
\\ ---------------------------------------------------------------

(define urdr.run.pr.k
  Name -> (urdr.canonical.string-bytes Name))

(define urdr.run.pr.s
  Name -> [symbol (urdr.run.pr.k Name)])

(define urdr.run.pr.big
  N -> (urdr.int.raw.from-small N))

(define urdr.run.pr.boot
  -> [symbol (urdr.run.pr.k "boot")])

\\ The client gives up after this many requests (seq 1..3).
(define urdr.run.pr.retry-limit
  -> (urdr.run.pr.big 3))

\\ ---------------------------------------------------------------
\\ Shared message shape: [record [[msg SYMBOL] [seq INTEGER]]]
\\ (keys ascend msg < seq).
\\ ---------------------------------------------------------------

(define urdr.run.pr.message
  Name Seq ->
    [record
      [[(urdr.run.pr.k "msg") (urdr.run.pr.s Name)]
       [(urdr.run.pr.k "seq") Seq]]])

(define urdr.run.pr.msg-of
  Input ->
    (urdr.model.common.symbol-bytes
      (urdr.model.common.get Input (urdr.run.pr.k "msg"))))

(define urdr.run.pr.seq-of
  Input ->
    (urdr.model.common.integer
      (urdr.model.common.get Input (urdr.run.pr.k "seq"))))

(define urdr.run.pr.msg?
  Input Name ->
    (urdr.run.pr.same-msg (urdr.run.pr.msg-of Input) Name))

(define urdr.run.pr.same-msg
  none _ -> false
  Bs Name -> (urdr.model.common.same? Bs (urdr.run.pr.k Name)))

(define urdr.run.pr.absorb
  State -> [step State [] []])

\\ ---------------------------------------------------------------
\\ client: request, retry on timeout, ack on respond.
\\ State: [record [[tries INTEGER]]] — the retry counter.
\\ ---------------------------------------------------------------

(define urdr.run.pr.client-state
  Tries -> [record [[(urdr.run.pr.k "tries") Tries]]])

(define urdr.run.pr.client-initial
  -> (urdr.run.pr.client-state (urdr.int.zero)))

(define urdr.run.pr.client-tries
  State ->
    (urdr.model.common.integer
      (urdr.model.common.get State (urdr.run.pr.k "tries"))))

(define urdr.run.pr.client-request
  Tries ->
    [step (urdr.run.pr.client-state Tries)
      [[fact (urdr.run.pr.k "request")
         (urdr.run.pr.message "request" Tries)]]
      []])

(define urdr.run.pr.client
  State Event ->
    (urdr.run.pr.client-h
      (urdr.model.common.event-input Event) State))

(define urdr.run.pr.client-h
  Input State ->
    (if (= Input (urdr.run.pr.boot))
        (urdr.run.pr.client-request (urdr.int.one))
        (if (urdr.run.pr.msg? Input "respond")
            [step State
              [[fact (urdr.run.pr.k "ack") Input]]
              []]
            (if (urdr.run.pr.msg? Input "timeout")
                (urdr.run.pr.client-retry
                  (urdr.run.pr.client-tries State) State)
                (urdr.run.pr.absorb State)))))

\\ A malformed retry state is a model bug, not something to absorb.
(define urdr.run.pr.client-retry
  none State -> (urdr.model.common.error "pr-client-state-shape")
  Tries State ->
    (if (< (urdr.int.raw.compare Tries (urdr.run.pr.retry-limit)) 0)
        (urdr.run.pr.client-request
          (urdr.int.raw.add Tries (urdr.int.one)))
        [step State
          [[fact (urdr.run.pr.k "gave-up")
             [record [[(urdr.run.pr.k "tries") Tries]]]]]
          []]))

\\ ---------------------------------------------------------------
\\ fault-0: one partition-timing choice, then quiescent.
\\ State: [record [[members [list [symbol NODE] ...]]]] — the declared
\\ partition domain (split: partition of {c}).
\\ ---------------------------------------------------------------

(define urdr.run.pr.fault-initial
  -> [record
       [[(urdr.run.pr.k "members")
         [list [(urdr.run.pr.s "c")]]]]])

(define urdr.run.pr.when-alt
  Name -> [record [[(urdr.run.pr.k "when") (urdr.run.pr.s Name)]]])

(define urdr.run.pr.when-of
  Input ->
    (urdr.model.common.symbol-bytes
      (urdr.model.common.get Input (urdr.run.pr.k "when"))))

(define urdr.run.pr.fault
  State Event ->
    (urdr.run.pr.fault-h
      (urdr.model.common.event-input Event) State))

(define urdr.run.pr.fault-h
  Input State ->
    (if (= Input (urdr.run.pr.boot))
        [step State []
          (urdr.model.common.choice
            (urdr.run.pr.k "fault")
            [(urdr.run.pr.when-alt "early")
             (urdr.run.pr.when-alt "never")])]
        (urdr.run.pr.fault-when
          (urdr.run.pr.when-of Input) State)))

(define urdr.run.pr.fault-when
  none State -> (urdr.run.pr.absorb State)
  When State ->
    (if (urdr.model.common.same? When (urdr.run.pr.k "early"))
        [step State
          [[fact (urdr.run.pr.k "partition")
             [record
               [[(urdr.run.pr.k "members")
                 (urdr.model.common.get
                   State (urdr.run.pr.k "members"))]
                [(urdr.run.pr.k "msg")
                 (urdr.run.pr.s "partition")]]]]]
          []]
        (urdr.run.pr.absorb State)))

\\ ---------------------------------------------------------------
\\ net-0: the modeled network. State:
\\ [record [[cut [symbol off|on]] [pending INTEGER | [null]]]]
\\ (keys ascend cut < pending). `pending` is the seq of the one
\\ request awaiting its path selection; the protocol keeps at most
\\ one in flight (retries only follow timeouts).
\\ ---------------------------------------------------------------

(define urdr.run.pr.net-state
  Cut Pending ->
    [record
      [[(urdr.run.pr.k "cut") [symbol Cut]]
       [(urdr.run.pr.k "pending") Pending]]])

(define urdr.run.pr.net-initial
  -> (urdr.run.pr.net-state (urdr.run.pr.k "off") [null]))

(define urdr.run.pr.net-cut?
  State ->
    (urdr.run.pr.cut-on
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get State (urdr.run.pr.k "cut")))))

(define urdr.run.pr.cut-on
  none -> false
  Bs -> (urdr.model.common.same? Bs (urdr.run.pr.k "on")))

(define urdr.run.pr.net-pending
  State -> (urdr.model.common.get State (urdr.run.pr.k "pending")))

(define urdr.run.pr.via-of
  Input ->
    (urdr.model.common.symbol-bytes
      (urdr.model.common.get Input (urdr.run.pr.k "via"))))

(define urdr.run.pr.via-alt
  Name -> [record [[(urdr.run.pr.k "via") (urdr.run.pr.s Name)]]])

(define urdr.run.pr.timeout-step
  State Seq ->
    [step State
      [[fact (urdr.run.pr.k "timeout")
         (urdr.run.pr.message "timeout" Seq)]]
      []])

(define urdr.run.pr.net
  State Event ->
    (urdr.run.pr.net-h
      (urdr.model.common.event-input Event) State))

(define urdr.run.pr.net-h
  Input State ->
    (if (urdr.run.pr.msg? Input "partition")
        (urdr.run.pr.net-mask Input State)
        (if (urdr.run.pr.msg? Input "request")
            (urdr.run.pr.net-request
              (urdr.run.pr.seq-of Input) State)
            (if (urdr.run.pr.msg? Input "reply")
                (urdr.run.pr.net-reply
                  (urdr.run.pr.seq-of Input) State)
                (urdr.run.pr.net-via
                  (urdr.run.pr.via-of Input) State)))))

\\ The mask lands: the fabric is cut. The `masked` fact is the
\\ observable evidence that the routed partition took effect.
(define urdr.run.pr.net-mask
  Input State ->
    [step (urdr.run.pr.net-state
            (urdr.run.pr.k "on") (urdr.run.pr.net-pending State))
      [[fact (urdr.run.pr.k "masked")
         [record
           [[(urdr.run.pr.k "members")
             (urdr.model.common.get Input (urdr.run.pr.k "members"))]
            [(urdr.run.pr.k "msg") (urdr.run.pr.s "masked")]]]]]
      []])

\\ An uncut request opens the path choice; a cut one is withheld and
\\ surfaces as the sender's timeout.
(define urdr.run.pr.net-request
  none State -> (urdr.model.common.error "pr-net-request-shape")
  Seq State ->
    (if (urdr.run.pr.net-cut? State)
        (urdr.run.pr.timeout-step State Seq)
        [step (urdr.run.pr.net-state (urdr.run.pr.k "off") Seq)
          []
          (urdr.model.common.choice
            (urdr.run.pr.k "delivery")
            [(urdr.run.pr.via-alt "direct")
             (urdr.run.pr.via-alt "relay")])]))

(define urdr.run.pr.net-reply
  none State -> (urdr.model.common.error "pr-net-reply-shape")
  Seq State ->
    (if (urdr.run.pr.net-cut? State)
        (urdr.run.pr.timeout-step State Seq)
        [step State
          [[fact (urdr.run.pr.k "respond")
             (urdr.run.pr.message "respond" Seq)]]
          []]))

\\ The path selection returns. The partition may have landed while the
\\ menu was open — the selection then finds the fabric cut and the
\\ request is withheld like any other cut crossing.
(define urdr.run.pr.net-via
  none State -> (urdr.run.pr.absorb State)
  Via State ->
    (urdr.run.pr.net-via-pending
      (urdr.model.common.integer (urdr.run.pr.net-pending State))
      Via
      State))

(define urdr.run.pr.net-via-pending
  none _ State -> (urdr.run.pr.absorb State)
  Seq Via State ->
    (let Cleared (urdr.run.pr.net-state
                   (if (urdr.run.pr.net-cut? State)
                       (urdr.run.pr.k "on")
                       (urdr.run.pr.k "off"))
                   [null])
      (if (urdr.run.pr.net-cut? State)
          (urdr.run.pr.timeout-step Cleared Seq)
          (if (urdr.model.common.same? Via (urdr.run.pr.k "direct"))
              [step Cleared
                [[fact (urdr.run.pr.k "deliver")
                   (urdr.run.pr.message "deliver" Seq)]]
                []]
              [step Cleared
                [[fact (urdr.run.pr.k "hop")
                   (urdr.run.pr.message "hop" Seq)]]
                []]))))

\\ ---------------------------------------------------------------
\\ relay: the declared b hop — a routed `hop` becomes a `deliver`.
\\ ---------------------------------------------------------------

(define urdr.run.pr.relay-initial
  -> [record [[(urdr.run.pr.k "role") (urdr.run.pr.s "relay")]]])

(define urdr.run.pr.relay
  State Event ->
    (urdr.run.pr.relay-h
      (urdr.model.common.event-input Event) State))

(define urdr.run.pr.relay-h
  Input State ->
    (if (urdr.run.pr.msg? Input "hop")
        [step State
          [[fact (urdr.run.pr.k "deliver")
             (urdr.run.pr.message "deliver"
               (urdr.run.pr.seq-value Input))]]
          []]
        (urdr.run.pr.absorb State)))

\\ A hop without a seq is a protocol-shape bug, surfaced as zero
\\ rather than silently dropped: the reply's seq then disagrees with
\\ the request's, which the trace makes visible.
(define urdr.run.pr.seq-value
  Input -> (urdr.run.pr.seq-or-zero (urdr.run.pr.seq-of Input)))

(define urdr.run.pr.seq-or-zero
  none -> (urdr.int.zero)
  Seq -> Seq)

\\ ---------------------------------------------------------------
\\ server: acks every delivered request.
\\ ---------------------------------------------------------------

(define urdr.run.pr.server-initial
  -> [record [[(urdr.run.pr.k "role") (urdr.run.pr.s "server")]]])

(define urdr.run.pr.server
  State Event ->
    (urdr.run.pr.server-h
      (urdr.model.common.event-input Event) State))

(define urdr.run.pr.server-h
  Input State ->
    (if (urdr.run.pr.msg? Input "deliver")
        [step State
          [[fact (urdr.run.pr.k "reply")
             (urdr.run.pr.message "reply"
               (urdr.run.pr.seq-value Input))]]
          []]
        (urdr.run.pr.absorb State)))

\\ ---------------------------------------------------------------
\\ The model table urdr.run.execute consumes: [MODEL [HANDLER
\\ INIT-BUILDER]] ascending strictly by model name (registry.shen).
\\ Init-builders ignore the roster record and baseline — every
\\ initial state above is a function of the declaration this module
\\ mirrors.
\\ ---------------------------------------------------------------

(define urdr.run.pr.models
  -> [[(urdr.run.pr.k "pr-client")
       [(/. S E (urdr.run.pr.client S E))
        (/. C B (urdr.run.pr.client-initial))]]
      [(urdr.run.pr.k "pr-fault")
       [(/. S E (urdr.run.pr.fault S E))
        (/. C B (urdr.run.pr.fault-initial))]]
      [(urdr.run.pr.k "pr-net")
       [(/. S E (urdr.run.pr.net S E))
        (/. C B (urdr.run.pr.net-initial))]]
      [(urdr.run.pr.k "pr-relay")
       [(/. S E (urdr.run.pr.relay S E))
        (/. C B (urdr.run.pr.relay-initial))]]
      [(urdr.run.pr.k "pr-server")
       [(/. S E (urdr.run.pr.server S E))
        (/. C B (urdr.run.pr.server-initial))]]])
