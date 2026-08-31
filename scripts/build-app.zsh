#!/bin/zsh

build_app() {
  local configuration=$1
  local build_settings
  local target_build_dir
  local -a xcode_arguments=(
    -project "$PROJECT_DIR/Lang4Self.xcodeproj"
    -scheme Lang4Self
    -configuration "$configuration"
    -destination 'platform=macOS,arch=arm64'
    -skipPackagePluginValidation
  )

  xcodebuild "${xcode_arguments[@]}" build

  build_settings=$(xcodebuild "${xcode_arguments[@]}" -showBuildSettings -json)
  target_build_dir=$(print -rn -- "$build_settings" | \
    /usr/bin/plutil -extract '0.buildSettings.TARGET_BUILD_DIR' raw -o - -)
  typeset -g BUILT_APP_PATH="$target_build_dir/Lang4Self.app"

  if [[ ! -d "$BUILT_APP_PATH" ]]; then
    print -u2 "App build did not produce a bundle: $BUILT_APP_PATH"
    return 1
  fi

  print "App: $BUILT_APP_PATH"
}
