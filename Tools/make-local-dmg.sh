#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Packages an installed build into a DMG signed with a local Apple Development
# certificate (no Developer ID, no notarization). Usage:
#   ./Tools/make-local-dmg.sh ["/Applications/Vorssaint (Developer).app"]
# Re-signs the app inside-out first, then writes dist/<name>.dmg.
# Anyone installing it must clear the quarantine flag once, because the DMG is
# not notarized:  xattr -dr com.apple.quarantine "/Applications/<name>.app"
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-/Applications/Vorssaint (Developer).app}"
ID="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep 'Apple Development' | head -1 | sed -E 's/^ *[0-9]+\) ([0-9A-F]+) .*/\1/')}"
[[ -d "$SRC" ]] || { echo "✗ $SRC not found" >&2; exit 1; }
[[ -n "$ID" ]] || { echo "✗ no Apple Development identity in the keychain" >&2; exit 1; }
NAME="$(basename "$SRC" .app)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$SRC/Contents/Info.plist")"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/$NAME.app"
ditto "$SRC" "$APP"
xattr -cr "$APP"

echo "▸ Signing with $ID…"
FAN="$(ls "$APP/Contents/Library/LaunchServices" 2>/dev/null | head -1 || true)"
while IFS= read -r f; do
    codesign --force --strip-disallowed-xattrs --sign "$ID" "$f"
done < <(find "$APP/Contents/Frameworks" "$APP/Contents/Resources/bin" -type f \( -name '*.dylib' -o -perm -111 \) 2>/dev/null)
[[ -n "$FAN" ]] && codesign --force --strip-disallowed-xattrs --identifier "$FAN" --sign "$ID" \
    "$APP/Contents/Library/LaunchServices/$FAN"
[[ -f "$APP/Contents/MacOS/VorssaintDictationWorker" ]] && codesign --force --strip-disallowed-xattrs --sign "$ID" \
    "$APP/Contents/MacOS/VorssaintDictationWorker"
codesign --force --strip-disallowed-xattrs --entitlements Resources/Vorssaint.entitlements --sign "$ID" "$APP"
codesign --verify --deep --strict "$APP"

mkdir -p dist
OUT="dist/${NAME// /-}-$VERSION.dmg"
rm -f "$OUT"
ln -s /Applications "$STAGE/Applications"
echo "▸ Writing $OUT…"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
codesign --force --sign "$ID" "$OUT"
codesign --verify "$OUT" && echo "✓ $OUT ($(du -h "$OUT" | cut -f1))"
