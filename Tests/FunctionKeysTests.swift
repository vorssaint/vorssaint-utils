// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The Spotlight (F4), dictation (F5) and Do Not Disturb (F6) keys: which presses are taken,
/// which pass through, and that a held key or its release never reaches the
/// system once its press was taken.
enum FunctionKeysTests {
    static func run(_ suite: TestSuite) {
        typealias Support = FunctionKeysSupport
        let f4 = Support.spotlightKeyCode
        let f5 = Support.dictationKeyCode
        let f6 = Support.doNotDisturbKeyCode
        let both = Support.Configuration(micMuteEnabled: true, sleepEnabled: true, microphoneMuteAvailable: true)
        let all = Support.Configuration(micMuteEnabled: true, sleepEnabled: true, microphoneMuteAvailable: true,
                                        findEnabled: true)
        let findOnly = Support.Configuration(micMuteEnabled: false, sleepEnabled: false,
                                             microphoneMuteAvailable: false, findEnabled: true)
        func decide(_ key: Int64, down: Bool = true, repeating: Bool = false, modifiers: Bool = false,
                    _ configuration: Support.Configuration) -> Support.Decision {
            Support.decision(keyCode: key, isKeyDown: down, isAutoRepeat: repeating,
                             hasModifiers: modifiers, configuration: configuration)
        }

        suite.expect(f4 == 177 && f5 == 176 && f6 == 178,
                     "the key codes are the ones an Apple keyboard sends for F4, F5 and F6")
        suite.expect(Support.Key(keyCode: f4) == .spotlight && Support.Key(keyCode: f5) == .dictation
                     && Support.Key(keyCode: f6) == .doNotDisturb
                     && Support.Key(keyCode: 96) == nil && Support.Key(keyCode: 0) == nil,
                     "only the Spotlight, dictation and Do Not Disturb keys are recognized")

        // F4 presses Command-F, whatever the other two are set to.
        suite.expect(decide(f4, all) == .perform(.findInFrontApp) && decide(f4, findOnly) == .perform(.findInFrontApp),
                     "F4 presses Command-F when it is switched on, with or without the microphone mute installed")
        suite.expect(decide(f4, both) == .passThrough && decide(f4, .off) == .passThrough,
                     "F4 stays Spotlight while its own switch is off")
        suite.expect(decide(f5, findOnly) == .passThrough && decide(f6, findOnly) == .passThrough,
                     "switching F4 on takes neither of the other two keys")
        suite.expect(decide(f4, all) != decide(f5, all) && decide(f4, all) != decide(f6, all)
                     && decide(f5, all) == .perform(.toggleMicrophone) && decide(f6, all) == .perform(.sleepSystem),
                     "with all three on, each key keeps its own job")
        suite.expect(decide(f4, down: true, repeating: true, findOnly) == .swallow
                     && decide(f4, down: false, findOnly) == .swallow,
                     "a held F4 searches once and neither the repeat nor the release reaches Spotlight")
        suite.expect(decide(f4, modifiers: true, findOnly) == .passThrough
                     && decide(f4, down: false, modifiers: true, findOnly) == .passThrough,
                     "F4 held with Command, Control, Option or Shift belongs to the system")
        suite.expect(Support.findKeyCode == 3 && Support.findShortcutFlags == .maskCommand
                     && !Support.findShortcutFlags.contains(.maskSecondaryFn),
                     "the key it presses is F with Command alone, without the Fn flag F4 arrives with")

        suite.expect(decide(f5, both) == .perform(.toggleMicrophone),
                     "F5 toggles the microphone mute when it is switched on")
        suite.expect(decide(f6, both) == .perform(.sleepSystem),
                     "F6 puts the Mac to sleep when it is switched on")
        suite.expect(decide(f5, .off) == .passThrough && decide(f6, .off) == .passThrough,
                     "nothing is taken while the feature is off")
        suite.expect(decide(f5, Support.Configuration(micMuteEnabled: false, sleepEnabled: true,
                                                      microphoneMuteAvailable: true)) == .passThrough
                     && decide(f6, Support.Configuration(micMuteEnabled: true, sleepEnabled: false,
                                                         microphoneMuteAvailable: true)) == .passThrough,
                     "each key follows its own switch")
        suite.expect(decide(f5, Support.Configuration(micMuteEnabled: true, sleepEnabled: true,
                                                      microphoneMuteAvailable: false)) == .passThrough
                     && decide(f6, Support.Configuration(micMuteEnabled: true, sleepEnabled: true,
                                                         microphoneMuteAvailable: false)) == .perform(.sleepSystem),
                     "F5 is left to dictation when the microphone mute is not installed, and F6 is unaffected")
        suite.expect(decide(96, both) == .passThrough && decide(0, both) == .passThrough
                     && decide(36, down: false, both) == .passThrough,
                     "every other key passes through untouched")

        suite.expect(decide(f5, down: true, repeating: true, both) == .swallow
                     && decide(f6, down: true, repeating: true, both) == .swallow,
                     "a held key repeats nothing and is still kept from the system")
        suite.expect(decide(f5, down: false, both) == .swallow && decide(f6, down: false, both) == .swallow,
                     "the release of a taken key is kept from the system too")
        suite.expect(decide(f5, modifiers: true, both) == .passThrough
                     && decide(f6, modifiers: true, both) == .passThrough
                     && decide(f5, down: false, modifiers: true, both) == .passThrough,
                     "a key held with Command, Control, Option or Shift belongs to the system")
        suite.expect(Support.shortcutModifiers == [.maskCommand, .maskControl, .maskAlternate, .maskShift]
                     && !Support.shortcutModifiers.contains(.maskSecondaryFn),
                     "the Fn modifier alone does not count as a shortcut")

        suite.expect(findOnly.wantsTap && !Support.Configuration(micMuteEnabled: false, sleepEnabled: false,
                                                                 microphoneMuteAvailable: true).wantsTap,
                     "F4 alone is enough to run the tap")
        suite.expect(!Support.Configuration.off.wantsTap && both.wantsTap
                     && Support.Configuration(micMuteEnabled: false, sleepEnabled: true,
                                              microphoneMuteAvailable: false).wantsTap
                     && !Support.Configuration(micMuteEnabled: true, sleepEnabled: false,
                                               microphoneMuteAvailable: false).wantsTap,
                     "the tap runs only when a switched-on key can actually do its job")

        // The feature's place in the catalog and its defaults.
        suite.expect(AppFeature.functionKeys.rawValue == "functionKeys",
                     "the feature keeps a stable id")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.functionKeysMicMuteEnabled] as? Bool == false
                     && Defaults.registeredDefaults[DefaultsKey.functionKeysSleepEnabled] as? Bool == false
                     && Defaults.registeredDefaults[DefaultsKey.functionKeysFindEnabled] as? Bool == false,
                     "all three keys are off by default")
        suite.expect(AppFeature.functionKeys.enabledKeys
                        == [DefaultsKey.functionKeysMicMuteEnabled, DefaultsKey.functionKeysSleepEnabled,
                            DefaultsKey.functionKeysFindEnabled],
                     "the feature counts as on when any key is switched on")
        suite.expect(!AppFeature.functionKeys.installedByDefault,
                     "the feature is not installed until someone adds it")
        suite.expect(AppFeature.functionKeys.permissions == [.accessibility],
                     "the tap needs Accessibility")
    }
}
