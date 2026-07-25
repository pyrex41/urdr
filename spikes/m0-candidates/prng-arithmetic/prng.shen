\\ URDR-PHILOX-FRAMED-v1: arithmetic-only named counter PRNG.
\\ Requires bigint.shen. 32-bit words are [low16 high16].

(define pa.xor16
  A B -> (pa.xor16-loop A B 1 16 0))

(define pa.xor16-loop
  _ _ _ 0 Acc -> Acc
  A B Place Left Acc ->
    (let AD (pa.small-divmod A 2)
          BD (pa.small-divmod B 2)
          AB (hd (tl AD))
          BB (hd (tl BD))
          Next (if (= AB BB) Acc (+ Acc Place))
          (pa.xor16-loop (hd AD) (hd BD) (+ Place Place)
                         (- Left 1) Next)))

(define pa.word-xor
  [AL AH] [BL BH] -> [(pa.xor16 AL BL) (pa.xor16 AH BH)])

(define pa.word-xor3
  A B C -> (pa.word-xor (pa.word-xor A B) C))

(define pa.word-add
  [AL AH] [BL BH] ->
    (let LD (pa.small-divmod (+ AL BL) 65536)
          HD (pa.small-divmod (+ (+ AH BH) (hd LD)) 65536)
          [(hd (tl LD)) (hd (tl HD))]))

(define pa.limb-at
  [] _ -> 0
  [D | _] 0 -> D
  [_ | Ds] N -> (pa.limb-at Ds (- N 1)))

\\ Exact 32x32 -> [low-word high-word].
(define pa.word-mul-wide
  [AL AH] [BL BH] ->
    (let P (pa.mag-mul [AL AH] [BL BH])
         [[(pa.limb-at P 0) (pa.limb-at P 1)]
          [(pa.limb-at P 2) (pa.limb-at P 3)]]))

(define pa.philox-m0
  -> [8019 53841])

(define pa.philox-m1
  -> [36183 52638])

(define pa.philox-w0
  -> [31161 40503])

(define pa.philox-w1
  -> [44677 47975])

(define pa.philox-round
  [C0 C1 C2 C3] [K0 K1] ->
    (let P0 (pa.word-mul-wide (pa.philox-m0) C0)
          P1 (pa.word-mul-wide (pa.philox-m1) C2)
          Lo0 (hd P0)
          Hi0 (hd (tl P0))
          Lo1 (hd P1)
          Hi1 (hd (tl P1))
          [(pa.word-xor3 Hi1 C1 K0)
           Lo1
           (pa.word-xor3 Hi0 C3 K1)
           Lo0]))

(define pa.philox-bump-key
  [K0 K1] -> [(pa.word-add K0 (pa.philox-w0))
               (pa.word-add K1 (pa.philox-w1))])

(define pa.philox-rounds
  0 C _ -> C
  N C K -> (pa.philox-rounds (- N 1)
                              (pa.philox-round C K)
                              (pa.philox-bump-key K)))

(define pa.philox4x32-10
  Counter Key -> (pa.philox-rounds 10 Counter Key))

(define pa.valid-bytes?
  [] -> true
  [B | Bs] -> (and (integer? B)
                    (and (pa.ge-small B 0)
                         (and (> 256 B) (pa.valid-bytes? Bs))))
  _ -> false)

(define pa.mag-bytes
  [] Acc -> Acc
  Mag Acc ->
    (let QR (pa.mag-div-small Mag 256)
         (pa.mag-bytes (hd QR) [(hd (tl QR)) | Acc])))

(define pa.bi-signed-payload
  [0] -> [0]
  [1 | Mag] -> [1 | (pa.mag-bytes Mag [])]
  [-1 | Mag] -> [2 | (pa.mag-bytes Mag [])])

(define pa.bi-natural-payload
  [0] -> []
  [1 | Mag] -> (pa.mag-bytes Mag [])
  _ -> (simple-error "pa.bi-natural-payload: negative coordinate"))

\\ A payload byte becomes two values 1..16; zero terminates a field.
(define pa.nibble-frame
  [] -> []
  [B | Bs] ->
    (let D (pa.small-divmod B 16)
         [(+ (hd D) 1) (+ (hd (tl D)) 1) | (pa.nibble-frame Bs)]))

(define pa.field-frame
  Tag Payload -> [Tag | (append (pa.nibble-frame Payload) [0])])

(define pa.coordinate-frame
  Seed Subsystem Actor Purpose Counter Block ->
    (simple-error "pa.coordinate-frame: invalid bigint coordinate")
      where (not (and (pa.valid-bi? Seed)
                 (and (pa.valid-bi? Counter) (pa.valid-bi? Block))))
  Seed Subsystem Actor Purpose Counter Block ->
    (simple-error "pa.coordinate-frame: invalid octet field")
      where (not (and (pa.valid-bytes? Subsystem)
                 (and (pa.valid-bytes? Actor) (pa.valid-bytes? Purpose))))
  Seed Subsystem Actor Purpose Counter Block ->
    (simple-error "pa.coordinate-frame: negative counter")
      where (not (and (pa.nonnegative? Counter) (pa.nonnegative? Block)))
  Seed Subsystem Actor Purpose Counter Block ->
    (append [85 82 68 82 45 80 72 73 76 79 88 45 70 82 65 77 69 45 118 49]
      (append (pa.field-frame 1 (pa.bi-signed-payload Seed))
        (append (pa.field-frame 2 Subsystem)
          (append (pa.field-frame 3 Actor)
            (append (pa.field-frame 4 Purpose)
              (append (pa.field-frame 5 (pa.bi-natural-payload Counter))
                      (pa.field-frame 6 (pa.bi-natural-payload Block)))))))))

(define pa.byte-padding
  Bytes ->
    (let Used (pa.small-rem (+ (length Bytes) 1) 16)
          Zeros (if (= Used 0) 0 (- 16 Used))
          (append Bytes [128 | (pa.zeros Zeros)])))

(define pa.word-from-bytes
  [B0 B1 B2 B3] -> [(+ B0 (* 256 B1)) (+ B2 (* 256 B3))])

(define pa.block-words
  [B0 B1 B2 B3 B4 B5 B6 B7 B8 B9 B10 B11 B12 B13 B14 B15 | Rest] ->
    [[(pa.word-from-bytes [B0 B1 B2 B3])
      (pa.word-from-bytes [B4 B5 B6 B7])
      (pa.word-from-bytes [B8 B9 B10 B11])
      (pa.word-from-bytes [B12 B13 B14 B15])]
     Rest])

(define pa.words-xor
  [] [] -> []
  [A | As] [B | Bs] -> [(pa.word-xor A B) | (pa.words-xor As Bs)])

(define pa.frame-key
  [S0 S1 S2 S3] -> [(pa.word-xor S0 S2) (pa.word-xor S1 S3)])

(define pa.frame-compress
  State Block ->
    (let Input (pa.words-xor State Block)
          Output (pa.philox4x32-10 Input (pa.frame-key State))
          (pa.words-xor Output (pa.words-xor State Block))))

(define pa.frame-digest-loop
  [] State -> (pa.philox4x32-10 State (pa.frame-key State))
  Bytes State ->
    (let BR (pa.block-words Bytes)
         (pa.frame-digest-loop (hd (tl BR))
                               (pa.frame-compress State (hd BR)))))

(define pa.frame-digest
  Bytes ->
    (pa.frame-digest-loop (pa.byte-padding Bytes)
      [[27272 9279] [2259 34211] [35374 4889] [29508 880]]))

\\ Pure random-access 128-bit block. No stream state is read or changed.
(define pa.prng-block
  Seed Subsystem Actor Purpose Counter Block ->
    (pa.frame-digest
      (pa.coordinate-frame Seed Subsystem Actor Purpose Counter Block)))

(define pa.flatten-words
  [] -> []
  [[Lo Hi] | Ws] -> [Lo Hi | (pa.flatten-words Ws)])

\\ Cantor pairing gives each (attempt, chunk) a distinct arbitrary block index.
(define pa.pair-natural
  A B -> (simple-error "pa.pair-natural: negative input")
    where (not (and (pa.nonnegative? A) (pa.nonnegative? B)))
  A B ->
    (let S (pa.add A B)
          Triangle (pa.divide (pa.multiply S (pa.add S (pa.from-small 1)))
                              (pa.from-small 2))
          (pa.add Triangle B)))

(define pa.take-prefix
  _ 0 Acc -> (reverse Acc)
  [] _ Acc -> (reverse Acc)
  [X | Xs] N Acc -> (pa.take-prefix Xs (- N 1) [X | Acc]))

(define pa.min-small
  A B -> A where (> B A)
  _ B -> B)

(define pa.draw-limbs
  _ _ _ _ _ _ 0 _ Acc Coords -> [(pa.mag-normalize Acc) (reverse Coords)]
  Seed Subsystem Actor Purpose Counter Attempt Need Chunk Acc Coords ->
    (let Paired (pa.pair-natural Attempt Chunk)
          Words (pa.prng-block Seed Subsystem Actor Purpose Counter Paired)
          Limbs (pa.flatten-words Words)
          Take (pa.min-small Need 8)
          Used (pa.take-prefix Limbs Take [])
          Coord [Seed Subsystem Actor Purpose Counter Paired]
          (pa.draw-limbs Seed Subsystem Actor Purpose Counter Attempt
                         (- Need Take) (pa.add Chunk (pa.from-small 1))
                         (append Acc Used) [Coord | Coords])))

(define pa.sample-bounded
  Seed Subsystem Actor Purpose Counter Bound ->
    (simple-error "pa.sample-bounded: bound must be positive")
      where (not (= (pa.compare Bound [0]) 1))
  Seed Subsystem Actor Purpose Counter Bound ->
    (let K (length (pa.mag Bound))
          Range (pa.bi 1 (pa.mag-shift [1] K))
          Limit (pa.subtract Range (pa.remainder Range Bound))
          (pa.sample-loop Seed Subsystem Actor Purpose Counter Bound
                          K Limit [0] [])))

(define pa.sample-loop
  Seed Subsystem Actor Purpose Counter Bound K Limit Attempt History ->
    (let Draw (pa.draw-limbs Seed Subsystem Actor Purpose Counter Attempt
                             K [0] [] [])
          X (pa.bi 1 (hd Draw))
          Coords (hd (tl Draw))
          C (pa.compare X Limit)
          (if (= C -1)
              [(pa.remainder X Bound)
               (reverse [[accept Attempt Coords X] | History])]
              (pa.sample-loop Seed Subsystem Actor Purpose Counter Bound
                              K Limit (pa.add Attempt (pa.from-small 1))
                              [[reject Attempt Coords X] | History]))))
