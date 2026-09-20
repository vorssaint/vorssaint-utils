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

enum CommandBarFeatureTests {
    static func run(_ suite: TestSuite) {
        let isCodeLine: (String) -> Bool = {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        }
        let commandBarCatalogLines = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift",
            encoding: .utf8)) ?? "").components(separatedBy: "\n")
        func pageVisible(_ page: SettingsPage, available: Set<AppFeature>) -> Bool {
            FeatureVisibilitySupport.isPageVisible(page) { available.contains($0) }
        }
        // MARK: Command bar calculator

        func math(_ input: String, decimal: String = ".", grouping: String = ",") -> String? {
            CommandBarMath.evaluate(input,
                                    decimalSeparator: decimal,
                                    groupingSeparator: grouping,
                                    locale: Locale(identifier: "en_US"))?.formatted
        }
        func mathValue(_ input: String, decimal: String = ".", grouping: String = ",") -> Double? {
            CommandBarMath.evaluate(input,
                                    decimalSeparator: decimal,
                                    groupingSeparator: grouping,
                                    locale: Locale(identifier: "en_US"))?.value
        }

        suite.expect(math("2+2") == "4", "the calculator answers a sum")
        suite.expect(math("10 * 4.5") == "45", "spaces and decimals are fine")
        suite.expect(math("(2+3)*4") == "20", "parentheses come first")
        suite.expect(math("2+3*4") == "14", "multiplication binds tighter than addition")
        suite.expect(math("10/4") == "2.5", "division keeps its decimals")
        suite.expect(math("2^3^2") == "512", "powers group to the right")
        suite.expect(math("-5+2") == "-3", "a leading minus is a sign, not an error")
        suite.expect(math("--5+1") == "6", "two minuses cancel")
        suite.expect(math("1920/2") == "960", "the everyday case works")
        suite.expect(mathValue("0.1+0.2") == 0.3 && math("0.1+0.2") == "0.3",
               "floating point noise never reaches the eye")
        suite.expect(math("1,000+1") == "1,001", "grouped thousands parse and print grouped")
        suite.expect(math("2 x 3") == "6" && math("10 ÷ 2") == "5" && math("2 × 3") == "6",
               "the written multiplication and division signs work too")
        suite.expect(math("2(3+4)") == "14" && math("(1+2)(3+4)") == "21",
               "a number against a parenthesis multiplies")
        suite.expect(math("-2^2") == "-4", "a sign applies to the whole power, as on paper")
        suite.expect(math("2^0.5")?.hasPrefix("1.41421") == true, "a fractional power is fine")
        suite.expect(math("1/1000000000") == "1e-9", "a billionth reads as a billionth, not as zero")
        suite.expect(math("2^100")?.contains("e") == true, "a huge answer switches notation instead of vanishing")
        suite.expect(math("2026-07-27") == nil && math("27/07/2026") == nil && math("10:30") == nil,
               "a date or a time is never answered as a sum")
        suite.expect(math("100-50") == "50", "two numbers around a minus are still a subtraction")
        suite.expect(math("SDL_VIDEODRIVER=") == nil && math("x=5") == nil,
               "an assignment shape is not an expression")
        suite.expect(math("7+3=") == "10", "a trailing equals sign is just habit")

        suite.expect(math("480+15%") == "552", "a percentage after plus is relative")
        suite.expect(math("480-15%") == "408", "and after minus too")
        suite.expect(math("20% of 480") == "96", "percent of a number reads as it is said")
        suite.expect(math("20% de 480") == "96", "the same in the other words people type")
        suite.expect(math("50%") == nil, "a lone percentage is not a question")
        suite.expect(math("200*10%") == "20", "a percentage multiplies as a fraction")

        suite.expect(math("5") == nil, "a lone number is a search, not an answer")
        suite.expect(math("hello") == nil, "words are not expressions")
        suite.expect(math("1password") == nil, "an app name that starts with a digit stays a search")
        suite.expect(math("volume 20") == nil, "a command with a number is not a sum")
        suite.expect(math("brilho 40") == nil, "neither is the same command in another language")
        suite.expect(math("10/0") == nil, "dividing by zero has no answer to show")
        suite.expect(math("2+") == nil && math("(2+3") == "5" && math("2++") == nil,
               "only missing closing brackets are supplied virtually")
        suite.expect(math("2 * -3") == "-6", "a sign after an operator is read as a sign")
        suite.expect(math(String(repeating: "(", count: 60) + "1" + String(repeating: ")", count: 60)) == nil,
               "a wall of parentheses is refused instead of eating the stack")
        suite.expect(math("e-mail") == nil, "a hyphenated word is not a subtraction")
        suite.expect(math("9999999999999999*99")?.contains("e") == true,
               "a number past plain reading switches notation")

        // The same numbers as the owner's Mac writes them.
        suite.expect(CommandBarMath.evaluate("1.234,5 + 1",
                                       decimalSeparator: ",",
                                       groupingSeparator: ".",
                                       locale: Locale(identifier: "pt_BR"))?.formatted == "1.235,5",
               "a comma decimal parses and prints back in the same shape")
        suite.expect(CommandBarMath.evaluate("1,5*2",
                                       decimalSeparator: ",",
                                       groupingSeparator: ".",
                                       locale: Locale(identifier: "pt_BR"))?.value == 3,
               "the comma is the decimal point where that is the custom")
        suite.expect(math("1.500+1", decimal: ",", grouping: ".") == "1,501",
               "three digits after the grouping separator read as thousands")

        suite.expect(CommandBarMath.evaluate("([2+3")?.closingBrackets == "])"
                && CommandBarMath.evaluate("2+3")?.closingBrackets == "",
               "virtual closers preserve bracket kind and nesting")
        suite.expect(mathValue("sqrt(81") == 9 && mathValue("2*(3+[4") == 14,
               "functions and nested brackets evaluate before closers are typed")
        for expression in ["(2+3]", "2+3)", "2*(3+", "sqrt(", "sin2", "log100(2)",
                           "sqrt(-1)", "log(0)", "acos(2)", "1e309+0", "7=+3", "7+3=="] {
            suite.expect(mathValue(expression) == nil
                    && CommandBarMath.evaluate(expression)?.closingBrackets == nil,
                   "invalid calculator input has neither an answer nor ghost brackets: \(expression)")
        }
        for (expression, expected) in [
            ("sqrt(9)+abs(-3)", 6.0), ("sin(pi/2)+cos(0)+tan(0)", 2.0),
            ("asin(1)+acos(1)+atan(1)", Double.pi * 0.75),
            ("ln(exp(1))+log(100)+log10(100)", 5.0),
            ("floor(1.9)+ceil(1.1)+round(1.5)", 5.0),
            ("2pi", 2 * Double.pi), ("π+e", Double.pi + Foundation.exp(1)),
            ("2x3+2 x 4", 14.0), ("2(3)+(2)(3)+2[3]", 18.0), ("1e-9*1e9", 1.0),
        ] {
            suite.expect(mathValue(expression).map { abs($0 - expected) < 1e-7 } ?? false,
                   "scientific calculator evaluates \(expression)")
        }
        suite.expect(mathValue("1,5e-3*2", decimal: ",", grouping: ".") == 0.003,
               "scientific mantissas respect decimal-comma locales")
        for (expression, expected) in [("sin(1e-13)*1e13", 1.0),
                                       ("tan(1e-13)*1e13", 1.0),
                                       ("sin(-1e-13)*1e13", -1.0),
                                       ("1/sin(1e-13)", 1e13),
                                       ("cos(pi/2+1e-13)/cos(pi/2+1e-13)", 1.0)] {
            suite.expect(mathValue(expression) == expected,
                   "small trigonometric values remain available to the rest of the calculation: \(expression)")
        }
        for expression in ["0.1+0.2", "1/3", "-2^2", "1e-9+0", "2^100"] {
            if let result = CommandBarMath.evaluate(expression,
                                                     decimalSeparator: ".",
                                                     groupingSeparator: ",") {
                let reusable = CommandBarMath.reusableExpression(for: result, decimalSeparator: ".")
                suite.expect(mathValue(reusable + "+0") == result.value,
                       "reusing \(expression) preserves its stored value")
                if result.value == 0.3 {
                    suite.expect(reusable == "0.3", "reuse hides binary noise")
                }
                if result.value == -4 {
                    suite.expect(mathValue(reusable + "^2") == 16,
                           "negative reuse preserves power precedence")
                }
                let comma = CommandBarMath.reusableExpression(for: result, decimalSeparator: ",")
                suite.expect(mathValue(comma + "+0", decimal: ",", grouping: ".") == result.value,
                       "reused answers also round-trip in decimal-comma locales")
            } else {
                suite.expect(false, "calculator produces an answer to reuse for \(expression)")
            }
        }

        // MARK: Command bar, what the person controls

        suite.expect(CommandBarSource.allCases.map(\.rawValue) == [
            "actions", "apps", "menus", "windows", "quitApps", "uninstallApps", "settingsPages",
            "macSettings", "snippets", "clipboard", "emoji", "folders", "answers", "calculator",
            "selection", "links", "files", "killProcess",
        ], "source ids are stable (they persist inside the disabled list)")
        suite.expect(CommandBarSource.actions.isAlwaysOn
                && CommandBarSource.allCases.filter(\.isAlwaysOn).count == 1,
               "only the app's own actions cannot be switched off")
        suite.expect(CommandBarClipboardAccess.canUseHistory(captureEnabled: true,
                                                       hasSavedItems: false),
               "clipboard capture makes the command bar history available")
        suite.expect(CommandBarClipboardAccess.canUseHistory(captureEnabled: false,
                                                       hasSavedItems: true),
               "saved clipboard items stay available when capture is off")
        suite.expect(!CommandBarClipboardAccess.canUseHistory(captureEnabled: false,
                                                        hasSavedItems: false),
               "an empty disabled clipboard still points to setup")
        let japaneseClipboard = FeatureStrings.clipboard(.ja)
        let clipboardClearKeywords = [japaneseClipboard.title,
                                      ClipboardFeatureStrings.enUS.title,
                                      ClipboardFeatureStrings.enUS.clearRecent]
            .joined(separator: " ")
        suite.expect(CommandBarSearch.matches(title: japaneseClipboard.clearRecent,
                                        keywords: clipboardClearKeywords,
                                        query: "clear clipboard"),
               "the clipboard clear action stays findable by its English name in a non-Latin locale")
        let clipboardActionsCode = commandBarCatalogLines.firstIndex {
            isCodeLine($0) && $0.contains("if AppFeature.clipboardHistory.isAvailable {")
        }.map {
            commandBarCatalogLines[$0...]
                .prefix { !$0.contains("if AppFeature.textSnippets.isAvailable {") }
                .filter(isCodeLine)
                .joined(separator: "\n")
        } ?? ""
        suite.expect(clipboardActionsCode.contains("id: \"action.clipboardClearRecent\"")
                && clipboardActionsCode.contains("title: clipboard.clearRecent")
                && clipboardActionsCode.contains("confirmationPrompt: clipboard.clearRecent")
                && clipboardActionsCode.contains("ClipboardHistoryService.shared.clearRecent()"),
               "the Command Bar clears only unpinned clipboard items after confirmation")

        // MARK: Compact mode, what an empty field shows
        suite.expect(CommandBarHome.showsBrowseList(compact: false, hasCategory: false, isPeeking: false),
               "the browse list is what an ordinary empty bar shows")
        suite.expect(!CommandBarHome.showsBrowseList(compact: true, hasCategory: false, isPeeking: false),
               "a compact bar draws no list until something is typed")
        suite.expect(CommandBarHome.showsBrowseList(compact: true, hasCategory: true, isPeeking: false),
               "a category is an explicit drill-in and always shows its rows")
        suite.expect(CommandBarHome.showsBrowseList(compact: true, hasCategory: false, isPeeking: true),
               "a peek is the person asking for the list anyway")
        suite.expect(CommandBarHome.isCollapsed(compact: true, query: "",
                                          hasCategory: false, isPeeking: false),
               "an empty compact field is the whole panel")
        suite.expect(CommandBarHome.isCollapsed(compact: true, query: "   ",
                                          hasCategory: false, isPeeking: false),
               "whitespace is not something typed")
        suite.expect(!CommandBarHome.isCollapsed(compact: true, query: "fire",
                                           hasCategory: false, isPeeking: false),
               "one letter brings the list and the footer back")
        suite.expect(!CommandBarHome.isCollapsed(compact: true, query: "",
                                           hasCategory: true, isPeeking: false),
               "a category keeps the panel open")
        suite.expect(!CommandBarHome.isCollapsed(compact: true, query: "",
                                           hasCategory: false, isPeeking: true),
               "a peeked bar is not collapsed either")
        suite.expect(!CommandBarHome.isCollapsed(compact: false, query: "",
                                           hasCategory: false, isPeeking: false),
               "the ordinary bar is never collapsed")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.commandBarCompactMode] as? Bool == false,
               "compact mode ships off: the browse list is how the bar introduces itself")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarCompactMode),
               "compact mode is configuration, so it travels with an exported setup")
        suite.expect(SettingsBackupSupport.valueLooksRight(DefaultsKey.commandBarCompactMode, true)
                && !SettingsBackupSupport.valueLooksRight(DefaultsKey.commandBarCompactMode, "yes"),
               "a restored compact mode has to be a switch, not text that looks like one")

        // MARK: What the bar noticed about this session
        suite.expect(CommandBarQueryMemory.prefixes(of: "wha") == ["w", "wh", "wha"],
               "choosing a row for what was typed also answers every shorter piece of it")
        suite.expect(CommandBarQueryMemory.prefixes(of: "  Résumé ")
                == ["r", "re", "res", "resu", "resum", "resume"],
               "what is remembered is folded the way the ranking folds, accents and all")
        suite.expect(CommandBarQueryMemory.prefixes(of: "   ").isEmpty,
               "an empty field teaches nothing")
        suite.expect(CommandBarQueryMemory.prefixes(of: String(repeating: "a", count: 40)).count
                == CommandBarQueryMemory.longestPrefix,
               "past a word's worth of letters the ranking already knows what to do")

        var barMemory = CommandBarQueryMemory()
        suite.expect(barMemory.isEmpty && barMemory.boost(query: "pri", id: "app.primary") == 0,
               "a row never chosen for these letters is worth nothing extra")
        barMemory.record(query: "primary", id: "app.primary", step: 1)
        suite.expect(barMemory.boost(query: "pri", id: "app.primary") > 0
                && barMemory.boost(query: "pri", id: "app.other") == 0
                && barMemory.boost(query: "prim", id: "app.primary") > 0,
               "the row chosen for a word answers to the letters on the way to it")
        suite.expect(barMemory.boost(query: "primary extra", id: "app.primary") == 0,
               "letters that were never typed on their own teach nothing")
        barMemory.record(query: "primary", id: "app.primary", step: 2)
        barMemory.record(query: "primary", id: "app.primary", step: 3)
        barMemory.record(query: "primary", id: "app.primary", step: 4)
        suite.expect(barMemory.boost(query: "pri", id: "app.primary")
                == CommandBarQueryMemory.maximumBoost,
               "choosing the same row again stops adding up once it is certain")
        let keywordPrefixScore = CommandBarSearch.score(title: "Other",
                                                        keywords: "primary",
                                                        query: "pri") ?? 0
        let keywordExactScore = CommandBarSearch.score(title: "Other",
                                                       keywords: "pri",
                                                       query: "pri") ?? 0
        suite.expect(keywordPrefixScore + CommandBarQueryMemory.maximumBoost < keywordExactScore,
               "what the bar noticed reorders ties and never beats a better keyword match")
        barMemory.forget(id: "app.primary")
        suite.expect(barMemory.isEmpty, "forgetting one row takes it out of every prefix")
        barMemory.record(query: "a", id: "one", step: 1)
        barMemory.clear()
        suite.expect(barMemory.isEmpty, "and the whole session can be forgotten at once")
        // Five rows compete for one prefix; the least chosen is the one that
        // stops being remembered.
        var crowdedPrefix = CommandBarQueryMemory()
        for index in 0..<(CommandBarQueryMemory.idsPerQuery + 1) {
            for repeatCount in 0...(index == 0 ? 0 : 3) {
                crowdedPrefix.record(query: "x", id: "row.\(index)", step: index * 10 + repeatCount)
            }
        }
        suite.expect(crowdedPrefix.boost(query: "x", id: "row.0") == 0
                && crowdedPrefix.boost(query: "x", id: "row.4") > 0,
               "one prefix remembers a few rows, and the one picked least drops out")

        // MARK: Finding a file from the bar
        suite.expect(CommandBarFileSearchSupport.expression(for: "annual report")
                == "kMDItemFSName == \"*annual*\"cd && kMDItemFSName == \"*report*\"cd",
               "every word has to be in the name, in any order")
        suite.expect(CommandBarFileSearchSupport.expression(for: "a") == nil
                && CommandBarFileSearchSupport.expression(for: "   ") == nil,
               "one letter is not a search, so Spotlight is never asked")
        suite.expect(CommandBarFileSearchSupport.escaped("re*port") == "re\\*port"
                && CommandBarFileSearchSupport.escaped("say \"hi\"") == "say \\\"hi\\\"",
               "a wildcard somebody typed is the character, not a wider search")
        let searchableDirectories: Set<String> = [
            "/Users/x/Notes", "/Users/x/Documents", "/tmp",
        ]
        suite.expect(CommandBarFileSearchSupport.resolvedScopes(
                ["~/Notes", "~/Notes/", "~/single.txt", "/tmp"],
                homeDirectory: "/Users/x",
                homeChildren: [],
                isSearchableDirectory: searchableDirectories.contains)
                == ["/Users/x/Notes", "/tmp"],
               "saved scopes are live directories, deduplicated after tilde expansion")
        suite.expect(CommandBarFileSearchSupport.resolvedScopes(
                ["~"],
                homeDirectory: "/Users/x",
                homeChildren: ["Documents", "Library", ".ssh", "single.txt", "Archive.pkg"],
                isSearchableDirectory: searchableDirectories.contains)
                == ["/Users/x/Documents"],
               "home expands only to visible ordinary directories, never files or packages")
        suite.expect(CommandBarFileSearchSupport.resolvedScopes(
                [], homeDirectory: "/Users/x", homeChildren: ["Documents"],
                isSearchableDirectory: searchableDirectories.contains).isEmpty,
               "a list the person cleared searches nothing, instead of searching everything")
        let packagePaths: Set<String> = [
            "/Applications/Utility.app", "/Users/x/Notes/Archive.unknownpackage",
        ]
        suite.expect(CommandBarFileSearchSupport.isOfferable(
                    path: "/Users/x/Notes/plan.md", isPackage: packagePaths.contains)
                && !CommandBarFileSearchSupport.isOfferable(
                    path: "/Users/x/.ssh/config", isPackage: packagePaths.contains)
                && !CommandBarFileSearchSupport.isOfferable(
                    path: "/Users/x/Notes/.draft.md", isPackage: packagePaths.contains),
               "a hidden file, and anything under a hidden folder, is never offered")
        suite.expect(CommandBarFileSearchSupport.isOfferable(
                    path: "/Applications/Utility.app", isPackage: packagePaths.contains)
                && !CommandBarFileSearchSupport.isOfferable(
                    path: "/Applications/Utility.app/Contents/Info.plist",
                    isPackage: packagePaths.contains)
                && !CommandBarFileSearchSupport.isOfferable(
                    path: "/Users/x/Notes/Archive.unknownpackage/data/item",
                    isPackage: packagePaths.contains),
               "filesystem package metadata seals known and future package types")
        suite.expect(CommandBarFileSearchSupport.isIgnored(path: "/x/node_modules/a/index.js",
                                                     patterns: ["node_modules"])
                && !CommandBarFileSearchSupport.isIgnored(path: "/x/rebuild-notes.md",
                                                          patterns: ["build"]),
               "a name never worth showing matches a whole name, never half of one")
        suite.expect(CommandBarFileSearchSupport.isIgnored(path: "/x/run.log", patterns: ["*.log"])
                && CommandBarFileSearchSupport.isIgnored(path: "/x/run.log", patterns: [".log"])
                && !CommandBarFileSearchSupport.isIgnored(path: "/x/log", patterns: [".log"]),
               "an extension written either way takes out the kind of file, not a folder called log")
        suite.expect(CommandBarFileSearchSupport.offerable(
            paths: ["/x/a.md", "/x/a.md", "/x/.hidden", "/x/node_modules/b.js", "/x/c.md"],
            patterns: ["node_modules"],
            isPackage: { _ in false }) == ["/x/a.md", "/x/c.md"],
               "one path is one row, and what is filtered stays filtered")
        suite.expect(CommandBarFileSearchSupport.shouldPublishResult(for: "new", currentQuery: "new")
                && !CommandBarFileSearchSupport.shouldPublishResult(
                    for: "old", currentQuery: "new")
                && !CommandBarFileSearchSupport.shouldPublishResult(
                    for: "old", currentQuery: nil),
               "a cancelled or superseded asynchronous search never refreshes the visible bar")
        suite.expect(CommandBarFileSearchSupport.decodeList(" a \n\n b \na") == ["a", "b"]
                && CommandBarFileSearchSupport.encodeList(["a", "", "a", "b"]) == "a\nb",
               "the saved lists never repeat themselves and survive a round trip")
        suite.expect(CommandBarFileSearchSupport.abbreviating("/Users/x/Notes", homeDirectory: "/Users/x")
                == "~/Notes"
                && CommandBarFileSearchSupport.abbreviating("/tmp/a", homeDirectory: "/Users/x")
                == "/tmp/a",
               "a path is written the short way only where it really is inside home")
        suite.expect(CommandBarFileSearchSupport.candidateLimit >= CommandBarFileSearchSupport.resultLimit,
               "more names are asked for than are shown, since most are filtered away")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.commandBarFileScopes] as? String == ""
                && Defaults.registeredDefaults[DefaultsKey.commandBarFileIgnores] as? String == "",
               "out of the box the bar has been given no folder, so it looks for no files")
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarFileScopes)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarFileIgnores),
               "folder authority stays on one Mac while ignored names remain portable")
        let fileSearchBackup = SettingsBackupSupport.sanitizedSettings(from: [
            SettingsBackupSupport.formatVersionKey: SettingsBackupSupport.formatVersion,
            SettingsBackupSupport.settingsKey: [
                DefaultsKey.commandBarFileScopes: "~/Documents",
                DefaultsKey.commandBarFileIgnores: "*.log",
            ],
        ])
        suite.expect(fileSearchBackup?[DefaultsKey.commandBarFileScopes] == nil
                && fileSearchBackup?[DefaultsKey.commandBarFileIgnores] as? String == "*.log",
               "a backup restores ignored names but never grants a folder on another Mac")
        let invalidFileSearchBackup = SettingsBackupSupport.sanitizedSettings(from: [
            SettingsBackupSupport.formatVersionKey: SettingsBackupSupport.formatVersion,
            SettingsBackupSupport.settingsKey: [
                DefaultsKey.commandBarFileScopes: 42,
                DefaultsKey.commandBarFileIgnores: false,
            ],
        ])
        suite.expect(invalidFileSearchBackup?.isEmpty == true,
               "a backup cannot restore non-text file search preferences")
        suite.expect(CommandBarPreferences.rankBias(for: .files)
                    < CommandBarPreferences.rankBias(for: .actions)
                && CommandBarPreferences.rankBias(for: .apps)
                    > CommandBarPreferences.rankBias(for: .actions),
               "apps lead commands, while a file needs a plainly better match")
        suite.expect(CommandBarPreferences.rankBias(for: .uninstallApps) == 0,
               "uninstall browse entries have no source ranking boost")

        // MARK: Command Bar ASCII layout switch

        let latinSourceID = "com.apple.keylayout.ABC"
        let russianSourceID = "com.apple.keylayout.RussianWin"
        let pinyinSourceID = "com.apple.inputmethod.SCIM.Shuangpin"
        let latinSource = InputSourceSelection.Snapshot(id: latinSourceID, isLayout: true, isASCIICapable: true)
        let russianSource = InputSourceSelection.Snapshot(id: russianSourceID, isLayout: true, isASCIICapable: false)
        let pinyinSource = InputSourceSelection.Snapshot(id: pinyinSourceID, isLayout: false, isASCIICapable: false)
        suite.expect(InputSourceSelection.asciiLayoutID(currentID: russianSourceID, snapshots: [russianSource, latinSource])
                == latinSourceID,
               "a non-Latin layout borrows the first enabled ASCII layout")
        suite.expect(InputSourceSelection.asciiLayoutID(currentID: pinyinSourceID, snapshots: [latinSource, pinyinSource])
                == latinSourceID,
               "an input method borrows the enabled ASCII layout")
        suite.expect(InputSourceSelection.asciiLayoutID(currentID: latinSourceID, snapshots: [latinSource, russianSource]) == nil,
               "a bar opened on an ASCII layout switches nothing and restores nothing")
        suite.expect(InputSourceSelection.asciiLayoutID(currentID: russianSourceID, snapshots: [russianSource]) == nil,
               "with no ASCII layout enabled there is nothing to borrow")
        suite.expect(InputSourceSelection.asciiLayoutID(currentID: nil, snapshots: [russianSource, latinSource]) == latinSourceID,
               "an unreadable current source still borrows the ASCII layout")
        let asciiCapableMethod = InputSourceSelection.Snapshot(
            id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Roman", isLayout: false, isASCIICapable: true)
        suite.expect(InputSourceSelection.asciiLayoutID(currentID: asciiCapableMethod.id,
                                                  snapshots: [asciiCapableMethod, latinSource]) == latinSourceID,
               "an ASCII-capable input method still moves to a plain layout")

        let commandBarServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/CommandBar/CommandBarService.swift",
            encoding: .utf8)) ?? ""
        suite.expect(commandBarServiceSource.contains("InputSourceSelection.asciiLayoutID"),
               "the bar borrows the ASCII layout through the shared TIS selection")
        suite.expect(commandBarServiceSource.contains("restoreSuspendedInputSource"),
               "closing the bar gives the suspended input source back")
        let asciiSettingsSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/CommandBarSettings.swift",
            encoding: .utf8)) ?? ""
        suite.expect(asciiSettingsSource.contains("DefaultsKey.commandBarASCIILayoutEnabled"),
               "the ASCII layout switch has its own settings row")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.commandBarASCIILayoutEnabled] as? Bool == false,
               "the ASCII layout switch ships off: the bar starts on whatever layout is already up")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarASCIILayoutEnabled),
               "the ASCII layout switch is configuration, so it travels with an exported setup")
        suite.expect(SettingsBackupSupport.valueLooksRight(DefaultsKey.commandBarASCIILayoutEnabled, true)
                && !SettingsBackupSupport.valueLooksRight(DefaultsKey.commandBarASCIILayoutEnabled, "yes"),
               "a restored ASCII layout switch has to be a switch, not text that looks like one")
        let superKeySource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/SuperKey/SuperKeyService.swift",
            encoding: .utf8)) ?? ""
        suite.expect(superKeySource.contains("InputSourceSelection.selectableInputSources()"),
               "the Super key cycle shares the TIS plumbing instead of its own copy")

        // MARK: The Mac's own Settings panes
        let openablePane: [String: Any] = [
            "EXAppExtensionAttributes": [
                "SettingsExtensionAttributes": [
                    "allowsXAppleSystemPreferencesURLScheme": true,
                    "legacyPrefPaneBundleName": "Legacy.prefPane",
                ],
            ],
        ]
        suite.expect(CommandBarSystemSettingsSupport.isOpenablePane(info: openablePane),
               "a pane that answers to the system settings address is one the bar can open")
        suite.expect(!CommandBarSystemSettingsSupport.isOpenablePane(info: [
            "EXAppExtensionAttributes": [
                "SettingsExtensionAttributes": ["allowsXAppleSystemPreferencesURLScheme": false],
            ],
        ]) && !CommandBarSystemSettingsSupport.isOpenablePane(info: ["CFBundleName": "Thumbnails"]),
               "a thumbnailer, and a pane with no address, are not rows")
        suite.expect(CommandBarSystemSettingsSupport.legacyPaneName(info: openablePane)
                == "Legacy.prefPane"
                && CommandBarSystemSettingsSupport.legacyPaneName(info: ["a": 1]) == nil,
               "the older pane is followed only where the newer one names it")
        suite.expect(CommandBarSystemSettingsSupport.paneName(localizedDisplayName: "Coverage & Support",
                                                        displayName: "CoveragePane_Internal",
                                                        bundleName: "Coverage",
                                                        fileName: "CoverageSettings.appex")
                == "Coverage & Support",
               "a pane is called what System Settings calls it")
        suite.expect(CommandBarSystemSettingsSupport.paneName(localizedDisplayName: nil,
                                                        displayName: "  ",
                                                        bundleName: nil,
                                                        fileName: "VPN.appex") == "VPN",
               "a pane that declares no name at all still gets one")
        // Every pane names its own groups, so all of them are read, in a fixed
        // order: one Mac and the next must produce the same words.
        suite.expect(CommandBarSystemSettingsSupport.keywords(fromSearchTerms: [
            "bSection": ["localizableStrings": [["title": "Brillo", "index": "aclarar, atenuar"]]],
            "aSection": ["localizableStrings": [["title": "Alinear", "index": "espejo,  , Alinear"]]],
        ]) == "Alinear espejo Brillo aclarar atenuar",
               "the words a pane answers to are read from every group and never repeat")
        suite.expect(CommandBarSystemSettingsSupport.keywords(fromSearchTerms: ["Main": "not a group"])
                .isEmpty,
               "a search index in a shape nobody recognizes is no words, not a crash")
        suite.expect(CommandBarSystemSettingsSupport.keywords(fromSearchTerms: [
            "a": ["localizableStrings": [["title": "one", "index": "two, three"]]],
        ], limit: 2) == "one two",
               "one pane never contributes more words than the ranking can use")
        let longPaneTerms = (1...45).map { ["title": "term\($0)", "index": ""] }
        suite.expect(CommandBarSystemSettingsSupport.keywords(fromSearchTerms: [
            "Main": ["localizableStrings": longPaneTerms],
        ]).contains("term45"),
               "important terms beyond the old forty-word cutoff remain searchable")
        suite.expect(Set(AppLanguage.allCases.map(CommandBarSystemSettingsSupport.resourceFolder)).count
                == AppLanguage.allCases.count,
               "each language reads its own words, so no two share a folder")

        suite.expect(CommandBarPreferences.source(ofRowID: "app.x") == .apps
                && CommandBarPreferences.source(ofRowID: "menu.1.Bold") == .menus
                && CommandBarPreferences.source(ofRowID: "folder./tmp") == .folders
                && CommandBarPreferences.source(ofRowID: "macsettings.com.apple.Sound-Settings.extension")
                    == .macSettings
                && CommandBarPreferences.source(ofRowID: "settings.general") == .settingsPages
                && CommandBarPreferences.source(ofRowID: "action.screenshot") == .actions
                && CommandBarPreferences.source(ofRowID: "action.recentCaptures") == .actions
                && CommandBarPreferences.emojiBrowserRowID == "emoji.browse"
                && CommandBarPreferences.source(ofRowID: CommandBarPreferences.emojiBrowserRowID)
                    == .emoji,
               "every row knows which source it came from")
        suite.expect(CommandBarPreferences.isEnabled(.folders, disabledRaw: "folders,emoji") == false
                && CommandBarPreferences.isEnabled(.apps, disabledRaw: "folders,emoji") == true
                && CommandBarPreferences.isEnabled(.actions, disabledRaw: "actions") == true,
               "a switched off source stays off, and actions never can be")
        suite.expect(CommandBarPreferences.storageValue(for: [.emoji, .folders, .actions])
                == "emoji,folders",
               "the disabled list writes the same way every time")
        suite.expect(CommandBarPreferences.disabledSources(from: "folders, nonsense ,emoji")
                == Set([.folders, .emoji]),
               "an unknown source id is dropped instead of corrupting the set")

        var barAliases = CommandBarPreferences.settingAlias("codex", for: "app./Applications/Chat.app",
                                                            in: [:])
        suite.expect(barAliases["app./Applications/Chat.app"] == "codex", "a row takes the name it was given")
        suite.expect(CommandBarPreferences.aliasMatches("codex", query: "codex")
                && CommandBarPreferences.aliasMatches("codex", query: "cod")
                && !CommandBarPreferences.aliasMatches("codex", query: "codexx"),
               "the name matches whole or as it is being typed, never beyond it")
        suite.expect(CommandBarPreferences.aliasMatches("meu chat codex", query: "codex"),
               "several words all find the same row")
        suite.expect(CommandBarPreferences.aliasMatches("Códex", query: "codex"),
               "accents in a name never break it")
        barAliases = CommandBarPreferences.settingAlias("  ", for: "app./Applications/Chat.app",
                                                        in: barAliases)
        suite.expect(barAliases.isEmpty, "clearing the field removes the name")
        suite.expect(CommandBarPreferences.decodeAliases(
                CommandBarPreferences.encodeAliases(["a": "one", "b": "two"])) == ["a": "one", "b": "two"],
               "names survive the round trip")
        suite.expect(CommandBarPreferences.decodeAliases("not json").isEmpty,
               "a corrupt name list decodes as none")
        suite.expect(CommandBarPreferences.acceptsAlias(rowID: "app.x")
                && !CommandBarPreferences.acceptsAlias(rowID: "menu.1.Bold")
                && !CommandBarPreferences.acceptsAlias(rowID: "window.4")
                && !CommandBarPreferences.acceptsAlias(rowID: "clipboard.abc")
                && !CommandBarPreferences.acceptsAlias(rowID: "uninstall.x"),
               "only rows that are the same thing tomorrow can be named")
        suite.expect(!CommandBarPreferences.acceptsPin(rowID: "uninstall.x")
                && !CommandBarPreferences.acceptsPin(rowID: "menu.1.Bold")
                && CommandBarPreferences.acceptsPin(rowID: "app.x"),
               "an uninstall row is offered fresh each time, so it cannot be pinned")

        var barPins = CommandBarPreferences.togglingPin("action.screenshot", in: [])
        barPins = CommandBarPreferences.togglingPin("app.chat", in: barPins)
        suite.expect(barPins == ["action.screenshot", "app.chat"], "pins keep the order they were made in")
        suite.expect(CommandBarPreferences.togglingPin("action.screenshot", in: barPins) == ["app.chat"],
               "the same gesture unpins")
        suite.expect(CommandBarPreferences.leadingPins(["app.chat", "app.gone"],
                                                 available: ["app.chat", "action.a"])
                == ["app.chat"],
               "the empty bar leads with the pins that still exist")
        suite.expect(CommandBarPreferences.listedPins(
                    ["action.cleaningMode", "app.chat", "settings.cleaningMode"],
                    present: ["app.chat"])
                == ["app.chat"],
               "an uninstalled feature is not listed as a pin")
        suite.expect(CommandBarPreferences.listedPins(
                    ["action.cleaningMode", "app.gone"],
                    present: ["action.cleaningMode"])
                == ["action.cleaningMode", "app.gone"],
               "an app that left this Mac still appears so its pin can be removed")
        suite.expect(CommandBarPreferences.pinTieBreak < 700,
               "a pin breaks a tie and never jumps over a better match")
        suite.expect(CommandBarPreferences.aliasHit("codex", query: "codex") == .exact
                && CommandBarPreferences.aliasHit("codex", query: "cod") == .prefix
                && CommandBarPreferences.aliasHit("codex", query: "zzz") == nil,
               "a finished name outranks one still being typed")
        suite.expect(CommandBarPreferences.AliasHit.exact.rawValue > 1200
                && CommandBarPreferences.AliasHit.prefix.rawValue > 900,
               "the name the person gave beats the app's own title")
        suite.expect(CommandBarPreferences.rowUsingAlias("codex", in: ["app.a": "codex"], excluding: "app.b")
                == "app.a",
               "a name already taken is reported instead of being stolen")
        suite.expect(CommandBarPreferences.rowUsingAlias("codex", in: ["app.a": "codex"], excluding: "app.a")
                == nil,
               "renaming a row never conflicts with itself")
        var barHidden = CommandBarPreferences.togglingHidden("app.x", in: [])
        suite.expect(barHidden == ["app.x"], "a row can be told never to show")
        barHidden = CommandBarPreferences.togglingHidden("app.x", in: barHidden)
        suite.expect(barHidden.isEmpty, "and told to come back")
        suite.expect(CommandBarPreferences.decodeHidden(
                CommandBarPreferences.encodeHidden(["b", "a"])) == ["a", "b"],
               "hidden rows survive the round trip")
        suite.expect(CommandBarPreferences.decodePins(CommandBarPreferences.encodePins(["a", "b"])) == ["a", "b"]
                && CommandBarPreferences.decodePins("a\na\n\nb") == ["a", "b"],
               "pins survive the round trip and never repeat")
        let positionOffset = CGSize(width: -24.4, height: 80.6)
        suite.expect(CommandBarPreferences.decodePositionOffset(
            CommandBarPreferences.encodePositionOffset(positionOffset))
            == CGSize(width: -24, height: 81),
               "the command bar position offset survives a rounded round trip")
        for invalidOffset in ["", "12", "12,", "12,nope", "12,nope,20", "nan,1", "inf,1"] {
            suite.expect(CommandBarPreferences.decodePositionOffset(invalidOffset) == .zero,
                   "an invalid command bar position offset is ignored (\(invalidOffset))")
        }
        suite.expect(CommandBarPreferences.encodePositionOffset(.zero).isEmpty
                && CommandBarPreferences.encodePositionOffset(
                    CGSize(width: CGFloat.infinity, height: 1)).isEmpty,
               "an empty or non-finite command bar position offset is not stored")
        let commandBarScreen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let commandBarSize = CGSize(width: 560, height: 380)
        let upperRight = CommandBarPreferences.clampedPanelOrigin(
            size: commandBarSize, in: commandBarScreen,
            offset: CGSize(width: 10_000, height: 10_000))
        let lowerLeft = CommandBarPreferences.clampedPanelOrigin(
            size: commandBarSize, in: commandBarScreen,
            offset: CGSize(width: -10_000, height: -10_000))
        suite.expect(upperRight == CGPoint(x: -576, y: 504)
                && lowerLeft == CGPoint(x: -1424, y: 16),
               "the command bar stays fully inside a screen on both axes")

        // MARK: Command bar unit conversion

        func units(_ input: String) -> String? {
            CommandBarUnits.convert(input,
                                    decimalSeparator: ".",
                                    groupingSeparator: ",",
                                    locale: Locale(identifier: "en_US"))?.formatted
        }
        func unitValue(_ input: String) -> Double? {
            CommandBarUnits.convert(input,
                                    decimalSeparator: ".",
                                    groupingSeparator: ",",
                                    locale: Locale(identifier: "en_US"))?.value
        }

        suite.expect(unitValue("100 km to mi").map { abs($0 - 62.1371) < 0.001 } == true,
               "a distance converts")
        suite.expect(unitValue("20 c to f").map { abs($0 - 68) < 0.001 } == true,
               "a temperature converts as an absolute reading, not as a step")
        suite.expect(unitValue("0 c to f").map { abs($0 - 32) < 0.001 } == true,
               "freezing reads as freezing")
        suite.expect(unitValue("5 gb to mb").map { abs($0 - 5000) < 0.001 } == true,
               "storage uses the decimal units it is written with")
        suite.expect(unitValue("1 gib to mib").map { abs($0 - 1024) < 0.001 } == true,
               "and the binary ones when those are written instead")
        suite.expect(unitValue("100km to mi").map { abs($0 - 62.1371) < 0.001 } == true,
               "the number and the unit do not need a space between them")
        suite.expect(unitValue("5 in to cm").map { abs($0 - 12.7) < 0.001 } == true,
               "the word that also means inches is read correctly on both sides")
        suite.expect(unitValue("2 h to min").map { abs($0 - 120) < 0.001 } == true,
               "hours become minutes")
        suite.expect(unitValue("1 kg to lb").map { abs($0 - 2.20462) < 0.001 } == true,
               "mass converts")
        suite.expect(unitValue("1.5 l to ml").map { abs($0 - 1500) < 0.001 } == true,
               "a decimal amount converts")
        suite.expect(units("100 km to kg") == nil, "two different families never meet")
        suite.expect(units("100 km") == nil, "without the word there is no conversion")
        suite.expect(units("to") == nil && units("in") == nil,
               "the little words alone convert nothing")
        suite.expect(units("safari to dock") == nil, "plain words are not units")
        suite.expect(units("5 xyz to cm") == nil, "an unknown unit is refused, never guessed")
        suite.expect(units("minutes to read the article") == nil,
               "a sentence that happens to contain a unit word stays a search")
        suite.expect(CommandBarUnits.convert("1,5 m to cm",
                                       decimalSeparator: ",",
                                       groupingSeparator: ".",
                                       locale: Locale(identifier: "pt_BR"))
                .map { abs($0.value - 150) < 0.001 } == true,
               "a comma decimal converts where that is the custom")

        // MeasurementFormatter words the unit from the localization data of the
        // macOS it runs on, not from the locale it is handed, so pinning
        // "5 ft 10.87 in" here failed on macOS 15.x with nothing changed
        // (issue #1344). What this file decides is the split into whole feet
        // and leftover inches, and the number format; the words are the
        // system's to choose.
        let unitNumbers: (String?) -> [String] = { text in
            (text ?? "").split(whereSeparator: { !"0123456789.,-".contains($0) })
                .filter { $0.rangeOfCharacter(from: .decimalDigits) != nil }
                .map(String.init)
        }
        suite.expect(unitNumbers(units("180 cm to ft")) == ["5", "10.87"],
               "a length converting to feet keeps precise feet and inches")
        suite.expect(unitNumbers(units("1.75 m to ft")) == ["5", "8.9"],
               "a decimal length keeps its fractional inches")
        suite.expect(unitNumbers(units("6 ft to ft")) == ["6"],
               "a whole number of feet has no leftover inches shown")
        suite.expect(unitNumbers(units("5.9999 ft to ft")) == ["6"],
               "inches that round up to twelve carry into the next whole foot")
        suite.expect(unitNumbers(units("2 cm to ft")) == ["0.0656"],
               "a length below one foot stays precise instead of rounding to inches")
        suite.expect(unitNumbers(units("-180 cm to ft")) == ["-5.91"],
               "a negative length keeps the existing decimal format")
        suite.expect(unitNumbers(units("180 cm to in")) == ["70.87"],
               "converting to inches specifically stays a plain decimal, unaffected by the feet formatting")
        suite.expect(unitNumbers(CommandBarUnits.convert("180 cm para pes",
                                                   decimalSeparator: ",",
                                                   groupingSeparator: ".",
                                                   locale: Locale(identifier: "pt_BR"))?.formatted)
                == ["5", "10,87"],
               "feet and inches follow the person's number format")

        // MARK: Command bar emoji

        suite.expect(CommandBarEmoji.emoji.count > 1_000, "the searchable Unicode emoji set is there")
        suite.expect(CommandBarEmoji.emoji.allSatisfy { !$0.name.isEmpty && !$0.character.isEmpty },
               "every emoji carries the words that find it")
        suite.expect(CommandBarEmoji.emoji.contains {
            $0.character == "😂" && $0.name == "face with tears of joy"
                && $0.keywords.contains("haha") && $0.keywords.contains("roflmao")
        }, "chat vocabulary finds laughter the way mainstream pickers do")
        suite.expect(CommandBarEmoji.emoji.contains {
            $0.character == "🤷" && $0.keywords.contains("idk")
                && $0.keywords.contains("whatever")
        }, "conversational aliases find common reactions")
        suite.expect(CommandBarEmoji.emoji.contains {
            $0.character == "🙏" && $0.keywords.contains("appreciate")
                && $0.keywords.contains("thx")
        }, "chat shorthand and intent find emoji, not only literal gestures")
        suite.expect(CommandBarEmoji.emoji.contains { $0.name.contains("heart") },
               "the ones people look for by feeling are findable")
        suite.expect(CommandBarEmoji.emoji.contains {
            $0.character == "💀" && $0.name == "skull" && $0.keywords.contains("dead")
        }, "common emoji answer to both Unicode names and human aliases")
        suite.expect(CommandBarEmoji.emoji.contains {
            $0.character == "🖥️" && $0.identity == "🖥"
        }, "emoji presentation does not change a popular row's stored identity")
        suite.expect(CommandBarEmoji.emoji.contains {
            $0.character == "❤️" && $0.identity == "❤️"
        }, "an existing selector remains part of its original row identity")
        let emojiCharacters = Set(CommandBarEmoji.emoji.map(\.character))
        suite.expect(["©️", "™️", "✂️"].allSatisfy(emojiCharacters.contains),
               "text-default emoji get the selector that displays them as emoji")
        suite.expect(["🌤️", "🌧️", "⛈️", "🗺️", "🖥️", "🖱️", "🖨️", "🛠️"].allSatisfy {
            emojiCharacters.contains($0) && $0.unicodeScalars.last?.value == 0xFE0F
        }, "popular text-default emoji keep their emoji presentation selector")
        suite.expect(["#️", "*️", "0️", "9️", "🏻", "🇦", "🦰", "🦱", "🦲", "🦳"].allSatisfy {
            !emojiCharacters.contains($0)
        }, "incomplete emoji sequence components are not offered alone")
        suite.expect(CommandBarEmoji.emoji.first?.character == "😀",
               "popular emoji keep a predictable lead over the Unicode long tail")
        suite.expect(emojiCharacters.count == CommandBarEmoji.emoji.count,
               "no emoji is offered twice")

        // MARK: Skin tones

        suite.expect(CommandBarEmoji.SkinTone.allCases.count == 6
                && CommandBarEmoji.SkinTone.none.modifier == nil
                && CommandBarEmoji.SkinTone.allCases.dropFirst().allSatisfy {
                    $0.modifier?.properties.isEmojiModifier == true
                },
               "the yellow default and the five tones Unicode defines, and nothing else")
        suite.expect(CommandBarEmoji.acceptsSkinTone("👍") && CommandBarEmoji.acceptsSkinTone("☝️"),
               "a hand takes a tone whether or not it carries a presentation selector")
        suite.expect(!CommandBarEmoji.acceptsSkinTone("😀") && !CommandBarEmoji.acceptsSkinTone("🍕")
                && !CommandBarEmoji.acceptsSkinTone("🤷\u{200D}♀️"),
               "a face, an object and a sequence are all left alone")
        suite.expect(CommandBarEmoji.applying(.medium, to: "👍") == "👍\u{1F3FD}",
               "a tone is the modifier appended to the emoji")
        suite.expect(CommandBarEmoji.applying(.medium, to: "☝️") == "\u{261D}\u{1F3FD}",
               "the presentation selector goes with the tone, which already implies it")
        suite.expect(CommandBarEmoji.SkinTone.allCases.allSatisfy {
            CommandBarEmoji.applying($0, to: "☝️").count == 1
        }, "every tone of an emoji is still one character to type and to delete")
        suite.expect(CommandBarEmoji.applying(.none, to: "👍") == "👍"
                && CommandBarEmoji.applying(.dark, to: "🍕") == "🍕",
               "the default and an emoji with no tone to give are returned untouched")
        suite.expect(Set(CommandBarEmoji.SkinTone.allCases.map(\.swatch)).count
                == CommandBarEmoji.SkinTone.allCases.count,
               "the picker shows a different hand for every tone it offers")
        suite.expect(CommandBarEmoji.emoji.contains { CommandBarEmoji.acceptsSkinTone($0.character) }
                && CommandBarEmoji.emoji.contains { !CommandBarEmoji.acceptsSkinTone($0.character) },
               "the offered set has emoji that take a tone and emoji that do not")
        suite.expect(CommandBarPreferences.skinTone(from: "") == CommandBarEmoji.SkinTone.none
                && CommandBarPreferences.skinTone(from: "dark") == CommandBarEmoji.SkinTone.dark
                && CommandBarPreferences.skinTone(from: "mauve") == CommandBarEmoji.SkinTone.none,
               "a tone survives storage, and one this version does not know reads as the default")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.commandBarEmojiSkinTone] as? String == "",
               "emoji ship in the tone Unicode gives them until the person says otherwise")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarEmojiSkinTone),
               "the chosen tone is configuration, so it travels with an exported setup")
        suite.expect(CommandBarPreferences.emojiIdentity(
            fromRowID: CommandBarPreferences.emojiRowID(identity: "👍")) == "👍",
               "the emoji comes back out of the id its row is stored under")
        suite.expect(CommandBarEmoji.SkinTone.allCases.filter { $0 != .none }.allSatisfy {
            CommandBarEmoji.applying($0, to: "👍") != "👍"
        }, "every tone changes the character, so an id carrying one would move with it")
        suite.expect(CommandBarPreferences.emojiIdentity(fromRowID: "app.finder") == nil
                && CommandBarPreferences.emojiIdentity(fromRowID: "emoji.") == nil,
               "a row of another kind, and an id with no emoji left in it, answer with nothing")
        let catalogSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift",
            encoding: .utf8)) ?? ""
        suite.expect(catalogSource.contains(
            "CommandBarPreferences.emojiRowID(identity: emoji.identity)"),
               "the emoji rows take their id from the seam above, not from the toned character")
        suite.expect(CommandBarSearch.emojiQuery(from: "fire") == nil,
               "an ordinary search never opens the emoji index")
        suite.expect(CommandBarSearch.emojiQuery(from: ":fire") == "fire"
                && CommandBarSearch.emojiQuery(from: "  : heart  ") == "heart",
               "a leading colon scopes the search and stays out of the emoji query")
        suite.expect(CommandBarSearch.emojiQuery(from: ":") == "",
               "a colon by itself opens the emoji index for browsing")

        // MARK: Command bar highlighting

        suite.expect(CommandBarSearch.highlightOffsets(title: "Screen brightness", query: "bright")
                == Set(7..<13),
               "the matched word is marked where it really is")
        suite.expect(CommandBarSearch.highlightOffsets(title: "Brilho da tela", query: "brilho tela")
                == Set(0..<6).union(Set(10..<14)),
               "every token gets its own mark")
        suite.expect(CommandBarSearch.highlightOffsets(title: "Reunião com João", query: "reuniao")
                == Set(0..<7),
               "accents do not shift the marks")
        suite.expect(CommandBarSearch.highlightOffsets(title: "Settings", query: "brlho").isEmpty,
               "a typo rescue marks nothing rather than guessing")
        suite.expect(CommandBarSearch.highlightOffsets(title: "Empty the Trash", query: "trash")
                == Set(10..<15),
               "the mark lands on the word, not on the first letters that repeat")
        suite.expect(CommandBarSearch.highlightOffsets(title: "Anything", query: "").isEmpty,
               "nothing typed, nothing marked")

        // MARK: Command bar wiring

        suite.expect(Defaults.registeredDefaults[DefaultsKey.commandBarShortcutEnabled] as? Bool == false,
               "the command bar shortcut ships off like every new feature")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.commandBarShortcut] as? String
                == "option:49",
               "the default command bar shortcut is option space, the launcher convention")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.commandBarPositionOffset] as? String == "",
               "the command bar position starts at its default spot")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityCommandBar] as? Bool == true,
               "the command bar panel row ships visible like its siblings")
        suite.expect(GlobalShortcutRole.commandBar.requiredEnableKeys == [DefaultsKey.commandBarShortcutEnabled]
                && GlobalShortcutRole.commandBar.feature == .commandBar,
               "the command bar shortcut role gates on its toggle and feature")
        suite.expect(AppFeature.commandBar.group == .tools && AppFeature.commandBar.enabledKeys.isEmpty
                && AppFeature.commandBar.permissions == [.accessibility],
               "the command bar is an on-demand tool that reads and types through accessibility")
        suite.expect(AppFeature.commandBar.energyProfile == .idle,
               "the command bar costs nothing while closed")
        suite.expect(pageVisible(.commandBar, available: [.commandBar])
                && !pageVisible(.commandBar, available: []),
               "the command bar page follows its hub switch")
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarUsage)
                && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarQueryHabits),
               "what the person runs most never travels in a backup")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarShortcutEnabled)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarShortcut)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarLinks)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarPositionOffset),
               "the command bar settings travel in backups")
        // MARK: Command bar search and ranking

        let firstBarPresentation = UUID()
        let secondBarPresentation = UUID()
        var barLifecycle = CommandBarPresentationLifecycle()
        barLifecycle.beginHome(firstBarPresentation)
        suite.expect(barLifecycle.isLoadingHome,
               "home presents with no stale runnable rows while its catalog hydrates")
        barLifecycle.hide()
        suite.expect(!barLifecycle.completeHomeHydration(firstBarPresentation, isVisible: false),
               "closing the panel cancels deferred hydration")

        barLifecycle.beginHome(firstBarPresentation)
        barLifecycle.beginHome(secondBarPresentation)
        suite.expect(!barLifecycle.completeHomeHydration(firstBarPresentation, isVisible: true)
                && barLifecycle.completeHomeHydration(secondBarPresentation, isVisible: true),
               "only the latest visible home presentation may receive deferred work")
        suite.expect(barLifecycle.acceptsHomeUpdates(secondBarPresentation, isVisible: true)
                && !barLifecycle.acceptsHomeUpdates(firstBarPresentation, isVisible: true)
                && !barLifecycle.acceptsHomeUpdates(secondBarPresentation, isVisible: false),
               "background rows update only their still-visible home presentation")
        suite.expect(barLifecycle.acceptsSharedCacheCompletion(
                    startedBy: firstBarPresentation,
                    currentID: secondBarPresentation,
                    isVisible: true),
               "a shared cache completion refreshes the newer visible Home")
        barLifecycle.hide()
        suite.expect(!barLifecycle.acceptsSharedCacheCompletion(
                    startedBy: firstBarPresentation,
                    currentID: secondBarPresentation,
                    isVisible: true),
               "a shared cache completion never mutates a hidden panel")

        var deferredShortcut = CommandBarDeferredRowShortcut()
        deferredShortcut.schedule("action.trash", for: firstBarPresentation)
        suite.expect(deferredShortcut.key(for: secondBarPresentation) == nil
                && deferredShortcut.key(for: firstBarPresentation) == "action.trash"
                && deferredShortcut.take(for: secondBarPresentation) == nil
                && deferredShortcut.take(for: firstBarPresentation) == "action.trash"
                && deferredShortcut.take(for: firstBarPresentation) == nil,
               "an async row shortcut waits without being consumed, then runs once on its presentation")
        deferredShortcut.schedule("action.trash", for: firstBarPresentation)
        deferredShortcut.cancel()
        suite.expect(deferredShortcut.take(for: firstBarPresentation) == nil,
               "closing or superseding a presentation cancels its prompt shortcut")

        suite.expect(CommandBarSearch.normalized("  Brilho   da\tTela ") == "brilho da tela",
               "command bar folds case and collapses whitespace")
        suite.expect(CommandBarSearch.matches(title: "Reunião com João", query: "reuniao joao"),
               "command bar search ignores accents and case")
        suite.expect(CommandBarSearch.matches(title: "Brilho da tela", query: "brilho"),
               "a plain word finds its command")
        suite.expect(CommandBarSearch.matches(title: "Brilho da tela", query: "Brilho"),
               "capitalized queries land in the same place")
        suite.expect(CommandBarSearch.matches(title: "Brilho da tela", query: "brlho"),
               "a dropped letter still finds the command")
        suite.expect(CommandBarSearch.matches(title: "Brilho da tela", query: "birlho"),
               "two swapped letters still find the command")
        suite.expect(CommandBarSearch.matches(title: "Zen", query: "zne"),
               "a swapped pair still finds a three-letter name")
        suite.expect(!CommandBarSearch.matches(title: "Brilho da tela", query: "volume"),
               "an unrelated word stays out")
        suite.expect(!CommandBarSearch.matches(title: "Zen", query: "zip"),
               "short substitutions do not make unrelated names match")
        suite.expect(CommandBarSearch.matches(title: "Capturar tela", keywords: "screenshot print", query: "print"),
               "keywords match like the title does")
        suite.expect(CommandBarSearch.matches(title: "Capturas recentes",
                                        keywords: "Recent captures screenshot recording",
                                        query: "recent captures"),
               "recent captures stays searchable by its familiar English name")
        suite.expect(CommandBarSearch.pinyinKeywords("云笔记") == "yunbiji ybj",
               "pinyin keywords run the syllables together and add the initials")
        suite.expect(CommandBarSearch.pinyinKeywords("Reader").isEmpty,
               "a name without Han characters gets no pinyin keywords")
        let pinyinKeywords = CommandBarSearch.pinyinKeywords("云笔记")
        suite.expect(CommandBarSearch.matches(title: "云笔记", keywords: pinyinKeywords,
                                        query: "yunbiji"),
               "a Chinese title is found by its pinyin")
        suite.expect(CommandBarSearch.matches(title: "云笔记", keywords: pinyinKeywords, query: "ybj"),
               "a Chinese title is found by its pinyin initials")
        let applicationKeywords = CommandBarSearch.applicationKeywords(
            title: "云笔记", diskName: "CloudNotes", alternateNames: ["Former Notes"])
        suite.expect(CommandBarSearch.matches(title: "云笔记", keywords: applicationKeywords,
                                        query: "cloudnotes")
                && CommandBarSearch.matches(title: "云笔记", keywords: applicationKeywords,
                                            query: "former")
                && CommandBarSearch.matches(title: "云笔记", keywords: applicationKeywords,
                                            query: "yunbiji"),
               "an app keeps its disk, alternate and phonetic names searchable")
        suite.expect(CommandBarSearch.matches(title: "Silenciar microfone", query: "silenciar micro"),
               "tokens match in any order as prefixes")
        suite.expect(!CommandBarSearch.matches(title: "Silenciar microfone", query: "silenciar tela"),
               "every token must land somewhere")
        suite.expect(CommandBarSearch.isSubsequence("brlho", of: "brilho")
                && !CommandBarSearch.isSubsequence("brilhoo", of: "brilho"),
               "subsequence needs every letter in order")
        suite.expect(CommandBarSearch.withinOneEdit("birlho", "brilho")
                && CommandBarSearch.withinOneEdit("brilo", "brilho")
                && CommandBarSearch.withinOneEdit("brilyo", "brilho")
                && !CommandBarSearch.withinOneEdit("brolyo", "brilho"),
               "one edit means one swap, one gap or one wrong letter")
        suite.expect(CommandBarSearch.isAdjacentTransposition("zne", "zen")
                && !CommandBarSearch.isAdjacentTransposition("zne", "zone")
                && !CommandBarSearch.isAdjacentTransposition("zip", "zen"),
               "short typo tolerance accepts one neighboring swap only")

        let barCandidates = [
            CommandBarCandidate(index: 0, title: "Capturar tela"),
            CommandBarCandidate(index: 1, title: "Copiar texto da tela"),
            CommandBarCandidate(index: 2, title: "Bloquear a tela"),
            CommandBarCandidate(index: 3, title: "Manter acordado"),
        ]
        suite.expect(CommandBarSearch.rankedIndexes(candidates: barCandidates, matching: "tela")
                == [0, 1, 2],
               "matching rows keep catalog order on equal scores")
        suite.expect(CommandBarSearch.rankedIndexes(candidates: barCandidates, matching: "capturar tela")
                .first == 0,
               "the full title wins the top row")
        let boosted = [
            CommandBarCandidate(index: 0, title: "Capturar tela"),
            CommandBarCandidate(index: 1, title: "Copiar texto da tela", boost: 300),
        ]
        suite.expect(CommandBarSearch.rankedIndexes(candidates: boosted, matching: "tela") == [1, 0],
               "usage boost reorders equally good matches")
        suite.expect(CommandBarSearch.rankedIndexes(candidates: boosted, matching: "capturar") == [0],
               "a boost never resurrects a non-match")
        suite.expect(CommandBarSearch.rankedIndexes(candidates: barCandidates, matching: " ").isEmpty,
               "a blank query ranks nothing; suggestions handle it")
        let typoCandidates = [
            CommandBarCandidate(index: 0, title: "Zebra"),
            CommandBarCandidate(index: 1, title: "Zen"),
            CommandBarCandidate(index: 2, title: "Zne Tools"),
        ]
        suite.expect(CommandBarSearch.rankedIndexes(candidates: typoCandidates, matching: "zne")
                == [2, 1],
               "literal short matches rank above a transposition and unrelated names stay out")

        // One widely installed app carries a left-to-right mark in front of
        // its name, which made it stop being an exact match for the name it
        // shows and sink under every menu row that merely started with it.
        suite.expect(CommandBarSearch.normalized("\u{200E}WhatsApp") == "whatsapp"
                && CommandBarSearch.normalized("Soft\u{00AD}hyphen") == "softhyphen",
               "characters that take up no space never reach the matching")
        let invisible = [
            CommandBarCandidate(index: 0, title: "WhatsApp Business (and 1 more tab)",
                                keywords: "Menu Safari History Recently Closed"),
            CommandBarCandidate(index: 1, title: "\u{200E}WhatsApp"),
        ]
        suite.expect(CommandBarSearch.rankedIndexes(candidates: invisible, matching: "whatsapp")
                == [1, 0],
               "the app named exactly what was typed leads, invisible mark and all")
        suite.expect(CommandBarPreferences.rankBias(for: .menus) < 0
                && CommandBarPreferences.rankBias(for: .apps)
                    > CommandBarPreferences.rankBias(for: .actions)
                && CommandBarPreferences.rankBias(for: .actions) == 0,
               "apps lead owned actions, and borrowed menu rows sit below both")
        let borrowed = [
            CommandBarCandidate(index: 0, title: "Tela cheia",
                                boost: CommandBarPreferences.rankBias(for: .menus)),
            CommandBarCandidate(index: 1, title: "Tela cheia"),
        ]
        suite.expect(CommandBarSearch.rankedIndexes(candidates: borrowed, matching: "tela cheia")
                == [1, 0],
               "at equal quality the app's own row wins over the menu of the app in front")
        let sharper = [
            CommandBarCandidate(index: 0, title: "Fechar aba",
                                boost: CommandBarPreferences.rankBias(for: .menus)),
            CommandBarCandidate(index: 1, title: "Fechar todas as abas do navegador"),
        ]
        suite.expect(CommandBarSearch.rankedIndexes(candidates: sharper, matching: "fechar aba")
                .first == 0,
               "the step down never buries a menu command that is what was typed")
        let appBeforeDiscovery = [
            CommandBarCandidate(index: 0, title: "What's New",
                                boost: CommandBarPreferences.rankBias(for: .settingsPages)),
            CommandBarCandidate(index: 1, title: "Whatever",
                                boost: CommandBarPreferences.rankBias(for: .apps)),
        ]
        suite.expect(CommandBarSearch.rankedIndexes(candidates: appBeforeDiscovery, matching: "what")
                .first == 1,
               "an equally good app match leads a low-priority discovery page")
        let learnedBeforeExact = [
            CommandBarCandidate(index: 0, title: "Passwords"),
            CommandBarCandidate(index: 1, title: "Secure Pass", priority: 1),
        ]
        suite.expect(CommandBarSearch.rankedIndexes(candidates: learnedBeforeExact, matching: "pass")
                .first == 1,
               "a learned query choice outranks an unselected stronger text match")
        let namedApp = [
            CommandBarCandidate(index: 0, title: "Editor"),
            CommandBarCandidate(index: 1, title: "Source Studio",
                                keywords: "editor", priority: 2_400),
        ]
        suite.expect(CommandBarSearch.rankedIndexes(candidates: namedApp, matching: "editor")
                .first == 1,
               "a name deliberately given to an app still leads its ordinary title match")
        let aliasBeforeLearning = [
            CommandBarCandidate(index: 0, title: "Passwords", priority: 1_100),
            CommandBarCandidate(index: 1, title: "Secure Pass", priority: 720),
        ]
        suite.expect(CommandBarSearch.rankedIndexes(candidates: aliasBeforeLearning, matching: "pass")
                .first == 0,
               "an explicit alias remains stronger than learned query behavior")

        // Two rows with one id is undefined behaviour in a SwiftUI list, and
        // the list is stitched from six providers plus whatever was saved.
        suite.expect(CommandBarSearch.firstOccurrences(of: ["a", "b", "a", "c", "b"]) == [0, 1, 3],
               "a repeated id keeps the better ranked row and drops the other")
        suite.expect(CommandBarSearch.firstOccurrences(of: []).isEmpty, "an empty list stays empty")
        suite.expect(CommandBarSearch.firstOccurrences(of: ["a", "b"]) == [0, 1],
               "a list with nothing repeated is left alone")

        // A combination tied to one row of the bar.
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option, .command])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option, .command])
        let commandPeriod = GlobalShortcut(keyCode: 47, modifiers: [.command])
        var bound = CommandBarRowShortcuts.setting(optionB, for: "app.bundle.a", in: [:])
        suite.expect(bound["app.bundle.a"] == optionB, "a row answers to the keys it was given")
        suite.expect(CommandBarRowShortcuts.assignmentIssue(optionB, for: "app.bundle.a", in: bound) == nil,
               "recording an app's existing shortcut is allowed")
        suite.expect(CommandBarRowShortcuts.assignmentIssue(optionB, for: "app.bundle.b", in: bound)
                == .occupied("app.bundle.a"),
               "the app editor names an occupied shortcut before replacing another app's binding")
        suite.expect(CommandBarRowShortcuts.assignmentIssue(
                    GlobalShortcut(keyCode: 11, modifiers: []), for: "app.bundle.a", in: bound) == .invalid,
               "an app shortcut cannot take an ordinary typing key even when editing an existing binding")
        bound = CommandBarRowShortcuts.setting(optionB, for: "app.bundle.b", in: bound)
        suite.expect(bound["app.bundle.b"] == optionB && bound["app.bundle.a"] == nil,
               "the same keys move to the last row that asked; two rows never share one")
        suite.expect(CommandBarRowShortcuts.setting(nil, for: "app.bundle.b", in: bound).isEmpty,
               "taking the keys off leaves nothing behind")
        suite.expect(CommandBarRowShortcuts.key(for: optionB, in: bound) == "app.bundle.b"
                && CommandBarRowShortcuts.key(for: optionN, in: bound) == nil,
               "a press is routed to the row that owns it")
        suite.expect(CommandBarRowShortcuts.isUsable(optionB)
                && !CommandBarRowShortcuts.isUsable(GlobalShortcut(keyCode: 11, modifiers: [])),
               "a bare letter is never taken from every app on the Mac")
        suite.expect(CommandBarRowShortcuts.decode(CommandBarRowShortcuts.encode(bound)) == bound,
               "the bindings survive a round trip through storage")
        let emojiBinding = CommandBarRowShortcuts.setting(
            commandPeriod, for: CommandBarPreferences.emojiBrowserRowID, in: [:])
        suite.expect(CommandBarRowShortcuts.key(for: commandPeriod, in: emojiBinding)
                == CommandBarPreferences.emojiBrowserRowID,
               "the Emoji browser row can own a global shortcut like any other row")
        var full: [String: GlobalShortcut] = [:]
        for index in 0..<CommandBarRowShortcuts.limit {
            full["row.\(index)"] = GlobalShortcut(keyCode: Int64(index), modifiers: [.control])
        }
        suite.expect(!CommandBarRowShortcuts.hasRoom(for: "row.new", in: full)
                && CommandBarRowShortcuts.hasRoom(for: "row.0", in: full)
                && CommandBarRowShortcuts.hasRoom(for: "row.new", in: [:]),
               "a full list says so before the keys are taken, and rebinding is always allowed")
        suite.expect(CommandBarRowShortcuts.assignmentIssue(optionN, for: "row.new", in: full) == .full
                && CommandBarRowShortcuts.assignmentIssue(optionN, for: "row.0", in: full) == nil,
               "the app editor reports a full list while still allowing existing shortcuts to change")
        let appBindings = ["app.bundle.a": optionB, "app.bundle.b": optionN]
        var pendingApp = CommandBarRowShortcuts.PendingAppLaunch()
        pendingApp.schedule("app.bundle.a", in: appBindings)
        suite.expect(pendingApp.take(in: appBindings, isAvailable: true) == "app.bundle.a"
                && pendingApp.take(in: appBindings, isAvailable: true) == nil,
               "an app shortcut waiting for its first catalog runs exactly once")
        pendingApp.schedule("app.bundle.a", in: appBindings)
        pendingApp.schedule("app.bundle.b", in: appBindings)
        suite.expect(pendingApp.take(in: appBindings, isAvailable: true) == "app.bundle.b",
               "the latest app shortcut replaces an earlier request while the catalog loads")
        pendingApp.schedule("app.bundle.a", in: appBindings)
        suite.expect(pendingApp.take(in: [:], isAvailable: true) == nil,
               "removing a shortcut while apps load cancels its pending launch")
        pendingApp.schedule("app.bundle.a", in: appBindings)
        suite.expect(pendingApp.take(in: ["app.bundle.a": optionN], isAvailable: true) == nil,
               "changing a shortcut while apps load cannot run its previous binding")
        pendingApp.schedule("app.bundle.a", in: appBindings)
        suite.expect(pendingApp.take(in: appBindings, isAvailable: false) == nil
                && pendingApp.take(in: appBindings, isAvailable: true) == nil,
               "disabling the feature discards the deferred launch rather than postponing it")
        pendingApp.schedule("app.bundle.a", in: appBindings)
        pendingApp.cancel()
        suite.expect(pendingApp.take(in: appBindings, isAvailable: true) == nil,
               "suspending shortcuts or running another command cancels a queued app launch")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.commandBarRowShortcuts,
                    DefaultsKey.commandBarAliases, DefaultsKey.commandBarPins]),
               "the app center reuses shortcut, alias and favorite preferences carried by settings backups")
        suite.expect(CommandBarRowShortcuts.isUsable(
                    GlobalShortcut(keyCode: Int64(kVK_ANSI_Q), modifiers: [.command])),
               "Command Q is a real combination; the card has to be able to store it")
        let commandBarSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/CommandBar/CommandBarService.swift",
            encoding: .utf8)) ?? ""
        let commandBarCode = commandBarSource
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let monitorParts = (commandBarCode
            .components(separatedBy: "private func installMonitors(for panel: NSPanel)")
            .last ?? "").components(separatedBy: "\n    private func ")
        let monitor = monitorParts.first ?? ""
        suite.expect(monitorParts.count > 1
                && monitor.contains("? event.charactersIgnoringModifiers")
                && monitor.contains(": event.characters)?.lowercased()")
                && monitor.contains("let key = event.charactersIgnoringModifiers?.lowercased()")
                && !monitor.contains("case kVK_ANSI_Q")
                && monitor.contains("digitIndex(for: event.keyCode)"),
               "the Command Bar uses macOS Command letters while Control follows typed letters and digits stay positional")
        suite.expect(monitor.contains("#selector(NSText.selectAll(_:))")
                && monitor.contains("#selector(NSText.copy(_:))")
                && monitor.contains("#selector(NSText.cut(_:))")
                && monitor.contains("#selector(NSText.paste(_:))")
                && monitor.contains("NSApp.sendAction"),
               "the Command Bar sends standard editing commands through its responder chain")
        // Ends on the next declaration rather than naming a neighbour: a
        // rename would find no separator, leave the slice running to end of
        // file, and quietly restore the whole-file search.
        let captureBeginParts = (commandBarCode
            .components(separatedBy: "private func beginCapturingShortcut(")
            .last ?? "").components(separatedBy: "\n    private func ")
        let captureBegin = captureBeginParts.first ?? ""
        suite.expect(captureBeginParts.count > 1,
               "the Command Bar capture start finds the end of beginCapturingShortcut")
        suite.expect(captureBegin.contains("ShortcutCapture.begin()")
                && captureBegin.contains("ShortcutRecordingTap.begin"),
               "the capture card starts the same pair Settings uses, so Command Q reaches it")
        let captureEndParts = (commandBarCode
            .components(separatedBy: "private func endCapturingShortcut()")
            .last ?? "").components(separatedBy: "\n    private func ")
        let captureEnd = captureEndParts.first ?? ""
        suite.expect(captureEndParts.count > 1,
               "the Command Bar capture stop finds the end of endCapturingShortcut")
        suite.expect(captureEnd.contains("ShortcutRecordingTap.end()")
                && captureEnd.contains("ShortcutCapture.end()"),
               "leaving the card gives the keyboard back")

        // Dates and places, answered by the calendar this Mac carries.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "UTC")!
        let english = Locale(identifier: "en_US")
        let tuesday = Date(timeIntervalSince1970: 1_785_240_000)   // 2026-07-28
        func dated(_ input: String, _ locale: Locale = english) -> String? {
            CommandBarDates.evaluate(input, now: tuesday, calendar: gregorian, locale: locale)?.formatted
        }
        suite.expect(dated("in 3 weeks") == "August 18, 2026",
               "three weeks from now is a date, not a search")
        suite.expect(dated("daqui 10 dias", Locale(identifier: "pt_BR")) == "7 de agosto de 2026",
               "the same question in the person's own words, written their way")
        suite.expect(dated("3 days ago") == "July 25, 2026" && dated("ha 3 dias") == "July 25, 2026",
               "backwards counts backwards, before or after the number")
        suite.expect(dated("today + 10 days") == "August 7, 2026"
                && dated("today - 10 days") == "July 18, 2026",
               "a plain sign decides the direction")
        suite.expect(dated("3 days") == nil && dated("2+2") == nil && dated("100 km to mi") == nil,
               "without a direction it is not a question, and a sum is not a date")
        suite.expect(CommandBarDates.evaluate("in 3 weeks", now: tuesday, calendar: gregorian,
                                        locale: english)?.detail == "Tuesday",
               "the answer says which weekday it lands on")
        suite.expect(dated("days until 12/25")?.contains("150") == true,
               "how far away a written date is, counted in whole days")
        suite.expect(CommandBarDates.evaluate("time in tokyo", now: tuesday, calendar: gregorian,
                                        locale: english)?.detail.hasPrefix("Tokyo") == true,
               "the clock somewhere else, from the time zones the Mac already knows")
        suite.expect(CommandBarDates.evaluate("hora em londres", now: tuesday, calendar: gregorian,
                                        locale: english)?.detail.hasPrefix("London") == true,
               "a city named the way the person's language names it")
        suite.expect(CommandBarDates.evaluate("time", now: tuesday, calendar: gregorian,
                                        locale: english) == nil,
               "a time word with nowhere to look is not an answer")
        // The gate is the whole safety of this: anything a person might be
        // searching for that happens to carry a number must fall through.
        for innocent in ["1password", "2 monitors", "3 tags", "notes", "day one",
                         "5 minutes", "2026-07-28", "the 3 body problem"] {
            suite.expect(CommandBarDates.evaluate(innocent, now: tuesday, calendar: gregorian,
                                            locale: english) == nil,
                   "\"\(innocent)\" is a search, not a date")
        }

        // The places the person saves themselves.
        suite.expect(CommandBarLinks.expand("https://x.com/search?q={query}", kind: .link,
                                      query: "café com leite")
                == "https://x.com/search?q=caf%C3%A9%20com%20leite",
               "what goes into a web address is escaped")
        suite.expect(CommandBarLinks.expand("~/Projects/{query}", kind: .place, query: "my folder")
                == "~/Projects/my folder",
               "a path is not a URL and is never escaped")
        suite.expect(CommandBarLinks.expand("https://x.com/{clipboard}", kind: .link,
                                      clipboard: "a+b") == "https://x.com/a%2Bb",
               "a plus sign inside a search is escaped, not read as a space")
        suite.expect(CommandBarLinks.trailingArgument(query: "gh vorssaint utils", name: "gh")
                == "vorssaint utils",
               "what comes after the name is what the saved search opens with")
        suite.expect(CommandBarLinks.trailingArgument(query: "GH Vorssaint", name: "gh") == "Vorssaint",
               "the name is matched without case; the argument keeps its own")
        suite.expect(CommandBarLinks.trailingArgument(query: "ghost writer", name: "gh") == nil
                && CommandBarLinks.trailingArgument(query: "gh", name: "gh") == nil,
               "a longer word is not the name, and the name alone is not an argument")
        suite.expect(CommandBarLinks.trailingArgument(query: "bd\u{3000}123", name: "bd") == "123",
               "a full-width space separates the name from its argument")
        suite.expect(CommandBarLink(name: "gh", kind: .link, destination: "https://x/{query}").takesQuery
                && !CommandBarLink(name: "a", kind: .link, destination: "https://x").takesQuery,
               "a destination that waits for a query is a search")
        suite.expect(CommandBarLinks.url(for: CommandBarLink(name: "a", kind: .link, destination: "x.com"),
                                   expanded: "x.com")?.scheme == "https",
               "a destination pasted without a scheme is still a site")
        suite.expect(CommandBarLinks.decode(CommandBarLinks.encode([
            CommandBarLink(name: "", kind: .link, destination: "x"),
            CommandBarLink(name: "ok", kind: .link, destination: "x"),
        ])).count == 1, "a half-written shortcut never survives a round trip")
        // MARK: The other names macOS knows an app by
        suite.expect(SpotlightNamesSupport.usableAlternateNames(["Legacy Planner", "Planner.app"],
                                                          displayName: "Planner",
                                                          fileName: "Planner.app")
                == ["Legacy Planner"],
               "a real alias is kept and the bundle's own file name is not")
        suite.expect(SpotlightNamesSupport.usableAlternateNames(
                ["Preferences", "Settings", "Configuration.app", "Previous Settings",
                 "Configuration"],
                displayName: "Configuration",
                fileName: "Configuration.app")
                == ["Preferences", "Settings", "Previous Settings"],
               "an alias repeating the name under the icon teaches the search nothing")
        suite.expect(SpotlightNamesSupport.usableAlternateNames(["ALTERNATE_NAME_1", "  ", "browser"],
                                                          displayName: "Navigator",
                                                          fileName: "Navigator.app") == ["browser"],
               "an untranslated placeholder is not a name anybody types")
        suite.expect(SpotlightNamesSupport.usableAlternateNames(["Café", "cafe"],
                                                          displayName: "Reader",
                                                          fileName: "Reader.app") == ["Café"],
               "two aliases that differ only by accent or case are one alias")

        suite.expect(CommandBarLinks.revealPath(for: CommandBarLink(name: "notes", kind: .place,
                                                              destination: "~/Notes"))
                == NSHomeDirectory() + "/Notes",
               "a saved folder can be shown where it lives")
        suite.expect(CommandBarLinks.revealPath(for: CommandBarLink(name: "site", kind: .link,
                                                              destination: "https://example.invalid")) == nil,
               "a site has no place on the disk to show")
        suite.expect(CommandBarLinks.revealPath(for: CommandBarLink(name: "day", kind: .place,
                                                              destination: "~/Notes/{date}.md")) == nil,
               "a place still holding a placeholder is a different file every time it runs")
        suite.expect(CommandBarLinks.rankingTitle(name: "gh", query: "gh vorssaint utils")
                == "gh vorssaint utils",
               "once an argument follows the name, the row is scored against the whole query")
        suite.expect(CommandBarLinks.rankingTitle(name: "gh", query: "gh") == "gh",
               "the name alone still scores against its own name")
        suite.expect(CommandBarLinks.rankingTitle(name: "gh", query: "ghost writer") == "gh",
               "a word that only starts with the name is not an argument, so scoring is untouched")
        // The defect itself: scored against its own name, a saved search left
        // the list on the first word of the argument, which is the moment it
        // was about to run.
        suite.expect(CommandBarSearch.score(title: "gh", keywords: "Link",
                                      query: "gh vorssaint utils") == nil
                && CommandBarSearch.score(
                    title: CommandBarLinks.rankingTitle(name: "gh", query: "gh vorssaint utils"),
                    keywords: "Link", query: "gh vorssaint utils") != nil,
               "a saved search stays in the list while what to look for is typed")

        suite.expect(CommandBarLink.Kind.script.symbolName == "terminal",
               "a script link gets its own icon")
        suite.expect(CommandBarLink(name: "cur", kind: .script, destination: "/tmp/x").takesArgument
                && !CommandBarLink(name: "a", kind: .place, destination: "/tmp").takesArgument,
               "a script always takes its argument; a plain place or link does not")
        suite.expect(CommandBarLink(name: "gh", kind: .link, destination: "https://x/{query}").takesArgument,
               "a query link still takes its argument through the existing placeholder check")
        suite.expect(CommandBarLinks.url(for: CommandBarLink(name: "cur", kind: .script,
                                                        destination: "/tmp/x"),
                                   expanded: "/tmp/x") == nil,
               "a script has nothing to open")
        let scriptLinks = [
            CommandBarLink(name: "a", kind: .link, destination: "https://x"),
            CommandBarLink(name: "cur", kind: .script, destination: "/tmp/currency-convert.sh"),
        ]
        suite.expect(CommandBarLinks.matchingScriptLink(in: scriptLinks, query: "cur 100 usd eur")?.argument
                == "100 usd eur",
               "a script link matches once something follows its name")
        suite.expect(CommandBarLinks.matchingScriptLink(in: scriptLinks, query: "cur") == nil,
               "the bare name alone has nothing to run yet")
        let bareRunnable = [
            CommandBarLink(name: "clean", kind: .script, destination: "/tmp/clean",
                           runsWithoutArgument: true),
        ]
        suite.expect(CommandBarLinks.matchingScriptLink(in: bareRunnable, query: "clean")?.argument == "",
               "a script marked as needing nothing runs on its bare name")
        suite.expect(CommandBarLinks.matchingScriptLink(in: bareRunnable, query: "  Clean  ")?.argument
                == "",
               "the bare name is matched the same way every other name is")
        suite.expect(CommandBarLinks.matchingScriptLink(in: bareRunnable, query: "clean code")?.argument
                == "code",
               "that same script still receives an argument when one is typed")
        suite.expect(CommandBarLinks.matchingScriptLink(in: bareRunnable, query: "cle") == nil
                && CommandBarLinks.matchingScriptLink(in: bareRunnable, query: "cleaner") == nil,
               "a script never runs off a prefix of its name, or a longer word starting with it")
        // The list drops a script's own row once the answer row stands in for
        // it. That has to use the same rule that decided the script would run,
        // or a bare name shows the script twice: once as an answer and once as
        // the plain row nothing removed.
        suite.expect(CommandBarLinks.matchingScriptLinks(in: bareRunnable, query: "clean")
                .map(\.name) == ["clean"],
               "a bare-name match is dropped from the list, like any other script match")
        suite.expect(CommandBarLinks.matchingScriptLinks(in: scriptLinks, query: "cur 100 usd eur")
                .map(\.name) == ["cur"],
               "a script named with an argument is dropped from the list")
        suite.expect(CommandBarLinks.matchingScriptLinks(in: scriptLinks, query: "cur").isEmpty
                && CommandBarLinks.matchingScriptLinks(in: scriptLinks, query: "a 1").isEmpty,
               "nothing is dropped for a script that did not match, or for a non-script link")
        suite.expect(CommandBarLinks.matchingScriptLink(in: scriptLinks, query: "a 100 usd eur") == nil,
               "a non-script link never matches, even with an argument")
        let overlappingScripts = [
            CommandBarLink(name: "run", kind: .script, destination: "/tmp/short"),
            CommandBarLink(name: "run report", kind: .script, destination: "/tmp/specific"),
        ]
        suite.expect(CommandBarLinks.matchingScriptLink(in: overlappingScripts,
                                                   query: "run report today")?.link.name
                == "run report",
               "the most specific script name wins over a shorter prefix")
        suite.expect(CommandBarLinks.matchingScriptLinks(in: overlappingScripts, query: "run report x")
                .map(\.name).sorted() == ["run", "run report"],
               "both overlapping names are dropped, so only the answer row is left")
        suite.expect(CommandBarLinks.resultText("  100 USD = 86.70 EUR\n") == "100 USD = 86.70 EUR",
               "a script's output loses its wrapping whitespace")
        suite.expect(CommandBarLinks.resultText("   \n") == nil,
               "empty output means nothing is ready yet")

        let savedBeforeTheField = #"[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","name":"gh","#
            + #""kind":"link","destination":"https://x"}]"#
        let loadedOldShortcuts = CommandBarLinks.decode(Data(savedBeforeTheField.utf8))
        suite.expect(loadedOldShortcuts.count == 1 && loadedOldShortcuts.first?.name == "gh"
                && loadedOldShortcuts.first?.runsWithoutArgument == false,
               "a shortcut saved before runsWithoutArgument existed still loads, defaulting to off")
        let roundTripped = CommandBarLinks.decode(
            CommandBarLinks.encode([CommandBarLink(name: "clean", kind: .script,
                                                   destination: "/tmp/clean",
                                                   runsWithoutArgument: true)]))
        suite.expect(roundTripped.first?.runsWithoutArgument == true,
               "the flag survives being saved and loaded again")

        // MARK: Open what was typed as a URL
        for address in ["example.com", "example.com/x", "https://example.com",
                        "example.com:8080/path", "http://example.com/path?q=1",
                        "sub.domain.co.uk", "https://example.museum", "https://例子.中国"] {
            suite.expect(CommandBarLinks.typedURL(address) != nil,
                   "\"\(address)\" reads like a URL")
        }
        for plain in ["hello", "file.txt", "3.14", "version 2.0", "notes",
                      "a b c", "", "  ", "v1.2", "localhost",
                      "user@example.com", "something/else", "https://", "http:notes",
                      "https://exa mple.com", "ftp://files.example.org"] {
            suite.expect(CommandBarLinks.typedURL(plain) == nil,
                   "\"\(plain)\" is a search, not a URL")
        }
        suite.expect(CommandBarLinks.typedURL("example.com")?.absoluteString == "https://example.com",
               "a typed bare domain is opened with an https scheme")
        suite.expect(CommandBarLinks.typedURL("example.com:8080/path")?.absoluteString
                == "https://example.com:8080/path",
               "a port on a bare domain does not become a fake scheme")
        suite.expect(CommandBarLinks.typedURL("https://example.com/x")?.absoluteString
                == "https://example.com/x",
               "a typed address with a scheme keeps its scheme")

        suite.expect(CommandBarText.wordCount("uma frase com cinco palavras") == 5
                && CommandBarText.wordCount("  espaços   demais  ") == 2
                && CommandBarText.wordCount("") == 0,
               "words are counted the way a person counts them")
        suite.expect(CommandBarText.characterCount("café") == 4,
               "an accented letter is one character, not two")
        suite.expect(CommandBarText.preview("uma linha\ncom quebra") == "uma linha com quebra",
               "a preview of a paragraph stays on one line")
        suite.expect(CommandBarText.preview(String(repeating: "a", count: 60), limit: 10)
                == String(repeating: "a", count: 10) + "…",
               "a long selection is cut with an ellipsis")
        suite.expect(CommandBarText.changesCase("abc", to: { $0.localizedUppercase })
                && !CommandBarText.changesCase("ABC", to: { $0.localizedUppercase }),
               "a case row is only offered when the case would change")

        suite.expect(CommandBarSearch.splitTrailingNumber("brilho 40")
                == CommandBarNumberSplit(text: "brilho", number: 40),
               "a trailing number splits off the verb")
        suite.expect(CommandBarSearch.splitTrailingNumber("volume 20%")
                == CommandBarNumberSplit(text: "volume", number: 20),
               "a percent sign on the number is fine")
        suite.expect(CommandBarSearch.splitTrailingNumber("brilho")
                == CommandBarNumberSplit(text: "brilho", number: nil),
               "a bare verb carries no number")
        suite.expect(CommandBarSearch.splitTrailingNumber("40")
                == CommandBarNumberSplit(text: "40", number: nil),
               "a number alone is a search, not a command")
        suite.expect(CommandBarSearch.splitTrailingNumber("manter acordado 30")
                == CommandBarNumberSplit(text: "manter acordado", number: 30),
               "multi-word verbs keep their words")
        suite.expect(CommandBarSearch.argumentValue("40", in: 0...100) == 40
                && CommandBarSearch.argumentValue("140", in: 0...100) == 100
                && CommandBarSearch.argumentValue("35%", in: 0...100) == 35
                && CommandBarSearch.argumentValue("abc", in: 0...100) == nil
                && CommandBarSearch.argumentValue("", in: 0...100) == nil,
               "inline arguments accept digits, clamp and reject the rest")

        let barNow: Double = 1_800_000_000
        var barUsage: [String: CommandBarUse] = [:]
        barUsage = CommandBarUsage.recording(barUsage, id: "action.screenshot", now: barNow)
        barUsage = CommandBarUsage.recording(barUsage, id: "action.screenshot", now: barNow + 10)
        barUsage = CommandBarUsage.recording(barUsage, id: "action.darkMode", now: barNow + 20)
        suite.expect(barUsage["action.screenshot"]?.count == 2
                && barUsage["action.screenshot"]?.lastUsed == barNow + 10,
               "recording a run counts it and stamps the time")
        let barEncoded = CommandBarUsage.encode(barUsage)
        suite.expect(CommandBarUsage.decode(barEncoded) == barUsage,
               "usage survives the round trip")
        suite.expect(CommandBarUsage.decode("not json").isEmpty && CommandBarUsage.decode(nil).isEmpty,
               "corrupt usage decodes as a clean slate")
        var crowded: [String: CommandBarUse] = [:]
        for index in 0..<(CommandBarUsage.storedIDLimit + 5) {
            crowded = CommandBarUsage.recording(crowded, id: "app.\(index)", now: barNow + Double(index))
        }
        suite.expect(crowded.count == CommandBarUsage.storedIDLimit && crowded["app.0"] == nil
                && crowded["app.\(CommandBarUsage.storedIDLimit + 4)"] != nil,
               "the usage store caps by dropping the oldest ids")
        suite.expect(CommandBarUsage.boost(for: CommandBarUse(count: 3, lastUsed: barNow), now: barNow + 60)
                > CommandBarUsage.boost(for: CommandBarUse(count: 3, lastUsed: barNow), now: barNow + 30 * 86400),
               "a habit fades as it ages")
        suite.expect(CommandBarUsage.boost(for: CommandBarUse(count: 999, lastUsed: barNow), now: barNow) < 700,
               "no habit outruns a literal text hit")
        suite.expect(CommandBarUsage.boost(for: nil, now: barNow) == 0,
               "no usage, no boost")
        let categoryOrder = CommandBarUsage.categoryIDs(
            usage: [
                "emoji.fire": CommandBarUse(count: 3, lastUsed: barNow),
                "emoji.heart": CommandBarUse(count: 3, lastUsed: barNow + 10),
                "emoji.wave": CommandBarUse(count: 1, lastUsed: barNow + 20),
            ],
            available: ["emoji.grin", "emoji.fire", "emoji.wave", "emoji.heart", "emoji.star"])
        suite.expect(categoryOrder == [
            "emoji.heart", "emoji.fire", "emoji.wave", "emoji.grin", "emoji.star",
        ], "empty categories lead with frequent and recent choices, then keep catalog order")
        suite.expect(CommandBarUsage.categoryIDs(usage: [:],
                                           available: ["emoji.grin", "emoji.fire", "emoji.wave"])
                == ["emoji.grin", "emoji.fire", "emoji.wave"],
               "an unlearned category preserves its useful catalog order")

        let officialHabitService = CommandBarQueryHabits.installationKeyService(
            bundleID: "com.vorssaint.utils")
        let developerHabitService = CommandBarQueryHabits.installationKeyService(
            bundleID: "com.vorssaint.utils.dev")
        suite.expect(officialHabitService == "com.vorssaint.utils.command-bar-query-habits"
                && officialHabitService != developerHabitService,
               "uninstalling one app variant cannot target the other variant's query key")

        let habitKey = Data(repeating: 0x31, count: 32)
        let otherHabitKey = Data(repeating: 0x72, count: 32)
        for shortQuery in ["w", "wa"] {
            let prepared = CommandBarQueryHabits.prepare(shortQuery, key: habitKey)
            let recorded = CommandBarQueryHabits.recording(
                [:], preparedQuery: prepared, resultID: "app.whatever", now: barNow)
            let restored = CommandBarQueryHabits.decode(CommandBarQueryHabits.encode(recorded))
            suite.expect(CommandBarQueryHabits.boost(
                for: "app.whatever", preparedQuery: prepared, store: restored, now: barNow) > 0,
                "one- and two-character choices survive a storage round trip")
        }
        let preparedWhat = CommandBarQueryHabits.prepare("what", key: habitKey)
        let preparedWhatever = CommandBarQueryHabits.prepare("whatever", key: habitKey)
        var queryHabits: CommandBarQueryHabits.Store = [:]
        queryHabits = CommandBarQueryHabits.recording(
            queryHabits, preparedQuery: preparedWhat,
            resultID: "app./Applications/Whatever.app", now: barNow)
        queryHabits = CommandBarQueryHabits.recording(
            queryHabits, preparedQuery: preparedWhat,
            resultID: "app./Applications/Whatever.app", now: barNow + 10)
        let learnedExact = CommandBarQueryHabits.boost(
            for: "app./Applications/Whatever.app", preparedQuery: preparedWhat,
            store: queryHabits, now: barNow + 20)
        let learnedRelated = CommandBarQueryHabits.boost(
            for: "app./Applications/Whatever.app", preparedQuery: preparedWhatever,
            store: queryHabits, now: barNow + 20)
        suite.expect(learnedExact > 0 && learnedRelated > 0,
               "repeated choices teach the exact query and a longer related query")
        suite.expect(CommandBarQueryHabits.boost(
                    for: "app./Applications/Whatever Beta.app", preparedQuery: preparedWhat,
                    store: queryHabits,
                    now: barNow + 20) == 0,
               "a learned query lifts only the selected result")
        let encodedQueryHabits = CommandBarQueryHabits.encode(queryHabits)
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        let otherPreparedWhat = CommandBarQueryHabits.prepare("what", key: otherHabitKey)
        let otherKeyHabits = CommandBarQueryHabits.recording(
            [:], preparedQuery: otherPreparedWhat, resultID: "app.test", now: barNow)
        let encodedKeysAreDigests = queryHabits.keys.allSatisfy { key in
            key.count == 24 && key.unicodeScalars.allSatisfy(hexadecimal.contains)
        }
        let keysAreInstallationSpecific = Set(queryHabits.keys)
            .isDisjoint(with: Set(otherKeyHabits.keys))
        let habitsRoundTrip = CommandBarQueryHabits.decode(encodedQueryHabits) == queryHabits
        suite.expect(encodedKeysAreDigests && preparedWhat.keyCount == 4
                && keysAreInstallationSpecific && habitsRoundTrip,
               "query habits round-trip as per-install keyed digests, prepared once per query")
        suite.expect(CommandBarQueryHabits.removing(
                    resultID: "app./Applications/Whatever.app", from: queryHabits).isEmpty,
               "forgetting a result removes its learned query choices")

        var maximumHabitStore: CommandBarQueryHabits.Store = [:]
        for queryIndex in 0..<CommandBarQueryHabits.storedQueryLimit {
            let queryKey = String(format: "%024x", queryIndex)
            var choices: [String: CommandBarUse] = [:]
            for resultIndex in 0..<4 {
                choices["app.\(resultIndex)"] = CommandBarUse(
                    count: resultIndex + 1,
                    lastUsed: barNow + Double(queryIndex * 4 + resultIndex))
            }
            maximumHabitStore[queryKey] = choices
        }
        let maximumHabitPayload = CommandBarQueryHabits.encode(maximumHabitStore)
        var habitDecodeCount = 0
        var habitStoreCache = CommandBarQueryHabitStoreCache()
        habitStoreCache.reload(maximumHabitPayload) { raw in
            habitDecodeCount += 1
            return CommandBarQueryHabits.decode(raw)
        }
        for length in 3...24 {
            let prepared = CommandBarQueryHabits.prepare(
                String("abcdefghijklmnopqrstuvwx".prefix(length)), key: habitKey)
            _ = CommandBarQueryHabits.boost(
                for: "app.0", preparedQuery: prepared,
                store: habitStoreCache.store, now: barNow)
        }
        suite.expect(habitDecodeCount == 1 && habitStoreCache.store.count == 320,
               "a maximum learned-query store is decoded once, not once per keystroke")

        var digestCount = 0
        var preparationCache = CommandBarQueryHabits.PreparationCache()
        var lastPrepared = CommandBarQueryHabits.prepare("", key: habitKey)
        for length in 3...24 {
            lastPrepared = CommandBarQueryHabits.prepare(
                String("abcdefghijklmnopqrstuvwx".prefix(length)),
                key: habitKey,
                cache: &preparationCache) { prefix, _ in
                    digestCount += 1
                    return String(repeating: "0", count: 24 - String(prefix.count).count)
                        + String(prefix.count)
                }
        }
        suite.expect(digestCount == 24 && lastPrepared.keyCount == 24,
               "extending a query hashes only each newly-added prefix")
        _ = CommandBarQueryHabits.prepare(
            "abcdefghijkl", key: habitKey, cache: &preparationCache) { _, _ in
                digestCount += 1
                return "unused"
            }
        suite.expect(digestCount == 24,
               "deleting from a prepared query reuses its matching prefix slice")

        habitStoreCache.forgetAll()
        suite.expect(habitStoreCache.store.isEmpty,
               "forgetting all learned choices clears the decoded store immediately")
        habitStoreCache.record(preparedQuery: preparedWhat,
                               resultID: "action.screenshot", now: barNow)
        suite.expect(!habitStoreCache.store.isEmpty,
               "recording any durable result updates the decoded store immediately")
        habitStoreCache.remove(resultID: "action.screenshot")
        suite.expect(habitStoreCache.store.isEmpty,
               "forgetting one result updates the decoded store immediately")
        habitStoreCache.reload(encodedQueryHabits)
        suite.expect(habitStoreCache.store == queryHabits,
               "reloading preferences replaces the decoded store with persisted learning")

        let persistedHabitKey = Data(repeating: 0x44, count: 32)
        var keyReads: [(OSStatus, Data?)] = [(errSecSuccess, persistedHabitKey)]
        var generatedKeyCount = 0
        var addedKeyCount = 0
        var updatedKeyCount = 0
        func habitKeyStore() -> CommandBarQueryHabitKeyStore {
            CommandBarQueryHabitKeyStore(
                read: { keyReads.removeFirst() },
                randomKey: {
                    generatedKeyCount += 1
                    return persistedHabitKey
                },
                add: { _ in addedKeyCount += 1; return errSecSuccess },
                update: { _ in updatedKeyCount += 1; return errSecSuccess })
        }
        suite.expect(CommandBarQueryHabits.loadInstallationKey(using: habitKeyStore())
                == persistedHabitKey
                && generatedKeyCount == 0 && addedKeyCount == 0 && updatedKeyCount == 0,
               "a valid stored query key is used without mutation")

        keyReads = [(errSecInteractionNotAllowed, nil)]
        suite.expect(CommandBarQueryHabits.loadInstallationKey(using: habitKeyStore()) == nil
                && generatedKeyCount == 0,
               "a transient Keychain read error never creates an ephemeral query key")

        keyReads = [(errSecItemNotFound, nil), (errSecSuccess, persistedHabitKey)]
        suite.expect(CommandBarQueryHabits.loadInstallationKey(using: habitKeyStore())
                == persistedHabitKey && generatedKeyCount == 1 && addedKeyCount == 1,
               "a new query key is published only after successful read-back")

        keyReads = [(errSecItemNotFound, nil), (errSecSuccess, persistedHabitKey)]
        let duplicateStore = CommandBarQueryHabitKeyStore(
            read: { keyReads.removeFirst() },
            randomKey: { Data(repeating: 0x55, count: 32) },
            add: { _ in errSecDuplicateItem },
            update: { _ in errSecInternalError })
        suite.expect(CommandBarQueryHabits.loadInstallationKey(using: duplicateStore)
                == persistedHabitKey,
               "a duplicate-item race uses the other writer's persisted query key")

        keyReads = [(errSecSuccess, Data([0x01]))]
        let failedRepairStore = CommandBarQueryHabitKeyStore(
            read: { keyReads.removeFirst() },
            randomKey: { persistedHabitKey },
            add: { _ in errSecInternalError },
            update: { _ in errSecInteractionNotAllowed })
        suite.expect(CommandBarQueryHabits.loadInstallationKey(using: failedRepairStore) == nil,
               "a malformed query key is not replaced or published when repair fails")

        keyReads = [(errSecSuccess, Data([0x01])), (errSecSuccess, persistedHabitKey)]
        let repairedStore = CommandBarQueryHabitKeyStore(
            read: { keyReads.removeFirst() },
            randomKey: { persistedHabitKey },
            add: { _ in errSecInternalError },
            update: { _ in errSecSuccess })
        suite.expect(CommandBarQueryHabits.loadInstallationKey(using: repairedStore)
                == persistedHabitKey,
               "a repaired query key is published only after successful read-back")

        keyReads = [(errSecItemNotFound, nil)]
        let randomFailureStore = CommandBarQueryHabitKeyStore(
            read: { keyReads.removeFirst() },
            randomKey: { nil },
            add: { _ in errSecSuccess },
            update: { _ in errSecSuccess })
        suite.expect(CommandBarQueryHabits.loadInstallationKey(using: randomFailureStore) == nil,
               "random generation failure leaves query learning without a key")

        keyReads = [(errSecItemNotFound, nil)]
        let addFailureStore = CommandBarQueryHabitKeyStore(
            read: { keyReads.removeFirst() },
            randomKey: { persistedHabitKey },
            add: { _ in errSecInteractionNotAllowed },
            update: { _ in errSecSuccess })
        suite.expect(CommandBarQueryHabits.loadInstallationKey(using: addFailureStore) == nil,
               "a failed query-key insert never publishes its random candidate")

        let loadStarted = DispatchSemaphore(value: 0)
        let letLoadFinish = DispatchSemaphore(value: 0)
        let cache = CommandBarQueryHabitKeyCache(
            queue: DispatchQueue(label: "org.vorssaint.tests.command-bar-query-key")) {
                loadStarted.signal()
                letLoadFinish.wait()
                return persistedHabitKey
            }
        let keyReady = DispatchSemaphore(value: 0)
        cache.warm { keyReady.signal() }
        suite.expect(loadStarted.wait(timeout: .now() + 1) == .success && cache.cachedKey == nil,
               "query-key warm-up never waits on the typing path")
        letLoadFinish.signal()
        suite.expect(keyReady.wait(timeout: .now() + 1) == .success
                && cache.cachedKey == persistedHabitKey,
               "a background query-key load publishes a validated key and announces readiness")

        let removalQueue = DispatchQueue(label: "org.vorssaint.tests.query-key-removal")
        let removalLoadStarted = DispatchSemaphore(value: 0)
        let finishRemovalLoad = DispatchSemaphore(value: 0)
        let removedKeyReady = DispatchSemaphore(value: 0)
        var keyLifecycle: [String] = []
        let removalCache = CommandBarQueryHabitKeyCache(queue: removalQueue) {
            keyLifecycle.append("load started")
            removalLoadStarted.signal()
            finishRemovalLoad.wait()
            keyLifecycle.append("load finished")
            return persistedHabitKey
        }
        removalCache.warm { removedKeyReady.signal() }
        suite.expect(removalLoadStarted.wait(timeout: .now() + 1) == .success,
               "the uninstall race starts with a key load in flight")
        let keyRemoval = removalCache.stopAndRemove { keyLifecycle.append("removed") }
        removalCache.warm { removedKeyReady.signal() }
        finishRemovalLoad.signal()
        suite.expect(keyRemoval.wait(timeout: .now() + 1) == .success,
               "uninstall waits for key deletion after the pending load")
        removalCache.warm { removedKeyReady.signal() }
        removalQueue.sync {}
        suite.expect(keyLifecycle == ["load started", "load finished", "removed"]
                && removalCache.cachedKey == nil
                && removedKeyReady.wait(timeout: .now()) == .timedOut,
               "uninstall suppresses readiness and later warm-ups without recreating the key")

        var retryCount = 0
        let retryCache = CommandBarQueryHabitKeyCache(
            queue: DispatchQueue(label: "org.vorssaint.tests.command-bar-query-key-retry")) {
                retryCount += 1
                return retryCount == 1 ? nil : persistedHabitKey
            }
        retryCache.warm()
        let secondRetryDeadline = Date().addingTimeInterval(1)
        while retryCache.cachedKey == nil && Date() < secondRetryDeadline {
            retryCache.warm()
            Thread.sleep(forTimeInterval: 0.001)
        }
        suite.expect(retryCount == 2 && retryCache.cachedKey == persistedHabitKey,
               "a failed query-key warm-up remains retryable")
        let completedEmoji = CommandBarCompletion.completedQuery(
            current: ":fire", title: "🔥  fire", matchTitle: "fire")
        suite.expect(completedEmoji == ":fire"
                && CommandBarSearch.emojiQuery(from: completedEmoji) == "fire",
               "Tab completion retains emoji scope and the searchable name")
        for categoryQuery in ["fir", ""] {
            let completedCategoryEmoji = CommandBarCompletion.completedQuery(
                current: categoryQuery, title: "🔥  fire", matchTitle: "fire")
            suite.expect(completedCategoryEmoji == "fire"
                    && CommandBarSearch.emojiQuery(from: completedCategoryEmoji) == nil
                    && CommandBarSearch.rankedIndexes(
                        candidates: [CommandBarCandidate(index: 0, title: "fire")],
                        matching: completedCategoryEmoji) == [0],
                   "Tab keeps a selected Emoji category result searchable from a query or browse")
        }
        suite.expect(CommandBarCompletion.completedQuery(
            current: "whts", title: "Whatever", matchTitle: nil) == "Whatever",
               "ordinary Tab completion still uses the selected title")
        let learnedCompletion = CommandBarCompletion.queryForLearning(
            current: "Whatever", beforeCompletion: "whts")
        let retainedCompletion = CommandBarCompletion.retainedOriginal(
            "whts", completedValue: "Whatever", afterChangingTo: "Whatever")
        let editedCompletion = CommandBarCompletion.retainedOriginal(
            "whts", completedValue: "Whatever", afterChangingTo: "Whatever b")
        suite.expect(learnedCompletion == "whts" && retainedCompletion == "whts"
                && editedCompletion == nil,
               "Tab remembers the fuzzy search unless the completed field is edited")

        let learningDefaultsName = "com.vorssaint.tests.command-bar-learning"
        let learningDefaults = UserDefaults(suiteName: learningDefaultsName)!
        learningDefaults.set("usage", forKey: DefaultsKey.commandBarUsage)
        learningDefaults.set("habits", forKey: DefaultsKey.commandBarQueryHabits)
        CommandBarLearning.forgetAll(in: learningDefaults)
        suite.expect(learningDefaults.object(forKey: DefaultsKey.commandBarUsage) == nil
                && learningDefaults.object(forKey: DefaultsKey.commandBarQueryHabits) == nil,
               "forgetting all learned use clears usage and query choices together")
        learningDefaults.removePersistentDomain(forName: learningDefaultsName)

        let barSuggestions = CommandBarUsage.suggestionIDs(
            usage: barUsage,
            available: ["action.screenshot", "action.darkMode", "action.colorPicker", "action.ocr"],
            curated: ["action.colorPicker", "action.gone", "action.ocr"],
            limit: 3)
        suite.expect(barSuggestions == ["action.screenshot", "action.darkMode", "action.colorPicker"],
               "suggestions lead with the most used and fill with curated ones")
        suite.expect(CommandBarUsage.suggestionIDs(usage: [:],
                                             available: ["a", "b"],
                                             curated: ["c", "b", "a"],
                                             limit: 5) == ["b", "a"],
               "curated suggestions skip whatever is unavailable")

        // The ranking folds what was typed once and hands the folded letters to
        // every row in the pool. Both readings have to agree, or a name the
        // person gave would rank differently depending on which one asked.
        var foldedMemory = CommandBarQueryMemory()
        suite.expect(foldedMemory.boost(normalizedQuery: "pri", id: "app.primary") == 0,
               "a memory holding nothing is worth nothing for folded letters either")
        foldedMemory.record(query: "Primary", id: "app.primary", step: 1)
        suite.expect(foldedMemory.boost(normalizedQuery: CommandBarSearch.normalized("PRÍ"),
                                  id: "app.primary") > 0
                && foldedMemory.boost(normalizedQuery: CommandBarSearch.normalized("PRÍ"),
                                      id: "app.primary")
                    == foldedMemory.boost(query: "PRÍ", id: "app.primary"),
               "folded letters ask the query memory the same question the raw ones do")
        suite.expect(CommandBarPreferences.aliasHit(
                    "Códex", normalizedQuery: CommandBarSearch.normalized("CÓD")) == .prefix
                && CommandBarPreferences.aliasHit(
                    "Códex", normalizedQuery: CommandBarSearch.normalized("CÓD"))
                    == CommandBarPreferences.aliasHit("Códex", query: "CÓD"),
               "folded letters ask an alias the same question the raw ones do")

        // Both background passes guard on a few fields of a tuple they store
        // whole. Returning before the store would leave every field the guard
        // does not name at the reading it had when the named ones last moved.
        for (pass, marker) in [("refreshStorageAnswer", "cachedBootVolumeSpace = space"),
                               ("refreshSystemAnswers", "cachedMemory = memory")] {
            let parts = (commandBarCode
                .components(separatedBy: "private func \(pass)(").last ?? "")
                .components(separatedBy: "\n    private func ")
            let body = parts.first ?? ""
            suite.expect(parts.count > 1, "\(pass) finds the end of its own body")
            func offset(_ needle: String) -> Int {
                body.range(of: needle)
                    .map { body.distance(from: body.startIndex, to: $0.lowerBound) } ?? -1
            }
            let stored = offset(marker)
            let guarded = offset("guard changed else { return }")
            suite.expect(stored >= 0 && guarded > stored,
                   "\(pass) stores the whole sample before it decides whether the rows changed")
        }

    }
}
