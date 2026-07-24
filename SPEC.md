# Urdr: Deterministic Whole-System Laboratory

Status: Initial architecture specification  
Repository: `github.com/pyrex41/urdr`  
Visibility: Private  
Primary implementation language: Shen, portable across conforming Shen runtimes  
Reference execution substrate: Firecracker on Linux/KVM  
Reference guest: Single-vCPU custom Linux image running k3s

## 1. Summary

Urdr is a deterministic simulation, replay, and fault-exploration environment for
whole distributed systems. Its first target is a complete k3s cluster running
inside one Firecracker microVM. Later targets include multi-node Kubernetes
clusters and Fargate-compatible task environments.

Urdr treats a running system as a state machine. A portable Shen program, the
world kernel, owns every intentionally variable decision: logical time,
randomness, event ordering, network delivery, fault injection, checkpoint
selection, replay, and schedule shrinking. Native components execute commands
from the world kernel but do not independently make simulation-policy decisions.

The initial product guarantee is observable determinism: for a certified run,
the same initial snapshot and decision transcript must produce the same
externally visible protocol results, durable state, fault sequence, event
ordering, and property verdicts. Urdr records and classifies any interaction
outside that guarantee.

Urdr does not initially promise instruction-exact replay. It is designed so that
an exact executor, such as QEMU TCG or a future modified KVM/Firecracker
executor, can consume the same scenario and decision transcript.

## 2. Name

Urdr is the ASCII project name for Urðr, one of the Norns associated with fate.
It follows the Norse naming lineage of Bifrost and Ratatoskr while describing
the project's purpose: making a system's path reproducible and inspectable.

The command-line executable is `urdr`.

## 3. Product goals

### 3.1 Primary goals

1. Run a real, unmodified application stack and a real k3s control plane inside
   a controlled Linux environment.
2. Make all important distributed-system choices explicit, seeded, logged, and
   replayable.
3. Reproduce a failed run from a compact artifact containing an initial
   snapshot, scenario, inputs, and decision transcript.
4. Explore alternative event schedules and injected faults using seeded search.
5. Minimize a failing execution by removing irrelevant faults and scheduling
   choices while preserving the failure.
6. Bound residual nondeterminism and identify its source category rather than
   silently treating divergent behavior as deterministic.
7. Express scenarios, policies, search strategies, and correctness properties
   in Shen.
8. Run the same Shen world semantics on multiple Shen implementations and use
   Bifrost to prove agreement.
9. Support Linux x86-64 and Linux ARM64 hosts with KVM.
10. Keep the executor interface general enough for Firecracker, gVisor, abstract
    models, and exact emulators to share scenarios and transcripts.

### 3.2 Secondary goals

- Provide deterministic packet-level network behavior and semantic L7 models.
- Record external services once and replay them without network access.
- Permit checkpoint trees that branch from intermediate states.
- Produce machine-readable determinism certificates and divergence reports.
- Support temporal, safety, liveness, crash, and log-based properties.
- Allow model components and workload components to coexist in one simulated
  world.

### 3.3 Non-goals for v0

- Reproducing AWS's internal Fargate implementation.
- Multi-vCPU deterministic execution.
- Transparent instruction-exact replay on stock KVM.
- Production workload hosting.
- Performance benchmarking using virtual time.
- Live internet access during a certified deterministic replay.
- Exhaustively enumerating every possible machine instruction interleaving.
- Simulating cache coherence, speculative execution, power management, or
  microarchitectural timing.
- Shipping built-in emulations of specific cloud services.

## 4. Determinism model

Urdr models the world as:

```text
(world[n+1], commands, choices) = reduce(world[n], event[n])
```

The world contains all simulator-owned state. An event is the sole input to a
reduction. Commands request effects from native adapters. An effect does not
become world state until its resulting observation returns as a new event.
Choices expose legal alternative transitions to the search engine.

A run is identified by:

```text
run-id = hash(
  engine-version,
  scenario,
  initial-snapshot,
  immutable-artifact-manifest,
  input-transcript,
  decision-transcript,
  determinism-profile
)
```

Host execution duration is explicitly outside simulated state. A host may pause
for a minute without causing virtual time to advance.

### 4.1 Observable equivalence

Two D1 runs are equivalent when they have identical canonical:

- World-kernel event streams
- Network outputs at declared observation points
- Recorded service responses
- Durable block-state roots
- Kubernetes API observations requested by the scenario
- Structured workload observations
- Property evaluations and final verdict

Incidental host logs, host timestamps, CPU utilization, and snapshot file
layout are not observable state.

### 4.2 Determinism profiles

Urdr defines progressive profiles rather than a single vague determinism claim.

#### D0: Captured

Every interaction crossing the controlled boundary is classified as pure,
modeled, recorded, or uncontrolled. Replay may consume recorded observations.
D0 does not claim that guest-internal concurrency is repeatable.

#### D1: Observable deterministic

The same snapshot and transcript produce the same declared observable state.
The reference v0 target is D1 for the bundled single-vCPU k3s image.

#### D2: Device and scheduling deterministic

In addition to D1, virtual CPU admission, timers, interrupts, packets, block
completions, entropy, and guest scheduling inputs are repeatable.

#### D3: Instruction-exact

The guest instruction stream and asynchronous event injection points are
replayable exactly. D3 is a future executor profile and may initially be
provided by QEMU TCG rather than Firecracker.

Every run reports the highest profile it actually satisfies. Profiles cannot be
selected merely as labels; adapters must provide the capabilities required by
the profile.

## 5. Sources of nondeterminism

Urdr's threat model includes:

- Wall, monotonic, process, thread, and device clocks
- VDSO and direct timestamp-counter reads
- Kernel and userspace timers
- `getrandom`, random devices, boot entropy, stack canaries, ASLR, and RDRAND
- CPU identity, CPUID, rseq, and CPU migration
- Thread/process scheduling, futex wake ordering, and signal delivery
- Packet arrival, queuing, loss, duplication, corruption, and reordering
- DNS and service discovery
- Block completion order, flushes, errors, and capacity limits
- Filesystem timestamps, allocation, inode identity, and directory ordering
- Cloud APIs and arbitrary external services
- Resource exhaustion and host-originated failures
- Firecracker, KVM, and host-kernel scheduling behavior
- Runtime-specific behavior in Shen hosts

Each source must be eliminated, modeled, recorded, forbidden, or named as an
uncontrolled residual in the run certificate.

## 6. System architecture

```text
                      +-------------------------+
                      | Shen world kernel       |
                      | time / choices / search |
                      | replay / properties     |
                      +------------+------------+
                                   |
                    Urdr Adapter Protocol (UAP)
                                   |
          +------------------------+------------------------+
          |                        |                        |
 +--------v---------+    +---------v---------+    +---------v---------+
 | VM executor      |    | packet broker     |    | service gateway   |
 | Firecracker/KVM  |    | deterministic L2/3|    | OpenResty/Shen-Lua|
 +--------+---------+    +---------+---------+    +---------+---------+
          |                        |                        |
 +--------v---------+              +------------------------+
 | custom Linux     |                         |
 | k3s + workloads  |                  recorded services
 +------------------+
```

### 6.1 Authority rule

There is exactly one authoritative world kernel per run. Embedding Shen in
several native components is allowed, but embedded copies may only evaluate
pure policy delegated by the authoritative kernel. They may not independently
advance time, consume a shared random stream, assign event IDs, or select among
world-level choices.

### 6.2 Native-code rule

Code remains in Shen unless one of these is true:

1. It must invoke an operating-system or hypervisor interface unavailable to
   portable Shen.
2. Measurement demonstrates that it is on a material data-plane hot path.
3. It implements a small trusted adapter around an existing native library.

Native components should move bytes and expose facts. Shen decides what those
facts mean and what happens next.

## 7. Shen world kernel

The following components are implemented in portable Shen:

- Canonical world-state model
- Event reducer
- Logical clock and timer queue
- Choice representation and seeded choice selection
- Splittable/counter-based pseudorandom streams
- Scenario language
- Fault language
- Property language and evaluators
- Replay transcript reader/writer
- Schedule and fault shrinker
- Determinism-certificate model
- State canonicalization and semantic hashing
- Adapter command validation
- Search strategies
- Human-readable explanations of failing properties

### 7.1 Portability contract

The world kernel must produce byte-identical canonical outputs on every
supported Shen runtime. It must not depend on:

- Map/hash iteration order
- Object address or runtime identity
- Floating-point arithmetic
- Host current time
- Host randomness
- Unspecified exception text
- Runtime-specific concurrency
- Locale-sensitive formatting

Time, sequence numbers, sizes, counters, and fixed-point quantities use
arbitrary-precision integers. Ordered association lists or explicitly sorted
maps are used where iteration order is observable.

### 7.2 Bifrost integration

Urdr ships a `bifrost.suite.json` manifest. Bifrost runs the same world-kernel
fixtures on all available Shen ports and requires agreement.

At minimum, cross-runtime tests cover:

- Scenario parsing
- Canonical serialization
- PRNG test vectors
- Event ordering
- Reduction traces
- Property verdicts
- Replay
- Shrinking
- Certificate generation

The first supported runtime is whichever conforming runtime Bifrost resolves.
No one Shen implementation is semantically privileged. Native packaging may
choose a preferred runtime for operational reasons, but Bifrost agreement is
the language-level oracle.

### 7.3 Urdr Adapter Protocol

The Urdr Adapter Protocol is a versioned, length-prefixed stream of canonical
UTF-8 S-expressions.

Requirements:

- Integer-only numeric core
- Explicit schema and protocol version
- Canonically ordered fields
- Stable symbols and UTF-8 encoding
- Request IDs allocated by the world kernel
- Idempotency keys for commands
- No ambient timestamps
- No adapter-generated simulation IDs

An adapter can be in-process through an FFI or out-of-process over a Unix
socket. Both forms must have identical protocol semantics.

## 8. Logical time and quiescence

Virtual time advances only when the world kernel performs an
`advance-to-next-event` transition.

The reference guest kernel uses:

- One virtual CPU
- Tickless operation
- No periodic scheduler tick
- A deterministic paravirtual clocksource
- A deterministic paravirtual clock-event device
- Deterministic entropy supplied by the same device family
- Cooperative quiescence reporting

When all guest work is blocked, the guest reports its next timer deadline and
halts. The world kernel chooses the next eligible event, advances virtual time,
and requests the corresponding interrupt or device delivery.

Host preemption changes only how long a run takes on the host. It must not
change virtual time.

### 8.1 Compute-bound guests

A runnable guest that neither blocks nor yields prevents discrete-event
quiescence. In v0:

- A host watchdog may abort the run.
- The abort is reported as `unbounded-compute`, not as a simulated timeout.
- No wall-clock-driven interrupt is injected into a certified run.

Later executors may use deterministic retired-branch quanta, precise PMU exits,
single-stepping, instrumentation, or software CPU emulation.

## 9. Firecracker executor

Firecracker provides:

- A minimal VM/device boundary
- KVM execution on x86-64 and ARM64 Linux
- VM pause/resume
- Memory and device snapshots
- Virtio block, network, and vsock devices

Firecracker does not itself provide determinism. The Urdr executor must own or
modify all device paths that can introduce guest-visible asynchronous events.

### 9.1 Reference VM constraints

- Exactly one vCPU
- Fixed and normalized CPUID/feature set per architecture
- No guest-visible host wall clock
- No host-provided entropy
- RDRAND/RDSEED masked or trapped
- User-mode RDTSC disabled or trapped
- Stable memory size and device topology
- Stable MAC, IP, disk, and machine identity derived from scenario IDs
- No ballooning or dynamic device hotplug in v0
- No bridged host networking

### 9.2 Executor commands

The initial command set includes:

- Create VM from immutable manifest
- Boot until guest-agent ready
- Run until quiescence or observable exit
- Pause/resume
- Deliver clock event
- Deliver packet
- Complete or fail block operation
- Read structured guest observation
- Create/restore/delete snapshot
- Terminate VM

Every completion returns an observation to the world kernel. The executor does
not schedule a subsequent action by itself.

### 9.3 Exact-executor compatibility

The executor API must permit a QEMU TCG backend. QEMU is the initial candidate
for D3 diagnosis and as an oracle for behavior that the faster Firecracker
backend cannot yet certify.

## 10. Custom guest kernel and agent

The reference image may require a custom Linux kernel and init/agent. This is an
intentional design choice.

### 10.1 Kernel responsibilities

- Use the Urdr paravirtual clock as the system clocksource
- Program virtual deadlines through the Urdr clock-event interface
- Populate VDSO time from virtual time
- Obtain boot and runtime entropy from deterministic streams
- Run single-vCPU and tickless
- Disable or mask uncontrolled CPU entropy/time instructions
- Expose quiescence and next-deadline information
- Ensure stable boot identity and device enumeration
- Emit structured panic, OOM, and shutdown observations

### 10.2 Guest-agent responsibilities

- Establish a control channel independent of workload networking
- Load scenario-provided OCI images and manifests
- Start and observe k3s
- Apply Kubernetes resources
- Expose structured probes without assigning policy
- Coordinate filesystem freeze for snapshots when required
- Report workload readiness and terminal state
- Never advance virtual time or choose fault outcomes

The agent communicates over vsock or a dedicated deterministic virtio device.
Vsock is a control channel, not the implementation of guest time.

## 11. Kubernetes reference environment

The v0 reference environment is one Firecracker microVM containing:

- Custom Urdr Linux kernel
- k3s server
- container runtime and kubelet supplied by k3s
- CoreDNS and normal cluster services
- User-provided OCI workloads

The guest-image interface remains distribution-neutral so that upstream
Kubernetes or another distribution can be added later.

The single-VM design proves world control, replay, properties, and diagnostics
before introducing cross-VM coordination. A later multi-node profile assigns
one VM per node and may place control-plane components on dedicated VMs.

## 12. Deterministic network fabric

### 12.1 Packet broker

Each Firecracker network interface connects to an unbridged TAP endpoint owned
by the Urdr packet broker.

The broker:

- Captures egress packets
- Assigns no simulated ordering of its own
- Reports packet observations to the world kernel
- Retains packets until instructed to deliver or discard them
- Delivers ingress packets only on world-kernel command
- Maintains snapshotable queues and endpoint state
- Prohibits accidental host routing

The world kernel controls:

- Delivery order and virtual delivery time
- Loss, duplication, corruption, and reordering
- Partitions and asymmetric reachability
- Queue capacity and overflow
- Link bandwidth expressed in virtual-time rules
- Stable addressing

Readiness notification order from host `epoll` is not simulation order. If
several host events become ready together, they are collected and presented to
Shen in canonical endpoint/sequence order before a choice is made.

### 12.2 OpenResty and Shen-Lua

OpenResty with Shen-Lua is the semantic L7 service and interception layer, not
the packet scheduler.

It may implement:

- HTTP and gRPC-aware matching
- DNS responses
- Metadata endpoints
- Request/response mutation
- Semantic delays and failures
- External-service recording and replay
- Protocol assertions

OpenResty workers may not use wall-clock timers or I/O readiness order to make
simulation-policy decisions. A single authoritative service-model worker is
preferred initially. Performance-sensitive byte movement can remain native,
while request interpretation and policy remain in Shen.

## 13. External-service record/replay gateway

v0 ships a generic record/replay gateway rather than built-in cloud-service
emulators.

### 13.1 Record mode

Record mode may contact explicitly allowlisted external endpoints. It stores:

- Canonical request identity
- Response status, headers, and body
- Streaming frame boundaries where semantically relevant
- TLS/server identity metadata
- Connection and retry observations
- An explicit ordering relation
- Redaction metadata

Secrets are never written unless a scenario explicitly configures a safe
redaction or replacement policy.

Record mode is D0 and cannot produce a D1 certificate because it consumes live
external state.

### 13.2 Replay mode

Replay mode performs no external network access. Responses are selected by
Shen using the frozen transcript and scenario policy. Missing, ambiguous, or
unexpected requests fail closed with a diagnostic.

Transcripts are immutable, content-addressed inputs to the run ID.

## 14. Storage

Firecracker guests use block devices rather than OverlayFS as the authoritative
snapshot boundary.

The reference layout is:

- Immutable, content-addressed base image
- Per-run copy-on-write writable block layer
- Optional memory-backed writable layer for small scenarios
- Content-addressed OCI image store

OverlayFS may still be used inside the guest by the container runtime, but Urdr
does not treat an OverlayFS upper directory as a complete system snapshot.

The block adapter must make completion and failure visible as simulator events.
Host I/O completion timing cannot directly trigger guest progress.

Durable-state comparison uses a canonical block-state root or a declared
filesystem-level semantic projection. Host allocation layout is not observable.

## 15. Coordinated snapshots

A valid snapshot is a barrier across:

- VM CPU, memory, and device state
- Writable block layers
- Packet queues and endpoint state
- Service gateway connections and models
- External replay cursors
- Shen world state
- Logical time
- PRNG stream counters
- Search frontier and decision transcript position

The snapshot protocol is:

1. Stop admitting new world events.
2. Drive adapters to a declared safe point.
3. Pause the VM.
4. Freeze or checkpoint storage as required.
5. Snapshot every adapter.
6. Serialize and hash the Shen world last.
7. Write a manifest linking all content-addressed components.
8. Resume only after the manifest commits.

Partial snapshots are invalid and garbage-collectable.

Snapshots form a tree. Branches share immutable components and copy-on-write
state.

## 16. Randomness

Urdr uses a specified, portable counter-based or splittable PRNG with published
test vectors.

Random streams are addressed by semantic path:

```text
(seed, subsystem, actor-id, purpose, local-counter)
```

Examples:

- `scheduler/vm-0/runnable`
- `network/link-2/loss`
- `faults/disk-0/result`
- `guest/vm-0/entropy`

Adding a draw to one stream must not perturb another stream. PRNG algorithm,
seed, stream identifiers, and counters are part of snapshots and transcripts.

Cryptographic security is not a goal of simulated entropy. Preventing accidental
reuse of deterministic credentials outside the laboratory is a security goal.

## 17. Exploration and shrinking

v0 uses seeded randomized exploration rather than exhaustive DFS/BFS.

A choice contains:

- Stable choice ID
- Logical time
- Choice kind
- Canonically ordered alternatives
- Selected alternative
- Selection reason and PRNG coordinates

Search strategies are Shen programs. The initial strategy biases toward:

- Boundary timing conditions
- Packet reorderings
- Retry and timeout edges
- Process and node failures
- Storage failures
- Previously uncovered event pairs

### 17.1 Failure shrinking

Given a reproducible failure, Urdr minimizes:

1. Injected faults
2. Network perturbations
3. Artificial delays
4. Scheduling choices
5. External transcript entries
6. Scenario actions

Shrinking restores the nearest useful snapshot and reruns the candidate
transcript. A candidate is accepted only when the same canonical property
failure persists.

The minimized artifact must remain independently replayable.

## 18. Scenario and property language

Scenarios are Shen programs evaluated by the world kernel.

A scenario declares:

- Artifact and guest-image manifests
- Initial seed and determinism profile
- Cluster manifests and OCI workloads
- Network topology and baseline policy
- External transcripts
- Fault domains and allowed fault types
- Search budget
- Observation points
- Properties
- Artifact-retention policy

### 18.1 Property classes

Urdr supports:

- State invariants: a predicate holds at every selected observation point
- Temporal properties: ordering and eventuality over event streams
- Liveness deadlines: an event occurs before a virtual deadline
- Crash predicates: panic, signal, exit, OOM, or reboot behavior
- Log predicates: structured events match or avoid a pattern
- Metamorphic properties: related inputs preserve a declared relation

Property evaluation is deterministic and included in Bifrost conformance tests.
Raw unstructured host logs are not valid property inputs.

## 19. CLI

The primary interface is a CLI with Shen scenario files.

Initial command surface:

```text
urdr run SCENARIO.shen
urdr explore SCENARIO.shen --seed N --budget N
urdr replay RUN-ARTIFACT
urdr shrink RUN-ARTIFACT
urdr inspect RUN-ARTIFACT
urdr diff RUN-A RUN-B
urdr certificate RUN-ARTIFACT
urdr snapshot list|inspect|gc
urdr doctor
```

Common options:

```text
--shen-impl IMPL
--executor firecracker|qemu
--arch x86_64|aarch64
--determinism D0|D1|D2|D3
--artifact-dir PATH
--json
```

`urdr doctor` verifies KVM, Firecracker, guest artifacts, TAP permissions,
required Shen ports, Bifrost, architecture capabilities, and determinism-profile
requirements.

## 20. Event log and diagnostics

Each event record contains:

- Run ID and monotonically increasing event ID
- Logical time
- Actor and subsystem
- Event type and canonical payload
- Causal parent IDs
- Input/output state hashes
- Adapter request/observation IDs
- Determinism classification
- Source location when available

Large payloads are content-addressed rather than duplicated.

### 20.1 Entropy firewall

Every boundary observation is classified:

- `pure`: immutable input validated by hash
- `modeled`: generated by deterministic world policy
- `recorded`: frozen external observation consumed from a transcript
- `uncontrolled`: observation outside the declared model
- `forbidden`: attempted interaction aborts the run

A D1 certificate permits no uncontrolled or forbidden events.

### 20.2 Divergence diagnosis

When repeated runs differ, Urdr:

1. Compares run manifests and capabilities.
2. Finds the first different event or state hash.
3. Restores the nearest common snapshot.
4. Replays with progressively finer observations.
5. Reports the smallest subsystem containing the divergence.
6. Recommends escalation to a stronger executor when CPU execution remains the
   uncontrolled domain.

Memory and disk state may use dirty-page Merkle trees to localize divergence
without hashing all bytes at every event.

## 21. Determinism certificate

A certificate includes:

- Run ID
- Scenario and artifact hashes
- World-kernel and adapter versions
- Shen runtime used
- Bifrost conformance suite/version
- Host architecture and normalized guest CPU model
- Requested and achieved determinism profile
- Counts by entropy-firewall classification
- Residual nondeterminism domains
- Replay verification result
- Final semantic state root
- Property verdicts

The CLI must distinguish:

- `PASS`: properties passed under the achieved requested profile
- `FAIL`: a property failed reproducibly
- `DIVERGED`: repeated execution disagreed
- `UNCERTIFIED`: execution completed but did not satisfy requested controls
- `ERROR`: infrastructure or artifact failure

## 22. Security and isolation

- Urdr is a testing laboratory, not a tenant-isolation service.
- Firecracker's jailer and least privilege are used where practical.
- Record mode requires explicit endpoint allowlists.
- Replay mode denies external egress.
- Deterministic guest entropy must never generate production credentials.
- Transcript redaction is fail-closed.
- Run artifacts may contain workload memory, disks, requests, and secrets and
  must be treated as sensitive.
- Native adapters validate all Shen-issued commands.
- Scenario code is trusted in v0.

## 23. Proposed repository layout

```text
SPEC.md
README.md
bifrost.suite.json
shen/
  world/
  scenario/
  properties/
  search/
  shrink/
  protocol/
  tests/
adapters/
  firecracker/
  qemu/
  network/
  block/
  gateway/
guest/
  kernel/
  device/
  agent/
  images/
openresty/
  nginx.conf
  shen/
protocol/
  uap.md
  fixtures/
scenarios/
  smoke/
  kubernetes/
scripts/
docs/
```

The repository should not vendor Shen ports. Bifrost discovers installed ports
or CI-provided ports through its normal adapter mechanism.

## 24. Milestones

### M0: Semantic nucleus

- Define canonical Shen data representation
- Implement world reduction and integer logical time
- Implement named deterministic PRNG streams
- Define UAP
- Add Bifrost suite across available Shen ports
- Prove byte-identical fixture traces

Exit criterion: at least three Shen ports produce identical canonical traces,
PRNG vectors, property verdicts, and replay output.

### M1: Abstract world

- Implement scenario DSL
- Implement packet/timer/fault models without VMs
- Implement state and temporal properties
- Implement event log, replay, and certificates
- Implement seeded exploration and basic shrinking

Exit criterion: a modeled distributed scenario explores, fails, shrinks, and
replays identically across Shen runtimes.

### M2: Firecracker capsule

- Implement Firecracker adapter
- Build x86-64 and ARM64 custom guest kernels
- Implement guest agent and deterministic control channel
- Boot one VM to a quiescent ready state
- Coordinate full snapshots

Exit criterion: both architectures restore a VM snapshot and produce identical
declared boot observations under the same architecture.

### M3: Deterministic I/O

- Implement TAP packet broker
- Implement deterministic clock/clock-event path
- Implement deterministic entropy
- Gate block and packet completions
- Implement entropy-firewall enforcement

Exit criterion: repeated networked guest tests achieve D1 certificates with no
uncontrolled boundary events.

### M4: k3s reference cluster

- Produce immutable k3s guest image
- Apply OCI workloads and Kubernetes manifests
- Add Kubernetes observation adapters
- Add virtual-time readiness and liveness tests
- Snapshot and restore a running cluster

Exit criterion: the same scenario and transcript produce identical Kubernetes,
network, durable-state, and property outputs across repeated runs.

### M5: External record/replay

- Implement allowlisted recording gateway
- Implement redaction
- Implement transcript replay through OpenResty/Shen-Lua
- Detect missing and ambiguous requests

Exit criterion: a workload recorded once against a real service replays with
all external egress disabled and an achieved D1 certificate.

### M6: Exploration and diagnosis

- Implement coverage-guided seeded choices
- Implement snapshot-aware shrinking
- Implement first-divergence analysis
- Add QEMU TCG diagnostic executor

Exit criterion: Urdr discovers an injected distributed failure, minimizes it,
replays it, and escalates a deliberately CPU-sensitive divergence to the exact
executor.

### M7: Multi-VM and Fargate contracts

- Add multiple independently scheduled Firecracker VMs
- Add deterministic inter-VM packet scheduling
- Add Kubernetes node images
- Define a local Fargate-visible task contract

Exit criterion: a multi-node failure and a Fargate-style task failure are each
reproducible from portable run artifacts.

## 25. v0 acceptance criteria

v0 is complete when:

1. The portable Shen nucleus passes Bifrost agreement on at least three ports.
2. The same Shen source can drive x86-64 and ARM64 Linux/KVM hosts.
3. A custom single-vCPU Firecracker guest boots k3s.
4. Virtual time does not advance while the host process is paused.
5. Guest entropy is reproducible from a named stream.
6. Guest network traffic cannot bypass the deterministic packet broker.
7. Replay mode cannot access the external network.
8. A running k3s cluster can be snapshotted and restored with the complete
   world state.
9. A reference scenario passes 100 consecutive replay-verification runs with
   identical observable roots.
10. A seeded network or service fault causes a reproducible property failure.
11. The shrinker removes at least one irrelevant choice from the failure.
12. The resulting run artifact replays on another compatible host of the same
    architecture.
13. The certificate contains zero uncontrolled events for a D1 run.
14. A deliberately unsupported source of entropy produces `UNCERTIFIED` or a
    fail-closed error rather than a false D1 claim.

## 26. Major risks

### 26.1 Firecracker device completion

Stock Firecracker may expose host-timed completion behavior. Urdr may need a
maintained fork or a narrower custom VMM integration.

### 26.2 Guest compute without quiescence

Discrete-event time cannot preempt an indefinitely runnable guest
deterministically. Mitigations include cooperative yields, PMU-based fuel,
instrumentation, and QEMU TCG escalation.

### 26.3 Guest-kernel complexity

Clock, entropy, timer, and scheduling modifications create a kernel maintenance
burden. Changes should be implemented as small, reviewable devices and drivers
against an explicitly pinned LTS kernel.

### 26.4 Cross-runtime Shen semantics

Port differences can corrupt transcripts or policy. Bifrost agreement is a
release gate, canonical formats avoid runtime-specific representations, and
test vectors are versioned.

### 26.5 Snapshot consistency

Independent VM, disk, network, and world snapshots can create impossible
states. Only globally committed snapshot manifests are restorable.

### 26.6 TLS and semantic interception

Encrypted traffic limits L7 visibility. Scenarios must either provide a test
trust root, configure explicit endpoints, use transcript-aware clients, or
accept packet-level-only control.

### 26.7 False determinism claims

The greatest product risk is reporting determinism while an uncontrolled path
remains. Capability-negotiated profiles, entropy-firewall accounting, replay
verification, and fail-closed certification are mandatory.

## 27. Architectural invariants

These rules are non-negotiable:

1. Only Shen's authoritative world kernel advances logical time.
2. Every nondeterministic choice is explicit and transcript-addressable.
3. Native adapters execute policy; they do not invent it.
4. No certified replay contacts an unrecorded external service.
5. Host elapsed time is never guest virtual time.
6. A snapshot is global or invalid.
7. Random streams are named and isolated.
8. Canonical world semantics agree across Bifrost-supported Shen runtimes.
9. An uncontrolled observation lowers certification or aborts the run.
10. Urdr never claims a stronger determinism profile than its executor and
    adapters can demonstrate.

## 28. Initial implementation decision record

The following decisions are accepted for v0:

- Project name: Urdr
- Repository: private GitHub repository under `pyrex41`
- Reference workload: one complete k3s cluster in one Firecracker VM
- Default guarantee: observable determinism
- Guest policy: custom Linux kernel and guest agent are permitted
- Host architectures: Linux x86-64 and ARM64
- Language policy: implement as much as practical in portable Shen
- Runtime policy: support multiple Shen runtimes rather than selecting one
- Conformance: use `github.com/pyrex41/bifrost`
- Exploration: seeded randomized exploration with replay and shrinking
- Network: deterministic packet broker plus OpenResty/Shen-Lua L7 models
- External integration: generic record/replay gateway
- Interface: CLI with Shen scenarios
- Properties: state, temporal, liveness, crash, and log predicates

Changes to these decisions should be recorded as architecture decision records
under `docs/adr/`.
