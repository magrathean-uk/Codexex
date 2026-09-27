# Third-party notices

The required attribution for third-party material Codexex ships is in
[NOTICE](../../NOTICE). This page adds the fuller dependency inventory.

## Rust helper (`Helper/CodexexHelper/`)

`Package.swift` declares no third-party Swift package dependencies. The helper's direct
dependencies are declared in `Helper/CodexexHelper/Cargo.toml`; the repository's
`cargo-deny` workflow checks their licence, source and ban policy on every push and pull
request to `main`.

| Dependency group | Licence |
| --- | --- |
| `codex-app-server-protocol`, `codex-backend-client`, `codex-client`, `codex-login` (from `openai/codex`) | Apache-2.0 |
| `anyhow`, `base64`, `chrono`, `reqwest`, `serde`, `serde_json`, `thiserror`, `pretty_assertions`, `tempfile` | MIT OR Apache-2.0 |
| `tokio`, `urlencoding`, `tokio-tungstenite`, `tungstenite`, `serial_test`, `wiremock` | MIT |

This table repeats the project's existing dependency declarations; it is not a fresh
resolved-package audit. Run `cargo metadata --offline --manifest-path
Helper/CodexexHelper/Cargo.toml` for the resolved graph before distributing a binary.

## Prototype (`Prototypes/MatrixQuota/`)

`Prototypes/MatrixQuota/package.json` declares npm dependencies, but the repository has
no licence inventory for that dependency graph yet. The licence for those dependencies
must be confirmed from the lockfile before the prototype is distributed.

## Icon asset

The OpenAI/Codex provider icon in the macOS menu bar, adapted from CodexBar's
`ProviderIcon-codex.svg` (MIT, Copyright (c) 2026 Peter Steinberger), is recorded with its
full licence text in [NOTICE](../../NOTICE).
