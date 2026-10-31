#!/bin/sh
# Builds "build/Keynote Companion.app" from the Swift package.
# Set SIGN_IDENTITY to sign with your own certificate; the default is an ad-hoc signature.
set -eu

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
APP="build/Keynote Companion.app"

swift build -c "$CONFIG" --product KeynoteCompanion
BIN="$(swift build -c "$CONFIG" --show-bin-path)/KeynoteCompanion"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/KeynoteCompanion"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" \
    --entitlements Resources/KeynoteCompanion.entitlements "$APP"

echo "Built $APP"
