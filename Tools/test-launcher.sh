#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Emre Aribulan
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/vorssaint-shortcuts.XXXXXX")"
trap 'rm -rf "$TEST_DIRECTORY"' EXIT
trap 'exit 1' INT TERM HUP
mkdir -p "$TEST_DIRECTORY/module-cache"
TASK_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
TASK_FLAGS=(-Xfrontend -interface-compiler-version -Xfrontend 6.3.2)
if [[ -n "${DEVELOPER_DIR:-}" || ! -d "$TASK_SDK" ]]; then
    TASK_SDK="$(xcrun --show-sdk-path)"
    TASK_FLAGS=()
fi
swiftc -sdk "$TASK_SDK" "${TASK_FLAGS[@]}" -module-cache-path "$TEST_DIRECTORY/module-cache" \
    Sources/Vorssaint/Services/Notch/Shortcuts/IslandLauncherSupport.swift \
    Sources/Vorssaint/Services/Notch/Shortcuts/WebsiteShortcutSupport.swift \
    Tools/LauncherTests/LauncherTests.swift -o "$TEST_DIRECTORY/launcher-tests"
"$TEST_DIRECTORY/launcher-tests"
swiftc -sdk "$TASK_SDK" "${TASK_FLAGS[@]}" -module-cache-path "$TEST_DIRECTORY/module-cache" \
    Sources/Vorssaint/Services/Notch/Shortcuts/IslandLauncherSupport.swift \
    Sources/Vorssaint/Services/Notch/Shortcuts/WebsiteShortcutSupport.swift \
    Sources/Vorssaint/Services/Notch/Shortcuts/WebsiteShortcutIconService.swift \
    Tools/LauncherTests/WebsiteIconTests.swift -o "$TEST_DIRECTORY/website-icon-tests"
python3 Tools/LauncherTests/network-fixture.py "$TEST_DIRECTORY/website-icon-tests"
