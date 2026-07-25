\\ Deterministic fixture implementations of the world module's abstract
\\ canonical, bigint, and PRNG interfaces.  Production implementations can be
\\ substituted without changing shen/world/world.shen.

(define urdr.canonical.equal?
  A B -> (= A B))

(define urdr.bigint.zero
  -> 0)

(define urdr.bigint.nonnegative?
  X -> (and (integer? X) (>= X 0)))

(define urdr.bigint.compare
  A B -> (if (< A B)
             less
             (if (> A B) greater equal)))

(define urdr.bigint.successor
  X -> (+ X 1))

(define urdr.prng.select
  State Coordinates [First | _]
  -> [urdr-prng-selection/v1
       (urdr.bigint.successor State)
       First])
