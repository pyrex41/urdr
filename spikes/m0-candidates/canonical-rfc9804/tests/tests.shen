\\ Shared-fixture and API tests for canonical.shen.

(define cr-bytes-string
  [] -> ""
  [B | Bs] -> (cn (n->string B) (cr-bytes-string Bs)))

(define cr-lines
  Bs -> (cr-lines-loop Bs [] []))

(define cr-lines-loop
  [] Current Acc ->
    (if (= Current [])
        (cr-rev Acc)
        (cr-rev [(cr-rev Current) | Acc]))
  [10 | Bs] Current Acc -> (cr-lines-loop Bs [] [(cr-rev Current) | Acc])
  [13 | Bs] Current Acc -> (cr-lines-loop Bs Current Acc)
  [B | Bs] Current Acc -> (cr-lines-loop Bs [B | Current] Acc))

(define cr-fields
  Bs -> (cr-fields-loop Bs [] []))

(define cr-fields-loop
  [] Current Acc -> (cr-rev [(cr-rev Current) | Acc])
  [124 | Bs] Current Acc -> (cr-fields-loop Bs [] [(cr-rev Current) | Acc])
  [B | Bs] Current Acc -> (cr-fields-loop Bs [B | Current] Acc))

(define cr-hex-nibble
  B -> [ok (- B 48)] where (and (>= B 48) (<= B 57))
  B -> [ok (+ 10 (- B 97))] where (and (>= B 97) (<= B 102))
  _ -> [error fixture-hex])

(define cr-hex-decode
  Bs -> (cr-hex-decode-loop Bs []))

(define cr-hex-decode-loop
  [] Acc -> [ok (cr-rev Acc)]
  [A B | Bs] Acc -> (cr-hex-pair (cr-hex-nibble A) (cr-hex-nibble B) Bs Acc)
  _ Acc -> [error fixture-hex])

(define cr-hex-pair
  [error E] B Bs Acc -> [error E]
  A [error E] Bs Acc -> [error E]
  [ok A] [ok B] Bs Acc -> (cr-hex-decode-loop Bs [(+ (* A 16) B) | Acc]))

(define cr-hex-digit
  N -> (+ 48 N) where (< N 10)
  N -> (+ 87 N))

(define cr-hex-encode
  [] -> []
  [B | Bs] ->
    [(cr-hex-digit (cr-small-div16 B))
     (cr-hex-digit (cr-small-mod16 B))
     | (cr-hex-encode Bs)])

\\ Inputs are octets, so bounded repeated subtraction avoids host div/mod APIs.
(define cr-small-div16
  N -> (cr-small-div16-loop N 0))

(define cr-small-div16-loop
  N Q -> Q where (< N 16)
  N Q -> (cr-small-div16-loop (- N 16) (+ Q 1)))

(define cr-small-mod16
  N -> N where (< N 16)
  N -> (cr-small-mod16 (- N 16)))

(define cr-split-at
  0 Bs Acc -> [ok (cr-rev Acc) Bs]
  N [B | Bs] Acc -> (cr-split-at (- N 1) Bs [B | Acc])
  _ _ _ -> [error split])

(define cr-stream-two
  Prefix Suffix Value ->
    (cr-stream-two-first (cr-stream-feed (cr-stream-new) Prefix) Suffix Value))

(define cr-stream-two-first
  [error E] Suffix Value -> [error E]
  [ok State Out1] Suffix Value ->
    (cr-stream-two-second (cr-stream-feed State Suffix) Out1 Value))

(define cr-stream-two-second
  [error E] Out1 Value -> [error E]
  [ok State Out2] Out1 Value ->
    (if (= (cr-stream-finish State) [ok])
        (if (= (append Out1 Out2) [Value])
            [ok]
            [error split-values])
        [error split-finish]))

(define cr-test-splits
  Raw Value N Limit ->
    (if (> N Limit)
        [ok]
        (cr-test-split-one (cr-split-at N Raw []) Raw Value N Limit)))

(define cr-test-split-one
  [error E] Raw Value N Limit -> [error E]
  [ok Prefix Suffix] Raw Value N Limit ->
    (let R (cr-stream-two Prefix Suffix Value)
      (if (= R [ok])
          (cr-test-splits Raw Value (+ N 1) Limit)
          R)))

(define cr-stream-bytes
  Raw Value -> (cr-stream-bytes-loop Raw (cr-stream-new) [] Value))

(define cr-stream-bytes-loop
  [] State Out Value ->
    (if (= (cr-stream-finish State) [ok])
        (if (= Out [Value]) [ok] [error byte-values])
        [error byte-finish])
  [B | Bs] State Out Value ->
    (cr-stream-bytes-step (cr-stream-feed State [B]) Bs Out Value))

(define cr-stream-bytes-step
  [error E] Bs Out Value -> [error E]
  [ok State Emitted] Bs Out Value ->
    (cr-stream-bytes-loop Bs State (append Out Emitted) Value))

(define cr-valid
  Name Hex ->
    (cr-valid-hex Name Hex (cr-hex-decode Hex)))

(define cr-valid-hex
  Name Hex [error E] -> [error E]
  Name Hex [ok Raw] ->
    (if (= (cr-hex-encode Raw) Hex)
        (cr-valid-decoded Name Hex Raw (cr-decode-frame Raw))
        [error fixture-hex-case]))

(define cr-valid-decoded
  Name Hex Raw [error E] -> [error E]
  Name Hex Raw [ok Value] ->
    (cr-valid-encoded Name Hex Raw Value (cr-encode-frame Value)))

(define cr-valid-encoded
  Name Hex Raw Value [error E] -> [error E]
  Name Hex Raw Value [ok Encoded] ->
    (if (= Encoded Raw)
        (let Splits (cr-test-splits Raw Value 0 (length Raw))
          (if (= Splits [ok])
              (let Bytes (cr-stream-bytes Raw Value)
                (if (= Bytes [ok])
                    (do (output "valid|~A|~A~%"
                                (cr-bytes-string Name)
                                (cr-bytes-string (cr-hex-encode Raw)))
                        [ok])
                    Bytes))
              Splits))
        [error reencode]))

(define cr-invalid
  Name Hex ExpectedBytes ->
    (cr-invalid-hex Name Hex ExpectedBytes (cr-hex-decode Hex)))

(define cr-invalid-hex
  Name Hex ExpectedBytes [error E] -> [error E]
  Name Hex ExpectedBytes [ok Raw] ->
    (let Expected (intern (cr-bytes-string ExpectedBytes))
         Result (cr-decode-frame Raw)
      (if (= Result [error Expected])
          (do (output "reject|~A|~A~%"
                      (cr-bytes-string Name)
                      (cr-bytes-string ExpectedBytes))
              [ok])
          [error wrong-rejection])))

(define cr-fixture-line
  [] -> [ok skip]
  [35 | _] -> [ok skip]
  Line -> (cr-fixture-fields (cr-fields Line)))

(define cr-fixture-fields
  [[86] Name Hex] -> (cr-valid Name Hex)
  [[88] Name Hex Expected] -> (cr-invalid Name Hex Expected)
  _ -> [error fixture-shape])

(define cr-fixtures
  [] Count -> [ok Count]
  [Line | Lines] Count ->
    (cr-fixtures-step (cr-fixture-line Line) Lines Count))

(define cr-fixtures-step
  [error E] Lines Count -> [error E]
  [ok skip] Lines Count -> (cr-fixtures Lines Count)
  [ok] Lines Count -> (cr-fixtures Lines (+ Count 1)))

(define cr-repeat
  0 X -> []
  N X -> [X | (cr-repeat (- N 1) X)])

(define cr-api-tests
  -> (let Digits (cr-repeat 255 57)
          Huge (cr-int-parse [45 | Digits])
          HugeRound (if (= Huge [ok [int negative Digits]])
                        (cr-int-render [int negative Digits])
                        [error software-integer])
       (if (not (= HugeRound [ok [45 | Digits]]))
           [error software-integer]
           (if (not (= (cr-encode-frame 1.5) [error value-type]))
               [error float-encoder]
               (if (not (= (cr-encode-frame [list (cons [null] improper)])
                           [error improper-list]))
                   [error improper-encoder]
                   (cr-api-stream-test))))))

(define cr-api-stream-test
  -> (let A (cr-encode-frame [null])
          B (cr-encode-frame [text [206 187]])
       (cr-api-stream-frames A B)))

(define cr-api-stream-frames
  [error E] B -> [error E]
  A [error E] -> [error E]
  [ok A] [ok B] ->
    (cr-api-stream-result (cr-stream-feed (cr-stream-new) (append A B))))

(define cr-api-stream-result
  [error E] -> [error E]
  [ok State [[null] [text [206 187]]]] -> (cr-stream-finish State)
  _ -> [error multi-frame])

(define cr-run-tests
  FixturePath ->
    (let API (cr-api-tests)
      (if (not (= API [ok]))
          (do (output "FAIL|api|~A~%" API) false)
          (let Result (cr-fixtures (cr-lines (read-file-as-bytelist FixturePath)) 0)
            (if (= Result [ok 42])
                (do (output "ALL PASS~%") true)
                (do (output "FAIL|fixtures|~A~%" Result) false))))))
