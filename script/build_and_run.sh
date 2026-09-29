#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Codexex"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Clean Development: honour the routed derived-data and SwiftPM cache
# locations; fall back to /tmp only when they are unset.
DERIVED_DATA="${XCODE_DERIVED_DATA_PATH:-/tmp}/codexex-macos-derived"
SWIFTPM_CACHE="${SWIFTPM_SHARED_CACHE:-/tmp}/codexex-swiftpm-cache"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

case "$MODE" in
  run|--debug|--logs|--telemetry|--verify) ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

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
