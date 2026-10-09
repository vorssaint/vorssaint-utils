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

enum WindowBulkActionsTests {
    static func run(_ suite: TestSuite) {
        // MARK: - Pure helper

        suite.expect(DockClickSupport.minimizeTargets(excludingFrontmost: false, from: []).isEmpty,
               "no candidates means no minimizes: the nothing-open press is a clean no-op")
        let mixed: [(pid: pid_t, isFrontmost: Bool, hasVisibleWindow: Bool)] = [
            (101, false, true),
            (102, true, true),
            (103, false, false),
            (104, false, true),
        ]
        suite.expect(DockClickSupport.minimizeTargets(excludingFrontmost: false, from: mixed) == [101, 102, 104],
               "windowless apps are skipped and survivors keep input order")
        suite.expect(DockClickSupport.minimizeTargets(excludingFrontmost: true, from: mixed) == [101, 104],
               "excluding the frontmost app leaves the workspace the user is typing in alone")
        suite.expect(DockClickSupport.minimizeTargets(excludingFrontmost: true,
                                                      from: [(201, true, false)]).isEmpty,
               "a frontmost app with nothing visible still minimizes nothing")
        suite.expect(DockClickSupport.minimizeTargets(excludingFrontmost: false,
                                                      from: [(301, false, true), (302, false, true)])
                        == [301, 302],
               "with no frontmost app the workspace order stands")

        // MARK: - Shortcut role wiring

        suite.expect(GlobalShortcutRole.minimizeAllWindows.storageKey == DefaultsKey.minimizeAllWindowsShortcut
                && GlobalShortcutRole.minimizeAllWindows.defaultShortcut == .minimizeAllWindowsDefault
                && GlobalShortcutRole.minimizeAllWindows.requiredEnableKeys
                    == [DefaultsKey.minimizeAllWindowsShortcutEnabled]
                && GlobalShortcutRole.minimizeAllWindows.feature == .windowLayout,
               "the minimize-all shortcut is wired to its own keys and Window Layout")
        // The role resolves itself as the holder of its own default, which
        // proves it participates in the conflict candidate list: with every
        // gate on, only a wired requiredEnableKeys + feature pair keeps it
        // in `activeRoles`. An unrelated exclusion stands in for the other
        // role holding the same combination, which the recorder surfaces
        // instead of silently dropping.
        suite.expect(GlobalShortcutRole.conflict(for: .minimizeAllWindowsDefault,
                                                excluding: .micMute,
                                                isOn: { _ in true },
                                                isAvailable: { _ in true }) == .minimizeAllWindows,
               "the same shortcut on minimize-all and another role surfaces a conflict")
        suite.expect(GlobalShortcutRole.conflict(for: .minimizeAllWindowsDefault,
                                                excluding: .minimizeAllWindows,
                                                isOn: { _ in true },
                                                isAvailable: { _ in true }) == nil,
               "no other role holds the minimize-all default, so editing it reports no conflict")
        suite.expect(GlobalShortcut.minimizeAllWindowsDefault
                == GlobalShortcut(keyCode: Int64(kVK_ANSI_O), modifiers: [.control, .option, .command]),
               "the minimize-all default stays on its documented combination")
        // O sits free of every other ⌃⌥⌘ default, which a saved-shortcut
        // lookup cannot prove: it only sees a clash once both roles are
        // saved — so it is asserted against the other defaults directly.
        suite.expect(!GlobalShortcutRole.allCases.contains { $0 != .minimizeAllWindows
                    && $0.defaultShortcut == GlobalShortcut.minimizeAllWindowsDefault },
               "no other role ships the minimize-all default, so the combination is unambiguous")

        // MARK: - Locale coverage

        for language in AppLanguage.allCases {
            suite.expect(!FeatureStrings.windowLayout(language).minimizeAllWindows.isEmpty,
                         "\(language.rawValue) names the minimize-all action")
        }
        suite.expect(FeatureStrings.windowLayout(.enUS).minimizeAllWindows == "Minimize all windows",
               "the English minimize-all label reads as the action it performs")

        // MARK: - Registered defaults

        suite.expect(Defaults.registeredDefaults[DefaultsKey.minimizeAllWindowsShortcutEnabled] as? Bool == false,
               "minimize-all ships opt-in like every other shortcut toggle")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.minimizeAllWindowsShortcut] as? String
                        == GlobalShortcut.minimizeAllWindowsDefault.storageValue,
               "the registered minimize-all combination is its default")

        // MARK: - Unminimize-all role

        suite.expect(GlobalShortcutRole.unminimizeAllWindows.storageKey
                == DefaultsKey.unminimizeAllWindowsShortcut
                && GlobalShortcutRole.unminimizeAllWindows.defaultShortcut == .unminimizeAllWindowsDefault
                && GlobalShortcutRole.unminimizeAllWindows.requiredEnableKeys
                    == [DefaultsKey.unminimizeAllWindowsShortcutEnabled]
                && GlobalShortcutRole.unminimizeAllWindows.feature == .windowLayout,
               "the unminimize-all shortcut is wired to its own keys and Window Layout")
        suite.expect(GlobalShortcutRole.conflict(for: .unminimizeAllWindowsDefault,
                                                excluding: .micMute,
                                                isOn: { _ in true },
                                                isAvailable: { _ in true }) == .unminimizeAllWindows,
               "the same shortcut on unminimize-all and another role surfaces a conflict")
        suite.expect(GlobalShortcutRole.conflict(for: .unminimizeAllWindowsDefault,
                                                excluding: .unminimizeAllWindows,
                                                isOn: { _ in true },
                                                isAvailable: { _ in true }) == nil,
               "no other role holds the unminimize-all default, so editing it reports no conflict")
        suite.expect(GlobalShortcut.unminimizeAllWindowsDefault
                == GlobalShortcut(keyCode: Int64(kVK_ANSI_R), modifiers: [.control, .option, .command]),
               "the unminimize-all default stays on its documented combination")
        // R also carries Window Layout's restore action, but on ⌃⌥ — a
        // different combination, so the role default stays unambiguous.
        suite.expect(!GlobalShortcutRole.allCases.contains { $0 != .unminimizeAllWindows
                    && $0.defaultShortcut == GlobalShortcut.unminimizeAllWindowsDefault },
               "no other role ships the unminimize-all default, so the combination is unambiguous")
        for language in AppLanguage.allCases {
            suite.expect(!FeatureStrings.windowLayout(language).unminimizeAllWindows.isEmpty,
                         "\(language.rawValue) names the unminimize-all action")
        }
        suite.expect(FeatureStrings.windowLayout(.enUS).unminimizeAllWindows == "Unminimize all windows",
               "the English unminimize-all label reads as the action it performs")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.unminimizeAllWindowsShortcutEnabled] as? Bool == false,
               "unminimize-all ships opt-in like every other shortcut toggle")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.unminimizeAllWindowsShortcut] as? String
                        == GlobalShortcut.unminimizeAllWindowsDefault.storageValue,
               "the registered unminimize-all combination is its default")
    }
}
