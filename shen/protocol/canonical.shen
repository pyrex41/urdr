\\ Urdr canonical values and netstring framing (ADR 0002).
\\ Octets are proper lists of exact host integers in [0,255].
\\ Integers use ADR 0003 values: [big SIGN LITTLE-ENDIAN-BASE-10000-LIMBS].
\\ Public operations return [ok ...] or [error stable-code].

(set *urdr.canonical.max-frame* 4096)
(set *urdr.canonical.max-atom* 256)
(set *urdr.canonical.max-depth* 32)
(set *urdr.canonical.max-nodes* 256)
(set *urdr.canonical.max-integer-digits* 255)
(set *urdr.canonical.max-symbol* 64)

(define urdr.canonical.exact-natural-weights?
  N [] -> (= N 0)
  N [Weight | Weights] ->
    (if (>= N Weight)
        (urdr.canonical.exact-natural-weights?
          (- N Weight) Weights)
        (urdr.canonical.exact-natural-weights? N Weights)))

(define urdr.canonical.small-natural-bounded?
  N Limit Weights ->
    (if (number? N)
        (if (and (>= N 0) (<= N Limit))
            (urdr.canonical.exact-natural-weights? N Weights)
            false)
        false))

(define urdr.canonical.small-natural?
  N 255 ->
    (urdr.canonical.small-natural-bounded?
      N 255 [128 64 32 16 8 4 2 1])
  N 9999 ->
    (urdr.canonical.small-natural-bounded?
      N 9999 [8192 4096 2048 1024 512 256 128
              64 32 16 8 4 2 1])
  N Limit -> false)

(define urdr.canonical.digit?
  B -> (and (>= B 48) (<= B 57)))

(define urdr.canonical.byte?
  B -> (urdr.canonical.small-natural? B 255))

(define urdr.canonical.byte-list?
  [] -> true
  [B | Bs] -> (and (urdr.canonical.byte? B)
                   (urdr.canonical.byte-list? Bs))
  _ -> false)

(define urdr.canonical.reverse-onto
  [] Ys -> Ys
  [X | Xs] Ys -> (urdr.canonical.reverse-onto Xs [X | Ys])
  _ Ys -> [error improper-list])

(define urdr.canonical.rev
  Xs -> (urdr.canonical.reverse-onto Xs []))

(define urdr.canonical.scan-digits
  [B | Bs] Acc ->
    (urdr.canonical.scan-digits Bs [B | Acc])
    where (urdr.canonical.digit? B)
  Bs Acc -> [(urdr.canonical.rev Acc) Bs])

(define urdr.canonical.decimal-loop
  [] Limit TooLarge N -> [ok N]
  [D | Ds] Limit TooLarge N ->
    (let Next (+ (* N 10) (- D 48))
      (if (> Next Limit)
          [error TooLarge]
          (urdr.canonical.decimal-loop Ds Limit TooLarge Next))))

(define urdr.canonical.decimal
  [] Limit TooLarge LeadingZero -> [error length-colon]
  [48 | Ds] Limit TooLarge LeadingZero ->
    (if (= Ds [])
        [ok 0]
        [error LeadingZero])
  Ds Limit TooLarge LeadingZero ->
    (urdr.canonical.decimal-loop Ds Limit TooLarge 0))

(define urdr.canonical.take
  0 Bs Acc -> [ok (urdr.canonical.rev Acc) Bs]
  N [] Acc -> [error truncated]
  N [B | Bs] Acc -> (urdr.canonical.take (- N 1) Bs [B | Acc])
  _ _ _ -> [error improper-list])

\\ Generic RFC 9804 canonical atom/list parser.
(define urdr.canonical.node
  [] Depth Nodes -> [error csexp-truncated]
  [40 | Bs] Depth Nodes ->
    (if (> Depth (value *urdr.canonical.max-depth*))
        [error depth-too-large]
        (if (>= Nodes (value *urdr.canonical.max-nodes*))
            [error nodes-too-many]
            (urdr.canonical.node-list Bs Depth (+ Nodes 1) [])))
  [B | Bs] Depth Nodes ->
    (if (urdr.canonical.digit? B)
        (if (>= Nodes (value *urdr.canonical.max-nodes*))
            [error nodes-too-many]
            (urdr.canonical.node-atom [B | Bs] (+ Nodes 1)))
        [error csexp-token])
  _ Depth Nodes -> [error value-type])

(define urdr.canonical.node-list
  [] Depth Nodes Acc -> [error list-unclosed]
  [41 | Bs] Depth Nodes Acc ->
    [ok [urdr.canonical.list-node (urdr.canonical.rev Acc)] Bs Nodes]
  Bs Depth Nodes Acc ->
    (urdr.canonical.node-list-step
      (urdr.canonical.node Bs (+ Depth 1) Nodes) Depth Acc))

(define urdr.canonical.node-list-step
  [error E] Depth Acc -> [error E]
  [ok Node Rest Nodes] Depth Acc ->
    (urdr.canonical.node-list Rest Depth Nodes [Node | Acc]))

(define urdr.canonical.node-atom
  Bs Nodes ->
    (let Scan (urdr.canonical.scan-digits Bs [])
      (urdr.canonical.node-atom-digits
        (hd Scan) (hd (tl Scan)) Nodes)))

(define urdr.canonical.node-atom-digits
  Digits [58 | Bs] Nodes ->
    (urdr.canonical.node-atom-length
      (urdr.canonical.decimal
        Digits
        (value *urdr.canonical.max-atom*)
        atom-too-large
        length-leading-zero)
      Bs
      Nodes)
  Digits _ Nodes -> [error length-colon])

(define urdr.canonical.node-atom-length
  [error E] Bs Nodes -> [error E]
  [ok N] Bs Nodes ->
    (urdr.canonical.node-atom-take
      (urdr.canonical.take N Bs []) Nodes))

(define urdr.canonical.node-atom-take
  [error truncated] Nodes -> [error atom-truncated]
  [error E] Nodes -> [error E]
  [ok Atom Rest] Nodes ->
    [ok [urdr.canonical.atom-node Atom] Rest Nodes])

(define urdr.canonical.parse-payload
  Bs ->
    (if (urdr.canonical.byte-list? Bs)
        (urdr.canonical.parse-payload-result
          (urdr.canonical.node Bs 1 0))
        [error value-type]))

(define urdr.canonical.parse-payload-result
  [error E] -> [error E]
  [ok Node [] Nodes] -> [ok Node]
  [ok Node Rest Nodes] -> [error payload-trailing])

\\ Strict RFC 3629 shortest-form UTF-8 over Unicode scalar values.
(define urdr.canonical.continuation?
  B -> (and (>= B 128) (<= B 191)))

(define urdr.canonical.utf8?
  [] -> true
  [B | Bs] -> (urdr.canonical.utf8? Bs) where (<= B 127)
  [B C | Bs] -> (urdr.canonical.utf8? Bs)
    where (and (and (>= B 194) (<= B 223))
               (urdr.canonical.continuation? C))
  [224 C D | Bs] -> (urdr.canonical.utf8? Bs)
    where (and (and (>= C 160) (<= C 191))
               (urdr.canonical.continuation? D))
  [B C D | Bs] -> (urdr.canonical.utf8? Bs)
    where (and (and (>= B 225) (<= B 236))
               (and (urdr.canonical.continuation? C)
                    (urdr.canonical.continuation? D)))
  [237 C D | Bs] -> (urdr.canonical.utf8? Bs)
    where (and (and (>= C 128) (<= C 159))
               (urdr.canonical.continuation? D))
  [B C D | Bs] -> (urdr.canonical.utf8? Bs)
    where (and (and (>= B 238) (<= B 239))
               (and (urdr.canonical.continuation? C)
                    (urdr.canonical.continuation? D)))
  [240 C D E | Bs] -> (urdr.canonical.utf8? Bs)
    where (and (and (>= C 144) (<= C 191))
               (and (urdr.canonical.continuation? D)
                    (urdr.canonical.continuation? E)))
  [B C D E | Bs] -> (urdr.canonical.utf8? Bs)
    where (and (and (>= B 241) (<= B 243))
               (and (urdr.canonical.continuation? C)
                    (and (urdr.canonical.continuation? D)
                         (urdr.canonical.continuation? E))))
  [244 C D E | Bs] -> (urdr.canonical.utf8? Bs)
    where (and (and (>= C 128) (<= C 143))
               (and (urdr.canonical.continuation? D)
                    (urdr.canonical.continuation? E)))
  _ -> false)

(define urdr.canonical.symbol-rest?
  [] -> true
  [B | Bs] -> (urdr.canonical.symbol-rest? Bs)
    where (or (and (>= B 65) (<= B 90))
              (or (and (>= B 97) (<= B 122))
                  (or (and (>= B 48) (<= B 57))
                      (or (= B 46)
                          (or (= B 95)
                              (or (= B 47) (= B 45)))))))
  _ -> false)

(define urdr.canonical.symbol?
  [] -> false
  [B | Bs] ->
    (and (<= (+ 1 (length Bs))
             (value *urdr.canonical.max-symbol*))
         (and (or (and (>= B 65) (<= B 90))
                  (and (>= B 97) (<= B 122)))
              (urdr.canonical.symbol-rest? Bs)))
  _ -> false)

(define urdr.canonical.bytes-compare
  [] [] -> eq
  [] _ -> lt
  _ [] -> gt
  [A | As] [B | Bs] -> lt where (< A B)
  [A | As] [B | Bs] -> gt where (> A B)
  [A | As] [B | Bs] ->
    (urdr.canonical.bytes-compare As Bs))

\\ Exact bounded host arithmetic used only for base-10000 limbs.
(define urdr.canonical.small-divmod-loop
  N D Q ->
    (if (< N D)
        [Q N]
        (urdr.canonical.small-divmod-loop (- N D) D (+ Q 1))))

(define urdr.canonical.small-divmod
  N D -> (urdr.canonical.small-divmod-loop N D 0))

(define urdr.canonical.mag-mul10-add
  Limbs Digit ->
    (urdr.canonical.mag-mul10-add-loop Limbs Digit))

(define urdr.canonical.mag-mul10-add-loop
  [] 0 -> []
  [] Carry -> [Carry]
  [Limb | Limbs] Carry ->
    (let QR (urdr.canonical.small-divmod
              (+ (* Limb 10) Carry) 10000)
      [(hd (tl QR)) |
       (urdr.canonical.mag-mul10-add-loop Limbs (hd QR))]))

(define urdr.canonical.decimal-to-mag
  Digits -> (urdr.canonical.decimal-to-mag-loop Digits []))

(define urdr.canonical.decimal-to-mag-loop
  [] Magnitude -> Magnitude
  [D | Ds] Magnitude ->
    (urdr.canonical.decimal-to-mag-loop
      Ds
      (urdr.canonical.mag-mul10-add Magnitude (- D 48))))

(define urdr.canonical.all-digits?
  [] -> true
  [D | Ds] ->
    (and (urdr.canonical.digit? D)
         (urdr.canonical.all-digits? Ds))
  _ -> false)

\\ Parse canonical decimal octets directly to ADR 0003 integers.
(define urdr.canonical.int-parse
  Raw ->
    (if (urdr.canonical.byte-list? Raw)
        (urdr.canonical.int-parse-bytes Raw)
        [error value-type]))

(define urdr.canonical.int-parse-bytes
  [] -> [error integer-empty]
  [43 | Ds] -> [error integer-plus]
  [45] -> [error integer-empty]
  [45 | Ds] ->
    (if (> (length Ds)
           (value *urdr.canonical.max-integer-digits*))
        [error integer-too-large]
        (if (= Ds [48])
            [error integer-negative-zero]
            (urdr.canonical.int-digits Ds -1)))
  Ds ->
    (if (> (length Ds)
           (value *urdr.canonical.max-integer-digits*))
        [error integer-too-large]
        (urdr.canonical.int-digits Ds 1)))

(define urdr.canonical.int-digits
  [] Sign -> [error integer-empty]
  [48 | Ds] Sign ->
    (if (= Ds [])
        [ok [big 0 []]]
        [error integer-leading-zero])
  Ds Sign ->
    (if (urdr.canonical.all-digits? Ds)
        [ok [big Sign (urdr.canonical.decimal-to-mag Ds)]]
        [error integer-digit]))

(define urdr.canonical.mag-valid?
  [] -> false
  [D] ->
    (and (urdr.canonical.small-natural? D 9999)
         (not (= D 0)))
  [D | Ds] ->
    (and (urdr.canonical.small-natural? D 9999)
         (urdr.canonical.mag-valid? Ds))
  _ -> false)

(define urdr.canonical.big-valid?
  [big 0 []] -> true
  [big 1 Magnitude] -> (urdr.canonical.mag-valid? Magnitude)
  [big -1 Magnitude] -> (urdr.canonical.mag-valid? Magnitude)
  _ -> false)

(define urdr.canonical.decimal-byte
  0 -> 48
  1 -> 49
  2 -> 50
  3 -> 51
  4 -> 52
  5 -> 53
  6 -> 54
  7 -> 55
  8 -> 56
  9 -> 57)

(define urdr.canonical.decimal-limb4
  N ->
    (let A (urdr.canonical.small-divmod N 1000)
          B (urdr.canonical.small-divmod (hd (tl A)) 100)
          C (urdr.canonical.small-divmod (hd (tl B)) 10)
      [(urdr.canonical.decimal-byte (hd A))
       (urdr.canonical.decimal-byte (hd B))
       (urdr.canonical.decimal-byte (hd C))
       (urdr.canonical.decimal-byte (hd (tl C)))]))

(define urdr.canonical.drop-leading-zeroes
  [48 | Rest] -> (urdr.canonical.drop-leading-zeroes Rest)
  [] -> [48]
  Ds -> Ds)

(define urdr.canonical.limbs-bytes
  [] -> []
  [D | Ds] ->
    (append (urdr.canonical.decimal-limb4 D)
            (urdr.canonical.limbs-bytes Ds)))

(define urdr.canonical.mag-bytes
  Magnitude ->
    (let Rev (reverse Magnitude)
      (append
        (urdr.canonical.drop-leading-zeroes
          (urdr.canonical.decimal-limb4 (hd Rev)))
        (urdr.canonical.limbs-bytes (tl Rev)))))

(define urdr.canonical.int-render
  Big ->
    (if (urdr.canonical.big-valid? Big)
        (urdr.canonical.int-render-valid Big)
        [error integer-representation]))

(define urdr.canonical.int-render-valid
  [big 0 []] -> [ok [48]]
  [big 1 Magnitude] ->
    (urdr.canonical.int-render-magnitude
      (urdr.canonical.mag-bytes Magnitude) false)
  [big -1 Magnitude] ->
    (urdr.canonical.int-render-magnitude
      (urdr.canonical.mag-bytes Magnitude) true))

(define urdr.canonical.int-render-magnitude
  Magnitude Negative ->
    (if (> (length Magnitude)
           (value *urdr.canonical.max-integer-digits*))
        [error integer-too-large]
        [ok (if Negative [45 | Magnitude] Magnitude)]))

\\ Convert generic canonical nodes to typed Urdr values.
(define urdr.canonical.typed
  [urdr.canonical.list-node
    [[urdr.canonical.atom-node Tag] | Args]] ->
      (urdr.canonical.typed-tag Tag Args)
  _ -> [error typed-list])

(define urdr.canonical.typed-tag
  [110 117 108 108] [] -> [ok [null]]
  [110 117 108 108] _ -> [error typed-arity]
  [98 111 111 108]
    [[urdr.canonical.atom-node [116 114 117 101]]] ->
      [ok [bool true]]
  [98 111 111 108]
    [[urdr.canonical.atom-node [102 97 108 115 101]]] ->
      [ok [bool false]]
  [98 111 111 108] [[urdr.canonical.atom-node _]] ->
    [error bool-value]
  [98 111 111 108] _ -> [error typed-arity]
  [105 110 116] [[urdr.canonical.atom-node Raw]] ->
    (urdr.canonical.int-parse Raw)
  [105 110 116] _ -> [error typed-arity]
  [116 101 120 116] [[urdr.canonical.atom-node Raw]] ->
    (if (urdr.canonical.utf8? Raw)
        [ok [text Raw]]
        [error utf8-invalid])
  [116 101 120 116] _ -> [error typed-arity]
  [98 121 116 101 115] [[urdr.canonical.atom-node Raw]] ->
    [ok [bytes Raw]]
  [98 121 116 101 115] _ -> [error typed-arity]
  [115 121 109 98 111 108]
    [[urdr.canonical.atom-node Raw]] ->
      (if (> (length Raw) (value *urdr.canonical.max-symbol*))
          [error symbol-too-large]
          (if (urdr.canonical.symbol? Raw)
              [ok [symbol Raw]]
              [error symbol-invalid]))
  [115 121 109 98 111 108] _ -> [error typed-arity]
  [108 105 115 116] Items ->
    (urdr.canonical.typed-many Items [])
  [114 101 99 111 114 100] Entries ->
    (urdr.canonical.typed-record Entries none [])
  _ _ -> [error typed-tag])

(define urdr.canonical.typed-many
  [] Acc -> [ok [list (urdr.canonical.rev Acc)]]
  [Node | Nodes] Acc ->
    (urdr.canonical.typed-many-step
      (urdr.canonical.typed Node) Nodes Acc)
  _ Acc -> [error improper-list])

(define urdr.canonical.typed-many-step
  [error E] Nodes Acc -> [error E]
  [ok Value] Nodes Acc ->
    (urdr.canonical.typed-many Nodes [Value | Acc]))

(define urdr.canonical.typed-record
  [] Previous Acc -> [ok [record (urdr.canonical.rev Acc)]]
  [[urdr.canonical.list-node
    [[urdr.canonical.atom-node Key] Node]] | Entries]
    Previous Acc ->
      (if (> (length Key) (value *urdr.canonical.max-symbol*))
          [error symbol-too-large]
          (if (urdr.canonical.symbol? Key)
              (urdr.canonical.record-order
                Key Previous Node Entries Acc)
              [error symbol-invalid]))
  [_ | Entries] Previous Acc -> [error record-entry]
  _ Previous Acc -> [error improper-list])

(define urdr.canonical.record-order
  Key none Node Entries Acc ->
    (urdr.canonical.typed-record-value
      (urdr.canonical.typed Node) Key Entries Acc)
  Key Previous Node Entries Acc ->
    (let Order (urdr.canonical.bytes-compare Key Previous)
      (if (= Order eq)
          [error record-duplicate]
          (if (= Order lt)
              [error record-order]
              (urdr.canonical.typed-record-value
                (urdr.canonical.typed Node) Key Entries Acc)))))

(define urdr.canonical.typed-record-value
  [error E] Key Entries Acc -> [error E]
  [ok Value] Key Entries Acc ->
    (urdr.canonical.typed-record
      Entries Key [[Key Value] | Acc]))

(define urdr.canonical.decode-payload
  Bs ->
    (urdr.canonical.decode-node
      (urdr.canonical.parse-payload Bs)))

(define urdr.canonical.decode-node
  [error E] -> [error E]
  [ok Node] -> (urdr.canonical.typed Node))

\\ Byte-counted netstring outer stream.
(define urdr.canonical.frame-length
  Bs ->
    (let Scan (urdr.canonical.scan-digits Bs [])
      (urdr.canonical.frame-length-scan
        (hd Scan) (hd (tl Scan)))))

(define urdr.canonical.frame-length-scan
  [] Rest -> [error frame-length]
  Digits [] ->
    (if (> (length Digits)
           (length
             (urdr.canonical.number-bytes
               (value *urdr.canonical.max-frame*))))
        [error frame-length]
        [need])
  Digits [58 | Rest] ->
    (urdr.canonical.frame-length-value
      (urdr.canonical.decimal
        Digits
        (value *urdr.canonical.max-frame*)
        frame-too-large
        frame-leading-zero)
      Rest)
  Digits _ -> [error frame-length])

(define urdr.canonical.frame-length-value
  [error E] Rest -> [error E]
  [ok N] Rest -> [ok N Rest])

(define urdr.canonical.frame-one
  [] -> [need]
  [B | Bs] -> [error frame-length]
    where (not (urdr.canonical.digit? B))
  Bs ->
    (urdr.canonical.frame-body
      (urdr.canonical.frame-length Bs)))

(define urdr.canonical.frame-body
  [need] -> [need]
  [error E] -> [error E]
  [ok N Rest] ->
    (urdr.canonical.frame-body-take
      (urdr.canonical.take N Rest [])))

(define urdr.canonical.frame-body-take
  [error truncated] -> [need]
  [error E] -> [error E]
  [ok Body []] -> [need]
  [ok Body [44 | Rest]] ->
    (urdr.canonical.frame-body-value
      (urdr.canonical.decode-payload Body) Rest)
  [ok Body _] -> [error frame-comma])

(define urdr.canonical.frame-body-value
  [error E] Rest -> [error E]
  [ok Value] Rest -> [ok Value Rest])

(define urdr.canonical.decode-frame
  Bs ->
    (if (urdr.canonical.byte-list? Bs)
        (urdr.canonical.decode-frame-result
          (urdr.canonical.frame-one Bs))
        [error value-type]))

(define urdr.canonical.decode-frame-result
  [need] -> [error frame-truncated]
  [error E] -> [error E]
  [ok Value []] -> [ok Value]
  [ok Value Rest] -> [error frame-trailing])

(define urdr.canonical.string-bytes
  S -> (urdr.canonical.chars-bytes (explode S)))

(define urdr.canonical.chars-bytes
  [] -> []
  [C | Cs] ->
    [(string->n C) | (urdr.canonical.chars-bytes Cs)])

(define urdr.canonical.number-bytes
  N -> (urdr.canonical.string-bytes (str N)))

(define urdr.canonical.atom
  Bs ->
    (if (not (urdr.canonical.byte-list? Bs))
        [error value-type]
        (if (> (length Bs) (value *urdr.canonical.max-atom*))
            [error atom-too-large]
            [ok
              (append
                (urdr.canonical.number-bytes (length Bs))
                [58 | Bs])])))

\\ Typed encoder. The completed payload is reparsed before return so the
\\ decoder's exact list-depth and RFC-node budgets are also encoder limits.
(define urdr.canonical.enc
  Value Depth TypedNodes ->
    (if (> Depth (value *urdr.canonical.max-depth*))
        [error depth-too-large]
        (if (>= TypedNodes (value *urdr.canonical.max-nodes*))
            [error nodes-too-many]
            (urdr.canonical.enc-value
              Value Depth (+ TypedNodes 1)))))

(define urdr.canonical.enc-value
  [null] Depth Nodes ->
    [ok [40 52 58 110 117 108 108 41] Nodes]
  [bool true] Depth Nodes ->
    [ok
      [40 52 58 98 111 111 108
       52 58 116 114 117 101 41]
      Nodes]
  [bool false] Depth Nodes ->
    [ok
      [40 52 58 98 111 111 108
       53 58 102 97 108 115 101 41]
      Nodes]
  [bool _] Depth Nodes -> [error bool-value]
  [big Sign Magnitude] Depth Nodes ->
    (urdr.canonical.enc-int
      (urdr.canonical.int-render [big Sign Magnitude]) Nodes)
  [text Bs] Depth Nodes ->
    (if (not (urdr.canonical.byte-list? Bs))
        [error value-type]
        (if (urdr.canonical.utf8? Bs)
            (urdr.canonical.enc-tagged
              [116 101 120 116] Bs Nodes)
            [error utf8-invalid]))
  [bytes Bs] Depth Nodes ->
    (if (urdr.canonical.byte-list? Bs)
        (urdr.canonical.enc-tagged
          [98 121 116 101 115] Bs Nodes)
        [error value-type])
  [symbol Bs] Depth Nodes ->
    (if (not (urdr.canonical.byte-list? Bs))
        [error value-type]
        (if (> (length Bs) (value *urdr.canonical.max-symbol*))
            [error symbol-too-large]
            (if (urdr.canonical.symbol? Bs)
                (urdr.canonical.enc-tagged
                  [115 121 109 98 111 108] Bs Nodes)
                [error symbol-invalid])))
  [list Values] Depth Nodes ->
    (urdr.canonical.enc-list Values Depth Nodes)
  [record Fields] Depth Nodes ->
    (urdr.canonical.enc-record
      Fields Depth Nodes none [])
  _ Depth Nodes -> [error value-type])

(define urdr.canonical.enc-int
  [error E] Nodes -> [error E]
  [ok Raw] Nodes ->
    (urdr.canonical.enc-tagged [105 110 116] Raw Nodes))

(define urdr.canonical.enc-tagged
  Tag Raw Nodes ->
    (urdr.canonical.enc-tagged-atoms
      (urdr.canonical.atom Tag)
      (urdr.canonical.atom Raw)
      Nodes))

(define urdr.canonical.enc-tagged-atoms
  [error E] B Nodes -> [error E]
  A [error E] Nodes -> [error E]
  [ok A] [ok B] Nodes ->
    [ok (append [40] (append A (append B [41]))) Nodes])

(define urdr.canonical.enc-list
  Values Depth Nodes ->
    (urdr.canonical.enc-list-values
      (urdr.canonical.enc-many
        Values (+ Depth 1) Nodes [])))

(define urdr.canonical.enc-list-values
  [error E] -> [error E]
  [ok Body NewNodes] ->
    [ok
      (append
        [40 52 58 108 105 115 116]
        (append Body [41]))
      NewNodes])

(define urdr.canonical.enc-many
  [] Depth Nodes Acc ->
    [ok (urdr.canonical.rev Acc) Nodes]
  [Value | Values] Depth Nodes Acc ->
    (urdr.canonical.enc-many-step
      (urdr.canonical.enc Value Depth Nodes)
      Values
      Depth
      Acc)
  _ Depth Nodes Acc -> [error improper-list])

(define urdr.canonical.enc-many-step
  [error E] Values Depth Acc -> [error E]
  [ok Bytes Nodes] Values Depth Acc ->
    (urdr.canonical.enc-many
      Values
      Depth
      Nodes
      (urdr.canonical.reverse-onto Bytes Acc)))

(define urdr.canonical.enc-record
  [] Depth Nodes Previous Acc ->
    [ok
      (append
        [40 54 58 114 101 99 111 114 100]
        (append (urdr.canonical.rev Acc) [41]))
      Nodes]
  [[Key Value] | Fields] Depth Nodes Previous Acc ->
    (if (not (urdr.canonical.byte-list? Key))
        [error value-type]
        (if (> (length Key) (value *urdr.canonical.max-symbol*))
            [error symbol-too-large]
            (if (urdr.canonical.symbol? Key)
                (urdr.canonical.enc-record-order
                  Key Value Fields Depth Nodes Previous Acc)
                [error symbol-invalid])))
  [_ | Fields] Depth Nodes Previous Acc -> [error record-entry]
  _ Depth Nodes Previous Acc -> [error improper-list])

(define urdr.canonical.enc-record-order
  Key Value Fields Depth Nodes none Acc ->
    (urdr.canonical.enc-record-value
      (urdr.canonical.atom Key)
      Key Value Fields Depth Nodes Acc)
  Key Value Fields Depth Nodes Previous Acc ->
    (let Order (urdr.canonical.bytes-compare Key Previous)
      (if (= Order eq)
          [error record-duplicate]
          (if (= Order lt)
              [error record-order]
              (urdr.canonical.enc-record-value
                (urdr.canonical.atom Key)
                Key Value Fields Depth Nodes Acc)))))

(define urdr.canonical.enc-record-value
  [error E] Key Value Fields Depth Nodes Acc -> [error E]
  [ok KeyAtom] Key Value Fields Depth Nodes Acc ->
    (urdr.canonical.enc-record-entry
      (urdr.canonical.enc Value (+ Depth 1) Nodes)
      KeyAtom Key Fields Depth Acc))

(define urdr.canonical.enc-record-entry
  [error E] KeyAtom Key Fields Depth Acc -> [error E]
  [ok ValueBytes Nodes] KeyAtom Key Fields Depth Acc ->
    (let Entry
      (append [40] (append KeyAtom (append ValueBytes [41])))
      (urdr.canonical.enc-record
        Fields
        Depth
        Nodes
        Key
        (urdr.canonical.reverse-onto Entry Acc))))

(define urdr.canonical.encode-payload
  Value ->
    (urdr.canonical.encode-payload-result
      (urdr.canonical.enc Value 1 0)))

(define urdr.canonical.encode-payload-result
  [error E] -> [error E]
  [ok Bytes Nodes] ->
    (if (> (length Bytes) (value *urdr.canonical.max-frame*))
        [error frame-too-large]
        (urdr.canonical.encode-payload-reparse
          Bytes
          (urdr.canonical.parse-payload Bytes))))

(define urdr.canonical.encode-payload-reparse
  Bytes [error E] -> [error E]
  Bytes [ok Node] -> [ok Bytes])

(define urdr.canonical.encode-frame
  Value ->
    (urdr.canonical.encode-frame-payload
      (urdr.canonical.encode-payload Value)))

(define urdr.canonical.encode-frame-payload
  [error E] -> [error E]
  [ok Payload] ->
    [ok
      (append
        (urdr.canonical.number-bytes (length Payload))
        [58 | (append Payload [44])])])

\\ Incremental stream state is [urdr.canonical.stream buffered-octets].
(define urdr.canonical.stream-new
  -> [urdr.canonical.stream []])

(define urdr.canonical.stream-feed
  [urdr.canonical.stream Buffer] Chunk ->
    (if (not (urdr.canonical.byte-list? Buffer))
        [error stream-state]
        (if (urdr.canonical.byte-list? Chunk)
            (urdr.canonical.stream-drain
              (append Buffer Chunk) [])
            [error chunk-type]))
  _ Chunk -> [error stream-state])

(define urdr.canonical.stream-drain
  Buffer Acc ->
    (urdr.canonical.stream-drain-result
      (urdr.canonical.frame-one Buffer) Buffer Acc))

(define urdr.canonical.stream-drain-result
  [need] Buffer Acc ->
    [ok
      [urdr.canonical.stream Buffer]
      (urdr.canonical.rev Acc)]
  [error E] Buffer Acc -> [error E]
  [ok Value Rest] Buffer Acc ->
    (urdr.canonical.stream-drain Rest [Value | Acc]))

(define urdr.canonical.stream-finish
  [urdr.canonical.stream []] -> [ok]
  [urdr.canonical.stream Buffer] ->
    (if (urdr.canonical.byte-list? Buffer)
        [error frame-truncated]
        [error stream-state])
  _ -> [error stream-state])
