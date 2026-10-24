#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
set -euo pipefail
cd "$(dirname "$0")/../.."
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
swiftc -parse-as-library Sources/Vorssaint/Services/Continuity/ContinuityWorkflow.swift Tests/Continuity/main.swift -o "$TEMP_DIR/continuity-tests"
"$TEMP_DIR/continuity-tests"
