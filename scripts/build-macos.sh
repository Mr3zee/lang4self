#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}

source "$SCRIPT_DIR/build-app.zsh"

build_app Debug
