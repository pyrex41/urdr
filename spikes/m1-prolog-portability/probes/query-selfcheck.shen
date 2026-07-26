\\ Four-port self-check for the ADR 0004 Decision 3 fallback evaluator,
\\ shen/properties/query.shen.
\\
\\ Status: ANALYSIS ONLY. This is spike evidence that the fallback surface is
\\ portable where the Prolog surface is not. It is not the admissibility gate
\\ and it is not a Bifrost case.
\\
\\ Run from the repository root; the runner passes the same projection as the
\\ Prolog probes, so output is compared byte-for-byte across the four ports.

(define uqs.eval-forms
  [] -> loaded
  [[load _] | Forms] -> (uqs.eval-forms Forms)
  [Form | Forms] -> (let Ignored (eval Form) (uqs.eval-forms Forms)))

(define uqs.quiet-load
  File -> (uqs.eval-forms (read-file File)))

(uqs.quiet-load "shen/properties/query.shen")

(define uqs.items
  [X] -> (uqs.pp X)
  [X | Y] -> (@s (uqs.pp X) (@s " " (uqs.items Y)))
  X -> (@s "| " (uqs.pp X)))

(define uqs.pp
  [] -> "[]"
  X -> (@s "[" (@s (uqs.items X) "]")) where (cons? X)
  X -> (str X))

(define uqs.probe
  Id F -> (output "PROBE|~A|~A~%" Id (trap-error (uqs.pp (thaw F)) (/. E "<error>"))))

\\ A small transition system. States are canonical symbols; a second model uses
\\ record-like list states so the field and membership predicates are covered.
(define uqs.model
  -> [model [a b c d e]
            [[edge a b] [edge a c] [edge b d] [edge c d] [edge d e]]])

\\ A model with a state that violates an invariant, reachable only via c.
(define uqs.model2
  -> [model [[s 0 ok] [s 1 ok] [s 2 bad] [s 3 ok]]
            [[edge [s 0 ok] [s 1 ok]]
             [edge [s 1 ok] [s 2 bad]]
             [edge [s 1 ok] [s 3 ok]]
             [edge [s 3 ok] [s 0 ok]]]])

\\ A model whose invariant IS inductive.
(define uqs.model3
  -> [model [[s 0 ok] [s 1 ok]]
            [[edge [s 0 ok] [s 1 ok]] [edge [s 1 ok] [s 0 ok]]]])

(uqs.probe Q1-reach-hit
           (freeze (urdr.query.reachable (uqs.model) a [p-is e] 100)))
(uqs.probe Q2-reach-miss
           (freeze (urdr.query.reachable (uqs.model) b [p-is c] 100)))
(uqs.probe Q3-reach-self
           (freeze (urdr.query.reachable (uqs.model) a [p-is a] 100)))
(uqs.probe Q4-reach-order
           (freeze (urdr.query.reachable (uqs.model) a [p-is d] 100)))
(uqs.probe Q5-bound-exceeded
           (freeze (urdr.query.reachable (uqs.model) a [p-is e] 2)))
(uqs.probe Q6-bound-zero
           (freeze (urdr.query.reachable (uqs.model) a [p-is e] 0)))
(uqs.probe Q7-bad-bound
           (freeze (urdr.query.reachable (uqs.model) a [p-is e] -1)))
(uqs.probe Q8-malformed-model
           (freeze (urdr.query.reachable [not-a-model] a [p-is e] 10)))
(uqs.probe Q9-malformed-predicate
           (freeze (urdr.query.reachable (uqs.model) a [p-bogus] 10)))

(uqs.probe Q10-field-predicate
           (freeze (urdr.query.reachable (uqs.model2) [s 0 ok] [p-at 2 bad] 100)))
(uqs.probe Q11-member-predicate
           (freeze (urdr.query.reachable (uqs.model2) [s 0 ok] [p-holds 3] 100)))
(uqs.probe Q12-conjunction
           (freeze (urdr.query.reachable (uqs.model2)
                                         [s 0 ok]
                                         [p-and [p-at 2 ok] [p-at 1 3]]
                                         100)))
(uqs.probe Q13-disjunction
           (freeze (urdr.query.reachable (uqs.model2)
                                         [s 0 ok]
                                         [p-or [p-at 2 bad] [p-at 1 9]]
                                         100)))
(uqs.probe Q14-negation
           (freeze (urdr.query.reachable (uqs.model2)
                                         [s 0 ok]
                                         [p-not [p-at 2 ok]]
                                         100)))
(uqs.probe Q15-non-list-state
           (freeze (urdr.query.reachable (uqs.model) a [p-at 0 z] 100)))

(uqs.probe Q16-invariant-violated
           (freeze (urdr.query.invariant (uqs.model2) [s 0 ok] [p-at 2 ok] 100)))
(uqs.probe Q17-invariant-holds
           (freeze (urdr.query.invariant (uqs.model3) [s 0 ok] [p-at 2 ok] 100)))
(uqs.probe Q18-counterexample
           (freeze (urdr.query.counterexample (uqs.model2)
                                              [s 0 ok]
                                              [p-at 2 bad]
                                              100)))

(uqs.probe Q19-inductive-yes
           (freeze (urdr.query.inductive (uqs.model3) [[s 0 ok]] [p-at 2 ok])))
(uqs.probe Q20-inductive-no
           (freeze (urdr.query.inductive (uqs.model2) [[s 0 ok]] [p-at 2 ok])))
(uqs.probe Q21-inductive-bad-init
           (freeze (urdr.query.inductive (uqs.model3) [[s 9 bad]] [p-at 2 ok])))
(uqs.probe Q22-inductive-malformed
           (freeze (urdr.query.inductive [nope] [[s 0 ok]] [p-at 2 ok])))

\\ ADR 0003 software integers as states, to show the fallback carries the same
\\ value substrate the Prolog probes used.
(define uqs.bigmodel
  -> [model [[big 0 []] [big 1 [1]] [big 1 [2]]]
            [[edge [big 0 []] [big 1 [1]]]
             [edge [big 1 [1]] [big 1 [2]]]]])

(uqs.probe Q23-bigint-reach
           (freeze (urdr.query.reachable (uqs.bigmodel) [big 0 []] [p-is [big 1 [2]]] 100)))
(uqs.probe Q24-bigint-miss
           (freeze (urdr.query.reachable (uqs.bigmodel) [big 1 [2]] [p-is [big 0 []]] 100)))

(output "PROBES COMPLETE~%")
