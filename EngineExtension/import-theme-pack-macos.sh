#!/bin/bash

set -euo pipefail

. "$(cd "$(dirname "$0")" && pwd -P)/common-macos.sh"

ARCHIVE=""
REPLACE="false"
JSON_OUTPUT="false"
VALIDATE_ONLY="false"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --file)
      [ "$#" -ge 2 ] || { /usr/bin/printf 'Missing value for --file.\n' >&2; exit 2; }
      ARCHIVE="$2"
      shift 2
      ;;
    --replace)
      REPLACE="true"
      shift
      ;;
    --json)
      JSON_OUTPUT="true"
      shift
      ;;
    --validate-only)
      VALIDATE_ONLY="true"
      shift
      ;;
    *)
      /usr/bin/printf 'Unknown import argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

ensure_node_runtime
ensure_state_root
THEMES_ROOT="$STATE_ROOT/themes"
IMPORTS_ROOT="$STATE_ROOT/.imports"
/bin/mkdir -p "$THEMES_ROOT" "$IMPORTS_ROOT"
/bin/chmod 700 "$THEMES_ROOT" "$IMPORTS_ROOT"

WORK=""
INCOMING=""
BACKUP=""
DEST=""
cleanup_import() {
  case "${WORK:-}/" in
    "$IMPORTS_ROOT/"*) [ -z "$WORK" ] || /bin/rm -rf "$WORK" ;;
  esac
  case "${INCOMING:-}/" in
    "$THEMES_ROOT/.incoming."*) [ -z "$INCOMING" ] || /bin/rm -rf "$INCOMING" ;;
  esac
  case "${BACKUP:-}/" in
    "$THEMES_ROOT/.backup."*)
      if [ -n "$BACKUP" ] && [ -e "$BACKUP" ]; then
        if [ -n "$DEST" ] && [ ! -e "$DEST" ]; then
          /bin/mv "$BACKUP" "$DEST" 2>/dev/null || true
        else
          /bin/rm -rf "$BACKUP"
        fi
      fi
      ;;
  esac
}
trap cleanup_import EXIT

emit_json() {
  "$NODE" -e '
    const [pass, code, message, id, name] = process.argv.slice(1);
    process.stdout.write(`${JSON.stringify({
      pass: pass === "true", code, message, themeId: id, themeName: name,
    })}\n`);
  ' "$1" "$2" "$3" "${4:-}" "${5:-}"
}

abort_import() {
  local exit_code="$1"
  local code="$2"
  local message="$3"
  local id="${4:-}"
  local name="${5:-}"
  if [ "$JSON_OUTPUT" = "true" ]; then
    emit_json false "$code" "$message" "$id" "$name"
  fi
  /usr/bin/printf '%s\n' "$message" >&2
  exit "$exit_code"
}

[ -n "$ARCHIVE" ] \
  || abort_import 2 invalid_argument 'Usage: import-theme-pack-macos.sh --file <theme.codexskin> [--replace] [--validate-only] --json'
case "$ARCHIVE" in
  *.codexskin) ;;
  *) abort_import 2 invalid_extension 'Theme package must use the .codexskin extension.' ;;
esac
[ -f "$ARCHIVE" ] && [ ! -L "$ARCHIVE" ] \
  || abort_import 2 invalid_file 'Theme package must be a regular, non-symlink file.'
ARCHIVE_BYTES="$(/usr/bin/stat -f '%z' "$ARCHIVE")"
[ "$ARCHIVE_BYTES" -gt 0 ] && [ "$ARCHIVE_BYTES" -le 20971520 ] \
  || abort_import 2 archive_size 'Theme package must be non-empty and no larger than 20 MB.'

WORK="$(/usr/bin/mktemp -d "$IMPORTS_ROOT/import.XXXXXX")"
/bin/chmod 700 "$WORK"
ENTRIES="$WORK/entries.txt"
/usr/bin/unzip -Z1 "$ARCHIVE" > "$ENTRIES" 2>/dev/null \
  || abort_import 2 invalid_zip 'Theme package is not a readable ZIP archive.'
[ "$(/usr/bin/wc -l < "$ENTRIES" | /usr/bin/tr -d ' ')" -eq 2 ] \
  || abort_import 2 invalid_entries 'Theme package must contain exactly theme.json and one image.'

THEME_JSON_COUNT=0
IMAGE_ENTRY=""
while IFS= read -r entry; do
  case "$entry" in
    ''|.*|*/*|*\\*|*..*)
      abort_import 2 unsafe_entry 'Theme package entries must be flat safe filenames.'
      ;;
  esac
  if [ "$entry" = "theme.json" ]; then
    THEME_JSON_COUNT=$((THEME_JSON_COUNT + 1))
  else
    IMAGE_ENTRY="$entry"
  fi
done < "$ENTRIES"
[ "$THEME_JSON_COUNT" -eq 1 ] && [ -n "$IMAGE_ENTRY" ] \
  || abort_import 2 invalid_entries 'Theme package must contain theme.json and one image.'
case "$IMAGE_ENTRY" in
  *.png|*.PNG|*.jpg|*.JPG|*.jpeg|*.JPEG|*.webp|*.WEBP) ;;
  *) abort_import 2 invalid_image_type 'Theme image must be PNG, JPEG, or WebP.' ;;
esac

UNCOMPRESSED_BYTES="$(/usr/bin/unzip -l "$ARCHIVE" | /usr/bin/awk '
  $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9][0-9][0-9][0-9]-/ { total += $1 }
  END { print total + 0 }
')"
[ "$UNCOMPRESSED_BYTES" -le 33554432 ] \
  || abort_import 2 expanded_size 'Expanded theme package must not exceed 32 MB.'

EXTRACTED="$WORK/extracted"
SNAPSHOT="$WORK/snapshot"
/bin/mkdir -p "$EXTRACTED" "$SNAPSHOT"
/usr/bin/unzip -qq "$ARCHIVE" -d "$EXTRACTED" \
  || abort_import 2 extract_failed 'Theme package could not be extracted.'
[ -z "$(/usr/bin/find "$EXTRACTED" -type l -print -quit)" ] \
  || abort_import 2 link_entry 'Theme package may not contain links.'
[ "$(/usr/bin/find "$EXTRACTED" -maxdepth 1 -type f | /usr/bin/wc -l | /usr/bin/tr -d ' ')" -eq 2 ] \
  || abort_import 2 invalid_entries 'Extracted package does not contain exactly two regular files.'
[ "$(/usr/bin/stat -f '%z' "$EXTRACTED/theme.json")" -le 65536 ] \
  || abort_import 2 manifest_size 'theme.json must not exceed 64 KB.'

THEME_IMAGE="$("$NODE" "$SCRIPT_DIR/stage-theme.mjs" "$EXTRACTED" "$SNAPSHOT" 2>/dev/null)" \
  || abort_import 2 invalid_theme 'Theme manifest or referenced image is invalid.'
[ "$THEME_IMAGE" = "$IMAGE_ENTRY" ] \
  || abort_import 2 image_mismatch 'theme.json image does not match the packaged image.'
PAYLOAD="$("$NODE" "$INJECTOR" --check-payload --theme-dir "$SNAPSHOT" 2>/dev/null)" \
  || abort_import 2 invalid_payload 'Theme failed Dream Skin payload validation.'

THEME_ID="$("$NODE" -e '
  const value = JSON.parse(process.argv[1]);
  process.stdout.write(typeof value.themeId === "string" ? value.themeId : "");
' "$PAYLOAD")"
THEME_NAME="$("$NODE" -e '
  const value = JSON.parse(process.argv[1]);
  process.stdout.write(typeof value.themeName === "string" ? value.themeName : "");
' "$PAYLOAD")"
RAW_ID="$("$NODE" -e '
  const fs = require("node:fs");
  const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  process.stdout.write(typeof value.id === "string" ? value.id.trim() : "");
' "$SNAPSHOT/theme.json")"
[ "$RAW_ID" = "$THEME_ID" ] && [ -n "$THEME_NAME" ] \
  || abort_import 2 invalid_metadata 'Theme id and name must be non-empty strings.'
case "$THEME_ID" in
  ''|*[!A-Za-z0-9_-]*) abort_import 2 invalid_id 'Theme id contains unsupported characters.' ;;
esac
[ "${#THEME_ID}" -le 80 ] \
  || abort_import 2 invalid_id 'Theme id is too long.'

if [ "$VALIDATE_ONLY" = "true" ]; then
  if [ "$JSON_OUTPUT" = "true" ]; then
    emit_json true validated 'Theme package validated successfully.' "$THEME_ID" "$THEME_NAME"
  else
    /usr/bin/printf 'Validated: %s\n' "$THEME_NAME"
  fi
  exit 0
fi

DEST="$THEMES_ROOT/$THEME_ID"
if [ -e "$DEST" ] && [ "$REPLACE" != "true" ]; then
  abort_import 3 theme_exists "Theme already exists: $THEME_NAME" "$THEME_ID" "$THEME_NAME"
fi

INCOMING="$(/usr/bin/mktemp -d "$THEMES_ROOT/.incoming.$THEME_ID.XXXXXX")"
/bin/cp "$SNAPSHOT/theme.json" "$SNAPSHOT/$THEME_IMAGE" "$INCOMING/"
/bin/chmod 600 "$INCOMING/"*
if [ -e "$DEST" ]; then
  BACKUP="$(/usr/bin/mktemp -d "$THEMES_ROOT/.backup.$THEME_ID.XXXXXX")"
  /bin/rmdir "$BACKUP"
  /bin/mv "$DEST" "$BACKUP"
  if ! /bin/mv "$INCOMING" "$DEST"; then
    /bin/mv "$BACKUP" "$DEST" || true
    BACKUP=""
    abort_import 2 publish_failed 'Theme could not be replaced atomically.'
  fi
  INCOMING=""
  /bin/rm -rf "$BACKUP"
  BACKUP=""
else
  /bin/mv "$INCOMING" "$DEST" \
    || abort_import 2 publish_failed 'Theme could not be installed atomically.'
  INCOMING=""
fi

if [ "$JSON_OUTPUT" = "true" ]; then
  emit_json true imported 'Theme imported successfully.' "$THEME_ID" "$THEME_NAME"
else
  /usr/bin/printf 'Imported: %s\n' "$THEME_NAME"
fi
