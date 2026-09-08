// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum QuitProtectionTests {
    static func run(expect: (Bool, String) -> Void) {
        func expectFormat(_ format: String, _ expected: [String], _ label: String) {
            let actual = formatSpecifiers(in: format)
            expect(actual == expected, "\(label): got \(actual), expected \(expected)")
        }

        // MARK: Command-Q / Command-W protection
        expect(QuitProtectionSupport.sanitizedHoldDuration(100) == 250,
               "quit protection clamps a too-short hold duration")
        expect(QuitProtectionSupport.sanitizedHoldDuration(3_000) == 2_000,
               "quit protection clamps an overly long hold duration")
        expect(QuitProtectionSupport.sanitizedHoldDuration(.nan)
                == QuitProtectionSupport.defaultHoldDurationMilliseconds
                && QuitProtectionSupport.sanitizedHoldDuration(.infinity)
                    == QuitProtectionSupport.defaultHoldDurationMilliseconds,
               "quit protection replaces non-finite hold durations with its default")
        expect(QuitProtectionSupport.sanitizedDoublePressInterval(100) == 200,
               "quit protection clamps a too-short double-press interval")
        expect(QuitProtectionSupport.sanitizedDoublePressInterval(3_000) == 1_500,
               "quit protection clamps an overly long double-press interval")
        expect(QuitProtectionSupport.sanitizedDoublePressInterval(.nan)
                == QuitProtectionSupport.defaultDoublePressIntervalMilliseconds
                && QuitProtectionSupport.sanitizedDoublePressInterval(-.infinity)
                    == QuitProtectionSupport.defaultDoublePressIntervalMilliseconds,
               "quit protection replaces non-finite double-press intervals with its default")
        expect(!SettingsBackupSupport.valueLooksRight(
                    DefaultsKey.quitProtectionQuitDoubleIntervalMs, Double.nan)
                && !SettingsBackupSupport.valueLooksRight(
                    DefaultsKey.quitProtectionQuitDoubleIntervalMs, Double.infinity),
               "settings backups reject non-finite numeric preferences")
        expect(QuitProtectionSupport.isWithinDoublePressInterval(
            firstTimestamp: 1_000_000_000,
            secondTimestamp: 2_500_000_000,
            intervalMilliseconds: 1_500
        ), "a second press on the interval edge confirms")
        expect(!QuitProtectionSupport.isWithinDoublePressInterval(
            firstTimestamp: 1_000_000_000,
            secondTimestamp: 2_500_000_001,
            intervalMilliseconds: 1_500
        ), "a second press after the interval starts a new confirmation")
        expect(QuitProtectionSupport.usesNativeQuitRequest(for: .quit)
                && !QuitProtectionSupport.usesNativeQuitRequest(for: .close),
               "quit confirmation asks the target app to terminate while close stays a window shortcut")

        expect(QuitProtectionSupport.scopeAllows(.all, bundleIdentifier: nil, exceptions: []),
               "all-app scope protects even an app without a bundle identifier")
        expect(QuitProtectionSupport.scopeAllows(.selectedOnly,
                                                 bundleIdentifier: "com.example.editor",
                                                 exceptions: ["com.example.editor"]),
               "selected-only scope protects a selected bundle")
        expect(!QuitProtectionSupport.scopeAllows(.selectedOnly,
                                                  bundleIdentifier: "com.example.other",
                                                  exceptions: ["com.example.editor"]),
               "selected-only scope leaves an unselected bundle alone")
        expect(!QuitProtectionSupport.scopeAllows(.allExceptSelected,
                                                  bundleIdentifier: "com.example.editor",
                                                  exceptions: ["com.example.editor"]),
               "all-except scope leaves a selected bundle alone")
        expect(QuitProtectionSupport.scopeAllows(.allExceptSelected,
                                                 bundleIdentifier: "com.example.other",
                                                 exceptions: ["com.example.editor"]),
               "all-except scope protects an unselected bundle")

        expect(QuitProtectionSupport.matchesKey(keyCharacter: "\u{439}", keyCode: 12,
                                                commandLabel: "Q", shortcut: .quit),
               "a Cyrillic layout is protected on the key Command-Q quits from, "
               + "which types \u{439} rather than q")
        expect(!QuitProtectionSupport.matchesKey(keyCharacter: "'", keyCode: 12,
                                                 commandLabel: "'", shortcut: .quit),
               "a Dvorak layout leaves the key Command-Q does not quit from alone")
        expect(QuitProtectionSupport.matchesKey(keyCharacter: "q", keyCode: 0,
                                                commandLabel: nil, shortcut: .quit),
               "quit protection falls back to the typed character without a layout")
        expect(QuitProtectionSupport.matchesKey(keyCharacter: nil, keyCode: 13,
                                                commandLabel: nil, shortcut: .close),
               "quit protection falls back to the W key code with neither a character nor a layout")
        expect(QuitProtectionSupport.isBaseShortcut(keyCharacter: "q", keyCode: 12,
                                                    commandLabel: "Q",
                                                    command: true, control: false,
                                                    option: false, shift: false, shortcut: .quit),
               "plain Command-Q is recognized")
        expect(!QuitProtectionSupport.isBaseShortcut(keyCharacter: "q", keyCode: 12,
                                                     commandLabel: "Q",
                                                     command: true, control: false,
                                                     option: false, shift: true, shortcut: .quit),
               "Shift-Command-Q is not mistaken for plain Command-Q")
        expect(QuitProtectionSupport.isExtraShortcut(keyCharacter: "q", keyCode: 12,
                                                     commandLabel: "Q",
                                                     command: true, control: false,
                                                     option: false, shift: true,
                                                     shortcut: .quit, extraModifier: .shift),
               "Shift-Command-Q is recognized as an extra-modifier confirmation")
        expect(QuitProtectionSupport.isExtraShortcut(keyCharacter: "w", keyCode: 13,
                                                     commandLabel: "W",
                                                     command: true, control: true,
                                                     option: false, shift: false,
                                                     shortcut: .close, extraModifier: .control),
               "Control-Command-W is recognized as an extra-modifier confirmation")
        expect(!QuitProtectionSupport.isExtraShortcut(keyCharacter: "q", keyCode: 12,
                                                      commandLabel: "Q",
                                                      command: true, control: false,
                                                      option: true, shift: false,
                                                      shortcut: .quit, extraModifier: .shift),
               "an unrelated modifier combination is not protected")

        // Feeds the matcher what the tap sees for a key on an installed layout:
        // the bare character the event carries and the Command-table label.
        func layoutProtects(_ layoutID: String, _ keyCode: Int64,
                            _ shortcut: QuitProtectionShortcut) -> Bool? {
            guard let data = testLayoutData(for: layoutID) else { return nil }
            GlobalShortcut.refreshLayoutLabels(layoutData: data)
            return QuitProtectionSupport.matchesKey(
                keyCharacter: GlobalShortcut.layoutKeyLabel(for: keyCode, usesCommand: false),
                keyCode: keyCode,
                commandLabel: GlobalShortcut.layoutKeyLabel(for: keyCode, usesCommand: true),
                shortcut: shortcut)
        }
        let usID = "com.apple.keylayout.US"
        if let quit = layoutProtects(usID, 12, .quit), let close = layoutProtects(usID, 13, .close) {
            expect(quit && close, "US layout keeps Command-Q and Command-W on their own keys")
        }
        let russianID = "com.apple.keylayout.Russian"
        if let quit = layoutProtects(russianID, 12, .quit),
           let close = layoutProtects(russianID, 13, .close) {
            expect(quit && close,
                   "a Cyrillic layout still quits and closes from the Latin Q and W keys")
        }
        let greekID = "com.apple.keylayout.Greek"
        if let quit = layoutProtects(greekID, 12, .quit), let close = layoutProtects(greekID, 13, .close) {
            expect(quit && close, "a Greek layout still quits and closes from the Latin Q and W keys")
        }
        let dvorakID = "com.apple.keylayout.Dvorak"
        if let quit = layoutProtects(dvorakID, 7, .quit), let close = layoutProtects(dvorakID, 43, .close),
           let quote = layoutProtects(dvorakID, 12, .quit) {
            expect(quit && close && !quote,
                   "Dvorak moves Command-Q and Command-W to the keys it types q and w on, "
                   + "and leaves the key that types ' alone")
        }
        let dvorakCommandID = "com.apple.keylayout.DVORAK-QWERTYCMD"
        if let quit = layoutProtects(dvorakCommandID, 12, .quit),
           let close = layoutProtects(dvorakCommandID, 13, .close) {
            expect(quit && close, "the Dvorak layout that reverts to QWERTY under Command is followed there")
        }
        let frenchID = "com.apple.keylayout.French"
        if let quit = layoutProtects(frenchID, 0, .quit), let close = layoutProtects(frenchID, 6, .close) {
            expect(quit && close, "French AZERTY moves Command-Q and Command-W to its own q and w keys")
        }
        GlobalShortcut.refreshLayoutLabels()

        let quitProtectionKeys = [
            DefaultsKey.quitProtectionQuitEnabled,
            DefaultsKey.quitProtectionQuitMode,
            DefaultsKey.quitProtectionQuitHoldDurationMs,
            DefaultsKey.quitProtectionQuitDoubleIntervalMs,
            DefaultsKey.quitProtectionQuitExtraModifier,
            DefaultsKey.quitProtectionQuitScope,
            DefaultsKey.quitProtectionQuitExceptions,
            DefaultsKey.quitProtectionQuitShowFeedback,
            DefaultsKey.quitProtectionCloseEnabled,
            DefaultsKey.quitProtectionCloseMode,
            DefaultsKey.quitProtectionCloseHoldDurationMs,
            DefaultsKey.quitProtectionCloseDoubleIntervalMs,
            DefaultsKey.quitProtectionCloseExtraModifier,
            DefaultsKey.quitProtectionCloseScope,
            DefaultsKey.quitProtectionCloseExceptions,
            DefaultsKey.quitProtectionCloseShowFeedback,
        ]
        expect(quitProtectionKeys.allSatisfy { Defaults.registeredDefaults[$0] != nil },
               "quit and close protection settings have registered defaults")
        expect(SettingsBackupSupport.exportKeys().isSuperset(of: Set<String>(quitProtectionKeys)),
               "quit and close protection settings are included in portable backup")

        for language in AppLanguage.allCases {
            let quitProtection = FeatureStrings.quitProtection(language)
            let quitProtectionValues = Mirror(reflecting: quitProtection).children
                .compactMap { $0.value as? String }
            expect(quitProtectionValues.count == 29 && quitProtectionValues.allSatisfy { !$0.isEmpty },
                   "every quit protection string is set for \(language.rawValue)")
            expect(quitProtectionValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in quit protection strings (\(language.rawValue))")
            expectFormat(quitProtection.holdHUDFormat, ["@"],
                         "\(language.rawValue) quit protection hold HUD format")
            expectFormat(quitProtection.doubleHUDFormat, ["@"],
                         "\(language.rawValue) quit protection double HUD format")
            expectFormat(quitProtection.extraHUDFormat, ["@"],
                         "\(language.rawValue) quit protection modifier HUD format")
        }
    }

    static func runHUD(expect: (Bool, String) -> Void) {
        // The confirmation HUD is a hand-laid AppKit panel, so its width is
        // pinned as source shape. It used to be a fixed 300pt, which clipped
        // the longer translations. Sizing it from a separate
        // NSString measurement of the same text would leave whatever inset
        // the label's cell adds unaccounted for -- the labels have to be the
        // ones asked.
        let quitHUDSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/QuitProtection/QuitProtectionHUD.swift",
            encoding: .utf8)) ?? ""
        expect(quitHUDSource.count > 1_000,
               "the quit protection HUD source is readable (\(quitHUDSource.count) bytes)")
        let quitHUDCode = quitHUDSource
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(quitHUDCode.contains("title.fittingSize.width")
                && quitHUDCode.contains("detail.fittingSize.width"),
               "the confirmation HUD takes its width from the labels that draw the text")
        expect(!quitHUDCode.contains("size(withAttributes:"),
               "the confirmation HUD does not size itself from a separate text measurement")
        let quitHUDShow = quitHUDCode
            .components(separatedBy: "func show(title: String, detail: String").last ?? ""
        let quitHUDShowBody = quitHUDShow.components(separatedBy: "\n    func ").first ?? ""
        if let filled = quitHUDShowBody.range(of: "content.update("),
           let sized = quitHUDShowBody.range(of: "fittingSize(content)"),
           let applied = quitHUDShowBody.range(of: "setContentSize(size)") {
            expect(filled.lowerBound < sized.lowerBound && sized.lowerBound < applied.lowerBound,
                   "the confirmation HUD fills its labels, then measures them, then resizes")
        } else {
            expect(false,
                   "the confirmation HUD's show() fills the labels, measures them and resizes")
        }
    }
}
