\\ Portable Shen prototype. Octets are lists of integers in [0,255].
\\ Public results are [ok Value] or [error stable-code].

(set *cr-max-frame* 4096)
(set *cr-max-atom* 256)
(set *cr-max-depth* 32)
(set *cr-max-nodes* 256)
(set *cr-max-integer-digits* 255)
(set *cr-max-symbol* 64)

(define cr-digit?
  B -> (and (>= B 48) (<= B 57)))

(define cr-byte?
  B -> (and (number? B) (and (>= B 0) (<= B 255))))

(define cr-byte-list?
  [] -> true
  [B | Bs] -> (and (cr-byte? B) (cr-byte-list? Bs))
  _ -> false)

(define cr-reverse-onto
  [] Ys -> Ys
  [X | Xs] Ys -> (cr-reverse-onto Xs [X | Ys]))

(define cr-rev
  Xs -> (cr-reverse-onto Xs []))

(define cr-scan-digits
  [B | Bs] Acc -> (cr-scan-digits Bs [B | Acc]) where (cr-digit? B)
  Bs Acc -> [(cr-rev Acc) Bs])

(define cr-decimal-loop
  [] Limit TooLarge N -> [ok N]
  [D | Ds] Limit TooLarge N ->
    (let Next (+ (* N 10) (- D 48))
      (if (> Next Limit)
          [error TooLarge]
          (cr-decimal-loop Ds Limit TooLarge Next))))

(define cr-decimal
  [] Limit TooLarge LeadingZero -> [error length-colon]
  [48 | Ds] Limit TooLarge LeadingZero ->
    (if (= Ds [])
        [ok 0]
        [error LeadingZero])
  Ds Limit TooLarge LeadingZero -> (cr-decimal-loop Ds Limit TooLarge 0))

(define cr-take
  0 Bs Acc -> [ok (cr-rev Acc) Bs]
  N [] Acc -> [error truncated]
  N [B | Bs] Acc -> (cr-take (- N 1) Bs [B | Acc]))

(define cr-node
  [] Depth Nodes -> [error csexp-truncated]
  [40 | Bs] Depth Nodes ->
    (if (> Depth (value *cr-max-depth*))
        [error depth-too-large]
        (if (>= Nodes (value *cr-max-nodes*))
            [error nodes-too-many]
            (cr-node-list Bs Depth (+ Nodes 1) [])))
  [B | Bs] Depth Nodes ->
    (if (cr-digit? B)
        (if (>= Nodes (value *cr-max-nodes*))
            [error nodes-too-many]
            (cr-node-atom [B | Bs] (+ Nodes 1)))
        [error csexp-token]))

(define cr-node-list
  [] Depth Nodes Acc -> [error list-unclosed]
  [41 | Bs] Depth Nodes Acc -> [ok [l (cr-rev Acc)] Bs Nodes]
  Bs Depth Nodes Acc ->
    (cr-node-list-step (cr-node Bs (+ Depth 1) Nodes) Depth Acc))

(define cr-node-list-step
  [error E] Depth Acc -> [error E]
  [ok Node Rest Nodes] Depth Acc -> (cr-node-list Rest Depth Nodes [Node | Acc]))

(define cr-node-atom
  Bs Nodes ->
    (let Scan (cr-scan-digits Bs [])
      (cr-node-atom-digits (hd Scan) (hd (tl Scan)) Nodes)))

(define cr-node-atom-digits
  Digits [58 | Bs] Nodes ->
    (cr-node-atom-length
      (cr-decimal Digits (value *cr-max-atom*) atom-too-large length-leading-zero)
      Bs Nodes)
  Digits _ Nodes -> [error length-colon])

(define cr-node-atom-length
  [error E] Bs Nodes -> [error E]
  [ok N] Bs Nodes -> (cr-node-atom-take (cr-take N Bs []) Nodes))

(define cr-node-atom-take
  [error truncated] Nodes -> [error atom-truncated]
  [ok Atom Rest] Nodes -> [ok [a Atom] Rest Nodes])

(define cr-parse-payload
  Bs -> (cr-parse-payload-result (cr-node Bs 1 0)))

(define cr-parse-payload-result
  [error E] -> [error E]
  [ok Node [] Nodes] -> [ok Node]
  [ok Node Rest Nodes] -> [error payload-trailing])

(define cr-cont?
  B -> (and (>= B 128) (<= B 191)))

(define cr-utf8
  [] -> true
  [B | Bs] -> (cr-utf8 Bs) where (<= B 127)
  [B C | Bs] -> (cr-utf8 Bs)
    where (and (and (>= B 194) (<= B 223)) (cr-cont? C))
  [224 C D | Bs] -> (cr-utf8 Bs)
    where (and (and (>= C 160) (<= C 191)) (cr-cont? D))
  [B C D | Bs] -> (cr-utf8 Bs)
    where (and (and (>= B 225) (<= B 236))
               (and (cr-cont? C) (cr-cont? D)))
  [237 C D | Bs] -> (cr-utf8 Bs)
    where (and (and (>= C 128) (<= C 159)) (cr-cont? D))
  [B C D | Bs] -> (cr-utf8 Bs)
    where (and (and (>= B 238) (<= B 239))
               (and (cr-cont? C) (cr-cont? D)))
  [240 C D E | Bs] -> (cr-utf8 Bs)
    where (and (and (>= C 144) (<= C 191))
               (and (cr-cont? D) (cr-cont? E)))
  [B C D E | Bs] -> (cr-utf8 Bs)
    where (and (and (>= B 241) (<= B 243))
               (and (cr-cont? C) (and (cr-cont? D) (cr-cont? E))))
  [244 C D E | Bs] -> (cr-utf8 Bs)
    where (and (and (>= C 128) (<= C 143))
               (and (cr-cont? D) (cr-cont? E)))
  _ -> false)

(define cr-symbol-rest?
  [] -> true
  [B | Bs] -> (cr-symbol-rest? Bs)
    where (or (and (>= B 65) (<= B 90))
              (or (and (>= B 97) (<= B 122))
                  (or (and (>= B 48) (<= B 57))
                      (or (= B 46) (or (= B 95) (or (= B 47) (= B 45)))))))
  _ -> false)

(define cr-symbol?
  [] -> false
  [B | Bs] ->
    (and (<= (+ 1 (length Bs)) (value *cr-max-symbol*))
         (and (or (and (>= B 65) (<= B 90))
                  (and (>= B 97) (<= B 122)))
              (cr-symbol-rest? Bs)))
  _ -> false)

(define cr-bytes-compare
  [] [] -> eq
  [] _ -> lt
  _ [] -> gt
  [A | As] [B | Bs] -> lt where (< A B)
  [A | As] [B | Bs] -> gt where (> A B)
  [A | As] [B | Bs] -> (cr-bytes-compare As Bs))

\\ Software integer interface. No host integer conversion occurs.
(define cr-int-parse
  Raw ->
    (if (cr-byte-list? Raw)
        (cr-int-parse-bytes Raw)
        [error value-type]))

(define cr-int-parse-bytes
  [] -> [error integer-empty]
  [43 | Ds] -> [error integer-plus]
  [45] -> [error integer-empty]
  [45 | Ds] ->
    (if (> (length Ds) (value *cr-max-integer-digits*))
        [error integer-too-large]
        (if (= Ds [48])
            [error integer-negative-zero]
            (cr-int-digits Ds negative)))
  Ds ->
    (if (> (length Ds) (value *cr-max-integer-digits*))
        [error integer-too-large]
        (cr-int-digits Ds positive)))

(define cr-int-digits
  [] Sign -> [error integer-empty]
  [48 | Ds] Sign ->
    (if (= Ds [])
        [ok [int Sign [48]]]
        [error integer-leading-zero])
  Ds Sign ->
    (if (cr-all-digits? Ds)
        [ok [int Sign Ds]]
        [error integer-digit]))

(define cr-all-digits?
  [] -> true
  [D | Ds] -> (and (cr-digit? D) (cr-all-digits? Ds))
  _ -> false)

(define cr-int-render
  [int positive Ds] -> (cr-int-render-positive (cr-int-parse Ds))
  [int negative Ds] -> (cr-int-render-negative (cr-int-parse [45 | Ds]))
  _ -> [error value-type])

(define cr-int-render-positive
  [ok [int positive Ds]] -> [ok Ds]
  [error E] -> [error E]
  _ -> [error value-type])

(define cr-int-render-negative
  [ok [int negative Ds]] -> [ok [45 | Ds]]
  [error E] -> [error E]
  _ -> [error value-type])

(define cr-typed
  [l [[a Tag] | Args]] -> (cr-typed-tag Tag Args)
  _ -> [error typed-list])

(define cr-typed-tag
  [110 117 108 108] [] -> [ok [null]]
  [110 117 108 108] _ -> [error typed-arity]
  [98 111 111 108] [[a [116 114 117 101]]] -> [ok [bool true]]
  [98 111 111 108] [[a [102 97 108 115 101]]] -> [ok [bool false]]
  [98 111 111 108] [[a _]] -> [error bool-value]
  [98 111 111 108] _ -> [error typed-arity]
  [105 110 116] [[a Raw]] -> (cr-int-parse Raw)
  [105 110 116] _ -> [error typed-arity]
  [116 101 120 116] [[a Raw]] ->
    (if (cr-utf8 Raw) [ok [text Raw]] [error utf8-invalid])
  [116 101 120 116] _ -> [error typed-arity]
  [98 121 116 101 115] [[a Raw]] -> [ok [bytes Raw]]
  [98 121 116 101 115] _ -> [error typed-arity]
  [115 121 109 98 111 108] [[a Raw]] ->
    (if (> (length Raw) (value *cr-max-symbol*))
        [error symbol-too-large]
        (if (cr-symbol? Raw)
            [ok [symbol Raw]]
            [error symbol-invalid]))
  [115 121 109 98 111 108] _ -> [error typed-arity]
  [108 105 115 116] Items -> (cr-typed-many Items [])
  [114 101 99 111 114 100] Entries -> (cr-typed-record Entries none [])
  _ _ -> [error typed-tag])

(define cr-typed-many
  [] Acc -> [ok [list (cr-rev Acc)]]
  [Node | Nodes] Acc -> (cr-typed-many-step (cr-typed Node) Nodes Acc)
  _ Acc -> [error improper-list])

(define cr-typed-many-step
  [error E] Nodes Acc -> [error E]
  [ok Value] Nodes Acc -> (cr-typed-many Nodes [Value | Acc]))

(define cr-typed-record
  [] Prev Acc -> [ok [record (cr-rev Acc)]]
  [[l [[a Key] Node]] | Entries] Prev Acc ->
    (if (> (length Key) (value *cr-max-symbol*))
        [error symbol-too-large]
        (if (cr-symbol? Key)
            (cr-record-order Key Prev Node Entries Acc)
            [error symbol-invalid]))
  [_ | Entries] Prev Acc -> [error record-entry]
  _ Prev Acc -> [error improper-list])

(define cr-record-order
  Key none Node Entries Acc -> (cr-typed-record-value (cr-typed Node) Key Entries Acc)
  Key Prev Node Entries Acc ->
    (let Order (cr-bytes-compare Key Prev)
      (if (= Order eq)
          [error record-duplicate]
          (if (= Order lt)
              [error record-order]
              (cr-typed-record-value (cr-typed Node) Key Entries Acc)))))

(define cr-typed-record-value
  [error E] Key Entries Acc -> [error E]
  [ok Value] Key Entries Acc -> (cr-typed-record Entries Key [[Key Value] | Acc]))

(define cr-decode-payload
  Bs -> (cr-decode-node (cr-parse-payload Bs)))

(define cr-decode-node
  [error E] -> [error E]
  [ok Node] -> (cr-typed Node))

(define cr-frame-length
  Bs ->
    (let Scan (cr-scan-digits Bs [])
      (cr-frame-length-scan (hd Scan) (hd (tl Scan)))))

(define cr-frame-length-scan
  [] Rest -> [error frame-length]
  Digits [] ->
    (if (> (length Digits) (length (cr-number-bytes (value *cr-max-frame*))))
        [error frame-length]
        [need])
  Digits [58 | Rest] ->
    (cr-frame-length-value
      (cr-decimal Digits (value *cr-max-frame*) frame-too-large frame-leading-zero)
      Rest)
  Digits _ -> [error frame-length])

(define cr-frame-length-value
  [error E] Rest -> [error E]
  [ok N] Rest -> [ok N Rest])

(define cr-frame-one
  [] -> [need]
  [B | Bs] -> [error frame-length] where (not (cr-digit? B))
  Bs -> (cr-frame-body (cr-frame-length Bs)))

(define cr-frame-body
  [need] -> [need]
  [error E] -> [error E]
  [ok N Rest] -> (cr-frame-body-take (cr-take N Rest [])))

(define cr-frame-body-take
  [error truncated] -> [need]
  [ok Body []] -> [need]
  [ok Body [44 | Rest]] -> (cr-frame-body-value (cr-decode-payload Body) Rest)
  [ok Body _] -> [error frame-comma])

(define cr-frame-body-value
  [error E] Rest -> [error E]
  [ok Value] Rest -> [ok Value Rest])

(define cr-decode-frame
  Bs ->
    (if (cr-byte-list? Bs)
        (cr-decode-frame-result (cr-frame-one Bs))
        [error value-type]))

(define cr-decode-frame-result
  [need] -> [error frame-truncated]
  [error E] -> [error E]
  [ok Value []] -> [ok Value]
  [ok Value Rest] -> [error frame-trailing])

(define cr-string-bytes
  S -> (cr-chars-bytes (explode S)))

(define cr-chars-bytes
  [] -> []
  [C | Cs] -> [(string->n C) | (cr-chars-bytes Cs)])

(define cr-number-bytes
  N -> (cr-string-bytes (str N)))

(define cr-atom
  Bs ->
    (if (not (cr-byte-list? Bs))
        [error value-type]
        (if (> (length Bs) (value *cr-max-atom*))
            [error atom-too-large]
            [ok (append (cr-number-bytes (length Bs)) [58 | Bs])])))

(define cr-enc
  Value Depth Nodes ->
    (if (> Depth (value *cr-max-depth*))
        [error depth-too-large]
        (if (>= Nodes (value *cr-max-nodes*))
            [error nodes-too-many]
            (cr-enc-value Value Depth (+ Nodes 1)))))

(define cr-enc-value
  [null] Depth Nodes -> [ok [40 52 58 110 117 108 108 41] Nodes]
  [bool true] Depth Nodes -> [ok [40 52 58 98 111 111 108 52 58 116 114 117 101 41] Nodes]
  [bool false] Depth Nodes -> [ok [40 52 58 98 111 111 108 53 58 102 97 108 115 101 41] Nodes]
  [bool _] Depth Nodes -> [error bool-value]
  [int Sign Ds] Depth Nodes ->
    (cr-enc-int (cr-int-render [int Sign Ds]) Nodes)
  [text Bs] Depth Nodes ->
    (if (not (cr-byte-list? Bs))
        [error value-type]
        (if (cr-utf8 Bs)
            (cr-enc-tagged [116 101 120 116] Bs Nodes)
            [error utf8-invalid]))
  [bytes Bs] Depth Nodes ->
    (if (cr-byte-list? Bs)
        (cr-enc-tagged [98 121 116 101 115] Bs Nodes)
        [error value-type])
  [symbol Bs] Depth Nodes ->
    (if (not (cr-byte-list? Bs))
        [error value-type]
        (if (> (length Bs) (value *cr-max-symbol*))
            [error symbol-too-large]
            (if (cr-symbol? Bs)
                (cr-enc-tagged [115 121 109 98 111 108] Bs Nodes)
                [error symbol-invalid])))
  [list Values] Depth Nodes -> (cr-enc-list Values Depth Nodes)
  [record Fields] Depth Nodes -> (cr-enc-record Fields Depth Nodes none [])
  _ Depth Nodes -> [error value-type])

(define cr-enc-int
  [error E] Nodes -> [error E]
  [ok Raw] Nodes -> (cr-enc-tagged [105 110 116] Raw Nodes))

(define cr-enc-tagged
  Tag Raw Nodes ->
    (cr-enc-tagged-atoms (cr-atom Tag) (cr-atom Raw) Nodes))

(define cr-enc-tagged-atoms
  [error E] B Nodes -> [error E]
  A [error E] Nodes -> [error E]
  [ok A] [ok B] Nodes -> [ok (append [40] (append A (append B [41]))) Nodes])

(define cr-enc-list
  Values Depth Nodes ->
    (cr-enc-list-values (cr-enc-many Values (+ Depth 1) Nodes []) Nodes))

(define cr-enc-list-values
  [error E] Nodes -> [error E]
  [ok Body NewNodes] Nodes ->
    [ok (append [40 52 58 108 105 115 116] (append Body [41])) NewNodes])

(define cr-enc-many
  [] Depth Nodes Acc -> [ok (cr-rev Acc) Nodes]
  [V | Vs] Depth Nodes Acc -> (cr-enc-many-step (cr-enc V Depth Nodes) Vs Depth Acc)
  _ Depth Nodes Acc -> [error improper-list])

(define cr-enc-many-step
  [error E] Vs Depth Acc -> [error E]
  [ok Bytes Nodes] Vs Depth Acc ->
    (cr-enc-many Vs Depth Nodes (cr-reverse-onto Bytes Acc)))

(define cr-enc-record
  [] Depth Nodes Prev Acc ->
    [ok (append [40 54 58 114 101 99 111 114 100] (append (cr-rev Acc) [41])) Nodes]
  [[Key Value] | Fields] Depth Nodes Prev Acc ->
    (if (not (cr-byte-list? Key))
        [error value-type]
        (if (> (length Key) (value *cr-max-symbol*))
            [error symbol-too-large]
            (if (cr-symbol? Key)
                (cr-enc-record-order Key Value Fields Depth Nodes Prev Acc)
                [error symbol-invalid])))
  [_ | Fields] Depth Nodes Prev Acc -> [error record-entry]
  _ Depth Nodes Prev Acc -> [error improper-list])

(define cr-enc-record-order
  Key Value Fields Depth Nodes none Acc ->
    (cr-enc-record-value (cr-atom Key) Key Value Fields Depth Nodes Acc)
  Key Value Fields Depth Nodes Prev Acc ->
    (let Order (cr-bytes-compare Key Prev)
      (if (= Order eq)
          [error record-duplicate]
          (if (= Order lt)
              [error record-order]
              (cr-enc-record-value (cr-atom Key) Key Value Fields Depth Nodes Acc)))))

(define cr-enc-record-value
  [error E] Key Value Fields Depth Nodes Acc -> [error E]
  [ok KeyAtom] Key Value Fields Depth Nodes Acc ->
    (cr-enc-record-entry (cr-enc Value (+ Depth 1) Nodes)
                         KeyAtom Key Fields Depth Acc))

(define cr-enc-record-entry
  [error E] KeyAtom Key Fields Depth Acc -> [error E]
  [ok ValueBytes Nodes] KeyAtom Key Fields Depth Acc ->
    (let Entry (append [40] (append KeyAtom (append ValueBytes [41])))
      (cr-enc-record Fields Depth Nodes Key (cr-reverse-onto Entry Acc))))

(define cr-encode-payload
  Value -> (cr-encode-payload-result (cr-enc Value 1 0)))

(define cr-encode-payload-result
  [error E] -> [error E]
  [ok Bytes Nodes] ->
    (if (> (length Bytes) (value *cr-max-frame*))
        [error frame-too-large]
        [ok Bytes]))

(define cr-encode-frame
  Value -> (cr-encode-frame-payload (cr-encode-payload Value)))

(define cr-encode-frame-payload
  [error E] -> [error E]
  [ok Payload] ->
    [ok (append (cr-number-bytes (length Payload)) [58 | (append Payload [44])])])

\\ Incremental netstring stream. A state is [stream buffered-octets].
(define cr-stream-new
  -> [stream []])

(define cr-stream-feed
  [stream Buffer] Chunk ->
    (if (cr-byte-list? Chunk)
        (cr-stream-drain (append Buffer Chunk) [])
        [error chunk-type])
  _ Chunk -> [error stream-state])

(define cr-stream-drain
  Buffer Acc -> (cr-stream-drain-result (cr-frame-one Buffer) Buffer Acc))

(define cr-stream-drain-result
  [need] Buffer Acc -> [ok [stream Buffer] (cr-rev Acc)]
  [error E] Buffer Acc -> [error E]
  [ok Value Rest] Buffer Acc -> (cr-stream-drain Rest [Value | Acc]))

(define cr-stream-finish
  [stream []] -> [ok]
  [stream _] -> [error frame-truncated]
  _ -> [error stream-state])
