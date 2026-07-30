(define uwt.eval-forms
  [] -> loaded
  [[load _] | Forms] -> (uwt.eval-forms Forms)
  [Form | Forms] ->
    (let Ignored (eval Form)
      (uwt.eval-forms Forms)))

(define uwt.quiet-load
  File -> (uwt.eval-forms (read-file File)))

(uwt.quiet-load "shen/protocol/canonical.shen")
(uwt.quiet-load "shen/world/integer.shen")
(uwt.quiet-load "shen/world/prng.shen")
(uwt.quiet-load "shen/world/component.shen")
(uwt.quiet-load "shen/world/world.shen")

(define uwt.nth
  0 [X | _] -> X
  N [_ | Xs] -> (uwt.nth (- N 1) Xs))

(define uwt.all?
  [] -> true
  [true | Xs] -> (uwt.all? Xs)
  [_ | _] -> false)

(define uwt.big
  N -> (hd (tl (urdr.int.from-small N))))

(define uwt.decimal
  Bs -> (hd (tl (urdr.int.from-decimal-octets Bs))))

(define uwt.seed
  -> [119 111 114 108 100 45 115 101 101 100])

(define uwt.subsystem
  -> [115 99 104 101 100 117 108 101 114])

(define uwt.actor-a
  -> [118 109 45 97])

(define uwt.actor-b
  -> [118 109 45 98])

(define uwt.purpose
  -> [116 105 101 45 98 114 101 97 107])

\\ Strictly ascending in canonical encoding order, which the reducer now
\\ requires of scheduled choice alternatives. Canonical atoms are
\\ length-prefixed, so beta ("4:beta") encodes before alpha ("5:alpha");
\\ alphabetical order would be rejected.
(define uwt.alternatives
  -> [[symbol [98 101 116 97]]
      [symbol [97 108 112 104 97]]
      [symbol [103 97 109 109 97]]])

(define uwt.property-id
  -> [symbol [112 45 101 113]])

(define uwt.property-value
  T -> [list [[symbol [115 116 97 98 108 101]] T]])

(define uwt.choice
  Actor -> [choice
             (uwt.subsystem)
             Actor
             (uwt.purpose)
             (uwt.alternatives)])

(define uwt.inputs
  Base Late ->
    [[schedule Late command [symbol [108 97 116 101 45 97]]]
     [schedule Late command [symbol [108 97 116 101 45 98]]]
     [schedule Base property-equals
       [property
         (uwt.property-id)
         (uwt.property-value Base)
         (uwt.property-value Base)]]
     [schedule Late choice (uwt.choice (uwt.actor-a))]
     [schedule Late choice (uwt.choice (uwt.actor-b))]
     [schedule Late choice (uwt.choice (uwt.actor-a))]
     [advance-to-next-event]
     [advance-to-next-event]
     [advance-to-next-event]
     [advance-to-next-event]
     [advance-to-next-event]
     [advance-to-next-event]])

(define uwt.setup
  -> (let Base
       (uwt.decimal
         [57 48 48 55 49 57 57 50 53 52 55 52 48 57 57 51])
       (let Late (hd (tl (urdr.time.add Base (uwt.big 2))))
       (let W0 (urdr.world.initial (uwt.seed))
       (let Inputs (uwt.inputs Base Late)
       (let Replay (urdr.world.replay W0 Inputs)
         [fixture Base Late W0 Inputs Replay]))))))

(define uwt.base
  [fixture Base _ _ _ _] -> Base)

(define uwt.late
  [fixture _ Late _ _ _] -> Late)

(define uwt.initial
  [fixture _ _ W0 _ _] -> W0)

(define uwt.inputs-of
  [fixture _ _ _ Inputs _] -> Inputs)

(define uwt.replay
  [fixture _ _ _ _ Replay] -> Replay)

(define uwt.reductions
  Fixture -> (urdr.world.replay-reductions (uwt.replay Fixture)))

(define uwt.final
  Fixture -> (urdr.world.replay-world (uwt.replay Fixture)))

(define uwt.after-schedules
  Fixture -> (urdr.world.reduction-world
               (uwt.nth 5 (uwt.reductions Fixture))))

(define uwt.pending-keys
  [] -> []
  [[event Id At _ _] | Rest] ->
    [[Id At] | (uwt.pending-keys Rest)])

(define uwt.command-id
  [record [[[101 118 101 110 116 45 105 100] Id] | _]] -> Id)

(define uwt.choice-selected
  [record [_ _ _ [_ Selected] _ _]] -> Selected)

(define uwt.choice-coordinates
  [record [_ [_ Coordinates] _ _ _ _]] -> Coordinates)

(define uwt.choice-at
  Fixture N -> (hd (urdr.world.reduction-choices
                     (uwt.nth N (uwt.reductions Fixture)))))

(define uwt.error?
  Reduction Code ->
    (= (urdr.world.reduction-choices Reduction)
       [error (urdr.world.error-value Code [null])]))

(define uwt.scheduling?
  Fixture ->
    (let W (uwt.after-schedules Fixture)
      (and (= (urdr.world.time W) (urdr.int.zero))
           (= (uwt.pending-keys (urdr.world.pending W))
              [[(uwt.big 2) (uwt.base Fixture)]
               [(uwt.big 0) (uwt.late Fixture)]
               [(uwt.big 1) (uwt.late Fixture)]
               [(uwt.big 3) (uwt.late Fixture)]
               [(uwt.big 4) (uwt.late Fixture)]
               [(uwt.big 5) (uwt.late Fixture)]]))))

(define uwt.immutable?
  Fixture ->
    (let W0 (uwt.initial Fixture)
      (and (= W0 (urdr.world.initial (uwt.seed)))
           (and (= (urdr.world.time W0) (urdr.int.zero))
                (= (urdr.world.pending W0) [])))))

(define uwt.final-state?
  Fixture ->
    (let Final (uwt.final Fixture)
      (and (= (urdr.world.time Final) (uwt.late Fixture))
           (and (= (urdr.world.next-event-id Final) (uwt.big 6))
                (= (urdr.world.pending Final) [])))))

(define uwt.tie-order?
  Fixture ->
    (let Reductions (uwt.reductions Fixture)
      (and (= (uwt.command-id
                (hd (urdr.world.reduction-commands
                      (uwt.nth 7 Reductions))))
              (uwt.big 0))
           (= (uwt.command-id
                (hd (urdr.world.reduction-commands
                      (uwt.nth 8 Reductions))))
              (uwt.big 1)))))

(define uwt.property?
  Fixture ->
    (= (urdr.world.verdicts (uwt.final Fixture))
       [[verdict
          (uwt.property-id)
          [symbol [80 65 83 83]]
          (uwt.big 2)
          (uwt.base Fixture)]]))

(define uwt.isolated-b
  Fixture ->
    (let Inputs
      [[schedule (uwt.late Fixture) choice (uwt.choice (uwt.actor-b))]
       [advance-to-next-event]]
      (let Replay (urdr.world.replay (uwt.initial Fixture) Inputs)
        (hd (urdr.world.reduction-choices
              (uwt.nth 1
                (urdr.world.replay-reductions Replay)))))))

(define uwt.path-isolation?
  Fixture ->
    (let MainB (uwt.choice-at Fixture 10)
         IsolatedB (uwt.isolated-b Fixture)
      (and (= (uwt.choice-selected MainB)
              (uwt.choice-selected IsolatedB))
           (= (uwt.choice-coordinates MainB)
              (uwt.choice-coordinates IsolatedB)))))

(define uwt.stream-counters?
  Fixture ->
    (= (urdr.world.streams (uwt.final Fixture))
       [[path (uwt.subsystem) (uwt.actor-a) (uwt.purpose) (uwt.big 2)]
        [path (uwt.subsystem) (uwt.actor-b) (uwt.purpose) (uwt.big 1)]]))

(define uwt.replay-equality?
  Fixture ->
    (and (= (uwt.replay Fixture)
            (urdr.world.replay
              (uwt.initial Fixture)
              (uwt.inputs-of Fixture)))
         (= (urdr.world.transcript (uwt.final Fixture))
            (uwt.inputs-of Fixture))))

(define uwt.invalid-time?
  Fixture ->
    (let W0 (uwt.initial Fixture)
         Reduction (urdr.world.reduce
                     W0
                     [schedule [big -1 [1]] command [null]])
      (and (uwt.error?
             Reduction
             [105 110 118 97 108 105 100 45 116 105 109 101])
           (= (urdr.world.reduction-world Reduction) W0))))

(define uwt.stale-and-rollback?
  Fixture ->
    (let Final (uwt.final Fixture)
         Stale (urdr.world.reduce
                 Final
                 [schedule (uwt.base Fixture) command [null]])
         Rollback (urdr.world.reduce
                    Final
                    [rollback (uwt.base Fixture)])
      (and (uwt.error?
             Stale
             [115 116 97 108 101 45 101 118 101 110 116])
           (and (= (urdr.world.reduction-world Stale) Final)
                (and (uwt.error?
                       Rollback
                       [116 105 109 101 45 114 111 108 108 98 97
                        99 107 45 102 111 114 98 105 100 100 101 110])
                     (= (urdr.world.reduction-world Rollback)
                        Final))))))

(define uwt.invalid-event?
  Fixture ->
    (let Final (uwt.final Fixture)
         Reduction (urdr.world.reduce Final [invalid-event])
      (and (uwt.error?
             Reduction
             [105 110 118 97 108 105 100 45 101 118 101 110 116])
           (= (urdr.world.reduction-world Reduction) Final))))

\\ Positional selection makes alternative order semantic: a scheduled
\\ choice whose alternatives are not strictly ascending in canonical
\\ encoding order — a permutation (alphabetical [alpha beta] encodes
\\ descending) or a duplicate — is rejected fail-closed under its own
\\ stable code, choice-alternatives-order, before any state change.
(define uwt.order-code
  -> [99 104 111 105 99 101 45 97 108 116 101 114 110 97 116 105 118
      101 115 45 111 114 100 101 114])

(define uwt.choice-order-rejected?
  Fixture Alternatives ->
    (let W0 (uwt.initial Fixture)
         Reduction (urdr.world.reduce
                     W0
                     [schedule (uwt.base Fixture) choice
                       [choice
                         (uwt.subsystem)
                         (uwt.actor-a)
                         (uwt.purpose)
                         Alternatives]])
      (and (uwt.error? Reduction (uwt.order-code))
           (= (urdr.world.reduction-world Reduction) W0))))

(define uwt.unordered-choice-rejected?
  Fixture ->
    (uwt.choice-order-rejected?
      Fixture
      [[symbol [97 108 112 104 97]] [symbol [98 101 116 97]]]))

(define uwt.duplicate-choice-rejected?
  Fixture ->
    (uwt.choice-order-rejected?
      Fixture
      [[symbol [98 101 116 97]] [symbol [98 101 116 97]]]))

\\ Modeled-component fixtures (ADR 0004 Decision 1). One well-behaved
\\ component and one variant per banned authority, each of which must be
\\ rejected fail-closed rather than repaired.

(define uwt.counter-name
  -> [99 111 117 110 116 101 114])

(define uwt.counter-state
  Count -> [record [[[99 111 117 110 116] Count]]])

(define uwt.counter-input
  -> [symbol [98 117 109 112]])

(define uwt.counter-choice
  -> [alternatives [100 101 108 97 121]
       [[symbol [102 97 115 116]] [symbol [115 108 111 119]]]])

\\ Well behaved: advances only its own state, names one fact, and offers
\\ canonically ordered alternatives it does not select among.
(define uwt.counter
  [record [[[99 111 117 110 116] Count]]]
  [record [[[105 110 112 117 116] [symbol [98 117 109 112]]] | _]] ->
    (let Next (hd (tl (urdr.int.add Count (uwt.big 1))))
      [step
        (uwt.counter-state Next)
        [[fact [116 105 99 107] (uwt.counter-state Next)]]
        [(uwt.counter-choice)]])
  _ _ ->
    [error (urdr.canonical.string-bytes "counter-unknown-input")])

\\ Misbehaving: emits a world event directly.
(define uwt.emitter
  State _ ->
    [step
      State
      [[fact [101 109 105 116]
         [record
           [[[112 97 121 108 111 97 100] [null]]
            [[116 121 112 101] [symbol [101 118 101 110 116]]]]]]]
      []])

\\ Misbehaving: allocates an event identifier.
(define uwt.inventor
  State _ ->
    [step
      State
      [[fact [105 115 115 117 101]
         [record [[[101 118 101 110 116 45 105 100] (uwt.big 41)]]]]]
      []])

\\ Misbehaving: returns a state that is not a canonical value.
(define uwt.noncanonical
  State _ -> [step [record [[[99 111 117 110 116] [oops]]]] [] []])

\\ Misbehaving: raises instead of returning a result.
(define uwt.raiser
  State _ -> (simple-error "component fixture raised"))

\\ Misbehaving: returns something that is not a step result.
(define uwt.shapeless
  State _ -> [stepped State])

\\ Misbehaving: writes logical time back as a fact key, which claims a
\\ time advance. (It no longer echoes the whole event: the event record
\\ now carries the reserved `self` key first, which would mask the time
\\ claim under scan order.)
(define uwt.ticker
  State Event ->
    [step
      State
      [[fact [116 105 99 107 101 100]
         [record [[[116 105 109 101] [null]]]]]]
      []])

\\ Misbehaving: echoes the event it was handed back as a fact, which
\\ claims the reserved `self` identity key (ADR 0007 D3) — the first
\\ reserved name the scan meets in input < self < time < type order.
(define uwt.selfish
  State Event ->
    [step State [[fact [101 99 104 111 101 100] Event]] []])

\\ Misbehaving: offers alternatives out of canonical order.
(define uwt.unordered
  State _ ->
    [step
      State
      []
      [[alternatives [100 101 108 97 121]
         [[symbol [115 108 111 119]] [symbol [102 97 115 116]]]]]])

(define uwt.zero-state
  -> (uwt.counter-state (urdr.int.zero)))

(define uwt.emitter-name
  -> [101 109 105 116 116 101 114])

\\ Every fixture world registers the well-behaved counter plus exactly one
\\ other component, so that a step can be shown to touch the stepped
\\ component alone. Registry entries ascend strictly by name.
(define uwt.pair-registry
  Name Handler ->
    [(urdr.component.entry
       (uwt.counter-name) (/. S E (uwt.counter S E)) (uwt.zero-state))
     (urdr.component.entry Name Handler (uwt.zero-state))])

(define uwt.pair-world
  Name Handler ->
    (hd (tl (urdr.world.initial-with-components
              (uwt.seed) (uwt.pair-registry Name Handler)))))

(define uwt.emitter-world
  -> (uwt.pair-world
       (uwt.emitter-name) (/. S E (uwt.emitter S E))))

(define uwt.component-inputs
  Name Count ->
    (append
      (uwt.component-schedules Name Count)
      (uwt.component-advances Count)))

(define uwt.component-schedules
  _ 0 -> []
  Name N ->
    [[schedule (urdr.int.zero) component
       [component-input Name (uwt.counter-input)]] |
     (uwt.component-schedules Name (- N 1))])

(define uwt.component-advances
  0 -> []
  N -> [[advance-to-next-event] | (uwt.component-advances (- N 1))])

(define uwt.component-replay
  -> (urdr.world.replay
       (uwt.emitter-world)
       (uwt.component-inputs (uwt.counter-name) 2)))

(define uwt.component-setup
  -> [cfixture (uwt.component-replay)])

(define uwt.creductions
  [cfixture Replay] -> (urdr.world.replay-reductions Replay))

(define uwt.cfinal
  [cfixture Replay] -> (urdr.world.replay-world Replay))

(define uwt.expected-fact
  Id Count ->
    [record
      [[[99 111 109 112 111 110 101 110 116] [bytes (uwt.counter-name)]]
       [[101 118 101 110 116 45 105 100] Id]
       [[110 97 109 101] [symbol [116 105 99 107]]]
       [[116 105 109 101] (urdr.int.zero)]
       [[116 121 112 101] [symbol [102 97 99 116]]]
       [[118 97 108 117 101] (uwt.counter-state Count)]]])

(define uwt.expected-choice
  Id ->
    [record
      [[[97 108 116 101 114 110 97 116 105 118 101 115]
        [list [[symbol [102 97 115 116]] [symbol [115 108 111 119]]]]]
       [[99 111 109 112 111 110 101 110 116] [bytes (uwt.counter-name)]]
       [[101 118 101 110 116 45 105 100] Id]
       [[112 117 114 112 111 115 101] [symbol [100 101 108 97 121]]]
       [[116 105 109 101] (urdr.int.zero)]
       [[116 121 112 101]
        [symbol [99 111 109 112 111 110 101 110 116 45
                 99 104 111 105 99 101]]]]])

(define uwt.entry-state
  [component _ _ State _] -> State
  _ -> none)

(define uwt.component-state-of
  Name World ->
    (uwt.entry-state
      (urdr.world.component-find Name (urdr.world.components World))))

\\ The component that was not stepped keeps its initial state.
(define uwt.other-untouched?
  World ->
    (= (uwt.component-state-of (uwt.emitter-name) World)
       (uwt.zero-state)))

(define uwt.component-run?
  Fixture ->
    (let Final (uwt.cfinal Fixture)
         Reductions (uwt.creductions Fixture)
      (and (= (urdr.world.facts Final)
              [(uwt.expected-fact (uwt.big 0) (uwt.big 1))
               (uwt.expected-fact (uwt.big 1) (uwt.big 2))])
           (and (= (urdr.world.reduction-choices
                     (uwt.nth 2 Reductions))
                   [(uwt.expected-choice (uwt.big 0))])
                (and (= (urdr.world.reduction-choices
                          (uwt.nth 3 Reductions))
                        [(uwt.expected-choice (uwt.big 1))])
                     (and (= (uwt.component-state-of
                               (uwt.counter-name) Final)
                             (uwt.counter-state (uwt.big 2)))
                          (uwt.other-untouched? Final)))))))

\\ A component step is the component's own business: it may not move logical
\\ time, allocate identifiers, touch PRNG streams, or record verdicts.
(define uwt.component-isolation?
  Fixture ->
    (let Final (uwt.cfinal Fixture)
      (and (= (urdr.world.time Final) (urdr.int.zero))
           (and (= (urdr.world.next-event-id Final) (uwt.big 2))
                (and (= (urdr.world.streams Final) [])
                     (and (= (urdr.world.verdicts Final) [])
                          (= (urdr.world.pending Final) [])))))))

\\ Worlds carrying components are compared through their canonical snapshot,
\\ never by host object equality: a component handler is code, and code has
\\ no canonical identity (SPEC.md 7.1).
(define uwt.component-replay-equality?
  Fixture ->
    (let Again (urdr.world.replay-world (uwt.component-replay))
         Final (uwt.cfinal Fixture)
      (and (= (urdr.world.snapshot-frame Final)
              (urdr.world.snapshot-frame Again))
           (and (= (urdr.world.facts Final) (urdr.world.facts Again))
                (= (urdr.world.transcript Final)
                   (uwt.component-inputs (uwt.counter-name) 2))))))

(define uwt.fail-closed?
  Name Handler Code Detail ->
    (uwt.replay-error?
      (urdr.world.replay
        (uwt.pair-world Name Handler)
        (uwt.component-inputs Name 1))
      (urdr.canonical.string-bytes Code)
      (urdr.world.component-detail Name Detail)))

(define uwt.replay-error?
  [replay-error _ _ Choices] Code Detail ->
    (= Choices [error (urdr.world.error-value Code Detail)])
  _ _ _ -> false)

(define uwt.claim
  Name -> [symbol (urdr.canonical.string-bytes Name)])

\\ The banned authorities of ADR 0004 Decision 1 (extended by ADR 0007
\\ D3's `self`), one fixture each: direct event emission, identifier
\\ allocation, an implied time advance, an identity claim, and a
\\ non-canonical result. The reducer names the claimed authority.
(define uwt.misbehaviour?
  -> (and (uwt.fail-closed?
            (uwt.emitter-name)
            (/. S E (uwt.emitter S E))
            "component-fact-authority"
            (uwt.claim "event"))
          (and (uwt.fail-closed?
                 [105 110 118 101 110 116 111 114]
                 (/. S E (uwt.inventor S E))
                 "component-fact-authority"
                 (uwt.claim "event-id"))
               (and (uwt.fail-closed?
                      [116 105 99 107 101 114]
                      (/. S E (uwt.ticker S E))
                      "component-fact-authority"
                      (uwt.claim "time"))
                    (and (uwt.fail-closed?
                           [115 101 108 102 105 115 104]
                           (/. S E (uwt.selfish S E))
                           "component-fact-authority"
                           (uwt.claim "self"))
                         (uwt.fail-closed?
                           [110 111 110 99 97 110 111 110 105 99 97 108]
                           (/. S E (uwt.noncanonical S E))
                           "component-state-invalid"
                           [null]))))))

(define uwt.malformed?
  -> (and (uwt.fail-closed?
            [117 110 111 114 100 101 114 101 100]
            (/. S E (uwt.unordered S E))
            "component-alternative-order"
            [null])
          (and (uwt.fail-closed?
                 [115 104 97 112 101 108 101 115 115]
                 (/. S E (uwt.shapeless S E))
                 "component-result-shape"
                 [null])
               (uwt.fail-closed?
                 [114 97 105 115 101 114]
                 (/. S E (uwt.raiser S E))
                 "component-step-failed"
                 [null]))))

\\ A component that cannot interpret its input returns a canonical error,
\\ and the reducer converts it to a fail-closed run error unchanged.
(define uwt.component-own-error?
  -> (uwt.replay-error?
       (urdr.world.replay
         (uwt.emitter-world)
         [[schedule (urdr.int.zero) component
            [component-input (uwt.counter-name)
              [symbol [98 111 103 117 115]]]]
          [advance-to-next-event]])
       (urdr.canonical.string-bytes "counter-unknown-input")
       (urdr.world.component-detail (uwt.counter-name) [null])))

(define uwt.component-unknown?
  -> (uwt.replay-error?
       (urdr.world.replay
         (uwt.emitter-world)
         (uwt.component-inputs [109 105 115 115 105 110 103] 1))
       (urdr.canonical.string-bytes "component-unknown")
       (urdr.world.component-detail
         [109 105 115 115 105 110 103] [null])))

\\ A component name that usurps a reserved authority is refused before the
\\ event is ever scheduled.
(define uwt.component-input-rejected?
  -> (let W0 (uwt.emitter-world)
          Reduction (urdr.world.reduce
                      W0
                      [schedule (urdr.int.zero) component
                        [component-input [116 105 109 101]
                          (uwt.counter-input)]])
       (and (uwt.error?
              Reduction
              [105 110 118 97 108 105 100 45 101 118 101 110 116])
            (= (urdr.world.snapshot-frame
                 (urdr.world.reduction-world Reduction))
               (urdr.world.snapshot-frame W0)))))

(define uwt.duplicate-registry
  -> [(urdr.component.entry
        (uwt.counter-name) (/. S E (uwt.counter S E)) (uwt.zero-state))
      (urdr.component.entry
        (uwt.counter-name) (/. S E (uwt.counter S E)) (uwt.zero-state))])

(define uwt.bad-state-registry
  -> [(urdr.component.entry
        (uwt.counter-name) (/. S E (uwt.counter S E)) [oops])])

\\ META is validated at registration exactly like state: a malformed
\\ META record and a bad META field carry their own stable codes.
(define uwt.bad-meta-registry
  Meta ->
    [[component (uwt.counter-name)
       (/. S E (uwt.counter S E)) (uwt.zero-state) Meta]])

(define uwt.meta-rejected?
  -> (and (= (urdr.world.initial-with-components
               (uwt.seed)
               (uwt.bad-meta-registry [record [[[110 111 100 101] [null]]]]))
             [error (urdr.canonical.string-bytes
                      "component-meta-shape")
                    [null]])
          (= (urdr.world.initial-with-components
               (uwt.seed)
               (uwt.bad-meta-registry
                 [record
                   [[[109 111 100 101 108] [null]]
                    [[110 111 100 101] [symbol [116 105 109 101]]]]]))
             [error (urdr.canonical.string-bytes
                      "component-meta-value")
                    [null]])))

(define uwt.registry-rejected?
  -> (and (= (urdr.world.initial-with-components
               (uwt.seed) (uwt.duplicate-registry))
             [error (urdr.canonical.string-bytes
                      "component-registry-order")
                    [symbol (uwt.counter-name)]])
          (and (= (urdr.world.initial-with-components
                    (uwt.seed) (uwt.bad-state-registry))
                  [error (urdr.canonical.string-bytes
                           "component-state-invalid")
                         [null]])
               (uwt.meta-rejected?))))

(define uwt.component-trace-value
  Fixture ->
    (let Reductions (uwt.creductions Fixture)
      [record
        [[[99 104 111 105 99 101 115]
          [list
            (append
              (urdr.world.reduction-choices (uwt.nth 2 Reductions))
              (urdr.world.reduction-choices (uwt.nth 3 Reductions)))]]
         [[102 97 99 116 115]
          [list (urdr.world.facts (uwt.cfinal Fixture))]]
         [[119 111 114 108 100]
          (urdr.world.snapshot-value (uwt.cfinal Fixture))]]]))

(define uwt.trace-value
  Fixture ->
    (let Reductions (uwt.reductions Fixture)
      [record
        [[[99 104 111 105 99 101] (uwt.choice-at Fixture 10)]
         [[99 111 109 109 97 110 100 115]
          [list
            [(hd (urdr.world.reduction-commands
                   (uwt.nth 7 Reductions)))
             (hd (urdr.world.reduction-commands
                   (uwt.nth 8 Reductions)))]]]
         [[119 111 114 108 100]
          (urdr.world.snapshot-value (uwt.final Fixture))]]]))

(define uwt.finish
  Checks [ok Bytes] [ok ComponentBytes] ->
    (if (uwt.all? Checks)
        (let Hex (hd (tl (urdr.bytes.hex Bytes)))
             ComponentHex (hd (tl (urdr.bytes.hex ComponentBytes)))
          (do
            (output "WORLD-TRACE ~A~%" Hex)
            (output "WORLD-COMPONENT-TRACE ~A~%" ComponentHex)
            (output "WORLD TESTS: 22/22 PASS~%")
            (output "ALL PASS~%")
            true))
        (do
          (output "WORLD TESTS: FAIL~%")
          false))
  _ _ _ ->
    (do
      (output "WORLD TRACE: ENCODE FAIL~%")
      false))

(define uwt.run
  -> (let Fixture (uwt.setup)
          Components (uwt.component-setup)
       (let Checks
         [(= (length (uwt.reductions Fixture)) 12)
          (uwt.scheduling? Fixture)
          (uwt.immutable? Fixture)
          (uwt.final-state? Fixture)
          (uwt.tie-order? Fixture)
          (uwt.property? Fixture)
          (uwt.path-isolation? Fixture)
          (uwt.stream-counters? Fixture)
          (uwt.replay-equality? Fixture)
          (uwt.invalid-time? Fixture)
          (and (uwt.stale-and-rollback? Fixture)
               (uwt.invalid-event? Fixture))
          (and (uwt.unordered-choice-rejected? Fixture)
               (uwt.duplicate-choice-rejected? Fixture))
          (= (length (uwt.creductions Components)) 4)
          (uwt.component-run? Components)
          (uwt.component-isolation? Components)
          (uwt.component-replay-equality? Components)
          (uwt.misbehaviour?)
          (uwt.malformed?)
          (uwt.component-own-error?)
          (uwt.component-unknown?)
          (uwt.component-input-rejected?)
          (uwt.registry-rejected?)]
         (uwt.finish
           Checks
           (urdr.canonical.encode-frame
             (uwt.trace-value Fixture))
           (urdr.canonical.encode-frame
             (uwt.component-trace-value Components))))))

(uwt.run)
