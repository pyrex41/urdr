\* The logical timer model (plan Wave C, ADR 0004 Decision 1).

Requires shen/protocol/canonical.shen, shen/world/integer.shen,
shen/world/component.shen, and shen/world/models/common.shen to be loaded
by the caller.

A timer is a queue of named deadlines in logical time. Deadlines are ADR
0003 software integers; there is no host clock anywhere in this file. The
component never fires a deadline on its own: when logical time has
reached a deadline it publishes a `fire` alternative and stops. Firing is
a world-kernel choice, and the kernel then schedules the corresponding
component input.

State
-----

  [record [[deadlines [list ENTRY ...]]]]
  ENTRY [record [[due DEADLINE] [id [symbol TIMER-ID]]]]

The key is `due`, not `time`: `time` is one of the nine authorities
reserved to the world kernel, and a component that puts it in a
structural position of its own state is rejected. The current logical
time arrives on the event and is read only.

Entries are kept in ascending (due, id) order under software-integer
comparison, which is a different order from canonical encoding order for
integers of differing decimal width; the published alternatives are
sorted separately, by canonical encoding, because that is the order the
component-interface validator checks.

Inputs
------

  set    [record [[due DEADLINE] [id [symbol ID]] [kind [symbol set]]]]
  cancel [record [[id [symbol ID]] [kind [symbol cancel]]]]
  fire   [record [[id [symbol ID]] [kind [symbol fire]]]]
  poll   [record [[kind [symbol poll]]]]

Facts: armed, cancelled, fired.
Choices: purpose `timer-fire`, one alternative per due deadline. *\

\\ ---------------------------------------------------------------
\\ Names
\\ ---------------------------------------------------------------

(define urdr.model.timer.n.armed
  -> (urdr.canonical.string-bytes "armed"))

(define urdr.model.timer.n.cancel
  -> (urdr.canonical.string-bytes "cancel"))

(define urdr.model.timer.n.cancelled
  -> (urdr.canonical.string-bytes "cancelled"))

(define urdr.model.timer.n.deadlines
  -> (urdr.canonical.string-bytes "deadlines"))

(define urdr.model.timer.n.due
  -> (urdr.canonical.string-bytes "due"))

(define urdr.model.timer.n.fire
  -> (urdr.canonical.string-bytes "fire"))

(define urdr.model.timer.n.fired
  -> (urdr.canonical.string-bytes "fired"))

(define urdr.model.timer.n.id
  -> (urdr.canonical.string-bytes "id"))

(define urdr.model.timer.n.kind
  -> (urdr.canonical.string-bytes "kind"))

(define urdr.model.timer.n.poll
  -> (urdr.canonical.string-bytes "poll"))

(define urdr.model.timer.n.purpose
  -> (urdr.canonical.string-bytes "timer-fire"))

(define urdr.model.timer.n.set
  -> (urdr.canonical.string-bytes "set"))

\\ ---------------------------------------------------------------
\\ State
\\ ---------------------------------------------------------------

(define urdr.model.timer.entry-value
  [deadline Due Id] ->
    [record
      [[(urdr.model.timer.n.due) Due]
       [(urdr.model.timer.n.id) [symbol Id]]]])

(define urdr.model.timer.entries-value
  [] -> []
  [Entry | Rest] ->
    [(urdr.model.timer.entry-value Entry) |
     (urdr.model.timer.entries-value Rest)])

(define urdr.model.timer.state-value
  Deadlines ->
    [record
      [[(urdr.model.timer.n.deadlines)
        [list (urdr.model.timer.entries-value Deadlines)]]]])

(define urdr.model.timer.initial
  -> (urdr.model.timer.state-value []))

(define urdr.model.timer.entry-of
  Value ->
    (urdr.model.timer.entry-parts
      (urdr.model.common.integer
        (urdr.model.common.get Value (urdr.model.timer.n.due)))
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get Value (urdr.model.timer.n.id)))))

(define urdr.model.timer.entry-parts
  none Id -> none
  Due none -> none
  Due Id -> [deadline Due Id])

(define urdr.model.timer.entry-compare
  [deadline DueA IdA] [deadline DueB IdB] ->
    (let Order (urdr.int.raw.compare DueA DueB)
      (if (< Order 0)
          lt
          (if (> Order 0)
              gt
              (urdr.canonical.bytes-compare IdA IdB)))))

(define urdr.model.timer.decode-loop
  [] Previous Acc -> [ok (urdr.model.common.rev Acc)]
  [Value | Rest] Previous Acc ->
    (urdr.model.timer.decode-step
      (urdr.model.timer.entry-of Value) Rest Previous Acc)
  _ Previous Acc -> (urdr.model.common.error "timer-state-shape"))

(define urdr.model.timer.decode-step
  none Rest Previous Acc -> (urdr.model.common.error "timer-entry-shape")
  Entry Rest none Acc -> (urdr.model.timer.decode-loop Rest Entry [Entry | Acc])
  Entry Rest Previous Acc ->
    (if (= (urdr.model.timer.entry-compare Previous Entry) lt)
        (urdr.model.timer.decode-loop Rest Entry [Entry | Acc])
        (urdr.model.common.error "timer-state-order")))

(define urdr.model.timer.decode
  State ->
    (urdr.model.timer.decode-items
      (urdr.model.common.items
        (urdr.model.common.get State (urdr.model.timer.n.deadlines)))))

(define urdr.model.timer.decode-items
  none -> (urdr.model.common.error "timer-state-shape")
  Items -> (urdr.model.timer.decode-loop Items none []))

\\ ---------------------------------------------------------------
\\ Queue operations
\\ ---------------------------------------------------------------

(define urdr.model.timer.find
  Id [] -> none
  Id [[deadline Due EntryId] | Rest] ->
    (if (urdr.model.common.same? Id EntryId)
        [deadline Due EntryId]
        (urdr.model.timer.find Id Rest))
  Id _ -> none)

(define urdr.model.timer.insert
  Entry [] -> [Entry]
  Entry [Head | Rest] ->
    (if (= (urdr.model.timer.entry-compare Entry Head) lt)
        [Entry Head | Rest]
        [Head | (urdr.model.timer.insert Entry Rest)]))

(define urdr.model.timer.remove
  Id [] Acc -> (urdr.model.common.rev Acc)
  Id [[deadline Due EntryId] | Rest] Acc ->
    (if (urdr.model.common.same? Id EntryId)
        (urdr.model.common.append (urdr.model.common.rev Acc) Rest)
        (urdr.model.timer.remove Id Rest [[deadline Due EntryId] | Acc]))
  Id _ Acc -> (urdr.model.common.rev Acc))

\\ ---------------------------------------------------------------
\\ Choices: every deadline logical time has already reached.
\\ ---------------------------------------------------------------

(define urdr.model.timer.due-loop
  [] Now Acc -> Acc
  [[deadline Due Id] | Rest] Now Acc ->
    (if (<= (urdr.int.raw.compare Due Now) 0)
        (urdr.model.timer.due-loop
          Rest
          Now
          [(urdr.model.timer.entry-value [deadline Due Id]) | Acc])
        (urdr.model.timer.due-loop Rest Now Acc))
  _ Now Acc -> Acc)

(define urdr.model.timer.choices
  Deadlines Now ->
    (urdr.model.common.choice
      (urdr.model.timer.n.purpose)
      (urdr.model.timer.due-loop Deadlines Now [])))

(define urdr.model.timer.result
  Deadlines Facts Now ->
    [step
      (urdr.model.timer.state-value Deadlines)
      Facts
      (urdr.model.timer.choices Deadlines Now)])

\\ ---------------------------------------------------------------
\\ Operations
\\ ---------------------------------------------------------------

(define urdr.model.timer.set
  Deadlines Now Input ->
    (urdr.model.timer.set-entry
      (urdr.model.timer.entry-of Input) Deadlines Now))

(define urdr.model.timer.set-entry
  none Deadlines Now -> (urdr.model.common.error "timer-input-shape")
  [deadline Due Id] Deadlines Now ->
    (if (urdr.int.raw.negative? Due)
        (urdr.model.common.error "timer-deadline-range")
        (if (< (urdr.int.raw.compare Due Now) 0)
            (urdr.model.common.error "timer-deadline-stale")
            (if (= (urdr.model.timer.find Id Deadlines) none)
                (urdr.model.timer.result
                  (urdr.model.timer.insert [deadline Due Id] Deadlines)
                  [[fact (urdr.model.timer.n.armed)
                     (urdr.model.timer.entry-value [deadline Due Id])]]
                  Now)
                (urdr.model.common.error "timer-duplicate")))))

(define urdr.model.timer.cancel
  Deadlines Now Input ->
    (urdr.model.timer.cancel-id
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get Input (urdr.model.timer.n.id)))
      Deadlines
      Now))

(define urdr.model.timer.cancel-id
  none Deadlines Now -> (urdr.model.common.error "timer-input-shape")
  Id Deadlines Now ->
    (urdr.model.timer.cancel-found
      (urdr.model.timer.find Id Deadlines) Id Deadlines Now))

(define urdr.model.timer.cancel-found
  none Id Deadlines Now -> (urdr.model.common.error "timer-unknown")
  Entry Id Deadlines Now ->
    (urdr.model.timer.result
      (urdr.model.timer.remove Id Deadlines [])
      [[fact (urdr.model.timer.n.cancelled)
         (urdr.model.timer.entry-value Entry)]]
      Now))

(define urdr.model.timer.fire
  Deadlines Now Input ->
    (urdr.model.timer.fire-id
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get Input (urdr.model.timer.n.id)))
      Deadlines
      Now))

(define urdr.model.timer.fire-id
  none Deadlines Now -> (urdr.model.common.error "timer-input-shape")
  Id Deadlines Now ->
    (urdr.model.timer.fire-found
      (urdr.model.timer.find Id Deadlines) Id Deadlines Now))

\\ A deadline that logical time has not yet reached cannot fire. The world
\\ kernel offers the alternative only when it is due, and the component
\\ refuses it independently, so a mis-scheduled fire is a run error rather
\\ than a silent early timeout.
(define urdr.model.timer.fire-found
  none Id Deadlines Now -> (urdr.model.common.error "timer-unknown")
  [deadline Due EntryId] Id Deadlines Now ->
    (if (> (urdr.int.raw.compare Due Now) 0)
        (urdr.model.common.error "timer-not-due")
        (urdr.model.timer.result
          (urdr.model.timer.remove Id Deadlines [])
          [[fact (urdr.model.timer.n.fired)
             (urdr.model.timer.entry-value [deadline Due EntryId])]]
          Now)))

\\ ---------------------------------------------------------------
\\ The component-step entry point
\\ ---------------------------------------------------------------

(define urdr.model.timer.step
  State Event ->
    (urdr.model.timer.step-decoded
      (urdr.model.timer.decode State)
      (urdr.model.common.event-input Event)
      (urdr.model.common.event-now Event)))

(define urdr.model.timer.step-decoded
  [error E] Input Now -> [error E]
  [error E Detail] Input Now -> [error E Detail]
  [ok Deadlines] none Now -> (urdr.model.common.error "timer-input-shape")
  [ok Deadlines] Input none ->
    (urdr.model.common.error "timer-event-shape")
  [ok Deadlines] Input Now ->
    (urdr.model.timer.dispatch
      (urdr.model.common.symbol-bytes
        (urdr.model.common.get Input (urdr.model.timer.n.kind)))
      Deadlines
      Now
      Input))

(define urdr.model.timer.dispatch
  none Deadlines Now Input -> (urdr.model.common.error "timer-input-shape")
  Kind Deadlines Now Input ->
    (if (urdr.model.common.same? Kind (urdr.model.timer.n.set))
        (urdr.model.timer.set Deadlines Now Input)
        (if (urdr.model.common.same? Kind (urdr.model.timer.n.cancel))
            (urdr.model.timer.cancel Deadlines Now Input)
            (if (urdr.model.common.same? Kind (urdr.model.timer.n.fire))
                (urdr.model.timer.fire Deadlines Now Input)
                (if (urdr.model.common.same?
                      Kind (urdr.model.timer.n.poll))
                    (urdr.model.timer.result Deadlines [] Now)
                    (urdr.model.common.error "timer-unknown-input"))))))

\\ ---------------------------------------------------------------
\\ Input construction
\\ ---------------------------------------------------------------

(define urdr.model.timer.set-input
  Id Due ->
    [record
      [[(urdr.model.timer.n.due) Due]
       [(urdr.model.timer.n.id) [symbol Id]]
       [(urdr.model.timer.n.kind) [symbol (urdr.model.timer.n.set)]]]])

(define urdr.model.timer.cancel-input
  Id ->
    [record
      [[(urdr.model.timer.n.id) [symbol Id]]
       [(urdr.model.timer.n.kind)
        [symbol (urdr.model.timer.n.cancel)]]]])

(define urdr.model.timer.fire-input
  Id ->
    [record
      [[(urdr.model.timer.n.id) [symbol Id]]
       [(urdr.model.timer.n.kind) [symbol (urdr.model.timer.n.fire)]]]])

(define urdr.model.timer.poll-input
  -> [record
       [[(urdr.model.timer.n.kind)
         [symbol (urdr.model.timer.n.poll)]]]])
