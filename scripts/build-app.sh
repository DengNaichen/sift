#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Mailroom"
BUNDLE_ID="dev.mailroom.deck"
DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"

echo "==> Building MailroomApp (Release)..."
swift build -c release --package-path "${ROOT_DIR}"

BIN_PATH="$(swift build -c release --show-bin-path --package-path "${ROOT_DIR}")/MailroomApp"

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/MailroomApp"
cp "${ROOT_DIR}/Config/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
chmod +x "${APP_BUNDLE}/Contents/MacOS/MailroomApp"

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

echo "==> Built: ${APP_BUNDLE}"
