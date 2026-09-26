# License and third-party inventory

## Codexex

Codexex is proprietary software owned by Magrathean UK Ltd. The complete grant
and restrictions are in [`LICENSE`](./LICENSE). Public availability of this
repository does not create permissions beyond that licence.

Copyright © 2026 Magrathean UK Ltd. All rights reserved.

`NOTICE` preserves the in-tree attribution for the OpenAI/Codex Rust crates,
the provider-icon asset, and third-party trademarks. [`TRADEMARKS.md`](./TRADEMARKS.md)
identifies the project and third-party marks mentioned in the repository.

## Dependency record

`Package.swift` currently declares no third-party Swift package dependencies.
The Rust helper's direct dependency names are declared in
`Helper/CodexexHelper/Cargo.toml`; the repository's `cargo-deny` workflow checks
their licence, source, and ban policy. The entries below repeat the existing
project inventory and notices. They are not a fresh resolved-package audit.

`Prototypes/MatrixQuota/package.json` declares npm dependencies, but the
repository provides no corresponding first-party licence inventory or notice
bundle. This document makes no licence claim for that prototype dependency
graph. Review its lockfile and resolved package notices before distribution.

| Dependency group | Existing recorded licence or notice |
| --- | --- |
| `codex-app-server-protocol`, `codex-backend-client`, `codex-client`, `codex-login` | Apache-2.0, from the pinned `openai/codex` source in the helper manifest |
| `anyhow`, `base64`, `chrono`, `reqwest`, `serde`, `serde_json`, `thiserror`, `pretty_assertions`, `tempfile` | MIT OR Apache-2.0 |
| `tokio`, `urlencoding`, `tokio-tungstenite`, `tungstenite`, `serial_test`, `wiremock` | MIT |

This is a source-inventory aid, not a replacement for the controlling licence
texts, package metadata, or any attribution required for a distributed binary.
Before shipping a binary, review the resolved dependency graph and any notices
it requires.
