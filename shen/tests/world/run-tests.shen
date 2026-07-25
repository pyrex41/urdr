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

(define uwt.alternatives
  -> [[symbol [97 108 112 104 97]]
      [symbol [98 101 116 97]]
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
  Checks [ok Bytes] ->
    (if (uwt.all? Checks)
        (let Hex (hd (tl (urdr.bytes.hex Bytes)))
          (do
            (output "WORLD-TRACE ~A~%" Hex)
            (output "WORLD TESTS: 11/11 PASS~%")
            (output "ALL PASS~%")
            true))
        (do
          (output "WORLD TESTS: FAIL~%")
          false))
  _ [error _] ->
    (do
      (output "WORLD TRACE: ENCODE FAIL~%")
      false))

(define uwt.run
  -> (let Fixture (uwt.setup)
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
               (uwt.invalid-event? Fixture))]
         (uwt.finish
           Checks
           (urdr.canonical.encode-frame
             (uwt.trace-value Fixture))))))

(uwt.run)
