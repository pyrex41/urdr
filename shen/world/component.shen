\\ Modeled-component transition interface (ADR 0004 Decision 1).
\\ Requires canonical.shen to be loaded by the caller; world.shen loads after.
\\
\\   component-step : component-state -> event -> [step State' Facts Choices]
\\
\\ Only urdr.world.reduce, through its dispatch table, invokes a component.
\\ A component never advances logical time, allocates event or choice
\\ identifiers, draws randomness out of band, or emits world events. Each of
\\ those authorities belongs to the world kernel alone and has a reserved
\\ name; a component that puts one in a structural position of its returned
\\ state, facts, or choices is rejected fail-closed. There is no silent
\\ repair and no partial acceptance: the whole step is rejected.
\\
\\ Operations return [ok], [ok VALUE], or [error CODE DETAIL], where CODE is
\\ a canonical symbol name and DETAIL is a canonical value.

\\ Cold-path helper: error codes are stable ASCII symbol names.
(define urdr.component.code
  Name -> (urdr.canonical.string-bytes Name))

\\ Authorities reserved to the world kernel: emitting world constructs
\\ (choice, command, event), allocating identifiers (choice-id, event-id),
\\ advancing logical time (time), randomness (coordinates, seed), and
\\ component identity (self, ADR 0007 D3): the reducer tells a component
\\ who it is, and a component that claims `self` in a structural position
\\ of its output would be asserting an identity only the kernel may bind.
\\ Written as literal octets because this is the scan hot path.
(define urdr.component.reserved
  -> [[99 104 111 105 99 101]
      [99 104 111 105 99 101 45 105 100]
      [99 111 109 109 97 110 100]
      [99 111 111 114 100 105 110 97 116 101 115]
      [101 118 101 110 116]
      [101 118 101 110 116 45 105 100]
      [115 101 101 100]
      [115 101 108 102]
      [116 105 109 101]])

(define urdr.component.member?
  _ [] -> false
  Name [Name | _] -> true
  Name [_ | Rest] -> (urdr.component.member? Name Rest))

(define urdr.component.reserved?
  Name -> (urdr.component.member? Name (urdr.component.reserved)))

(define urdr.component.canonical?
  Value -> (= (hd (urdr.canonical.encode-payload-with-profile
                    (urdr.canonical.profile.m1-large) Value))
              ok))

(define urdr.component.encoding
  Value -> (hd (tl (urdr.canonical.encode-payload-with-profile
                     (urdr.canonical.profile.m1-large) Value))))

\\ A component name, fact name, or choice purpose is a canonical symbol that
\\ does not usurp a reserved authority.
(define urdr.component.name-valid?
  Name ->
    (and (urdr.canonical.byte-list? Name)
         (and (urdr.canonical.symbol? Name)
              (not (urdr.component.reserved? Name)))))

\\ The first reserved authority a canonical value claims, or none. Record
\\ keys and symbol values are structural positions; bytes and text are data.
(define urdr.component.claim
  [record Fields] -> (urdr.component.claim-fields Fields)
  [list Values] -> (urdr.component.claim-values Values)
  [symbol Bs] -> (if (urdr.component.reserved? Bs) Bs none)
  _ -> none)

(define urdr.component.claim-values
  [] -> none
  [Value | Rest] ->
    (let Claim (urdr.component.claim Value)
      (if (= Claim none)
          (urdr.component.claim-values Rest)
          Claim))
  _ -> none)

(define urdr.component.claim-fields
  [] -> none
  [[Key Value] | Rest] ->
    (if (urdr.component.reserved? Key)
        Key
        (let Claim (urdr.component.claim Value)
          (if (= Claim none)
              (urdr.component.claim-fields Rest)
              Claim)))
  _ -> none)

(define urdr.component.check-value
  Value Invalid Authority ->
    (if (urdr.component.canonical? Value)
        (urdr.component.check-claim
          (urdr.component.claim Value) Authority)
        [error (urdr.component.code Invalid) [null]]))

(define urdr.component.check-claim
  none _ -> [ok]
  Claim Authority ->
    [error (urdr.component.code Authority) [symbol Claim]])

\\ A fact is [fact NAME VALUE]: the component asserts NAME with VALUE. The
\\ reducer, not the component, stamps identity and logical time onto the
\\ record it writes into world state.
(define urdr.component.check-fact
  [fact Name Value] ->
    (if (urdr.component.name-valid? Name)
        (urdr.component.check-value
          Value "component-fact-invalid" "component-fact-authority")
        [error (urdr.component.code "component-fact-name") [null]])
  _ -> [error (urdr.component.code "component-fact-shape") [null]])

(define urdr.component.check-facts
  [] -> [ok]
  [Fact | Rest] ->
    (urdr.component.check-facts-step
      (urdr.component.check-fact Fact) Rest)
  _ -> [error (urdr.component.code "component-facts-shape") [null]])

(define urdr.component.check-facts-step
  [ok] Rest -> (urdr.component.check-facts Rest)
  Error _ -> Error)

\\ A choice is [alternatives PURPOSE ALTERNATIVES]: the legal alternatives
\\ the component offers the search engine, nonempty and strictly ascending in
\\ canonical encoding order. The component never selects among them, and
\\ choices themselves ascend by purpose so no host iteration order can reach
\\ world semantics.
(define urdr.component.choice-purpose
  [alternatives Purpose _] -> Purpose)

(define urdr.component.after?
  none _ -> true
  Previous Current ->
    (= (urdr.canonical.bytes-compare Previous Current) lt))

(define urdr.component.check-choices
  Choices -> (urdr.component.check-choices-loop Choices none))

(define urdr.component.check-choices-loop
  [] _ -> [ok]
  [Choice | Rest] Previous ->
    (urdr.component.check-choices-step
      (urdr.component.check-choice Choice Previous) Choice Rest)
  _ _ -> [error (urdr.component.code "component-choices-shape") [null]])

(define urdr.component.check-choices-step
  [ok] Choice Rest ->
    (urdr.component.check-choices-loop
      Rest (urdr.component.choice-purpose Choice))
  Error _ _ -> Error)

(define urdr.component.check-choice
  [alternatives Purpose Alternatives] Previous ->
    (if (not (urdr.component.name-valid? Purpose))
        [error (urdr.component.code "component-choice-purpose") [null]]
        (if (urdr.component.after? Previous Purpose)
            (urdr.component.check-alternatives Alternatives none)
            [error (urdr.component.code "component-choice-order")
                   [symbol Purpose]]))
  _ _ -> [error (urdr.component.code "component-choice-shape") [null]])

(define urdr.component.check-alternatives
  [] none -> [error (urdr.component.code "component-choice-empty") [null]]
  [] _ -> [ok]
  [Alternative | Rest] Previous ->
    (urdr.component.check-alternatives-step
      (urdr.component.check-alternative Alternative Previous)
      Alternative
      Rest)
  _ _ ->
    [error (urdr.component.code "component-alternatives-shape") [null]])

(define urdr.component.check-alternatives-step
  [ok] Alternative Rest ->
    (urdr.component.check-alternatives Rest Alternative)
  Error _ _ -> Error)

(define urdr.component.check-alternative
  Alternative Previous ->
    (urdr.component.check-alternative-order
      (urdr.component.check-value
        Alternative
        "component-alternative-invalid"
        "component-alternative-authority")
      Alternative
      Previous))

\\ Strict ascension in canonical encoding order, shared by the component
\\ door (check-alternative-order below) and the world kernel's
\\ scheduled-choice door (urdr.world.schedule): the one comparison both
\\ enforce so no host iteration order can reach world semantics. Both
\\ values must already be known canonically encodable — the comparison
\\ reads their encodings. Strict ascension also rejects duplicates:
\\ equal values encode identically and compare eq, never lt.
(define urdr.component.encoding-ascending?
  Previous Current ->
    (= (urdr.canonical.bytes-compare
         (urdr.component.encoding Previous)
         (urdr.component.encoding Current))
       lt))

(define urdr.component.check-alternative-order
  [ok] _ none -> [ok]
  [ok] Alternative Previous ->
    (if (urdr.component.encoding-ascending? Previous Alternative)
        [ok]
        [error (urdr.component.code "component-alternative-order")
               [null]])
  Error _ _ -> Error)

\\ Result validation. A component may also return its own canonical error
\\ when it cannot interpret its input; the reducer converts either kind of
\\ error into a fail-closed run error.
(define urdr.component.check
  [step State Facts Choices] ->
    (urdr.component.check-step State Facts Choices)
  [error Code] -> (urdr.component.check-error Code [null])
  [error Code Detail] -> (urdr.component.check-error Code Detail)
  _ -> [error (urdr.component.code "component-result-shape") [null]])

(define urdr.component.check-error
  Code Detail ->
    (if (not (urdr.component.name-valid? Code))
        [error (urdr.component.code "component-error-code") [null]]
        (if (urdr.component.canonical? Detail)
            [error Code Detail]
            [error (urdr.component.code "component-error-detail") [null]])))

(define urdr.component.check-step
  State Facts Choices ->
    (urdr.component.check-step-state
      (urdr.component.check-value
        State "component-state-invalid" "component-state-authority")
      State
      Facts
      Choices))

(define urdr.component.check-step-state
  [ok] State Facts Choices ->
    (urdr.component.check-step-facts
      (urdr.component.check-facts Facts) State Facts Choices)
  Error _ _ _ -> Error)

(define urdr.component.check-step-facts
  [ok] State Facts Choices ->
    (urdr.component.check-step-choices
      (urdr.component.check-choices Choices) State Facts Choices)
  Error _ _ _ -> Error)

(define urdr.component.check-step-choices
  [ok] State Facts Choices -> [ok [step State Facts Choices]]
  Error _ _ _ -> Error)

(define urdr.component.raised
  -> [error (urdr.component.code "component-step-failed") [null]])

\\ The reducer's sole entry point into a component. A component that raises
\\ instead of returning a value becomes a fail-closed run error, never a
\\ crashed run and never a repaired one.
(define urdr.component.step
  Handler State Event ->
    (urdr.component.check
      (trap-error (Handler State Event)
                  (/. Raised (urdr.component.raised)))))

\\ A registry entry is [component NAME HANDLER STATE META]. NAME is a
\\ canonical symbol and entries ascend strictly by name. HANDLER is the
\\ component's transition function: code, not world state, and never
\\ encoded, compared, or hashed. STATE is a canonical value. META is a
\\ validated canonical record binding the component's declared identity
\\ (ADR 0007 D3): exactly the keys `model` and `node`, in that (ascending
\\ ASCII) order, each value either [null] or a canonical symbol that does
\\ not usurp a reserved authority. The reducer reads META to build the
\\ `self` key of every event it hands the component.
(define urdr.component.n.model
  -> [109 111 100 101 108])

(define urdr.component.n.node
  -> [110 111 100 101])

(define urdr.component.meta-value
  none -> [null]
  Bs -> [symbol Bs])

(define urdr.component.meta
  Model Node ->
    [record
      [[(urdr.component.n.model) (urdr.component.meta-value Model)]
       [(urdr.component.n.node) (urdr.component.meta-value Node)]]])

(define urdr.component.meta-empty
  -> (urdr.component.meta none none))

\\ Convenience constructor for entries with no declared identity: test
\\ fixtures and single-component harnesses stay terse, while the stored
\\ entry shape stays uniform at five elements.
(define urdr.component.entry
  Name Handler State ->
    [component Name Handler State (urdr.component.meta-empty)])

\\ Accessors over a META record already proved valid at registration.
(define urdr.component.meta-model-value
  [record [[_ Model] [_ _]]] -> Model
  _ -> [null])

(define urdr.component.meta-node-value
  [record [[_ _] [_ Node]]] -> Node
  _ -> [null])

(define urdr.component.meta-field-ok?
  [null] -> true
  [symbol Bs] -> (urdr.component.name-valid? Bs)
  _ -> false)

\\ Fail-closed META validation at registration: wrong record shape and a
\\ bad field value carry distinct stable codes so a malformed entry names
\\ what it got wrong.
(define urdr.component.meta-check
  [record [[ModelKey Model] [NodeKey Node]]] ->
    (if (and (= ModelKey (urdr.component.n.model))
             (= NodeKey (urdr.component.n.node)))
        (if (and (urdr.component.meta-field-ok? Model)
                 (urdr.component.meta-field-ok? Node))
            [ok]
            [error (urdr.component.code "component-meta-value") [null]])
        [error (urdr.component.code "component-meta-shape") [null]])
  _ -> [error (urdr.component.code "component-meta-shape") [null]])

(define urdr.component.shape-loop
  [] _ -> true
  [[component Name _ _ _] | Rest] Previous ->
    (and (urdr.component.name-valid? Name)
         (and (urdr.component.after? Previous Name)
              (urdr.component.shape-loop Rest Name)))
  _ _ -> false)

\\ Cheap per-reduction invariant: names and order only. Component states are
\\ validated on construction and again on every transition, so re-encoding
\\ them on each reduction would prove nothing new.
(define urdr.component.registry-shape?
  Registry -> (urdr.component.shape-loop Registry none))

(define urdr.component.registry-step
  [ok] Meta Rest Name ->
    (urdr.component.registry-meta
      (urdr.component.meta-check Meta) Rest Name)
  Error _ _ _ -> Error)

(define urdr.component.registry-meta
  [ok] Rest Name -> (urdr.component.registry-loop Rest Name)
  Error _ _ -> Error)

(define urdr.component.registry-loop
  [] _ -> [ok]
  [[component Name _ State Meta] | Rest] Previous ->
    (if (not (urdr.component.name-valid? Name))
        [error (urdr.component.code "component-registry-name") [null]]
        (if (urdr.component.after? Previous Name)
            (urdr.component.registry-step
              (urdr.component.check-value
                State
                "component-state-invalid"
                "component-state-authority")
              Meta
              Rest
              Name)
            [error (urdr.component.code "component-registry-order")
                   [symbol Name]]))
  _ _ -> [error (urdr.component.code "component-registry-shape") [null]])

\\ Full construction-time validation, including component states and META.
(define urdr.component.registry-valid?
  Registry -> (urdr.component.registry-loop Registry none))
