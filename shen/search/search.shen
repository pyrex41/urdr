\\ Seeded exploration: choice records, strategies, and the explore driver
\\ (SPEC.md 17, M1 plan Wave F). Requires shen/protocol/canonical.shen,
\\ shen/world/integer.shen, shen/world/prng.shen,
\\ shen/world/component.shen (encoding order), shen/world/world.shen,
\\ shen/world/eventlog.shen, and shen/world/certificate.shen to be loaded
\\ by the caller.
\\
\\ Pure: no I/O, no host time, no host randomness, no floating point, no
\\ defprolog. Every operation returns [ok ...] or [error CODE DETAIL] and
\\ performs no work before validating.
\\
\\ NOT owned here: the reducer, property evaluation, or shrinking.
\\ Strategies only draw from named PRNG streams (ADR 0003). Selections
\\ are ordinary transcript choice entries compatible with Wave E replay
\\ (urdr.replay.run).
\\
\\ =====================================================================
\\ 1. Choice records (SPEC.md 17)
\\ =====================================================================
\\
\\ A choice record is the search-layer view of a single explicit decision.
\\ It projects the world reducer's choice payload
\\ (urdr.world.choice-value) and adds the fields SPEC.md 17 requires that
\\ the world record does not carry on its own:
\\
\\   stable choice ID, logical time, kind, canonically ordered
\\   alternatives, selected alternative, selection reason, PRNG
\\   coordinates.
\\
\\ Canonical value (keys ascending unsigned-ASCII):
\\
\\   [record [[alternatives [list ALT ...]]
\\            [coordinates  [list COORD ...]]
\\            [id           INTEGER]
\\            [kind         [symbol KIND]]
\\            [reason       [symbol REASON]]
\\            [selected     ALT]
\\            [time         INTEGER]]]
\\
\\ KIND is one of the section-17 strategy bias classes plus a catch-all:
\\   fault, timing, reorder, retry, schedule, scenario, other
\\
\\ REASON names the strategy that selected:
\\   baseline-random, boundary-biased
\\
\\ An open choice MENU presented to a strategy (from a reduction or a
\\ fixture) is:
\\
\\   [menu Id At Kind Subsystem Actor Purpose Alternatives]
\\
\\ Alternatives are nonempty and strictly ascending in canonical
\\ encoding order (the component contract, enforced here as
\\ search-menu-order and again by the reducer as
\\ choice-alternatives-order). The strategy never reorders them for
\\ selection identity; boundary bias only reweights a parallel index
\\ bag.
\\
\\ =====================================================================
\\ 2. Strategies
\\ =====================================================================
\\
\\ Both strategies draw only from named streams whose subsystem is the
\\ octet string "search". Actor and purpose are the menu's actor/purpose
\\ so a draw is coordinate-stable under the same seed and counters.
\\
\\   baseline   uniform sample over the alternative list via
\\              urdr.prng.sample.
\\   boundary   pure ranking/reweight: each alternative receives a
\\              positive integer weight from its menu kind (fault and
\\              timing edges weigh more than ordinary schedule/scenario
\\              choices). The strategy builds a weighted bag of indices
\\              in alternative order and samples uniformly from that bag,
\\              still only via named streams. No floating point.
\\
\\ =====================================================================
\\ 3. Explore driver
\\ =====================================================================
\\
\\   explore SEED BUDGET STRATEGY MENUS BUILD EVAL
\\
\\ SEED is an octet list (PRNG seed). BUDGET is a positive small natural
\\ bound on the number of attempt paths. STRATEGY is baseline or
\\ boundary. MENUS is the list of open choice menus for one scenario
\\ step sequence. BUILD turns a list of choice records into a decision
\\ transcript (list of reducer inputs). EVAL Transcript returns
\\ [ok VERDICT-VALUES] or [error ...]; a failure-signature of those
\\ verdicts that is distinct from the empty-failure signature is a
\\ discovery.
\\
\\ The driver is pure: it threads a counter stream, records every
\\ selection as a choice record, and never consults host time or
\\ randomness. Same seed + same menus => same path and same discovery.
\\
\\ =====================================================================
\\ 4. Public entry points
\\ =====================================================================
\\
\\   menu              Id At Kind Sub Actor Purpose Alts
\\                       -> [ok MENU] | [error C D]
\\   choice-record     Id At Kind Alts Selected Reason Coords
\\                       -> [ok RECORD] | [error C D]
\\   choice-value      RECORD -> canonical record
\\   choice-id / choice-kind / choice-selected / choice-reason
\\   choice-alternatives / choice-coordinates / choice-time
\\   schedule-input    RECORD Sub Actor Purpose -> reducer input
\\   select            STRATEGY SEED COUNTER MENU
\\                       -> [ok [RECORD NEXT-COUNTER]] | [error C D]
\\   explore           SEED BUDGET STRATEGY MENUS BUILD EVAL
\\                       -> [ok RESULT] | [error C D]
\\   result-status / result-transcript / result-choices / result-seed
\\   path-digest       [RECORD ...] -> [ok OCTETS] | [error C D]
\\
\\ RESULT shape: [discovery STATUS TRANSCRIPT CHOICES SEED]
\\ STATUS is found or exhausted.

\\ ---------------------------------------------------------------
\\ ASCII names as octet lists.
\\ ---------------------------------------------------------------

(define urdr.search.n
  k-alternatives ->
    [97 108 116 101 114 110 97 116 105 118 101 115]
  k-coordinates ->
    [99 111 111 114 100 105 110 97 116 101 115]
  k-id ->
    [105 100]
  k-kind ->
    [107 105 110 100]
  k-reason ->
    [114 101 97 115 111 110]
  k-selected ->
    [115 101 108 101 99 116 101 100]
  k-time ->
    [116 105 109 101]
  w-baseline ->
    [98 97 115 101 108 105 110 101 45 114 97 110 100 111 109]
  w-boundary ->
    [98 111 117 110 100 97 114 121 45 98 105 97 115 101 100]
  w-fault ->
    [102 97 117 108 116]
  w-timing ->
    [116 105 109 105 110 103]
  w-reorder ->
    [114 101 111 114 100 101 114]
  w-retry ->
    [114 101 116 114 121]
  w-schedule ->
    [115 99 104 101 100 117 108 101]
  w-scenario ->
    [115 99 101 110 97 114 105 111]
  w-other ->
    [111 116 104 101 114]
  w-search ->
    [115 101 97 114 99 104]
  t-path ->
    [117 114 100 114 45 115 101 97 114 99 104 45 112 97 116 104
     45 118 49]
  c-menu-shape ->
    [115 101 97 114 99 104 45 109 101 110 117 45 115 104 97 112
     101]
  c-menu-empty ->
    [115 101 97 114 99 104 45 109 101 110 117 45 101 109 112 116
     121]
  c-menu-order ->
    [115 101 97 114 99 104 45 109 101 110 117 45 111 114 100 101
     114]
  c-kind ->
    [115 101 97 114 99 104 45 107 105 110 100]
  c-strategy ->
    [115 101 97 114 99 104 45 115 116 114 97 116 101 103 121]
  c-budget ->
    [115 101 97 114 99 104 45 98 117 100 103 101 116]
  c-seed ->
    [115 101 97 114 99 104 45 115 101 101 100]
  c-alts ->
    [115 101 97 114 99 104 45 97 108 116 101 114 110 97 116 105
     118 101 115]
  c-select ->
    [115 101 97 114 99 104 45 115 101 108 101 99 116]
  c-record-shape ->
    [115 101 97 114 99 104 45 114 101 99 111 114 100 45 115 104
     97 112 101])

(define urdr.search.big
  N -> (urdr.int.raw.from-small N))

\\ ---------------------------------------------------------------
\\ Validation helpers
\\ ---------------------------------------------------------------

(define urdr.search.kind?
  fault -> true
  timing -> true
  reorder -> true
  retry -> true
  schedule -> true
  scenario -> true
  other -> true
  _ -> false)

(define urdr.search.strategy?
  baseline -> true
  boundary -> true
  _ -> false)

(define urdr.search.kind-octets
  fault -> (urdr.search.n w-fault)
  timing -> (urdr.search.n w-timing)
  reorder -> (urdr.search.n w-reorder)
  retry -> (urdr.search.n w-retry)
  schedule -> (urdr.search.n w-schedule)
  scenario -> (urdr.search.n w-scenario)
  other -> (urdr.search.n w-other))

(define urdr.search.reason-octets
  baseline -> (urdr.search.n w-baseline)
  boundary -> (urdr.search.n w-boundary))

(define urdr.search.nonempty?
  [_ | _] -> true
  _ -> false)

(define urdr.search.canonical-list?
  [] -> true
  [V | Vs] ->
    (and (= (hd (urdr.canonical.encode-payload V)) ok)
         (urdr.search.canonical-list? Vs))
  _ -> false)

\\ Strict ascension in canonical encoding order, the same comparison the
\\ component and world-reducer doors enforce
\\ (urdr.component.encoding-ascending?). Rejecting an unordered menu at
\\ construction gives strategy authors the error where they built it,
\\ not at reduce time. Callers must have proved the list canonically
\\ encodable first: the comparison reads encodings.
(define urdr.search.ascending?
  [] -> true
  [_] -> true
  [A B | Rest] ->
    (and (urdr.component.encoding-ascending? A B)
         (urdr.search.ascending? [B | Rest])))

(define urdr.search.nth
  0 [X | _] -> X
  N [_ | Xs] -> (urdr.search.nth (- N 1) Xs))

(define urdr.search.length
  [] -> 0
  [_ | Xs] -> (+ 1 (urdr.search.length Xs)))

(define urdr.search.list-count
  Xs -> (urdr.search.list-count-h Xs (urdr.int.zero)))

(define urdr.search.list-count-h
  [] C -> C
  [_ | Xs] C ->
    (urdr.search.list-count-h
      Xs (urdr.int.raw.add C (urdr.int.one))))

\\ Convert a software integer (or already-small number) to a host small
\\ natural for list indexing. Bounds in this module are scenario-scale.
\\ Magnitude decoding is delegated to urdr.int.small-of so the
\\ little-endian limb order of ADR 0003 is honoured in exactly one
\\ place; anything outside its host-safe window clamps to 0, matching
\\ this module's treatment of every other malformed index.
(define urdr.search.small-of
  N -> N where (and (number? N) (>= N 0))
  [big 1 Mag] ->
    (urdr.search.small-of-ok (urdr.int.small-of [big 1 Mag]))
  [big -1 _] -> 0
  [big 0 _] -> 0
  _ -> 0)

(define urdr.search.small-of-ok
  [ok N] -> N
  _ -> 0)

\\ ---------------------------------------------------------------
\\ Menu construction
\\ ---------------------------------------------------------------

(define urdr.search.menu
  Id At Kind Subsystem Actor Purpose Alternatives ->
    (if (not (urdr.search.kind? Kind))
        [error (urdr.search.n c-kind) [null]]
        (if (not (urdr.search.nonempty? Alternatives))
            [error (urdr.search.n c-menu-empty) [null]]
            (if (not (urdr.search.canonical-list? Alternatives))
                [error (urdr.search.n c-alts) [null]]
                (if (not (urdr.search.ascending? Alternatives))
                    [error (urdr.search.n c-menu-order) [null]]
                (if (not (= (hd (urdr.prng.octets.check Subsystem)) ok))
                    [error (urdr.search.n c-menu-shape) [null]]
                    (if (not (= (hd (urdr.prng.octets.check Actor)) ok))
                        [error (urdr.search.n c-menu-shape) [null]]
                        (if (not (= (hd (urdr.prng.octets.check Purpose))
                                    ok))
                            [error (urdr.search.n c-menu-shape) [null]]
                            [ok [menu Id At Kind Subsystem Actor Purpose
                                  Alternatives]]))))))))

(define urdr.search.menu-id
  [menu Id _ _ _ _ _ _] -> Id)

(define urdr.search.menu-time
  [menu _ At _ _ _ _ _] -> At)

(define urdr.search.menu-kind
  [menu _ _ Kind _ _ _ _] -> Kind)

(define urdr.search.menu-subsystem
  [menu _ _ _ Sub _ _ _] -> Sub)

(define urdr.search.menu-actor
  [menu _ _ _ _ Actor _ _] -> Actor)

(define urdr.search.menu-purpose
  [menu _ _ _ _ _ Purpose _] -> Purpose)

(define urdr.search.menu-alternatives
  [menu _ _ _ _ _ _ Alts] -> Alts)

\\ ---------------------------------------------------------------
\\ Choice records
\\ ---------------------------------------------------------------

(define urdr.search.choice-record
  Id At Kind Alternatives Selected Reason Coordinates ->
    (if (not (urdr.search.kind? Kind))
        [error (urdr.search.n c-kind) [null]]
        (if (not (urdr.search.nonempty? Alternatives))
            [error (urdr.search.n c-alts) [null]]
            (if (not (urdr.search.canonical-list? Alternatives))
                [error (urdr.search.n c-alts) [null]]
                (if (not (= (hd (urdr.canonical.encode-payload Selected))
                            ok))
                    [error (urdr.search.n c-record-shape) [null]]
                    [ok [choice-record Id At Kind Alternatives Selected
                          Reason Coordinates]])))))

(define urdr.search.choice-id
  [choice-record Id _ _ _ _ _ _] -> Id)

(define urdr.search.choice-time
  [choice-record _ At _ _ _ _ _] -> At)

(define urdr.search.choice-kind
  [choice-record _ _ Kind _ _ _ _] -> Kind)

(define urdr.search.choice-alternatives
  [choice-record _ _ _ Alts _ _ _] -> Alts)

(define urdr.search.choice-selected
  [choice-record _ _ _ _ Selected _ _] -> Selected)

(define urdr.search.choice-reason
  [choice-record _ _ _ _ _ Reason _] -> Reason)

(define urdr.search.choice-coordinates
  [choice-record _ _ _ _ _ _ Coords] -> Coords)

\\ Canonical value. Coordinates reuse urdr.world.coordinate-value so the
\\ search record and the world choice payload cannot drift on that field.
(define urdr.search.choice-value
  [choice-record Id At Kind Alternatives Selected Reason Coordinates] ->
    [record
      [[(urdr.search.n k-alternatives) [list Alternatives]]
       [(urdr.search.n k-coordinates)
        [list (urdr.world.coordinates-value Coordinates)]]
       [(urdr.search.n k-id) Id]
       [(urdr.search.n k-kind)
        [symbol (urdr.search.kind-octets Kind)]]
       [(urdr.search.n k-reason)
        [symbol (urdr.search.reason-octets Reason)]]
       [(urdr.search.n k-selected) Selected]
       [(urdr.search.n k-time) At]]]
  _ -> [null])

\\ A reducer input that schedules the decision the strategy just made,
\\ in the world's SELECTED choice form (ADR 0007 D2): menu, selected
\\ alternative, and the PRNG coordinates of the strategy's draw. The
\\ world applies the recorded selection without re-drawing, so explore's
\\ transcripts are pinned by construction -- a transcript survives a
\\ strategy change, and replaying it cannot perturb world streams. The
\\ coordinates travel verbatim as evidence of the driver-space draw;
\\ the search record remains the decision-level audit of the same fact.
(define urdr.search.schedule-input
  [choice-record _ At _ Alternatives Selected _ Coordinates]
  Subsystem Actor Purpose ->
    [schedule At choice
      [choice Subsystem Actor Purpose Alternatives Selected
        Coordinates]]
  _ _ _ _ -> [error (urdr.search.n c-record-shape) [null]])

\\ ---------------------------------------------------------------
\\ Boundary weights (pure ranking; no floating point)
\\ ---------------------------------------------------------------
\\
\\ Prefer per-alternative tags when the alternative is a record with a
\\ `tag` key naming a bias class; otherwise fall back to the menu kind.
\\ Higher weight => more bag copies. No floating point.

(define urdr.search.kind-weight
  fault -> 8
  timing -> 6
  reorder -> 5
  retry -> 5
  schedule -> 2
  scenario -> 2
  other -> 1
  _ -> 1)

(define urdr.search.tag-key
  -> [116 97 103])

(define urdr.search.alt-weight
  MenuKind [record Fields] ->
    (urdr.search.alt-weight-fields MenuKind Fields)
  MenuKind _ -> (urdr.search.kind-weight MenuKind))

(define urdr.search.alt-weight-fields
  MenuKind [] -> (urdr.search.kind-weight MenuKind)
  MenuKind [[Key [symbol TagBs]] | Rest] ->
    (if (= Key (urdr.search.tag-key))
        (urdr.search.kind-weight (urdr.search.tag-kind TagBs))
        (urdr.search.alt-weight-fields MenuKind Rest))
  MenuKind [_ | Rest] -> (urdr.search.alt-weight-fields MenuKind Rest))

(define urdr.search.tag-kind
  Bs ->
    (if (= Bs (urdr.search.n w-fault))
        fault
        (if (= Bs (urdr.search.n w-timing))
            timing
            (if (= Bs (urdr.search.n w-reorder))
                reorder
                (if (= Bs (urdr.search.n w-retry))
                    retry
                    (if (= Bs (urdr.search.n w-schedule))
                        schedule
                        (if (= Bs (urdr.search.n w-scenario))
                            scenario
                            other)))))))

(define urdr.search.replicate
  0 _ Acc -> Acc
  N X Acc -> (urdr.search.replicate (- N 1) X [X | Acc]))

\\ Weighted bag of alternative indices (not values), so equal-weight
\\ ties stay stable under bag order.
(define urdr.search.weighted-bag
  [] _ _ Acc -> (urdr.canonical.rev Acc)
  [Alt | Alts] Kind I Acc ->
    (urdr.search.weighted-bag
      Alts Kind (+ I 1)
      (urdr.search.replicate
        (urdr.search.alt-weight Kind Alt) I Acc)))

\\ ---------------------------------------------------------------
\\ Selection
\\ ---------------------------------------------------------------

(define urdr.search.select
  Strategy Seed Counter Menu ->
    (if (not (urdr.search.strategy? Strategy))
        [error (urdr.search.n c-strategy) [null]]
        (if (not (= (hd (urdr.prng.octets.check Seed)) ok))
            [error (urdr.search.n c-seed) [null]]
            (urdr.search.select-menu Strategy Seed Counter Menu))))

(define urdr.search.select-menu
  Strategy Seed Counter
  [menu Id At Kind Subsystem Actor Purpose Alternatives] ->
    (if (= Strategy baseline)
        (urdr.search.select-baseline
          Seed Counter Id At Kind Actor Purpose Alternatives)
        (urdr.search.select-boundary
          Seed Counter Id At Kind Actor Purpose Alternatives))
  _ _ _ _ -> [error (urdr.search.n c-menu-shape) [null]])

(define urdr.search.select-baseline
  Seed Counter Id At Kind Actor Purpose Alternatives ->
    (let Stream (urdr.prng.stream
                  Seed
                  (urdr.search.n w-search)
                  Actor
                  Purpose
                  Counter)
      (if (= (hd Stream) error)
          [error (urdr.search.n c-select) [null]]
          (urdr.search.sample-and-record
            baseline Id At Kind Alternatives
            (urdr.prng.sample
              (hd (tl Stream))
              (urdr.search.list-count Alternatives))))))

(define urdr.search.select-boundary
  Seed Counter Id At Kind Actor Purpose Alternatives ->
    (let Bag (urdr.search.weighted-bag Alternatives Kind 0 [])
         Stream (urdr.prng.stream
                  Seed
                  (urdr.search.n w-search)
                  Actor
                  Purpose
                  Counter)
      (if (= (hd Stream) error)
          [error (urdr.search.n c-select) [null]]
          (urdr.search.sample-bag-and-record
            Id At Kind Alternatives Bag
            (urdr.prng.sample
              (hd (tl Stream))
              (urdr.search.list-count Bag))))))

(define urdr.search.sample-and-record
  Reason Id At Kind Alternatives
  [ok [sample Index
        [stream _ _ _ _ _ NextCounter]
        Coordinates]] ->
    (let Selected (urdr.search.nth
                    (urdr.search.small-of Index) Alternatives)
      (urdr.search.record-ok
        Id At Kind Alternatives Selected Reason Coordinates
        NextCounter))
  _ _ _ _ _ [error Code Detail] -> [error Code Detail]
  _ _ _ _ _ _ -> [error (urdr.search.n c-select) [null]])

(define urdr.search.sample-bag-and-record
  Id At Kind Alternatives Bag
  [ok [sample Index
        [stream _ _ _ _ _ NextCounter]
        Coordinates]] ->
    (let AltIndex (urdr.search.nth (urdr.search.small-of Index) Bag)
         Selected (urdr.search.nth AltIndex Alternatives)
      (urdr.search.record-ok
        Id At Kind Alternatives Selected boundary Coordinates
        NextCounter))
  _ _ _ _ _ [error Code Detail] -> [error Code Detail]
  _ _ _ _ _ _ -> [error (urdr.search.n c-select) [null]])

(define urdr.search.record-ok
  Id At Kind Alternatives Selected Reason Coordinates NextCounter ->
    (let Rec (urdr.search.choice-record
               Id At Kind Alternatives Selected Reason Coordinates)
      (if (= (hd Rec) error)
          Rec
          [ok [(hd (tl Rec)) NextCounter]])))

\\ ---------------------------------------------------------------
\\ Explore driver
\\ ---------------------------------------------------------------

(define urdr.search.empty-failure-sig
  -> (let Sig (urdr.certificate.failure-signature [])
       (if (= (hd Sig) ok)
           (hd (tl Sig))
           [])))

(define urdr.search.explore
  Seed Budget Strategy Menus Build Eval ->
    (if (not (= (hd (urdr.prng.octets.check Seed)) ok))
        [error (urdr.search.n c-seed) [null]]
        (if (not (urdr.search.strategy? Strategy))
            [error (urdr.search.n c-strategy) [null]]
            (if (< Budget 1)
                [error (urdr.search.n c-budget) [null]]
                (urdr.search.explore-loop
                  Seed Budget Strategy Menus Build Eval 0)))))

(define urdr.search.explore-loop
  Seed Budget Strategy Menus Build Eval Attempt ->
    (if (>= Attempt Budget)
        [ok [discovery exhausted [] [] Seed]]
        (urdr.search.explore-attempt
          Seed Budget Strategy Menus Build Eval Attempt
          (urdr.search.select-all
            Strategy Seed
            (urdr.int.raw.from-small
              (* Attempt (+ 1 (urdr.search.length Menus))))
            Menus []))))

(define urdr.search.select-all
  _ _ _ [] Acc -> [ok [(urdr.canonical.rev Acc)]]
  Strategy Seed Counter [Menu | Rest] Acc ->
    (urdr.search.select-all-step
      Strategy Seed Counter Rest Acc
      (urdr.search.select Strategy Seed Counter Menu))
  _ _ _ _ _ -> [error (urdr.search.n c-menu-shape) [null]])

(define urdr.search.select-all-step
  Strategy Seed Counter Rest Acc [ok [Record Next]] ->
    (urdr.search.select-all
      Strategy Seed Next Rest [Record | Acc])
  _ _ _ _ _ [error Code Detail] -> [error Code Detail]
  _ _ _ _ _ _ -> [error (urdr.search.n c-select) [null]])

(define urdr.search.explore-attempt
  Seed Budget Strategy Menus Build Eval Attempt [error Code Detail] ->
    [error Code Detail]
  Seed Budget Strategy Menus Build Eval Attempt [ok [Choices]] ->
    (urdr.search.explore-built
      Seed Budget Strategy Menus Build Eval Attempt Choices
      (Build Choices)))

(define urdr.search.explore-built
  Seed Budget Strategy Menus Build Eval Attempt Choices Transcript ->
    (urdr.search.explore-checked
      Seed Budget Strategy Menus Build Eval Attempt Choices Transcript
      (Eval Transcript)))

(define urdr.search.explore-checked
  Seed Budget Strategy Menus Build Eval Attempt Choices Transcript
  [ok Verdicts] ->
    (urdr.search.explore-sig
      Seed Budget Strategy Menus Build Eval Attempt Choices Transcript
      (urdr.certificate.failure-signature Verdicts))
  Seed Budget Strategy Menus Build Eval Attempt _ _ _ ->
    (urdr.search.explore-loop
      Seed Budget Strategy Menus Build Eval (+ Attempt 1)))

(define urdr.search.explore-sig
  Seed Budget Strategy Menus Build Eval Attempt Choices Transcript
  [ok Sig] ->
    (if (= Sig (urdr.search.empty-failure-sig))
        (urdr.search.explore-loop
          Seed Budget Strategy Menus Build Eval (+ Attempt 1))
        [ok [discovery found Transcript Choices Seed]])
  Seed Budget Strategy Menus Build Eval Attempt _ _ _ ->
    (urdr.search.explore-loop
      Seed Budget Strategy Menus Build Eval (+ Attempt 1)))

(define urdr.search.result-status
  [discovery found _ _ _] -> found
  [discovery exhausted _ _ _] -> exhausted
  _ -> unknown)

(define urdr.search.result-transcript
  [discovery _ Transcript _ _] -> Transcript)

(define urdr.search.result-choices
  [discovery _ _ Choices _] -> Choices)

(define urdr.search.result-seed
  [discovery _ _ _ Seed] -> Seed)

\\ Path digest: tagged root over the digests of every choice-value in
\\ selection order. Stable across ports; used by tests for SEED lines.
(define urdr.search.path-digest
  Choices ->
    (urdr.search.path-digest-of
      (urdr.eventlog.value-digests
        (urdr.search.choice-values Choices) [])))

(define urdr.search.choice-values
  [] -> []
  [C | Cs] ->
    [(urdr.search.choice-value C) | (urdr.search.choice-values Cs)])

(define urdr.search.path-digest-of
  [ok Digests] ->
    (urdr.eventlog.root-of (urdr.search.n t-path) Digests)
  Error -> Error)
