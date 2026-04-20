#!/usr/bin/env bash
set -euo pipefail

repo_root="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
helper_dir="$repo_root/Helper/CodexexHelper"
cargo_target_dir="$TARGET_TEMP_DIR/cargo"
staging_dir="$DERIVED_FILE_DIR/codexex-helper"
staging_binary="$staging_dir/codexex-helper"

source "$repo_root/../build-env.sh"

mkdir -p "$cargo_target_dir" "$staging_dir"

cd "$helper_dir"
CARGO_TARGET_DIR="$cargo_target_dir" cargo build --release --locked
cp "$cargo_target_dir/release/codexex-helper" "$staging_binary"
chmod 755 "$staging_binary"
