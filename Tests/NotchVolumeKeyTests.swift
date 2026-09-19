// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchVolumeKeyTests {
    static func run(expect: (Bool, String) -> Void) {
        NotchVolumeFeedbackTests.run(expect: expect)
        var gate = NotchVolumeKeyGate()
        func press(_ key: Int32 = 0, state: Int = 0x0a, enabled: Bool = true, visible: Bool = true,
                   volume: Bool = true, mute: Bool = true, option: Bool = false,
                   shift: Bool = false, modified: Bool = false, repeated: Bool = false) -> NotchVolumeKeyGate.Action {
            gate.handle(keyCode: key, state: state, isRepeat: repeated,
                        enabled: enabled, acceptsNewPress: visible, hasVolume: volume, hasMute: mute,
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

        for key: Int32 in [0, 1, 7] {
            let action: NotchVolumeKeyGate.Action = key == 7 ? .toggleMute : .step(key == 0 ? 1 : -1)
            let repeatedAction: NotchVolumeKeyGate.Action = key == 7 ? .consume : action
            expect(press(key, visible: false) == .passThrough, "hidden volume starts with the native handler")
            for visible in [false, true, false, true] {
                expect(press(key, visible: visible, repeated: true) == .passThrough,
                       "revealing and hiding the island never takes over a native held key")
            }
            expect(press(key, state: 0x0b) == .passThrough, "the native handler receives its release after revealing")

            expect(press(key) == action, "the next fresh visible press can use island volume")
            for visible in [true, false, true, false] {
                expect(press(key, visible: visible, repeated: true) == repeatedAction,
                       "a held island key keeps working through visibility changes without leaking native repeats")
            }
            expect(press(key, state: 0x0b, visible: false) == .consume,
                   "the island releases its held key after hiding")
        }
        for unavailable: () -> NotchVolumeKeyGate.Action in [
            { press(enabled: false, repeated: true) }, { press(volume: false, repeated: true) },
            { press(option: true, repeated: true) }, { press(modified: true, repeated: true) }
        ] {
            expect(press() == .step(1), "an eligible press starts before conditions change")
            expect(unavailable() == .consume,
                   "disabling or losing a volume control stops adjustment without sending an orphan native repeat")
            expect(press(state: 0x0b) == .consume, "an interrupted adjustment still owns its release")
        }
    }
}
