\* Scenario DSL conformance suite (SPEC.md 18 M1 subset).

Semantic output lines, in fixture order, are:

  accept|NAME|HEX      valid frame parsed and re-encoded to the same bytes
  reject|NAME|CODE     frame or in-memory value rejected with a stable code
  urdr-scenario: N/N passed
  ALL PASS

Any failure prints a FAIL| line and suppresses the marker. *\

(load "shen/protocol/canonical.shen")
(load "shen/world/integer.shen")
(load "shen/scenario/scenario.shen")

(define urdr.scenario.test.bytes-string
  [] -> ""
  [B | Bs] ->
    (cn (n->string B)
        (urdr.scenario.test.bytes-string Bs)))

(define urdr.scenario.test.lines
  Bs -> (urdr.scenario.test.lines-loop Bs [] []))

(define urdr.scenario.test.lines-loop
  [] Current Acc ->
    (if (= Current [])
        (urdr.canonical.rev Acc)
        (urdr.canonical.rev
          [(urdr.canonical.rev Current) | Acc]))
  [10 | Bs] Current Acc ->
    (urdr.scenario.test.lines-loop
      Bs [] [(urdr.canonical.rev Current) | Acc])
  [13 | Bs] Current Acc ->
    (urdr.scenario.test.lines-loop Bs Current Acc)
  [B | Bs] Current Acc ->
    (urdr.scenario.test.lines-loop Bs [B | Current] Acc))

(define urdr.scenario.test.fields
  Bs -> (urdr.scenario.test.fields-loop Bs [] []))

(define urdr.scenario.test.fields-loop
  [] Current Acc ->
    (urdr.canonical.rev [(urdr.canonical.rev Current) | Acc])
  [124 | Bs] Current Acc ->
    (urdr.scenario.test.fields-loop
      Bs [] [(urdr.canonical.rev Current) | Acc])
  [B | Bs] Current Acc ->
    (urdr.scenario.test.fields-loop Bs [B | Current] Acc))

(define urdr.scenario.test.div16
  N -> (urdr.scenario.test.div16-loop N 0))

(define urdr.scenario.test.div16-loop
  N Q -> Q where (< N 16)
  N Q -> (urdr.scenario.test.div16-loop (- N 16) (+ Q 1)))

(define urdr.scenario.test.mod16
  N -> N where (< N 16)
  N -> (urdr.scenario.test.mod16 (- N 16)))

(define urdr.scenario.test.hex-digit
  N -> (+ 48 N) where (< N 10)
  N -> (+ 87 N))

(define urdr.scenario.test.hex
  [] -> []
  [B | Bs] ->
    [(urdr.scenario.test.hex-digit
       (urdr.scenario.test.div16 B))
     (urdr.scenario.test.hex-digit
       (urdr.scenario.test.mod16 B))
     | (urdr.scenario.test.hex Bs)])

(define urdr.scenario.test.fixture-path
  Relative ->
    (cn "protocol/fixtures/v1/scenario/"
        (urdr.scenario.test.bytes-string Relative)))

\* A valid fixture must parse, and the validated representation must
   re-render to exactly the fixture bytes: validation is lossless and
   nothing is normalized away. *\
(define urdr.scenario.test.valid
  Name Relative ->
    (let Raw
      (read-file-as-bytelist
        (urdr.scenario.test.fixture-path Relative))
      (urdr.scenario.test.valid-parsed
        Name Raw (urdr.scenario.parse-frame Raw))))

(define urdr.scenario.test.valid-parsed
  Name Raw [error E] -> [error E]
  Name Raw [ok Scenario] ->
    (urdr.scenario.test.valid-encoded
      Name Raw Scenario (urdr.scenario.encode-frame Scenario)))

(define urdr.scenario.test.valid-encoded
  Name Raw Scenario [error E] -> [error E]
  Name Raw Scenario [ok Encoded] ->
    (if (not (= Encoded Raw))
        [error reencode]
        (if (not (= (urdr.scenario.parse-frame Encoded) [ok Scenario]))
            [error reparse]
            (do
              (output
                "accept|~A|~A~%"
                (urdr.scenario.test.bytes-string Name)
                (urdr.scenario.test.bytes-string
                  (urdr.scenario.test.hex Raw)))
              [ok]))))

(define urdr.scenario.test.invalid
  Name Relative ExpectedBytes ->
    (let Raw
      (read-file-as-bytelist
        (urdr.scenario.test.fixture-path Relative))
      (urdr.scenario.test.reject
        Name
        ExpectedBytes
        (urdr.scenario.parse-frame Raw))))

(define urdr.scenario.test.reject
  Name ExpectedBytes Result ->
    (let Expected
      (intern (urdr.scenario.test.bytes-string ExpectedBytes))
      (if (= Result [error Expected])
          (do
            (output
              "reject|~A|~A~%"
              (urdr.scenario.test.bytes-string Name)
              (urdr.scenario.test.bytes-string ExpectedBytes))
            [ok])
          [error wrong-rejection])))

(define urdr.scenario.test.fixture-line
  [] -> [ok skip]
  [35 | _] -> [ok skip]
  Line ->
    (urdr.scenario.test.fixture-fields
      (urdr.scenario.test.fields Line)))

(define urdr.scenario.test.fixture-fields
  [[86] Name Relative] -> (urdr.scenario.test.valid Name Relative)
  [[88] Name Relative Expected] ->
    (urdr.scenario.test.invalid Name Relative Expected)
  _ -> [error fixture-shape])

(define urdr.scenario.test.fixtures
  [] Count -> [ok Count]
  [Line | Lines] Count ->
    (urdr.scenario.test.fixtures-step
      (urdr.scenario.test.fixture-line Line) Lines Count))

(define urdr.scenario.test.fixtures-step
  [error E] Lines Count -> [error E]
  [ok skip] Lines Count ->
    (urdr.scenario.test.fixtures Lines Count)
  [ok] Lines Count ->
    (urdr.scenario.test.fixtures Lines (+ Count 1)))

\* In-memory rejection classes that no frame can express, because the
   canonical decoder refuses to produce the value in the first place.
   These prove urdr.scenario.validate is fail-closed on its own, not
   only behind the ADR 0002 decoder. *\
(define urdr.scenario.test.api-name
  Chars -> (urdr.canonical.string-bytes Chars))

(define urdr.scenario.test.minimal-fields
  -> [[[98 117 100 103 101 116]
       [record
         [[[109 97 120 45 101 118 101 110 116 115] [big 1 [1]]]
          [[109 97 120 45 114 117 110 115] [big 1 [1]]]
          [[109 97 120 45 115 116 101 112 115] [big 1 [1]]]]]]
      [[99 111 109 112 111 110 101 110 116 115] [list []]]
      [[100 101 116 101 114 109 105 110 105 115 109]
       [symbol [109 111 100 101 108 101 100]]]
      [[102 97 117 108 116 115] [list []]]
      [[104 101 97 100 101 114 45 118 111 99 97 98 117 108 97 114 121]
       [list
         [[record
            [[[102 105 101 108 100] [symbol [100 115 116]]]
             [[118 97 108 117 101 115] [list [[big 0 []]]]]]]
          [record
            [[[102 105 101 108 100] [symbol [115 114 99]]]
             [[118 97 108 117 101 115] [list [[big 0 []]]]]]]]]]
      [[111 98 115 101 114 118 97 116 105 111 110 115] [list []]]
      [[112 114 111 112 101 114 116 105 101 115] [list []]]
      [[115 101 101 100] [bytes [109 49]]]
      [[116 111 112 111 108 111 103 121]
       [record
         [[[108 105 110 107 115] [list []]]
          [[110 111 100 101 115]
           [list
             [[record
                [[[97 100 100 114 101 115 115] [big 0 []]]
                 [[105 100] [symbol [97]]]]]]]]]]]
      [[118 101 114 115 105 111 110]
       [symbol
         [115 99 101 110 97 114 105 111 47 118 49]]]])

(define urdr.scenario.test.replace
  Key Value [] -> []
  Key Value [[K V] | Fields] ->
    (if (= (urdr.canonical.bytes-compare Key K) eq)
        [[K Value] | Fields]
        [[K V] | (urdr.scenario.test.replace Key Value Fields)]))

(define urdr.scenario.test.minimal
  -> [record (urdr.scenario.test.minimal-fields)])

(define urdr.scenario.test.mutated
  Key Value ->
    [record
      (urdr.scenario.test.replace
        Key Value (urdr.scenario.test.minimal-fields))])

(define urdr.scenario.test.unordered
  -> (let Fields (urdr.scenario.test.minimal-fields)
       [record
         (append (tl Fields) [(hd Fields)])]))

(define urdr.scenario.test.duplicated
  -> (let Fields (urdr.scenario.test.minimal-fields)
       [record [(hd Fields) | Fields]]))

(define urdr.scenario.test.api-cases
  -> [[(urdr.scenario.test.api-name "api-field-order")
       (urdr.scenario.test.unordered)
       record-order]
      [(urdr.scenario.test.api-name "api-duplicate-field")
       (urdr.scenario.test.duplicated)
       record-duplicate]
      [(urdr.scenario.test.api-name "api-float-value")
       (urdr.scenario.test.mutated [115 101 101 100] 1.5)
       value-type]
      [(urdr.scenario.test.api-name "api-noncanonical-integer")
       (urdr.scenario.test.mutated
         [98 117 100 103 101 116]
         [record
           [[[109 97 120 45 101 118 101 110 116 115] [big 1 [1 0]]]
            [[109 97 120 45 114 117 110 115] [big 1 [1]]]
            [[109 97 120 45 115 116 101 112 115] [big 1 [1]]]]])
       integer-representation]
      [(urdr.scenario.test.api-name "api-improper-list")
       (urdr.scenario.test.mutated
         [102 97 117 108 116 115]
         [list (cons [null] improper)])
       improper-list]
      [(urdr.scenario.test.api-name "api-not-a-record")
       [list []]
       scenario-type]])

(define urdr.scenario.test.api-loop
  [] Count -> [ok Count]
  [[Name Value Expected] | Cases] Count ->
    (urdr.scenario.test.api-step
      (urdr.scenario.test.reject
        Name
        (urdr.canonical.string-bytes (str Expected))
        (urdr.scenario.validate Value))
      Cases
      Count))

(define urdr.scenario.test.api-step
  [error E] Cases Count -> [error E]
  [ok] Cases Count ->
    (urdr.scenario.test.api-loop Cases (+ Count 1)))

\* The accessor surface must agree with the declarations it came from,
   so downstream waves read validated structure, not raw records. *\
(define urdr.scenario.test.accessors
  ->
    (urdr.scenario.test.accessors-of
      (urdr.scenario.validate (urdr.scenario.test.minimal))))

(define urdr.scenario.test.accessors-of
  [error E] -> [error E]
  [ok S] ->
    (if (not (urdr.scenario.valid? S))
        [error not-valid]
        (if (not (= (urdr.scenario.seed-of S) [109 49]))
            [error seed]
            (if (not (= (urdr.scenario.determinism-of S)
                        [109 111 100 101 108 101 100]))
                [error determinism]
                (if (not (= (urdr.scenario.budget-of S)
                            [budget [big 1 [1]] [big 1 [1]] [big 1 [1]]]))
                    [error budget]
                    (if (not (= (urdr.scenario.nodes-of
                                  (urdr.scenario.topology-of S))
                                [[node [big 0 []] [97]]]))
                        [error nodes]
                        (if (not (= (urdr.scenario.links-of
                                      (urdr.scenario.topology-of S))
                                    []))
                            [error links]
                            (if (not (= (urdr.scenario.encode-frame [not-a-scenario])
                                        [error scenario-type]))
                                [error encode-guard]
                                [ok]))))))))

(define urdr.scenario.test.run
  CasesPath ->
    (let Accessors (urdr.scenario.test.accessors)
      (if (not (= Accessors [ok]))
          (do (output "FAIL|accessors|~A~%" Accessors) false)
          (urdr.scenario.test.run-fixtures
            (urdr.scenario.test.fixtures
              (urdr.scenario.test.lines
                (read-file-as-bytelist CasesPath))
              0)))))

(define urdr.scenario.test.run-fixtures
  [error E] -> (do (output "FAIL|fixtures|~A~%" E) false)
  [ok Count] ->
    (urdr.scenario.test.run-api
      Count (urdr.scenario.test.api-loop (urdr.scenario.test.api-cases) 0)))

(define urdr.scenario.test.run-api
  Count [error E] -> (do (output "FAIL|api|~A~%" E) false)
  Count [ok ApiCount] ->
    (let Total (+ Count ApiCount)
      (if (= Total 82)
          (do
            (output "urdr-scenario: ~A/~A passed~%" Total Total)
            (output "ALL PASS~%")
            true)
          (do
            (output "FAIL|count|~A~%" Total)
            false))))

(urdr.scenario.test.run "protocol/fixtures/v1/scenario/cases.tsv")
