\\ Pure immutable world nucleus.
\\ Requires canonical.shen and prng.shen to be loaded by the caller.

(define urdr.world.initial
  Seed -> [world/v1
           (urdr.int.zero)
           (urdr.int.zero)
           []
           Seed
           []
           []
           []])

(define urdr.world.valid?
  [world/v1 Time NextId _ Seed _ _ _] ->
    (and (= (hd (urdr.time.check Time)) ok)
         (and (= (hd (urdr.time.check NextId)) ok)
              (= (hd (urdr.prng.octets.check Seed)) ok)))
  _ -> false)

(define urdr.world.time
  [world/v1 Time _ _ _ _ _ _] -> Time)

(define urdr.world.next-event-id
  [world/v1 _ NextId _ _ _ _ _] -> NextId)

(define urdr.world.pending
  [world/v1 _ _ Pending _ _ _ _] -> Pending)

(define urdr.world.seed
  [world/v1 _ _ _ Seed _ _ _] -> Seed)

(define urdr.world.streams
  [world/v1 _ _ _ _ Streams _ _] -> Streams)

(define urdr.world.transcript
  [world/v1 _ _ _ _ _ Transcript _] -> Transcript)

(define urdr.world.verdicts
  [world/v1 _ _ _ _ _ _ Verdicts] -> Verdicts)

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
  [world/v1 Time NextId Pending Seed Streams Transcript Verdicts]
  At Kind Payload ->
    (let ValidTime (urdr.time.check At)
      (if (= (hd ValidTime) error)
          (urdr.world.error
            [world/v1
              Time NextId Pending Seed Streams Transcript Verdicts]
            [105 110 118 97 108 105 100 45 116 105 109 101]
            [null])
          (let Order (hd (tl (urdr.time.compare At Time)))
            (if (< Order 0)
                (urdr.world.error
                  [world/v1
                    Time NextId Pending Seed Streams Transcript Verdicts]
                  [115 116 97 108 101 45 101 118 101 110 116]
                  [null])
                (if (not (urdr.world.event-valid?
                           Seed Kind Payload))
                    (urdr.world.error
                      [world/v1
                        Time NextId Pending Seed Streams
                        Transcript Verdicts]
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
                          Verdicts]
                        []
                        []])))))))

(define urdr.world.advance
  [world/v1 Time NextId [] Seed Streams Transcript Verdicts] ->
    (urdr.world.error
      [world/v1 Time NextId [] Seed Streams Transcript Verdicts]
      [110 111 45 112 101 110 100 105 110 103 45 101 118 101 110 116]
      [null])
  [world/v1
    Time NextId [[event Id At Kind Payload] | Rest]
    Seed Streams Transcript Verdicts] ->
    (let Advanced
      [world/v1
        At NextId Rest Seed Streams
        (append Transcript [[advance-to-next-event]])
        Verdicts]
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
  [world/v1 Time NextId Pending Seed Streams Transcript Verdicts]
  Id At property-equals [property PropertyId Actual Expected] ->
    (let Equal (urdr.world.canonical-equal Actual Expected)
      (if (= (hd Equal) error)
          (urdr.world.error
            [world/v1
              Time NextId Pending Seed Streams Transcript Verdicts]
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
                  [[verdict PropertyId Result Id At]])]
              []
              []])))
  World Id At choice
  [choice Subsystem Actor Purpose Alternatives] ->
    (urdr.world.choose
      World Id At Subsystem Actor Purpose Alternatives)
  World _ _ _ _ ->
    (urdr.world.error
      World
      [105 110 118 97 108 105 100 45 112 101 110 100 105 110 103
       45 101 118 101 110 116]
      [null]))

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
  [world/v1 Time NextId Pending Seed Streams Transcript Verdicts]
  Id At Subsystem Actor Purpose Alternatives ->
    (let Path [path Subsystem Actor Purpose (urdr.int.zero)]
         Counter (urdr.world.path-counter Path Streams)
         Stream (urdr.prng.stream
                  Seed Subsystem Actor Purpose Counter)
         Bound (urdr.world.list-count Alternatives)
      (if (= (hd Stream) error)
          (urdr.world.error
            [world/v1
              Time NextId Pending Seed Streams Transcript Verdicts]
            [105 110 118 97 108 105 100 45 112 114 110 103 45 112
             97 116 104]
            [null])
          (urdr.world.choose-sample
            [world/v1
              Time NextId Pending Seed Streams Transcript Verdicts]
            Id At Subsystem Actor Purpose Alternatives
            (urdr.prng.sample (hd (tl Stream)) Bound)))))

(define urdr.world.choose-sample
  World Id At Subsystem Actor Purpose Alternatives [error _] ->
    (urdr.world.error
      World
      [112 114 110 103 45 115 97 109 112 108 101 45 102 97 105
       108 101 100]
      [null])
  [world/v1 Time NextId Pending Seed Streams Transcript Verdicts]
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
          Time NextId Pending Seed NextStreams Transcript Verdicts]
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

(define urdr.world.snapshot-value
  [world/v1 Time NextId Pending Seed Streams Transcript Verdicts] ->
    [record
      [[[110 101 120 116 45 101 118 101 110 116 45 105 100] NextId]
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
    (if (urdr.world.valid? World)
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
