\\ ADR 0004 Decision 2 conformance suite over the normative NetKAT
\\ fixtures. Every semantic line is reproduced independently by
\\ shen/tests/netkat/oracle.py; shen/tests/netkat/test.sh compares them.

(define unt.eval-forms
  [] -> loaded
  [[load _] | Forms] -> (unt.eval-forms Forms)
  [Form | Forms] ->
    (let Ignored (eval Form)
      (unt.eval-forms Forms)))

(define unt.quiet-load
  File -> (unt.eval-forms (read-file File)))

(unt.quiet-load "shen/protocol/canonical.shen")
(unt.quiet-load "shen/world/integer.shen")
(unt.quiet-load "shen/world/netkat.shen")

\\ ---------------------------------------------------------------
\\ Octet helpers
\\ ---------------------------------------------------------------

(define unt.string
  [] -> ""
  [B | Bs] -> (cn (n->string B) (unt.string Bs)))

(define unt.div16
  N Q -> Q where (< N 16)
  N Q -> (unt.div16 (- N 16) (+ Q 1)))

(define unt.mod16
  N -> N where (< N 16)
  N -> (unt.mod16 (- N 16)))

(define unt.hex-digit
  N -> (+ 48 N) where (< N 10)
  N -> (+ 87 N))

(define unt.hex
  [] -> []
  [B | Bs] ->
    [(unt.hex-digit (unt.div16 B 0))
     (unt.hex-digit (unt.mod16 B))
     | (unt.hex Bs)])

(define unt.lines
  Bs -> (unt.lines-loop Bs [] []))

(define unt.lines-loop
  [] Current Acc ->
    (if (= Current [])
        (urdr.canonical.rev Acc)
        (urdr.canonical.rev [(urdr.canonical.rev Current) | Acc]))
  [10 | Bs] Current Acc ->
    (unt.lines-loop Bs [] [(urdr.canonical.rev Current) | Acc])
  [13 | Bs] Current Acc -> (unt.lines-loop Bs Current Acc)
  [B | Bs] Current Acc -> (unt.lines-loop Bs [B | Current] Acc))

(define unt.fields
  Bs -> (unt.fields-loop Bs [] []))

(define unt.fields-loop
  [] Current Acc ->
    (urdr.canonical.rev [(urdr.canonical.rev Current) | Acc])
  [124 | Bs] Current Acc ->
    (unt.fields-loop Bs [] [(urdr.canonical.rev Current) | Acc])
  [B | Bs] Current Acc -> (unt.fields-loop Bs [B | Current] Acc))

\\ ---------------------------------------------------------------
\\ Case-frame vocabulary
\\ ---------------------------------------------------------------

(define unt.key
  expect -> [101 120 112 101 99 116]
  input -> [105 110 112 117 116]
  kind -> [107 105 110 100]
  policy -> [112 111 108 105 99 121]
  vocabulary -> [118 111 99 97 98 117 108 97 114 121]
  left -> [108 101 102 116]
  right -> [114 105 103 104 116]
  ingress -> [105 110 103 114 101 115 115]
  egress -> [101 103 114 101 115 115]
  verdict -> [118 101 114 100 105 99 116])

(define unt.kind-of
  [101 118 97 108] -> eval
  [101 113 117 105 118 97 108 101 110 99 101] -> equivalence
  [114 101 97 99 104 97 98 105 108 105 116 121] -> reachability
  [105 110 118 97 108 105 100 45
   118 111 99 97 98 117 108 97 114 121] -> invalid-vocabulary
  [105 110 118 97 108 105 100 45
   112 111 108 105 99 121] -> invalid-policy
  [105 110 118 97 108 105 100 45
   112 97 99 107 101 116] -> invalid-packet
  [105 110 118 97 108 105 100 45
   114 101 97 99 104 97 98 105 108 105 116 121] -> invalid-reachability
  _ -> unknown)

(define unt.entries-get
  [] Key -> none
  [[K V] | Es] Key -> (if (= K Key) V (unt.entries-get Es Key)))

(define unt.get
  [record Entries] Key -> (unt.entries-get Entries (unt.key Key))
  _ Key -> none)

(define unt.case-kind
  Case -> (unt.kind-symbol (unt.get Case kind)))

(define unt.kind-symbol
  [symbol Bs] -> (unt.kind-of Bs)
  _ -> unknown)

\\ ---------------------------------------------------------------
\\ Case execution
\\ ---------------------------------------------------------------

(define unt.reject-only
  [error E] -> [error E]
  _ -> [error case-not-rejected])

(define unt.policy-stage
  [error E] Policy -> [error E]
  [ok Vocab] Policy -> (urdr.netkat.term Vocab Policy))

(define unt.packet-stage
  [error E] Input -> [error E]
  [ok Vocab] Input -> (urdr.netkat.packet Vocab Input))

(define unt.eval-result
  [error E] -> [error E]
  [ok Set] -> [ok (urdr.netkat.set-value Set)])

(define unt.equivalence-result
  [error E] -> [error E]
  [ok Verdict] -> [ok (urdr.netkat.equivalence-value Verdict)])

(define unt.reachability-result
  [error E] -> [error E]
  [ok Verdict] -> [ok (urdr.netkat.reachability-value Verdict)])

(define unt.run-case
  eval Case ->
    (unt.eval-result
      (urdr.netkat.check-evaluate
        (unt.get Case vocabulary)
        (unt.get Case policy)
        (unt.get Case input)))
  equivalence Case ->
    (unt.equivalence-result
      (urdr.netkat.check-equivalence
        (unt.get Case vocabulary)
        (unt.get Case left)
        (unt.get Case right)))
  reachability Case ->
    (unt.reachability-result
      (urdr.netkat.check-reachability
        (unt.get Case vocabulary)
        (unt.get Case ingress)
        (unt.get Case policy)
        (unt.get Case egress)))
  invalid-vocabulary Case ->
    (unt.reject-only (urdr.netkat.vocabulary (unt.get Case vocabulary)))
  invalid-policy Case ->
    (unt.reject-only
      (unt.policy-stage
        (urdr.netkat.vocabulary (unt.get Case vocabulary))
        (unt.get Case policy)))
  invalid-packet Case ->
    (unt.reject-only
      (unt.packet-stage
        (urdr.netkat.vocabulary (unt.get Case vocabulary))
        (unt.get Case input)))
  invalid-reachability Case ->
    (unt.reject-only
      (urdr.netkat.check-reachability
        (unt.get Case vocabulary)
        (unt.get Case ingress)
        (unt.get Case policy)
        (unt.get Case egress)))
  unknown Case -> [error case-kind-unknown])

(define unt.verdict-bytes
  [symbol Bs] -> Bs
  _ -> none)

(define unt.verdict-of
  [record Entries] ->
    (unt.verdict-bytes (unt.entries-get Entries (unt.key verdict)))
  _ -> none)

(define unt.report-frame
  Name Value [error E] -> [error E]
  Name Value [ok Bytes] ->
    (do
      (output "NETKAT-OK|~A|~A~%"
        (unt.string Name) (unt.string (unt.hex Bytes)))
      [ok (unt.verdict-of Value)]))

(define unt.report
  Name [error Code] [symbol Bs] ->
    (if (= Code (intern (unt.string Bs)))
        (do
          (output "NETKAT-REJECT|~A|~A~%"
            (unt.string Name) (unt.string Bs))
          [ok none])
        [error wrong-rejection])
  Name [error Code] Expect -> [error unexpected-rejection]
  Name [ok Value] Expect ->
    (if (= Value Expect)
        (unt.report-frame Name Value (urdr.canonical.encode-frame Value))
        [error wrong-result]))

(define unt.case-path
  Relative -> (cn "protocol/fixtures/v1/netkat/" (unt.string Relative)))

(define unt.case-decoded
  Name [error E] -> [error E]
  Name [ok Case] ->
    (unt.report Name
      (unt.run-case (unt.case-kind Case) Case)
      (unt.get Case expect)))

(define unt.case
  Name Relative ->
    (unt.case-decoded Name
      (urdr.canonical.decode-frame
        (read-file-as-bytelist (unt.case-path Relative)))))

\\ ---------------------------------------------------------------
\\ Mutation flips
\\ ---------------------------------------------------------------

(define unt.lookup
  [] Name -> missing
  [[N V] | Rest] Name -> (if (= N Name) V (unt.lookup Rest Name)))

(define unt.flip
  Verdicts Left Right ->
    (unt.flip-pair
      Left Right (unt.lookup Verdicts Left) (unt.lookup Verdicts Right)))

(define unt.flip-pair
  Left Right missing _ -> [error flip-unknown-case]
  Left Right _ missing -> [error flip-unknown-case]
  Left Right none _ -> [error flip-no-verdict]
  Left Right _ none -> [error flip-no-verdict]
  Left Right A B ->
    (if (= A B)
        [error flip-not-flipped]
        (do
          (output "NETKAT-FLIP|~A|~A~%"
            (unt.string Left) (unt.string Right))
          [ok])))

\\ ---------------------------------------------------------------
\\ Index walk
\\ ---------------------------------------------------------------

(define unt.index-line
  [] Verdicts Count -> [ok Verdicts Count]
  [35 | _] Verdicts Count -> [ok Verdicts Count]
  Line Verdicts Count ->
    (unt.index-entry (unt.fields Line) Verdicts Count))

(define unt.index-entry
  [[67] Name Relative] Verdicts Count ->
    (unt.index-case Name (unt.case Name Relative) Verdicts Count)
  [[70] Left Right] Verdicts Count ->
    (unt.index-flip (unt.flip Verdicts Left Right) Verdicts Count)
  _ Verdicts Count -> [error index-shape])

(define unt.index-case
  Name [error E] Verdicts Count -> [error E]
  Name [ok Verdict] Verdicts Count ->
    [ok [[Name Verdict] | Verdicts] (+ Count 1)])

(define unt.index-flip
  [error E] Verdicts Count -> [error E]
  [ok] Verdicts Count -> [ok Verdicts Count])

(define unt.index
  [] Verdicts Count -> [ok Count]
  [Line | Lines] Verdicts Count ->
    (unt.index-step (unt.index-line Line Verdicts Count) Lines))

(define unt.index-step
  [error E] Lines -> [error E]
  [ok Verdicts Count] Lines -> (unt.index Lines Verdicts Count))

\\ ---------------------------------------------------------------
\\ Direct checks for branches no canonical frame can express
\\ ---------------------------------------------------------------

(define unt.big
  N -> (hd (tl (urdr.int.from-small N))))

(define unt.dst -> [100 115 116])
(define unt.src -> [115 114 99])

(define unt.small-vocab
  -> [record
       [[(unt.dst) [list [(unt.big 1) (unt.big 2)]]]
        [(unt.src) [list [(unt.big 1) (unt.big 2)]]]]])

(define unt.checked-vocab
  -> (hd (tl (urdr.netkat.vocabulary (unt.small-vocab)))))

(define unt.big-term
  0 -> [nk-id]
  N -> [nk-union [nk-id] (unt.big-term (- N 1))])

(define unt.sorted-step
  A [] -> true
  A [B | Rest] ->
    (and (= (urdr.netkat.packet-compare A B) lt)
         (unt.sorted-step B Rest)))

(define unt.sorted?
  [] -> true
  [A | Rest] -> (unt.sorted-step A Rest))

(define unt.space-ok?
  -> (let Vocab (unt.checked-vocab)
          Space (urdr.netkat.space Vocab)
       (and (unt.sorted? Space)
            (= (length Space) (urdr.netkat.vocab-space-size Vocab)))))

(define unt.round-trip-term
  -> [nk-seq
       [nk-neg [nk-test [symbol (unt.dst)] (unt.big 1)]]
       [nk-star [nk-set [symbol (unt.src)] (unt.big 2)]]])

(define unt.round-trip-ok?
  -> (= (urdr.netkat.term-decode
          (urdr.netkat.term-encode (unt.round-trip-term)))
        [ok (unt.round-trip-term)]))

(define unt.direct-error
  Name [error Code] Expected ->
    (if (= Code (intern Expected))
        (do (output "NETKAT-DIRECT|~A|~A~%" Name Expected) [ok])
        [error direct-wrong-code])
  Name _ Expected -> [error direct-not-rejected])

(define unt.direct-ok
  Name true -> (do (output "NETKAT-DIRECT|~A|ok~%" Name) [ok])
  Name _ -> [error direct-failed])

(define unt.direct-checks
  -> [(unt.direct-error "vocab-field-symbol"
        (urdr.netkat.vocabulary
          [record [[[49 50] [list [(unt.big 1)]]]]])
        "vocab-field-symbol")
      (unt.direct-error "vocab-field-order"
        (urdr.netkat.vocabulary
          [record
            [[(unt.src) [list [(unt.big 1)]]]
             [(unt.dst) [list [(unt.big 1)]]]]])
        "vocab-field-order")
      (unt.direct-error "vocab-field-duplicate"
        (urdr.netkat.vocabulary
          [record
            [[(unt.dst) [list [(unt.big 1)]]]
             [(unt.dst) [list [(unt.big 1)]]]]])
        "vocab-field-order")
      (unt.direct-error "vocab-shape-improper"
        (urdr.netkat.vocabulary [record [nk-bogus]])
        "vocab-shape")
      (unt.direct-error "packet-shape-symbol"
        (urdr.netkat.packet (unt.checked-vocab) [symbol (unt.dst)])
        "packet-shape")
      (unt.direct-error "term-shape-atom"
        (urdr.netkat.term-check (unt.checked-vocab) nk-bogus)
        "term-shape")
      (unt.direct-error "term-shape-empty"
        (urdr.netkat.term-check (unt.checked-vocab) [])
        "term-shape")
      (unt.direct-error "term-head-direct"
        (urdr.netkat.term-check (unt.checked-vocab) [nk-bogus])
        "term-head")
      (unt.direct-error "term-arity-direct"
        (urdr.netkat.term-check
          (unt.checked-vocab) [nk-star [nk-id] [nk-id]])
        "term-arity")
      (unt.direct-error "term-too-large"
        (urdr.netkat.term-check (unt.checked-vocab) (unt.big-term 600))
        "term-too-large")
      (unt.direct-ok "term-under-limit"
        (= (urdr.netkat.term-check
             (unt.checked-vocab) (unt.big-term 400))
           [ok (unt.big-term 400)]))
      (unt.direct-ok "space-order" (unt.space-ok?))
      (unt.direct-ok "term-round-trip" (unt.round-trip-ok?))])

(define unt.all-ok?
  [] -> true
  [[ok] | Rest] -> (unt.all-ok? Rest)
  _ -> false)

\\ ---------------------------------------------------------------
\\ Entry point
\\ ---------------------------------------------------------------

(define unt.finish
  Count Directs ->
    (if (unt.all-ok? Directs)
        (do (output "NETKAT DIRECT: ~A~%" (length Directs))
            (output "ALL PASS~%")
            done)
        (do (output "NETKAT DIRECT FAILED~%") failed)))

(define unt.report-count
  [error E] -> (do (output "NETKAT FAILED: ~A~%" E) failed)
  [ok Count] ->
    (do (output "NETKAT CASES: ~A~%" Count)
        (unt.finish Count (unt.direct-checks))))

(define unt.run
  -> (unt.report-count
       (unt.index
         (unt.lines
           (read-file-as-bytelist
             "protocol/fixtures/v1/netkat/cases.tsv"))
         []
         0)))

(unt.run)
