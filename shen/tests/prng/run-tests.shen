(load "shen/world/prng.shen")

(define urdr.test.decimal.byte
  "0" -> 48
  "1" -> 49
  "2" -> 50
  "3" -> 51
  "4" -> 52
  "5" -> 53
  "6" -> 54
  "7" -> 55
  "8" -> 56
  "9" -> 57
  "-" -> 45
  "+" -> 43)

(define urdr.test.decimal.octets
  "" -> []
  S -> [(urdr.test.decimal.byte (pos S 0)) |
         (urdr.test.decimal.octets (tlstr S))])

(define urdr.test.parse
  S -> (hd (tl (urdr.int.from-decimal-octets
                 (urdr.test.decimal.octets S)))))

(define urdr.test.hex.octets
  "" -> []
  S -> [(urdr.prng.sha.hex-byte S 0) |
         (urdr.test.hex.octets (tlstr (tlstr S)))])

(define urdr.test.hex
  Bs -> (hd (tl (urdr.bytes.hex Bs))))

(define urdr.test.ok
  Name Actual Expected ->
    (if (= Actual Expected)
        (do (output "PASS ~A~%" Name) true)
        (do (output "FAIL ~A expected=~A actual=~A~%"
                    Name Expected Actual)
            false)))

(define urdr.test.all
  [] -> true
  [true | Rest] -> (urdr.test.all Rest)
  [_ | _] -> false)

(define urdr.test.transcript.pairs
  [] -> []
  [[coordinate urdr-sha256-counter-v1 _ _ _ _ C B] | Rest] ->
    [[C B] | (urdr.test.transcript.pairs Rest)])

(define urdr.test.run
  ->
  (let A (urdr.test.parse
           "123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890")
       B (urdr.test.parse
           "987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321")
       BigCounter (urdr.test.parse
           "1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000123456789")
       BigBlock (urdr.test.parse
           "100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007")
       Seed [115 101 101 100]
       Subsystem [115 99 104 101 100 117 108 101 114]
       Actor [118 109 45 48]
       Purpose [114 117 110 110 97 98 108 101]
       Stream0 (hd (tl (urdr.prng.stream
                         Seed Subsystem Actor Purpose (urdr.int.zero))))
       Draw0 (hd (tl (urdr.prng.draw Stream0)))
       Stream1 (hd (tl (tl Draw0)))
       Draw1 (hd (tl (urdr.prng.draw Stream1)))
       SmallSample (hd (tl (urdr.prng.sample
                             (hd (tl (urdr.prng.stream
                               Seed Subsystem Actor Purpose
                               (urdr.int.raw.from-small 42))))
                             (urdr.int.raw.from-small 10))))
       RejectBound (urdr.test.parse
         "57896044618658097711785492504343953926634992332820282019728792003956564819969")
       RejectSample (hd (tl (urdr.prng.sample
                              (hd (tl (urdr.prng.stream
                                Seed Subsystem Actor Purpose
                                (urdr.int.one))))
                              RejectBound)))
       Div (hd (tl (urdr.int.divmod A B)))
       NegA (hd (tl (urdr.int.negate A)))
       NegDiv (hd (tl (urdr.int.divmod NegA B)))
       Results
       [(urdr.test.ok "integer-normalize-zero"
          (urdr.int.make -1 [0 0 0])
          [ok [big 0 []]])
        (urdr.test.ok "integer-normalize-high-zeroes"
          (urdr.int.make 1 [1 0 0])
          [ok [big 1 [1]]])
        (urdr.test.ok "integer-invalid-sign"
          (urdr.int.make 2 []) [error invalid-sign])
        (urdr.test.ok "integer-zero-sign-magnitude"
          (urdr.int.make 0 [1]) [error zero-sign-with-magnitude])
        (urdr.test.ok "integer-invalid-limb-high"
          (urdr.int.make 1 [10000]) [error invalid-limb])
        (urdr.test.ok "integer-invalid-limb-low"
          (urdr.int.make 1 [-1]) [error invalid-limb])
        (urdr.test.ok "integer-invalid-limb-fraction"
          (urdr.int.make 1 [1.5]) [error invalid-limb])
        (urdr.test.ok "integer-improper-limbs"
          (urdr.int.make 1 [1 | 2]) [error improper-limbs])
        (urdr.test.ok "integer-reject-nonnormal"
          (urdr.int.validate [big 1 [1 0]])
          [error noncanonical-integer])
        (urdr.test.ok "decimal-leading-zero"
          (urdr.int.from-decimal-octets [48 48])
          [error noncanonical-decimal])
        (urdr.test.ok "decimal-negative-zero"
          (urdr.int.from-decimal-octets [45 48])
          [error noncanonical-decimal])
        (urdr.test.ok "decimal-plus"
          (urdr.int.from-decimal-octets [43 49])
          [error invalid-decimal-octet])
        (urdr.test.ok "decimal-invalid-octet"
          (urdr.int.from-decimal-octets [256])
          [error invalid-octet])
        (urdr.test.ok "decimal-improper-octets"
          (urdr.int.from-decimal-octets [49 | 50])
          [error improper-octets])
        (urdr.test.ok "integer-roundtrip-hundreds"
          (urdr.int.to-decimal-octets A)
          [ok (urdr.test.decimal.octets
            "123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890")])
        (urdr.test.ok "integer-add"
          (urdr.int.to-decimal-octets
            (hd (tl (urdr.int.add A B))))
          [ok (urdr.test.decimal.octets
            "123456789012345678901234567890123456789012345678902222222211222222221122222222112222222211222222221122222222112222222211222222221122222222112222222211")])
        (urdr.test.ok "integer-subtract"
          (urdr.int.to-decimal-octets
            (hd (tl (urdr.int.subtract A B))))
          [ok (urdr.test.decimal.octets
            "123456789012345678901234567890123456789012345678900246913569024691356902469135690246913569024691356902469135690246913569024691356902469135690246913569")])
        (urdr.test.ok "integer-multiply"
          (urdr.int.to-decimal-octets
            (hd (tl (urdr.int.multiply A B))))
          [ok (urdr.test.decimal.octets
            "121932631137021795226185032733866788594511507391563633592367611644557885992987901082152001356500521248285321124828532112482853211248285321124828532112360920580111263525898643499378616064616736777929561194939744871208653362292333223746380111126352690")])
        (urdr.test.ok "integer-divide"
          [(urdr.int.raw.to-decimal-octets (hd (tl Div)))
           (urdr.int.raw.to-decimal-octets (hd (tl (tl Div))))]
          [(urdr.test.decimal.octets
             "124999998860937500014238281249822021484377224731445")
           (urdr.test.decimal.octets
             "281176155028117615502811761550281176155028117615515157440451515744045151574404515157440451515744045")])
        (urdr.test.ok "integer-signed-divide"
          [(urdr.int.raw.to-decimal-octets (hd (tl NegDiv)))
           (urdr.int.raw.to-decimal-octets (hd (tl (tl NegDiv))))]
          [(urdr.test.decimal.octets
             "-124999998860937500014238281249822021484377224731445")
           (urdr.test.decimal.octets
             "-281176155028117615502811761550281176155028117615515157440451515744045151574404515157440451515744045")])
        (urdr.test.ok "integer-divide-zero"
          (urdr.int.divmod A (urdr.int.zero))
          [error divide-by-zero])
        (urdr.test.ok "time-compare"
          (urdr.time.compare A B) [ok 1])
        (urdr.test.ok "time-successor"
          (urdr.time.successor B)
          [ok (urdr.int.raw.add B (urdr.int.one))])
        (urdr.test.ok "time-underflow"
          (urdr.time.subtract B A) [error time-underflow])
        (urdr.test.ok "time-negative"
          (urdr.time.add NegA B) [error negative-time])
        (urdr.test.ok "sha-invalid-octet"
          (urdr.sha256 [256]) [error invalid-octet])
        (urdr.test.ok "sha-improper-octets"
          (urdr.sha256 [1 | 2]) [error improper-octets])
        (urdr.test.ok "nist-sha256-empty"
          (urdr.test.hex (hd (tl (urdr.sha256 []))))
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        (urdr.test.ok "nist-sha256-abc"
          (urdr.test.hex (hd (tl (urdr.sha256 [97 98 99]))))
          "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        (urdr.test.ok "nist-sha256-long"
          (urdr.test.hex (hd (tl (urdr.sha256
            (urdr.test.hex.octets
              "6162636462636465636465666465666765666768666768696768696a68696a6b696a6b6c6a6b6c6d6b6c6d6e6c6d6e6f6d6e6f706e6f7071")))))
          "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        (urdr.test.ok "uvar-zero"
          (urdr.prng.uvar.encode (urdr.int.zero)) [ok [0]])
        (urdr.test.ok "uvar-128"
          (urdr.prng.uvar.encode (urdr.int.raw.from-small 128))
          [ok [129 0]])
        (urdr.test.ok "uvar-decode"
          (urdr.prng.uvar.decode [129 0])
          [uvar [big 1 [128]] []])
        (urdr.test.ok "uvar-nonminimal"
          (urdr.prng.uvar.decode [128 0])
          [error nonminimal-uvar])
        (urdr.test.ok "uvar-truncated"
          (urdr.prng.uvar.decode [129])
          [error truncated-uvar])
        (urdr.test.ok "uvar-invalid-octet"
          (urdr.prng.uvar.decode [256])
          [error invalid-octet])
        (urdr.test.ok "uvar-improper-octets"
          (urdr.prng.uvar.decode [1 | 2])
          [error improper-octets])
        (urdr.test.ok "coordinate-exact-bytes"
          (urdr.test.hex (hd (tl (urdr.prng.coordinate
            Seed Subsystem Actor Purpose
            (urdr.int.raw.from-small 42)
            (urdr.int.raw.from-small 3)))))
          "555244522d50524e472d534841323536000101047365656402097363686564756c65720304766d2d30040872756e6e61626c6505023432060133")
        (urdr.test.ok "coordinate-exact-digest"
          (urdr.test.hex (hd (tl (urdr.prng.block
            Seed Subsystem Actor Purpose
            (urdr.int.raw.from-small 42)
            (urdr.int.raw.from-small 3)))))
          "d0fa83280565fdd6bce844bc0d104a12dce9be1cb1a83cd71c803ea77b30d5ab")
        (urdr.test.ok "coordinate-huge-digest"
          (urdr.test.hex (hd (tl (urdr.prng.block
            Seed Subsystem Actor Purpose BigCounter BigBlock))))
          "a1dcd484b919db486f01706451aa2c5c79054e92d4fd128691b8cb0d25c09fca")
        (urdr.test.ok "coordinate-field-collision"
          (= (urdr.prng.coordinate
               [1] [2 3] [] [] (urdr.int.zero) (urdr.int.zero))
             (urdr.prng.coordinate
               [1 2] [3] [] [] (urdr.int.zero) (urdr.int.zero)))
          false)
        (urdr.test.ok "coordinate-invalid-octet"
          (urdr.prng.coordinate
            [256] [] [] [] (urdr.int.zero) (urdr.int.zero))
          [error invalid-octet])
        (urdr.test.ok "coordinate-negative-counter"
          (urdr.prng.coordinate
            [] [] [] [] (urdr.int.raw.negate (urdr.int.one))
            (urdr.int.zero))
          [error negative-counter])
        (urdr.test.ok "coordinate-negative-block"
          (urdr.prng.coordinate
            [] [] [] [] (urdr.int.zero)
            (urdr.int.raw.negate (urdr.int.one)))
          [error negative-block-index])
        (urdr.test.ok "coordinate-noncanonical-counter"
          (urdr.prng.coordinate
            [] [] [] [] [big 1 [1 0]] (urdr.int.zero))
          [error noncanonical-integer])
        (urdr.test.ok "stream-wrong-algorithm"
          (urdr.prng.draw
            [stream wrong [] [] [] [] [big 0 []]])
          [error wrong-prng-algorithm])
        (urdr.test.ok "stream-improper-octets"
          (urdr.prng.draw
            [stream urdr-sha256-counter-v1
              [1 | 2] [] [] [] [big 0 []]])
          [error improper-octets])
        (urdr.test.ok "stream-scheduler-0"
          (urdr.test.hex (hd (tl Draw0)))
          "2d644005d0a6c164c1710b2f062ac3c1db36deec6f244f684487278b33293cda")
        (urdr.test.ok "stream-scheduler-1"
          (urdr.test.hex (hd (tl Draw1)))
          "930f1f83a5bf2eb8d418c7562271d411aadd7993895e909e6a557577960833c2")
        (urdr.test.ok "stream-network-independent"
          (urdr.test.hex (hd (tl (urdr.prng.block
            Seed
            [110 101 116 119 111 114 107]
            [108 105 110 107 45 50]
            [108 111 115 115]
            (urdr.int.zero) (urdr.int.zero)))))
          "3213080997ee63801bf3428bfb6bcc6f8c6c4cfde0c61af8f350ced737b8fcb2")
        (urdr.test.ok "stream-isolation-after-other-draw"
          (hd (tl Draw1))
          (hd (tl (urdr.prng.block
            Seed Subsystem Actor Purpose
            (urdr.int.one) (urdr.int.zero)))))
        (urdr.test.ok "bounded-sample-small"
          [(hd (tl SmallSample))
           (hd (tl (tl SmallSample)))
           (urdr.test.transcript.pairs
             (hd (tl (tl (tl SmallSample)))))]
          [(urdr.int.zero)
           [stream urdr-sha256-counter-v1
             Seed Subsystem Actor Purpose
             (urdr.int.raw.from-small 43)]
           [[(urdr.int.raw.from-small 42) (urdr.int.zero)]]])
        (urdr.test.ok "bounded-sample-rejection"
          [(hd (tl RejectSample))
           (hd (tl (tl RejectSample)))
           (urdr.test.transcript.pairs
             (hd (tl (tl (tl RejectSample)))))]
          [(urdr.test.parse
             "11445315209345693383347083455327355573348432142624635742835919096968712688866")
           [stream urdr-sha256-counter-v1
             Seed Subsystem Actor Purpose (urdr.int.raw.from-small 2)]
           [[(urdr.int.one) (urdr.int.zero)]
            [(urdr.int.one) (urdr.int.one)]]])
        (urdr.test.ok "bounded-sample-zero"
          (urdr.prng.sample Stream0 (urdr.int.zero))
          [error invalid-bound])
        (urdr.test.ok "bounded-sample-noncanonical"
          (urdr.prng.sample Stream0 [big 1 [1 0]])
          [error noncanonical-integer])
        (urdr.test.ok "bounded-sample-too-large"
          (urdr.prng.sample Stream0
            (urdr.test.parse
              "115792089237316195423570985008687907853269984665640564039457584007913129639937"))
          [error bound-too-large])]
    (if (urdr.test.all Results)
        (do (output "urdr-prng: ~A/~A passed~%"
                    (length Results) (length Results))
            (output "ALL PASS~%")
            true)
        (do (output "urdr-prng: SOME FAILED~%") false))))

(urdr.test.run)
