#!/bin/bash
# Notarizes and staples build/Yami.app using a stored notarytool profile.
#
# The profile is created once, by you, so no key material passes through this
# script or the repository:
#
#   xcrun notarytool store-credentials yami \
#       --key ~/Downloads/AuthKey_XXXXXXXX.p8 \
#       --key-id XXXXXXXXXX \
#       --issuer xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#
# CI does the same work from repository secrets; this exists to prove the chain
# locally before trusting it in a release.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Yami.app"
PROFILE="${YAMI_NOTARY_PROFILE:-yami}"
UPLOAD="$(mktemp -d)/Yami.zip"

[ -d "$APP" ] || { echo "no build/Yami.app — run ./build.sh release first" >&2; exit 1; }

# Captured first, and parsed without an early `exit`: awk quitting mid-stream
# SIGPIPEs codesign, which `pipefail` turns into an abort.
SIGNATURE="$(codesign -dv --verbose=2 "$APP" 2>&1 || true)"
IDENTITY="$(printf '%s\n' "$SIGNATURE" | awk -F= '/^Authority/ && !seen {print $2; seen=1}')"
case "$IDENTITY" in
    "Developer ID Application"*) ;;
    *)
        echo "app is signed by '${IDENTITY:-nothing}', not a Developer ID certificate." >&2
        echo "Apple will reject it. Rebuild once the Developer ID cert exists." >&2
        exit 1
        ;;
esac

echo "submitting to Apple (this usually takes a few minutes)…"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$UPLOAD"
xcrun notarytool submit "$UPLOAD" --keychain-profile "$PROFILE" --wait --timeout 30m
rm -f "$UPLOAD"

# Stapling writes the ticket into the bundle so it validates without a network.
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo
echo "Gatekeeper's verdict on a fresh download:"
spctl -a -t exec -vvv "$APP"
