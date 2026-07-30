\* The explicit choice record (SPEC.md 17, M1 plan Wave F).

Requires shen/protocol/canonical.shen, shen/world/integer.shen,
shen/world/prng.shen, shen/world/component.shen, shen/world/world.shen,
and shen/world/eventlog.shen to be loaded by the caller.

Pure: no I/O, no host time, no host randomness, no floating point, no
defprolog. A choice record is a total function of its declared inputs.
Every operation returns [ok ...] or [error CODE DETAIL] and performs no
work before validating.

NOT owned here (docs/module-boundaries.md): ambient randomness. This
module never draws. It records the coordinates of a draw somebody else
made, and refuses to record a shape that could not have come from one.

=====================================================================
1. What SPEC.md 17 requires
=====================================================================

  A choice contains:
    - Stable choice ID
    - Logical time
    - Choice kind
    - Canonically ordered alternatives
    - Selected alternative
    - Selection reason and PRNG coordinates

Each of the six is a field below, plus one that SPEC.md 17 leaves
implicit and ADR 0003 makes explicit: the ACTOR the choice belongs to.
The actor is already half of the stream path (subsystem, actor-id,
purpose), so leaving it out of the record would make the record a
strictly weaker artifact than the coordinates it carries.

The internal form is

  [schoice ID TIME ACTOR KIND ALTERNATIVES SELECTED REASON COORDINATES]

and the canonical rendering is

  [record [[actor        [bytes ACTOR]]
           [alternatives [list ALTERNATIVE ...]]
           [choice-id    [bytes DIGEST]]
           [coordinates  [list COORDINATE ...]]
           [kind         [symbol KIND]]
           [reason       [symbol REASON]]
           [selected     ALTERNATIVE]
           [time         INTEGER]]]

The eight keys ascend in unsigned-ASCII order, so a choice record is
itself a canonical value and can be digested, rooted, and pinned.

`choice-id`, `coordinates`, and `time` are three of the eight authorities
reserved to modelled components (component.shen). That is deliberate and
is the point: a choice record is world-kernel-side authority, produced by
the search engine and never by a component, so it is exactly the place
those names belong. Nothing in this module is ever handed to a component.

COORDINATE is urdr.world.coordinate-value's rendering, reused verbatim so
the shape a transcript carries for a PRNG draw has one spelling in the
repository.

=====================================================================
2. The stable choice ID
=====================================================================

The ID must be stable -- the same choice reached the same way in two
runs of the same seed must carry the same ID -- and it must separate two
choices that differ in anything that matters. It is therefore derived,
never allocated:

  preimage = "URDR-CHOICE-ID" 0x00 0x01
             ++ field(1, decimal octets of the sequence number)
             ++ field(2, actor)
             ++ field(3, kind)
             ++ field(4, decimal octets of the logical time)
             ++ field(5, root over the alternative digests)

  choice-id = SHA-256(preimage)

field(TAG, PAYLOAD) is urdr.prng.field.raw: a one-octet tag, an
unsigned-varint length, then the payload, so no two distinct tuples share
a preimage. The alternatives enter through a tagged root over their
individual digests (eventlog.shen section 4) rather than through one
encoding, so an alternative set too large for a single canonical frame
still has a bounded, total identity.

The sequence number is the choice's 0-based position in the exploration
that produced it. Without it two textually identical choice points --
the same component offering the same alternatives at the same logical
time twice -- would collide, and a transcript could not name which one it
meant. With it, the ID is a function of (where in the search, what was
offered), which is what "stable" has to mean for a search that is itself
a deterministic function of its seed.

The ID deliberately does NOT commit to the selected alternative or to the
PRNG coordinates. A choice point has an identity independent of what was
chosen there, which is what lets a shrinker say "the same choice, decided
differently".

=====================================================================
3. Validation
=====================================================================

Strict, fail-closed, and performed before any field is read out:

  - ID is exactly 32 octets.
  - TIME is a valid non-negative software integer.
  - ACTOR is a canonical symbol name (octets).
  - KIND is a canonical symbol name (octets).
  - ALTERNATIVES is non-empty, every element is canonical under the ADR
    0005 m1-large profile, and the list ascends STRICTLY in canonical
    encoding order. That is the same order and the same comparison
    urdr.component.check-alternatives applies to what a component
    publishes, so a choice record cannot claim an ordering the component
    interface would have rejected. The m1-large bound is the component
    interface's, not the digest's: the choice id digests each
    alternative through urdr.eventlog.value-digest, which encodes under
    the m0 profile, so an alternative that is legal for a component but
    too large for an m0 frame makes `make` fail with the event log's own
    code. That is a clean refusal rather than a silent narrowing, and it
    is where an M2 raise of the digest profile would be noticed.
  - SELECTED is canonically equal to one of the alternatives.
  - REASON is one of exactly three names (section 4).
  - COORDINATES is non-empty; every element is a
    [coordinate urdr-sha256-counter-v1 ...] whose seed, subsystem,
    actor, purpose, and counter agree with every other element, and
    whose block indices are exactly 0, 1, 2, ... in order.

The last check is the one that makes the record evidence rather than
decoration. ADR 0003 bounded sampling rejects a block that falls in the
biased tail and retries with the NEXT BLOCK INDEX at the SAME COUNTER, so
a genuine draw is always a run of block indices from zero at one counter.
A coordinate list of any other shape did not come from
urdr.prng.sample and is refused.

=====================================================================
4. Selection reasons
=====================================================================

  forced    the choice offered exactly one alternative. Recorded, and
            still drawn for, because a search whose stream advances only
            on branching choices is a search whose stream position
            depends on the shape of the world -- and then adding an
            alternative to one component silently reseeds every later
            choice everywhere. ADR 0003's "adding a draw to one stream
            must not perturb another" is only worth having if a draw
            happens where the model says it happens.
  uniform   selected by bias-free bounded sampling over the alternative
            count.
  weighted  selected by bias-free bounded sampling over a weight sum.

The set is closed. A strategy that wants to explain itself differently
adds a name here, in the open, rather than writing prose into a record.

=====================================================================
5. Public entry points
=====================================================================

  make          SEQ TIME ACTOR KIND ALTERNATIVES SELECTED REASON
                COORDINATES -> [ok CHOICE] | [error CODE DETAIL]
  check         CHOICE -> [ok] | [error CODE DETAIL]
  id / time / actor / kind / alternatives / selected / reason /
  coordinates   CHOICE -> the field
  draw          CHOICE -> the accepted coordinate (the last)
  rejections    CHOICE -> the rejected coordinates (all but the last)
  counter       CHOICE -> the stream counter the draw was made at
  path          CHOICE -> [path SUBSYSTEM ACTOR PURPOSE COUNTER]
  value         CHOICE -> canonical record (section 1)
  values        [CHOICE ...] -> [canonical record ...]
  digest        CHOICE -> [ok OCTETS] | [error CODE DETAIL]
  root          [CHOICE ...] -> [ok OCTETS] | [error CODE DETAIL]
  reason-uniform / reason-weighted / reason-forced -> REASON octets
  error-value   CODE DETAIL -> canonical record
  code-octets   CODE -> OCTETS *\

\\ ---------------------------------------------------------------
\\ ASCII names (k- keys, w- words, t- domain tags, c- error codes).
\\ ---------------------------------------------------------------

(define urdr.search.choice.n
  k-actor -> (urdr.canonical.string-bytes "actor")
  k-alternatives -> (urdr.canonical.string-bytes "alternatives")
  k-choice-id -> (urdr.canonical.string-bytes "choice-id")
  k-code -> (urdr.canonical.string-bytes "code")
  k-coordinates -> (urdr.canonical.string-bytes "coordinates")
  k-detail -> (urdr.canonical.string-bytes "detail")
  k-kind -> (urdr.canonical.string-bytes "kind")
  k-reason -> (urdr.canonical.string-bytes "reason")
  k-selected -> (urdr.canonical.string-bytes "selected")
  k-time -> (urdr.canonical.string-bytes "time")
  w-forced -> (urdr.canonical.string-bytes "forced")
  w-uniform -> (urdr.canonical.string-bytes "uniform")
  w-weighted -> (urdr.canonical.string-bytes "weighted")
  t-alternatives ->
    (urdr.canonical.string-bytes "urdr-choice-alternatives-v1")
  t-choices -> (urdr.canonical.string-bytes "urdr-choice-root-v1")
  c-shape -> (urdr.canonical.string-bytes "search-choice-shape")
  c-id -> (urdr.canonical.string-bytes "search-choice-id")
  c-time -> (urdr.canonical.string-bytes "search-choice-time")
  c-actor -> (urdr.canonical.string-bytes "search-choice-actor")
  c-kind -> (urdr.canonical.string-bytes "search-choice-kind")
  c-alternatives ->
    (urdr.canonical.string-bytes "search-choice-alternatives")
  c-alternative-order ->
    (urdr.canonical.string-bytes "search-choice-alternative-order")
  c-selected -> (urdr.canonical.string-bytes "search-choice-selected")
  c-reason -> (urdr.canonical.string-bytes "search-choice-reason")
  c-coordinates ->
    (urdr.canonical.string-bytes "search-choice-coordinates")
  c-unmapped -> (urdr.canonical.string-bytes "search-unmapped-code"))

\\ The domain prefix of the choice-id preimage: "URDR-CHOICE-ID" then the
\\ two version octets, exactly as urdr.prng.coordinate.raw frames its own
\\ preimage.
(define urdr.search.choice.prefix
  -> [85 82 68 82 45 67 72 79 73 67 69 45 73 68 0 1])

\\ Stable Shen-symbol codes and their canonical octet names. Anything
\\ without a clause renders as search-unmapped-code rather than as an
\\ unstable host rendering of a symbol.
(define urdr.search.choice.code-octets
  search-choice-shape -> (urdr.search.choice.n c-shape)
  search-choice-id -> (urdr.search.choice.n c-id)
  search-choice-time -> (urdr.search.choice.n c-time)
  search-choice-actor -> (urdr.search.choice.n c-actor)
  search-choice-kind -> (urdr.search.choice.n c-kind)
  search-choice-alternatives -> (urdr.search.choice.n c-alternatives)
  search-choice-alternative-order ->
    (urdr.search.choice.n c-alternative-order)
  search-choice-selected -> (urdr.search.choice.n c-selected)
  search-choice-reason -> (urdr.search.choice.n c-reason)
  search-choice-coordinates -> (urdr.search.choice.n c-coordinates)
  _ -> (urdr.search.choice.n c-unmapped))

(define urdr.search.choice.error-value
  Code Detail ->
    [record
      [[(urdr.search.choice.n k-code)
        [symbol (urdr.search.choice.code-octets Code)]]
       [(urdr.search.choice.n k-detail) Detail]]])

\\ ---------------------------------------------------------------
\\ Reason names
\\ ---------------------------------------------------------------

(define urdr.search.choice.reason-forced
  -> (urdr.search.choice.n w-forced))

(define urdr.search.choice.reason-uniform
  -> (urdr.search.choice.n w-uniform))

(define urdr.search.choice.reason-weighted
  -> (urdr.search.choice.n w-weighted))

(define urdr.search.choice.reason?
  Reason ->
    (or (= Reason (urdr.search.choice.n w-forced))
        (or (= Reason (urdr.search.choice.n w-uniform))
            (= Reason (urdr.search.choice.n w-weighted)))))

\\ ---------------------------------------------------------------
\\ Small helpers
\\ ---------------------------------------------------------------

(define urdr.search.choice.big
  N -> (urdr.int.raw.from-small N))

(define urdr.search.choice.octet-count
  [] Acc -> Acc
  [_ | Rest] Acc -> (urdr.search.choice.octet-count Rest (+ Acc 1))
  _ Acc -> Acc)

(define urdr.search.choice.encoding
  Value ->
    (urdr.search.choice.encoding-of
      (urdr.canonical.encode-payload-with-profile
        (urdr.canonical.profile.m1-large) Value)))

(define urdr.search.choice.encoding-of
  [ok Bytes] -> [some Bytes]
  _ -> none)

\\ Canonical equality: two values are the same value exactly when their
\\ canonical encodings agree. An unencodable value equals nothing, not
\\ even itself.
(define urdr.search.choice.same?
  A B ->
    (urdr.search.choice.same-encodings?
      (urdr.search.choice.encoding A)
      (urdr.search.choice.encoding B)))

(define urdr.search.choice.same-encodings?
  [some A] [some B] -> (= A B)
  _ _ -> false)

\\ urdr.canonical.symbol? is a predicate over OCTETS and is not total on
\\ arbitrary values: it compares its elements arithmetically. The octet
\\ scan therefore comes first, exactly as urdr.component.name-valid?
\\ orders the same two checks, so a non-octet name is a rejection rather
\\ than a host type error.
(define urdr.search.choice.symbol-name?
  Name ->
    (if (urdr.canonical.byte-list? Name)
        (urdr.canonical.symbol? Name)
        false))

(define urdr.search.choice.member?
  _ [] -> false
  Value [Alternative | Rest] ->
    (if (urdr.search.choice.same? Value Alternative)
        true
        (urdr.search.choice.member? Value Rest))
  _ _ -> false)

\\ ---------------------------------------------------------------
\\ Alternatives: non-empty, canonical, strictly ascending
\\ ---------------------------------------------------------------

(define urdr.search.choice.check-alternatives
  [] -> [error search-choice-alternatives [null]]
  Alternatives ->
    (urdr.search.choice.alternatives-loop Alternatives none))

(define urdr.search.choice.alternatives-loop
  [] _ -> [ok]
  [Alternative | Rest] Previous ->
    (urdr.search.choice.alternatives-step
      (urdr.search.choice.encoding Alternative) Rest Previous)
  _ _ -> [error search-choice-alternatives [null]])

(define urdr.search.choice.alternatives-step
  none _ _ -> [error search-choice-alternatives [null]]
  [some Encoding] Rest none ->
    (urdr.search.choice.alternatives-loop Rest [some Encoding])
  [some Encoding] Rest [some Previous] ->
    (if (= (urdr.canonical.bytes-compare Previous Encoding) lt)
        (urdr.search.choice.alternatives-loop Rest [some Encoding])
        [error search-choice-alternative-order [null]]))

\\ ---------------------------------------------------------------
\\ Coordinates: one counter, block indices 0, 1, 2, ...
\\ ---------------------------------------------------------------

(define urdr.search.choice.check-coordinates
  [] -> [error search-choice-coordinates [null]]
  [Coordinate | Rest] ->
    (urdr.search.choice.coordinates-first Coordinate Rest)
  _ -> [error search-choice-coordinates [null]])

(define urdr.search.choice.coordinates-first
  [coordinate urdr-sha256-counter-v1 Seed Sub Actor Purpose Counter
    Block] Rest ->
    (if (urdr.int.raw.zero? Block)
        (urdr.search.choice.coordinates-loop
          Rest Seed Sub Actor Purpose Counter (urdr.int.one))
        [error search-choice-coordinates [null]])
  _ _ -> [error search-choice-coordinates [null]])

(define urdr.search.choice.coordinates-loop
  [] _ _ _ _ _ _ -> [ok]
  [[coordinate urdr-sha256-counter-v1 Seed Sub Actor Purpose Counter
     Block] | Rest]
  Seed Sub Actor Purpose Counter Expected ->
    (if (= (urdr.int.raw.compare Block Expected) 0)
        (urdr.search.choice.coordinates-loop
          Rest Seed Sub Actor Purpose Counter
          (urdr.int.raw.add Expected (urdr.int.one)))
        [error search-choice-coordinates [null]])
  _ _ _ _ _ _ _ -> [error search-choice-coordinates [null]])

\\ ---------------------------------------------------------------
\\ The stable choice ID (section 2)
\\ ---------------------------------------------------------------

(define urdr.search.choice.alternatives-root
  Alternatives ->
    (urdr.search.choice.alternatives-root-of
      (urdr.eventlog.value-digests Alternatives [])))

(define urdr.search.choice.alternatives-root-of
  [error Code Detail] -> [error Code Detail]
  [ok Digests] ->
    (urdr.eventlog.root-of
      (urdr.search.choice.n t-alternatives) Digests))

(define urdr.search.choice.id-of
  Seq Time Actor Kind Alternatives ->
    (urdr.search.choice.id-with-root
      (urdr.search.choice.alternatives-root Alternatives)
      Seq Time Actor Kind))

(define urdr.search.choice.id-with-root
  [error Code Detail] _ _ _ _ -> [error Code Detail]
  [ok Root] Seq Time Actor Kind ->
    [ok
      (urdr.prng.sha256.raw
        (append (urdr.search.choice.prefix)
          (append
            (urdr.prng.field.raw
              1 (urdr.int.raw.to-decimal-octets
                  (urdr.search.choice.big Seq)))
            (append (urdr.prng.field.raw 2 Actor)
              (append (urdr.prng.field.raw 3 Kind)
                (append
                  (urdr.prng.field.raw
                    4 (urdr.int.raw.to-decimal-octets Time))
                  (urdr.prng.field.raw 5 Root)))))))])

\\ ---------------------------------------------------------------
\\ Construction
\\ ---------------------------------------------------------------

(define urdr.search.choice.make
  Seq Time Actor Kind Alternatives Selected Reason Coordinates ->
    (urdr.search.choice.make-checked
      (urdr.search.choice.check-parts
        Time Actor Kind Alternatives Selected Reason Coordinates)
      Seq Time Actor Kind Alternatives Selected Reason Coordinates))

(define urdr.search.choice.make-checked
  [error Code Detail] _ _ _ _ _ _ _ _ -> [error Code Detail]
  [ok] Seq Time Actor Kind Alternatives Selected Reason Coordinates ->
    (urdr.search.choice.make-id
      (urdr.search.choice.id-of Seq Time Actor Kind Alternatives)
      Time Actor Kind Alternatives Selected Reason Coordinates))

(define urdr.search.choice.make-id
  [error Code Detail] _ _ _ _ _ _ _ -> [error Code Detail]
  [ok Id] Time Actor Kind Alternatives Selected Reason Coordinates ->
    [ok [schoice Id Time Actor Kind Alternatives Selected Reason
          Coordinates]])

\\ Everything except the derived ID, so that `make` and `check` agree by
\\ construction rather than by two lists of rules kept in step by hand.
(define urdr.search.choice.check-parts
  Time Actor Kind Alternatives Selected Reason Coordinates ->
    (if (not (urdr.int.valid? Time))
        [error search-choice-time [null]]
        (if (urdr.int.raw.negative? Time)
            [error search-choice-time [null]]
            (if (not (urdr.search.choice.symbol-name? Actor))
                [error search-choice-actor [null]]
                (if (not (urdr.search.choice.symbol-name? Kind))
                    [error search-choice-kind [null]]
                    (urdr.search.choice.check-rest
                      (urdr.search.choice.check-alternatives
                        Alternatives)
                      Alternatives Selected Reason Coordinates))))))

(define urdr.search.choice.check-rest
  [error Code Detail] _ _ _ _ -> [error Code Detail]
  [ok] Alternatives Selected Reason Coordinates ->
    (if (not (urdr.search.choice.member? Selected Alternatives))
        [error search-choice-selected [null]]
        (if (not (urdr.search.choice.reason? Reason))
            [error search-choice-reason [null]]
            (urdr.search.choice.check-coordinates Coordinates))))

\\ Full validation of an assembled record, including the derived ID. A
\\ record whose ID is not the ID its own fields imply is refused: an ID
\\ that could be asserted would not be an identity.
(define urdr.search.choice.check
  [schoice Id Time Actor Kind Alternatives Selected Reason
    Coordinates] ->
    (if (= (urdr.search.choice.octet-count Id 0) 32)
        (urdr.search.choice.check-parts
          Time Actor Kind Alternatives Selected Reason Coordinates)
        [error search-choice-id [null]])
  _ -> [error search-choice-shape [null]])

\\ ---------------------------------------------------------------
\\ Accessors
\\ ---------------------------------------------------------------

(define urdr.search.choice.id
  [schoice Id _ _ _ _ _ _ _] -> Id)

(define urdr.search.choice.time
  [schoice _ Time _ _ _ _ _ _] -> Time)

(define urdr.search.choice.actor
  [schoice _ _ Actor _ _ _ _ _] -> Actor)

(define urdr.search.choice.kind
  [schoice _ _ _ Kind _ _ _ _] -> Kind)

(define urdr.search.choice.alternatives
  [schoice _ _ _ _ Alternatives _ _ _] -> Alternatives)

(define urdr.search.choice.selected
  [schoice _ _ _ _ _ Selected _ _] -> Selected)

(define urdr.search.choice.reason
  [schoice _ _ _ _ _ _ Reason _] -> Reason)

(define urdr.search.choice.coordinates
  [schoice _ _ _ _ _ _ _ Coordinates] -> Coordinates)

\\ The accepted draw is the last coordinate; every earlier one is a
\\ rejection recorded so that the biased tail a bounded sample discarded
\\ is visible instead of invisible.
(define urdr.search.choice.last
  [Coordinate] -> Coordinate
  [_ | Rest] -> (urdr.search.choice.last Rest))

(define urdr.search.choice.draw
  Choice ->
    (urdr.search.choice.last (urdr.search.choice.coordinates Choice)))

(define urdr.search.choice.drop-last
  [_] -> []
  [Coordinate | Rest] -> [Coordinate | (urdr.search.choice.drop-last Rest)]
  _ -> [])

(define urdr.search.choice.rejections
  Choice ->
    (urdr.search.choice.drop-last
      (urdr.search.choice.coordinates Choice)))

(define urdr.search.choice.counter
  Choice ->
    (urdr.search.choice.coordinate-counter
      (urdr.search.choice.draw Choice)))

(define urdr.search.choice.coordinate-counter
  [coordinate _ _ _ _ _ Counter _] -> Counter)

(define urdr.search.choice.path
  Choice ->
    (urdr.search.choice.coordinate-path
      (urdr.search.choice.draw Choice)))

(define urdr.search.choice.coordinate-path
  [coordinate _ _ Sub Actor Purpose Counter _] ->
    [path Sub Actor Purpose Counter])

\\ ---------------------------------------------------------------
\\ Canonical rendering
\\ ---------------------------------------------------------------

(define urdr.search.choice.value
  [schoice Id Time Actor Kind Alternatives Selected Reason
    Coordinates] ->
    [record
      [[(urdr.search.choice.n k-actor) [bytes Actor]]
       [(urdr.search.choice.n k-alternatives) [list Alternatives]]
       [(urdr.search.choice.n k-choice-id) [bytes Id]]
       [(urdr.search.choice.n k-coordinates)
        [list (urdr.world.coordinates-value Coordinates)]]
       [(urdr.search.choice.n k-kind) [symbol Kind]]
       [(urdr.search.choice.n k-reason) [symbol Reason]]
       [(urdr.search.choice.n k-selected) Selected]
       [(urdr.search.choice.n k-time) Time]]])

(define urdr.search.choice.values
  [] -> []
  [Choice | Rest] ->
    [(urdr.search.choice.value Choice) |
     (urdr.search.choice.values Rest)])

(define urdr.search.choice.digest
  Choice ->
    (urdr.eventlog.value-digest (urdr.search.choice.value Choice)))

\\ The identity of a whole decision sequence: the tagged root over the
\\ per-choice digests, in order. Two explorations agree exactly when this
\\ agrees.
(define urdr.search.choice.root
  Choices ->
    (urdr.search.choice.root-of
      (urdr.eventlog.value-digests
        (urdr.search.choice.values Choices) [])))

(define urdr.search.choice.root-of
  [error Code Detail] -> [error Code Detail]
  [ok Digests] ->
    (urdr.eventlog.root-of (urdr.search.choice.n t-choices) Digests))
