#!/bin/zsh
set -u

HS_BIN=${HS_BIN:-}
if [[ -z "${HS_BIN}" ]]; then
  if command -v hs >/dev/null 2>&1; then
    HS_BIN=$(command -v hs)
  elif [[ -x /Applications/Hammerspoon.app/Contents/Frameworks/hs/hs ]]; then
    HS_BIN=/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs
  else
    print -u2 "Hammerspoon's hs command is not installed"
    exit 1
  fi
fi

if ! "${HS_BIN}" -c 'return true' >/dev/null 2>&1; then
  open -a Hammerspoon
  print "Hammerspoon was launched. Run this command once more after it finishes opening."
  exit 2
fi

ACCESSIBILITY=$("${HS_BIN}" -c 'return hs.accessibilityState(true)' 2>/dev/null)
SCREEN_RECORDING=$("${HS_BIN}" -c 'return hs.screenRecordingState(true)' 2>/dev/null)

print "Accessibility: ${ACCESSIBILITY}"
print "Screen Recording: ${SCREEN_RECORDING}"

if [[ "${ACCESSIBILITY}" == "true" && "${SCREEN_RECORDING}" == "true" ]]; then
  print "Both permissions are ready."
  exit 0
fi

print "Enable Hammerspoon in the System Settings panes that macOS opened."
print "Then quit and reopen Hammerspoon and run ./scripts/doctor.sh."
exit 2
