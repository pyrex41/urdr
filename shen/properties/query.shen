\* ADR 0004 Decision 3 fallback: explicit-state query evaluator in plain Shen.

   Status: ANALYSIS. Nothing in this module is certifying. It carries no
   Bifrost case and contributes to no verdict, certificate, or golden digest.

   Why this module exists instead of a Prolog one: the Wave G spike
   (spikes/m1-prolog-portability/) found that Shen's integrated Prolog does
   NOT behave identically across the four required ports. ADR 0004 Decision 3
   forbids partial trust, so the Prolog surface is dropped and the same query
   surface is provided here in plain Shen.

   The queries are the three ADR 0004 Decision 3 names: reachability,
   inductive-invariant checking, and counterexample search. They are pure with
   respect to world semantics: they read canonical model terms, they produce
   canonical results, and they never mutate world state, draw randomness, or
   advance logical time.

   Portability: this module uses only structural equality over canonical
   values, explicit list order, and software integers where a magnitude is
   needed. No floating point, no map iteration, no host time, no host
   randomness, no absvectors, no gensym. Every result is a canonical value in
   a deterministic order, so the module is byte-reproducible by construction
   rather than by a port's Prolog engine agreeing with three others.

   Model representation (all canonical values, ADR 0002):

     transition ::= [edge STATE STATE]
     model      ::= [model [STATE ...] [transition ...]]

   The transition list is explicit and finite; successors are taken in
   declaration order, which is what makes enumeration order canonical.

   Predicate language. A predicate is a canonical term, not a Shen function,
   so that queries stay data and can be serialised, compared, and pinned:

     pred ::= [p-true]
            | [p-false]
            | [p-is    TERM]        state is exactly TERM
            | [p-at    N TERM]      the Nth field (0-based) of a list state
                                    is exactly TERM
            | [p-holds TERM]        TERM occurs as a member of a list state
            | [p-not   PRED]
            | [p-and   PRED PRED]
            | [p-or    PRED PRED]

   Results are canonical terms:

     [reached [STATE ...]]        witness path, initial state first
     [unreached]
     [bound-exceeded]
     [holds]
     [violated [STATE ...]]       witness path to the violating state
     [inductive]
     [not-inductive STATE STATE]  an edge leaving the invariant
     [error REASON]               fail-closed; never a silent default
*\

\\ ------------------------------------------------------------- list helpers

(define urdr.query.member?
  _ [] -> false
  X [Y | Ys] -> (if (= X Y) true (urdr.query.member? X Ys)))

(define urdr.query.at
  _ [] -> [error index-out-of-range]
  0 [X | _] -> [ok X]
  N [_ | Xs] -> (if (> N 0)
                    (urdr.query.at (- N 1) Xs)
                    [error negative-index]))

(define urdr.query.snoc
  [] Y -> [Y]
  [X | Xs] Y -> [X | (urdr.query.snoc Xs Y)])

\\ ------------------------------------------------------------- predicates

(define urdr.query.eval
  [p-true] _ -> [ok true]
  [p-false] _ -> [ok false]
  [p-is Term] State -> [ok (= State Term)]
  [p-holds Term] State -> (if (cons? State)
                              [ok (urdr.query.member? Term State)]
                              [error non-list-state])
  [p-at N Term] State -> (if (cons? State)
                             (urdr.query.at.check N Term State)
                             [error non-list-state])
  [p-not P] State -> (urdr.query.eval.not (urdr.query.eval P State))
  [p-and P Q] State -> (urdr.query.eval.and (urdr.query.eval P State) Q State)
  [p-or P Q] State -> (urdr.query.eval.or (urdr.query.eval P State) Q State)
  _ _ -> [error malformed-predicate])

(define urdr.query.at.check
  N Term State -> (urdr.query.at.check.h (urdr.query.at N State) Term))

(define urdr.query.at.check.h
  [ok Field] Term -> [ok (= Field Term)]
  [error Reason] _ -> [error Reason])

(define urdr.query.eval.not
  [ok V] -> [ok (not V)]
  [error Reason] -> [error Reason])

(define urdr.query.eval.and
  [error Reason] _ _ -> [error Reason]
  [ok false] _ _ -> [ok false]
  [ok true] Q State -> (urdr.query.eval Q State))

(define urdr.query.eval.or
  [error Reason] _ _ -> [error Reason]
  [ok true] _ _ -> [ok true]
  [ok false] Q State -> (urdr.query.eval Q State))

\\ --------------------------------------------------------------- the model

(define urdr.query.successors
  _ [] -> []
  S [[edge From To] | Es] -> (if (= S From)
                                 [To | (urdr.query.successors S Es)]
                                 (urdr.query.successors S Es))
  _ [_ | _] -> [error malformed-edge])

(define urdr.query.model.ok?
  [model States Edges] -> (and (cons? [dummy | States]) (cons? [dummy | Edges]))
  _ -> false)

\\ ------------------------------------------------------------ reachability

\* Breadth-first search over the explicit edge list. The frontier holds paths
   with the current state at the head (so paths are built in reverse and
   reversed once on success). Successors are appended in edge-declaration
   order, so the first witness found is a canonical function of the model, not
   of any engine's search strategy.

   Bound is a plain nonnegative Shen integer counting expanded states, which
   makes exhaustion explicit rather than a hang. *\

(define urdr.query.reachable
  [model _ Edges] Init Goal Bound ->
    (if (and (integer? Bound) (>= Bound 0))
        (urdr.query.reach.loop Edges Goal [[Init]] [Init] Bound)
        [error bad-bound])
  _ _ _ _ -> [error malformed-model])

(define urdr.query.reach.loop
  _ _ [] _ _ -> [unreached]
  Edges Goal [Path | Rest] Seen Bound ->
    (if (= Bound 0)
        [bound-exceeded]
        (urdr.query.reach.step Edges Goal Path Rest Seen Bound
                               (urdr.query.eval Goal (hd Path)))))

(define urdr.query.reach.step
  _ _ _ _ _ _ [error Reason] -> [error Reason]
  _ _ Path _ _ _ [ok true] -> [reached (reverse Path)]
  Edges Goal Path Rest Seen Bound [ok false] ->
    (let Next (urdr.query.successors (hd Path) Edges)
      (if (= Next [error malformed-edge])
          [error malformed-edge]
          (let Fresh (urdr.query.fresh Next Seen)
               Paths (urdr.query.extend Path Fresh)
            (urdr.query.reach.loop Edges
                                   Goal
                                   (append Rest Paths)
                                   (append Seen Fresh)
                                   (- Bound 1))))))

\\ Keeps declaration order and drops states already seen or already queued.
(define urdr.query.fresh
  [] _ -> []
  [S | Ss] Seen -> (if (urdr.query.member? S Seen)
                       (urdr.query.fresh Ss Seen)
                       [S | (urdr.query.fresh Ss [S | Seen])]))

(define urdr.query.extend
  _ [] -> []
  Path [S | Ss] -> [[S | Path] | (urdr.query.extend Path Ss)])

\\ ---------------------------------------------------- invariant by search

\* A state invariant holds over the reachable set iff its negation is
   unreachable. A violation is reported with the witness path that reaches it,
   which is exactly the counterexample a scenario compiler would lower to a
   replayable schedule. *\

(define urdr.query.invariant
  Model Init Inv Bound ->
    (urdr.query.invariant.h (urdr.query.reachable Model Init [p-not Inv] Bound)))

(define urdr.query.invariant.h
  [unreached] -> [holds]
  [reached Path] -> [violated Path]
  [bound-exceeded] -> [bound-exceeded]
  [error Reason] -> [error Reason])

\\ Counterexample search is the same query read the other way round: find a
\\ state satisfying Goal, and report the path that witnesses it.
(define urdr.query.counterexample
  Model Init Goal Bound -> (urdr.query.reachable Model Init Goal Bound))

\\ --------------------------------------------------- inductive invariants

\* Induction is checked WITHOUT search: every declared state satisfying Inv
   must have every successor satisfy Inv, and every initial state must satisfy
   Inv. This is the standard two-obligation check, and unlike reachability it
   needs no bound. A failure names the offending edge. *\

(define urdr.query.inductive
  [model States Edges] Inits Inv ->
    (urdr.query.inductive.init States Edges Inits Inv)
  _ _ _ -> [error malformed-model])

(define urdr.query.inductive.init
  States Edges [] Inv -> (urdr.query.inductive.edges States Edges Inv)
  States Edges [I | Is] Inv ->
    (urdr.query.inductive.init.h (urdr.query.eval Inv I) States Edges Is Inv I))

(define urdr.query.inductive.init.h
  [error Reason] _ _ _ _ _ -> [error Reason]
  [ok false] _ _ _ _ I -> [not-inductive initial I]
  [ok true] States Edges Is Inv _ ->
    (urdr.query.inductive.init States Edges Is Inv))

(define urdr.query.inductive.edges
  _ [] _ -> [inductive]
  States [[edge From To] | Es] Inv ->
    (urdr.query.inductive.edge States Es Inv From To
                               (urdr.query.eval Inv From))
  _ [_ | _] _ -> [error malformed-edge])

(define urdr.query.inductive.edge
  _ _ _ _ _ [error Reason] -> [error Reason]
  States Es Inv _ _ [ok false] -> (urdr.query.inductive.edges States Es Inv)
  States Es Inv From To [ok true] ->
    (urdr.query.inductive.edge.h (urdr.query.eval Inv To) States Es Inv From To))

(define urdr.query.inductive.edge.h
  [error Reason] _ _ _ _ _ -> [error Reason]
  [ok false] _ _ _ From To -> [not-inductive From To]
  [ok true] States Es Inv _ _ -> (urdr.query.inductive.edges States Es Inv))
