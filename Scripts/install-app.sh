#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
LAUNCH="true"
case "${1:-}" in
  "") ;;
  --no-launch) LAUNCH="false" ;;
  *) /usr/bin/printf 'Usage: install-app.sh [--no-launch]\n' >&2; exit 2 ;;
esac

/bin/bash "$PROJECT_ROOT/Scripts/build-app.sh"

SOURCE_APP="$PROJECT_ROOT/build/Codex Skin Manager.app"
INSTALL_ROOT="$HOME/Applications"
TARGET_APP="$INSTALL_ROOT/Codex Skin Manager.app"
INSTALLING_APP="$INSTALL_ROOT/.Codex Skin Manager.app.installing.$$"
BACKUP_APP="$INSTALL_ROOT/.Codex Skin Manager.app.previous.$$"

cleanup_install() {
  case "${INSTALLING_APP:-}/" in
    "$INSTALL_ROOT/.Codex Skin Manager.app.installing."*) /bin/rm -rf "$INSTALLING_APP" ;;
  esac
  case "${BACKUP_APP:-}/" in
    "$INSTALL_ROOT/.Codex Skin Manager.app.previous."*)
      if [ -e "$BACKUP_APP" ]; then
        if [ ! -e "$TARGET_APP" ]; then
          /bin/mv "$BACKUP_APP" "$TARGET_APP" 2>/dev/null || true
        else
          /bin/rm -rf "$BACKUP_APP"
        fi
      fi
      ;;
  esac
}
trap cleanup_install EXIT

/bin/mkdir -p "$INSTALL_ROOT"
[ ! -e "$INSTALLING_APP" ] && [ ! -e "$BACKUP_APP" ] \
  || { /usr/bin/printf 'A temporary install path already exists.\n' >&2; exit 1; }
/bin/cp -R "$SOURCE_APP" "$INSTALLING_APP"
/usr/bin/codesign --verify --deep --strict "$INSTALLING_APP"

if [ -e "$TARGET_APP" ]; then
  /bin/mv "$TARGET_APP" "$BACKUP_APP"
fi
/bin/mv "$INSTALLING_APP" "$TARGET_APP"
if [ -e "$BACKUP_APP" ]; then /bin/rm -rf "$BACKUP_APP"; fi

ENGINE_ROOT="${CODEX_DREAM_SKIN_ENGINE:-$HOME/.codex/codex-dream-skin-studio}"
ENGINE_SCRIPTS="$ENGINE_ROOT/scripts"
IMPORT_SOURCE="$PROJECT_ROOT/EngineExtension/import-theme-pack-macos.sh"
if [ -f "$ENGINE_SCRIPTS/common-macos.sh" ] \
  && [ -f "$ENGINE_SCRIPTS/stage-theme.mjs" ] \
  && [ -f "$ENGINE_SCRIPTS/injector.mjs" ]; then
  IMPORT_TEMP="$ENGINE_SCRIPTS/.import-theme-pack-macos.sh.$$"
  /usr/bin/install -m 700 "$IMPORT_SOURCE" "$IMPORT_TEMP"
  /bin/mv -f "$IMPORT_TEMP" "$ENGINE_SCRIPTS/import-theme-pack-macos.sh"
  /usr/bin/printf 'Installed theme importer: %s\n' "$ENGINE_SCRIPTS/import-theme-pack-macos.sh"
else
  /usr/bin/printf 'Warning: Dream Skin engine not found at %s; importing is unavailable until it is installed.\n' \
    "$ENGINE_ROOT" >&2
fi

/usr/bin/printf 'Installed: %s\n' "$TARGET_APP"
if [ "$LAUNCH" = "true" ]; then /usr/bin/open "$TARGET_APP"; fi
