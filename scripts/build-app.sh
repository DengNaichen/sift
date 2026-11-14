#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="${ROOT_DIR}/Config/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "${INFO_PLIST}")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO_PLIST}")"
ARCH="${ARCH:-arm64}"
DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${OUTPUT_APP_BUNDLE:-${DIST_DIR}/${APP_NAME}.app}"

echo "==> Building MailroomApp (Release, ${ARCH})..."
swift build -c release --arch "${ARCH}" --product MailroomApp --package-path "${ROOT_DIR}"

BIN_PATH="$(swift build -c release --arch "${ARCH}" --show-bin-path --package-path "${ROOT_DIR}")/MailroomApp"

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/MailroomApp"
cp "${INFO_PLIST}" "${APP_BUNDLE}/Contents/Info.plist"
chmod +x "${APP_BUNDLE}/Contents/MacOS/MailroomApp"

# Compile the editable Icon Composer source into Assets.car + Sift.icns + bundle icon metadata.
echo "==> Compiling Sift app icon..."
ICON_INFO_PLIST="$(mktemp "${TMPDIR:-/tmp}/sift-app-icon-info.XXXXXX")"
trap 'rm -f "${ICON_INFO_PLIST}"' EXIT

MINIMUM_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${APP_BUNDLE}/Contents/Info.plist")"
xcrun actool "${ROOT_DIR}/Resources/Brand/Sift.icon" \
  --compile "${APP_BUNDLE}/Contents/Resources" \
  --platform macosx \
  --target-device mac \
  --minimum-deployment-target "${MINIMUM_MACOS}" \
  --app-icon Sift \
  --output-partial-info-plist "${ICON_INFO_PLIST}" \
  --output-format human-readable-text
/usr/libexec/PlistBuddy -c "Merge '${ICON_INFO_PLIST}'" "${APP_BUNDLE}/Contents/Info.plist"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "==> Signing with explicit identity: ${CODESIGN_IDENTITY}"
  for attempt in 1 2 3; do
    if codesign --force --timestamp --options runtime \
      --entitlements "${ROOT_DIR}/Config/Mailroom.entitlements" \
      --sign "${CODESIGN_IDENTITY}" \
      "${APP_BUNDLE}"; then
      break
    fi
    if [[ "${attempt}" -eq 3 ]]; then
      echo "codesign failed after 3 attempts" >&2
      exit 1
    fi
    echo "codesign timestamp transient failure (attempt ${attempt}/3); retrying in 2s..." >&2
    sleep 2
  done
else
  # 优先使用钥匙串中的 Apple Development 证书签名，避免重新编译后丢失 Full Disk Access 授权
  DEV_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development:/ {print $2; exit}')"

  if [[ -n "${DEV_IDENTITY}" ]]; then
    echo "==> Signing with Developer identity: ${DEV_IDENTITY}"
    codesign --force --options runtime \
      --entitlements "${ROOT_DIR}/Config/Mailroom.entitlements" \
      --sign "${DEV_IDENTITY}" \
      "${APP_BUNDLE}"
  else
    echo "==> No Apple Development certificate found; using stable identifier ad-hoc signature (${BUNDLE_ID})"
    codesign --force \
      --identifier "${BUNDLE_ID}" \
      --entitlements "${ROOT_DIR}/Config/Mailroom.entitlements" \
      --sign - \
      "${APP_BUNDLE}"
  fi
fi

echo "==> Built: ${APP_BUNDLE}"
