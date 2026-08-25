#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Cleanly removes Vorssaint and every piece of system state it created:
# the fan helper daemon, the login item, TCC permissions, preferences, saved
# state, the app's own data folder and (if present) the password-free
# closed-lid sudoers rule. Leaves no dead entries behind.
# Also clears the pre-rename "Vorssaint Utils.app" if it is still around.
set -uo pipefail

BUNDLE="com.vorssaint.utils"
APP="/Applications/Vorssaint.app"
LEGACY_APP="/Applications/Vorssaint Utils.app"

echo "▸ Quitting…"
pkill -x Vorssaint 2>/dev/null || true
pkill -x VorssaintUtils 2>/dev/null || true
sleep 0.5

# Detach from the system from inside whichever bundle still exists: unregisters
# the login item (no BTM tombstone) and restores normal sleep.
# The fan helper's registration lives in the system, not in the bundle, so
# deleting the app below cannot reach it. Only the binary can drop it, and the
# check after the loop settles what its absence or failure left behind.
detached=1
for candidate in "$APP/Contents/MacOS/Vorssaint" "$LEGACY_APP/Contents/MacOS/VorssaintUtils"; do
    if [[ -x "$candidate" ]]; then
        echo "▸ Detaching the fan helper and login item, restoring sleep…"
        if "$candidate" --uninstall; then detached=0; fi
        break
    fi
done
# `detached` cannot tell a failed unregister from no binary having run, and the
# second is ordinary: an app trashed by hand, then this script for the rest. It
# also cannot see a daemon that went despite a reported failure. launchctl
# settles both without sudo, and still finds a registration held back for a
# pending fan recovery, which is the one case that must keep warning.
if (( detached )); then
    launchctl print "system/$BUNDLE.fan-control" >/dev/null 2>&1
    # 113 is "no such service", the only answer that proves absence. Any other
    # failure means launchctl could not tell us, and warning then is the honest
    # side of a check that exists to stop this script claiming what it cannot see.
    (( $? == 113 )) && detached=0
fi

echo "▸ Resetting permissions (Accessibility, Screen Recording)…"
tccutil reset All "$BUNDLE" >/dev/null 2>&1 || true

echo "▸ Removing app, preferences, saved state and stored data (clipboard history, shelf files, share links)…"
rm -rf "$APP" "$LEGACY_APP"
defaults delete "$BUNDLE" >/dev/null 2>&1 || true
rm -f "$HOME/Library/Preferences/$BUNDLE.plist"
rm -rf "$HOME/Library/Saved Application State/$BUNDLE.savedState"
# Clipboard history, shelf files, captures and the share delete tokens live
# here; the in-app uninstall takes them, so this path must not keep them.
rm -rf "$HOME/Library/Application Support/$BUNDLE"
rm -rf "$HOME/Library/Caches/$BUNDLE"
# Written by URLSession on the app's behalf, so they exist without the app ever
# naming the path; `defaults delete` does not reach them either.
rm -rf "$HOME/Library/HTTPStorages/$BUNDLE" "$HOME/Library/HTTPStorages/$BUNDLE.binarycookies"
# `defaults delete` does not reach ByHost. The (N) qualifier is load-bearing:
# without it zsh aborts the command on an unmatched pattern, which is the
# ordinary case, and prints an error over a successful uninstall.
rm -f "$HOME/Library/Preferences/ByHost/$BUNDLE".*.plist(N)

RULES="/etc/sudoers.d/vorssaint-clamshell /etc/sudoers.d/vorssaint-utils-clamshell /etc/sudoers.d/vorss-clamshell"
if ls $RULES >/dev/null 2>&1; then
    echo "▸ Removing closed-lid sudoers rule (asks for your admin password)…"
    osascript -e "do shell script \"rm -f $RULES\" with administrator privileges with prompt \"Vorssaint uninstaller\"" || true
fi

if (( detached == 0 )); then
    echo "✓ Vorssaint fully removed."
else
    echo "⚠ Vorssaint removed, but its fan helper is still registered with the system." >&2
    echo "  Reinstall Vorssaint, then use Settings › Advanced to uninstall from inside the app." >&2
    exit 1
fi
