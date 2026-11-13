#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
if (( EUID != 0 )); then
    exec sudo /bin/zsh "$0"
fi
entries=('VorssaintAudio:com.vorssaint.utils.software-volume.driver' 'VorssaintAudioFork:com.vorssaint.audiofork.driver')
# Validate every destination before deleting anything. Never follow a symlink
# or remove an unrelated HAL plug-in that happens to use this directory name.
for entry in "${entries[@]}"; do
    name="${entry%%:*}"
    expected="${entry#*:}"
    bundle="/Library/Audio/Plug-Ins/HAL/$name.driver"
    if [[ -e "$bundle" || -L "$bundle" ]]; then
        [[ -d "$bundle" && ! -L "$bundle" ]] || { echo 'Unexpected driver path; nothing removed.' >&2; exit 1; }
        identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")"
        [[ "$identifier" == "$expected" ]] || { echo 'Unexpected driver identity; nothing removed.' >&2; exit 1; }
    fi
done
changed=0
for entry in "${entries[@]}"; do
    name="${entry%%:*}"
    expected="${entry#*:}"
    bundle="/Library/Audio/Plug-Ins/HAL/$name.driver"
    if [[ -d "$bundle" ]]; then
        /bin/rm -rf "$bundle"
        changed=1
    fi
    # Also clean a stale receipt after manual bundle removal.
    /usr/sbin/pkgutil --forget "$expected.pkg" 2>/dev/null || true
done
if (( changed )); then /usr/bin/killall coreaudiod 2>/dev/null || true; fi
echo 'Vorssaint Audio component removed.'
