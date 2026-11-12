#!/bin/bash
# Builds macApp/build/H1 Control.app: the Kotlin core as a static framework, then the Swift menu bar app.
# Needs only the Command Line Tools (xcode-select --install) and JDK 17.
set -euo pipefail
cd "$(dirname "$0")/.."
export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 17)}"

if ! xcrun xcodebuild -version >/dev/null 2>&1; then
    tools/make-devdir.sh
    export DEVELOPER_DIR="$PWD/.devdir/CommandLineTools"
fi

./gradlew :core:linkReleaseFrameworkMacosArm64 -q

FRAMEWORKS=core/build/bin/macosArm64/releaseFramework
APP="macApp/build/H1 Control.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp macApp/Info.plist "$APP/Contents/Info.plist"
cp macApp/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

swiftc -O -swift-version 5 -parse-as-library \
    -target arm64-apple-macos13.0 \
    -F "$FRAMEWORKS" -framework H1Core -framework IOBluetooth -lc++ \
    -o "$APP/Contents/MacOS/H1Control" \
    macApp/Sources/*.swift

codesign --force --sign - "$APP"
echo "Built $APP"
