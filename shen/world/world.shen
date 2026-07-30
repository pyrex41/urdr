\\ Pure immutable world nucleus.
\\ Requires canonical.shen, prng.shen, and component.shen to be loaded by
\\ the caller.
\\
\\ world/v2 (ADR 0007 D4): the world value grows a tenth slot carrying
\\ the declared fact routes, the route-cascade limit, and the count of
\\ routed deliveries at the current logical time. Routing is world
\\ state — two worlds with the same components but different routes
\\ reduce differently — so it lives in the world value and in the
\\ snapshot rather than beside them; smuggling it into the Components
\\ slot would have hidden a semantic input from every accessor and from
\\ the shape checks. Every constructor site and the snapshot change with
\\ the slot, hence the version bump: a world/v1 value is not a world/v2
\\ value and no code path accepts both.
\\
\\ The router (ADR 0007 D4): after a component step commits, the kernel
\\ matches the step's newly emitted facts — only that step's facts —
\\ against the declared routes in declaration order (outer loop), each
\\ route against the facts in emission order (inner loop), and enqueues
\\ every match as an ordinary [component TARGET VALUE] pending event at
\\ the current logical time with a fresh event id. Enqueue order is
\\ therefore (route declaration order, fact emission order), and the
\\ pending queue's existing (time, id) order makes routed deliveries
\\ dispatch after any same-time events that were already pending. A node
\\ target resolves to every registered component whose META node matches,
\\ in registry order — the registry ascends strictly by component name,
\\ so fan-out order is canonical component-name order and no host
\\ iteration order can reach it. Facts matching no route remain
\\ observations exactly as before. Routing introduces no choice, no time
\\ advance, and no PRNG draw.
\\
\\ Cascade guard: a routed input, when dispatched, may emit facts that
\\ route again, all at one logical time. The count slot counts every
\\ individual routed delivery (one per resolved target component)
\\ enqueued at the current logical time; advancing to a strictly later
\\ time resets it. A commit whose deliveries would push the count past
\\ the limit fails closed with route-cascade-exceeded before any state
\\ change — the step's state, facts, and enqueues are all discarded.
\\ The limit is 64 this wave (D5 binds it to the scenario budget's
\\ max-steps when the driver lands).

(define urdr.world.route-depth-default
  -> (urdr.int.raw.from-small 64))

(define urdr.world.routing-empty
  -> [routing [] (urdr.world.route-depth-default) (urdr.int.zero)])

(define urdr.world.initial
  Seed -> [world/v2
           (urdr.int.zero)
           (urdr.int.zero)
           []
           Seed
           []
           []
           []
           []
           []
           (urdr.world.routing-empty)])

\\ Boot a world with a modeled-component registry (ADR 0004 Decision 1).
\\ Registry entries are [component NAME HANDLER STATE META] (ADR 0007
\\ D3); an invalid registry is refused here rather than repaired at the
\\ first dispatch. Routeless boot is routed boot with no routes, so all
\\ pre-D4 call sites keep their behavior.
(define urdr.world.initial-with-components
  Seed Registry ->
    (urdr.world.initial-with-routes Seed Registry []))

\\ Routed boot (ADR 0007 D4). Routes are [route FACT FROM TARGET] with
\\ TARGET ::= [component ID] | [node NODE]. The scenario validator is
\\ the primary gate; this door re-checks the parts the kernel depends
\\ on — fact and from names, and that every component named actually
\\ registered — so a hand-built world cannot route to a component the
\\ dispatcher would then fail to find.
(define urdr.world.initial-with-routes
  Seed Registry Routes ->
    (let Valid (urdr.component.registry-valid? Registry)
      (if (= (hd Valid) error)
          Valid
          (urdr.world.initial-routed
            (urdr.world.routes-check Routes Registry)
            Seed
            Registry
            Routes))))

(define urdr.world.initial-routed
  [error Code Detail] Seed Registry Routes -> [error Code Detail]
  [ok] Seed Registry Routes ->
    [ok [world/v2
          (urdr.int.zero)
          (urdr.int.zero)
          []
          Seed
          []
          []
          []
          Registry
          []
          [routing
            Routes
            (urdr.world.route-depth-default)
            (urdr.int.zero)]]])

(define urdr.world.route-registered?
  Name Registry ->
    (not (= (urdr.world.component-find Name Registry) none)))

(define urdr.world.routes-check
  [] _ -> [ok]
  [[route Fact From Target] | Rest] Registry ->
    (if (not (and (urdr.component.name-valid? Fact)
                  (urdr.component.name-valid? From)))
        [error (urdr.component.code "route-shape") [null]]
        (if (not (urdr.world.route-registered? From Registry))
            [error (urdr.component.code "route-unknown-component")
                   [symbol From]]
            (urdr.world.routes-check-target Target Rest Registry)))
  _ _ -> [error (urdr.component.code "route-shape") [null]])

(define urdr.world.routes-check-target
  [component Id] Rest Registry ->
    (if (urdr.world.route-registered? Id Registry)
        (urdr.world.routes-check Rest Registry)
        [error (urdr.component.code "route-unknown-component")
               [symbol Id]])
  [node N] Rest Registry ->
    (if (urdr.component.name-valid? N)
        (urdr.world.routes-check Rest Registry)
        [error (urdr.component.code "route-shape") [null]])
  _ _ _ -> [error (urdr.component.code "route-shape") [null]])

\\ Cheap per-reduction shape check, the routing counterpart of
\\ urdr.component.registry-shape?: names only, because membership was
\\ proved at construction and never changes afterwards.
(define urdr.world.route-target-shape?
  [component Id] -> (urdr.component.name-valid? Id)
  [node N] -> (urdr.component.name-valid? N)
  _ -> false)

(define urdr.world.routes-shape?
  [] -> true
  [[route Fact From Target] | Rest] ->
    (and (urdr.component.name-valid? Fact)
         (and (urdr.component.name-valid? From)
              (and (urdr.world.route-target-shape? Target)
                   (urdr.world.routes-shape? Rest))))
  _ -> false)

(define urdr.world.routing-shape?
  [routing Routes Limit Count] ->
    (and (urdr.world.routes-shape? Routes)
         (and (urdr.int.valid? Limit)
              (urdr.int.valid? Count)))
  _ -> false)

(define urdr.world.valid?
  [world/v2 Time NextId _ Seed _ _ _ Components _ Routing] ->
    (and (= (hd (urdr.time.check Time)) ok)
         (and (= (hd (urdr.time.check NextId)) ok)
              (and (= (hd (urdr.prng.octets.check Seed)) ok)
                   (and (urdr.component.registry-shape? Components)
                        (urdr.world.routing-shape? Routing)))))
  _ -> false)

(define urdr.world.time
  [world/v2 Time _ _ _ _ _ _ _ _ _] -> Time)

(define urdr.world.next-event-id
  [world/v2 _ NextId _ _ _ _ _ _ _ _] -> NextId)

(define urdr.world.pending
  [world/v2 _ _ Pending _ _ _ _ _ _ _] -> Pending)

(define urdr.world.seed
  [world/v2 _ _ _ Seed _ _ _ _ _ _] -> Seed)

(define urdr.world.streams
  [world/v2 _ _ _ _ Streams _ _ _ _ _] -> Streams)

(define urdr.world.transcript
  [world/v2 _ _ _ _ _ Transcript _ _ _ _] -> Transcript)

(define urdr.world.verdicts
  [world/v2 _ _ _ _ _ _ Verdicts _ _ _] -> Verdicts)

(define urdr.world.components
  [world/v2 _ _ _ _ _ _ _ Components _ _] -> Components)

(define urdr.world.facts
  [world/v2 _ _ _ _ _ _ _ _ Facts _] -> Facts)

(define urdr.world.routing
  [world/v2 _ _ _ _ _ _ _ _ _ Routing] -> Routing)

(define urdr.world.routes
  [world/v2 _ _ _ _ _ _ _ _ _ [routing Routes _ _]] -> Routes)

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

\\ Scheduled choice alternatives must be strictly ascending in canonical
\\ encoding order — the same comparison the component door enforces
\\ (urdr.component.encoding-ascending?) — because selection is by
\\ positional index: without this, two permutations of one alternative
\\ set would be two different worlds under one seed, and a host's
\\ iteration order could reach world semantics. Strict ascension already
\\ rejects duplicates (equal values compare eq, never lt), so no
\\ separate duplicate check is needed. Callers must first prove every
\\ alternative canonically encodable (urdr.world.canonical-list-valid?):
\\ the comparison reads encodings.
(define urdr.world.alternatives-ascending?
  [] -> true
  [_] -> true
  [A B | Rest] ->
    (and (urdr.component.encoding-ascending? A B)
         (urdr.world.alternatives-ascending? [B | Rest])))

\\ Ordering is checked after event-valid? has proved encodability, in
\\ the same reject-before-any-state-change phase, but under its own
\\ stable code so an unordered menu is distinguishable from a
\\ malformed one. Both choice forms are ordered by the same rule: the
\\ selected form still identifies alternatives positionally in every
\\ artifact that renders the menu, so permutation freedom would be the
\\ same host-order hazard either way.
(define urdr.world.event-order-valid?
  choice [choice _ _ _ Alternatives] ->
    (urdr.world.alternatives-ascending? Alternatives)
  choice [choice _ _ _ Alternatives _ _] ->
    (urdr.world.alternatives-ascending? Alternatives)
  _ _ -> true)

\\ A recorded PRNG coordinate travelling inside a selected choice
\\ (ADR 0007 D2) must be exactly what urdr.prng.sample emits:
\\ the urdr-sha256-counter-v1 algorithm and fields the PRNG's own
\\ constructor door accepts. Re-using urdr.prng.coordinate as the
\\ validator means the transcript can never carry a coordinate the
\\ PRNG could not have produced, without this module restating the
\\ PRNG's field rules.
(define urdr.world.coordinate-shape?
  [coordinate urdr-sha256-counter-v1
    Seed Subsystem Actor Purpose Counter BlockIndex] ->
    (= (hd (urdr.prng.coordinate
             Seed Subsystem Actor Purpose Counter BlockIndex))
       ok)
  _ -> false)

(define urdr.world.coordinates-shape?
  [] -> true
  [Coordinate | Rest] ->
    (and (urdr.world.coordinate-shape? Coordinate)
         (urdr.world.coordinates-shape? Rest))
  _ -> false)

\\ Membership is by canonical-encoding equality — the only value
\\ identity this kernel recognises (ADR 0002) — never host equality of
\\ the parsed forms. Encodability of the selection and of every
\\ alternative was proved by event-valid? before this runs, so the
\\ encodings exist. The selection's encoding is computed once.
(define urdr.world.selection-member?
  Selected Alternatives ->
    (urdr.world.selection-member-enc
      (hd (tl (urdr.canonical.encode-payload Selected)))
      Alternatives))

(define urdr.world.selection-member-enc
  _ [] -> false
  Encoded [Alternative | Rest] ->
    (or (= Encoded
           (hd (tl (urdr.canonical.encode-payload Alternative))))
        (urdr.world.selection-member-enc Encoded Rest)))

\\ The membership door for the selected choice form (ADR 0007 D2): a
\\ selection that is not an element of its own menu is rejected before
\\ any state change, under its own stable code, at the same door that
\\ enforces encodability and ordering. Dispatch relies on this proof —
\\ pending events only enter through this door — exactly as routed
\\ deliveries rely on the routes-check proof.
(define urdr.world.event-selection-valid?
  choice [choice _ _ _ Alternatives Selected _] ->
    (urdr.world.selection-member? Selected Alternatives)
  _ _ -> true)

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
  \\ Selected form (ADR 0007 D2): the same validations as the drawn
  \\ form — the PRNG path must still be well-formed even though no
  \\ draw will happen, so a selected transcript never smuggles in a
  \\ path the drawn form would have refused — plus encodability of the
  \\ selection and shape of the recorded coordinates. Membership is a
  \\ separate door (event-selection-valid?) with its own stable code.
  Seed choice
  [choice Subsystem Actor Purpose Alternatives Selected Coordinates] ->
    (and (urdr.world.nonempty? Alternatives)
         (and (urdr.world.canonical-list-valid? Alternatives)
              (and (urdr.world.canonical-valid? Selected)
                   (and (urdr.world.coordinates-shape? Coordinates)
                        (urdr.world.choice-path-valid?
                          Seed Subsystem Actor Purpose)))))
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
  [world/v2
    Time NextId Pending Seed Streams Transcript Verdicts
    Components Facts Routing]
  At Kind Payload ->
    (let ValidTime (urdr.time.check At)
      (if (= (hd ValidTime) error)
          (urdr.world.error
            [world/v2
              Time NextId Pending Seed Streams Transcript Verdicts
              Components Facts Routing]
            [105 110 118 97 108 105 100 45 116 105 109 101]
            [null])
          (let Order (hd (tl (urdr.time.compare At Time)))
            (if (< Order 0)
                (urdr.world.error
                  [world/v2
                    Time NextId Pending Seed Streams Transcript Verdicts
                    Components Facts Routing]
                  [115 116 97 108 101 45 101 118 101 110 116]
                  [null])
                (if (not (urdr.world.event-valid?
                           Seed Kind Payload))
                    (urdr.world.error
                      [world/v2
                        Time NextId Pending Seed Streams
                        Transcript Verdicts Components Facts Routing]
                      [105 110 118 97 108 105 100 45 101 118 101 110 116]
                      [null])
                (if (not (urdr.world.event-order-valid? Kind Payload))
                    (urdr.world.error
                      [world/v2
                        Time NextId Pending Seed Streams
                        Transcript Verdicts Components Facts Routing]
                      [99 104 111 105 99 101 45 97 108 116 101 114 110
                       97 116 105 118 101 115 45 111 114 100 101 114]
                      [null])
                (if (not (urdr.world.event-selection-valid? Kind Payload))
                    (urdr.world.error
                      [world/v2
                        Time NextId Pending Seed Streams
                        Transcript Verdicts Components Facts Routing]
                      [99 104 111 105 99 101 45 115 101 108 101 99 116
                       105 111 110 45 110 111 116 45 109 101 109 98 101
                       114]
                      [null])
                    (let Event [event NextId At Kind Payload]
                         Next (hd (tl
                                (urdr.time.successor NextId)))
                         Input [schedule At Kind Payload]
                      [reduction
                        [world/v2
                          Time
                          Next
                          (urdr.world.insert-event Event Pending)
                          Seed
                          Streams
                          (append Transcript [Input])
                          Verdicts
                          Components
                          Facts
                          Routing]
                        []
                        []])))))))))

\\ Advancing to a strictly later logical time opens a fresh routed-
\\ delivery budget; same-time advances (several events at one instant)
\\ keep the running count, which is what makes an unbounded same-time
\\ cascade finite.
(define urdr.world.routing-advanced
  [routing Routes Limit Count] Time At ->
    (if (> (hd (tl (urdr.time.compare At Time))) 0)
        [routing Routes Limit (urdr.int.zero)]
        [routing Routes Limit Count]))

(define urdr.world.advance
  [world/v2
    Time NextId [] Seed Streams Transcript Verdicts
    Components Facts Routing] ->
    (urdr.world.error
      [world/v2
        Time NextId [] Seed Streams Transcript Verdicts
        Components Facts Routing]
      [110 111 45 112 101 110 100 105 110 103 45 101 118 101 110 116]
      [null])
  [world/v2
    Time NextId [[event Id At Kind Payload] | Rest]
    Seed Streams Transcript Verdicts Components Facts Routing] ->
    (let Advanced
      [world/v2
        At NextId Rest Seed Streams
        (append Transcript [[advance-to-next-event]])
        Verdicts Components Facts
        (urdr.world.routing-advanced Routing Time At)]
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
  [world/v2
    Time NextId Pending Seed Streams Transcript Verdicts
    Components Facts Routing]
  Id At property-equals [property PropertyId Actual Expected] ->
    (let Equal (urdr.world.canonical-equal Actual Expected)
      (if (= (hd Equal) error)
          (urdr.world.error
            [world/v2
              Time NextId Pending Seed Streams Transcript Verdicts
              Components Facts Routing]
            [105 110 118 97 108 105 100 45 99 97 110 111 110 105 99
             97 108 45 118 97 108 117 101]
            [null])
          (let Result
            (if (hd (tl Equal))
                [symbol [80 65 83 83]]
                [symbol [70 65 73 76]]
            )
            [reduction
              [world/v2
                Time NextId Pending Seed Streams Transcript
                (append Verdicts
                  [[verdict PropertyId Result Id At]])
                Components Facts Routing]
              []
              []])))
  World Id At choice
  [choice Subsystem Actor Purpose Alternatives] ->
    (urdr.world.choose
      World Id At Subsystem Actor Purpose Alternatives)
  World Id At choice
  [choice Subsystem Actor Purpose Alternatives Selected Coordinates] ->
    (urdr.world.apply-selected
      World Id At Alternatives Selected Coordinates)
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
  Name [[component Name Handler State Meta] | _] ->
    [component Name Handler State Meta]
  Name [_ | Rest] -> (urdr.world.component-find Name Rest))

(define urdr.world.component-put
  [component Name Handler State Meta] [] ->
    [[component Name Handler State Meta]]
  [component Name Handler State Meta] [[component Name _ _ _] | Rest] ->
    [[component Name Handler State Meta] | Rest]
  Entry [Head | Rest] ->
    [Head | (urdr.world.component-put Entry Rest)])

\\ The component's declared identity (ADR 0007 D3): its registered name
\\ and, from the validated META record, the node it was declared on. The
\\ component reads its identity under the event's `self` key; it may
\\ never emit `self` back — the reserved-authority scan rejects that.
(define urdr.world.self-value
  Name Meta ->
    [record
      [[[105 100] [symbol Name]]
       [[110 111 100 101] (urdr.component.meta-node-value Meta)]]])

\\ The component reads logical time and its own identity; it may never
\\ assert either back. Keys ascend: input < self < time < type.
(define urdr.world.component-event
  At Value Name Meta ->
    [record
      [[[105 110 112 117 116] Value]
       [[115 101 108 102] (urdr.world.self-value Name Meta)]
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
  World Id At Name Value [component _ Handler State Meta] ->
    (urdr.world.component-result
      World Id At Name Handler Meta
      (urdr.component.step
        Handler State
        (urdr.world.component-event At Value Name Meta))))

(define urdr.world.component-result
  World Id At Name Handler Meta [error Code Detail] ->
    (urdr.world.error
      World Code (urdr.world.component-detail Name Detail))
  World Id At Name Handler Meta [ok [step State Facts Choices]] ->
    (urdr.world.component-commit
      World Id At Name Handler Meta State Facts Choices))

\\ The router (ADR 0007 D4). Deliveries for one commit are computed
\\ first — (route declaration order, fact emission order), node targets
\\ fanned out in registry (canonical component-name) order — and the
\\ cascade budget is checked against their count before any state
\\ change, so an over-budget step alters nothing.
(define urdr.world.component-commit
  [world/v2
    Time NextId Pending Seed Streams Transcript Verdicts
    Components Facts [routing Routes Limit Count]]
  Id At Name Handler Meta State NewFacts Choices ->
    (urdr.world.commit-deliveries
      [world/v2
        Time NextId Pending Seed Streams Transcript Verdicts
        Components Facts [routing Routes Limit Count]]
      Id At Name Handler Meta State NewFacts Choices
      (urdr.world.route-deliveries
        Routes Name NewFacts Components [])))

(define urdr.world.commit-deliveries
  [world/v2
    Time NextId Pending Seed Streams Transcript Verdicts
    Components Facts [routing Routes Limit Count]]
  Id At Name Handler Meta State NewFacts Choices Deliveries ->
    (let NewCount
         (urdr.int.raw.add
           Count (urdr.world.list-count Deliveries))
      (if (> (urdr.int.raw.compare NewCount Limit) 0)
          (urdr.world.error
            [world/v2
              Time NextId Pending Seed Streams Transcript Verdicts
              Components Facts [routing Routes Limit Count]]
            (urdr.component.code "route-cascade-exceeded")
            (urdr.world.component-detail Name [null]))
          (urdr.world.commit-enqueued
            (urdr.world.route-enqueue Deliveries At NextId Pending)
            [world/v2
              Time NextId Pending Seed Streams Transcript Verdicts
              Components Facts [routing Routes Limit NewCount]]
            Id At Name Handler Meta State NewFacts Choices))))

(define urdr.world.commit-enqueued
  [queued NewNextId NewPending]
  [world/v2
    Time NextId Pending Seed Streams Transcript Verdicts
    Components Facts Routing]
  Id At Name Handler Meta State NewFacts Choices ->
    [reduction
      [world/v2
        Time NewNextId NewPending Seed Streams Transcript Verdicts
        (urdr.world.component-put
          [component Name Handler State Meta] Components)
        (append Facts
          (urdr.world.fact-values Id At Name NewFacts))
        Routing]
      []
      (urdr.world.component-choice-values Id At Name Choices)])

\\ Every routed delivery becomes an ordinary component pending event at
\\ the current logical time with a fresh id, ordered among same-time
\\ events by (time, id) exactly as a scheduled one would be. The value
\\ was proved canonical by the component door and the target name was
\\ proved registered at construction, so no schedule-door re-check is
\\ needed, and the transcript records nothing: replay re-derives the
\\ same enqueues from the same routes.
(define urdr.world.route-enqueue
  [] At NextId Pending -> [queued NextId Pending]
  [[deliver Target Value] | Rest] At NextId Pending ->
    (urdr.world.route-enqueue
      Rest
      At
      (hd (tl (urdr.time.successor NextId)))
      (urdr.world.insert-event
        [event NextId At component [component-input Target Value]]
        Pending)))

\\ Deliveries accumulate reversed and are put back in order once, so the
\\ nested walk stays tail recursive.
(define urdr.world.route-deliveries
  [] Name NewFacts Components Acc -> (urdr.canonical.rev Acc)
  [[route Fact From Target] | Rest] Name NewFacts Components Acc ->
    (urdr.world.route-deliveries
      Rest Name NewFacts Components
      (urdr.world.route-match
        Fact From Target Name NewFacts Components Acc))
  _ Name NewFacts Components Acc -> (urdr.canonical.rev Acc))

(define urdr.world.route-match
  Fact From Target From NewFacts Components Acc ->
    (urdr.world.route-facts Fact Target NewFacts Components Acc)
  Fact From Target Name NewFacts Components Acc -> Acc)

(define urdr.world.route-facts
  Fact Target [] Components Acc -> Acc
  Fact Target [[fact Fact Value] | Rest] Components Acc ->
    (urdr.world.route-facts
      Fact Target Rest Components
      (urdr.world.route-resolve Target Value Components Acc))
  Fact Target [_ | Rest] Components Acc ->
    (urdr.world.route-facts Fact Target Rest Components Acc))

\\ A node target fans out to every component whose META node matches, in
\\ registry order; entries are consed in that order and the caller's
\\ single reversal restores it.
(define urdr.world.route-resolve
  [component Id] Value Components Acc -> [[deliver Id Value] | Acc]
  [node N] Value Components Acc ->
    (urdr.world.route-node N Value Components Acc))

(define urdr.world.route-node
  N Value [] Acc -> Acc
  N Value [[component CName _ _ Meta] | Rest] Acc ->
    (if (= (urdr.component.meta-node-value Meta) [symbol N])
        (urdr.world.route-node N Value Rest [[deliver CName Value] | Acc])
        (urdr.world.route-node N Value Rest Acc))
  N Value _ Acc -> Acc)

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

\\ Selected-form dispatch (ADR 0007 D2): the decision transcript, not
\\ the PRNG, is the replay authority. The draw already happened when
\\ the decision was made — in driver space, on the driver's stream —
\\ so dispatch applies the recorded selection WITHOUT drawing: no
\\ urdr.prng call, and no per-path stream counter advance. Advancing a
\\ counter here would perturb every later draw on the same path, which
\\ is exactly the replay non-interference the drawn form's path
\\ isolation guarantees. The recorded Coordinates are embedded in the
\\ emitted choice record verbatim: they are evidence of the original
\\ draw, not something this dispatch can re-derive (the originating
\\ stream may not even be a world stream), so re-deriving or repairing
\\ them would make the transcript a witness of less than the run.
\\ Validity — encodability, menu order, PRNG path, coordinate shape,
\\ and membership of Selected in Alternatives — was proved at the
\\ schedule door before the event entered the pending queue; a
\\ non-member selection fails closed there (choice-selection-not-
\\ member) before any state change.
(define urdr.world.apply-selected
  World Id At Alternatives Selected Coordinates ->
    [reduction
      World
      []
      [(urdr.world.choice-value
         Id At Alternatives Selected Coordinates)]])

(define urdr.world.choose
  [world/v2
    Time NextId Pending Seed Streams Transcript Verdicts
    Components Facts Routing]
  Id At Subsystem Actor Purpose Alternatives ->
    (let Path [path Subsystem Actor Purpose (urdr.int.zero)]
         Counter (urdr.world.path-counter Path Streams)
         Stream (urdr.prng.stream
                  Seed Subsystem Actor Purpose Counter)
         Bound (urdr.world.list-count Alternatives)
      (if (= (hd Stream) error)
          (urdr.world.error
            [world/v2
              Time NextId Pending Seed Streams Transcript Verdicts
              Components Facts Routing]
            [105 110 118 97 108 105 100 45 112 114 110 103 45 112
             97 116 104]
            [null])
          (urdr.world.choose-sample
            [world/v2
              Time NextId Pending Seed Streams Transcript Verdicts
              Components Facts Routing]
            Id At Subsystem Actor Purpose Alternatives
            (urdr.prng.sample (hd (tl Stream)) Bound)))))

(define urdr.world.choose-sample
  World Id At Subsystem Actor Purpose Alternatives [error _] ->
    (urdr.world.error
      World
      [112 114 110 103 45 115 97 109 112 108 101 45 102 97 105
       108 101 100]
      [null])
  [world/v2
    Time NextId Pending Seed Streams Transcript Verdicts
    Components Facts Routing]
  Id At Subsystem Actor Purpose Alternatives
  [ok [sample Index
        [stream _ _ _ _ _ NextCounter]
        Coordinates]] ->
    (let Selected (urdr.world.nth-big Alternatives Index)
         NextStreams (urdr.world.stream-put
                       [path Subsystem Actor Purpose NextCounter]
                       Streams)
      [reduction
        [world/v2
          Time NextId Pending Seed NextStreams Transcript Verdicts
          Components Facts Routing]
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

\\ The snapshot binds name and state digest only. Binding the entry's
\\ META (model and node identity) into snapshots and certificates is
\\ deliberately deferred to the ADR 0008 wave, so the snapshot shape is
\\ unchanged this wave even though META exists at runtime.
(define urdr.world.component-values
  [] -> []
  [[component Name _ State _] | Rest] ->
    [(urdr.world.component-value Name State) |
     (urdr.world.component-values Rest)])

(define urdr.world.route-target-value
  [component Id] -> [symbol Id]
  [node N] -> [record [[[110 111 100 101] [symbol N]]]])

(define urdr.world.route-value
  [route Fact From Target] ->
    [record
      [[[102 97 99 116] [symbol Fact]]
       [[102 114 111 109] [symbol From]]
       [[116 111] (urdr.world.route-target-value Target)]]])

(define urdr.world.route-values
  [] -> []
  [Route | Rest] ->
    [(urdr.world.route-value Route) |
     (urdr.world.route-values Rest)])

\\ Routing is world state, so the snapshot binds it whole: the rules and
\\ limit as declared, and the current same-time delivery count, which
\\ determines how much routed capacity the world has left at this
\\ instant. The value itself is embedded rather than a digest — routes
\\ are declaration-sized (a handful of three-symbol records bounded by
\\ the scenario profile), so a digest would cost the same octets while
\\ hiding the rules from a snapshot diff. Keys ascend count < limit <
\\ rules; route keys ascend fact < from < to; both mirror the scenario
\\ DSL's own rendering so no translation layer can drift.
(define urdr.world.routing-value
  [routing Routes Limit Count] ->
    [record
      [[[99 111 117 110 116] Count]
       [[108 105 109 105 116] Limit]
       [[114 117 108 101 115] [list (urdr.world.route-values Routes)]]]])

(define urdr.world.snapshot-value
  [world/v2
    Time NextId Pending Seed Streams Transcript Verdicts
    Components Facts Routing] ->
    [record
      [[[99 111 109 112 111 110 101 110 116 115]
        [list (urdr.world.component-values Components)]]
       [[102 97 99 116 45 99 111 117 110 116]
        (urdr.world.list-count Facts)]
       [[110 101 120 116 45 101 118 101 110 116 45 105 100] NextId]
       [[112 101 110 100 105 110 103 45 101 118 101 110 116 45
         105 100 115]
        [list (urdr.world.pending-ids Pending)]]
       [[114 111 117 116 101 115]
        (urdr.world.routing-value Routing)]
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
