#!/usr/bin/env bash
set -euo pipefail

repo_root="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source_binary="$DERIVED_FILE_DIR/codexex-helper/codexex-helper"
app_helper_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
xpc_bundle_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/XPCServices/CodexexXPCService.xpc"
xpc_helper_dir="$xpc_bundle_dir/Contents/Helpers"
entitlements_file="$repo_root/AppStore/CodexexHelper.entitlements"
xpc_entitlements_file="$repo_root/AppStore/CodexexXPCService.entitlements"

install_helper() {
  local destination_dir="$1"
  local destination_binary="$destination_dir/codexex-helper"

  mkdir -p "$destination_dir"
  cp "$source_binary" "$destination_binary"
  chmod 755 "$destination_binary"

  if [[ "${CODE_SIGNING_ALLOWED:-NO}" != "YES" ]]; then
    return
  fi

  local sign_identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"

  codesign \
    --force \
    --sign "$sign_identity" \
    --entitlements "$entitlements_file" \
    --timestamp=none \
    "$destination_binary"
}

install_helper "$app_helper_dir"

if [[ "${WRAPPER_EXTENSION:-}" != "xpc" && -d "$xpc_bundle_dir/Contents" ]]; then
  install_helper "$xpc_helper_dir"
fi

if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" && "${WRAPPER_EXTENSION:-}" == "xpc" ]]; then
  sign_identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
  codesign \
    --force \
    --sign "$sign_identity" \
    --entitlements "$xpc_entitlements_file" \
    --timestamp=none \
    "$TARGET_BUILD_DIR/$WRAPPER_NAME"
fi

if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" && "${WRAPPER_EXTENSION:-}" != "xpc" && -d "$xpc_bundle_dir/Contents" ]]; then
  sign_identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
  codesign \
    --force \
    --sign "$sign_identity" \
    --entitlements "$xpc_entitlements_file" \
    --timestamp=none \
    "$xpc_bundle_dir"
fi
