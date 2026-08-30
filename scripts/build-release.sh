#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_PATH="$PROJECT_DIR/.derived/Build/Products/Release/Lang4Self.app"

xcodebuild \
  -project "$PROJECT_DIR/Lang4Self.xcodeproj" \
  -scheme Lang4Self \
  -configuration Release \
  -derivedDataPath "$PROJECT_DIR/.derived" \
  build

print "App: $APP_PATH"
