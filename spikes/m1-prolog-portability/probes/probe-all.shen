\\ Wave G Prolog portability probes (ADR 0004 Decision 3).
\\
\\ Status: ANALYSIS ONLY. Nothing here certifies anything until the
\\ four-port admissibility gate passes.
\\
\\ Every probe prints exactly one line:
\\
\\     PROBE|<id>|<canonical-rendering>
\\
\\ The rendering is produced by the self-contained printer below, never by a
\\ port's own value writer, so runtime variable naming, gensym counters, and
\\ launcher chatter cannot leak into the compared bytes. Any probe that raises
\\ renders as the fixed token <error> (message text is port-specific prose and
\\ is deliberately not compared).
\\
\\ This file is self-contained on purpose: it uses no (load), so `load`
\\ semantics are not a variable in the experiment.

\\ ---------------------------------------------------------------- printer

(define upp.items
  [X] -> (upp X)
  [X | Y] -> (@s (upp X) (@s " " (upp.items Y)))
  X -> (@s "| " (upp X)))

(define upp
  [] -> "[]"
  X -> (@s "[" (@s (upp.items X) "]")) where (cons? X)
  X -> (str X))

(define uprobe
  Id F -> (output "PROBE|~A|~A~%" Id (trap-error (upp (thaw F)) (/. E "<error>"))))

\\ A boolean-ish classifier, so that a probe can report a verdict without ever
\\ printing a runtime value whose text is port-specific.
(define uclass
  false -> failed
  X -> X)

\\ ------------------------------------------------- A: enumeration order

(defprolog uparent
  abe homer <--;
  homer bart <--;
  homer lisa <--;
  abe herb <--;)

(defprolog ugrandparent
  X Z <-- (uparent X Y) (uparent Y Z);)

(defprolog umember
  X [X | _] <--;
  X [_ | Y] <-- (umember X Y);)

(defprolog uappend
  [] X X <--;
  [X | Xs] Y [X | Zs] <-- (uappend Xs Y Zs);)

\\ Three clause heads, two of which match a cons and two of which match [].
(defprolog utag
  [] nil <--;
  [_ | _] cons <--;
  _ any <--;)

\\ A small acyclic graph, enumerated by a doubly recursive predicate.
(defprolog uedge
  a b <--;
  a c <--;
  b d <--;
  c d <--;
  d e <--;)

(defprolog upath
  X Y [X Y] <-- (uedge X Y);
  X Z [X | P] <-- (uedge X Y) (upath Y Z P);)

(uprobe A1-first-fact (freeze (prolog? (uparent abe W) (return W))))
(uprobe A2-first-rule (freeze (prolog? (ugrandparent abe W) (return W))))
(uprobe A3-facts-findall
        (freeze (prolog? (findall [X Y] (uparent X Y) L) (return L))))
(uprobe A4-rule-findall
        (freeze (prolog? (findall W (ugrandparent abe W) L) (return L))))
(uprobe A5-member-findall
        (freeze (prolog? (findall X (umember X [a b c]) L) (return L))))
(uprobe A6-member-dup
        (freeze (prolog? (findall X (umember X [a b a c a]) L) (return L))))
(uprobe A7-append-splits
        (freeze (prolog? (findall [A B] (uappend A B [1 2 3]) L) (return L))))
(uprobe A8-heads-nil
        (freeze (prolog? (findall T (utag [] T) L) (return L))))
(uprobe A9-heads-cons
        (freeze (prolog? (findall T (utag [z] T) L) (return L))))
(uprobe A10-heads-atom
        (freeze (prolog? (findall T (utag zz T) L) (return L))))
(uprobe A11-paths
        (freeze (prolog? (findall P (upath a e P) L) (return L))))
(uprobe A12-first-path
        (freeze (prolog? (upath a e P) (return P))))

\\ --------------------------------------------- B: backtracking / retry

(defprolog upair
  X Y <-- (umember X [1 2 3]) (umember Y [a b]);)

\\ The second conjunct rejects one value of the first, forcing re-satisfaction
\\ of the first conjunct after a mid-conjunction failure.
(defprolog ufiltered
  X <-- (umember X [1 2 3 4]) (umember X [2 4 6]);)

\\ A goal whose later conjunct fails for every solution of the earlier one.
(defprolog udead
  X <-- (umember X [1 2 3]) (umember X [7 8]);)

\\ Backtracking that must unwind bindings made by a deeper recursive call.
(defprolog usplit3
  A B C <-- (uappend A R [1 2 3]) (uappend B C R);)

(uprobe B1-nested-pairs
        (freeze (prolog? (findall [X Y] (upair X Y) L) (return L))))
(uprobe B2-refilter
        (freeze (prolog? (findall X (ufiltered X) L) (return L))))
(uprobe B3-dead-end
        (freeze (prolog? (findall X (udead X) L) (return L))))
(uprobe B4-dead-end-query
        (freeze (uclass (prolog? (udead X) (return found)))))
(uprobe B5-triple-split
        (freeze (prolog? (findall [A B C] (usplit3 A B C) L) (return L))))
(uprobe B6-deep-append
        (freeze (prolog? (findall A (uappend A B [1 2 3 4 5]) L) (return L))))

\\ ------------------------------------------------------------- C: cut

\\ Clause-local cut: the cut in the first clause must prune the remaining
\\ clauses for this call.
(defprolog ucut1
  a one <-- !;
  a two <--;
  b three <--;)

\\ Cut inside a conjunction: it must prune both the remaining solutions of the
\\ preceding goal and the remaining clauses.
(defprolog ucut2
  X <-- (umember X [1 2 3]) !;
  X <-- (is X 99);)

\\ Cut in the middle of a conjunction: goals to the right of the cut must still
\\ backtrack normally.
(defprolog ucut3
  X Y <-- (umember X [1 2]) ! (umember Y [a b]);
  X Y <-- (is X 99) (is Y zz);)

\\ Cut transparency: a cut inside a called predicate must be local to that
\\ predicate and must not prune the caller's choice points.
(defprolog ucutlocal
  X Y <-- (umember X [1 2]) (ucut1 a Y);)

\\ Cut in a recursive predicate: once a match is found, stop.
(defprolog ufirstmatch
  X [X | _] <-- !;
  X [_ | Y] <-- (ufirstmatch X Y);)

\\ Negation as failure, spelled with cut, specialised to one relation.
(defprolog unotparent
  X Y <-- (uparent X Y) ! (when false);
  _ _ <--;)

\\ Negation as failure over a generic goal, via the kernel's call/1.
(defprolog unot
  G <-- (call G) ! (when false);
  _ <--;)

\\ Generate-and-test using negation as failure, which only enumerates correctly
\\ if the cut inside unotparent is local to it.
(defprolog uchildless
  X <-- (umember X [abe homer bart lisa herb]) (unotparent X Y);)

(uprobe C1-clause-cut
        (freeze (prolog? (findall R (ucut1 a R) L) (return L))))
(uprobe C2-clause-cut-other
        (freeze (prolog? (findall R (ucut1 b R) L) (return L))))
(uprobe C3-conj-cut
        (freeze (prolog? (findall X (ucut2 X) L) (return L))))
(uprobe C4-mid-cut
        (freeze (prolog? (findall [X Y] (ucut3 X Y) L) (return L))))
(uprobe C5-cut-local
        (freeze (prolog? (findall [X Y] (ucutlocal X Y) L) (return L))))
(uprobe C6-firstmatch
        (freeze (prolog? (findall X (ufirstmatch X [a b c]) L) (return L))))
(uprobe C7-naf-true
        (freeze (uclass (prolog? (unotparent abe homer) (return holds)))))
(uprobe C8-naf-false
        (freeze (uclass (prolog? (unotparent abe zzz) (return holds)))))
(uprobe C9-naf-generic-true
        (freeze (uclass (prolog? (unot (uparent abe homer)) (return holds)))))
(uprobe C10-naf-generic-false
        (freeze (uclass (prolog? (unot (uparent abe zzz)) (return holds)))))
(uprobe C11-naf-enumerate
        (freeze (prolog? (findall X (uchildless X) L) (return L))))

\\ --------------------------------------------------------- D: failure

(defprolog uempty
  zzz zzz <--;)

(defprolog umidfail
  X <-- (umember X [1 2 3]) (when false) (is X 7);)

(defprolog udeepfail
  X <-- (uappend X Y [1 2 3]) (umember 9 X);)

(uprobe D1-fact-miss
        (freeze (uclass (prolog? (uparent zzz W) (return W)))))
(uprobe D2-head-mismatch
        (freeze (uclass (prolog? (uempty aaa bbb) (return holds)))))
(uprobe D3-findall-empty
        (freeze (prolog? (findall X (uparent zzz X) L) (return L))))
(uprobe D4-mid-conjunction
        (freeze (uclass (prolog? (umidfail X) (return holds)))))
(uprobe D5-mid-conjunction-findall
        (freeze (prolog? (findall X (umidfail X) L) (return L))))
(uprobe D6-deep-failure
        (freeze (uclass (prolog? (udeepfail X) (return holds)))))
(uprobe D7-last-literal-fails
        (freeze (uclass (prolog? (uparent abe homer) (when false) (return holds)))))
(uprobe D8-when-false
        (freeze (uclass (prolog? (when false) (return holds)))))
(uprobe D9-when-true
        (freeze (uclass (prolog? (when true) (return holds)))))
(uprobe D10-unify-clash
        (freeze (uclass (prolog? (is a b) (return holds)))))
(uprobe D11-findall-of-failure-then-success
        (freeze (prolog? (findall X (umember X []) L) (return L))))

\\ ------------------------------------- E: variables and unification

\\ Reports varhood without ever printing a runtime variable.
(defprolog uvarness
  X unbound <-- (var? X) !;
  _ bound <--;)

\\ Aliasing: two variables unified with each other, then one bound.
(defprolog ualias
  Z <-- (is X Y) (is X 5) (is Z Y);)

\\ A recursive predicate whose clause variables must be renamed per call; if
\\ renaming leaked, the two levels would collide and this would fail.
(defprolog unocapture
  [X Y] [Y X] <--;)

(defprolog uswaptwice
  A C <-- (unocapture A B) (unocapture B C);)

\\ A head with a repeated variable. The kernel linearises this into a guard
\\ that is compiled to the occurs-checking unifier when *occurs* is set and to
\\ the plain one otherwise, so this is the observable occurs-check path. A
\\ directly written (is X Y) literal never occurs-checks on any port.
(defprolog usame
  X X yes <--;)

\\ The is/is! choice above is made when defprolog COMPILES the clause, not when
\\ the query runs, so the occurs-check-off variant must be defined while the
\\ flag is off. Both spellings are probed; the compile-time-vs-query-time
\\ binding of the flag is itself a portability question.
(occurs-check -)

(defprolog usameoff
  X X yes <--;)

(occurs-check +)

(uprobe E1-var-unbound
        (freeze (prolog? (uvarness X R) (return R))))
(uprobe E2-var-bound
        (freeze (prolog? (is X 3) (uvarness X R) (return R))))
(uprobe E3-alias
        (freeze (prolog? (ualias Z) (return Z))))
(uprobe E4-no-capture
        (freeze (prolog? (uswaptwice [p q] C) (return C))))
(uprobe E5-repeat-query-1
        (freeze (prolog? (findall X (umember X [a b c]) L) (return L))))
(uprobe E6-repeat-query-2
        (freeze (prolog? (findall X (umember X [a b c]) L) (return L))))
(uprobe E7-fresh-var-in-result
        (freeze (prolog? (uappend [1] X Y) (uvarness X R) (return R))))
(uprobe E8-same-ground
        (freeze (uclass (prolog? (usame p p R) (return R)))))
(uprobe E9-same-clash
        (freeze (uclass (prolog? (usame p q R) (return R)))))
(uprobe E10-occurs-default
        (freeze (uclass (prolog? (usame X [X] R) (return R)))))
(uprobe E11-occurs-on
        (freeze (do (occurs-check +)
                    (uclass (prolog? (usame X [X] R) (return R))))))
(uprobe E12-occurs-on-nested
        (freeze (uclass (prolog? (usame X [a [b X]] R) (return R)))))
(uprobe E13-occurs-off-compiled
        (freeze (uclass (prolog? (usameoff X [X] R) (return R)))))
(uprobe E14-occurs-off-ground
        (freeze (uclass (prolog? (usameoff p p R) (return R)))))
(uprobe E15-occurs-flag-is-compile-time
        (freeze (do (occurs-check -)
                    (let V (uclass (prolog? (usame X [X] R) (return R)))
                         (do (occurs-check +) V)))))
(uprobe E16-plain-is-never-occurs-checks
        (freeze (uclass (prolog? (is X [X]) (return holds)))))

\\ ------------------------------------- F: Shen values as Prolog terms

\\ ADR 0003 software integers: [big SIGN LITTLE-ENDIAN-BASE-10000-LIMBS].
(defprolog ubigsign
  [big S _] S <--;)

(defprolog ubiglimbs
  [big _ Ls] Ls <--;)

(defprolog ubigzero
  [big 0 []] <--;)

(defprolog ubigpos
  [big 1 _] <--;)

(defprolog ubigmember
  B [B | _] <--;
  B [_ | Bs] <-- (ubigmember B Bs);)

(defprolog ubigpositives
  B <-- (ubigmember B [[big 0 []] [big 1 [1]] [big -1 [7]] [big 1 [0 3]]])
        (ubigpos B);)

(defprolog usymtag
  urdr.world.tick tick <--;
  urdr.world-step step <--;
  _ unknown <--;)

(defprolog uimproper
  [X | Y] X Y <--;)

(defprolog unested
  [[a [b c]] d] ok <--;)

(uprobe F1-big-sign-zero
        (freeze (prolog? (ubigsign [big 0 []] S) (return S))))
(uprobe F2-big-sign-neg
        (freeze (prolog? (ubigsign [big -1 [1 2]] S) (return S))))
(uprobe F3-big-limbs
        (freeze (prolog? (ubiglimbs [big 1 [9999 0 1]] Ls) (return Ls))))
(uprobe F4-big-zero-match
        (freeze (uclass (prolog? (ubigzero [big 0 []]) (return holds)))))
(uprobe F5-big-zero-miss
        (freeze (uclass (prolog? (ubigzero [big 1 [1]]) (return holds)))))
(uprobe F6-big-filter
        (freeze (prolog? (findall B (ubigpositives B) L) (return L))))
(uprobe F7-big-unify-var
        (freeze (prolog? (is [big 1 [X 2]] [big 1 [5 2]]) (return X))))
(uprobe F8-symbols
        (freeze (prolog? (findall T
                                  (ubigmember T [urdr.world.tick urdr.world-step other])
                                  L)
                         (return L))))
(uprobe F9-symbol-tag
        (freeze (prolog? (usymtag urdr.world.tick T) (return T))))
(uprobe F10-symbol-tag-dash
        (freeze (prolog? (usymtag urdr.world-step T) (return T))))
(uprobe F11-improper
        (freeze (prolog? (uimproper [a | b] H T) (return [H T]))))
(uprobe F12-nested
        (freeze (prolog? (unested [[a [b c]] d] R) (return R))))
(uprobe F13-nested-miss
        (freeze (uclass (prolog? (unested [[a [b z]] d] R) (return R)))))
(uprobe F14-empty-list-term
        (freeze (prolog? (findall X (umember X [[] [a] []]) L) (return L))))
(uprobe F15-negative-integers
        (freeze (prolog? (findall X (umember X [-1 0 1 -10000]) L) (return L))))
(uprobe F16-large-integers
        (freeze (prolog? (findall X (umember X [9999 10000 123456789]) L) (return L))))

(output "PROBES COMPLETE~%")
