# ADR 0006: Host number rendering is not portable

Status: Accepted for M1

Date: 2026-07-29

Supersedes: None

Superseded by: None

Relates to: `docs/adr/0003-portable-integers-and-named-prng.md`, `SPEC.md`
§7.1 and §16, and architectural invariants 1 and 7

## Context

ADR 0003 established that Urdr's own numbers are base-10,000 software
integers, because Shen leaves native numeric precision
implementation-dependent. That decision was made about *arithmetic*. This ADR
records a second, independent finding about *rendering*, established by
measurement on 2026-07-29 across all four required ports at their pinned
commits.

The four ports do not agree on how a host number is printed, and the
disagreement is not a formatting preference that could be settled by picking
a convention. It follows from each port's numeric tower.

### Measured behaviour

Magnitude. Two ports carry arbitrary-precision integers and two do not:

| expression | shen-cl | shen-rust | shen-go | shen-lua |
| --- | --- | --- | --- | --- |
| `1e19` | `10000000000000000000` | same | same | same |
| 2^70 | `1180591620717411303424` | `1180591620717411300000` | `1180591620717411300000` | `1180591620717411300000` |

shen-cl is exact because it holds a bignum. The other three hold an IEEE-754
double and render the shortest round-tripping decimal, zero-padded. **This is
a value difference, not a rendering difference**, and no rendering rule can
close it.

Type tags. Two ports carry a distinct integer type and suffix `.0` on the
float one; two have a single double type and cannot:

| expression | shen-cl | shen-rust | shen-go | shen-lua |
| --- | --- | --- | --- | --- |
| `(/ 1e300 1e290)` | `10000000000` | `10000000000.0` | `10000000000` | `10000000000` |
| `(* 1.0 5)` | `5` | `5.0` | `5` | `5` |
| `(* 2.5 2)` | `5.0` | `5.0` | `5` | `5` |

shen-cl and shen-rust disagree **with each other** here, for different
reasons: shen-cl's reader turns `1.0` and `1e300` into exact integers and CL
doubles always carry `.0`, while shen-rust promotes `Int` to `Float` only on
`i64` overflow. Reproducing either rule on shen-go or shen-lua would require
giving those ports an int/float distinction, which would print `42` as
`42.0`.

Literal reading. The kernel's `reader.shen` computes `10^N` by repeated
floating multiplication, which is exact only to 10^22. shen-go was fixed on
2026-07-29 (`e3517b0`) to answer base-10 integer powers exactly; **shen-rust
and shen-lua still carry the defect** and read `1e300` as
`1.0000000000000002e300`. shen-cl is unaffected because it reads into
bignums. So the same source literal denotes different values on different
ports.

Non-finite values. `+inf`/`-inf` render as `inf`/`-inf` on shen-go,
shen-lua, and shen-rust; shen-cl signals `FLOATING-POINT-OVERFLOW` and never
produces the value. NaN was aligned to lowercase `nan` on 2026-07-29
(shen-rust `0f5408a`). Whether overflow should signal or produce an infinity
is **not** decided here: an exhaustive search of Tarver's canonical S41.2 for
`NaN|infinity|floating-point-overflow|overflow` returns zero hits, and the
kernel's own `integer?` (`KLambda/sys.kl:179`) fails to terminate on an
infinity, which is evidence the specification never contemplated non-finite
values at all. That question stays open rather than being settled by fiat.

## Decision

1. **Host number rendering is not a portable observable.** No Urdr verdict,
   certificate, golden digest, or fixture may contain a host-rendered number.
   This is already true by construction — ADR 0003 requires software integers
   spelled as octet lists — and this ADR makes the reason explicit so the
   invariant is not weakened by someone who observes that "the ports agree on
   small integers."

2. **Small-integer agreement is coincidence, not a constraint.** The four
   ports do agree for values below 2^53 with no fractional part. Nothing in
   the Shen kernel requires that, and the divergences above show the
   agreement ending at magnitudes and types that are easy to reach by
   accident. Treat it exactly as ADR 0004 Decision 3 treats Prolog agreement.

3. **Cross-port fixes remain worthwhile, up to the tower boundary.** Where a
   port disagrees for a reason that is *not* its numeric tower — a saturating
   printer, an inconsistent threshold, an inexact reader — that is a defect
   and should be fixed against the majority, or against Tarver's reference
   primitives when the ports split evenly. Four fixes landed on 2026-07-29
   under this rule. Where the disagreement *is* the tower, record it here and
   stop.

4. **Full four-port byte-identity on numeric rendering is not a goal.** It is
   unreachable without changing the ports' numeric towers, which is out of
   scope for Urdr and would be a breaking change to each port.

## Consequences

- Urdr's float-freedom is load-bearing, not stylistic. The M1 four-port gate
  stayed green through every rendering change above precisely because no
  reviewed case emits a host number; every value is a base-10,000 limb below
  10,000 and renders as plain digits everywhere.
- A future case that prints a host number would be a portability regression
  even if it passed the gate on the day it was written.
- Two defects are recorded as open, both real and neither urgent:
  shen-rust's `format_float` switches from `{x:.1}` to `{x}` at a `1e16`
  threshold, so integral floats one ulp of magnitude apart render
  inconsistently; and shen-rust and shen-lua still carry the inexact
  `10^N` reader.
- The overflow-policy question (signal versus infinity) is open. Reopening it
  requires either a specification source that does not currently exist or an
  explicit Urdr-local decision recorded in a new ADR.
