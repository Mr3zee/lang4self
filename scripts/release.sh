#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_PATH="$PROJECT_DIR/.derived/Build/Products/Release/Lang4Self.app"
APPLICATIONS_DIRECTORY="${HOME}/Applications"
APPLICATIONS_APP="${APPLICATIONS_DIRECTORY}/Lang4Self.app"
CLI_DIRECTORY="${HOME}/.local/bin"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"$SCRIPT_DIR/build-release.sh"

swift build --package-path "$PROJECT_DIR" -c release --product lang4self
CLI_BUILD_DIR=$(swift build --package-path "$PROJECT_DIR" -c release --show-bin-path)

mkdir -p "$APPLICATIONS_DIRECTORY"
/usr/bin/ditto "$APP_PATH" "$APPLICATIONS_APP"
"$LSREGISTER" -f "$APPLICATIONS_APP"
mkdir -p "$CLI_DIRECTORY"
/usr/bin/install -m 755 "$CLI_BUILD_DIR/lang4self" "$CLI_DIRECTORY/lang4self"

print "Applications app: $APPLICATIONS_APP"
print "CLI: $CLI_DIRECTORY/lang4self"
