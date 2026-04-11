#!/usr/bin/env bash
set -euo pipefail

repo_root="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source_binary="$DERIVED_FILE_DIR/codexex-helper/codexex-helper"
destination_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
destination_binary="$destination_dir/codexex-helper"
entitlements_file="$repo_root/AppStore/CodexexHelper.entitlements"

mkdir -p "$destination_dir"
cp "$source_binary" "$destination_binary"
chmod 755 "$destination_binary"

if [[ "${CODE_SIGNING_ALLOWED:-NO}" != "YES" ]]; then
  exit 0
fi

sign_identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"

codesign \
  --force \
  --sign "$sign_identity" \
  --entitlements "$entitlements_file" \
  --timestamp=none \
  "$destination_binary"
