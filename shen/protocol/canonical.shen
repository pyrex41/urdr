\\ Urdr canonical values and netstring framing (ADR 0002, ADR 0005).
\\ Octets are proper lists of exact host integers in [0,255].
\\ Integers use ADR 0003 values: [big SIGN LITTLE-ENDIAN-BASE-10000-LIMBS].
\\ Public operations return [ok ...] or [error stable-code].
\\
\\ Resource limits are carried by an explicit profile value (ADR 0005).
\\ There is no ambient or mutable profile state: every parse/encode entry
\\ point takes exactly one profile, and each surface names its profile
\\ statically. The historical entry points keep their ADR 0002 names,
\\ arities, and behavior by delegating to canonical-profile/m0.

\\ ---------------------------------------------------------------------
\\ Resource profiles (ADR 0005).
\\
\\ A profile is the canonical record
\\
\\   [urdr.canonical.profile NAME MAX-FRAME MAX-ATOM MAX-DEPTH
\\                           MAX-NODES MAX-INTEGER-DIGITS MAX-SYMBOL]
\\
\\ NAME is the ADR 0005 profile name and is diagnostic only: no decision
\\ anywhere in this module reads it, so a profile is fully described by
\\ its bounds. Profiles are never selected by input content.
\\ ---------------------------------------------------------------------

\\ ADR 0002 M0 profile, byte for byte: 4,096 payload octets, 256-octet
\\ atoms, 32 nested lists, 256 parsed nodes, 255 integer digits,
\\ 64-octet symbols.
(define urdr.canonical.profile.m0
  -> [urdr.canonical.profile
       canonical-profile/m0 4096 256 32 256 255 64])

\\ ADR 0005 M1 profile: 65,536 payload octets, 8,192 parsed nodes, 64
\\ nested lists. Atom, integer-digit, and symbol bounds are unchanged
\\ from ADR 0002.
(define urdr.canonical.profile.m1-large
  -> [urdr.canonical.profile
       canonical-profile/m1-large 65536 256 64 8192 255 64])

(define urdr.canonical.profile?
  [urdr.canonical.profile Name Frame Atom Depth Nodes Digits Symbol]
    -> true
  _ -> false)

(define urdr.canonical.profile-name
  [urdr.canonical.profile Name Frame Atom Depth Nodes Digits Symbol]
    -> Name)

(define urdr.canonical.profile-max-frame
  [urdr.canonical.profile Name Frame Atom Depth Nodes Digits Symbol]
    -> Frame)

(define urdr.canonical.profile-max-atom
  [urdr.canonical.profile Name Frame Atom Depth Nodes Digits Symbol]
    -> Atom)

(define urdr.canonical.profile-max-depth
  [urdr.canonical.profile Name Frame Atom Depth Nodes Digits Symbol]
    -> Depth)

(define urdr.canonical.profile-max-nodes
  [urdr.canonical.profile Name Frame Atom Depth Nodes Digits Symbol]
    -> Nodes)

(define urdr.canonical.profile-max-integer-digits
  [urdr.canonical.profile Name Frame Atom Depth Nodes Digits Symbol]
    -> Digits)

(define urdr.canonical.profile-max-symbol
  [urdr.canonical.profile Name Frame Atom Depth Nodes Digits Symbol]
    -> Symbol)

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

\\ `and` is an ordinary two-argument function on the pinned ports, so the
\\ recursive call would be an argument rather than a tail call and the
\\ scan would consume host stack proportional to the payload length. `if`
\\ keeps the same verdict (urdr.canonical.byte? is total on any input and
\\ always answers a boolean) with bounded stack, which the ADR 0005
\\ m1-large payload bound requires: oversize must be a deterministic
\\ rejection, never a per-port resource failure.
(define urdr.canonical.byte-list?
  [] -> true
  [B | Bs] ->
    (if (urdr.canonical.byte? B)
        (urdr.canonical.byte-list? Bs)
        false)
  _ -> false)

(define urdr.canonical.reverse-onto
  [] Ys -> Ys
  [X | Xs] Ys -> (urdr.canonical.reverse-onto Xs [X | Ys])
  _ Ys -> [error improper-list])

(define urdr.canonical.rev
  Xs -> (urdr.canonical.reverse-onto Xs []))

\\ Stack-safe concatenation for proper lists whose length is bounded only
\\ by the payload limit. The kernel `append` recurses over its first
\\ argument, so it is kept only where that argument is a short fixed
\\ prefix; everywhere the prefix can approach the frame bound this is
\\ used instead. Two tail recursions, identical result.
(define urdr.canonical.concat
  Xs Ys -> (urdr.canonical.reverse-onto (urdr.canonical.rev Xs) Ys))

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

\\ Generic RFC 9804 canonical atom/list parser, bounded by Profile.
(define urdr.canonical.node
  Profile [] Depth Nodes -> [error csexp-truncated]
  Profile [40 | Bs] Depth Nodes ->
    (if (> Depth (urdr.canonical.profile-max-depth Profile))
        [error depth-too-large]
        (if (>= Nodes (urdr.canonical.profile-max-nodes Profile))
            [error nodes-too-many]
            (urdr.canonical.node-list
              Profile Bs Depth (+ Nodes 1) [])))
  Profile [B | Bs] Depth Nodes ->
    (if (urdr.canonical.digit? B)
        (if (>= Nodes (urdr.canonical.profile-max-nodes Profile))
            [error nodes-too-many]
            (urdr.canonical.node-atom
              Profile [B | Bs] (+ Nodes 1)))
        [error csexp-token])
  Profile _ Depth Nodes -> [error value-type])

(define urdr.canonical.node-list
  Profile [] Depth Nodes Acc -> [error list-unclosed]
  Profile [41 | Bs] Depth Nodes Acc ->
    [ok [urdr.canonical.list-node (urdr.canonical.rev Acc)] Bs Nodes]
  Profile Bs Depth Nodes Acc ->
    (urdr.canonical.node-list-step
      Profile
      (urdr.canonical.node Profile Bs (+ Depth 1) Nodes)
      Depth
      Acc))

(define urdr.canonical.node-list-step
  Profile [error E] Depth Acc -> [error E]
  Profile [ok Node Rest Nodes] Depth Acc ->
    (urdr.canonical.node-list
      Profile Rest Depth Nodes [Node | Acc]))

(define urdr.canonical.node-atom
  Profile Bs Nodes ->
    (let Scan (urdr.canonical.scan-digits Bs [])
      (urdr.canonical.node-atom-digits
        Profile (hd Scan) (hd (tl Scan)) Nodes)))

(define urdr.canonical.node-atom-digits
  Profile Digits [58 | Bs] Nodes ->
    (urdr.canonical.node-atom-length
      (urdr.canonical.decimal
        Digits
        (urdr.canonical.profile-max-atom Profile)
        atom-too-large
        length-leading-zero)
      Bs
      Nodes)
  Profile Digits _ Nodes -> [error length-colon])

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

(define urdr.canonical.parse-payload-with-profile
  Profile Bs ->
    (if (not (urdr.canonical.profile? Profile))
        [error profile-type]
        (if (urdr.canonical.byte-list? Bs)
            (urdr.canonical.parse-payload-result
              (urdr.canonical.node Profile Bs 1 0))
            [error value-type])))

(define urdr.canonical.parse-payload
  Bs ->
    (urdr.canonical.parse-payload-with-profile
      (urdr.canonical.profile.m0) Bs))

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

(define urdr.canonical.symbol-bounded?
  Limit [] -> false
  Limit [B | Bs] ->
    (and (<= (+ 1 (length Bs)) Limit)
         (and (or (and (>= B 65) (<= B 90))
                  (and (>= B 97) (<= B 122)))
              (urdr.canonical.symbol-rest? Bs)))
  Limit _ -> false)

(define urdr.canonical.symbol-with-profile?
  Profile Bs ->
    (if (urdr.canonical.profile? Profile)
        (urdr.canonical.symbol-bounded?
          (urdr.canonical.profile-max-symbol Profile) Bs)
        false))

(define urdr.canonical.symbol?
  Bs ->
    (urdr.canonical.symbol-with-profile?
      (urdr.canonical.profile.m0) Bs))

(define urdr.canonical.bytes-compare
  [] [] -> eq
  [] _ -> lt
  _ [] -> gt
  [A | As] [B | Bs] -> lt where (< A B)
  [A | As] [B | Bs] -> gt where (> A B)
  [A | As] [B | Bs] ->
    (urdr.canonical.bytes-compare As Bs))

\\ Exact bounded host arithmetic used only for base-10000 limbs.
\\ Truncating divmod of a nonnegative host natural by a positive host
\\ natural in O(log(N/D)) host operations instead of repeated
\\ subtraction's O(N/D): collect [Weight Bit] pairs with
\\ Weight = Bit * D by doubling, largest weight first, then subtract
\\ them in descending order while summing the Bits -- the same
\\ descending-weights walk as urdr.canonical.exact-natural-weights?.
\\ Doubling is guarded by (<= Weight (- N Weight)), which is
\\ 2*Weight <= N rewritten to use only subtraction, so Weight, Bit,
\\ the quotient, and the remainder all stay within [0, N]; no host
\\ intermediate ever exceeds N itself, hence never the reviewed
\\ ADR 0003 bound of 99,990,000 that every caller already respects.
\\ Divisor 0 is a caller error and diverges, exactly like the previous
\\ repeated-subtraction loop; the callers here pass only the constants
\\ 10000, 1000, 100, and 10. This mirrors urdr.int.small.divmod, which
\\ the protocol layer must not depend on.
(define urdr.canonical.small-divmod-down
  N [] Q -> [Q N]
  N [[W B] | Ws] Q ->
    (if (>= N W)
        (urdr.canonical.small-divmod-down (- N W) Ws (+ Q B))
        (urdr.canonical.small-divmod-down N Ws Q)))

(define urdr.canonical.small-divmod-up
  N W B Ws ->
    (if (> W (- N W))
        (urdr.canonical.small-divmod-down N [[W B] | Ws] 0)
        (urdr.canonical.small-divmod-up N (+ W W) (+ B B) [[W B] | Ws])))

(define urdr.canonical.small-divmod
  N D -> (if (< N D)
             [0 N]
             (urdr.canonical.small-divmod-up N D 1 [])))

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
(define urdr.canonical.int-parse-with-profile
  Profile Raw ->
    (if (not (urdr.canonical.profile? Profile))
        [error profile-type]
        (if (urdr.canonical.byte-list? Raw)
            (urdr.canonical.int-parse-bytes
              (urdr.canonical.profile-max-integer-digits Profile) Raw)
            [error value-type])))

(define urdr.canonical.int-parse
  Raw ->
    (urdr.canonical.int-parse-with-profile
      (urdr.canonical.profile.m0) Raw))

(define urdr.canonical.int-parse-bytes
  Limit [] -> [error integer-empty]
  Limit [43 | Ds] -> [error integer-plus]
  Limit [45] -> [error integer-empty]
  Limit [45 | Ds] ->
    (if (> (length Ds) Limit)
        [error integer-too-large]
        (if (= Ds [48])
            [error integer-negative-zero]
            (urdr.canonical.int-digits Ds -1)))
  Limit Ds ->
    (if (> (length Ds) Limit)
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

(define urdr.canonical.int-render-with-profile
  Profile Big ->
    (if (not (urdr.canonical.profile? Profile))
        [error profile-type]
        (if (urdr.canonical.big-valid? Big)
            (urdr.canonical.int-render-valid
              (urdr.canonical.profile-max-integer-digits Profile) Big)
            [error integer-representation])))

(define urdr.canonical.int-render
  Big ->
    (urdr.canonical.int-render-with-profile
      (urdr.canonical.profile.m0) Big))

(define urdr.canonical.int-render-valid
  Limit [big 0 []] -> [ok [48]]
  Limit [big 1 Magnitude] ->
    (urdr.canonical.int-render-magnitude
      Limit (urdr.canonical.mag-bytes Magnitude) false)
  Limit [big -1 Magnitude] ->
    (urdr.canonical.int-render-magnitude
      Limit (urdr.canonical.mag-bytes Magnitude) true))

(define urdr.canonical.int-render-magnitude
  Limit Magnitude Negative ->
    (if (> (length Magnitude) Limit)
        [error integer-too-large]
        [ok (if Negative [45 | Magnitude] Magnitude)]))

\\ Convert generic canonical nodes to typed Urdr values.
(define urdr.canonical.typed
  Profile
  [urdr.canonical.list-node
    [[urdr.canonical.atom-node Tag] | Args]] ->
      (urdr.canonical.typed-tag Profile Tag Args)
  Profile _ -> [error typed-list])

(define urdr.canonical.typed-tag
  Profile [110 117 108 108] [] -> [ok [null]]
  Profile [110 117 108 108] _ -> [error typed-arity]
  Profile [98 111 111 108]
    [[urdr.canonical.atom-node [116 114 117 101]]] ->
      [ok [bool true]]
  Profile [98 111 111 108]
    [[urdr.canonical.atom-node [102 97 108 115 101]]] ->
      [ok [bool false]]
  Profile [98 111 111 108] [[urdr.canonical.atom-node _]] ->
    [error bool-value]
  Profile [98 111 111 108] _ -> [error typed-arity]
  Profile [105 110 116] [[urdr.canonical.atom-node Raw]] ->
    (urdr.canonical.int-parse-with-profile Profile Raw)
  Profile [105 110 116] _ -> [error typed-arity]
  Profile [116 101 120 116] [[urdr.canonical.atom-node Raw]] ->
    (if (urdr.canonical.utf8? Raw)
        [ok [text Raw]]
        [error utf8-invalid])
  Profile [116 101 120 116] _ -> [error typed-arity]
  Profile [98 121 116 101 115] [[urdr.canonical.atom-node Raw]] ->
    [ok [bytes Raw]]
  Profile [98 121 116 101 115] _ -> [error typed-arity]
  Profile [115 121 109 98 111 108]
    [[urdr.canonical.atom-node Raw]] ->
      (if (> (length Raw)
             (urdr.canonical.profile-max-symbol Profile))
          [error symbol-too-large]
          (if (urdr.canonical.symbol-with-profile? Profile Raw)
              [ok [symbol Raw]]
              [error symbol-invalid]))
  Profile [115 121 109 98 111 108] _ -> [error typed-arity]
  Profile [108 105 115 116] Items ->
    (urdr.canonical.typed-many Profile Items [])
  Profile [114 101 99 111 114 100] Entries ->
    (urdr.canonical.typed-record Profile Entries none [])
  Profile _ _ -> [error typed-tag])

(define urdr.canonical.typed-many
  Profile [] Acc -> [ok [list (urdr.canonical.rev Acc)]]
  Profile [Node | Nodes] Acc ->
    (urdr.canonical.typed-many-step
      Profile (urdr.canonical.typed Profile Node) Nodes Acc)
  Profile _ Acc -> [error improper-list])

(define urdr.canonical.typed-many-step
  Profile [error E] Nodes Acc -> [error E]
  Profile [ok Value] Nodes Acc ->
    (urdr.canonical.typed-many Profile Nodes [Value | Acc]))

(define urdr.canonical.typed-record
  Profile [] Previous Acc ->
    [ok [record (urdr.canonical.rev Acc)]]
  Profile
  [[urdr.canonical.list-node
    [[urdr.canonical.atom-node Key] Node]] | Entries]
    Previous Acc ->
      (if (> (length Key)
             (urdr.canonical.profile-max-symbol Profile))
          [error symbol-too-large]
          (if (urdr.canonical.symbol-with-profile? Profile Key)
              (urdr.canonical.record-order
                Profile Key Previous Node Entries Acc)
              [error symbol-invalid]))
  Profile [_ | Entries] Previous Acc -> [error record-entry]
  Profile _ Previous Acc -> [error improper-list])

(define urdr.canonical.record-order
  Profile Key none Node Entries Acc ->
    (urdr.canonical.typed-record-value
      Profile (urdr.canonical.typed Profile Node) Key Entries Acc)
  Profile Key Previous Node Entries Acc ->
    (let Order (urdr.canonical.bytes-compare Key Previous)
      (if (= Order eq)
          [error record-duplicate]
          (if (= Order lt)
              [error record-order]
              (urdr.canonical.typed-record-value
                Profile
                (urdr.canonical.typed Profile Node)
                Key
                Entries
                Acc)))))

(define urdr.canonical.typed-record-value
  Profile [error E] Key Entries Acc -> [error E]
  Profile [ok Value] Key Entries Acc ->
    (urdr.canonical.typed-record
      Profile Entries Key [[Key Value] | Acc]))

(define urdr.canonical.decode-payload-with-profile
  Profile Bs ->
    (urdr.canonical.decode-node
      Profile
      (urdr.canonical.parse-payload-with-profile Profile Bs)))

(define urdr.canonical.decode-payload
  Bs ->
    (urdr.canonical.decode-payload-with-profile
      (urdr.canonical.profile.m0) Bs))

(define urdr.canonical.decode-node
  Profile [error E] -> [error E]
  Profile [ok Node] -> (urdr.canonical.typed Profile Node))

\\ Byte-counted netstring outer stream.
(define urdr.canonical.frame-length
  Profile Bs ->
    (let Scan (urdr.canonical.scan-digits Bs [])
      (urdr.canonical.frame-length-scan
        Profile (hd Scan) (hd (tl Scan)))))

(define urdr.canonical.frame-length-scan
  Profile [] Rest -> [error frame-length]
  Profile Digits [] ->
    (if (> (length Digits)
           (length
             (urdr.canonical.number-bytes
               (urdr.canonical.profile-max-frame Profile))))
        [error frame-length]
        [need])
  Profile Digits [58 | Rest] ->
    (urdr.canonical.frame-length-value
      (urdr.canonical.decimal
        Digits
        (urdr.canonical.profile-max-frame Profile)
        frame-too-large
        frame-leading-zero)
      Rest)
  Profile Digits _ -> [error frame-length])

(define urdr.canonical.frame-length-value
  [error E] Rest -> [error E]
  [ok N] Rest -> [ok N Rest])

(define urdr.canonical.frame-one
  Profile [] -> [need]
  Profile [B | Bs] -> [error frame-length]
    where (not (urdr.canonical.digit? B))
  Profile Bs ->
    (urdr.canonical.frame-body
      Profile (urdr.canonical.frame-length Profile Bs)))

(define urdr.canonical.frame-body
  Profile [need] -> [need]
  Profile [error E] -> [error E]
  Profile [ok N Rest] ->
    (urdr.canonical.frame-body-take
      Profile (urdr.canonical.take N Rest [])))

(define urdr.canonical.frame-body-take
  Profile [error truncated] -> [need]
  Profile [error E] -> [error E]
  Profile [ok Body []] -> [need]
  Profile [ok Body [44 | Rest]] ->
    (urdr.canonical.frame-body-value
      (urdr.canonical.decode-payload-with-profile Profile Body)
      Rest)
  Profile [ok Body _] -> [error frame-comma])

(define urdr.canonical.frame-body-value
  [error E] Rest -> [error E]
  [ok Value] Rest -> [ok Value Rest])

(define urdr.canonical.decode-frame-with-profile
  Profile Bs ->
    (if (not (urdr.canonical.profile? Profile))
        [error profile-type]
        (if (urdr.canonical.byte-list? Bs)
            (urdr.canonical.decode-frame-result
              (urdr.canonical.frame-one Profile Bs))
            [error value-type])))

(define urdr.canonical.decode-frame
  Bs ->
    (urdr.canonical.decode-frame-with-profile
      (urdr.canonical.profile.m0) Bs))

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

(define urdr.canonical.atom-with-profile
  Profile Bs ->
    (if (not (urdr.canonical.profile? Profile))
        [error profile-type]
        (urdr.canonical.atom-bounded
          (urdr.canonical.profile-max-atom Profile) Bs)))

(define urdr.canonical.atom-bounded
  Limit Bs ->
    (if (not (urdr.canonical.byte-list? Bs))
        [error value-type]
        (if (> (length Bs) Limit)
            [error atom-too-large]
            [ok
              (append
                (urdr.canonical.number-bytes (length Bs))
                [58 | Bs])])))

(define urdr.canonical.atom
  Bs ->
    (urdr.canonical.atom-with-profile
      (urdr.canonical.profile.m0) Bs))

\\ Typed encoder. The completed payload is reparsed before return so the
\\ decoder's exact list-depth and RFC-node budgets are also encoder limits.
(define urdr.canonical.enc
  Profile Value Depth TypedNodes ->
    (if (> Depth (urdr.canonical.profile-max-depth Profile))
        [error depth-too-large]
        (if (>= TypedNodes (urdr.canonical.profile-max-nodes Profile))
            [error nodes-too-many]
            (urdr.canonical.enc-value
              Profile Value Depth (+ TypedNodes 1)))))

(define urdr.canonical.enc-value
  Profile [null] Depth Nodes ->
    [ok [40 52 58 110 117 108 108 41] Nodes]
  Profile [bool true] Depth Nodes ->
    [ok
      [40 52 58 98 111 111 108
       52 58 116 114 117 101 41]
      Nodes]
  Profile [bool false] Depth Nodes ->
    [ok
      [40 52 58 98 111 111 108
       53 58 102 97 108 115 101 41]
      Nodes]
  Profile [bool _] Depth Nodes -> [error bool-value]
  Profile [big Sign Magnitude] Depth Nodes ->
    (urdr.canonical.enc-int
      Profile
      (urdr.canonical.int-render-with-profile
        Profile [big Sign Magnitude])
      Nodes)
  Profile [text Bs] Depth Nodes ->
    (if (not (urdr.canonical.byte-list? Bs))
        [error value-type]
        (if (urdr.canonical.utf8? Bs)
            (urdr.canonical.enc-tagged
              Profile [116 101 120 116] Bs Nodes)
            [error utf8-invalid]))
  Profile [bytes Bs] Depth Nodes ->
    (if (urdr.canonical.byte-list? Bs)
        (urdr.canonical.enc-tagged
          Profile [98 121 116 101 115] Bs Nodes)
        [error value-type])
  Profile [symbol Bs] Depth Nodes ->
    (if (not (urdr.canonical.byte-list? Bs))
        [error value-type]
        (if (> (length Bs)
               (urdr.canonical.profile-max-symbol Profile))
            [error symbol-too-large]
            (if (urdr.canonical.symbol-with-profile? Profile Bs)
                (urdr.canonical.enc-tagged
                  Profile [115 121 109 98 111 108] Bs Nodes)
                [error symbol-invalid])))
  Profile [list Values] Depth Nodes ->
    (urdr.canonical.enc-list Profile Values Depth Nodes)
  Profile [record Fields] Depth Nodes ->
    (urdr.canonical.enc-record
      Profile Fields Depth Nodes none [])
  Profile _ Depth Nodes -> [error value-type])

(define urdr.canonical.enc-int
  Profile [error E] Nodes -> [error E]
  Profile [ok Raw] Nodes ->
    (urdr.canonical.enc-tagged
      Profile [105 110 116] Raw Nodes))

(define urdr.canonical.enc-tagged
  Profile Tag Raw Nodes ->
    (urdr.canonical.enc-tagged-atoms
      (urdr.canonical.atom-with-profile Profile Tag)
      (urdr.canonical.atom-with-profile Profile Raw)
      Nodes))

(define urdr.canonical.enc-tagged-atoms
  [error E] B Nodes -> [error E]
  A [error E] Nodes -> [error E]
  [ok A] [ok B] Nodes ->
    [ok (append [40] (append A (append B [41]))) Nodes])

(define urdr.canonical.enc-list
  Profile Values Depth Nodes ->
    (urdr.canonical.enc-list-values
      (urdr.canonical.enc-many
        Profile Values (+ Depth 1) Nodes [])))

(define urdr.canonical.enc-list-values
  [error E] -> [error E]
  [ok Body NewNodes] ->
    [ok
      (append
        [40 52 58 108 105 115 116]
        (urdr.canonical.concat Body [41]))
      NewNodes])

(define urdr.canonical.enc-many
  Profile [] Depth Nodes Acc ->
    [ok (urdr.canonical.rev Acc) Nodes]
  Profile [Value | Values] Depth Nodes Acc ->
    (urdr.canonical.enc-many-step
      Profile
      (urdr.canonical.enc Profile Value Depth Nodes)
      Values
      Depth
      Acc)
  Profile _ Depth Nodes Acc -> [error improper-list])

(define urdr.canonical.enc-many-step
  Profile [error E] Values Depth Acc -> [error E]
  Profile [ok Bytes Nodes] Values Depth Acc ->
    (urdr.canonical.enc-many
      Profile
      Values
      Depth
      Nodes
      (urdr.canonical.reverse-onto Bytes Acc)))

(define urdr.canonical.enc-record
  Profile [] Depth Nodes Previous Acc ->
    [ok
      (append
        [40 54 58 114 101 99 111 114 100]
        (urdr.canonical.concat (urdr.canonical.rev Acc) [41]))
      Nodes]
  Profile [[Key Value] | Fields] Depth Nodes Previous Acc ->
    (if (not (urdr.canonical.byte-list? Key))
        [error value-type]
        (if (> (length Key)
               (urdr.canonical.profile-max-symbol Profile))
            [error symbol-too-large]
            (if (urdr.canonical.symbol-with-profile? Profile Key)
                (urdr.canonical.enc-record-order
                  Profile Key Value Fields Depth Nodes Previous Acc)
                [error symbol-invalid])))
  Profile [_ | Fields] Depth Nodes Previous Acc ->
    [error record-entry]
  Profile _ Depth Nodes Previous Acc -> [error improper-list])

(define urdr.canonical.enc-record-order
  Profile Key Value Fields Depth Nodes none Acc ->
    (urdr.canonical.enc-record-value
      Profile
      (urdr.canonical.atom-with-profile Profile Key)
      Key Value Fields Depth Nodes Acc)
  Profile Key Value Fields Depth Nodes Previous Acc ->
    (let Order (urdr.canonical.bytes-compare Key Previous)
      (if (= Order eq)
          [error record-duplicate]
          (if (= Order lt)
              [error record-order]
              (urdr.canonical.enc-record-value
                Profile
                (urdr.canonical.atom-with-profile Profile Key)
                Key Value Fields Depth Nodes Acc)))))

(define urdr.canonical.enc-record-value
  Profile [error E] Key Value Fields Depth Nodes Acc -> [error E]
  Profile [ok KeyAtom] Key Value Fields Depth Nodes Acc ->
    (urdr.canonical.enc-record-entry
      Profile
      (urdr.canonical.enc Profile Value (+ Depth 1) Nodes)
      KeyAtom Key Fields Depth Acc))

(define urdr.canonical.enc-record-entry
  Profile [error E] KeyAtom Key Fields Depth Acc -> [error E]
  Profile [ok ValueBytes Nodes] KeyAtom Key Fields Depth Acc ->
    (let Entry
      (append
        [40]
        (append KeyAtom (urdr.canonical.concat ValueBytes [41])))
      (urdr.canonical.enc-record
        Profile
        Fields
        Depth
        Nodes
        Key
        (urdr.canonical.reverse-onto Entry Acc))))

(define urdr.canonical.encode-payload-with-profile
  Profile Value ->
    (if (not (urdr.canonical.profile? Profile))
        [error profile-type]
        (urdr.canonical.encode-payload-result
          Profile (urdr.canonical.enc Profile Value 1 0))))

(define urdr.canonical.encode-payload
  Value ->
    (urdr.canonical.encode-payload-with-profile
      (urdr.canonical.profile.m0) Value))

(define urdr.canonical.encode-payload-result
  Profile [error E] -> [error E]
  Profile [ok Bytes Nodes] ->
    (if (> (length Bytes)
           (urdr.canonical.profile-max-frame Profile))
        [error frame-too-large]
        (urdr.canonical.encode-payload-reparse
          Bytes
          (urdr.canonical.parse-payload-with-profile
            Profile Bytes))))

(define urdr.canonical.encode-payload-reparse
  Bytes [error E] -> [error E]
  Bytes [ok Node] -> [ok Bytes])

(define urdr.canonical.encode-frame-with-profile
  Profile Value ->
    (urdr.canonical.encode-frame-payload
      (urdr.canonical.encode-payload-with-profile Profile Value)))

(define urdr.canonical.encode-frame
  Value ->
    (urdr.canonical.encode-frame-with-profile
      (urdr.canonical.profile.m0) Value))

(define urdr.canonical.encode-frame-payload
  [error E] -> [error E]
  [ok Payload] ->
    [ok
      (append
        (urdr.canonical.number-bytes (length Payload))
        [58 | (urdr.canonical.concat Payload [44])])])

\\ Incremental stream state is [urdr.canonical.stream buffered-octets].
\\ The state carries no profile: each feed names the profile explicitly.
(define urdr.canonical.stream-new
  -> [urdr.canonical.stream []])

(define urdr.canonical.stream-feed-with-profile
  Profile [urdr.canonical.stream Buffer] Chunk ->
    (if (not (urdr.canonical.profile? Profile))
        [error profile-type]
        (if (not (urdr.canonical.byte-list? Buffer))
            [error stream-state]
            (if (urdr.canonical.byte-list? Chunk)
                (urdr.canonical.stream-drain
                  Profile (urdr.canonical.concat Buffer Chunk) [])
                [error chunk-type])))
  Profile _ Chunk -> [error stream-state])

(define urdr.canonical.stream-feed
  Stream Chunk ->
    (urdr.canonical.stream-feed-with-profile
      (urdr.canonical.profile.m0) Stream Chunk))

(define urdr.canonical.stream-drain
  Profile Buffer Acc ->
    (urdr.canonical.stream-drain-result
      Profile (urdr.canonical.frame-one Profile Buffer) Buffer Acc))

(define urdr.canonical.stream-drain-result
  Profile [need] Buffer Acc ->
    [ok
      [urdr.canonical.stream Buffer]
      (urdr.canonical.rev Acc)]
  Profile [error E] Buffer Acc -> [error E]
  Profile [ok Value Rest] Buffer Acc ->
    (urdr.canonical.stream-drain Profile Rest [Value | Acc]))

(define urdr.canonical.stream-finish
  [urdr.canonical.stream []] -> [ok]
  [urdr.canonical.stream Buffer] ->
    (if (urdr.canonical.byte-list? Buffer)
        [error frame-truncated]
        [error stream-state])
  _ -> [error stream-state])
