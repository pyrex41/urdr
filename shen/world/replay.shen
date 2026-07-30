\\ Decision-transcript writer, reader, and replay verification
\\ (M1 plan Wave E, SPEC.md 4 and 20.2). Requires
\\ shen/protocol/canonical.shen, shen/world/integer.shen,
\\ shen/world/prng.shen, shen/world/component.shen,
\\ shen/world/world.shen, and shen/world/eventlog.shen to be loaded by
\\ the caller.
\\
\\ Pure: no I/O, no host time, no host randomness, no floating point, no
\\ defprolog. Replay is a total function of (initial world, candidate
\\ transcript, recorded artifact). Every operation returns [ok ...] or
\\ [error CODE DETAIL] and performs no work before validating.
\\
\\ NOT owned here: the reducer, and the meaning of any event. This module
\\ re-drives urdr.world.reduce over a transcript and compares digests. It
\\ never decides what a divergence means beyond naming where it is.
\\ world.shen is unchanged; urdr.world.replay (a different function, in a
\\ different namespace) is left exactly as it was.
\\
\\ =====================================================================
\\ 1. The written transcript
\\ =====================================================================
\\
\\ A reducer input is written as one canonical record. A schedule:
\\
\\   [record [[at      INTEGER]
\\            [kind    [symbol KIND]]
\\            [payload CANONICAL-VALUE]
\\            [type    [symbol schedule]]]]
\\
\\ An advance:
\\
\\   [record [[type [symbol advance]]]]
\\
\\ KIND is one of command-input, choice-input, component-input,
\\ property-input. The bare reducer tags `command` and `choice` are
\\ reserved-authority names (component.shen) and are never written into a
\\ structural position; urdr.eventlog.kind-name and kind-of-name own that
\\ translation in both directions, and the payload projection is
\\ urdr.eventlog.payload-value / payload-of, so the writer and the event
\\ log cannot drift apart.
\\
\\ A choice-input payload carries either the drawn form (menu only: the
\\ world re-draws on reduce) or the selected form (ADR 0007 D2: menu
\\ plus the selected alternative and the PRNG coordinates that produced
\\ it, so the transcript -- not the PRNG -- is the replay authority).
\\ The selected and coordinates keys are additive: menu-only entries
\\ written before the selected form existed read back unchanged.
\\
\\ urdr.replay.write is a total inverse of urdr.replay.read on every
\\ transcript the reducer can produce. A written entry that does not read
\\ back is replay-entry-shape, never a silent repair.
\\
\\ The transcript root is
\\   root(urdr-transcript-root-v1, [SHA-256(entry value) ...])
\\ using the same tagged fixed-width construction as the event root
\\ (eventlog.shen section 4). The transcript header value is
\\
\\   [record [[count   INTEGER]
\\            [root    [bytes SHA-256]]
\\            [version [symbol urdr-transcript-v1]]]]
\\
\\ so an arbitrarily long transcript is still a bounded canonical value:
\\ content addressing, per SPEC.md 20, rather than a bigger frame.
\\
\\ =====================================================================
\\ 2. The recorded artifact
\\ =====================================================================
\\
\\   [recorded ENTRY-DIGESTS TRANSCRIPT-ROOT EVENT-DIGESTS EVENT-ROOT
\\             STATE-ROOT]
\\
\\ Everything a verifier needs and nothing it does not: no world, no
\\ handlers, no payloads. urdr.replay.recorded projects it out of a run.
\\
\\ =====================================================================
\\ 3. Divergence taxonomy
\\ =====================================================================
\\
\\ Verification is fail-closed and each failure mode has its own stable
\\ code. The transcript is classified BEFORE the reduction is re-driven,
\\ because a transcript that is not the recorded one cannot produce
\\ meaningful evidence about the engine:
\\
\\   replay-transcript-truncated  fewer entries than recorded
\\   replay-transcript-extended   more entries than recorded
\\   replay-transcript-reordered  same multiset of entries, different
\\                                order; detail names the first index
\\                                that differs
\\   replay-transcript-tampered   same length, different multiset;
\\                                detail names the first index that
\\                                differs
\\
\\ Reordering and tampering are separated deliberately. They are the two
\\ ways a transcript of the right length can be wrong, they have
\\ different causes (a scheduler bug versus a corrupted artifact), and a
\\ shrinker that reorders needs to know which one it produced.
\\
\\ With a matching transcript, the re-drive is compared event by event:
\\
\\   replay-event-count       the two event streams have different
\\                            lengths (only reachable if a reduction
\\                            stopped early)
\\   replay-event-divergence  the first differing event, by log event-id,
\\                            with the expected and actual record digests
\\   replay-state-divergence  every event agreed but the final state
\\                            roots differ
\\   replay-selection-divergence  the re-drive refused a recorded
\\                            selection: the world rejected a selected
\\                            choice entry as not a member of its menu
\\                            (choice-selection-not-member)
\\
\\ A reduction that fails during the re-drive surfaces the event log's
\\ own code (eventlog-reduction-error and friends) unchanged, because the
\\ run did not diverge -- it did not happen. The one exception is a
\\ choice-selection-not-member refusal (ADR 0007 D2): the transcript
\\ already matched the recorded entry digests, so the artifact is the
\\ recorded one, and a recorded selection the engine's own membership
\\ door now refuses is not "the run did not happen" -- it is the engine
\\ and the artifact disagreeing about what was decided, the same species
\\ of evidence as a differing event digest. It is therefore classified
\\ replay-selection-divergence and joins the DIVERGED family in
\\ certificate.shen's replay-code partition; the world's error record
\\ travels as the detail so the refused selection stays attributable.
\\
\\ =====================================================================
\\ 4. Public entry points
\\ =====================================================================
\\
\\   entry-value        INPUT -> [ok VALUE] | [error CODE DETAIL]
\\   entry-of           VALUE -> [ok INPUT] | [error CODE DETAIL]
\\   write              TRANSCRIPT -> [ok [VALUE ...]] | [error C D]
\\   read               [VALUE ...] -> [ok TRANSCRIPT] | [error C D]
\\   entry-digests      TRANSCRIPT -> [ok [OCTETS ...]] | [error C D]
\\   transcript-root    TRANSCRIPT -> [ok OCTETS] | [error C D]
\\   transcript-value   TRANSCRIPT -> [ok VALUE] | [error C D]
\\   run                INITIAL TRANSCRIPT -> [ok RUN] | [error C D]
\\   run-log / run-entry-digests / run-transcript-root
\\   run-event-root / run-state-root / run-count
\\   recorded           RUN -> RECORDED
\\   recorded-value     RECORDED -> canonical record
\\   verify             INITIAL TRANSCRIPT RECORDED
\\                        -> [ok VERIFIED] | [error CODE DETAIL]
\\   verified-value     VERIFIED -> canonical record
\\   error-value        CODE DETAIL -> canonical record
\\   code-octets        CODE -> OCTETS

\\ ---------------------------------------------------------------
\\ ASCII names as octet lists (k- keys, w- words, t- domain tags,
\\ c- stable error codes). The prefixes keep Shen primitive names such
\\ as `value`, `type`, and `length` out of argument position.
\\ ---------------------------------------------------------------

(define urdr.replay.n
  k-at ->
    [97 116]
  k-kind ->
    [107 105 110 100]
  k-payload ->
    [112 97 121 108 111 97 100]
  k-type ->
    [116 121 112 101]
  k-count ->
    [99 111 117 110 116]
  k-root ->
    [114 111 111 116]
  k-version ->
    [118 101 114 115 105 111 110]
  k-actual ->
    [97 99 116 117 97 108]
  k-expected ->
    [101 120 112 101 99 116 101 100]
  k-actual-length ->
    [97 99 116 117 97 108 45 108 101 110 103 116 104]
  k-expected-length ->
    [101 120 112 101 99 116 101 100 45 108 101 110 103 116 104]
  k-index ->
    [105 110 100 101 120]
  k-event-id ->
    [101 118 101 110 116 45 105 100]
  k-code ->
    [99 111 100 101]
  k-detail ->
    [100 101 116 97 105 108]
  k-entries ->
    [101 110 116 114 105 101 115]
  k-event-root ->
    [101 118 101 110 116 45 114 111 111 116]
  k-state-root ->
    [115 116 97 116 101 45 114 111 111 116]
  k-transcript-root ->
    [116 114 97 110 115 99 114 105 112 116 45 114 111 111 116]
  k-result ->
    [114 101 115 117 108 116]
  w-schedule ->
    [115 99 104 101 100 117 108 101]
  w-advance ->
    [97 100 118 97 110 99 101]
  w-transcript-v1 ->
    [117 114 100 114 45 116 114 97 110 115 99 114 105 112 116 45
     118 49]
  w-recorded-v1 ->
    [117 114 100 114 45 114 101 99 111 114 100 101 100 45 118 49]
  w-verified ->
    [118 101 114 105 102 105 101 100]
  t-transcript-root ->
    [117 114 100 114 45 116 114 97 110 115 99 114 105 112 116 45
     114 111 111 116 45 118 49]
  c-entry-shape ->
    [114 101 112 108 97 121 45 101 110 116 114 121 45 115 104 97
     112 101]
  c-transcript-shape ->
    [114 101 112 108 97 121 45 116 114 97 110 115 99 114 105 112
     116 45 115 104 97 112 101]
  c-transcript-truncated ->
    [114 101 112 108 97 121 45 116 114 97 110 115 99 114 105 112
     116 45 116 114 117 110 99 97 116 101 100]
  c-transcript-extended ->
    [114 101 112 108 97 121 45 116 114 97 110 115 99 114 105 112
     116 45 101 120 116 101 110 100 101 100]
  c-transcript-reordered ->
    [114 101 112 108 97 121 45 116 114 97 110 115 99 114 105 112
     116 45 114 101 111 114 100 101 114 101 100]
  c-transcript-tampered ->
    [114 101 112 108 97 121 45 116 114 97 110 115 99 114 105 112
     116 45 116 97 109 112 101 114 101 100]
  c-event-count ->
    [114 101 112 108 97 121 45 101 118 101 110 116 45 99 111 117
     110 116]
  c-event-divergence ->
    [114 101 112 108 97 121 45 101 118 101 110 116 45 100 105 118
     101 114 103 101 110 99 101]
  c-state-divergence ->
    [114 101 112 108 97 121 45 115 116 97 116 101 45 100 105 118
     101 114 103 101 110 99 101]
  c-selection-divergence ->
    [114 101 112 108 97 121 45 115 101 108 101 99 116 105 111 110
     45 100 105 118 101 114 103 101 110 99 101]
  c-recorded-shape ->
    [114 101 112 108 97 121 45 114 101 99 111 114 100 101 100 45
     115 104 97 112 101]
  c-unmapped ->
    [114 101 112 108 97 121 45 117 110 109 97 112 112 101 100 45
     99 111 100 101])

\\ Stable Shen-symbol codes, and their canonical octet names. Every code
\\ this module can emit has a clause; anything else renders as
\\ replay-unmapped-code rather than as an unstable host rendering of a
\\ symbol.
(define urdr.replay.code-octets
  replay-entry-shape -> (urdr.replay.n c-entry-shape)
  replay-transcript-shape -> (urdr.replay.n c-transcript-shape)
  replay-transcript-truncated ->
    (urdr.replay.n c-transcript-truncated)
  replay-transcript-extended -> (urdr.replay.n c-transcript-extended)
  replay-transcript-reordered ->
    (urdr.replay.n c-transcript-reordered)
  replay-transcript-tampered -> (urdr.replay.n c-transcript-tampered)
  replay-event-count -> (urdr.replay.n c-event-count)
  replay-event-divergence -> (urdr.replay.n c-event-divergence)
  replay-state-divergence -> (urdr.replay.n c-state-divergence)
  replay-selection-divergence ->
    (urdr.replay.n c-selection-divergence)
  replay-recorded-shape -> (urdr.replay.n c-recorded-shape)
  _ -> (urdr.replay.n c-unmapped))

(define urdr.replay.error-value
  Code Detail ->
    [record
      [[(urdr.replay.n k-code)
        [symbol (urdr.replay.code-octets Code)]]
       [(urdr.replay.n k-detail) Detail]]])

(define urdr.replay.big
  N -> (urdr.int.raw.from-small N))

\\ ---------------------------------------------------------------
\\ Writer
\\ ---------------------------------------------------------------

(define urdr.replay.entry-value
  [schedule At Kind Payload] ->
    (urdr.replay.schedule-value
      (urdr.eventlog.kind-name Kind)
      (urdr.eventlog.payload-value Kind Payload)
      At)
  [advance-to-next-event] ->
    [ok
      [record
        [[(urdr.replay.n k-type)
          [symbol (urdr.replay.n w-advance)]]]]]
  _ -> [error replay-entry-shape [null]])

(define urdr.replay.schedule-value
  [error Code Detail] _ _ -> [error Code Detail]
  _ [error Code Detail] _ -> [error Code Detail]
  [ok Kind] [ok Payload] At ->
    [ok
      [record
        [[(urdr.replay.n k-at) At]
         [(urdr.replay.n k-kind) [symbol Kind]]
         [(urdr.replay.n k-payload) Payload]
         [(urdr.replay.n k-type)
          [symbol (urdr.replay.n w-schedule)]]]]])

(define urdr.replay.write
  Transcript -> (urdr.replay.write-loop Transcript []))

(define urdr.replay.write-loop
  [] Acc -> [ok (urdr.canonical.rev Acc)]
  [Input | Rest] Acc ->
    (urdr.replay.write-step (urdr.replay.entry-value Input) Rest Acc)
  _ Acc -> [error replay-transcript-shape [null]])

(define urdr.replay.write-step
  [error Code Detail] _ _ -> [error Code Detail]
  [ok Value] Rest Acc -> (urdr.replay.write-loop Rest [Value | Acc]))

\\ ---------------------------------------------------------------
\\ Reader
\\ ---------------------------------------------------------------

(define urdr.replay.entry-of
  [record
    [[[97 116] At]
     [[107 105 110 100] [symbol KindName]]
     [[112 97 121 108 111 97 100] Payload]
     [[116 121 112 101]
      [symbol [115 99 104 101 100 117 108 101]]]]] ->
    (urdr.replay.entry-of-kind
      (urdr.eventlog.kind-of-name KindName) At Payload)
  [record
    [[[116 121 112 101]
      [symbol [97 100 118 97 110 99 101]]]]] ->
    [ok [advance-to-next-event]]
  _ -> [error replay-entry-shape [null]])

(define urdr.replay.entry-of-kind
  [error Code Detail] _ _ -> [error Code Detail]
  [ok Kind] At Payload ->
    (urdr.replay.entry-of-payload
      (urdr.eventlog.payload-of Kind Payload) At Kind))

(define urdr.replay.entry-of-payload
  [error Code Detail] _ _ -> [error Code Detail]
  [ok Payload] At Kind -> [ok [schedule At Kind Payload]])

(define urdr.replay.read
  Values -> (urdr.replay.read-loop Values []))

(define urdr.replay.read-loop
  [] Acc -> [ok (urdr.canonical.rev Acc)]
  [Value | Rest] Acc ->
    (urdr.replay.read-step (urdr.replay.entry-of Value) Rest Acc)
  _ Acc -> [error replay-transcript-shape [null]])

(define urdr.replay.read-step
  [error Code Detail] _ _ -> [error Code Detail]
  [ok Input] Rest Acc -> (urdr.replay.read-loop Rest [Input | Acc]))

\\ ---------------------------------------------------------------
\\ Transcript digests and root
\\ ---------------------------------------------------------------

(define urdr.replay.entry-digests
  Transcript ->
    (urdr.replay.entry-digests-of (urdr.replay.write Transcript)))

(define urdr.replay.entry-digests-of
  [error Code Detail] -> [error Code Detail]
  [ok Values] -> (urdr.eventlog.value-digests Values []))

(define urdr.replay.transcript-root
  Transcript ->
    (urdr.replay.transcript-root-of
      (urdr.replay.entry-digests Transcript)))

(define urdr.replay.transcript-root-of
  [error Code Detail] -> [error Code Detail]
  [ok Digests] ->
    (urdr.eventlog.root-of (urdr.replay.n t-transcript-root) Digests))

(define urdr.replay.transcript-header
  Root Count ->
    [record
      [[(urdr.replay.n k-count) (urdr.replay.big Count)]
       [(urdr.replay.n k-root) [bytes Root]]
       [(urdr.replay.n k-version)
        [symbol (urdr.replay.n w-transcript-v1)]]]])

(define urdr.replay.transcript-value
  Transcript ->
    (urdr.replay.transcript-value-of
      (urdr.replay.transcript-root Transcript)
      (urdr.replay.transcript-length Transcript 0)))

(define urdr.replay.transcript-length
  [] Acc -> Acc
  [_ | Rest] Acc -> (urdr.replay.transcript-length Rest (+ Acc 1))
  _ Acc -> Acc)

(define urdr.replay.transcript-value-of
  [error Code Detail] _ -> [error Code Detail]
  [ok Root] Count -> [ok (urdr.replay.transcript-header Root Count)])

\\ ---------------------------------------------------------------
\\ Running
\\ ---------------------------------------------------------------

(define urdr.replay.run
  Initial Transcript ->
    (urdr.replay.run-digests
      (urdr.replay.entry-digests Transcript) Initial Transcript))

(define urdr.replay.run-digests
  [error Code Detail] _ _ -> [error Code Detail]
  [ok EntryDigests] Initial Transcript ->
    (urdr.replay.run-root
      (urdr.eventlog.root-of
        (urdr.replay.n t-transcript-root) EntryDigests)
      EntryDigests Initial Transcript))

(define urdr.replay.run-root
  [error Code Detail] _ _ _ -> [error Code Detail]
  [ok Root] EntryDigests Initial Transcript ->
    (urdr.replay.run-log-of
      (urdr.eventlog.of-run Initial Transcript) EntryDigests Root))

(define urdr.replay.run-log-of
  [error Code Detail] _ _ -> [error Code Detail]
  [ok Log] EntryDigests Root -> [ok [run Log EntryDigests Root]])

(define urdr.replay.run-log
  [run Log _ _] -> Log)

(define urdr.replay.run-entry-digests
  [run _ Digests _] -> Digests)

(define urdr.replay.run-transcript-root
  [run _ _ Root] -> Root)

(define urdr.replay.run-event-root
  [run Log _ _] -> (urdr.eventlog.root Log))

(define urdr.replay.run-state-root
  [run Log _ _] -> (urdr.eventlog.state-root Log))

(define urdr.replay.run-count
  [run Log _ _] -> (urdr.eventlog.count Log))

\\ ---------------------------------------------------------------
\\ The recorded artifact
\\ ---------------------------------------------------------------

(define urdr.replay.recorded
  [run Log EntryDigests Root] ->
    [recorded
      EntryDigests
      Root
      (urdr.eventlog.digests Log)
      (urdr.eventlog.root Log)
      (urdr.eventlog.state-root Log)])

(define urdr.replay.recorded-value
  [recorded _ TranscriptRoot _ EventRoot StateRoot] ->
    [record
      [[(urdr.replay.n k-event-root) [bytes EventRoot]]
       [(urdr.replay.n k-state-root) [bytes StateRoot]]
       [(urdr.replay.n k-transcript-root) [bytes TranscriptRoot]]
       [(urdr.replay.n k-version)
        [symbol (urdr.replay.n w-recorded-v1)]]]])

\\ ---------------------------------------------------------------
\\ Digest list comparison
\\ ---------------------------------------------------------------

(define urdr.replay.length
  Values -> (urdr.replay.transcript-length Values 0))

\\ The index of the first position at which two equal-length digest
\\ lists differ, or none.
(define urdr.replay.first-difference
  [] [] _ -> none
  [A | As] [B | Bs] Index ->
    (if (= A B)
        (urdr.replay.first-difference As Bs (+ Index 1))
        Index)
  _ _ _ -> none)

(define urdr.replay.insert
  D [] -> [D]
  D [Head | Rest] ->
    (if (= (urdr.canonical.bytes-compare D Head) gt)
        [Head | (urdr.replay.insert D Rest)]
        [D Head | Rest]))

(define urdr.replay.sort
  [] -> []
  [D | Rest] -> (urdr.replay.insert D (urdr.replay.sort Rest)))

\\ Two digest lists are a permutation of one another exactly when their
\\ sorted forms are equal. Digests are fixed-width octet lists, so the
\\ ordering is total.
(define urdr.replay.permutation?
  As Bs -> (= (urdr.replay.sort As) (urdr.replay.sort Bs)))

(define urdr.replay.length-detail
  Actual Expected Index ->
    [record
      [[(urdr.replay.n k-actual-length) (urdr.replay.big Actual)]
       [(urdr.replay.n k-expected-length) (urdr.replay.big Expected)]
       [(urdr.replay.n k-index) Index]]])

(define urdr.replay.digest-detail
  Actual Expected Id ->
    [record
      [[(urdr.replay.n k-actual) [bytes Actual]]
       [(urdr.replay.n k-event-id) Id]
       [(urdr.replay.n k-expected) [bytes Expected]]]])

(define urdr.replay.state-detail
  Actual Expected ->
    [record
      [[(urdr.replay.n k-actual) [bytes Actual]]
       [(urdr.replay.n k-expected) [bytes Expected]]]])

\\ ---------------------------------------------------------------
\\ Verification (section 3)
\\ ---------------------------------------------------------------

(define urdr.replay.verify
  Initial Transcript
  [recorded EntryDigests TranscriptRoot EventDigests EventRoot
            StateRoot] ->
    (urdr.replay.verify-entries
      (urdr.replay.entry-digests Transcript)
      Initial Transcript EntryDigests EventDigests EventRoot StateRoot)
  Initial Transcript _ -> [error replay-recorded-shape [null]])

(define urdr.replay.verify-entries
  [error Code Detail] _ _ _ _ _ _ -> [error Code Detail]
  [ok Actual] Initial Transcript Expected EventDigests EventRoot
  StateRoot ->
    (urdr.replay.verify-transcript
      (urdr.replay.classify-transcript Actual Expected)
      Initial Transcript EventDigests EventRoot StateRoot))

\\ Classify the candidate transcript against the recorded one before any
\\ reduction runs.
(define urdr.replay.classify-transcript
  Actual Expected ->
    (urdr.replay.classify-lengths
      Actual Expected
      (urdr.replay.length Actual)
      (urdr.replay.length Expected)))

(define urdr.replay.classify-lengths
  Actual Expected A E ->
    (if (< A E)
        [error replay-transcript-truncated
          (urdr.replay.length-detail A E [null])]
        (if (> A E)
            [error replay-transcript-extended
              (urdr.replay.length-detail A E [null])]
            (urdr.replay.classify-order
              Actual Expected A E
              (urdr.replay.first-difference Actual Expected 0)))))

(define urdr.replay.classify-order
  Actual Expected A E none -> [ok]
  Actual Expected A E Index ->
    (if (urdr.replay.permutation? Actual Expected)
        [error replay-transcript-reordered
          (urdr.replay.length-detail A E (urdr.replay.big Index))]
        [error replay-transcript-tampered
          (urdr.replay.length-detail A E (urdr.replay.big Index))]))

(define urdr.replay.verify-transcript
  [error Code Detail] _ _ _ _ _ -> [error Code Detail]
  [ok] Initial Transcript EventDigests EventRoot StateRoot ->
    (urdr.replay.verify-run
      (urdr.replay.classify-redrive
        (urdr.eventlog.of-run Initial Transcript))
      EventDigests EventRoot StateRoot))

\\ Section 3: only reached AFTER the transcript matched the recorded
\\ entry digests, so a re-drive refusal of a recorded selection is
\\ engine/artifact disagreement (DIVERGED family), not a run that never
\\ happened. The stable world code is matched by its octet name so this
\\ classification cannot drift from the reducer's own vocabulary; every
\\ other reduction error passes through unchanged, and the recorder path
\\ (urdr.replay.run) is deliberately NOT classified -- while recording
\\ there is no artifact to disagree with yet.
(define urdr.replay.selection-code-octets
  -> [99 104 111 105 99 101 45 115 101 108 101 99 116 105 111 110
      45 110 111 116 45 109 101 109 98 101 114])

(define urdr.replay.classify-redrive
  [error eventlog-reduction-error
    [record [[[99 111 100 101] [symbol Code]] | Fields]]] ->
    (if (= Code (urdr.replay.selection-code-octets))
        [error replay-selection-divergence
          [record [[[99 111 100 101] [symbol Code]] | Fields]]]
        [error eventlog-reduction-error
          [record [[[99 111 100 101] [symbol Code]] | Fields]]])
  Result -> Result)

(define urdr.replay.verify-run
  [error Code Detail] _ _ _ -> [error Code Detail]
  [ok Log] EventDigests EventRoot StateRoot ->
    (urdr.replay.verify-events
      (urdr.replay.compare-events
        (urdr.eventlog.digests Log) EventDigests 0)
      Log EventRoot StateRoot))

(define urdr.replay.compare-events
  [] [] _ -> [ok]
  [] Expected Index ->
    [error replay-event-count
      (urdr.replay.length-detail
        Index (+ Index (urdr.replay.length Expected))
        (urdr.replay.big Index))]
  Actual [] Index ->
    [error replay-event-count
      (urdr.replay.length-detail
        (+ Index (urdr.replay.length Actual)) Index
        (urdr.replay.big Index))]
  [A | As] [E | Es] Index ->
    (if (= A E)
        (urdr.replay.compare-events As Es (+ Index 1))
        [error replay-event-divergence
          (urdr.replay.digest-detail A E (urdr.replay.big Index))]))

(define urdr.replay.verify-events
  [error Code Detail] _ _ _ -> [error Code Detail]
  [ok] Log EventRoot StateRoot ->
    (if (not (= (urdr.eventlog.root Log) EventRoot))
        [error replay-event-divergence
          (urdr.replay.digest-detail
            (urdr.eventlog.root Log) EventRoot [null])]
        (if (not (= (urdr.eventlog.state-root Log) StateRoot))
            [error replay-state-divergence
              (urdr.replay.state-detail
                (urdr.eventlog.state-root Log) StateRoot)]
            [ok [verified Log]])))

(define urdr.replay.verified-log
  [verified Log] -> Log)

(define urdr.replay.verified-value
  [verified Log] ->
    [record
      [[(urdr.replay.n k-count)
        (urdr.replay.big (urdr.eventlog.count Log))]
       [(urdr.replay.n k-event-root)
        [bytes (urdr.eventlog.root Log)]]
       [(urdr.replay.n k-result)
        [symbol (urdr.replay.n w-verified)]]
       [(urdr.replay.n k-state-root)
        [bytes (urdr.eventlog.state-root Log)]]]])
