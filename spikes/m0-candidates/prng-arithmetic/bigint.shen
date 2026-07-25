\\ Portable signed software integers for the arithmetic PRNG candidate.
\\ Representation: [Sign | little-endian base-65536 magnitude limbs].
\\ Zero is [0], positive values start with 1, and negative values with -1.

(define pa.ge-small
  X Y -> (or (> X Y) (= X Y)))

(define pa.small-divmod
  N D -> (simple-error "pa.small-divmod: invalid operands")
    where (or (< N 0) (or (< D 1) (or (not (integer? N))
                                      (not (integer? D)))))
  N D -> (pa.small-divmod-take N (pa.small-multiples N D 1 [])))

(define pa.small-multiples
  N M Q Acc -> Acc where (> M N)
  N M Q Acc -> (pa.small-multiples N (+ M M) (+ Q Q) [[M Q] | Acc]))

(define pa.small-divmod-take
  N [] -> [0 N]
  N [[M Q] | Rest] ->
    (if (pa.ge-small N M)
        (let QR (pa.small-divmod-take (- N M) Rest)
             [(+ Q (hd QR)) (hd (tl QR))])
        (pa.small-divmod-take N Rest)))

(define pa.small-quot
  N D -> (hd (pa.small-divmod N D)))

(define pa.small-rem
  N D -> (hd (tl (pa.small-divmod N D))))

(define pa.drop-high-zeros
  [] -> []
  [0 | Ds] -> (pa.drop-high-zeros Ds)
  Ds -> Ds)

(define pa.mag-normalize
  Ds -> (reverse (pa.drop-high-zeros (reverse Ds))))

(define pa.valid-limbs?
  [] -> true
  [D | Ds] -> (and (integer? D)
                    (and (pa.ge-small D 0)
                         (and (> 65536 D) (pa.valid-limbs? Ds))))
  _ -> false)

(define pa.valid-bi?
  [0] -> true
  [S | Ds] -> (and (or (= S 1) (= S -1))
                    (and (not (= Ds []))
                         (and (pa.valid-limbs? Ds)
                              (not (= (hd (reverse Ds)) 0)))))
  _ -> false)

(define pa.bi
  _ Ds -> [0] where (= (pa.mag-normalize Ds) [])
  S Ds -> [S | (pa.mag-normalize Ds)] where (or (= S 1) (= S -1))
  _ _ -> (simple-error "pa.bi: sign must be -1 or 1"))

(define pa.sign
  [S | _] -> S)

(define pa.mag
  [_ | Ds] -> Ds)

(define pa.zero?
  [0] -> true
  _ -> false)

(define pa.negative?
  [-1 | _] -> true
  _ -> false)

(define pa.nonnegative?
  X -> (not (pa.negative? X)))

(define pa.from-small
  0 -> [0]
  N -> (pa.bi -1 (pa.mag-from-small (- 0 N))) where (< N 0)
  N -> (pa.bi 1 (pa.mag-from-small N)))

(define pa.mag-from-small
  0 -> []
  N -> (let QR (pa.small-divmod N 65536)
             [(hd (tl QR)) | (pa.mag-from-small (hd QR))]))

(define pa.mag-compare
  A B -> 1 where (> (length A) (length B))
  A B -> -1 where (> (length B) (length A))
  A B -> (pa.mag-compare-msb (reverse A) (reverse B)))

(define pa.mag-compare-msb
  [] [] -> 0
  [A | As] [B | Bs] -> 1 where (> A B)
  [A | As] [B | Bs] -> -1 where (> B A)
  [_ | As] [_ | Bs] -> (pa.mag-compare-msb As Bs))

(define pa.compare
  A B -> (simple-error "pa.compare: invalid bigint")
    where (not (and (pa.valid-bi? A) (pa.valid-bi? B)))
  [SA | As] [SB | Bs] -> 1 where (> SA SB)
  [SA | As] [SB | Bs] -> -1 where (> SB SA)
  [0] [0] -> 0
  [1 | As] [1 | Bs] -> (pa.mag-compare As Bs)
  [-1 | As] [-1 | Bs] -> (- 0 (pa.mag-compare As Bs)))

(define pa.mag-add
  A B -> (pa.mag-normalize (pa.mag-add-carry A B 0)))

(define pa.mag-add-carry
  [] [] 0 -> []
  [] [] C -> [C]
  [A | As] [] C -> (pa.mag-add-carry [A | As] [0] C)
  [] [B | Bs] C -> (pa.mag-add-carry [0] [B | Bs] C)
  [A | As] [B | Bs] C ->
    (let QR (pa.small-divmod (+ (+ A B) C) 65536)
         [(hd (tl QR)) | (pa.mag-add-carry As Bs (hd QR))]))

\\ Requires A >= B.
(define pa.mag-sub
  A B -> (pa.mag-normalize (pa.mag-sub-borrow A B 0)))

(define pa.mag-sub-borrow
  [] [] 0 -> []
  [A | As] [] Borrow -> (pa.mag-sub-borrow [A | As] [0] Borrow)
  [A | As] [B | Bs] Borrow ->
    (let D (- (- A B) Borrow)
         (if (< D 0)
             [(+ D 65536) | (pa.mag-sub-borrow As Bs 1)]
             [D | (pa.mag-sub-borrow As Bs 0)])))

(define pa.negate
  [0] -> [0]
  [S | Ds] -> [(- 0 S) | Ds])

(define pa.add
  A B -> (simple-error "pa.add: invalid bigint")
    where (not (and (pa.valid-bi? A) (pa.valid-bi? B)))
  [0] B -> B
  A [0] -> A
  [S | As] [S | Bs] -> (pa.bi S (pa.mag-add As Bs))
  [SA | As] [SB | Bs] ->
    (let C (pa.mag-compare As Bs)
         (if (= C 0)
             [0]
             (if (= C 1)
                 (pa.bi SA (pa.mag-sub As Bs))
                 (pa.bi SB (pa.mag-sub Bs As))))))

(define pa.subtract
  A B -> (pa.add A (pa.negate B)))

\\ Exact 16x16 -> [low16 high16], using only products of 8-bit values.
(define pa.mul16
  A B ->
    (let AD (pa.small-divmod A 256)
          BD (pa.small-divmod B 256)
          A1 (hd AD)
          A0 (hd (tl AD))
          B1 (hd BD)
          B0 (hd (tl BD))
          P0 (* A0 B0)
          P1 (+ (* A0 B1) (* A1 B0))
          P2 (* A1 B1)
          P1D (pa.small-divmod P1 256)
          LowWide (+ P0 (* 256 (hd (tl P1D))))
          LowD (pa.small-divmod LowWide 65536)
          High (+ (+ P2 (hd P1D)) (hd LowD))
          [(hd (tl LowD)) High]))

(define pa.mag-mul-digit
  Ds D -> (pa.mag-normalize (pa.mag-mul-digit-carry Ds D 0)))

(define pa.mag-mul-digit-carry
  [] 0 0 -> []
  [] _ 0 -> []
  [] _ Carry -> [Carry]
  [A | As] D Carry ->
    (let P (pa.mul16 A D)
          Sum (+ (hd P) Carry)
          SD (pa.small-divmod Sum 65536)
          NextCarry (+ (hd (tl P)) (hd SD))
          [(hd (tl SD)) | (pa.mag-mul-digit-carry As D NextCarry)]))

(define pa.zeros
  0 -> []
  N -> [0 | (pa.zeros (- N 1))])

(define pa.mag-shift
  Ds N -> (append (pa.zeros N) Ds))

(define pa.mag-mul
  A B -> (pa.mag-normalize (pa.mag-mul-loop A B 0 [])))

(define pa.mag-mul-loop
  _ [] _ Acc -> Acc
  A [B | Bs] Shift Acc ->
    (pa.mag-mul-loop A Bs (+ Shift 1)
      (pa.mag-add Acc (pa.mag-shift (pa.mag-mul-digit A B) Shift))))

(define pa.multiply
  A B -> (simple-error "pa.multiply: invalid bigint")
    where (not (and (pa.valid-bi? A) (pa.valid-bi? B)))
  [0] _ -> [0]
  _ [0] -> [0]
  [SA | As] [SB | Bs] -> (pa.bi (* SA SB) (pa.mag-mul As Bs)))

(define pa.mag-qdigit
  Cur Div Lo Hi -> Lo where (= Lo Hi)
  Cur Div Lo Hi ->
    (let Mid (pa.small-quot (+ (+ Lo Hi) 1) 2)
          P (pa.mag-mul-digit Div Mid)
          C (pa.mag-compare P Cur)
          (if (= C 1)
              (pa.mag-qdigit Cur Div Lo (- Mid 1))
              (pa.mag-qdigit Cur Div Mid Hi))))

(define pa.mag-divmod
  _ [] -> (simple-error "pa.mag-divmod: divide by zero")
  A B -> (pa.mag-divmod-msb (reverse (pa.mag-normalize A))
                            (pa.mag-normalize B) [] []))

(define pa.mag-divmod-msb
  [] _ QAcc R -> [(pa.mag-normalize QAcc) R]
  [D | Ds] Div QAcc R ->
    (let Cur (pa.mag-normalize [D | R])
          QD (pa.mag-qdigit Cur Div 0 65535)
          NextR (pa.mag-sub Cur (pa.mag-mul-digit Div QD))
          (pa.mag-divmod-msb Ds Div [QD | QAcc] NextR)))

\\ Quotient truncates toward zero; remainder has the dividend's sign.
(define pa.divmod
  A B -> (simple-error "pa.divmod: invalid bigint")
    where (not (and (pa.valid-bi? A) (pa.valid-bi? B)))
  _ [0] -> (simple-error "pa.divmod: divide by zero")
  [0] _ -> [[0] [0]]
  [SA | As] [SB | Bs] ->
    (let QR (pa.mag-divmod As Bs)
          Q (pa.bi (* SA SB) (hd QR))
          R (pa.bi SA (hd (tl QR)))
          [Q R]))

(define pa.divide
  A B -> (hd (pa.divmod A B)))

(define pa.remainder
  A B -> (hd (tl (pa.divmod A B))))

(define pa.mag-div-small
  A D -> (pa.mag-div-small-msb (reverse A) D [] 0))

(define pa.mag-div-small-msb
  [] _ QAcc R -> [(pa.mag-normalize QAcc) R]
  [A | As] D QAcc R ->
    (let QR (pa.small-divmod (+ (* R 65536) A) D)
         (pa.mag-div-small-msb As D [(hd QR) | QAcc] (hd (tl QR)))))

(define pa.digit-char
  0 -> "0"
  1 -> "1"
  2 -> "2"
  3 -> "3"
  4 -> "4"
  5 -> "5"
  6 -> "6"
  7 -> "7"
  8 -> "8"
  9 -> "9")

(define pa.join-strings
  [] -> ""
  [S | Ss] -> (cn S (pa.join-strings Ss)))

(define pa.mag-decimal
  [] Digits -> (pa.join-strings Digits)
  Mag Digits ->
    (let QR (pa.mag-div-small Mag 10)
         (pa.mag-decimal (hd QR)
                         [(pa.digit-char (hd (tl QR))) | Digits])))

(define pa.to-decimal
  X -> (simple-error "pa.to-decimal: invalid bigint") where (not (pa.valid-bi? X))
  [0] -> "0"
  [1 | Ds] -> (pa.mag-decimal Ds [])
  [-1 | Ds] -> (cn "-" (pa.mag-decimal Ds [])))

(define pa.char-digit
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
  _ -> (simple-error "pa.from-decimal: non-digit"))

(define pa.decimal-loop
  "" Mag -> (pa.bi 1 Mag)
  S Mag -> (pa.decimal-loop (tlstr S)
             (pa.mag-add (pa.mag-mul-digit Mag 10)
                         (pa.mag-from-small (pa.char-digit (hdstr S))))))

(define pa.from-decimal
  "" -> (simple-error "pa.from-decimal: empty")
  "0" -> [0]
  "-0" -> (simple-error "pa.from-decimal: negative zero")
  S -> (simple-error "pa.from-decimal: leading zero")
    where (= (hdstr S) "0")
  S -> (let T (tlstr S)
         (if (= T "")
             (simple-error "pa.from-decimal: missing magnitude")
             (if (= (hdstr T) "0")
                 (simple-error "pa.from-decimal: leading zero")
                 (pa.negate (pa.decimal-loop T [])))))
    where (= (hdstr S) "-")
  S -> (simple-error "pa.from-decimal: plus is not canonical")
    where (= (hdstr S) "+")
  S -> (pa.decimal-loop S []))

\\ Nonnegative logical-time helpers fail closed.
(define pa.time-compare
  A B -> (simple-error "pa.time-compare: negative time")
    where (not (and (pa.nonnegative? A) (pa.nonnegative? B)))
  A B -> (pa.compare A B))

(define pa.time-add
  A B -> (simple-error "pa.time-add: negative time")
    where (not (and (pa.nonnegative? A) (pa.nonnegative? B)))
  A B -> (pa.add A B))

(define pa.time-subtract
  A B -> (simple-error "pa.time-subtract: negative result")
    where (or (not (and (pa.nonnegative? A) (pa.nonnegative? B)))
              (= (pa.compare A B) -1))
  A B -> (pa.subtract A B))
