#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}

"${PROJECT_DIR}/.venv/bin/python3" -m pytest -q "${PROJECT_DIR}/tests/python"
lua "${PROJECT_DIR}/tests/lua/run.lua" "${PROJECT_DIR}"

find "${PROJECT_DIR}" -name '*.lua' -not -path '*/.venv/*' -print0 | while IFS= read -r -d '' file; do
  luac -p "${file}"
done

print "All automated checks passed."
