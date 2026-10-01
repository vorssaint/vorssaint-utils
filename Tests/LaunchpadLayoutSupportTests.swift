// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LaunchpadLayoutSupportTests {
    static func run(_ suite: TestSuite) {
        suite.expect(LaunchpadLayoutSupport.applyingCatalog(.initial, knownAppIDs: ["a", "b"]).items.map(\.id) == ["a", "b"],
                     "an empty layout picks up every known app, in catalog order")

        let existing = LaunchpadLayout(items: [.app("b"), .app("a")])
        suite.expect(LaunchpadLayoutSupport.applyingCatalog(existing, knownAppIDs: ["a", "b"]).items.map(\.id) == ["b", "a"],
                     "an existing order is kept as-is when nothing changed")

        suite.expect(LaunchpadLayoutSupport.applyingCatalog(existing, knownAppIDs: ["a"]).items.map(\.id) == ["a"],
                     "an app no longer installed drops out of the layout")

        suite.expect(LaunchpadLayoutSupport.applyingCatalog(existing, knownAppIDs: ["a", "b", "c"]).items.map(\.id) == ["b", "a", "c"],
                     "a newly installed app is appended after the existing order")

        let folder = LaunchpadFolder(id: UUID(), name: "Utilities", appIDs: ["x", "y"])
        let withFolder = LaunchpadLayout(items: [.app("a"), .folder(folder)])
        suite.expect(LaunchpadLayoutSupport.applyingCatalog(withFolder, knownAppIDs: ["a", "x"]).items == [.app("a"), .app("x")],
                     "a folder left with only one app after an uninstall dissolves into that loose app")

        let dissolving = LaunchpadLayout(items: [.app("a"), .folder(LaunchpadFolder(id: folder.id, name: "Utilities", appIDs: ["x"]))])
        suite.expect(LaunchpadLayoutSupport.applyingCatalog(dissolving, knownAppIDs: ["a"]).items == [.app("a")],
                     "a folder left with no apps at all dissolves out of the layout")

        suite.expect(LaunchpadLayoutSupport.moving(LaunchpadLayout(items: [.app("a"), .app("b"), .app("c")]), itemID: "c", beforeItemID: "a").items.map(\.id) == ["c", "a", "b"],
                     "moving an item places it just before its target")

        suite.expect(LaunchpadLayoutSupport.moving(LaunchpadLayout(items: [.app("a"), .app("b")]), itemID: "a", beforeItemID: nil).items.map(\.id) == ["b", "a"],
                     "a nil target moves the item to the very end")

        let combined = LaunchpadLayoutSupport.combining(LaunchpadLayout(items: [.app("a"), .app("b")]), draggedAppID: "a", ontoID: "b", defaultFolderName: "New Folder")
        suite.expect(combined.items.count == 1, "combining two loose apps replaces both with one folder")
        if case .folder(let created) = combined.items.first {
            suite.expect(created.name == "New Folder" && created.appIDs == ["b", "a"],
                         "the new folder is named with the given default and holds the target first, then the dragged app")
        } else {
            suite.expect(false, "combining two apps must produce a folder item")
        }

        let intoFolder = LaunchpadLayoutSupport.combining(LaunchpadLayout(items: [.app("a"), .folder(folder)]), draggedAppID: "a", ontoID: folder.id.uuidString, defaultFolderName: "New Folder")
        suite.expect(intoFolder.items.count == 1, "dragging a loose app onto an existing folder adds it there instead of nesting folders")
        if case .folder(let updated) = intoFolder.items.first {
            suite.expect(updated.appIDs == ["x", "y", "a"], "the app joins at the end of the folder's existing apps")
        } else {
            suite.expect(false, "the target folder must remain a folder item")
        }

        let twoAppFolder = LaunchpadFolder(id: UUID(), name: "Pair", appIDs: ["x", "y"])
        let removed = LaunchpadLayoutSupport.removingFromFolder(LaunchpadLayout(items: [.folder(twoAppFolder)]), appID: "y", folderID: twoAppFolder.id)
        suite.expect(removed.items.map(\.id) == ["x", "y"] && removed.items.allSatisfy { if case .app = $0 { return true }; return false },
                     "removing the second-to-last app dissolves the folder back into two loose apps")

        let threeAppFolder = LaunchpadFolder(id: UUID(), name: "Trio", appIDs: ["x", "y", "z"])
        let removedOne = LaunchpadLayoutSupport.removingFromFolder(LaunchpadLayout(items: [.folder(threeAppFolder)]), appID: "y", folderID: threeAppFolder.id)
        suite.expect(removedOne.items.count == 2, "removing one app from a folder of three keeps the folder with the remaining two")

        let overCapacity = LaunchpadLayout(items: (0..<600).map { .app("\($0)") })
        suite.expect(LaunchpadLayoutSupport.sanitized(overCapacity).items.count == 512,
                     "sanitizing caps the total item count so a corrupted or huge blob can't grow without bound")

        let duplicated = LaunchpadLayout(items: [.app("a"), .app("a"), .app("b")])
        suite.expect(LaunchpadLayoutSupport.sanitized(duplicated).items.map(\.id) == ["a", "b"],
                     "sanitizing drops a duplicate item id")

        let renameFolder = LaunchpadFolder(id: UUID(), name: "Old Name", appIDs: ["x", "y"])
        let renamed = LaunchpadLayoutSupport.renamingFolder(LaunchpadLayout(items: [.folder(renameFolder)]), folderID: renameFolder.id, name: "Work")
        if case .folder(let updated) = renamed.items.first {
            suite.expect(updated.name == "Work", "renaming a folder replaces its name")
        } else {
            suite.expect(false, "renaming a folder must not turn it into something else")
        }

        let blankRename = LaunchpadLayoutSupport.renamingFolder(LaunchpadLayout(items: [.folder(renameFolder)]), folderID: renameFolder.id, name: "   ")
        if case .folder(let unchanged) = blankRename.items.first {
            suite.expect(unchanged.name == "Old Name", "a blank name is ignored rather than leaving a folder untitled")
        } else {
            suite.expect(false, "an ignored rename must not touch the folder otherwise")
        }

        suite.expect(LaunchpadLayoutSupport.renamingFolder(LaunchpadLayout(items: [.app("a")]), folderID: UUID(), name: "X").items.map(\.id) == ["a"],
                     "renaming a folder id that isn't in the layout does nothing")

        let finder = LaunchpadApp(id: "/System/Applications/Finder.app", name: "Finder", bundleID: nil, path: "/System/Applications/Finder.app")
        let terminal = LaunchpadApp(id: "/System/Applications/Utilities/Terminal.app", name: "Terminal", bundleID: nil, path: "/System/Applications/Utilities/Terminal.app")
        let console = LaunchpadApp(id: "/System/Applications/Utilities/Console.app", name: "Console", bundleID: nil, path: "/System/Applications/Utilities/Console.app")
        let defaultLayout = LaunchpadLayoutSupport.defaultLayout(for: [terminal, finder, console], utilitiesFolderName: "Utilities")
        suite.expect(defaultLayout.items.contains(.app(finder.id)), "an app outside the native Utilities subfolder stays loose")
        if case .folder(let utilities) = defaultLayout.items.first(where: { if case .folder = $0 { return true }; return false }) {
            suite.expect(utilities.name == "Utilities" && Set(utilities.appIDs) == Set([terminal.id, console.id]),
                         "two or more apps from the real Utilities subfolder are grouped into one folder by that name")
        } else {
            suite.expect(false, "two native utility apps must produce a folder")
        }

        let singleUtility = LaunchpadLayoutSupport.defaultLayout(for: [finder, terminal], utilitiesFolderName: "Utilities")
        suite.expect(singleUtility.items == [.app(finder.id), .app(terminal.id)],
                     "a single native utility app stays loose rather than becoming a one-item folder")

        let longName = LaunchpadFolder(id: UUID(), name: String(repeating: "a", count: 80), appIDs: ["x", "y"])
        let sanitizedLongName = LaunchpadLayoutSupport.sanitized(LaunchpadLayout(items: [.folder(longName)]))
        if case .folder(let capped) = sanitizedLongName.items.first {
            suite.expect(capped.name.count == LaunchpadLayoutSupport.maximumFolderNameLength,
                         "sanitizing caps an overly long folder name")
        } else {
            suite.expect(false, "sanitizing a long folder name must not drop the folder")
        }
    }
}
