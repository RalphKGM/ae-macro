#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
DESTINATION="${PROJECT_DIR}/assets/maps/v4"
RELEASE_URL="https://github.com/QuantumMacro/anime-expeditions/releases/download/v0.4/AnimeExpeditionsAIO_dist.zip"
EXPECTED_COUNT=21

existing_count=0
if [[ -d "${DESTINATION}" ]]; then
  existing_count=$(find "${DESTINATION}" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')
fi
if (( existing_count >= EXPECTED_COUNT )); then
  print "v0.4 map images already installed"
  exit 0
fi

ASSET_TMP_DIR=$(mktemp -d /tmp/ae-v4-maps.XXXXXX)
cleanup() {
  if [[ "${ASSET_TMP_DIR}" == /tmp/ae-v4-maps.* ]]; then
    rm -rf -- "${ASSET_TMP_DIR}"
  fi
}
trap cleanup EXIT

curl -fL --retry 2 "${RELEASE_URL}" -o "${ASSET_TMP_DIR}/v4.zip"
mkdir -p "${DESTINATION}"
unzip -jo "${ASSET_TMP_DIR}/v4.zip" 'assets/maps/*.png' -d "${DESTINATION}"

installed_count=$(find "${DESTINATION}" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')
if (( installed_count < EXPECTED_COUNT )); then
  print -u2 "expected ${EXPECTED_COUNT} map images, found ${installed_count}"
  exit 1
fi

for image in "${DESTINATION}"/*.png; do
  dimensions=$(sips -g pixelWidth -g pixelHeight "${image}" 2>/dev/null)
  if [[ "${dimensions}" != *"pixelWidth: 816"* || "${dimensions}" != *"pixelHeight: 638"* ]]; then
    print -u2 "unexpected map dimensions: ${image}"
    exit 1
  fi
done

print "installed ${installed_count} v0.4 map images"
