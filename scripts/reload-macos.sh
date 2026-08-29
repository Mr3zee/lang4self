#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_PATH="$PROJECT_DIR/.derived/Build/Products/Debug/Lang4Self.app"

print "Stopping Lang4Self…"
/usr/bin/pkill -x Lang4Self 2>/dev/null || true

"$SCRIPT_DIR/build-macos.sh"

print "Launching Lang4Self…"
/usr/bin/open "$APP_PATH"
