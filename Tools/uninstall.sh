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

# A readable domain with a missing key is different from a failed read. Export
# the whole domain first, including an empty dictionary when it does not exist.
spaces_read_domain() {
    local snapshot
    snapshot="$(defaults export "$1" - 2>/dev/null)" || return 1
    /usr/bin/plutil -lint -s - <<< "$snapshot" >/dev/null 2>&1 || return 1
    print -r -- "$snapshot"
}

spaces_recovery_value() {
    local snapshot=$1 key=$2 kind value
    kind="$(/usr/bin/plutil -type "$key" - <<< "$snapshot" 2>/dev/null)" || return 0
    [[ "$kind" == string ]] || return 1
    value="$(/usr/bin/plutil -extract "$key" raw -o - - <<< "$snapshot" 2>/dev/null)" || return 1
    [[ -n "$value" ]] || return 1
    print -r -- "$value"
}

spaces_dock_preference() {
    local snapshot kind value
    snapshot="$(spaces_read_domain com.apple.dock)" || { print unknown; return; }
    kind="$(/usr/bin/plutil -type mru-spaces - <<< "$snapshot" 2>/dev/null)" || return 0
    value="$(/usr/bin/plutil -extract mru-spaces raw -o - - <<< "$snapshot" 2>/dev/null)" \
        || { print unknown; return; }
    case "$kind:$value" in
        bool:false|integer:0) print 0 ;;
        bool:true|integer:1) print 1 ;;
        *) print unknown ;;
    esac
}

spaces_dock_pid() {
    local pids result
    if pids="$(pgrep -x -U "$UID" Dock 2>/dev/null)"; then
        [[ -n "$pids" ]] && print -r -- "${pids%%$'\n'*}" || print unknown
    else
        result=$?
        [[ "$result" == 1 ]] || print unknown
    fi
    return 0
}

# What fixed Space order still owes, from the restore
# marker, the journal of a restart the Dock still owes, the Dock's mru-spaces
# value and the running Dock's process: "stuck" while rearranging is still off,
# "unloaded" while it is back on but the Dock keeps a fixed order until it
# restarts, and nothing when settled. The owed restart counts on its own,
# because the marker is gone once the setting is back. The journal counts only
# while the same Dock process runs and the preference still reads as written:
# a Dock that restarted since has read it, and any other value is a later
# change the Dock applied itself. An "off" marker owes nothing: rearranging was
# already off when the feature turned on, so it is the user's own. An
# inconclusive read is unknown while recovery is recorded, never absent.
spaces_leftover() {
    local owed=$1 journal=$2 preference=$3 dock_pid=$4
    local journal_pid journal_runs journal_wrote reads=""
    [[ ( -z "$owed" || "$owed" == off ) && -z "$journal" ]] && return 0
    case "$owed" in
        ""|absent|on|off) ;;
        *) print unknown; return ;;
    esac
    if [[ "$preference" == unknown || ( -n "$journal" && "$dock_pid" == unknown ) ]]; then
        print unknown
        return
    fi
    read -r journal_pid journal_runs journal_wrote <<< "$journal"
    if [[ -n "$journal" ]]; then
        if [[ "$journal_pid" != <-> || "$journal_runs" != (fixed|rearranging) || -z "$journal_wrote" ]]; then
            print unknown
            return
        fi
        local written
        for written in ${=journal_wrote}; do
            case "$written" in
                absent|on|off) ;;
                *) print unknown; return ;;
            esac
        done
    fi
    case "$preference" in
        0) reads=off ;;
        1) reads=on ;;
        "") reads=absent ;;
        *) print unknown; return ;;
    esac
    if [[ -n "$owed" && "$owed" != off && "$preference" == "0" ]]; then
        print stuck
    elif [[ "$journal_runs" == fixed && "$preference" != "0" && -n "$dock_pid" && "$journal_pid" == "$dock_pid"
            && " $journal_wrote " == *" $reads "* ]]; then
        print unloaded
    fi
}

spaces_removal_state() {
    local owed=$1 journal=$2
    [[ ( -z "$owed" || "$owed" == off ) && -z "$journal" ]] && return 0
    spaces_leftover "$owed" "$journal" "$(spaces_dock_preference)" "$(spaces_dock_pid)"
}

echo "▸ Quitting…"
pkill -x Vorssaint 2>/dev/null || true
pkill -x VorssaintUtils 2>/dev/null || true
sleep 0.5

# Detach from the system from inside whichever bundle still exists: unregisters
# the login item (no BTM tombstone), restores normal sleep and puts back Space
# rearranging.
# The fan helper's registration lives in the system, not in the bundle, so
# deleting the app below cannot reach it. Only the binary can drop it, and the
# check after the loop settles what its absence or failure left behind.
detached=1
for candidate in "$APP/Contents/MacOS/Vorssaint" "$LEGACY_APP/Contents/MacOS/VorssaintUtils"; do
    if [[ -x "$candidate" ]]; then
        echo "▸ Detaching the fan helper and login item, restoring sleep and Space rearranging…"
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

# Whether the closed-lid feature is the reason sleep is off. Read here because
# the preferences that hold it are deleted a few lines below, and without it a
# check on the setting alone would blame Vorssaint for a `pmset disablesleep 1`
# that somebody else, or the user, had set.
sleep_was_ours=0
[[ "$(defaults read "$BUNDLE" vorssDisabledSleep 2>/dev/null)" == "1" ]] && sleep_was_ours=1

# Whether Space rearranging is still owed back. `--uninstall` clears this
# marker once the setting is back, so one still here means that restore failed
# or never ran (an app trashed by hand). It is read here for the same reason
# as the sleep flag above.
if ! spaces_snapshot="$(spaces_read_domain "$BUNDLE")" \
    || ! spaces_owed="$(spaces_recovery_value "$spaces_snapshot" spacesOrderRestore)" \
    || ! spaces_journal="$(spaces_recovery_value "$spaces_snapshot" spacesOrderRestartPending)"; then
    print -u2 "Could not read Space arrangement recovery. The app and its preferences were kept."
    print -u2 "Try uninstalling again when the preferences can be read."
    exit 1
fi
spaces_before_removal="$(spaces_removal_state "$spaces_owed" "$spaces_journal")"
if [[ -n "$spaces_before_removal" ]]; then
    case "$spaces_before_removal" in
        stuck) print -u2 "Space rearranging has not been restored." ;;
        unloaded) print -u2 "The Dock has not loaded the restored Space arrangement yet." ;;
        *) print -u2 "Could not confirm that Space rearranging was restored." ;;
    esac
    print -u2 "The app and its recovery preferences were kept. Try uninstalling again."
    exit 1
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

# The closed-lid rule under its current name and the two earlier ones, the
# same files the app looks for. Each path is checked on its own. zsh passes an
# unquoted string to a command as a single word, and one `ls` over all three
# fails as soon as any of them is missing.
RULES=(/etc/sudoers.d/vorssaint-clamshell /etc/sudoers.d/vorssaint-utils-clamshell /etc/sudoers.d/vorss-clamshell)
found_rules=()
for rule in "${RULES[@]}"; do
    [[ -e "$rule" ]] && found_rules+=("$rule")
done
if (( ${#found_rules} )); then
    echo "▸ Removing closed-lid sudoers rule (asks for your admin password)…"
    osascript -e "do shell script \"rm -f $found_rules\" with administrator privileges with prompt \"Vorssaint uninstaller\"" || true
fi

# `--uninstall` restores sleep, but it runs before the app has an
# NSApplication and so cannot raise the password dialog the in-app uninstall
# falls back to. A restore that needed one therefore reaches here as a setting
# still switched on. `pmset -g` reads it without sudo, and this is the only
# warning anyone will get: the app that knew the setting was its doing has
# just been removed.
sleep_stuck=0
sleep_unknown=0
if (( sleep_was_ours )); then
    sleep_state="$(pmset -g 2>/dev/null | awk '/SleepDisabled/ { print $2 }')"
    # "0" is the only answer that proves sleep came back, and "1" the only one
    # that proves it did not. Anything else is pmset not answering: it must not
    # pass as success, and it must not be reported as a failed restore either.
    if [[ "$sleep_state" == "1" ]]; then
        sleep_stuck=1
    elif [[ "$sleep_state" != "0" ]]; then
        sleep_unknown=1
    fi
fi

# With the marker gone, nothing will ever put Space rearranging back, so this
# is the only warning anyone will get. Only a 0 proves it is still off: a
# missing key is the system default, which rearranges. This only reads the
# Dock's preference; changing it is left to the user.
spaces_stuck=0
spaces_unloaded=0
spaces_unknown=0
case "$(spaces_removal_state "$spaces_owed" "$spaces_journal")" in
    stuck) spaces_stuck=1 ;;
    unloaded) spaces_unloaded=1 ;;
    unknown) spaces_unknown=1 ;;
esac

if (( detached == 0 && sleep_stuck == 0 && sleep_unknown == 0 && spaces_stuck == 0 && spaces_unloaded == 0 && spaces_unknown == 0 )); then
    echo "✓ Vorssaint fully removed."
    exit 0
fi
if (( detached )); then
    echo "⚠ Vorssaint removed, but its fan helper is still registered with the system." >&2
    echo "  Reinstall Vorssaint, then use Settings › Advanced to uninstall from inside the app." >&2
fi
if (( sleep_stuck )); then
    echo "⚠ Vorssaint removed, but this Mac still has sleep switched off." >&2
    echo "  Closed-lid mode disabled it, and restoring it needed a password this script could not ask for." >&2
    echo "  Put it back with: sudo pmset disablesleep 0" >&2
fi
if (( sleep_unknown )); then
    echo "⚠ Vorssaint removed, but whether sleep came back could not be read." >&2
    echo "  Closed-lid mode had switched it off. Check with: pmset -g | grep SleepDisabled" >&2
    echo "  If that reads 1, put it back with: sudo pmset disablesleep 0" >&2
fi
if (( spaces_stuck )); then
    echo "⚠ Vorssaint removed, but Spaces are still kept in a fixed order." >&2
    echo "  Fixed Space order had turned rearranging off, and it was not put back." >&2
    echo "  Turn it back on in System Settings › Desktop & Dock with" >&2
    echo "  \"Automatically rearrange Spaces based on most recent use\"." >&2
fi
if (( spaces_unloaded )); then
    echo "⚠ Vorssaint removed, but the Dock still keeps Spaces in a fixed order." >&2
    echo "  Space rearranging was put back on, and the Dock reads it when it restarts." >&2
    echo "  Log out and back in to finish." >&2
fi
if (( spaces_unknown )); then
    print -u2 "Vorssaint removed, but whether Space rearranging was restored could not be confirmed."
    print -u2 "Check Automatically rearrange Spaces based on most recent use in System Settings."
fi
exit 1
