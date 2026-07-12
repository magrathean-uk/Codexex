# AGENTS.md

Current release: `5.1` (`14`) for macOS and iOS/iPadOS.

Read in this order:

- [README](./README.md)
- [RUNBOOK](./RUNBOOK.md)
- `project.yml`
- `Package.swift`
- `Scripts/release-smoke.sh`

Older prompts may mention `/Users/bolyki/dev/source/AGENTS.md` and
`/Users/bolyki/dev/source/AGENT_INDEX.md`. They are not present in this
checkout; do not stop for them. If they appear later, read them before this
file and follow the closest AGENTS.md when rules conflict.

Rules:

- Build, test, and packaging commands must be self-contained in this checkout. Do not depend on parent-directory environment scripts.
- `project.yml` is the Xcode source of truth. Regenerate `CodexMeter.xcodeproj`; do not hand-edit it.
- Keep core quota parsing and contracts in `Sources/CodexMeterCore/`.
- Keep macOS menu bar UI, onboarding, settings, and history state in `Sources/CodexMeterApp/`.
- Keep the iPhone/iPad companion in `Sources/CodexMeteriOS/`; shared quota and formatting contracts stay in core.
- Keep helper auth and quota work in `Helper/CodexexHelper/`; keep sandbox bridge work in `Sources/CodexexXPCService/`.
- Do not add browser scraping, private APIs, cookie theft, or alternate auth flows.
- Keep release text in `fastlane/metadata/` and privacy text in `PRIVACY.md`; do not grow extra review-note markdown.
- For Figma-driven UI work: use SwiftUI only, use project tokens/components, do not paste Tailwind styles, fetch Figma context and a screenshot before implementation, and reuse provided Figma assets when present.
- Do not edit `CodexMeter.xcodeproj` directly; update `project.yml` and run `xcodegen generate --spec project.yml`.
- `.codex/hooks.json` is the checked-in project hook surface. It receives Codex hook JSON on stdin and blocks direct `apply_patch` edits under `.xcodeproj/`. Review changed project hooks with `/hooks` before expecting them to run.

## Commands

Run from repo root unless noted. Use explicit local cache paths when Xcode needs them:

- Swift package tests: `swift test`
- Helper tests: `cargo test --manifest-path Helper/CodexexHelper/Cargo.toml`
- Regenerate project: `xcodegen generate --spec project.yml`
- macOS app tests: `xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeterApp -derivedDataPath /tmp/codexex-derived-data -clonedSourcePackagesDirPath /tmp/codexex-swiftpm-cache test`
- Release smoke: `bash Scripts/release-smoke.sh`
- Companion script smoke: `bash Scripts/check-codexex-companions.sh`

No SwiftLint, SwiftFormat config, Makefile, Justfile, or CI workflow was found in this checkout. Builds, tests, and the release smoke script are the project gates.

## Done when

- The change is scoped to the right owner directory above.
- Relevant tests or smoke scripts ran, or the blocker is named.
- `project.yml` changes are followed by project regeneration.
- Release-facing text stays in `fastlane/metadata/` or `PRIVACY.md`.
- Final notes include verification, result, blockers, and any risky unknowns.

## Telemetry

- Do not add Sentry or external crash telemetry. Keep diagnostics local unless a repo runbook says otherwise.
