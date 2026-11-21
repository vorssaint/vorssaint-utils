// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// A feature that is installed but off pays nothing at launch: the shelf does
/// not read its saved items to hand out an anchor, the display repair is asked
/// from the saved list instead of the service, and the Command Bar does not
/// build a panel and a view tree for a shortcut nobody pressed.
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
        suite.expect(BrightnessSupport.hasDisplaysToRestore(stored: [0, 7]),
                     "any saved display number asks for the repair")
        suite.expect(!BrightnessSupport.hasDisplaysToRestore(stored: [-1]),
                     "a negative number is not a display")
        suite.expect(!BrightnessSupport.hasDisplaysToRestore(stored: [Int.max]),
                     "a number past a display id is not a display")

        let appDelegate = source("Sources/Vorssaint/App/AppDelegate.swift")
        suite.expect(line(in: appDelegate, containing: "BrightnessService.hasDisplaysToRestore") != nil,
                     "launch asks for the saved list before touching the brightness service")
        suite.expect(line(in: appDelegate, containing: "BrightnessService.shared.restoreDisplaysLeftOff()")
                        .map { $0.hasPrefix("            ") } == true,
                     "the repair itself runs only inside that question")

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

        let commandBar = source("Sources/Vorssaint/Services/CommandBar/CommandBarService.swift")
        suite.expect(commandBar.contains("guard enabled, AppFeature.commandBar.isAvailable, let self"),
                     "the launch warm-up keeps requiring the shortcut to be on")
        let warmUpLine = line(in: commandBar, containing: "Build the one view tree after launch")
        suite.expect(warmUpLine != nil, "the warm-up block is still documented in place")
    }
}
