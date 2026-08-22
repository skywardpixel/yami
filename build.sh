#!/bin/bash
# Assembles Yami.app from the SwiftPM build products.
#
# Signing order matters: the helper is nested code, so it must be signed before
# the bundle that seals it. SMAppService will refuse a daemon whose signature
# does not match the plist it was registered from.
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Yami.app"
# First available signing identity, unless told otherwise.
IDENTITY="${YAMI_IDENTITY:-$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application|Apple Development/ {print $2; exit}')}"
if [ -z "$IDENTITY" ]; then
    echo "no code signing identity found; set YAMI_IDENTITY" >&2
    exit 1
fi

# The app icon is drawn from the same crescent as the menu bar mark, so it is
# generated rather than checked in as an opaque binary.
if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
    mkdir -p "$ROOT/build"
    swiftc -O "$ROOT/Sources/Yami/MenuBarIcon.swift" "$ROOT/tools/main.swift" \
        -o "$ROOT/build/makeicon"
    "$ROOT/build/makeicon" "$ROOT/Resources/AppIcon.icns"
fi

swift build -c "$CONFIG" --product Yami
# The app icon is drawn from the same crescent as the menu bar mark, so it is
# generated rather than checked in as an opaque binary.
if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
    mkdir -p "$ROOT/build"
    swiftc -O "$ROOT/Sources/Yami/MenuBarIcon.swift" "$ROOT/tools/main.swift" \
        -o "$ROOT/build/makeicon"
    "$ROOT/build/makeicon" "$ROOT/Resources/AppIcon.icns"
fi

swift build -c "$CONFIG" --product YamiHelper
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchDaemons" "$APP/Contents/Resources"
cp "$BIN/Yami" "$APP/Contents/MacOS/Yami"
cp "$BIN/YamiHelper" "$APP/Contents/MacOS/dev.yami.helper"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/dev.yami.helper.plist" "$APP/Contents/Library/LaunchDaemons/"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"

codesign --force --options runtime --identifier dev.yami.helper \
    --sign "$IDENTITY" "$APP/Contents/MacOS/dev.yami.helper" 2>&1 | sed 's/^/  /'
codesign --force --options runtime --identifier dev.yami \
    --sign "$IDENTITY" "$APP" 2>&1 | sed 's/^/  /'

codesign --verify --deep --strict "$APP"
echo "built $APP"
