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

# A release build always ships the core; debug builds bundle it only if it has
# already been fetched, so day-to-day iteration does not wait on a 43 MB
# download and falls back to the Homebrew binary instead.
if [ "$CONFIG" = "release" ] && [ ! -x "$ROOT/vendor/mihomo" ]; then
    "$ROOT/scripts/fetch-mihomo.sh"
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

# A release build always ships the core; debug builds bundle it only if it has
# already been fetched, so day-to-day iteration does not wait on a 43 MB
# download and falls back to the Homebrew binary instead.
if [ "$CONFIG" = "release" ] && [ ! -x "$ROOT/vendor/mihomo" ]; then
    "$ROOT/scripts/fetch-mihomo.sh"
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

if [ -x "$ROOT/vendor/mihomo" ]; then
    cp "$ROOT/vendor/mihomo" "$APP/Contents/MacOS/mihomo"
    # mihomo is GPL-3.0; bundling it is redistribution, so its licence ships too.
    cp "$ROOT/vendor/mihomo-LICENSE.txt" "$APP/Contents/Resources/"
    BUNDLED_CORE=1
else
    echo "  note: no vendor/mihomo — the app will fall back to /opt/homebrew/bin/mihomo"
    echo "        run scripts/fetch-mihomo.sh to bundle the core"
    BUNDLED_CORE=0
fi

codesign --force --options runtime --identifier dev.yami.helper \
    --sign "$IDENTITY" "$APP/Contents/MacOS/dev.yami.helper" 2>&1 | sed 's/^/  /'

# Upstream ships it ad-hoc signed as "a.out" with no hardened runtime, which
# fails notarization. Re-sign before the bundle is sealed: nested code first.
if [ "$BUNDLED_CORE" = "1" ]; then
    codesign --force --options runtime --identifier dev.yami.mihomo \
        --sign "$IDENTITY" "$APP/Contents/MacOS/mihomo" 2>&1 | sed 's/^/  /'
fi
codesign --force --options runtime --identifier dev.yami \
    --sign "$IDENTITY" "$APP" 2>&1 | sed 's/^/  /'

codesign --verify --deep --strict "$APP"
echo "built $APP"
