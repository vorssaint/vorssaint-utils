// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation

enum CommandBarTests {
    static func run(expect: (Bool, String) -> Void) {
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

        expect(math("2+2") == "4", "the calculator answers a sum")
        expect(math("10 * 4.5") == "45", "spaces and decimals are fine")
        expect(math("(2+3)*4") == "20", "parentheses come first")
        expect(math("2+3*4") == "14", "multiplication binds tighter than addition")
        expect(math("10/4") == "2.5", "division keeps its decimals")
        expect(math("2^3^2") == "512", "powers group to the right")
        expect(math("-5+2") == "-3", "a leading minus is a sign, not an error")
        expect(math("--5+1") == "6", "two minuses cancel")
        expect(math("1920/2") == "960", "the everyday case works")
        expect(mathValue("0.1+0.2") == 0.3 && math("0.1+0.2") == "0.3",
               "floating point noise never reaches the eye")
        expect(math("1,000+1") == "1,001", "grouped thousands parse and print grouped")
        expect(math("2 x 3") == "6" && math("10 ÷ 2") == "5" && math("2 × 3") == "6",
               "the written multiplication and division signs work too")
        expect(math("2(3+4)") == "14" && math("(1+2)(3+4)") == "21",
               "a number against a parenthesis multiplies")
        expect(math("-2^2") == "-4", "a sign applies to the whole power, as on paper")
        expect(math("2^0.5")?.hasPrefix("1.41421") == true, "a fractional power is fine")
        expect(math("1/1000000000") == "1e-9", "a billionth reads as a billionth, not as zero")
        expect(math("2^100")?.contains("e") == true, "a huge answer switches notation instead of vanishing")
        expect(math("2026-07-27") == nil && math("27/07/2026") == nil && math("10:30") == nil,
               "a date or a time is never answered as a sum")
        expect(math("100-50") == "50", "two numbers around a minus are still a subtraction")
        expect(math("SDL_VIDEODRIVER=") == nil && math("x=5") == nil,
               "an assignment shape is not an expression")
        expect(math("7+3=") == "10", "a trailing equals sign is just habit")

        expect(math("480+15%") == "552", "a percentage after plus is relative")
        expect(math("480-15%") == "408", "and after minus too")
        expect(math("20% of 480") == "96", "percent of a number reads as it is said")
        expect(math("20% de 480") == "96", "the same in the other words people type")
        expect(math("50%") == nil, "a lone percentage is not a question")
        expect(math("200*10%") == "20", "a percentage multiplies as a fraction")

        expect(math("5") == nil, "a lone number is a search, not an answer")
        expect(math("hello") == nil, "words are not expressions")
        expect(math("1password") == nil, "an app name that starts with a digit stays a search")
        expect(math("volume 20") == nil, "a command with a number is not a sum")
        expect(math("brilho 40") == nil, "neither is the same command in another language")
        expect(math("10/0") == nil, "dividing by zero has no answer to show")
        expect(math("2+") == nil && math("(2+3") == nil && math("2++") == nil,
               "an unfinished expression stays quiet")
        expect(math("2 * -3") == "-6", "a sign after an operator is read as a sign")
        expect(math(String(repeating: "(", count: 60) + "1" + String(repeating: ")", count: 60)) == nil,
               "a wall of parentheses is refused instead of eating the stack")
        expect(math("e-mail") == nil, "a hyphenated word is not a subtraction")
        expect(math("9999999999999999*99")?.contains("e") == true,
               "a number past plain reading switches notation")

        // The same numbers as the owner's Mac writes them.
        expect(CommandBarMath.evaluate("1.234,5 + 1",
                                       decimalSeparator: ",",
                                       groupingSeparator: ".",
                                       locale: Locale(identifier: "pt_BR"))?.formatted == "1.235,5",
               "a comma decimal parses and prints back in the same shape")
        expect(CommandBarMath.evaluate("1,5*2",
                                       decimalSeparator: ",",
                                       groupingSeparator: ".",
                                       locale: Locale(identifier: "pt_BR"))?.value == 3,
               "the comma is the decimal point where that is the custom")
        expect(math("1.500+1", decimal: ",", grouping: ".") == "1,501",
               "three digits after the grouping separator read as thousands")

        // MARK: Command bar, what the person controls

        expect(CommandBarSource.allCases.map(\.rawValue) == [
            "actions", "apps", "menus", "windows", "quitApps", "settingsPages", "macSettings",
            "snippets", "clipboard", "emoji", "folders", "answers", "calculator",
            "selection", "links", "files", "killProcess",
        ], "source ids are stable (they persist inside the disabled list)")
        expect(CommandBarSource.actions.isAlwaysOn
                && CommandBarSource.allCases.filter(\.isAlwaysOn).count == 1,
               "only the app's own actions cannot be switched off")
        expect(CommandBarClipboardAccess.canUseHistory(captureEnabled: true,
                                                       hasSavedItems: false),
               "clipboard capture makes the command bar history available")
        expect(CommandBarClipboardAccess.canUseHistory(captureEnabled: false,
                                                       hasSavedItems: true),
               "saved clipboard items stay available when capture is off")
        expect(!CommandBarClipboardAccess.canUseHistory(captureEnabled: false,
                                                        hasSavedItems: false),
               "an empty disabled clipboard still points to setup")
        let japaneseClipboard = FeatureStrings.clipboard(.ja)
        let clipboardClearKeywords = [japaneseClipboard.title,
                                      ClipboardFeatureStrings.enUS.title,
                                      ClipboardFeatureStrings.enUS.clearRecent]
            .joined(separator: " ")
        expect(CommandBarSearch.matches(title: japaneseClipboard.clearRecent,
                                        keywords: clipboardClearKeywords,
                                        query: "clear clipboard"),
               "the clipboard clear action stays findable by its English name in a non-Latin locale")
        let commandBarCatalogLines = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift",
            encoding: .utf8)) ?? "").components(separatedBy: "\n")
        let clipboardActionsCode = commandBarCatalogLines.firstIndex {
            isCodeLine($0) && $0.contains("if AppFeature.clipboardHistory.isAvailable {")
        }.map {
            commandBarCatalogLines[$0...]
                .prefix { !$0.contains("if AppFeature.textSnippets.isAvailable {") }
                .filter(isCodeLine)
                .joined(separator: "\n")
        } ?? ""
        expect(clipboardActionsCode.contains("id: \"action.clipboardClearRecent\"")
                && clipboardActionsCode.contains("title: clipboard.clearRecent")
                && clipboardActionsCode.contains("confirmationPrompt: clipboard.clearRecent")
                && clipboardActionsCode.contains("ClipboardHistoryService.shared.clearRecent()"),
               "the Command Bar clears only unpinned clipboard items after confirmation")

        // MARK: Compact mode, what an empty field shows
        expect(CommandBarHome.showsBrowseList(compact: false, hasCategory: false, isPeeking: false),
               "the browse list is what an ordinary empty bar shows")
        expect(!CommandBarHome.showsBrowseList(compact: true, hasCategory: false, isPeeking: false),
               "a compact bar draws no list until something is typed")
        expect(CommandBarHome.showsBrowseList(compact: true, hasCategory: true, isPeeking: false),
               "a category is an explicit drill-in and always shows its rows")
        expect(CommandBarHome.showsBrowseList(compact: true, hasCategory: false, isPeeking: true),
               "a peek is the person asking for the list anyway")
        expect(CommandBarHome.isCollapsed(compact: true, query: "",
                                          hasCategory: false, isPeeking: false),
               "an empty compact field is the whole panel")
        expect(CommandBarHome.isCollapsed(compact: true, query: "   ",
                                          hasCategory: false, isPeeking: false),
               "whitespace is not something typed")
        expect(!CommandBarHome.isCollapsed(compact: true, query: "fire",
                                           hasCategory: false, isPeeking: false),
               "one letter brings the list and the footer back")
        expect(!CommandBarHome.isCollapsed(compact: true, query: "",
                                           hasCategory: true, isPeeking: false),
               "a category keeps the panel open")
        expect(!CommandBarHome.isCollapsed(compact: true, query: "",
                                           hasCategory: false, isPeeking: true),
               "a peeked bar is not collapsed either")
        expect(!CommandBarHome.isCollapsed(compact: false, query: "",
                                           hasCategory: false, isPeeking: false),
               "the ordinary bar is never collapsed")
        expect(Defaults.registeredDefaults[DefaultsKey.commandBarCompactMode] as? Bool == false,
               "compact mode ships off: the browse list is how the bar introduces itself")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarCompactMode),
               "compact mode is configuration, so it travels with an exported setup")
        expect(SettingsBackupSupport.valueLooksRight(DefaultsKey.commandBarCompactMode, true)
                && !SettingsBackupSupport.valueLooksRight(DefaultsKey.commandBarCompactMode, "yes"),
               "a restored compact mode has to be a switch, not text that looks like one")

        // MARK: What the bar noticed about this session
        expect(CommandBarQueryMemory.prefixes(of: "wha") == ["w", "wh", "wha"],
               "choosing a row for what was typed also answers every shorter piece of it")
        expect(CommandBarQueryMemory.prefixes(of: "  Résumé ")
                == ["r", "re", "res", "resu", "resum", "resume"],
               "what is remembered is folded the way the ranking folds, accents and all")
        expect(CommandBarQueryMemory.prefixes(of: "   ").isEmpty,
               "an empty field teaches nothing")
        expect(CommandBarQueryMemory.prefixes(of: String(repeating: "a", count: 40)).count
                == CommandBarQueryMemory.longestPrefix,
               "past a word's worth of letters the ranking already knows what to do")

        var barMemory = CommandBarQueryMemory()
        expect(barMemory.isEmpty && barMemory.boost(query: "pri", id: "app.primary") == 0,
               "a row never chosen for these letters is worth nothing extra")
        barMemory.record(query: "primary", id: "app.primary", step: 1)
        expect(barMemory.boost(query: "pri", id: "app.primary") > 0
                && barMemory.boost(query: "pri", id: "app.other") == 0
                && barMemory.boost(query: "prim", id: "app.primary") > 0,
               "the row chosen for a word answers to the letters on the way to it")
        expect(barMemory.boost(query: "primary extra", id: "app.primary") == 0,
               "letters that were never typed on their own teach nothing")
        barMemory.record(query: "primary", id: "app.primary", step: 2)
        barMemory.record(query: "primary", id: "app.primary", step: 3)
        barMemory.record(query: "primary", id: "app.primary", step: 4)
        expect(barMemory.boost(query: "pri", id: "app.primary")
                == CommandBarQueryMemory.maximumBoost,
               "choosing the same row again stops adding up once it is certain")
        let keywordPrefixScore = CommandBarSearch.score(title: "Other",
                                                        keywords: "primary",
                                                        query: "pri") ?? 0
        let keywordExactScore = CommandBarSearch.score(title: "Other",
                                                       keywords: "pri",
                                                       query: "pri") ?? 0
        expect(keywordPrefixScore + CommandBarQueryMemory.maximumBoost < keywordExactScore,
               "what the bar noticed reorders ties and never beats a better keyword match")
        barMemory.forget(id: "app.primary")
        expect(barMemory.isEmpty, "forgetting one row takes it out of every prefix")
        barMemory.record(query: "a", id: "one", step: 1)
        barMemory.clear()
        expect(barMemory.isEmpty, "and the whole session can be forgotten at once")
        // Five rows compete for one prefix; the least chosen is the one that
        // stops being remembered.
        var crowdedPrefix = CommandBarQueryMemory()
        for index in 0..<(CommandBarQueryMemory.idsPerQuery + 1) {
            for repeatCount in 0...(index == 0 ? 0 : 3) {
                crowdedPrefix.record(query: "x", id: "row.\(index)", step: index * 10 + repeatCount)
            }
        }
        expect(crowdedPrefix.boost(query: "x", id: "row.0") == 0
                && crowdedPrefix.boost(query: "x", id: "row.4") > 0,
               "one prefix remembers a few rows, and the one picked least drops out")

        // MARK: Finding a file from the bar
        expect(CommandBarFileSearchSupport.expression(for: "annual report")
                == "kMDItemFSName == \"*annual*\"cd && kMDItemFSName == \"*report*\"cd",
               "every word has to be in the name, in any order")
        expect(CommandBarFileSearchSupport.expression(for: "a") == nil
                && CommandBarFileSearchSupport.expression(for: "   ") == nil,
               "one letter is not a search, so Spotlight is never asked")
        expect(CommandBarFileSearchSupport.escaped("re*port") == "re\\*port"
                && CommandBarFileSearchSupport.escaped("say \"hi\"") == "say \\\"hi\\\"",
               "a wildcard somebody typed is the character, not a wider search")
        let searchableDirectories: Set<String> = [
            "/Users/x/Notes", "/Users/x/Documents", "/tmp",
        ]
        expect(CommandBarFileSearchSupport.resolvedScopes(
                ["~/Notes", "~/Notes/", "~/single.txt", "/tmp"],
                homeDirectory: "/Users/x",
                homeChildren: [],
                isSearchableDirectory: searchableDirectories.contains)
                == ["/Users/x/Notes", "/tmp"],
               "saved scopes are live directories, deduplicated after tilde expansion")
        expect(CommandBarFileSearchSupport.resolvedScopes(
                ["~"],
                homeDirectory: "/Users/x",
                homeChildren: ["Documents", "Library", ".ssh", "single.txt", "Archive.pkg"],
                isSearchableDirectory: searchableDirectories.contains)
                == ["/Users/x/Documents"],
               "home expands only to visible ordinary directories, never files or packages")
        expect(CommandBarFileSearchSupport.resolvedScopes(
                [], homeDirectory: "/Users/x", homeChildren: ["Documents"],
                isSearchableDirectory: searchableDirectories.contains).isEmpty,
               "a list the person cleared searches nothing, instead of searching everything")
        let packagePaths: Set<String> = [
            "/Applications/Utility.app", "/Users/x/Notes/Archive.unknownpackage",
        ]
        expect(CommandBarFileSearchSupport.isOfferable(
                    path: "/Users/x/Notes/plan.md", isPackage: packagePaths.contains)
                && !CommandBarFileSearchSupport.isOfferable(
                    path: "/Users/x/.ssh/config", isPackage: packagePaths.contains)
                && !CommandBarFileSearchSupport.isOfferable(
                    path: "/Users/x/Notes/.draft.md", isPackage: packagePaths.contains),
               "a hidden file, and anything under a hidden folder, is never offered")
        expect(CommandBarFileSearchSupport.isOfferable(
                    path: "/Applications/Utility.app", isPackage: packagePaths.contains)
                && !CommandBarFileSearchSupport.isOfferable(
                    path: "/Applications/Utility.app/Contents/Info.plist",
                    isPackage: packagePaths.contains)
                && !CommandBarFileSearchSupport.isOfferable(
                    path: "/Users/x/Notes/Archive.unknownpackage/data/item",
                    isPackage: packagePaths.contains),
               "filesystem package metadata seals known and future package types")
        expect(CommandBarFileSearchSupport.isIgnored(path: "/x/node_modules/a/index.js",
                                                     patterns: ["node_modules"])
                && !CommandBarFileSearchSupport.isIgnored(path: "/x/rebuild-notes.md",
                                                          patterns: ["build"]),
               "a name never worth showing matches a whole name, never half of one")
        expect(CommandBarFileSearchSupport.isIgnored(path: "/x/run.log", patterns: ["*.log"])
                && CommandBarFileSearchSupport.isIgnored(path: "/x/run.log", patterns: [".log"])
                && !CommandBarFileSearchSupport.isIgnored(path: "/x/log", patterns: [".log"]),
               "an extension written either way takes out the kind of file, not a folder called log")
        expect(CommandBarFileSearchSupport.offerable(
            paths: ["/x/a.md", "/x/a.md", "/x/.hidden", "/x/node_modules/b.js", "/x/c.md"],
            patterns: ["node_modules"],
            isPackage: { _ in false }) == ["/x/a.md", "/x/c.md"],
               "one path is one row, and what is filtered stays filtered")
        expect(CommandBarFileSearchSupport.shouldPublishResult(for: "new", currentQuery: "new")
                && !CommandBarFileSearchSupport.shouldPublishResult(
                    for: "old", currentQuery: "new")
                && !CommandBarFileSearchSupport.shouldPublishResult(
                    for: "old", currentQuery: nil),
               "a cancelled or superseded asynchronous search never refreshes the visible bar")
        expect(CommandBarFileSearchSupport.decodeList(" a \n\n b \na") == ["a", "b"]
                && CommandBarFileSearchSupport.encodeList(["a", "", "a", "b"]) == "a\nb",
               "the saved lists never repeat themselves and survive a round trip")
        expect(CommandBarFileSearchSupport.abbreviating("/Users/x/Notes", homeDirectory: "/Users/x")
                == "~/Notes"
                && CommandBarFileSearchSupport.abbreviating("/tmp/a", homeDirectory: "/Users/x")
                == "/tmp/a",
               "a path is written the short way only where it really is inside home")
        expect(CommandBarFileSearchSupport.candidateLimit >= CommandBarFileSearchSupport.resultLimit,
               "more names are asked for than are shown, since most are filtered away")
        expect(Defaults.registeredDefaults[DefaultsKey.commandBarFileScopes] as? String == ""
                && Defaults.registeredDefaults[DefaultsKey.commandBarFileIgnores] as? String == "",
               "out of the box the bar has been given no folder, so it looks for no files")
        expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarFileScopes)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarFileIgnores),
               "folder authority stays on one Mac while ignored names remain portable")
        let fileSearchBackup = SettingsBackupSupport.sanitizedSettings(from: [
            SettingsBackupSupport.formatVersionKey: SettingsBackupSupport.formatVersion,
            SettingsBackupSupport.settingsKey: [
                DefaultsKey.commandBarFileScopes: "~/Documents",
                DefaultsKey.commandBarFileIgnores: "*.log",
            ],
        ])
        expect(fileSearchBackup?[DefaultsKey.commandBarFileScopes] == nil
                && fileSearchBackup?[DefaultsKey.commandBarFileIgnores] as? String == "*.log",
               "a backup restores ignored names but never grants a folder on another Mac")
        let invalidFileSearchBackup = SettingsBackupSupport.sanitizedSettings(from: [
            SettingsBackupSupport.formatVersionKey: SettingsBackupSupport.formatVersion,
            SettingsBackupSupport.settingsKey: [
                DefaultsKey.commandBarFileScopes: 42,
                DefaultsKey.commandBarFileIgnores: false,
            ],
        ])
        expect(invalidFileSearchBackup?.isEmpty == true,
               "a backup cannot restore non-text file search preferences")
        expect(CommandBarPreferences.rankBias(for: .files)
                    < CommandBarPreferences.rankBias(for: .actions)
                && CommandBarPreferences.rankBias(for: .apps)
                    > CommandBarPreferences.rankBias(for: .actions),
               "apps lead commands, while a file needs a plainly better match")

        // MARK: The Mac's own Settings panes
        let openablePane: [String: Any] = [
            "EXAppExtensionAttributes": [
                "SettingsExtensionAttributes": [
                    "allowsXAppleSystemPreferencesURLScheme": true,
                    "legacyPrefPaneBundleName": "Legacy.prefPane",
                ],
            ],
        ]
        expect(CommandBarSystemSettingsSupport.isOpenablePane(info: openablePane),
               "a pane that answers to the system settings address is one the bar can open")
        expect(!CommandBarSystemSettingsSupport.isOpenablePane(info: [
            "EXAppExtensionAttributes": [
                "SettingsExtensionAttributes": ["allowsXAppleSystemPreferencesURLScheme": false],
            ],
        ]) && !CommandBarSystemSettingsSupport.isOpenablePane(info: ["CFBundleName": "Thumbnails"]),
               "a thumbnailer, and a pane with no address, are not rows")
        expect(CommandBarSystemSettingsSupport.legacyPaneName(info: openablePane)
                == "Legacy.prefPane"
                && CommandBarSystemSettingsSupport.legacyPaneName(info: ["a": 1]) == nil,
               "the older pane is followed only where the newer one names it")
        expect(CommandBarSystemSettingsSupport.paneName(localizedDisplayName: "Coverage & Support",
                                                        displayName: "CoveragePane_Internal",
                                                        bundleName: "Coverage",
                                                        fileName: "CoverageSettings.appex")
                == "Coverage & Support",
               "a pane is called what System Settings calls it")
        expect(CommandBarSystemSettingsSupport.paneName(localizedDisplayName: nil,
                                                        displayName: "  ",
                                                        bundleName: nil,
                                                        fileName: "VPN.appex") == "VPN",
               "a pane that declares no name at all still gets one")
        // Every pane names its own groups, so all of them are read, in a fixed
        // order: one Mac and the next must produce the same words.
        expect(CommandBarSystemSettingsSupport.keywords(fromSearchTerms: [
            "bSection": ["localizableStrings": [["title": "Brillo", "index": "aclarar, atenuar"]]],
            "aSection": ["localizableStrings": [["title": "Alinear", "index": "espejo,  , Alinear"]]],
        ]) == "Alinear espejo Brillo aclarar atenuar",
               "the words a pane answers to are read from every group and never repeat")
        expect(CommandBarSystemSettingsSupport.keywords(fromSearchTerms: ["Main": "not a group"])
                .isEmpty,
               "a search index in a shape nobody recognizes is no words, not a crash")
        expect(CommandBarSystemSettingsSupport.keywords(fromSearchTerms: [
            "a": ["localizableStrings": [["title": "one", "index": "two, three"]]],
        ], limit: 2) == "one two",
               "one pane never contributes more words than the ranking can use")
        let longPaneTerms = (1...45).map { ["title": "term\($0)", "index": ""] }
        expect(CommandBarSystemSettingsSupport.keywords(fromSearchTerms: [
            "Main": ["localizableStrings": longPaneTerms],
        ]).contains("term45"),
               "important terms beyond the old forty-word cutoff remain searchable")
        expect(Set(AppLanguage.allCases.map(CommandBarSystemSettingsSupport.resourceFolder)).count
                == AppLanguage.allCases.count,
               "each language reads its own words, so no two share a folder")

        expect(CommandBarPreferences.source(ofRowID: "app.x") == .apps
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
        expect(CommandBarPreferences.isEnabled(.folders, disabledRaw: "folders,emoji") == false
                && CommandBarPreferences.isEnabled(.apps, disabledRaw: "folders,emoji") == true
                && CommandBarPreferences.isEnabled(.actions, disabledRaw: "actions") == true,
               "a switched off source stays off, and actions never can be")
        expect(CommandBarPreferences.storageValue(for: [.emoji, .folders, .actions])
                == "emoji,folders",
               "the disabled list writes the same way every time")
        expect(CommandBarPreferences.disabledSources(from: "folders, nonsense ,emoji")
                == Set([.folders, .emoji]),
               "an unknown source id is dropped instead of corrupting the set")

        var barAliases = CommandBarPreferences.settingAlias("codex", for: "app./Applications/Chat.app",
                                                            in: [:])
        expect(barAliases["app./Applications/Chat.app"] == "codex", "a row takes the name it was given")
        expect(CommandBarPreferences.aliasMatches("codex", query: "codex")
                && CommandBarPreferences.aliasMatches("codex", query: "cod")
                && !CommandBarPreferences.aliasMatches("codex", query: "codexx"),
               "the name matches whole or as it is being typed, never beyond it")
        expect(CommandBarPreferences.aliasMatches("meu chat codex", query: "codex"),
               "several words all find the same row")
        expect(CommandBarPreferences.aliasMatches("Códex", query: "codex"),
               "accents in a name never break it")
        barAliases = CommandBarPreferences.settingAlias("  ", for: "app./Applications/Chat.app",
                                                        in: barAliases)
        expect(barAliases.isEmpty, "clearing the field removes the name")
        expect(CommandBarPreferences.decodeAliases(
                CommandBarPreferences.encodeAliases(["a": "one", "b": "two"])) == ["a": "one", "b": "two"],
               "names survive the round trip")
        expect(CommandBarPreferences.decodeAliases("not json").isEmpty,
               "a corrupt name list decodes as none")
        expect(CommandBarPreferences.acceptsAlias(rowID: "app.x")
                && !CommandBarPreferences.acceptsAlias(rowID: "menu.1.Bold")
                && !CommandBarPreferences.acceptsAlias(rowID: "window.4")
                && !CommandBarPreferences.acceptsAlias(rowID: "clipboard.abc"),
               "only rows that are the same thing tomorrow can be named")

        var barPins = CommandBarPreferences.togglingPin("action.screenshot", in: [])
        barPins = CommandBarPreferences.togglingPin("app.chat", in: barPins)
        expect(barPins == ["action.screenshot", "app.chat"], "pins keep the order they were made in")
        expect(CommandBarPreferences.togglingPin("action.screenshot", in: barPins) == ["app.chat"],
               "the same gesture unpins")
        expect(CommandBarPreferences.leadingPins(["app.chat", "app.gone"],
                                                 available: ["app.chat", "action.a"])
                == ["app.chat"],
               "the empty bar leads with the pins that still exist")
        expect(CommandBarPreferences.listedPins(
                    ["action.cleaningMode", "app.chat", "settings.cleaningMode"],
                    present: ["app.chat"])
                == ["app.chat"],
               "an uninstalled feature is not listed as a pin")
        expect(CommandBarPreferences.listedPins(
                    ["action.cleaningMode", "app.gone"],
                    present: ["action.cleaningMode"])
                == ["action.cleaningMode", "app.gone"],
               "an app that left this Mac still appears so its pin can be removed")
        expect(CommandBarPreferences.pinTieBreak < 700,
               "a pin breaks a tie and never jumps over a better match")
        expect(CommandBarPreferences.aliasHit("codex", query: "codex") == .exact
                && CommandBarPreferences.aliasHit("codex", query: "cod") == .prefix
                && CommandBarPreferences.aliasHit("codex", query: "zzz") == nil,
               "a finished name outranks one still being typed")
        expect(CommandBarPreferences.AliasHit.exact.rawValue > 1200
                && CommandBarPreferences.AliasHit.prefix.rawValue > 900,
               "the name the person gave beats the app's own title")
        expect(CommandBarPreferences.rowUsingAlias("codex", in: ["app.a": "codex"], excluding: "app.b")
                == "app.a",
               "a name already taken is reported instead of being stolen")
        expect(CommandBarPreferences.rowUsingAlias("codex", in: ["app.a": "codex"], excluding: "app.a")
                == nil,
               "renaming a row never conflicts with itself")
        var barHidden = CommandBarPreferences.togglingHidden("app.x", in: [])
        expect(barHidden == ["app.x"], "a row can be told never to show")
        barHidden = CommandBarPreferences.togglingHidden("app.x", in: barHidden)
        expect(barHidden.isEmpty, "and told to come back")
        expect(CommandBarPreferences.decodeHidden(
                CommandBarPreferences.encodeHidden(["b", "a"])) == ["a", "b"],
               "hidden rows survive the round trip")
        expect(CommandBarPreferences.decodePins(CommandBarPreferences.encodePins(["a", "b"])) == ["a", "b"]
                && CommandBarPreferences.decodePins("a\na\n\nb") == ["a", "b"],
               "pins survive the round trip and never repeat")
        let positionOffset = CGSize(width: -24.4, height: 80.6)
        expect(CommandBarPreferences.decodePositionOffset(
            CommandBarPreferences.encodePositionOffset(positionOffset))
            == CGSize(width: -24, height: 81),
               "the command bar position offset survives a rounded round trip")
        for invalidOffset in ["", "12", "12,", "12,nope", "12,nope,20", "nan,1", "inf,1"] {
            expect(CommandBarPreferences.decodePositionOffset(invalidOffset) == .zero,
                   "an invalid command bar position offset is ignored (\(invalidOffset))")
        }
        expect(CommandBarPreferences.encodePositionOffset(.zero).isEmpty
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
        expect(upperRight == CGPoint(x: -576, y: 504)
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

        expect(unitValue("100 km to mi").map { abs($0 - 62.1371) < 0.001 } == true,
               "a distance converts")
        expect(unitValue("20 c to f").map { abs($0 - 68) < 0.001 } == true,
               "a temperature converts as an absolute reading, not as a step")
        expect(unitValue("0 c to f").map { abs($0 - 32) < 0.001 } == true,
               "freezing reads as freezing")
        expect(unitValue("5 gb to mb").map { abs($0 - 5000) < 0.001 } == true,
               "storage uses the decimal units it is written with")
        expect(unitValue("1 gib to mib").map { abs($0 - 1024) < 0.001 } == true,
               "and the binary ones when those are written instead")
        expect(unitValue("100km to mi").map { abs($0 - 62.1371) < 0.001 } == true,
               "the number and the unit do not need a space between them")
        expect(unitValue("5 in to cm").map { abs($0 - 12.7) < 0.001 } == true,
               "the word that also means inches is read correctly on both sides")
        expect(unitValue("2 h to min").map { abs($0 - 120) < 0.001 } == true,
               "hours become minutes")
        expect(unitValue("1 kg to lb").map { abs($0 - 2.20462) < 0.001 } == true,
               "mass converts")
        expect(unitValue("1.5 l to ml").map { abs($0 - 1500) < 0.001 } == true,
               "a decimal amount converts")
        expect(units("100 km to kg") == nil, "two different families never meet")
        expect(units("100 km") == nil, "without the word there is no conversion")
        expect(units("to") == nil && units("in") == nil,
               "the little words alone convert nothing")
        expect(units("safari to dock") == nil, "plain words are not units")
        expect(units("5 xyz to cm") == nil, "an unknown unit is refused, never guessed")
        expect(units("minutes to read the article") == nil,
               "a sentence that happens to contain a unit word stays a search")
        expect(CommandBarUnits.convert("1,5 m to cm",
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
        expect(unitNumbers(units("180 cm to ft")) == ["5", "10.87"],
               "a length converting to feet keeps precise feet and inches")
        expect(unitNumbers(units("1.75 m to ft")) == ["5", "8.9"],
               "a decimal length keeps its fractional inches")
        expect(unitNumbers(units("6 ft to ft")) == ["6"],
               "a whole number of feet has no leftover inches shown")
        expect(unitNumbers(units("5.9999 ft to ft")) == ["6"],
               "inches that round up to twelve carry into the next whole foot")
        expect(unitNumbers(units("2 cm to ft")) == ["0.0656"],
               "a length below one foot stays precise instead of rounding to inches")
        expect(unitNumbers(units("-180 cm to ft")) == ["-5.91"],
               "a negative length keeps the existing decimal format")
        expect(unitNumbers(units("180 cm to in")) == ["70.87"],
               "converting to inches specifically stays a plain decimal, unaffected by the feet formatting")
        expect(unitNumbers(CommandBarUnits.convert("180 cm para pes",
                                                   decimalSeparator: ",",
                                                   groupingSeparator: ".",
                                                   locale: Locale(identifier: "pt_BR"))?.formatted)
                == ["5", "10,87"],
               "feet and inches follow the person's number format")

        // MARK: Command bar emoji

        expect(CommandBarEmoji.emoji.count > 1_000, "the searchable Unicode emoji set is there")
        expect(CommandBarEmoji.emoji.allSatisfy { !$0.name.isEmpty && !$0.character.isEmpty },
               "every emoji carries the words that find it")
        expect(CommandBarEmoji.emoji.contains {
            $0.character == "😂" && $0.name == "face with tears of joy"
                && $0.keywords.contains("haha") && $0.keywords.contains("roflmao")
        }, "chat vocabulary finds laughter the way mainstream pickers do")
        expect(CommandBarEmoji.emoji.contains {
            $0.character == "🤷" && $0.keywords.contains("idk")
                && $0.keywords.contains("whatever")
        }, "conversational aliases find common reactions")
        expect(CommandBarEmoji.emoji.contains {
            $0.character == "🙏" && $0.keywords.contains("appreciate")
                && $0.keywords.contains("thx")
        }, "chat shorthand and intent find emoji, not only literal gestures")
        expect(CommandBarEmoji.emoji.contains { $0.name.contains("heart") },
               "the ones people look for by feeling are findable")
        expect(CommandBarEmoji.emoji.contains {
            $0.character == "💀" && $0.name == "skull" && $0.keywords.contains("dead")
        }, "common emoji answer to both Unicode names and human aliases")
        expect(CommandBarEmoji.emoji.contains {
            $0.character == "🖥️" && $0.identity == "🖥"
        }, "emoji presentation does not change a popular row's stored identity")
        expect(CommandBarEmoji.emoji.contains {
            $0.character == "❤️" && $0.identity == "❤️"
        }, "an existing selector remains part of its original row identity")
        let emojiCharacters = Set(CommandBarEmoji.emoji.map(\.character))
        expect(["©️", "™️", "✂️"].allSatisfy(emojiCharacters.contains),
               "text-default emoji get the selector that displays them as emoji")
        expect(["🌤️", "🌧️", "⛈️", "🗺️", "🖥️", "🖱️", "🖨️", "🛠️"].allSatisfy {
            emojiCharacters.contains($0) && $0.unicodeScalars.last?.value == 0xFE0F
        }, "popular text-default emoji keep their emoji presentation selector")
        expect(["#️", "*️", "0️", "9️", "🏻", "🇦", "🦰", "🦱", "🦲", "🦳"].allSatisfy {
            !emojiCharacters.contains($0)
        }, "incomplete emoji sequence components are not offered alone")
        expect(CommandBarEmoji.emoji.first?.character == "😀",
               "popular emoji keep a predictable lead over the Unicode long tail")
        expect(emojiCharacters.count == CommandBarEmoji.emoji.count,
               "no emoji is offered twice")
        expect(CommandBarSearch.emojiQuery(from: "fire") == nil,
               "an ordinary search never opens the emoji index")
        expect(CommandBarSearch.emojiQuery(from: ":fire") == "fire"
                && CommandBarSearch.emojiQuery(from: "  : heart  ") == "heart",
               "a leading colon scopes the search and stays out of the emoji query")
        expect(CommandBarSearch.emojiQuery(from: ":") == "",
               "a colon by itself opens the emoji index for browsing")

        // MARK: Command bar highlighting

        expect(CommandBarSearch.highlightOffsets(title: "Screen brightness", query: "bright")
                == Set(7..<13),
               "the matched word is marked where it really is")
        expect(CommandBarSearch.highlightOffsets(title: "Brilho da tela", query: "brilho tela")
                == Set(0..<6).union(Set(10..<14)),
               "every token gets its own mark")
        expect(CommandBarSearch.highlightOffsets(title: "Reunião com João", query: "reuniao")
                == Set(0..<7),
               "accents do not shift the marks")
        expect(CommandBarSearch.highlightOffsets(title: "Settings", query: "brlho").isEmpty,
               "a typo rescue marks nothing rather than guessing")
        expect(CommandBarSearch.highlightOffsets(title: "Empty the Trash", query: "trash")
                == Set(10..<15),
               "the mark lands on the word, not on the first letters that repeat")
        expect(CommandBarSearch.highlightOffsets(title: "Anything", query: "").isEmpty,
               "nothing typed, nothing marked")

        // MARK: Command bar wiring

        expect(Defaults.registeredDefaults[DefaultsKey.commandBarShortcutEnabled] as? Bool == false,
               "the command bar shortcut ships off like every new feature")
        expect(Defaults.registeredDefaults[DefaultsKey.commandBarShortcut] as? String
                == "option:49",
               "the default command bar shortcut is option space, the launcher convention")
        expect(Defaults.registeredDefaults[DefaultsKey.commandBarPositionOffset] as? String == "",
               "the command bar position starts at its default spot")
        expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityCommandBar] as? Bool == true,
               "the command bar panel row ships visible like its siblings")
        expect(GlobalShortcutRole.commandBar.requiredEnableKeys == [DefaultsKey.commandBarShortcutEnabled]
                && GlobalShortcutRole.commandBar.feature == .commandBar,
               "the command bar shortcut role gates on its toggle and feature")
        expect(AppFeature.commandBar.group == .tools && AppFeature.commandBar.enabledKeys.isEmpty
                && AppFeature.commandBar.permissions == [.accessibility],
               "the command bar is an on-demand tool that reads and types through accessibility")
        expect(AppFeature.commandBar.energyProfile == .idle,
               "the command bar costs nothing while closed")
        expect(pageVisible(.commandBar, available: [.commandBar])
                && !pageVisible(.commandBar, available: []),
               "the command bar page follows its hub switch")
        expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarUsage)
                && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarQueryHabits),
               "what the person runs most never travels in a backup")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarShortcutEnabled)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarShortcut)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarLinks)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarPositionOffset),
               "the command bar settings travel in backups")
    }
}
