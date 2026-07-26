\* ADR 0004 Decision 4: the Kubernetes NetworkPolicy compiler.

Requires shen/protocol/canonical.shen, shen/world/integer.shen, and
shen/world/netkat.shen to be loaded by the caller.

Scope. The compiled object is *connection admission* for the
`networking.k8s.io/v1` semantics pinned by ADR 0004: a canonical
connection attempt (src, dst, protocol, dst-port) is admitted iff the
source's egress side and the destination's ingress side both allow it.
Stateful reply traffic is out of scope and is not modelled. Every
compiled result carries the `spec-semantics-only` marker; nothing here
claims fidelity to a live CNI enforcement path.

Compilation vocabulary. Four NetKAT fields over the scenario-declared
universe, in canonical key order:

  dst-pod    endpoint index of the connection destination
  dst-port   a scenario-declared port number
  protocol   6 (TCP), 17 (UDP), or 132 (SCTP), when declared
  src-pod    endpoint index of the connection source

Endpoints are the declared pods, in (namespace, name) order, followed by
the declared externals, in name order. There is deliberately no runtime
IP field: `ipBlock` CIDR containment is decided at compile time over the
declared endpoint addresses, so an `ipBlock` peer compiles to a union of
`src-pod`/`dst-pod` tests, and `except` subtracts with predicate
negation as Decision 4 requires. The declared header space and the
compiled term are both re-checked against the Decision 2 budgets, so an
oversized manifest set fails closed with the NetKAT code rather than
being silently narrowed.

Representations

  universe    [universe Endpoints Namespaces Ports Protocols Names]
  endpoint    [endpoint IndexBig Name Namespace Address Labels Ports
               HostNetwork]
  namespace   [Name Labels]
  labels      [[KEY-BYTES VALUE-BYTES] ...] in record order
  selector    [selector Labels Expressions]
  expression  [expr KEY-BYTES OPERATOR VALUES]
  peer        [peer-ip Network Length Excepts]
            | [peer-sel NamespaceSelector PodSelector]
  port entry  [entry PROTOCOL-CODE NAMED LOW HIGH]
  rule        [rule ALL-PEERS Peers ALL-PORTS Entries]
  policy      [policy Name Namespace Selector Ingress? Egress?
               IngressRules EgressRules]
  compiled    [compiled Vocab Term EgressSide IngressSide
               EgressAllows IngressAllows Isolation Space]

Every public operation returns [ok ...] or [error stable-code]. Address
octets, prefix lengths, and endpoint indices are bounded host naturals
handled exactly as the ADR 0002 length prefixes are; every value that
reaches a NetKAT term is an ADR 0003 software integer. *\

\\ ---------------------------------------------------------------
\\ Canonical key and word octets
\\ ---------------------------------------------------------------

(define urdr.netpol.key
  k-externals -> [101 120 116 101 114 110 97 108 115]
  k-namespaces -> [110 97 109 101 115 112 97 99 101 115]
  k-pods -> [112 111 100 115]
  k-ports -> [112 111 114 116 115]
  k-protocols -> [112 114 111 116 111 99 111 108 115]
  k-labels -> [108 97 98 101 108 115]
  k-name -> [110 97 109 101]
  k-namespace -> [110 97 109 101 115 112 97 99 101]
  k-address -> [97 100 100 114 101 115 115]
  k-host-network -> [104 111 115 116 45 110 101 116 119 111 114 107]
  k-egress -> [101 103 114 101 115 115]
  k-ingress -> [105 110 103 114 101 115 115]
  k-pod-selector -> [112 111 100 45 115 101 108 101 99 116 111 114]
  k-policy-types -> [112 111 108 105 99 121 45 116 121 112 101 115]
  k-from -> [102 114 111 109]
  k-to -> [116 111]
  k-ip-block -> [105 112 45 98 108 111 99 107]
  k-namespace-selector ->
    [110 97 109 101 115 112 97 99 101 45
     115 101 108 101 99 116 111 114]
  k-cidr -> [99 105 100 114]
  k-except -> [101 120 99 101 112 116]
  k-end-port -> [101 110 100 45 112 111 114 116]
  k-port -> [112 111 114 116]
  k-protocol -> [112 114 111 116 111 99 111 108]
  k-match-expressions ->
    [109 97 116 99 104 45 101 120 112 114 101 115 115 105 111 110 115]
  k-match-labels -> [109 97 116 99 104 45 108 97 98 101 108 115]
  k-key -> [107 101 121]
  k-operator -> [111 112 101 114 97 116 111 114]
  k-values -> [118 97 108 117 101 115]
  k-admitted -> [97 100 109 105 116 116 101 100]
  k-isolation -> [105 115 111 108 97 116 105 111 110]
  k-marker -> [109 97 114 107 101 114]
  k-space -> [115 112 97 99 101]
  k-err -> [101 114 114 111 114])

(define urdr.netpol.word
  w-tcp -> [84 67 80]
  w-udp -> [85 68 80]
  w-sctp -> [83 67 84 80]
  w-in -> [73 110]
  w-notin -> [78 111 116 73 110]
  w-exists -> [69 120 105 115 116 115]
  w-doesnotexist -> [68 111 101 115 78 111 116 69 120 105 115 116]
  w-ingress -> [73 110 103 114 101 115 115]
  w-egress -> [69 103 114 101 115 115]
  w-marker ->
    [115 112 101 99 45 115 101 109 97 110 116 105 99 115 45 111 110 108 121]
  f-dst-pod -> [100 115 116 45 112 111 100]
  f-dst-port -> [100 115 116 45 112 111 114 116]
  f-protocol -> [112 114 111 116 111 99 111 108]
  f-src-pod -> [115 114 99 45 112 111 100])

\\ ---------------------------------------------------------------
\\ Result plumbing
\\ ---------------------------------------------------------------

(define urdr.netpol.bind
  [error E] F -> [error E]
  [ok V] F -> (F V))

(define urdr.netpol.each
  F [] Acc -> [ok (urdr.canonical.rev Acc)]
  F [X | Xs] Acc ->
    (urdr.netpol.bind (F X) (/. V (urdr.netpol.each F Xs [V | Acc])))
  F _ Acc -> [error manifest-shape])

\\ ---------------------------------------------------------------
\\ Canonical accessors
\\ ---------------------------------------------------------------

(define urdr.netpol.assoc
  [] Key -> none
  [[K V] | Es] Key -> (if (= K Key) [ok V] (urdr.netpol.assoc Es Key))
  _ Key -> none)

(define urdr.netpol.member-bytes?
  B [] -> false
  B [X | Xs] -> (if (= B X) true (urdr.netpol.member-bytes? B Xs))
  B _ -> false)

(define urdr.netpol.keys-known?
  [] Allowed -> true
  [[K _] | Es] Allowed ->
    (if (urdr.netpol.member-bytes? K Allowed)
        (urdr.netpol.keys-known? Es Allowed)
        false)
  _ Allowed -> false)

(define urdr.netpol.keys-present?
  Entries [] -> true
  Entries [K | Ks] ->
    (if (= (urdr.netpol.assoc Entries K) none)
        false
        (urdr.netpol.keys-present? Entries Ks)))

(define urdr.netpol.record-fields
  [record Entries] Allowed Required [Shape Unmodeled Missing] ->
    (if (not (urdr.netpol.keys-known? Entries Allowed))
        [error Unmodeled]
        (if (not (urdr.netpol.keys-present? Entries Required))
            [error Missing]
            [ok Entries]))
  _ Allowed Required [Shape Unmodeled Missing] -> [error Shape])

(define urdr.netpol.universe-codes
  -> [universe-shape universe-unmodeled-field universe-missing-field])

(define urdr.netpol.manifest-codes
  -> [manifest-shape manifest-unmodeled-field manifest-missing-field])

(define urdr.netpol.text-of
  [text Bs] Code -> [ok Bs]
  _ Code -> [error Code])

(define urdr.netpol.list-of
  [list Vs] Code -> [ok Vs]
  _ Code -> [error Code])

(define urdr.netpol.record-of
  [record Es] Code -> [ok Es]
  _ Code -> [error Code])

(define urdr.netpol.int-of
  [big S M] Code -> [ok [big S M]]
  _ Code -> [error Code])

(define urdr.netpol.symbol-of
  [symbol Bs] Code -> [ok Bs]
  _ Code -> [error Code])

(define urdr.netpol.bool-of
  [bool B] Code -> [ok B]
  _ Code -> [error Code])

\\ ---------------------------------------------------------------
\\ Bounded host naturals: octets, prefix lengths, and division
\\ ---------------------------------------------------------------

(define urdr.netpol.quot
  N D -> (hd (urdr.int.small.divmod N D)))

(define urdr.netpol.pow2
  1 -> 2
  2 -> 4
  3 -> 8
  4 -> 16
  5 -> 32
  6 -> 64
  7 -> 128)

(define urdr.netpol.digit?
  B -> (and (>= B 48) (<= B 57)))

(define urdr.netpol.split
  Sep Bs -> (urdr.netpol.split-loop Sep Bs [] []))

(define urdr.netpol.split-loop
  Sep [] Cur Acc ->
    (urdr.canonical.rev [(urdr.canonical.rev Cur) | Acc])
  Sep [B | Bs] Cur Acc ->
    (if (= B Sep)
        (urdr.netpol.split-loop Sep Bs [] [(urdr.canonical.rev Cur) | Acc])
        (urdr.netpol.split-loop Sep Bs [B | Cur] Acc)))

(define urdr.netpol.decimal-loop
  [] Count N -> (if (= Count 0) none [ok N])
  [B | Bs] Count N ->
    (if (urdr.netpol.digit? B)
        (if (>= Count 3)
            none
            (urdr.netpol.decimal-loop Bs (+ Count 1) (+ (* N 10) (- B 48))))
        none)
  _ Count N -> none)

\\ A bounded decimal natural with no leading zero, at most three digits.
(define urdr.netpol.decimal
  [48] -> [ok 0]
  [48 | Bs] -> none
  Bs -> (urdr.netpol.decimal-loop Bs 0 0))

(define urdr.netpol.octet
  Bs -> (urdr.netpol.octet-bounded (urdr.netpol.decimal Bs)))

(define urdr.netpol.octet-bounded
  none -> [error address-malformed]
  [ok N] -> (if (> N 255) [error address-malformed] [ok N]))

(define urdr.netpol.address-octets
  [A B C D] ->
    (urdr.netpol.each (/. X (urdr.netpol.octet X)) [A B C D] [])
  _ -> [error address-malformed])

(define urdr.netpol.address
  Bs ->
    (if (urdr.netpol.member-bytes? 58 Bs)
        [error address-unmodeled]
        (urdr.netpol.address-octets (urdr.netpol.split 46 Bs))))

(define urdr.netpol.cidr
  Bs ->
    (if (urdr.netpol.member-bytes? 58 Bs)
        [error address-unmodeled]
        (urdr.netpol.cidr-parts (urdr.netpol.split 47 Bs))))

(define urdr.netpol.cidr-parts
  [A L] -> (urdr.netpol.cidr-length A (urdr.netpol.decimal L))
  _ -> [error cidr-malformed])

(define urdr.netpol.cidr-length
  A none -> [error cidr-malformed]
  A [ok N] ->
    (if (> N 32)
        [error cidr-malformed]
        (urdr.netpol.cidr-network (urdr.netpol.address-octets
                                    (urdr.netpol.split 46 A))
                                  N)))

(define urdr.netpol.cidr-network
  [error E] N -> [error cidr-malformed]
  [ok Octets] N -> [ok [Octets N]])

(define urdr.netpol.contained?
  Address Network 0 -> true
  [A | As] [N | Ns] Length ->
    (if (>= Length 8)
        (if (= A N)
            (urdr.netpol.contained? As Ns (- Length 8))
            false)
        (= (urdr.netpol.quot A (urdr.netpol.pow2 (- 8 Length)))
           (urdr.netpol.quot N (urdr.netpol.pow2 (- 8 Length)))))
  _ _ Length -> false)

\\ ---------------------------------------------------------------
\\ Label and port-name shapes
\\ ---------------------------------------------------------------

(define urdr.netpol.alnum?
  B -> (or (and (>= B 48) (<= B 57))
           (or (and (>= B 65) (<= B 90))
               (and (>= B 97) (<= B 122)))))

(define urdr.netpol.lower?
  B -> (or (and (>= B 48) (<= B 57)) (and (>= B 97) (<= B 122))))

(define urdr.netpol.label-mid?
  B -> (or (urdr.netpol.alnum? B)
           (or (= B 46) (or (= B 95) (or (= B 47) (= B 45))))))

(define urdr.netpol.label-tail?
  [] Count -> false
  [B] Count -> (and (urdr.netpol.alnum? B) (<= Count 61))
  [B | Bs] Count ->
    (and (urdr.netpol.label-mid? B)
         (urdr.netpol.label-tail? Bs (+ Count 1)))
  _ Count -> false)

(define urdr.netpol.label?
  [] -> false
  [B] -> (urdr.netpol.alnum? B)
  [B | Bs] ->
    (and (urdr.netpol.alnum? B) (urdr.netpol.label-tail? Bs 0))
  _ -> false)

(define urdr.netpol.port-name-tail?
  [] Count -> false
  [B] Count -> (and (urdr.netpol.lower? B) (<= Count 13))
  [B | Bs] Count ->
    (and (or (urdr.netpol.lower? B) (= B 45))
         (urdr.netpol.port-name-tail? Bs (+ Count 1)))
  _ Count -> false)

(define urdr.netpol.port-name?
  [] -> false
  [B] -> (urdr.netpol.lower? B)
  [B | Bs] ->
    (and (urdr.netpol.lower? B) (urdr.netpol.port-name-tail? Bs 0))
  _ -> false)

\\ ---------------------------------------------------------------
\\ Labels
\\ ---------------------------------------------------------------

(define urdr.netpol.labels-entries
  [] Code Acc -> [ok (urdr.canonical.rev Acc)]
  [[K V] | Es] Code Acc ->
    (if (not (urdr.netpol.label? K))
        [error label-invalid]
        (urdr.netpol.bind (urdr.netpol.text-of V Code)
          (/. Bs
            (if (not (urdr.netpol.label? Bs))
                [error label-invalid]
                (urdr.netpol.labels-entries Es Code [[K Bs] | Acc])))))
  _ Code Acc -> [error Code])

(define urdr.netpol.labels
  Value Code ->
    (urdr.netpol.bind (urdr.netpol.record-of Value Code)
      (/. Es (urdr.netpol.labels-entries Es Code []))))

(define urdr.netpol.labels-get
  [] K -> none
  [[K2 V] | Es] K -> (if (= K2 K) [ok V] (urdr.netpol.labels-get Es K)))

\\ ---------------------------------------------------------------
\\ Software-integer helpers over declared value sets
\\ ---------------------------------------------------------------

(define urdr.netpol.int-member?
  V [] -> false
  V [W | Ws] ->
    (if (= (urdr.int.raw.compare V W) 0)
        true
        (urdr.netpol.int-member? V Ws)))

(define urdr.netpol.int-filter
  [] Chosen Acc -> (urdr.canonical.rev Acc)
  [V | Vs] Chosen Acc ->
    (if (urdr.netpol.int-member? V Chosen)
        (urdr.netpol.int-filter Vs Chosen [V | Acc])
        (urdr.netpol.int-filter Vs Chosen Acc)))

(define urdr.netpol.indices
  0 Acc -> Acc
  N Acc ->
    (urdr.netpol.indices (- N 1) [(urdr.int.raw.from-small (- N 1)) | Acc]))

\\ ---------------------------------------------------------------
\\ NetKAT term construction (the predicate fragment)
\\ ---------------------------------------------------------------

(define urdr.netpol.mk-union
  [nk-drop] B -> B
  A [nk-drop] -> A
  [nk-id] B -> [nk-id]
  A [nk-id] -> [nk-id]
  A B -> (if (= A B) A [nk-union A B]))

(define urdr.netpol.mk-seq
  [nk-drop] B -> [nk-drop]
  A [nk-drop] -> [nk-drop]
  [nk-id] B -> B
  A [nk-id] -> A
  A B -> (if (= A B) A [nk-seq A B]))

(define urdr.netpol.mk-neg
  [nk-drop] -> [nk-id]
  [nk-id] -> [nk-drop]
  A -> [nk-neg A])

(define urdr.netpol.union-all
  [] -> [nk-drop]
  [T | Ts] -> (urdr.netpol.mk-union T (urdr.netpol.union-all Ts)))

(define urdr.netpol.test-term
  Field V -> [nk-test [symbol Field] V])

(define urdr.netpol.tests
  Field [] -> []
  Field [V | Vs] ->
    [(urdr.netpol.test-term Field V) | (urdr.netpol.tests Field Vs)])

(define urdr.netpol.value-set
  Field Chosen Declared ->
    (urdr.netpol.value-set-picked
      Field (urdr.netpol.int-filter Declared Chosen []) Declared))

(define urdr.netpol.value-set-picked
  Field [] Declared -> [nk-drop]
  Field Picked Declared ->
    (if (= (length Picked) (length Declared))
        [nk-id]
        (urdr.netpol.union-all (urdr.netpol.tests Field Picked))))

\\ ---------------------------------------------------------------
\\ Term rendering: a compact, unambiguous prefix form for goldens
\\ ---------------------------------------------------------------

(define urdr.netpol.render
  [nk-drop] -> [48]
  [nk-id] -> [49]
  [nk-test [symbol F] V] ->
    (append [40 63]
      (append F
        [61 | (append (urdr.int.raw.to-decimal-octets V) [41])]))
  [nk-union A B] ->
    (append [40 43]
      (append (urdr.netpol.render A)
        (append (urdr.netpol.render B) [41])))
  [nk-seq A B] ->
    (append [40 59]
      (append (urdr.netpol.render A)
        (append (urdr.netpol.render B) [41])))
  [nk-neg A] ->
    (append [40 126] (append (urdr.netpol.render A) [41])))

\\ ---------------------------------------------------------------
\\ The declared universe
\\ ---------------------------------------------------------------

(define urdr.netpol.universe-keys
  -> [(urdr.netpol.key k-externals)
      (urdr.netpol.key k-namespaces)
      (urdr.netpol.key k-pods)
      (urdr.netpol.key k-ports)
      (urdr.netpol.key k-protocols)])

(define urdr.netpol.universe-required
  -> [(urdr.netpol.key k-namespaces)
      (urdr.netpol.key k-pods)
      (urdr.netpol.key k-ports)
      (urdr.netpol.key k-protocols)])

(define urdr.netpol.u-field
  Entries Key -> (urdr.netpol.assoc Entries (urdr.netpol.key Key)))

(define urdr.netpol.port-bounds
  -> [(urdr.int.raw.from-small 1) (urdr.int.raw.from-small 65535)])

(define urdr.netpol.port-range?
  V ->
    (let Bounds (urdr.netpol.port-bounds)
      (and (>= (urdr.int.raw.compare V (hd Bounds)) 0)
           (<= (urdr.int.raw.compare V (hd (tl Bounds))) 0))))

(define urdr.netpol.u-ports-loop
  [] Previous Acc ->
    (if (= Acc [])
        [error universe-ports-empty]
        [ok (urdr.canonical.rev Acc)])
  [V | Vs] Previous Acc ->
    (urdr.netpol.bind (urdr.netpol.int-of V universe-shape)
      (/. P
        (if (not (urdr.netpol.port-range? P))
            [error universe-port-range]
            (if (and (not (= Previous none))
                     (<= (urdr.int.raw.compare P Previous) 0))
                [error universe-port-order]
                (urdr.netpol.u-ports-loop Vs P [P | Acc])))))
  _ Previous Acc -> [error universe-shape])

(define urdr.netpol.u-ports
  Entries ->
    (urdr.netpol.bind
      (urdr.netpol.list-of
        (hd (tl (urdr.netpol.u-field Entries k-ports))) universe-shape)
      (/. Vs (urdr.netpol.u-ports-loop Vs none []))))

(define urdr.netpol.protocol-code
  Bs ->
    (if (= Bs (urdr.netpol.word w-tcp))
        [ok 6]
        (if (= Bs (urdr.netpol.word w-udp))
            [ok 17]
            (if (= Bs (urdr.netpol.word w-sctp))
                [ok 132]
                [error protocol-unknown]))))

(define urdr.netpol.u-protocols-loop
  [] Previous Acc ->
    (if (= Acc [])
        [error universe-protocols-empty]
        [ok (urdr.canonical.rev Acc)])
  [V | Vs] Previous Acc ->
    (urdr.netpol.bind (urdr.netpol.symbol-of V universe-shape)
      (/. Bs
        (urdr.netpol.bind (urdr.netpol.protocol-code Bs)
          (/. Code
            (if (and (not (= Previous none)) (<= Code Previous))
                [error universe-protocol-order]
                (urdr.netpol.u-protocols-loop Vs Code [Code | Acc]))))))
  _ Previous Acc -> [error universe-shape])

(define urdr.netpol.u-protocols
  Entries ->
    (urdr.netpol.bind
      (urdr.netpol.list-of
        (hd (tl (urdr.netpol.u-field Entries k-protocols)))
        universe-shape)
      (/. Vs (urdr.netpol.u-protocols-loop Vs none []))))

(define urdr.netpol.u-namespace-labels
  Entries ->
    (urdr.netpol.optional-labels
      (urdr.netpol.assoc Entries (urdr.netpol.key k-labels))))

(define urdr.netpol.optional-labels
  none -> [ok []]
  [ok V] -> (urdr.netpol.labels V universe-shape))

(define urdr.netpol.u-namespace
  Value ->
    (urdr.netpol.bind
      (urdr.netpol.record-fields Value
        [(urdr.netpol.key k-labels) (urdr.netpol.key k-name)]
        [(urdr.netpol.key k-name)]
        (urdr.netpol.universe-codes))
      (/. Es
        (urdr.netpol.bind
          (urdr.netpol.text-of
            (hd (tl (urdr.netpol.assoc Es (urdr.netpol.key k-name))))
            universe-shape)
          (/. Name
            (if (not (urdr.netpol.label? Name))
                [error universe-shape]
                (urdr.netpol.bind (urdr.netpol.u-namespace-labels Es)
                  (/. Labels [ok [Name Labels]]))))))))

(define urdr.netpol.u-namespaces-loop
  [] Previous Acc ->
    (if (= Acc [])
        [error universe-namespaces-empty]
        [ok (urdr.canonical.rev Acc)])
  [V | Vs] Previous Acc ->
    (urdr.netpol.bind (urdr.netpol.u-namespace V)
      (/. Entry
        (if (and (not (= Previous none))
                 (not (= (urdr.canonical.bytes-compare (hd Entry) Previous)
                         gt)))
            [error universe-namespace-order]
            (urdr.netpol.u-namespaces-loop Vs (hd Entry) [Entry | Acc]))))
  _ Previous Acc -> [error universe-shape])

(define urdr.netpol.u-namespaces
  Entries ->
    (urdr.netpol.bind
      (urdr.netpol.list-of
        (hd (tl (urdr.netpol.u-field Entries k-namespaces)))
        universe-shape)
      (/. Vs (urdr.netpol.u-namespaces-loop Vs none []))))

(define urdr.netpol.namespace-known?
  Name [] -> false
  Name [[N _] | Ns] ->
    (if (= N Name) true (urdr.netpol.namespace-known? Name Ns)))

(define urdr.netpol.namespace-labels
  Name [] -> []
  Name [[N L] | Ns] ->
    (if (= N Name) L (urdr.netpol.namespace-labels Name Ns)))

(define urdr.netpol.container-ports-loop
  [] Ports Acc -> [ok (urdr.canonical.rev Acc)]
  [[K V] | Es] Ports Acc ->
    (if (not (urdr.netpol.port-name? K))
        [error container-port-invalid]
        (urdr.netpol.bind (urdr.netpol.int-of V universe-shape)
          (/. P
            (if (not (urdr.netpol.int-member? P Ports))
                [error container-port-invalid]
                (urdr.netpol.container-ports-loop Es Ports [[K P] | Acc])))))
  _ Ports Acc -> [error universe-shape])

(define urdr.netpol.container-ports
  none Ports -> [ok []]
  [ok V] Ports ->
    (urdr.netpol.bind (urdr.netpol.record-of V universe-shape)
      (/. Es (urdr.netpol.container-ports-loop Es Ports []))))

(define urdr.netpol.host-network
  none -> [ok false]
  [ok V] -> (urdr.netpol.bool-of V universe-shape))

(define urdr.netpol.pod-keys
  -> [(urdr.netpol.key k-address)
      (urdr.netpol.key k-host-network)
      (urdr.netpol.key k-labels)
      (urdr.netpol.key k-name)
      (urdr.netpol.key k-namespace)
      (urdr.netpol.key k-ports)])

(define urdr.netpol.u-pod
  Value Index Ports Namespaces ->
    (urdr.netpol.bind
      (urdr.netpol.record-fields Value
        (urdr.netpol.pod-keys)
        [(urdr.netpol.key k-address)
         (urdr.netpol.key k-name)
         (urdr.netpol.key k-namespace)]
        (urdr.netpol.universe-codes))
      (/. Es (urdr.netpol.u-pod-entries Es Index Ports Namespaces))))

(define urdr.netpol.u-pod-entries
  Es Index Ports Namespaces ->
    (urdr.netpol.bind
      (urdr.netpol.text-of
        (hd (tl (urdr.netpol.assoc Es (urdr.netpol.key k-name))))
        universe-shape)
      (/. Name
        (urdr.netpol.bind
          (urdr.netpol.text-of
            (hd (tl (urdr.netpol.assoc Es (urdr.netpol.key k-namespace))))
            universe-shape)
          (/. Ns
            (if (not (and (urdr.netpol.label? Name)
                          (urdr.netpol.label? Ns)))
                [error universe-shape]
                (if (not (urdr.netpol.namespace-known? Ns Namespaces))
                    [error universe-namespace-unknown]
                    (urdr.netpol.u-pod-rest Es Index Ports Name Ns))))))))

(define urdr.netpol.u-pod-rest
  Es Index Ports Name Ns ->
    (urdr.netpol.bind
      (urdr.netpol.text-of
        (hd (tl (urdr.netpol.assoc Es (urdr.netpol.key k-address))))
        universe-shape)
      (/. Raw
        (urdr.netpol.bind (urdr.netpol.address Raw)
          (/. Address
            (urdr.netpol.bind (urdr.netpol.optional-labels
                                (urdr.netpol.assoc
                                  Es (urdr.netpol.key k-labels)))
              (/. Labels
                (urdr.netpol.bind
                  (urdr.netpol.container-ports
                    (urdr.netpol.assoc Es (urdr.netpol.key k-ports)) Ports)
                  (/. Named
                    (urdr.netpol.bind
                      (urdr.netpol.host-network
                        (urdr.netpol.assoc
                          Es (urdr.netpol.key k-host-network)))
                      (/. Host
                        [ok [endpoint (urdr.int.raw.from-small Index)
                             Name Ns Address Labels Named Host]])))))))))))

(define urdr.netpol.u-pods-loop
  [] Index Ports Namespaces Previous Acc ->
    [ok (urdr.canonical.rev Acc)]
  [V | Vs] Index Ports Namespaces Previous Acc ->
    (urdr.netpol.bind (urdr.netpol.u-pod V Index Ports Namespaces)
      (/. E
        (let Key [(urdr.netpol.endpoint-namespace E)
                  (urdr.netpol.endpoint-name E)]
          (if (and (not (= Previous none))
                   (not (= (urdr.netpol.pair-compare Key Previous) gt)))
              [error universe-pod-order]
              (urdr.netpol.u-pods-loop
                Vs (+ Index 1) Ports Namespaces Key [E | Acc])))))
  _ Index Ports Namespaces Previous Acc -> [error universe-shape])

(define urdr.netpol.pair-compare
  [A1 A2] [B1 B2] ->
    (let C (urdr.canonical.bytes-compare A1 B1)
      (if (= C eq) (urdr.canonical.bytes-compare A2 B2) C)))

(define urdr.netpol.u-pods
  Entries Ports Namespaces ->
    (urdr.netpol.bind
      (urdr.netpol.list-of
        (hd (tl (urdr.netpol.u-field Entries k-pods))) universe-shape)
      (/. Vs (urdr.netpol.u-pods-loop Vs 0 Ports Namespaces none []))))

(define urdr.netpol.u-external
  Value Index ->
    (urdr.netpol.bind
      (urdr.netpol.record-fields Value
        [(urdr.netpol.key k-address) (urdr.netpol.key k-name)]
        [(urdr.netpol.key k-address) (urdr.netpol.key k-name)]
        (urdr.netpol.universe-codes))
      (/. Es
        (urdr.netpol.bind
          (urdr.netpol.text-of
            (hd (tl (urdr.netpol.assoc Es (urdr.netpol.key k-name))))
            universe-shape)
          (/. Name
            (if (not (urdr.netpol.label? Name))
                [error universe-shape]
                (urdr.netpol.bind
                  (urdr.netpol.text-of
                    (hd (tl (urdr.netpol.assoc
                              Es (urdr.netpol.key k-address))))
                    universe-shape)
                  (/. Raw
                    (urdr.netpol.bind (urdr.netpol.address Raw)
                      (/. Address
                        [ok [endpoint (urdr.int.raw.from-small Index)
                             Name none Address [] [] false]]))))))))))

(define urdr.netpol.u-externals-loop
  [] Index Previous Acc -> [ok (urdr.canonical.rev Acc)]
  [V | Vs] Index Previous Acc ->
    (urdr.netpol.bind (urdr.netpol.u-external V Index)
      (/. E
        (let Name (urdr.netpol.endpoint-name E)
          (if (and (not (= Previous none))
                   (not (= (urdr.canonical.bytes-compare Name Previous) gt)))
              [error universe-external-order]
              (urdr.netpol.u-externals-loop
                Vs (+ Index 1) Name [E | Acc])))))
  _ Index Previous Acc -> [error universe-shape])

(define urdr.netpol.u-externals
  Entries Index ->
    (urdr.netpol.u-externals-field
      (urdr.netpol.u-field Entries k-externals) Index))

(define urdr.netpol.u-externals-field
  none Index -> [ok []]
  [ok V] Index ->
    (urdr.netpol.bind (urdr.netpol.list-of V universe-shape)
      (/. Vs (urdr.netpol.u-externals-loop Vs Index none []))))

(define urdr.netpol.endpoint-index
  [endpoint I _ _ _ _ _ _] -> I)

(define urdr.netpol.endpoint-name
  [endpoint _ N _ _ _ _ _] -> N)

(define urdr.netpol.endpoint-namespace
  [endpoint _ _ Ns _ _ _ _] -> Ns)

(define urdr.netpol.endpoint-address
  [endpoint _ _ _ A _ _ _] -> A)

(define urdr.netpol.endpoint-labels
  [endpoint _ _ _ _ L _ _] -> L)

(define urdr.netpol.endpoint-ports
  [endpoint _ _ _ _ _ P _] -> P)

(define urdr.netpol.endpoint-host?
  [endpoint _ _ _ _ _ _ H] -> H)

(define urdr.netpol.endpoint-pod?
  E -> (not (= (urdr.netpol.endpoint-namespace E) none)))

(define urdr.netpol.address-unique?
  [] Seen -> true
  [E | Es] Seen ->
    (let A (urdr.netpol.endpoint-address E)
      (if (urdr.netpol.member-bytes? A Seen)
          false
          (urdr.netpol.address-unique? Es [A | Seen]))))

(define urdr.netpol.named-ports
  [] Acc -> Acc
  [E | Es] Acc ->
    (urdr.netpol.named-ports Es
      (urdr.netpol.named-ports-add (urdr.netpol.endpoint-ports E) Acc)))

(define urdr.netpol.named-ports-add
  [] Acc -> Acc
  [[K _] | Ps] Acc ->
    (urdr.netpol.named-ports-add Ps
      (if (urdr.netpol.member-bytes? K Acc) Acc [K | Acc])))

(define urdr.netpol.universe-finish
  Ports Protocols Namespaces Endpoints ->
    (if (= Endpoints [])
        [error universe-endpoints-empty]
        (if (not (urdr.netpol.address-unique? Endpoints []))
            [error universe-address-duplicate]
            [ok [universe Endpoints Namespaces Ports Protocols
                 (urdr.netpol.named-ports Endpoints [])]])))

(define urdr.netpol.universe
  Value ->
    (urdr.netpol.bind
      (urdr.netpol.record-fields Value
        (urdr.netpol.universe-keys) (urdr.netpol.universe-required)
        (urdr.netpol.universe-codes))
      (/. Es
        (urdr.netpol.bind (urdr.netpol.u-ports Es)
          (/. Ports
            (urdr.netpol.bind (urdr.netpol.u-protocols Es)
              (/. Protocols
                (urdr.netpol.bind (urdr.netpol.u-namespaces Es)
                  (/. Namespaces
                    (urdr.netpol.bind
                      (urdr.netpol.u-pods Es Ports Namespaces)
                      (/. Pods
                        (urdr.netpol.bind
                          (urdr.netpol.u-externals Es (length Pods))
                          (/. Externals
                            (urdr.netpol.universe-finish
                              Ports Protocols Namespaces
                              (append Pods Externals)))))))))))))))

(define urdr.netpol.universe-endpoints
  [universe E _ _ _ _] -> E)

(define urdr.netpol.universe-namespaces
  [universe _ N _ _ _] -> N)

(define urdr.netpol.universe-ports
  [universe _ _ P _ _] -> P)

(define urdr.netpol.universe-protocols
  [universe _ _ _ P _] -> P)

(define urdr.netpol.universe-names
  [universe _ _ _ _ N] -> N)

\\ ---------------------------------------------------------------
\\ Selectors
\\ ---------------------------------------------------------------

(define urdr.netpol.operator
  Bs ->
    (if (= Bs (urdr.netpol.word w-in))
        [ok op-in]
        (if (= Bs (urdr.netpol.word w-notin))
            [ok op-notin]
            (if (= Bs (urdr.netpol.word w-exists))
                [ok op-exists]
                (if (= Bs (urdr.netpol.word w-doesnotexist))
                    [ok op-doesnotexist]
                    [error selector-operator-unknown])))))

(define urdr.netpol.expr-values-loop
  [] Previous Acc -> [ok (urdr.canonical.rev Acc)]
  [V | Vs] Previous Acc ->
    (urdr.netpol.bind (urdr.netpol.text-of V manifest-shape)
      (/. Bs
        (if (not (urdr.netpol.label? Bs))
            [error label-invalid]
            (if (and (not (= Previous none))
                     (not (= (urdr.canonical.bytes-compare Bs Previous) gt)))
                [error selector-values-order]
                (urdr.netpol.expr-values-loop Vs Bs [Bs | Acc])))))
  _ Previous Acc -> [error manifest-shape])

(define urdr.netpol.expr-values
  none -> [ok []]
  [ok V] ->
    (urdr.netpol.bind (urdr.netpol.list-of V manifest-shape)
      (/. Vs (urdr.netpol.expr-values-loop Vs none []))))

(define urdr.netpol.expr-check
  Key Op Values ->
    (if (and (or (= Op op-in) (= Op op-notin)) (= Values []))
        [error selector-values-missing]
        (if (and (or (= Op op-exists) (= Op op-doesnotexist))
                 (not (= Values [])))
            [error selector-values-forbidden]
            [ok [expr Key Op Values]])))

(define urdr.netpol.expression
  Value ->
    (urdr.netpol.bind
      (urdr.netpol.record-fields Value
        [(urdr.netpol.key k-key)
         (urdr.netpol.key k-operator)
         (urdr.netpol.key k-values)]
        [(urdr.netpol.key k-key) (urdr.netpol.key k-operator)]
        (urdr.netpol.manifest-codes))
      (/. Es
        (urdr.netpol.bind
          (urdr.netpol.text-of
            (hd (tl (urdr.netpol.assoc Es (urdr.netpol.key k-key))))
            manifest-shape)
          (/. Key
            (if (not (urdr.netpol.label? Key))
                [error label-invalid]
                (urdr.netpol.bind
                  (urdr.netpol.symbol-of
                    (hd (tl (urdr.netpol.assoc
                              Es (urdr.netpol.key k-operator))))
                    manifest-shape)
                  (/. Raw
                    (urdr.netpol.bind (urdr.netpol.operator Raw)
                      (/. Op
                        (urdr.netpol.bind
                          (urdr.netpol.expr-values
                            (urdr.netpol.assoc
                              Es (urdr.netpol.key k-values)))
                          (/. Values
                            (urdr.netpol.expr-check Key Op Values)))))))))))))

(define urdr.netpol.selector-labels
  none -> [ok []]
  [ok V] -> (urdr.netpol.labels V manifest-shape))

(define urdr.netpol.selector-exprs
  none -> [ok []]
  [ok V] ->
    (urdr.netpol.bind (urdr.netpol.list-of V manifest-shape)
      (/. Vs
        (urdr.netpol.each (/. X (urdr.netpol.expression X)) Vs []))))

(define urdr.netpol.selector
  Value ->
    (urdr.netpol.bind
      (urdr.netpol.record-fields Value
        [(urdr.netpol.key k-match-expressions)
         (urdr.netpol.key k-match-labels)]
        []
        (urdr.netpol.manifest-codes))
      (/. Es
        (urdr.netpol.bind
          (urdr.netpol.selector-labels
            (urdr.netpol.assoc Es (urdr.netpol.key k-match-labels)))
          (/. Labels
            (urdr.netpol.bind
              (urdr.netpol.selector-exprs
                (urdr.netpol.assoc
                  Es (urdr.netpol.key k-match-expressions)))
              (/. Exprs [ok [selector Labels Exprs]])))))))

(define urdr.netpol.labels-match?
  [] Target -> true
  [[K V] | Ls] Target ->
    (if (= (urdr.netpol.labels-get Target K) [ok V])
        (urdr.netpol.labels-match? Ls Target)
        false))

(define urdr.netpol.expr-match?
  [expr Key op-in Values] Target ->
    (urdr.netpol.expr-in? (urdr.netpol.labels-get Target Key) Values)
  [expr Key op-notin Values] Target ->
    (not (urdr.netpol.expr-in? (urdr.netpol.labels-get Target Key) Values))
  [expr Key op-exists Values] Target ->
    (not (= (urdr.netpol.labels-get Target Key) none))
  [expr Key op-doesnotexist Values] Target ->
    (= (urdr.netpol.labels-get Target Key) none))

(define urdr.netpol.expr-in?
  none Values -> false
  [ok V] Values -> (urdr.netpol.member-bytes? V Values))

(define urdr.netpol.exprs-match?
  [] Target -> true
  [E | Es] Target ->
    (if (urdr.netpol.expr-match? E Target)
        (urdr.netpol.exprs-match? Es Target)
        false))

(define urdr.netpol.selector-matches?
  [selector Labels Exprs] Target ->
    (and (urdr.netpol.labels-match? Labels Target)
         (urdr.netpol.exprs-match? Exprs Target)))

\\ ---------------------------------------------------------------
\\ Peers
\\ ---------------------------------------------------------------

(define urdr.netpol.excepts-loop
  [] Network Length Previous Acc -> [ok (urdr.canonical.rev Acc)]
  [V | Vs] Network Length Previous Acc ->
    (urdr.netpol.bind (urdr.netpol.text-of V manifest-shape)
      (/. Raw
        (if (and (not (= Previous none))
                 (not (= (urdr.canonical.bytes-compare Raw Previous) gt)))
            [error ipblock-except-order]
            (urdr.netpol.bind (urdr.netpol.cidr Raw)
              (/. Block
                (if (or (< (hd (tl Block)) Length)
                        (not (urdr.netpol.contained?
                               (hd Block) Network Length)))
                    [error ipblock-except-outside-cidr]
                    (urdr.netpol.excepts-loop
                      Vs Network Length Raw [Block | Acc])))))))
  _ Network Length Previous Acc -> [error manifest-shape])

(define urdr.netpol.excepts
  none Network Length -> [ok []]
  [ok V] Network Length ->
    (urdr.netpol.bind (urdr.netpol.list-of V manifest-shape)
      (/. Vs (urdr.netpol.excepts-loop Vs Network Length none []))))

(define urdr.netpol.ip-block
  Value ->
    (urdr.netpol.bind
      (urdr.netpol.record-fields Value
        [(urdr.netpol.key k-cidr) (urdr.netpol.key k-except)]
        [(urdr.netpol.key k-cidr)]
        (urdr.netpol.manifest-codes))
      (/. Es
        (urdr.netpol.bind
          (urdr.netpol.text-of
            (hd (tl (urdr.netpol.assoc Es (urdr.netpol.key k-cidr))))
            manifest-shape)
          (/. Raw
            (urdr.netpol.bind (urdr.netpol.cidr Raw)
              (/. Block
                (urdr.netpol.bind
                  (urdr.netpol.excepts
                    (urdr.netpol.assoc Es (urdr.netpol.key k-except))
                    (hd Block) (hd (tl Block)))
                  (/. Excepts
                    [ok [peer-ip (hd Block) (hd (tl Block)) Excepts]])))))))))

(define urdr.netpol.optional-selector
  none -> [ok none]
  [ok V] ->
    (urdr.netpol.bind (urdr.netpol.selector V) (/. S [ok S])))

(define urdr.netpol.peer-selectors
  Es ->
    (urdr.netpol.bind
      (urdr.netpol.optional-selector
        (urdr.netpol.assoc Es (urdr.netpol.key k-namespace-selector)))
      (/. NsSel
        (urdr.netpol.bind
          (urdr.netpol.optional-selector
            (urdr.netpol.assoc Es (urdr.netpol.key k-pod-selector)))
          (/. PodSel [ok [peer-sel NsSel PodSel]])))))

(define urdr.netpol.peer-entries
  [] -> [error peer-empty]
  Es ->
    (if (= (urdr.netpol.assoc Es (urdr.netpol.key k-ip-block)) none)
        (urdr.netpol.peer-selectors Es)
        (if (and (= (urdr.netpol.assoc
                      Es (urdr.netpol.key k-namespace-selector))
                    none)
                 (= (urdr.netpol.assoc Es (urdr.netpol.key k-pod-selector))
                    none))
            (urdr.netpol.ip-block
              (hd (tl (urdr.netpol.assoc Es (urdr.netpol.key k-ip-block)))))
            [error peer-ipblock-exclusive])))

(define urdr.netpol.peer
  Value ->
    (urdr.netpol.bind
      (urdr.netpol.record-fields Value
        [(urdr.netpol.key k-ip-block)
         (urdr.netpol.key k-namespace-selector)
         (urdr.netpol.key k-pod-selector)]
        []
        (urdr.netpol.manifest-codes))
      (/. Es (urdr.netpol.peer-entries Es))))

\\ ---------------------------------------------------------------
\\ Port entries
\\ ---------------------------------------------------------------

(define urdr.netpol.entry-protocol
  none Universe -> (urdr.netpol.entry-protocol-code 6 Universe)
  [ok V] Universe ->
    (urdr.netpol.bind (urdr.netpol.symbol-of V manifest-shape)
      (/. Bs
        (urdr.netpol.bind (urdr.netpol.protocol-code Bs)
          (/. Code (urdr.netpol.entry-protocol-code Code Universe))))))

(define urdr.netpol.entry-protocol-code
  Code Universe ->
    (if (urdr.netpol.member-bytes? Code (urdr.netpol.universe-protocols
                                          Universe))
        [ok Code]
        [error protocol-out-of-vocabulary]))

(define urdr.netpol.entry-port
  none Universe -> [ok [none none none]]
  [ok [text Bs]] Universe ->
    (if (not (urdr.netpol.port-name? Bs))
        [error named-port-invalid]
        (if (not (urdr.netpol.member-bytes?
                   Bs (urdr.netpol.universe-names Universe)))
            [error named-port-unresolved]
            [ok [Bs none none]]))
  [ok V] Universe ->
    (urdr.netpol.bind (urdr.netpol.int-of V manifest-shape)
      (/. P
        (if (not (urdr.netpol.port-range? P))
            [error port-range]
            [ok [none P P]]))))

(define urdr.netpol.entry-end
  none Universe [Named Low High] -> (urdr.netpol.entry-plain Named Low High
                                      Universe)
  [ok V] Universe [Named Low High] ->
    (if (not (= Named none))
        [error end-port-named-port]
        (if (= Low none)
            [error end-port-without-port]
            (urdr.netpol.bind (urdr.netpol.int-of V manifest-shape)
              (/. E
                (if (not (urdr.netpol.port-range? E))
                    [error port-range]
                    (if (< (urdr.int.raw.compare E Low) 0)
                        [error end-port-range]
                        [ok [Named Low E]])))))))

\\ Without an endPort a numeric port must name a declared port; a range
\\ instead projects onto the declared vocabulary and needs no such check.
(define urdr.netpol.entry-plain
  none none High Universe -> [ok [none none High]]
  none Low High Universe ->
    (if (urdr.netpol.int-member? Low (urdr.netpol.universe-ports Universe))
        [ok [none Low High]]
        [error port-out-of-vocabulary])
  Named Low High Universe -> [ok [Named Low High]])

(define urdr.netpol.port-entry
  Value Universe ->
    (urdr.netpol.bind
      (urdr.netpol.record-fields Value
        [(urdr.netpol.key k-end-port)
         (urdr.netpol.key k-port)
         (urdr.netpol.key k-protocol)]
        []
        (urdr.netpol.manifest-codes))
      (/. Es
        (urdr.netpol.bind
          (urdr.netpol.entry-protocol
            (urdr.netpol.assoc Es (urdr.netpol.key k-protocol)) Universe)
          (/. Code
            (urdr.netpol.bind
              (urdr.netpol.entry-port
                (urdr.netpol.assoc Es (urdr.netpol.key k-port)) Universe)
              (/. Parts
                (urdr.netpol.bind
                  (urdr.netpol.entry-end
                    (urdr.netpol.assoc Es (urdr.netpol.key k-end-port))
                    Universe Parts)
                  (/. Final
                    [ok [entry Code (hd Final) (hd (tl Final))
                         (hd (tl (tl Final)))]])))))))))

\\ ---------------------------------------------------------------
\\ Rules and policies
\\ ---------------------------------------------------------------

(define urdr.netpol.rule-peers
  none -> [ok [true []]]
  [ok V] ->
    (urdr.netpol.bind (urdr.netpol.list-of V manifest-shape)
      (/. Vs
        (if (= Vs [])
            [ok [true []]]
            (urdr.netpol.bind
              (urdr.netpol.each (/. X (urdr.netpol.peer X)) Vs [])
              (/. Peers [ok [false Peers]]))))))

(define urdr.netpol.rule-ports
  none Universe -> [ok [true []]]
  [ok V] Universe ->
    (urdr.netpol.bind (urdr.netpol.list-of V manifest-shape)
      (/. Vs
        (if (= Vs [])
            [ok [true []]]
            (urdr.netpol.bind
              (urdr.netpol.each
                (/. X (urdr.netpol.port-entry X Universe)) Vs [])
              (/. Entries [ok [false Entries]]))))))

(define urdr.netpol.rule
  Value Universe PeerKey ->
    (urdr.netpol.bind
      (urdr.netpol.record-fields Value
        [(urdr.netpol.key PeerKey) (urdr.netpol.key k-ports)]
        []
        (urdr.netpol.manifest-codes))
      (/. Es
        (urdr.netpol.bind
          (urdr.netpol.rule-peers
            (urdr.netpol.assoc Es (urdr.netpol.key PeerKey)))
          (/. P
            (urdr.netpol.bind
              (urdr.netpol.rule-ports
                (urdr.netpol.assoc Es (urdr.netpol.key k-ports)) Universe)
              (/. Q
                [ok [rule (hd P) (hd (tl P)) (hd Q) (hd (tl Q))]])))))))

(define urdr.netpol.rules
  none Universe PeerKey -> [ok []]
  [ok V] Universe PeerKey ->
    (urdr.netpol.bind (urdr.netpol.list-of V manifest-shape)
      (/. Vs
        (urdr.netpol.each
          (/. X (urdr.netpol.rule X Universe PeerKey)) Vs []))))

(define urdr.netpol.types-loop
  [] Previous Acc -> [ok Acc]
  [V | Vs] Previous Acc ->
    (urdr.netpol.bind (urdr.netpol.symbol-of V manifest-shape)
      (/. Bs
        (if (not (or (= Bs (urdr.netpol.word w-ingress))
                     (= Bs (urdr.netpol.word w-egress))))
            [error policy-type-unknown]
            (if (and (not (= Previous none))
                     (not (= (urdr.canonical.bytes-compare Bs Previous) gt)))
                [error policy-type-order]
                (urdr.netpol.types-loop Vs Bs [Bs | Acc])))))
  _ Previous Acc -> [error manifest-shape])

(define urdr.netpol.policy-types
  none HasEgress ->
    [ok [true HasEgress]]
  [ok V] HasEgress ->
    (urdr.netpol.bind (urdr.netpol.list-of V manifest-shape)
      (/. Vs
        (urdr.netpol.bind (urdr.netpol.types-loop Vs none [])
          (/. Names
            [ok [(urdr.netpol.member-bytes?
                   (urdr.netpol.word w-ingress) Names)
                 (urdr.netpol.member-bytes?
                   (urdr.netpol.word w-egress) Names)]])))))

(define urdr.netpol.policy-keys
  -> [(urdr.netpol.key k-egress)
      (urdr.netpol.key k-ingress)
      (urdr.netpol.key k-name)
      (urdr.netpol.key k-namespace)
      (urdr.netpol.key k-pod-selector)
      (urdr.netpol.key k-policy-types)])

(define urdr.netpol.policy
  Value Universe ->
    (urdr.netpol.bind
      (urdr.netpol.record-fields Value
        (urdr.netpol.policy-keys)
        [(urdr.netpol.key k-name)
         (urdr.netpol.key k-namespace)
         (urdr.netpol.key k-pod-selector)]
        (urdr.netpol.manifest-codes))
      (/. Es (urdr.netpol.policy-entries Es Universe))))

(define urdr.netpol.policy-entries
  Es Universe ->
    (urdr.netpol.bind
      (urdr.netpol.text-of
        (hd (tl (urdr.netpol.assoc Es (urdr.netpol.key k-name))))
        manifest-shape)
      (/. Name
        (urdr.netpol.bind
          (urdr.netpol.text-of
            (hd (tl (urdr.netpol.assoc Es (urdr.netpol.key k-namespace))))
            manifest-shape)
          (/. Ns
            (if (not (and (urdr.netpol.label? Name)
                          (urdr.netpol.label? Ns)))
                [error manifest-shape]
                (if (not (urdr.netpol.namespace-known?
                           Ns (urdr.netpol.universe-namespaces Universe)))
                    [error policy-namespace-unknown]
                    (urdr.netpol.policy-rest Es Universe Name Ns))))))))

(define urdr.netpol.policy-rest
  Es Universe Name Ns ->
    (urdr.netpol.bind
      (urdr.netpol.selector
        (hd (tl (urdr.netpol.assoc Es (urdr.netpol.key k-pod-selector)))))
      (/. Sel
        (urdr.netpol.bind
          (urdr.netpol.rules
            (urdr.netpol.assoc Es (urdr.netpol.key k-ingress))
            Universe k-from)
          (/. In
            (urdr.netpol.bind
              (urdr.netpol.rules
                (urdr.netpol.assoc Es (urdr.netpol.key k-egress))
                Universe k-to)
              (/. Out
                (urdr.netpol.bind
                  (urdr.netpol.policy-types
                    (urdr.netpol.assoc Es (urdr.netpol.key k-policy-types))
                    (not (= (urdr.netpol.assoc
                              Es (urdr.netpol.key k-egress))
                            none)))
                  (/. Types
                    [ok [policy Name Ns Sel (hd Types) (hd (tl Types))
                         In Out]])))))))))

(define urdr.netpol.policy-name
  [policy N _ _ _ _ _ _] -> N)

(define urdr.netpol.policy-namespace
  [policy _ Ns _ _ _ _ _] -> Ns)

(define urdr.netpol.policy-selector
  [policy _ _ S _ _ _ _] -> S)

(define urdr.netpol.policy-ingress?
  [policy _ _ _ I _ _ _] -> I)

(define urdr.netpol.policy-egress?
  [policy _ _ _ _ E _ _] -> E)

(define urdr.netpol.policy-ingress-rules
  [policy _ _ _ _ _ R _] -> R)

(define urdr.netpol.policy-egress-rules
  [policy _ _ _ _ _ _ R] -> R)

(define urdr.netpol.policies-loop
  [] Universe Previous Acc -> [ok (urdr.canonical.rev Acc)]
  [V | Vs] Universe Previous Acc ->
    (urdr.netpol.bind (urdr.netpol.policy V Universe)
      (/. P
        (let Key [(urdr.netpol.policy-namespace P)
                  (urdr.netpol.policy-name P)]
          (if (and (not (= Previous none))
                   (not (= (urdr.netpol.pair-compare Key Previous) gt)))
              [error policy-order]
              (urdr.netpol.policies-loop Vs Universe Key [P | Acc])))))
  _ Universe Previous Acc -> [error policies-shape])

(define urdr.netpol.policies
  Value Universe ->
    (urdr.netpol.bind (urdr.netpol.list-of Value policies-shape)
      (/. Vs (urdr.netpol.policies-loop Vs Universe none []))))

\\ ---------------------------------------------------------------
\\ Compilation
\\ ---------------------------------------------------------------

(define urdr.netpol.selects?
  Policy Endpoint ->
    (and (urdr.netpol.endpoint-pod? Endpoint)
         (and (= (urdr.netpol.endpoint-namespace Endpoint)
                 (urdr.netpol.policy-namespace Policy))
              (urdr.netpol.selector-matches?
                (urdr.netpol.policy-selector Policy)
                (urdr.netpol.endpoint-labels Endpoint)))))

(define urdr.netpol.direction?
  Policy dir-ingress -> (urdr.netpol.policy-ingress? Policy)
  Policy dir-egress -> (urdr.netpol.policy-egress? Policy))

(define urdr.netpol.direction-rules
  Policy dir-ingress -> (urdr.netpol.policy-ingress-rules Policy)
  Policy dir-egress -> (urdr.netpol.policy-egress-rules Policy))

(define urdr.netpol.isolated?
  [] Endpoint Direction -> false
  [P | Ps] Endpoint Direction ->
    (if (and (urdr.netpol.direction? P Direction)
             (urdr.netpol.selects? P Endpoint))
        true
        (urdr.netpol.isolated? Ps Endpoint Direction)))

\\ ipBlock containment over the declared endpoint addresses.
(define urdr.netpol.inside
  [] Network Length Acc -> (urdr.canonical.rev Acc)
  [E | Es] Network Length Acc ->
    (if (urdr.netpol.contained?
          (urdr.netpol.endpoint-address E) Network Length)
        (urdr.netpol.inside Es Network Length
          [(urdr.netpol.endpoint-index E) | Acc])
        (urdr.netpol.inside Es Network Length Acc)))

(define urdr.netpol.excluded?
  Address [] -> false
  Address [[Network Length] | Bs] ->
    (if (urdr.netpol.contained? Address Network Length)
        true
        (urdr.netpol.excluded? Address Bs)))

(define urdr.netpol.outside
  [] Excepts Acc -> (urdr.canonical.rev Acc)
  [E | Es] Excepts Acc ->
    (if (urdr.netpol.excluded? (urdr.netpol.endpoint-address E) Excepts)
        (urdr.netpol.outside Es Excepts
          [(urdr.netpol.endpoint-index E) | Acc])
        (urdr.netpol.outside Es Excepts Acc)))

(define urdr.netpol.namespaces-matching
  [] Selector Acc -> (urdr.canonical.rev Acc)
  [[N L] | Ns] Selector Acc ->
    (if (urdr.netpol.selector-matches? Selector L)
        (urdr.netpol.namespaces-matching Ns Selector [N | Acc])
        (urdr.netpol.namespaces-matching Ns Selector Acc)))

(define urdr.netpol.pods-matching
  [] Names Selector Acc -> (urdr.canonical.rev Acc)
  [E | Es] Names Selector Acc ->
    (if (and (urdr.netpol.endpoint-pod? E)
             (and (urdr.netpol.member-bytes?
                    (urdr.netpol.endpoint-namespace E) Names)
                  (or (= Selector none)
                      (urdr.netpol.selector-matches?
                        Selector (urdr.netpol.endpoint-labels E)))))
        (urdr.netpol.pods-matching Es Names Selector
          [(urdr.netpol.endpoint-index E) | Acc])
        (urdr.netpol.pods-matching Es Names Selector Acc)))

(define urdr.netpol.peer-term
  [peer-ip Network Length Excepts] Field Namespace Universe Indices ->
    (urdr.netpol.mk-seq
      (urdr.netpol.value-set Field
        (urdr.netpol.inside
          (urdr.netpol.universe-endpoints Universe) Network Length [])
        Indices)
      (urdr.netpol.mk-neg
        (urdr.netpol.value-set Field
          (urdr.netpol.outside
            (urdr.netpol.universe-endpoints Universe) Excepts [])
          Indices)))
  [peer-sel NsSel PodSel] Field Namespace Universe Indices ->
    (urdr.netpol.value-set Field
      (urdr.netpol.pods-matching
        (urdr.netpol.universe-endpoints Universe)
        (if (= NsSel none)
            [Namespace]
            (urdr.netpol.namespaces-matching
              (urdr.netpol.universe-namespaces Universe) NsSel []))
        PodSel [])
      Indices))

(define urdr.netpol.peers-term
  [] Field Namespace Universe Indices -> []
  [P | Ps] Field Namespace Universe Indices ->
    [(urdr.netpol.peer-term P Field Namespace Universe Indices)
     | (urdr.netpol.peers-term Ps Field Namespace Universe Indices)])

(define urdr.netpol.rule-peer-term
  [rule true Peers _ _] Field Namespace Universe Indices -> [nk-id]
  [rule false Peers _ _] Field Namespace Universe Indices ->
    (urdr.netpol.union-all
      (urdr.netpol.peers-term Peers Field Namespace Universe Indices)))

(define urdr.netpol.entry-ports
  [entry Code Named Low High] Universe Destination ->
    (if (= Named none)
        (if (= Low none)
            (urdr.netpol.universe-ports Universe)
            (urdr.netpol.range-ports
              (urdr.netpol.universe-ports Universe) Low High []))
        (urdr.netpol.named-lookup
          (urdr.netpol.endpoint-ports Destination) Named)))

(define urdr.netpol.named-lookup
  [] Named -> []
  [[K V] | Ps] Named ->
    (if (= K Named) [V] (urdr.netpol.named-lookup Ps Named)))

(define urdr.netpol.range-ports
  [] Low High Acc -> (urdr.canonical.rev Acc)
  [P | Ps] Low High Acc ->
    (if (and (>= (urdr.int.raw.compare P Low) 0)
             (<= (urdr.int.raw.compare P High) 0))
        (urdr.netpol.range-ports Ps Low High [P | Acc])
        (urdr.netpol.range-ports Ps Low High Acc)))

(define urdr.netpol.entry-term
  Entry Universe Destination ->
    (urdr.netpol.mk-seq
      (urdr.netpol.test-term (urdr.netpol.word f-protocol)
        (urdr.int.raw.from-small (hd (tl Entry))))
      (urdr.netpol.value-set (urdr.netpol.word f-dst-port)
        (urdr.netpol.entry-ports Entry Universe Destination)
        (urdr.netpol.universe-ports Universe))))

(define urdr.netpol.entries-term
  [] Universe Destination -> []
  [E | Es] Universe Destination ->
    [(urdr.netpol.entry-term E Universe Destination)
     | (urdr.netpol.entries-term Es Universe Destination)])

(define urdr.netpol.entry-named?
  [entry _ Named _ _] -> (not (= Named none)))

(define urdr.netpol.entries-named?
  [] -> false
  [E | Es] ->
    (if (urdr.netpol.entry-named? E)
        true
        (urdr.netpol.entries-named? Es)))

(define urdr.netpol.distributed-ports
  [] Entries Universe -> []
  [E | Es] Entries Universe ->
    [(urdr.netpol.mk-seq
       (urdr.netpol.test-term (urdr.netpol.word f-dst-pod)
         (urdr.netpol.endpoint-index E))
       (urdr.netpol.union-all
         (urdr.netpol.entries-term Entries Universe E)))
     | (urdr.netpol.distributed-ports Es Entries Universe)])

(define urdr.netpol.rule-ports-term
  [rule _ _ true Entries] Universe Destination -> [nk-id]
  [rule _ _ false Entries] Universe none ->
    (if (urdr.netpol.entries-named? Entries)
        (urdr.netpol.union-all
          (urdr.netpol.distributed-ports
            (urdr.netpol.universe-endpoints Universe) Entries Universe))
        (urdr.netpol.union-all
          (urdr.netpol.entries-term Entries Universe none)))
  [rule _ _ false Entries] Universe Destination ->
    (urdr.netpol.union-all
      (urdr.netpol.entries-term Entries Universe Destination)))

(define urdr.netpol.rule-term
  Rule Policy Endpoint dir-ingress Universe Indices ->
    (urdr.netpol.mk-seq
      (urdr.netpol.rule-peer-term Rule (urdr.netpol.word f-src-pod)
        (urdr.netpol.policy-namespace Policy) Universe Indices)
      (urdr.netpol.rule-ports-term Rule Universe Endpoint))
  Rule Policy Endpoint dir-egress Universe Indices ->
    (urdr.netpol.mk-seq
      (urdr.netpol.rule-peer-term Rule (urdr.netpol.word f-dst-pod)
        (urdr.netpol.policy-namespace Policy) Universe Indices)
      (urdr.netpol.rule-ports-term Rule Universe none)))

(define urdr.netpol.rule-terms
  [] Policy Endpoint Direction Universe Indices -> []
  [R | Rs] Policy Endpoint Direction Universe Indices ->
    [(urdr.netpol.rule-term R Policy Endpoint Direction Universe Indices)
     | (urdr.netpol.rule-terms Rs Policy Endpoint Direction Universe
         Indices)])

(define urdr.netpol.policy-terms
  [] Endpoint Direction Universe Indices -> []
  [P | Ps] Endpoint Direction Universe Indices ->
    (if (and (urdr.netpol.direction? P Direction)
             (urdr.netpol.selects? P Endpoint))
        (append
          (urdr.netpol.rule-terms
            (urdr.netpol.direction-rules P Direction)
            P Endpoint Direction Universe Indices)
          (urdr.netpol.policy-terms Ps Endpoint Direction Universe Indices))
        (urdr.netpol.policy-terms Ps Endpoint Direction Universe Indices)))

(define urdr.netpol.allow-term
  Policies Endpoint Direction Universe Indices ->
    (if (not (urdr.netpol.isolated? Policies Endpoint Direction))
        [nk-id]
        (urdr.netpol.union-all
          (urdr.netpol.policy-terms
            Policies Endpoint Direction Universe Indices))))

(define urdr.netpol.allow-terms
  [] Policies Direction Universe Indices -> []
  [E | Es] Policies Direction Universe Indices ->
    [(urdr.netpol.allow-term Policies E Direction Universe Indices)
     | (urdr.netpol.allow-terms Es Policies Direction Universe Indices)])

(define urdr.netpol.all-id?
  [] -> true
  [[nk-id] | Ts] -> (urdr.netpol.all-id? Ts)
  _ -> false)

(define urdr.netpol.side-terms
  [] [] Field -> []
  [E | Es] [A | As] Field ->
    [(urdr.netpol.mk-seq
       (urdr.netpol.test-term Field (urdr.netpol.endpoint-index E)) A)
     | (urdr.netpol.side-terms Es As Field)])

(define urdr.netpol.side-of
  Allows Endpoints Field ->
    (if (urdr.netpol.all-id? Allows)
        [nk-id]
        (urdr.netpol.union-all
          (urdr.netpol.side-terms Endpoints Allows Field))))

(define urdr.netpol.isolation-bytes
  [] Policies -> []
  [E | Es] Policies ->
    [(if (urdr.netpol.isolated? Policies E dir-ingress) 73 45)
     (if (urdr.netpol.isolated? Policies E dir-egress) 69 45)
     | (urdr.netpol.isolation-bytes Es Policies)])

(define urdr.netpol.host-network-free?
  [] -> true
  [E | Es] ->
    (if (urdr.netpol.endpoint-host? E)
        false
        (urdr.netpol.host-network-free? Es)))

(define urdr.netpol.vocab-value
  Universe Indices ->
    [record
      [[(urdr.netpol.word f-dst-pod) [list Indices]]
       [(urdr.netpol.word f-dst-port)
        [list (urdr.netpol.universe-ports Universe)]]
       [(urdr.netpol.word f-protocol)
        [list (urdr.netpol.protocol-values
                (urdr.netpol.universe-protocols Universe))]]
       [(urdr.netpol.word f-src-pod) [list Indices]]]])

(define urdr.netpol.protocol-values
  [] -> []
  [C | Cs] ->
    [(urdr.int.raw.from-small C) | (urdr.netpol.protocol-values Cs)])

(define urdr.netpol.compile-terms
  Universe Policies Vocab Indices ->
    (let Endpoints (urdr.netpol.universe-endpoints Universe)
         Out (urdr.netpol.allow-terms
               Endpoints Policies dir-egress Universe Indices)
         In (urdr.netpol.allow-terms
              Endpoints Policies dir-ingress Universe Indices)
         Egress (urdr.netpol.side-of
                  Out Endpoints (urdr.netpol.word f-src-pod))
         Ingress (urdr.netpol.side-of
                   In Endpoints (urdr.netpol.word f-dst-pod))
         Term (urdr.netpol.mk-seq Egress Ingress)
      (urdr.netpol.compile-checked
        (urdr.netkat.term-check Vocab Term)
        Vocab Egress Ingress Out In
        (urdr.netpol.isolation-bytes Endpoints Policies))))

(define urdr.netpol.compile-checked
  [error E] Vocab Egress Ingress Out In Isolation -> [error E]
  [ok Term] Vocab Egress Ingress Out In Isolation ->
    [ok [compiled Vocab Term Egress Ingress Out In Isolation
         (urdr.netkat.vocab-space-size Vocab)]])

(define urdr.netpol.compile
  Universe Policies ->
    (if (and (not (= Policies []))
             (not (urdr.netpol.host-network-free?
                    (urdr.netpol.universe-endpoints Universe))))
        [error host-network-pod-under-policy]
        (let Indices (urdr.netpol.indices
                       (length (urdr.netpol.universe-endpoints Universe)) [])
          (urdr.netpol.bind
            (urdr.netkat.vocabulary
              (urdr.netpol.vocab-value Universe Indices))
            (/. Vocab
              (urdr.netpol.compile-terms
                Universe Policies Vocab Indices))))))

\\ ---------------------------------------------------------------
\\ Compiled results
\\ ---------------------------------------------------------------

(define urdr.netpol.compiled-vocab
  [compiled V _ _ _ _ _ _ _] -> V)

\\ The total connection-admission term: the egress side sequenced with
\\ the ingress side.
(define urdr.netpol.compiled-term
  [compiled _ T _ _ _ _ _ _] -> T)

(define urdr.netpol.compiled-egress
  [compiled _ _ E _ _ _ _ _] -> E)

(define urdr.netpol.compiled-ingress
  [compiled _ _ _ I _ _ _ _] -> I)

\\ Per-endpoint allow terms, in declared endpoint order.
(define urdr.netpol.compiled-egress-allows
  [compiled _ _ _ _ A _ _ _] -> A)

(define urdr.netpol.compiled-ingress-allows
  [compiled _ _ _ _ _ A _ _] -> A)

\\ Two octets per endpoint: 'I'/'-' for ingress, 'E'/'-' for egress.
(define urdr.netpol.compiled-isolation
  [compiled _ _ _ _ _ _ I _] -> I)

(define urdr.netpol.compiled-space
  [compiled _ _ _ _ _ _ _ S] -> S)

(define urdr.netpol.admitted-bytes
  Term [] -> []
  Term [P | Ps] ->
    [(if (= (urdr.netkat.eval Term P) []) 46 97)
     | (urdr.netpol.admitted-bytes Term Ps)])

(define urdr.netpol.chunk
  [] Acc -> (urdr.canonical.rev Acc)
  Bs Acc -> (urdr.netpol.chunk-take Bs 64 [] Acc))

(define urdr.netpol.chunk-take
  Bs 0 Cur Acc ->
    (urdr.netpol.chunk Bs [[text (urdr.canonical.rev Cur)] | Acc])
  [] N Cur Acc ->
    (urdr.canonical.rev [[text (urdr.canonical.rev Cur)] | Acc])
  [B | Bs] N Cur Acc ->
    (urdr.netpol.chunk-take Bs (- N 1) [B | Cur] Acc))

(define urdr.netpol.compiled-value
  Compiled ->
    [record
      [[(urdr.netpol.key k-admitted)
        [list (urdr.netpol.chunk
                (urdr.netpol.admitted-bytes
                  (urdr.netpol.compiled-term Compiled)
                  (urdr.netkat.space
                    (urdr.netpol.compiled-vocab Compiled)))
                [])]]
       [(urdr.netpol.key k-isolation)
        [text (urdr.netpol.compiled-isolation Compiled)]]
       [(urdr.netpol.key k-marker)
        [symbol (urdr.netpol.word w-marker)]]
       [(urdr.netpol.key k-space)
        (urdr.int.raw.from-small
          (urdr.netpol.compiled-space Compiled))]]])

(define urdr.netpol.compiled-render
  Compiled -> (urdr.netpol.render (urdr.netpol.compiled-term Compiled)))

\\ ---------------------------------------------------------------
\\ Checked entry point over canonical values
\\ ---------------------------------------------------------------

(define urdr.netpol.check-compile
  UniverseValue PoliciesValue ->
    (urdr.netpol.bind (urdr.netpol.universe UniverseValue)
      (/. Universe
        (urdr.netpol.bind (urdr.netpol.policies PoliciesValue Universe)
          (/. Policies (urdr.netpol.compile Universe Policies))))))
