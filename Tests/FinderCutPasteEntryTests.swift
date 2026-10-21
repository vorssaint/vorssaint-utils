// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the production entry points against inert clipboard and move endpoints.
/// It never reads the user's clipboard or enables a global input tap.
enum FinderCutPasteEntryContract {
    enum Feature {
        static var finderCutPaste = FeatureState()
        struct FeatureState { var isAvailable = true }
    }
    final class Pasteboard {
        static let general = Pasteboard()
        var changeCount = 10
    }
    class Fixture {
        typealias AppFeature = Feature
        typealias NSPasteboard = Pasteboard
        var cutPasteEnabled = true
        var moveInProgress = false
        var operationGeneration = 0
        var marked: [URL] = []
        var markedChangeCount = 10
        var requestedDestination: URL?
        func applyCut(_ urls: [URL]) { marked = urls }
        func pasteAsync(destination: URL) { requestedDestination = destination }
    }
    static func run(_ suite: TestSuite) {
        suite.run("Finder cut and paste entry points") {
            defer { Feature.finderCutPaste.isAvailable = true; Pasteboard.general.changeCount = 10 }
            let host = Host()
            let input = URL(fileURLWithPath: "/tmp/selected.txt")
            let directory = URL(fileURLWithPath: "/tmp/destination", isDirectory: true)
            suite.expect(!host.pasteFromTools(into: directory) && host.requestedDestination == nil,
                         "an empty cut buffer cannot move files")
            suite.expect(!host.cutFromTools([URL(string: "https://example.com")!]) && host.marked.isEmpty,
                         "remote URLs cannot enter the cut buffer")
            suite.expect(host.cutFromTools([input]) && host.marked == [input] && host.operationGeneration == 1,
                         "an explicit cut marks exactly the selected files and invalidates older selection reads")
            Pasteboard.general.changeCount = 11
            suite.expect(!host.pasteFromTools(into: directory) && host.requestedDestination == nil,
                         "changing the clipboard invalidates a pending cut")
            Pasteboard.general.changeCount = 10
            suite.expect(host.pasteFromTools(into: directory) && host.requestedDestination == directory,
                         "paste uses the chosen destination instead of querying Finder")
            host.moveInProgress = true
            suite.expect(!host.cutFromTools([directory]) && !host.pasteFromTools(into: directory) && host.marked == [input],
                         "a running move cannot be replaced or started twice")
            host.moveInProgress = false
            Feature.finderCutPaste.isAvailable = false
            suite.expect(!host.cutFromTools([directory]) && !host.pasteFromTools(into: directory),
                         "uninstalling the owning feature blocks both entry points")
        }
    }
}
