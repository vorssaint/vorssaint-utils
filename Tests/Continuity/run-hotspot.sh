#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
set -euo pipefail
cd "$(dirname "$0")/../.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
cat Sources/Vorssaint/Services/Continuity/ContinuityHotspotConnector.swift Tests/Continuity/hotspot-snapshot.swift > "$TEST_DIR/main.swift"
swiftc "$TEST_DIR/main.swift" -o "$TEST_DIR/hotspot-tests"
"$TEST_DIR/hotspot-tests"
