#!/usr/bin/env bash
# Builds dist/Email2Claude.app and dist/Email2Claude.dmg for Apple Silicon.
#
# Optional environment (all three groups needed for a notarized build):
#   SIGN_IDENTITY   "Developer ID Application: Name (TEAMID)"; unset = ad-hoc signing
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD   notarytool credentials
#   VERSION         defaults to 0.1.0
set -euo pipefail
cd "$(dirname "$0")/.."

NAME=Email2Claude
VERSION=${VERSION:-0.1.0}
IDENTITY=${SIGN_IDENTITY:--}
APP=dist/$NAME.app
DMG=dist/$NAME.dmg

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
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/$NAME" "$APP/Contents/MacOS/$NAME"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
sign --entitlements Resources/$NAME.entitlements "$APP"

if [ -n "${APPLE_ID:-}" ] && [ "$IDENTITY" != "-" ]; then
    ditto -c -k --keepParent "$APP" dist/$NAME.zip
    notarize dist/$NAME.zip
    xcrun stapler staple "$APP"
    rm dist/$NAME.zip
fi

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

sign "$DMG"
notarize "$DMG"
if [ -n "${APPLE_ID:-}" ] && [ "$IDENTITY" != "-" ]; then xcrun stapler staple "$DMG"; fi

echo "Built $DMG"
