# Contributing to Codexex

Codexex is proprietary software. Read [LICENSE](LICENSE) before copying, modifying, or distributing it. Public repository access does not create a contribution or redistribution licence. Discuss work outside an existing agreement through the contact in [SUPPORT.md](SUPPORT.md).

## Working on an authorised change

Keep changes focused and preserve unrelated work. Use the ownership map and project rules in [AGENTS.md](AGENTS.md). Keep generated Xcode configuration in sync by editing `project.yml` and running `xcodegen generate --spec project.yml`.

Build prerequisites, commands, helper packaging, and manual checks are documented in [RUNBOOK.md](RUNBOOK.md). Start with the checks for the code you changed:

| Change | Checks |
| --- | --- |
| Core parsing or formatting | `swift test` |
| macOS UI, settings, or XPC | `CodexMeterApp` Xcode scheme tests and the relevant manual flow |
| iOS UI, authentication, or Live Activity | `CodexMeteriOS` Xcode scheme tests and simulator or device checks appropriate to the change |
| Rust authentication or quota helper | `cargo test --manifest-path Helper/CodexexHelper/Cargo.toml` |
| Companion scripts | `bash Scripts/check-codexex-companions.sh` |
| Release or helper packaging | `bash Scripts/release-smoke.sh` and the runbook's review smoke path |
| MatrixQuota prototype | Scoped guidance in [Prototypes/MatrixQuota/AGENTS.md](Prototypes/MatrixQuota/AGENTS.md) |

## Review information

Explain the problem, resulting behavior, and checks performed. Name blockers and distinguish automated checks from visual or device evidence. Include redacted screenshots for visual changes when useful. Keep release copy in `fastlane/metadata/` and privacy copy in `PRIVACY.md`.

Do not include credentials, account details, private session logs, signing material, or local machine paths in a report. Keep diagnostics local. Report suspected vulnerabilities through [SECURITY.md](SECURITY.md).

Preserve third-party notices and the project's licence terms. Do not add dependencies or change licensing, sign-in flows, telemetry, or release infrastructure as incidental cleanup.
