\* Named reachability masks (plan Wave C, ADR 0004 Decision 2).

Requires shen/protocol/canonical.shen, shen/world/integer.shen,
shen/world/netkat.shen, and shen/world/models/common.shen to be loaded by
the caller.

ADR 0004 Decision 2 says partitions and reachability faults are
"expressed as named policy transformations selected by the fault model,
so the symbolic and executed views cannot drift". This module is that
naming. A mask is a canonical descriptor

  [record [[fault   [symbol KIND]]
           [id      [symbol MASK-ID]]
           [members [list ADDRESS ...]]]]

and urdr.model.mask.term is the single function that turns one into a
NetKAT predicate. The fault model emits descriptors; the network model
composes the terms derived from them. Neither holds a private copy of
what a partition means, and there is exactly one definition to review.

Why a descriptor and not the term itself: a component state is one ADR
0002 canonical value under the M0 resource profile (256 parsed nodes). A
partition term for a single member costs on the order of 130 parsed
nodes once canonically tagged, so a network state carrying two masks and
a queued packet cannot be encoded at all. The descriptor costs about
fifteen. The kinds are the scenario DSL's own pinned reachability faults
{delay, drop, partition}, so nothing expressible is lost; a general
term-valued mask would need a larger canonical profile than M1 has
accepted (see ADR 0005, which raises limits for scenario and compiled
policy surfaces but not for component states).

Term derivations, with IN(f) the union of nk-test f = a over the member
addresses a in ascending order (nk-drop when there are none, and no unit
term when there is at least one):

  partition  nk-neg( IN(src);nk-neg(IN(dst))  +  nk-neg(IN(src));IN(dst) )
             every packet that crosses the domain boundary in either
             direction is denied; traffic wholly inside or wholly
             outside is untouched.
  drop       nk-neg( IN(src) + IN(dst) )
             the members are cut off in both directions.
  delay      nk-id
             reachability-neutral. Delay changes when a packet is
             delivered, and delivery order is a world-kernel choice
             (SPEC.md 12.1), surfaced by the network model's delivery
             alternatives and the timer model's deadlines. Keeping it in
             the mask vocabulary makes the composition uniform without
             giving the fault model ordering authority.

Sequencing predicates is their conjunction, so masks intersect and the
order in which they were activated cannot change the composed policy. *\

(define urdr.model.mask.n.delay
  -> (urdr.canonical.string-bytes "delay"))

(define urdr.model.mask.n.drop
  -> (urdr.canonical.string-bytes "drop"))

(define urdr.model.mask.n.dst
  -> (urdr.canonical.string-bytes "dst"))

(define urdr.model.mask.n.fault
  -> (urdr.canonical.string-bytes "fault"))

(define urdr.model.mask.n.id
  -> (urdr.canonical.string-bytes "id"))

(define urdr.model.mask.n.members
  -> (urdr.canonical.string-bytes "members"))

(define urdr.model.mask.n.partition
  -> (urdr.canonical.string-bytes "partition"))

(define urdr.model.mask.n.src
  -> (urdr.canonical.string-bytes "src"))

\\ ---------------------------------------------------------------
\\ Term derivation
\\ ---------------------------------------------------------------

(define urdr.model.mask.in-set
  Field [] -> [nk-drop]
  Field [Address] -> [nk-test [symbol Field] Address]
  Field [Address | Rest] ->
    [nk-union
      [nk-test [symbol Field] Address]
      (urdr.model.mask.in-set Field Rest)]
  Field _ -> [nk-drop])

(define urdr.model.mask.partition-term
  Addresses ->
    (let Src (urdr.model.mask.in-set (urdr.model.mask.n.src) Addresses)
         Dst (urdr.model.mask.in-set (urdr.model.mask.n.dst) Addresses)
      [nk-neg
        [nk-union
          [nk-seq Src [nk-neg Dst]]
          [nk-seq [nk-neg Src] Dst]]]))

(define urdr.model.mask.drop-term
  Addresses ->
    [nk-neg
      [nk-union
        (urdr.model.mask.in-set (urdr.model.mask.n.src) Addresses)
        (urdr.model.mask.in-set (urdr.model.mask.n.dst) Addresses)]])

(define urdr.model.mask.reachability?
  Kind ->
    (or (urdr.model.common.same? Kind (urdr.model.mask.n.partition))
        (or (urdr.model.common.same? Kind (urdr.model.mask.n.drop))
            (urdr.model.common.same? Kind (urdr.model.mask.n.delay)))))

(define urdr.model.mask.term
  Kind Addresses ->
    (if (urdr.model.common.same? Kind (urdr.model.mask.n.partition))
        [ok (urdr.model.mask.partition-term Addresses)]
        (if (urdr.model.common.same? Kind (urdr.model.mask.n.drop))
            [ok (urdr.model.mask.drop-term Addresses)]
            (if (urdr.model.common.same? Kind (urdr.model.mask.n.delay))
                [ok [nk-id]]
                (urdr.model.common.error "mask-kind-unknown")))))

\\ ---------------------------------------------------------------
\\ Descriptor value
\\ ---------------------------------------------------------------

(define urdr.model.mask.value
  Id Kind Addresses ->
    [record
      [[(urdr.model.mask.n.fault) [symbol Kind]]
       [(urdr.model.mask.n.id) [symbol Id]]
       [(urdr.model.mask.n.members) [list Addresses]]]])

(define urdr.model.mask.addresses
  [] Acc -> [ok (urdr.model.common.rev Acc)]
  [Value | Rest] Acc ->
    (urdr.model.mask.addresses-step
      (urdr.model.common.integer Value) Rest Acc)
  _ Acc -> (urdr.model.common.error "mask-members-shape"))

(define urdr.model.mask.addresses-step
  none Rest Acc -> (urdr.model.common.error "mask-member-integer")
  Address Rest Acc -> (urdr.model.mask.addresses Rest [Address | Acc]))

(define urdr.model.mask.of
  Value ->
    (urdr.model.mask.parts
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get Value (urdr.model.mask.n.id)))
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get Value (urdr.model.mask.n.fault)))
      (urdr.model.common.items
        (urdr.model.common.get Value (urdr.model.mask.n.members)))))

(define urdr.model.mask.parts
  none Kind Items -> (urdr.model.common.error "mask-shape")
  Id none Items -> (urdr.model.common.error "mask-shape")
  Id Kind none -> (urdr.model.common.error "mask-shape")
  Id Kind Items ->
    (if (not (urdr.model.mask.reachability? Kind))
        (urdr.model.common.error "mask-kind-unknown")
        (urdr.model.mask.assembled
          Id Kind (urdr.model.mask.addresses Items []))))

(define urdr.model.mask.assembled
  Id Kind [error E] -> [error E]
  Id Kind [error E Detail] -> [error E Detail]
  Id Kind [ok Addresses] -> [ok [mask Id Kind Addresses]])
