# Codexex contributor guidance

Purpose: Codexex is an Apple-platform app for tracking Codex usage quota (Swift package plus Xcode project from `project.yml`), with a React prototype under `Prototypes/MatrixQuota`.

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

## Models

Claude Code (Fable, or Opus 5.5, for cross-cutting work and review; Sonnet 5.5 for routine implementation; Haiku 5.5 for exploration) or Codex `gpt-6.1-sol` (`gpt-6-luna` for swarm exploration). Keep changes small; distinguish local checks from device and live-service evidence.

<!-- clean-development-policy:v4 (clean-development 0.6.0; canonical: bolyki-dev/clean-development/docs/policy-snippet.md) -->
## Clean development (mandatory)

- Storage is routed for you: every zsh loads `~/dev/machine/env.zsh`; hooks pin the mode per session (`$CLEAN_DEV_MODE` is `external` when the 4TB is attached, else `internal`). Do not wrap commands, override or unset the routed variables.
- Temp files go to `$TMPDIR` (session scratch, deleted at session end), throwaway build output to `$CLEAN_DEV_BUILDS`, caches wherever their variables point. Never write caches, builds or temp files into `~`, `~/dev` or this repo outside its git-ignored build directories.
- Internal mode: before any download or build likely over 5 GB, stop and ask G (suggest waiting for the 4TB).
- This repo's `.clean-development.json` (schema v2) lists its git-ignored `buildDirs`/`depDirs`; keep it accurate when the build layout changes.
- No dot-folders in `~` or `~/dev`. `.env` files stay git-ignored; read them only when the task needs them; never commit them.

## Validation

Run commands from the repository root, through Clean Development as described
above. Xcode commands take their derived-data and SwiftPM cache locations from
the routed `XCODE_DERIVED_DATA_PATH` and `SWIFTPM_SHARED_CACHE` variables.
Load `~/dev/machine/env.zsh` first; missing routing is an error rather than a `/tmp` fallback.

```bash
source "$HOME/dev/machine/env.zsh"
swift test
cargo test --manifest-path Helper/CodexexHelper/Cargo.toml
xcodegen generate --spec project.yml
xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeterApp \
  -derivedDataPath "${XCODE_DERIVED_DATA_PATH:?Load ~/dev/machine/env.zsh}/codexex-derived-data" \
  -clonedSourcePackagesDirPath "${SWIFTPM_SHARED_CACHE:?Load ~/dev/machine/env.zsh}/codexex-swiftpm-cache" test
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

## Pending URL migration

The next release must apply [NEXT-RELEASE-URLS.md](NEXT-RELEASE-URLS.md): product sites moved to `https://magrathean.uk/solutions/<slug>/` and support addresses to `contact+<slug>@magrathean.uk`. Remove this section with that file once released.
