#!/usr/bin/env bash
# Builds "dist/MailtoChat.app" and dist/MailtoChat.dmg for Apple Silicon.
#
# Optional environment (all three groups needed for a notarized build):
#   SIGN_IDENTITY   "Developer ID Application: Name (TEAMID)"; unset = ad-hoc signing
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD   notarytool credentials
#   VERSION         defaults to 0.1.0
set -euo pipefail
cd "$(dirname "$0")/.."

EXECUTABLE=Email2Claude
DISPLAY_NAME="MailtoChat"
VERSION=${VERSION:-0.1.0}
IDENTITY=${SIGN_IDENTITY:--}
APP="dist/$DISPLAY_NAME.app"
DMG="dist/MailtoChat.dmg"

sign() {
    if [ "$IDENTITY" = "-" ]; then
        codesign --force --sign - --options runtime --timestamp=none "$@"
    else
        codesign --force --sign "$IDENTITY" --options runtime --timestamp "$@"
    fi
}

notarize() {
    [ -n "${APPLE_ID:-}" ] && [ "$IDENTITY" != "-" ] || return 0
    xcrun notarytool submit "$1" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" --wait
}

swift build -c release --arch arm64
BIN=$(swift build -c release --arch arm64 --show-bin-path)

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/MenuBarIcon.png "$APP/Contents/Resources/"

# App icon: build AppIcon.icns from the 1024 px master.
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

sign --entitlements Resources/$EXECUTABLE.entitlements "$APP"

if [ -n "${APPLE_ID:-}" ] && [ "$IDENTITY" != "-" ]; then
    ditto -c -k --keepParent "$APP" dist/notarize.zip
    notarize dist/notarize.zip
    xcrun stapler staple "$APP"
    rm dist/notarize.zip
fi

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

sign "$DMG"
notarize "$DMG"
if [ -n "${APPLE_ID:-}" ] && [ "$IDENTITY" != "-" ]; then xcrun stapler staple "$DMG"; fi

echo "Built $DMG"
