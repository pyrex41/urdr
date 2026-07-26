\* ADR 0004 Decision 2: the history-free NetKAT fragment.

Requires shen/protocol/canonical.shen and shen/world/integer.shen to be
loaded by the caller.

Representations

  vocabulary value  [record [[FIELD-BYTES [list INTEGER ...]] ...]]
  validated vocab   [nk-vocab [[FIELD-BYTES [INTEGER ...]] ...] SPACE]
  packet            [record [[FIELD-BYTES INTEGER] ...]], one entry per
                    declared field, in the vocabulary's key order
  packet set        packets strictly increasing under
                    urdr.netkat.packet-compare
  policy term       [nk-drop] | [nk-id]
                    | [nk-test [symbol FIELD] INTEGER]
                    | [nk-set  [symbol FIELD] INTEGER]
                    | [nk-union TERM TERM] | [nk-seq TERM TERM]
                    | [nk-star TERM] | [nk-neg PREDICATE]

  predicate         [nk-drop] | [nk-id] | [nk-test _ _]
                    | [nk-union PRED PRED] | [nk-seq PRED PRED]
                    | [nk-neg PRED]

Integers are ADR 0003 software integers; field names are ADR 0002
canonical symbol octets. No host arithmetic reaches semantics apart from
the bounded structural counters that mirror the ADR 0002 resource
profile.

Validation returns [ok ...] or [error stable-code]. The denotation
urdr.netkat.eval and the decision procedures urdr.netkat.equivalence and
urdr.netkat.reachability are total functions of already-validated
inputs; the check-* wrappers validate first. *\

\\ Deterministic resource profile. These are protocol limits, not
\\ semantic claims: the decision procedures tabulate the whole declared
\\ header space, so an unbounded vocabulary would be an unbounded run.
(set *urdr.netkat.max-fields* 8)
(set *urdr.netkat.max-field-values* 64)
(set *urdr.netkat.max-space* 1024)
(set *urdr.netkat.max-term-nodes* 1024)

\\ ---------------------------------------------------------------
\\ Term tags
\\ ---------------------------------------------------------------

(define urdr.netkat.tag-head
  [110 107 45 100 114 111 112] -> nk-drop
  [110 107 45 105 100] -> nk-id
  [110 107 45 116 101 115 116] -> nk-test
  [110 107 45 115 101 116] -> nk-set
  [110 107 45 117 110 105 111 110] -> nk-union
  [110 107 45 115 101 113] -> nk-seq
  [110 107 45 115 116 97 114] -> nk-star
  [110 107 45 110 101 103] -> nk-neg
  _ -> unknown)

(define urdr.netkat.head-tag
  nk-drop -> [110 107 45 100 114 111 112]
  nk-id -> [110 107 45 105 100]
  nk-test -> [110 107 45 116 101 115 116]
  nk-set -> [110 107 45 115 101 116]
  nk-union -> [110 107 45 117 110 105 111 110]
  nk-seq -> [110 107 45 115 101 113]
  nk-star -> [110 107 45 115 116 97 114]
  nk-neg -> [110 107 45 110 101 103])

(define urdr.netkat.known-head?
  nk-drop -> true
  nk-id -> true
  nk-test -> true
  nk-set -> true
  nk-union -> true
  nk-seq -> true
  nk-star -> true
  nk-neg -> true
  _ -> false)

\\ ---------------------------------------------------------------
\\ Header vocabulary
\\ ---------------------------------------------------------------

(define urdr.netkat.key-after?
  Key none -> true
  Key Previous ->
    (= (urdr.canonical.bytes-compare Key Previous) gt))

(define urdr.netkat.value-after?
  V none -> true
  V Previous -> (> (urdr.int.raw.compare V Previous) 0))

(define urdr.netkat.value-set
  [] Previous Acc Count ->
    (if (= Count 0)
        [error vocab-values-empty]
        [ok (urdr.canonical.rev Acc) Count])
  [V | Vs] Previous Acc Count ->
    (if (not (urdr.int.valid? V))
        [error vocab-value-integer]
        (if (not (urdr.netkat.value-after? V Previous))
            [error vocab-value-order]
            (if (>= Count (value *urdr.netkat.max-field-values*))
                [error vocab-too-many-values]
                (urdr.netkat.value-set Vs V [V | Acc] (+ Count 1)))))
  _ Previous Acc Count -> [error vocab-values-shape])

(define urdr.netkat.vocab-entry-values
  Key [list Values] Rest Previous Acc Count Space ->
    (urdr.netkat.vocab-values-result
      (urdr.netkat.value-set Values none [] 0)
      Key Rest Acc Count Space)
  Key _ Rest Previous Acc Count Space -> [error vocab-values-shape])

(define urdr.netkat.vocab-values-result
  [error E] Key Rest Acc Count Space -> [error E]
  [ok Values N] Key Rest Acc Count Space ->
    (if (>= Count (value *urdr.netkat.max-fields*))
        [error vocab-too-many-fields]
        (let Grown (* Space N)
          (if (> Grown (value *urdr.netkat.max-space*))
              [error vocab-space-too-large]
              (urdr.netkat.vocab-entries
                Rest Key [[Key Values] | Acc] (+ Count 1) Grown)))))

(define urdr.netkat.vocab-entries
  [] Previous Acc Count Space ->
    [ok [nk-vocab (urdr.canonical.rev Acc) Space]]
  [[Key Value] | Rest] Previous Acc Count Space ->
    (if (not (urdr.canonical.symbol? Key))
        [error vocab-field-symbol]
        (if (not (urdr.netkat.key-after? Key Previous))
            [error vocab-field-order]
            (urdr.netkat.vocab-entry-values
              Key Value Rest Previous Acc Count Space)))
  _ Previous Acc Count Space -> [error vocab-shape])

(define urdr.netkat.vocabulary
  [record []] -> [error vocab-empty]
  [record Entries] -> (urdr.netkat.vocab-entries Entries none [] 0 1)
  _ -> [error vocab-shape])

(define urdr.netkat.vocab-fields
  [nk-vocab Fields _] -> Fields)

(define urdr.netkat.vocab-space-size
  [nk-vocab _ Space] -> Space)

(define urdr.netkat.field-values
  [] Key -> none
  [[Key2 Values] | Fs] Key ->
    (if (= Key2 Key) [ok Values] (urdr.netkat.field-values Fs Key)))

(define urdr.netkat.member-value?
  V [] -> false
  V [W | Ws] -> (if (= V W) true (urdr.netkat.member-value? V Ws)))

\\ ---------------------------------------------------------------
\\ Packets
\\ ---------------------------------------------------------------

(define urdr.netkat.packet-entries
  [] [] Acc -> [ok [record (urdr.canonical.rev Acc)]]
  [] _ Acc -> [error packet-field-mismatch]
  [_ | _] [] Acc -> [error packet-field-mismatch]
  [[Key Values] | Fs] [[Key2 V] | Es] Acc ->
    (if (not (= Key Key2))
        [error packet-field-mismatch]
        (if (not (urdr.int.valid? V))
            [error packet-value-integer]
            (if (not (urdr.netkat.member-value? V Values))
                [error packet-value-unknown]
                (urdr.netkat.packet-entries Fs Es [[Key V] | Acc]))))
  _ _ Acc -> [error packet-shape])

(define urdr.netkat.packet
  Vocab [record Entries] ->
    (urdr.netkat.packet-entries
      (urdr.netkat.vocab-fields Vocab) Entries [])
  Vocab _ -> [error packet-shape])

(define urdr.netkat.entries-get
  [] Key -> none
  [[K V] | Es] Key ->
    (if (= K Key) V (urdr.netkat.entries-get Es Key)))

(define urdr.netkat.packet-get
  [record Entries] Key -> (urdr.netkat.entries-get Entries Key))

\\ Every validated term names a declared field and every validated
\\ packet carries every declared field, so the replaced entry always
\\ exists and the vocabulary key order is preserved.
(define urdr.netkat.entries-put
  [] Key V -> []
  [[K _] | Es] Key V -> [[K V] | Es] where (= K Key)
  [E | Es] Key V -> [E | (urdr.netkat.entries-put Es Key V)])

(define urdr.netkat.packet-put
  [record Entries] Key V ->
    [record (urdr.netkat.entries-put Entries Key V)])

(define urdr.netkat.entries-compare
  [] [] -> eq
  [] _ -> lt
  [_ | _] [] -> gt
  [[KA VA] | As] [[KB VB] | Bs] ->
    (let KC (urdr.canonical.bytes-compare KA KB)
      (if (= KC eq)
          (let VC (urdr.int.raw.compare VA VB)
            (if (= VC 0)
                (urdr.netkat.entries-compare As Bs)
                (if (< VC 0) lt gt)))
          KC)))

(define urdr.netkat.packet-compare
  [record A] [record B] -> (urdr.netkat.entries-compare A B))

\\ ---------------------------------------------------------------
\\ Canonically ordered packet sets
\\ ---------------------------------------------------------------

(define urdr.netkat.set-union
  [] B -> B
  A [] -> A
  [P | Ps] [Q | Qs] ->
    (let C (urdr.netkat.packet-compare P Q)
      (if (= C lt)
          [P | (urdr.netkat.set-union Ps [Q | Qs])]
          (if (= C gt)
              [Q | (urdr.netkat.set-union [P | Ps] Qs)]
              [P | (urdr.netkat.set-union Ps Qs)]))))

(define urdr.netkat.set-difference
  [] B -> []
  A [] -> A
  [P | Ps] [Q | Qs] ->
    (let C (urdr.netkat.packet-compare P Q)
      (if (= C lt)
          [P | (urdr.netkat.set-difference Ps [Q | Qs])]
          (if (= C gt)
              (urdr.netkat.set-difference [P | Ps] Qs)
              (urdr.netkat.set-difference Ps Qs)))))

\\ ---------------------------------------------------------------
\\ Term validation
\\ ---------------------------------------------------------------

(define urdr.netkat.predicate?
  [nk-drop] -> true
  [nk-id] -> true
  [nk-test _ _] -> true
  [nk-union A B] ->
    (and (urdr.netkat.predicate? A) (urdr.netkat.predicate? B))
  [nk-seq A B] ->
    (and (urdr.netkat.predicate? A) (urdr.netkat.predicate? B))
  [nk-neg A] -> (urdr.netkat.predicate? A)
  _ -> false)

(define urdr.netkat.check-shape
  [Head | Args] ->
    (if (urdr.netkat.known-head? Head)
        [error term-arity]
        [error term-head])
  _ -> [error term-shape])

(define urdr.netkat.check-field
  none V Nodes -> [error term-field-unknown]
  [ok Values] V Nodes ->
    (if (urdr.netkat.member-value? V Values)
        [ok Nodes]
        [error term-value-unknown]))

(define urdr.netkat.check-atomic
  Vocab [symbol F] V Nodes ->
    (if (not (urdr.int.valid? V))
        [error term-value-integer]
        (urdr.netkat.check-field
          (urdr.netkat.field-values
            (urdr.netkat.vocab-fields Vocab) F)
          V
          Nodes))
  Vocab _ V Nodes -> [error term-field-shape])

(define urdr.netkat.check-binary
  Vocab A B Nodes ->
    (urdr.netkat.check-binary-left
      (urdr.netkat.check Vocab A Nodes) Vocab B))

(define urdr.netkat.check-binary-left
  [error E] Vocab B -> [error E]
  [ok Nodes] Vocab B -> (urdr.netkat.check Vocab B Nodes))

(define urdr.netkat.check-negation
  [error E] A -> [error E]
  [ok Nodes] A ->
    (if (urdr.netkat.predicate? A)
        [ok Nodes]
        [error term-neg-nonpredicate]))

(define urdr.netkat.check-node
  Vocab [nk-drop] Nodes -> [ok Nodes]
  Vocab [nk-id] Nodes -> [ok Nodes]
  Vocab [nk-test F V] Nodes ->
    (urdr.netkat.check-atomic Vocab F V Nodes)
  Vocab [nk-set F V] Nodes ->
    (urdr.netkat.check-atomic Vocab F V Nodes)
  Vocab [nk-union A B] Nodes ->
    (urdr.netkat.check-binary Vocab A B Nodes)
  Vocab [nk-seq A B] Nodes ->
    (urdr.netkat.check-binary Vocab A B Nodes)
  Vocab [nk-star A] Nodes -> (urdr.netkat.check Vocab A Nodes)
  Vocab [nk-neg A] Nodes ->
    (urdr.netkat.check-negation (urdr.netkat.check Vocab A Nodes) A)
  Vocab Term Nodes -> (urdr.netkat.check-shape Term))

(define urdr.netkat.check
  Vocab Term Nodes ->
    (if (>= Nodes (value *urdr.netkat.max-term-nodes*))
        [error term-too-large]
        (urdr.netkat.check-node Vocab Term (+ Nodes 1))))

(define urdr.netkat.term-check
  Vocab Term ->
    (urdr.netkat.term-check-result
      (urdr.netkat.check Vocab Term 0) Term))

(define urdr.netkat.term-check-result
  [error E] Term -> [error E]
  [ok _] Term -> [ok Term])

\\ ---------------------------------------------------------------
\\ Term codec against ADR 0002 canonical values
\\ ---------------------------------------------------------------

(define urdr.netkat.decode-atomic
  Head [symbol F] V ->
    (if (urdr.int.valid? V)
        [ok [Head [symbol F] V]]
        [error term-value-integer])
  Head _ V -> [error term-field-shape])

(define urdr.netkat.decode-unary
  Head A ->
    (urdr.netkat.decode-unary-result
      Head (urdr.netkat.term-decode A)))

(define urdr.netkat.decode-unary-result
  Head [error E] -> [error E]
  Head [ok T] -> [ok [Head T]])

(define urdr.netkat.decode-binary
  Head A B ->
    (urdr.netkat.decode-binary-left
      Head (urdr.netkat.term-decode A) B))

(define urdr.netkat.decode-binary-left
  Head [error E] B -> [error E]
  Head [ok TA] B ->
    (urdr.netkat.decode-binary-right
      Head TA (urdr.netkat.term-decode B)))

(define urdr.netkat.decode-binary-right
  Head TA [error E] -> [error E]
  Head TA [ok TB] -> [ok [Head TA TB]])

(define urdr.netkat.decode-head
  unknown Args -> [error term-head]
  nk-drop [] -> [ok [nk-drop]]
  nk-id [] -> [ok [nk-id]]
  nk-test [F V] -> (urdr.netkat.decode-atomic nk-test F V)
  nk-set [F V] -> (urdr.netkat.decode-atomic nk-set F V)
  nk-union [A B] -> (urdr.netkat.decode-binary nk-union A B)
  nk-seq [A B] -> (urdr.netkat.decode-binary nk-seq A B)
  nk-star [A] -> (urdr.netkat.decode-unary nk-star A)
  nk-neg [A] -> (urdr.netkat.decode-unary nk-neg A)
  _ Args -> [error term-arity])

(define urdr.netkat.term-decode
  [list [[symbol Tag] | Args]] ->
    (urdr.netkat.decode-head (urdr.netkat.tag-head Tag) Args)
  _ -> [error term-encoding])

(define urdr.netkat.term-encode
  [nk-drop] -> [list [[symbol (urdr.netkat.head-tag nk-drop)]]]
  [nk-id] -> [list [[symbol (urdr.netkat.head-tag nk-id)]]]
  [nk-test F V] ->
    [list [[symbol (urdr.netkat.head-tag nk-test)] F V]]
  [nk-set F V] ->
    [list [[symbol (urdr.netkat.head-tag nk-set)] F V]]
  [nk-union A B] ->
    [list [[symbol (urdr.netkat.head-tag nk-union)]
           (urdr.netkat.term-encode A)
           (urdr.netkat.term-encode B)]]
  [nk-seq A B] ->
    [list [[symbol (urdr.netkat.head-tag nk-seq)]
           (urdr.netkat.term-encode A)
           (urdr.netkat.term-encode B)]]
  [nk-star A] ->
    [list [[symbol (urdr.netkat.head-tag nk-star)]
           (urdr.netkat.term-encode A)]]
  [nk-neg A] ->
    [list [[symbol (urdr.netkat.head-tag nk-neg)]
           (urdr.netkat.term-encode A)]])

(define urdr.netkat.term
  Vocab Value ->
    (urdr.netkat.term-decoded Vocab (urdr.netkat.term-decode Value)))

(define urdr.netkat.term-decoded
  Vocab [error E] -> [error E]
  Vocab [ok Term] -> (urdr.netkat.term-check Vocab Term))

(define urdr.netkat.predicate
  Vocab Value ->
    (urdr.netkat.predicate-checked (urdr.netkat.term Vocab Value)))

(define urdr.netkat.predicate-checked
  [error E] -> [error E]
  [ok Term] ->
    (if (urdr.netkat.predicate? Term)
        [ok Term]
        [error term-nonpredicate]))

\\ ---------------------------------------------------------------
\\ Denotation: packet -> canonically ordered packet set
\\ ---------------------------------------------------------------

(define urdr.netkat.field-bytes
  [symbol Bs] -> Bs)

(define urdr.netkat.eval-test
  F V P ->
    (if (= (urdr.netkat.packet-get P (urdr.netkat.field-bytes F)) V)
        [P]
        []))

\\ Kleene star as a finite fixpoint. Reached is the set of packets
\\ produced by some number of iterations of A; Frontier is the packets
\\ first produced by the most recent iteration. Each round either
\\ terminates or adds at least one packet to Reached, and every packet
\\ reachable from a validated packet under a validated term lies in the
\\ declared header space (nk-set only writes declared values), so the
\\ loop runs at most (urdr.netkat.vocab-space-size Vocab) rounds.
(define urdr.netkat.star
  A Reached [] -> Reached
  A Reached Frontier ->
    (let Fresh
         (urdr.netkat.set-difference
           (urdr.netkat.eval-set A Frontier) Reached)
      (urdr.netkat.star
        A (urdr.netkat.set-union Reached Fresh) Fresh)))

(define urdr.netkat.eval-set
  T [] -> []
  T [P | Ps] ->
    (urdr.netkat.set-union
      (urdr.netkat.eval T P) (urdr.netkat.eval-set T Ps)))

(define urdr.netkat.eval
  [nk-drop] P -> []
  [nk-id] P -> [P]
  [nk-test F V] P -> (urdr.netkat.eval-test F V P)
  [nk-set F V] P ->
    [(urdr.netkat.packet-put P (urdr.netkat.field-bytes F) V)]
  [nk-union A B] P ->
    (urdr.netkat.set-union
      (urdr.netkat.eval A P) (urdr.netkat.eval B P))
  [nk-seq A B] P -> (urdr.netkat.eval-set B (urdr.netkat.eval A P))
  [nk-star A] P -> (urdr.netkat.star A [P] [P])
  [nk-neg A] P -> (if (= (urdr.netkat.eval A P) []) [P] []))

\\ ---------------------------------------------------------------
\\ The declared finite header space, in packet-compare order
\\ ---------------------------------------------------------------

(define urdr.netkat.space-prefix
  Key V [] -> []
  Key V [[record Es] | Ss] ->
    [[record [[Key V] | Es]] | (urdr.netkat.space-prefix Key V Ss)])

(define urdr.netkat.space-extend
  Key [] Suffixes -> []
  Key [V | Vs] Suffixes ->
    (append
      (urdr.netkat.space-prefix Key V Suffixes)
      (urdr.netkat.space-extend Key Vs Suffixes)))

(define urdr.netkat.space-fields
  [] -> [[record []]]
  [[Key Values] | Fs] ->
    (urdr.netkat.space-extend
      Key Values (urdr.netkat.space-fields Fs)))

(define urdr.netkat.space
  Vocab -> (urdr.netkat.space-fields (urdr.netkat.vocab-fields Vocab)))

\\ ---------------------------------------------------------------
\\ Decision procedures over the declared finite header space
\\ ---------------------------------------------------------------

(define urdr.netkat.equivalence-loop
  A B [] -> [equivalent]
  A B [P | Ps] ->
    (let SA (urdr.netkat.eval A P)
         SB (urdr.netkat.eval B P)
      (if (= SA SB)
          (urdr.netkat.equivalence-loop A B Ps)
          [differs P SA SB])))

(define urdr.netkat.equivalence
  Vocab A B ->
    (urdr.netkat.equivalence-loop A B (urdr.netkat.space Vocab)))

(define urdr.netkat.reachability-loop
  T [] -> [unreachable]
  T [P | Ps] ->
    (let S (urdr.netkat.eval T P)
      (if (= S [])
          (urdr.netkat.reachability-loop T Ps)
          [reachable P (hd S)])))

(define urdr.netkat.reachability
  Vocab Ingress Policy Egress ->
    (urdr.netkat.reachability-loop
      [nk-seq Ingress [nk-seq Policy Egress]]
      (urdr.netkat.space Vocab)))

\\ ---------------------------------------------------------------
\\ Canonical result values
\\ ---------------------------------------------------------------

(define urdr.netkat.word
  equivalent -> [101 113 117 105 118 97 108 101 110 116]
  differs -> [100 105 102 102 101 114 115]
  reachable -> [114 101 97 99 104 97 98 108 101]
  unreachable -> [117 110 114 101 97 99 104 97 98 108 101])

(define urdr.netkat.key
  verdict -> [118 101 114 100 105 99 116]
  left-output -> [108 101 102 116 45 111 117 116 112 117 116]
  right-output -> [114 105 103 104 116 45 111 117 116 112 117 116]
  witness-packet ->
    [119 105 116 110 101 115 115 45 112 97 99 107 101 116]
  egress-packet -> [101 103 114 101 115 115 45 112 97 99 107 101 116]
  ingress-packet ->
    [105 110 103 114 101 115 115 45 112 97 99 107 101 116])

(define urdr.netkat.verdict-symbol
  Word -> [symbol (urdr.netkat.word Word)])

(define urdr.netkat.set-value
  Set -> [list Set])

(define urdr.netkat.equivalence-value
  [equivalent] ->
    [record
      [[(urdr.netkat.key verdict)
        (urdr.netkat.verdict-symbol equivalent)]]]
  [differs P A B] ->
    [record
      [[(urdr.netkat.key left-output) (urdr.netkat.set-value A)]
       [(urdr.netkat.key right-output) (urdr.netkat.set-value B)]
       [(urdr.netkat.key verdict) (urdr.netkat.verdict-symbol differs)]
       [(urdr.netkat.key witness-packet) P]]])

(define urdr.netkat.reachability-value
  [unreachable] ->
    [record
      [[(urdr.netkat.key verdict)
        (urdr.netkat.verdict-symbol unreachable)]]]
  [reachable In Out] ->
    [record
      [[(urdr.netkat.key egress-packet) Out]
       [(urdr.netkat.key ingress-packet) In]
       [(urdr.netkat.key verdict)
        (urdr.netkat.verdict-symbol reachable)]]])

\\ ---------------------------------------------------------------
\\ Checked entry points over canonical values
\\ ---------------------------------------------------------------

(define urdr.netkat.check-evaluate
  VocabValue PolicyValue PacketValue ->
    (urdr.netkat.check-evaluate-vocab
      (urdr.netkat.vocabulary VocabValue) PolicyValue PacketValue))

(define urdr.netkat.check-evaluate-vocab
  [error E] PolicyValue PacketValue -> [error E]
  [ok Vocab] PolicyValue PacketValue ->
    (urdr.netkat.check-evaluate-term
      (urdr.netkat.term Vocab PolicyValue) Vocab PacketValue))

(define urdr.netkat.check-evaluate-term
  [error E] Vocab PacketValue -> [error E]
  [ok Term] Vocab PacketValue ->
    (urdr.netkat.check-evaluate-packet
      (urdr.netkat.packet Vocab PacketValue) Term))

(define urdr.netkat.check-evaluate-packet
  [error E] Term -> [error E]
  [ok Packet] Term -> [ok (urdr.netkat.eval Term Packet)])

(define urdr.netkat.check-equivalence
  VocabValue LeftValue RightValue ->
    (urdr.netkat.check-equivalence-vocab
      (urdr.netkat.vocabulary VocabValue) LeftValue RightValue))

(define urdr.netkat.check-equivalence-vocab
  [error E] LeftValue RightValue -> [error E]
  [ok Vocab] LeftValue RightValue ->
    (urdr.netkat.check-equivalence-left
      (urdr.netkat.term Vocab LeftValue) Vocab RightValue))

(define urdr.netkat.check-equivalence-left
  [error E] Vocab RightValue -> [error E]
  [ok Left] Vocab RightValue ->
    (urdr.netkat.check-equivalence-right
      (urdr.netkat.term Vocab RightValue) Vocab Left))

(define urdr.netkat.check-equivalence-right
  [error E] Vocab Left -> [error E]
  [ok Right] Vocab Left ->
    [ok (urdr.netkat.equivalence Vocab Left Right)])

(define urdr.netkat.check-reachability
  VocabValue IngressValue PolicyValue EgressValue ->
    (urdr.netkat.check-reachability-vocab
      (urdr.netkat.vocabulary VocabValue)
      IngressValue PolicyValue EgressValue))

(define urdr.netkat.check-reachability-vocab
  [error E] IngressValue PolicyValue EgressValue -> [error E]
  [ok Vocab] IngressValue PolicyValue EgressValue ->
    (urdr.netkat.check-reachability-ingress
      (urdr.netkat.predicate Vocab IngressValue)
      Vocab PolicyValue EgressValue))

(define urdr.netkat.check-reachability-ingress
  [error E] Vocab PolicyValue EgressValue -> [error E]
  [ok Ingress] Vocab PolicyValue EgressValue ->
    (urdr.netkat.check-reachability-policy
      (urdr.netkat.term Vocab PolicyValue)
      Vocab Ingress EgressValue))

(define urdr.netkat.check-reachability-policy
  [error E] Vocab Ingress EgressValue -> [error E]
  [ok Policy] Vocab Ingress EgressValue ->
    (urdr.netkat.check-reachability-egress
      (urdr.netkat.predicate Vocab EgressValue)
      Vocab Ingress Policy))

(define urdr.netkat.check-reachability-egress
  [error E] Vocab Ingress Policy -> [error E]
  [ok Egress] Vocab Ingress Policy ->
    [ok (urdr.netkat.reachability Vocab Ingress Policy Egress)])
