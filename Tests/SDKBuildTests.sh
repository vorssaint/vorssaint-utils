#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

set -euo pipefail
cd "$(dirname "$0")/.."
sdk_test_dir=$(mktemp -d)
trap 'command rm -rf "$sdk_test_dir"' EXIT

# Exercise the actual build configuration and compiler, without launching UI.
# With SDK 27+, this fails if SwiftUI's State macro plugin cannot be loaded.
sed -n '/^# Prefer the macOS 26 SDK/,/^# The defaults migrations/{ /^# The defaults migrations/!p; }' build.sh > "$sdk_test_dir/config.zsh"
[[ -s "$sdk_test_dir/config.zsh" ]]
source "$sdk_test_dir/config.zsh"
if [[ -n "${SDKROOT:-}" && -d "$SDKROOT" ]]; then
    [[ "$SDK" -ef "$SDKROOT" ]] || {
        print -u2 "SDKROOT was ignored: requested $SDKROOT, selected $SDK"
        exit 1
    }
fi
cat > "$sdk_test_dir/MacroCheck.swift" <<'SWIFT'
import SwiftUI
struct MacroCheck: View {
    @State private var enabled = false
    var body: some View { Text(enabled ? "on" : "off") }
}
SWIFT
swiftc -typecheck -target arm64-apple-macosx14.0 -sdk "$SDK" \
    "${SDK_COMPAT_FLAGS[@]}" "$sdk_test_dir/MacroCheck.swift"
print "SDK BUILD TESTS OK ($SDK)"
