#!/bin/bash
# Kotlin/Native runs `xcrun xcodebuild -version`, which fails on machines with only the Command Line Tools.
# This builds .devdir/CommandLineTools: symlinks to the real Command Line Tools plus a stub `xcodebuild`
# that prints a version. Use it with DEVELOPER_DIR=.devdir/CommandLineTools. Nothing system-wide changes.
set -euo pipefail
cd "$(dirname "$0")/.."
CLT=/Library/Developer/CommandLineTools
SHIM="$PWD/.devdir/CommandLineTools"
[ -x "$SHIM/usr/bin/xcodebuild" ] && exit 0
rm -rf .devdir
mkdir -p "$SHIM/usr/bin"
ln -s "$CLT/SDKs" "$SHIM/SDKs"
ln -s "$CLT/Library" "$SHIM/Library"
for d in "$CLT"/usr/*; do [ "$(basename "$d")" != bin ] && ln -s "$d" "$SHIM/usr/"; done
for f in "$CLT"/usr/bin/*; do ln -s "$f" "$SHIM/usr/bin/"; done
printf '#!/bin/sh\necho "Xcode 16.2"\necho "Build version 16C5032a"\n' > "$SHIM/usr/bin/xcodebuild"
chmod +x "$SHIM/usr/bin/xcodebuild"
