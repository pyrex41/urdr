\\ Deterministic property evaluators and canonical verdicts
\\ (SPEC.md 18.1, M1 plan Wave D). Requires canonical.shen (ADR 0002) and
\\ integer.shen (ADR 0003) to be loaded by the caller. Nothing else is
\\ required: world.shen and scenario.shen are integrated by SHAPE, not by
\\ a code dependency, so this module can be loaded and tested alone.
\\
\\ Pure: no I/O, no host time, no host randomness, no floating point, no
\\ defprolog. A verdict is a total function of (canonical trace,
\\ compiled property spec) and of nothing else. Every operation returns
\\ [ok ...] or [error STABLE-CODE] and performs no work before validating.
\\
\\ NOT owned here (docs/module-boundaries.md): host-log interpretation.
\\ The only accepted input is a canonical trace of reducer-stamped facts.
\\ There is no code path that reads text, files, or host output.
\\
\\ =====================================================================
\\ 1. The canonical trace
\\ =====================================================================
\\
\\   trace ::= [trace [ENTRY ...]]
\\
\\ An ENTRY is exactly the record the world reducer stamps onto a
\\ component fact (urdr.world.fact-value), reused verbatim so that no
\\ translation layer sits between what the reducer recorded and what a
\\ verdict is computed from:
\\
\\   [record [[component [bytes NAME]]
\\            [event-id  INTEGER]
\\            [name      [symbol FACT-NAME]]
\\            [time      INTEGER]
\\            [type      [symbol fact]]
\\            [value     CANONICAL-VALUE]]]
\\
\\ Keys are exactly those six, in that order (which is strictly ascending
\\ unsigned-ASCII order, so the record is canonical). Any other key set,
\\ order, or arity is properties-trace-entry-shape.
\\
\\ Validation, all fail-closed:
\\   - component and name are canonical symbols;
\\   - type is exactly the symbol `fact`. M1 traces carry facts only. An
\\     event-record type is a later, deliberate extension, not a silent
\\     one (properties-trace-entry-type);
\\   - event-id and time are valid non-negative software integers;
\\   - value is a canonical value;
\\   - the sequence is non-decreasing in (time, event-id). That is the
\\     order the reducer produces (events are drained from the pending
\\     queue in (time, id) order and facts are stamped with the draining
\\     event), and it is what makes "before", "prefix", and "window" total
\\     functions of the trace. Two entries may share (time, event-id):
\\     one component step may emit several facts. Going backwards is
\\     properties-trace-order.
\\
\\ Trace position: an entry's `index` is its 0-based position in the
\\ trace, held as a software integer. Index is the ordering used by every
\\ evaluator; event-id is reported but never used for ordering, because
\\ event ids are allocated at scheduling time and are not monotone in
\\ processing order.
\\
\\ urdr.properties.trace-of-world lifts a world/v2 value to a trace by
\\ taking its fact log unchanged.
\\
\\ =====================================================================
\\ 2. The term and predicate language (shared by all three classes)
\\ =====================================================================
\\
\\ Every node is one canonical record:
\\
\\   NODE ::= [record [[args [list ARG ...]] [op [symbol OP]]]]
\\
\\ Arity is fixed per op and checked at load time, so evaluation is total
\\ and terminates by structure: each recursive call is on a strict
\\ subterm of a finite canonical value.
\\
\\ TERMS evaluate to [val V] or [undef]:
\\
\\   op        args                 meaning
\\   --------  -------------------  ------------------------------------
\\   this      []                   the value of the entry under test.
\\                                  [undef] outside a pattern.
\\   const     [VALUE]              a literal canonical value.
\\   fact      [[symbol NAME]]      the value of the most recent entry
\\                                  named NAME in the evaluation prefix.
\\                                  [undef] if there is none.
\\   fact-of   [[symbol NAME]
\\              [symbol SOURCE]]    same, restricted to entries emitted
\\                                  by component SOURCE.
\\   project   [TERM INTEGER]       the Nth element (0-based) of TERM
\\                                  when TERM is [list ...]; else [undef].
\\   key       [TERM [symbol KEY]]  the KEY field of TERM when TERM is
\\                                  [record ...]; else [undef].
\\
\\ Component-state projection in M1 is expressed with fact / fact-of plus
\\ project / key. A component publishes state by emitting facts, which the
\\ reducer stamps; nothing else about a component is observable from a
\\ trace, and that is deliberate — it keeps evaluation a pure function of
\\ the recorded trace instead of of a live registry.
\\
\\ PREDICATES evaluate to true or false, never to an error:
\\
\\   op        args           meaning
\\   --------  -------------  -------------------------------------------
\\   true      []             true.
\\   false     []             false.
\\   defined   [TERM]         TERM evaluates to a value.
\\   eq        [TERM TERM]    both defined and canonically equal.
\\   ne        [TERM TERM]    both defined and NOT canonically equal.
\\   lt le gt ge  [TERM TERM] both defined, both software integers, and
\\                            the comparison holds; false otherwise.
\\   not       [PRED]         classical negation of a predicate.
\\   and       [PRED PRED]    conjunction.
\\   or        [PRED PRED]    disjunction.
\\
\\ Undefinedness is fail-closed on BOTH polarities: if either side of a
\\ comparison is undefined, eq is false AND ne is false, and every
\\ ordering comparison is false. `ne` is therefore NOT `(not eq)`. This is
\\ deliberate: a missing fact must not make a property true by accident.
\\ `defined` is the explicit way to ask about presence, and `not` is the
\\ explicit way to ask for classical negation.
\\
\\ Non-integer operands of lt/le/gt/ge are false rather than an error, for
\\ the same reason: a comparison that cannot be performed has not been
\\ satisfied.
\\
\\ EVALUATION PREFIX. Terms are evaluated in an environment
\\ [env REVERSE-PREFIX CURRENT]:
\\   - REVERSE-PREFIX is the relevant trace entries in reverse
\\     chronological order (most recent first), so "most recent fact
\\     named N" is the first match found;
\\   - CURRENT is [some VALUE] inside a pattern (the entry under test) and
\\     none inside an invariant predicate.
\\ For an invariant at observation point (at, id) the prefix is every
\\ entry with time <= at — an observation sees the end of its logical
\\ instant, including every entry stamped at exactly that time.
\\ For a pattern the prefix is every entry strictly before the entry under
\\ test, so a pattern may refer to history without seeing its own future.
\\
\\ =====================================================================
\\ 3. Pattern
\\ =====================================================================
\\
\\   PATTERN ::= [record [[name   [symbol FACT-NAME]]
\\                        [source [symbol COMPONENT] | [null]]
\\                        [value  PRED | [null]]]]
\\
\\ An entry matches when its fact name equals name, its component equals
\\ source (or source is [null] = any component), and value is [null] or
\\ the predicate holds with the entry's value bound to `this`.
\\
\\ =====================================================================
\\ 4. Per-class spec schemas
\\ =====================================================================
\\
\\ The scenario DSL (shen/scenario/scenario.shen) validates a property
\\ declaration as [property CLASS ID SPEC] and deliberately leaves SPEC
\\ opaque. The per-class schema below is defined and enforced HERE, at
\\ load time, strictly and fail-closed. scenario.shen is not changed.
\\
\\ ---- invariant --------------------------------------------------------
\\
\\   [record [[points [list [symbol POINT-ID] ...]]
\\            [pred   PRED]]]
\\
\\ points must be non-empty and strictly ascending; every id must resolve
\\ against the scenario's declared observation points [observation AT ID].
\\ There is no "all points" default: an unnamed point is a typo, not a
\\ wildcard.
\\
\\ Verdict: PASS iff pred holds at every named point. The points are
\\ evaluated in (at, id) order, so the reported witness is the earliest
\\ failing point in logical time.
\\ Witness on FAIL: the point id and its logical time, plus the index and
\\ event-id of the last entry at or before it, or [null] for both when the
\\ prefix is empty. Witness on PASS: no-witness — a pass is a statement
\\ about every point, so no single event witnesses it.
\\
\\ ---- temporal ---------------------------------------------------------
\\
\\   [record [[args [list ...]] [form [symbol FORM]]]]
\\
\\ FORM is one of exactly three; anything else is
\\ properties-temporal-form-unsupported.
\\
\\   before             args [PATTERN-A PATTERN-B]
\\     PASS iff an A-match occurs at a strictly smaller index than the
\\     first B-match. Deliberately STRONG: if either pattern never
\\     matches, the verdict is FAIL. A never-occurring B does not
\\     vacuously discharge an ordering claim.
\\     FAIL witness: the first B-match when B occurred at or before every
\\     A-match; no-witness when B never occurred at all.
\\     PASS witness: the first A-match, the earliest event that makes the
\\     ordering true.
\\     If one entry matches both patterns the indexes are equal, "strictly
\\     before" is unsatisfied, and the verdict is FAIL.
\\
\\   always-eventually  args [PATTERN-A PATTERN-B WINDOW]
\\     For every A-match a, some B-match b must exist with
\\     index(b) > index(a) and time(b) <= time(a) + WINDOW. WINDOW is a
\\     non-negative software integer of logical time; the bound is
\\     INCLUSIVE, so a consequent at exactly time(a) + WINDOW satisfies it.
\\     PASS with no-witness when at least one A matched and every
\\     obligation was discharged.
\\     PASS with the `vacuous` marker when no A ever matched (see 5).
\\     FAIL with the first A-match whose obligation is unfulfilled.
\\
\\   never              args [PATTERN-A]
\\     PASS iff no entry matches A. PASS witness: no-witness.
\\     FAIL witness: the first matching entry.
\\
\\ ---- liveness ---------------------------------------------------------
\\
\\   [record [[deadline INTEGER] [pattern PATTERN]]]
\\
\\ PASS iff some entry matches pattern at logical time <= deadline. The
\\ deadline is a non-negative software integer and the bound is INCLUSIVE.
\\ PASS witness: the first matching entry at or before the deadline.
\\ FAIL witness: the first matching entry when every match is late (the
\\ event happened, but too late — the distinction a shrinker needs);
\\ no-witness when nothing ever matched.
\\
\\ ---- reserved classes -------------------------------------------------
\\
\\ crash, log, and metamorphic (SPEC.md 18.1) need real guests (M3+).
\\ Their names are reserved constants here and every load of one is
\\ properties-class-unsupported-in-m1. The scenario DSL already rejects
\\ them at declaration; this is defence in depth on the second door, and
\\ scenario.shen is not modified to achieve it.
\\
\\ =====================================================================
\\ 5. Finite-trace semantics, stated once and pinned by fixtures
\\ =====================================================================
\\
\\ A recorded trace is finite and is the whole of the evidence. The rules
\\ below follow from one principle: an obligation that the evidence does
\\ not discharge is NOT discharged. Nothing is given the benefit of the
\\ doubt at end of trace.
\\
\\ (a) An unfulfilled eventuality FAILS. always-eventually fails at end of
\\     trace even when the window has not yet elapsed in logical time.
\\     A run that stops early can therefore fail a property a longer run
\\     would pass; that is the fail-closed direction, and the remedy is to
\\     run the scenario long enough, not to weaken the verdict.
\\ (b) A missing liveness event FAILS (empty trace, or no match, or every
\\     match after the deadline).
\\ (c) `before` is strong: a missing A or a missing B FAILS.
\\ (d) `never` is a safety property: the empty trace PASSES it. This is
\\     not the benefit of the doubt — there is no outstanding obligation,
\\     and the evidence contains no violation.
\\ (e) A vacuous antecedent (always-eventually with no A-match anywhere)
\\     PASSES, and the verdict carries the distinct marker `vacuous`
\\     instead of no-witness. The universally quantified implication is
\\     genuinely true over an empty antecedent set, so reporting FAIL
\\     would be dishonest; but a property that never fired is also not
\\     evidence of anything, so the vacuity is made machine-visible rather
\\     than hidden inside a PASS. Consumers (certificates, reports) can
\\     surface "this property never fired" without re-deriving it.
\\ (f) The empty trace, per class:
\\       invariant           every fact term is [undef]. [op true] passes;
\\                           any comparison is false, so a real invariant
\\                           FAILS. No evidence is not proof.
\\       temporal before     FAIL (no A, no B), witness no-witness.
\\       temporal a-e        PASS with `vacuous` (no antecedent).
\\       temporal never      PASS, witness no-witness.
\\       liveness            FAIL, witness no-witness.
\\
\\ =====================================================================
\\ 6. Verdicts
\\ =====================================================================
\\
\\ The certifying verdict value is
\\
\\   [record [[class    [symbol CLASS]]
\\            [property [symbol ID]]
\\            [result   [symbol PASS] | [symbol FAIL]]
\\            [witness  WITNESS]]]
\\
\\   WITNESS ::= [symbol no-witness]
\\             | [symbol vacuous]
\\             | [record [[event-id INTEGER | [null]]
\\                        [index    INTEGER | [null]]
\\                        [point    [symbol POINT-ID] | [null]]
\\                        [time     INTEGER]]]
\\
\\ urdr.properties.world-verdict projects the same verdict onto the tuple
\\ the world already stores in its verdicts slot,
\\ [verdict PROPERTY-ID RESULT EVENT-ID TIME], which urdr.world.verdict-
\\ value renders. That projection is lossy: class and witness kind do not
\\ fit the existing four-field slot, and when there is no witness both
\\ integers are zero. The record above is the certifying artifact; the
\\ world slot carries the pass/fail into the existing snapshot digest.

\\ =====================================================================
\\ 7. Public entry points
\\ =====================================================================
\\
\\   check-trace        TRACE -> [ok] | [error CODE]
\\   trace-of-world     WORLD -> [ok TRACE] | [error CODE]
\\   load               PROPERTY OBSERVATIONS -> [ok LOADED] | [error CODE]
\\   load-all           PROPERTIES OBSERVATIONS
\\                        -> [ok [LOADED ...]] | [error CODE]
\\   evaluate           LOADED TRACE -> [ok VERDICT] | [error CODE]
\\   evaluate-all       [LOADED ...] TRACE
\\                        -> [ok [VERDICT ...]] | [error CODE]
\\   check              PROPERTIES OBSERVATIONS TRACE
\\                        -> [ok [VERDICT ...]] | [error CODE]
\\   verdict-value      VERDICT -> canonical record (section 6)
\\   verdict-values     [VERDICT ...] -> [canonical record ...]
\\   frame              [VERDICT ...] -> [ok OCTETS] | [error CODE]
\\   world-verdict      VERDICT -> the world verdicts-slot tuple
\\   world-verdicts     [VERDICT ...] -> [tuple ...]
\\   verdict-class / verdict-id / verdict-result / verdict-witness
\\
\\ PROPERTY is the scenario DSL's [property CLASS ID SPEC]; OBSERVATIONS
\\ is its [[observation AT ID] ...]. Loading is separated from evaluation
\\ so a scenario's declarations are rejected before any run starts, not
\\ after one has produced a trace.

\\ ---------------------------------------------------------------------
\\ ASCII names, spelled as octet lists so no host string model enters
\\ semantics (the discipline of world.shen and scenario.shen).
\\ ---------------------------------------------------------------------

(define urdr.properties.n.args
  -> [97 114 103 115])

(define urdr.properties.n.class
  -> [99 108 97 115 115])

(define urdr.properties.n.component
  -> [99 111 109 112 111 110 101 110 116])

(define urdr.properties.n.deadline
  -> [100 101 97 100 108 105 110 101])

(define urdr.properties.n.event-id
  -> [101 118 101 110 116 45 105 100])

(define urdr.properties.n.form
  -> [102 111 114 109])

(define urdr.properties.n.index
  -> [105 110 100 101 120])

(define urdr.properties.n.name
  -> [110 97 109 101])

(define urdr.properties.n.op
  -> [111 112])

(define urdr.properties.n.pattern
  -> [112 97 116 116 101 114 110])

(define urdr.properties.n.point
  -> [112 111 105 110 116])

(define urdr.properties.n.points
  -> [112 111 105 110 116 115])

(define urdr.properties.n.pred
  -> [112 114 101 100])

(define urdr.properties.n.property
  -> [112 114 111 112 101 114 116 121])

(define urdr.properties.n.result
  -> [114 101 115 117 108 116])

(define urdr.properties.n.source
  -> [115 111 117 114 99 101])

(define urdr.properties.n.time
  -> [116 105 109 101])

(define urdr.properties.n.type
  -> [116 121 112 101])

(define urdr.properties.n.value
  -> [118 97 108 117 101])

(define urdr.properties.n.witness
  -> [119 105 116 110 101 115 115])

(define urdr.properties.n.invariant
  -> [105 110 118 97 114 105 97 110 116])

(define urdr.properties.n.liveness
  -> [108 105 118 101 110 101 115 115])

(define urdr.properties.n.temporal
  -> [116 101 109 112 111 114 97 108])

(define urdr.properties.n.crash
  -> [99 114 97 115 104])

(define urdr.properties.n.log
  -> [108 111 103])

(define urdr.properties.n.metamorphic
  -> [109 101 116 97 109 111 114 112 104 105 99])

(define urdr.properties.n.fact
  -> [102 97 99 116])

(define urdr.properties.n.PASS
  -> [80 65 83 83])

(define urdr.properties.n.FAIL
  -> [70 65 73 76])

(define urdr.properties.n.no-witness
  -> [110 111 45 119 105 116 110 101 115 115])

(define urdr.properties.n.vacuous
  -> [118 97 99 117 111 117 115])

(define urdr.properties.n.const
  -> [99 111 110 115 116])

(define urdr.properties.n.fact-of
  -> [102 97 99 116 45 111 102])

(define urdr.properties.n.key
  -> [107 101 121])

(define urdr.properties.n.project
  -> [112 114 111 106 101 99 116])

(define urdr.properties.n.this
  -> [116 104 105 115])

(define urdr.properties.n.and
  -> [97 110 100])

(define urdr.properties.n.defined
  -> [100 101 102 105 110 101 100])

(define urdr.properties.n.eq
  -> [101 113])

(define urdr.properties.n.false
  -> [102 97 108 115 101])

(define urdr.properties.n.ge
  -> [103 101])

(define urdr.properties.n.gt
  -> [103 116])

(define urdr.properties.n.le
  -> [108 101])

(define urdr.properties.n.lt
  -> [108 116])

(define urdr.properties.n.ne
  -> [110 101])

(define urdr.properties.n.not
  -> [110 111 116])

(define urdr.properties.n.or
  -> [111 114])

(define urdr.properties.n.true
  -> [116 114 117 101])

(define urdr.properties.n.always-eventually
  -> [97 108 119 97 121 115 45 101 118 101 110 116 117 97 108 108
      121])

(define urdr.properties.n.before
  -> [98 101 102 111 114 101])

(define urdr.properties.n.never
  -> [110 101 118 101 114])

\\ The M1 property classes, and the classes whose tags are reserved for
\\ M3+ guests and rejected until then.
(define urdr.properties.classes
  -> [(urdr.properties.n.invariant)
      (urdr.properties.n.liveness)
      (urdr.properties.n.temporal)])

(define urdr.properties.reserved-classes
  -> [(urdr.properties.n.crash)
      (urdr.properties.n.log)
      (urdr.properties.n.metamorphic)])

(define urdr.properties.compare-ops
  -> [(urdr.properties.n.eq)
      (urdr.properties.n.ge)
      (urdr.properties.n.gt)
      (urdr.properties.n.le)
      (urdr.properties.n.lt)
      (urdr.properties.n.ne)])

\\ ---------------------------------------------------------------------
\\ Generic helpers.
\\ ---------------------------------------------------------------------

(define urdr.properties.rev
  Xs -> (urdr.canonical.rev Xs))

(define urdr.properties.beq
  A B -> (= (urdr.canonical.bytes-compare A B) eq))

(define urdr.properties.member?
  _ [] -> false
  Bs [X | Xs] ->
    (if (urdr.properties.beq Bs X)
        true
        (urdr.properties.member? Bs Xs)))

(define urdr.properties.proper?
  [] -> true
  [_ | Xs] -> (urdr.properties.proper? Xs)
  _ -> false)

(define urdr.properties.canonical?
  Value -> (= (hd (urdr.canonical.encode-payload Value)) ok))

\\ Canonical equality is encoding equality, the same definition the world
\\ reducer uses (urdr.world.canonical-equal). Non-canonical operands are
\\ never equal to anything, including themselves.
(define urdr.properties.ceq
  A B ->
    (urdr.properties.ceq-h
      (urdr.canonical.encode-payload A)
      (urdr.canonical.encode-payload B)))

(define urdr.properties.ceq-h
  [ok A] [ok B] -> (= A B)
  _ _ -> false)

\\ Strict record projection: exactly these keys, in exactly this order,
\\ and nothing else.
(define urdr.properties.fields
  [record Fs] Keys Code ->
    (urdr.properties.fields-loop Fs Keys Code [])
  _ _ Code -> [error Code])

(define urdr.properties.fields-loop
  [] [] _ Acc -> [ok (urdr.properties.rev Acc)]
  [[K V] | Fs] [Key | Ks] Code Acc ->
    (if (urdr.properties.beq K Key)
        (urdr.properties.fields-loop Fs Ks Code [V | Acc])
        [error Code])
  _ _ Code _ -> [error Code])

(define urdr.properties.symbol-of
  [symbol Bs] Code ->
    (if (urdr.canonical.symbol? Bs) [ok Bs] [error Code])
  _ Code -> [error Code])

(define urdr.properties.opt-symbol
  [null] _ -> [ok none]
  [symbol Bs] Code ->
    (if (urdr.canonical.symbol? Bs) [ok [some Bs]] [error Code])
  _ Code -> [error Code])

(define urdr.properties.nonneg
  Value TypeCode NegCode ->
    (urdr.properties.nonneg-h
      (urdr.int.validate Value) TypeCode NegCode))

(define urdr.properties.nonneg-h
  [ok I] _ NegCode ->
    (if (urdr.int.raw.negative? I) [error NegCode] [ok I])
  _ TypeCode _ -> [error TypeCode])

(define urdr.properties.strictly-after?
  none _ -> true
  Previous Current ->
    (= (urdr.canonical.bytes-compare Previous Current) lt))

(define urdr.properties.same-name?
  none _ -> false
  Previous Current ->
    (= (urdr.canonical.bytes-compare Previous Current) eq))

\\ ---------------------------------------------------------------------
\\ Trace validation. Entries become [tentry INDEX ID TIME SOURCE NAME
\\ VALUE] tuples; every later stage works on those, never on records.
\\ ---------------------------------------------------------------------

(define urdr.properties.entry-keys
  -> [(urdr.properties.n.component)
      (urdr.properties.n.event-id)
      (urdr.properties.n.name)
      (urdr.properties.n.time)
      (urdr.properties.n.type)
      (urdr.properties.n.value)])

(define urdr.properties.e.index
  [tentry X _ _ _ _ _] -> X)

(define urdr.properties.e.id
  [tentry _ X _ _ _ _] -> X)

(define urdr.properties.e.time
  [tentry _ _ X _ _ _] -> X)

(define urdr.properties.e.source
  [tentry _ _ _ X _ _] -> X)

(define urdr.properties.e.name
  [tentry _ _ _ _ X _] -> X)

(define urdr.properties.e.value
  [tentry _ _ _ _ _ X] -> X)

(define urdr.properties.entries
  [trace Items] ->
    (urdr.properties.entries-loop Items none (urdr.int.zero) [])
  _ -> [error properties-trace-shape])

(define urdr.properties.entries-loop
  [] _ _ Acc -> [ok (urdr.properties.rev Acc)]
  [Item | Items] Previous Index Acc ->
    (urdr.properties.entries-step
      (urdr.properties.entry Item Index) Items Previous Index Acc)
  _ _ _ _ -> [error properties-trace-shape])

(define urdr.properties.entries-step
  [error E] _ _ _ _ -> [error E]
  [ok Entry] Items Previous Index Acc ->
    (if (urdr.properties.entry-after? Previous Entry)
        (urdr.properties.entries-loop
          Items
          Entry
          (urdr.int.raw.add Index (urdr.int.one))
          [Entry | Acc])
        [error properties-trace-order]))

\\ Non-decreasing in (time, event-id): equal pairs are legal because one
\\ component step may emit several facts under one event.
(define urdr.properties.entry-after?
  none _ -> true
  [tentry _ IdA TimeA _ _ _] [tentry _ IdB TimeB _ _ _] ->
    (let T (urdr.int.raw.compare TimeA TimeB)
      (if (< T 0)
          true
          (if (> T 0)
              false
              (<= (urdr.int.raw.compare IdA IdB) 0)))))

(define urdr.properties.entry
  Item Index ->
    (urdr.properties.entry-fields
      (urdr.properties.fields
        Item (urdr.properties.entry-keys) properties-trace-entry-shape)
      Index))

(define urdr.properties.entry-fields
  [error E] _ -> [error E]
  [ok [Component Id Name Time Type Value]] Index ->
    (urdr.properties.entry-component
      Component Id Name Time Type Value Index)
  _ _ -> [error properties-trace-entry-shape])

(define urdr.properties.entry-component
  [bytes C] Id Name Time Type Value Index ->
    (if (urdr.canonical.symbol? C)
        (urdr.properties.entry-name C Id Name Time Type Value Index)
        [error properties-trace-entry-component])
  _ _ _ _ _ _ _ -> [error properties-trace-entry-component])

(define urdr.properties.entry-name
  C Id [symbol N] Time Type Value Index ->
    (if (urdr.canonical.symbol? N)
        (urdr.properties.entry-type C Id N Time Type Value Index)
        [error properties-trace-entry-name])
  _ _ _ _ _ _ _ -> [error properties-trace-entry-name])

(define urdr.properties.entry-type
  C Id N Time [symbol T] Value Index ->
    (if (urdr.properties.beq T (urdr.properties.n.fact))
        (urdr.properties.entry-id
          (urdr.properties.nonneg
            Id properties-trace-entry-id properties-trace-entry-id)
          C N Time Value Index)
        [error properties-trace-entry-type])
  _ _ _ _ _ _ _ -> [error properties-trace-entry-type])

(define urdr.properties.entry-id
  [error E] _ _ _ _ _ -> [error E]
  [ok I] C N Time Value Index ->
    (urdr.properties.entry-time
      (urdr.properties.nonneg
        Time properties-trace-entry-time properties-trace-entry-time)
      C N I Value Index))

(define urdr.properties.entry-time
  [error E] _ _ _ _ _ -> [error E]
  [ok T] C N I Value Index ->
    (if (urdr.properties.canonical? Value)
        [ok [tentry Index I T C N Value]]
        [error properties-trace-entry-value]))

(define urdr.properties.check-trace
  Trace -> (urdr.properties.check-trace-h (urdr.properties.entries Trace)))

(define urdr.properties.check-trace-h
  [error E] -> [error E]
  [ok _] -> [ok])

\\ A world/v2 value's fact log is already a canonical trace. The shape is
\\ matched directly so this module needs no dependency on world.shen; a
\\ future world/v3 fails closed here rather than being reinterpreted.
(define urdr.properties.trace-of-world
  [world/v2 _ _ _ _ _ _ _ _ Facts _] -> [ok [trace Facts]]
  _ -> [error properties-world-shape])

\\ ---------------------------------------------------------------------
\\ Node shape shared by terms and predicates.
\\ ---------------------------------------------------------------------

(define urdr.properties.node-keys
  -> [(urdr.properties.n.args) (urdr.properties.n.op)])

(define urdr.properties.node
  Value Code ->
    (urdr.properties.node-h
      (urdr.properties.fields
        Value (urdr.properties.node-keys) Code)
      Code))

(define urdr.properties.node-h
  [error E] _ -> [error E]
  [ok [Args Op]] Code -> (urdr.properties.node-op Args Op Code)
  _ Code -> [error Code])

(define urdr.properties.node-op
  [list As] [symbol Op] Code ->
    (if (and (urdr.properties.proper? As)
             (urdr.canonical.symbol? Op))
        [ok [node Op As]]
        [error Code])
  _ _ Code -> [error Code])

\\ ---------------------------------------------------------------------
\\ Term compilation.
\\ ---------------------------------------------------------------------

(define urdr.properties.term
  Value ->
    (urdr.properties.term-node
      (urdr.properties.node Value properties-term-shape)))

(define urdr.properties.term-node
  [error E] -> [error E]
  [ok [node Op Args]] -> (urdr.properties.term-op Op Args))

(define urdr.properties.term-op
  Op Args ->
    (if (urdr.properties.beq Op (urdr.properties.n.this))
        (urdr.properties.term-this Args)
        (if (urdr.properties.beq Op (urdr.properties.n.const))
            (urdr.properties.term-const Args)
            (if (urdr.properties.beq Op (urdr.properties.n.fact))
                (urdr.properties.term-fact Args)
                (urdr.properties.term-op2 Op Args)))))

(define urdr.properties.term-op2
  Op Args ->
    (if (urdr.properties.beq Op (urdr.properties.n.fact-of))
        (urdr.properties.term-fact-of Args)
        (if (urdr.properties.beq Op (urdr.properties.n.project))
            (urdr.properties.term-project Args)
            (if (urdr.properties.beq Op (urdr.properties.n.key))
                (urdr.properties.term-key Args)
                [error properties-term-op-unknown]))))

(define urdr.properties.term-this
  [] -> [ok [t-this]]
  _ -> [error properties-term-arity])

(define urdr.properties.term-const
  [V] ->
    (if (urdr.properties.canonical? V)
        [ok [t-const V]]
        [error properties-term-const])
  _ -> [error properties-term-arity])

(define urdr.properties.term-fact
  [Name] ->
    (urdr.properties.term-fact-h
      (urdr.properties.symbol-of Name properties-term-name))
  _ -> [error properties-term-arity])

(define urdr.properties.term-fact-h
  [error E] -> [error E]
  [ok N] -> [ok [t-fact N]])

(define urdr.properties.term-fact-of
  [Name Source] ->
    (urdr.properties.term-fact-of-h
      (urdr.properties.symbol-of Name properties-term-name)
      (urdr.properties.symbol-of Source properties-term-source))
  _ -> [error properties-term-arity])

(define urdr.properties.term-fact-of-h
  [error E] _ -> [error E]
  _ [error E] -> [error E]
  [ok N] [ok S] -> [ok [t-fact-of N S]])

(define urdr.properties.term-project
  [Inner Index] ->
    (urdr.properties.term-project-h
      (urdr.properties.term Inner)
      (urdr.properties.nonneg
        Index properties-term-index properties-term-index))
  _ -> [error properties-term-arity])

(define urdr.properties.term-project-h
  [error E] _ -> [error E]
  _ [error E] -> [error E]
  [ok T] [ok I] -> [ok [t-project T I]])

(define urdr.properties.term-key
  [Inner Key] ->
    (urdr.properties.term-key-h
      (urdr.properties.term Inner)
      (urdr.properties.symbol-of Key properties-term-key))
  _ -> [error properties-term-arity])

(define urdr.properties.term-key-h
  [error E] _ -> [error E]
  _ [error E] -> [error E]
  [ok T] [ok K] -> [ok [t-key T K]])

\\ ---------------------------------------------------------------------
\\ Predicate compilation.
\\ ---------------------------------------------------------------------

(define urdr.properties.pred
  Value ->
    (urdr.properties.pred-node
      (urdr.properties.node Value properties-predicate-shape)))

(define urdr.properties.pred-node
  [error E] -> [error E]
  [ok [node Op Args]] -> (urdr.properties.pred-op Op Args))

(define urdr.properties.pred-op
  Op Args ->
    (if (urdr.properties.member? Op (urdr.properties.compare-ops))
        (urdr.properties.pred-compare Op Args)
        (urdr.properties.pred-op2 Op Args)))

(define urdr.properties.pred-op2
  Op Args ->
    (if (urdr.properties.beq Op (urdr.properties.n.true))
        (urdr.properties.pred-nullary [p-true] Args)
        (if (urdr.properties.beq Op (urdr.properties.n.false))
            (urdr.properties.pred-nullary [p-false] Args)
            (if (urdr.properties.beq Op (urdr.properties.n.defined))
                (urdr.properties.pred-defined Args)
                (urdr.properties.pred-op3 Op Args)))))

(define urdr.properties.pred-op3
  Op Args ->
    (if (urdr.properties.beq Op (urdr.properties.n.not))
        (urdr.properties.pred-not Args)
        (if (urdr.properties.beq Op (urdr.properties.n.and))
            (urdr.properties.pred-binary p-and Args)
            (if (urdr.properties.beq Op (urdr.properties.n.or))
                (urdr.properties.pred-binary p-or Args)
                [error properties-predicate-op-unknown]))))

(define urdr.properties.pred-nullary
  P [] -> [ok P]
  _ _ -> [error properties-predicate-arity])

(define urdr.properties.pred-compare
  Op [A B] ->
    (urdr.properties.pred-compare-h
      Op (urdr.properties.term A) (urdr.properties.term B))
  _ _ -> [error properties-predicate-arity])

(define urdr.properties.pred-compare-h
  _ [error E] _ -> [error E]
  _ _ [error E] -> [error E]
  Op [ok TA] [ok TB] -> [ok [p-compare Op TA TB]])

(define urdr.properties.pred-defined
  [A] ->
    (urdr.properties.pred-defined-h (urdr.properties.term A))
  _ -> [error properties-predicate-arity])

(define urdr.properties.pred-defined-h
  [error E] -> [error E]
  [ok T] -> [ok [p-defined T]])

(define urdr.properties.pred-not
  [A] -> (urdr.properties.pred-not-h (urdr.properties.pred A))
  _ -> [error properties-predicate-arity])

(define urdr.properties.pred-not-h
  [error E] -> [error E]
  [ok P] -> [ok [p-not P]])

(define urdr.properties.pred-binary
  Tag [A B] ->
    (urdr.properties.pred-binary-h
      Tag (urdr.properties.pred A) (urdr.properties.pred B))
  _ _ -> [error properties-predicate-arity])

(define urdr.properties.pred-binary-h
  _ [error E] _ -> [error E]
  _ _ [error E] -> [error E]
  Tag [ok P] [ok Q] -> [ok [p-bin Tag P Q]])

\\ ---------------------------------------------------------------------
\\ Term and predicate evaluation. Total by construction: every recursive
\\ call is on a strict subterm of a finite compiled tree.
\\ ---------------------------------------------------------------------

(define urdr.properties.eval-term
  [t-this] [env _ [some V]] -> [val V]
  [t-this] [env _ none] -> [undef]
  [t-const V] _ -> [val V]
  [t-fact N] [env RPrefix _] -> (urdr.properties.find-fact N RPrefix)
  [t-fact-of N S] [env RPrefix _] ->
    (urdr.properties.find-fact-of N S RPrefix)
  [t-project T I] Env ->
    (urdr.properties.project-h (urdr.properties.eval-term T Env) I)
  [t-key T K] Env ->
    (urdr.properties.key-h (urdr.properties.eval-term T Env) K))

(define urdr.properties.find-fact
  _ [] -> [undef]
  N [E | Es] ->
    (if (urdr.properties.beq N (urdr.properties.e.name E))
        [val (urdr.properties.e.value E)]
        (urdr.properties.find-fact N Es)))

(define urdr.properties.find-fact-of
  _ _ [] -> [undef]
  N S [E | Es] ->
    (if (and (urdr.properties.beq N (urdr.properties.e.name E))
             (urdr.properties.beq S (urdr.properties.e.source E)))
        [val (urdr.properties.e.value E)]
        (urdr.properties.find-fact-of N S Es)))

(define urdr.properties.project-h
  [val [list Vs]] I -> (urdr.properties.nth Vs I)
  _ _ -> [undef])

(define urdr.properties.nth
  [] _ -> [undef]
  [V | Vs] I ->
    (if (urdr.int.raw.zero? I)
        [val V]
        (urdr.properties.nth
          Vs (urdr.int.raw.subtract I (urdr.int.one))))
  _ _ -> [undef])

(define urdr.properties.key-h
  [val [record Fs]] K -> (urdr.properties.key-lookup K Fs)
  _ _ -> [undef])

(define urdr.properties.key-lookup
  _ [] -> [undef]
  K [[Key V] | Fs] ->
    (if (urdr.properties.beq K Key)
        [val V]
        (urdr.properties.key-lookup K Fs))
  _ _ -> [undef])

(define urdr.properties.eval-pred
  [p-true] _ -> true
  [p-false] _ -> false
  [p-defined T] Env ->
    (urdr.properties.defined? (urdr.properties.eval-term T Env))
  [p-not P] Env -> (not (urdr.properties.eval-pred P Env))
  [p-bin p-and P Q] Env ->
    (and (urdr.properties.eval-pred P Env)
         (urdr.properties.eval-pred Q Env))
  [p-bin p-or P Q] Env ->
    (or (urdr.properties.eval-pred P Env)
        (urdr.properties.eval-pred Q Env))
  [p-compare Op A B] Env ->
    (urdr.properties.compare-vals
      Op
      (urdr.properties.eval-term A Env)
      (urdr.properties.eval-term B Env)))

(define urdr.properties.defined?
  [val _] -> true
  _ -> false)

(define urdr.properties.compare-vals
  Op [val A] [val B] ->
    (if (urdr.properties.beq Op (urdr.properties.n.eq))
        (urdr.properties.ceq A B)
        (if (urdr.properties.beq Op (urdr.properties.n.ne))
            (not (urdr.properties.ceq A B))
            (urdr.properties.compare-ints Op A B)))
  _ _ _ -> false)

(define urdr.properties.compare-ints
  Op A B ->
    (urdr.properties.compare-ints-h Op (urdr.int.compare A B)))

(define urdr.properties.compare-ints-h
  Op [ok N] ->
    (if (urdr.properties.beq Op (urdr.properties.n.lt))
        (< N 0)
        (if (urdr.properties.beq Op (urdr.properties.n.le))
            (<= N 0)
            (if (urdr.properties.beq Op (urdr.properties.n.gt))
                (> N 0)
                (>= N 0))))
  _ _ -> false)

\\ ---------------------------------------------------------------------
\\ Patterns.
\\ ---------------------------------------------------------------------

(define urdr.properties.pattern-keys
  -> [(urdr.properties.n.name)
      (urdr.properties.n.source)
      (urdr.properties.n.value)])

(define urdr.properties.pattern
  Value ->
    (urdr.properties.pattern-h
      (urdr.properties.fields
        Value (urdr.properties.pattern-keys)
        properties-pattern-shape)))

(define urdr.properties.pattern-h
  [error E] -> [error E]
  [ok [Name Source Value]] ->
    (urdr.properties.pattern-name
      (urdr.properties.symbol-of Name properties-pattern-name)
      Source
      Value)
  _ -> [error properties-pattern-shape])

(define urdr.properties.pattern-name
  [error E] _ _ -> [error E]
  [ok N] Source Value ->
    (urdr.properties.pattern-source
      N
      (urdr.properties.opt-symbol Source properties-pattern-source)
      Value))

(define urdr.properties.pattern-source
  _ [error E] _ -> [error E]
  N [ok S] Value ->
    (urdr.properties.pattern-value
      N S (urdr.properties.opt-pred Value)))

(define urdr.properties.opt-pred
  [null] -> [ok none]
  V -> (urdr.properties.opt-pred-h (urdr.properties.pred V)))

(define urdr.properties.opt-pred-h
  [error E] -> [error E]
  [ok P] -> [ok [some P]])

(define urdr.properties.pattern-value
  _ _ [error E] -> [error E]
  N S [ok P] -> [ok [cpat N S P]])

(define urdr.properties.match?
  [cpat N S P] E RPrefix ->
    (and (urdr.properties.beq N (urdr.properties.e.name E))
         (and (urdr.properties.match-source? S E)
              (urdr.properties.match-value? P E RPrefix))))

(define urdr.properties.match-source?
  none _ -> true
  [some S] E -> (urdr.properties.beq S (urdr.properties.e.source E)))

(define urdr.properties.match-value?
  none _ _ -> true
  [some P] E RPrefix ->
    (urdr.properties.eval-pred
      P [env RPrefix [some (urdr.properties.e.value E)]]))

\\ ---------------------------------------------------------------------
\\ Observation points. Shape [observation AT ID] is the scenario DSL's
\\ (shen/scenario/scenario.shen), matched as data so this module carries
\\ no dependency on it.
\\ ---------------------------------------------------------------------

(define urdr.properties.check-observations
  Observations ->
    (urdr.properties.observations-loop Observations none))

(define urdr.properties.observations-loop
  [] _ -> [ok]
  [[observation At Id] | Rest] Previous ->
    (if (not (urdr.canonical.symbol? Id))
        [error properties-observation-shape]
        (if (not (urdr.properties.strictly-after? Previous Id))
            [error properties-observation-order]
            (urdr.properties.observations-step
              (urdr.properties.nonneg
                At
                properties-observation-time
                properties-observation-time)
              Rest
              Id)))
  _ _ -> [error properties-observations-shape])

(define urdr.properties.observations-step
  [error E] _ _ -> [error E]
  [ok _] Rest Id -> (urdr.properties.observations-loop Rest Id))

(define urdr.properties.observation-at
  _ [] -> none
  Id [[observation At OId] | Rest] ->
    (if (urdr.properties.beq Id OId)
        [some At]
        (urdr.properties.observation-at Id Rest))
  _ _ -> none)

\\ ---------------------------------------------------------------------
\\ invariant spec.
\\ ---------------------------------------------------------------------

(define urdr.properties.invariant-keys
  -> [(urdr.properties.n.points) (urdr.properties.n.pred)])

(define urdr.properties.invariant-spec
  Spec Observations ->
    (urdr.properties.invariant-h
      (urdr.properties.fields
        Spec (urdr.properties.invariant-keys)
        properties-invariant-spec-shape)
      Observations))

(define urdr.properties.invariant-h
  [error E] _ -> [error E]
  [ok [Points Pred]] Observations ->
    (urdr.properties.invariant-points
      (urdr.properties.points Points Observations) Pred)
  _ _ -> [error properties-invariant-spec-shape])

(define urdr.properties.invariant-points
  [error E] _ -> [error E]
  [ok Ps] Pred ->
    (urdr.properties.invariant-pred Ps (urdr.properties.pred Pred)))

(define urdr.properties.invariant-pred
  _ [error E] -> [error E]
  Ps [ok P] -> [ok [cinvariant Ps P]])

(define urdr.properties.points
  [list Items] Observations ->
    (urdr.properties.points-loop Items Observations none [])
  _ _ -> [error properties-invariant-points-shape])

(define urdr.properties.points-loop
  [] _ none _ -> [error properties-invariant-points-empty]
  [] _ _ Acc ->
    [ok (urdr.properties.sort-points (urdr.properties.rev Acc))]
  [Item | Items] Observations Previous Acc ->
    (urdr.properties.points-step
      (urdr.properties.symbol-of
        Item properties-invariant-point-type)
      Items Observations Previous Acc)
  _ _ _ _ -> [error properties-invariant-points-shape])

(define urdr.properties.points-step
  [error E] _ _ _ _ -> [error E]
  [ok Id] Items Observations Previous Acc ->
    (if (urdr.properties.strictly-after? Previous Id)
        (urdr.properties.points-resolve
          (urdr.properties.observation-at Id Observations)
          Id Items Observations Acc)
        [error properties-invariant-point-order]))

(define urdr.properties.points-resolve
  none _ _ _ _ -> [error properties-invariant-point-unknown]
  [some At] Id Items Observations Acc ->
    (urdr.properties.points-loop
      Items Observations Id [[point Id At] | Acc]))

\\ Selected points are evaluated in (at, id) order so that the reported
\\ witness is the earliest failure in logical time, not in spelling order.
(define urdr.properties.sort-points
  Ps -> (urdr.properties.sort-points-loop Ps []))

(define urdr.properties.sort-points-loop
  [] Acc -> Acc
  [P | Ps] Acc ->
    (urdr.properties.sort-points-loop
      Ps (urdr.properties.insert-point P Acc)))

(define urdr.properties.insert-point
  P [] -> [P]
  P [Q | Qs] ->
    (if (urdr.properties.point-before? P Q)
        [P Q | Qs]
        [Q | (urdr.properties.insert-point P Qs)]))

(define urdr.properties.point-before?
  [point IdA AtA] [point IdB AtB] ->
    (let C (urdr.int.raw.compare AtA AtB)
      (if (< C 0)
          true
          (if (> C 0)
              false
              (= (urdr.canonical.bytes-compare IdA IdB) lt)))))

\\ ---------------------------------------------------------------------
\\ temporal spec.
\\ ---------------------------------------------------------------------

(define urdr.properties.temporal-keys
  -> [(urdr.properties.n.args) (urdr.properties.n.form)])

(define urdr.properties.temporal-spec
  Spec ->
    (urdr.properties.temporal-h
      (urdr.properties.fields
        Spec (urdr.properties.temporal-keys)
        properties-temporal-spec-shape)))

(define urdr.properties.temporal-h
  [error E] -> [error E]
  [ok [Args Form]] ->
    (urdr.properties.temporal-form
      Args
      (urdr.properties.symbol-of Form properties-temporal-form))
  _ -> [error properties-temporal-spec-shape])

(define urdr.properties.temporal-form
  _ [error E] -> [error E]
  Args [ok F] ->
    (if (urdr.properties.beq F (urdr.properties.n.before))
        (urdr.properties.temporal-before Args)
        (if (urdr.properties.beq F (urdr.properties.n.always-eventually))
            (urdr.properties.temporal-ae Args)
            (if (urdr.properties.beq F (urdr.properties.n.never))
                (urdr.properties.temporal-never Args)
                [error properties-temporal-form-unsupported]))))

(define urdr.properties.temporal-before
  [list [A B]] ->
    (urdr.properties.temporal-before-h
      (urdr.properties.pattern A) (urdr.properties.pattern B))
  _ -> [error properties-temporal-args])

(define urdr.properties.temporal-before-h
  [error E] _ -> [error E]
  _ [error E] -> [error E]
  [ok PA] [ok PB] -> [ok [ctemporal-before PA PB]])

(define urdr.properties.temporal-ae
  [list [A B W]] ->
    (urdr.properties.temporal-ae-h
      (urdr.properties.pattern A)
      (urdr.properties.pattern B)
      (urdr.properties.nonneg
        W
        properties-temporal-window
        properties-temporal-window-negative))
  _ -> [error properties-temporal-args])

(define urdr.properties.temporal-ae-h
  [error E] _ _ -> [error E]
  _ [error E] _ -> [error E]
  _ _ [error E] -> [error E]
  [ok PA] [ok PB] [ok Window] -> [ok [ctemporal-ae PA PB Window]])

(define urdr.properties.temporal-never
  [list [A]] ->
    (urdr.properties.temporal-never-h (urdr.properties.pattern A))
  _ -> [error properties-temporal-args])

(define urdr.properties.temporal-never-h
  [error E] -> [error E]
  [ok PA] -> [ok [ctemporal-never PA]])

\\ ---------------------------------------------------------------------
\\ liveness spec.
\\ ---------------------------------------------------------------------

(define urdr.properties.liveness-keys
  -> [(urdr.properties.n.deadline) (urdr.properties.n.pattern)])

(define urdr.properties.liveness-spec
  Spec ->
    (urdr.properties.liveness-h
      (urdr.properties.fields
        Spec (urdr.properties.liveness-keys)
        properties-liveness-spec-shape)))

(define urdr.properties.liveness-h
  [error E] -> [error E]
  [ok [Deadline Pattern]] ->
    (urdr.properties.liveness-fields
      (urdr.properties.nonneg
        Deadline
        properties-liveness-deadline
        properties-liveness-deadline-negative)
      (urdr.properties.pattern Pattern))
  _ -> [error properties-liveness-spec-shape])

(define urdr.properties.liveness-fields
  [error E] _ -> [error E]
  _ [error E] -> [error E]
  [ok D] [ok P] -> [ok [cliveness P D]])

\\ ---------------------------------------------------------------------
\\ Load: strict per-class validation of an opaque scenario spec.
\\ ---------------------------------------------------------------------

(define urdr.properties.load
  Property Observations ->
    (urdr.properties.load-checked
      (urdr.properties.check-observations Observations)
      Property
      Observations))

(define urdr.properties.load-checked
  [error E] _ _ -> [error E]
  [ok] Property Observations ->
    (urdr.properties.load-one Property Observations))

(define urdr.properties.load-one
  [property Class Id Spec] Observations ->
    (urdr.properties.load-class Class Id Spec Observations)
  _ _ -> [error properties-property-shape])

(define urdr.properties.load-class
  Class Id Spec Observations ->
    (if (not (urdr.canonical.symbol? Id))
        [error properties-property-id]
        (if (urdr.properties.member?
              Class (urdr.properties.reserved-classes))
            [error properties-class-unsupported-in-m1]
            (urdr.properties.load-spec Class Id Spec Observations))))

(define urdr.properties.load-spec
  Class Id Spec Observations ->
    (if (not (urdr.properties.canonical? Spec))
        [error properties-spec-noncanonical]
        (if (urdr.properties.beq Class (urdr.properties.n.invariant))
            (urdr.properties.wrap
              Class Id
              (urdr.properties.invariant-spec Spec Observations))
            (if (urdr.properties.beq Class (urdr.properties.n.temporal))
                (urdr.properties.wrap
                  Class Id (urdr.properties.temporal-spec Spec))
                (if (urdr.properties.beq
                      Class (urdr.properties.n.liveness))
                    (urdr.properties.wrap
                      Class Id (urdr.properties.liveness-spec Spec))
                    [error properties-class-unknown])))))

(define urdr.properties.wrap
  _ _ [error E] -> [error E]
  Class Id [ok Compiled] -> [ok [loaded Class Id Compiled]])

(define urdr.properties.loaded-class
  [loaded Class _ _] -> Class)

(define urdr.properties.loaded-id
  [loaded _ Id _] -> Id)

(define urdr.properties.load-all
  Properties Observations ->
    (urdr.properties.load-all-checked
      (urdr.properties.check-observations Observations)
      Properties
      Observations))

(define urdr.properties.load-all-checked
  [error E] _ _ -> [error E]
  [ok] Properties Observations ->
    (urdr.properties.load-all-loop Properties Observations none []))

(define urdr.properties.load-all-loop
  [] _ _ Acc -> [ok (urdr.properties.rev Acc)]
  [P | Ps] Observations Previous Acc ->
    (urdr.properties.load-all-step
      (urdr.properties.load-one P Observations)
      Ps Observations Previous Acc)
  _ _ _ _ -> [error properties-properties-shape])

(define urdr.properties.load-all-step
  [error E] _ _ _ _ -> [error E]
  [ok Loaded] Ps Observations Previous Acc ->
    (let Id (urdr.properties.loaded-id Loaded)
      (if (urdr.properties.same-name? Previous Id)
          [error properties-duplicate-property]
          (if (urdr.properties.strictly-after? Previous Id)
              (urdr.properties.load-all-loop
                Ps Observations Id [Loaded | Acc])
              [error properties-property-order]))))

\\ ---------------------------------------------------------------------
\\ Evaluation.
\\ ---------------------------------------------------------------------

(define urdr.properties.evaluate
  Loaded Trace ->
    (urdr.properties.evaluate-h Loaded (urdr.properties.entries Trace)))

(define urdr.properties.evaluate-h
  _ [error E] -> [error E]
  [loaded Class Id Compiled] [ok Es] ->
    [ok (urdr.properties.verdict
          Class Id (urdr.properties.run Compiled Es))]
  _ _ -> [error properties-loaded-shape])

(define urdr.properties.evaluate-all
  Loadeds Trace ->
    (urdr.properties.evaluate-all-h
      Loadeds (urdr.properties.entries Trace)))

(define urdr.properties.evaluate-all-h
  _ [error E] -> [error E]
  Loadeds [ok Es] ->
    (urdr.properties.evaluate-all-loop Loadeds Es []))

(define urdr.properties.evaluate-all-loop
  [] _ Acc -> [ok (urdr.properties.rev Acc)]
  [[loaded Class Id Compiled] | Ls] Es Acc ->
    (urdr.properties.evaluate-all-loop
      Ls
      Es
      [(urdr.properties.verdict
         Class Id (urdr.properties.run Compiled Es)) | Acc])
  _ _ _ -> [error properties-loaded-shape])

\\ One-shot: declarations plus a trace in, canonical verdicts out.
(define urdr.properties.check
  Properties Observations Trace ->
    (urdr.properties.check-h
      (urdr.properties.load-all Properties Observations) Trace))

(define urdr.properties.check-h
  [error E] _ -> [error E]
  [ok Loadeds] Trace ->
    (urdr.properties.evaluate-all Loadeds Trace))

(define urdr.properties.verdict
  Class Id [result Result Witness] ->
    [pverdict Class Id Result Witness])

(define urdr.properties.run
  [cinvariant Ps P] Es -> (urdr.properties.run-invariant Ps P Es)
  [ctemporal-before A B] Es -> (urdr.properties.run-before A B Es)
  [ctemporal-ae A B W] Es -> (urdr.properties.run-ae A B W Es)
  [ctemporal-never A] Es -> (urdr.properties.run-never A Es)
  [cliveness P D] Es -> (urdr.properties.run-liveness P D Es))

\\ ---- invariant --------------------------------------------------------

(define urdr.properties.run-invariant
  [] _ _ -> [result pass none-witness]
  [[point Id At] | Ps] P Es ->
    (let RPrefix (urdr.properties.rprefix Es At)
      (if (urdr.properties.eval-pred P [env RPrefix none])
          (urdr.properties.run-invariant Ps P Es)
          [result fail (urdr.properties.point-witness Id At RPrefix)])))

\\ Entries with time <= At, most recent first. The trace is time-ordered,
\\ so the scan stops at the first entry past the point.
(define urdr.properties.rprefix
  Es At -> (urdr.properties.rprefix-loop Es At []))

(define urdr.properties.rprefix-loop
  [] _ Acc -> Acc
  [E | Es] At Acc ->
    (if (> (urdr.int.raw.compare (urdr.properties.e.time E) At) 0)
        Acc
        (urdr.properties.rprefix-loop Es At [E | Acc])))

(define urdr.properties.point-witness
  Id At [] -> [wit none none At [some Id]]
  Id At [E | _] ->
    [wit
      [some (urdr.properties.e.index E)]
      [some (urdr.properties.e.id E)]
      At
      [some Id]])

\\ ---- temporal: before -------------------------------------------------

(define urdr.properties.first-match
  _ [] _ -> none
  Pat [E | Es] RAcc ->
    (if (urdr.properties.match? Pat E RAcc)
        [some E]
        (urdr.properties.first-match Pat Es [E | RAcc])))

(define urdr.properties.run-before
  A B Es ->
    (urdr.properties.before-h
      (urdr.properties.first-match A Es [])
      (urdr.properties.first-match B Es [])))

(define urdr.properties.before-h
  none none -> [result fail none-witness]
  none [some B] -> [result fail (urdr.properties.entry-witness B)]
  [some _] none -> [result fail none-witness]
  [some A] [some B] ->
    (if (< (urdr.int.raw.compare
             (urdr.properties.e.index A)
             (urdr.properties.e.index B))
           0)
        [result pass (urdr.properties.entry-witness A)]
        [result fail (urdr.properties.entry-witness B)]))

(define urdr.properties.entry-witness
  E ->
    [wit
      [some (urdr.properties.e.index E)]
      [some (urdr.properties.e.id E)]
      (urdr.properties.e.time E)
      none])

\\ ---- temporal: always-A-implies-eventually-B-within-window ------------

(define urdr.properties.run-ae
  A B W Es -> (urdr.properties.ae-loop A B W Es [] false))

(define urdr.properties.ae-loop
  _ _ _ [] _ false -> [result pass vacuous]
  _ _ _ [] _ _ -> [result pass none-witness]
  A B W [E | Es] RAcc Seen ->
    (if (urdr.properties.match? A E RAcc)
        (urdr.properties.ae-antecedent A B W E Es RAcc)
        (urdr.properties.ae-loop A B W Es [E | RAcc] Seen)))

(define urdr.properties.ae-antecedent
  A B W E Es RAcc ->
    (if (urdr.properties.ae-scan
          B
          (urdr.int.raw.add (urdr.properties.e.time E) W)
          Es
          [E | RAcc])
        (urdr.properties.ae-loop A B W Es [E | RAcc] true)
        [result fail (urdr.properties.entry-witness E)]))

\\ The consequent must be a strictly later entry (the scan starts after
\\ the antecedent) at logical time <= antecedent + window, inclusive. The
\\ trace is time-ordered, so passing the limit ends the search.
(define urdr.properties.ae-scan
  _ _ [] _ -> false
  B Limit [E | Es] RAcc ->
    (if (> (urdr.int.raw.compare (urdr.properties.e.time E) Limit) 0)
        false
        (if (urdr.properties.match? B E RAcc)
            true
            (urdr.properties.ae-scan B Limit Es [E | RAcc]))))

\\ ---- temporal: never --------------------------------------------------

(define urdr.properties.run-never
  A Es ->
    (urdr.properties.never-h (urdr.properties.first-match A Es [])))

(define urdr.properties.never-h
  none -> [result pass none-witness]
  [some E] -> [result fail (urdr.properties.entry-witness E)])

\\ ---- liveness ---------------------------------------------------------

(define urdr.properties.run-liveness
  P D Es -> (urdr.properties.liveness-scan P D Es [] none))

(define urdr.properties.liveness-scan
  _ _ [] _ none -> [result fail none-witness]
  _ _ [] _ [some E] -> [result fail (urdr.properties.entry-witness E)]
  P D [E | Es] RAcc First ->
    (if (urdr.properties.match? P E RAcc)
        (if (<= (urdr.int.raw.compare (urdr.properties.e.time E) D) 0)
            [result pass (urdr.properties.entry-witness E)]
            (urdr.properties.liveness-scan
              P D Es [E | RAcc] (urdr.properties.first-of First E)))
        (urdr.properties.liveness-scan P D Es [E | RAcc] First)))

(define urdr.properties.first-of
  none E -> [some E]
  Some _ -> Some)

\\ ---------------------------------------------------------------------
\\ Verdict values.
\\ ---------------------------------------------------------------------

(define urdr.properties.verdict-class
  [pverdict Class _ _ _] -> Class)

(define urdr.properties.verdict-id
  [pverdict _ Id _ _] -> Id)

(define urdr.properties.verdict-result
  [pverdict _ _ Result _] -> Result)

(define urdr.properties.verdict-witness
  [pverdict _ _ _ Witness] -> Witness)

(define urdr.properties.result-bytes
  pass -> (urdr.properties.n.PASS)
  fail -> (urdr.properties.n.FAIL))

(define urdr.properties.opt-value
  [some V] -> V
  _ -> [null])

(define urdr.properties.opt-symbol-value
  [some Bs] -> [symbol Bs]
  _ -> [null])

(define urdr.properties.witness-value
  none-witness -> [symbol (urdr.properties.n.no-witness)]
  vacuous -> [symbol (urdr.properties.n.vacuous)]
  [wit IndexOpt IdOpt Time PointOpt] ->
    [record
      [[(urdr.properties.n.event-id)
        (urdr.properties.opt-value IdOpt)]
       [(urdr.properties.n.index)
        (urdr.properties.opt-value IndexOpt)]
       [(urdr.properties.n.point)
        (urdr.properties.opt-symbol-value PointOpt)]
       [(urdr.properties.n.time) Time]]])

(define urdr.properties.verdict-value
  [pverdict Class Id Result Witness] ->
    [record
      [[(urdr.properties.n.class) [symbol Class]]
       [(urdr.properties.n.property) [symbol Id]]
       [(urdr.properties.n.result)
        [symbol (urdr.properties.result-bytes Result)]]
       [(urdr.properties.n.witness)
        (urdr.properties.witness-value Witness)]]])

(define urdr.properties.verdict-values
  [] -> []
  [V | Vs] ->
    [(urdr.properties.verdict-value V) |
     (urdr.properties.verdict-values Vs)])

(define urdr.properties.frame
  Verdicts ->
    (urdr.canonical.encode-frame
      [list (urdr.properties.verdict-values Verdicts)]))

\\ ---------------------------------------------------------------------
\\ World verdict-slot projection. The tuple shape is the one
\\ urdr.world.verdict-value already renders; a no-witness verdict reports
\\ zero for both integers, which is why the record above, not this tuple,
\\ is the certifying artifact.
\\ ---------------------------------------------------------------------

(define urdr.properties.witness-id
  [wit _ [some I] _ _] -> I
  _ -> (urdr.int.zero))

(define urdr.properties.witness-time
  [wit _ _ Time _] -> Time
  _ -> (urdr.int.zero))

(define urdr.properties.world-verdict
  [pverdict _ Id Result Witness] ->
    [verdict
      [symbol Id]
      [symbol (urdr.properties.result-bytes Result)]
      (urdr.properties.witness-id Witness)
      (urdr.properties.witness-time Witness)])

(define urdr.properties.world-verdicts
  [] -> []
  [V | Vs] ->
    [(urdr.properties.world-verdict V) |
     (urdr.properties.world-verdicts Vs)])
