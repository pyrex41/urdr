\\ Pure immutable world nucleus.
\\ Requires canonical.shen, prng.shen, and component.shen to be loaded by
\\ the caller.

(define urdr.world.initial
  Seed -> [world/v1
           (urdr.int.zero)
           (urdr.int.zero)
           []
           Seed
           []
           []
           []
           []
           []])

\\ Boot a world with a modeled-component registry (ADR 0004 Decision 1).
\\ Registry entries are [component NAME HANDLER STATE]; an invalid registry
\\ is refused here rather than repaired at the first dispatch.
(define urdr.world.initial-with-components
  Seed Registry ->
    (let Valid (urdr.component.registry-valid? Registry)
      (if (= (hd Valid) error)
          Valid
          [ok [world/v1
                (urdr.int.zero)
                (urdr.int.zero)
                []
                Seed
                []
                []
                []
                Registry
                []]])))

(define urdr.world.valid?
  [world/v1 Time NextId _ Seed _ _ _ Components _] ->
    (and (= (hd (urdr.time.check Time)) ok)
         (and (= (hd (urdr.time.check NextId)) ok)
              (and (= (hd (urdr.prng.octets.check Seed)) ok)
                   (urdr.component.registry-shape? Components))))
  _ -> false)

(define urdr.world.time
  [world/v1 Time _ _ _ _ _ _ _ _] -> Time)

(define urdr.world.next-event-id
  [world/v1 _ NextId _ _ _ _ _ _ _] -> NextId)

(define urdr.world.pending
  [world/v1 _ _ Pending _ _ _ _ _ _] -> Pending)

(define urdr.world.seed
  [world/v1 _ _ _ Seed _ _ _ _ _] -> Seed)

(define urdr.world.streams
  [world/v1 _ _ _ _ Streams _ _ _ _] -> Streams)

(define urdr.world.transcript
  [world/v1 _ _ _ _ _ Transcript _ _ _] -> Transcript)

(define urdr.world.verdicts
  [world/v1 _ _ _ _ _ _ Verdicts _ _] -> Verdicts)

(define urdr.world.components
  [world/v1 _ _ _ _ _ _ _ Components _] -> Components)

(define urdr.world.facts
  [world/v1 _ _ _ _ _ _ _ _ Facts] -> Facts)

(define urdr.world.reduction-world
  [reduction World _ _] -> World)

(define urdr.world.reduction-commands
  [reduction _ Commands _] -> Commands)

(define urdr.world.reduction-choices
  [reduction _ _ Choices] -> Choices)

(define urdr.world.reduction-error?
  [reduction _ _ [error _]] -> true
  _ -> false)

(define urdr.world.error-value
  Code Detail ->
    [record
      [[[99 111 100 101] [symbol Code]]
       [[100 101 116 97 105 108] Detail]
       [[116 121 112 101] [symbol [101 114 114 111 114]]]]])

(define urdr.world.error
  World Code Detail ->
    [reduction
      World
      []
      [error (urdr.world.error-value Code Detail)]])

(define urdr.world.canonical-valid?
  Value -> (= (hd (urdr.canonical.encode-payload Value)) ok))

(define urdr.world.canonical-list-valid?
  [] -> true
  [Value | Values] ->
    (and (urdr.world.canonical-valid? Value)
         (urdr.world.canonical-list-valid? Values))
  _ -> false)

(define urdr.world.nonempty?
  [_ | _] -> true
  _ -> false)

(define urdr.world.choice-path-valid?
  Seed Subsystem Actor Purpose ->
    (= (hd (urdr.prng.stream
             Seed Subsystem Actor Purpose (urdr.int.zero)))
       ok))

(define urdr.world.event-valid?
  Seed command Payload ->
    (urdr.world.canonical-valid? Payload)
  Seed property-equals [property PropertyId Actual Expected] ->
    (and (urdr.world.canonical-valid? PropertyId)
         (and (urdr.world.canonical-valid? Actual)
              (urdr.world.canonical-valid? Expected)))
  Seed choice [choice Subsystem Actor Purpose Alternatives] ->
    (and (urdr.world.nonempty? Alternatives)
         (and (urdr.world.canonical-list-valid? Alternatives)
              (urdr.world.choice-path-valid?
                Seed Subsystem Actor Purpose)))
  Seed component [component-input Name Value] ->
    (and (urdr.component.name-valid? Name)
         (urdr.world.canonical-valid? Value))
  _ _ _ -> false)

(define urdr.world.event-before?
  [event IdA TimeA _ _] [event IdB TimeB _ _] ->
    (let TimeOrder (hd (tl (urdr.time.compare TimeA TimeB)))
      (if (< TimeOrder 0)
          true
          (if (> TimeOrder 0)
              false
              (< (hd (tl (urdr.int.compare IdA IdB))) 0)))))

(define urdr.world.insert-event
  Event [] -> [Event]
  Event [Head | Tail] ->
    (if (urdr.world.event-before? Event Head)
        [Event Head | Tail]
        [Head | (urdr.world.insert-event Event Tail)]))

(define urdr.world.reduce
  World Input ->
    (if (urdr.world.valid? World)
        (urdr.world.reduce-valid World Input)
        (urdr.world.error
          World
          [105 110 118 97 108 105 100 45 119 111 114 108 100]
          [null])))

(define urdr.world.reduce-valid
  World [schedule At Kind Payload] ->
    (urdr.world.schedule World At Kind Payload)
  World [advance-to-next-event] ->
    (urdr.world.advance World)
  World [rollback _] ->
    (urdr.world.error
      World
      [116 105 109 101 45 114 111 108 108 98 97 99 107 45
       102 111 114 98 105 100 100 101 110]
      [null])
  World _ ->
    (urdr.world.error
      World
      [105 110 118 97 108 105 100 45 101 118 101 110 116]
      [null]))

(define urdr.world.schedule
  [world/v1
    Time NextId Pending Seed Streams Transcript Verdicts
    Components Facts]
  At Kind Payload ->
    (let ValidTime (urdr.time.check At)
      (if (= (hd ValidTime) error)
          (urdr.world.error
            [world/v1
              Time NextId Pending Seed Streams Transcript Verdicts
              Components Facts]
            [105 110 118 97 108 105 100 45 116 105 109 101]
            [null])
          (let Order (hd (tl (urdr.time.compare At Time)))
            (if (< Order 0)
                (urdr.world.error
                  [world/v1
                    Time NextId Pending Seed Streams Transcript Verdicts
                    Components Facts]
                  [115 116 97 108 101 45 101 118 101 110 116]
                  [null])
                (if (not (urdr.world.event-valid?
                           Seed Kind Payload))
                    (urdr.world.error
                      [world/v1
                        Time NextId Pending Seed Streams
                        Transcript Verdicts Components Facts]
                      [105 110 118 97 108 105 100 45 101 118 101 110 116]
                      [null])
                    (let Event [event NextId At Kind Payload]
                         Next (hd (tl
                                (urdr.time.successor NextId)))
                         Input [schedule At Kind Payload]
                      [reduction
                        [world/v1
                          Time
                          Next
                          (urdr.world.insert-event Event Pending)
                          Seed
                          Streams
                          (append Transcript [Input])
                          Verdicts
                          Components
                          Facts]
                        []
                        []])))))))

(define urdr.world.advance
  [world/v1
    Time NextId [] Seed Streams Transcript Verdicts
    Components Facts] ->
    (urdr.world.error
      [world/v1
        Time NextId [] Seed Streams Transcript Verdicts
        Components Facts]
      [110 111 45 112 101 110 100 105 110 103 45 101 118 101 110 116]
      [null])
  [world/v1
    Time NextId [[event Id At Kind Payload] | Rest]
    Seed Streams Transcript Verdicts Components Facts] ->
    (let Advanced
      [world/v1
        At NextId Rest Seed Streams
        (append Transcript [[advance-to-next-event]])
        Verdicts Components Facts]
      (urdr.world.dispatch Advanced Id At Kind Payload)))

(define urdr.world.command-value
  Id At Payload ->
    [record
      [[[101 118 101 110 116 45 105 100] Id]
       [[112 97 121 108 111 97 100] Payload]
       [[116 105 109 101] At]
       [[116 121 112 101] [symbol [99 111 109 109 97 110 100]]]]])

(define urdr.world.canonical-equal
  A B ->
    (let EA (urdr.canonical.encode-payload A)
         EB (urdr.canonical.encode-payload B)
      (if (= (hd EA) error)
          [error invalid-canonical-value]
          (if (= (hd EB) error)
              [error invalid-canonical-value]
              [ok (= (hd (tl EA)) (hd (tl EB)))]))))

(define urdr.world.verdict-value
  [verdict PropertyId Result Id At] ->
    [record
      [[[101 118 101 110 116 45 105 100] Id]
       [[112 114 111 112 101 114 116 121] PropertyId]
       [[114 101 115 117 108 116] Result]
       [[116 105 109 101] At]]])

(define urdr.world.dispatch
  World Id At command Payload ->
    [reduction World [(urdr.world.command-value Id At Payload)] []]
  [world/v1
    Time NextId Pending Seed Streams Transcript Verdicts
    Components Facts]
  Id At property-equals [property PropertyId Actual Expected] ->
    (let Equal (urdr.world.canonical-equal Actual Expected)
      (if (= (hd Equal) error)
          (urdr.world.error
            [world/v1
              Time NextId Pending Seed Streams Transcript Verdicts
              Components Facts]
            [105 110 118 97 108 105 100 45 99 97 110 111 110 105 99
             97 108 45 118 97 108 117 101]
            [null])
          (let Result
            (if (hd (tl Equal))
                [symbol [80 65 83 83]]
                [symbol [70 65 73 76]]
            )
            [reduction
              [world/v1
                Time NextId Pending Seed Streams Transcript
                (append Verdicts
                  [[verdict PropertyId Result Id At]])
                Components Facts]
              []
              []])))
  World Id At choice
  [choice Subsystem Actor Purpose Alternatives] ->
    (urdr.world.choose
      World Id At Subsystem Actor Purpose Alternatives)
  World Id At component [component-input Name Value] ->
    (urdr.world.component-step World Id At Name Value)
  World _ _ _ _ ->
    (urdr.world.error
      World
      [105 110 118 97 108 105 100 45 112 101 110 100 105 110 103
       45 101 118 101 110 116]
      [null]))

\\ Modeled-component dispatch (ADR 0004 Decision 1). The reducer supplies
\\ the component with logical time and the scheduled input, invokes it, and
\\ folds the validated result into the reduction: state back into the
\\ registry, facts into world state, offered alternatives into the
\\ reduction's choices. Every rejection is a fail-closed run error.
(define urdr.world.component-find
  _ [] -> none
  Name [[component Name Handler State] | _] ->
    [component Name Handler State]
  Name [_ | Rest] -> (urdr.world.component-find Name Rest))

(define urdr.world.component-put
  [component Name Handler State] [] ->
    [[component Name Handler State]]
  [component Name Handler State] [[component Name _ _] | Rest] ->
    [[component Name Handler State] | Rest]
  Entry [Head | Rest] ->
    [Head | (urdr.world.component-put Entry Rest)])

\\ The component reads logical time; it may never assert one back.
(define urdr.world.component-event
  At Value ->
    [record
      [[[105 110 112 117 116] Value]
       [[116 105 109 101] At]
       [[116 121 112 101]
        [symbol [99 111 109 112 111 110 101 110 116 45
                 101 118 101 110 116]]]]])

(define urdr.world.component-detail
  Name Detail ->
    [record
      [[[99 111 109 112 111 110 101 110 116] [bytes Name]]
       [[100 101 116 97 105 108] Detail]]])

(define urdr.world.fact-value
  Id At Name [fact FactName Value] ->
    [record
      [[[99 111 109 112 111 110 101 110 116] [bytes Name]]
       [[101 118 101 110 116 45 105 100] Id]
       [[110 97 109 101] [symbol FactName]]
       [[116 105 109 101] At]
       [[116 121 112 101] [symbol [102 97 99 116]]]
       [[118 97 108 117 101] Value]]])

(define urdr.world.fact-values
  _ _ _ [] -> []
  Id At Name [Fact | Rest] ->
    [(urdr.world.fact-value Id At Name Fact) |
     (urdr.world.fact-values Id At Name Rest)])

(define urdr.world.component-choice-value
  Id At Name [alternatives Purpose Alternatives] ->
    [record
      [[[97 108 116 101 114 110 97 116 105 118 101 115]
        [list Alternatives]]
       [[99 111 109 112 111 110 101 110 116] [bytes Name]]
       [[101 118 101 110 116 45 105 100] Id]
       [[112 117 114 112 111 115 101] [symbol Purpose]]
       [[116 105 109 101] At]
       [[116 121 112 101]
        [symbol [99 111 109 112 111 110 101 110 116 45
                 99 104 111 105 99 101]]]]])

(define urdr.world.component-choice-values
  _ _ _ [] -> []
  Id At Name [Choice | Rest] ->
    [(urdr.world.component-choice-value Id At Name Choice) |
     (urdr.world.component-choice-values Id At Name Rest)])

(define urdr.world.component-step
  World Id At Name Value ->
    (urdr.world.component-entry
      World Id At Name Value
      (urdr.world.component-find Name (urdr.world.components World))))

(define urdr.world.component-entry
  World Id At Name Value none ->
    (urdr.world.error
      World
      (urdr.component.code "component-unknown")
      (urdr.world.component-detail Name [null]))
  World Id At Name Value [component _ Handler State] ->
    (urdr.world.component-result
      World Id At Name Handler
      (urdr.component.step
        Handler State (urdr.world.component-event At Value))))

(define urdr.world.component-result
  World Id At Name Handler [error Code Detail] ->
    (urdr.world.error
      World Code (urdr.world.component-detail Name Detail))
  World Id At Name Handler [ok [step State Facts Choices]] ->
    (urdr.world.component-commit
      World Id At Name Handler State Facts Choices))

(define urdr.world.component-commit
  [world/v1
    Time NextId Pending Seed Streams Transcript Verdicts
    Components Facts]
  Id At Name Handler State NewFacts Choices ->
    [reduction
      [world/v1
        Time NextId Pending Seed Streams Transcript Verdicts
        (urdr.world.component-put
          [component Name Handler State] Components)
        (append Facts
          (urdr.world.fact-values Id At Name NewFacts))]
      []
      (urdr.world.component-choice-values Id At Name Choices)])

(define urdr.world.path-compare
  [path SubA ActorA PurposeA _] [path SubB ActorB PurposeB _] ->
    (let S (urdr.canonical.bytes-compare SubA SubB)
      (if (not (= S eq))
          S
          (let A (urdr.canonical.bytes-compare ActorA ActorB)
            (if (not (= A eq))
                A
                (urdr.canonical.bytes-compare PurposeA PurposeB))))))

(define urdr.world.path-counter
  _ [] -> (urdr.int.zero)
  [path Sub Actor Purpose _]
  [[path Sub Actor Purpose Counter] | _] -> Counter
  Path [_ | Rest] -> (urdr.world.path-counter Path Rest))

(define urdr.world.stream-put
  Path [] -> [Path]
  [path Sub Actor Purpose Counter]
  [[path Sub Actor Purpose _] | Rest] ->
    [[path Sub Actor Purpose Counter] | Rest]
  Path [Head | Rest] ->
    (if (= (urdr.world.path-compare Path Head) lt)
        [Path Head | Rest]
        [Head | (urdr.world.stream-put Path Rest)]))

(define urdr.world.list-count
  Values -> (urdr.world.list-count-h Values (urdr.int.zero)))

(define urdr.world.list-count-h
  [] Count -> Count
  [_ | Rest] Count ->
    (urdr.world.list-count-h
      Rest (urdr.int.raw.add Count (urdr.int.one))))

(define urdr.world.nth-big
  [Value | _] Index -> Value
    where (urdr.int.raw.zero? Index)
  [_ | Rest] Index ->
    (urdr.world.nth-big
      Rest (urdr.int.raw.subtract Index (urdr.int.one))))

(define urdr.world.choose
  [world/v1
    Time NextId Pending Seed Streams Transcript Verdicts
    Components Facts]
  Id At Subsystem Actor Purpose Alternatives ->
    (let Path [path Subsystem Actor Purpose (urdr.int.zero)]
         Counter (urdr.world.path-counter Path Streams)
         Stream (urdr.prng.stream
                  Seed Subsystem Actor Purpose Counter)
         Bound (urdr.world.list-count Alternatives)
      (if (= (hd Stream) error)
          (urdr.world.error
            [world/v1
              Time NextId Pending Seed Streams Transcript Verdicts
              Components Facts]
            [105 110 118 97 108 105 100 45 112 114 110 103 45 112
             97 116 104]
            [null])
          (urdr.world.choose-sample
            [world/v1
              Time NextId Pending Seed Streams Transcript Verdicts
              Components Facts]
            Id At Subsystem Actor Purpose Alternatives
            (urdr.prng.sample (hd (tl Stream)) Bound)))))

(define urdr.world.choose-sample
  World Id At Subsystem Actor Purpose Alternatives [error _] ->
    (urdr.world.error
      World
      [112 114 110 103 45 115 97 109 112 108 101 45 102 97 105
       108 101 100]
      [null])
  [world/v1
    Time NextId Pending Seed Streams Transcript Verdicts
    Components Facts]
  Id At Subsystem Actor Purpose Alternatives
  [ok [sample Index
        [stream _ _ _ _ _ NextCounter]
        Coordinates]] ->
    (let Selected (urdr.world.nth-big Alternatives Index)
         NextStreams (urdr.world.stream-put
                       [path Subsystem Actor Purpose NextCounter]
                       Streams)
      [reduction
        [world/v1
          Time NextId Pending Seed NextStreams Transcript Verdicts
          Components Facts]
        []
        [(urdr.world.choice-value
           Id At Alternatives Selected Coordinates)]]))

(define urdr.world.coordinate-value
  [coordinate Algorithm Seed Subsystem Actor Purpose Counter BlockIndex] ->
    [record
      [[[97 99 116 111 114] [bytes Actor]]
       [[97 108 103 111 114 105 116 104]
        [symbol [117 114 100 114 45 115 104 97 50 53 54 45
                 99 111 117 110 116 101 114 45 118 49]]]
       [[98 108 111 99 107 45 105 110 100 101 120] BlockIndex]
       [[99 111 117 110 116 101 114] Counter]
       [[112 117 114 112 111 115 101] [bytes Purpose]]
       [[115 101 101 100] [bytes Seed]]
       [[115 117 98 115 121 115 116 101 109] [bytes Subsystem]]]])

(define urdr.world.coordinates-value
  [] -> []
  [Coordinate | Rest] ->
    [(urdr.world.coordinate-value Coordinate) |
     (urdr.world.coordinates-value Rest)])

(define urdr.world.choice-value
  Id At Alternatives Selected Coordinates ->
    [record
      [[[97 108 116 101 114 110 97 116 105 118 101 115]
        [list Alternatives]]
       [[99 111 111 114 100 105 110 97 116 101 115]
        [list (urdr.world.coordinates-value Coordinates)]]
       [[101 118 101 110 116 45 105 100] Id]
       [[115 101 108 101 99 116 101 100] Selected]
       [[116 105 109 101] At]
       [[116 121 112 101] [symbol [99 104 111 105 99 101]]]]])

(define urdr.world.pending-ids
  [] -> []
  [[event Id _ _ _] | Rest] ->
    [Id | (urdr.world.pending-ids Rest)])

(define urdr.world.stream-value
  [path Subsystem Actor Purpose Counter] ->
    [record
      [[[97 99 116 111 114] [bytes Actor]]
       [[99 111 117 110 116 101 114] Counter]
       [[112 117 114 112 111 115 101] [bytes Purpose]]
       [[115 117 98 115 121 115 116 101 109] [bytes Subsystem]]]])

(define urdr.world.stream-values
  [] -> []
  [Stream | Rest] ->
    [(urdr.world.stream-value Stream) |
     (urdr.world.stream-values Rest)])

(define urdr.world.verdict-values
  [] -> []
  [Verdict | Rest] ->
    [(urdr.world.verdict-value Verdict) |
     (urdr.world.verdict-values Rest)])

\\ Component state is world state: the snapshot binds each registered
\\ component name to a SHA-256 digest of its canonically encoded state, so a
\\ component transition can never be invisible to a snapshot comparison
\\ while staying inside the canonical frame budget.
(define urdr.world.state-digest-value
  State ->
    (let Encoded (urdr.canonical.encode-payload-with-profile
                   (urdr.canonical.profile.m1-large) State)
      (if (= (hd Encoded) error)
          [symbol [105 110 118 97 108 105 100 45
                   115 116 97 116 101]]
          [bytes (hd (tl (urdr.sha256 (hd (tl Encoded)))))])))

(define urdr.world.component-value
  Name State ->
    [record
      [[[110 97 109 101] [bytes Name]]
       [[115 116 97 116 101 45 100 105 103 101 115 116]
        (urdr.world.state-digest-value State)]]])

(define urdr.world.component-values
  [] -> []
  [[component Name _ State] | Rest] ->
    [(urdr.world.component-value Name State) |
     (urdr.world.component-values Rest)])

(define urdr.world.snapshot-value
  [world/v1
    Time NextId Pending Seed Streams Transcript Verdicts
    Components Facts] ->
    [record
      [[[99 111 109 112 111 110 101 110 116 115]
        [list (urdr.world.component-values Components)]]
       [[102 97 99 116 45 99 111 117 110 116]
        (urdr.world.list-count Facts)]
       [[110 101 120 116 45 101 118 101 110 116 45 105 100] NextId]
       [[112 101 110 100 105 110 103 45 101 118 101 110 116 45
         105 100 115]
        [list (urdr.world.pending-ids Pending)]]
       [[115 101 101 100] [bytes Seed]]
       [[115 116 114 101 97 109 45 99 111 117 110 116 101 114 115]
        [list (urdr.world.stream-values Streams)]]
       [[116 105 109 101] Time]
       [[116 114 97 110 115 99 114 105 112 116 45 108 101 110
         103 116 104]
        (urdr.world.list-count Transcript)]
       [[118 101 114 100 105 99 116 115]
        [list (urdr.world.verdict-values Verdicts)]]]])

(define urdr.world.snapshot-frame
  World ->
    (if (and (urdr.world.valid? World)
             (= (hd (urdr.component.registry-valid?
                      (urdr.world.components World)))
                ok))
        (urdr.canonical.encode-frame
          (urdr.world.snapshot-value World))
        [error invalid-world]))

(define urdr.world.replay
  Initial Transcript ->
    (if (urdr.world.valid? Initial)
        (urdr.world.replay-h Initial Transcript [])
        [replay-error Initial [] invalid-world]))

(define urdr.world.replay-h
  World [] Reductions ->
    [replay World Reductions]
  World [Input | Rest] Reductions ->
    (let Reduction (urdr.world.reduce World Input)
      (if (urdr.world.reduction-error? Reduction)
          [replay-error
            World
            (append Reductions [Reduction])
            (urdr.world.reduction-choices Reduction)]
          (urdr.world.replay-h
            (urdr.world.reduction-world Reduction)
            Rest
            (append Reductions [Reduction]))))
  World _ Reductions ->
    [replay-error World Reductions invalid-transcript])

(define urdr.world.replay-world
  [replay World _] -> World)

(define urdr.world.replay-reductions
  [replay _ Reductions] -> Reductions)
