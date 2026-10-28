#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Runs the App Shortcuts window lifecycle probe against the production
# controller. Its own HOME keeps the probe out of the user's preferences.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$PWD"
OUT="$ROOT/build/command-bar-app-shortcuts-probe"
rm -rf "$OUT"
mkdir -p "$OUT/home"

xcrun swiftc -Onone -o "$OUT/probe" \
    "$ROOT/Sources/Vorssaint/UI/Settings/CommandBarAppShortcutsWindow.swift" \
    "$ROOT/Tests/Probes/CommandBarAppShortcutsWindowProbe.swift"

HOME="$OUT/home" "$OUT/probe"
