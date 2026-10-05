#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Runs the real Space arrangement check from Tools/uninstall.sh, lifted out of
# the script so nothing here quits, resets or removes anything.
set -euo pipefail
cd "$(dirname "$0")/.."
for helper in spaces_read_domain spaces_recovery_value spaces_dock_preference spaces_dock_pid spaces_leftover spaces_removal_state; do
    source <(sed -n "/^${helper}() {$/,/^}$/p" Tools/uninstall.sh)
    (( $+functions[$helper] ))
done

failures=0
expect() {
    local wanted=$1 owed=$2 journal=$3 preference=$4 dock_pid=$5 found
    found="$(spaces_leftover "$owed" "$journal" "$preference" "$dock_pid")"
    if [[ "$found" != "$wanted" ]]; then
        print -u2 "spaces_leftover '$owed' '$journal' '$preference' '$dock_pid': wanted '$wanted', found '$found'"
        failures=$((failures + 1))
    fi
}

# Settled: nothing owed, or a restore the Dock already reads.
expect "" "" "" "" 500
expect "" "" "" "1" 500
expect "" "absent" "" "" 500
expect "" "on" "" "1" 500
# Rearranging the user turned off themselves is theirs, not a failed restore.
expect "" "" "" "0" 500
# Nor is rearranging that was already off when fixed order turned on.
expect "" "off" "" "0" 500
expect "" "off" "" "1" 500
expect "" "off" "" "" 500
# A restore that never happened.
expect stuck "absent" "" "0" 500
expect stuck "on" "500 rearranging off" "0" 500
# A restore written back while the same Dock still keeps a fixed order. The
# marker is already gone once the setting is back.
expect unloaded "" "500 fixed absent" "" 500
expect unloaded "" "500 fixed on" "1" 500
expect unloaded "absent" "500 fixed absent" "" 500
expect unloaded "" "500 fixed absent off absent" "" 500
# A Dock that restarted since, or none running, has read the preference.
expect "" "" "500 fixed absent" "" 501
expect "" "" "500 fixed absent" "" ""
# A value never written is a later change the Dock applied itself.
expect "" "" "500 fixed absent" "1" 500
# The Dock already runs what an owed restart would load.
expect "" "" "500 fixed absent off" "0" 500
expect "" "" "500 rearranging off absent" "" 500

# An unreadable value is never a confirmed absent key while recovery is owed.
expect unknown on "" unknown 500
expect unknown "" "500 fixed absent" unknown 500
expect unknown "" "500 fixed on" 1 unknown
expect unknown on "" unexpected 500
expect unknown unexpected "" 1 500
expect unknown "" "broken journal" 1 500
expect unknown "" "500 fixed unexpected" 1 500
# No recorded debt, including a setting that was already fixed, needs no probe.
expect "" "" "" unknown unknown
expect "" off "" unknown unknown

# Run the real probes with only defaults and pgrep replaced. plutil handles
# these in-memory fixtures, and no domain is read or written by the tests.
probe_xml='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict/></plist>'
probe_status=0
probe_pid=500
probe_pid_status=0
recovery_xml=''
defaults() {
    [[ "$1" == export && "$3" == - ]] || return 2
    if [[ "$2" == example && -n "$recovery_xml" ]]; then
        print -r -- "$recovery_xml"
        return 0
    fi
    print -r -- "$probe_xml"
    return "$probe_status"
}
pgrep() {
    print -r -- "$probe_pid"
    return "$probe_pid_status"
}
expect_probe() {
    local wanted=$1 found
    found="$(spaces_dock_preference)"
    if [[ "$found" != "$wanted" ]]; then
        print -u2 "spaces_dock_preference wanted '$wanted', found '$found'"
        failures=$((failures + 1))
    fi
}
expect_state() {
    local wanted=$1 owed=$2 journal=$3 found
    found="$(spaces_removal_state "$owed" "$journal")"
    if [[ "$found" != "$wanted" ]]; then
        print -u2 "spaces_removal_state wanted '$wanted', found '$found'"
        failures=$((failures + 1))
    fi
}

expect_probe ""
expect_state "" on ""
probe_status=1
expect_probe unknown
expect_state unknown on ""
expect_state "" "" ""
expect_state "" off ""
if spaces_read_domain example >/dev/null; then
    print -u2 'a failed app-domain read must stop before recovery is removed'
    failures=$((failures + 1))
fi
probe_status=0
probe_xml='unreadable plist'
expect_probe unknown
probe_xml='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>mru-spaces</key><false/></dict></plist>'
expect_probe 0
expect_state stuck on ""
expect_state "" off ""
probe_xml='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>mru-spaces</key><true/></dict></plist>'
expect_probe 1
expect_state "" on ""
expect_state unloaded "" '500 fixed on'
probe_pid_status=2
expect_state unknown "" '500 fixed on'
probe_pid_status=1
expect_state "" "" '500 fixed on'
probe_pid_status=0
probe_xml='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>mru-spaces</key><integer>0</integer></dict></plist>'
expect_probe 0
probe_xml='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>mru-spaces</key><integer>1</integer></dict></plist>'
expect_probe 1
probe_xml='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>mru-spaces</key><string>0</string></dict></plist>'
expect_probe unknown

# A valid domain may contain unrelated data values that JSON cannot represent.
probe_xml='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>unrelated</key><data>AA==</data></dict></plist>'
snapshot="$(spaces_read_domain example)"
[[ -z "$(spaces_recovery_value "$snapshot" spacesOrderRestore)" ]] || failures=$((failures + 1))
probe_xml='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>spacesOrderRestore</key><string>on</string><key>spacesOrderRestartPending</key><string>500 fixed on</string></dict></plist>'
snapshot="$(spaces_read_domain example)"
[[ "$(spaces_recovery_value "$snapshot" spacesOrderRestore)" == on ]] || failures=$((failures + 1))
[[ "$(spaces_recovery_value "$snapshot" spacesOrderRestartPending)" == '500 fixed on' ]] || failures=$((failures + 1))
probe_xml='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>spacesOrderRestore</key><array/></dict></plist>'
snapshot="$(spaces_read_domain example)"
if spaces_recovery_value "$snapshot" spacesOrderRestore >/dev/null; then
    print -u2 'an unreadable recovery value must stop before preferences are removed'
    failures=$((failures + 1))
fi

# Run only the real pre-removal guard, ending before any reset or deletion.
# Both commands it can read are fakes above, and exit stays in the subshell.
preflight="$(sed -n '/^if ! spaces_snapshot=/,/^echo "▸ Resetting permissions/{ /^echo "▸ Resetting permissions/d; p; }' Tools/uninstall.sh)"
[[ -n "$preflight" ]] || exit 1
BUNDLE=example
recovery_xml='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>spacesOrderRestore</key><string>on</string></dict></plist>'
probe_status=1
if (source /dev/stdin <<< "$preflight") >/dev/null 2>&1; then
    print -u2 'unknown restoration must exit before resets or preference deletion'
    failures=$((failures + 1))
fi
probe_status=0
probe_xml='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>mru-spaces</key><false/></dict></plist>'
if (source /dev/stdin <<< "$preflight") >/dev/null 2>&1; then
    print -u2 'a failed restore must keep its recovery rather than remove the app'
    failures=$((failures + 1))
fi
recovery_xml='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>spacesOrderRestore</key><string>off</string></dict></plist>'
probe_status=1
if ! (source /dev/stdin <<< "$preflight") >/dev/null 2>&1; then
    print -u2 'an original fixed order without restart debt must not block removal'
    failures=$((failures + 1))
fi
recovery_xml='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict/></plist>'
if ! (source /dev/stdin <<< "$preflight") >/dev/null 2>&1; then
    print -u2 'no recorded recovery must not block removal'
    failures=$((failures + 1))
fi

(( failures == 0 )) || exit 1
print 'UNINSTALL SPACES TESTS OK'
