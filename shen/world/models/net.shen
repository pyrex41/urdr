\* The abstract network model (plan Wave C, ADR 0004 Decisions 1 and 2).

Requires shen/protocol/canonical.shen, shen/world/integer.shen,
shen/world/netkat.shen, shen/world/component.shen, and
shen/world/models/common.shen to be loaded by the caller.

The network is a modeled component. It holds one FIFO queue of pending
packets per declared directed link, it publishes the legal delivery
alternatives as a choice, and it delivers exactly the packets the active
NetKAT policy admits. It never orders deliveries, never selects among the
alternatives it publishes, and never invents a packet: every delivered
packet comes out of urdr.netkat.eval applied to a packet the model was
previously told to send.

State
-----

  [record [[baseline TERM-VALUE]
           [links    [list LINK ...]]
           [masks    [list MASK ...]]
           [pending  [list QUEUE ...]]
           [vocab    VOCAB-VALUE]]]

  LINK  [record [[dst ADDRESS] [from [symbol NODE]]
                 [src ADDRESS] [to [symbol NODE]]]]
  MASK  [record [[fault [symbol KIND]] [id [symbol MASK-ID]]
                 [members [list ADDRESS ...]]]]
  QUEUE [record [[items [list PACKET ...]] [via VIA]]]
  VIA   [record [[from [symbol NODE]] [to [symbol NODE]]]]

No key and no symbol value above is one of the nine authorities reserved
to the world kernel, so the component-interface scan accepts the state.
Logical time never appears: the queue is ordered by arrival, not by a
timestamp the model would have had to invent.

Inputs (the value of a [component-input NAME VALUE] event)
----------------------------------------------------------

  send    [record [[kind [symbol send]] [packet PACKET] [via VIA]]]
  deliver [record [[kind [symbol deliver]] [selection ALTERNATIVE]]]
  mask    [record [[fault [symbol KIND]] [id [symbol MASK-ID]]
                   [kind [symbol mask]] [members [list ADDRESS ...]]]]
  unmask  [record [[id [symbol MASK-ID]] [kind [symbol unmask]]]]
  poll    [record [[kind [symbol poll]]]]

Facts: queued, delivered, dropped, blocked, masked, unmasked.

Choices: one purpose, `delivery`, whose alternatives are

  [record [[action [symbol deliver | drop | duplicate]]
           [index INDEX] [via VIA]]]

for every pending packet on every link. `deliver` at index 0 is delivery
in order; `deliver` at a higher index is a reordering candidate;
`duplicate` delivers without dequeuing. Which alternative is taken is the
world kernel's search decision, never the model's.

Active policy composition (canonical order)
-------------------------------------------

  active = nk-seq(TOPOLOGY, nk-seq(MASKS, BASELINE))

  TOPOLOGY  right-folded nk-union over the declared links in ascending
            (from, to) order, each link contributing
            nk-seq(nk-test src ADDR-from, nk-test dst ADDR-to). An empty
            link set folds to nk-drop: a packet whose src/dst pair is not
            a declared link is admitted by nothing.
  MASKS     right-folded nk-seq over the active fault masks in ascending
            mask-id order, with nk-id as the unit, each mask's term
            derived by urdr.model.mask.term from the descriptor the fault
            model published. Sequencing predicates is their conjunction,
            so masks intersect and the order of activation cannot change
            the result.
  BASELINE  the scenario's baseline forwarding/admission policy.

The composition is rebuilt from state on every step and revalidated by
urdr.netkat.term-check, so a composition that would exceed the NetKAT
resource profile fails closed with the algebra's own code rather than
being silently truncated. *\

\\ ---------------------------------------------------------------
\\ Names
\\ ---------------------------------------------------------------

(define urdr.model.net.n.action
  -> (urdr.canonical.string-bytes "action"))

(define urdr.model.net.n.baseline
  -> (urdr.canonical.string-bytes "baseline"))

(define urdr.model.net.n.blocked
  -> (urdr.canonical.string-bytes "blocked"))

(define urdr.model.net.n.deliver
  -> (urdr.canonical.string-bytes "deliver"))

(define urdr.model.net.n.delivered
  -> (urdr.canonical.string-bytes "delivered"))

(define urdr.model.net.n.delivery
  -> (urdr.canonical.string-bytes "delivery"))

(define urdr.model.net.n.drop
  -> (urdr.canonical.string-bytes "drop"))

(define urdr.model.net.n.dropped
  -> (urdr.canonical.string-bytes "dropped"))

(define urdr.model.net.n.dst
  -> (urdr.model.mask.n.dst))

(define urdr.model.net.n.duplicate
  -> (urdr.canonical.string-bytes "duplicate"))

(define urdr.model.net.n.from
  -> (urdr.canonical.string-bytes "from"))

(define urdr.model.net.n.id
  -> (urdr.canonical.string-bytes "id"))

(define urdr.model.net.n.index
  -> (urdr.canonical.string-bytes "index"))

(define urdr.model.net.n.items
  -> (urdr.canonical.string-bytes "items"))

(define urdr.model.net.n.kind
  -> (urdr.canonical.string-bytes "kind"))

(define urdr.model.net.n.links
  -> (urdr.canonical.string-bytes "links"))

(define urdr.model.net.n.mask
  -> (urdr.canonical.string-bytes "mask"))

(define urdr.model.net.n.masked
  -> (urdr.canonical.string-bytes "masked"))

(define urdr.model.net.n.masks
  -> (urdr.canonical.string-bytes "masks"))

(define urdr.model.net.n.packet
  -> (urdr.canonical.string-bytes "packet"))

(define urdr.model.net.n.pending
  -> (urdr.canonical.string-bytes "pending"))

(define urdr.model.net.n.poll
  -> (urdr.canonical.string-bytes "poll"))

(define urdr.model.net.n.queued
  -> (urdr.canonical.string-bytes "queued"))

(define urdr.model.net.n.selection
  -> (urdr.canonical.string-bytes "selection"))

(define urdr.model.net.n.send
  -> (urdr.canonical.string-bytes "send"))

(define urdr.model.net.n.sent
  -> (urdr.canonical.string-bytes "sent"))

(define urdr.model.net.n.src
  -> (urdr.model.mask.n.src))

(define urdr.model.net.n.to
  -> (urdr.canonical.string-bytes "to"))

(define urdr.model.net.n.unmask
  -> (urdr.canonical.string-bytes "unmask"))

(define urdr.model.net.n.unmasked
  -> (urdr.canonical.string-bytes "unmasked"))

(define urdr.model.net.n.via
  -> (urdr.canonical.string-bytes "via"))

(define urdr.model.net.n.vocab
  -> (urdr.canonical.string-bytes "vocab"))

\\ ---------------------------------------------------------------
\\ State rendering
\\ ---------------------------------------------------------------

(define urdr.model.net.via-value
  From To ->
    [record
      [[(urdr.model.net.n.from) [symbol From]]
       [(urdr.model.net.n.to) [symbol To]]]])

(define urdr.model.net.link-value
  [link From To Src Dst] ->
    [record
      [[(urdr.model.net.n.dst) Dst]
       [(urdr.model.net.n.from) [symbol From]]
       [(urdr.model.net.n.src) Src]
       [(urdr.model.net.n.to) [symbol To]]]])

(define urdr.model.net.links-value
  [] -> []
  [Link | Rest] ->
    [(urdr.model.net.link-value Link) |
     (urdr.model.net.links-value Rest)])

(define urdr.model.net.mask-value
  [mask Id Kind Addresses] ->
    (urdr.model.mask.value Id Kind Addresses))

(define urdr.model.net.masks-value
  [] -> []
  [Mask | Rest] ->
    [(urdr.model.net.mask-value Mask) |
     (urdr.model.net.masks-value Rest)])

(define urdr.model.net.queue-value
  [queue From To Packets] ->
    [record
      [[(urdr.model.net.n.items) [list Packets]]
       [(urdr.model.net.n.via) (urdr.model.net.via-value From To)]]])

(define urdr.model.net.queues-value
  [] -> []
  [Queue | Rest] ->
    [(urdr.model.net.queue-value Queue) |
     (urdr.model.net.queues-value Rest)])

(define urdr.model.net.state-value
  VocabValue BaselineValue Links Masks Pending ->
    [record
      [[(urdr.model.net.n.baseline) BaselineValue]
       [(urdr.model.net.n.links)
        [list (urdr.model.net.links-value Links)]]
       [(urdr.model.net.n.masks)
        [list (urdr.model.net.masks-value Masks)]]
       [(urdr.model.net.n.pending)
        [list (urdr.model.net.queues-value Pending)]]
       [(urdr.model.net.n.vocab) VocabValue]]])

\\ ---------------------------------------------------------------
\\ State decoding. Every step revalidates the whole state against the
\\ algebra rather than trusting a previously accepted shape.
\\ ---------------------------------------------------------------

(define urdr.model.net.link-of
  Value ->
    (urdr.model.net.link-parts
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get Value (urdr.model.net.n.from)))
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get Value (urdr.model.net.n.to)))
      (urdr.model.common.integer
        (urdr.model.common.get Value (urdr.model.net.n.src)))
      (urdr.model.common.integer
        (urdr.model.common.get Value (urdr.model.net.n.dst)))))

(define urdr.model.net.link-parts
  none To Src Dst -> none
  From none Src Dst -> none
  From To none Dst -> none
  From To Src none -> none
  From To Src Dst -> [link From To Src Dst])

(define urdr.model.net.via-of
  Value ->
    (urdr.model.net.via-parts
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get Value (urdr.model.net.n.from)))
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get Value (urdr.model.net.n.to)))))

(define urdr.model.net.via-parts
  none To -> none
  From none -> none
  From To -> [via From To])

(define urdr.model.net.endpoint-compare
  [link FromA ToA _ _] [link FromB ToB _ _] ->
    (urdr.model.net.pair-compare FromA ToA FromB ToB)
  [queue FromA ToA _] [queue FromB ToB _] ->
    (urdr.model.net.pair-compare FromA ToA FromB ToB))

(define urdr.model.net.pair-compare
  FromA ToA FromB ToB ->
    (let Order (urdr.canonical.bytes-compare FromA FromB)
      (if (= Order eq)
          (urdr.canonical.bytes-compare ToA ToB)
          Order)))

(define urdr.model.net.links-loop
  [] Previous Acc -> [ok (urdr.model.common.rev Acc)]
  [Value | Rest] Previous Acc ->
    (urdr.model.net.links-step
      (urdr.model.net.link-of Value) Rest Previous Acc)
  _ Previous Acc -> (urdr.model.common.error "net-links-shape"))

(define urdr.model.net.links-step
  none Rest Previous Acc -> (urdr.model.common.error "net-link-shape")
  Link Rest none Acc ->
    (urdr.model.net.links-loop Rest Link [Link | Acc])
  Link Rest Previous Acc ->
    (if (= (urdr.model.net.endpoint-compare Previous Link) lt)
        (urdr.model.net.links-loop Rest Link [Link | Acc])
        (urdr.model.common.error "net-links-order")))

(define urdr.model.net.links-of
  none -> (urdr.model.common.error "net-links-shape")
  Items -> (urdr.model.net.links-loop Items none []))

(define urdr.model.net.masks-loop
  [] Previous Acc -> [ok (urdr.model.common.rev Acc)]
  [Value | Rest] Previous Acc ->
    (urdr.model.net.masks-step
      (urdr.model.mask.of Value) Rest Previous Acc)
  _ Previous Acc -> (urdr.model.common.error "net-masks-shape"))

(define urdr.model.net.masks-step
  [error E] Rest Previous Acc -> [error E]
  [error E Detail] Rest Previous Acc -> [error E Detail]
  [ok [mask Id Kind Addresses]] Rest none Acc ->
    (urdr.model.net.masks-loop
      Rest Id [[mask Id Kind Addresses] | Acc])
  [ok [mask Id Kind Addresses]] Rest Previous Acc ->
    (if (= (urdr.canonical.bytes-compare Previous Id) lt)
        (urdr.model.net.masks-loop
          Rest Id [[mask Id Kind Addresses] | Acc])
        (urdr.model.common.error "net-masks-order")))

(define urdr.model.net.masks-of
  none -> (urdr.model.common.error "net-masks-shape")
  Items -> (urdr.model.net.masks-loop Items none []))

(define urdr.model.net.packets-loop
  Vocab [] Acc -> [ok (urdr.model.common.rev Acc)]
  Vocab [Value | Rest] Acc ->
    (urdr.model.net.packets-step
      (urdr.netkat.packet Vocab Value) Vocab Rest Acc)
  Vocab _ Acc -> (urdr.model.common.error "net-items-shape"))

(define urdr.model.net.packets-step
  [error E] Vocab Rest Acc -> (urdr.model.common.netkat-error [error E])
  [ok Packet] Vocab Rest Acc ->
    (urdr.model.net.packets-loop Vocab Rest [Packet | Acc]))

(define urdr.model.net.queue-of
  Vocab Value ->
    (urdr.model.net.queue-parts
      (urdr.model.net.via-of
        (urdr.model.common.get Value (urdr.model.net.n.via)))
      (urdr.model.common.items
        (urdr.model.common.get Value (urdr.model.net.n.items)))
      Vocab))

(define urdr.model.net.queue-parts
  none Items Vocab -> (urdr.model.common.error "net-queue-shape")
  Via none Vocab -> (urdr.model.common.error "net-queue-shape")
  [via From To] Items Vocab ->
    (urdr.model.net.queue-packets
      (urdr.model.net.packets-loop Vocab Items []) From To))

(define urdr.model.net.queue-packets
  [error E] From To -> [error E]
  [error E Detail] From To -> [error E Detail]
  [ok Packets] From To -> [ok [queue From To Packets]])

(define urdr.model.net.pending-loop
  Vocab Links [] Previous Acc -> [ok (urdr.model.common.rev Acc)]
  Vocab Links [Value | Rest] Previous Acc ->
    (urdr.model.net.pending-step
      (urdr.model.net.queue-of Vocab Value) Vocab Links Rest Previous Acc)
  Vocab Links _ Previous Acc ->
    (urdr.model.common.error "net-pending-shape"))

(define urdr.model.net.pending-step
  [error E] Vocab Links Rest Previous Acc -> [error E]
  [error E Detail] Vocab Links Rest Previous Acc -> [error E Detail]
  [ok Queue] Vocab Links Rest Previous Acc ->
    (if (not (urdr.model.net.declared? Queue Links))
        (urdr.model.common.error "net-unknown-link")
        (urdr.model.net.pending-order Queue Vocab Links Rest Previous Acc)))

(define urdr.model.net.pending-order
  Queue Vocab Links Rest none Acc ->
    (urdr.model.net.pending-loop Vocab Links Rest Queue [Queue | Acc])
  Queue Vocab Links Rest Previous Acc ->
    (if (= (urdr.model.net.endpoint-compare Previous Queue) lt)
        (urdr.model.net.pending-loop Vocab Links Rest Queue [Queue | Acc])
        (urdr.model.common.error "net-pending-order")))

(define urdr.model.net.declared?
  [queue From To _] Links ->
    (urdr.model.net.link-declared? From To Links))

(define urdr.model.net.link-declared?
  From To [] -> false
  From To [[link LinkFrom LinkTo _ _] | Rest] ->
    (if (and (urdr.model.common.same? From LinkFrom)
             (urdr.model.common.same? To LinkTo))
        true
        (urdr.model.net.link-declared? From To Rest))
  From To _ -> false)

(define urdr.model.net.pending-of
  none Vocab Links -> (urdr.model.common.error "net-pending-shape")
  Items Vocab Links ->
    (urdr.model.net.pending-loop Vocab Links Items none []))

\\ ---------------------------------------------------------------
\\ Active policy composition
\\ ---------------------------------------------------------------

(define urdr.model.net.link-test
  [link From To Src Dst] ->
    [nk-seq
      [nk-test [symbol (urdr.model.net.n.src)] Src]
      [nk-test [symbol (urdr.model.net.n.dst)] Dst]])

(define urdr.model.net.topology
  [] -> [nk-drop]
  [Link] -> (urdr.model.net.link-test Link)
  [Link | Rest] ->
    [nk-union
      (urdr.model.net.link-test Link)
      (urdr.model.net.topology Rest)]
  _ -> [nk-drop])

(define urdr.model.net.mask-chain
  Vocab [] -> [ok [nk-id]]
  Vocab [[mask Id Kind Addresses] | Rest] ->
    (urdr.model.net.mask-chain-head
      (urdr.model.mask.term Kind Addresses) Vocab Rest)
  Vocab _ -> (urdr.model.common.error "net-masks-shape"))

(define urdr.model.net.mask-chain-head
  [error E] Vocab Rest -> [error E]
  [error E Detail] Vocab Rest -> [error E Detail]
  [ok Term] Vocab Rest ->
    (urdr.model.net.mask-chain-tail
      Term (urdr.model.net.mask-chain Vocab Rest)))

(define urdr.model.net.mask-chain-tail
  Term [error E] -> [error E]
  Term [error E Detail] -> [error E Detail]
  Term [ok Rest] -> [ok [nk-seq Term Rest]])

(define urdr.model.net.active
  Vocab Links Masks BaselineValue ->
    (urdr.model.net.active-baseline
      (urdr.netkat.term Vocab BaselineValue) Vocab Links Masks))

(define urdr.model.net.active-baseline
  [error E] Vocab Links Masks ->
    (urdr.model.common.netkat-error [error E])
  [ok Baseline] Vocab Links Masks ->
    (urdr.model.net.active-masks
      (urdr.model.net.mask-chain Vocab Masks) Vocab Links Baseline))

(define urdr.model.net.active-masks
  [error E] Vocab Links Baseline -> [error E]
  [error E Detail] Vocab Links Baseline -> [error E Detail]
  [ok Chain] Vocab Links Baseline ->
    (urdr.model.net.active-checked
      (urdr.netkat.term-check
        Vocab
        [nk-seq
          (urdr.model.net.topology Links)
          [nk-seq Chain Baseline]])))

(define urdr.model.net.active-checked
  [error E] -> (urdr.model.common.netkat-error [error E])
  [ok Term] -> [ok Term])

\\ ---------------------------------------------------------------
\\ Whole-state decoding
\\ ---------------------------------------------------------------

(define urdr.model.net.required-fields?
  Vocab ->
    (and (cons? (urdr.netkat.field-values
                  (urdr.netkat.vocab-fields Vocab)
                  (urdr.model.net.n.src)))
         (cons? (urdr.netkat.field-values
                  (urdr.netkat.vocab-fields Vocab)
                  (urdr.model.net.n.dst)))))

(define urdr.model.net.decode
  State ->
    (urdr.model.net.decode-vocab
      (urdr.netkat.vocabulary
        (urdr.model.common.get State (urdr.model.net.n.vocab)))
      State))

(define urdr.model.net.decode-vocab
  [error E] State -> (urdr.model.common.netkat-error [error E])
  [ok Vocab] State ->
    (if (not (urdr.model.net.required-fields? Vocab))
        (urdr.model.common.error "net-vocabulary-fields")
        (urdr.model.net.decode-links
          (urdr.model.net.links-of
            (urdr.model.common.items
              (urdr.model.common.get State (urdr.model.net.n.links))))
          Vocab
          State)))

(define urdr.model.net.decode-links
  [error E] Vocab State -> [error E]
  [error E Detail] Vocab State -> [error E Detail]
  [ok Links] Vocab State ->
    (urdr.model.net.decode-masks
      (urdr.model.net.masks-of
        (urdr.model.common.items
          (urdr.model.common.get State (urdr.model.net.n.masks))))
      Vocab
      Links
      State))

(define urdr.model.net.decode-masks
  [error E] Vocab Links State -> [error E]
  [error E Detail] Vocab Links State -> [error E Detail]
  [ok Masks] Vocab Links State ->
    (urdr.model.net.decode-pending
      (urdr.model.net.pending-of
        (urdr.model.common.items
          (urdr.model.common.get State (urdr.model.net.n.pending)))
        Vocab
        Links)
      Vocab
      Links
      Masks
      State))

(define urdr.model.net.decode-pending
  [error E] Vocab Links Masks State -> [error E]
  [error E Detail] Vocab Links Masks State -> [error E Detail]
  [ok Pending] Vocab Links Masks State ->
    (urdr.model.net.decode-active
      (urdr.model.net.active
        Vocab
        Links
        Masks
        (urdr.model.common.get State (urdr.model.net.n.baseline)))
      Vocab
      Links
      Masks
      Pending
      State))

(define urdr.model.net.decode-active
  [error E] Vocab Links Masks Pending State -> [error E]
  [error E Detail] Vocab Links Masks Pending State -> [error E Detail]
  [ok Active] Vocab Links Masks Pending State ->
    [ok [net
          Vocab
          Active
          Links
          Masks
          Pending
          (urdr.model.common.get State (urdr.model.net.n.vocab))
          (urdr.model.common.get State (urdr.model.net.n.baseline))]])

(define urdr.model.net.rebuild
  [net _ _ Links Masks Pending VocabValue BaselineValue] ->
    (urdr.model.net.state-value
      VocabValue BaselineValue Links Masks Pending))

\\ The public read model: the active policy of a state, as a validated
\\ term. The witness bridge and the auditor use the same function the step
\\ uses, so no second notion of "the policy in force" can exist.
(define urdr.model.net.active-policy
  State -> (urdr.model.net.active-policy-decoded
             (urdr.model.net.decode State)))

(define urdr.model.net.active-policy-decoded
  [error E] -> [error E]
  [error E Detail] -> [error E Detail]
  [ok [net _ Active _ _ _ _ _]] -> [ok Active])

(define urdr.model.net.vocabulary-of
  State -> (urdr.model.net.vocabulary-decoded
             (urdr.model.net.decode State)))

(define urdr.model.net.vocabulary-decoded
  [error E] -> [error E]
  [error E Detail] -> [error E Detail]
  [ok [net Vocab _ _ _ _ _ _]] -> [ok Vocab])

(define urdr.model.net.links-list
  State -> (urdr.model.net.links-decoded (urdr.model.net.decode State)))

(define urdr.model.net.links-decoded
  [error E] -> [error E]
  [error E Detail] -> [error E Detail]
  [ok [net _ _ Links _ _ _ _]] -> [ok Links])

\\ ---------------------------------------------------------------
\\ Facts
\\ ---------------------------------------------------------------

(define urdr.model.net.transfer-value
  Packet From To ->
    [record
      [[(urdr.model.net.n.packet) Packet]
       [(urdr.model.net.n.via) (urdr.model.net.via-value From To)]]])

(define urdr.model.net.delivered-value
  Out Sent From To ->
    [record
      [[(urdr.model.net.n.packet) Out]
       [(urdr.model.net.n.sent) Sent]
       [(urdr.model.net.n.via) (urdr.model.net.via-value From To)]]])

(define urdr.model.net.delivered-facts
  [] Sent From To -> []
  [Out | Rest] Sent From To ->
    [[fact (urdr.model.net.n.delivered)
       (urdr.model.net.delivered-value Out Sent From To)] |
     (urdr.model.net.delivered-facts Rest Sent From To)])

(define urdr.model.net.identity-value
  Id -> [record [[(urdr.model.net.n.id) [symbol Id]]]])

\\ ---------------------------------------------------------------
\\ Choices: every pending packet, three actions, canonical order.
\\ ---------------------------------------------------------------

(define urdr.model.net.alternative
  Action Index From To ->
    [record
      [[(urdr.model.net.n.action) [symbol Action]]
       [(urdr.model.net.n.index) (urdr.model.common.big Index)]
       [(urdr.model.net.n.via) (urdr.model.net.via-value From To)]]])

(define urdr.model.net.queue-alternatives
  [] Index From To Acc -> Acc
  [_ | Rest] Index From To Acc ->
    (urdr.model.net.queue-alternatives
      Rest
      (+ Index 1)
      From
      To
      [(urdr.model.net.alternative
         (urdr.model.net.n.deliver) Index From To)
       (urdr.model.net.alternative
         (urdr.model.net.n.drop) Index From To)
       (urdr.model.net.alternative
         (urdr.model.net.n.duplicate) Index From To)
       | Acc])
  _ Index From To Acc -> Acc)

(define urdr.model.net.alternatives
  [] Acc -> Acc
  [[queue From To Packets] | Rest] Acc ->
    (urdr.model.net.alternatives
      Rest
      (urdr.model.net.queue-alternatives Packets 0 From To Acc))
  _ Acc -> Acc)

(define urdr.model.net.choices
  Pending ->
    (urdr.model.common.choice
      (urdr.model.net.n.delivery)
      (urdr.model.net.alternatives Pending [])))

\\ ---------------------------------------------------------------
\\ Denotation audit. The step calls this on its own output, so an
\\ out-of-denotation delivery is not merely unreachable by construction:
\\ it is refused at run time with a stable code.
\\ ---------------------------------------------------------------

(define urdr.model.net.member-packet?
  Packet [] -> false
  Packet [Q | Qs] ->
    (if (= (urdr.netkat.packet-compare Packet Q) eq)
        true
        (urdr.model.net.member-packet? Packet Qs))
  Packet _ -> false)

(define urdr.model.net.audit-outputs
  [] Permitted -> [ok]
  [Out | Rest] Permitted ->
    (if (urdr.model.net.member-packet? Out Permitted)
        (urdr.model.net.audit-outputs Rest Permitted)
        (urdr.model.common.error "net-denotation-violation"))
  _ Permitted -> (urdr.model.common.error "net-denotation-violation"))

\\ Auditor over emitted facts: every `delivered` fact must name a packet
\\ inside the denotation of the active policy applied to the packet the
\\ same fact records as sent.
(define urdr.model.net.audit-facts
  Active [] -> [ok]
  Active [[fact Name Value] | Rest] ->
    (if (urdr.model.common.same? Name (urdr.model.net.n.delivered))
        (urdr.model.net.audit-fact Active Value Rest)
        (urdr.model.net.audit-facts Active Rest))
  Active _ -> (urdr.model.common.error "net-denotation-violation"))

(define urdr.model.net.audit-fact
  Active Value Rest ->
    (urdr.model.net.audit-fact-parts
      (urdr.model.common.get Value (urdr.model.net.n.packet))
      (urdr.model.common.get Value (urdr.model.net.n.sent))
      Active
      Rest))

(define urdr.model.net.audit-fact-parts
  none Sent Active Rest ->
    (urdr.model.common.error "net-denotation-violation")
  Out none Active Rest ->
    (urdr.model.common.error "net-denotation-violation")
  Out Sent Active Rest ->
    (if (urdr.model.net.member-packet?
          Out (urdr.netkat.eval Active Sent))
        (urdr.model.net.audit-facts Active Rest)
        (urdr.model.common.error "net-denotation-violation")))

\\ ---------------------------------------------------------------
\\ Queue operations
\\ ---------------------------------------------------------------

(define urdr.model.net.queue-find
  From To [] -> none
  From To [[queue QFrom QTo Packets] | Rest] ->
    (if (and (urdr.model.common.same? From QFrom)
             (urdr.model.common.same? To QTo))
        [queue QFrom QTo Packets]
        (urdr.model.net.queue-find From To Rest))
  From To _ -> none)

\\ Queues stay in ascending (from, to) order; an empty queue is dropped so
\\ that a quiescent network has one canonical state.
(define urdr.model.net.queue-put
  [queue From To []] [] -> []
  [queue From To Packets] [] -> [[queue From To Packets]]
  [queue From To Packets] [Head | Rest] ->
    (let Order
      (urdr.model.net.endpoint-compare [queue From To Packets] Head)
      (if (= Order lt)
          (urdr.model.net.queue-cons
            [queue From To Packets] [Head | Rest])
          (if (= Order eq)
              (urdr.model.net.queue-cons
                [queue From To Packets] Rest)
              [Head | (urdr.model.net.queue-put
                        [queue From To Packets] Rest)]))))

(define urdr.model.net.queue-cons
  [queue From To []] Rest -> Rest
  Queue Rest -> [Queue | Rest])

\\ ---------------------------------------------------------------
\\ send
\\ ---------------------------------------------------------------

(define urdr.model.net.send
  Decoded Input ->
    (urdr.model.net.send-via
      (urdr.model.net.via-of
        (urdr.model.common.get Input (urdr.model.net.n.via)))
      (urdr.model.common.get Input (urdr.model.net.n.packet))
      Decoded))

(define urdr.model.net.send-via
  none PacketValue Decoded ->
    (urdr.model.common.error "net-input-shape")
  Via none Decoded -> (urdr.model.common.error "net-input-shape")
  [via From To] PacketValue [net Vocab Active Links Masks Pending VV BV] ->
    (if (not (urdr.model.net.link-declared? From To Links))
        (urdr.model.common.error "net-unknown-link")
        (urdr.model.net.send-packet
          (urdr.netkat.packet Vocab PacketValue)
          From
          To
          [net Vocab Active Links Masks Pending VV BV])))

(define urdr.model.net.send-packet
  [error E] From To Decoded -> (urdr.model.common.netkat-error [error E])
  [ok Packet] From To [net Vocab Active Links Masks Pending VV BV] ->
    (let Existing (urdr.model.net.queue-find From To Pending)
         Items (urdr.model.net.queue-items Existing)
         Next (urdr.model.net.queue-put
                [queue From To
                  (urdr.model.common.append Items [Packet])]
                Pending)
      [step
        (urdr.model.net.state-value VV BV Links Masks Next)
        [[fact (urdr.model.net.n.queued)
           (urdr.model.net.transfer-value Packet From To)]]
        (urdr.model.net.choices Next)]))

(define urdr.model.net.queue-items
  none -> []
  [queue _ _ Packets] -> Packets)

\\ ---------------------------------------------------------------
\\ deliver
\\ ---------------------------------------------------------------

(define urdr.model.net.deliver
  Decoded Input ->
    (urdr.model.net.deliver-selection
      (urdr.model.common.get Input (urdr.model.net.n.selection))
      Decoded))

(define urdr.model.net.deliver-selection
  none Decoded -> (urdr.model.common.error "net-input-shape")
  Selection Decoded ->
    (urdr.model.net.deliver-parts
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get Selection (urdr.model.net.n.action)))
      (urdr.model.net.via-of
        (urdr.model.common.get Selection (urdr.model.net.n.via)))
      (urdr.model.common.get Selection (urdr.model.net.n.index))
      Decoded))

(define urdr.model.net.deliver-parts
  none Via IndexValue Decoded ->
    (urdr.model.common.error "net-input-shape")
  Action none IndexValue Decoded ->
    (urdr.model.common.error "net-input-shape")
  Action [via From To] IndexValue
  [net Vocab Active Links Masks Pending VV BV] ->
    (urdr.model.net.deliver-queue
      (urdr.model.net.queue-find From To Pending)
      Action
      IndexValue
      [net Vocab Active Links Masks Pending VV BV]))

(define urdr.model.net.deliver-queue
  none Action IndexValue Decoded ->
    (urdr.model.common.error "net-unknown-link")
  [queue From To Packets] Action IndexValue Decoded ->
    (urdr.model.net.deliver-index
      (urdr.model.common.index
        IndexValue (urdr.model.common.count Packets 0))
      Action
      [queue From To Packets]
      Decoded))

(define urdr.model.net.deliver-index
  none Action Queue Decoded ->
    (urdr.model.common.error "net-index-range")
  Index Action [queue From To Packets] Decoded ->
    (urdr.model.net.deliver-action
      Action
      Index
      (urdr.model.common.nth Packets Index)
      [queue From To Packets]
      Decoded))

(define urdr.model.net.deliver-action
  Action Index Packet [queue From To Packets]
  [net Vocab Active Links Masks Pending VV BV] ->
    (if (urdr.model.common.same? Action (urdr.model.net.n.drop))
        (urdr.model.net.dequeued
          [queue From To (urdr.model.common.without Packets Index [])]
          [[fact (urdr.model.net.n.dropped)
             (urdr.model.net.transfer-value Packet From To)]]
          [net Vocab Active Links Masks Pending VV BV])
        (if (urdr.model.common.same? Action (urdr.model.net.n.deliver))
            (urdr.model.net.forward
              Packet
              [queue From To
                (urdr.model.common.without Packets Index [])]
              [net Vocab Active Links Masks Pending VV BV])
            (if (urdr.model.common.same?
                  Action (urdr.model.net.n.duplicate))
                (urdr.model.net.forward
                  Packet
                  [queue From To Packets]
                  [net Vocab Active Links Masks Pending VV BV])
                (urdr.model.common.error "net-unknown-action")))))

(define urdr.model.net.dequeued
  Queue Facts [net Vocab Active Links Masks Pending VV BV] ->
    (let Next (urdr.model.net.queue-put Queue Pending)
      [step
        (urdr.model.net.state-value VV BV Links Masks Next)
        Facts
        (urdr.model.net.choices Next)]))

\\ The one and only producer of `delivered` facts: the denotation of the
\\ active policy applied to the packet that was actually sent. An empty
\\ denotation is reported as `blocked`, never as silence.
(define urdr.model.net.forward
  Packet [queue From To Rest] Decoded ->
    (urdr.model.net.forward-outputs
      (urdr.model.net.outputs Packet Decoded)
      Packet
      [queue From To Rest]
      Decoded))

(define urdr.model.net.outputs
  Packet [net Vocab Active Links Masks Pending VV BV] ->
    (urdr.netkat.eval Active Packet))

(define urdr.model.net.forward-outputs
  [] Packet [queue From To Rest] Decoded ->
    (urdr.model.net.dequeued
      [queue From To Rest]
      [[fact (urdr.model.net.n.blocked)
         (urdr.model.net.transfer-value Packet From To)]]
      Decoded)
  Outputs Packet [queue From To Rest]
  [net Vocab Active Links Masks Pending VV BV] ->
    (urdr.model.net.forward-audited
      (urdr.model.net.audit-outputs
        Outputs (urdr.netkat.eval Active Packet))
      (urdr.model.net.delivered-facts Outputs Packet From To)
      [queue From To Rest]
      [net Vocab Active Links Masks Pending VV BV]))

(define urdr.model.net.forward-audited
  [error E] Facts Queue Decoded -> [error E]
  [error E Detail] Facts Queue Decoded -> [error E Detail]
  [ok] Facts Queue Decoded ->
    (urdr.model.net.dequeued Queue Facts Decoded))

\\ ---------------------------------------------------------------
\\ mask / unmask: the fault model's policy transformations
\\ ---------------------------------------------------------------

(define urdr.model.net.mask-insert
  Mask [] -> [ok [Mask]]
  [mask Id Kind Addresses] [[mask MId MKind MAddresses] | Rest] ->
    (let Order (urdr.canonical.bytes-compare Id MId)
      (if (= Order lt)
          [ok [[mask Id Kind Addresses]
               [mask MId MKind MAddresses] | Rest]]
          (if (= Order eq)
              (urdr.model.common.error "net-mask-duplicate")
              (urdr.model.net.mask-insert-tail
                [mask MId MKind MAddresses]
                (urdr.model.net.mask-insert
                  [mask Id Kind Addresses] Rest))))))

(define urdr.model.net.mask-insert-tail
  Head [error E] -> [error E]
  Head [error E Detail] -> [error E Detail]
  Head [ok Rest] -> [ok [Head | Rest]])

(define urdr.model.net.mask-remove
  Id [] Acc -> (urdr.model.common.error "net-mask-unknown")
  Id [[mask MId MKind MAddresses] | Rest] Acc ->
    (if (urdr.model.common.same? Id MId)
        [ok (urdr.model.common.append
              (urdr.model.common.rev Acc) Rest)]
        (urdr.model.net.mask-remove
          Id Rest [[mask MId MKind MAddresses] | Acc]))
  Id _ Acc -> (urdr.model.common.error "net-masks-shape"))

\\ The mask input carries the fault model's descriptor verbatim: the
\\ network re-reads it with the same urdr.model.mask.of the fault model's
\\ own state uses, so nothing between the two can reinterpret it.
(define urdr.model.net.mask
  Decoded Input ->
    (urdr.model.net.mask-checked (urdr.model.mask.of Input) Decoded))

(define urdr.model.net.mask-checked
  [error E] Decoded -> [error E]
  [error E Detail] Decoded -> [error E Detail]
  [ok [mask Id Kind Addresses]]
  [net Vocab Active Links Masks Pending VV BV] ->
    (urdr.model.net.mask-inserted
      (urdr.model.net.mask-insert [mask Id Kind Addresses] Masks)
      Id
      [net Vocab Active Links Masks Pending VV BV]))

\\ The composed policy is revalidated before the new state is returned, so
\\ a mask that would push the composition past the NetKAT resource profile
\\ is refused at activation with the algebra's own code.
(define urdr.model.net.mask-inserted
  [error E] Id Decoded -> [error E]
  [error E Detail] Id Decoded -> [error E Detail]
  [ok Next] Id [net Vocab Active Links Masks Pending VV BV] ->
    (urdr.model.net.mask-composed
      (urdr.model.net.active Vocab Links Next BV)
      (urdr.model.net.n.masked)
      Id
      Next
      [net Vocab Active Links Masks Pending VV BV]))

(define urdr.model.net.mask-composed
  [error E] Name Id Next Decoded -> [error E]
  [error E Detail] Name Id Next Decoded -> [error E Detail]
  [ok _] Name Id Next [net Vocab Active Links Masks Pending VV BV] ->
    [step
      (urdr.model.net.state-value VV BV Links Next Pending)
      [[fact Name (urdr.model.net.identity-value Id)]]
      (urdr.model.net.choices Pending)])

(define urdr.model.net.unmask
  Decoded Input ->
    (urdr.model.net.unmask-id
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get Input (urdr.model.net.n.id)))
      Decoded))

(define urdr.model.net.unmask-id
  none Decoded -> (urdr.model.common.error "net-input-shape")
  Id [net Vocab Active Links Masks Pending VV BV] ->
    (urdr.model.net.unmask-removed
      (urdr.model.net.mask-remove Id Masks [])
      Id
      [net Vocab Active Links Masks Pending VV BV]))

(define urdr.model.net.unmask-removed
  [error E] Id Decoded -> [error E]
  [error E Detail] Id Decoded -> [error E Detail]
  [ok Next] Id [net Vocab Active Links Masks Pending VV BV] ->
    (urdr.model.net.mask-composed
      (urdr.model.net.active Vocab Links Next BV)
      (urdr.model.net.n.unmasked)
      Id
      Next
      [net Vocab Active Links Masks Pending VV BV]))

\\ ---------------------------------------------------------------
\\ poll: publish the current alternatives without changing anything
\\ ---------------------------------------------------------------

(define urdr.model.net.poll
  [net Vocab Active Links Masks Pending VV BV] ->
    [step
      (urdr.model.net.state-value VV BV Links Masks Pending)
      []
      (urdr.model.net.choices Pending)])

\\ ---------------------------------------------------------------
\\ The component-step entry point
\\ ---------------------------------------------------------------

(define urdr.model.net.step
  State Event ->
    (urdr.model.net.step-decoded
      (urdr.model.net.decode State)
      (urdr.model.common.event-input Event)))

(define urdr.model.net.step-decoded
  [error E] Input -> [error E]
  [error E Detail] Input -> [error E Detail]
  [ok Decoded] none -> (urdr.model.common.error "net-input-shape")
  [ok Decoded] Input ->
    (urdr.model.net.dispatch
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get Input (urdr.model.net.n.kind)))
      Decoded
      Input))

(define urdr.model.net.dispatch
  none Decoded Input -> (urdr.model.common.error "net-input-shape")
  Kind Decoded Input ->
    (if (urdr.model.common.same? Kind (urdr.model.net.n.send))
        (urdr.model.net.send Decoded Input)
        (if (urdr.model.common.same? Kind (urdr.model.net.n.deliver))
            (urdr.model.net.deliver Decoded Input)
            (if (urdr.model.common.same? Kind (urdr.model.net.n.mask))
                (urdr.model.net.mask Decoded Input)
                (if (urdr.model.common.same?
                      Kind (urdr.model.net.n.unmask))
                    (urdr.model.net.unmask Decoded Input)
                    (if (urdr.model.common.same?
                          Kind (urdr.model.net.n.poll))
                        (urdr.model.net.poll Decoded)
                        (urdr.model.common.error
                          "net-unknown-input")))))))

\\ ---------------------------------------------------------------
\\ Input construction, shared with the witness bridge and the tests
\\ ---------------------------------------------------------------

(define urdr.model.net.send-input
  Packet From To ->
    [record
      [[(urdr.model.net.n.kind) [symbol (urdr.model.net.n.send)]]
       [(urdr.model.net.n.packet) Packet]
       [(urdr.model.net.n.via) (urdr.model.net.via-value From To)]]])

(define urdr.model.net.deliver-input
  Action Index From To ->
    [record
      [[(urdr.model.net.n.kind) [symbol (urdr.model.net.n.deliver)]]
       [(urdr.model.net.n.selection)
        (urdr.model.net.alternative Action Index From To)]]])

(define urdr.model.net.mask-input
  Id Kind Addresses ->
    [record
      [[(urdr.model.mask.n.fault) [symbol Kind]]
       [(urdr.model.net.n.id) [symbol Id]]
       [(urdr.model.net.n.kind) [symbol (urdr.model.net.n.mask)]]
       [(urdr.model.mask.n.members) [list Addresses]]]])

(define urdr.model.net.unmask-input
  Id ->
    [record
      [[(urdr.model.net.n.id) [symbol Id]]
       [(urdr.model.net.n.kind) [symbol (urdr.model.net.n.unmask)]]]])

(define urdr.model.net.poll-input
  -> [record
       [[(urdr.model.net.n.kind) [symbol (urdr.model.net.n.poll)]]]])
