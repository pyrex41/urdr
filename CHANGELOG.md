# Changelog

## v0.1.0 — 2026-08-04

First tagged release. Urdr becomes a consumable substrate:

- **Apache-2.0 license** — the repository (and the `urdr-uap` package) now
  carry an explicit grant; contributions are accepted under the same terms.
- **`urdr-uap` 0.1.0** — the UAP M0 reference implementation
  (`adapters/common/uap`) is pip-installable as import package `urdr_uap`
  without moving files. The compatibility contract is the wire format,
  `CanonicalCodec.name == b"urdr-rfc9804-v1"`, not the import path.
- **`shen/load.shen`** — canonical dependency-ordered load manifest for
  consuming the Shen tree as a library (cwd must be the repo root). The
  integration conformance lane loads through it, so the order is exercised
  by the four-port Bifrost gate.
- **Zero consumer-specific content** — any out-of-tree dogfood adapters
  (never committed here) live with their consumer repos; plan-doc citations
  of consumer repos were de-specialized. Downstream consumers pin this repo
  by tag/commit and resolve it via a `URDR_ROOT` environment variable.

State of the substrate at this tag: milestones M0–M1.5 (canonical codec,
named PRNG streams, modeled world kernel, property/replay/shrink engine,
four-port Bifrost conformance gate) are implemented and gated; the
whole-system laboratory (SPEC §9–§15) is unstarted design. GitHub Actions
CI is billing-blocked, so the annotated tag message records the digest of
a local conformance gate run as the trust anchor for this release.
