\* Shared helpers for the M1 abstract models (plan Wave C).

Requires shen/protocol/canonical.shen, shen/world/integer.shen,
shen/world/netkat.shen, and shen/world/component.shen to be loaded by the
caller.

Every model in shen/world/models/ is a pure `component-step` function of
ADR 0004 Decision 1:

  handler : component-state -> event -> [step State' Facts Choices]

with `[error CODE]` or `[error CODE DETAIL]` as the only other result.
Components here never draw randomness, never allocate identifiers, never
advance logical time, and never select among the alternatives they
publish. The reserved-authority scan of shen/world/component.shen rejects
any state, fact, or choice whose record keys or symbol values name
choice, choice-id, command, coordinates, event, event-id, seed, or time,
so no model below uses those names for anything. Logical time arrives as
the event's read-only `time` key and is never written back.

Alternatives inside one choice must be strictly ascending in canonical
encoding order, so every model builds them through
urdr.model.common.sort, which sorts by the same encoding the validator
compares and drops exact duplicates. *\

\\ ---------------------------------------------------------------
\\ Names and stable error codes
\\ ---------------------------------------------------------------

(define urdr.model.common.code
  Name -> (urdr.canonical.string-bytes Name))

(define urdr.model.common.error
  Name -> [error (urdr.model.common.code Name)])

(define urdr.model.common.error-with
  Name Detail -> [error (urdr.model.common.code Name) Detail])

\\ A NetKAT rejection keeps its own stable code so a model never restates
\\ or softens the algebra's verdict. The four pinned ports were probed for
\\ (str SYMBOL) agreement before this was written; all four render an
\\ error atom byte-identically.
(define urdr.model.common.netkat-error
  [error E] -> [error (urdr.canonical.string-bytes (str E))])

\\ ---------------------------------------------------------------
\\ Canonical-value accessors
\\ ---------------------------------------------------------------

(define urdr.model.common.entries-get
  [] Key -> none
  [[K V] | Es] Key ->
    (if (= (urdr.canonical.bytes-compare K Key) eq)
        V
        (urdr.model.common.entries-get Es Key))
  _ Key -> none)

(define urdr.model.common.get
  [record Es] Key -> (urdr.model.common.entries-get Es Key)
  _ Key -> none)

(define urdr.model.common.symbol-bytes
  [symbol Bs] -> Bs
  _ -> none)

(define urdr.model.common.items
  [list Items] -> Items
  _ -> none)

(define urdr.model.common.integer
  [big Sign Magnitude] ->
    (if (urdr.int.valid? [big Sign Magnitude])
        [big Sign Magnitude]
        none)
  _ -> none)

\\ ---------------------------------------------------------------
\\ Canonical-encoding order
\\ ---------------------------------------------------------------

(define urdr.model.common.encoding-of
  [ok Bytes] -> Bytes
  _ -> [])

(define urdr.model.common.encoding
  Value ->
    (urdr.model.common.encoding-of
      (urdr.canonical.encode-payload Value)))

(define urdr.model.common.compare
  A B ->
    (urdr.canonical.bytes-compare
      (urdr.model.common.encoding A) (urdr.model.common.encoding B)))

(define urdr.model.common.insert
  V [] -> [V]
  V [W | Ws] ->
    (let Order (urdr.model.common.compare V W)
      (if (= Order lt)
          [V W | Ws]
          (if (= Order eq)
              [W | Ws]
              [W | (urdr.model.common.insert V Ws)]))))

(define urdr.model.common.sort
  [] -> []
  [V | Vs] -> (urdr.model.common.insert V (urdr.model.common.sort Vs)))

\\ A choice with no alternatives is invalid, so a model publishes a
\\ purpose only when it has something to offer.
(define urdr.model.common.choice
  Purpose [] -> []
  Purpose Alternatives ->
    [[alternatives Purpose (urdr.model.common.sort Alternatives)]])

\\ ---------------------------------------------------------------
\\ Octet-list helpers
\\ ---------------------------------------------------------------

(define urdr.model.common.same?
  A B -> (= (urdr.canonical.bytes-compare A B) eq))

(define urdr.model.common.member?
  Bs [] -> false
  Bs [X | Xs] ->
    (if (urdr.model.common.same? Bs X)
        true
        (urdr.model.common.member? Bs Xs))
  Bs _ -> false)

(define urdr.model.common.append
  [] Ys -> Ys
  [X | Xs] Ys -> [X | (urdr.model.common.append Xs Ys)])

(define urdr.model.common.rev
  Xs -> (urdr.canonical.rev Xs))

(define urdr.model.common.symbols
  [] -> []
  [Bs | Rest] -> [[symbol Bs] | (urdr.model.common.symbols Rest)])

(define urdr.model.common.symbol-list
  [] Acc -> [ok (urdr.model.common.rev Acc)]
  [[symbol Bs] | Rest] Acc ->
    (urdr.model.common.symbol-list Rest [Bs | Acc])
  _ Acc -> none)

\\ ---------------------------------------------------------------
\\ Small software integers used as list indices
\\ ---------------------------------------------------------------

(define urdr.model.common.big
  N -> (hd (tl (urdr.int.from-small N))))

(define urdr.model.common.nth
  [] N -> none
  [X | Xs] N -> (if (= N 0) X (urdr.model.common.nth Xs (- N 1)))
  _ N -> none)

(define urdr.model.common.without
  [] N Acc -> (urdr.model.common.rev Acc)
  [X | Xs] N Acc ->
    (if (= N 0)
        (urdr.model.common.append (urdr.model.common.rev Acc) Xs)
        (urdr.model.common.without Xs (- N 1) [X | Acc]))
  _ N Acc -> (urdr.model.common.rev Acc))

(define urdr.model.common.count
  [] N -> N
  [_ | Xs] N -> (urdr.model.common.count Xs (+ N 1))
  _ N -> N)

\\ An index carried in a canonical value is a software integer; it becomes
\\ a host counter only after it is proved to sit inside the list it
\\ indexes, which bounds it by the model's own state.
(define urdr.model.common.index
  Value Bound ->
    (urdr.model.common.index-value
      (urdr.model.common.integer Value) Bound 0))

(define urdr.model.common.index-value
  none Bound N -> none
  Value Bound N ->
    (if (= N Bound)
        none
        (if (= (urdr.int.raw.compare Value (urdr.model.common.big N)) 0)
            N
            (urdr.model.common.index-value Value Bound (+ N 1)))))

\\ ---------------------------------------------------------------
\\ Event accessors. The component reads logical time; it never writes it.
\\ ---------------------------------------------------------------

(define urdr.model.common.n.input
  -> (urdr.canonical.string-bytes "input"))

(define urdr.model.common.n.time
  -> (urdr.canonical.string-bytes "time"))

(define urdr.model.common.event-input
  Event -> (urdr.model.common.get Event (urdr.model.common.n.input)))

(define urdr.model.common.event-now
  Event ->
    (urdr.model.common.integer
      (urdr.model.common.get Event (urdr.model.common.n.time))))
