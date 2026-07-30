\* ADR 0003 portable signed base-10,000 software integers. *\

\* Truncating divmod of a nonnegative host natural by a positive host
   natural in O(log(N/D)) host operations instead of repeated
   subtraction's O(N/D): collect [Weight Bit] pairs with
   Weight = Bit * D by doubling, largest weight first, then subtract
   them in descending order while summing the Bits -- the same
   descending-weights walk as urdr.canonical.exact-natural-weights?.
   Doubling is guarded by (<= Weight (- N Weight)), which is
   2*Weight <= N rewritten to use only subtraction, so Weight, Bit,
   the quotient, and the remainder all stay within [0, N]; no host
   intermediate ever exceeds N itself, hence never the reviewed
   ADR 0003 bound of 99,990,000 that every caller already respects.
   Divisor 0 is a caller error and diverges, exactly like the previous
   repeated-subtraction loop; every semantic caller either rejects it
   first (urdr.int.divmod's divide-by-zero) or passes a constant. *\

(define urdr.int.small.divmod.down
  N [] Q -> [Q N]
  N [[W B] | Ws] Q ->
    (if (>= N W)
        (urdr.int.small.divmod.down (- N W) Ws (+ Q B))
        (urdr.int.small.divmod.down N Ws Q)))

(define urdr.int.small.divmod.up
  N W B Ws ->
    (if (> W (- N W))
        (urdr.int.small.divmod.down N [[W B] | Ws] 0)
        (urdr.int.small.divmod.up N (+ W W) (+ B B) [[W B] | Ws])))

(define urdr.int.small.divmod
  N D -> (if (< N D)
             [0 N]
             (urdr.int.small.divmod.up N D 1 [])))

(define urdr.int.small.quot
  N D -> (hd (urdr.int.small.divmod N D)))

(define urdr.int.list.repeat
  0 _ -> []
  N X -> [X | (urdr.int.list.repeat (- N 1) X)])

(define urdr.int.mag.drop-high-zeroes
  [] -> []
  [0 | Ds] -> (urdr.int.mag.drop-high-zeroes Ds)
  Ds -> Ds)

(define urdr.int.mag.normalize
  Ds -> (reverse (urdr.int.mag.drop-high-zeroes (reverse Ds))))

(define urdr.int.limbs.check
  [] -> [ok]
  Ds -> (if (cons? Ds)
            (let D (hd Ds)
              (if (and (integer? D) (and (>= D 0) (< D 10000)))
                  (urdr.int.limbs.check (tl Ds))
                  [error invalid-limb]))
            [error improper-limbs]))

(define urdr.int.make
  Sign Limbs ->
    (if (not (and (integer? Sign)
                  (or (= Sign -1) (or (= Sign 0) (= Sign 1)))))
        [error invalid-sign]
        (let Checked (urdr.int.limbs.check Limbs)
          (if (= (hd Checked) error)
              Checked
              (let Normal (urdr.int.mag.normalize Limbs)
                (if (= Normal [])
                    [ok [big 0 []]]
                    (if (= Sign 0)
                        [error zero-sign-with-magnitude]
                        [ok [big Sign Normal]])))))))

(define urdr.int.validate
  [big Sign Limbs] ->
    (let Made (urdr.int.make Sign Limbs)
      (if (= (hd Made) error)
          Made
          (if (= (hd (tl Made)) [big Sign Limbs])
              [ok [big Sign Limbs]]
              [error noncanonical-integer])))
  _ -> [error invalid-integer])

(define urdr.int.valid?
  X -> (= (hd (urdr.int.validate X)) ok))

(define urdr.int.zero
  -> [big 0 []])

(define urdr.int.one
  -> [big 1 [1]])

(define urdr.int.raw.sign
  [big S _] -> S)

(define urdr.int.raw.mag
  [big _ Ds] -> Ds)

(define urdr.int.raw.zero?
  [big 0 []] -> true
  _ -> false)

(define urdr.int.raw.negative?
  [big -1 _] -> true
  _ -> false)

(define urdr.int.raw.make
  _ [] -> [big 0 []]
  S Ds -> (let N (urdr.int.mag.normalize Ds)
            (if (= N [])
                [big 0 []]
                [big S N])))

(define urdr.int.mag.from-small.loop
  0 -> []
  N -> (let QR (urdr.int.small.divmod N 10000)
         [(hd (tl QR)) | (urdr.int.mag.from-small.loop (hd QR))]))

(define urdr.int.from-small
  N -> (if (not (integer? N))
           [error invalid-host-integer]
           (if (or (> N 99990000) (< N -99990000))
               [error unsafe-host-integer]
               (if (= N 0)
                   [ok (urdr.int.zero)]
                   (if (< N 0)
                       [ok [big -1
                             (urdr.int.mag.from-small.loop (- 0 N))]]
                       [ok [big 1
                             (urdr.int.mag.from-small.loop N)]])))))

(define urdr.int.raw.from-small
  N -> (hd (tl (urdr.int.from-small N))))

\* Inverse of from-small over the same host-safe window. Limbs are
   little-endian (ADR 0003): a magnitude [D0 D1] denotes
   D0 + 10000 * D1, so the fold below weights each later limb, never
   the accumulator. A magnitude wider than two limbs, or one that
   decodes above 99990000, leaves the window from-small accepts and
   fails closed (unsafe-host-integer) before any host arithmetic
   could overflow a port's small integers. *\

(define urdr.int.mag.to-small
  [] -> 0
  [D | Ds] -> (+ D (* 10000 (urdr.int.mag.to-small Ds))))

(define urdr.int.small-of.checked
  [big 0 []] -> [ok 0]
  [big S Ds] ->
    (if (> (length Ds) 2)
        [error unsafe-host-integer]
        (let N (urdr.int.mag.to-small Ds)
          (if (> N 99990000)
              [error unsafe-host-integer]
              [ok (if (= S -1) (- 0 N) N)]))))

(define urdr.int.small-of
  X -> (let V (urdr.int.validate X)
         (if (= (hd V) error)
             V
             (urdr.int.small-of.checked X))))

(define urdr.int.mag.compare.same-length
  [] [] -> 0
  [A | As] [B | Bs] ->
    (if (> A B)
        1
        (if (< A B)
            -1
            (urdr.int.mag.compare.same-length As Bs))))

(define urdr.int.mag.compare
  A B -> (let LA (length A)
              LB (length B)
           (if (> LA LB)
               1
               (if (< LA LB)
                   -1
                   (urdr.int.mag.compare.same-length
                     (reverse A) (reverse B))))))

(define urdr.int.raw.compare
  [big SA A] [big SB B] ->
    (if (> SA SB)
        1
        (if (< SA SB)
            -1
            (if (= SA 0)
                0
                (if (= SA 1)
                    (urdr.int.mag.compare A B)
                    (- 0 (urdr.int.mag.compare A B)))))))

(define urdr.int.compare
  A B -> (let VA (urdr.int.validate A)
               VB (urdr.int.validate B)
            (if (= (hd VA) error)
                VA
                (if (= (hd VB) error)
                    VB
                    [ok (urdr.int.raw.compare A B)]))))

(define urdr.int.mag.add.carry
  [] [] 0 -> []
  [] [] C -> [C]
  [A | As] [] C ->
    (let QR (urdr.int.small.divmod (+ A C) 10000)
      [(hd (tl QR)) |
        (urdr.int.mag.add.carry As [] (hd QR))])
  [] [B | Bs] C ->
    (let QR (urdr.int.small.divmod (+ B C) 10000)
      [(hd (tl QR)) |
        (urdr.int.mag.add.carry [] Bs (hd QR))])
  [A | As] [B | Bs] C ->
    (let QR (urdr.int.small.divmod (+ (+ A B) C) 10000)
      [(hd (tl QR)) |
        (urdr.int.mag.add.carry As Bs (hd QR))]))

(define urdr.int.mag.add
  A B -> (urdr.int.mag.add.carry A B 0))

(define urdr.int.mag.sub.borrow
  [] [] 0 -> []
  [A | As] [] Borrow ->
    (let V (- A Borrow)
      (if (< V 0)
          [(+ V 10000) | (urdr.int.mag.sub.borrow As [] 1)]
          [V | (urdr.int.mag.sub.borrow As [] 0)]))
  [A | As] [B | Bs] Borrow ->
    (let V (- (- A B) Borrow)
      (if (< V 0)
          [(+ V 10000) | (urdr.int.mag.sub.borrow As Bs 1)]
          [V | (urdr.int.mag.sub.borrow As Bs 0)])))

(define urdr.int.mag.sub
  A B -> (urdr.int.mag.normalize (urdr.int.mag.sub.borrow A B 0)))

(define urdr.int.raw.negate
  [big 0 []] -> [big 0 []]
  [big S Ds] -> [big (- 0 S) Ds])

(define urdr.int.negate
  X -> (let V (urdr.int.validate X)
         (if (= (hd V) error)
             V
             [ok (urdr.int.raw.negate X)])))

(define urdr.int.raw.add
  [big 0 []] B -> B
  A [big 0 []] -> A
  [big SA A] [big SB B] ->
    (if (= SA SB)
        (urdr.int.raw.make SA (urdr.int.mag.add A B))
        (let C (urdr.int.mag.compare A B)
          (if (= C 0)
              (urdr.int.zero)
              (if (> C 0)
                  (urdr.int.raw.make SA (urdr.int.mag.sub A B))
                  (urdr.int.raw.make SB (urdr.int.mag.sub B A)))))))

(define urdr.int.binary.checked
  A B Operation ->
    (let VA (urdr.int.validate A)
         VB (urdr.int.validate B)
      (if (= (hd VA) error)
          VA
          (if (= (hd VB) error)
              VB
              [ok (if (= Operation add)
                      (urdr.int.raw.add A B)
                      (if (= Operation subtract)
                          (urdr.int.raw.subtract A B)
                          (urdr.int.raw.multiply A B)))]))))

(define urdr.int.add
  A B -> (urdr.int.binary.checked A B add))

(define urdr.int.raw.subtract
  A B -> (urdr.int.raw.add A (urdr.int.raw.negate B)))

(define urdr.int.subtract
  A B -> (urdr.int.binary.checked A B subtract))

(define urdr.int.mag.mul-digit.carry
  [] 0 _ -> []
  [] Carry _ -> (urdr.int.mag.from-small.loop Carry)
  [A | As] Carry D ->
    (let QR (urdr.int.small.divmod (+ (* A D) Carry) 10000)
      [(hd (tl QR)) |
        (urdr.int.mag.mul-digit.carry As (hd QR) D)]))

(define urdr.int.mag.mul-digit
  _ 0 -> []
  A D -> (urdr.int.mag.normalize
           (urdr.int.mag.mul-digit.carry A 0 D)))

(define urdr.int.mag.mul.rows
  _ [] _ Acc -> Acc
  A [B | Bs] Shift Acc ->
    (let Row (append (urdr.int.list.repeat Shift 0)
                      (urdr.int.mag.mul-digit A B))
      (urdr.int.mag.mul.rows A Bs (+ Shift 1)
        (urdr.int.mag.add Acc Row))))

(define urdr.int.mag.mul
  A B -> (urdr.int.mag.normalize
           (urdr.int.mag.mul.rows A B 0 [])))

(define urdr.int.raw.multiply
  [big 0 []] _ -> [big 0 []]
  _ [big 0 []] -> [big 0 []]
  [big SA A] [big SB B] ->
    (urdr.int.raw.make (* SA SB) (urdr.int.mag.mul A B)))

(define urdr.int.multiply
  A B -> (urdr.int.binary.checked A B multiply))

(define urdr.int.raw.mul-small
  X N -> (urdr.int.raw.multiply X (urdr.int.raw.from-small N)))

(define urdr.int.mag.qdigit.search
  Den Rem Lo Hi ->
    (if (> Lo Hi)
        (- Lo 1)
        (let Mid (urdr.int.small.quot (+ Lo Hi) 2)
             C (urdr.int.mag.compare
                 (urdr.int.mag.mul-digit Den Mid) Rem)
          (if (> C 0)
              (urdr.int.mag.qdigit.search Den Rem Lo (- Mid 1))
              (urdr.int.mag.qdigit.search Den Rem (+ Mid 1) Hi)))))

(define urdr.int.mag.divmod.step
  [] _ Qbe Rem ->
    [(urdr.int.mag.normalize Qbe) (urdr.int.mag.normalize Rem)]
  [D | Ds] Den Qbe Rem ->
    (let R2 (urdr.int.mag.normalize [D | Rem])
         QD (urdr.int.mag.qdigit.search Den R2 0 9999)
         R3 (urdr.int.mag.sub R2 (urdr.int.mag.mul-digit Den QD))
      (urdr.int.mag.divmod.step Ds Den [QD | Qbe] R3)))

(define urdr.int.mag.divmod
  Num Den ->
    (if (< (urdr.int.mag.compare Num Den) 0)
        [[] Num]
        (urdr.int.mag.divmod.step (reverse Num) Den [] [])))

(define urdr.int.raw.divmod
  [big 0 []] _ -> [division [big 0 []] [big 0 []]]
  [big SA A] [big SB B] ->
    (let QR (urdr.int.mag.divmod A B)
      [division
        (urdr.int.raw.make (* SA SB) (hd QR))
        (urdr.int.raw.make SA (hd (tl QR)))]))

(define urdr.int.divmod
  A B -> (let VA (urdr.int.validate A)
               VB (urdr.int.validate B)
            (if (= (hd VA) error)
                VA
                (if (= (hd VB) error)
                    VB
                    (if (urdr.int.raw.zero? B)
                        [error divide-by-zero]
                        [ok (urdr.int.raw.divmod A B)])))))

(define urdr.int.mag.div-small.step
  [] _ Carry Qbe -> [(urdr.int.mag.normalize Qbe) Carry]
  [D | Ds] Div Carry Qbe ->
    (let QR (urdr.int.small.divmod (+ (* Carry 10000) D) Div)
      (urdr.int.mag.div-small.step Ds Div
        (hd (tl QR)) [(hd QR) | Qbe])))

(define urdr.int.mag.div-small
  Ds Div -> (urdr.int.mag.div-small.step (reverse Ds) Div 0 []))

(define urdr.int.raw.div-small
  [big 0 []] _ -> [[big 0 []] 0]
  [big 1 Ds] Div ->
    (let QR (urdr.int.mag.div-small Ds Div)
      [(urdr.int.raw.make 1 (hd QR)) (hd (tl QR))]))

(define urdr.int.decimal-octet?
  B -> (and (integer? B) (and (>= B 48) (<= B 57))))

(define urdr.int.decimal.parse.loop
  [] N -> [ok N]
  [B | Bs] N ->
    (if (urdr.int.decimal-octet? B)
        (urdr.int.decimal.parse.loop Bs
          (urdr.int.raw.add
            (urdr.int.raw.mul-small N 10)
            (urdr.int.raw.from-small (- B 48))))
        [error invalid-decimal-octet]))

(define urdr.int.from-decimal-octets.valid
  [] -> [error invalid-decimal]
  [45] -> [error invalid-decimal]
  [45 48 | _] -> [error noncanonical-decimal]
  [45 | Bs] ->
    (let Parsed (urdr.int.decimal.parse.loop Bs (urdr.int.zero))
      (if (= (hd Parsed) error)
          Parsed
          [ok (urdr.int.raw.negate (hd (tl Parsed)))]))
  [48] -> [ok [big 0 []]]
  [48 | _] -> [error noncanonical-decimal]
  Bs -> (urdr.int.decimal.parse.loop Bs (urdr.int.zero)))

(define urdr.int.octets.check
  [] -> [ok]
  Bs -> (if (cons? Bs)
            (let B (hd Bs)
              (if (and (integer? B) (and (>= B 0) (<= B 255)))
                  (urdr.int.octets.check (tl Bs))
                  [error invalid-octet]))
            [error improper-octets]))

(define urdr.int.from-decimal-octets
  Bs -> (let Checked (urdr.int.octets.check Bs)
          (if (= (hd Checked) error)
              Checked
              (urdr.int.from-decimal-octets.valid Bs))))

(define urdr.int.decimal.byte
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

(define urdr.int.decimal.limb4
  N -> (let A (urdr.int.small.divmod N 1000)
            B (urdr.int.small.divmod (hd (tl A)) 100)
            C (urdr.int.small.divmod (hd (tl B)) 10)
         [(urdr.int.decimal.byte (hd A))
          (urdr.int.decimal.byte (hd B))
          (urdr.int.decimal.byte (hd C))
          (urdr.int.decimal.byte (hd (tl C)))]))

(define urdr.int.decimal.drop-leading
  [48 | Rest] -> (urdr.int.decimal.drop-leading Rest)
  [] -> [48]
  Ds -> Ds)

(define urdr.int.decimal.limbs
  [] -> []
  [D | Ds] ->
    (append (urdr.int.decimal.limb4 D)
            (urdr.int.decimal.limbs Ds)))

(define urdr.int.raw.to-decimal-octets
  [big 0 []] -> [48]
  [big 1 Ds] ->
    (let Rev (reverse Ds)
      (append
        (urdr.int.decimal.drop-leading
          (urdr.int.decimal.limb4 (hd Rev)))
        (urdr.int.decimal.limbs (tl Rev))))
  [big -1 Ds] ->
    [45 | (urdr.int.raw.to-decimal-octets [big 1 Ds])])

(define urdr.int.to-decimal-octets
  N -> (let Valid (urdr.int.validate N)
         (if (= (hd Valid) error)
             Valid
             [ok (urdr.int.raw.to-decimal-octets N)])))

(define urdr.time.check
  N -> (let Valid (urdr.int.validate N)
         (if (= (hd Valid) error)
             Valid
             (if (urdr.int.raw.negative? N)
                 [error negative-time]
                 [ok N]))))

(define urdr.time.compare
  A B -> (let VA (urdr.time.check A)
               VB (urdr.time.check B)
            (if (= (hd VA) error)
                VA
                (if (= (hd VB) error)
                    VB
                    [ok (urdr.int.raw.compare A B)]))))

(define urdr.time.add
  A B -> (let VA (urdr.time.check A)
               VB (urdr.time.check B)
            (if (= (hd VA) error)
                VA
                (if (= (hd VB) error)
                    VB
                    [ok (urdr.int.raw.add A B)]))))

(define urdr.time.subtract
  A B -> (let VA (urdr.time.check A)
               VB (urdr.time.check B)
            (if (= (hd VA) error)
                VA
                (if (= (hd VB) error)
                    VB
                    (if (< (urdr.int.raw.compare A B) 0)
                        [error time-underflow]
                        [ok (urdr.int.raw.subtract A B)])))))

(define urdr.time.successor
  A -> (let Valid (urdr.time.check A)
         (if (= (hd Valid) error)
             Valid
             [ok (urdr.int.raw.add A (urdr.int.one))])))
