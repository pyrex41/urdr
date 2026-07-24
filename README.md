# Urdr

Urdr is a Shen-governed deterministic laboratory for whole distributed
systems. Its first target is a complete k3s cluster inside a controlled
Firecracker microVM, with deterministic logical time, network delivery,
entropy, external-service replay, fault exploration, snapshots, and failure
shrinking.

The authoritative design is in [SPEC.md](SPEC.md).

## Initial direction

- Portable Shen world kernel and scenario/property language
- Cross-runtime semantic agreement through
  [Bifrost](https://github.com/pyrex41/bifrost)
- Firecracker/KVM execution on Linux x86-64 and ARM64
- Custom single-vCPU Linux guest with deterministic clock and entropy devices
- Packet-level broker plus OpenResty/Shen-Lua service models
- Seeded exploration, exact decision replay, and snapshot-aware shrinking
- Explicit determinism certificates that fail closed on uncontrolled inputs

Urdr is currently at the specification stage.
