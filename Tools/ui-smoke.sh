#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Read-only UI smoke test for the installed Developer build. Drives the real
# app through Accessibility (menu panel, quick panel, Settings), captures
# screenshots and fails loudly when a surface does not appear. It never
# changes preferences: everything it opens is closed again, and no toggle is
# flipped. Requires Accessibility + Screen Recording permission for the
# terminal running it.
#
# Usage: ./Tools/ui-smoke.sh [output-dir]
set -uo pipefail

APP="/Applications/Vorssaint (Developer).app"
PROCESS="VorssaintDeveloper"
OUT="${1:-$(mktemp -d /tmp/vorss-ui-smoke.XXXXXX)}"
mkdir -p "$OUT"
FAILURES=0

step() { echo "▸ $1"; }
fail() { echo "✗ $1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "  ✓ $1"; }

ax() { osascript -e "tell application \"System Events\" to tell process \"$PROCESS\" to $1" 2>/dev/null; }

if [[ ! -d "$APP" ]]; then
    echo "✗ $APP not installed — run ./build.sh --dev --install first" >&2
    exit 1
fi

step "Launching the app"
open "$APP"
sleep 3
if ! pgrep -xq "$PROCESS"; then
    fail "app process did not start"
    exit 1
fi
pass "process running"

step "Status item"
ITEMS=$(ax 'count menu bar items of menu bar 2')
if [[ "${ITEMS:-0}" -ge 1 ]]; then
    pass "menu bar has $ITEMS status item(s)"
else
    fail "no status item in the menu bar"
fi

step "Menu panel"
ax 'click menu bar item 1 of menu bar 2' >/dev/null
sleep 1.5
if [[ "$(ax 'exists pop over 1 of menu bar item 1 of menu bar 2')" == "true" ]]; then
    pass "panel popover opened"
    screencapture -x "$OUT/panel.png"
else
    fail "panel popover did not open"
fi
osascript -e 'tell application "System Events" to key code 53' >/dev/null
sleep 0.8

step "Quick panel"
osascript -e 'tell application "System Events" to keystroke "v" using {control down, command down}' >/dev/null
sleep 1.5
QP=$(ax 'get position of window "Vorssaint"')
if [[ -n "${QP:-}" ]]; then
    pass "quick panel window at $QP"
    screencapture -x "$OUT/quick-panel.png"
else
    fail "quick panel window did not appear"
fi
osascript -e 'tell application "System Events" to key code 53' >/dev/null
sleep 0.8

step "Settings window"
ax 'click menu bar item 1 of menu bar 2' >/dev/null
sleep 1.2
ax 'click button 9 of group 1 of pop over 1 of menu bar item 1 of menu bar 2' >/dev/null
sleep 1.5
SW=$(ax 'get position of window "Vorssaint Settings"')
if [[ -n "${SW:-}" ]]; then
    pass "settings window at $SW"
    screencapture -x "$OUT/settings.png"
    ax 'click button 1 of window "Vorssaint Settings"' >/dev/null
else
    fail "settings window did not open"
fi

echo ""
if [[ $FAILURES -eq 0 ]]; then
    echo "UI SMOKE OK — screenshots in $OUT"
else
    echo "UI SMOKE FAILED ($FAILURES failure(s)) — screenshots in $OUT" >&2
    exit 1
fi
