#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

set -euo pipefail
cd "$(dirname "$0")/.."
source <(sed -n '/^discard_test_preferences() {$/,/^}$/p' build.sh)
cleanup_test_dir=$(mktemp -d)
trap 'command rm -rf "$cleanup_test_dir"' EXIT

# Emulate the preferences daemon completing a write after each cleanup pass.
# This exercises the real cleanup without touching the user's preferences.
remaining_writes=2
sleep() {
    if (( remaining_writes > 0 )); then
        print '{}' > "$cleanup_test_dir/com.vorssaint.tests.delayed.plist"
        remaining_writes=$((remaining_writes - 1))
    fi
}
print '{}' > "$cleanup_test_dir/vorss.tests.first.plist"
print '{}' > "$cleanup_test_dir/metrics-tests.plist"
print 'preserve' > "$cleanup_test_dir/unrelated.plist"
discard_test_preferences "$cleanup_test_dir"
[[ ! -e "$cleanup_test_dir/com.vorssaint.tests.delayed.plist" ]]
[[ ! -e "$cleanup_test_dir/vorss.tests.first.plist" ]]
[[ ! -e "$cleanup_test_dir/metrics-tests.plist" ]]
[[ "$(cat "$cleanup_test_dir/unrelated.plist")" == preserve ]]

# A writer that never settles must still fail rather than hiding the problem.
remaining_writes=100
if discard_test_preferences "$cleanup_test_dir" 2>/dev/null; then
    print -u2 'preference cleanup accepted a persistent writer'
    exit 1
fi
[[ $remaining_writes == 90 ]]
remaining_writes=0
discard_test_preferences "$cleanup_test_dir"
print 'PREFERENCE CLEANUP TESTS OK'
