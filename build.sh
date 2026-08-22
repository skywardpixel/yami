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
# Developer ID first: it is the only identity a downloaded build can be
# notarized with. `security` lists Apple Development first, so taking the first
# match would quietly sign releases with a certificate Apple rejects.
#
# Captured once and parsed without an early `exit` — awk quitting mid-stream
# SIGPIPEs `security`, which `pipefail` turns into a silent abort.
IDENTITY="${YAMI_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    AVAILABLE="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    for PATTERN in "Developer ID Application" "Apple Development"; do
        IDENTITY="$(printf '%s\n' "$AVAILABLE" \
            | awk -F'"' -v p="$PATTERN" 'index($0, p) && !seen {print $2; seen=1}')"
        [ -n "$IDENTITY" ] && break
    done
fi
if [ -z "$IDENTITY" ]; then
    echo "no code signing identity found; set YAMI_IDENTITY" >&2
    exit 1
fi
echo "signing as: $IDENTITY"

# The app icon is drawn from the same crescent as the menu bar mark, so it is
# generated rather than checked in as an opaque binary.
if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
    mkdir -p "$ROOT/build"
    swiftc -O "$ROOT/Sources/Yami/MenuBarIcon.swift" "$ROOT/tools/GenerateArtwork.swift" \
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
    swiftc -O "$ROOT/Sources/Yami/MenuBarIcon.swift" "$ROOT/tools/GenerateArtwork.swift" \
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

# Stamped before signing, never after: editing Info.plist invalidates the seal.
# CI derives these from the commit, so a downloaded build says where it came from.
if [ -n "${YAMI_VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $YAMI_VERSION" \
        "$APP/Contents/Info.plist"
fi
if [ -n "${YAMI_BUILD:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $YAMI_BUILD" "$APP/Contents/Info.plist"
fi
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

codesign --force --options runtime --timestamp --identifier dev.yami.helper \
    --sign "$IDENTITY" "$APP/Contents/MacOS/dev.yami.helper" 2>&1 | sed 's/^/  /'

# Upstream ships it ad-hoc signed as "a.out" with no hardened runtime, which
# fails notarization. Re-sign before the bundle is sealed: nested code first.
if [ "$BUNDLED_CORE" = "1" ]; then
    codesign --force --options runtime --timestamp --identifier dev.yami.mihomo \
        --sign "$IDENTITY" "$APP/Contents/MacOS/mihomo" 2>&1 | sed 's/^/  /'
fi
codesign --force --options runtime --timestamp --identifier dev.yami \
    --sign "$IDENTITY" "$APP" 2>&1 | sed 's/^/  /'

codesign --verify --deep --strict "$APP"
echo "built $APP"
