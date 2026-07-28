\* ADR 0003 arithmetic-only SHA-256 named counter streams. *\

(load "shen/world/integer.shen")

(define urdr.prng.list.take
  0 _ -> []
  N [X | Xs] -> [X | (urdr.prng.list.take (- N 1) Xs)])

(define urdr.prng.list.drop
  0 Xs -> Xs
  N [_ | Xs] -> (urdr.prng.list.drop (- N 1) Xs))

(define urdr.prng.list.repeat
  0 _ -> []
  N X -> [X | (urdr.prng.list.repeat (- N 1) X)])

(define urdr.prng.list.nth
  0 [X | _] -> X
  N [_ | Xs] -> (urdr.prng.list.nth (- N 1) Xs))

(define urdr.prng.list.flatten
  [] -> []
  [Xs | Rest] -> (append Xs (urdr.prng.list.flatten Rest)))

(define urdr.prng.bit.not
  0 -> 1
  1 -> 0)

(define urdr.prng.bit.and
  1 1 -> 1
  _ _ -> 0)

(define urdr.prng.bit.xor
  A B -> (if (= A B) 0 1))

(define urdr.prng.byte.bits.weights
  _ [] -> []
  N [W | Ws] ->
    (if (>= N W)
        [1 | (urdr.prng.byte.bits.weights (- N W) Ws)]
        [0 | (urdr.prng.byte.bits.weights N Ws)]))

(define urdr.prng.byte.bits
  N -> (urdr.prng.byte.bits.weights N [128 64 32 16 8 4 2 1]))

(define urdr.prng.byte.from-bits.loop
  [] N -> N
  [B | Bs] N -> (urdr.prng.byte.from-bits.loop Bs (+ (* N 2) B)))

(define urdr.prng.byte.from-bits
  Bs -> (urdr.prng.byte.from-bits.loop Bs 0))

(define urdr.prng.word.bits
  [A B C D] ->
    (append (urdr.prng.byte.bits A)
      (append (urdr.prng.byte.bits B)
        (append (urdr.prng.byte.bits C)
                (urdr.prng.byte.bits D)))))

(define urdr.prng.bits.word
  Bs -> [(urdr.prng.byte.from-bits
           (urdr.prng.list.take 8 Bs))
         (urdr.prng.byte.from-bits
           (urdr.prng.list.take 8 (urdr.prng.list.drop 8 Bs)))
         (urdr.prng.byte.from-bits
           (urdr.prng.list.take 8 (urdr.prng.list.drop 16 Bs)))
         (urdr.prng.byte.from-bits
           (urdr.prng.list.take 8 (urdr.prng.list.drop 24 Bs)))])

(define urdr.prng.bits.not
  [] -> []
  [A | As] -> [(urdr.prng.bit.not A) | (urdr.prng.bits.not As)])

(define urdr.prng.bits.and
  [] [] -> []
  [A | As] [B | Bs] ->
    [(urdr.prng.bit.and A B) | (urdr.prng.bits.and As Bs)])

(define urdr.prng.bits.xor
  [] [] -> []
  [A | As] [B | Bs] ->
    [(urdr.prng.bit.xor A B) | (urdr.prng.bits.xor As Bs)])

(define urdr.prng.word.not
  W -> (urdr.prng.bits.word
         (urdr.prng.bits.not (urdr.prng.word.bits W))))

(define urdr.prng.word.and
  A B -> (urdr.prng.bits.word
           (urdr.prng.bits.and
             (urdr.prng.word.bits A)
             (urdr.prng.word.bits B))))

(define urdr.prng.word.xor
  A B -> (urdr.prng.bits.word
           (urdr.prng.bits.xor
             (urdr.prng.word.bits A)
             (urdr.prng.word.bits B))))

(define urdr.prng.word.xor3
  A B C -> (urdr.prng.word.xor (urdr.prng.word.xor A B) C))

(define urdr.prng.word.rotr
  W N -> (let Bs (urdr.prng.word.bits W)
           (urdr.prng.bits.word
             (append (urdr.prng.list.drop (- 32 N) Bs)
                     (urdr.prng.list.take (- 32 N) Bs)))))

(define urdr.prng.word.shr
  W N -> (urdr.prng.bits.word
           (append (urdr.prng.list.repeat N 0)
                   (urdr.prng.list.take
                     (- 32 N) (urdr.prng.word.bits W)))))

(define urdr.prng.word.add.rev
  [] [] _ Out -> Out
  [A | As] [B | Bs] Carry Out ->
    (let QR (urdr.int.small.divmod (+ (+ A B) Carry) 256)
      (urdr.prng.word.add.rev
        As Bs (hd QR) [(hd (tl QR)) | Out])))

(define urdr.prng.word.add2
  A B -> (urdr.prng.word.add.rev (reverse A) (reverse B) 0 []))

(define urdr.prng.word.add-all
  [] -> [0 0 0 0]
  [W | Ws] -> (urdr.prng.word.add2
                W (urdr.prng.word.add-all Ws)))

(define urdr.prng.sha.ch
  X Y Z -> (urdr.prng.word.xor
             (urdr.prng.word.and X Y)
             (urdr.prng.word.and (urdr.prng.word.not X) Z)))

(define urdr.prng.sha.maj
  X Y Z -> (urdr.prng.word.xor3
             (urdr.prng.word.and X Y)
             (urdr.prng.word.and X Z)
             (urdr.prng.word.and Y Z)))

(define urdr.prng.sha.big-sigma0
  X -> (urdr.prng.word.xor3
         (urdr.prng.word.rotr X 2)
         (urdr.prng.word.rotr X 13)
         (urdr.prng.word.rotr X 22)))

(define urdr.prng.sha.big-sigma1
  X -> (urdr.prng.word.xor3
         (urdr.prng.word.rotr X 6)
         (urdr.prng.word.rotr X 11)
         (urdr.prng.word.rotr X 25)))

(define urdr.prng.sha.small-sigma0
  X -> (urdr.prng.word.xor3
         (urdr.prng.word.rotr X 7)
         (urdr.prng.word.rotr X 18)
         (urdr.prng.word.shr X 3)))

(define urdr.prng.sha.small-sigma1
  X -> (urdr.prng.word.xor3
         (urdr.prng.word.rotr X 17)
         (urdr.prng.word.rotr X 19)
         (urdr.prng.word.shr X 10)))

(define urdr.prng.hex.nibble
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

(define urdr.prng.sha.hex-byte
  S I -> (+ (* 16 (urdr.prng.hex.nibble (pos S I)))
            (urdr.prng.hex.nibble (pos S (+ I 1)))))

(define urdr.prng.sha.hex-word
  S -> [(urdr.prng.sha.hex-byte S 0)
        (urdr.prng.sha.hex-byte S 2)
        (urdr.prng.sha.hex-byte S 4)
        (urdr.prng.sha.hex-byte S 6)])

(define urdr.prng.sha.hex-words
  [] -> []
  [S | Ss] ->
    [(urdr.prng.sha.hex-word S) | (urdr.prng.sha.hex-words Ss)])

(define urdr.prng.sha.initial
  -> (urdr.prng.sha.hex-words
       ["6a09e667" "bb67ae85" "3c6ef372" "a54ff53a"
        "510e527f" "9b05688c" "1f83d9ab" "5be0cd19"]))

(define urdr.prng.sha.constants
  -> (urdr.prng.sha.hex-words
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

(define urdr.prng.sha.message-info.loop
  [] N Mod -> [N Mod]
  [_ | Bs] N Mod ->
    (urdr.prng.sha.message-info.loop
      Bs (urdr.int.raw.add N (urdr.int.one))
      (if (= Mod 63) 0 (+ Mod 1))))

(define urdr.prng.sha.message-info
  Bs -> (urdr.prng.sha.message-info.loop Bs (urdr.int.zero) 0))

(define urdr.prng.sha.zero-count
  Mod N -> (if (= Mod 56)
               N
               (urdr.prng.sha.zero-count
                 (if (= Mod 63) 0 (+ Mod 1)) (+ N 1))))

(define urdr.prng.int.fixed-be.loop
  N 0 Out ->
    (if (urdr.int.raw.zero? N)
        [ok Out]
        [error integer-too-large])
  N Count Out ->
    (let QR (urdr.int.raw.div-small N 256)
      (urdr.prng.int.fixed-be.loop
        (hd QR) (- Count 1) [(hd (tl QR)) | Out])))

(define urdr.prng.int.fixed-be
  N Count -> (if (urdr.int.raw.negative? N)
                 [error negative-integer]
                 (urdr.prng.int.fixed-be.loop N Count [])))

(define urdr.prng.sha.pad
  Bs -> (let Info (urdr.prng.sha.message-info Bs)
             Len (hd Info)
             Mod (hd (tl Info))
             Z (urdr.prng.sha.zero-count
                 (if (= Mod 63) 0 (+ Mod 1)) 0)
             LenBytes (urdr.prng.int.fixed-be
                        (urdr.int.raw.mul-small Len 8) 8)
          (if (= (hd LenBytes) error)
              [error sha-message-too-long]
              [ok (append Bs
                    (append [128]
                      (append (urdr.prng.list.repeat Z 0)
                              (hd (tl LenBytes)))))])))

(define urdr.prng.sha.block-words
  [] -> []
  [A B C D | Rest] ->
    [[A B C D] | (urdr.prng.sha.block-words Rest)])

(define urdr.prng.sha.extend
  W 64 -> W
  W I -> (let Next
                  (urdr.prng.word.add-all
                    [(urdr.prng.sha.small-sigma1
                       (urdr.prng.list.nth (- I 2) W))
                     (urdr.prng.list.nth (- I 7) W)
                     (urdr.prng.sha.small-sigma0
                       (urdr.prng.list.nth (- I 15) W))
                     (urdr.prng.list.nth (- I 16) W)])
            (urdr.prng.sha.extend (append W [Next]) (+ I 1))))

(define urdr.prng.sha.round
  [A B C D E F G H] K W ->
    (let T1 (urdr.prng.word.add-all
              [H
               (urdr.prng.sha.big-sigma1 E)
               (urdr.prng.sha.ch E F G)
               K W])
         T2 (urdr.prng.word.add2
              (urdr.prng.sha.big-sigma0 A)
              (urdr.prng.sha.maj A B C))
      [(urdr.prng.word.add2 T1 T2)
       A B C (urdr.prng.word.add2 D T1) E F G]))

(define urdr.prng.sha.rounds
  Work _ _ 64 -> Work
  Work Ks Ws I ->
    (urdr.prng.sha.rounds
      (urdr.prng.sha.round
        Work
        (urdr.prng.list.nth I Ks)
        (urdr.prng.list.nth I Ws))
      Ks Ws (+ I 1)))

(define urdr.prng.sha.add-state
  [] [] -> []
  [A | As] [B | Bs] ->
    [(urdr.prng.word.add2 A B) |
      (urdr.prng.sha.add-state As Bs)])

(define urdr.prng.sha.compress
  State Block ->
    (let Ws (urdr.prng.sha.extend
              (urdr.prng.sha.block-words Block) 16)
         Work (urdr.prng.sha.rounds
                State (urdr.prng.sha.constants) Ws 0)
      (urdr.prng.sha.add-state State Work)))

(define urdr.prng.sha.blocks
  [] State -> State
  Bytes State ->
    (urdr.prng.sha.blocks
      (urdr.prng.list.drop 64 Bytes)
      (urdr.prng.sha.compress
        State (urdr.prng.list.take 64 Bytes))))

(define urdr.prng.sha256.pure
  Bytes -> (let Padded (urdr.prng.sha.pad Bytes)
             (if (= (hd Padded) error)
                 Padded
                 (urdr.prng.list.flatten
                   (urdr.prng.sha.blocks
                     (hd (tl Padded))
                     (urdr.prng.sha.initial))))))

\* ---- host acceleration (ADR 0003) ----

A port that implements the shen.x SHA-256 extension binds
shen.x.sha256-octets-host (list of 0..255 -> 32-byte list) and may set
shen.x.*sha256-backend* to host. When that binding is present urdr uses it;
otherwise the arithmetic-only oracle above runs unchanged.

ADR 0003 permits native acceleration only as a byte-for-byte verified
optimization, with portable Shen remaining the semantic oracle. Both
properties hold here: urdr.prng.sha256.pure is always reachable and is what
runs on any port without the extension, and shen/tests/prng/run-tests.shen
checks the host result against the pure result on every vector, so a
disagreeing host fails the suite rather than silently changing semantics.

Disabling is a port-level concern (SHEN_X_SHA256=pure), so no host
environment read enters urdr semantics. *\

(define urdr.prng.sha256.host?
  -> (trap-error
       (= (value shen.x.*sha256-backend*) host)
       (/. E
           (trap-error
             (do (shen.x.sha256-octets-host []) true)
             (/. E2 false)))))

\\ Keep the pure length guard so the host path is identical in every case,
\\ including the unreachable over-long message. It costs one list walk
\\ against native compression, not against 64 software rounds per block.
(define urdr.prng.sha256.via-host
  Bytes -> (let Info (urdr.prng.sha.message-info Bytes)
                LenBytes (urdr.prng.int.fixed-be
                           (urdr.int.raw.mul-small (hd Info) 8) 8)
             (if (= (hd LenBytes) error)
                 [error sha-message-too-long]
                 (shen.x.sha256-octets-host Bytes))))

(define urdr.prng.sha256.raw
  Bytes -> (if (urdr.prng.sha256.host?)
               (urdr.prng.sha256.via-host Bytes)
               (urdr.prng.sha256.pure Bytes)))

(define urdr.prng.octets.check
  Bs -> (urdr.int.octets.check Bs))

(define urdr.sha256
  Bytes -> (let Valid (urdr.prng.octets.check Bytes)
             (if (= (hd Valid) error)
                 Valid
                 [ok (urdr.prng.sha256.raw Bytes)])))

(define urdr.prng.hex.char
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

(define urdr.prng.bytes.hex.raw
  [] -> ""
  [B | Bs] ->
    (let QR (urdr.int.small.divmod B 16)
      (cn (urdr.prng.hex.char (hd QR))
          (cn (urdr.prng.hex.char (hd (tl QR)))
              (urdr.prng.bytes.hex.raw Bs)))))

(define urdr.bytes.hex
  Bs -> (let Valid (urdr.prng.octets.check Bs)
          (if (= (hd Valid) error)
              Valid
              [ok (urdr.prng.bytes.hex.raw Bs)])))

(define urdr.prng.int.from-octets.loop
  [] N -> N
  [B | Bs] N ->
    (urdr.prng.int.from-octets.loop Bs
      (urdr.int.raw.add
        (urdr.int.raw.mul-small N 256)
        (urdr.int.raw.from-small B))))

(define urdr.prng.int.from-octets
  Bs -> (urdr.prng.int.from-octets.loop Bs (urdr.int.zero)))

(define urdr.prng.octets.length.loop
  [] N -> N
  [_ | Xs] N ->
    (urdr.prng.octets.length.loop
      Xs (urdr.int.raw.add N (urdr.int.one))))

(define urdr.prng.octets.length
  Xs -> (urdr.prng.octets.length.loop Xs (urdr.int.zero)))

(define urdr.prng.uvar.digits
  N -> (if (< (urdr.int.raw.compare
                N (urdr.int.raw.from-small 128)) 0)
           [(hd (tl (urdr.int.raw.div-small N 128)))]
           (let QR (urdr.int.raw.div-small N 128)
             [(hd (tl QR)) |
               (urdr.prng.uvar.digits (hd QR))])))

(define urdr.prng.uvar.mark
  [D] -> [D]
  [D | Ds] -> [(+ D 128) | (urdr.prng.uvar.mark Ds)])

(define urdr.prng.uvar.encode.raw
  N -> (urdr.prng.uvar.mark
         (reverse (urdr.prng.uvar.digits N))))

(define urdr.prng.uvar.encode
  N -> (let Valid (urdr.int.validate N)
         (if (= (hd Valid) error)
             Valid
             (if (urdr.int.raw.negative? N)
                 [error negative-uvar]
                 [ok (urdr.prng.uvar.encode.raw N)]))))

(define urdr.prng.uvar.decode.loop
  [] _ -> [error truncated-uvar]
  [B | Bs] Acc ->
    (let QR (urdr.int.small.divmod B 128)
         Next (urdr.int.raw.add
                (urdr.int.raw.mul-small Acc 128)
                (urdr.int.raw.from-small (hd (tl QR))))
      (if (= (hd QR) 0)
          [uvar Next Bs]
          (urdr.prng.uvar.decode.loop Bs Next))))

(define urdr.prng.uvar.decode.valid
  [] -> [error truncated-uvar]
  [B | Bs] ->
    (let QR (urdr.int.small.divmod B 128)
      (if (and (= (hd QR) 1) (= (hd (tl QR)) 0))
          [error nonminimal-uvar]
          (urdr.prng.uvar.decode.loop [B | Bs] (urdr.int.zero)))))

(define urdr.prng.uvar.decode
  Bs -> (let Valid (urdr.prng.octets.check Bs)
          (if (= (hd Valid) error)
              Valid
              (urdr.prng.uvar.decode.valid Bs))))

(define urdr.prng.field.raw
  Tag Payload ->
    [Tag | (append
             (urdr.prng.uvar.encode.raw
               (urdr.prng.octets.length Payload))
             Payload)])

(define urdr.prng.algorithm
  -> urdr-sha256-counter-v1)

(define urdr.prng.coordinate.raw
  Seed Subsystem Actor Purpose Counter BlockIndex ->
    (append
      [85 82 68 82 45 80 82 78 71 45 83 72 65 50 53 54 0 1]
      (append (urdr.prng.field.raw 1 Seed)
        (append (urdr.prng.field.raw 2 Subsystem)
          (append (urdr.prng.field.raw 3 Actor)
            (append (urdr.prng.field.raw 4 Purpose)
              (append
                (urdr.prng.field.raw
                  5 (urdr.int.raw.to-decimal-octets Counter))
                (urdr.prng.field.raw
                  6 (urdr.int.raw.to-decimal-octets
                      BlockIndex)))))))))

(define urdr.prng.fields.check
  Seed Subsystem Actor Purpose ->
    (let VS (urdr.prng.octets.check Seed)
         VSub (urdr.prng.octets.check Subsystem)
         VA (urdr.prng.octets.check Actor)
         VP (urdr.prng.octets.check Purpose)
      (if (= (hd VS) error)
          VS
          (if (= (hd VSub) error)
              VSub
              (if (= (hd VA) error)
                  VA
                  VP)))))

(define urdr.prng.coordinate
  Seed Subsystem Actor Purpose Counter BlockIndex ->
    (let Fields (urdr.prng.fields.check
                  Seed Subsystem Actor Purpose)
         VC (urdr.int.validate Counter)
         VB (urdr.int.validate BlockIndex)
      (if (= (hd Fields) error)
          Fields
          (if (= (hd VC) error)
              VC
              (if (= (hd VB) error)
                  VB
                  (if (urdr.int.raw.negative? Counter)
                      [error negative-counter]
                      (if (urdr.int.raw.negative? BlockIndex)
                          [error negative-block-index]
                          [ok (urdr.prng.coordinate.raw
                                Seed Subsystem Actor Purpose
                                Counter BlockIndex)])))))))

(define urdr.prng.block
  Seed Subsystem Actor Purpose Counter BlockIndex ->
    (let Coordinate (urdr.prng.coordinate
                      Seed Subsystem Actor Purpose Counter BlockIndex)
      (if (= (hd Coordinate) error)
          Coordinate
          [ok (urdr.prng.sha256.raw (hd (tl Coordinate)))])))

(define urdr.prng.stream
  Seed Subsystem Actor Purpose Counter ->
    (let Fields (urdr.prng.fields.check
                  Seed Subsystem Actor Purpose)
         VC (urdr.int.validate Counter)
      (if (= (hd Fields) error)
          Fields
          (if (= (hd VC) error)
              VC
              (if (urdr.int.raw.negative? Counter)
                  [error negative-counter]
                  [ok [stream urdr-sha256-counter-v1
                        Seed Subsystem Actor Purpose Counter]])))))

(define urdr.prng.stream.validate
  [stream urdr-sha256-counter-v1 Seed Subsystem Actor Purpose Counter] ->
    (urdr.prng.stream Seed Subsystem Actor Purpose Counter)
  [stream _ _ _ _ _ _] -> [error wrong-prng-algorithm]
  _ -> [error invalid-stream])

(define urdr.prng.transcript-coordinate
  Seed Subsystem Actor Purpose Counter BlockIndex ->
    [coordinate urdr-sha256-counter-v1
      Seed Subsystem Actor Purpose Counter BlockIndex])

(define urdr.prng.draw.valid
  [stream urdr-sha256-counter-v1 Seed Subsystem Actor Purpose Counter] ->
    (let BlockIndex (urdr.int.zero)
         Block (urdr.prng.block
                 Seed Subsystem Actor Purpose Counter BlockIndex)
         Next (urdr.int.raw.add Counter (urdr.int.one))
      [ok [draw
            (hd (tl Block))
            [stream urdr-sha256-counter-v1
              Seed Subsystem Actor Purpose Next]
            (urdr.prng.transcript-coordinate
              Seed Subsystem Actor Purpose Counter BlockIndex)]]))

(define urdr.prng.draw
  Stream -> (let Valid (urdr.prng.stream.validate Stream)
             (if (= (hd Valid) error)
                 Valid
                 (urdr.prng.draw.valid Stream))))

(define urdr.prng.space
  -> [big 1
       [9936 2963 9131 4007 5758 394 564 6564 9846 3269
        785 6879 5008 7098 4235 6195 3731 892 5792 11]])

(define urdr.prng.sample.loop
  Seed Subsystem Actor Purpose Counter BlockIndex Bound Limit Transcript ->
    (let Block (urdr.prng.block
                 Seed Subsystem Actor Purpose Counter BlockIndex)
         X (urdr.prng.int.from-octets (hd (tl Block)))
         Coord (urdr.prng.transcript-coordinate
                 Seed Subsystem Actor Purpose Counter BlockIndex)
      (if (< (urdr.int.raw.compare X Limit) 0)
          (let Div (urdr.int.raw.divmod X Bound)
               Value (hd (tl (tl Div)))
               Next (urdr.int.raw.add Counter (urdr.int.one))
            [ok [sample
                  Value
                  [stream urdr-sha256-counter-v1
                    Seed Subsystem Actor Purpose Next]
                  (reverse [Coord | Transcript])]])
          (urdr.prng.sample.loop
            Seed Subsystem Actor Purpose Counter
            (urdr.int.raw.add BlockIndex (urdr.int.one))
            Bound Limit [Coord | Transcript]))))

(define urdr.prng.sample.valid
  [stream urdr-sha256-counter-v1 Seed Subsystem Actor Purpose Counter]
  Bound ->
    (let Space (urdr.prng.space)
      (if (> (urdr.int.raw.compare Bound Space) 0)
          [error bound-too-large]
          (let Div (urdr.int.raw.divmod Space Bound)
               Limit (urdr.int.raw.multiply (hd (tl Div)) Bound)
            (urdr.prng.sample.loop
              Seed Subsystem Actor Purpose Counter (urdr.int.zero)
              Bound Limit [])))))

(define urdr.prng.sample
  Stream Bound ->
    (let VS (urdr.prng.stream.validate Stream)
         VB (urdr.int.validate Bound)
      (if (= (hd VS) error)
          VS
          (if (= (hd VB) error)
              VB
              (if (or (urdr.int.raw.negative? Bound)
                      (urdr.int.raw.zero? Bound))
                  [error invalid-bound]
                  (urdr.prng.sample.valid Stream Bound))))))
