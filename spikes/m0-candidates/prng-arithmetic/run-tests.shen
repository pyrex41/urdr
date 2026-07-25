(load "spikes/m0-candidates/prng-arithmetic/bigint.shen")
(load "spikes/m0-candidates/prng-arithmetic/prng.shen")

(define pa.test
  _ true -> 1
  Name false -> (do (output "FAIL: ~A~%" Name) 0))

(define pa.tests
  ->
  (let Huge "123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890"
       Divisor "-9988776655443322110099887766554433221100998877665544332211009988776655443322110099887766554433221100998877665544332211009988776655443322110099887766554433221100"
       HugeBI (pa.from-decimal Huge)
       DivisorBI (pa.from-decimal Divisor)
       HugeQR (pa.divmod HugeBI DivisorBI)
       ZeroBlock (pa.prng-block [0] [] [] [] [0] [0])
       ABc (pa.prng-block (pa.from-small 7) [97] [98 99] []
                          (pa.from-small 9) (pa.from-small 2))
       AbC (pa.prng-block (pa.from-small 7) [97 98] [99] []
                          (pa.from-small 9) (pa.from-small 2))
       Ten (pa.sample-bounded (pa.from-small 42)
             [110 101 116 119 111 114 107]
             [108 105 110 107 45 50] [108 111 115 115]
             (pa.from-small 3) (pa.from-small 10))
       Reject (pa.sample-bounded (pa.from-small 1)
                [116 101 115 116 115] [97 99 116 111 114]
                [114 101 106 101 99 116] (pa.from-small 1)
                (pa.from-small 32769))
       HugeBound (pa.from-decimal "99999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999877")
       HugeCounter (pa.from-decimal "1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000987654321")
       HugeSample (pa.sample-bounded (pa.from-small -99)
                    [103 117 101 115 116] [118 109 45 48]
                    [101 110 116 114 111 112 121] HugeCounter HugeBound)
       T1 (pa.test decimal-hundreds (= (pa.to-decimal HugeBI) Huge))
       T2 (pa.test add-subtract
            (= (pa.subtract (pa.add HugeBI DivisorBI) DivisorBI) HugeBI))
       T3 (pa.test multiply
            (= (pa.to-decimal
                 (pa.multiply (pa.from-decimal "12345678901234567890")
                              (pa.from-decimal "-98765432109876543210")))
               "-1219326311370217952237463801111263526900"))
       T4 (pa.test divide-quotient
            (= (pa.to-decimal (hd HugeQR))
               "-12359550450561797741547910617471278878942080999306212046203435864045723357251456813635903681621065778861083254290313409237234737916527737742"))
       T5 (pa.test divide-remainder
            (= (pa.to-decimal (hd (tl HugeQR)))
               "4295906420689924380055304743108133811690553047431081338116905530474310813381169055304743108133811690553047431081338116905530474310813381169055304743108133811690"))
       T6 (pa.test division-identity
            (= (pa.add (pa.multiply (hd HugeQR) DivisorBI)
                       (hd (tl HugeQR))) HugeBI))
       T7 (pa.test time-add
            (= (pa.time-add HugeBI (pa.from-small 10))
               (pa.add HugeBI (pa.from-small 10))))
       T8 (pa.test time-subtract
            (= (pa.time-subtract HugeBI (pa.from-small 10))
               (pa.subtract HugeBI (pa.from-small 10))))
       T9 (pa.test philox-random123-zero
            (= (pa.philox4x32-10
                 [[0 0] [0 0] [0 0] [0 0]] [[0 0] [0 0]])
               [[59605 26151] [50573 57705] [44108 48215] [56280 39680]]))
       T10 (pa.test coordinate-frame
             (= (pa.coordinate-frame [0] [] [] [] [0] [0])
                [85 82 68 82 45 80 72 73 76 79 88 45 70 82 65 77 69 45 118 49
                 1 1 1 0 2 0 3 0 4 0 5 0 6 0]))
       T11 (pa.test coordinate-zero-vector
             (= ZeroBlock
                [[62655 1825] [14122 11144] [62599 589] [34110 26609]]))
       T12 (pa.test field-boundaries-differ (not (= ABc AbC)))
       T13 (pa.test boundary-a-bc-vector
             (= ABc
                [[47974 25295] [58886 46521] [46662 36926] [51852 10196]]))
       T14 (pa.test boundary-ab-c-vector
             (= AbC
                [[34907 46492] [44766 12062] [41348 25480] [8448 63634]]))
       T15 (pa.test random-access-repeat
             (= ABc (pa.prng-block (pa.from-small 7) [97] [98 99] []
                                    (pa.from-small 9) (pa.from-small 2))))
       T16 (pa.test bounded-ten (= (pa.to-decimal (hd Ten)) "2"))
       T17 (pa.test bounded-ten-coordinate
             (= (hd (tl Ten))
                [[accept [0]
                  [[(pa.from-small 42)
                    [110 101 116 119 111 114 107]
                    [108 105 110 107 45 50] [108 111 115 115]
                    (pa.from-small 3) [0]]]
                  (pa.from-small 18722)]]))
       T18 (pa.test bounded-rejection-value
             (= (pa.to-decimal (hd Reject)) "30510"))
       T19 (pa.test bounded-rejection-transcript
             (and (= (length (hd (tl Reject))) 2)
                  (= (map (/. Record (hd Record)) (hd (tl Reject)))
                     [reject accept])))
       T20 (pa.test bounded-rejection-coordinates
             (= (map (/. Record
                       (hd (hd (tl (tl Record)))))
                     (hd (tl Reject)))
                [[(pa.from-small 1)
                  [116 101 115 116 115] [97 99 116 111 114]
                  [114 101 106 101 99 116] (pa.from-small 1) [0]]
                 [(pa.from-small 1)
                  [116 101 115 116 115] [97 99 116 111 114]
                  [114 101 106 101 99 116] (pa.from-small 1)
                  (pa.from-small 1)]]))
       T21 (pa.test bounded-hundreds
             (= (pa.to-decimal (hd HugeSample))
                "70793246827458850802842818613359711353119119001071080951880551760754520052203861930300522668633046208608308876768323811425464368818509000545088826540887115600038964617217187544859351981366414218017300"))
       T22 (pa.test bounded-hundreds-range
             (= (pa.compare (hd HugeSample) HugeBound) -1))
       Total (+ T1 (+ T2 (+ T3 (+ T4 (+ T5 (+ T6 (+ T7 (+ T8
             (+ T9 (+ T10 (+ T11 (+ T12 (+ T13 (+ T14 (+ T15 (+ T16
             (+ T17 (+ T18 (+ T19 (+ T20 (+ T21 T22)))))))))))))))))))))
       (if (= Total 22)
           (do (output "prng-arithmetic: 22/22 passed~%")
               (output "ALL PASS~%")
               true)
           (do (output "prng-arithmetic: ~A/22 passed~%" Total)
               false))))

(pa.tests)
