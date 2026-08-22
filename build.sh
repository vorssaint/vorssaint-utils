#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Builds Vorssaint, assembles the .app bundle, signs it and (with --install)
# installs it into /Applications.
#
# The bundle is staged in a temporary directory outside ~/Documents: folders synced
# by File Provider gain xattrs (com.apple.provenance etc.) that invalidate codesign.
set -euo pipefail
cd "$(dirname "$0")"

# Flags: --dev builds the local-only "Vorssaint (Developer)" variant (its own
# bundle id, so it coexists with the official app); --install puts it in /Applications.
DEV=0
INSTALL=0
TEST=0
for arg in "$@"; do
    case "$arg" in
        --dev)     DEV=1 ;;
        --install) INSTALL=1 ;;
        --test)    TEST=1 ;;
    esac
done

if (( DEV )); then
    APP_NAME="Vorssaint (Developer)"
    EXECUTABLE="VorssaintDeveloper"
    APP_BUNDLE_ID="com.vorssaint.utils.dev"
    BUILD_VARIANT_FLAGS=(-D VORSSAINT_DEVELOPMENT)
    APP_OPTIMIZATION_FLAGS=(-Onone)
    BUILD_CONFIGURATION="debug"
else
    APP_NAME="Vorssaint"
    EXECUTABLE="Vorssaint"
    APP_BUNDLE_ID="com.vorssaint.utils"
    BUILD_VARIANT_FLAGS=()
    APP_OPTIMIZATION_FLAGS=(-O)
    BUILD_CONFIGURATION="release"
fi
FAN_HELPER_ID="$APP_BUNDLE_ID.fan-control"
TARGET="arm64-apple-macosx14.0"
ENTITLEMENTS="Resources/Vorssaint.entitlements"
LEGACY_IDENTITY="Vorssaint Utils Signing"

developer_id_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | grep 'Developer ID Application' \
        | head -1 \
        | sed -E 's/.*"(.*)".*/\1/' || true
}

codesign_with_timestamp_retry() {
    local attempt
    for attempt in 1 2 3; do
        if /usr/bin/codesign "$@"; then
            return 0
        fi
        if (( attempt < 3 )); then
            echo "  Developer ID signing failed; retrying ($((attempt + 1))/3)"
            sleep "$attempt"
        fi
    done
    return 1
}

write_swift_output_file_map() {
    local output_file="$1"
    local object_dir="$2"
    shift 2
    local source artifact

    {
        print -r -- "{"
        print -r -- "  \"\": {"
        print -r -- "    \"swift-dependencies\": \"$object_dir/master.swiftdeps\""
        print -r -- "  }"
        for source in "$@"; do
            artifact="${source//\//__}"
            artifact="${artifact%.swift}"
            print -r -- ","
            print -r -- "  \"$source\": {"
            print -r -- "    \"object\": \"$object_dir/$artifact.o\","
            print -r -- "    \"swift-dependencies\": \"$object_dir/$artifact.swiftdeps\""
            print -r -- "  }"
        done
        print -r -- "}"
    } > "$output_file"
}

finalize_installed_bundle_after_child() {
    local bundle="$1"
    local helper="$bundle/Contents/Library/LaunchServices/$FAN_HELPER_ID"
    local devid
    devid="$(developer_id_identity)"

    echo "▸ Finalizing installed signature…"
    sleep 3
    if [[ -n "$devid" ]]; then
        [[ -f "$helper" ]] && codesign_with_timestamp_retry --force --strip-disallowed-xattrs \
            --options runtime --timestamp --identifier "$FAN_HELPER_ID" --sign "$devid" "$helper"
        codesign_with_timestamp_retry --force --strip-disallowed-xattrs --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS" --sign "$devid" "$bundle"
    elif security find-identity -p codesigning 2>/dev/null | grep -q "$LEGACY_IDENTITY"; then
        [[ -f "$helper" ]] && /usr/bin/codesign --force --strip-disallowed-xattrs \
            --identifier "$FAN_HELPER_ID" --sign "$LEGACY_IDENTITY" "$helper"
        /usr/bin/codesign --force --strip-disallowed-xattrs --sign "$LEGACY_IDENTITY" "$bundle"
    else
        [[ -f "$helper" ]] && /usr/bin/codesign --force --strip-disallowed-xattrs \
            --identifier "$FAN_HELPER_ID" --sign - "$helper"
        /usr/bin/codesign --force --strip-disallowed-xattrs --sign - "$bundle"
    fi
    [[ -f "$helper" ]] && /usr/bin/codesign --verify --strict "$helper"
    /usr/bin/codesign --verify --deep --strict "$bundle"
    echo "✓ Signature ready: $bundle"
}

if (( INSTALL && ! TEST )) && [[ "${VORSSAINT_INSTALL_CHILD:-0}" != "1" ]]; then
    VORSSAINT_INSTALL_CHILD=1 "$0" "$@"
    child_status=$?
    if (( child_status != 0 )); then
        exit "$child_status"
    fi
    finalize_installed_bundle_after_child "/Applications/$APP_NAME.app"
    exit 0
fi

# Prefer the macOS 26 SDK when present: the 27 SDK turns SwiftUI property wrappers
# into macros (SwiftUIMacros plugin) that the Command Line Tools cannot load yet.
PINNED_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    SDK="$(xcrun --show-sdk-path)"
elif [[ -d "$PINNED_SDK" ]]; then
    SDK="$PINNED_SDK"
else
    SDK="$(xcrun --show-sdk-path)"
fi
SDK_COMPAT_FLAGS=()
if [[ "$SDK" == "$PINNED_SDK" ]]; then
    # Swift 6.4 can read the SDK 26 interfaces when given their compiler version.
    SDK_COMPAT_FLAGS=(-Xfrontend -interface-compiler-version -Xfrontend 6.3.2)
fi

# --test: compile and run the standalone unit tests (pure helpers only: metrics,
# Homebrew parsing, defaults, localization contracts; no app, no UI, no IOKit),
# then exit. Fast and deterministic; no XCTest needed.
if (( TEST )); then
    echo "▸ Building & running unit tests against $(basename "$SDK")…"
    rm -rf build
    mkdir -p build
    # The full app build below remains optimized and is the optimizer gate.
    # Unit assertions do not need optimization; avoiding it cuts most of the
    # test harness compile time without reducing the code the tests exercise.
    swiftc -Onone -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" \
        Sources/Vorssaint/Services/Media/MediaSupport.swift \
        Sources/Vorssaint/Core/Defaults.swift \
        Sources/Vorssaint/Core/FeatureCatalog.swift \
        Sources/Vorssaint/Core/FeaturePresets.swift \
        Sources/Vorssaint/Core/FeatureHubStrings.swift \
        Sources/Vorssaint/Core/ShortcutSettingsStrings.swift \
        Sources/Vorssaint/Core/SettingsBackupSupport.swift \
        Sources/Vorssaint/Core/BackupStrings.swift \
        Sources/Vorssaint/Core/SnippetStrings.swift \
        Sources/Vorssaint/Core/BrightnessStrings.swift \
        Sources/Vorssaint/Core/MediaImageStrings.swift \
        Sources/Vorssaint/Core/QuickToggleStrings.swift \
        Sources/Vorssaint/Core/ScreenshotStrings.swift \
        Sources/Vorssaint/Core/RecentCaptureStrings.swift \
        Sources/Vorssaint/Core/RecorderStrings.swift \
        Sources/Vorssaint/Core/RecorderShareStrings.swift \
        Sources/Vorssaint/Core/CameraPreviewStrings.swift \
        Sources/Vorssaint/Core/ScratchpadStrings.swift \
        Sources/Vorssaint/Core/FinderRenameStrings.swift \
        Sources/Vorssaint/Core/CommandBarStrings.swift \
        Sources/Vorssaint/Core/FeedbackStrings.swift \
        Sources/Vorssaint/Core/RadialMenuStrings.swift \
        Sources/Vorssaint/Core/MenuBarAppearanceStrings.swift \
        Sources/Vorssaint/Core/AppAppearance.swift \
        Sources/Vorssaint/Core/AppearanceStrings.swift \
        Sources/Vorssaint/Core/BatteryTimeStrings.swift \
        Sources/Vorssaint/Core/KeepAwakeStrings.swift \
        Sources/Vorssaint/Core/PermissionGuideStrings.swift \
        Sources/Vorssaint/Core/FanControlStrings.swift \
        Sources/Vorssaint/Services/FanControl/FanControlSupport.swift \
        Sources/Vorssaint/Services/Snippets/TextSnippetSupport.swift \
        Sources/Vorssaint/Services/RadialMenu/RadialMenuSupport.swift \
        Sources/Vorssaint/Services/QuickTools/ScratchpadSupport.swift \
        Sources/Vorssaint/Services/KillProcess/KillProcessSupport.swift \
        Sources/Vorssaint/Services/Recorder/RecorderSupport.swift \
        Sources/Vorssaint/Services/Recorder/RecordingSharingSupport.swift \
        Sources/Vorssaint/Services/PrivateFileStore.swift \
        Sources/Vorssaint/Services/Recorder/RecorderTakeStore.swift \
        Sources/Vorssaint/Services/Recorder/RecorderMotion.swift \
        Sources/Vorssaint/Services/Recorder/RecorderPointerTrack.swift \
        Sources/Vorssaint/Services/Recorder/RecorderTypingTrack.swift \
        Sources/Vorssaint/Services/Recorder/RecorderTimeline.swift \
        Sources/Vorssaint/Services/Recorder/RecorderTextOverlay.swift \
        Sources/Vorssaint/Services/Recorder/RecorderEditDocument.swift \
        Sources/Vorssaint/Core/AppInfo.swift \
        Sources/Vorssaint/Core/GlobalShortcut.swift \
        Sources/Vorssaint/Core/Localization.swift \
        Sources/Vorssaint/Core/Localizations/Strings+*.swift \
        Sources/Vorssaint/Core/FeatureStrings.swift \
        Sources/Vorssaint/Core/KillProcessStrings.swift \
        Sources/Vorssaint/Core/WhatsAppDownloadStrings.swift \
        Sources/Vorssaint/Core/WhatsAppOrganizerStrings.swift \
        Sources/Vorssaint/Core/ReleaseNotes.swift \
        Sources/Vorssaint/Core/URLCleaning.swift \
        Sources/Vorssaint/Services/GeneralPasteboardAccess.swift \
        Sources/Vorssaint/Services/Audio/MixerRoutingSupport.swift \
        Sources/Vorssaint/Services/Audio/MusicLaunchSupport.swift \
        Sources/Vorssaint/UI/MenuPanel/MixerPercentNativeTextField.swift \
        Sources/Vorssaint/Services/Audio/BoostLimiter.swift \
        Sources/Vorssaint/Services/Audio/MixerRender.swift \
        Sources/Vorssaint/Services/DockPreview/DockPreviewSupport.swift \
        Sources/Vorssaint/Services/Homebrew/HomebrewSupport.swift \
        Sources/Vorssaint/Services/AppUpdates/AppUpdatesSupport.swift \
        Sources/Vorssaint/Core/AppUpdateStrings.swift \
        Sources/Vorssaint/Core/DiskImageInstallerStrings.swift \
        Sources/Vorssaint/Services/DiskImageInstaller/DiskImageInstallerSupport.swift \
        Sources/Vorssaint/Services/Clipboard/ClipboardHistorySupport.swift \
        Sources/Vorssaint/Services/Clipboard/ClipboardAutoClearSupport.swift \
        Sources/Vorssaint/Services/AutoQuit/AutoQuitSupport.swift \
        Sources/Vorssaint/Services/Shelf/ShelfSupport.swift \
        Sources/Vorssaint/Services/Finder/FinderRenameSupport.swift \
        Sources/Vorssaint/Services/Update/UpdateInstallerSupport.swift \
        Sources/Vorssaint/Services/Update/UpdateServiceSupport.swift \
        Sources/Vorssaint/Services/InstalledApps.swift \
        Sources/Vorssaint/Services/LaunchAtLoginSupport.swift \
        Sources/Vorssaint/UI/Settings/SettingsSearchSupport.swift \
        Sources/Vorssaint/UI/Settings/FeatureVisibilitySupport.swift \
        Sources/Vorssaint/App/MenuBarSpacingSupport.swift \
        Sources/Vorssaint/App/StatusItemAnchorSupport.swift \
        Sources/Vorssaint/Services/DockClick/DockClickSupport.swift \
        Sources/Vorssaint/Services/Finder/CutPasteProgressSupport.swift \
        Sources/Vorssaint/Services/Finder/FinderPasteImageSupport.swift \
        Sources/Vorssaint/Services/MiddleClick/MiddleClickSupport.swift \
        Sources/Vorssaint/Services/MouseNavigation/MouseNavigationSupport.swift \
        Sources/Vorssaint/Services/MouseButtons/MouseButtonShortcutSupport.swift \
        Sources/Vorssaint/Services/MouseExceptions/MouseAppExceptionSupport.swift \
        Sources/Vorssaint/Core/MouseButtonStrings.swift \
        Sources/Vorssaint/Core/MouseExceptionStrings.swift \
        Sources/Vorssaint/Core/ClipboardIgnoredAppsStrings.swift \
        Sources/Vorssaint/Core/WindowPreviewExclusionStrings.swift \
        Sources/Vorssaint/Core/SwitcherAppRulesStrings.swift \
        Sources/Vorssaint/Services/QuickTools/QuickToolsSupport.swift \
        Sources/Vorssaint/Services/CommandBar/CommandBarSupport.swift \
        Sources/Vorssaint/Services/CommandBar/CommandBarPreferences.swift \
        Sources/Vorssaint/Services/CommandBar/CommandBarMath.swift \
        Sources/Vorssaint/Services/CommandBar/CommandBarUnits.swift \
        Sources/Vorssaint/Services/CommandBar/CommandBarEmoji.swift \
        Sources/Vorssaint/Services/CommandBar/CommandBarLinks.swift \
        Sources/Vorssaint/Services/CommandBar/CommandBarDates.swift \
        Sources/Vorssaint/Services/CommandBar/CommandBarRowShortcuts.swift \
        Sources/Vorssaint/Services/CommandBar/CommandBarSystemSettingsSupport.swift \
        Sources/Vorssaint/Services/CommandBar/CommandBarFileSearchSupport.swift \
        Sources/Vorssaint/Services/CommandBar/CommandBarQueryMemory.swift \
        Sources/Vorssaint/Services/SpotlightNamesSupport.swift \
        Sources/Vorssaint/Services/QuickTools/MicMuteSupport.swift \
        Sources/Vorssaint/Services/QuickTools/QuickTogglesSupport.swift \
        Sources/Vorssaint/Services/QuickTools/ScreenshotCapturePolicy.swift \
        Sources/Vorssaint/Services/QuickTools/ScreenshotSupport.swift \
        Sources/Vorssaint/Services/QuickTools/ScreenshotSharingSupport.swift \
        Sources/Vorssaint/Services/QuickTools/WindowActivationPolicy.swift \
        Sources/Vorssaint/Services/KeyboardDebounce/KeyboardDebounceSupport.swift \
        Sources/Vorssaint/Services/SuperKey/SuperKeySupport.swift \
        Sources/Vorssaint/Core/SuperKeyStrings.swift \
        Sources/Vorssaint/Services/ScrollWheelSupport.swift \
        Sources/Vorssaint/Services/SmoothScrollSupport.swift \
        Sources/Vorssaint/Services/FocusFollowsMouse/FocusFollowsMouseSupport.swift \
        Sources/Vorssaint/Services/Switcher/SwitcherModels.swift \
        Sources/Vorssaint/Services/Switcher/SwitcherSupport.swift \
        Sources/Vorssaint/Services/Switcher/SpaceHopSupport.swift \
        Sources/Vorssaint/Services/Switcher/WindowUseOrder.swift \
        Sources/Vorssaint/Services/Metrics/MetricFormat.swift \
        Sources/Vorssaint/Services/KeepAwakeAutomationSupport.swift \
        Sources/Vorssaint/Services/SudoersSupport.swift \
        Sources/Vorssaint/Services/Metrics/BatteryTimeSupport.swift \
        Sources/Vorssaint/Services/BoundedProcessRunner.swift \
        Sources/Vorssaint/Services/ShellSupport.swift \
        Sources/Vorssaint/Services/Metrics/NetworkProcessSupport.swift \
        Sources/Vorssaint/Services/Metrics/NetworkSampler.swift \
        Sources/Vorssaint/Services/Metrics/PeripheralBatterySupport.swift \
        Sources/Vorssaint/Services/Metrics/DiskSupport.swift \
        Sources/Vorssaint/Services/Metrics/MonitorSamplingPolicy.swift \
        Sources/Vorssaint/Services/Metrics/MaxCapacityProbe.swift \
        Sources/Vorssaint/Services/Metrics/TemperatureSensorSelector.swift \
        Sources/Vorssaint/Services/Metrics/SustainedAlertGate.swift \
        Sources/Vorssaint/Services/WindowLayout/WindowLayoutSupport.swift \
        Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift \
        Sources/Vorssaint/Core/WindowDirectionalStrings.swift \
        Sources/Vorssaint/Services/CleaningMode/CleaningUnlockCounter.swift \
        Sources/Vorssaint/Services/Display/ExtraBrightnessSupport.swift \
        Sources/Vorssaint/Services/Display/BrightnessSupport.swift \
        Sources/Vorssaint/Services/Cleaner/CleanerSupport.swift \
        Sources/Vorssaint/Services/Cleaner/CleanerPolicy.swift \
        Sources/Vorssaint/Services/Cleaner/CleanerSchedule.swift \
        Sources/Vorssaint/Services/Uninstall/UninstallerSupport.swift \
        Sources/Vorssaint/Services/ManagedDownloads/WhatsAppDownloadSupport.swift \
        Tests/MetricsTests.swift \
        -o build/metrics-tests
    ./build/metrics-tests
    exit $?
fi

echo "▸ Compiling ($BUILD_CONFIGURATION) against $(basename "$SDK")…"
APP_SOURCES=(Sources/Vorssaint/**/*.swift)
if (( DEV )); then
    APP_OBJECT_DIR="build/objects/$EXECUTABLE"
    mkdir -p build "$APP_OBJECT_DIR"
    APP_OUTPUT_FILE_MAP="$APP_OBJECT_DIR/output-file-map.json"
    write_swift_output_file_map "$APP_OUTPUT_FILE_MAP" "$APP_OBJECT_DIR" "${APP_SOURCES[@]}"
    swiftc "${APP_OPTIMIZATION_FLAGS[@]}" -incremental -j "$(sysctl -n hw.logicalcpu)" \
        -output-file-map "$APP_OUTPUT_FILE_MAP" \
        -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" "${BUILD_VARIANT_FLAGS[@]}" \
        "${APP_SOURCES[@]}" -o "build/$EXECUTABLE"
else
    rm -rf build
    mkdir -p build
    swiftc "${APP_OPTIMIZATION_FLAGS[@]}" -target "$TARGET" -sdk "$SDK" \
        "${SDK_COMPAT_FLAGS[@]}" "${BUILD_VARIANT_FLAGS[@]}" \
        "${APP_SOURCES[@]}" -o "build/$EXECUTABLE"
fi

echo "▸ Compiling protected fan helper…"
swiftc -O -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" "${BUILD_VARIANT_FLAGS[@]}" \
    Sources/Vorssaint/Services/FanControl/FanControlSupport.swift \
    Sources/Vorssaint/Services/FanControl/FanControlXPC.swift \
    Sources/Vorssaint/Services/SystemMonitor/SMCClient.swift \
    Sources/Vorssaint/Services/Metrics/TemperatureSensorSelector.swift \
    Sources/Vorssaint/Services/FanControl/FanControlHardware.swift \
    Sources/FanControlHelper/main.swift \
    -o "build/$FAN_HELPER_ID"
"build/$FAN_HELPER_ID" --selftest

echo "▸ Generating app icon…"
swift Tools/MakeIcon.swift build/AppIcon.iconset
xattr -c -r build/AppIcon.iconset build/AppIcon.icns build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png 2>/dev/null || true

echo "▸ Assembling and signing bundle…"
STAGE="$(mktemp -d)/$APP_NAME.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources" \
    "$STAGE/Contents/Library/LaunchDaemons" "$STAGE/Contents/Library/LaunchServices"
cp "build/$EXECUTABLE" "$STAGE/Contents/MacOS/$EXECUTABLE"
cp "build/$FAN_HELPER_ID" "$STAGE/Contents/Library/LaunchServices/$FAN_HELPER_ID"
cp Resources/com.vorssaint.utils.fan-control.plist \
    "$STAGE/Contents/Library/LaunchDaemons/$FAN_HELPER_ID.plist"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
cp CHANGELOG.md "$STAGE/Contents/Resources/CHANGELOG.md"
for lproj in Resources/*.lproj(N); do
    cp -R "$lproj" "$STAGE/Contents/Resources/"
done
if (( DEV )); then
    # A distinct identity so the Developer build installs and runs next to the
    # official app, with its own permissions, preferences and login item.
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.vorssaint.utils.dev" "$STAGE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName Vorssaint (Developer)" "$STAGE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Vorssaint (Developer)" "$STAGE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXECUTABLE" "$STAGE/Contents/Info.plist"
    FAN_PLIST="$STAGE/Contents/Library/LaunchDaemons/$FAN_HELPER_ID.plist"
    /usr/libexec/PlistBuddy -c "Set :Label $FAN_HELPER_ID" "$FAN_PLIST"
    /usr/libexec/PlistBuddy -c "Set :BundleProgram Contents/Library/LaunchServices/$FAN_HELPER_ID" "$FAN_PLIST"
    /usr/libexec/PlistBuddy -c "Delete :MachServices:com.vorssaint.utils.fan-control" "$FAN_PLIST"
    /usr/libexec/PlistBuddy -c "Add :MachServices:$FAN_HELPER_ID bool true" "$FAN_PLIST"
    # Stamp the source commit + build time so the running dev app shows (in About)
    # exactly which code it was compiled from. Lets you verify it matches HEAD before
    # testing, instead of unknowingly running a stale build. Dev-only; never shipped.
    SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    [[ -n "$(git status --porcelain 2>/dev/null)" ]] && SHA="$SHA-dirty"
    /usr/libexec/PlistBuddy -c "Add :VorssaintBuildCommit string '$SHA · $(date '+%Y-%m-%d %H:%M')'" "$STAGE/Contents/Info.plist"
    echo "  stamped dev build: $SHA"
fi
FAN_HELPER_VERSION="$(
    export LC_ALL=C
    /usr/bin/shasum -a 256 \
        "$STAGE/Contents/Library/LaunchServices/$FAN_HELPER_ID" \
        "$STAGE/Contents/Library/LaunchDaemons/$FAN_HELPER_ID.plist" \
        | /usr/bin/awk '{print $1}' | /usr/bin/shasum -a 256 \
        | /usr/bin/awk '{print $1}'
)"
/usr/libexec/PlistBuddy -c "Add :VorssaintFanControlHelperVersion string '$FAN_HELPER_VERSION'" \
    "$STAGE/Contents/Info.plist"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"
cp build/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
cp build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png "$STAGE/Contents/Resources/"
if [[ -d Resources/Gifs ]]; then
    mkdir -p "$STAGE/Contents/Resources/Gifs"
    cp Resources/Gifs/*.gif "$STAGE/Contents/Resources/Gifs/"
fi
if [[ -d Resources/Images ]]; then
    mkdir -p "$STAGE/Contents/Resources/Images"
    cp Resources/Images/* "$STAGE/Contents/Resources/Images/"
fi
xattr -c -r "$STAGE" 2>/dev/null || true

# Signing, in order of preference:
#   1. Developer ID Application — the real, Apple-issued identity used for
#      notarized releases. Signed with the hardened runtime (required for
#      notarization), the app's entitlements and a secure timestamp. Gives a
#      stable, team-based designated requirement, so permissions persist across
#      updates AND Gatekeeper shows no "unverified developer" warning.
#   2. "Vorssaint Utils Signing" — the legacy stable self-signed identity, kept
#      as a fallback so contributors without a Developer ID still get a constant
#      designated requirement across their local builds.
#   3. Ad-hoc — fresh clone with no identity at all.
DEVID="$(developer_id_identity)"
codesign_app() {
    local target="$1"
    if [[ -n "$DEVID" ]]; then
        codesign_with_timestamp_retry --force --strip-disallowed-xattrs --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS" --sign "$DEVID" "$target"
    elif security find-identity -p codesigning 2>/dev/null | grep -q "$LEGACY_IDENTITY"; then
        codesign --force --strip-disallowed-xattrs --sign "$LEGACY_IDENTITY" "$target"
    else
        codesign --force --strip-disallowed-xattrs --sign - "$target"
    fi
}

codesign_fan_helper() {
    local target="$1"
    if [[ -n "$DEVID" ]]; then
        codesign_with_timestamp_retry --force --strip-disallowed-xattrs --options runtime --timestamp \
            --identifier "$FAN_HELPER_ID" --sign "$DEVID" "$target"
    elif security find-identity -p codesigning 2>/dev/null | grep -q "$LEGACY_IDENTITY"; then
        codesign --force --strip-disallowed-xattrs --identifier "$FAN_HELPER_ID" \
            --sign "$LEGACY_IDENTITY" "$target"
    else
        codesign --force --strip-disallowed-xattrs --identifier "$FAN_HELPER_ID" --sign - "$target"
    fi
}

sign_bundle() {
    local bundle="$1"
    local executable="$bundle/Contents/MacOS/$EXECUTABLE"
    local helper="$bundle/Contents/Library/LaunchServices/$FAN_HELPER_ID"

    if [[ -n "$DEVID" ]]; then
        echo "  signing with Developer ID (hardened runtime): $DEVID"
    elif security find-identity -p codesigning 2>/dev/null | grep -q "$LEGACY_IDENTITY"; then
        echo "  signing with legacy self-signed identity: $LEGACY_IDENTITY"
    else
        echo "  signing ad-hoc (no identity installed — run Tools/setup-signing.sh)"
    fi
    [[ -f "$helper" ]] && codesign_fan_helper "$helper"
    codesign_app "$bundle"

    # If local filesystem metadata invalidates the first signature, sign once
    # more. The installed Developer bundle is signed again after the final copy.
    if ! codesign --verify --deep --strict "$bundle" >/dev/null 2>&1; then
        echo "  re-signing after filesystem metadata settled"
        xattr -c -r "$bundle" 2>/dev/null || true
        [[ -f "$helper" ]] && codesign_fan_helper "$helper"
        codesign_app "$bundle"
    fi
    [[ -f "$executable" ]] && codesign --verify --strict "$executable"
    [[ -f "$helper" ]] && codesign --verify --strict "$helper"
    codesign --verify --deep --strict "$bundle"
}

sign_installed_bundle() {
    local bundle="$1"
    wait_for_install_metadata "$bundle"
    sign_bundle "$bundle"
}

sign_bundle "$STAGE"

process_is_running() {
    local proc="$1"
    if (( ${#proc} > 15 )); then
        pgrep -f "/Contents/MacOS/$proc" >/dev/null 2>&1
    else
        pgrep -x "$proc" >/dev/null 2>&1
    fi
}

stop_process() {
    local proc="$1"
    if (( ${#proc} > 15 )); then
        pkill -f "/Contents/MacOS/$proc" 2>/dev/null || true
    else
        pkill -x "$proc" 2>/dev/null || true
    fi
    for _ in {1..50}; do
        if ! process_is_running "$proc"; then
            return 0
        fi
        sleep 0.1
    done
    echo "✗ $proc is still running — quit it and retry" >&2
    return 1
}

wait_for_install_metadata() {
    local bundle="$1"
    local missing
    for _ in {1..50}; do
        missing=0
        while IFS= read -r file; do
            if ! xattr -p com.apple.provenance "$file" >/dev/null 2>&1; then
                missing=1
                break
            fi
        done < <(find "$bundle/Contents" -type f ! -path "*/_CodeSignature/*")
        if (( missing == 0 )); then
            return 0
        fi
        sleep 0.1
    done
}

mkdir -p "build/stage"
BUILD_STAGE="build/stage/$APP_NAME.app"
rm -rf "$BUILD_STAGE"
ditto --noextattr --noqtn "$STAGE" "$BUILD_STAGE"
xattr -c -r "$BUILD_STAGE" 2>/dev/null || true
if ! codesign --verify --deep --strict "$BUILD_STAGE" >/dev/null 2>&1; then
    if xattr -lr "$BUILD_STAGE" 2>/dev/null | grep -Eq 'com\.apple\.(FinderInfo|ResourceFork|provenance|fileprovider)'; then
        echo "  build/stage copy has local filesystem metadata; temp bundle was verified"
    else
        codesign --verify --deep --strict "$BUILD_STAGE"
    fi
fi
echo "✓ Bundle ready: $BUILD_STAGE"

if (( INSTALL )); then
    echo "▸ Installing into /Applications…"
    stop_process "$EXECUTABLE"
    # Remove the pre-rename apps so two menu bar items never coexist. Same bundle
    # id, so macOS keeps the granted permissions for the new bundle.
    for legacy in "Vorss:Vorss" "Vorssaint Utils:VorssaintUtils"; do
        name="${legacy%%:*}"; proc="${legacy##*:}"
        if [[ -d "/Applications/$name.app" ]]; then
            stop_process "$proc"
            rm -rf "/Applications/$name.app"
            echo "  (legacy $name.app removed)"
        fi
    done
    INSTALL_DEST="/Applications/$APP_NAME.app"
    rm -rf "$INSTALL_DEST"
    ditto --noextattr --noqtn "$STAGE" "$INSTALL_DEST"
    sign_installed_bundle "$INSTALL_DEST"
    echo "✓ Installed: $INSTALL_DEST"
fi
