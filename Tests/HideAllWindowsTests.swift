// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import VMStatisticsCompat

enum HideAllWindowsTests {
    static func run(_ suite: TestSuite) {
        // MARK: - Pure helper

        suite.expect(DockClickSupport.pidsToHide(from: []).isEmpty,
               "no candidates means no hides: the nothing-open press is a clean no-op")
        let mixed: [(pid: pid_t, isActive: Bool, hasVisibleWindow: Bool)] = [
            (101, false, true),
            (102, true, true),
            (103, false, false),
            (104, false, true),
        ]
        suite.expect(DockClickSupport.pidsToHide(from: mixed) == [102, 101, 104],
               "windowless apps are skipped, the active app hides first, the rest keep input order")
        suite.expect(DockClickSupport.pidsToHide(from: [(201, false, false)]).isEmpty,
               "an app with nothing visible contributes no hide target")
        suite.expect(DockClickSupport.pidsToHide(from: [(301, false, true), (302, false, true)]) == [301, 302],
               "with no active app the workspace order stands")
        suite.expect(DockClickSupport.pidsToHide(from: [(401, false, true), (402, true, true), (403, false, true)])
                == [402, 401, 403],
               "the active app jumps the queue even from the middle of the list")

        // MARK: - Shortcut role wiring

        suite.expect(GlobalShortcutRole.hideAllWindows.storageKey == DefaultsKey.hideAllWindowsShortcut
                && GlobalShortcutRole.hideAllWindows.defaultShortcut == .hideAllWindowsDefault
                && GlobalShortcutRole.hideAllWindows.requiredEnableKeys == [DefaultsKey.hideAllWindowsShortcutEnabled]
                && GlobalShortcutRole.hideAllWindows.feature == .windowLayout,
               "the hide-all shortcut is wired to its own keys and Window Layout")
        // The role resolves itself as the holder of its own default, which
        // proves it participates in the conflict candidate list: with every
        // gate on, only a wired requiredEnableKeys + feature pair keeps it
        // in `activeRoles`. An unrelated exclusion stands in for the other
        // role holding the same combination, which the recorder surfaces
        // instead of silently dropping.
        suite.expect(GlobalShortcutRole.conflict(for: .hideAllWindowsDefault,
                                                excluding: .micMute,
                                                isOn: { _ in true },
                                                isAvailable: { _ in true }) == .hideAllWindows,
               "the same shortcut on hide-all and another role surfaces a conflict")
        suite.expect(GlobalShortcutRole.conflict(for: .hideAllWindowsDefault,
                                                excluding: .hideAllWindows,
                                                isOn: { _ in true },
                                                isAvailable: { _ in true }) == nil,
               "no other role holds the hide-all default, so editing it reports no conflict")
        suite.expect(GlobalShortcut.hideAllWindowsDefault
                == GlobalShortcut(keyCode: Int64(kVK_ANSI_A), modifiers: [.control, .option, .command]),
               "the hide-all default stays on its documented combination")
        // H is the obvious mnemonic for hide and it is already spoken for by
        // recent captures. A default that collides with another role's is the
        // one mistake here that still builds and still passes every test
        // above, because the conflict lookup only sees it once both roles are
        // saved — so it is asserted against the other defaults directly.
        suite.expect(!GlobalShortcutRole.allCases.contains { $0 != .hideAllWindows
                    && $0.defaultShortcut == GlobalShortcut.hideAllWindowsDefault },
               "no other role ships the hide-all default, so the combination is unambiguous")

        // MARK: - Locale coverage

        for language in AppLanguage.allCases {
            suite.expect(!FeatureStrings.windowLayout(language).hideAllWindows.isEmpty,
                         "\(language.rawValue) names the hide-all action")
        }
        suite.expect(FeatureStrings.windowLayout(.enUS).hideAllWindows == "Hide all windows",
               "the English hide-all label reads as the action it performs")

        // MARK: - Registered defaults

        suite.expect(Defaults.registeredDefaults[DefaultsKey.hideAllWindowsShortcutEnabled] as? Bool == false,
               "hide-all ships opt-in like every other shortcut toggle")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.hideAllWindowsShortcut] as? String
                        == GlobalShortcut.hideAllWindowsDefault.storageValue,
               "the registered hide-all combination is its default")
    }
}
