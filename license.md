# License — Codexex (CodexMeter)

## This Project

Codexex is **proprietary software** owned by Magrathean UK Ltd.

> See [`LICENSE`](./LICENSE) for the full proprietary licence text.
> Copyright © 2026 Magrathean UK Ltd. All rights reserved.

This file (`LICENSE.md`) is the **third-party notice and component inventory** for Codexex. The Apache-2.0 attribution required by the openai/codex crates and other upstream Apache-2.0 components is recorded in [`NOTICE`](./NOTICE). The Codexex source itself is governed exclusively by [`LICENSE`](./LICENSE).

---

## Third-Party Dependencies

### Swift package — `Package.swift`

| Package | License | Declared in |
|---------|---------|-------------|

### Rust helper — `Helper/CodexexHelper/Cargo.toml`

| Package | License | Declared in |
|---------|---------|-------------|
| `anyhow` | MIT OR Apache-2.0 | `Helper/CodexexHelper/Cargo.toml` |
| `base64` | MIT OR Apache-2.0 | `Helper/CodexexHelper/Cargo.toml` |
| `chrono` | MIT OR Apache-2.0 | `Helper/CodexexHelper/Cargo.toml` |
| `codex-app-server-protocol` | Apache-2.0 | `Helper/CodexexHelper/Cargo.toml` (git: openai/codex) |
| `codex-backend-client` | Apache-2.0 | `Helper/CodexexHelper/Cargo.toml` (git: openai/codex) |
| `codex-client` | Apache-2.0 | `Helper/CodexexHelper/Cargo.toml` (git: openai/codex) |
| `codex-login` | Apache-2.0 | `Helper/CodexexHelper/Cargo.toml` (git: openai/codex) |
| `reqwest` | MIT OR Apache-2.0 | `Helper/CodexexHelper/Cargo.toml` |
| `serde` | MIT OR Apache-2.0 | `Helper/CodexexHelper/Cargo.toml` |
| `serde_json` | MIT OR Apache-2.0 | `Helper/CodexexHelper/Cargo.toml` |
| `thiserror` | MIT OR Apache-2.0 | `Helper/CodexexHelper/Cargo.toml` |
| `tokio` | MIT | `Helper/CodexexHelper/Cargo.toml` |
| `urlencoding` | MIT | `Helper/CodexexHelper/Cargo.toml` |
| `tokio-tungstenite` *(patch)* | MIT | `Helper/CodexexHelper/Cargo.toml` (openai fork) |
| `tungstenite` *(patch)* | MIT | `Helper/CodexexHelper/Cargo.toml` (openai fork) |
| `pretty_assertions` *(dev)* | MIT OR Apache-2.0 | `Helper/CodexexHelper/Cargo.toml` |
| `serial_test` *(dev)* | MIT | `Helper/CodexexHelper/Cargo.toml` |
| `tempfile` *(dev)* | MIT OR Apache-2.0 | `Helper/CodexexHelper/Cargo.toml` |
| `wiremock` *(dev)* | MIT | `Helper/CodexexHelper/Cargo.toml` |

> The `codex-*` crates are pulled from `github.com/openai/codex` at a pinned revision.
> The openai/codex repository is licensed under Apache-2.0.

---

## License Obligations Summary

| License | Action required on redistribution |
|---------|-----------------------------------|
| MIT | Retain copyright notice and licence text |
| Apache-2.0 | Retain NOTICE file (if any) and licence text |
