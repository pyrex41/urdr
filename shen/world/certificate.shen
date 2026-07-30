\\ The modeled-run certificate (SPEC.md 4, 20.1, 21; M1 plan Wave E).
\\ Requires shen/protocol/canonical.shen, shen/world/integer.shen,
\\ shen/world/prng.shen, shen/world/component.shen,
\\ shen/world/world.shen, shen/world/eventlog.shen, and
\\ shen/world/replay.shen to be loaded by the caller.
\\
\\ Pure: no I/O, no host time, no host randomness, no floating point, no
\\ defprolog. A certificate is a total function of its declared inputs.
\\ Every operation returns [ok ...] or [error CODE DETAIL] and performs
\\ no work before validating.
\\
\\ NOT owned here: property evaluation. This module never loads or
\\ evaluates a property. It consumes the FULL canonical verdict records
\\ that shen/properties/properties.shen renders
\\ (urdr.properties.verdict-values) as opaque canonical values, reading
\\ only their `property`, `result`, and `witness` fields. That is a data
\\ dependency, not a code dependency: nothing here calls into
\\ shen/properties/, so the world kernel does not depend on the property
\\ layer (docs/module-boundaries.md dependency direction).
\\
\\ The world slot tuple ([verdict ID RESULT EVENT-ID TIME]) is
\\ deliberately NOT the input. It is lossy -- it carries neither the
\\ property class nor the witness kind -- and a certificate that could
\\ not tell a PASS that fired from a PASS that never fired would be
\\ making a stronger claim than its evidence supports.
\\
\\ =====================================================================
\\ 1. Run id (SPEC.md 4)
\\ =====================================================================
\\
\\ SPEC.md 4 defines
\\
\\   run-id = hash(engine-version, scenario, initial-snapshot,
\\                 immutable-artifact-manifest, input-transcript,
\\                 decision-transcript, determinism-profile)
\\
\\ The exact preimage is fixed here, once, as an unambiguous octet
\\ string. Each component is a tag-length-value field in the framing
\\ urdr.prng.field.raw already defines for PRNG coordinates (a one-octet
\\ tag, an unsigned-varint length, then the payload), so no two distinct
\\ input tuples can produce the same preimage:
\\
\\   preimage = "URDR-RUN-ID" 0x00 0x01
\\              ++ field(1, engine-version octets)
\\              ++ field(2, SHA-256(canonical payload of the scenario))
\\              ++ field(3, SHA-256(canonical payload of the initial
\\                                  world snapshot value))
\\              ++ field(4, SHA-256(canonical payload of the immutable
\\                                  artifact manifest))
\\              ++ field(5, input-transcript root)
\\              ++ field(6, decision-transcript root)
\\              ++ field(7, determinism-profile octets)
\\
\\   run-id   = SHA-256(preimage)
\\
\\ Notes on the M1 instantiation of each field:
\\
\\ - The initial snapshot is urdr.world.snapshot-value of the world the
\\   run started from. It already binds every registered component's
\\   state through a per-component digest (world.shen), so a different
\\   starting component state is a different run id.
\\ - The `models` field (ADR 0008) adds NO preimage field. The snapshot
\\   value binds every registry entry's META — model and node — since
\\   ADR 0008, and field 3 hashes that snapshot, so two runs that
\\   differ only in a model binding already have different run ids
\\   transitively. A separate preimage field would be a second,
\\   unvalidated copy of the same fact, exactly the redundancy the
\\   per-record run-id note above forbids. (This mirrors the
\\   baseline-descriptor reasoning in section 2: what the initial
\\   snapshot already commits to is not hashed twice.)
\\ - The immutable artifact manifest is a caller-supplied canonical
\\   value. An abstract run has no VM images or binaries to pin, so the
\\   Wave E fixtures pass [list []]; the field exists so the preimage
\\   does not change shape when M2 adds real artifacts.
\\ - The input transcript is the external-input stream. An abstract run
\\   has none, so field 5 is the root of the EMPTY transcript, which is
\\   a fixed 32-octet value, not an omitted field. Omitting it would make
\\   an M1 run id and an M2 run id with no external inputs collide.
\\ - The determinism profile in the preimage is the REQUESTED profile. It
\\   is an input to the run. The ACHIEVED profile is an outcome and is
\\   deliberately not hashed: a run must not change identity because it
\\   failed to reach the profile it asked for.
\\
\\ Because the decision-transcript root commits to every entry
\\ (replay.shen section 1), altering any transcript entry, reordering
\\ two, or dropping one all change the run id.
\\
\\ =====================================================================
\\ 2. Markers
\\ =====================================================================
\\
\\ `modeled-world-only` is unconditional. There is no code path that
\\ produces a certificate without it, because there is no M1 run that
\\ earns a whole-system claim.
\\
\\ `spec-semantics-only` propagates from the network baseline. A
\\ certificate spec does not take markers; it takes the run's BASELINE
\\ DESCRIPTORS -- the canonical values that describe where the network
\\ baseline came from -- and derives the markers from them.
\\ urdr.certificate.markers-of reads the `marker` key out of a descriptor
\\ as an opaque canonical record, which is exactly the shape
\\ urdr.netpol.compiled-value produces. So a run whose baseline is a
\\ compiled NetworkPolicy carries `spec-semantics-only` by construction,
\\ with no code dependency on netpol.shen and no opportunity for a caller
\\ to assert or suppress the marker by hand. A run over an unrestricted
\\ fabric supplies a descriptor with no `marker` key and carries none,
\\ and the two cases are distinguishable in the certificate. This is the
\\ answer to Wave C2's open question 5.
\\
\\ Markers are deduplicated and sorted into ascending unsigned-ASCII
\\ order, so the list is a function of the marker SET and not of the
\\ order the descriptors happened to arrive in.
\\
\\ A baseline descriptor is certificate metadata, not run identity, and
\\ is deliberately absent from the run-id preimage. The baseline itself
\\ lives inside the network model's component state, which field 3 of the
\\ preimage already binds through the initial snapshot digest. Two runs
\\ that differ only in the descriptor they declare therefore share a run
\\ id, which is correct: they are the same run. Declaring a descriptor
\\ that does not match the modeled baseline is a caller error this module
\\ cannot detect, and the Wave I integration is expected to take both
\\ from the same compile.
\\
\\ =====================================================================
\\ 3. Entropy firewall and status (SPEC.md 20.1, 21)
\\ =====================================================================
\\
\\ The certificate reports counts for all five classifications, including
\\ the four that must be zero (eventlog.shen). A single record outside
\\ {pure, modeled} voids the modeled-D1-analog claim.
\\
\\ The CLI-grade status of SPEC.md 21, in precedence order:
\\
\\   DIVERGED      the independent re-drive disagreed with the recorded
\\                 run: replay-event-divergence, replay-state-divergence,
\\                 or replay-event-count.
\\   UNCERTIFIED   the run completed but did not satisfy the requested
\\                 controls: a non-pure/modeled event, or a replay
\\                 verification that failed for an artifact reason (a
\\                 truncated, extended, reordered, or tampered
\\                 transcript is not the same run, so it is evidence
\\                 about the artifact, not about the engine).
\\   FAIL          controls satisfied, some property verdict is FAIL.
\\   PASS          controls satisfied, every property verdict is PASS.
\\
\\ ERROR is not a status value here. An infrastructure or artifact
\\ failure means no certificate is produced at all: urdr.certificate.build
\\ returns [error CODE DETAIL] instead, so a caller cannot mistake a
\\ malformed input for a certified negative result.
\\
\\ Achieved profile is `modeled-d1-analog` when the replay verified and
\\ the entropy counts are clean, and `uncertified` otherwise. It is never
\\ a D-profile name: an M1 artifact must not be readable as a D1 claim.
\\
\\ =====================================================================
\\ 4. Vacuity
\\ =====================================================================
\\
\\ properties.shen distinguishes the witness `vacuous` from `no-witness`
\\ by design: a PASS whose antecedent never fired is not the same
\\ evidence as a PASS that fired and was discharged. The certificate
\\ surfaces that distinction twice -- once in the verbatim verdict
\\ records, and once in a summary that survives content addressing:
\\
\\   [record [[fail               INTEGER]
\\            [pass               INTEGER]
\\            [vacuous            INTEGER]
\\            [vacuous-properties [list [symbol ID] ...]]]]
\\
\\ The summary is not derived from the verdict list at read time; it is
\\ computed here and pinned. If the verdict list is content-addressed
\\ because it is large, the vacuity of the run is still legible from the
\\ certificate alone.
\\
\\ =====================================================================
\\ 5. Certificate schema
\\ =====================================================================
\\
\\   [record [[achieved-profile      [symbol ...]]
\\            [artifact-manifest     [bytes DIGEST]]
\\            [engine-version        [bytes ...]]
\\            [entropy               [record counts]]
\\            [event-root            [bytes DIGEST]]
\\            [input-transcript-root [bytes DIGEST]]
\\            [markers               [list [symbol ...] ...]]
\\            [models                [list [record ...] ...]]
\\            [replay                [record ...]]
\\            [requested-profile     [bytes ...]]
\\            [run-id                [bytes DIGEST]]
\\            [scenario-digest       [bytes DIGEST]]
\\            [state-root            [bytes DIGEST]]
\\            [status                [symbol ...]]
\\            [transcript-root       [bytes DIGEST]]
\\            [verdict-summary       [record ...]]
\\            [verdicts              SLOT]
\\            [version               [symbol urdr-certificate-v2]]]]
\\
\\ The eighteen keys ascend in unsigned-ASCII order (markers < models <
\\ replay: 97 < 111 at octet 2, 109 < 114 at octet 1), so the
\\ certificate is itself a canonical value. `verdicts` is a list slot
\\ (urdr.eventlog.list-slot): inline when it fits the m0 profile,
\\ content-addressed element-wise when it does not, which is the SPEC.md
\\ 20 rule applied to the certificate's own body.
\\
\\ `models` (ADR 0008) is the model bindings of the INITIAL world's
\\ registry: one [record [[component [symbol ID]] [model [symbol ...] |
\\ [null]] [node [symbol ...] | [null]]]] per registered component, in
\\ registry order — the registry ascends strictly by component name, so
\\ the list is sorted ascending by component and no host iteration
\\ order can reach it. The INITIAL registry is the right authority:
\\ bindings never change during a run (component-put preserves META),
\\ and the initial world is what the run id's field 3 hashes. The
\\ addition of this key is why `version` moved from urdr-certificate-v1
\\ to urdr-certificate-v2: an 18-key certificate is a schema change,
\\ and a v1 reader must fail on it rather than silently ignore the
\\ field it does not know.
\\
\\ `replay` is urdr.replay.verified-value on success and
\\ urdr.replay.error-value on failure; the discriminator is the presence
\\ of a `result` key versus a `code` key.
\\
\\ =====================================================================
\\ 6. Public entry points
\\ =====================================================================
\\
\\   spec           ENGINE SCENARIO MANIFEST PROFILE INITIAL TRANSCRIPT
\\                  VERDICT-VALUES BASELINE-DESCRIPTORS -> SPEC
\\   build          SPEC -> [ok CERT] | [error CODE DETAIL]
\\   value          CERT -> canonical record (section 5)
\\   frame          CERT -> [ok OCTETS] | [error CODE DETAIL]
\\   run-id         CERT -> OCTETS
\\   status         CERT -> OCTETS
\\   markers        CERT -> [OCTETS ...]
\\   models         CERT -> [list [record ...] ...] (section 5)
\\   log            CERT -> the event log
\\   recorded       CERT -> the recorded replay artifact
\\   run-id-of      ENGINE SCENARIO MANIFEST INITIAL TRANSCRIPT-ROOT
\\                  PROFILE -> [ok OCTETS] | [error CODE DETAIL]
\\   markers-of     VALUE -> [OCTETS ...]
\\   markers-of-all [VALUE ...] -> [OCTETS ...]
\\   verdict-summary  CERT -> canonical record (section 4)
\\   failure-signature VERDICT-VALUES -> [ok OCTETS] | [error CODE D]
\\
\\ failure-signature exists for the Wave F shrinker: it is the canonical
\\ identity of a run's property failure, so "the same failure persists"
\\ is a digest comparison rather than a structural walk each caller
\\ reimplements. See section 7.
\\
\\ =====================================================================
\\ 7. What a shrinker compares
\\ =====================================================================
\\
\\ A shrink candidate is a DIFFERENT transcript, so urdr.replay.verify is
\\ the wrong tool for it: verify asks "is this the recorded run?", and
\\ for a candidate the honest answer is always no. A shrinker drives the
\\ candidate with urdr.replay.run, takes the final world out of the
\\ resulting log, evaluates its properties, and compares
\\ urdr.certificate.failure-signature of the candidate's verdicts against
\\ the signature of the original's. Equal signatures mean the same
\\ canonical property failure persisted and the candidate may be
\\ accepted; anything else, including an error, means it may not.

\\ ---------------------------------------------------------------
\\ ASCII names as octet lists (k- keys, w- words, t- domain tags).
\\ ---------------------------------------------------------------

(define urdr.certificate.n
  k-achieved-profile ->
    [97 99 104 105 101 118 101 100 45 112 114 111 102 105 108 101]
  k-artifact-manifest ->
    [97 114 116 105 102 97 99 116 45 109 97 110 105 102 101 115
     116]
  k-engine-version ->
    [101 110 103 105 110 101 45 118 101 114 115 105 111 110]
  k-entropy ->
    [101 110 116 114 111 112 121]
  k-event-root ->
    [101 118 101 110 116 45 114 111 111 116]
  k-input-transcript-root ->
    [105 110 112 117 116 45 116 114 97 110 115 99 114 105 112 116
     45 114 111 111 116]
  k-markers ->
    [109 97 114 107 101 114 115]
  k-models ->
    [109 111 100 101 108 115]
  k-replay ->
    [114 101 112 108 97 121]
  k-requested-profile ->
    [114 101 113 117 101 115 116 101 100 45 112 114 111 102 105
     108 101]
  k-run-id ->
    [114 117 110 45 105 100]
  k-scenario-digest ->
    [115 99 101 110 97 114 105 111 45 100 105 103 101 115 116]
  k-state-root ->
    [115 116 97 116 101 45 114 111 111 116]
  k-status ->
    [115 116 97 116 117 115]
  k-transcript-root ->
    [116 114 97 110 115 99 114 105 112 116 45 114 111 111 116]
  k-verdict-summary ->
    [118 101 114 100 105 99 116 45 115 117 109 109 97 114 121]
  k-verdicts ->
    [118 101 114 100 105 99 116 115]
  k-version ->
    [118 101 114 115 105 111 110]
  k-fail ->
    [102 97 105 108]
  k-pass ->
    [112 97 115 115]
  k-vacuous ->
    [118 97 99 117 111 117 115]
  k-vacuous-properties ->
    [118 97 99 117 111 117 115 45 112 114 111 112 101 114 116 105
     101 115]
  k-result ->
    [114 101 115 117 108 116]
  k-witness ->
    [119 105 116 110 101 115 115]
  k-property ->
    [112 114 111 112 101 114 116 121]
  k-marker ->
    [109 97 114 107 101 114]
  k-component ->
    [99 111 109 112 111 110 101 110 116]
  k-model ->
    [109 111 100 101 108]
  k-node ->
    [110 111 100 101]
  w-modeled-world-only ->
    [109 111 100 101 108 101 100 45 119 111 114 108 100 45 111 110
     108 121]
  w-spec-semantics-only ->
    [115 112 101 99 45 115 101 109 97 110 116 105 99 115 45 111
     110 108 121]
  w-PASS ->
    [80 65 83 83]
  w-FAIL ->
    [70 65 73 76]
  w-DIVERGED ->
    [68 73 86 69 82 71 69 68]
  w-UNCERTIFIED ->
    [85 78 67 69 82 84 73 70 73 69 68]
  w-vacuous ->
    [118 97 99 117 111 117 115]
  w-modeled-d1-analog ->
    [109 111 100 101 108 101 100 45 100 49 45 97 110 97 108 111
     103]
  w-uncertified ->
    [117 110 99 101 114 116 105 102 105 101 100]
  \\ v2: the `models` key joined the schema (ADR 0008; section 5).
  w-certificate-v2 ->
    [117 114 100 114 45 99 101 114 116 105 102 105 99 97 116 101
     45 118 50]
  t-verdict-list ->
    [117 114 100 114 45 118 101 114 100 105 99 116 45 108 105 115
     116 45 118 49]
  t-failure-signature ->
    [117 114 100 114 45 102 97 105 108 117 114 101 45 115 105 103
     110 97 116 117 114 101 45 118 49]
  t-run-id ->
    [85 82 68 82 45 82 85 78 45 73 68 0 1])

(define urdr.certificate.big
  N -> (urdr.int.raw.from-small N))

\\ ---------------------------------------------------------------
\\ Canonical record field lookup. Verdict records and compiled-policy
\\ values are read as opaque canonical data, never as module types.
\\ ---------------------------------------------------------------

(define urdr.certificate.assoc
  _ [] -> none
  Key [[Key Value] | _] -> [some Value]
  Key [_ | Rest] -> (urdr.certificate.assoc Key Rest)
  _ _ -> none)

(define urdr.certificate.field-of
  Key [record Fields] -> (urdr.certificate.assoc Key Fields)
  _ _ -> none)

\\ ---------------------------------------------------------------
\\ Markers (section 2)
\\ ---------------------------------------------------------------

\\ The `marker` field of a compiled-policy value, if there is one. Any
\\ other value contributes nothing; a caller that passes an unrelated
\\ value does not silently acquire a marker.
(define urdr.certificate.markers-of
  Value ->
    (urdr.certificate.marker-field
      (urdr.certificate.field-of
        (urdr.certificate.n k-marker) Value)))

(define urdr.certificate.marker-field
  [some [symbol Bs]] -> [Bs]
  _ -> [])

(define urdr.certificate.markers-of-all
  [] -> []
  [Value | Rest] ->
    (append (urdr.certificate.markers-of Value)
            (urdr.certificate.markers-of-all Rest))
  _ -> [])

(define urdr.certificate.insert-marker
  M [] -> [M]
  M [Head | Rest] ->
    (let Order (urdr.canonical.bytes-compare M Head)
      (if (= Order eq)
          [Head | Rest]
          (if (= Order lt)
              [M Head | Rest]
              [Head | (urdr.certificate.insert-marker M Rest)]))))

(define urdr.certificate.sort-markers
  [] Acc -> Acc
  [M | Rest] Acc ->
    (urdr.certificate.sort-markers
      Rest (urdr.certificate.insert-marker M Acc))
  _ Acc -> Acc)

\\ modeled-world-only is unconditional (section 2).
(define urdr.certificate.markers-value
  Markers ->
    (urdr.certificate.sort-markers
      Markers
      [(urdr.certificate.n w-modeled-world-only)]))

(define urdr.certificate.symbols
  [] -> []
  [Bs | Rest] -> [[symbol Bs] | (urdr.certificate.symbols Rest)])

(define urdr.certificate.markers-valid?
  [] -> true
  [Bs | Rest] ->
    (and (urdr.canonical.byte-list? Bs)
         (and (urdr.canonical.symbol? Bs)
              (urdr.certificate.markers-valid? Rest)))
  _ -> false)

\\ ---------------------------------------------------------------
\\ Model bindings (section 5, ADR 0008)
\\ ---------------------------------------------------------------

\\ One binding record per registry entry of the INITIAL world, in
\\ registry order — already strictly ascending by component name, so
\\ the sorted-list requirement of section 5 is met by construction and
\\ needs no re-sort here. Keys ascend component < model < node. The
\\ META accessors return [null] or a canonical symbol, both of which
\\ were validated at registration, so the record is canonical by
\\ construction. Only the two well-formed shapes are matched: a
\\ malformed registry cannot reach this point (urdr.replay.run refuses
\\ an invalid world before the certificate is assembled), and matching
\\ anything looser would repair what should have failed.
(define urdr.certificate.model-binding-value
  [component Name _ _ Meta] ->
    [record
      [[(urdr.certificate.n k-component) [symbol Name]]
       [(urdr.certificate.n k-model)
        (urdr.component.meta-model-value Meta)]
       [(urdr.certificate.n k-node)
        (urdr.component.meta-node-value Meta)]]])

(define urdr.certificate.models-value
  Initial ->
    (urdr.certificate.model-binding-values
      (urdr.world.components Initial)))

(define urdr.certificate.model-binding-values
  [] -> []
  [Entry | Rest] ->
    [(urdr.certificate.model-binding-value Entry) |
     (urdr.certificate.model-binding-values Rest)])

\\ ---------------------------------------------------------------
\\ Run id (section 1)
\\ ---------------------------------------------------------------

(define urdr.certificate.input-transcript-root
  -> (urdr.eventlog.root-of
       (urdr.replay.n t-transcript-root) []))

(define urdr.certificate.preimage
  Engine Scenario Initial Manifest InputRoot DecisionRoot Profile ->
    (append
      (urdr.certificate.n t-run-id)
      (append (urdr.prng.field.raw 1 Engine)
        (append (urdr.prng.field.raw 2 Scenario)
          (append (urdr.prng.field.raw 3 Initial)
            (append (urdr.prng.field.raw 4 Manifest)
              (append (urdr.prng.field.raw 5 InputRoot)
                (append (urdr.prng.field.raw 6 DecisionRoot)
                  (urdr.prng.field.raw 7 Profile)))))))))

(define urdr.certificate.run-id-of
  Engine ScenarioValue ManifestValue Initial DecisionRoot Profile ->
    (urdr.certificate.run-id-scenario
      (urdr.eventlog.value-digest ScenarioValue)
      Engine ManifestValue Initial DecisionRoot Profile))

(define urdr.certificate.run-id-scenario
  [error Code Detail] _ _ _ _ _ -> [error Code Detail]
  [ok ScenarioDigest] Engine ManifestValue Initial DecisionRoot
  Profile ->
    (urdr.certificate.run-id-manifest
      (urdr.eventlog.value-digest ManifestValue)
      Engine ScenarioDigest Initial DecisionRoot Profile))

(define urdr.certificate.run-id-manifest
  [error Code Detail] _ _ _ _ _ -> [error Code Detail]
  [ok ManifestDigest] Engine ScenarioDigest Initial DecisionRoot
  Profile ->
    (urdr.certificate.run-id-initial
      (urdr.eventlog.state-digest Initial)
      Engine ScenarioDigest ManifestDigest DecisionRoot Profile))

(define urdr.certificate.run-id-initial
  [error Code Detail] _ _ _ _ _ -> [error Code Detail]
  [ok InitialDigest] Engine ScenarioDigest ManifestDigest DecisionRoot
  Profile ->
    (urdr.certificate.run-id-input
      (urdr.certificate.input-transcript-root)
      Engine ScenarioDigest InitialDigest ManifestDigest DecisionRoot
      Profile))

(define urdr.certificate.run-id-input
  [error Code Detail] _ _ _ _ _ _ -> [error Code Detail]
  [ok InputRoot] Engine ScenarioDigest InitialDigest ManifestDigest
  DecisionRoot Profile ->
    (urdr.eventlog.digest-of
      (urdr.certificate.preimage
        Engine ScenarioDigest InitialDigest ManifestDigest InputRoot
        DecisionRoot Profile)))

\\ ---------------------------------------------------------------
\\ Verdict summary (section 4)
\\ ---------------------------------------------------------------

(define urdr.certificate.verdict-result
  Verdict ->
    (urdr.certificate.symbol-field
      (urdr.certificate.field-of
        (urdr.certificate.n k-result) Verdict)))

(define urdr.certificate.verdict-id
  Verdict ->
    (urdr.certificate.symbol-field
      (urdr.certificate.field-of
        (urdr.certificate.n k-property) Verdict)))

(define urdr.certificate.symbol-field
  [some [symbol Bs]] -> [some Bs]
  _ -> none)

(define urdr.certificate.verdict-vacuous?
  Verdict ->
    (= (urdr.certificate.field-of
         (urdr.certificate.n k-witness) Verdict)
       [some [symbol (urdr.certificate.n w-vacuous)]]))

\\ A verdict record must carry a symbol `property`, a symbol `result`
\\ that is PASS or FAIL, and a `witness`. Anything else is refused; a
\\ certificate does not summarise a value it cannot read.
(define urdr.certificate.verdicts-valid?
  [] -> true
  [Verdict | Rest] ->
    (and (urdr.certificate.verdict-valid? Verdict)
         (urdr.certificate.verdicts-valid? Rest))
  _ -> false)

(define urdr.certificate.verdict-valid?
  Verdict ->
    (and (not (= (urdr.certificate.verdict-id Verdict) none))
         (and (urdr.certificate.result-valid?
                (urdr.certificate.verdict-result Verdict))
              (not (= (urdr.certificate.field-of
                        (urdr.certificate.n k-witness) Verdict)
                      none)))))

(define urdr.certificate.result-valid?
  [some Bs] ->
    (or (= Bs (urdr.certificate.n w-PASS))
        (= Bs (urdr.certificate.n w-FAIL)))
  _ -> false)

(define urdr.certificate.count-results
  [] Bs Acc -> Acc
  [Verdict | Rest] Bs Acc ->
    (urdr.certificate.count-results
      Rest Bs
      (if (= (urdr.certificate.verdict-result Verdict) [some Bs])
          (+ Acc 1)
          Acc)))

(define urdr.certificate.vacuous-ids
  [] Acc -> (urdr.canonical.rev Acc)
  [Verdict | Rest] Acc ->
    (urdr.certificate.vacuous-ids
      Rest
      (if (urdr.certificate.verdict-vacuous? Verdict)
          (urdr.certificate.cons-id
            (urdr.certificate.verdict-id Verdict) Acc)
          Acc)))

(define urdr.certificate.cons-id
  [some Bs] Acc -> [[symbol Bs] | Acc]
  none Acc -> Acc)

(define urdr.certificate.summary-value
  Verdicts ->
    [record
      [[(urdr.certificate.n k-fail)
        (urdr.certificate.big
          (urdr.certificate.count-results
            Verdicts (urdr.certificate.n w-FAIL) 0))]
       [(urdr.certificate.n k-pass)
        (urdr.certificate.big
          (urdr.certificate.count-results
            Verdicts (urdr.certificate.n w-PASS) 0))]
       [(urdr.certificate.n k-vacuous)
        (urdr.certificate.big
          (length (urdr.certificate.vacuous-ids Verdicts [])))]
       [(urdr.certificate.n k-vacuous-properties)
        [list (urdr.certificate.vacuous-ids Verdicts [])]]]])

(define urdr.certificate.any-fail?
  Verdicts ->
    (> (urdr.certificate.count-results
         Verdicts (urdr.certificate.n w-FAIL) 0)
       0))

\\ ---------------------------------------------------------------
\\ Failure signature
\\ ---------------------------------------------------------------

\\ The canonical identity of "what failed", for a shrinker that may only
\\ accept a candidate when THE SAME failure persists (SPEC.md 17.1, M1
\\ plan Wave F). It is the tagged root over the digests of the FAIL
\\ verdict records, in verdict order, and nothing else:
\\
\\ - It ignores PASS verdicts entirely, so a candidate that additionally
\\   discharges some passing obligation is still the same failure.
\\ - It includes the whole FAIL record -- class, property id, and witness
\\   -- so a candidate that fails the same property at a different
\\   witness is a DIFFERENT failure and must be rejected. That is the
\\   fail-closed direction: a shrinker that accepted it would be
\\   minimising towards a bug it was not asked to preserve.
\\ - It is order-sensitive, because verdict order is the declared
\\   property order and is a function of the scenario, not of the run.
\\
\\ An empty failure set has the well-defined signature SHA-256(tag),
\\ which is distinct from every non-empty one, so "nothing failed" never
\\ compares equal to "something failed".
(define urdr.certificate.failures
  [] -> []
  [Verdict | Rest] ->
    (if (= (urdr.certificate.verdict-result Verdict)
           [some (urdr.certificate.n w-FAIL)])
        [Verdict | (urdr.certificate.failures Rest)]
        (urdr.certificate.failures Rest))
  _ -> [])

(define urdr.certificate.failure-signature
  Verdicts ->
    (if (urdr.certificate.verdicts-valid? Verdicts)
        (urdr.certificate.failure-root
          (urdr.eventlog.value-digests
            (urdr.certificate.failures Verdicts) []))
        [error certificate-verdict-shape [null]]))

(define urdr.certificate.failure-root
  [error Code Detail] -> [error Code Detail]
  [ok Digests] ->
    (urdr.eventlog.root-of
      (urdr.certificate.n t-failure-signature) Digests))

\\ ---------------------------------------------------------------
\\ Status (section 3)
\\ ---------------------------------------------------------------

\\ Only the four engine-level disagreements are DIVERGED. A transcript
\\ that is not the recorded one is evidence about the artifact.
\\ replay-selection-divergence joins the family with ADR 0007 D2's
\\ pinned selections: it only arises after the candidate transcript
\\ matched the recorded entry digests, when the engine's membership
\\ door refuses a selection that same artifact records as decided --
\\ the engine and the artifact disagreeing about the run, exactly what
\\ DIVERGED names. (Codes for transcripts that fail to match at all --
\\ truncated/extended/reordered/tampered -- stay outside: they say the
\\ artifact is not the recorded one, nothing about the engine.)
(define urdr.certificate.divergence?
  replay-event-divergence -> true
  replay-state-divergence -> true
  replay-event-count -> true
  replay-selection-divergence -> true
  _ -> false)

(define urdr.certificate.status-of
  Verified Clean Code Verdicts ->
    (if (and (not Verified) (urdr.certificate.divergence? Code))
        (urdr.certificate.n w-DIVERGED)
        (if (or (not Verified) (not Clean))
            (urdr.certificate.n w-UNCERTIFIED)
            (if (urdr.certificate.any-fail? Verdicts)
                (urdr.certificate.n w-FAIL)
                (urdr.certificate.n w-PASS)))))

(define urdr.certificate.profile-of
  Verified Clean ->
    (if (and Verified Clean)
        (urdr.certificate.n w-modeled-d1-analog)
        (urdr.certificate.n w-uncertified)))

\\ ---------------------------------------------------------------
\\ Building
\\ ---------------------------------------------------------------

\\ Baselines are canonical descriptors of where the run's network
\\ baseline came from, NOT marker names: markers are derived, never
\\ asserted (section 2).
(define urdr.certificate.spec
  Engine ScenarioValue ManifestValue Profile Initial Transcript
  Verdicts Baselines ->
    [cert-spec Engine ScenarioValue ManifestValue Profile Initial
      Transcript Verdicts Baselines])

(define urdr.certificate.build
  [cert-spec Engine ScenarioValue ManifestValue Profile Initial
    Transcript Verdicts Baselines] ->
    (urdr.certificate.build-checked
      Engine ScenarioValue ManifestValue Profile Initial Transcript
      Verdicts (urdr.certificate.markers-of-all Baselines))
  _ -> [error certificate-spec-shape [null]])

(define urdr.certificate.build-checked
  Engine ScenarioValue ManifestValue Profile Initial Transcript
  Verdicts Markers ->
    (if (not (urdr.canonical.byte-list? Engine))
        [error certificate-engine-version [null]]
        (if (not (urdr.canonical.byte-list? Profile))
            [error certificate-profile [null]]
            (if (not (urdr.certificate.verdicts-valid? Verdicts))
                [error certificate-verdict-shape [null]]
                (if (not (urdr.certificate.markers-valid? Markers))
                    [error certificate-marker-shape [null]]
                    (urdr.certificate.build-run
                      (urdr.replay.run Initial Transcript)
                      Engine ScenarioValue ManifestValue Profile
                      Initial Transcript Verdicts Markers))))))

(define urdr.certificate.build-run
  [error Code Detail] _ _ _ _ _ _ _ _ -> [error Code Detail]
  [ok Run] Engine ScenarioValue ManifestValue Profile Initial
  Transcript Verdicts Markers ->
    (urdr.certificate.build-id
      (urdr.certificate.run-id-of
        Engine ScenarioValue ManifestValue Initial
        (urdr.replay.run-transcript-root Run) Profile)
      Run Engine ScenarioValue ManifestValue Profile Initial
      Transcript Verdicts Markers))

(define urdr.certificate.build-id
  [error Code Detail] _ _ _ _ _ _ _ _ _ -> [error Code Detail]
  [ok RunId] Run Engine ScenarioValue ManifestValue Profile Initial
  Transcript Verdicts Markers ->
    (urdr.certificate.build-digests
      (urdr.eventlog.value-digest ScenarioValue)
      (urdr.eventlog.value-digest ManifestValue)
      RunId Run Engine Profile Initial Transcript Verdicts Markers))

(define urdr.certificate.build-digests
  [error Code Detail] _ _ _ _ _ _ _ _ _ -> [error Code Detail]
  _ [error Code Detail] _ _ _ _ _ _ _ _ -> [error Code Detail]
  [ok ScenarioDigest] [ok ManifestDigest] RunId Run Engine Profile
  Initial Transcript Verdicts Markers ->
    (urdr.certificate.build-slot
      (urdr.eventlog.list-slot
        (urdr.certificate.n t-verdict-list) Verdicts)
      ScenarioDigest ManifestDigest RunId Run Engine Profile Initial
      Transcript Verdicts Markers))

\\ The model bindings are read off the initial world HERE, at the last
\\ point the build path still holds it: after this call the initial
\\ world is dropped and only its derived commitments travel on.
(define urdr.certificate.build-slot
  [error Code Detail] _ _ _ _ _ _ _ _ _ _ -> [error Code Detail]
  [ok Slot] ScenarioDigest ManifestDigest RunId Run Engine Profile
  Initial Transcript Verdicts Markers ->
    (urdr.certificate.build-verify
      (urdr.replay.verify
        Initial Transcript (urdr.replay.recorded Run))
      (urdr.certificate.models-value Initial)
      Slot ScenarioDigest ManifestDigest RunId Run Engine Profile
      Verdicts Markers))

\\ The replay result in the certificate is an INDEPENDENT re-drive
\\ compared against the artifact the first drive recorded, not a restated
\\ copy of the first drive. That is what makes the field evidence rather
\\ than a tautology, and it is the same comparison the 100-replay
\\ identity check performs, once.
(define urdr.certificate.build-verify
  Verification Models Slot ScenarioDigest ManifestDigest RunId Run
  Engine Profile Verdicts Markers ->
    (urdr.certificate.assemble
      (urdr.certificate.verified? Verification)
      (urdr.certificate.replay-value Verification)
      (urdr.certificate.verification-code Verification)
      Models Slot ScenarioDigest ManifestDigest RunId Run Engine
      Profile Verdicts Markers))

(define urdr.certificate.verified?
  [ok _] -> true
  _ -> false)

(define urdr.certificate.verification-code
  [error Code _] -> Code
  _ -> none)

(define urdr.certificate.replay-value
  [ok Verified] -> (urdr.replay.verified-value Verified)
  [error Code Detail] -> (urdr.replay.error-value Code Detail))

(define urdr.certificate.assemble
  Verified ReplayValue Code Models Slot ScenarioDigest ManifestDigest
  RunId Run Engine Profile Verdicts Markers ->
    (urdr.certificate.finish
      (urdr.eventlog.abstract? (urdr.replay.run-log Run))
      Verified ReplayValue Code Models Slot ScenarioDigest
      ManifestDigest RunId Run Engine Profile Verdicts Markers))

(define urdr.certificate.finish
  Clean Verified ReplayValue Code Models Slot ScenarioDigest
  ManifestDigest RunId Run Engine Profile Verdicts Markers ->
    [ok
      [certificate
        RunId
        (urdr.certificate.status-of Verified Clean Code Verdicts)
        (urdr.certificate.profile-of Verified Clean)
        Engine
        Profile
        ScenarioDigest
        ManifestDigest
        (urdr.certificate.markers-value Markers)
        Models
        ReplayValue
        Slot
        (urdr.certificate.summary-value Verdicts)
        Run]])

\\ ---------------------------------------------------------------
\\ Certificate accessors and canonical value
\\ ---------------------------------------------------------------

(define urdr.certificate.run-id
  [certificate RunId _ _ _ _ _ _ _ _ _ _ _ _] -> RunId)

(define urdr.certificate.status
  [certificate _ Status _ _ _ _ _ _ _ _ _ _ _] -> Status)

(define urdr.certificate.achieved-profile
  [certificate _ _ Profile _ _ _ _ _ _ _ _ _ _] -> Profile)

(define urdr.certificate.markers
  [certificate _ _ _ _ _ _ _ Markers _ _ _ _ _] -> Markers)

\\ The model bindings (ADR 0008): the sorted binding records of
\\ section 5, exposed so a consumer can answer "which model produced
\\ this evidence" without decoding the whole artifact.
(define urdr.certificate.models
  [certificate _ _ _ _ _ _ _ _ Models _ _ _ _] -> Models)

\\ The vacuity summary is exposed separately from the certificate value
\\ so a consumer can read "this property never fired" without decoding
\\ the whole artifact, and without re-deriving it from a verdict list
\\ that may be content-addressed.
(define urdr.certificate.verdict-summary
  [certificate _ _ _ _ _ _ _ _ _ _ _ Summary _] -> Summary)

(define urdr.certificate.run
  [certificate _ _ _ _ _ _ _ _ _ _ _ _ Run] -> Run)

(define urdr.certificate.log
  Cert -> (urdr.replay.run-log (urdr.certificate.run Cert)))

(define urdr.certificate.recorded
  Cert -> (urdr.replay.recorded (urdr.certificate.run Cert)))

(define urdr.certificate.value
  [certificate RunId Status Achieved Engine Profile ScenarioDigest
    ManifestDigest Markers Models ReplayValue Slot Summary Run] ->
    [record
      [[(urdr.certificate.n k-achieved-profile) [symbol Achieved]]
       [(urdr.certificate.n k-artifact-manifest)
        [bytes ManifestDigest]]
       [(urdr.certificate.n k-engine-version) [bytes Engine]]
       [(urdr.certificate.n k-entropy)
        (urdr.eventlog.counts-value (urdr.replay.run-log Run))]
       [(urdr.certificate.n k-event-root)
        [bytes (urdr.replay.run-event-root Run)]]
       [(urdr.certificate.n k-input-transcript-root)
        (urdr.certificate.input-root-value
          (urdr.certificate.input-transcript-root))]
       [(urdr.certificate.n k-markers)
        [list (urdr.certificate.symbols Markers)]]
       [(urdr.certificate.n k-models) [list Models]]
       [(urdr.certificate.n k-replay) ReplayValue]
       [(urdr.certificate.n k-requested-profile) [bytes Profile]]
       [(urdr.certificate.n k-run-id) [bytes RunId]]
       [(urdr.certificate.n k-scenario-digest) [bytes ScenarioDigest]]
       [(urdr.certificate.n k-state-root)
        [bytes (urdr.replay.run-state-root Run)]]
       [(urdr.certificate.n k-status) [symbol Status]]
       [(urdr.certificate.n k-transcript-root)
        [bytes (urdr.replay.run-transcript-root Run)]]
       [(urdr.certificate.n k-verdict-summary) Summary]
       [(urdr.certificate.n k-verdicts) Slot]
       [(urdr.certificate.n k-version)
        [symbol (urdr.certificate.n w-certificate-v2)]]]])

(define urdr.certificate.input-root-value
  [ok Root] -> [bytes Root]
  _ -> [null])

(define urdr.certificate.frame
  Cert -> (urdr.canonical.encode-frame (urdr.certificate.value Cert)))

(define urdr.certificate.payload
  Cert ->
    (urdr.canonical.encode-payload (urdr.certificate.value Cert)))
