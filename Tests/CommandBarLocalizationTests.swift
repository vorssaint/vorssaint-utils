// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CommandBarLocalizationTests {
    static func run(expect: (Bool, String) -> Void) {
        // A translated format string whose placeholders drifted from the
        // English one does not misprint: String(format:) reads the argument
        // list by the specifiers, so a "%@" where a "%d" belongs walks off the
        // stack and takes the app with it. This is the one translation mistake
        // that is a crash rather than a typo, so it is pinned here.
        func specifiers(of format: String) -> [String] {
            var found: [String] = []
            let characters = Array(format)
            var index = 0
            while index < characters.count {
                guard characters[index] == "%" else {
                    index += 1
                    continue
                }
                var cursor = index + 1
                // Positional and width flags sit between the % and the letter.
                while cursor < characters.count,
                      "0123456789$.-+ #'lhqLzjt".contains(characters[cursor]) {
                    cursor += 1
                }
                guard cursor < characters.count else { break }
                found.append(String(characters[index...cursor]))
                index = cursor + 1
            }
            return found
        }
        var englishFormats: [String: [String]] = [:]
        for language in AppLanguage.allCases {
            for child in Mirror(reflecting: FeatureStrings.commandBar(language)).children {
                guard let label = child.label, let value = child.value as? String else { continue }
                let found = specifiers(of: value)
                if language == .enUS {
                    englishFormats[label] = found
                } else {
                    expect(englishFormats[label] == found,
                           "\(label) takes the same arguments in \(language.rawValue) as in en-US")
                }
            }
        }

        for language in AppLanguage.allCases {
            let commandBarValues = Mirror(reflecting: FeatureStrings.commandBar(language)).children
                .compactMap { $0.value as? String }
            expect(commandBarValues.count == 158 && commandBarValues.allSatisfy { !$0.isEmpty },
                   "every command bar string is set for \(language.rawValue)")
            expect(commandBarValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible command bar strings (\(language.rawValue))")
            // The battery example chip types this word into the bar, and the
            // answer it must reach is titled with it. Two words would not be
            // one typable example, and an empty one would be no example.
            let batteryExample = FeatureStrings.commandBar(language).answerBatteryLabel
            expect(!batteryExample.isEmpty && !batteryExample.contains(" "),
                   "the battery answer is one typable word in \(language.rawValue)")
        }

        // A count in front of a noun makes the noun agree with it in these
        // languages, and one string cannot hold every form. Where the sentence
        // allows it, the count goes last behind a label, which is right at any
        // number and is how the app already words several other counts. The
        // ones left out need no agreement: Turkish keeps the noun singular
        // after a number, and Chinese, Japanese and Korean do not inflect.
        let agreeingLanguages: [AppLanguage] = [.enUS, .ptBR, .ru, .es, .de, .fr, .it]
        for language in agreeingLanguages {
            let selection = FeatureStrings.commandBar(language).selectionCountFormat
            expect(!selection.hasPrefix("%d"),
                   "the selection count does not put a bare number in front of a noun in \(language.rawValue)")
            let processes = FeatureStrings.killProcess(language).processCountFormat
            expect(!processes.hasPrefix("%d"),
                   "the process count does not put a bare number in front of a noun in \(language.rawValue)")
        }

        // A plain sort orders by Unicode scalar, which throws every accented
        // name past Z. Lists of names people read are sorted by the rules of
        // the language instead, and the onboarding one is on the first screen
        // anyone sees.
        let accented = ["Zebra", "Ímã", "Área"]
        expect(accented.sorted() == ["Zebra", "Área", "Ímã"],
               "a plain sort really does put accented names after Z")
        expect(accented.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                == ["Área", "Ímã", "Zebra"],
               "the localized compare is what puts them where a reader expects")
        let onboardingSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Onboarding/OnboardingView.swift",
            encoding: .utf8)) ?? ""
        expect(!onboardingSource.isEmpty, "the onboarding source reads back for its sorting check")
        let onboardingCode = onboardingSource.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(!onboardingCode.contains(".sorted()\n"),
               "onboarding sorts the names it shows by the rules of the language")

        // Case folding that inherits the Mac's locale answers differently for
        // a Turkish user: there the dotted I folds to a dotless one, so a
        // search for "istanbul" stops finding "ISTANBUL". The app ships
        // Turkish, so every search normalizer folds with no locale at all.
        let dottedI = "ISTANBUL"
        let foldOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        expect(dottedI.folding(options: foldOptions, locale: Locale(identifier: "tr_TR"))
                != dottedI.folding(options: foldOptions, locale: nil),
               "the dotted I is exactly where locale-aware folding diverges")
        for path in ["Sources/Vorssaint/Services/Clipboard/ClipboardHistorySupport.swift",
                     "Sources/Vorssaint/UI/Settings/SettingsSearchSupport.swift",
                     "Sources/Vorssaint/Services/Switcher/SwitcherSupport.swift",
                     "Sources/Vorssaint/Services/CommandBar/CommandBarSupport.swift"] {
            let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            expect(!source.isEmpty, "\(path) reads back for its folding check")
            let code = source.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            expect(!code.contains("locale: .current"),
                   "search folding in \(path) does not follow the Mac's locale")
        }
        expect(ClipboardHistorySearch.matches("ISTANBUL kahvesi", query: "istanbul"),
               "clipboard search folds case whatever the Mac's locale is")
        expect(ClipboardHistorySearch.matches("café da manhã", query: "cafe"),
               "clipboard search folds accents so a plain query still finds them")

        // An example chip is a promise that typing it does something. The
        // battery answer is titled with a localized string, so a fixed English
        // "battery" matched nothing outside English and the chip led to an
        // empty list, which teaches the opposite of what an example is for.
        let commandBarViewSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/CommandBar/CommandBarView.swift",
            encoding: .utf8)) ?? ""
        expect(!commandBarViewSource.isEmpty, "the command bar view source reads back for its shape check")
        // Comments are stripped so prose naming the old literal cannot fail
        // for code that no longer uses it.
        let commandBarViewCode = commandBarViewSource.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(!commandBarViewCode.contains("\"battery\""),
               "the command bar's battery example is the localized word, not a fixed English one")

        // A key glyph in front of a button label reads as that button's
        // shortcut, so neither command bar action button carries one.
        let commandBarSettingsSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/CommandBarSettings.swift",
            encoding: .utf8)) ?? ""
        expect(!commandBarSettingsSource.contains("Label(text.openButton, systemImage:")
                && !commandBarSettingsSource.contains("Label(text.resetPositionButton, systemImage:"),
               "neither command bar action button wears an icon")
        expect(commandBarSettingsSource.contains("Toggle(text.shortcutToggle,")
                && !commandBarSettingsSource.contains("l10n.s.quickToolShortcutToggle"),
               "the command bar shortcut toggle says what the shortcut opens")
        for language in AppLanguage.allCases {
            let recordingShareValues = Mirror(
                reflecting: FeatureStrings.recorderShare(language)).children
                .compactMap { $0.value as? String }
            expect(recordingShareValues.count == 9
                    && recordingShareValues.allSatisfy { !$0.isEmpty },
                   "every recording share string is set for \(language.rawValue)")
            expect(recordingShareValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in recording share strings (\(language.rawValue))")
        }
        expect(Set(GlobalShortcutRole.allCases.map(\.defaultShortcut)).count
                == GlobalShortcutRole.allCases.count,
               "no two shortcut roles share a default combination")

        // A heavy, rare verb stays out of the list until it is asked for, in
        // every language the app speaks.
        for language in AppLanguage.allCases {
            let format = FeatureStrings.commandBar(language).quitFormat
            let verb = format.replacingOccurrences(of: "%@", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            expect(CommandBarSearch.matchesVerb(verb, in: format),
                   "the quit verb finds its own rows in \(language.rawValue)")
        }
        expect(CommandBarSearch.matchesVerb("quit saf", in: "Quit %@")
                && CommandBarSearch.matchesVerb("encerrar", in: "Encerrar %@")
                && CommandBarSearch.matchesVerb("終了", in: "%@を終了"),
               "the verb is recognized with the name typed after it, and without spaces too")
        expect(!CommandBarSearch.matchesVerb("safari", in: "Quit %@")
                && !CommandBarSearch.matchesVerb("", in: "Quit %@"),
               "an app name alone never drags the quit rows in")
        expect(InstalledApps.isSystemApplication(
                    at: URL(fileURLWithPath: "/System/Applications/SystemUtility.app"))
                && InstalledApps.isSystemApplication(
                    at: URL(fileURLWithPath: "/Library/Apple/SystemUtility.app"))
                && !InstalledApps.isSystemApplication(
                    at: URL(fileURLWithPath: "/Applications/UserUtility.app")),
               "app controls never offer system apps to the uninstaller")
    }
}
