(load "src/prng-sha256.shen")

(define test.hex-bytes
  "" -> []
  S -> [(sha.hex-byte S 0) | (test.hex-bytes (tlstr (tlstr S)))])

(define test.ok
  Name Actual Expected ->
    (if (= Actual Expected)
        (do (output "PASS ~A~%" Name) true)
        (do (output "FAIL ~A expected=~A actual=~A~%" Name Expected Actual)
            false)))

(define test.all
  [] -> true
  [true | Rest] -> (test.all Rest)
  [_ | _] -> false)

(define test.parse
  S -> (hd (tl (bi.from-decimal S))))

(define test.counter-strings
  [] -> []
  [[coordinate C B] | Rest] ->
    [[(bi.to-decimal C) (bi.to-decimal B)] |
      (test.counter-strings Rest)])

(define test.run
  ->
  (let A (test.parse
           "123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890")
       B (test.parse
           "987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321")
       BigCounter (test.parse
           "1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000123456789")
       BigBlock (test.parse
           "100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007")
       Seed [115 101 101 100]
       Subsystem [115 99 104 101 100 117 108 101 114]
       Actor [118 109 45 48]
       Purpose [114 117 110 110 97 98 108 101]
       Coordinate (prng.coordinate Seed Subsystem Actor Purpose
                                   BigCounter BigBlock)
       Draw0 (prng.draw (prng.stream Seed Subsystem Actor Purpose (bi.zero)))
       Draw1 (prng.draw (hd (tl (tl Draw0))))
       SmallSample (prng.sample
                     (prng.stream Seed Subsystem Actor Purpose
                                  (bi.from-small 42))
                     (bi.from-small 10))
       RejectBound (test.parse
         "57896044618658097711785492504343953926634992332820282019728792003956564819969")
       RejectSample (prng.sample
                      (prng.stream Seed Subsystem Actor Purpose (bi.one))
                      RejectBound)
       Div (bi.divmod A B)
       NegDiv (bi.divmod (bi.negate A) B)
       Results
       [(test.ok "bigint-normalize-zero"
          (bi.make -1 [0 0 0]) [big 0 []])
        (test.ok "bigint-canonical-leading-zero"
          (bi.from-decimal "00") [error noncanonical-decimal])
        (test.ok "bigint-canonical-negative-zero"
          (bi.from-decimal "-0") [error noncanonical-decimal])
        (test.ok "bigint-canonical-plus"
          (bi.from-decimal "+1") [error invalid-decimal])
        (test.ok "bigint-roundtrip-hundreds"
          (bi.to-decimal A)
          "123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890")
        (test.ok "bigint-add"
          (bi.to-decimal (bi.add A B))
          "123456789012345678901234567890123456789012345678902222222211222222221122222222112222222211222222221122222222112222222211222222221122222222112222222211")
        (test.ok "bigint-subtract"
          (bi.to-decimal (bi.subtract A B))
          "123456789012345678901234567890123456789012345678900246913569024691356902469135690246913569024691356902469135690246913569024691356902469135690246913569")
        (test.ok "bigint-signed-add"
          (bi.to-decimal (bi.add (bi.negate A) B))
          "-123456789012345678901234567890123456789012345678900246913569024691356902469135690246913569024691356902469135690246913569024691356902469135690246913569")
        (test.ok "bigint-multiply"
          (bi.to-decimal (bi.multiply A B))
          "121932631137021795226185032733866788594511507391563633592367611644557885992987901082152001356500521248285321124828532112482853211248285321124828532112360920580111263525898643499378616064616736777929561194939744871208653362292333223746380111126352690")
        (test.ok "bigint-divide"
          [(bi.to-decimal (hd (tl Div)))
           (bi.to-decimal (hd (tl (tl Div))))]
          ["124999998860937500014238281249822021484377224731445"
           "281176155028117615502811761550281176155028117615515157440451515744045151574404515157440451515744045"])
        (test.ok "bigint-signed-divide-truncates"
          [(bi.to-decimal (hd (tl NegDiv)))
           (bi.to-decimal (hd (tl (tl NegDiv))))]
          ["-124999998860937500014238281249822021484377224731445"
           "-281176155028117615502811761550281176155028117615515157440451515744045151574404515157440451515744045"])
        (test.ok "bigint-divide-zero"
          (bi.divmod A (bi.zero)) [error divide-by-zero])
        (test.ok "time-add"
          (time.add A B) [ok (bi.add A B)])
        (test.ok "time-underflow"
          (time.subtract B A) [error time-underflow])
        (test.ok "time-negative"
          (time.add (bi.negate B) A) [error negative-time])
        (test.ok "nist-sha256-empty"
          (bytes.hex (sha256 []))
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        (test.ok "nist-sha256-abc"
          (bytes.hex (sha256 [97 98 99]))
          "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        (test.ok "nist-sha256-long"
          (bytes.hex (sha256
            (test.hex-bytes
              "6162636462636465636465666465666765666768666768696768696a68696a6b696a6b6c6a6b6c6d6b6c6d6e6c6d6e6f6d6e6f706e6f7071")))
          "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        (test.ok "coordinate-encoding-length-oracle"
          (length Coordinate) 379)
        (test.ok "coordinate-digest-oracle"
          (bytes.hex (sha256 Coordinate))
          "a1dcd484b919db486f01706451aa2c5c79054e92d4fd128691b8cb0d25c09fca")
        (test.ok "coordinate-field-collision"
          (= (prng.coordinate [1] [2 3] [] [] (bi.zero) (bi.zero))
             (prng.coordinate [1 2] [3] [] [] (bi.zero) (bi.zero)))
          false)
        (test.ok "coordinate-negative-rejected"
          (prng.block Seed Subsystem Actor Purpose
                      (bi.negate (bi.one)) (bi.zero))
          [error negative-coordinate])
        (test.ok "stream-scheduler-0"
          (bytes.hex (hd (tl Draw0)))
          "2d644005d0a6c164c1710b2f062ac3c1db36deec6f244f684487278b33293cda")
        (test.ok "stream-scheduler-1"
          (bytes.hex (hd (tl Draw1)))
          "930f1f83a5bf2eb8d418c7562271d411aadd7993895e909e6a557577960833c2")
        (test.ok "stream-network-independent"
          (bytes.hex
            (prng.block Seed
              [110 101 116 119 111 114 107]
              [108 105 110 107 45 50]
              [108 111 115 115]
              (bi.zero) (bi.zero)))
          "3213080997ee63801bf3428bfb6bcc6f8c6c4cfde0c61af8f350ced737b8fcb2")
        (test.ok "stream-isolation-after-other-draw"
          (bytes.hex (hd (tl Draw1)))
          (bytes.hex
            (prng.block Seed Subsystem Actor Purpose (bi.one) (bi.zero))))
        (test.ok "bounded-sample-small"
          [(bi.to-decimal (hd (tl SmallSample)))
           (bi.to-decimal (hd (tl (tl SmallSample))))
           (test.counter-strings (hd (tl (tl (tl SmallSample)))))]
          ["0" "43" [["42" "0"]]])
        (test.ok "bounded-sample-rejection-transcript"
          [(bi.to-decimal (hd (tl RejectSample)))
           (bi.to-decimal (hd (tl (tl RejectSample))))
           (test.counter-strings (hd (tl (tl (tl RejectSample)))))]
          ["36739179105117227529564779242672866340069775620302227845470142327270182628524"
           "4"
           [["1" "0"] ["2" "0"] ["3" "0"]]])
        (test.ok "bounded-sample-invalid"
          (prng.sample (prng.stream Seed Subsystem Actor Purpose (bi.zero))
                       (bi.zero))
          [error invalid-bound])]
    (if (test.all Results)
        (do (output "prng-sha256: ~A/~A passed~%"
                    (length Results) (length Results))
            (output "ALL PASS~%")
            true)
        (do (output "prng-sha256: SOME FAILED~%") false))))

(test.run)
