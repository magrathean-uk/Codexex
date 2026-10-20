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

<!-- clean-development-policy:v2 (canonical text: ~/dev/source/dev-bootstrap/snippets/clean-development-policy.md) -->
## Clean development (mandatory)

This project follows [Clean Development](https://github.com/magrathean-uk/clean-development) and the machine rule that nothing creates tool state under `~` (only the allow-listed agent homes).

- Load `~/dev/machine/env.zsh`; `~/.zshenv` does this for every zsh. Machine storage preferences live in `~/dev/machine/storage.conf`; workspace navigation is in `~/dev/START-HERE.md`.
- New sessions select `/Volumes/4TB/machine/cache` when the configured volume is actually mounted and writable, otherwise `~/dev/machine/cache` for ordinary smaller work. Use routed `DEVCACHE`, `CLEAN_DEVELOPMENT_{ROOT,CACHE_ROOT,BUILD_ROOT,SCRATCH_ROOT}`, `BOLYKI_DEV_LIBS` and `TMPDIR`; builds and scratch are beneath the selected cache. Keep active-session destinations fixed; stop if required storage disappears. Other users configure their own volume and fallback.
- SpecieX, large video/model jobs and VMs require external storage; never use internal fallback. Persistent labs, credentials, installed toolchains, source and final deliverables are not disposable caches.
- All active Git entry points belong under `~/dev/source/`, third-party repositories in `source/third-party/`, websites in `source/magrathean/`, and Teslatlas products/docs in `source/teslatlas-service/`. Do not read, scan, move or edit `~/dev/porn`.
- Preserve routed tool homes/caches, caller overrides and SDK/toolchain choices. Never unset or bypass routing. Scrubbed environments must restore the reviewed routing before cache-writing tools run; preserve intentional hermetic Git/Cargo isolation.
- Run builds, tests, installs and anything else that writes caches or build output through Clean Development: `clean-development run --session session-only -- <command>`. Follow its docs and keep its receipts.
- Do not add installers or scripts that default into `~` (`~/.cargo`, `~/.rustup`, `~/.cache`, `~/.npm`, `~/.swiftpm`, `~/.gradle`, ...) and do not hardcode `$HOME` paths for caches; use the routed variables.
- Before finishing, run `dev-env-check`, `dev-projects-check` and `dev-audit`; require passing environment/project checks and no new home-audit entries compared with the task baseline. Fix violations your work caused.

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
