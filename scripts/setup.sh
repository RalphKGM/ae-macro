#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}

if [[ -z "${PYTHON_BIN:-}" ]]; then
  for candidate in \
    /opt/homebrew/Caskroom/miniconda/base/bin/python3 \
    /opt/homebrew/bin/python3 \
    /usr/local/bin/python3 \
    /usr/bin/python3; do
    if [[ -x "${candidate}" ]] && "${candidate}" -c 'import sys; raise SystemExit(sys.version_info < (3, 12))'; then
      PYTHON_BIN=${candidate}
      break
    fi
  done
fi

if [[ -z "${PYTHON_BIN:-}" ]]; then
  print -u2 "python 3.12 or newer is required"
  exit 1
fi

if [[ -d "${PROJECT_DIR}/.venv" ]] && ! "${PROJECT_DIR}/.venv/bin/python3" -c 'import sys; raise SystemExit(sys.version_info < (3, 12))' 2>/dev/null; then
  "${PYTHON_BIN}" -m venv --clear "${PROJECT_DIR}/.venv"
elif [[ ! -d "${PROJECT_DIR}/.venv" ]]; then
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

if [[ "${AE_SKIP_V4_MAPS:-0}" != "1" ]]; then
  if ! "${PROJECT_DIR}/scripts/import_v4_maps.sh"; then
    print -u2 "warning: v0.4 map images could not be downloaded; the built-in king's tomb map still works"
  fi
fi

mkdir -p "${PROJECT_DIR}/runtime/bin"
swiftc -O "${PROJECT_DIR}/native/ae_input.swift" -o "${PROJECT_DIR}/runtime/bin/ae-input"
codesign --force --sign - "${PROJECT_DIR}/runtime/bin/ae-input"
"${PROJECT_DIR}/scripts/run_checks.sh"
print "Setup complete. See README.md for setup and usage."
