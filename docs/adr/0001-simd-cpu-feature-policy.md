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

CPUID masking is not merely advisory for XSAVE-managed features, but neither
is one masked leaf sufficient. AVX-family enforcement requires consistent
feature bits in leaves 1 and 7, component bits in leaf `0xD`, and an XCR0 that
excludes the masked state. KVM must reject an inconsistent XSETBV. A guest
whose effective CPUID and XCR0 exclude AVX-512 then takes #UD on AVX-512
instructions even when the host supports them. Enforcement tiers, from
strongest to weakest:

1. **Enable-gated** — AVX/AVX2/AVX-512 and other XSAVE-managed state:
   consistent CPUID/XCR0 masking causes actual faults, not just changed
   dispatch.
2. **Hidden or executor-controlled** — stock KVM does not expose
   Firecracker userspace exits for RDRAND, RDSEED, RDTSC, or RDPMC. A profile
   must hide an instruction with verified architectural enforcement, prohibit
   it in admitted code, or use an executor/KVM path that can deterministically
   emulate it. Advertising one without such control is incompatible with D1.
3. **Advertised only** — feature bits that change dispatch but whose
   instructions still execute if issued blindly (e.g. BMI, SSE4.2 above the
   x86-64 baseline). Masking is sufficient for well-behaved code; hostile or
   buggy code that issues unadvertised-but-executable instructions is a
   divergence source the entropy firewall cannot see. Unless admission or
   runtime enforcement proves this path unavailable, the run is
   `UNCERTIFIED`, not D1. Replay sampling alone is not proof of control.
4. **Uncontrollable** — SSE2 is architecturally baseline on x86-64 and
   cannot be removed.

### 1.2 Value-level nondeterminism (real but narrow)

Integer and bitwise SIMD — the bulk of real-world vector code, e.g. byte
scanning, comparisons, and masking of the kind popularized in Mitchell
Hashimoto's "Everyone Should Know SIMD" (mitchellh.com, 2026) — is
value-deterministic for a fixed instruction and operands. Vector width changes
which instructions execute, not their integer result, and width is frozen by
the pinned binary plus the locked CPU profile. Ordinary finite IEEE-754
add, sub, mul, div, sqrt, and FMA are similarly deterministic only when the
ISA instruction, binary format, operands, and FP control state are fixed.
NaN propagation, subnormals, signed zero, conversions, min/max operations,
and cross-ISA comparison require explicit architectural rules and tests. The
remaining hazard list includes:

- **Approximation instructions.** x86 scalar and packed reciprocal-estimate
  families (`RCPSS`/`RCPPS`, `RSQRTSS`/`RSQRTPS`, and VEX/EVEX 14/28-bit
  families) have family-specific accuracy contracts; exact results can differ
  between vendors and microarchitectural generations. AArch64 estimate
  instructions have architecture pseudocode, but still require profile tests.
- **Deliberately relaxed operations at the runtime level**, e.g.
  WebAssembly relaxed-SIMD, where cross-platform result divergence is
  permitted by design. Relevant only when guest workloads embed such
  runtimes.
- **FP environment state** — MXCSR FTZ/DAZ, rounding mode, FPCR on ARM,
  default-NaN modes, and context-switch behavior. This per-thread state must
  be normalized at admission and verified across snapshot/restore.

Compile-time effects (FMA contraction, x87 vs SSE codegen) are properties of
the binary, not the run, and are frozen by content-addressed artifacts.

### 1.3 Timing and microarchitectural effects (mostly out of scope at D1)

Instruction latency, AVX-induced frequency transitions, and pipeline behavior
differ across CPU generations. Urdr's discrete-event model is required to
prevent these from advancing virtual time or ordering simulator events. PMU
access, architecture counters, host-timed completion, or any other path that
lets host progress affect a declared observation remains uncontrolled and
therefore blocks D1. A future fuel mechanism based on retired instructions or
branches needs its own deterministic capability contract.

### 1.4 Build-time variance (bounded by artifacts)

Compilers and runtimes emit different SIMD code depending on build host and
flags. The run ID binds an immutable content-addressed artifact manifest
(§4), so compile-time variance is frozen for a run. Runtime dispatch is
deterministic only after the effective CPU profile is verified and blind issue
is controlled. Disabling auto-vectorization is not a blanket v0 requirement.
The world kernel performs no floating-point policy calculation — §7.1 bans
floating point — but it does own the canonical profile identity, capability
validation, achieved-profile decision, and certificate semantics. OpenResty/
Shen-Lua policy code must keep decisions in the integer domain, as the UAP's
integer-only core requires.

## 2. Decision

1. **Locked, versioned CPU profile manifests.** Each scenario binds a
   canonical profile manifest. Its digest, not a mutable friendly name, is
   hashed into the run ID and recorded in every snapshot and certificate.
   A manifest fixes required and forbidden CPUID leaves, MSRs, XCR0 and PMU
   state on x86; ID registers and KVM vCPU features on ARM; trap/emulation
   requirements; topology; and required active probes. Provisional profile
   families are:
   - `urdr-x86-v2`: x86-64-v2-equivalent (SSE4.2/POPCNT, no AVX).
   - `urdr-x86-v3`: x86-64-v3-equivalent (AVX2/FMA/BMI2), the widest
     default profile.
   - `urdr-arm-neoverse`: a family name that is not certifiable until an
     exact model/version manifest is committed; NEON is fixed and SVE/SME
     are absent in v0.
   Firecracker implementations use vendor/model-specific custom templates
   and tested host allowlists. T2S/T2CL are not aliases for generic
   x86-64-v2/v3. The executor reports requested, applied, and actively probed
   state through UAP; Shen validates it before granting a profile.

2. **AVX-512 is never advertised or enable-gated in v0**, on any profile,
   for three independent reasons: (a) it fractures the host compatibility
   class for snapshots and cross-host replay; (b) QEMU TCG implements AVX
   and AVX2 but not AVX-512, so advertising it would sever the D3
   escalation path (§9.3, §20.2) — the exact executor must be able to run
   any binary the fast executor certified; (c) its state expands the XSAVE
   area and complicates snapshot compatibility. The pinned TCG capability
   matrix, not current host inventory, caps the profile. Instruction coverage
   does not by itself make TCG a cross-executor bit-exact oracle.

3. **Snapshot portability uses an explicit tested compatibility allowlist.**
   A "compatible host" (SPEC §25, criterion 12) is not inferred from a CPU
   feature superset or vendor family. Admission binds architecture, CPU
   vendor/model/stepping and microcode, resolved template state, host
   kernel/KVM capability identity, Firecracker build and snapshot format,
   and measured instruction-behavior class. Snapshot loadability,
   guest-visible CPU equality, and D1 behavioral equivalence are separate
   predicates. A mismatch fails before restore or lowers the run to
   `UNCERTIFIED`.

4. **Approximation-instruction audit.** Guest images and workload artifacts
   are statically scanned for all scalar and packed reciprocal-estimate
   families and x87 code. The scan is diagnostic evidence, not proof of
   non-execution; JIT, self-modifying, packed, downloaded, or otherwise
   uninspected executable code makes the evidence incomplete. A finding or
   coverage gap blocks cross-host D1 unless deterministic execution is
   enforced or an exact measured behavior class is bound into admission.
   QEMU TCG is not assumed to match hardware estimates bit-for-bit; an
   unsupported cross-executor comparison is reported as incomparable, never
   as successful escalation.

5. **Executor and guest obligations** (extends §10.1): the executor applies
   and reads back the x86 CPUID/MSR/XCR0 contract, leaves
   `KVM_ARM_VCPU_SVE` disabled, verifies sanitized ARM ID registers before
   first `KVM_RUN`, and keeps SME unexposed while KVM does not support it.
   The guest boots with the locked profile, never enables forbidden state,
   and reports probe results. Kernel-internal SIMD is permitted only within
   the admitted profile.

6. **Blind issue fails closed.** Code that can execute an instruction present
   on the host but absent from the advertised profile is not an accepted D1
   residual. Admission must prove the path unavailable, the executor must
   enforce equivalent behavior, or the achieved result is D0/
   `UNCERTIFIED`. Repeated replay is additional evidence, not a substitute
   for capability control.

## 3. Consequences

- SIMD arithmetic remains outside the world kernel, but Shen owns profile
  selection, capability-evidence validation, fail-closed certification, and
  canonical profile digests. Native components apply settings and report
  facts.
- Guests keep near-native SIMD performance under `urdr-x86-v3`; nothing in
  the D1 guarantee requires blanket scalarization, but unsupported execution
  prevents certification.
- The pinned QEMU version needs a tested per-profile opcode and semantics
  matrix before M6 can claim a usable escalation path.
- Hosts with AVX-512 run guests that cannot see it; that performance is
  deliberately left on the table in exchange for a stable compatibility
  class.
- If a future workload genuinely requires AVX-512, it forces either a new
  profile with its own narrowed host class and no TCG oracle, or waiting on
  TCG support — an explicit ADR-level decision, not a flag.

## 4. Required verification

No implementation may claim D1 from this ADR until automated tests show:

1. Canonical profile manifests resolve to byte-identical effective capability
   reports on every admitted host; changing any controlled bit changes the
   digest.
2. Guest probes confirm CPUID/ID-register state, XCR0, PMU/counter access,
   entropy instructions, architecture timers, and forbidden SIMD state.
3. A fake adapter that omits, alters, or silently downgrades requested
   capabilities is rejected deterministically by the Shen world kernel.
4. Positive and negative snapshot-restore matrices enforce the committed host
   compatibility allowlist before VM execution.
5. The FP corpus covers NaNs, subnormals, signed zero, rounding modes,
   context switches, and snapshot restore on every admitted CPU class.
6. Blind execution of a masked but physically present instruction and any
   incomplete executable-code audit produce `UNCERTIFIED` unless an enforcing
   capability is present.
7. The pinned QEMU build passes the profile's opcode/semantics matrix; an
   unsupported or behaviorally different operation is reported as
   incomparable.

## 5. Evidence baseline

- Firecracker CPU templates:
  <https://github.com/firecracker-microvm/firecracker/blob/main/docs/cpu_templates/cpu-templates.md>
- Firecracker snapshot support and versioning:
  <https://github.com/firecracker-microvm/firecracker/blob/main/docs/snapshotting/snapshot-support.md>
  and
  <https://github.com/firecracker-microvm/firecracker/blob/main/docs/snapshotting/versioning.md>
- Linux KVM API and ARM vCPU features:
  <https://docs.kernel.org/virt/kvm/api.html> and
  <https://docs.kernel.org/virt/kvm/arm/vcpu-features.html>
- QEMU x86 TCG feature masks:
  <https://github.com/qemu/qemu/blob/master/target/i386/cpu.c>

These moving upstream references inform the decision but are not certification
evidence. Implementations must pin exact versions and retain probe output.
