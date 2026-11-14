#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
ENV_FILE="$ROOT_DIR/.env.release"

if [[ -f "$ENV_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "${line:0:1}" == "#" || "$line" != *"="* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ ${+parameters[$key]} -eq 0 ]]; then
      export "$key=$value"
    fi
  done < "$ENV_FILE"
fi

PROFILE_NAME="${1:-${NOTARY_PROFILE:-sift-notary}}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APP_SPECIFIC_PASSWORD="${APP_SPECIFIC_PASSWORD:-}"

if [[ -z "$APPLE_ID" ]]; then
  echo "APPLE_ID is required."
  exit 1
fi

if [[ -z "$APPLE_TEAM_ID" ]]; then
  echo "APPLE_TEAM_ID is required."
  exit 1
fi

COMMAND=(
  xcrun notarytool store-credentials
  "$PROFILE_NAME"
  --apple-id "$APPLE_ID"
  --team-id "$APPLE_TEAM_ID"
  --validate
)

if [[ -n "$APP_SPECIFIC_PASSWORD" ]]; then
  COMMAND+=(--password "$APP_SPECIFIC_PASSWORD")
fi

echo "Storing notarytool credentials in Keychain profile '$PROFILE_NAME'..."
"${COMMAND[@]}"

echo
echo "Saved Keychain profile: $PROFILE_NAME"
