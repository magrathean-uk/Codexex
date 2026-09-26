# Codexex contributor guidance

Read the task-relevant product document before changing code: `README.md` for
the product and layout, `RUNBOOK.md` and `Scripts/release-smoke.sh` for release
work, `project.yml` for Xcode targets, and `Package.swift` for Swift package
work.

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

`project.yml` is the Xcode source of truth. Do not edit
`CodexMeter.xcodeproj` directly. After changing `project.yml`, run
`xcodegen generate --spec project.yml`.

No project-local Codex hook is installed. Do not add one for generated Xcode
files. Use normal local implementation and verification steps within the task
scope. Commit, push, deploy, sign, release, or change a live service when the
current task authorizes it.

The Matrix prototype has its own guidance in `Prototypes/MatrixQuota/AGENTS.md`.

## Validation

Run commands from the repository root. Xcode commands use local temporary
caches so they do not rely on parent-directory scripts.

```bash
swift test
cargo test --manifest-path Helper/CodexexHelper/Cargo.toml
xcodegen generate --spec project.yml
xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeterApp \
  -derivedDataPath /tmp/codexex-derived-data \
  -clonedSourcePackagesDirPath /tmp/codexex-swiftpm-cache test
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
