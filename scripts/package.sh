#!/usr/bin/env bash
# Builds "dist/MailtoChat.app" and dist/MailtoChat.dmg for Apple Silicon.
#
# Optional environment (all three groups needed for a notarized build):
#   SIGN_IDENTITY   "Developer ID Application: Name (TEAMID)"; unset = ad-hoc signing
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD   notarytool credentials
#   VERSION         defaults to 1.0
set -euo pipefail
cd "$(dirname "$0")/.."

EXECUTABLE=Email2Claude
DISPLAY_NAME="MailtoChat"
VERSION=${VERSION:-1.0}
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

# Submits once, then polls for the verdict. Polling (instead of `notarytool --wait`) means a
# dropped network connection during Apple's queue is retried rather than failing the whole build.
# Gives up after NOTARIZE_TIMEOUT_MIN minutes (default 120), or after $2 minutes when given.
# With $3 = soft, a timeout or rejection returns 1 instead of exiting, so the caller can carry on.
notarize() {
    local timeout_min=${2:-${NOTARIZE_TIMEOUT_MIN:-120}} soft=${3:-}
    [ -n "${APPLE_ID:-}" ] && [ "$IDENTITY" != "-" ] || return 0
    local creds=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
    local id="" out try
    for try in 1 2 3 4 5; do
        if out=$(xcrun notarytool submit "$1" "${creds[@]}" --output-format plist); then
            id=$(printf '%s' "$out" | plutil -extract id raw -o - -)
            break
        fi
        echo "Submit attempt $try failed; retrying"; sleep 15
    done
    [ -n "$id" ] || { echo "Could not submit $1 for notarization"; [ "$soft" = soft ] && return 1; exit 1; }
    echo "Submitted $1 for notarization: $id"

    local deadline=$((SECONDS + timeout_min * 60)) status
    while [ "$SECONDS" -lt "$deadline" ]; do
        if out=$(xcrun notarytool info "$id" "${creds[@]}" --output-format plist 2>/dev/null); then
            status=$(printf '%s' "$out" | plutil -extract status raw -o - - 2>/dev/null || echo unknown)
            echo "Notarization status: $status"
            case "$status" in
                Accepted) return 0 ;;
                Invalid|Rejected)
                    xcrun notarytool log "$id" "${creds[@]}" || true
                    [ "$soft" = soft ] && return 1
                    exit 1 ;;
            esac
        else
            echo "Status check failed (network?); will retry"
        fi
        sleep 30
    done
    echo "Notarization of $1 not finished after $timeout_min minutes (submission $id)"
    [ "$soft" = soft ] && return 1
    exit 1
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
# The app inside is already notarized and stapled, which is what Gatekeeper and the updater check,
# so the DMG's own notarization is a bonus: give it a short window and carry on without it.
if [ -n "${APPLE_ID:-}" ] && [ "$IDENTITY" != "-" ]; then
    if notarize "$DMG" 10 soft; then
        xcrun stapler staple "$DMG"
    else
        echo "warning: $DMG is signed but not notarized; the app inside is."
    fi
fi

echo "Built $DMG"
