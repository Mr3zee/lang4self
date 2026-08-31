#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

source "$SCRIPT_DIR/build-app.zsh"

print "Stopping Lang4Self…"
/usr/bin/pkill -x Lang4Self 2>/dev/null || true

build_app Debug
APP_PATH=$BUILT_APP_PATH

print "Launching Lang4Self…"
"$LSREGISTER" -f "$APP_PATH"
/usr/bin/open -n -a "$APP_PATH"
