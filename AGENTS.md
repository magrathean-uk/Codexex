# Repository Guidelines

## Project Structure & Module Organization

This is a Swift 6 package for a macOS 26+ menu bar app.

- `Package.swift` is the source of truth for targets and platforms.
- `project.yml` generates the checked-in Xcode project.
- `CodexMeter.xcodeproj/` is the Xcode project generated from `project.yml`.
- `Sources/CodexMeterCore/` contains the core logic: Codex probing, binary discovery, models, and formatting.
- `Sources/CodexMeterApp/` contains the SwiftUI menu bar app, views, and app entry point.
- `Tests/CodexMeterCoreTests/` contains XCTest coverage for core behavior.

Keep UI code in the app target and parsing or state logic in `CodexMeterCore`.

## Build, Test, and Development Commands

- `source ../build-env.sh` before `swift build`, `swift test`, or `swift run` so builds use the shared caches.
- `swift build` builds the package.
- `swift test` runs the XCTest suite.
- `xcodegen generate` regenerates `CodexMeter.xcodeproj` from `project.yml`.
- `xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeterApp -derivedDataPath "$XCODE_DERIVED_DATA_PATH" -clonedSourcePackagesDirPath "$SWIFTPM_SHARED_CACHE" build` builds the Xcode project.
- `swift run CodexMeterApp` launches the app from the command line on macOS.
- `open CodexMeter.xcodeproj` opens the project in Xcode.

## Coding Style & Naming Conventions

- Use Swift’s standard formatting: 4-space indentation, one declaration per file when practical, and `final` for non-inheritable classes.
- Prefer descriptive type names and feature-based filenames, such as `CodexBinaryLocator.swift` or `PopupRootView.swift`.
- Keep test method names in the `test...` form, e.g. `testCompactDuration()`.
- Avoid hand-editing generated artifacts; update the source of truth instead.

## Testing Guidelines

This repository uses XCTest. Add unit tests under `Tests/CodexMeterCoreTests/` for parsing, formatting, and binary-resolution behavior.

- Name tests after the behavior being verified.
- Prefer small, deterministic tests with explicit inputs and outputs.
- Run `swift test` before sharing changes that touch core logic.

## Commit & Pull Request Guidelines

This checkout does not include local git history, so there is no repository-specific commit log to summarize here. Use short, imperative commit subjects such as `Fix bucket parsing` or `Add reset-time formatting`.

Pull requests should include:

- A clear summary of the change and why it exists.
- Notes on behavior changes or limitations.
- Screenshots or screen recordings for UI changes.
- Links to any related issue or follow-up work.

## Security & Configuration Tips

- The app reads Codex state through the official `codex app-server` interface only.
- Do not add alternate login flows, browser scraping, or token parsing.
- Keep binary-discovery changes aligned with `CODEXMETER_CODEX_PATH` and the documented search order in `README.md`.
