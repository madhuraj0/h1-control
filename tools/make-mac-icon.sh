#!/bin/bash
# Regenerates macApp/AppIcon.icns from tools/MakeIcon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
swift tools/MakeIcon.swift "$TMP/icon.png"
SET="$TMP/AppIcon.iconset"
mkdir "$SET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$TMP/icon.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o macApp/AppIcon.icns
cp "$TMP/icon.png" macApp/AppIcon.png
rm -rf "$TMP"
echo "Wrote macApp/AppIcon.icns"
