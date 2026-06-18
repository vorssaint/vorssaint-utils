#!/bin/zsh
# MemoryKill — fork of vorssaint-utils focused on RAM purge/monitor.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MemoryKill"
EXECUTABLE="MemoryKill"
TARGET="arm64-apple-macosx14.0"
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
    esac
done

PINNED_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
if [[ -d "$PINNED_SDK" ]]; then
    SDK="$PINNED_SDK"
else
    SDK="$(xcrun --show-sdk-path)"
fi

echo "▸ Compiling MemoryKill against $(basename "$SDK")…"
rm -rf build
mkdir -p build
swiftc -O -target "$TARGET" -sdk "$SDK" \
    Sources/Vorssaint/**/*.swift \
    -o "build/$EXECUTABLE"

echo "▸ Assembling bundle…"
STAGE="$(mktemp -d)/$APP_NAME.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "build/$EXECUTABLE" "$STAGE/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.cashie.memorykill" "$STAGE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName MemoryKill" "$STAGE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName MemoryKill" "$STAGE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXECUTABLE" "$STAGE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.0.0" "$STAGE/Contents/Info.plist"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"
xattr -cr "$STAGE"
codesign --force --sign - "$STAGE"

mkdir -p "build/stage"
BUILD_STAGE="build/stage/$APP_NAME.app"
rm -rf "$BUILD_STAGE"
ditto "$STAGE" "$BUILD_STAGE"
echo "✓ Bundle ready: $BUILD_STAGE"

if (( INSTALL )); then
    DEST="/Applications/$APP_NAME.app"
    pkill -x "$EXECUTABLE" 2>/dev/null || true
    rm -rf "$DEST"
    ditto "$STAGE" "$DEST"
    codesign --force --sign - "$DEST"
    open "$DEST"
    echo "✓ Installed: $DEST"
fi