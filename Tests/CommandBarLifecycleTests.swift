// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Foundation

enum CommandBarLifecycleTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Command bar search and ranking

        let firstBarPresentation = UUID()
        let secondBarPresentation = UUID()
        var barLifecycle = CommandBarPresentationLifecycle()
        barLifecycle.beginHome(firstBarPresentation)
        expect(barLifecycle.isLoadingHome,
               "home presents with no stale runnable rows while its catalog hydrates")
        barLifecycle.hide()
        expect(!barLifecycle.completeHomeHydration(firstBarPresentation, isVisible: false),
               "closing the panel cancels deferred hydration")

        barLifecycle.beginHome(firstBarPresentation)
        barLifecycle.beginHome(secondBarPresentation)
        expect(!barLifecycle.completeHomeHydration(firstBarPresentation, isVisible: true)
                && barLifecycle.completeHomeHydration(secondBarPresentation, isVisible: true),
               "only the latest visible home presentation may receive deferred work")
        expect(barLifecycle.acceptsHomeUpdates(secondBarPresentation, isVisible: true)
                && !barLifecycle.acceptsHomeUpdates(firstBarPresentation, isVisible: true)
                && !barLifecycle.acceptsHomeUpdates(secondBarPresentation, isVisible: false),
               "background rows update only their still-visible home presentation")
        expect(barLifecycle.acceptsSharedCacheCompletion(
                    startedBy: firstBarPresentation,
                    currentID: secondBarPresentation,
                    isVisible: true),
               "a shared cache completion refreshes the newer visible Home")
        barLifecycle.hide()
        expect(!barLifecycle.acceptsSharedCacheCompletion(
                    startedBy: firstBarPresentation,
                    currentID: secondBarPresentation,
                    isVisible: true),
               "a shared cache completion never mutates a hidden panel")

        var deferredShortcut = CommandBarDeferredRowShortcut()
        deferredShortcut.schedule("action.trash", for: firstBarPresentation)
        expect(deferredShortcut.key(for: secondBarPresentation) == nil
                && deferredShortcut.key(for: firstBarPresentation) == "action.trash"
                && deferredShortcut.take(for: secondBarPresentation) == nil
                && deferredShortcut.take(for: firstBarPresentation) == "action.trash"
                && deferredShortcut.take(for: firstBarPresentation) == nil,
               "an async row shortcut waits without being consumed, then runs once on its presentation")
        deferredShortcut.schedule("action.trash", for: firstBarPresentation)
        deferredShortcut.cancel()
        expect(deferredShortcut.take(for: firstBarPresentation) == nil,
               "closing or superseding a presentation cancels its prompt shortcut")

        expect(CommandBarSearch.normalized("  Brilho   da\tTela ") == "brilho da tela",
               "command bar folds case and collapses whitespace")
        expect(CommandBarSearch.matches(title: "Reunião com João", query: "reuniao joao"),
               "command bar search ignores accents and case")
        expect(CommandBarSearch.matches(title: "Brilho da tela", query: "brilho"),
               "a plain word finds its command")
        expect(CommandBarSearch.matches(title: "Brilho da tela", query: "Brilho"),
               "capitalized queries land in the same place")
        expect(CommandBarSearch.matches(title: "Brilho da tela", query: "brlho"),
               "a dropped letter still finds the command")
        expect(CommandBarSearch.matches(title: "Brilho da tela", query: "birlho"),
               "two swapped letters still find the command")
        expect(CommandBarSearch.matches(title: "Zen", query: "zne"),
               "a swapped pair still finds a three-letter name")
        expect(!CommandBarSearch.matches(title: "Brilho da tela", query: "volume"),
               "an unrelated word stays out")
        expect(!CommandBarSearch.matches(title: "Zen", query: "zip"),
               "short substitutions do not make unrelated names match")
        expect(CommandBarSearch.matches(title: "Capturar tela", keywords: "screenshot print", query: "print"),
               "keywords match like the title does")
        expect(CommandBarSearch.matches(title: "Capturas recentes",
                                        keywords: "Recent captures screenshot recording",
                                        query: "recent captures"),
               "recent captures stays searchable by its familiar English name")
        expect(CommandBarSearch.pinyinKeywords("云笔记") == "yunbiji ybj",
               "pinyin keywords run the syllables together and add the initials")
        expect(CommandBarSearch.pinyinKeywords("Reader").isEmpty,
               "a name without Han characters gets no pinyin keywords")
        let pinyinKeywords = CommandBarSearch.pinyinKeywords("云笔记")
        expect(CommandBarSearch.matches(title: "云笔记", keywords: pinyinKeywords,
                                        query: "yunbiji"),
               "a Chinese title is found by its pinyin")
        expect(CommandBarSearch.matches(title: "云笔记", keywords: pinyinKeywords, query: "ybj"),
               "a Chinese title is found by its pinyin initials")
        let applicationKeywords = CommandBarSearch.applicationKeywords(
            title: "云笔记", diskName: "CloudNotes", alternateNames: ["Former Notes"])
        expect(CommandBarSearch.matches(title: "云笔记", keywords: applicationKeywords,
                                        query: "cloudnotes")
                && CommandBarSearch.matches(title: "云笔记", keywords: applicationKeywords,
                                            query: "former")
                && CommandBarSearch.matches(title: "云笔记", keywords: applicationKeywords,
                                            query: "yunbiji"),
               "an app keeps its disk, alternate and phonetic names searchable")
        expect(CommandBarSearch.matches(title: "Silenciar microfone", query: "silenciar micro"),
               "tokens match in any order as prefixes")
        expect(!CommandBarSearch.matches(title: "Silenciar microfone", query: "silenciar tela"),
               "every token must land somewhere")
        expect(CommandBarSearch.isSubsequence("brlho", of: "brilho")
                && !CommandBarSearch.isSubsequence("brilhoo", of: "brilho"),
               "subsequence needs every letter in order")
        expect(CommandBarSearch.withinOneEdit("birlho", "brilho")
                && CommandBarSearch.withinOneEdit("brilo", "brilho")
                && CommandBarSearch.withinOneEdit("brilyo", "brilho")
                && !CommandBarSearch.withinOneEdit("brolyo", "brilho"),
               "one edit means one swap, one gap or one wrong letter")
        expect(CommandBarSearch.isAdjacentTransposition("zne", "zen")
                && !CommandBarSearch.isAdjacentTransposition("zne", "zone")
                && !CommandBarSearch.isAdjacentTransposition("zip", "zen"),
               "short typo tolerance accepts one neighboring swap only")

        let barCandidates = [
            CommandBarCandidate(index: 0, title: "Capturar tela"),
            CommandBarCandidate(index: 1, title: "Copiar texto da tela"),
            CommandBarCandidate(index: 2, title: "Bloquear a tela"),
            CommandBarCandidate(index: 3, title: "Manter acordado"),
        ]
        expect(CommandBarSearch.rankedIndexes(candidates: barCandidates, matching: "tela")
                == [0, 1, 2],
               "matching rows keep catalog order on equal scores")
        expect(CommandBarSearch.rankedIndexes(candidates: barCandidates, matching: "capturar tela")
                .first == 0,
               "the full title wins the top row")
        let boosted = [
            CommandBarCandidate(index: 0, title: "Capturar tela"),
            CommandBarCandidate(index: 1, title: "Copiar texto da tela", boost: 300),
        ]
        expect(CommandBarSearch.rankedIndexes(candidates: boosted, matching: "tela") == [1, 0],
               "usage boost reorders equally good matches")
        expect(CommandBarSearch.rankedIndexes(candidates: boosted, matching: "capturar") == [0],
               "a boost never resurrects a non-match")
        expect(CommandBarSearch.rankedIndexes(candidates: barCandidates, matching: " ").isEmpty,
               "a blank query ranks nothing; suggestions handle it")
        let typoCandidates = [
            CommandBarCandidate(index: 0, title: "Zebra"),
            CommandBarCandidate(index: 1, title: "Zen"),
            CommandBarCandidate(index: 2, title: "Zne Tools"),
        ]
        expect(CommandBarSearch.rankedIndexes(candidates: typoCandidates, matching: "zne")
                == [2, 1],
               "literal short matches rank above a transposition and unrelated names stay out")

        // One widely installed app carries a left-to-right mark in front of
        // its name, which made it stop being an exact match for the name it
        // shows and sink under every menu row that merely started with it.
        expect(CommandBarSearch.normalized("\u{200E}WhatsApp") == "whatsapp"
                && CommandBarSearch.normalized("Soft\u{00AD}hyphen") == "softhyphen",
               "characters that take up no space never reach the matching")
        let invisible = [
            CommandBarCandidate(index: 0, title: "WhatsApp Business (and 1 more tab)",
                                keywords: "Menu Safari History Recently Closed"),
            CommandBarCandidate(index: 1, title: "\u{200E}WhatsApp"),
        ]
        expect(CommandBarSearch.rankedIndexes(candidates: invisible, matching: "whatsapp")
                == [1, 0],
               "the app named exactly what was typed leads, invisible mark and all")
        expect(CommandBarPreferences.rankBias(for: .menus) < 0
                && CommandBarPreferences.rankBias(for: .apps)
                    > CommandBarPreferences.rankBias(for: .actions)
                && CommandBarPreferences.rankBias(for: .actions) == 0,
               "apps lead owned actions, and borrowed menu rows sit below both")
        let borrowed = [
            CommandBarCandidate(index: 0, title: "Tela cheia",
                                boost: CommandBarPreferences.rankBias(for: .menus)),
            CommandBarCandidate(index: 1, title: "Tela cheia"),
        ]
        expect(CommandBarSearch.rankedIndexes(candidates: borrowed, matching: "tela cheia")
                == [1, 0],
               "at equal quality the app's own row wins over the menu of the app in front")
        let sharper = [
            CommandBarCandidate(index: 0, title: "Fechar aba",
                                boost: CommandBarPreferences.rankBias(for: .menus)),
            CommandBarCandidate(index: 1, title: "Fechar todas as abas do navegador"),
        ]
        expect(CommandBarSearch.rankedIndexes(candidates: sharper, matching: "fechar aba")
                .first == 0,
               "the step down never buries a menu command that is what was typed")
        let appBeforeDiscovery = [
            CommandBarCandidate(index: 0, title: "What's New",
                                boost: CommandBarPreferences.rankBias(for: .settingsPages)),
            CommandBarCandidate(index: 1, title: "Whatever",
                                boost: CommandBarPreferences.rankBias(for: .apps)),
        ]
        expect(CommandBarSearch.rankedIndexes(candidates: appBeforeDiscovery, matching: "what")
                .first == 1,
               "an equally good app match leads a low-priority discovery page")
        let learnedBeforeExact = [
            CommandBarCandidate(index: 0, title: "Passwords"),
            CommandBarCandidate(index: 1, title: "Secure Pass", priority: 1),
        ]
        expect(CommandBarSearch.rankedIndexes(candidates: learnedBeforeExact, matching: "pass")
                .first == 1,
               "a learned query choice outranks an unselected stronger text match")
        let namedApp = [
            CommandBarCandidate(index: 0, title: "Editor"),
            CommandBarCandidate(index: 1, title: "Source Studio",
                                keywords: "editor", priority: 2_400),
        ]
        expect(CommandBarSearch.rankedIndexes(candidates: namedApp, matching: "editor")
                .first == 1,
               "a name deliberately given to an app still leads its ordinary title match")
        let aliasBeforeLearning = [
            CommandBarCandidate(index: 0, title: "Passwords", priority: 1_100),
            CommandBarCandidate(index: 1, title: "Secure Pass", priority: 720),
        ]
        expect(CommandBarSearch.rankedIndexes(candidates: aliasBeforeLearning, matching: "pass")
                .first == 0,
               "an explicit alias remains stronger than learned query behavior")

        // Two rows with one id is undefined behaviour in a SwiftUI list, and
        // the list is stitched from six providers plus whatever was saved.
        expect(CommandBarSearch.firstOccurrences(of: ["a", "b", "a", "c", "b"]) == [0, 1, 3],
               "a repeated id keeps the better ranked row and drops the other")
        expect(CommandBarSearch.firstOccurrences(of: []).isEmpty, "an empty list stays empty")
        expect(CommandBarSearch.firstOccurrences(of: ["a", "b"]) == [0, 1],
               "a list with nothing repeated is left alone")

        // A combination tied to one row of the bar.
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option, .command])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option, .command])
        let commandPeriod = GlobalShortcut(keyCode: 47, modifiers: [.command])
        var bound = CommandBarRowShortcuts.setting(optionB, for: "app.bundle.a", in: [:])
        expect(bound["app.bundle.a"] == optionB, "a row answers to the keys it was given")
        expect(CommandBarRowShortcuts.assignmentIssue(optionB, for: "app.bundle.a", in: bound) == nil,
               "recording an app's existing shortcut is allowed")
        expect(CommandBarRowShortcuts.assignmentIssue(optionB, for: "app.bundle.b", in: bound)
                == .occupied("app.bundle.a"),
               "the app editor names an occupied shortcut before replacing another app's binding")
        expect(CommandBarRowShortcuts.assignmentIssue(
                    GlobalShortcut(keyCode: 11, modifiers: []), for: "app.bundle.a", in: bound) == .invalid,
               "an app shortcut cannot take an ordinary typing key even when editing an existing binding")
        bound = CommandBarRowShortcuts.setting(optionB, for: "app.bundle.b", in: bound)
        expect(bound["app.bundle.b"] == optionB && bound["app.bundle.a"] == nil,
               "the same keys move to the last row that asked; two rows never share one")
        expect(CommandBarRowShortcuts.setting(nil, for: "app.bundle.b", in: bound).isEmpty,
               "taking the keys off leaves nothing behind")
        expect(CommandBarRowShortcuts.key(for: optionB, in: bound) == "app.bundle.b"
                && CommandBarRowShortcuts.key(for: optionN, in: bound) == nil,
               "a press is routed to the row that owns it")
        expect(CommandBarRowShortcuts.isUsable(optionB)
                && !CommandBarRowShortcuts.isUsable(GlobalShortcut(keyCode: 11, modifiers: [])),
               "a bare letter is never taken from every app on the Mac")
        expect(CommandBarRowShortcuts.decode(CommandBarRowShortcuts.encode(bound)) == bound,
               "the bindings survive a round trip through storage")
        let emojiBinding = CommandBarRowShortcuts.setting(
            commandPeriod, for: CommandBarPreferences.emojiBrowserRowID, in: [:])
        expect(CommandBarRowShortcuts.key(for: commandPeriod, in: emojiBinding)
                == CommandBarPreferences.emojiBrowserRowID,
               "the Emoji browser row can own a global shortcut like any other row")
        var full: [String: GlobalShortcut] = [:]
        for index in 0..<CommandBarRowShortcuts.limit {
            full["row.\(index)"] = GlobalShortcut(keyCode: Int64(index), modifiers: [.control])
        }
        expect(!CommandBarRowShortcuts.hasRoom(for: "row.new", in: full)
                && CommandBarRowShortcuts.hasRoom(for: "row.0", in: full)
                && CommandBarRowShortcuts.hasRoom(for: "row.new", in: [:]),
               "a full list says so before the keys are taken, and rebinding is always allowed")
        expect(CommandBarRowShortcuts.assignmentIssue(optionN, for: "row.new", in: full) == .full
                && CommandBarRowShortcuts.assignmentIssue(optionN, for: "row.0", in: full) == nil,
               "the app editor reports a full list while still allowing existing shortcuts to change")
        let appBindings = ["app.bundle.a": optionB, "app.bundle.b": optionN]
        var pendingApp = CommandBarRowShortcuts.PendingAppLaunch()
        pendingApp.schedule("app.bundle.a", in: appBindings)
        expect(pendingApp.take(in: appBindings, isAvailable: true) == "app.bundle.a"
                && pendingApp.take(in: appBindings, isAvailable: true) == nil,
               "an app shortcut waiting for its first catalog runs exactly once")
        pendingApp.schedule("app.bundle.a", in: appBindings)
        pendingApp.schedule("app.bundle.b", in: appBindings)
        expect(pendingApp.take(in: appBindings, isAvailable: true) == "app.bundle.b",
               "the latest app shortcut replaces an earlier request while the catalog loads")
        pendingApp.schedule("app.bundle.a", in: appBindings)
        expect(pendingApp.take(in: [:], isAvailable: true) == nil,
               "removing a shortcut while apps load cancels its pending launch")
        pendingApp.schedule("app.bundle.a", in: appBindings)
        expect(pendingApp.take(in: ["app.bundle.a": optionN], isAvailable: true) == nil,
               "changing a shortcut while apps load cannot run its previous binding")
        pendingApp.schedule("app.bundle.a", in: appBindings)
        expect(pendingApp.take(in: appBindings, isAvailable: false) == nil
                && pendingApp.take(in: appBindings, isAvailable: true) == nil,
               "disabling the feature discards the deferred launch rather than postponing it")
        pendingApp.schedule("app.bundle.a", in: appBindings)
        pendingApp.cancel()
        expect(pendingApp.take(in: appBindings, isAvailable: true) == nil,
               "suspending shortcuts or running another command cancels a queued app launch")
        expect(SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.commandBarRowShortcuts,
                    DefaultsKey.commandBarAliases, DefaultsKey.commandBarPins]),
               "the app center reuses shortcut, alias and favorite preferences carried by settings backups")
        expect(CommandBarRowShortcuts.isUsable(
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
        expect(monitorParts.count > 1
                && monitor.contains("? event.charactersIgnoringModifiers")
                && monitor.contains(": event.characters)?.lowercased()")
                && monitor.contains("let key = event.charactersIgnoringModifiers?.lowercased()")
                && !monitor.contains("case kVK_ANSI_Q")
                && monitor.contains("digitIndex(for: event.keyCode)"),
               "the Command Bar uses macOS Command letters while Control follows typed letters and digits stay positional")
        expect(monitor.contains("#selector(NSText.selectAll(_:))")
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
        expect(captureBeginParts.count > 1,
               "the Command Bar capture start finds the end of beginCapturingShortcut")
        expect(captureBegin.contains("ShortcutCapture.begin()")
                && captureBegin.contains("ShortcutRecordingTap.begin"),
               "the capture card starts the same pair Settings uses, so Command Q reaches it")
        let captureEndParts = (commandBarCode
            .components(separatedBy: "private func endCapturingShortcut()")
            .last ?? "").components(separatedBy: "\n    private func ")
        let captureEnd = captureEndParts.first ?? ""
        expect(captureEndParts.count > 1,
               "the Command Bar capture stop finds the end of endCapturingShortcut")
        expect(captureEnd.contains("ShortcutRecordingTap.end()")
                && captureEnd.contains("ShortcutCapture.end()"),
               "leaving the card gives the keyboard back")
    }
}
