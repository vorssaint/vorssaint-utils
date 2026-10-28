// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Holds the Menu Bar Organizer catalog to the same contract as the other
/// feature string sets: complete, native punctuation, identical format
/// conversions in every language.
enum MenuBarOrganizerStringsTests {
    static func run(_ suite: TestSuite) {
        let english = FeatureStrings.menuBarOrganizer(.enUS)
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.menuBarOrganizer(language)
            let prefix = "menu bar organizer \(language.rawValue)"
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }

            suite.expect(values.count == Mirror(reflecting: strings).children.count
                         && values.allSatisfy { !$0.isEmpty },
                         "\(prefix): every string is filled in")
            suite.expect(values.allSatisfy { !$0.contains("\u{2014}") }, "\(prefix): no em-dash")
            suite.expect(values.allSatisfy { !$0.contains("\"") }, "\(prefix): no straight quotes")
            let angled = language == .fr || language == .ru || language == .uk
            suite.expect(angled || values.allSatisfy { !$0.contains("«") && !$0.contains("»") },
                         "\(prefix): angled quotes only in French, Russian and Ukrainian")
            let lowOpen = language == .de || language == .sk
            suite.expect(lowOpen || values.allSatisfy { !$0.contains("„") },
                         "\(prefix): low opening quote only in German and Slovak")
            suite.expect(!angled && !lowOpen || values.allSatisfy { !$0.contains("“") },
                         "\(prefix): no curly opening quote where the language has its own")
            suite.expect(strings.applying.hasSuffix("…") && !strings.applying.contains("..."),
                         "\(prefix): work in progress ends with the ellipsis character")

            let formats: [(String, [String], String)] = [
                (strings.unsupportedOSFormat, ["@"], "unsupported OS"),
                (strings.otherManagerFormat, ["@"], "other manager"),
                (strings.autoRehideSecondsFormat, ["d"], "auto re-hide seconds"),
                (strings.applyReportFormat, ["d", "d"], "apply report"),
                (strings.problemActivationFormat, ["@"], "activation problem"),
                (strings.problemPeekFailedFormat, ["@"], "peek problem"),
            ]
            for (format, expected, label) in formats {
                let actual = TestFormat.parse(format)?.conversions ?? ["invalid format"]
                suite.expect(actual == expected,
                             "\(prefix) \(label) format: got \(actual), expected \(expected)")
            }
            suite.expect(strings.applyReportFormat.contains("%1$d")
                         && strings.applyReportFormat.contains("%2$d"),
                         "\(prefix): apply report uses positional arguments")

            suite.expect(Set([strings.tierShow, strings.tierHide, strings.tierNever]).count == 3
                         && Set([strings.iconChevron, strings.iconDots, strings.iconLines, strings.iconGrid]).count == 4,
                         "\(prefix): the tiers and the icons each have a name of their own")

            let systemNames = [strings.systemBattery, strings.systemBluetooth, strings.systemClock,
                               strings.systemDisplays, strings.systemKeyboard, strings.systemSound, strings.systemWiFi,
                               strings.systemScreenMirroring, strings.systemControlCenter]
            suite.expect(Set(systemNames).count == systemNames.count,
                         "\(prefix): every system item has a name of its own")
            suite.expect(Set([strings.lockedSystem, strings.lockedPinned, strings.lockedOwn, strings.lockedHelper,
                              strings.lockedUnsigned]).count == 5,
                         "\(prefix): every lock reason and the unsigned note read differently")

            if language != .enUS {
                suite.expect(strings.title != english.title
                             && strings.enableCaption != english.enableCaption,
                             "\(prefix): translated, not a copy of English")
            }
        }
    }
}
