# Contributing to Urdr

Urdr is a fail-closed determinism project. Read `SPEC.md`, especially §27, and
all accepted ADRs before changing behavior. A passing test is evidence, not
permission to weaken an architectural invariant or claim an unsupported
determinism profile.

## Development contract

Use an isolated branch or worktree and keep each change inside its declared
module ownership. Verify a change against its allowed paths before review:

```text
scripts/check-owned-paths --base-ref main \
  --allow 'shen/world/' --allow 'shen/tests/'
```

An allow value ending in `/` covers that directory recursively. Other values
name one exact file. The command includes committed, staged, unstaged, and
untracked files. Reviewers must reject unexplained cross-module edits even when
the test suite passes.

Shen owns world policy: logical time, event and choice IDs, random coordinates,
ordering, profile validation, and certification decisions. Native code may
execute commands and report facts, but must not independently make those
decisions. See `docs/module-boundaries.md`.

## Reproducible commands

`make bootstrap` is the only standard command allowed to contact the network.
It validates pinned lock files and checks out each exact 40-character commit
under `.cache/urdr/dependencies`. Review lock-file changes like source changes.

All other standard commands are offline:

- `make fmt-check` checks repository text, JSON, workflow action pins, and
  generated-file hygiene using only Python's standard library and Git.
- `make test` runs offline foundation/unit tests.
- `make conformance` invokes the strict Bifrost gate. It fails closed until the
  M0 suite, pins, and gate are present.
- `make ci` runs formatting, tests, and conformance and proves that they did not
  change the working tree.
- `make quality` is the temporary Wave 0 foundation gate; it runs only the
  checks that exist before M0.

Do not add implicit installers, auto-downloads, floating dependency versions,
or skip-on-missing-runtime behavior to an ordinary test path.

## Generated files and formatting

Generated output belongs only in ignored cache/output locations. Golden
fixtures, dependency locks, schemas, and provenance are source inputs and must
be committed deliberately. After a check, `git status --porcelain=v1` must be
unchanged.

Text files must be UTF-8, use LF line endings, and end in one newline. Trailing
whitespace is forbidden except for Markdown's intentional two-space hard break.
JSON must parse. Every `uses:` reference in GitHub Actions must use a full
lowercase commit SHA; a tag may appear only in a comment for maintainability.

Before requesting review, run:

```text
make fmt-check
make test
git diff --check
git status --porcelain=v1
```

Once M0 dependencies have been bootstrapped, also run `make conformance` and
`make ci`. Never report unavailable conformance as a pass.

## Architecture decisions

Use `docs/adr/0000-template.md` for decisions that change accepted design,
portable semantics, protocol bytes, dependency policy, or certification
requirements. ADRs are immutable historical records after acceptance; replace
an accepted decision with a superseding ADR rather than silently rewriting it.

## License

By contributing to Urdr you agree that your contributions are accepted under
the terms of the [Apache License 2.0](LICENSE).
