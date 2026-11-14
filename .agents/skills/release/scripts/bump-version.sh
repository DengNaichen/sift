#!/bin/zsh
set -euo pipefail

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>  (e.g. $0 0.1.0)"
  exit 1
fi

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "Error: version must be in major.minor.patch format (got: $VERSION)"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
INFO_PLIST="$ROOT_DIR/Config/Info.plist"

cd "$ROOT_DIR"

if [[ "$(git branch --show-current)" != "main" ]]; then
  echo "Error: run this script from the main branch."
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: working tree must be clean before releasing."
  exit 1
fi

git fetch origin main
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  echo "Error: local main is not synchronized with origin/main."
  echo "Run: git merge --ff-only origin/main"
  exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"
BUILD_NUMBER=$(( 10#$MAJOR * 1000000 + 10#$MINOR * 1000 + 10#$PATCH ))

CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
CURRENT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
TAG="v$VERSION"

if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
  echo "Error: local tag $TAG already exists."
  exit 1
fi
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "Error: remote tag $TAG already exists."
  exit 1
fi

if [[ "$CURRENT_VERSION" != "$VERSION" || "$CURRENT_BUILD" != "$BUILD_NUMBER" ]]; then
  echo "Bumping $CURRENT_VERSION ($CURRENT_BUILD) → $VERSION (build $BUILD_NUMBER)"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"

  git add Config/Info.plist
  git commit -m "chore: bump version to $VERSION"
  git push origin HEAD:refs/heads/main
else
  echo "Config/Info.plist is already at $VERSION (build $BUILD_NUMBER); tagging HEAD."
fi

git tag "$TAG"
git push origin "$TAG"

echo "Released $TAG (build $BUILD_NUMBER)"
