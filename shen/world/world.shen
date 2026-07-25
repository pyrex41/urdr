\\ Pure world nucleus.
\\
\\ Required abstract interfaces (supplied by another module):
\\   (urdr.canonical.equal? A B) -> boolean
\\   (urdr.bigint.zero) -> nonnegative bigint
\\   (urdr.bigint.nonnegative? X) -> boolean
\\   (urdr.bigint.compare A B) -> less | equal | greater
\\   (urdr.bigint.successor X) -> bigint
\\   (urdr.prng.select State Coordinates Alternatives)
\\     -> [urdr-prng-selection/v1 NextState SelectedAlternative]
\\
\\ The world never examines canonical values or PRNG state.  Bigint values are
\\ used only through the interface above.  Interface implementations must be
\\ total on their declared inputs and must return deterministic values.

(define urdr.world.initial
  PrngState -> [urdr-world/v1
                 (urdr.bigint.zero)
                 (urdr.bigint.zero)
                 []
                 PrngState
                 []
                 []])

(define urdr.world.world?
  [urdr-world/v1 _ _ _ _ _ _] -> true
  _ -> false)

(define urdr.world.time
  [urdr-world/v1 Time _ _ _ _ _] -> Time
  _ -> [urdr-error/v1 malformed-world world])

(define urdr.world.next-event-id
  [urdr-world/v1 _ NextEventId _ _ _ _] -> NextEventId
  _ -> [urdr-error/v1 malformed-world world])

(define urdr.world.pending
  [urdr-world/v1 _ _ Pending _ _ _] -> Pending
  _ -> [urdr-error/v1 malformed-world world])

(define urdr.world.prng-state
  [urdr-world/v1 _ _ _ PrngState _ _] -> PrngState
  _ -> [urdr-error/v1 malformed-world world])

(define urdr.world.transcript
  [urdr-world/v1 _ _ _ _ Transcript _] -> Transcript
  _ -> [urdr-error/v1 malformed-world world])

(define urdr.world.verdicts
  [urdr-world/v1 _ _ _ _ _ Verdicts] -> Verdicts
  _ -> [urdr-error/v1 malformed-world world])

(define urdr.world.rebuild
  [urdr-world/v1 _ _ _ _ _ _]
  Time NextEventId Pending PrngState Transcript Verdicts
  -> [urdr-world/v1
       Time NextEventId Pending PrngState Transcript Verdicts])

(define urdr.world.ok
  World Commands Choices
  -> [urdr-reduction/v1 ok World Commands Choices no-error])

(define urdr.world.error
  World Code Detail
  -> [urdr-reduction/v1
       error World [] [] [urdr-error/v1 Code Detail]])

(define urdr.world.reduction-ok?
  [urdr-reduction/v1 ok _ _ _ _] -> true
  _ -> false)

(define urdr.world.reduction-world
  [urdr-reduction/v1 _ World _ _ _] -> World
  _ -> [urdr-error/v1 malformed-reduction reduction])

(define urdr.world.reduction-commands
  [urdr-reduction/v1 _ _ Commands _ _] -> Commands
  _ -> [urdr-error/v1 malformed-reduction reduction])

(define urdr.world.reduction-choices
  [urdr-reduction/v1 _ _ _ Choices _] -> Choices
  _ -> [urdr-error/v1 malformed-reduction reduction])

(define urdr.world.reduction-error
  [urdr-reduction/v1 _ _ _ _ Error] -> Error
  _ -> [urdr-error/v1 malformed-reduction reduction])

(define urdr.world.supported-event?
  command _ -> true
  property-equals [_ _ _] -> true
  choice [_ _ Alternatives] -> (urdr.world.nonempty? Alternatives)
  _ _ -> false)

(define urdr.world.nonempty?
  [_ | _] -> true
  _ -> false)

(define urdr.world.event-before?
  [urdr-event/v1 IdA TimeA _ _]
  [urdr-event/v1 IdB TimeB _ _]
  -> (let TimeOrder (urdr.bigint.compare TimeA TimeB)
       (if (= TimeOrder less)
           true
           (if (= TimeOrder greater)
               false
               (= (urdr.bigint.compare IdA IdB) less)))))

(define urdr.world.insert-event
  Event [] -> [Event]
  Event [Head | Tail]
  -> (if (urdr.world.event-before? Event Head)
         [Event Head | Tail]
         [Head | (urdr.world.insert-event Event Tail)]))

(define urdr.world.record-input
  [urdr-world/v1 Time NextEventId Pending PrngState Transcript Verdicts]
  Input
  -> [urdr-world/v1
       Time
       NextEventId
       Pending
       PrngState
       (append Transcript [Input])
       Verdicts])

(define urdr.world.reduce
  World Input
  -> (if (urdr.world.world? World)
         (urdr.world.reduce-valid World Input)
         (urdr.world.error World malformed-world world)))

(define urdr.world.reduce-valid
  World [urdr-input/v1 schedule At Kind Payload]
  -> (urdr.world.schedule World At Kind Payload)
  World [urdr-input/v1 advance-to-next-event]
  -> (urdr.world.advance World)
  World Input
  -> (urdr.world.error World malformed-input Input))

(define urdr.world.schedule
  [urdr-world/v1 Time NextEventId Pending PrngState Transcript Verdicts]
  At Kind Payload
  -> (if (urdr.bigint.nonnegative? At)
         (if (= (urdr.bigint.compare At Time) less)
             (urdr.world.error
               [urdr-world/v1
                 Time NextEventId Pending PrngState Transcript Verdicts]
               event-before-current-time
               [At Time])
             (if (urdr.world.supported-event? Kind Payload)
                 (let Event [urdr-event/v1 NextEventId At Kind Payload]
                   (let Input [urdr-input/v1 schedule At Kind Payload]
                     (urdr.world.ok
                       [urdr-world/v1
                         Time
                         (urdr.bigint.successor NextEventId)
                         (urdr.world.insert-event Event Pending)
                         PrngState
                         (append Transcript [Input])
                         Verdicts]
                       []
                       [])))
                 (urdr.world.error
                   [urdr-world/v1
                     Time NextEventId Pending PrngState Transcript Verdicts]
                   unsupported-event
                   [Kind Payload])))
         (urdr.world.error
           [urdr-world/v1
             Time NextEventId Pending PrngState Transcript Verdicts]
           invalid-logical-time
           At)))

(define urdr.world.advance
  [urdr-world/v1 Time NextEventId [] PrngState Transcript Verdicts]
  -> (urdr.world.error
       [urdr-world/v1
         Time NextEventId [] PrngState Transcript Verdicts]
       no-pending-event
       advance-to-next-event)
  [urdr-world/v1
    Time
    NextEventId
    [[urdr-event/v1 EventId EventTime Kind Payload] | Rest]
    PrngState
    Transcript
    Verdicts]
  -> (let Input [urdr-input/v1 advance-to-next-event]
       (let Advanced
         [urdr-world/v1
           EventTime
           NextEventId
           Rest
           PrngState
           (append Transcript [Input])
           Verdicts]
         (urdr.world.dispatch
           Advanced EventId EventTime Kind Payload))))

(define urdr.world.dispatch
  World EventId EventTime command Payload
  -> (urdr.world.ok
       World
       [[urdr-command/v1 EventId EventTime Payload]]
       [])
  [urdr-world/v1
    Time NextEventId Pending PrngState Transcript Verdicts]
  EventId EventTime property-equals [PropertyId Actual Expected]
  -> (let Result
       (if (urdr.canonical.equal? Actual Expected) "PASS" "FAIL")
       (urdr.world.ok
         [urdr-world/v1
           Time
           NextEventId
           Pending
           PrngState
           Transcript
           (append
             Verdicts
             [[urdr-verdict/v1
                PropertyId Result EventId EventTime]])]
         []
         []))
  [urdr-world/v1
    Time NextEventId Pending PrngState Transcript Verdicts]
  EventId EventTime choice [ChoiceKind Coordinates Alternatives]
  -> (let Selection
       (urdr.prng.select PrngState Coordinates Alternatives)
       (urdr.world.accept-selection
         [urdr-world/v1
           Time NextEventId Pending PrngState Transcript Verdicts]
         EventId
         EventTime
         ChoiceKind
         Coordinates
         Alternatives
         Selection))
  World EventId _ Kind Payload
  -> (urdr.world.error
       World
       malformed-pending-event
       [EventId Kind Payload]))

(define urdr.world.accept-selection
  [urdr-world/v1
    Time NextEventId Pending _ Transcript Verdicts]
  EventId EventTime ChoiceKind Coordinates Alternatives
  [urdr-prng-selection/v1 NextPrngState Selected]
  -> (if (urdr.world.canonical-member? Selected Alternatives)
         (urdr.world.ok
           [urdr-world/v1
             Time
             NextEventId
             Pending
             NextPrngState
             Transcript
             Verdicts]
           []
           [[urdr-choice/v1
              EventId
              EventTime
              ChoiceKind
              Alternatives
              Selected
              Coordinates]])
         (urdr.world.error
           [urdr-world/v1
             Time
             NextEventId
             Pending
             NextPrngState
             Transcript
             Verdicts]
           prng-selected-illegal-alternative
           EventId))
  World EventId _ _ _ _ Selection
  -> (urdr.world.error
       World
       malformed-prng-selection
       [EventId Selection]))

(define urdr.world.canonical-member?
  _ [] -> false
  Value [Head | Tail]
  -> (if (urdr.canonical.equal? Value Head)
         true
         (urdr.world.canonical-member? Value Tail)))

(define urdr.world.replay
  InitialWorld Transcript
  -> (if (urdr.world.world? InitialWorld)
         (urdr.world.replay-h InitialWorld Transcript [])
         [urdr-replay/v1
           error
           InitialWorld
           []
           [urdr-error/v1 malformed-world world]]))

(define urdr.world.replay-h
  World [] Reductions
  -> [urdr-replay/v1 ok World Reductions no-error]
  World [Input | Rest] Reductions
  -> (let Reduction (urdr.world.reduce World Input)
       (if (urdr.world.reduction-ok? Reduction)
           (urdr.world.replay-h
             (urdr.world.reduction-world Reduction)
             Rest
             (append Reductions [Reduction]))
           [urdr-replay/v1
             error
             (urdr.world.reduction-world Reduction)
             (append Reductions [Reduction])
             (urdr.world.reduction-error Reduction)]))
  World Transcript Reductions
  -> [urdr-replay/v1
       error
       World
       Reductions
       [urdr-error/v1 malformed-transcript Transcript]])

(define urdr.world.replay-ok?
  [urdr-replay/v1 ok _ _ _] -> true
  _ -> false)

(define urdr.world.replay-world
  [urdr-replay/v1 _ World _ _] -> World
  _ -> [urdr-error/v1 malformed-replay replay])

(define urdr.world.replay-reductions
  [urdr-replay/v1 _ _ Reductions _] -> Reductions
  _ -> [urdr-error/v1 malformed-replay replay])

(define urdr.world.replay-error
  [urdr-replay/v1 _ _ _ Error] -> Error
  _ -> [urdr-error/v1 malformed-replay replay])
