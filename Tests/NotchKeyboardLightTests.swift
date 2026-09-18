// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchKeyboardLightTests {
    static func run(expect: (Bool, String) -> Void) {
        for code in 0...31 {
            for state in [0, 10, 11, 255] {
                for repeatBit in [0, 1] {
                    let payload = (code << 16) | (state << 8) | repeatBit
                    expect(BrightnessSupport.isKeyboardLightPress(subtype: 8, data1: payload)
                           == ((21...23).contains(code) && state == 10),
                           "keyboard light notices recognize only native illumination key-downs, including repeats")
                    expect(!BrightnessSupport.isKeyboardLightPress(subtype: 1, data1: payload),
                           "other system event types never become keyboard light notices")
                }
            }
        }
        let suite = "com.vorssaint.tests.notch-keyboard-light"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(false, forKey: DefaultsKey.brightnessControlEnabled)
        expect(!NotchSupport.routes(.keyboardLight, in: defaults), "keyboard light notices are opt-in")
        defaults.set(true, forKey: DefaultsKey.notchKeyboardLight)
        expect(NotchSupport.routes(.keyboardLight, in: defaults),
               "keyboard light does not depend on enabling display control")
        defaults.set(false, forKey: AppFeature.brightness.availabilityKey)
        expect(!NotchSupport.routes(.keyboardLight, in: defaults), "removing brightness also gates its keyboard light notices")
        defaults.set(true, forKey: AppFeature.brightness.availabilityKey)
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        expect(!NotchSupport.routes(.keyboardLight, in: defaults), "the notch master switch suppresses keyboard light notices")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchKeyboardLight),
               "keyboard light notice preference travels in backup")
    }
}
