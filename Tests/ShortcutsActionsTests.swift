// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ShortcutsActionsTests {
    static func run(_ suite: TestSuite) {
        typealias Support = ShortcutsActionsSupport

        suite.expect(Support.refusal(actionsEnabled: false, featureInstalled: true) == .disabled,
                     "an action stays refused until the person allows Shortcuts to run them")
        suite.expect(Support.refusal(actionsEnabled: false, featureInstalled: false) == .disabled,
                     "the switch is the first thing an action reports, installed or not")
        suite.expect(Support.refusal(actionsEnabled: true, featureInstalled: false) == .featureNotInstalled,
                     "an allowed action still refuses for a feature that is uninstalled")
        suite.expect(Support.refusal(actionsEnabled: true, featureInstalled: true) == nil,
                     "an allowed action of an installed feature runs")

        for current in [false, true] {
            suite.expect(Support.switchValue(.on, current: current),
                         "On leaves the switch on whatever it was (was \(current))")
            suite.expect(!Support.switchValue(.off, current: current),
                         "Off leaves the switch off whatever it was (was \(current))")
            suite.expect(Support.switchValue(.toggle, current: current) == !current,
                         "Toggle flips the switch (was \(current))")
        }
        suite.expect(Support.offersPowerSwitch(enabledKeyCount: 1),
                     "a feature with one switch can be turned on and off")
        suite.expect(!Support.offersPowerSwitch(enabledKeyCount: 0),
                     "a feature that works on demand has nothing to turn on")
        suite.expect(!Support.offersPowerSwitch(enabledKeyCount: 2),
                     "a feature with two switches leaves 'on' ambiguous")

        suite.expect(Support.timerMinutes(1) == 1 && Support.timerMinutes(180) == 180,
                     "the ends of the timer range are accepted")
        suite.expect(Support.timerMinutes(0) == nil && Support.timerMinutes(181) == nil,
                     "a timer outside the ruler's range is refused, not bent into it")
        suite.expect(Support.appVolume(percent: 50) == 0.5, "50 percent is half of the app's level")
        suite.expect(Support.appVolume(percent: 0) == 0 && Support.appVolume(percent: 100) == 1,
                     "the ends of the slider are silence and the app's own level")
        suite.expect(Support.appVolume(percent: 250) == 1 && Support.appVolume(percent: -3) == 0,
                     "a value past the slider is held to its ends")

        suite.expect(!Support.quickToggleIDs.isEmpty, "Shortcuts is offered some quick toggles")
        suite.expect(!Support.quickToggleIDs.contains("emptyTrash"),
                     "emptying the Trash is never offered without a confirmation")
        suite.expect(!Support.quickToggleIDs.contains("ejectDisks"),
                     "ejecting disks is never offered to an automation")
        suite.expect(Set(Support.quickToggleIDs).count == Support.quickToggleIDs.count,
                     "each quick toggle is offered once")

        for minutes in Defaults.allowedDurations {
            suite.expect(Support.keepAwakeMinutes(minutes) == minutes,
                         "the panel's own duration of \(minutes) minutes is accepted as it is")
        }
        suite.expect(Support.keepAwakeMinutes(0) == 0, "zero stays until stopped")
        suite.expect(Support.keepAwakeMinutes(7) == nil,
                     "a duration the panel does not offer is refused, not turned into until stopped")
        suite.expect(Support.keepAwakeMinutes(-5) == nil, "a negative duration is refused")
        suite.expect(Support.keepAwakeMinutes(100_000) == nil, "an enormous duration is refused")
        localizationContract(suite)
    }

    /// The names Shortcuts shows are keyed by the English text in the source, so
    /// a literal added there without a line in every language would quietly
    /// show English to everyone else.
    private static func localizationContract(_ suite: TestSuite) {
        guard let source = try? String(
            contentsOfFile: "Sources/Vorssaint/Services/AppIntents/VorssaintIntents.swift", encoding: .utf8)
        else {
            suite.expect(false, "the intents source is readable from the repository root")
            return
        }
        func literals(_ pattern: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            let range = NSRange(source.startIndex..., in: source)
            return regex.matches(in: source, range: range).compactMap { match in
                Range(match.range(at: 1), in: source).map { String(source[$0]) }
            }
        }
        var keys = Set<String>()
        for pattern in [#"static let title: LocalizedStringResource = "([^"]+)""#,
                        #"IntentDescription\(\s*"([^"]+)"\s*\)"#,
                        #"@Parameter\(title: "([^"]+)""#,
                        #"TypeDisplayRepresentation\(name: "([^"]+)"\)"#,
                        #"\.[a-zA-Z0-9]+: "([^"]+)"\s*[,\]]"#] {
            keys.formUnion(literals(pattern))
        }
        // A summary writes its parameters as key paths; the catalog key spells
        // them ${name}.
        for summary in literals(#"Summary\("([^"]+)""#) {
            let key = summary.replacingOccurrences(
                of: #"\\\(\\\.\$([A-Za-z]+)\)"#, with: "${$1}", options: .regularExpression)
            keys.insert(key)
        }
        suite.expect(keys.count >= 40, "the contract found the literals in the intents source: \(keys.count)")

        let languages = ["de", "es", "fr", "it", "ja", "ko", "pt-BR", "ru", "sk", "tr", "uk",
                         "zh-HK", "zh-Hans", "zh-TW"]
        for language in languages {
            let path = "Resources/\(language).lproj/Localizable.strings"
            guard let table = NSDictionary(contentsOfFile: path) as? [String: String] else {
                suite.expect(false, "\(path) is a readable strings file")
                continue
            }
            let missing = keys.filter { table[$0]?.isEmpty != false }.sorted()
            suite.expect(missing.isEmpty, "\(language) has every action text: missing \(missing.prefix(3))")
            let stale = Set(table.keys).subtracting(keys).sorted()
            suite.expect(stale.isEmpty, "\(language) has no text the source no longer uses: \(stale.prefix(3))")
        }
    }
}
