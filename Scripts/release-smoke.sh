#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  echo "release-smoke: $*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing required file: $1"
}

require_text() {
  local needle="$1"
  local file="$2"
  grep -Fq "$needle" "$file" || fail "expected '$needle' in $file"
}

require_count() {
  local needle="$1"
  local expected="$2"
  local file="$3"
  local actual
  actual="$(grep -Foc -- "$needle" "$file" || true)"
  [[ "$actual" == "$expected" ]] || fail "expected '$needle' $expected time(s) in $file, found $actual"
}

require_file project.yml
require_file AppStore/Codexex.entitlements
require_file AppStore/CodexexHelper.entitlements
require_file AppStore/CodexexXPCService.entitlements
require_file Scripts/build-codexex-helper.sh
require_file Scripts/embed-codexex-helper.sh
require_file Scripts/check-codexex-companions.sh
require_file Helper/CodexexHelper/Cargo.toml
require_file Helper/CodexexHelper/src/auth.rs
require_file Helper/CodexexHelper/src/flow_registry.rs
require_file Helper/CodexexHelper/src/lib.rs
require_file Helper/CodexexHelper/src/main.rs
require_file Helper/CodexexHelper/src/protocol.rs
require_file Helper/CodexexHelper/src/quota.rs
require_file Helper/CodexexHelper/src/release_environment_gating.rs
require_file Helper/CodexexHelper/src/secure_file_permissions.rs
require_file Helper/CodexexHelper/src/state.rs
require_file Sources/CodexexXPCService/Info.plist
require_file Sources/CodexMeterApp/Assets.xcassets/OpenAILogo.imageset/openai-logo.svg
require_file PRIVACY.md

[[ -d fastlane/metadata ]] || fail "missing fastlane/metadata"

require_text "INFOPLIST_KEY_LSUIElement: YES" project.yml
require_text "CodexexXPCService" project.yml
require_count "Build Codexex Helper" 2 project.yml
require_count "Embed Codexex Helper" 2 project.yml
# These are literal Xcode build-setting expressions, not shell expansions.
# shellcheck disable=SC2016
require_count '- $(PROJECT_DIR)/Scripts/build-codexex-helper.sh' 2 project.yml
# shellcheck disable=SC2016
require_count '- $(PROJECT_DIR)/Scripts/embed-codexex-helper.sh' 2 project.yml
require_count 'Helper/CodexexHelper/src/flow_registry.rs' 2 project.yml
require_count 'Helper/CodexexHelper/src/release_environment_gating.rs' 2 project.yml
require_count 'Helper/CodexexHelper/src/secure_file_permissions.rs' 2 project.yml
# These are literal Xcode build-setting expressions, not shell expansions.
# shellcheck disable=SC2016
require_text '$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Helpers/codexex-helper' project.yml
# shellcheck disable=SC2016
require_text '$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/XPCServices/CodexexXPCService.xpc/Contents/Helpers/codexex-helper' project.yml
require_text 'x86_64-apple-darwin' Scripts/build-codexex-helper.sh
require_text 'CODEXEX_RUSTUP_TOOLCHAIN' Scripts/build-codexex-helper.sh
require_text 'CODEXEX_HELPER_PREFLIGHT_ONLY' Scripts/build-codexex-helper.sh
require_text 'CODEXEX_STRIP_BIN' Scripts/build-codexex-helper.sh
require_text 'CARGO_PROFILE_RELEASE_STRIP=false' Scripts/build-codexex-helper.sh
require_text "protocolVersion" Sources/CodexMeterCore/CodexServiceContracts.swift
require_text "requestId" Sources/CodexMeterCore/CodexServiceContracts.swift
require_text "CODEXEX_ENABLE_LEGACY_PROBE" Sources/CodexMeterCore/CodexAppServerProbe.swift
require_text "Helpers/codexex-helper" Sources/CodexexXPCService/CodexHelperProcess.swift
require_text "com.apple.security.app-sandbox" AppStore/Codexex.entitlements
require_text "com.apple.security.app-sandbox" AppStore/CodexexXPCService.entitlements
require_text "com.apple.security.inherit" AppStore/CodexexHelper.entitlements
require_text "ChatGPT/OpenAI sign-in" PRIVACY.md
require_text "Paid packaging" RUNBOOK.md
require_text "paid-upfront App Store pricing" RUNBOOK.md
require_text "MARKETING_VERSION: 6.0.0" project.yml
require_text "CURRENT_PROJECT_VERSION: 19" project.yml
require_text "OpenAILogo" Sources/CodexMeterApp/UI/StatusBarLabel.swift
require_text "Codexex 6.0.0" fastlane/metadata/up-6762058457/IOS/en-US/whats_new.txt
require_text "Codexex 6.0.0" fastlane/metadata/up-6762058457/MACOS/en-US/whats_new.txt

bash Scripts/check-codexex-companions.sh
bash -n Scripts/build-codexex-helper.sh
bash -n Scripts/embed-codexex-helper.sh

ARCHS="arm64 x86_64" CODEXEX_HELPER_PREFLIGHT_ONLY=YES \
  bash Scripts/build-codexex-helper.sh

configured_rustup="${CODEXEX_RUSTUP_BIN:-rustup}"
rustup_bin="$(command -v "$configured_rustup" || true)"
[[ -n "$rustup_bin" ]] || fail "rustup not found: $configured_rustup"
rustup_toolchain="${CODEXEX_RUSTUP_TOOLCHAIN:-stable}"
if ! cargo_bin="$("$rustup_bin" which --toolchain "$rustup_toolchain" cargo 2>/dev/null)"; then
  fail "cargo is unavailable for rustup toolchain '$rustup_toolchain'"
fi
if ! rustc_bin="$("$rustup_bin" which --toolchain "$rustup_toolchain" rustc 2>/dev/null)"; then
  fail "rustc is unavailable for rustup toolchain '$rustup_toolchain'"
fi
if ! rustdoc_bin="$("$rustup_bin" which --toolchain "$rustup_toolchain" rustdoc 2>/dev/null)"; then
  fail "rustdoc is unavailable for rustup toolchain '$rustup_toolchain'"
fi
RUSTC="$rustc_bin" RUSTDOC="$rustdoc_bin" "$cargo_bin" test --locked \
  --manifest-path Helper/CodexexHelper/Cargo.toml

if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild -project CodexMeter.xcodeproj \
    -scheme CodexMeterApp \
    -configuration Debug \
    -destination 'platform=macOS' \
    -showBuildSettings >/dev/null
  xcodebuild -project CodexMeter.xcodeproj \
    -scheme CodexMeteriOS \
    -configuration Debug \
    -sdk iphonesimulator \
    -showBuildSettings >/dev/null
else
  echo "release-smoke: xcodebuild unavailable; skipped Xcode build-settings smoke"
fi

echo "release-smoke: static release checks passed"
