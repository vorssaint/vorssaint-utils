#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Runs the real Space arrangement check from Tools/uninstall.sh, lifted out of
# the script so nothing here quits, resets or removes anything.
set -euo pipefail
cd "$(dirname "$0")/.."
source <(sed -n '/^spaces_leftover() {$/,/^}$/p' Tools/uninstall.sh)
(( $+functions[spaces_leftover] ))

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

(( failures == 0 )) || exit 1
print 'UNINSTALL SPACES TESTS OK'
