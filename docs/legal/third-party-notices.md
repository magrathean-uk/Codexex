# Third-party notices

This page lists the third-party material that Codexex ships and the licence each part is
under.

Last updated 28 September 2026.

The attribution and notice text that must accompany a Codexex distribution is in
[NOTICE](../../NOTICE). This page is the full inventory behind it.

## What ships

Codexex ships as a macOS app and an iOS app with its widgets. The macOS app embeds the Rust
helper (`Helper/CodexexHelper/`), built for `aarch64-apple-darwin` and
`x86_64-apple-darwin`, in the app bundle and in its XPC service. The iOS app does not
include the helper.

The MatrixQuota prototype (`Prototypes/MatrixQuota/`) is not part of any app target or
build script and is not distributed; its npm dependencies do not ship.

## Swift app

`Package.swift` declares no third-party Swift packages, and both `Package.resolved` files
(the repository root and `CodexMeter.xcodeproj`) contain no pinned packages.

### Icon asset

The OpenAI/Codex mark shown in the macOS menu bar
(`Sources/CodexMeterApp/Assets.xcassets/OpenAILogo.imageset/openai-logo.svg`) is adapted
from CodexBar's `ProviderIcon-codex.svg`.

| Component | Licence | Copyright |
| --- | --- | --- |
| CodexBar `ProviderIcon-codex.svg` ([steipete/CodexBar](https://github.com/steipete/CodexBar)) | MIT | Copyright (c) 2026 Peter Steinberger |

The full MIT licence text is reproduced in [NOTICE](../../NOTICE).

## Rust helper

The helper's dependencies are declared in `Helper/CodexexHelper/Cargo.toml` and pinned in
`Helper/CodexexHelper/Cargo.lock`. The repository's `cargo-deny` workflow checks their
licences, sources and bans on every push and pull request to `main`, against the allow-list
in `Helper/CodexexHelper/deny.toml`.

### Direct dependencies

| Dependency | Locked version | Licence |
| --- | --- | --- |
| `codex-protocol`, `codex-backend-client`, `codex-client`, `codex-login` ([openai/codex](https://github.com/openai/codex) at `be6e8eac029b183056b7e4402879f15d2c85f61b`) | 0.147.0 | Apache-2.0 |
| `anyhow` | 1.0.104 | MIT OR Apache-2.0 |
| `base64` | 0.22.1 | MIT OR Apache-2.0 |
| `chrono` | 0.4.45 | MIT OR Apache-2.0 |
| `httpdate` | 1.0.3 | MIT OR Apache-2.0 |
| `libc` | 0.2.184 | MIT OR Apache-2.0 |
| `reqwest` | 0.12.28 | MIT OR Apache-2.0 |
| `serde` | 1.0.229 | MIT OR Apache-2.0 |
| `serde_json` | 1.0.151 | MIT OR Apache-2.0 |
| `thiserror` | 2.0.20 | MIT OR Apache-2.0 |
| `tokio` | 1.53.1 | MIT |
| `urlencoding` | 2.1.3 | MIT |

`Cargo.toml` replaces two crates.io packages with forks:

| Crate | Fork and revision | Version | Licence |
| --- | --- | --- | --- |
| `tokio-tungstenite` | [openai-oss-forks/tokio-tungstenite](https://github.com/openai-oss-forks/tokio-tungstenite) at `0e5b2d73aa18dd9f0a50ee9ff199d5aef7594186` | 0.28.0 | MIT |
| `tungstenite` | [openai-oss-forks/tungstenite-rs](https://github.com/openai-oss-forks/tungstenite-rs) at `4fffad30fe373adbdcffab9545e9e9bf4f2fc19f` | 0.27.0 | MIT OR Apache-2.0 |

The development dependencies (`pretty_assertions`, `serial_test`, `tempfile`, `wiremock`
and the extra `tokio` test features) are used only for tests and do not ship.

### OpenAI Codex crates

The four direct `codex-*` dependencies bring in 39 crates from the
[openai/codex](https://github.com/openai/codex) repository at commit
`be6e8eac029b183056b7e4402879f15d2c85f61b`, all at version 0.147.0 and all under
Apache-2.0:

`codex-agent-identity`, `codex-api`, `codex-async-utils`, `codex-aws-auth`, `codex-backend-client`, `codex-backend-openapi-models`, `codex-client`, `codex-collaboration-mode-templates`, `codex-config`, `codex-execpolicy`, `codex-extension-items`, `codex-features`, `codex-feedback`, `codex-file-system`, `codex-git-utils`, `codex-http-client`, `codex-keyring-store`, `codex-login`, `codex-model-provider`, `codex-model-provider-info`, `codex-models-manager`, `codex-network-proxy`, `codex-otel`, `codex-protocol`, `codex-response-debug-context`, `codex-secrets`, `codex-terminal-detection`, `codex-utils-absolute-path`, `codex-utils-cache`, `codex-utils-home-dir`, `codex-utils-image`, `codex-utils-output-truncation`, `codex-utils-path`, `codex-utils-path-uri`, `codex-utils-pty`, `codex-utils-rustls-provider`, `codex-utils-string`, `codex-utils-template`, `codex-websocket-client`

The repository's `NOTICE` file at that commit is reproduced verbatim in
[NOTICE](../../NOTICE).

### Licences with specific conditions

Every licence in the helper's dependency graph is permissive, except the one file-level
copyleft licence noted below.

| Crate | Licence | How Codexex complies |
| --- | --- | --- |
| `moka` 0.12.15 | (MIT OR Apache-2.0) AND Apache-2.0 | Two of its files are under Apache-2.0 only. Its `NOTICE` file is reproduced verbatim in [NOTICE](../../NOTICE). |
| `option-ext` 0.2.0 | MPL-2.0 | Used unmodified. Its source code is available at [crates.io](https://crates.io/crates/option-ext/0.2.0) and [soc/option-ext](https://github.com/soc/option-ext). |
| `self_cell` 1.3.0 | Apache-2.0 OR GPL-2.0-only | Codexex uses it under Apache-2.0. |
| `webpki-roots` 1.0.6 | CDLA-Permissive-2.0 | The licence text is in the crate's `LICENSE` file and at <https://cdla.dev/permissive-2-0/>. |
| 20 crates from [unicode-org/icu4x](https://github.com/unicode-org/icu4x) | Unicode-3.0 | Listed in the inventory below; the licence text is in each crate's `LICENSE` file. |

### Full inventory

The table lists every crate compiled into the shipped helper binary, other than the
OpenAI Codex crates above: 569 crates. It is the normal (non-development, non-build-script,
non-procedural-macro) dependency graph resolved from `Cargo.lock` for both release targets
with `cargo tree --locked --edges normal,no-proc-macro`. Licences are as declared in each
crate's manifest; a legacy `/` is written as `OR` and alternatives are sorted. Each crate's
full licence text and copyright notice are in its published source at the version shown.

| Crate | Version | Licence |
| --- | --- | --- |
| `addr2line` | 0.25.1 | Apache-2.0 OR MIT |
| `aead` | 0.5.2 | Apache-2.0 OR MIT |
| `age` | 0.11.5 | Apache-2.0 OR MIT |
| `age-core` | 0.11.0 | Apache-2.0 OR MIT |
| `ahash` | 0.8.12 | Apache-2.0 OR MIT |
| `allocator-api2` | 0.2.21 | Apache-2.0 OR MIT |
| `annotate-snippets` | 0.9.2 | Apache-2.0 OR MIT |
| `anstream` | 1.0.0 | Apache-2.0 OR MIT |
| `anstyle` | 1.0.14 | Apache-2.0 OR MIT |
| `anstyle-parse` | 1.0.0 | Apache-2.0 OR MIT |
| `anstyle-query` | 1.1.5 | Apache-2.0 OR MIT |
| `anyhow` | 1.0.104 | Apache-2.0 OR MIT |
| `arc-swap` | 1.9.2 | Apache-2.0 OR MIT |
| `arrayvec` | 0.7.8 | Apache-2.0 OR MIT |
| `ascii` | 1.1.0 | Apache-2.0 OR MIT |
| `asn1-rs` | 0.7.1 | Apache-2.0 OR MIT |
| `async-channel` | 2.5.0 | Apache-2.0 OR MIT |
| `asynk-strim` | 0.1.5 | Apache-2.0 OR MIT |
| `atomic` | 0.5.3 | Apache-2.0 OR MIT |
| `atomic-waker` | 1.1.2 | Apache-2.0 OR MIT |
| `backtrace` | 0.3.76 | Apache-2.0 OR MIT |
| `base16ct` | 0.2.0 | Apache-2.0 OR MIT |
| `base64` | 0.21.7 | Apache-2.0 OR MIT |
| `base64` | 0.22.1 | Apache-2.0 OR MIT |
| `base64ct` | 1.8.3 | Apache-2.0 OR MIT |
| `bit-set` | 0.8.0 | Apache-2.0 OR MIT |
| `bit-vec` | 0.8.0 | Apache-2.0 OR MIT |
| `bitflags` | 1.3.2 | Apache-2.0 OR MIT |
| `bitflags` | 2.11.0 | Apache-2.0 OR MIT |
| `blake2` | 0.10.6 | Apache-2.0 OR MIT |
| `block-buffer` | 0.10.4 | Apache-2.0 OR MIT |
| `bstr` | 1.12.1 | Apache-2.0 OR MIT |
| `bumpalo` | 3.20.2 | Apache-2.0 OR MIT |
| `bytes-utils` | 0.1.4 | Apache-2.0 OR MIT |
| `cfg-if` | 1.0.4 | Apache-2.0 OR MIT |
| `chacha20` | 0.9.1 | Apache-2.0 OR MIT |
| `chacha20poly1305` | 0.10.1 | Apache-2.0 OR MIT |
| `chardetng` | 0.1.17 | Apache-2.0 OR MIT |
| `chrono` | 0.4.45 | Apache-2.0 OR MIT |
| `chunked_transfer` | 1.5.0 | Apache-2.0 OR MIT |
| `cipher` | 0.4.4 | Apache-2.0 OR MIT |
| `clap` | 4.6.0 | Apache-2.0 OR MIT |
| `clap_builder` | 4.6.0 | Apache-2.0 OR MIT |
| `clap_lex` | 1.1.0 | Apache-2.0 OR MIT |
| `cmp_any` | 0.8.1 | Apache-2.0 OR MIT |
| `cobs` | 0.3.0 | Apache-2.0 OR MIT |
| `colorchoice` | 1.0.5 | Apache-2.0 OR MIT |
| `concurrent-queue` | 2.5.0 | Apache-2.0 OR MIT |
| `const-hex` | 1.18.1 | Apache-2.0 OR MIT |
| `const-oid` | 0.9.6 | Apache-2.0 OR MIT |
| `cookie` | 0.18.1 | Apache-2.0 OR MIT |
| `cookie_store` | 0.22.1 | Apache-2.0 OR MIT |
| `core-foundation` | 0.9.4 | Apache-2.0 OR MIT |
| `core-foundation` | 0.10.1 | Apache-2.0 OR MIT |
| `core-foundation-sys` | 0.8.7 | Apache-2.0 OR MIT |
| `cpufeatures` | 0.2.17 | Apache-2.0 OR MIT |
| `crc` | 3.4.0 | Apache-2.0 OR MIT |
| `crc-catalog` | 2.5.0 | Apache-2.0 OR MIT |
| `crc32fast` | 1.5.0 | Apache-2.0 OR MIT |
| `critical-section` | 1.2.0 | Apache-2.0 OR MIT |
| `crossbeam-channel` | 0.5.15 | Apache-2.0 OR MIT |
| `crossbeam-deque` | 0.8.6 | Apache-2.0 OR MIT |
| `crossbeam-epoch` | 0.9.18 | Apache-2.0 OR MIT |
| `crossbeam-utils` | 0.8.21 | Apache-2.0 OR MIT |
| `crypto-bigint` | 0.5.5 | Apache-2.0 OR MIT |
| `crypto-common` | 0.1.7 | Apache-2.0 OR MIT |
| `crypto_box` | 0.9.1 | Apache-2.0 OR MIT |
| `crypto_secretbox` | 0.1.1 | Apache-2.0 OR MIT |
| `ctor` | 1.0.7 | Apache-2.0 OR MIT |
| `der` | 0.7.10 | Apache-2.0 OR MIT |
| `der-parser` | 10.0.0 | Apache-2.0 OR MIT |
| `deranged` | 0.5.8 | Apache-2.0 OR MIT |
| `digest` | 0.10.7 | Apache-2.0 OR MIT |
| `dirs` | 6.0.0 | Apache-2.0 OR MIT |
| `dirs-sys` | 0.5.0 | Apache-2.0 OR MIT |
| `display_container` | 0.9.0 | Apache-2.0 OR MIT |
| `dns-lookup` | 3.0.1 | Apache-2.0 OR MIT |
| `downcast-rs` | 1.2.1 | Apache-2.0 OR MIT |
| `dupe` | 0.9.1 | Apache-2.0 OR MIT |
| `dyn-clone` | 1.0.20 | Apache-2.0 OR MIT |
| `ecdsa` | 0.16.9 | Apache-2.0 OR MIT |
| `ed25519` | 2.2.3 | Apache-2.0 OR MIT |
| `either` | 1.15.0 | Apache-2.0 OR MIT |
| `elliptic-curve` | 0.13.8 | Apache-2.0 OR MIT |
| `env_filter` | 1.0.1 | Apache-2.0 OR MIT |
| `env_logger` | 0.11.10 | Apache-2.0 OR MIT |
| `equivalent` | 1.0.2 | Apache-2.0 OR MIT |
| `erased-serde` | 0.3.31 | Apache-2.0 OR MIT |
| `erased-serde` | 0.4.10 | Apache-2.0 OR MIT |
| `errno` | 0.3.14 | Apache-2.0 OR MIT |
| `event-listener` | 5.4.1 | Apache-2.0 OR MIT |
| `event-listener-strategy` | 0.5.4 | Apache-2.0 OR MIT |
| `eventsource-stream` | 0.2.3 | Apache-2.0 OR MIT |
| `fastrand` | 2.4.1 | Apache-2.0 OR MIT |
| `fd-lock` | 4.0.4 | Apache-2.0 OR MIT |
| `fdeflate` | 0.3.7 | Apache-2.0 OR MIT |
| `ff` | 0.13.1 | Apache-2.0 OR MIT |
| `findshlibs` | 0.10.2 | Apache-2.0 OR MIT |
| `flate2` | 1.1.9 | Apache-2.0 OR MIT |
| `fluent` | 0.16.1 | Apache-2.0 OR MIT |
| `fluent-bundle` | 0.15.3 | Apache-2.0 OR MIT |
| `fluent-langneg` | 0.13.1 | Apache-2.0 OR MIT |
| `fluent-syntax` | 0.11.1 | Apache-2.0 OR MIT |
| `flume` | 0.12.0 | Apache-2.0 OR MIT |
| `fnv` | 1.0.7 | Apache-2.0 OR MIT |
| `form_urlencoded` | 1.2.2 | Apache-2.0 OR MIT |
| `futures` | 0.3.32 | Apache-2.0 OR MIT |
| `futures-channel` | 0.3.32 | Apache-2.0 OR MIT |
| `futures-core` | 0.3.32 | Apache-2.0 OR MIT |
| `futures-executor` | 0.3.32 | Apache-2.0 OR MIT |
| `futures-io` | 0.3.32 | Apache-2.0 OR MIT |
| `futures-sink` | 0.3.32 | Apache-2.0 OR MIT |
| `futures-task` | 0.3.32 | Apache-2.0 OR MIT |
| `futures-util` | 0.3.32 | Apache-2.0 OR MIT |
| `fxhash` | 0.2.1 | Apache-2.0 OR MIT |
| `getrandom` | 0.2.17 | Apache-2.0 OR MIT |
| `getrandom` | 0.3.4 | Apache-2.0 OR MIT |
| `getrandom` | 0.4.2 | Apache-2.0 OR MIT |
| `gif` | 0.14.2 | Apache-2.0 OR MIT |
| `gimli` | 0.32.3 | Apache-2.0 OR MIT |
| `gix` | 0.81.0 | Apache-2.0 OR MIT |
| `gix-actor` | 0.40.0 | Apache-2.0 OR MIT |
| `gix-chunk` | 0.7.3 | Apache-2.0 OR MIT |
| `gix-command` | 0.8.1 | Apache-2.0 OR MIT |
| `gix-commitgraph` | 0.35.0 | Apache-2.0 OR MIT |
| `gix-config` | 0.54.0 | Apache-2.0 OR MIT |
| `gix-config-value` | 0.17.2 | Apache-2.0 OR MIT |
| `gix-date` | 0.15.6 | Apache-2.0 OR MIT |
| `gix-diff` | 0.61.0 | Apache-2.0 OR MIT |
| `gix-discover` | 0.49.0 | Apache-2.0 OR MIT |
| `gix-error` | 0.2.5 | Apache-2.0 OR MIT |
| `gix-features` | 0.46.2 | Apache-2.0 OR MIT |
| `gix-fs` | 0.19.2 | Apache-2.0 OR MIT |
| `gix-glob` | 0.24.0 | Apache-2.0 OR MIT |
| `gix-hash` | 0.23.0 | Apache-2.0 OR MIT |
| `gix-hashtable` | 0.13.0 | Apache-2.0 OR MIT |
| `gix-lock` | 21.0.2 | Apache-2.0 OR MIT |
| `gix-object` | 0.58.0 | Apache-2.0 OR MIT |
| `gix-odb` | 0.78.0 | Apache-2.0 OR MIT |
| `gix-pack` | 0.68.0 | Apache-2.0 OR MIT |
| `gix-packetline` | 0.21.5 | Apache-2.0 OR MIT |
| `gix-path` | 0.11.3 | Apache-2.0 OR MIT |
| `gix-protocol` | 0.59.0 | Apache-2.0 OR MIT |
| `gix-quote` | 0.7.2 | Apache-2.0 OR MIT |
| `gix-ref` | 0.61.0 | Apache-2.0 OR MIT |
| `gix-refspec` | 0.39.0 | Apache-2.0 OR MIT |
| `gix-revision` | 0.43.0 | Apache-2.0 OR MIT |
| `gix-revwalk` | 0.29.0 | Apache-2.0 OR MIT |
| `gix-sec` | 0.13.3 | Apache-2.0 OR MIT |
| `gix-shallow` | 0.10.0 | Apache-2.0 OR MIT |
| `gix-tempfile` | 21.0.2 | Apache-2.0 OR MIT |
| `gix-trace` | 0.1.21 | Apache-2.0 OR MIT |
| `gix-transport` | 0.55.1 | Apache-2.0 OR MIT |
| `gix-traverse` | 0.55.0 | Apache-2.0 OR MIT |
| `gix-url` | 0.35.3 | Apache-2.0 OR MIT |
| `gix-utils` | 0.3.5 | Apache-2.0 OR MIT |
| `gix-validate` | 0.11.3 | Apache-2.0 OR MIT |
| `group` | 0.13.0 | Apache-2.0 OR MIT |
| `hash32` | 0.2.1 | Apache-2.0 OR MIT |
| `hash32` | 0.3.1 | Apache-2.0 OR MIT |
| `hashbrown` | 0.14.5 | Apache-2.0 OR MIT |
| `hashbrown` | 0.16.1 | Apache-2.0 OR MIT |
| `hashbrown` | 0.17.0 | Apache-2.0 OR MIT |
| `heapless` | 0.7.17 | Apache-2.0 OR MIT |
| `heapless` | 0.8.0 | Apache-2.0 OR MIT |
| `hex` | 0.4.3 | Apache-2.0 OR MIT |
| `hickory-proto` | 0.25.2 | Apache-2.0 OR MIT |
| `hickory-resolver` | 0.25.2 | Apache-2.0 OR MIT |
| `hkdf` | 0.12.4 | Apache-2.0 OR MIT |
| `hmac` | 0.12.1 | Apache-2.0 OR MIT |
| `home` | 0.5.12 | Apache-2.0 OR MIT |
| `http` | 0.2.12 | Apache-2.0 OR MIT |
| `http` | 1.4.0 | Apache-2.0 OR MIT |
| `httparse` | 1.10.1 | Apache-2.0 OR MIT |
| `httpdate` | 1.0.3 | Apache-2.0 OR MIT |
| `hyper-timeout` | 0.5.2 | Apache-2.0 OR MIT |
| `hyper-tls` | 0.6.0 | Apache-2.0 OR MIT |
| `iana-time-zone` | 0.1.65 | Apache-2.0 OR MIT |
| `idna` | 1.1.0 | Apache-2.0 OR MIT |
| `idna_adapter` | 1.2.1 | Apache-2.0 OR MIT |
| `image` | 0.25.10 | Apache-2.0 OR MIT |
| `image-webp` | 0.2.4 | Apache-2.0 OR MIT |
| `indenter` | 0.3.4 | Apache-2.0 OR MIT |
| `indexmap` | 2.14.0 | Apache-2.0 OR MIT |
| `inout` | 0.1.4 | Apache-2.0 OR MIT |
| `intl-memoizer` | 0.5.3 | Apache-2.0 OR MIT |
| `intl_pluralrules` | 7.0.2 | Apache-2.0 OR MIT |
| `inventory` | 0.3.24 | Apache-2.0 OR MIT |
| `io_tee` | 0.1.1 | Apache-2.0 OR MIT |
| `ipnet` | 2.12.0 | Apache-2.0 OR MIT |
| `iri-string` | 0.7.12 | Apache-2.0 OR MIT |
| `is_terminal_polyfill` | 1.70.2 | Apache-2.0 OR MIT |
| `itertools` | 0.14.0 | Apache-2.0 OR MIT |
| `itoa` | 1.0.18 | Apache-2.0 OR MIT |
| `keyring` | 3.6.3 | Apache-2.0 OR MIT |
| `lazy_static` | 1.5.0 | Apache-2.0 OR MIT |
| `libc` | 0.2.184 | Apache-2.0 OR MIT |
| `link-section` | 0.18.1 | Apache-2.0 OR MIT |
| `lock_api` | 0.4.14 | Apache-2.0 OR MIT |
| `lock_free_hashtable` | 0.1.4 | Apache-2.0 OR MIT |
| `log` | 0.4.29 | Apache-2.0 OR MIT |
| `logos` | 0.15.1 | Apache-2.0 OR MIT |
| `maplit` | 1.0.2 | Apache-2.0 OR MIT |
| `md5` | 0.8.0 | Apache-2.0 OR MIT |
| `memmap2` | 0.9.11 | Apache-2.0 OR MIT |
| `mime` | 0.3.17 | Apache-2.0 OR MIT |
| `minimal-lexical` | 0.2.1 | Apache-2.0 OR MIT |
| `multimap` | 0.10.1 | Apache-2.0 OR MIT |
| `native-tls` | 0.2.18 | Apache-2.0 OR MIT |
| `num-bigint` | 0.4.6 | Apache-2.0 OR MIT |
| `num-conv` | 0.2.1 | Apache-2.0 OR MIT |
| `num-integer` | 0.1.46 | Apache-2.0 OR MIT |
| `num-traits` | 0.2.19 | Apache-2.0 OR MIT |
| `object` | 0.37.3 | Apache-2.0 OR MIT |
| `oid-registry` | 0.8.1 | Apache-2.0 OR MIT |
| `once_cell` | 1.21.4 | Apache-2.0 OR MIT |
| `opaque-debug` | 0.3.1 | Apache-2.0 OR MIT |
| `p256` | 0.13.2 | Apache-2.0 OR MIT |
| `parking` | 2.2.1 | Apache-2.0 OR MIT |
| `parking_lot` | 0.12.5 | Apache-2.0 OR MIT |
| `parking_lot_core` | 0.9.12 | Apache-2.0 OR MIT |
| `pbkdf2` | 0.12.2 | Apache-2.0 OR MIT |
| `pem-rfc7468` | 0.7.0 | Apache-2.0 OR MIT |
| `percent-encoding` | 2.3.2 | Apache-2.0 OR MIT |
| `pin-project` | 1.1.11 | Apache-2.0 OR MIT |
| `pin-project-lite` | 0.2.17 | Apache-2.0 OR MIT |
| `pin-utils` | 0.1.0 | Apache-2.0 OR MIT |
| `pkcs8` | 0.10.2 | Apache-2.0 OR MIT |
| `png` | 0.18.1 | Apache-2.0 OR MIT |
| `poly1305` | 0.8.0 | Apache-2.0 OR MIT |
| `portable-atomic` | 1.13.1 | Apache-2.0 OR MIT |
| `postcard` | 1.1.3 | Apache-2.0 OR MIT |
| `powerfmt` | 0.2.0 | Apache-2.0 OR MIT |
| `ppv-lite86` | 0.2.21 | Apache-2.0 OR MIT |
| `primeorder` | 0.13.6 | Apache-2.0 OR MIT |
| `psl` | 2.1.203 | Apache-2.0 OR MIT |
| `psl-types` | 2.0.11 | Apache-2.0 OR MIT |
| `publicsuffix` | 2.3.0 | Apache-2.0 OR MIT |
| `quick-error` | 2.0.1 | Apache-2.0 OR MIT |
| `rama-core` | 0.3.0-alpha.4 | Apache-2.0 OR MIT |
| `rama-dns` | 0.3.0-alpha.4 | Apache-2.0 OR MIT |
| `rama-error` | 0.3.0-alpha.4 | Apache-2.0 OR MIT |
| `rama-http` | 0.3.0-alpha.4 | Apache-2.0 OR MIT |
| `rama-http-backend` | 0.3.0-alpha.4 | Apache-2.0 OR MIT |
| `rama-http-core` | 0.3.0-alpha.4 | Apache-2.0 OR MIT |
| `rama-http-headers` | 0.3.0-alpha.4 | Apache-2.0 OR MIT |
| `rama-http-types` | 0.3.0-alpha.4 | Apache-2.0 OR MIT |
| `rama-net` | 0.3.0-alpha.4 | Apache-2.0 OR MIT |
| `rama-socks5` | 0.3.0-alpha.4 | Apache-2.0 OR MIT |
| `rama-tcp` | 0.3.0-alpha.4 | Apache-2.0 OR MIT |
| `rama-tls-rustls` | 0.3.0-alpha.4 | Apache-2.0 OR MIT |
| `rama-udp` | 0.3.0-alpha.4 | Apache-2.0 OR MIT |
| `rama-unix` | 0.3.0-alpha.4 | Apache-2.0 OR MIT |
| `rama-utils` | 0.3.0-alpha.4 | Apache-2.0 OR MIT |
| `rand` | 0.8.7 | Apache-2.0 OR MIT |
| `rand` | 0.9.3 | Apache-2.0 OR MIT |
| `rand` | 0.10.2 | Apache-2.0 OR MIT |
| `rand_chacha` | 0.3.1 | Apache-2.0 OR MIT |
| `rand_chacha` | 0.9.0 | Apache-2.0 OR MIT |
| `rand_core` | 0.6.4 | Apache-2.0 OR MIT |
| `rand_core` | 0.9.5 | Apache-2.0 OR MIT |
| `rand_core` | 0.10.1 | Apache-2.0 OR MIT |
| `rayon-core` | 1.13.0 | Apache-2.0 OR MIT |
| `rcgen` | 0.14.7 | Apache-2.0 OR MIT |
| `ref-cast` | 1.0.25 | Apache-2.0 OR MIT |
| `regex` | 1.12.3 | Apache-2.0 OR MIT |
| `regex-automata` | 0.4.14 | Apache-2.0 OR MIT |
| `regex-lite` | 0.1.9 | Apache-2.0 OR MIT |
| `regex-syntax` | 0.8.10 | Apache-2.0 OR MIT |
| `reqwest` | 0.12.28 | Apache-2.0 OR MIT |
| `resolv-conf` | 0.7.6 | Apache-2.0 OR MIT |
| `rfc6979` | 0.4.0 | Apache-2.0 OR MIT |
| `rustc-demangle` | 0.1.27 | Apache-2.0 OR MIT |
| `rustc-hash` | 1.1.0 | Apache-2.0 OR MIT |
| `rustc-hash` | 2.1.2 | Apache-2.0 OR MIT |
| `rusticata-macros` | 4.1.0 | Apache-2.0 OR MIT |
| `rustls-pki-types` | 1.14.0 | Apache-2.0 OR MIT |
| `salsa20` | 0.10.2 | Apache-2.0 OR MIT |
| `scopeguard` | 1.2.0 | Apache-2.0 OR MIT |
| `scrypt` | 0.11.0 | Apache-2.0 OR MIT |
| `sec1` | 0.7.3 | Apache-2.0 OR MIT |
| `secrecy` | 0.10.3 | Apache-2.0 OR MIT |
| `security-framework` | 3.7.0 | Apache-2.0 OR MIT |
| `security-framework-sys` | 2.17.0 | Apache-2.0 OR MIT |
| `sequence_trie` | 0.3.6 | Apache-2.0 OR MIT |
| `serde` | 1.0.229 | Apache-2.0 OR MIT |
| `serde_core` | 1.0.229 | Apache-2.0 OR MIT |
| `serde_ignored` | 0.1.14 | Apache-2.0 OR MIT |
| `serde_json` | 1.0.151 | Apache-2.0 OR MIT |
| `serde_path_to_error` | 0.1.20 | Apache-2.0 OR MIT |
| `serde_spanned` | 1.1.1 | Apache-2.0 OR MIT |
| `serde_urlencoded` | 0.7.1 | Apache-2.0 OR MIT |
| `serde_with` | 3.18.0 | Apache-2.0 OR MIT |
| `sha1` | 0.10.6 | Apache-2.0 OR MIT |
| `sha1-checked` | 0.10.0 | Apache-2.0 OR MIT |
| `sha2` | 0.10.9 | Apache-2.0 OR MIT |
| `shell-words` | 1.1.1 | Apache-2.0 OR MIT |
| `shlex` | 1.3.0 | Apache-2.0 OR MIT |
| `signal-hook-registry` | 1.4.8 | Apache-2.0 OR MIT |
| `signature` | 2.2.0 | Apache-2.0 OR MIT |
| `smallvec` | 1.15.1 | Apache-2.0 OR MIT |
| `smol_str` | 0.3.6 | Apache-2.0 OR MIT |
| `socket2` | 0.6.3 | Apache-2.0 OR MIT |
| `sorted_vector_map` | 0.2.1 | Apache-2.0 OR MIT |
| `spki` | 0.7.3 | Apache-2.0 OR MIT |
| `stable_deref_trait` | 1.2.1 | Apache-2.0 OR MIT |
| `static_assertions` | 1.1.0 | Apache-2.0 OR MIT |
| `static_interner` | 0.1.3 | Apache-2.0 OR MIT |
| `strong_hash` | 0.1.0 | Apache-2.0 OR MIT |
| `sys-locale` | 0.3.2 | Apache-2.0 OR MIT |
| `system-configuration` | 0.7.0 | Apache-2.0 OR MIT |
| `system-configuration-sys` | 0.6.0 | Apache-2.0 OR MIT |
| `tagptr` | 0.2.0 | Apache-2.0 OR MIT |
| `tempfile` | 3.27.0 | Apache-2.0 OR MIT |
| `thiserror` | 1.0.69 | Apache-2.0 OR MIT |
| `thiserror` | 2.0.20 | Apache-2.0 OR MIT |
| `thread_local` | 1.1.9 | Apache-2.0 OR MIT |
| `time` | 0.3.47 | Apache-2.0 OR MIT |
| `time-core` | 0.1.8 | Apache-2.0 OR MIT |
| `tiny_http` | 0.12.0 | Apache-2.0 OR MIT |
| `tokio-graceful` | 0.2.2 | Apache-2.0 OR MIT |
| `tokio-rustls` | 0.26.4 | Apache-2.0 OR MIT |
| `toml` | 0.9.12+spec-1.1.0 | Apache-2.0 OR MIT |
| `toml_datetime` | 0.7.5+spec-1.1.0 | Apache-2.0 OR MIT |
| `toml_edit` | 0.24.1+spec-1.1.0 | Apache-2.0 OR MIT |
| `toml_parser` | 1.1.2+spec-1.1.0 | Apache-2.0 OR MIT |
| `toml_writer` | 1.1.1+spec-1.1.0 | Apache-2.0 OR MIT |
| `triomphe` | 0.1.15 | Apache-2.0 OR MIT |
| `tungstenite` (fork: openai-oss-forks/tungstenite-rs at `4fffad30fe37`) | 0.27.0 | Apache-2.0 OR MIT |
| `type-map` | 0.5.1 | Apache-2.0 OR MIT |
| `typeid` | 1.0.3 | Apache-2.0 OR MIT |
| `typenum` | 1.19.0 | Apache-2.0 OR MIT |
| `uname` | 0.1.1 | Apache-2.0 OR MIT |
| `unic-langid` | 0.9.6 | Apache-2.0 OR MIT |
| `unic-langid-impl` | 0.9.6 | Apache-2.0 OR MIT |
| `unicase` | 2.9.0 | Apache-2.0 OR MIT |
| `unicode-normalization` | 0.1.25 | Apache-2.0 OR MIT |
| `unicode-segmentation` | 1.13.2 | Apache-2.0 OR MIT |
| `unicode-width` | 0.1.14 | Apache-2.0 OR MIT |
| `universal-hash` | 0.5.1 | Apache-2.0 OR MIT |
| `url` | 2.5.8 | Apache-2.0 OR MIT |
| `utf-8` | 0.7.6 | Apache-2.0 OR MIT |
| `utf8_iter` | 1.0.4 | Apache-2.0 OR MIT |
| `utf8parse` | 0.2.2 | Apache-2.0 OR MIT |
| `uuid` | 1.23.0 | Apache-2.0 OR MIT |
| `webbrowser` | 1.2.0 | Apache-2.0 OR MIT |
| `weezl` | 0.1.12 | Apache-2.0 OR MIT |
| `x509-parser` | 0.18.1 | Apache-2.0 OR MIT |
| `xmlparser` | 0.13.6 | Apache-2.0 OR MIT |
| `yasna` | 0.5.2 | Apache-2.0 OR MIT |
| `zeroize` | 1.8.2 | Apache-2.0 OR MIT |
| `zstd-safe` | 7.2.4 | Apache-2.0 OR MIT |
| `zstd-sys` | 2.0.16+zstd.1.5.7 | Apache-2.0 OR MIT |
| `base64-simd` | 0.8.0 | MIT |
| `bech32` | 0.9.1 | MIT |
| `block2` | 0.6.2 | MIT |
| `bytes` | 1.11.1 | MIT |
| `clru` | 0.6.3 | MIT |
| `color_quant` | 1.1.0 | MIT |
| `cookie-factory` | 0.3.3 | MIT |
| `dashmap` | 6.2.1 | MIT |
| `data-encoding` | 2.10.0 | MIT |
| `debugserver-types` | 0.5.0 | MIT |
| `derive_more` | 1.0.0 | MIT |
| `endian-type` | 0.1.2 | MIT |
| `endian-type` | 0.2.0 | MIT |
| `fancy-regex` | 0.16.2 | MIT |
| `faster-hex` | 0.10.0 | MIT |
| `filedescriptor` | 0.8.3 | MIT |
| `fluent-uri` | 0.1.4 | MIT |
| `generic-array` | 0.14.7 | MIT |
| `h2` | 0.4.13 | MIT |
| `headers` | 0.4.1 | MIT |
| `headers-core` | 0.3.0 | MIT |
| `hostname` | 0.4.2 | MIT |
| `http-body` | 0.4.6 | MIT |
| `http-body` | 1.0.1 | MIT |
| `http-body-util` | 0.1.3 | MIT |
| `http-range-header` | 0.4.2 | MIT |
| `hyper` | 1.9.0 | MIT |
| `hyper-util` | 0.1.20 | MIT |
| `i18n-embed` | 0.15.4 | MIT |
| `jsonwebtoken` | 9.3.1 | MIT |
| `lru` | 0.16.3 | MIT |
| `lsp-types` | 0.97.0 | MIT |
| `memoffset` | 0.9.1 | MIT |
| `mime_guess` | 2.0.5 | MIT |
| `mio` | 1.2.0 | MIT |
| `nibble_vec` | 0.1.0 | MIT |
| `nix` | 0.28.0 | MIT |
| `nix` | 0.30.1 | MIT |
| `nom` | 7.1.3 | MIT |
| `nom` | 8.0.0 | MIT |
| `nonempty` | 0.12.0 | MIT |
| `nu-ansi-term` | 0.50.3 | MIT |
| `objc2` | 0.6.4 | MIT |
| `objc2-encode` | 4.1.0 | MIT |
| `objc2-foundation` | 0.3.2 | MIT |
| `os_info` | 3.14.0 | MIT |
| `outref` | 0.5.2 | MIT |
| `pem` | 3.0.6 | MIT |
| `portable-pty` | 0.9.0 | MIT |
| `prodash` | 31.0.0 | MIT |
| `quick-xml` | 0.41.0 | MIT |
| `radix_trie` | 0.2.1 | MIT |
| `radix_trie` | 0.3.0 | MIT |
| `rust-embed` | 8.11.0 | MIT |
| `rust-embed-utils` | 8.11.0 | MIT |
| `rustyline` | 14.0.0 | MIT |
| `schemars` | 0.8.22 | MIT |
| `sentry` | 0.46.2 | MIT |
| `sentry-backtrace` | 0.46.2 | MIT |
| `sentry-contexts` | 0.46.2 | MIT |
| `sentry-core` | 0.46.2 | MIT |
| `sentry-debug-images` | 0.46.2 | MIT |
| `sentry-panic` | 0.46.2 | MIT |
| `sentry-types` | 0.46.2 | MIT |
| `serde_html_form` | 0.3.2 | MIT |
| `sharded-slab` | 0.1.7 | MIT |
| `simd-adler32` | 0.3.9 | MIT |
| `slab` | 0.4.12 | MIT |
| `spin` | 0.9.8 | MIT |
| `strsim` | 0.10.0 | MIT |
| `strsim` | 0.11.1 | MIT |
| `strum` | 0.27.2 | MIT |
| `take_mut` | 0.2.2 | MIT |
| `textwrap` | 0.11.0 | MIT |
| `tokio` | 1.53.1 | MIT |
| `tokio-native-tls` | 0.3.1 | MIT |
| `tokio-stream` | 0.1.18 | MIT |
| `tokio-test` | 0.4.5 | MIT |
| `tokio-tungstenite` (fork: openai-oss-forks/tokio-tungstenite at `0e5b2d73aa18`) | 0.28.0 | MIT |
| `tokio-util` | 0.7.18 | MIT |
| `tonic` | 0.14.5 | MIT |
| `tonic-prost` | 0.14.5 | MIT |
| `tower` | 0.5.3 | MIT |
| `tower-http` | 0.6.8 | MIT |
| `tower-layer` | 0.3.3 | MIT |
| `tower-service` | 0.3.3 | MIT |
| `tracing` | 0.1.44 | MIT |
| `tracing-core` | 0.1.36 | MIT |
| `tracing-log` | 0.2.0 | MIT |
| `tracing-opentelemetry` | 0.32.1 | MIT |
| `tracing-subscriber` | 0.3.23 | MIT |
| `try-lock` | 0.2.5 | MIT |
| `ts-rs` | 11.1.0 | MIT |
| `urlencoding` | 2.1.3 | MIT |
| `vsimd` | 0.8.0 | MIT |
| `want` | 0.3.1 | MIT |
| `wildmatch` | 2.6.1 | MIT |
| `winnow` | 0.7.15 | MIT |
| `winnow` | 1.0.1 | MIT |
| `zmij` | 1.0.21 | MIT |
| `zstd` | 0.13.3 | MIT |
| `allocative` | 0.3.6 | Apache-2.0 |
| `aws-config` | 1.8.15 | Apache-2.0 |
| `aws-credential-types` | 1.3.0 | Apache-2.0 |
| `aws-runtime` | 1.7.2 | Apache-2.0 |
| `aws-sdk-signin` | 1.8.0 | Apache-2.0 |
| `aws-sdk-sso` | 1.97.0 | Apache-2.0 |
| `aws-sdk-ssooidc` | 1.99.0 | Apache-2.0 |
| `aws-sdk-sts` | 1.102.0 | Apache-2.0 |
| `aws-sigv4` | 1.4.2 | Apache-2.0 |
| `aws-smithy-async` | 1.3.0 | Apache-2.0 |
| `aws-smithy-http` | 0.63.6 | Apache-2.0 |
| `aws-smithy-http` | 0.64.0 | Apache-2.0 |
| `aws-smithy-http-client` | 1.2.0 | Apache-2.0 |
| `aws-smithy-json` | 0.62.7 | Apache-2.0 |
| `aws-smithy-observability` | 0.2.6 | Apache-2.0 |
| `aws-smithy-observability` | 0.3.0 | Apache-2.0 |
| `aws-smithy-query` | 0.60.15 | Apache-2.0 |
| `aws-smithy-runtime` | 1.12.1 | Apache-2.0 |
| `aws-smithy-runtime-api` | 1.14.0 | Apache-2.0 |
| `aws-smithy-schema` | 0.1.0 | Apache-2.0 |
| `aws-smithy-schema` | 0.2.0 | Apache-2.0 |
| `aws-smithy-types` | 1.6.1 | Apache-2.0 |
| `aws-smithy-xml` | 0.60.15 | Apache-2.0 |
| `aws-types` | 1.5.0 | Apache-2.0 |
| `debugid` | 0.8.0 | Apache-2.0 |
| `gethostname` | 1.1.0 | Apache-2.0 |
| `opentelemetry` | 0.31.0 | Apache-2.0 |
| `opentelemetry-appender-tracing` | 0.31.1 | Apache-2.0 |
| `opentelemetry-http` | 0.31.0 | Apache-2.0 |
| `opentelemetry-otlp` | 0.31.1 | Apache-2.0 |
| `opentelemetry-proto` | 0.31.0 | Apache-2.0 |
| `opentelemetry-semantic-conventions` | 0.31.0 | Apache-2.0 |
| `opentelemetry_sdk` | 0.31.0 | Apache-2.0 |
| `pagable` | 0.4.2 | Apache-2.0 |
| `prost` | 0.14.3 | Apache-2.0 |
| `self_cell` | 0.10.3 | Apache-2.0 |
| `similar` | 2.7.0 | Apache-2.0 |
| `starlark` | 0.14.2 | Apache-2.0 |
| `starlark_map` | 0.14.2 | Apache-2.0 |
| `starlark_syntax` | 0.14.2 | Apache-2.0 |
| `sync_wrapper` | 1.0.2 | Apache-2.0 |
| `unicode-bom` | 2.0.3 | Apache-2.0 |
| `wildcard` | 0.3.0 | Apache-2.0 |
| `fixed_decimal` | 0.7.2 | Unicode-3.0 |
| `icu_collections` | 2.2.0 | Unicode-3.0 |
| `icu_decimal` | 2.2.0 | Unicode-3.0 |
| `icu_decimal_data` | 2.2.0 | Unicode-3.0 |
| `icu_locale` | 2.2.0 | Unicode-3.0 |
| `icu_locale_core` | 2.2.0 | Unicode-3.0 |
| `icu_locale_data` | 2.2.0 | Unicode-3.0 |
| `icu_normalizer` | 2.2.0 | Unicode-3.0 |
| `icu_normalizer_data` | 2.2.0 | Unicode-3.0 |
| `icu_properties` | 2.2.0 | Unicode-3.0 |
| `icu_properties_data` | 2.2.0 | Unicode-3.0 |
| `icu_provider` | 2.2.0 | Unicode-3.0 |
| `litemap` | 0.8.2 | Unicode-3.0 |
| `potential_utf` | 0.1.5 | Unicode-3.0 |
| `tinystr` | 0.8.3 | Unicode-3.0 |
| `writeable` | 0.6.3 | Unicode-3.0 |
| `yoke` | 0.8.2 | Unicode-3.0 |
| `zerofrom` | 0.1.7 | Unicode-3.0 |
| `zerotrie` | 0.2.4 | Unicode-3.0 |
| `zerovec` | 0.11.6 | Unicode-3.0 |
| `aho-corasick` | 1.1.4 | MIT OR Unlicense |
| `byteorder` | 1.5.0 | MIT OR Unlicense |
| `byteorder-lite` | 0.1.0 | MIT OR Unlicense |
| `csv` | 1.4.0 | MIT OR Unlicense |
| `csv-core` | 0.1.13 | MIT OR Unlicense |
| `globset` | 0.4.18 | MIT OR Unlicense |
| `jiff` | 0.2.28 | MIT OR Unlicense |
| `memchr` | 2.8.0 | MIT OR Unlicense |
| `quickcheck` | 1.1.0 | MIT OR Unlicense |
| `same-file` | 1.0.6 | MIT OR Unlicense |
| `walkdir` | 2.5.0 | MIT OR Unlicense |
| `bytemuck` | 1.25.0 | Apache-2.0 OR MIT OR Zlib |
| `miniz_oxide` | 0.8.9 | Apache-2.0 OR MIT OR Zlib |
| `objc2-core-foundation` | 0.3.2 | Apache-2.0 OR MIT OR Zlib |
| `tinyvec` | 1.11.0 | Apache-2.0 OR MIT OR Zlib |
| `tinyvec_macros` | 0.1.1 | Apache-2.0 OR MIT OR Zlib |
| `zune-core` | 0.5.1 | Apache-2.0 OR MIT OR Zlib |
| `zune-jpeg` | 0.5.15 | Apache-2.0 OR MIT OR Zlib |
| `curve25519-dalek` | 4.1.3 | BSD-3-Clause |
| `ed25519-dalek` | 2.2.0 | BSD-3-Clause |
| `subtle` | 2.6.1 | BSD-3-Clause |
| `x25519-dalek` | 2.0.1 | BSD-3-Clause |
| `rustls-webpki` | 0.103.11 | ISC |
| `simple_asn1` | 0.6.4 | ISC |
| `untrusted` | 0.7.1 | ISC |
| `untrusted` | 0.9.0 | ISC |
| `hyper-rustls` | 0.27.7 | Apache-2.0 OR ISC OR MIT |
| `rustls` | 0.23.37 | Apache-2.0 OR ISC OR MIT |
| `rustls-native-certs` | 0.8.3 | Apache-2.0 OR ISC OR MIT |
| `const_format` | 0.2.35 | Zlib |
| `foldhash` | 0.2.0 | Zlib |
| `zlib-rs` | 0.6.3 | Zlib |
| `moxcms` | 0.8.1 | Apache-2.0 OR BSD-3-Clause |
| `pxfm` | 0.1.28 | Apache-2.0 OR BSD-3-Clause |
| `constant_time_eq` | 0.3.1 | Apache-2.0 OR CC0-1.0 OR MIT-0 |
| `dunce` | 1.0.5 | Apache-2.0 OR CC0-1.0 OR MIT-0 |
| `encoding_rs` | 0.8.35 | (Apache-2.0 OR MIT) AND BSD-3-Clause |
| `moka` | 0.12.15 | (MIT OR Apache-2.0) AND Apache-2.0 |
| `adler2` | 2.0.1 | 0BSD OR Apache-2.0 OR MIT |
| `ring` | 0.17.14 | Apache-2.0 AND ISC |
| `serial2` | 0.2.38 | Apache-2.0 OR BSD-2-Clause |
| `zerocopy` | 0.8.48 | Apache-2.0 OR BSD-2-Clause OR MIT |
| `ryu` | 1.0.23 | Apache-2.0 OR BSL-1.0 |
| `self_cell` | 1.3.0 | Apache-2.0 OR GPL-2.0-only |
| `rustix` | 1.1.4 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT |
| `arrayref` | 0.3.9 | BSD-2-Clause |
| `blake3` | 1.8.2 | CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception |
| `webpki-roots` | 1.0.6 | CDLA-Permissive-2.0 |
| `aws-lc-rs` | 1.16.2 | ISC AND (Apache-2.0 OR ISC) |
| `aws-lc-sys` | 0.39.1 | ISC AND (Apache-2.0 OR ISC) AND Apache-2.0 AND MIT AND BSD-3-Clause AND (Apache-2.0 OR ISC OR MIT) AND (Apache-2.0 OR ISC OR MIT-0) |
| `matchit` | 0.9.2 | MIT AND BSD-3-Clause |
| `option-ext` | 0.2.0 | MPL-2.0 |

### Rust standard library

The helper also links the Rust standard library of the toolchain used to build it. The
standard library is licensed under Apache-2.0 OR MIT, with the exceptions listed in the
toolchain's `COPYRIGHT-library.html` (for example, `library/core/src/unicode` is under
Unicode-3.0).

## Keeping this page current

Regenerate the helper inventory whenever `Helper/CodexexHelper/Cargo.lock` changes, and
check any new licence or `NOTICE` file before the next release. This page reflects
`Cargo.lock` as last changed in commit `fca7629`.
