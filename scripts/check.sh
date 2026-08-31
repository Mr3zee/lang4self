#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}

swift test --package-path "$PROJECT_DIR"
xcodebuild -quiet \
  -project "$PROJECT_DIR/Lang4Self.xcodeproj" \
  -scheme Lang4Self \
  -destination 'platform=macOS,arch=arm64' \
  -skipPackagePluginValidation \
  build
