// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AutoFullscreenTests {
    static func run(_ suite: TestSuite) {
        // MARK: Which launches are watched

        suite.expect(AutoFullscreenSupport.shouldWatch(bundleIdentifier: "com.example.editor",
                                                       isRegularApp: true, isOwnApp: false,
                                                       exceptions: []),
               "an ordinary app launch is watched")
        suite.expect(!AutoFullscreenSupport.shouldWatch(bundleIdentifier: "com.example.editor",
                                                        isRegularApp: true, isOwnApp: false,
                                                        exceptions: ["com.example.editor"]),
               "an app on the exception list opens normally")
        suite.expect(!AutoFullscreenSupport.shouldWatch(bundleIdentifier: "com.example.editor",
                                                        isRegularApp: true, isOwnApp: false,
                                                        exceptions: [" com.example.editor "]),
               "a saved exception with stray whitespace still matches")
        suite.expect(!AutoFullscreenSupport.shouldWatch(bundleIdentifier: "com.example.agent",
                                                        isRegularApp: false, isOwnApp: false,
                                                        exceptions: []),
               "menu bar agents and background helpers are never touched")
        suite.expect(!AutoFullscreenSupport.shouldWatch(bundleIdentifier: "com.vorssaint.utils",
                                                        isRegularApp: true, isOwnApp: true,
                                                        exceptions: []),
               "Vorssaint never puts its own windows in full screen")
        suite.expect(AutoFullscreenSupport.shouldWatch(bundleIdentifier: nil,
                                                       isRegularApp: true, isOwnApp: false,
                                                       exceptions: ["com.example.editor"]),
               "an app without a bundle id cannot be listed, so it is watched")

        // MARK: Displays

        suite.expect(AutoFullscreenSupport.displaysAllow(builtInDisplayOnly: true, builtInFlags: [true]),
               "the built-in display alone allows full screen")
        suite.expect(!AutoFullscreenSupport.displaysAllow(builtInDisplayOnly: true, builtInFlags: [true, false]),
               "an external display next to the built-in one skips the launch")
        suite.expect(!AutoFullscreenSupport.displaysAllow(builtInDisplayOnly: true, builtInFlags: [false]),
               "clamshell mode, with only the external display online, skips the launch")
        suite.expect(!AutoFullscreenSupport.displaysAllow(builtInDisplayOnly: true, builtInFlags: nil)
                && !AutoFullscreenSupport.displaysAllow(builtInDisplayOnly: true, builtInFlags: []),
               "an unreadable display list skips the launch instead of guessing")
        suite.expect(AutoFullscreenSupport.displaysAllow(builtInDisplayOnly: false, builtInFlags: [false])
                && AutoFullscreenSupport.displaysAllow(builtInDisplayOnly: false, builtInFlags: nil),
               "with the option off, every display setup allows full screen")

        // MARK: Each look

        let window = AutoFullscreenSupport.launchWindow
        let late = window - AutoFullscreenSupport.lookInterval / 2
        suite.expect(AutoFullscreenSupport.nextStep(for: .windowed, appIsFrontmost: true, elapsed: 0.5)
                    == .requestFullScreen
                && AutoFullscreenSupport.nextStep(for: .windowed, appIsFrontmost: true, elapsed: late)
                    == .requestFullScreen,
               "a standard window of the app in front is asked to enter full screen, even on the last look")
        suite.expect(AutoFullscreenSupport.hasTimeLeft(after: 0.5)
                && !AutoFullscreenSupport.hasTimeLeft(after: late),
               "a request is confirmed by another look only while the launch window lasts")
        suite.expect(AutoFullscreenSupport.nextStep(for: .windowed, appIsFrontmost: false, elapsed: 0.5)
                    == .lookAgain
                && AutoFullscreenSupport.nextStep(for: .windowed, appIsFrontmost: false, elapsed: late)
                    == .finish,
               "an app launched in the background is never pulled into a new Space, only watched in case it comes forward")
        suite.expect(AutoFullscreenSupport.nextStep(for: .fullScreen, appIsFrontmost: true, elapsed: 2) == .finish
                && AutoFullscreenSupport.nextStep(for: .fullScreen, appIsFrontmost: false, elapsed: 2) == .finish,
               "a window already in full screen ends the series")
        suite.expect(AutoFullscreenSupport.nextStep(for: .fixed, appIsFrontmost: true, elapsed: 0.5) == .finish,
               "a window that cannot enter full screen is left alone at once")
        suite.expect(AutoFullscreenSupport.nextStep(for: .none, appIsFrontmost: true, elapsed: 0.5) == .lookAgain
                && AutoFullscreenSupport.nextStep(for: .none, appIsFrontmost: true, elapsed: late) == .finish
                && AutoFullscreenSupport.nextStep(for: .none, appIsFrontmost: true, elapsed: 120) == .finish,
               "an app with no window yet, or too busy to answer, is looked at again until the launch window ends")
        suite.expect(window >= 14 && window <= 16
                && AutoFullscreenSupport.firstLookDelay < window
                && AutoFullscreenSupport.lookInterval > 0,
               "slow apps get about fifteen seconds for their first window")

        // MARK: Preferences

        let registered = Defaults.registeredDefaults
        suite.expect(registered[DefaultsKey.autoFullscreenEnabled] as? Bool == false
                && registered[DefaultsKey.autoFullscreenExceptions] as? [String] == []
                && registered[DefaultsKey.autoFullscreenBuiltInDisplayOnly] as? Bool == true
                && registered[DefaultsKey.panelControlAutoFullscreen] as? Bool == true,
               "full screen on launch is opt-in, starts with no exceptions and only on the built-in display")
        let backupKeys = SettingsBackupSupport.exportKeys()
        suite.expect(backupKeys.contains(DefaultsKey.autoFullscreenEnabled)
                && backupKeys.contains(DefaultsKey.autoFullscreenExceptions)
                && backupKeys.contains(DefaultsKey.autoFullscreenBuiltInDisplayOnly)
                && backupKeys.contains(DefaultsKey.panelControlAutoFullscreen),
               "full screen on launch preferences travel with the settings backup")
        suite.expect(!AppFeature.autoFullscreen.installedByDefault
                && AppFeature.autoFullscreen.group == .windowsDock
                && AppFeature.autoFullscreen.permissions == [.accessibility]
                && AppFeature.autoFullscreen.settingsDestination == FeatureSettingsDestination(.autoFullscreen)
                && FeatureVisibilitySupport.features(for: .autoFullscreen) == [.autoFullscreen],
               "full screen on launch waits on the Features page and has its own Settings page")

        // MARK: Strings

        let english = FeatureStrings.autoFullscreen(.enUS)
        for language in AppLanguage.allCases where language != .enUS {
            let text = FeatureStrings.autoFullscreen(language)
            suite.expect(text.name != english.name
                    && text.enableCaption != english.enableCaption
                    && text.builtInDisplayOnlyCaption != english.builtInDisplayOnlyCaption
                    && text.exceptionsCaption != english.exceptionsCaption,
                   "full screen on launch is translated in \(language.rawValue)")
        }
    }
}
