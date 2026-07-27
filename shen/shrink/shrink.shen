\\ Transcript minimization (SPEC.md 17.1, M1 plan Wave F). Requires
\\ shen/protocol/canonical.shen, shen/world/integer.shen,
\\ shen/world/prng.shen, shen/world/world.shen, shen/world/eventlog.shen,
\\ shen/world/replay.shen, and shen/world/certificate.shen to be loaded
\\ by the caller.
\\
\\ Pure: no I/O, no host time, no host randomness, no floating point, no
\\ defprolog. Every operation returns [ok ...] or [error CODE DETAIL] and
\\ performs no work before validating.
\\
\\ NOT owned here: property evaluation, the reducer, or search strategies.
\\ This module drives candidates with a pure EVAL oracle and accepts a
\\ candidate only when urdr.certificate.failure-signature of the
\\ candidate's verdicts equals the original failure signature.
\\ certificate.shen section 7: use urdr.replay.run (NOT verify) for
\\ candidates; equal signatures => same failure persists; anything else
\\ => reject.
\\
\\ =====================================================================
\\ 1. What shrinks
\\ =====================================================================
\\
\\ Given a reproducible failure (original transcript + original failure
\\ signature), minimize over the SPEC.md 17.1 reduction order:
\\
\\   1. Injected faults
\\   2. Network perturbations
\\   3. Artificial delays
\\   4. Scheduling choices
\\   5. External transcript entries
\\   6. Scenario actions
\\
\\ Each transcript entry is classified by urdr.shrink.class-of. Entries
\\ whose class is outside the order above are left untouched.
\\
\\ Snapshot-awareness in M1 is transcript-prefix reuse, not VM snapshots:
\\ when a candidate shares a prefix with the original, the candidate is
\\ literally that prefix concatenated with a (possibly empty) suffix, so
\\ the shared prefix is never reconstructed by a different path.
\\
\\ =====================================================================
\\ 2. Acceptance oracle
\\ =====================================================================
\\
\\   accepts? ORIGINAL-SIG CANDIDATE-VERDICTS
\\     -> true  iff failure-signature(CANDIDATE-VERDICTS) = ORIGINAL-SIG
\\     -> false otherwise (including any error)
\\
\\ EVAL is a pure function Transcript -> [ok VERDICT-VALUES] | [error ...]
\\ supplied by the caller. For a full abstract run the caller composes
\\ urdr.replay.run with property evaluation; fixture suites may supply a
\\ lighter oracle that still produces property-shaped verdict records so
\\ the signature comparison is real.
\\
\\ A mutation that drops the actual failing fault must produce a different
\\ (or empty) signature and is rejected. Tests prove that direction.
\\
\\ =====================================================================
\\ 3. Public entry points
\\ =====================================================================
\\
\\   class-of          INPUT -> fault | perturbation | delay |
\\                              schedule | external | scenario | other
\\   classify          TRANSCRIPT -> [[CLASS INPUT] ...]
\\   accepts?          ORIGINAL-SIG VERDICTS -> true | false
\\   signature-of      VERDICTS -> [ok OCTETS] | [error C D]
\\   try-candidate     ORIGINAL-SIG EVAL CANDIDATE
\\                       -> [ok CANDIDATE] | [reject REASON]
\\   minimize          ORIGINAL-SIG EVAL TRANSCRIPT
\\                       -> [ok MINIMIZED] | [error C D]
\\   length            TRANSCRIPT -> small natural
\\
\\ The minimized transcript remains independently replayable via
\\ urdr.replay.run whenever the original was.

\\ ---------------------------------------------------------------
\\ ASCII names as octet lists.
\\ ---------------------------------------------------------------

(define urdr.shrink.n
  c-sig ->
    [115 104 114 105 110 107 45 115 105 103 110 97 116 117 114
     101]
  c-transcript ->
    [115 104 114 105 110 107 45 116 114 97 110 115 99 114 105 112
     116]
  w-reject-sig ->
    [115 105 103 110 97 116 117 114 101 45 109 105 115 109 97 116
     99 104]
  w-reject-error ->
    [101 118 97 108 45 101 114 114 111 114]
  s-fault ->
    [102 97 117 108 116]
  s-perturbation ->
    [112 101 114 116 117 114 98 97 116 105 111 110]
  s-delay ->
    [100 101 108 97 121]
  s-schedule ->
    [115 99 104 101 100 117 108 101]
  s-external ->
    [101 120 116 101 114 110 97 108]
  s-scenario ->
    [115 99 101 110 97 114 105 111]
  s-net ->
    [110 101 116]
  s-timer ->
    [116 105 109 101 114]
  k-shrink-class ->
    [115 104 114 105 110 107 45 99 108 97 115 115])

\\ ---------------------------------------------------------------
\\ Classification (SPEC.md 17.1)
\\ ---------------------------------------------------------------
\\
\\ Abstract transcripts carry reducer inputs. Classification is by the
\\ scheduled kind and a light payload tag when present:
\\
\\   choice purpose "fault"              -> fault
\\   choice purpose "perturbation"       -> perturbation
\\   choice purpose "delay"              -> delay
\\   choice purpose "schedule" / other   -> schedule
\\   component named fault/net/timer     -> fault/perturbation/delay
\\   command (optionally tagged)         -> external
\\   property / advance / other component-> scenario
\\
\\ Tagging: a command record may carry key shrink-class with a symbol
\\ naming the class. Untagged entries use the structural defaults.

(define urdr.shrink.bytes=
  A B -> (= A B))

(define urdr.shrink.purpose-class
  Purpose ->
    (if (urdr.shrink.bytes= Purpose (urdr.shrink.n s-fault))
        fault
        (if (urdr.shrink.bytes= Purpose (urdr.shrink.n s-perturbation))
            perturbation
            (if (urdr.shrink.bytes= Purpose (urdr.shrink.n s-delay))
                delay
                (if (urdr.shrink.bytes= Purpose (urdr.shrink.n s-schedule))
                    schedule
                    schedule)))))

(define urdr.shrink.payload-class
  [choice _ _ Purpose _] -> (urdr.shrink.purpose-class Purpose)
  [component-input Name _] ->
    (if (urdr.shrink.bytes= Name (urdr.shrink.n s-fault))
        fault
        (if (urdr.shrink.bytes= Name (urdr.shrink.n s-net))
            perturbation
            (if (urdr.shrink.bytes= Name (urdr.shrink.n s-timer))
                delay
                scenario)))
  [property _ _ _] -> scenario
  [record Fields] -> (urdr.shrink.record-class Fields)
  _ -> other)

(define urdr.shrink.record-class
  [] -> external
  [[Key [symbol ClassBs]] | Rest] ->
    (if (urdr.shrink.bytes= Key (urdr.shrink.n k-shrink-class))
        (urdr.shrink.symbol-class ClassBs)
        (urdr.shrink.record-class Rest))
  [_ | Rest] -> (urdr.shrink.record-class Rest))

(define urdr.shrink.symbol-class
  Bs ->
    (if (urdr.shrink.bytes= Bs (urdr.shrink.n s-fault))
        fault
        (if (urdr.shrink.bytes= Bs (urdr.shrink.n s-perturbation))
            perturbation
            (if (urdr.shrink.bytes= Bs (urdr.shrink.n s-delay))
                delay
                (if (urdr.shrink.bytes= Bs (urdr.shrink.n s-schedule))
                    schedule
                    (if (urdr.shrink.bytes= Bs (urdr.shrink.n s-external))
                        external
                        (if (urdr.shrink.bytes= Bs
                              (urdr.shrink.n s-scenario))
                            scenario
                            other)))))))

(define urdr.shrink.class-of
  [schedule _ choice Payload] -> (urdr.shrink.payload-class Payload)
  [schedule _ component Payload] -> (urdr.shrink.payload-class Payload)
  [schedule _ command Payload] -> (urdr.shrink.payload-class Payload)
  [schedule _ property-equals _] -> scenario
  [advance-to-next-event] -> scenario
  _ -> other)

(define urdr.shrink.classify
  [] -> []
  [Input | Rest] ->
    [[(urdr.shrink.class-of Input) Input] |
     (urdr.shrink.classify Rest)])

(define urdr.shrink.length
  [] -> 0
  [_ | Xs] -> (+ 1 (urdr.shrink.length Xs)))

\\ Classes in SPEC.md 17.1 reduction order.
(define urdr.shrink.order
  -> [fault perturbation delay schedule external scenario])

\\ ---------------------------------------------------------------
\\ Acceptance
\\ ---------------------------------------------------------------

(define urdr.shrink.signature-of
  Verdicts -> (urdr.certificate.failure-signature Verdicts))

(define urdr.shrink.accepts?
  OriginalSig Verdicts ->
    (urdr.shrink.accepts-sig
      OriginalSig (urdr.certificate.failure-signature Verdicts)))

(define urdr.shrink.accepts-sig
  OriginalSig [ok Sig] -> (= OriginalSig Sig)
  _ _ -> false)

(define urdr.shrink.try-candidate
  OriginalSig Eval Candidate ->
    (urdr.shrink.try-eval OriginalSig (Eval Candidate) Candidate))

(define urdr.shrink.try-eval
  OriginalSig [ok Verdicts] Candidate ->
    (if (urdr.shrink.accepts? OriginalSig Verdicts)
        [ok Candidate]
        [reject (urdr.shrink.n w-reject-sig)])
  _ [error _ _] _ -> [reject (urdr.shrink.n w-reject-error)]
  _ _ _ -> [reject (urdr.shrink.n w-reject-error)])

\\ ---------------------------------------------------------------
\\ List helpers
\\ ---------------------------------------------------------------

(define urdr.shrink.nth
  0 [X | _] -> X
  N [_ | Xs] -> (urdr.shrink.nth (- N 1) Xs))

(define urdr.shrink.take
  0 _ Acc -> (urdr.canonical.rev Acc)
  _ [] Acc -> (urdr.canonical.rev Acc)
  N [X | Xs] Acc -> (urdr.shrink.take (- N 1) Xs [X | Acc]))

(define urdr.shrink.drop
  0 Xs -> Xs
  _ [] -> []
  N [_ | Xs] -> (urdr.shrink.drop (- N 1) Xs))

(define urdr.shrink.without
  Transcript I ->
    (append (urdr.shrink.take I Transcript [])
            (urdr.shrink.drop (+ I 1) Transcript)))

(define urdr.shrink.without-pair
  Transcript I ->
    (append (urdr.shrink.take I Transcript [])
            (urdr.shrink.drop (+ I 2) Transcript)))

\\ Descending indices of Class entries.
(define urdr.shrink.indices-of
  Class Transcript ->
    (urdr.shrink.indices-of-h Class Transcript 0 []))

(define urdr.shrink.indices-of-h
  _ [] _ Acc -> Acc
  Class [Input | Rest] I Acc ->
    (if (= (urdr.shrink.class-of Input) Class)
        (urdr.shrink.indices-of-h
          Class Rest (+ I 1) [I | Acc])
        (urdr.shrink.indices-of-h Class Rest (+ I 1) Acc)))

(define urdr.shrink.pair-schedule?
  Transcript I ->
    (and (< (+ I 1) (urdr.shrink.length Transcript))
         (urdr.shrink.pair-h
           (urdr.shrink.nth I Transcript)
           (urdr.shrink.nth (+ I 1) Transcript))))

(define urdr.shrink.pair-h
  [schedule _ _ _] [advance-to-next-event] -> true
  _ _ -> false)

\\ ---------------------------------------------------------------
\\ Minimize
\\ ---------------------------------------------------------------
\\
\\ For each class in reduction order, repeatedly try to delete entries
\\ of that class (preferring schedule+advance pairs) from the right.
\\ On accept, restart the class against the shorter transcript. On
\\ reject, try the next index. Prefix reuse is structural: without at I
\\ keeps transcript[0..I) identical.

(define urdr.shrink.list?
  [] -> true
  [_ | _] -> true
  _ -> false)

(define urdr.shrink.minimize
  OriginalSig Eval Transcript ->
    (if (not (urdr.shrink.list? Transcript))
        [error (urdr.shrink.n c-transcript) [null]]
        [ok (urdr.shrink.minimize-classes
              OriginalSig Eval Transcript (urdr.shrink.order))]))

(define urdr.shrink.minimize-classes
  _ _ Transcript [] -> Transcript
  OriginalSig Eval Transcript [Class | Rest] ->
    (urdr.shrink.minimize-classes
      OriginalSig Eval
      (urdr.shrink.minimize-class OriginalSig Eval Transcript Class)
      Rest))

(define urdr.shrink.minimize-class
  OriginalSig Eval Transcript Class ->
    (urdr.shrink.minimize-indices
      OriginalSig Eval Transcript Class
      (urdr.shrink.indices-of Class Transcript)))

(define urdr.shrink.minimize-indices
  _ _ Transcript _ [] -> Transcript
  OriginalSig Eval Transcript Class [I | Rest] ->
    (urdr.shrink.minimize-at
      OriginalSig Eval Transcript Class I Rest))

(define urdr.shrink.minimize-at
  OriginalSig Eval Transcript Class I Rest ->
    (if (urdr.shrink.pair-schedule? Transcript I)
        (urdr.shrink.apply-try
          OriginalSig Eval Transcript Class Rest
          (urdr.shrink.without-pair Transcript I))
        (urdr.shrink.apply-try
          OriginalSig Eval Transcript Class Rest
          (urdr.shrink.without Transcript I))))

(define urdr.shrink.apply-try
  OriginalSig Eval Transcript Class Rest Candidate ->
    (urdr.shrink.apply-result
      OriginalSig Eval Transcript Class Rest Candidate
      (urdr.shrink.try-candidate OriginalSig Eval Candidate)))

(define urdr.shrink.apply-result
  OriginalSig Eval _ Class _ Candidate [ok _] ->
    \\ Accepted: restart this class on the shorter candidate so later
    \\ indices are recomputed (prefix-stable relative to Candidate).
    (urdr.shrink.minimize-class OriginalSig Eval Candidate Class)
  OriginalSig Eval Transcript Class Rest _ [reject _] ->
    (urdr.shrink.minimize-indices
      OriginalSig Eval Transcript Class Rest))
