#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "build-codexex-helper: $*" >&2
  exit 1
}

repo_root="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
helper_dir="$repo_root/Helper/CodexexHelper"
architectures="${ARCHS:-$(uname -m)}"
rust_targets=()

for architecture in $architectures; do
  case "$architecture" in
    arm64)
      rust_targets+=("aarch64-apple-darwin")
      ;;
    x86_64)
      rust_targets+=("x86_64-apple-darwin")
      ;;
    *)
      fail "unsupported helper architecture: $architecture"
      ;;
  esac
done

[[ "${#rust_targets[@]}" -gt 0 ]] || fail "no helper architectures requested"

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

[[ -x "$cargo_bin" ]] || fail "resolved cargo is not executable: $cargo_bin"
[[ -x "$rustc_bin" ]] || fail "resolved rustc is not executable: $rustc_bin"
[[ -x "$rustdoc_bin" ]] || fail "resolved rustdoc is not executable: $rustdoc_bin"

for rust_target in "${rust_targets[@]}"; do
  if ! target_libdir="$("$rustc_bin" --print target-libdir --target "$rust_target" 2>/dev/null)"; then
    fail "rust target '$rust_target' is unavailable for toolchain '$rustup_toolchain'"
  fi
  if [[ ! -d "$target_libdir" ]]; then
    fail "rust target '$rust_target' is not installed for toolchain '$rustup_toolchain'; run: $rustup_bin target add --toolchain $rustup_toolchain $rust_target"
  fi
done

lipo_bin=""
if [[ "${#rust_targets[@]}" -gt 1 ]]; then
  configured_lipo="${CODEXEX_LIPO_BIN:-lipo}"
  lipo_bin="$(command -v "$configured_lipo" || true)"
  [[ -n "$lipo_bin" ]] || fail "lipo not found: $configured_lipo"
fi

configured_strip="${CODEXEX_STRIP_BIN:-strip}"
strip_bin="$(command -v "$configured_strip" || true)"
[[ -n "$strip_bin" ]] || fail "strip not found: $configured_strip"

if [[ "${CODEXEX_HELPER_PREFLIGHT_ONLY:-NO}" == "YES" ]]; then
  echo "build-codexex-helper: toolchain '$rustup_toolchain' ready for ${rust_targets[*]}"
  exit 0
fi

shared_build_dir="${PROJECT_TEMP_DIR:-${TARGET_TEMP_DIR:-/tmp/codexex-helper-build}}"
cargo_target_dir="$shared_build_dir/codexex-helper-cargo"
staging_dir="${DERIVED_FILE_DIR:-/tmp/codexex-helper-derived}/codexex-helper"
staging_binary="$staging_dir/codexex-helper"
staging_tmp="$staging_binary.tmp.$$"

mkdir -p "$cargo_target_dir" "$staging_dir"
trap 'rm -f "$staging_tmp"' EXIT

cd "$helper_dir"

helper_binaries=()

for rust_target in "${rust_targets[@]}"; do
  env -u MACOSX_DEPLOYMENT_TARGET \
    CARGO_PROFILE_RELEASE_STRIP=false \
    RUSTC="$rustc_bin" \
    RUSTDOC="$rustdoc_bin" \
    CARGO_TARGET_DIR="$cargo_target_dir" \
    "$cargo_bin" build --release --locked --target "$rust_target"
  helper_binaries+=("$cargo_target_dir/$rust_target/release/codexex-helper")
done

if [[ "${#helper_binaries[@]}" -eq 1 ]]; then
  cp "${helper_binaries[0]}" "$staging_tmp"
else
  "$lipo_bin" -create "${helper_binaries[@]}" -output "$staging_tmp"
fi

"$strip_bin" -S "$staging_tmp"
chmod 755 "$staging_tmp"
mv -f "$staging_tmp" "$staging_binary"
