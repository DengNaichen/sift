#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_DIR_PATH="$(xcode-select -p)"
ICON_TOOL="$(dirname "${DEVELOPER_DIR_PATH}")/Applications/Icon Composer.app/Contents/Executables/ictool"

if [[ ! -x "${ICON_TOOL}" ]]; then
  echo "Icon Composer's ictool was not found in the selected Xcode: ${ICON_TOOL}" >&2
  exit 1
fi

"${ICON_TOOL}" "${ROOT_DIR}/Resources/Brand/Sift.icon" \
  --export-image \
  --output-file "${ROOT_DIR}/Resources/Brand/Sift.png" \
  --platform macOS \
  --rendition Default \
  --width 1024 --height 1024 --scale 1

echo "Exported: ${ROOT_DIR}/Resources/Brand/Sift.png"
