# AGENTS.md

Current release: `6.1.0` (`24`) for macOS and iOS/iPadOS.

Read task-relevant guidance: `README.md` for the repository overview; `RUNBOOK.md` and `Scripts/release-smoke.sh` for release work; `project.yml` for Xcode structure; `Package.swift` for package changes.

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
- No project-local Codex hook is installed. Do not add one for generated Xcode files; edit `project.yml` and regenerate instead.

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

Local disposable tests may be run and repaired within the requested task without repeated approval. Keep release, signing, production access and existing owner holds under their documented authority.

## Working guidance — GPT-6 Astra

Based on [OpenAI's Astra prompting guidance](https://developers.openai.com/api/docs/guides/latest-model#prompting-best-practices), reviewed 2026-09-19. These are working instructions, not a change to model or API settings.

- Complete the authorized task through implementation and relevant verification. Make routine choices yourself; ask only when a missing decision materially changes the result or requires new authority. Prepare reviewable work before requesting any necessary final approval.
- Current user instructions take precedence over repository and skill guidance within system and tool constraints. Preserve explicit exclusions and owner holds. Historical plans and session notes do not grant current authorization. If a file or skill blocks progress, identify its exact path and rule.
- Keep changes small and practical. Inspect current source and Git status, preserve unrelated work, and use existing conventions. Do not add speculative abstractions, dependencies, or unrelated cleanup. Commit, push, deploy, install, and live-service changes require authorization for that action.
- Use the reasoning effort the task needs. Follow explicit project delegation rules; otherwise use subagents only when requested, with bounded independent tasks and distinct file ownership. Batch independent reads; serialize dependent operations and conflicting edits.
- Run meaningful checks for the changed behavior and required project gates. Avoid tests that merely repeat low-impact edits. Broaden or repeat verification only after changes, failures, or unresolved concerns. Distinguish local checks from device, browser, and live-service evidence.
- Write concise, plain, outcome-first updates. State what changed, why, verification, and material gaps. Avoid filler and unnecessary formatting.
- Keep durable instructions in AGENTS.md and maintained product documentation. Do not create duplicate assistant instruction files or disposable plans, transcripts, status reports, and screenshots in source directories unless requested. Preserve source, tests, fixtures, assets, licences, and operational evidence regardless of who created them.
