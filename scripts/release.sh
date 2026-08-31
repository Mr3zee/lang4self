#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APPLICATIONS_DIRECTORY="${HOME}/Applications"
APPLICATIONS_APP="${APPLICATIONS_DIRECTORY}/Lang4Self.app"
CLI_DIRECTORY="${HOME}/.local/bin"
CLI_SCRATCH_PATH="$PROJECT_DIR/.derived/SwiftPMCLI"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

source "$SCRIPT_DIR/build-app.zsh"

build_app Release
APP_PATH=$BUILT_APP_PATH

swift build \
  --package-path "$PROJECT_DIR" \
  --scratch-path "$CLI_SCRATCH_PATH" \
  -c release \
  --product lang4self
CLI_BUILD_DIR=$(swift build \
  --package-path "$PROJECT_DIR" \
  --scratch-path "$CLI_SCRATCH_PATH" \
  -c release \
  --show-bin-path)
CLI_PATH="$CLI_BUILD_DIR/lang4self"

if [[ ! -x "$CLI_PATH" ]]; then
  print -u2 "CLI build did not produce an executable: $CLI_PATH"
  exit 1
fi

mkdir -p "$APPLICATIONS_DIRECTORY"
if [[ -d "$APPLICATIONS_APP" ]]; then
  "$LSREGISTER" -u "$APPLICATIONS_APP" || true
fi
/usr/bin/ditto "$APP_PATH" "$APPLICATIONS_APP"
/usr/bin/touch "$APPLICATIONS_APP"
"$LSREGISTER" -f "$APPLICATIONS_APP"
/usr/bin/mdimport "$APPLICATIONS_APP"
mkdir -p "$CLI_DIRECTORY"
/usr/bin/install -m 755 "$CLI_PATH" "$CLI_DIRECTORY/lang4self"

if /usr/bin/pgrep -x Raycast >/dev/null; then
  /usr/bin/killall Raycast || true
  for _ in {1..50}; do
    if ! /usr/bin/pgrep -x Raycast >/dev/null; then
      break
    fi
    /bin/sleep 0.1
  done
  /bin/sleep 0.5
  if ! /usr/bin/open -g -n -a Raycast; then
    /bin/sleep 0.5
    /usr/bin/open -g -n -a Raycast
  fi
fi

print "Applications app: $APPLICATIONS_APP"
print "CLI: $CLI_DIRECTORY/lang4self"
