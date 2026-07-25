\* Portable base-10,000 bigint and arithmetic-only SHA-256 candidate. *\

\* ---------- Small, exactly represented host-number helpers ---------- *\

(define small.divmod.loop
  N D Q -> (if (< N D)
               [Q N]
               (small.divmod.loop (- N D) D (+ Q 1))))

(define small.divmod
  N D -> (small.divmod.loop N D 0))

(define small.quot
  N D -> (hd (small.divmod N D)))

(define small.rem
  N D -> (hd (tl (small.divmod N D))))

(define list.take
  0 _ -> []
  N [X | Xs] -> [X | (list.take (- N 1) Xs)])

(define list.drop
  0 Xs -> Xs
  N [_ | Xs] -> (list.drop (- N 1) Xs))

(define list.repeat
  0 _ -> []
  N X -> [X | (list.repeat (- N 1) X)])

(define list.nth
  0 [X | _] -> X
  N [_ | Xs] -> (list.nth (- N 1) Xs))

(define list.flatten
  [] -> []
  [Xs | Rest] -> (append Xs (list.flatten Rest)))

\* ---------- Normalized signed base-10,000 software integers ---------- *\

(define mag.drop-high-zeroes
  [] -> []
  [0 | Ds] -> (mag.drop-high-zeroes Ds)
  Ds -> Ds)

(define mag.normalize
  Ds -> (reverse (mag.drop-high-zeroes (reverse Ds))))

(define bi.make
  _ [] -> [big 0 []]
  S Ds -> (let N (mag.normalize Ds)
            (if (= N [])
                [big 0 []]
                [big (if (< S 0) -1 1) N])))

(define bi.zero
  -> [big 0 []])

(define bi.one
  -> [big 1 [1]])

(define bi.sign
  [big S _] -> S)

(define bi.mag
  [big _ Ds] -> Ds)

(define bi.zero?
  [big 0 []] -> true
  _ -> false)

(define bi.negative?
  [big -1 _] -> true
  _ -> false)

(define bi.nonnegative?
  X -> (not (bi.negative? X)))

(define mag.from-small.loop
  0 -> []
  N -> (let QR (small.divmod N 10000)
         [(hd (tl QR)) | (mag.from-small.loop (hd QR))]))

(define bi.from-small
  N -> (if (= N 0)
           (bi.zero)
           (if (< N 0)
               (bi.make -1 (mag.from-small.loop (- 0 N)))
               (bi.make 1 (mag.from-small.loop N)))))

(define mag.compare.same-length
  [] [] -> 0
  [A | As] [B | Bs] ->
    (if (> A B)
        1
        (if (< A B)
            -1
            (mag.compare.same-length As Bs))))

(define mag.compare
  A B -> (let LA (length A)
              LB (length B)
           (if (> LA LB)
               1
               (if (< LA LB)
                   -1
                   (mag.compare.same-length (reverse A) (reverse B))))))

(define bi.compare
  [big SA A] [big SB B] ->
    (if (> SA SB)
        1
        (if (< SA SB)
            -1
            (if (= SA 0)
                0
                (if (= SA 1)
                    (mag.compare A B)
                    (- 0 (mag.compare A B)))))))

(define mag.add.carry
  [] [] 0 -> []
  [] [] C -> [C]
  [A | As] [] C ->
    (let QR (small.divmod (+ A C) 10000)
      [(hd (tl QR)) | (mag.add.carry As [] (hd QR))])
  [] [B | Bs] C ->
    (let QR (small.divmod (+ B C) 10000)
      [(hd (tl QR)) | (mag.add.carry [] Bs (hd QR))])
  [A | As] [B | Bs] C ->
    (let QR (small.divmod (+ (+ A B) C) 10000)
      [(hd (tl QR)) | (mag.add.carry As Bs (hd QR))]))

(define mag.add
  A B -> (mag.add.carry A B 0))

(define mag.sub.borrow
  [] [] 0 -> []
  [A | As] [] Borrow ->
    (let V (- A Borrow)
      (if (< V 0)
          [(+ V 10000) | (mag.sub.borrow As [] 1)]
          [V | (mag.sub.borrow As [] 0)]))
  [A | As] [B | Bs] Borrow ->
    (let V (- (- A B) Borrow)
      (if (< V 0)
          [(+ V 10000) | (mag.sub.borrow As Bs 1)]
          [V | (mag.sub.borrow As Bs 0)])))

(define mag.sub
  A B -> (mag.normalize (mag.sub.borrow A B 0)))

(define bi.negate
  [big 0 []] -> [big 0 []]
  [big S Ds] -> [big (- 0 S) Ds])

(define bi.add
  [big 0 []] B -> B
  A [big 0 []] -> A
  [big SA A] [big SB B] ->
    (if (= SA SB)
        (bi.make SA (mag.add A B))
        (let C (mag.compare A B)
          (if (= C 0)
              (bi.zero)
              (if (> C 0)
                  (bi.make SA (mag.sub A B))
                  (bi.make SB (mag.sub B A)))))))

(define bi.subtract
  A B -> (bi.add A (bi.negate B)))

(define mag.mul-digit.carry
  [] 0 _ -> []
  [] Carry _ -> (mag.from-small.loop Carry)
  [A | As] Carry D ->
    (let QR (small.divmod (+ (* A D) Carry) 10000)
      [(hd (tl QR)) | (mag.mul-digit.carry As (hd QR) D)]))

(define mag.mul-digit
  _ 0 -> []
  A D -> (mag.normalize (mag.mul-digit.carry A 0 D)))

(define mag.mul.rows
  _ [] _ Acc -> Acc
  A [B | Bs] Shift Acc ->
    (let Row (append (list.repeat Shift 0) (mag.mul-digit A B))
      (mag.mul.rows A Bs (+ Shift 1) (mag.add Acc Row))))

(define mag.mul
  A B -> (mag.normalize (mag.mul.rows A B 0 [])))

(define bi.multiply
  [big 0 []] _ -> [big 0 []]
  _ [big 0 []] -> [big 0 []]
  [big SA A] [big SB B] ->
    (bi.make (* SA SB) (mag.mul A B)))

(define bi.mul-small
  X N -> (bi.multiply X (bi.from-small N)))

(define mag.qdigit.search
  Den Rem Lo Hi ->
    (if (> Lo Hi)
        (- Lo 1)
        (let Mid (small.quot (+ Lo Hi) 2)
             C (mag.compare (mag.mul-digit Den Mid) Rem)
          (if (> C 0)
              (mag.qdigit.search Den Rem Lo (- Mid 1))
              (mag.qdigit.search Den Rem (+ Mid 1) Hi)))))

(define mag.divmod.step
  [] _ Qbe Rem -> [(mag.normalize Qbe) (mag.normalize Rem)]
  [D | Ds] Den Qbe Rem ->
    (let R2 (mag.normalize [D | Rem])
         QD (mag.qdigit.search Den R2 0 9999)
         R3 (mag.sub R2 (mag.mul-digit Den QD))
      (mag.divmod.step Ds Den [QD | Qbe] R3)))

(define mag.divmod
  Num Den ->
    (if (< (mag.compare Num Den) 0)
        [[] Num]
        (mag.divmod.step (reverse Num) Den [] [])))

(define bi.divmod
  _ [big 0 []] -> [error divide-by-zero]
  [big 0 []] _ -> [division [big 0 []] [big 0 []]]
  [big SA A] [big SB B] ->
    (let QR (mag.divmod A B)
      [division
        (bi.make (* SA SB) (hd QR))
        (bi.make SA (hd (tl QR)))]))

(define mag.div-small.step
  [] _ Carry Qbe -> [(mag.normalize Qbe) Carry]
  [D | Ds] Div Carry Qbe ->
    (let QR (small.divmod (+ (* Carry 10000) D) Div)
      (mag.div-small.step Ds Div (hd (tl QR)) [(hd QR) | Qbe])))

(define mag.div-small
  Ds Div -> (mag.div-small.step (reverse Ds) Div 0 []))

(define bi.div-small
  [big 0 []] _ -> [[big 0 []] 0]
  [big 1 Ds] Div ->
    (let QR (mag.div-small Ds Div)
      [(bi.make 1 (hd QR)) (hd (tl QR))]))

(define decimal.digit
  "0" -> 0
  "1" -> 1
  "2" -> 2
  "3" -> 3
  "4" -> 4
  "5" -> 5
  "6" -> 6
  "7" -> 7
  "8" -> 8
  "9" -> 9
  _ -> invalid)

(define bi.from-decimal.loop
  S N ->
    (if (= S "")
        [ok N]
        (let D (decimal.digit (pos S 0))
          (if (= D invalid)
              [error invalid-decimal]
              (bi.from-decimal.loop (tlstr S)
                (bi.add (bi.mul-small N 10) (bi.from-small D)))))))

(define bi.from-decimal
  "" -> [error invalid-decimal]
  S -> (let Negative (= (pos S 0) "-")
            Body (if Negative (tlstr S) S)
         (if (= Body "")
             [error invalid-decimal]
             (if (and (= (pos Body 0) "0")
                      (not (= (tlstr Body) "")))
                 [error noncanonical-decimal]
                 (let R (bi.from-decimal.loop Body (bi.zero))
                   (if (= (hd R) error)
                       R
                       (let N (hd (tl R))
                         (if (and Negative (bi.zero? N))
                             [error noncanonical-decimal]
                             [ok (if Negative (bi.negate N) N)]))))))))

(define decimal.byte
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

(define decimal.limb4
  N -> (let A (small.divmod N 1000)
            B (small.divmod (hd (tl A)) 100)
            C (small.divmod (hd (tl B)) 10)
         [(decimal.byte (hd A))
          (decimal.byte (hd B))
          (decimal.byte (hd C))
          (decimal.byte (hd (tl C)))]))

(define decimal.drop-leading
  [48 | Rest] -> (decimal.drop-leading Rest)
  [] -> [48]
  Ds -> Ds)

(define decimal.limbs-bytes
  [] -> []
  [D | Ds] -> (append (decimal.limb4 D) (decimal.limbs-bytes Ds)))

(define decimal.mag-bytes
  Ds -> (let Rev (reverse Ds)
          (append (decimal.drop-leading (decimal.limb4 (hd Rev)))
                  (decimal.limbs-bytes (tl Rev)))))

(define bi.to-decimal-bytes
  [big 0 []] -> [48]
  [big 1 Ds] -> (decimal.mag-bytes Ds)
  [big -1 Ds] -> [45 | (decimal.mag-bytes Ds)])

(define decimal.char
  45 -> "-"
  48 -> "0"
  49 -> "1"
  50 -> "2"
  51 -> "3"
  52 -> "4"
  53 -> "5"
  54 -> "6"
  55 -> "7"
  56 -> "8"
  57 -> "9")

(define decimal.bytes-string
  [] -> ""
  [B | Bs] -> (cn (decimal.char B) (decimal.bytes-string Bs)))

(define bi.to-decimal
  N -> (decimal.bytes-string (bi.to-decimal-bytes N)))

\* Deterministic, tagged nonnegative logical-time operations. *\

(define time.add
  A B -> (if (and (bi.nonnegative? A) (bi.nonnegative? B))
             [ok (bi.add A B)]
             [error negative-time]))

(define time.subtract
  A B -> (if (and (bi.nonnegative? A) (bi.nonnegative? B))
             (if (< (bi.compare A B) 0)
                 [error time-underflow]
                 [ok (bi.subtract A B)])
             [error negative-time]))

\* ---------- Arithmetic-only 32-bit SHA-256 words ---------- *\

(define bit.not
  0 -> 1
  1 -> 0)

(define bit.and
  1 1 -> 1
  _ _ -> 0)

(define bit.xor
  A B -> (if (= A B) 0 1))

(define byte.bits.weights
  _ [] -> []
  N [W | Ws] ->
    (if (>= N W)
        [1 | (byte.bits.weights (- N W) Ws)]
        [0 | (byte.bits.weights N Ws)]))

(define byte.bits
  N -> (byte.bits.weights N [128 64 32 16 8 4 2 1]))

(define byte.from-bits.loop
  [] N -> N
  [B | Bs] N -> (byte.from-bits.loop Bs (+ (* N 2) B)))

(define byte.from-bits
  Bs -> (byte.from-bits.loop Bs 0))

(define word.bits
  [A B C D] ->
    (append (byte.bits A)
      (append (byte.bits B)
        (append (byte.bits C) (byte.bits D)))))

(define bits.word
  Bs -> [(byte.from-bits (list.take 8 Bs))
         (byte.from-bits (list.take 8 (list.drop 8 Bs)))
         (byte.from-bits (list.take 8 (list.drop 16 Bs)))
         (byte.from-bits (list.take 8 (list.drop 24 Bs)))])

(define bits.not
  [] -> []
  [A | As] -> [(bit.not A) | (bits.not As)])

(define bits.and
  [] [] -> []
  [A | As] [B | Bs] -> [(bit.and A B) | (bits.and As Bs)])

(define bits.xor
  [] [] -> []
  [A | As] [B | Bs] -> [(bit.xor A B) | (bits.xor As Bs)])

(define word.not
  W -> (bits.word (bits.not (word.bits W))))

(define word.and
  A B -> (bits.word (bits.and (word.bits A) (word.bits B))))

(define word.xor
  A B -> (bits.word (bits.xor (word.bits A) (word.bits B))))

(define word.xor3
  A B C -> (word.xor (word.xor A B) C))

(define word.rotr
  W N -> (let Bs (word.bits W)
           (bits.word
             (append (list.drop (- 32 N) Bs)
                     (list.take (- 32 N) Bs)))))

(define word.shr
  W N -> (bits.word
           (append (list.repeat N 0)
                   (list.take (- 32 N) (word.bits W)))))

(define word.add.rev
  [] [] Carry Out ->
    (if (= Carry 0) Out Out)
  [A | As] [B | Bs] Carry Out ->
    (let QR (small.divmod (+ (+ A B) Carry) 256)
      (word.add.rev As Bs (hd QR) [(hd (tl QR)) | Out])))

(define word.add2
  A B -> (word.add.rev (reverse A) (reverse B) 0 []))

(define word.add-all
  [] -> [0 0 0 0]
  [W | Ws] -> (word.add2 W (word.add-all Ws)))

(define sha.ch
  X Y Z -> (word.xor (word.and X Y) (word.and (word.not X) Z)))

(define sha.maj
  X Y Z -> (word.xor3 (word.and X Y) (word.and X Z) (word.and Y Z)))

(define sha.big-sigma0
  X -> (word.xor3 (word.rotr X 2) (word.rotr X 13) (word.rotr X 22)))

(define sha.big-sigma1
  X -> (word.xor3 (word.rotr X 6) (word.rotr X 11) (word.rotr X 25)))

(define sha.small-sigma0
  X -> (word.xor3 (word.rotr X 7) (word.rotr X 18) (word.shr X 3)))

(define sha.small-sigma1
  X -> (word.xor3 (word.rotr X 17) (word.rotr X 19) (word.shr X 10)))

(define hex.nibble
  "0" -> 0
  "1" -> 1
  "2" -> 2
  "3" -> 3
  "4" -> 4
  "5" -> 5
  "6" -> 6
  "7" -> 7
  "8" -> 8
  "9" -> 9
  "a" -> 10
  "b" -> 11
  "c" -> 12
  "d" -> 13
  "e" -> 14
  "f" -> 15)

(define sha.hex-byte
  S I -> (+ (* 16 (hex.nibble (pos S I)))
            (hex.nibble (pos S (+ I 1)))))

(define sha.hex-word
  S -> [(sha.hex-byte S 0) (sha.hex-byte S 2)
        (sha.hex-byte S 4) (sha.hex-byte S 6)])

(define sha.hex-words
  [] -> []
  [S | Ss] -> [(sha.hex-word S) | (sha.hex-words Ss)])

(define sha.initial
  -> (sha.hex-words
       ["6a09e667" "bb67ae85" "3c6ef372" "a54ff53a"
        "510e527f" "9b05688c" "1f83d9ab" "5be0cd19"]))

(define sha.constants
  -> (sha.hex-words
       ["428a2f98" "71374491" "b5c0fbcf" "e9b5dba5"
        "3956c25b" "59f111f1" "923f82a4" "ab1c5ed5"
        "d807aa98" "12835b01" "243185be" "550c7dc3"
        "72be5d74" "80deb1fe" "9bdc06a7" "c19bf174"
        "e49b69c1" "efbe4786" "0fc19dc6" "240ca1cc"
        "2de92c6f" "4a7484aa" "5cb0a9dc" "76f988da"
        "983e5152" "a831c66d" "b00327c8" "bf597fc7"
        "c6e00bf3" "d5a79147" "06ca6351" "14292967"
        "27b70a85" "2e1b2138" "4d2c6dfc" "53380d13"
        "650a7354" "766a0abb" "81c2c92e" "92722c85"
        "a2bfe8a1" "a81a664b" "c24b8b70" "c76c51a3"
        "d192e819" "d6990624" "f40e3585" "106aa070"
        "19a4c116" "1e376c08" "2748774c" "34b0bcb5"
        "391c0cb3" "4ed8aa4a" "5b9cca4f" "682e6ff3"
        "748f82ee" "78a5636f" "84c87814" "8cc70208"
        "90befffa" "a4506ceb" "bef9a3f7" "c67178f2"]))

(define sha.message-info.loop
  [] N Mod -> [N Mod]
  [_ | Bs] N Mod ->
    (sha.message-info.loop Bs (bi.add N (bi.one))
      (if (= Mod 63) 0 (+ Mod 1))))

(define sha.message-info
  Bs -> (sha.message-info.loop Bs (bi.zero) 0))

(define sha.zero-count
  Mod N -> (if (= Mod 56)
               N
               (sha.zero-count (if (= Mod 63) 0 (+ Mod 1)) (+ N 1))))

(define bi.fixed-be.loop
  N 0 Out -> (if (bi.zero? N) [ok Out] [error integer-too-large])
  N Count Out ->
    (let QR (bi.div-small N 256)
      (bi.fixed-be.loop (hd QR) (- Count 1) [(hd (tl QR)) | Out])))

(define bi.fixed-be
  N Count -> (if (bi.nonnegative? N)
                 (bi.fixed-be.loop N Count [])
                 [error negative-integer]))

(define sha.pad
  Bs -> (let Info (sha.message-info Bs)
             Len (hd Info)
             Mod (hd (tl Info))
             Z (sha.zero-count (if (= Mod 63) 0 (+ Mod 1)) 0)
             LenBytes (bi.fixed-be (bi.mul-small Len 8) 8)
          (if (= (hd LenBytes) error)
              [error sha-message-too-long]
              [ok (append Bs
                    (append [128]
                      (append (list.repeat Z 0) (hd (tl LenBytes)))))])))

(define sha.block-words
  [] -> []
  [A B C D | Rest] -> [[A B C D] | (sha.block-words Rest)])

(define sha.extend
  W 64 -> W
  W I -> (let Next
                  (word.add-all
                    [(sha.small-sigma1 (list.nth (- I 2) W))
                     (list.nth (- I 7) W)
                     (sha.small-sigma0 (list.nth (- I 15) W))
                     (list.nth (- I 16) W)])
            (sha.extend (append W [Next]) (+ I 1))))

(define sha.round
  [A B C D E F G H] K W ->
    (let T1 (word.add-all [H (sha.big-sigma1 E) (sha.ch E F G) K W])
         T2 (word.add2 (sha.big-sigma0 A) (sha.maj A B C))
      [(word.add2 T1 T2) A B C (word.add2 D T1) E F G]))

(define sha.rounds
  Work _ _ 64 -> Work
  Work Ks Ws I ->
    (sha.rounds (sha.round Work (list.nth I Ks) (list.nth I Ws))
                Ks Ws (+ I 1)))

(define sha.add-state
  [] [] -> []
  [A | As] [B | Bs] -> [(word.add2 A B) | (sha.add-state As Bs)])

(define sha.compress
  State Block ->
    (let Ws (sha.extend (sha.block-words Block) 16)
         Work (sha.rounds State (sha.constants) Ws 0)
      (sha.add-state State Work)))

(define sha.blocks
  [] State -> State
  Bytes State ->
    (sha.blocks (list.drop 64 Bytes)
                (sha.compress State (list.take 64 Bytes))))

(define sha256
  Bytes -> (let Padded (sha.pad Bytes)
             (if (= (hd Padded) error)
                 Padded
                 (list.flatten
                   (sha.blocks (hd (tl Padded)) (sha.initial))))))

(define hex.char
  0 -> "0"
  1 -> "1"
  2 -> "2"
  3 -> "3"
  4 -> "4"
  5 -> "5"
  6 -> "6"
  7 -> "7"
  8 -> "8"
  9 -> "9"
  10 -> "a"
  11 -> "b"
  12 -> "c"
  13 -> "d"
  14 -> "e"
  15 -> "f")

(define bytes.hex
  [] -> ""
  [B | Bs] -> (let QR (small.divmod B 16)
                (cn (hex.char (hd QR))
                    (cn (hex.char (hd (tl QR)))
                        (bytes.hex Bs)))))

\* ---------- Collision-safe named counter streams ---------- *\

(define bi.from-byte-list.loop
  [] N -> N
  [B | Bs] N ->
    (bi.from-byte-list.loop Bs
      (bi.add (bi.mul-small N 256) (bi.from-small B))))

(define bi.from-byte-list
  Bs -> (bi.from-byte-list.loop Bs (bi.zero)))

(define list.software-length.loop
  [] N -> N
  [_ | Xs] N -> (list.software-length.loop Xs (bi.add N (bi.one))))

(define list.software-length
  Xs -> (list.software-length.loop Xs (bi.zero)))

(define uvar.digits
  N -> (if (< (bi.compare N (bi.from-small 128)) 0)
           [(hd (tl (bi.div-small N 128)))]
           (let QR (bi.div-small N 128)
             [(hd (tl QR)) | (uvar.digits (hd QR))])))

(define uvar.mark
  [D] -> [D]
  [D | Ds] -> [(+ D 128) | (uvar.mark Ds)])

(define uvar.encode
  N -> (uvar.mark (reverse (uvar.digits N))))

(define prng.field
  Tag Payload ->
    [Tag | (append (uvar.encode (list.software-length Payload)) Payload)])

(define prng.coordinate.valid
  Seed Subsystem Actor Purpose Counter BlockIndex ->
    (append
      [85 82 68 82 45 80 82 78 71 45 83 72 65 50 53 54 0 1]
      (append (prng.field 1 Seed)
        (append (prng.field 2 Subsystem)
          (append (prng.field 3 Actor)
            (append (prng.field 4 Purpose)
              (append (prng.field 5 (bi.to-decimal-bytes Counter))
                      (prng.field 6 (bi.to-decimal-bytes BlockIndex)))))))))

(define prng.coordinate
  Seed Subsystem Actor Purpose Counter BlockIndex ->
    (if (and (bi.nonnegative? Counter) (bi.nonnegative? BlockIndex))
        (prng.coordinate.valid Seed Subsystem Actor Purpose Counter BlockIndex)
        [error negative-coordinate]))

(define prng.block
  Seed Subsystem Actor Purpose Counter BlockIndex ->
    (let Coordinate
            (prng.coordinate Seed Subsystem Actor Purpose Counter BlockIndex)
      (if (= (hd Coordinate) error)
          Coordinate
          (sha256 Coordinate))))

(define prng.stream
  Seed Subsystem Actor Purpose Counter ->
    [stream Seed Subsystem Actor Purpose Counter])

(define prng.draw
  [stream Seed Subsystem Actor Purpose Counter] ->
    [draw
      (prng.block Seed Subsystem Actor Purpose Counter (bi.zero))
      [stream Seed Subsystem Actor Purpose (bi.add Counter (bi.one))]
      [coordinate Counter (bi.zero)]])

(define prng.sample.loop
  Seed Subsystem Actor Purpose Counter Bound Limit Transcript ->
    (let Bytes (prng.block Seed Subsystem Actor Purpose Counter (bi.zero))
         X (bi.from-byte-list Bytes)
         Coord [coordinate Counter (bi.zero)]
         Next (bi.add Counter (bi.one))
      (if (< (bi.compare X Limit) 0)
          (let QR (bi.divmod X Bound)
            [sample
              (hd (tl (tl QR)))
              Next
              (reverse [Coord | Transcript])])
          (prng.sample.loop Seed Subsystem Actor Purpose Next Bound Limit
                            [Coord | Transcript]))))

(define prng.sample
  [stream Seed Subsystem Actor Purpose Counter] Bound ->
    (if (or (bi.negative? Bound) (bi.zero? Bound))
        [error invalid-bound]
        (let Space
                  (hd (tl (bi.from-decimal
                    "115792089237316195423570985008687907853269984665640564039457584007913129639936")))
             QR (bi.divmod Space Bound)
             Limit (bi.multiply (hd (tl QR)) Bound)
          (prng.sample.loop Seed Subsystem Actor Purpose Counter Bound Limit []))))
