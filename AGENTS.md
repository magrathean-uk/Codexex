# AGENTS.md

Read in this order:

- [Root AGENTS](/Users/bolyki/dev/source/AGENTS.md)
- [Agent index](/Users/bolyki/dev/source/AGENT_INDEX.md)
- [README](./README.md)
- [RUNBOOK](./RUNBOOK.md)
- `project.yml`
- `Package.swift`

Rules:

- Source `/Users/bolyki/dev/source/build-env.sh` before local build, test, or packaging work.
- `project.yml` is the Xcode source of truth. Regenerate `CodexMeter.xcodeproj`; do not hand-edit it.
- Keep core quota parsing and contracts in `Sources/CodexMeterCore/`.
- Keep menu bar UI, onboarding, settings, and history state in `Sources/CodexMeterApp/`.
- Keep helper auth and quota work in `Helper/CodexexHelper/`; keep sandbox bridge work in `Sources/CodexexXPCService/`.
- Do not add browser scraping, private APIs, cookie theft, or alternate auth flows.
- Keep release text in `fastlane/metadata/` and privacy text in `PRIVACY.md`; do not grow extra review-note markdown.
