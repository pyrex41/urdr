\* The counterexample witness bridge (plan Wave C, ADR 0004 Decision 2,
required verification 4).

Requires shen/protocol/canonical.shen, shen/world/integer.shen,
shen/world/prng.shen, shen/world/netkat.shen, shen/world/component.shen,
shen/world/world.shen, shen/world/models/common.shen, and
shen/world/models/net.shen to be loaded by the caller.

A symbolic check over the NetKAT fragment produces a canonical verdict
record: urdr.netkat.reachability-value or urdr.netkat.equivalence-value.
When the verdict is a violation it carries a witness — a header
assignment, not a run. This module compiles that assignment into a
concrete schedule prefix against the network model and then *replays* it.

The contract, stated as ADR 0004 states it:

  A symbolic counterexample is a set of header assignments; a compiler
  lowers it to a concrete scenario schedule whose replay must exhibit the
  violation, or the check result is reported as `unconfirmed` — never
  silently accepted.

So there are exactly two outcomes and no third:

  [confirmed INPUTS FACTS]  the compiled schedule replayed and the fact
                            log contains the violation the witness
                            claimed.
  [unconfirmed REASON]      everything else, each with a stable reason:

  witness-shape                  the value is not a NetKAT verdict record
  witness-verdict-nonviolating   `equivalent` or `unreachable`: there is
                                 no violation to reproduce, and reporting
                                 one would be a fabrication
  witness-packet-invalid         the witness header assignment is not a
                                 packet of the network's vocabulary
  witness-link-unknown           no declared link carries the witness's
                                 (src, dst) pair, so no schedule exists
  witness-registry-invalid       the network state is not a valid
                                 component state
  witness-schedule-failed        replay of the compiled schedule produced
                                 a fail-closed run error
  witness-not-exhibited          replay succeeded but the claimed
                                 violation did not appear

`witness-not-exhibited` is the load-bearing case: a symbolic result that
the concrete model does not reproduce is reported, never converted into a
pass and never dropped. *\

(define urdr.netkat.witness.n.name
  -> (urdr.canonical.string-bytes "name"))

(define urdr.netkat.witness.n.reason
  -> (urdr.canonical.string-bytes "reason"))

(define urdr.netkat.witness.n.value
  -> (urdr.canonical.string-bytes "value"))

(define urdr.netkat.witness.n.verdict
  -> (urdr.canonical.string-bytes "verdict"))

(define urdr.netkat.witness.n.confirmed
  -> (urdr.canonical.string-bytes "confirmed"))

(define urdr.netkat.witness.n.unconfirmed
  -> (urdr.canonical.string-bytes "unconfirmed"))

(define urdr.netkat.witness.n.exhibited
  -> (urdr.canonical.string-bytes "witness-exhibited"))

\\ ---------------------------------------------------------------
\\ Reading the verdict record
\\ ---------------------------------------------------------------

(define urdr.netkat.witness.verdict-of
  Value ->
    (urdr.model.common.symbol-bytes
      (urdr.model.common.get Value (urdr.netkat.key verdict))))

(define urdr.netkat.witness.claim
  none -> none
  Verdict ->
    (if (urdr.model.common.same?
          Verdict (urdr.netkat.word reachable))
        reachable
        (if (urdr.model.common.same?
              Verdict (urdr.netkat.word differs))
            differs
            (if (urdr.model.common.same?
                  Verdict (urdr.netkat.word unreachable))
                unreachable
                (if (urdr.model.common.same?
                      Verdict (urdr.netkat.word equivalent))
                    equivalent
                    none)))))

\\ The packet the schedule must inject, and the packet the fact log must
\\ then show as delivered. A `differs` witness has no single expected
\\ output: the violation is that two policies disagree, which is confirmed
\\ by comparing two replays rather than by matching one packet.
(define urdr.netkat.witness.subject
  reachable Value ->
    [ok (urdr.model.common.get Value (urdr.netkat.key ingress-packet))
        (urdr.model.common.get Value (urdr.netkat.key egress-packet))]
  differs Value ->
    [ok (urdr.model.common.get Value (urdr.netkat.key witness-packet))
        none]
  unreachable Value -> [error witness-verdict-nonviolating]
  equivalent Value -> [error witness-verdict-nonviolating]
  none Value -> [error witness-shape])

\\ ---------------------------------------------------------------
\\ Compilation
\\ ---------------------------------------------------------------

(define urdr.netkat.witness.link-for
  Src Dst [] -> none
  Src Dst [[link From To LinkSrc LinkDst] | Rest] ->
    (if (and (= (urdr.int.raw.compare Src LinkSrc) 0)
             (= (urdr.int.raw.compare Dst LinkDst) 0))
        [via From To]
        (urdr.netkat.witness.link-for Src Dst Rest))
  Src Dst _ -> none)

(define urdr.netkat.witness.schedule
  Name Packet [via From To] ->
    [[schedule (urdr.int.zero) component
       [component-input Name
         (urdr.model.net.send-input Packet From To)]]
     [advance-to-next-event]
     [schedule (urdr.int.zero) component
       [component-input Name
         (urdr.model.net.deliver-input
           (urdr.model.net.n.deliver) 0 From To)]]
     [advance-to-next-event]])

(define urdr.netkat.witness.compile
  Name State Witness ->
    (urdr.netkat.witness.compile-subject
      (urdr.netkat.witness.subject
        (urdr.netkat.witness.claim
          (urdr.netkat.witness.verdict-of Witness))
        Witness)
      Name
      State))

(define urdr.netkat.witness.compile-subject
  [error E] Name State -> [error E]
  [ok none Expected] Name State -> [error witness-shape]
  [ok Ingress Expected] Name State ->
    (urdr.netkat.witness.compile-vocab
      (urdr.model.net.vocabulary-of State)
      Ingress
      Expected
      Name
      State))

(define urdr.netkat.witness.compile-vocab
  [error E] Ingress Expected Name State ->
    [error witness-registry-invalid]
  [error E Detail] Ingress Expected Name State ->
    [error witness-registry-invalid]
  [ok Vocab] Ingress Expected Name State ->
    (urdr.netkat.witness.compile-packet
      (urdr.netkat.packet Vocab Ingress) Expected Name State))

(define urdr.netkat.witness.compile-packet
  [error E] Expected Name State -> [error witness-packet-invalid]
  [ok Packet] Expected Name State ->
    (urdr.netkat.witness.compile-links
      (urdr.model.net.links-list State) Packet Expected Name))

(define urdr.netkat.witness.compile-links
  [error E] Packet Expected Name -> [error witness-registry-invalid]
  [error E Detail] Packet Expected Name -> [error witness-registry-invalid]
  [ok Links] Packet Expected Name ->
    (urdr.netkat.witness.compile-via
      (urdr.netkat.witness.link-for
        (urdr.netkat.packet-get Packet (urdr.model.net.n.src))
        (urdr.netkat.packet-get Packet (urdr.model.net.n.dst))
        Links)
      Packet
      Expected
      Name))

(define urdr.netkat.witness.compile-via
  none Packet Expected Name -> [error witness-link-unknown]
  Via Packet Expected Name ->
    [ok [witness-schedule
          (urdr.netkat.witness.schedule Name Packet Via)
          Packet
          Expected]])

\\ ---------------------------------------------------------------
\\ Replay
\\ ---------------------------------------------------------------

(define urdr.netkat.witness.world
  Seed Name State ->
    (urdr.world.initial-with-components
      Seed
      [(urdr.component.entry
         Name (/. S E (urdr.model.net.step S E)) State)]))

(define urdr.netkat.witness.run
  Seed Name State Inputs ->
    (urdr.netkat.witness.run-world
      (urdr.netkat.witness.world Seed Name State) Inputs))

(define urdr.netkat.witness.run-world
  [error _ _] Inputs -> [error witness-registry-invalid]
  [error _] Inputs -> [error witness-registry-invalid]
  [ok World] Inputs ->
    (urdr.netkat.witness.run-replay (urdr.world.replay World Inputs)))

(define urdr.netkat.witness.run-replay
  [replay World _] -> [ok (urdr.world.facts World)]
  _ -> [error witness-schedule-failed])

\\ ---------------------------------------------------------------
\\ Reading the fact log
\\ ---------------------------------------------------------------

(define urdr.netkat.witness.fact-name
  Fact ->
    (urdr.model.common.symbol-bytes
      (urdr.model.common.get Fact (urdr.netkat.witness.n.name))))

(define urdr.netkat.witness.fact-value
  Fact ->
    (urdr.model.common.get Fact (urdr.netkat.witness.n.value)))

(define urdr.netkat.witness.delivered
  [] Acc -> (urdr.model.common.rev Acc)
  [Fact | Rest] Acc ->
    (if (urdr.model.common.same?
          (urdr.netkat.witness.fact-name Fact)
          (urdr.model.net.n.delivered))
        (urdr.netkat.witness.delivered
          Rest
          [(urdr.model.common.get
             (urdr.netkat.witness.fact-value Fact)
             (urdr.model.net.n.packet)) | Acc])
        (urdr.netkat.witness.delivered Rest Acc))
  _ Acc -> (urdr.model.common.rev Acc))

(define urdr.netkat.witness.exhibits?
  Expected [] -> false
  Expected [Packet | Rest] ->
    (if (= (urdr.model.common.compare Expected Packet) eq)
        true
        (urdr.netkat.witness.exhibits? Expected Rest))
  Expected _ -> false)

\\ ---------------------------------------------------------------
\\ confirm: a reachability violation
\\ ---------------------------------------------------------------

(define urdr.netkat.witness.confirm
  Seed Name State Witness ->
    (urdr.netkat.witness.confirm-compiled
      (urdr.netkat.witness.compile Name State Witness)
      Seed
      Name
      State))

(define urdr.netkat.witness.confirm-compiled
  [error E] Seed Name State -> [unconfirmed E]
  [ok [witness-schedule Inputs Packet none]] Seed Name State ->
    [unconfirmed witness-shape]
  [ok [witness-schedule Inputs Packet Expected]] Seed Name State ->
    (urdr.netkat.witness.confirm-run
      (urdr.netkat.witness.run Seed Name State Inputs)
      Inputs
      Expected))

(define urdr.netkat.witness.confirm-run
  [error E] Inputs Expected -> [unconfirmed E]
  [ok Facts] Inputs Expected ->
    (if (urdr.netkat.witness.exhibits?
          Expected (urdr.netkat.witness.delivered Facts []))
        [confirmed Inputs Facts]
        [unconfirmed witness-not-exhibited]))

\\ ---------------------------------------------------------------
\\ confirm-difference: a policy-equivalence violation
\\
\\ The witness packet is injected into two otherwise identical networks
\\ whose baseline policies are the two terms under comparison. The
\\ violation is exhibited when the two fact logs deliver different packet
\\ sets; if they agree, the symbolic `differs` verdict is not reproduced
\\ concretely and the result is unconfirmed.
\\ ---------------------------------------------------------------

(define urdr.netkat.witness.confirm-difference
  Seed Name Left Right Witness ->
    (urdr.netkat.witness.difference-compiled
      (urdr.netkat.witness.compile Name Left Witness)
      Seed
      Name
      Left
      Right))

(define urdr.netkat.witness.difference-compiled
  [error E] Seed Name Left Right -> [unconfirmed E]
  [ok [witness-schedule Inputs Packet Expected]] Seed Name Left Right ->
    (urdr.netkat.witness.difference-left
      (urdr.netkat.witness.run Seed Name Left Inputs)
      Seed
      Name
      Right
      Inputs))

(define urdr.netkat.witness.difference-left
  [error E] Seed Name Right Inputs -> [unconfirmed E]
  [ok LeftFacts] Seed Name Right Inputs ->
    (urdr.netkat.witness.difference-right
      (urdr.netkat.witness.run Seed Name Right Inputs)
      LeftFacts
      Inputs))

(define urdr.netkat.witness.difference-right
  [error E] LeftFacts Inputs -> [unconfirmed E]
  [ok RightFacts] LeftFacts Inputs ->
    (if (= (urdr.netkat.witness.delivered LeftFacts [])
           (urdr.netkat.witness.delivered RightFacts []))
        [unconfirmed witness-not-exhibited]
        [confirmed Inputs RightFacts]))

\\ ---------------------------------------------------------------
\\ Canonical result value
\\ ---------------------------------------------------------------

(define urdr.netkat.witness.reason
  [confirmed _ _] -> (urdr.netkat.witness.n.exhibited)
  [unconfirmed Reason] -> (urdr.canonical.string-bytes (str Reason)))

(define urdr.netkat.witness.verdict
  [confirmed _ _] -> (urdr.netkat.witness.n.confirmed)
  [unconfirmed _] -> (urdr.netkat.witness.n.unconfirmed))

(define urdr.netkat.witness.value
  Result ->
    [record
      [[(urdr.netkat.witness.n.reason)
        [symbol (urdr.netkat.witness.reason Result)]]
       [(urdr.netkat.witness.n.verdict)
        [symbol (urdr.netkat.witness.verdict Result)]]]])
