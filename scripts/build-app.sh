#!/bin/sh
# Builds "build/Keynote Companion.app" from the Swift package.
# Set SIGN_IDENTITY to sign with your own certificate; the default is an ad-hoc signature.
# Set UNIVERSAL=1 to build for both Apple silicon and Intel, and VERSION to stamp the bundle version.
set -eu

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
APP="build/Keynote Companion.app"
IDENTITY="${SIGN_IDENTITY:--}"

if [ "${UNIVERSAL:-0}" = "1" ]; then
    set -- --arch arm64 --arch x86_64
else
    set --
fi

swift build -c "$CONFIG" --product KeynoteCompanion ${1+"$@"}
BIN="$(swift build -c "$CONFIG" --show-bin-path ${1+"$@"})/KeynoteCompanion"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/KeynoteCompanion"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi

# Notarization needs a secure timestamp, which an ad-hoc signature cannot have.
if [ "$IDENTITY" = "-" ]; then
    set -- --sign -
else
    set -- --sign "$IDENTITY" --timestamp
fi
codesign --force --options runtime "$@" \
    --entitlements Resources/KeynoteCompanion.entitlements "$APP"

echo "Built $APP"
