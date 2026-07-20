#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
. "$SCRIPT_DIR/common-macos.sh"

discover_codex_app
require_macos_runtime
ensure_state_root

if codex_is_running; then
  stop_codex true
fi

exec "$SCRIPT_DIR/start-dream-skin-macos.sh" --restart-existing
