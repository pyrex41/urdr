\* Search strategies (SPEC.md 17, M1 plan Wave F).

Requires shen/protocol/canonical.shen, shen/world/integer.shen,
shen/world/prng.shen, shen/world/component.shen, shen/world/world.shen,
shen/world/eventlog.shen, and shen/search/choice.shen to be loaded by
the caller.

Pure: no I/O, no host time, no host randomness, no floating point, no
defprolog. Every draw goes through ADR 0003 bounded sampling on a named
stream the caller supplies; this module owns no stream, allocates no
counter, and has no other source of entropy.

NOT owned here (docs/module-boundaries.md): ambient randomness, and the
meaning of any alternative. A strategy reads an alternative's SHAPE to
decide how interesting it is; it never asks a model what the alternative
means, and it never rejects one it does not recognise.

=====================================================================
1. The interface
=====================================================================

A strategy is a pure function

  (choice-context, stream-state) -> (selection, reason, stream-state')

spelled

  urdr.search.strategy.select STRATEGY CONTEXT STREAM
    -> [ok [selection SELECTED REASON STREAM' COORDINATES]]
     | [error CODE DETAIL]

  CONTEXT ::= [choice-context ACTOR KIND TIME [ALTERNATIVE ...]]

COORDINATES is the coordinate list ADR 0003 bounded sampling produced,
including every rejected block, so the selection carries its own
evidence into the choice record (choice.shen section 3).

A strategy is a VALUE, not a function symbol or a lambda:

  STRATEGY ::= [strategy NAME [[weight CLASS WEIGHT] ...]]

Two reasons. First, a strategy has to be describable: SPEC.md 4 makes
the run id a function of the run's declared inputs, and a search
whose policy is an anonymous closure cannot be pinned by anything.
urdr.search.strategy.descriptor-value renders the value canonically, so
the weights that steered a search are part of the artifact rather than
part of the binary. Second, dispatching on a name keeps the closed set of
strategies visible in one place; adding one is a diff here, in the open.

=====================================================================
2. baseline-random
=====================================================================

Uniform, bias-free selection over the alternative count:

  index = urdr.prng.sample(STREAM, |ALTERNATIVES|)

ADR 0003's sampler rejects the biased tail of the block space and redraws
at the next block index, so the distribution is exactly uniform and each
rejection is recorded rather than hidden. Reason `uniform`.

=====================================================================
3. boundary-biased
=====================================================================

SPEC.md 17 asks the initial strategy to bias toward boundary timing
conditions, packet reorderings, retry and timeout edges, and process and
node failures. The bias is expressed as explicit integer WEIGHTS over a
closed set of alternative CLASSES, and selection is bias-free bounded
sampling over the weight sum:

  total = sum of the per-alternative weights, in alternative order
  x     = urdr.prng.sample(STREAM, total)
  index = the least i with x < weight(0) + ... + weight(i)

which selects alternative i with probability weight(i)/total exactly.
Reason `weighted`.

The five classes and their default weights:

  fault-activation  4   a fault being turned on (SPEC.md 17: process and
                        node failures)
  ordinary          1   everything else, including everything this
                        module does not recognise
  reorder           3   a packet delivered out of queue order, or
                        duplicated
  retry-edge        3   a packet dropped, which is what forces a retry or
                        a timeout to be exercised at all
  timing-edge       4   a deadline fired at exactly its deadline, or a
                        delay at an extreme of the offered range

Weights are positive software integers and are part of the canonical
descriptor, so `boundary-biased with these weights` is reproducible and
`boundary-biased with different weights` is a different, distinguishable
search. urdr.search.strategy.boundary-with builds a strategy with a
caller's table.

CLASSIFICATION. The classifier reads the choice kind and the shape of
the alternative. It is a structural reading, in the same spirit as
certificate.shen consuming verdict records: no code here calls into
shen/world/models/, and a shape this table does not list is `ordinary`,
never an error. A new model whose alternatives are unrecognised is
therefore searched WITHOUT bias rather than searched wrongly.

  KIND            ALTERNATIVE                            CLASS
  --------------  -------------------------------------  ----------------
  timer-fire      due = the choice's logical time        timing-edge
  timer-fire      any other due                          ordinary
  delivery        action deliver, index 0                ordinary
  delivery        action deliver, index above 0          reorder
  delivery        action duplicate                       reorder
  delivery        action drop                            retry-edge
  fault-action    operation activate                     fault-activation
  fault-action    operation deactivate                   ordinary
  schedule-delay  the least or the greatest offered      timing-edge
  schedule-delay  any other offered delay                ordinary
  anything else   anything                               ordinary

`timer-fire` at exactly the deadline is the boundary timing condition of
SPEC.md 17 and of the plan's Wave D boundary fixtures: the deadline that
is met exactly is the case that separates `<=` from `<`.

`schedule-delay` is the exploration driver's own choice of how far ahead
of now to schedule a selected input (explore.shen section 3). Its
alternatives ARE the declared delay ladder, so the boundary of the
declared range is readable from the choice itself and needs no extra
input: the least and the greatest offered delay are the two edges, and
everything between them is interior. A ladder with one rung is entirely
boundary, which is correct and also irrelevant, because a choice with one
alternative is forced.

=====================================================================
4. Forced choices
=====================================================================

A choice offering exactly one alternative is `forced` under BOTH
strategies and is sampled with bound 1 under both, so the two strategies
consume a named stream identically wherever there is nothing to decide
and diverge only where there is. Drawing at all on a forced choice is
deliberate: see choice.shen section 4.

=====================================================================
5. Public entry points
=====================================================================

  baseline           -> STRATEGY
  boundary           -> STRATEGY
  boundary-with      [[weight CLASS WEIGHT] ...]
                       -> [ok STRATEGY] | [error CODE DETAIL]
  default-weights    -> [[weight CLASS WEIGHT] ...]
  check              STRATEGY -> [ok] | [error CODE DETAIL]
  name               STRATEGY -> OCTETS
  weights            STRATEGY -> [[weight CLASS WEIGHT] ...]
  descriptor-value   STRATEGY -> canonical record
  context            ACTOR KIND TIME ALTERNATIVES -> CONTEXT
  classify           KIND TIME ALTERNATIVES ALTERNATIVE -> CLASS OCTETS
  select             STRATEGY CONTEXT STREAM
                       -> [ok [selection SELECTED REASON STREAM'
                               COORDINATES]]
                        | [error CODE DETAIL]
  error-value        CODE DETAIL -> canonical record
  code-octets        CODE -> OCTETS *\

\\ ---------------------------------------------------------------
\\ ASCII names (k- keys, w- words, c- error codes).
\\ ---------------------------------------------------------------

(define urdr.search.strategy.n
  k-class -> (urdr.canonical.string-bytes "class")
  k-code -> (urdr.canonical.string-bytes "code")
  k-detail -> (urdr.canonical.string-bytes "detail")
  k-name -> (urdr.canonical.string-bytes "name")
  k-weight -> (urdr.canonical.string-bytes "weight")
  k-weights -> (urdr.canonical.string-bytes "weights")
  w-baseline -> (urdr.canonical.string-bytes "baseline-random")
  w-boundary -> (urdr.canonical.string-bytes "boundary-biased")
  c-fault-activation ->
    (urdr.canonical.string-bytes "fault-activation")
  c-ordinary -> (urdr.canonical.string-bytes "ordinary")
  c-reorder -> (urdr.canonical.string-bytes "reorder")
  c-retry-edge -> (urdr.canonical.string-bytes "retry-edge")
  c-timing-edge -> (urdr.canonical.string-bytes "timing-edge")
  a-action -> (urdr.canonical.string-bytes "action")
  a-activate -> (urdr.canonical.string-bytes "activate")
  a-deliver -> (urdr.canonical.string-bytes "deliver")
  a-delivery -> (urdr.canonical.string-bytes "delivery")
  a-drop -> (urdr.canonical.string-bytes "drop")
  a-due -> (urdr.canonical.string-bytes "due")
  a-duplicate -> (urdr.canonical.string-bytes "duplicate")
  a-fault-action -> (urdr.canonical.string-bytes "fault-action")
  a-index -> (urdr.canonical.string-bytes "index")
  a-operation -> (urdr.canonical.string-bytes "operation")
  a-schedule-delay -> (urdr.canonical.string-bytes "schedule-delay")
  a-timer-fire -> (urdr.canonical.string-bytes "timer-fire")
  e-shape -> (urdr.canonical.string-bytes "search-strategy-shape")
  e-name -> (urdr.canonical.string-bytes "search-strategy-name")
  e-weights -> (urdr.canonical.string-bytes "search-strategy-weights")
  e-weight -> (urdr.canonical.string-bytes "search-strategy-weight")
  e-context -> (urdr.canonical.string-bytes "search-strategy-context")
  e-sample -> (urdr.canonical.string-bytes "search-strategy-sample")
  e-unmapped -> (urdr.canonical.string-bytes "search-unmapped-code"))

(define urdr.search.strategy.code-octets
  search-strategy-shape -> (urdr.search.strategy.n e-shape)
  search-strategy-name -> (urdr.search.strategy.n e-name)
  search-strategy-weights -> (urdr.search.strategy.n e-weights)
  search-strategy-weight -> (urdr.search.strategy.n e-weight)
  search-strategy-context -> (urdr.search.strategy.n e-context)
  search-strategy-sample -> (urdr.search.strategy.n e-sample)
  _ -> (urdr.search.strategy.n e-unmapped))

(define urdr.search.strategy.error-value
  Code Detail ->
    [record
      [[(urdr.search.strategy.n k-code)
        [symbol (urdr.search.strategy.code-octets Code)]]
       [(urdr.search.strategy.n k-detail) Detail]]])

\\ ---------------------------------------------------------------
\\ Classes, in ascending unsigned-ASCII order
\\ ---------------------------------------------------------------

(define urdr.search.strategy.classes
  -> [(urdr.search.strategy.n c-fault-activation)
      (urdr.search.strategy.n c-ordinary)
      (urdr.search.strategy.n c-reorder)
      (urdr.search.strategy.n c-retry-edge)
      (urdr.search.strategy.n c-timing-edge)])

(define urdr.search.strategy.big
  N -> (urdr.int.raw.from-small N))

(define urdr.search.strategy.default-weights
  -> [[weight (urdr.search.strategy.n c-fault-activation)
        (urdr.search.strategy.big 4)]
      [weight (urdr.search.strategy.n c-ordinary)
        (urdr.search.strategy.big 1)]
      [weight (urdr.search.strategy.n c-reorder)
        (urdr.search.strategy.big 3)]
      [weight (urdr.search.strategy.n c-retry-edge)
        (urdr.search.strategy.big 3)]
      [weight (urdr.search.strategy.n c-timing-edge)
        (urdr.search.strategy.big 4)]])

\\ ---------------------------------------------------------------
\\ Construction and validation
\\ ---------------------------------------------------------------

(define urdr.search.strategy.baseline
  -> [strategy (urdr.search.strategy.n w-baseline) []])

(define urdr.search.strategy.boundary
  -> [strategy (urdr.search.strategy.n w-boundary)
       (urdr.search.strategy.default-weights)])

(define urdr.search.strategy.boundary-with
  Weights ->
    (urdr.search.strategy.boundary-checked
      (urdr.search.strategy.check-weights
        Weights (urdr.search.strategy.classes))
      Weights))

(define urdr.search.strategy.boundary-checked
  [error Code Detail] _ -> [error Code Detail]
  [ok] Weights ->
    [ok [strategy (urdr.search.strategy.n w-boundary) Weights]])

\\ The table must cover exactly the five classes, in class order, with a
\\ positive software integer each. A partial table would leave an
\\ alternative class with no declared weight, and a search cannot fall
\\ back on an undeclared number.
(define urdr.search.strategy.check-weights
  [] [] -> [ok]
  [[weight Class Weight] | Rest] [Class | Classes] ->
    (if (not (urdr.int.valid? Weight))
        [error search-strategy-weight [symbol Class]]
        (if (or (urdr.int.raw.negative? Weight)
                (urdr.int.raw.zero? Weight))
            [error search-strategy-weight [symbol Class]]
            (urdr.search.strategy.check-weights Rest Classes)))
  _ _ -> [error search-strategy-weights [null]])

(define urdr.search.strategy.check
  [strategy Name Weights] ->
    (if (= Name (urdr.search.strategy.n w-baseline))
        (urdr.search.strategy.check-empty Weights)
        (if (= Name (urdr.search.strategy.n w-boundary))
            (urdr.search.strategy.check-weights
              Weights (urdr.search.strategy.classes))
            [error search-strategy-name [null]]))
  _ -> [error search-strategy-shape [null]])

(define urdr.search.strategy.check-empty
  [] -> [ok]
  _ -> [error search-strategy-weights [null]])

(define urdr.search.strategy.name
  [strategy Name _] -> Name)

(define urdr.search.strategy.weights
  [strategy _ Weights] -> Weights)

\\ ---------------------------------------------------------------
\\ Canonical descriptor
\\ ---------------------------------------------------------------

(define urdr.search.strategy.weight-values
  [] -> []
  [[weight Class Weight] | Rest] ->
    [[record
       [[(urdr.search.strategy.n k-class) [symbol Class]]
        [(urdr.search.strategy.n k-weight) Weight]]] |
     (urdr.search.strategy.weight-values Rest)]
  _ -> [])

(define urdr.search.strategy.descriptor-value
  [strategy Name Weights] ->
    [record
      [[(urdr.search.strategy.n k-name) [symbol Name]]
       [(urdr.search.strategy.n k-weights)
        [list (urdr.search.strategy.weight-values Weights)]]]])

(define urdr.search.strategy.descriptor-digest
  Strategy ->
    (urdr.eventlog.value-digest
      (urdr.search.strategy.descriptor-value Strategy)))

\\ ---------------------------------------------------------------
\\ Reading an alternative's shape
\\ ---------------------------------------------------------------

(define urdr.search.strategy.field
  [record Fields] Key -> (urdr.search.strategy.field-of Fields Key)
  _ _ -> none)

(define urdr.search.strategy.field-of
  [] _ -> none
  [[K V] | Rest] Key ->
    (if (= (urdr.canonical.bytes-compare K Key) eq)
        [some V]
        (urdr.search.strategy.field-of Rest Key))
  _ _ -> none)

(define urdr.search.strategy.symbol-of
  [some [symbol Bs]] -> [some Bs]
  _ -> none)

(define urdr.search.strategy.integer-of
  [some [big Sign Magnitude]] ->
    (if (urdr.int.valid? [big Sign Magnitude])
        [some [big Sign Magnitude]]
        none)
  _ -> none)

(define urdr.search.strategy.symbol-field
  Value Key ->
    (urdr.search.strategy.symbol-of
      (urdr.search.strategy.field Value Key)))

(define urdr.search.strategy.integer-field
  Value Key ->
    (urdr.search.strategy.integer-of
      (urdr.search.strategy.field Value Key)))

\\ ---------------------------------------------------------------
\\ Classification (section 3)
\\ ---------------------------------------------------------------

(define urdr.search.strategy.classify
  Kind Time Alternatives Alternative ->
    (if (= Kind (urdr.search.strategy.n a-timer-fire))
        (urdr.search.strategy.classify-timer Time Alternative)
        (if (= Kind (urdr.search.strategy.n a-delivery))
            (urdr.search.strategy.classify-delivery Alternative)
            (if (= Kind (urdr.search.strategy.n a-fault-action))
                (urdr.search.strategy.classify-fault Alternative)
                (if (= Kind (urdr.search.strategy.n a-schedule-delay))
                    (urdr.search.strategy.classify-delay
                      Alternatives Alternative)
                    (urdr.search.strategy.n c-ordinary))))))

(define urdr.search.strategy.classify-timer
  Time Alternative ->
    (urdr.search.strategy.classify-timer-due
      Time
      (urdr.search.strategy.integer-field
        Alternative (urdr.search.strategy.n a-due))))

(define urdr.search.strategy.classify-timer-due
  Time [some Due] ->
    (if (= (urdr.int.raw.compare Due Time) 0)
        (urdr.search.strategy.n c-timing-edge)
        (urdr.search.strategy.n c-ordinary))
  Time _ -> (urdr.search.strategy.n c-ordinary))

(define urdr.search.strategy.classify-delivery
  Alternative ->
    (urdr.search.strategy.classify-action
      (urdr.search.strategy.symbol-field
        Alternative (urdr.search.strategy.n a-action))
      (urdr.search.strategy.integer-field
        Alternative (urdr.search.strategy.n a-index))))

(define urdr.search.strategy.classify-action
  [some Action] Index ->
    (if (= Action (urdr.search.strategy.n a-drop))
        (urdr.search.strategy.n c-retry-edge)
        (if (= Action (urdr.search.strategy.n a-duplicate))
            (urdr.search.strategy.n c-reorder)
            (if (= Action (urdr.search.strategy.n a-deliver))
                (urdr.search.strategy.classify-index Index)
                (urdr.search.strategy.n c-ordinary))))
  _ _ -> (urdr.search.strategy.n c-ordinary))

(define urdr.search.strategy.classify-index
  [some Index] ->
    (if (urdr.int.raw.zero? Index)
        (urdr.search.strategy.n c-ordinary)
        (urdr.search.strategy.n c-reorder))
  _ -> (urdr.search.strategy.n c-ordinary))

(define urdr.search.strategy.classify-fault
  Alternative ->
    (urdr.search.strategy.classify-operation
      (urdr.search.strategy.symbol-field
        Alternative (urdr.search.strategy.n a-operation))))

(define urdr.search.strategy.classify-operation
  [some Operation] ->
    (if (= Operation (urdr.search.strategy.n a-activate))
        (urdr.search.strategy.n c-fault-activation)
        (urdr.search.strategy.n c-ordinary))
  _ -> (urdr.search.strategy.n c-ordinary))

\\ The offered delays ARE the declared ladder, so its edges are the least
\\ and the greatest of them under software-integer comparison. Numeric
\\ order is used deliberately rather than canonical encoding order:
\\ encoded integers are length-prefixed decimal, so the two orders agree
\\ only until the DECIMAL WIDTH itself needs two digits, and a ladder
\\ that reached ten-digit delays would otherwise have its boundary
\\ silently move. "The edge of a range" has to mean the numeric edge.
(define urdr.search.strategy.classify-delay
  Alternatives Alternative ->
    (urdr.search.strategy.classify-delay-value
      (urdr.search.strategy.integer-of [some Alternative])
      Alternatives))

(define urdr.search.strategy.classify-delay-value
  none _ -> (urdr.search.strategy.n c-ordinary)
  [some Value] Alternatives ->
    (if (or (urdr.search.strategy.least? Value Alternatives)
            (urdr.search.strategy.greatest? Value Alternatives))
        (urdr.search.strategy.n c-timing-edge)
        (urdr.search.strategy.n c-ordinary)))

(define urdr.search.strategy.least?
  _ [] -> true
  Value [Other | Rest] ->
    (urdr.search.strategy.least-step
      Value (urdr.search.strategy.integer-of [some Other]) Rest)
  _ _ -> false)

(define urdr.search.strategy.least-step
  Value none Rest -> (urdr.search.strategy.least? Value Rest)
  Value [some Other] Rest ->
    (if (> (urdr.int.raw.compare Value Other) 0)
        false
        (urdr.search.strategy.least? Value Rest)))

(define urdr.search.strategy.greatest?
  _ [] -> true
  Value [Other | Rest] ->
    (urdr.search.strategy.greatest-step
      Value (urdr.search.strategy.integer-of [some Other]) Rest)
  _ _ -> false)

(define urdr.search.strategy.greatest-step
  Value none Rest -> (urdr.search.strategy.greatest? Value Rest)
  Value [some Other] Rest ->
    (if (< (urdr.int.raw.compare Value Other) 0)
        false
        (urdr.search.strategy.greatest? Value Rest)))

\\ ---------------------------------------------------------------
\\ Selection
\\ ---------------------------------------------------------------

(define urdr.search.strategy.context
  Actor Kind Time Alternatives ->
    [choice-context Actor Kind Time Alternatives])

(define urdr.search.strategy.count
  [] Acc -> Acc
  [_ | Rest] Acc ->
    (urdr.search.strategy.count
      Rest (urdr.int.raw.add Acc (urdr.int.one)))
  _ Acc -> Acc)

(define urdr.search.strategy.single?
  [_] -> true
  _ -> false)

(define urdr.search.strategy.select
  Strategy [choice-context Actor Kind Time Alternatives] Stream ->
    (urdr.search.strategy.select-checked
      (urdr.search.strategy.check Strategy)
      Strategy Kind Time Alternatives Stream)
  _ _ _ -> [error search-strategy-context [null]])

(define urdr.search.strategy.select-checked
  [error Code Detail] _ _ _ _ _ -> [error Code Detail]
  [ok] Strategy Kind Time [] Stream ->
    [error search-strategy-context [null]]
  [ok] Strategy Kind Time Alternatives Stream ->
    (if (urdr.search.strategy.single? Alternatives)
        (urdr.search.strategy.select-forced Alternatives Stream)
        (urdr.search.strategy.select-many
          Strategy Kind Time Alternatives Stream)))

\\ Forced: one alternative, sampled with bound 1 so the stream advances
\\ exactly once whichever strategy is driving (section 4).
(define urdr.search.strategy.select-forced
  [Alternative] Stream ->
    (urdr.search.strategy.forced-sample
      Alternative (urdr.prng.sample Stream (urdr.int.one))))

(define urdr.search.strategy.forced-sample
  Alternative [ok [sample _ Next Coordinates]] ->
    [ok [selection Alternative (urdr.search.choice.reason-forced) Next
          Coordinates]]
  Alternative _ -> [error search-strategy-sample [null]])

(define urdr.search.strategy.select-many
  [strategy Name Weights] Kind Time Alternatives Stream ->
    (if (= Name (urdr.search.strategy.n w-baseline))
        (urdr.search.strategy.select-uniform Alternatives Stream)
        (urdr.search.strategy.select-weighted
          Weights Kind Time Alternatives Stream)))

(define urdr.search.strategy.select-uniform
  Alternatives Stream ->
    (urdr.search.strategy.uniform-sample
      Alternatives
      (urdr.prng.sample
        Stream
        (urdr.search.strategy.count Alternatives (urdr.int.zero)))))

(define urdr.search.strategy.uniform-sample
  Alternatives [ok [sample Index Next Coordinates]] ->
    [ok [selection
          (urdr.world.nth-big Alternatives Index)
          (urdr.search.choice.reason-uniform)
          Next
          Coordinates]]
  Alternatives _ -> [error search-strategy-sample [null]])

(define urdr.search.strategy.weight-of
  [] _ -> (urdr.int.one)
  [[weight Class Weight] | Rest] Wanted ->
    (if (= Class Wanted)
        Weight
        (urdr.search.strategy.weight-of Rest Wanted))
  _ _ -> (urdr.int.one))

\\ One weight per alternative, in alternative order. Every alternative is
\\ classified against the WHOLE offered set, because `schedule-delay`
\\ classification is relative to the range on offer.
(define urdr.search.strategy.alternative-weights
  _ _ _ _ [] Acc -> (urdr.canonical.rev Acc)
  Table Kind Time All [Alternative | Rest] Acc ->
    (urdr.search.strategy.alternative-weights
      Table Kind Time All Rest
      [(urdr.search.strategy.weight-of
         Table
         (urdr.search.strategy.classify Kind Time All Alternative))
       | Acc])
  _ _ _ _ _ Acc -> (urdr.canonical.rev Acc))

(define urdr.search.strategy.sum
  [] Acc -> Acc
  [Weight | Rest] Acc ->
    (urdr.search.strategy.sum Rest (urdr.int.raw.add Acc Weight))
  _ Acc -> Acc)

\\ The least i with x < w(0) + ... + w(i). The bound handed to the
\\ sampler is the sum of the same list, so x is strictly below the total
\\ and the walk always lands; the final clauses exist so the function is
\\ total on any list pair rather than partial on the ones it expects.
(define urdr.search.strategy.pick
  [Alternative] _ _ -> Alternative
  [Alternative | Alternatives] [Weight | Weights] X ->
    (if (< (urdr.int.raw.compare X Weight) 0)
        Alternative
        (urdr.search.strategy.pick
          Alternatives Weights (urdr.int.raw.subtract X Weight)))
  [Alternative | _] _ _ -> Alternative)

(define urdr.search.strategy.select-weighted
  Table Kind Time Alternatives Stream ->
    (urdr.search.strategy.weighted-total
      (urdr.search.strategy.alternative-weights
        Table Kind Time Alternatives Alternatives [])
      Alternatives Stream))

(define urdr.search.strategy.weighted-total
  Ws Alternatives Stream ->
    (urdr.search.strategy.weighted-sample
      Alternatives Ws
      (urdr.prng.sample
        Stream (urdr.search.strategy.sum Ws (urdr.int.zero)))))

(define urdr.search.strategy.weighted-sample
  Alternatives Ws [ok [sample X Next Coordinates]] ->
    [ok [selection
          (urdr.search.strategy.pick Alternatives Ws X)
          (urdr.search.choice.reason-weighted)
          Next
          Coordinates]]
  Alternatives Ws _ -> [error search-strategy-sample [null]])
