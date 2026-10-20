#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Codexex"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Keep explicit caller paths; load machine routing when either path is missing.
DERIVED_DATA_ROOT="${XCODE_DERIVED_DATA_PATH:-}"
SWIFTPM_CACHE_ROOT="${SWIFTPM_SHARED_CACHE:-}"
if [[ -z "$DERIVED_DATA_ROOT" || -z "$SWIFTPM_CACHE_ROOT" ]]; then
  if [[ -r "$HOME/dev/machine/env.zsh" ]]; then
    source "$HOME/dev/machine/env.zsh"
  fi
fi
DERIVED_DATA_ROOT="${DERIVED_DATA_ROOT:-${XCODE_DERIVED_DATA_PATH:?Load ~/dev/machine/env.zsh or supply XCODE_DERIVED_DATA_PATH}}"
SWIFTPM_CACHE_ROOT="${SWIFTPM_CACHE_ROOT:-${SWIFTPM_SHARED_CACHE:?Load ~/dev/machine/env.zsh or supply SWIFTPM_SHARED_CACHE}}"
DERIVED_DATA="$DERIVED_DATA_ROOT/codexex-macos-derived"
SWIFTPM_CACHE="$SWIFTPM_CACHE_ROOT/codexex-swiftpm-cache"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

case "$MODE" in
  run|--debug|--logs|--telemetry|--verify) ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

output_ready() {
  local output="$1" parent="$1" mount_root="" mount_device parent_device
  case "$output" in
    /*) ;;
    *) echo "Codexex: output path must be absolute: $output" >&2; return 1 ;;
  esac
  case "$output" in
    /Volumes/*)
      mount_root="${output#/Volumes/}"
      mount_root="/Volumes/${mount_root%%/*}"
      /sbin/mount | /usr/bin/awk -v target="$mount_root" 'index($0, " on " target " (") { found=1 } END { exit !found }' || {
        echo "Codexex: external output volume is not mounted: $mount_root" >&2; return 1;
      } ;;
  esac
  while [[ ! -e "$parent" ]]; do
    parent="${parent%/*}"
    [[ -n "$parent" ]] || parent=/
  done
  [[ -d "$parent" && -w "$parent" && -x "$parent" ]] || {
    echo "Codexex: output parent is not writable: $parent" >&2; return 1;
  }
  if [[ -n "${mount_root:-}" ]]; then
    mount_device="$(/usr/bin/stat -L -f %d "$mount_root")" || return 1
    parent_device="$(/usr/bin/stat -L -f %d "$parent")" || return 1
    [[ "$mount_device" = "$parent_device" ]] || {
      echo "Codexex: output parent is outside the mounted volume: $parent" >&2; return 1;
    }
  fi
}
output_ready "$DERIVED_DATA"
output_ready "$SWIFTPM_CACHE"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild -quiet \
  -project "$ROOT_DIR/CodexMeter.xcodeproj" \
  -scheme CodexMeterApp \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$SWIFTPM_CACHE" \
  build

case "$MODE" in
  --debug)
    lldb -- "$APP_BINARY"
    ;;
  run)
    /usr/bin/open -n "$APP_BUNDLE"
    ;;
  --logs)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.magrathean.CodexexApp.performance"'
    ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    for _ in {1..20}; do
      if pgrep -x "$APP_NAME" >/dev/null; then
        exit 0
      fi
      sleep 0.5
    done
    echo "$APP_NAME did not start" >&2
    exit 1
    ;;
esac
