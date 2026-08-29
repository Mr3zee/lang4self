#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
DESKTOP_APP="${HOME}/Desktop/Lang4Self.app"
CLI_DIRECTORY="${HOME}/.local/bin"

xcodebuild \
  -project "$PROJECT_DIR/Lang4Self.xcodeproj" \
  -scheme Lang4Self \
  -configuration Release \
  -derivedDataPath "$PROJECT_DIR/.derived" \
  build

swift build --package-path "$PROJECT_DIR" -c release --product lang4self
CLI_BUILD_DIR=$(swift build --package-path "$PROJECT_DIR" -c release --show-bin-path)

/usr/bin/ditto "$PROJECT_DIR/.derived/Build/Products/Release/Lang4Self.app" "$DESKTOP_APP"
mkdir -p "$CLI_DIRECTORY"
/usr/bin/install -m 755 "$CLI_BUILD_DIR/lang4self" "$CLI_DIRECTORY/lang4self"

print "Desktop app: $DESKTOP_APP"
print "CLI: $CLI_DIRECTORY/lang4self"
