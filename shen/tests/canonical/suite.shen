\\ ADR 0002 product conformance suite over normative binary fixtures.

(define urdr.canonical.test.bytes-string
  [] -> ""
  [B | Bs] ->
    (cn (n->string B)
        (urdr.canonical.test.bytes-string Bs)))

(define urdr.canonical.test.lines
  Bs -> (urdr.canonical.test.lines-loop Bs [] []))

(define urdr.canonical.test.lines-loop
  [] Current Acc ->
    (if (= Current [])
        (urdr.canonical.rev Acc)
        (urdr.canonical.rev
          [(urdr.canonical.rev Current) | Acc]))
  [10 | Bs] Current Acc ->
    (urdr.canonical.test.lines-loop
      Bs [] [(urdr.canonical.rev Current) | Acc])
  [13 | Bs] Current Acc ->
    (urdr.canonical.test.lines-loop Bs Current Acc)
  [B | Bs] Current Acc ->
    (urdr.canonical.test.lines-loop Bs [B | Current] Acc))

(define urdr.canonical.test.fields
  Bs -> (urdr.canonical.test.fields-loop Bs [] []))

(define urdr.canonical.test.fields-loop
  [] Current Acc ->
    (urdr.canonical.rev
      [(urdr.canonical.rev Current) | Acc])
  [124 | Bs] Current Acc ->
    (urdr.canonical.test.fields-loop
      Bs [] [(urdr.canonical.rev Current) | Acc])
  [B | Bs] Current Acc ->
    (urdr.canonical.test.fields-loop Bs [B | Current] Acc))

(define urdr.canonical.test.small-div16
  N -> (urdr.canonical.test.small-div16-loop N 0))

(define urdr.canonical.test.small-div16-loop
  N Q -> Q where (< N 16)
  N Q ->
    (urdr.canonical.test.small-div16-loop
      (- N 16) (+ Q 1)))

(define urdr.canonical.test.small-mod16
  N -> N where (< N 16)
  N -> (urdr.canonical.test.small-mod16 (- N 16)))

(define urdr.canonical.test.hex-digit
  N -> (+ 48 N) where (< N 10)
  N -> (+ 87 N))

(define urdr.canonical.test.hex
  [] -> []
  [B | Bs] ->
    [(urdr.canonical.test.hex-digit
       (urdr.canonical.test.small-div16 B))
     (urdr.canonical.test.hex-digit
       (urdr.canonical.test.small-mod16 B))
     | (urdr.canonical.test.hex Bs)])

(define urdr.canonical.test.split-at
  0 Bs Acc -> [ok (urdr.canonical.rev Acc) Bs]
  N [B | Bs] Acc ->
    (urdr.canonical.test.split-at
      (- N 1) Bs [B | Acc])
  _ _ _ -> [error split])

(define urdr.canonical.test.stream-two
  Prefix Suffix Value ->
    (urdr.canonical.test.stream-two-first
      (urdr.canonical.stream-feed
        (urdr.canonical.stream-new) Prefix)
      Suffix
      Value))

(define urdr.canonical.test.stream-two-first
  [error E] Suffix Value -> [error E]
  [ok State Out1] Suffix Value ->
    (urdr.canonical.test.stream-two-second
      (urdr.canonical.stream-feed State Suffix)
      Out1
      Value))

(define urdr.canonical.test.stream-two-second
  [error E] Out1 Value -> [error E]
  [ok State Out2] Out1 Value ->
    (if (= (urdr.canonical.stream-finish State) [ok])
        (if (= (append Out1 Out2) [Value])
            [ok]
            [error split-values])
        [error split-finish]))

(define urdr.canonical.test.splits
  Raw Value N Limit ->
    (if (> N Limit)
        [ok]
        (urdr.canonical.test.split-one
          (urdr.canonical.test.split-at N Raw [])
          Raw
          Value
          N
          Limit)))

(define urdr.canonical.test.split-one
  [error E] Raw Value N Limit -> [error E]
  [ok Prefix Suffix] Raw Value N Limit ->
    (let Result
      (urdr.canonical.test.stream-two Prefix Suffix Value)
      (if (= Result [ok])
          (urdr.canonical.test.splits
            Raw Value (+ N 1) Limit)
          Result)))

(define urdr.canonical.test.selected-splits
  Raw Value [] -> [ok]
  Raw Value [N | Ns] ->
    (urdr.canonical.test.selected-split-one
      (urdr.canonical.test.split-at N Raw [])
      Raw
      Value
      Ns))

(define urdr.canonical.test.selected-split-one
  [error E] Raw Value Ns -> [error E]
  [ok Prefix Suffix] Raw Value Ns ->
    (let Result
      (urdr.canonical.test.stream-two Prefix Suffix Value)
      (if (= Result [ok])
          (urdr.canonical.test.selected-splits Raw Value Ns)
          Result)))

(define urdr.canonical.test.split-coverage
  Raw Value ->
    (let Size (length Raw)
      (if (> Size 1500)
          (urdr.canonical.test.selected-splits
            Raw
            Value
            [0 1 4 5 6 1024 2048 3072
             (- Size 1) Size])
          (urdr.canonical.test.splits Raw Value 0 Size))))

(define urdr.canonical.test.byte-coverage
  Raw Value ->
    (if (> (length Raw) 1500)
        [ok]
        (urdr.canonical.test.byte-chunks Raw Value)))

(define urdr.canonical.test.byte-chunks
  Raw Value ->
    (urdr.canonical.test.byte-chunks-loop
      Raw (urdr.canonical.stream-new) [] Value))

(define urdr.canonical.test.byte-chunks-loop
  [] State Out Value ->
    (if (= (urdr.canonical.stream-finish State) [ok])
        (if (= Out [Value])
            [ok]
            [error byte-values])
        [error byte-finish])
  [B | Bs] State Out Value ->
    (urdr.canonical.test.byte-chunks-step
      (urdr.canonical.stream-feed State [B])
      Bs
      Out
      Value))

(define urdr.canonical.test.byte-chunks-step
  [error E] Bs Out Value -> [error E]
  [ok State Emitted] Bs Out Value ->
    (urdr.canonical.test.byte-chunks-loop
      Bs State (append Out Emitted) Value))

(define urdr.canonical.test.fixture-path
  Relative ->
    (cn "protocol/fixtures/v1/canonical/"
        (urdr.canonical.test.bytes-string Relative)))

(define urdr.canonical.test.valid
  Name Relative ->
    (let Raw
      (read-file-as-bytelist
        (urdr.canonical.test.fixture-path Relative))
      (urdr.canonical.test.valid-decoded
        Name Raw (urdr.canonical.decode-frame Raw))))

(define urdr.canonical.test.valid-decoded
  Name Raw [error E] -> [error E]
  Name Raw [ok Value] ->
    (urdr.canonical.test.valid-encoded
      Name Raw Value (urdr.canonical.encode-frame Value)))

(define urdr.canonical.test.valid-encoded
  Name Raw Value [error E] -> [error E]
  Name Raw Value [ok Encoded] ->
    (if (= Encoded Raw)
        (let Splits
          (urdr.canonical.test.split-coverage Raw Value)
          (if (= Splits [ok])
              (let Bytes
                (urdr.canonical.test.byte-coverage Raw Value)
                (if (= Bytes [ok])
                    (do
                      (output
                        "valid|~A|~A~%"
                        (urdr.canonical.test.bytes-string Name)
                        (urdr.canonical.test.bytes-string
                          (urdr.canonical.test.hex Raw)))
                      [ok])
                    Bytes))
              Splits))
        [error reencode]))

(define urdr.canonical.test.invalid
  Name Relative ExpectedBytes ->
    (let Raw
      (read-file-as-bytelist
        (urdr.canonical.test.fixture-path Relative))
      (let Expected
        (intern
          (urdr.canonical.test.bytes-string ExpectedBytes))
        (let Result (urdr.canonical.decode-frame Raw)
          (if (= Result [error Expected])
              (do
                (output
                  "reject|~A|~A~%"
                  (urdr.canonical.test.bytes-string Name)
                  (urdr.canonical.test.bytes-string
                    ExpectedBytes))
                [ok])
              [error wrong-rejection])))))

(define urdr.canonical.test.fixture-line
  [] -> [ok skip]
  [35 | _] -> [ok skip]
  Line ->
    (urdr.canonical.test.fixture-fields
      (urdr.canonical.test.fields Line)))

(define urdr.canonical.test.fixture-fields
  [[86] Name Relative] ->
    (urdr.canonical.test.valid Name Relative)
  [[88] Name Relative Expected] ->
    (urdr.canonical.test.invalid
      Name Relative Expected)
  _ -> [error fixture-shape])

(define urdr.canonical.test.fixtures
  [] Count -> [ok Count]
  [Line | Lines] Count ->
    (urdr.canonical.test.fixtures-step
      (urdr.canonical.test.fixture-line Line)
      Lines
      Count))

(define urdr.canonical.test.fixtures-step
  [error E] Lines Count -> [error E]
  [ok skip] Lines Count ->
    (urdr.canonical.test.fixtures Lines Count)
  [ok] Lines Count ->
    (urdr.canonical.test.fixtures Lines (+ Count 1)))

(define urdr.canonical.test.repeat
  0 X -> []
  N X ->
    [X | (urdr.canonical.test.repeat (- N 1) X)])

(define urdr.canonical.test.api
  -> (let Digits (urdr.canonical.test.repeat 255 57)
          Parsed (urdr.canonical.int-parse Digits)
       (urdr.canonical.test.api-integer
         Digits Parsed)))

(define urdr.canonical.test.api-integer
  Digits [error E] -> [error E]
  Digits [ok Big] ->
    (if (not (= (urdr.canonical.int-render Big) [ok Digits]))
        [error software-integer]
        (if
          (not
            (=
              (urdr.canonical.int-parse
                [45
                 49 50 51 52 53 54 55 56 57 48
                 49 50 51 52 53 54 55 56 57 48
                 49 50 51 52 53 54 55 56 57 48])
              [ok
                [big -1
                  [7890 3456 9012 5678
                   1234 7890 3456 12]]]))
          [error integer-limbs]
          (urdr.canonical.test.api-rejections))))

(define urdr.canonical.test.api-rejections
  ->
    (if
      (not
        (= (urdr.canonical.encode-frame 1.5)
           [error value-type]))
      [error float-encoder]
      (if
        (not
          (=
            (urdr.canonical.encode-frame
              [list (cons [null] improper)])
            [error improper-list]))
        [error improper-encoder]
        (if
          (not
            (=
              (urdr.canonical.encode-frame [big 0 [1]])
              [error integer-representation]))
          [error integer-zero-representation]
          (if
            (not
              (=
                (urdr.canonical.encode-frame [big 1 [1 0]])
                [error integer-representation]))
            [error integer-leading-limb]
            (if
              (not
                (=
                  (urdr.canonical.encode-frame
                    [bytes [1.5]])
                  [error value-type]))
              [error fractional-octet]
              (if
                (not
                  (=
                    (urdr.canonical.stream-feed
                      [urdr.canonical.stream [1.5]]
                      [])
                    [error stream-state]))
                [error forged-stream]
                (urdr.canonical.test.api-stream))))))))

(define urdr.canonical.test.api-stream
  -> (let A (urdr.canonical.encode-frame [null])
          B (urdr.canonical.encode-frame [text [206 187]])
       (urdr.canonical.test.api-stream-frames A B)))

(define urdr.canonical.test.api-stream-frames
  [error E] B -> [error E]
  A [error E] -> [error E]
  [ok A] [ok B] ->
    (urdr.canonical.test.api-stream-result
      (urdr.canonical.stream-feed
        (urdr.canonical.stream-new)
        (append A B))))

(define urdr.canonical.test.api-stream-result
  [error E] -> [error E]
  [ok State [[null] [text [206 187]]]] ->
    (urdr.canonical.stream-finish State)
  _ -> [error multi-frame])

(define urdr.canonical.test.run
  CasesPath ->
    (let API (urdr.canonical.test.api)
      (if (not (= API [ok]))
          (do (output "FAIL|api|~A~%" API) false)
          (let Result
            (urdr.canonical.test.fixtures
              (urdr.canonical.test.lines
                (read-file-as-bytelist CasesPath))
              0)
            (if (= Result [ok 52])
                (do (output "ALL PASS~%") true)
                (do
                  (output "FAIL|fixtures|~A~%" Result)
                  false))))))
