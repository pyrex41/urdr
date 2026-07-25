(define urdr.tests.eval-forms
  [] -> loaded
  [Form | Rest]
  -> (let Ignored (eval Form)
       (urdr.tests.eval-forms Rest)))

(define urdr.tests.quiet-load
  File -> (urdr.tests.eval-forms (read-file File)))

(urdr.tests.quiet-load "shen/tests/world/test-interfaces.shen")
(urdr.tests.quiet-load "shen/world/world.shen")

(define urdr.tests.all-true?
  [] -> true
  [true | Rest] -> (urdr.tests.all-true? Rest)
  [_ | _] -> false)

(define urdr.tests.nth
  0 [Value | _] -> Value
  N [_ | Rest] -> (urdr.tests.nth (- N 1) Rest))

(define urdr.tests.fixture-inputs
  -> [[urdr-input/v1 schedule 5 command late-a]
      [urdr-input/v1 schedule 5 command late-b]
      [urdr-input/v1
        schedule
        3
        property-equals
        [p-eq [stable value] [stable value]]]
      [urdr-input/v1
        schedule
        5
        choice
        [coin [scheduler vm-0] [red blue]]]
      [urdr-input/v1 advance-to-next-event]
      [urdr-input/v1 advance-to-next-event]
      [urdr-input/v1 advance-to-next-event]
      [urdr-input/v1 advance-to-next-event]])

(define urdr.tests.world-checks
  W0 Inputs Replay
  -> (let Reductions (urdr.world.replay-reductions Replay)
       (let W4
         (urdr.world.reduction-world
           (urdr.tests.nth 3 Reductions))
       (let WA1
         (urdr.world.reduction-world
           (urdr.tests.nth 4 Reductions))
       (let Final (urdr.world.replay-world Replay)
       (let BadTime
         (urdr.world.reduce
           W0
           [urdr-input/v1 schedule -1 command impossible])
       (let PastTime
         (urdr.world.reduce
           Final
           [urdr-input/v1 schedule 4 command impossible])
       (let EmptyAdvance
         (urdr.world.reduce
           Final
           [urdr-input/v1 advance-to-next-event])
       (let Malformed
         (urdr.world.reduce W0 [urdr-input/v1 unknown])
         [(urdr.world.replay-ok? Replay)
          (= (length Reductions) 8)
          (= (urdr.world.time W4) 0)
          (= (urdr.world.pending W4)
             [[urdr-event/v1
                2
                3
                property-equals
                [p-eq [stable value] [stable value]]]
              [urdr-event/v1 0 5 command late-a]
              [urdr-event/v1 1 5 command late-b]
              [urdr-event/v1
                3
                5
                choice
                [coin [scheduler vm-0] [red blue]]]])
          (= (urdr.world.time WA1) 3)
          (= (urdr.world.verdicts WA1)
             [[urdr-verdict/v1 p-eq "PASS" 2 3]])
          (= (urdr.world.reduction-commands
               (urdr.tests.nth 5 Reductions))
             [[urdr-command/v1 0 5 late-a]])
          (= (urdr.world.reduction-commands
               (urdr.tests.nth 6 Reductions))
             [[urdr-command/v1 1 5 late-b]])
          (= (urdr.world.reduction-choices
               (urdr.tests.nth 7 Reductions))
             [[urdr-choice/v1
                3
                5
                coin
                [red blue]
                red
                [scheduler vm-0]]])
          (= (urdr.world.time Final) 5)
          (= (urdr.world.next-event-id Final) 4)
          (= (urdr.world.pending Final) [])
          (= (urdr.world.prng-state Final) 8)
          (= (urdr.world.transcript Final) Inputs)
          (= (urdr.world.replay-world
               (urdr.world.replay W0 Inputs))
             Final)
          (= (urdr.world.reduction-error BadTime)
             [urdr-error/v1 invalid-logical-time -1])
          (= (urdr.world.reduction-world BadTime) W0)
          (= (urdr.world.reduction-error PastTime)
             [urdr-error/v1 event-before-current-time [4 5]])
          (= (urdr.world.reduction-error EmptyAdvance)
             [urdr-error/v1
               no-pending-event
               advance-to-next-event])
          (= (urdr.world.reduction-error Malformed)
             [urdr-error/v1
               malformed-input
               [urdr-input/v1 unknown]])])))))))))

(define urdr.tests.run-world-fixture
  -> (let W0 (urdr.world.initial 7)
       (let Inputs (urdr.tests.fixture-inputs)
       (let Replay (urdr.world.replay W0 Inputs)
       (let Checks (urdr.tests.world-checks W0 Inputs Replay)
         (if (urdr.tests.all-true? Checks)
             (do
               (output "URDR-WORLD-FIXTURE-V1~%")
               (output
                 "TRACE T=5 IDS=2,0,1,3 CMD=0,1 CHOICE=3:red PROPERTY=p-eq:PASS PRNG=8~%")
               (output "WORLD TESTS: 20/20 PASS~%")
               (output "ALL PASS~%")
               true)
             (do
               (output "URDR-WORLD-FIXTURE-V1~%")
               (output "WORLD TESTS: FAIL~%")
               false)))))))

(urdr.tests.run-world-fixture)
