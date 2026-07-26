\\ Wave G Prolog portability stress probes (ADR 0004 Decision 3).
\\
\\ Status: ANALYSIS ONLY.
\\
\\ probe-all.shen covers the four gate criteria named by ADR 0004 Decision 3
\\ (solution order, backtracking, cut, failure). This file exists because
\\ shen-lua does not run the Shen kernel's Prolog at all: it ships an
\\ independent native Lua reimplementation (prolog_engine.lua /
\\ prolog_compile.lua). Where two independent implementations agree, the
\\ agreement is coincidental rather than structural, so the surface is probed
\\ harder here: deep search, nested findall, cut under findall, dynamic
\\ predicates, modes, and the remaining kernel builtins.
\\
\\ Output contract is identical to probe-all.shen: one PROBE|<id>|<value> line
\\ per probe, rendered by a self-contained printer, errors flattened to
\\ <error>.

\\ ---------------------------------------------------------------- printer

(define spp.items
  [X] -> (spp X)
  [X | Y] -> (@s (spp X) (@s " " (spp.items Y)))
  X -> (@s "| " (spp X)))

(define spp
  [] -> "[]"
  X -> (@s "[" (@s (spp.items X) "]")) where (cons? X)
  X -> (str X))

(define sprobe
  Id F -> (output "PROBE|~A|~A~%" Id (trap-error (spp (thaw F)) (/. E "<error>"))))

(define sclass
  false -> failed
  X -> X)

\\ Length, so that a large result can be compared as a count rather than as an
\\ unreadable wall of text where that is the more useful signal.
(define slen
  [] -> 0
  [_ | Y] -> (+ 1 (slen Y)))

\\ ------------------------------------------- G: deep and large searches

(defprolog smember
  X [X | _] <--;
  X [_ | Y] <-- (smember X Y);)

(defprolog sappend
  [] X X <--;
  [X | Xs] Y [X | Zs] <-- (sappend Xs Y Zs);)

\\ Count down N levels of recursion, to exercise deep continuation chains.
(defprolog sdown
  0 done <-- !;
  N R <-- (when (> N 0)) (is M (- N 1)) (sdown M R);)

\\ Naive reverse, the classic backtracking-free but allocation-heavy benchmark.
(defprolog srev
  [] [] <--;
  [X | Xs] R <-- (srev Xs Rs) (sappend Rs [X] R);)

\\ Permutations: a large, order-sensitive search space.
(defprolog sselect
  X [X | Xs] Xs <--;
  X [Y | Ys] [Y | Zs] <-- (sselect X Ys Zs);)

(defprolog sperm
  [] [] <--;
  L [H | T] <-- (sselect H L R) (sperm R T);)

\\ A predicate whose solutions are themselves gathered by a nested findall.
(defprolog sinner
  X L <-- (findall Y (smember Y [X 0]) L);)

(defprolog souter
  P <-- (smember X [1 2 3]) (sinner X L) (is P [X L]);)

\\ Cut underneath findall: findall must still collect every solution of the
\\ cut-free part while the cut prunes only inside the called predicate.
(defprolog scutinner
  X first <-- (smember X [1 2]) !;
  _ second <--;)

(defprolog scutunder
  [X R] <-- (smember X [7 8]) (scutinner X R);)

\\ Many choice points, all of which ultimately fail.
(defprolog sallfail
  X <-- (smember X [1 2 3 4 5 6]) (when false);)

(sprobe G1-member-20
        (freeze (prolog? (findall X
                                  (smember X [1 2 3 4 5 6 7 8 9 10
                                              11 12 13 14 15 16 17 18 19 20])
                                  L)
                         (return L))))
(sprobe G2-append-6
        (freeze (prolog? (findall [A B] (sappend A B [1 2 3 4 5 6]) L)
                         (return L))))
(sprobe G3-nested-findall
        (freeze (prolog? (findall P (souter P) L) (return L))))
\\ Recursion-depth ladder. This is a RESOURCE limit rather than a semantic
\\ rule, but for gate purposes it is still a divergence: one fixed query
\\ succeeds on some ports and raises on others, so the compared bytes differ.
\\ It matters more than a usual resource limit here, because the whole point of
\\ ADR 0004's Prolog layer is search over transition relations, where depth is
\\ exactly the quantity that varies.
(sprobe G4-depth-100
        (freeze (sclass (prolog? (sdown 100 R) (return R)))))
(sprobe G4b-depth-500
        (freeze (sclass (prolog? (sdown 500 R) (return R)))))
(sprobe G4c-depth-1000
        (freeze (sclass (prolog? (sdown 1000 R) (return R)))))
(sprobe G4d-depth-1500
        (freeze (sclass (prolog? (sdown 1500 R) (return R)))))
(sprobe G5-depth-2000
        (freeze (sclass (prolog? (sdown 2000 R) (return R)))))
(sprobe G5b-depth-5000
        (freeze (sclass (prolog? (sdown 5000 R) (return R)))))
(sprobe G5c-depth-20000
        (freeze (sclass (prolog? (sdown 20000 R) (return R)))))
(sprobe G6-permutations-3
        (freeze (prolog? (findall P (sperm [a b c] P) L) (return L))))
(sprobe G7-permutations-4-count
        (freeze (slen (prolog? (findall P (sperm [a b c d] P) L) (return L)))))
(sprobe G8-naive-reverse
        (freeze (prolog? (srev [1 2 3 4 5 6 7 8] R) (return R))))
(sprobe G9-cut-under-findall
        (freeze (prolog? (findall R (scutunder R) L) (return L))))
(sprobe G10-all-fail
        (freeze (prolog? (findall X (sallfail X) L) (return L))))
(sprobe G11-select-order
        (freeze (prolog? (findall [X R] (sselect X [a b c] R) L) (return L))))
(sprobe G12-findall-unbound-template
        (freeze (prolog? (findall k (smember X [a b c]) L) (return L))))
(sprobe G13-findall-compound
        (freeze (prolog? (findall [X X] (smember X [a b]) L) (return L))))
(sprobe G14-nested-findall-twice
        (freeze (prolog? (findall L1 (sinner 5 L1) L) (return L))))

\\ ------------------------------------------------- H: dynamic clauses

\\ assert/retract mutate a predicate's clause list at run time. Both the clause
\\ store and its ordering are engine state, so this is a prime divergence
\\ candidate for an independent reimplementation. ADR 0004 Decision 3 requires
\\ Prolog queries to be pure, so this surface is out of the intended usage; it
\\ is probed because a divergence here would still be evidence about how far
\\ the engines differ.
\\
\\ Note the trailing ";" in each asserted clause: the kernel splices the clause
\\ straight into a generated defprolog, whose grammar requires the terminator.
\\ Without it every port reports a Prolog syntax error.

(sprobe H1-assertz-two
        (freeze (do (assertz [[sdyn a] <-- ;])
                    (assertz [[sdyn b] <-- ;])
                    (prolog? (findall X (sdyn X) L) (return L)))))
(sprobe H2-asserta-front
        (freeze (do (asserta [[sdyn z] <-- ;])
                    (prolog? (findall X (sdyn X) L) (return L)))))
(sprobe H3-first-solution
        (freeze (sclass (prolog? (sdyn X) (return X)))))
(sprobe H4-retract
        (freeze (do (retract [[sdyn a] <-- ;])
                    (prolog? (findall X (sdyn X) L) (return L)))))
(sprobe H5-retract-missing
        (freeze (do (retract [[sdyn qqq] <-- ;])
                    (prolog? (findall X (sdyn X) L) (return L)))))
(sprobe H6-assert-malformed
        (freeze (sclass (assertz [[sdyn c] <--]))))

\\ ------------------------------- I: modes and the remaining builtins

\\ A minus-moded head argument matches without binding: the caller must supply
\\ it ground, and an unbound caller argument must not be bound by the head.
(defprolog sminus
  (mode X -) X matched <--;
  _ _ nomatch <--;)

(defprolog splus
  X X matched <--;
  _ _ nomatch <--;)

\\ bind/2 is the non-unifying assignment builtin.
(defprolog sbindp
  X <-- (bind X hello);)

\\ Strings as terms. The result is projected onto a symbol so that no port's
\\ string writer can leak into the compared bytes.
(defprolog sstring
  "abc" yes <--;
  _ no <--;)

\\ A guard that calls an ordinary Shen function.
(defprolog sguard
  X <-- (smember X [1 2 3 4 5 6]) (when (> X 3));)

\\ Arithmetic through is/2 with a Shen expression on the right.
(defprolog sarith
  N R <-- (is R (* N N));)

(sprobe I1-mode-minus-ground
        (freeze (prolog? (sminus a a R) (return R))))
(sprobe I2-mode-minus-clash
        (freeze (prolog? (sminus a b R) (return R))))
(sprobe I3-mode-minus-unbound
        (freeze (prolog? (sminus X a R) (return R))))
(sprobe I4-mode-plus-unbound
        (freeze (prolog? (splus X a R) (return R))))
(sprobe I5-bind
        (freeze (prolog? (sbindp X) (return X))))
(sprobe I6-string-match
        (freeze (prolog? (sstring "abc" R) (return R))))
(sprobe I7-string-miss
        (freeze (prolog? (sstring "abd" R) (return R))))
(sprobe I8-guard
        (freeze (prolog? (findall X (sguard X) L) (return L))))
(sprobe I9-arith
        (freeze (prolog? (sarith 12 R) (return R))))
(sprobe I10-arith-big
        (freeze (prolog? (sarith 99999 R) (return R))))
(sprobe I11-multi-literal-query
        (freeze (prolog? (smember X [1 2 3]) (when (> X 2)) (return X))))
(sprobe I12-query-no-return
        (freeze (sclass (prolog? (smember 2 [1 2 3])))))

\\ --------------------------------------------- J: engine capacity

\\ shen.*prolog-memory* is the size of the bindings vector that call-prolog
\\ allocates for each query, so it is a hard ceiling on the number of Prolog
\\ variables a single query may allocate. It is a per-port constant that the
\\ pinned kernel version does not fix, and it is the mechanism behind the
\\ recursion-depth ladder above. It is compared here deliberately: the number
\\ is a deterministic, canonical observable, and it differing across ports is
\\ itself the finding.
(sprobe J1-prolog-memory
        (freeze (value shen.*prolog-memory*)))

\\ Number of Prolog variables one query allocates, just under and just over the
\\ smallest port's ceiling.
(sprobe J2-under-smallest-ceiling
        (freeze (sclass (prolog? (sdown 900 R) (return R)))))
(sprobe J3-over-smallest-ceiling
        (freeze (sclass (prolog? (sdown 1200 R) (return R)))))

(output "PROBES COMPLETE~%")
