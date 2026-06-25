#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="差旅报销助手"
EXECUTABLE_NAME="TravelExpenseDesk"
DIST_DIR="$ROOT_DIR/dist"
DIST_APP_DIR="$DIST_DIR/$APP_NAME.app"
STAGING_ROOT="/private/tmp/TravelExpenseDeskPackage"
APP_DIR="$STAGING_ROOT/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/$APP_NAME.zip"
MODULE_CACHE_DIR="$ROOT_DIR/.build/module-cache"
ICON_BACKUP="$MODULE_CACHE_DIR/AppIcon.icns.backup"

mkdir -p "$MODULE_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"
export SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"

cd "$ROOT_DIR"
if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$ICON_BACKUP"
fi

if ! swift scripts/generate_app_icon.swift >/dev/null; then
  if [[ -f "$ICON_BACKUP" ]]; then
    cp "$ICON_BACKUP" "$ROOT_DIR/Resources/AppIcon.icns"
  fi
  if [[ ! -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
    echo "App icon generation failed and Resources/AppIcon.icns is missing." >&2
    exit 1
  fi
  echo "App icon generation failed; using existing Resources/AppIcon.icns." >&2
fi
swift build -c release

rm -rf "$STAGING_ROOT"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp ".build/release/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

rm -rf "$APP_DIR/Contents/_CodeSignature"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_DIR" || true
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
  codesign --verify --deep --strict "$APP_DIR"
fi

mkdir -p "$DIST_DIR"
rm -rf "$DIST_APP_DIR"
rm -f "$ZIP_PATH"
ditto --noextattr --noqtn "$APP_DIR" "$DIST_APP_DIR"
ditto -c -k --keepParent --norsrc --noextattr --noqtn "$APP_DIR" "$ZIP_PATH"

echo "$APP_DIR"
echo "$ZIP_PATH"
