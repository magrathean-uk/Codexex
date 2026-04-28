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
  actual="$(grep -Foc "$needle" "$file" || true)"
  [[ "$actual" == "$expected" ]] || fail "expected '$needle' $expected time(s) in $file, found $actual"
}

require_file project.yml
require_file AppStore/Codexex.entitlements
require_file AppStore/CodexexHelper.entitlements
require_file AppStore/CodexexXPCService.entitlements
require_file Scripts/build-codexex-helper.sh
require_file Scripts/embed-codexex-helper.sh
require_file Helper/CodexexHelper/Cargo.toml
require_file Helper/CodexexHelper/src/protocol.rs
require_file Sources/CodexexXPCService/Info.plist
require_file PRIVACY.md

[[ -d fastlane/metadata ]] || fail "missing fastlane/metadata"

require_text "INFOPLIST_KEY_LSUIElement: YES" project.yml
require_text "CodexexXPCService" project.yml
require_count "Build Codexex Helper" 1 project.yml
require_count "Embed Codexex Helper" 1 project.yml
require_text '$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Helpers/codexex-helper' project.yml
require_text "protocolVersion" Sources/CodexMeterCore/CodexServiceContracts.swift
require_text "requestId" Sources/CodexMeterCore/CodexServiceContracts.swift
require_text "CODEXEX_ENABLE_LEGACY_PROBE" Sources/CodexMeterCore/CodexAppServerProbe.swift
require_text "Helpers/codexex-helper" Sources/CodexexXPCService/CodexHelperProcess.swift
require_text "com.apple.security.app-sandbox" AppStore/Codexex.entitlements
require_text "com.apple.security.app-sandbox" AppStore/CodexexXPCService.entitlements
require_text "com.apple.security.inherit" AppStore/CodexexHelper.entitlements
require_text "ChatGPT sign-in" PRIVACY.md

if command -v cargo >/dev/null 2>&1; then
  cargo test --manifest-path Helper/CodexexHelper/Cargo.toml
else
  echo "release-smoke: cargo unavailable; skipped helper tests"
fi

if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild -project CodexMeter.xcodeproj \
    -scheme CodexMeterApp \
    -configuration Debug \
    -destination 'platform=macOS' \
    -showBuildSettings >/dev/null
else
  echo "release-smoke: xcodebuild unavailable; skipped Xcode build-settings smoke"
fi

echo "release-smoke: static release checks passed"
