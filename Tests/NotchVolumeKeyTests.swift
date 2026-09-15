// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchVolumeKeyTests {
    static func run(expect: (Bool, String) -> Void) {
        var gate = NotchVolumeKeyGate()
        func press(_ key: Int32 = 0, state: Int = 0x0a, enabled: Bool = true,
                   volume: Bool = true, mute: Bool = true, option: Bool = false,
                   shift: Bool = false, modified: Bool = false, repeated: Bool = false) -> NotchVolumeKeyGate.Action {
            gate.handle(keyCode: key, state: state, isRepeat: repeated,
                        enabled: enabled, hasVolume: volume, hasMute: mute,
                        option: option, shift: shift, commandOrControl: modified)
        }
        expect(press(enabled: false) == .passThrough, "disabled notch leaves native volume keys alone")
        expect(press(state: 0x0b) == .passThrough, "a native press keeps its native release")
        expect(press() == .step(1), "volume up requests one audible step")
        expect(press(state: 0x0b, enabled: false) == .consume,
               "a consumed press owns its release even if the feature turns off")
        expect(press(1) == .step(-1), "volume down requests one audible step")
        expect(press(1, state: 0x0b) == .consume, "volume down releases without stepping again")
        expect(press(volume: false) == .passThrough,
               "outputs without software volume retain native behavior")
        expect(press(option: true) == .passThrough, "Option-volume still opens the system sound settings")
        expect(press(option: true, shift: true) == .step(1), "fine volume keys reach the notch")
        _ = press(state: 0x0b)
        expect(press(modified: true) == .passThrough, "unrelated modifier shortcuts are preserved")
        expect(press(16) == .passThrough && press(2) == .passThrough,
               "playback and brightness keys never enter the volume path")
        expect(press(7, mute: false) == .passThrough, "unsupported mute remains native")
        expect(press(7, volume: false) == .toggleMute, "mute works independently of software volume")
        expect(press(7, repeated: true) == .consume, "holding mute cannot oscillate between muted and unmuted")
        expect(press(7, state: 0x0b) == .consume, "mute releases without toggling twice")
        expect(press(state: 0) == .passThrough, "unknown system-key states pass through")
    }
}
