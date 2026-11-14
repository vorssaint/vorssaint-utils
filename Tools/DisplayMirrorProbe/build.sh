#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
set -euo pipefail
cd "$(dirname "$0")/../.."
destination="$PWD/build/Display Mirror Probe.app"
stage="$(mktemp -d "${TMPDIR:-/tmp}/display-mirror-probe.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
bundle="$stage/Display Mirror Probe.app"
mkdir -p "$bundle/Contents/MacOS" build/probe-module-cache
xcrun swiftc -O -swift-version 5 -warnings-as-errors -target arm64-apple-macosx14.0 \
    -module-cache-path "$PWD/build/probe-module-cache" \
    Tools/DisplayMirrorProbe/ProbeSupport.swift Tools/DisplayMirrorProbe/ProbeRenderer.swift \
    Tools/DisplayMirrorProbe/main.swift \
    -o "$bundle/Contents/MacOS/DisplayMirrorProbe"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.local.display-mirror-probe</string>
<key>CFBundleName</key><string>Display Mirror Probe</string>
<key>CFBundleExecutable</key><string>DisplayMirrorProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Optional existing local identity; never create/import signing credentials.
/usr/bin/codesign --force --sign "${PROBE_SIGN_IDENTITY:--}" "$bundle"
mkdir -p "$destination"
/usr/bin/ditto "$bundle" "$destination"
printf 'Built: %s\n' "$destination"
