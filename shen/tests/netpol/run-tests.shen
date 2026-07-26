\\ ADR 0004 Decision 4 conformance suite over the normative NetworkPolicy
\\ fixtures. Every semantic line is reproduced independently by
\\ shen/tests/netpol/oracle.py; shen/tests/netpol/test.sh compares them.

(define nup.eval-forms
  [] -> loaded
  [[load _] | Forms] -> (nup.eval-forms Forms)
  [Form | Forms] ->
    (let Ignored (eval Form)
      (nup.eval-forms Forms)))

(define nup.quiet-load
  File -> (nup.eval-forms (read-file File)))

(nup.quiet-load "shen/protocol/canonical.shen")
(nup.quiet-load "shen/world/integer.shen")
(nup.quiet-load "shen/world/netkat.shen")
(nup.quiet-load "shen/world/netpol.shen")

\\ ---------------------------------------------------------------
\\ Octet helpers
\\ ---------------------------------------------------------------

(define nup.string
  [] -> ""
  [B | Bs] -> (cn (n->string B) (nup.string Bs)))

(define nup.div16
  N Q -> Q where (< N 16)
  N Q -> (nup.div16 (- N 16) (+ Q 1)))

(define nup.mod16
  N -> N where (< N 16)
  N -> (nup.mod16 (- N 16)))

(define nup.hex-digit
  N -> (+ 48 N) where (< N 10)
  N -> (+ 87 N))

(define nup.hex
  [] -> []
  [B | Bs] ->
    [(nup.hex-digit (nup.div16 B 0))
     (nup.hex-digit (nup.mod16 B))
     | (nup.hex Bs)])

(define nup.lines
  Bs -> (nup.lines-loop Bs [] []))

(define nup.lines-loop
  [] Current Acc ->
    (if (= Current [])
        (urdr.canonical.rev Acc)
        (urdr.canonical.rev [(urdr.canonical.rev Current) | Acc]))
  [10 | Bs] Current Acc ->
    (nup.lines-loop Bs [] [(urdr.canonical.rev Current) | Acc])
  [13 | Bs] Current Acc -> (nup.lines-loop Bs Current Acc)
  [B | Bs] Current Acc -> (nup.lines-loop Bs [B | Current] Acc))

(define nup.fields
  Bs -> (nup.fields-loop Bs [] []))

(define nup.fields-loop
  [] Current Acc ->
    (urdr.canonical.rev [(urdr.canonical.rev Current) | Acc])
  [124 | Bs] Current Acc ->
    (nup.fields-loop Bs [] [(urdr.canonical.rev Current) | Acc])
  [B | Bs] Current Acc -> (nup.fields-loop Bs [B | Current] Acc))

(define nup.dec
  N -> (urdr.int.raw.to-decimal-octets (urdr.int.raw.from-small N)))

\\ ---------------------------------------------------------------
\\ Case execution
\\ ---------------------------------------------------------------

(define nup.path
  Relative -> (cn "protocol/fixtures/v1/netpol/" (nup.string Relative)))

(define nup.frame
  Relative ->
    (urdr.canonical.decode-frame
      (read-file-as-bytelist (nup.path Relative))))

(define nup.run
  UniversePath PoliciesPath ->
    (urdr.netpol.bind (nup.frame UniversePath)
      (/. U
        (urdr.netpol.bind (nup.frame PoliciesPath)
          (/. P (urdr.netpol.check-compile U P))))))

(define nup.expect-error
  [record [[Key [symbol Bs]]]] ->
    (if (= Key (urdr.netpol.key k-err)) [ok Bs] none)
  _ -> none)

(define nup.admitted-of
  [record Entries] ->
    (nup.chunk-value
      (urdr.netpol.assoc Entries (urdr.netpol.key k-admitted)))
  _ -> none)

(define nup.chunk-value
  none -> none
  [ok [list Chunks]] -> (nup.chunk-join Chunks)
  [ok _] -> none)

(define nup.chunk-join
  [] -> []
  [[text Bs] | Cs] -> (append Bs (nup.chunk-join Cs)))

(define nup.report-ok
  Name Value [error E] -> [error E]
  Name Value [ok Bytes] ->
    (do
      (output "NETPOL-OK|~A|~A~%"
        (nup.string Name) (nup.string (nup.hex Bytes)))
      [ok (nup.admitted-of Value)]))

(define nup.report-term
  Name Compiled Result ->
    (nup.report-term-line
      Name (urdr.netpol.compiled-render Compiled) Result))

(define nup.report-term-line
  Name Rendered [error E] -> [error E]
  Name Rendered [ok Admitted] ->
    (do
      (output "NETPOL-TERM|~A|~A~%" (nup.string Name) (nup.string Rendered))
      [ok Admitted]))

(define nup.report
  Name [error Code] Expect ->
    (nup.report-reject Name Code (nup.expect-error Expect))
  Name [ok Compiled] Expect ->
    (nup.report-accept Name Compiled Expect))

(define nup.report-reject
  Name Code none -> [error unexpected-rejection]
  Name Code [ok Bs] ->
    (if (= Code (intern (nup.string Bs)))
        (do
          (output "NETPOL-REJECT|~A|~A~%" (nup.string Name) (nup.string Bs))
          [ok none])
        [error wrong-rejection]))

(define nup.report-accept
  Name Compiled Expect ->
    (let Value (urdr.netpol.compiled-value Compiled)
      (if (not (= Value Expect))
          [error wrong-result]
          (nup.report-term Name Compiled
            (nup.report-ok Name Value
              (urdr.canonical.encode-frame Value))))))

(define nup.case
  Name UniversePath PoliciesPath ExpectPath ->
    (nup.case-expect Name (nup.run UniversePath PoliciesPath)
      (nup.frame ExpectPath)))

(define nup.case-expect
  Name Result [error E] -> [error expect-frame-undecodable]
  Name Result [ok Expect] -> (nup.report Name Result Expect))

\\ ---------------------------------------------------------------
\\ Mutation flips
\\ ---------------------------------------------------------------

(define nup.lookup
  [] Name -> missing
  [[N V] | Rest] Name -> (if (= N Name) V (nup.lookup Rest Name)))

(define nup.flip
  Admitted Left Right ->
    (nup.flip-pair Left Right
      (nup.lookup Admitted Left) (nup.lookup Admitted Right)))

(define nup.flip-pair
  Left Right missing _ -> [error flip-unknown-case]
  Left Right _ missing -> [error flip-unknown-case]
  Left Right none _ -> [error flip-no-admission]
  Left Right _ none -> [error flip-no-admission]
  Left Right A B ->
    (if (= A B)
        [error flip-not-flipped]
        (do
          (output "NETPOL-FLIP|~A|~A~%" (nup.string Left) (nup.string Right))
          [ok])))

\\ ---------------------------------------------------------------
\\ Index walk
\\ ---------------------------------------------------------------

(define nup.index-line
  [] Admitted Count -> [ok Admitted Count]
  [35 | _] Admitted Count -> [ok Admitted Count]
  Line Admitted Count -> (nup.index-entry (nup.fields Line) Admitted Count))

(define nup.index-entry
  [[67] Name UniversePath PoliciesPath ExpectPath] Admitted Count ->
    (nup.index-case Name
      (nup.case Name UniversePath PoliciesPath ExpectPath) Admitted Count)
  [[70] Left Right] Admitted Count ->
    (nup.index-flip (nup.flip Admitted Left Right) Admitted Count)
  _ Admitted Count -> [error index-shape])

(define nup.index-case
  Name [error E] Admitted Count -> [error E]
  Name [ok Bytes] Admitted Count ->
    [ok [[Name Bytes] | Admitted] (+ Count 1)])

(define nup.index-flip
  [error E] Admitted Count -> [error E]
  [ok] Admitted Count -> [ok Admitted Count])

(define nup.index
  [] Admitted Count -> [ok Count]
  [Line | Lines] Admitted Count ->
    (nup.index-step (nup.index-line Line Admitted Count) Lines))

(define nup.index-step
  [error E] Lines -> [error E]
  [ok Admitted Count] Lines -> (nup.index Lines Admitted Count))

\\ ---------------------------------------------------------------
\\ Direct checks over synthetic universes no frame can express
\\ ---------------------------------------------------------------

(define nup.pod-name
  N -> (append [112] (append (nup.dec (nup.div10 N)) (nup.dec (nup.mod10 N)))))

(define nup.div10
  N -> (hd (urdr.int.small.divmod N 10)))

(define nup.mod10
  N -> (hd (tl (urdr.int.small.divmod N 10))))

(define nup.role
  N -> (append [118] (append (nup.dec (nup.div10 N)) (nup.dec (nup.mod10 N)))))

(define nup.address
  N -> (append [49 48 46 48 46 48 46] (nup.dec N)))

(define nup.big-pod
  N ->
    [record
      [[(urdr.netpol.key k-address) [text (nup.address N)]]
       [(urdr.netpol.key k-labels)
        [record [[[114 111 108 101] [text (nup.role N)]]]]]
       [(urdr.netpol.key k-name) [text (nup.pod-name N)]]
       [(urdr.netpol.key k-namespace)
        [text [100 101 102 97 117 108 116]]]]])

(define nup.big-pods
  0 Acc -> Acc
  N Acc -> (nup.big-pods (- N 1) [(nup.big-pod (- N 1)) | Acc]))

(define nup.big-universe
  Count Ports Protocols ->
    [record
      [[(urdr.netpol.key k-namespaces)
        [list
          [[record
             [[(urdr.netpol.key k-name)
               [text [100 101 102 97 117 108 116]]]]]]]]
       [(urdr.netpol.key k-pods) [list (nup.big-pods Count [])]]
       [(urdr.netpol.key k-ports) [list Ports]]
       [(urdr.netpol.key k-protocols) [list Protocols]]]])

(define nup.exclude-rule
  N ->
    [record
      [[(urdr.netpol.key k-from)
        [list
          [[record
             [[(urdr.netpol.key k-pod-selector)
               [record
                 [[(urdr.netpol.key k-match-expressions)
                   [list
                     [[record
                        [[(urdr.netpol.key k-key)
                          [text [114 111 108 101]]]
                         [(urdr.netpol.key k-operator)
                          [symbol (urdr.netpol.word w-notin)]]
                         [(urdr.netpol.key k-values)
                          [list [[text (nup.role N)]]]]]]]]]]]]]]]]]]])

(define nup.exclude-rules
  0 Acc -> Acc
  N Acc -> (nup.exclude-rules (- N 1) [(nup.exclude-rule (- N 1)) | Acc]))

(define nup.big-policies
  Rules ->
    [list
      [[record
         [[(urdr.netpol.key k-ingress) [list (nup.exclude-rules Rules [])]]
          [(urdr.netpol.key k-name) [text [112]]]
          [(urdr.netpol.key k-namespace)
           [text [100 101 102 97 117 108 116]]]
          [(urdr.netpol.key k-pod-selector) [record []]]
          [(urdr.netpol.key k-policy-types)
           [list [[symbol (urdr.netpol.word w-ingress)]]]]]]]])

(define nup.two-ports
  -> [(urdr.int.raw.from-small 80) (urdr.int.raw.from-small 443)])

(define nup.two-protocols
  -> [[symbol (urdr.netpol.word w-tcp)] [symbol (urdr.netpol.word w-udp)]])

(define nup.direct-error
  Name [error Code] Expected ->
    (if (= Code (intern Expected))
        (do (output "NETPOL-DIRECT|~A|~A~%" Name Expected) [ok])
        [error direct-wrong-code])
  Name _ Expected -> [error direct-not-rejected])

(define nup.direct-ok
  Name true -> (do (output "NETPOL-DIRECT|~A|ok~%" Name) [ok])
  Name _ -> [error direct-failed])

(define nup.marker-ok?
  [record Entries] ->
    (= (urdr.netpol.assoc Entries (urdr.netpol.key k-marker))
       [ok [symbol (urdr.netpol.word w-marker)]])
  _ -> false)

(define nup.marker-check
  [error E] -> false
  [ok Compiled] -> (nup.marker-ok? (urdr.netpol.compiled-value Compiled)))

(define nup.compiled?
  [ok Compiled] -> true
  _ -> false)

(define nup.direct-checks
  -> [(nup.direct-error "vocab-space-too-large"
        (urdr.netpol.check-compile
          (nup.big-universe 34 [(urdr.int.raw.from-small 80)]
            [[symbol (urdr.netpol.word w-tcp)]])
          [list []])
        "vocab-space-too-large")
      (nup.direct-error "term-too-large"
        (urdr.netpol.check-compile
          (nup.big-universe 16 (nup.two-ports) (nup.two-protocols))
          (nup.big-policies 3))
        "term-too-large")
      (nup.direct-ok "term-under-limit"
        (nup.compiled?
          (urdr.netpol.check-compile
            (nup.big-universe 16 (nup.two-ports) (nup.two-protocols))
            (nup.big-policies 2))))
      (nup.direct-ok "spec-semantics-only"
        (nup.marker-check
          (urdr.netpol.check-compile
            (nup.big-universe 4 (nup.two-ports) (nup.two-protocols))
            [list []])))])

(define nup.all-ok?
  [] -> true
  [[ok] | Rest] -> (nup.all-ok? Rest)
  _ -> false)

\\ ---------------------------------------------------------------
\\ Entry point
\\ ---------------------------------------------------------------

(define nup.finish
  Count Directs ->
    (if (nup.all-ok? Directs)
        (do (output "NETPOL DIRECT: ~A~%" (length Directs))
            (output "NETPOL MARKER: ~A~%"
              (nup.string (urdr.netpol.word w-marker)))
            (output "ALL PASS~%")
            done)
        (do (output "NETPOL DIRECT FAILED~%") failed)))

(define nup.report-count
  [error E] -> (do (output "NETPOL FAILED: ~A~%" E) failed)
  [ok Count] ->
    (do (output "NETPOL CASES: ~A~%" Count)
        (nup.finish Count (nup.direct-checks))))

(define nup.main
  -> (nup.report-count
       (nup.index
         (nup.lines
           (read-file-as-bytelist
             "protocol/fixtures/v1/netpol/cases.tsv"))
         []
         0)))

(nup.main)
