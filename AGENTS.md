# Codexex contributor guidance

Read the task-relevant product document before changing code: `README.md` for
the product and layout, `docs/development/runbook.md` and
`Scripts/release-smoke.sh` for release work, `project.yml` for Xcode targets,
and `Package.swift` for Swift package work.

## Boundaries

- Keep quota models, parsing, formatting, and shared contracts in
  `Sources/CodexMeterCore/`.
- Keep the macOS menu bar app, onboarding, settings, and local history UI in
  `Sources/CodexMeterApp/`.
- Keep the iPhone and iPad companion in `Sources/CodexMeteriOS/`. Shared quota
  contracts belong in core.
- Keep device authentication and quota helper work in `Helper/CodexexHelper/`.
  Keep the sandbox bridge in `Sources/CodexexXPCService/`.
- Do not add browser scraping, private APIs, cookie access, or an alternate
  authentication flow.
- Keep release metadata in `fastlane/metadata/` and privacy copy in
  `PRIVACY.md`.
- Legal files (`LICENSE`, `NOTICE`, `docs/legal/`, contributor terms, copyright and
  attribution strings) are owner-controlled: change them only on the owner's explicit
  instruction.

`project.yml` is the Xcode source of truth. Do not edit
`CodexMeter.xcodeproj` directly. After changing `project.yml`, run
`xcodegen generate --spec project.yml`.

No project-local Codex hook is installed. Do not add one for generated Xcode
files. Use normal local implementation and verification steps within the task
scope. Commit, push, deploy, sign, release, or change a live service when the
current task authorizes it.

The Matrix prototype has its own guidance in `Prototypes/MatrixQuota/AGENTS.md`.

<!-- clean-development-policy:v1 (canonical text: ~/dev/source/dev-bootstrap/snippets/clean-development-policy.md) -->
## Clean development (mandatory)

This project follows [Clean Development](https://github.com/magrathean-uk/clean-development) and the machine rule that nothing creates tool state under `~` (only the allow-listed agent homes).

- The shell environment comes from `~/.zshenv`, which loads `~/dev/env.zsh`. It routes every tool home and cache (`CARGO_HOME`, `RUSTUP_HOME`, `XDG_*`, `BUNDLE_USER_HOME`, `npm_config_cache`, `XCODE_DERIVED_DATA_PATH`, ...) and switches telemetry off. Never unset, override or bypass those variables. If a script needs a scrubbed environment, re-export them with `source ~/dev/env.zsh`.
- Run builds, tests, installs and anything else that writes caches or build output through Clean Development: `clean-development run --session session-only -- <command>`. Follow its docs and keep its receipts.
- Do not add installers or scripts that default into `~` (`~/.cargo`, `~/.rustup`, `~/.cache`, `~/.npm`, `~/.swiftpm`, `~/.gradle`, ...) and do not hardcode `$HOME` paths for caches; use the routed variables.
- Before finishing, run `dev-env-check` (must pass) and `dev-audit` (no new entries in `~`). If your work caused a violation, fix the cause in the repo and say so.

## Validation

Run commands from the repository root, through Clean Development as described
above. Xcode commands take their derived-data and SwiftPM cache locations from
the routed `XCODE_DERIVED_DATA_PATH` and `SWIFTPM_SHARED_CACHE` variables and
fall back to `/tmp` only when those are unset.

```bash
swift test
cargo test --manifest-path Helper/CodexexHelper/Cargo.toml
xcodegen generate --spec project.yml
xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeterApp \
  -derivedDataPath "${XCODE_DERIVED_DATA_PATH:-/tmp}/codexex-derived-data" \
  -clonedSourcePackagesDirPath "${SWIFTPM_SHARED_CACHE:-/tmp}/codexex-swiftpm-cache" test
bash Scripts/check-codexex-companions.sh
bash Scripts/release-smoke.sh
```

Use the smallest relevant check first. The repository also has the
`.github/workflows/cargo-deny.yml` workflow for Rust dependency licence, source,
and ban checks. Do not claim device, APNs, deployment, signing, or App Store
acceptance from local tests alone.

## Working practice

Preserve unrelated edits. Keep changes small and within the owning boundary.
Complete authorized local work and its necessary checks without repeated
permission requests. Use bounded delegation for independent work when the
benefit exceeds the overhead; keep file ownership distinct.
Use SwiftUI and existing project tokens/components for native app UI. For a
Figma-driven native-app change, obtain the supplied context and screenshot
before implementation, and reuse supplied assets. Do not add external crash
telemetry; diagnostics stay local unless product documentation says otherwise.
