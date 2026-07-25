# ADR 0001: SIMD and CPU feature policy

Status: Accepted for v0  
Relates to: SPEC.md §4.2 (determinism profiles), §7.1 (portability contract),
§8.1 (compute-bound guests), §9.1 (reference VM constraints), §9.3
(exact-executor compatibility), §15 (snapshots), §20.2 (divergence diagnosis),
§21 (certificate), §25 criterion 12 (cross-host replay)

## 1. Context

SIMD is frequently cited as part of the residual gap in practical
deterministic hypervisors. This ADR fixes Urdr's position: which SIMD-related
effects are real hazards at each determinism profile, which are already
neutralized by existing SPEC requirements, and what concrete policy the
executor, guest image, and certificate must implement.

The analysis separates four commonly conflated categories.

### 1.1 Feature-surface divergence (real, enforceable)

Guests and their libraries probe CPUID/XGETBV and dispatch different code
paths per host: glibc selects `memcpy`/`strlen` variants via IFUNC at load
time, the Go runtime gates AVX use in `internal/cpu`, OpenSSL and language
runtimes do the same. Two hosts with different visible features execute
different instruction sequences from identical binaries.

The key fact the usual framing misses is that CPUID masking is not merely
advisory for the features that matter. AVX, AVX2, and AVX-512 state is
enable-gated through XCR0/XSETBV, which KVM validates against the
guest-visible CPUID. A guest whose CPUID and XCR0 exclude AVX-512 takes #UD
on AVX-512 instructions even when the host supports them. Enforcement tiers,
from strongest to weakest:

1. **Enable-gated** — AVX/AVX2/AVX-512 and other XSAVE-managed state:
   masking CPUID leaf 0xD causes actual faults, not just changed dispatch.
2. **Trapped** — RDRAND/RDSEED (VMX exiting controls), RDTSC/RDPMC
   (already required by §9.1).
3. **Advertised only** — feature bits that change dispatch but whose
   instructions still execute if issued blindly (e.g. BMI, SSE4.2 above the
   x86-64 baseline). Masking is sufficient for well-behaved code; hostile or
   buggy code that issues unadvertised-but-executable instructions is a
   divergence source the entropy firewall cannot see. Accepted residual at
   D1; detectable only by replay verification or D3 escalation.
4. **Uncontrollable** — SSE2 is architecturally baseline on x86-64 and
   cannot be removed.

### 1.2 Value-level nondeterminism (real but narrow)

Integer and bitwise SIMD — the bulk of real-world vector code, e.g. byte
scanning, comparisons, and masking of the kind popularized in Mitchell
Hashimoto's "Everyone Should Know SIMD" (mitchellh.com, 2026) — is fully
value-deterministic: vector width changes which instructions execute, never
what they compute, and width is frozen by the pinned binary plus the locked
CPU profile. IEEE-754 basic operations — add, sub, mul, div, sqrt, FMA —
are likewise bit-deterministic on compliant hardware, scalar and SIMD
alike. The same binary executing the same instruction sequence on the same
inputs produces the same bits. The actual hazard list is short:

- **Approximation instructions.** x86 `RCPPS`/`RSQRTPS` and their VEX/EVEX
  successors are specified only by an error bound (≤ 1.5·2⁻¹²); exact
  results differ between vendors and between microarchitectural generations.
  AArch64 is cleaner: `FRECPE`/`FRSQRTE` results are exactly specified by
  architecture pseudocode.
- **Deliberately relaxed operations at the runtime level**, e.g.
  WebAssembly relaxed-SIMD, where cross-platform result divergence is
  permitted by design. Relevant only when guest workloads embed such
  runtimes.
- **FP environment state** — MXCSR FTZ/DAZ, rounding mode, FPCR on ARM.
  This is per-thread state, captured by XSAVE and therefore by snapshots;
  it is deterministic whenever execution is, and is a hazard only for
  snapshot/restore bugs, not for replay divergence per se.

Compile-time effects (FMA contraction, x87 vs SSE codegen) are properties of
the binary, not the run, and are frozen by content-addressed artifacts.

### 1.3 Timing and microarchitectural effects (mostly out of scope at D1)

Instruction latency, AVX-induced frequency transitions, and pipeline
behavior differ across CPU generations. Under Urdr's discrete-event model
these cannot leak into observable state: virtual time advances only by
world-kernel transition (§8), never by host progress. This category becomes
real only if a future executor derives preemption fuel from retired
instruction/branch counters (§8.1) — and even there the hazard is
performance-counter event determinism generally, not SIMD specifically; a
fixed binary retires a fixed instruction sequence regardless of how wide its
vectors are.

### 1.4 Build-time variance (already solved)

Compilers and runtimes emit different SIMD code depending on build host and
flags. Urdr does not need to disable auto-vectorization to neutralize this:
the run ID already binds an immutable content-addressed artifact manifest
(§4), and dispatch within those pinned binaries is a deterministic function
of the normalized CPUID. Disabling vectorization in guest workloads such as
k3s would buy nothing at D1 and is rejected. The world kernel needs no SIMD
policy at all — §7.1 already bans floating point outright, which is
strictly stronger than "prefer scalar." OpenResty/Shen-Lua policy code must
keep decisions in the integer domain (LuaJIT numbers are IEEE doubles), as
the UAP's integer-only core already forces at the protocol boundary.

## 2. Decision

1. **Locked, named CPU profiles.** Each scenario binds one profile; the
   profile ID is part of the determinism profile hashed into the run ID and
   recorded in the certificate alongside the actual host CPU model.
   - `urdr-x86-v2`: x86-64-v2-equivalent (SSE4.2/POPCNT, no AVX).
   - `urdr-x86-v3`: x86-64-v3-equivalent (AVX2/FMA/BMI2), the widest
     default profile.
   - `urdr-arm-neoverse`: fixed AArch64 profile with NEON; SVE masked in v0.
   Implementation on Firecracker uses its CPU-template mechanism (static
   templates such as T2S/T2CL, or custom CPUID+MSR templates), noting
   Firecracker's own caveat that templates mask advertisement but do not
   change instruction behavior — hence the enforcement tiers above.

2. **AVX-512 is never advertised or enable-gated in v0**, on any profile,
   for three independent reasons: (a) it fractures the host compatibility
   class for snapshots and cross-host replay; (b) QEMU TCG implements AVX
   and AVX2 but not AVX-512, so advertising it would sever the D3
   escalation path (§9.3, §20.2) — the exact executor must be able to run
   any binary the fast executor certified; (c) its state expands the XSAVE
   area, and XSAVE layout stability across hosts is what makes Firecracker
   snapshots portable at all. The TCG ceiling, not host inventory, caps the
   profile.

3. **Snapshot portability defines host compatibility.** A "compatible host"
   (SPEC §25, criterion 12) is one whose CPU supports a superset of the
   locked profile *and* belongs to the same instruction-behavior class for
   approximation instructions (in practice: same vendor family until
   measured otherwise). The certificate records both; replay verification
   across hosts is the empirical arbiter.

4. **Approximation-instruction audit.** Guest images and workload artifacts
   are statically scanned for the implementation-defined family (`RCPPS`,
   `RSQRTPS`, VEX/EVEX variants) and x87 code. Findings do not fail the run;
   they are recorded in the certificate as a named residual-nondeterminism
   domain (§21) that narrows the compatibility class to identical-behavior
   hosts. TCG cannot serve as a bit-exact oracle for these instructions
   (its softfloat estimates will not match hardware), so D3 escalation of a
   divergence inside this domain is reported as such rather than pursued.

5. **Guest kernel obligations** (extends §10.1): boot with the locked
   profile's XCR0, never enable masked XSAVE components, and mask SVE/SME
   on ARM via ID-register virtualization. Kernel-internal SIMD (crypto,
   RAID) is permitted — it is deterministic under a fixed profile.

6. **Blind-issue divergence is an accepted, named residual at D1** (tier 3
   in §1.1 above): code that executes instructions present on the host but
   absent from the advertised profile. It is listed in the certificate's
   residual domains, hunted by replay verification on heterogeneous hosts,
   and fully closed only at D3.

## 3. Consequences

- SIMD imposes no new mechanism on the world kernel; the entire policy
  lives in the executor (templates, XCR0, traps), the guest kernel, the
  artifact pipeline (scanner), and the certificate schema.
- Guests keep near-native SIMD performance under `urdr-x86-v3`; nothing in
  the D1 guarantee requires scalarizing workloads.
- Choosing the TCG-compatible ceiling now means the M6 divergence-escalation
  milestone needs no profile renegotiation later.
- Hosts with AVX-512 run guests that cannot see it; that performance is
  deliberately left on the table in exchange for a stable compatibility
  class.
- If a future workload genuinely requires AVX-512, it forces either a new
  profile with its own narrowed host class and no TCG oracle, or waiting on
  TCG support — an explicit ADR-level decision, not a flag.
