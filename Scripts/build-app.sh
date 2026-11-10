#!/bin/bash
# Builds Sunroom.app from the SwiftPM executable.
#
#   ./Scripts/build-app.sh              # release, current arch
#   ./Scripts/build-app.sh --universal  # arm64 + x86_64
#   ./Scripts/build-app.sh --debug
#
# The result lands in dist/Sunroom.app and is ad-hoc signed, which is enough
# for local use including Accessibility and Screen Recording. Distributing to
# other Macs requires a Developer ID signature and notarization.

set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="release"
UNIVERSAL=false
for arg in "$@"; do
  case "$arg" in
    --debug) CONFIG="debug" ;;
    --universal) UNIVERSAL=true ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

APP_NAME="Sunroom"
BUNDLE_ID="com.shashvat1965.sunroom"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building ($CONFIG)"
if [ "$UNIVERSAL" = true ]; then
  swift build -c "$CONFIG" --arch arm64 --arch x86_64 --product "$APP_NAME"
  BIN_PATH="$(swift build -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path)"
else
  swift build -c "$CONFIG" --product "$APP_NAME"
  BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
fi

BINARY="$BIN_PATH/$APP_NAME"
if [ ! -f "$BINARY" ]; then
  echo "error: built binary not found at $BINARY" >&2
  exit 1
fi

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true

if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
  echo "    (no AppIcon.icns yet — run: swift Scripts/make-icon.swift)"
fi

# Localized app name for the About window.
mkdir -p "$APP/Contents/Resources/en.lproj"
cat > "$APP/Contents/Resources/en.lproj/InfoPlist.strings" <<EOF
CFBundleName = "$APP_NAME";
CFBundleDisplayName = "$APP_NAME";
EOF

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null 2>&1 || {
  echo "    codesign failed; the app will still run, but permissions may not stick." >&2
}

# Refresh Launch Services so the icon and document types appear immediately.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1 || true

echo "==> Done: $APP  (bundle id: $BUNDLE_ID)"
echo "    open \"$APP\""
