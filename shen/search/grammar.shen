\\ Seeded generative grammar for scenario families (SPEC.md 17 / 18,
\\ ADR 0004 Decision 5, M1 plan Wave H). Requires
\\ shen/protocol/canonical.shen, shen/world/integer.shen,
\\ shen/world/prng.shen, shen/world/world.shen (coordinates-value),
\\ shen/world/eventlog.shen (path digests), and shen/search/search.shen
\\ to be loaded by the caller.
\\
\\ Pure: no I/O, no host time, no host randomness, no floating point, no
\\ defprolog. Every public operation returns [ok ...] or
\\ [error CODE DETAIL] and performs no work before validating.
\\
\\ =====================================================================
\\ Design (ADR 0004 Decision 5)
\\ =====================================================================
\\
\\ Scenario-family generation expands three dimensions of a plain
\\ generative grammar:
\\
\\   1. topology size   (node count + link mode)
\\   2. workload shape  (process count + traffic shape)
\\   3. fault schedule  (fault count + kind + schedule placement)
\\
\\ Each expansion draws from a named PRNG stream via the Wave F search
\\ strategy surface (urdr.search.select baseline) and is recorded as an
\\ ordinary choice record of kind `scenario`. The same seed + same family
\\ specification reproduces the same fragment, choice list, and decision
\\ transcript byte-for-byte.
\\
\\ The generated SCENARIO-FRAGMENT is an intermediate record Wave I can
\\ wrap into a full scenario/v1 declaration. Field shapes intentionally
\\ mirror shen/scenario/scenario.shen where feasible (nodes/links/
\\ components/faults as ascending canonical records). Full scenario
\\ validation is deliberately not re-implemented here.
\\
\\ =====================================================================
\\ Family specification
\\ =====================================================================
\\
\\   [family-spec TopologySizes LinkModes ProcessCounts WorkloadShapes
\\                FaultCounts FaultKinds ScheduleShapes]
\\
\\ Every field is a nonempty list of discrete options (no open ranges, no
\\ floating probabilities). Constructors validate membership and fail
\\ closed on empty lists, non-positive sizes, unknown symbols, and
\\ process counts that cannot fit any declared topology size.
\\
\\ Topology sizes / process counts / fault counts are positive (or, for
\\ fault counts, non-negative) small host naturals in [0, 64]. Link
\\ modes: line, star, mesh. Workload shapes: burst, steady, staggered.
\\ Fault kinds: crash, delay, drop, partition, restart. Schedule shapes:
\\ front, middle, back, uniform.
\\
\\ =====================================================================
\\ Public entry points
\\ =====================================================================
\\
\\   family-spec    TopologySizes LinkModes ProcessCounts WorkloadShapes
\\                  FaultCounts FaultKinds ScheduleShapes
\\                    -> [ok SPEC] | [error C D]
\\   expand         SEED SPEC
\\                    -> [ok [expanded FRAGMENT CHOICES TRANSCRIPT]]
\\                     | [error C D]
\\   result-fragment / result-choices / result-transcript
\\   fragment-value FRAGMENT -> canonical record
\\   fragment-digest FRAGMENT -> [ok OCTETS] | [error C D]
\\   path-digest    CHOICES  -> [ok OCTETS] | [error C D]
\\                    (delegates to urdr.search.path-digest)
\\
\\ FRAGMENT shape:
\\   [fragment Seed Topology Workload Faults Components]
\\
\\ Topology / Workload / Faults / Components are canonical values
\\ (records and lists) ready for Wave I assembly. CHOICES is a list of
\\ Wave F choice-records in expansion order. TRANSCRIPT is the list of
\\ reducer schedule/advance inputs produced from those choice-records
\\ (urdr.search.schedule-input + advance-to-next-event), so withholding
\\ an entry fails urdr.replay.verify with the standard divergence codes.

\\ ---------------------------------------------------------------
\\ ASCII names as octet lists.
\\ ---------------------------------------------------------------

(define urdr.grammar.n
  k-components ->
    [99 111 109 112 111 110 101 110 116 115]
  k-faults ->
    [102 97 117 108 116 115]
  k-id ->
    [105 100]
  k-kind ->
    [107 105 110 100]
  k-kinds ->
    [107 105 110 100 115]
  k-link-mode ->
    [108 105 110 107 45 109 111 100 101]
  k-links ->
    [108 105 110 107 115]
  k-members ->
    [109 101 109 98 101 114 115]
  k-node ->
    [110 111 100 101]
  k-nodes ->
    [110 111 100 101 115]
  k-process-count ->
    [112 114 111 99 101 115 115 45 99 111 117 110 116]
  k-schedule ->
    [115 99 104 101 100 117 108 101]
  k-seed ->
    [115 101 101 100]
  k-shape ->
    [115 104 97 112 101]
  k-size ->
    [115 105 122 101]
  k-topology ->
    [116 111 112 111 108 111 103 121]
  k-workload ->
    [119 111 114 107 108 111 97 100]
  k-address ->
    [97 100 100 114 101 115 115]
  k-from ->
    [102 114 111 109]
  k-to ->
    [116 111]
  k-count ->
    [99 111 117 110 116]
  w-grammar ->
    [103 114 97 109 109 97 114]
  w-topology ->
    [116 111 112 111 108 111 103 121]
  w-workload ->
    [119 111 114 107 108 111 97 100]
  w-fault-schedule ->
    [102 97 117 108 116 45 115 99 104 101 100 117 108 101]
  w-expand ->
    [101 120 112 97 110 100]
  w-line ->
    [108 105 110 101]
  w-star ->
    [115 116 97 114]
  w-mesh ->
    [109 101 115 104]
  w-burst ->
    [98 117 114 115 116]
  w-steady ->
    [115 116 101 97 100 121]
  w-staggered ->
    [115 116 97 103 103 101 114 101 100]
  w-crash ->
    [99 114 97 115 104]
  w-delay ->
    [100 101 108 97 121]
  w-drop ->
    [100 114 111 112]
  w-partition ->
    [112 97 114 116 105 116 105 111 110]
  w-restart ->
    [114 101 115 116 97 114 116]
  w-front ->
    [102 114 111 110 116]
  w-middle ->
    [109 105 100 100 108 101]
  w-back ->
    [98 97 99 107]
  w-uniform ->
    [117 110 105 102 111 114 109]
  w-process ->
    [112 114 111 99 101 115 115]
  t-fragment ->
    [117 114 100 114 45 103 114 97 109 109 97 114 45 102 114 97
     103 109 101 110 116 45 118 49]
  c-seed ->
    [103 114 97 109 109 97 114 45 115 101 101 100]
  c-spec ->
    [103 114 97 109 109 97 114 45 115 112 101 99]
  c-empty ->
    [103 114 97 109 109 97 114 45 101 109 112 116 121]
  c-size ->
    [103 114 97 109 109 97 114 45 115 105 122 101]
  c-mode ->
    [103 114 97 109 109 97 114 45 109 111 100 101]
  c-shape ->
    [103 114 97 109 109 97 114 45 115 104 97 112 101]
  c-kind ->
    [103 114 97 109 109 97 114 45 107 105 110 100]
  c-schedule ->
    [103 114 97 109 109 97 114 45 115 99 104 101 100 117 108 101]
  c-count ->
    [103 114 97 109 109 97 114 45 99 111 117 110 116]
  c-range ->
    [103 114 97 109 109 97 114 45 114 97 110 103 101]
  c-expand ->
    [103 114 97 109 109 97 114 45 101 120 112 97 110 100]
  c-fragment ->
    [103 114 97 109 109 97 114 45 102 114 97 103 109 101 110 116]
  c-select ->
    [103 114 97 109 109 97 114 45 115 101 108 101 99 116]
  c-menu ->
    [103 114 97 109 109 97 114 45 109 101 110 117])

(define urdr.grammar.big
  N -> (urdr.int.raw.from-small N))

(define urdr.grammar.max-option
  -> 64)

\\ ---------------------------------------------------------------
\\ Small helpers
\\ ---------------------------------------------------------------

(define urdr.grammar.nonempty?
  [_ | _] -> true
  _ -> false)

(define urdr.grammar.length
  [] -> 0
  [_ | Xs] -> (+ 1 (urdr.grammar.length Xs)))

(define urdr.grammar.nth
  0 [X | _] -> X
  N [_ | Xs] -> (urdr.grammar.nth (- N 1) Xs))

(define urdr.grammar.member-nat?
  _ [] -> false
  N [X | Xs] ->
    (if (= N X) true (urdr.grammar.member-nat? N Xs)))

(define urdr.grammar.max-of
  [] Acc -> Acc
  [N | Ns] Acc ->
    (if (> N Acc)
        (urdr.grammar.max-of Ns N)
        (urdr.grammar.max-of Ns Acc)))

(define urdr.grammar.min-of
  [] Acc -> Acc
  [N | Ns] Acc ->
    (if (< N Acc)
        (urdr.grammar.min-of Ns N)
        (urdr.grammar.min-of Ns Acc)))

(define urdr.grammar.filter-le
  [] _ Acc -> (urdr.canonical.rev Acc)
  [N | Ns] Bound Acc ->
    (if (<= N Bound)
        (urdr.grammar.filter-le Ns Bound [N | Acc])
        (urdr.grammar.filter-le Ns Bound Acc)))

(define urdr.grammar.small-nat?
  N -> (and (number? N)
            (>= N 0)
            (<= N (urdr.grammar.max-option))))

(define urdr.grammar.positive-nat?
  N -> (and (urdr.grammar.small-nat? N) (> N 0)))

\\ Integer quotient for small non-negative host naturals (no floating point).
(define urdr.grammar.div
  N D -> (hd (urdr.int.small.divmod N D)))

(define urdr.grammar.mod
  N D -> (hd (tl (urdr.int.small.divmod N D))))

\\ Decimal digit of a small natural 0..9 as an octet.
(define urdr.grammar.digit-octet
  N -> (+ 48 N))

\\ "n" ++ decimal(N) as octet list. N is a small natural in 0..64.
(define urdr.grammar.node-id-bytes
  N -> [110 | (urdr.grammar.decimal-bytes N)])

(define urdr.grammar.decimal-bytes
  N -> (urdr.grammar.decimal-bytes-h N []))

(define urdr.grammar.decimal-bytes-h
  N Acc ->
    (let Q (urdr.grammar.div N 10)
         R (urdr.grammar.mod N 10)
         Next [(urdr.grammar.digit-octet R) | Acc]
      (if (= Q 0)
          Next
          (urdr.grammar.decimal-bytes-h Q Next))))

\\ "f" ++ decimal(N)
(define urdr.grammar.fault-id-bytes
  N -> [102 | (urdr.grammar.decimal-bytes N)])

\\ "p" ++ decimal(N)
(define urdr.grammar.proc-id-bytes
  N -> [112 | (urdr.grammar.decimal-bytes N)])

\\ ---------------------------------------------------------------
\\ Option vocabularies
\\ ---------------------------------------------------------------

(define urdr.grammar.link-mode?
  line -> true
  star -> true
  mesh -> true
  _ -> false)

(define urdr.grammar.workload-shape?
  burst -> true
  steady -> true
  staggered -> true
  _ -> false)

(define urdr.grammar.fault-kind?
  crash -> true
  delay -> true
  drop -> true
  partition -> true
  restart -> true
  _ -> false)

(define urdr.grammar.schedule-shape?
  front -> true
  middle -> true
  back -> true
  uniform -> true
  _ -> false)

(define urdr.grammar.link-mode-octets
  line -> (urdr.grammar.n w-line)
  star -> (urdr.grammar.n w-star)
  mesh -> (urdr.grammar.n w-mesh))

(define urdr.grammar.workload-shape-octets
  burst -> (urdr.grammar.n w-burst)
  steady -> (urdr.grammar.n w-steady)
  staggered -> (urdr.grammar.n w-staggered))

(define urdr.grammar.fault-kind-octets
  crash -> (urdr.grammar.n w-crash)
  delay -> (urdr.grammar.n w-delay)
  drop -> (urdr.grammar.n w-drop)
  partition -> (urdr.grammar.n w-partition)
  restart -> (urdr.grammar.n w-restart))

(define urdr.grammar.schedule-shape-octets
  front -> (urdr.grammar.n w-front)
  middle -> (urdr.grammar.n w-middle)
  back -> (urdr.grammar.n w-back)
  uniform -> (urdr.grammar.n w-uniform))

\\ ---------------------------------------------------------------
\\ Family-spec validation
\\ ---------------------------------------------------------------

(define urdr.grammar.check-sizes
  [] -> [error (urdr.grammar.n c-empty) [null]]
  Sizes -> (urdr.grammar.check-sizes-h Sizes))

(define urdr.grammar.check-sizes-h
  [] -> [ok]
  [N | Ns] ->
    (if (urdr.grammar.positive-nat? N)
        (urdr.grammar.check-sizes-h Ns)
        [error (urdr.grammar.n c-size) [null]]))

(define urdr.grammar.check-counts-nn
  [] -> [error (urdr.grammar.n c-empty) [null]]
  Counts -> (urdr.grammar.check-counts-nn-h Counts))

(define urdr.grammar.check-counts-nn-h
  [] -> [ok]
  [N | Ns] ->
    (if (urdr.grammar.small-nat? N)
        (urdr.grammar.check-counts-nn-h Ns)
        [error (urdr.grammar.n c-count) [null]]))

(define urdr.grammar.check-modes
  [] -> [error (urdr.grammar.n c-empty) [null]]
  Modes -> (urdr.grammar.check-modes-h Modes))

(define urdr.grammar.check-modes-h
  [] -> [ok]
  [M | Ms] ->
    (if (urdr.grammar.link-mode? M)
        (urdr.grammar.check-modes-h Ms)
        [error (urdr.grammar.n c-mode) [null]]))

(define urdr.grammar.check-shapes
  [] -> [error (urdr.grammar.n c-empty) [null]]
  Shapes -> (urdr.grammar.check-shapes-h Shapes))

(define urdr.grammar.check-shapes-h
  [] -> [ok]
  [S | Ss] ->
    (if (urdr.grammar.workload-shape? S)
        (urdr.grammar.check-shapes-h Ss)
        [error (urdr.grammar.n c-shape) [null]]))

(define urdr.grammar.check-kinds
  [] -> [error (urdr.grammar.n c-empty) [null]]
  Kinds -> (urdr.grammar.check-kinds-h Kinds))

(define urdr.grammar.check-kinds-h
  [] -> [ok]
  [K | Ks] ->
    (if (urdr.grammar.fault-kind? K)
        (urdr.grammar.check-kinds-h Ks)
        [error (urdr.grammar.n c-kind) [null]]))

(define urdr.grammar.check-schedules
  [] -> [error (urdr.grammar.n c-empty) [null]]
  Shapes -> (urdr.grammar.check-schedules-h Shapes))

(define urdr.grammar.check-schedules-h
  [] -> [ok]
  [S | Ss] ->
    (if (urdr.grammar.schedule-shape? S)
        (urdr.grammar.check-schedules-h Ss)
        [error (urdr.grammar.n c-schedule) [null]]))

\\ At least one process count must fit the largest topology size.
(define urdr.grammar.check-fit
  TopologySizes ProcessCounts ->
    (let MaxN (urdr.grammar.max-of TopologySizes 0)
         Fit (urdr.grammar.filter-le ProcessCounts MaxN [])
      (if (urdr.grammar.nonempty? Fit)
          [ok]
          [error (urdr.grammar.n c-range) [null]])))

(define urdr.grammar.family-spec
  TopologySizes LinkModes ProcessCounts WorkloadShapes
  FaultCounts FaultKinds ScheduleShapes ->
    (urdr.grammar.family-spec-h
      (urdr.grammar.check-sizes TopologySizes)
      TopologySizes LinkModes ProcessCounts WorkloadShapes
      FaultCounts FaultKinds ScheduleShapes))

(define urdr.grammar.family-spec-h
  [error Code Detail] _ _ _ _ _ _ _ -> [error Code Detail]
  [ok] TopologySizes LinkModes ProcessCounts WorkloadShapes
  FaultCounts FaultKinds ScheduleShapes ->
    (urdr.grammar.family-spec-h2
      (urdr.grammar.check-modes LinkModes)
      TopologySizes LinkModes ProcessCounts WorkloadShapes
      FaultCounts FaultKinds ScheduleShapes))

(define urdr.grammar.family-spec-h2
  [error Code Detail] _ _ _ _ _ _ _ -> [error Code Detail]
  [ok] TopologySizes LinkModes ProcessCounts WorkloadShapes
  FaultCounts FaultKinds ScheduleShapes ->
    (urdr.grammar.family-spec-h3
      (urdr.grammar.check-sizes ProcessCounts)
      TopologySizes LinkModes ProcessCounts WorkloadShapes
      FaultCounts FaultKinds ScheduleShapes))

(define urdr.grammar.family-spec-h3
  [error Code Detail] _ _ _ _ _ _ _ -> [error Code Detail]
  [ok] TopologySizes LinkModes ProcessCounts WorkloadShapes
  FaultCounts FaultKinds ScheduleShapes ->
    (urdr.grammar.family-spec-h4
      (urdr.grammar.check-shapes WorkloadShapes)
      TopologySizes LinkModes ProcessCounts WorkloadShapes
      FaultCounts FaultKinds ScheduleShapes))

(define urdr.grammar.family-spec-h4
  [error Code Detail] _ _ _ _ _ _ _ -> [error Code Detail]
  [ok] TopologySizes LinkModes ProcessCounts WorkloadShapes
  FaultCounts FaultKinds ScheduleShapes ->
    (urdr.grammar.family-spec-h5
      (urdr.grammar.check-counts-nn FaultCounts)
      TopologySizes LinkModes ProcessCounts WorkloadShapes
      FaultCounts FaultKinds ScheduleShapes))

(define urdr.grammar.family-spec-h5
  [error Code Detail] _ _ _ _ _ _ _ -> [error Code Detail]
  [ok] TopologySizes LinkModes ProcessCounts WorkloadShapes
  FaultCounts FaultKinds ScheduleShapes ->
    (urdr.grammar.family-spec-h6
      (urdr.grammar.check-kinds FaultKinds)
      TopologySizes LinkModes ProcessCounts WorkloadShapes
      FaultCounts FaultKinds ScheduleShapes))

(define urdr.grammar.family-spec-h6
  [error Code Detail] _ _ _ _ _ _ _ -> [error Code Detail]
  [ok] TopologySizes LinkModes ProcessCounts WorkloadShapes
  FaultCounts FaultKinds ScheduleShapes ->
    (urdr.grammar.family-spec-h7
      (urdr.grammar.check-schedules ScheduleShapes)
      TopologySizes LinkModes ProcessCounts WorkloadShapes
      FaultCounts FaultKinds ScheduleShapes))

(define urdr.grammar.family-spec-h7
  [error Code Detail] _ _ _ _ _ _ _ -> [error Code Detail]
  [ok] TopologySizes LinkModes ProcessCounts WorkloadShapes
  FaultCounts FaultKinds ScheduleShapes ->
    (urdr.grammar.family-spec-h8
      (urdr.grammar.check-fit TopologySizes ProcessCounts)
      TopologySizes LinkModes ProcessCounts WorkloadShapes
      FaultCounts FaultKinds ScheduleShapes))

(define urdr.grammar.family-spec-h8
  [error Code Detail] _ _ _ _ _ _ _ -> [error Code Detail]
  [ok] TopologySizes LinkModes ProcessCounts WorkloadShapes
  FaultCounts FaultKinds ScheduleShapes ->
    [ok [family-spec TopologySizes LinkModes ProcessCounts
          WorkloadShapes FaultCounts FaultKinds ScheduleShapes]])

\\ ---------------------------------------------------------------
\\ Alternative records (canonical, ascending keys)
\\ ---------------------------------------------------------------
\\
\\ Topology alternative keys: link-mode, size
\\ Workload alternative keys: process-count, shape
\\ Fault alternative keys: count, kind, schedule

(define urdr.grammar.topo-alt
  Size Mode ->
    [record
      [[(urdr.grammar.n k-link-mode)
        [symbol (urdr.grammar.link-mode-octets Mode)]]
       [(urdr.grammar.n k-size) (urdr.grammar.big Size)]]])

(define urdr.grammar.work-alt
  Count Shape ->
    [record
      [[(urdr.grammar.n k-process-count) (urdr.grammar.big Count)]
       [(urdr.grammar.n k-shape)
        [symbol (urdr.grammar.workload-shape-octets Shape)]]]])

(define urdr.grammar.fault-alt
  Count Kind Schedule ->
    [record
      [[(urdr.grammar.n k-count) (urdr.grammar.big Count)]
       [(urdr.grammar.n k-kind)
        [symbol (urdr.grammar.fault-kind-octets Kind)]]
       [(urdr.grammar.n k-schedule)
        [symbol (urdr.grammar.schedule-shape-octets Schedule)]]]])

\\ Cartesian products in fixed nested order so alternatives are
\\ deterministically ordered (outer list order is author order).

(define urdr.grammar.topo-alts
  Sizes Modes -> (urdr.grammar.topo-alts-sizes Sizes Modes []))

(define urdr.grammar.topo-alts-sizes
  [] _ Acc -> (urdr.canonical.rev Acc)
  [S | Ss] Modes Acc ->
    (urdr.grammar.topo-alts-sizes
      Ss Modes (urdr.grammar.topo-alts-modes S Modes Acc)))

(define urdr.grammar.topo-alts-modes
  _ [] Acc -> Acc
  S [M | Ms] Acc ->
    (urdr.grammar.topo-alts-modes
      S Ms [(urdr.grammar.topo-alt S M) | Acc]))

(define urdr.grammar.work-alts
  Counts Shapes -> (urdr.grammar.work-alts-counts Counts Shapes []))

(define urdr.grammar.work-alts-counts
  [] _ Acc -> (urdr.canonical.rev Acc)
  [C | Cs] Shapes Acc ->
    (urdr.grammar.work-alts-counts
      Cs Shapes (urdr.grammar.work-alts-shapes C Shapes Acc)))

(define urdr.grammar.work-alts-shapes
  _ [] Acc -> Acc
  C [S | Ss] Acc ->
    (urdr.grammar.work-alts-shapes
      C Ss [(urdr.grammar.work-alt C S) | Acc]))

(define urdr.grammar.fault-alts
  Counts Kinds Schedules ->
    (urdr.grammar.fault-alts-counts Counts Kinds Schedules []))

(define urdr.grammar.fault-alts-counts
  [] _ _ Acc -> (urdr.canonical.rev Acc)
  [C | Cs] Kinds Schedules Acc ->
    (urdr.grammar.fault-alts-counts
      Cs Kinds Schedules
      (urdr.grammar.fault-alts-kinds C Kinds Schedules Acc)))

(define urdr.grammar.fault-alts-kinds
  _ [] _ Acc -> Acc
  C [K | Ks] Schedules Acc ->
    (urdr.grammar.fault-alts-kinds
      C Ks Schedules
      (urdr.grammar.fault-alts-schedules C K Schedules Acc)))

(define urdr.grammar.fault-alts-schedules
  _ _ [] Acc -> Acc
  C K [S | Ss] Acc ->
    (urdr.grammar.fault-alts-schedules
      C K Ss [(urdr.grammar.fault-alt C K S) | Acc]))

\\ ---------------------------------------------------------------
\\ Field projection from selected alternatives
\\ ---------------------------------------------------------------

(define urdr.grammar.field
  [] _ -> none
  [[Key Value] | Rest] Want ->
    (if (= Key Want) Value (urdr.grammar.field Rest Want))
  [_ | Rest] Want -> (urdr.grammar.field Rest Want))

(define urdr.grammar.small-of
  N -> N where (and (number? N) (>= N 0))
  [big 1 Mag] -> (urdr.grammar.mag-small Mag 0)
  [big -1 _] -> 0
  [big 0 _] -> 0
  _ -> 0)

(define urdr.grammar.mag-small
  [] Acc -> Acc
  [D | Ds] Acc -> (urdr.grammar.mag-small Ds (+ (* Acc 10000) D)))

(define urdr.grammar.symbol-bytes
  [symbol Bs] -> Bs
  _ -> [])

(define urdr.grammar.link-mode-of-bytes
  Bs ->
    (if (= Bs (urdr.grammar.n w-line))
        line
        (if (= Bs (urdr.grammar.n w-star))
            star
            (if (= Bs (urdr.grammar.n w-mesh))
                mesh
                line))))

(define urdr.grammar.workload-shape-of-bytes
  Bs ->
    (if (= Bs (urdr.grammar.n w-burst))
        burst
        (if (= Bs (urdr.grammar.n w-steady))
            steady
            (if (= Bs (urdr.grammar.n w-staggered))
                staggered
                steady))))

(define urdr.grammar.fault-kind-of-bytes
  Bs ->
    (if (= Bs (urdr.grammar.n w-crash))
        crash
        (if (= Bs (urdr.grammar.n w-delay))
            delay
            (if (= Bs (urdr.grammar.n w-drop))
                drop
                (if (= Bs (urdr.grammar.n w-partition))
                    partition
                    (if (= Bs (urdr.grammar.n w-restart))
                        restart
                        crash))))))

(define urdr.grammar.schedule-shape-of-bytes
  Bs ->
    (if (= Bs (urdr.grammar.n w-front))
        front
        (if (= Bs (urdr.grammar.n w-middle))
            middle
            (if (= Bs (urdr.grammar.n w-back))
                back
                (if (= Bs (urdr.grammar.n w-uniform))
                    uniform
                    front)))))

(define urdr.grammar.read-topo
  [record Fields] ->
    [topo
      (urdr.grammar.small-of
        (urdr.grammar.field Fields (urdr.grammar.n k-size)))
      (urdr.grammar.link-mode-of-bytes
        (urdr.grammar.symbol-bytes
          (urdr.grammar.field Fields (urdr.grammar.n k-link-mode))))]
  _ -> [topo 1 line])

(define urdr.grammar.read-work
  [record Fields] ->
    [work
      (urdr.grammar.small-of
        (urdr.grammar.field Fields (urdr.grammar.n k-process-count)))
      (urdr.grammar.workload-shape-of-bytes
        (urdr.grammar.symbol-bytes
          (urdr.grammar.field Fields (urdr.grammar.n k-shape))))]
  _ -> [work 1 steady])

(define urdr.grammar.read-fault
  [record Fields] ->
    [fault-sel
      (urdr.grammar.small-of
        (urdr.grammar.field Fields (urdr.grammar.n k-count)))
      (urdr.grammar.fault-kind-of-bytes
        (urdr.grammar.symbol-bytes
          (urdr.grammar.field Fields (urdr.grammar.n k-kind))))
      (urdr.grammar.schedule-shape-of-bytes
        (urdr.grammar.symbol-bytes
          (urdr.grammar.field Fields (urdr.grammar.n k-schedule))))]
  _ -> [fault-sel 0 crash front])

\\ ---------------------------------------------------------------
\\ Materialize topology / workload / faults / components
\\ ---------------------------------------------------------------

(define urdr.grammar.node-record
  I ->
    [record
      [[(urdr.grammar.n k-address) (urdr.grammar.big I)]
       [(urdr.grammar.n k-id)
        [symbol (urdr.grammar.node-id-bytes I)]]]])

(define urdr.grammar.nodes-value
  N -> [list (urdr.grammar.nodes-loop 0 N [])])

(define urdr.grammar.nodes-loop
  I N Acc ->
    (if (>= I N)
        (urdr.canonical.rev Acc)
        (urdr.grammar.nodes-loop
          (+ I 1) N [(urdr.grammar.node-record I) | Acc])))

(define urdr.grammar.link-record
  From To ->
    [record
      [[(urdr.grammar.n k-from)
        [symbol (urdr.grammar.node-id-bytes From)]]
       [(urdr.grammar.n k-to)
        [symbol (urdr.grammar.node-id-bytes To)]]]])

\\ Line: n0→n1→…→n{N-1}. Empty when N < 2.
(define urdr.grammar.links-line
  N -> [list (urdr.grammar.links-line-loop 0 N [])])

(define urdr.grammar.links-line-loop
  I N Acc ->
    (if (>= (+ I 1) N)
        (urdr.canonical.rev Acc)
        (urdr.grammar.links-line-loop
          (+ I 1) N
          [(urdr.grammar.link-record I (+ I 1)) | Acc])))

\\ Star: n0→n1, n0→n2, …
(define urdr.grammar.links-star
  N -> [list (urdr.grammar.links-star-loop 1 N [])])

(define urdr.grammar.links-star-loop
  I N Acc ->
    (if (>= I N)
        (urdr.canonical.rev Acc)
        (urdr.grammar.links-star-loop
          (+ I 1) N
          [(urdr.grammar.link-record 0 I) | Acc])))

\\ Mesh: every ordered pair i≠j, outer i ascending, inner j ascending.
(define urdr.grammar.links-mesh
  N -> [list (urdr.grammar.links-mesh-i 0 N [])])

(define urdr.grammar.links-mesh-i
  I N Acc ->
    (if (>= I N)
        (urdr.canonical.rev Acc)
        (urdr.grammar.links-mesh-i
          (+ I 1) N (urdr.grammar.links-mesh-j I 0 N Acc))))

(define urdr.grammar.links-mesh-j
  I J N Acc ->
    (if (>= J N)
        Acc
        (if (= I J)
            (urdr.grammar.links-mesh-j I (+ J 1) N Acc)
            (urdr.grammar.links-mesh-j
              I (+ J 1) N
              [(urdr.grammar.link-record I J) | Acc]))))

(define urdr.grammar.links-value
  N line -> (urdr.grammar.links-line N)
  N star -> (urdr.grammar.links-star N)
  N mesh -> (urdr.grammar.links-mesh N)
  N _ -> (urdr.grammar.links-line N))

(define urdr.grammar.topology-value
  N Mode ->
    [record
      [[(urdr.grammar.n k-links) (urdr.grammar.links-value N Mode)]
       [(urdr.grammar.n k-nodes) (urdr.grammar.nodes-value N)]]])

(define urdr.grammar.workload-value
  Count Shape ->
    [record
      [[(urdr.grammar.n k-process-count) (urdr.grammar.big Count)]
       [(urdr.grammar.n k-shape)
        [symbol (urdr.grammar.workload-shape-octets Shape)]]]])

\\ Component roster: process p0..p{P-1} on nodes n0..n{P-1}.
(define urdr.grammar.component-record
  I ->
    [record
      [[(urdr.grammar.n k-id)
        [symbol (urdr.grammar.proc-id-bytes I)]]
       [(urdr.grammar.n k-kind)
        [symbol (urdr.grammar.n w-process)]]
       [(urdr.grammar.n k-node)
        [symbol (urdr.grammar.node-id-bytes I)]]]])

(define urdr.grammar.components-value
  P -> [list (urdr.grammar.components-loop 0 P [])])

(define urdr.grammar.components-loop
  I P Acc ->
    (if (>= I P)
        (urdr.canonical.rev Acc)
        (urdr.grammar.components-loop
          (+ I 1) P [(urdr.grammar.component-record I) | Acc])))

\\ Member indices for fault placement.
\\ front: 0,1,...   back: N-1,N-2,...   middle: around N/2
\\ uniform: spread by step = max(1, N / count) (integer division)
(define urdr.grammar.member-indices
  0 _ _ -> []
  Count N front -> (urdr.grammar.indices-front 0 Count N [])
  Count N back -> (urdr.grammar.indices-back (- N 1) Count N [])
  Count N middle ->
    (urdr.grammar.indices-front
      (urdr.grammar.middle-start Count N) Count N [])
  Count N uniform ->
    (urdr.grammar.indices-uniform 0 Count N
      (urdr.grammar.uniform-step Count N) [])
  Count N _ -> (urdr.grammar.indices-front 0 Count N []))

(define urdr.grammar.middle-start
  Count N ->
    (let Half (urdr.grammar.div N 2)
         Start (- Half (urdr.grammar.div Count 2))
      (if (< Start 0) 0 Start)))

(define urdr.grammar.uniform-step
  Count N ->
    (if (<= Count 0)
        1
        (let S (urdr.grammar.div N Count)
          (if (< S 1) 1 S))))

(define urdr.grammar.indices-front
  I Count N Acc ->
    (if (or (>= (urdr.grammar.length Acc) Count) (>= I N))
        (urdr.canonical.rev Acc)
        (urdr.grammar.indices-front
          (+ I 1) Count N [I | Acc])))

(define urdr.grammar.indices-back
  I Count N Acc ->
    (if (or (>= (urdr.grammar.length Acc) Count) (< I 0))
        (urdr.canonical.rev Acc)
        (urdr.grammar.indices-back
          (- I 1) Count N [I | Acc])))

(define urdr.grammar.indices-uniform
  I Count N Step Acc ->
    (if (or (>= (urdr.grammar.length Acc) Count) (>= I N))
        (urdr.canonical.rev Acc)
        (urdr.grammar.indices-uniform
          (+ I Step) Count N Step [I | Acc])))

(define urdr.grammar.fault-record
  I Kind Member ->
    [record
      [[(urdr.grammar.n k-id)
        [symbol (urdr.grammar.fault-id-bytes I)]]
       [(urdr.grammar.n k-kinds)
        [list [[symbol (urdr.grammar.fault-kind-octets Kind)]]]]
       [(urdr.grammar.n k-members)
        [list [[symbol (urdr.grammar.node-id-bytes Member)]]]]]])

(define urdr.grammar.faults-value
  Count Kind Schedule N ->
    [list (urdr.grammar.faults-loop
            0 Count Kind
            (urdr.grammar.member-indices Count N Schedule) [])])

(define urdr.grammar.faults-loop
  _ 0 _ _ Acc -> (urdr.canonical.rev Acc)
  I Count Kind [] Acc ->
    \\ Fewer members than faults (empty topology / zero count path):
    \\ stop without inventing nodes.
    (urdr.canonical.rev Acc)
  I Count Kind [M | Ms] Acc ->
    (if (>= I Count)
        (urdr.canonical.rev Acc)
        (urdr.grammar.faults-loop
          (+ I 1) Count Kind Ms
          [(urdr.grammar.fault-record I Kind M) | Acc])))

(define urdr.grammar.build-fragment
  Seed N Mode ProcCount Shape FaultCount FaultKind Schedule ->
    [fragment Seed
      (urdr.grammar.topology-value N Mode)
      (urdr.grammar.workload-value ProcCount Shape)
      (urdr.grammar.faults-value FaultCount FaultKind Schedule N)
      (urdr.grammar.components-value ProcCount)])

\\ Canonical projection of a fragment for digests / Wave I wrapping.
\\ Keys ascending: components, faults, seed, topology, workload.
(define urdr.grammar.fragment-value
  [fragment Seed Topology Workload Faults Components] ->
    [record
      [[(urdr.grammar.n k-components) Components]
       [(urdr.grammar.n k-faults) Faults]
       [(urdr.grammar.n k-seed) [bytes Seed]]
       [(urdr.grammar.n k-topology) Topology]
       [(urdr.grammar.n k-workload) Workload]]]
  _ -> [null])

(define urdr.grammar.fragment-digest
  Fragment ->
    (urdr.grammar.fragment-digest-of
      (urdr.eventlog.value-digest
        (urdr.grammar.fragment-value Fragment))))

(define urdr.grammar.fragment-digest-of
  [ok D] ->
    (urdr.eventlog.root-of (urdr.grammar.n t-fragment) [D])
  Error -> Error)

(define urdr.grammar.path-digest
  Choices -> (urdr.search.path-digest Choices))

\\ ---------------------------------------------------------------
\\ Expand: three dependent scenario-kind selections
\\ ---------------------------------------------------------------

(define urdr.grammar.menu
  Id Actor Alts ->
    (urdr.search.menu
      (urdr.grammar.big Id)
      (urdr.int.zero)
      scenario
      (urdr.grammar.n w-grammar)
      Actor
      (urdr.grammar.n w-expand)
      Alts))

(define urdr.grammar.select
  Seed Counter Id Actor Alts ->
    (urdr.grammar.select-of
      Seed Counter
      (urdr.grammar.menu Id Actor Alts)))

(define urdr.grammar.select-of
  Seed Counter [ok Menu] ->
    (urdr.search.select baseline Seed Counter Menu)
  _ _ [error Code Detail] -> [error Code Detail]
  _ _ _ -> [error (urdr.grammar.n c-menu) [null]])

\\ Build the decision transcript: for each choice, schedule the menu
\\ then advance. Order matches Wave F explore BUILD convention so
\\ urdr.replay.run accepts the transcript on a fixture world.
(define urdr.grammar.transcript-of
  Choices -> (urdr.grammar.transcript-h Choices []))

(define urdr.grammar.transcript-h
  [] Acc -> (urdr.canonical.rev Acc)
  [C | Cs] Acc ->
    (urdr.grammar.transcript-h
      Cs
      [[advance-to-next-event]
       (urdr.search.schedule-input
         C
         (urdr.grammar.n w-grammar)
         (urdr.grammar.actor-of C)
         (urdr.grammar.n w-expand))
       | Acc]))

\\ Actor octets recovered from the choice coordinates when present;
\\ fall back to grammar subsystem actor for schedule payload identity.
\\ schedule-input only needs Sub/Actor/Purpose for the menu; the search
\\ choice-record does not store actor, so we pass phase actors explicitly
\\ via a parallel list when building. See expand-finish.

(define urdr.grammar.actor-of
  _ -> (urdr.grammar.n w-grammar))

(define urdr.grammar.transcript-with-actors
  Choices Actors ->
    (urdr.grammar.transcript-actors-h Choices Actors []))

(define urdr.grammar.transcript-actors-h
  [] _ Acc -> (urdr.canonical.rev Acc)
  [C | Cs] [A | As] Acc ->
    (urdr.grammar.transcript-actors-h
      Cs As
      [[advance-to-next-event]
       (urdr.search.schedule-input
         C
         (urdr.grammar.n w-grammar)
         A
         (urdr.grammar.n w-expand))
       | Acc])
  _ _ Acc -> (urdr.canonical.rev Acc))

(define urdr.grammar.expand
  Seed Spec ->
    (if (not (= (hd (urdr.prng.octets.check Seed)) ok))
        [error (urdr.grammar.n c-seed) [null]]
        (urdr.grammar.expand-spec Seed Spec)))

(define urdr.grammar.expand-spec
  Seed
  [family-spec TopologySizes LinkModes ProcessCounts WorkloadShapes
               FaultCounts FaultKinds ScheduleShapes] ->
    (urdr.grammar.expand-topo
      Seed
      (urdr.grammar.topo-alts TopologySizes LinkModes)
      ProcessCounts WorkloadShapes
      FaultCounts FaultKinds ScheduleShapes)
  _ _ -> [error (urdr.grammar.n c-spec) [null]])

(define urdr.grammar.expand-topo
  Seed TopoAlts ProcessCounts WorkloadShapes
  FaultCounts FaultKinds ScheduleShapes ->
    (if (not (urdr.grammar.nonempty? TopoAlts))
        [error (urdr.grammar.n c-empty) [null]]
        (urdr.grammar.expand-topo-sel
          Seed
          (urdr.grammar.select
            Seed (urdr.int.zero) 0
            (urdr.grammar.n w-topology) TopoAlts)
          ProcessCounts WorkloadShapes
          FaultCounts FaultKinds ScheduleShapes)))

(define urdr.grammar.expand-topo-sel
  Seed [error Code Detail] _ _ _ _ _ -> [error Code Detail]
  Seed [ok [TopoChoice Next0]] ProcessCounts WorkloadShapes
  FaultCounts FaultKinds ScheduleShapes ->
    (let Topo (urdr.grammar.read-topo
                (urdr.search.choice-selected TopoChoice))
      (urdr.grammar.expand-work
        Seed TopoChoice Next0 Topo
        ProcessCounts WorkloadShapes
        FaultCounts FaultKinds ScheduleShapes))
  _ _ _ _ _ _ _ -> [error (urdr.grammar.n c-select) [null]])

(define urdr.grammar.expand-work
  Seed TopoChoice Counter [topo N Mode]
  ProcessCounts WorkloadShapes
  FaultCounts FaultKinds ScheduleShapes ->
    (let Fit (urdr.grammar.filter-le ProcessCounts N [])
      (if (not (urdr.grammar.nonempty? Fit))
          [error (urdr.grammar.n c-range) [null]]
          (urdr.grammar.expand-work-sel
            Seed TopoChoice Counter N Mode
            (urdr.grammar.select
              Seed Counter 1
              (urdr.grammar.n w-workload)
              (urdr.grammar.work-alts Fit WorkloadShapes))
            FaultCounts FaultKinds ScheduleShapes)))
  _ _ _ _ _ _ _ _ _ -> [error (urdr.grammar.n c-expand) [null]])

(define urdr.grammar.expand-work-sel
  Seed TopoChoice _ _ _ [error Code Detail] _ _ _ ->
    [error Code Detail]
  Seed TopoChoice Counter N Mode [ok [WorkChoice Next1]]
  FaultCounts FaultKinds ScheduleShapes ->
    (let Work (urdr.grammar.read-work
                (urdr.search.choice-selected WorkChoice))
      (urdr.grammar.expand-fault
        Seed TopoChoice WorkChoice Next1 N Mode Work
        FaultCounts FaultKinds ScheduleShapes))
  _ _ _ _ _ _ _ _ _ -> [error (urdr.grammar.n c-select) [null]])

(define urdr.grammar.expand-fault
  Seed TopoChoice WorkChoice Counter N Mode [work ProcCount Shape]
  FaultCounts FaultKinds ScheduleShapes ->
    (let FaultAlts (urdr.grammar.fault-alts
                     FaultCounts FaultKinds ScheduleShapes)
      (if (not (urdr.grammar.nonempty? FaultAlts))
          [error (urdr.grammar.n c-empty) [null]]
          (urdr.grammar.expand-fault-sel
            Seed TopoChoice WorkChoice Counter N Mode
            ProcCount Shape
            (urdr.grammar.select
              Seed Counter 2
              (urdr.grammar.n w-fault-schedule) FaultAlts))))
  _ _ _ _ _ _ _ _ _ _ -> [error (urdr.grammar.n c-expand) [null]])

(define urdr.grammar.expand-fault-sel
  Seed TopoChoice WorkChoice _ _ _ _ _ [error Code Detail] ->
    [error Code Detail]
  Seed TopoChoice WorkChoice Counter N Mode ProcCount Shape
  [ok [FaultChoice Next2]] ->
    (let Fault (urdr.grammar.read-fault
                 (urdr.search.choice-selected FaultChoice))
      (urdr.grammar.expand-finish
        Seed TopoChoice WorkChoice FaultChoice
        N Mode ProcCount Shape Fault))
  _ _ _ _ _ _ _ _ _ -> [error (urdr.grammar.n c-select) [null]])

(define urdr.grammar.expand-finish
  Seed TopoChoice WorkChoice FaultChoice
  N Mode ProcCount Shape
  [fault-sel FaultCount FaultKind Schedule] ->
    (let Fragment (urdr.grammar.build-fragment
                    Seed N Mode ProcCount Shape
                    FaultCount FaultKind Schedule)
         Choices [TopoChoice WorkChoice FaultChoice]
         Actors [(urdr.grammar.n w-topology)
                 (urdr.grammar.n w-workload)
                 (urdr.grammar.n w-fault-schedule)]
         Transcript (urdr.grammar.transcript-with-actors
                      Choices Actors)
      [ok [expanded Fragment Choices Transcript]])
  _ _ _ _ _ _ _ _ _ -> [error (urdr.grammar.n c-expand) [null]])

(define urdr.grammar.result-fragment
  [expanded Fragment _ _] -> Fragment)

(define urdr.grammar.result-choices
  [expanded _ Choices _] -> Choices)

(define urdr.grammar.result-transcript
  [expanded _ _ Transcript] -> Transcript)
