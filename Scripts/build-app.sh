#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
BUILD_ROOT="$PROJECT_ROOT/build"
TARGET_APP="$BUILD_ROOT/Codex Skin Manager.app"
TEMP_ROOT=""
TEMP_APP=""
BACKUP_APP=""

cleanup_build() {
  case "${TEMP_ROOT:-}/" in
    "$BUILD_ROOT/.bundle."*) [ -z "$TEMP_ROOT" ] || /bin/rm -rf "$TEMP_ROOT" ;;
  esac
  case "${BACKUP_APP:-}/" in
    "$BUILD_ROOT/.previous."*)
      if [ -n "$BACKUP_APP" ] && [ -e "$BACKUP_APP" ]; then
        if [ ! -e "$TARGET_APP" ]; then
          /bin/mv "$BACKUP_APP" "$TARGET_APP" 2>/dev/null || true
        else
          /bin/rm -rf "$BACKUP_APP"
        fi
      fi
      ;;
  esac
}
trap cleanup_build EXIT

/bin/mkdir -p "$BUILD_ROOT"
/bin/bash "$PROJECT_ROOT/Scripts/test.sh"
cd "$PROJECT_ROOT"
/usr/bin/xcrun swift build -c release

TEMP_ROOT="$(/usr/bin/mktemp -d "$BUILD_ROOT/.bundle.XXXXXX")"
TEMP_APP="$TEMP_ROOT/Codex Skin Manager.app"
/bin/mkdir -p "$TEMP_APP/Contents/MacOS" "$TEMP_APP/Contents/Resources/EngineExtension"
/bin/cp "$PROJECT_ROOT/.build/release/CodexSkinManager" "$TEMP_APP/Contents/MacOS/CodexSkinManager"
/bin/chmod 755 "$TEMP_APP/Contents/MacOS/CodexSkinManager"
/bin/cp "$PROJECT_ROOT/Resources/Info.plist" "$TEMP_APP/Contents/Info.plist"
/bin/chmod 644 "$TEMP_APP/Contents/Info.plist"
/bin/cp "$PROJECT_ROOT/EngineExtension/import-theme-pack-macos.sh" \
  "$TEMP_APP/Contents/Resources/EngineExtension/import-theme-pack-macos.sh"
/bin/chmod 700 "$TEMP_APP/Contents/Resources/EngineExtension/import-theme-pack-macos.sh"

/usr/bin/plutil -lint "$TEMP_APP/Contents/Info.plist" >/dev/null
/usr/bin/codesign --force --deep --sign - "$TEMP_APP"
/usr/bin/codesign --verify --deep --strict "$TEMP_APP"

if [ -e "$TARGET_APP" ]; then
  BACKUP_APP="$BUILD_ROOT/.previous.$$.app"
  [ ! -e "$BACKUP_APP" ] || { /usr/bin/printf 'Temporary backup already exists: %s\n' "$BACKUP_APP" >&2; exit 1; }
  /bin/mv "$TARGET_APP" "$BACKUP_APP"
fi
/bin/mv "$TEMP_APP" "$TARGET_APP"
TEMP_APP=""
if [ -n "$BACKUP_APP" ]; then
  /bin/rm -rf "$BACKUP_APP"
  BACKUP_APP=""
fi

/usr/bin/printf 'Built: %s\n' "$TARGET_APP"
