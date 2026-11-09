#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
set -euo pipefail
cd "$(dirname "$0")/../.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
# Compile the actual AppLanguage and CountAgreement declarations, including all
# their members. Stop before L10n, whose app-wide dependencies are unnecessary.
awk '/^final class L10n:/ { exit } { print }' Sources/Vorssaint/Core/Localization.swift > "$TEST_DIR/Language.swift"
printf '\nenum FeatureStrings {}\n' >> "$TEST_DIR/Language.swift"
swiftc "$TEST_DIR/Language.swift" \
    Sources/Vorssaint/Core/ContinuityStrings.swift \
    Tests/Continuity/strings.swift -o "$TEST_DIR/strings-tests"
"$TEST_DIR/strings-tests"
