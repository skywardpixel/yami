#!/bin/bash
# Downloads the pinned mihomo core into vendor/ so build.sh can bundle it.
#
# Upstream publishes no checksums or signatures for its release assets, so the
# hashes below were recorded from a download verified by hand (it runs and
# reports the pinned version, Go build and tags). Everything after that first
# pin is reproducible: a changed artefact fails here rather than being signed
# with our identity and shipped.
set -euo pipefail

VERSION="v1.19.30"
ASSET="mihomo-darwin-arm64-${VERSION}.gz"
GZ_SHA256="2c7f3a7904fa1cee291e124123e630e7b1ebd13765dd9bf26c0a28432004d9f4"
BIN_SHA256="e80c6334b4e3aae53dfbc86cddd4434cec1565a61d4483931fac2ae12fec6d30"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor"
BINARY="$VENDOR/mihomo"
LICENSE="$VENDOR/mihomo-LICENSE.txt"

verify() {  # <file> <expected sha256> <label>
    local actual
    actual="$(shasum -a 256 "$1" | cut -d' ' -f1)"
    if [ "$actual" != "$2" ]; then
        echo "checksum mismatch for $3" >&2
        echo "  expected $2" >&2
        echo "  actual   $actual" >&2
        rm -f "$1"
        exit 1
    fi
}

mkdir -p "$VENDOR"

if [ -x "$BINARY" ] && [ "$(shasum -a 256 "$BINARY" | cut -d' ' -f1)" = "$BIN_SHA256" ]; then
    echo "mihomo $VERSION already vendored"
else
    echo "fetching mihomo $VERSION (arm64)…"
    curl -fsSL --max-time 300 -o "$VENDOR/$ASSET" \
        "https://github.com/MetaCubeX/mihomo/releases/download/${VERSION}/${ASSET}"
    verify "$VENDOR/$ASSET" "$GZ_SHA256" "$ASSET"

    gzip -dc "$VENDOR/$ASSET" > "$BINARY"
    rm -f "$VENDOR/$ASSET"
    verify "$BINARY" "$BIN_SHA256" "mihomo binary"
    chmod +x "$BINARY"
    echo "  vendored $($BINARY -v | head -1)"
fi

# mihomo is GPL-3.0. Bundling it means redistributing it, so the licence ships
# with the app and the README points at the exact tag these bytes came from.
if [ ! -s "$LICENSE" ]; then
    curl -fsSL --max-time 60 -o "$LICENSE" \
        "https://raw.githubusercontent.com/MetaCubeX/mihomo/${VERSION}/LICENSE"
    grep -q "GNU GENERAL PUBLIC LICENSE" "$LICENSE" || {
        echo "unexpected licence content" >&2; rm -f "$LICENSE"; exit 1
    }
    echo "  vendored licence"
fi
