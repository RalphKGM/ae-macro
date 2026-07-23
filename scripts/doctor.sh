#!/bin/zsh
set -u

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
FAILED=0

check() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    print "PASS  ${label}"
  else
    print "FAIL  ${label}"
    FAILED=1
  fi
}

check "Roblox app installed" test -d /Applications/Roblox.app
check "Hammerspoon 1.1.1+ installed" test -d /Applications/Hammerspoon.app
check "Native Roblox click helper" command -v cliclick
check "Native Roblox camera helper" test -x "${PROJECT_DIR}/runtime/bin/ae-input"
check "Project virtual environment" test -x "${PROJECT_DIR}/.venv/bin/python3"
check "OpenCV import" "${PROJECT_DIR}/.venv/bin/python3" -c 'import cv2'
check "Hammerspoon IPC reachable" hs -c 'return true'

if hs -c 'return _G.AnimeExpeditionsMac ~= nil' 2>/dev/null | grep -q true; then
  print "PASS  Project bootstrap loaded"
  STATUS=$(hs -c 'return hs.json.encode(_G.AnimeExpeditionsMac:status(), true)' 2>/dev/null)
  print "\nRuntime status:"
  print -r -- "${STATUS}"
else
  print "FAIL  Project bootstrap loaded"
  FAILED=1
fi

exit ${FAILED}
