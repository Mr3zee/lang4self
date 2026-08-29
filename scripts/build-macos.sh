#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}

xcodebuild \
  -project "$PROJECT_DIR/Lang4Self.xcodeproj" \
  -scheme Lang4Self \
  -configuration Debug \
  -derivedDataPath "$PROJECT_DIR/.derived" \
  build

print "App: $PROJECT_DIR/.derived/Build/Products/Debug/Lang4Self.app"
