#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$ROOT_DIR/Config/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$INFO_PLIST")"
DIST_DIR="$ROOT_DIR/dist/github-release"
ENV_FILE="$ROOT_DIR/.env.release"

load_env_file() {
  local env_file="$1"

  [[ -f "$env_file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    [[ "$line" != *"="* ]] && continue

    local key="${line%%=*}"
    local value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ ${+parameters[$key]} -eq 1 ]]; then
      continue
    fi

    export "$key=$value"
  done < "$env_file"
}

load_env_file "$ENV_FILE"

: "${NOTARY_PROFILE:?NOTARY_PROFILE is required (for example sift-notary).}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required (for example DengNaichen/sift).}"
: "${GITHUB_TAG:?GITHUB_TAG is required (for example v0.1.0).}"

DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-Developer ID Application}"

expected_build_number_for_version() {
  local version="$1"
  local major=""
  local minor=""
  local patch=""
  local extra=""

  IFS='.' read -r major minor patch extra <<< "$version"

  if [[ -n "$extra" || -z "$major" || -z "$minor" || -z "$patch" ]]; then
    echo "Unsupported CFBundleShortVersionString format: $version" >&2
    echo "Expected semantic version in major.minor.patch format." >&2
    exit 1
  fi

  if [[ ! "$major" =~ '^[0-9]+$' || ! "$minor" =~ '^[0-9]+$' || ! "$patch" =~ '^[0-9]+$' ]]; then
    echo "Unsupported CFBundleShortVersionString format: $version" >&2
    echo "Each semantic version component must be numeric." >&2
    exit 1
  fi

  printf '%d\n' $((10#$major * 1000000 + 10#$minor * 1000 + 10#$patch))
}

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
EXPECTED_TAG_PREFIX="v${VERSION}"
EXPECTED_BUILD="$(expected_build_number_for_version "$VERSION")"

if [[ "$GITHUB_TAG" != "$EXPECTED_TAG_PREFIX" && "$GITHUB_TAG" != ${EXPECTED_TAG_PREFIX}-* ]]; then
  cat <<EOF >&2
Release tag does not match Config/Info.plist version.

Expected tag: ${EXPECTED_TAG_PREFIX} or ${EXPECTED_TAG_PREFIX}-<suffix>
Actual tag:   ${GITHUB_TAG}
App version:  ${VERSION}
App build:    ${BUILD}

Run ./scripts/bump-version.sh <version> before releasing.
EOF
  exit 1
fi

if [[ "$BUILD" != "$EXPECTED_BUILD" ]]; then
  cat <<EOF >&2
Release build number does not match Config/Info.plist version.

Expected CFBundleVersion: ${EXPECTED_BUILD}
Actual CFBundleVersion:   ${BUILD}
App version:              ${VERSION}
EOF
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "$DEVELOPER_ID_APPLICATION"; then
  echo "Missing signing identity: $DEVELOPER_ID_APPLICATION" >&2
  echo "Install the Developer ID Application certificate in Keychain first." >&2
  exit 1
fi

WORK_DIR="$DIST_DIR/$GITHUB_TAG"
APP_PATH="$WORK_DIR/${APP_NAME}.app"
DMG_OUTPUT_DIR="$WORK_DIR/dmg"
DMG_STAGING_DIR="$WORK_DIR/dmg-staging"
APP_ENTITLEMENTS="$WORK_DIR/${APP_NAME}.entitlements.plist"
NOTARY_SUBMISSION_PLIST="$WORK_DIR/notary-submission.plist"
NOTARY_LOG_JSON="$WORK_DIR/notary-log.json"

mkdir -p "$WORK_DIR"
rm -rf "$APP_PATH" "$DMG_OUTPUT_DIR" "$DMG_STAGING_DIR" "$APP_ENTITLEMENTS" "$NOTARY_SUBMISSION_PLIST" "$NOTARY_LOG_JSON"

ARCH="arm64" \
OUTPUT_APP_BUNDLE="$APP_PATH" \
CODESIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  "$ROOT_DIR/scripts/build-app.sh"

BINARY_ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/MailroomApp")"
if [[ "$BINARY_ARCHS" != "arm64" ]]; then
  echo "Expected arm64 binary, got: $BINARY_ARCHS" >&2
  exit 1
fi

codesign --display --entitlements "$APP_ENTITLEMENTS" --xml "$APP_PATH"
plutil -lint "$APP_ENTITLEMENTS" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Creating release DMG..."
mkdir -p "$DMG_OUTPUT_DIR" "$DMG_STAGING_DIR"
RELEASE_DMG_NAME="${RELEASE_DMG_NAME:-${APP_NAME}-${GITHUB_TAG}.dmg}"
FINAL_DMG="$DMG_OUTPUT_DIR/$RELEASE_DMG_NAME"

ditto "$APP_PATH" "$DMG_STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$FINAL_DMG"

for attempt in 1 2 3; do
  if codesign \
    --force \
    --sign "$DEVELOPER_ID_APPLICATION" \
    --timestamp \
    "$FINAL_DMG"; then
    break
  fi
  if [[ "$attempt" -eq 3 ]]; then
    echo "DMG codesign failed after 3 attempts" >&2
    exit 1
  fi
  echo "DMG codesign timestamp transient failure (attempt $attempt/3); retrying in 2s..." >&2
  sleep 2
done

codesign --verify --verbose=2 "$FINAL_DMG"

echo "==> Submitting DMG for Apple notarization..."
xcrun notarytool submit \
  "$FINAL_DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format plist \
  > "$NOTARY_SUBMISSION_PLIST"

NOTARY_ID="$(/usr/libexec/PlistBuddy -c 'Print :id' "$NOTARY_SUBMISSION_PLIST")"
NOTARY_STATUS="$(/usr/libexec/PlistBuddy -c 'Print :status' "$NOTARY_SUBMISSION_PLIST")"

if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
  echo "Notarization failed with status: $NOTARY_STATUS" >&2
  xcrun notarytool log "$NOTARY_ID" "$NOTARY_LOG_JSON" --keychain-profile "$NOTARY_PROFILE" || true
  echo "Saved notarization log to $NOTARY_LOG_JSON" >&2
  exit 1
fi

echo "==> Stapling notarization ticket..."
xcrun stapler staple -v "$FINAL_DMG"
xcrun stapler validate -v "$FINAL_DMG"
if ! spctl -a -vv --type open "$FINAL_DMG"; then
  echo "Warning: spctl assessment failed for $FINAL_DMG, but stapler validation already succeeded."
fi

echo
echo "Release artifacts:"
echo "  App:        $APP_PATH"
echo "  DMG:        $FINAL_DMG"
echo "  Notary ID:  $NOTARY_ID"
