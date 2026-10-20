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

reject_text() {
  local needle="$1"
  local file="$2"
  if grep -Fq "$needle" "$file"; then
    fail "unexpected '$needle' in $file"
  fi
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
require_file Sources/CodexMeteriOS/Info.plist
require_file Sources/CodexMeterApp/PrivacyInfo.xcprivacy
require_file Sources/CodexMeteriOS/PrivacyInfo.xcprivacy
require_file Sources/CodexMeterApp/Assets.xcassets/OpenAILogo.imageset/openai-logo.svg
require_file PRIVACY.md

[[ -d fastlane/metadata ]] || fail "missing fastlane/metadata"

require_text "INFOPLIST_KEY_LSUIElement: YES" project.yml
require_text "<key>CFBundleDevelopmentRegion</key>" Sources/CodexMeteriOS/Info.plist
require_text "35F9.1" Sources/CodexMeterApp/PrivacyInfo.xcprivacy
require_text "35F9.1" Sources/CodexMeteriOS/PrivacyInfo.xcprivacy
reject_text "35F4.1" Sources/CodexMeterApp/PrivacyInfo.xcprivacy
reject_text "35F4.1" Sources/CodexMeteriOS/PrivacyInfo.xcprivacy
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
require_text "Paid packaging" docs/development/runbook.md
require_text "paid-upfront App Store pricing" docs/development/runbook.md
grep -Eq 'MARKETING_VERSION: [0-9]+\.[0-9]+\.[0-9]+' project.yml || fail "missing marketing version"
grep -Eq 'CURRENT_PROJECT_VERSION: [1-9][0-9]*' project.yml || fail "missing positive build number"
require_text "OpenAILogo" Sources/CodexMeterApp/UI/StatusBarLabel.swift
for release_platform in IOS MACOS; do
  release_metadata="fastlane/metadata/up-6762058457/$release_platform/en-US"
  for release_field in description whats_new promotional_text keywords; do
    require_file "$release_metadata/$release_field.txt"
    [[ -s "$release_metadata/$release_field.txt" ]] || fail "empty $release_platform $release_field"
  done
done
python3 - <<'PY'
from pathlib import Path
for platform in ("IOS", "MACOS"):
    root = Path("fastlane/metadata/up-6762058457") / platform / "en-US"
    for field, limit in (("description", 4000), ("whats_new", 4000), ("promotional_text", 170), ("keywords", 100)):
        value = (root / f"{field}.txt").read_text().strip()
        if len(value) > limit:
            raise SystemExit(f"release-smoke: {platform} {field} exceeds {limit} characters")
PY

# Keep the removed quota product out of source, tests, and documentation. Store
# release notes intentionally mention the removal for App Store review context.
legacy_bucket_term='s''park'
if git grep -n -i -F -- "$legacy_bucket_term" -- . ':(exclude)fastlane/metadata'; then
  fail "removed quota bucket is still referenced"
fi

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
(
  cd "$repo_root/Helper/CodexexHelper"
  # The adapter dispatches the literal tool name. Pin its resolved executable
  # to the selected rustup toolchain without changing the caller's global PATH.
  release_cargo_directory="$(dirname "$cargo_bin")"
  PATH="$release_cargo_directory:$PATH" RUSTC="$rustc_bin" RUSTDOC="$rustdoc_bin" \
    clean-development run --session session-only -- cargo test --locked \
      --manifest-path Cargo.toml
)

if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild -project CodexMeter.xcodeproj \
    -scheme CodexMeterApp \
    -configuration Debug \
    -destination 'platform=macOS' \
    -showBuildSettings >/dev/null
  xcodebuild -project CodexMeter.xcodeproj \
    -scheme CodexMeteriOS \
    -configuration Release \
    -sdk iphoneos \
    -showBuildSettings -json | python3 -c '
import json, re, sys
targets = {row["target"]: row["buildSettings"] for row in json.load(sys.stdin)}
pairs = []
for name in ("CodexMeteriOS", "CodexMeterWidgets"):
    settings = targets.get(name, {})
    version = settings.get("MARKETING_VERSION", "")
    build = settings.get("CURRENT_PROJECT_VERSION", "")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) or not re.fullmatch(r"[1-9][0-9]*", build):
        raise SystemExit(f"release-smoke: invalid Release version for {name}")
    pairs.append((version, build))
if pairs[0] != pairs[1]:
    raise SystemExit("release-smoke: iOS app and widget versions differ")
print(f"release-smoke: iOS app and widget Release version {pairs[0][0]} ({pairs[0][1]})")
'
else
  echo "release-smoke: xcodebuild unavailable; skipped Xcode build-settings smoke"
fi

echo "release-smoke: static release checks passed"
