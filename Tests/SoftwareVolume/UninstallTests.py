# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise the shipped uninstaller in a disposable filesystem, never the HAL.

Only its fixed system paths, elevation and OS notification commands are replaced.
The identity validation and deletion control flow are the production script.
"""
import pathlib
import plistlib
import subprocess
import tempfile

source = pathlib.Path('Tools/uninstall-software-volume-driver.sh').read_text()
checks = 0
with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    hal = root / 'HAL'
    hal.mkdir()
    calls = root / 'calls'
    notify = root / 'notify'
    notify.write_text('#!/bin/zsh\nprint -r -- "$*" >> ' + repr(str(calls)) + '\n')
    notify.chmod(0o755)
    script = root / 'uninstall.sh'
    script.write_text(source.replace('if (( EUID != 0 )); then\n    exec sudo /bin/zsh "$0"\nfi\n', '')
                      .replace('/Library/Audio/Plug-Ins/HAL', str(hal))
                      .replace('/usr/sbin/pkgutil', str(notify))
                      .replace('/usr/bin/killall', str(notify)))

    def bundle(name, identifier):
        destination = hal / (name + '.driver')
        (destination / 'Contents').mkdir(parents=True)
        with (destination / 'Contents/Info.plist').open('wb') as file:
            plistlib.dump({'CFBundleIdentifier': identifier}, file)
        return destination

    def run():
        calls.write_text('')
        return subprocess.run(['/bin/zsh', str(script)], capture_output=True).returncode

    def expect(value, description):
        global checks
        checks += 1
        assert value, description

    other = bundle('OtherAudio', 'org.example.other')
    current = bundle('VorssaintAudio', 'com.vorssaint.utils.software-volume.driver')
    legacy = bundle('VorssaintAudioFork', 'com.vorssaint.audiofork.driver')
    expect(run() == 0, 'remove both identified driver versions')
    expect(not current.exists() and not legacy.exists(), 'all driver payloads removed')
    expect(other.exists(), 'unrelated HAL driver preserved')
    expect(calls.read_text().count('--forget ') == 2, 'both package receipts forgotten')
    expect('coreaudiod' in calls.read_text(), 'restart audio after removal')
    expect(run() == 0, 'repeat removal is idempotent')
    expect(calls.read_text().count('--forget ') == 2 and 'coreaudiod' not in calls.read_text(),
           'clean stale receipts even without bundles; avoid unnecessary restart')
    current = bundle('VorssaintAudio', 'com.vorssaint.utils.software-volume.driver')
    legacy = bundle('VorssaintAudioFork', 'org.example.unrelated')
    expect(run() != 0 and current.exists() and legacy.exists(), 'preflight all identities before any deletion')
    expect(calls.read_text() == '', 'mismatching identity does not mutate receipts/audio')
    # Use a separate fresh directory for the symlink case, preserving fixtures.
    linked = root / 'linkedHAL'
    linked.mkdir()
    (linked / 'VorssaintAudio.driver').symlink_to(current, target_is_directory=True)
    script.write_text(script.read_text().replace(str(hal), str(linked)))
    expect(run() != 0 and current.exists(), 'refuse symbolic-link driver destinations')
print(f'VORSSAINT AUDIO UNINSTALL: {checks} checks, 0 failures')
