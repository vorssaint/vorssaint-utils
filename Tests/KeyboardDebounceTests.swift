// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum KeyboardDebounceTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Keyboard debounce

        var debounceState = KeyboardDebounceState()
        let debounceConfig = KeyboardDebounceConfig(enabled: true,
                                                    globalWindowMs: 50,
                                                    keyWindows: [:])
        func debounceDown(_ keyCode: Int64,
                          at time: TimeInterval,
                          repeat isAutoRepeat: Bool = false,
                          config: KeyboardDebounceConfig) -> Bool {
            debounceState.shouldSuppress(keyCode: keyCode,
                                         isAutoRepeat: isAutoRepeat,
                                         event: .keyDown,
                                         time: time,
                                         config: config)
        }
        func debounceUp(_ keyCode: Int64,
                        at time: TimeInterval,
                        config: KeyboardDebounceConfig) -> Bool {
            debounceState.shouldSuppress(keyCode: keyCode,
                                         isAutoRepeat: false,
                                         event: .keyUp,
                                         time: time,
                                         config: config)
        }
        expect(!debounceDown(37, at: 10.00, config: debounceConfig),
               "debounce accepts the first key press")
        expect(!debounceUp(37, at: 10.01, config: debounceConfig),
               "debounce accepts key release")
        expect(debounceDown(37, at: 10.03, config: debounceConfig),
               "debounce suppresses same-key bounce after release")
        expect(!debounceDown(37, at: 10.06, config: debounceConfig),
               "debounce accepts same-key press after the release window")
        expect(!debounceDown(37, at: 10.07, repeat: true, config: debounceConfig),
               "debounce leaves key auto-repeat alone")
        let fastConfig = KeyboardDebounceConfig(enabled: true,
                                                globalWindowMs: 10,
                                                keyWindows: [:])
        debounceState.reset()
        expect(!debounceDown(0, at: 40.000, config: fastConfig),
               "debounce 10 ms accepts the first fast key press")
        _ = debounceUp(0, at: 40.004, config: fastConfig)
        expect(debounceDown(0, at: 40.009, config: fastConfig),
               "debounce 10 ms suppresses same-key bounce inside the release window")
        expect(!debounceDown(0, at: 40.014, config: fastConfig),
               "debounce 10 ms accepts the same key at the release boundary")
        let defaultDebounceConfig = KeyboardDebounceConfig(enabled: true,
                                                           globalWindowMs: Defaults.defaultKeyboardDebounceWindowMs,
                                                           keyWindows: [:])
        debounceState.reset()
        expect(!debounceDown(0, at: 45.000, config: defaultDebounceConfig),
               "debounce 5 ms default accepts the first fast key press")
        _ = debounceUp(0, at: 45.001, config: defaultDebounceConfig)
        expect(debounceDown(0, at: 45.005, config: defaultDebounceConfig),
               "debounce 5 ms default suppresses same-key bounce inside the release window")
        expect(!debounceDown(0, at: 45.006, config: defaultDebounceConfig),
               "debounce 5 ms default accepts the same key at the release boundary")
        debounceState.reset()
        expect(!debounceDown(37, at: 50.000, config: fastConfig),
               "debounce accepts normal phrase first letter")
        _ = debounceUp(37, at: 50.020, config: fastConfig)
        expect(!debounceDown(14, at: 50.025, config: fastConfig),
               "debounce accepts normal phrase next letter")
        _ = debounceUp(14, at: 50.045, config: fastConfig)
        expect(!debounceDown(17, at: 50.050, config: fastConfig),
               "debounce accepts normal phrase repeated-letter first press")
        _ = debounceUp(17, at: 50.070, config: fastConfig)
        expect(!debounceDown(17, at: 50.110, config: fastConfig),
               "debounce accepts normal phrase repeated-letter second press")
        debounceState.reset()
        expect(!debounceDown(0, at: 60.000, config: fastConfig),
               "debounce accepts the first key in an alternating pattern")
        _ = debounceUp(0, at: 60.004, config: fastConfig)
        expect(!debounceDown(11, at: 60.006, config: fastConfig),
               "debounce accepts a different key inside another key's window")
        _ = debounceUp(11, at: 60.009, config: fastConfig)
        expect(!debounceDown(0, at: 60.011, config: fastConfig),
               "debounce accepts a same-key press after another key was accepted")
        debounceState.reset()
        expect(!debounceDown(0, at: 70.000, config: fastConfig),
               "debounce accepts the first key before duplicate down")
        expect(debounceDown(0, at: 70.004, config: fastConfig),
               "debounce suppresses non-repeat duplicate down while the key is still down")
        expect(!debounceUp(0, at: 70.020, config: fastConfig),
               "debounce still passes the release after a duplicate down")
        debounceState.reset()
        expect(!debounceDown(0, at: 75.000, config: fastConfig),
               "debounce accepts a key before a missing release")
        expect(!debounceDown(0, at: 75.020, config: fastConfig),
               "debounce accepts a same-key press after the window even if release was missed")
        debounceState.reset()
        expect(!debounceDown(0, at: 80.000, config: fastConfig),
               "debounce accepts the first key before an out-of-order event")
        _ = debounceUp(0, at: 80.010, config: fastConfig)
        expect(!debounceDown(0, at: 79.990, config: fastConfig),
               "debounce resets same-key state when event timestamps move backward")
        let perKeyConfig = KeyboardDebounceConfig(enabled: true,
                                                  globalWindowMs: 20,
                                                  keyWindows: [37: 100, 40: 0])
        debounceState.reset()
        _ = debounceDown(37, at: 20.00, config: perKeyConfig)
        _ = debounceUp(37, at: 20.01, config: perKeyConfig)
        expect(debounceDown(37, at: 20.06, config: perKeyConfig),
               "debounce per-key window overrides the global window")
        _ = debounceDown(40, at: 30.00, config: perKeyConfig)
        _ = debounceUp(40, at: 30.005, config: perKeyConfig)
        expect(!debounceDown(40, at: 30.006, config: perKeyConfig),
               "debounce per-key zero disables filtering for that key")
        let encodedKeyWindows = KeyboardDebounceConfig.encodeKeyWindows([37: 100, 40: 0])
        expect(encodedKeyWindows == "37:100,40:0",
               "debounce key windows encode in stable key order")
        expect(KeyboardDebounceConfig.decodeKeyWindows("37:100,bad,40:0,99:999")
               == [37: 100, 40: 0, 99: Defaults.defaultKeyboardDebounceWindowMs],
               "debounce key windows decode and sanitize stored values")
    }
}
