#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
PYTHON_BIN=${PYTHON_BIN:-$(command -v python3)}

if [[ -z "${PYTHON_BIN}" ]]; then
  print -u2 "python3 is required"
  exit 1
fi

if [[ ! -d "${PROJECT_DIR}/.venv" ]]; then
  "${PYTHON_BIN}" -m venv "${PROJECT_DIR}/.venv"
fi

"${PROJECT_DIR}/.venv/bin/python3" -m pip install --upgrade pip
"${PROJECT_DIR}/.venv/bin/python3" -m pip install -r "${PROJECT_DIR}/vision/requirements.txt"

if [[ "${1:-}" == "--install-hammerspoon" ]]; then
  if [[ ! -d /Applications/Hammerspoon.app ]]; then
    brew install --cask hammerspoon
  fi
fi

if ! command -v cliclick >/dev/null 2>&1; then
  brew install cliclick
fi

mkdir -p "${PROJECT_DIR}/runtime/bin"
swiftc -O "${PROJECT_DIR}/native/ae_input.swift" -o "${PROJECT_DIR}/runtime/bin/ae-input"
codesign --force --sign - "${PROJECT_DIR}/runtime/bin/ae-input"

"${PROJECT_DIR}/scripts/run_checks.sh"
print "Setup complete. See LIVE_TEST.md for the assisted capture test."
