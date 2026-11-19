#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/NotchAgentTester.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
[[ -d "$SDK" ]] || SDK="$(xcrun --sdk macosx --show-sdk-path)"
swiftc -O -parse-as-library -target arm64-apple-macosx14.0 -sdk "$SDK" \
    -Xfrontend -interface-compiler-version -Xfrontend 6.3.2 \
    Tools/NotchAgentTester.swift -o "$APP/Contents/MacOS/NotchAgentTester"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key><string>Notch AI Card Tester</string>
    <key>CFBundleExecutable</key><string>NotchAgentTester</string>
    <key>CFBundleIdentifier</key><string>com.vorssaint.notch-agent-tester</string>
    <key>CFBundleName</key><string>Notch AI Card Tester</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null
echo "Tester ready: $APP"
