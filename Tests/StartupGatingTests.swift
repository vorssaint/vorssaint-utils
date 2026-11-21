// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Launch decisions for display recovery, the shelf anchor and Command Bar shortcuts.
enum StartupGatingTests {
    static func run(_ suite: TestSuite) {
        func source(_ path: String) -> String {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
                suite.expect(false, "\(path) is readable")
                return ""
            }
            return text
        }

        /// The single line carrying `needle`, so a check cannot pass on a word
        /// that happens to sit in another body of the same file.
        func line(in text: String, containing needle: String) -> String? {
            text.components(separatedBy: "\n").first { $0.contains(needle) }
        }

        // MARK: Display repair asked from the saved list

        suite.expect(!BrightnessSupport.hasDisplaysToRestore(stored: nil),
                     "no saved list asks for nothing")
        suite.expect(!BrightnessSupport.hasDisplaysToRestore(stored: []),
                     "an empty saved list asks for nothing")
        suite.expect(BrightnessSupport.hasDisplaysToRestore(stored: [1]),
                     "one saved display asks for the repair")
        suite.expect(!BrightnessSupport.hasDisplaysToRestore(stored: [0]),
                     "the null display id does not start a repair")
        suite.expect(BrightnessSupport.hasDisplaysToRestore(stored: [0, 7]),
                     "a null entry does not hide a valid saved display")
        suite.expect(!BrightnessSupport.hasDisplaysToRestore(stored: [-1]),
                     "a negative number is not a display")
        suite.expect(!BrightnessSupport.hasDisplaysToRestore(stored: [Int.max]),
                     "a number past a display id is not a display")

        let appDelegate = source("Sources/Vorssaint/App/AppDelegate.swift")
        let launchStatements = appDelegate.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        let repair = """
            if BrightnessService.hasDisplaysToRestore {
            BrightnessService.shared.restoreDisplaysLeftOff()
            }
            """
        suite.expect(launchStatements.contains(repair),
                     "launch recovers a saved display even when brightness is uninstalled")

        // MARK: Shelf anchor registered without the service

        let shelfAnchorLine = line(in: appDelegate, containing: "statusItemFrameProvider =")
        suite.expect(shelfAnchorLine?.contains("ShelfService.statusItemFrameProvider =") == true,
                     "launch registers the shelf anchor on the type, got \(shelfAnchorLine ?? "nothing")")
        suite.expect(appDelegate.contains("ShelfService.shared.statusItemFrameProvider") == false,
                     "launch never reaches the shared shelf service for an anchor")

        let shelf = source("Sources/Vorssaint/Services/Shelf/ShelfService.swift")
        suite.expect(shelf.contains("static var statusItemFrameProvider"),
                     "the anchor lives on the type, so assigning it builds nothing")
        let anchoredReads = shelf.components(separatedBy: "Self.statusItemFrameProvider?()").count - 1
        suite.expect(anchoredReads == 2, "both docked placements read the type anchor, got \(anchoredReads)")
        suite.expect(shelf.contains("statusItemFrameProvider?()") &&
                     shelf.components(separatedBy: "statusItemFrameProvider?()").count - 1 == anchoredReads,
                     "no placement still reads an instance anchor")

        // MARK: Command Bar drops rows without building a service

        let runtime = source("Sources/Vorssaint/App/FeatureRuntime.swift")
        let hubChangeLine = line(in: runtime, containing: "CommandBarService.shared.noteHubChange()")
        suite.expect(hubChangeLine?.contains("AppFeature.commandBar.isAvailable") == true,
                     "a Command Bar that is not installed is not asked about hub changes, got \(hubChangeLine ?? "nothing")")

        testCommandBarShortcuts(suite)
    }

    private static func testCommandBarShortcuts(_ suite: TestSuite) {
        typealias Fixture = UninstallerCommandBarCleanupTests
        let domain = "com.vorssaint.tests.command-bar-startup.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        Fixture.Preferences.standard = defaults
        defer {
            Fixture.Queue.pending = []
            Fixture.Feature.available = true
            Fixture.Preferences.standard = nil
            defaults.removePersistentDomain(forName: domain)
        }
        let service = Fixture.Service()
        let shortcut = GlobalShortcut(keyCode: 11, modifiers: [.option, .command])
        let emoji = CommandBarPreferences.emojiBrowserRowID
        let app = CommandBarRowShortcuts.appKey(bundleID: "com.apple.TextEdit", path: "/Applications/TextEdit.app")
        func bind(_ rows: [String: GlobalShortcut]) {
            defaults.set(CommandBarRowShortcuts.encode(rows), forKey: DefaultsKey.commandBarRowShortcuts)
            service.syncRowHotkeys()
        }

        bind([:])
        bind([app: shortcut])
        suite.expect(Fixture.Queue.pending.isEmpty && service.panel == nil,
                     "click-only and direct app shortcuts leave the panel unloaded")
        bind([emoji: shortcut])
        bind([app: shortcut])
        Fixture.Queue.drain()
        suite.expect(service.panel == nil, "replacing the emoji shortcut before warm-up leaves the panel unloaded")
        bind([emoji: shortcut])
        Fixture.Queue.drain()
        suite.expect(service.panel?.displayedAfterLayout == true,
                     "the emoji shortcut lays out and draws the panel with the main shortcut off")

        service.panel = nil
        let existingPanel = service.ensurePanel()
        bind([emoji: shortcut])
        Fixture.Queue.drain()
        suite.expect(existingPanel.displayedAfterLayout && existingPanel.displayCount == 1,
                     "a panel created for an island presentation still prepares for its first window shortcut")
        existingPanel.isVisible = true
        bind([emoji: shortcut])
        Fixture.Queue.drain()
        suite.expect(existingPanel.displayCount == 1, "synchronizing shortcuts does not redraw a visible panel")

        service.panel = nil
        bind([emoji: shortcut])
        service.rowHotkeys[emoji]?.unregister()
        Fixture.Queue.drain()
        suite.expect(service.panel == nil, "releasing registered row keys cancels their queued warm-up")

        let mainKey = DefaultsKey.commandBarShortcutEnabled
        defaults.set(true, forKey: mainKey)
        _ = service.hotkey.sync(enabled: true, shortcut: shortcut, storageKey: DefaultsKey.commandBarShortcut)
        bind([:])
        defaults.set(false, forKey: mainKey)
        Fixture.Queue.drain()
        suite.expect(service.panel == nil, "turning off the main shortcut cancels its queued warm-up")
        defaults.set(true, forKey: mainKey)
        bind([:])
        service.hotkey.unregister()
        Fixture.Queue.drain()
        suite.expect(service.panel == nil, "suspending the main shortcut cancels its queued warm-up")

        _ = service.hotkey.sync(enabled: true, shortcut: shortcut, storageKey: DefaultsKey.commandBarShortcut)
        bind([:])
        Fixture.Feature.available = false
        Fixture.Queue.drain()
        suite.expect(service.panel == nil, "uninstalling the Command Bar cancels queued warm-up")
        Fixture.Feature.available = true
        bind([:])
        Fixture.Queue.drain()
        suite.expect(service.panel != nil, "an active main shortcut prepares the panel for typing")
    }
}
