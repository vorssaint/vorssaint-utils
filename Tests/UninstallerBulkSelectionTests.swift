// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Production selection, summaries and Homebrew guards run against the flow
/// fixture. Scanning and package removal stay simulated; no files are removed.
enum UninstallerBulkSelectionTests {
    private typealias Bulk = UninstallerSupport.BulkSelection
    private typealias Fixture = UninstallerFlowTests

    static func run(_ suite: TestSuite) {
        suite.expect(Bulk(included: 0, total: 0) == .none,
                     "an empty results list shows an empty box")
        suite.expect(Bulk(included: 0, total: 3) == .none,
                     "no chosen rows show an empty box")
        suite.expect(Bulk(included: 1, total: 3) == .some,
                     "some chosen rows show a mixed box")
        suite.expect(Bulk(included: 3, total: 3) == .all,
                     "every chosen row shows a checked box")
        suite.expect(Bulk(included: 2, total: 2) == .all,
                     "a full list of two reads the same as a full list of many")

        suite.expect(Bulk.none.nextInclude && Bulk.some.nextInclude,
                     "clicking an empty or mixed box selects everything")
        suite.expect(!Bulk.all.nextInclude,
                     "clicking a full box clears the selection")
        modelChecks(suite)
    }

    private static func modelChecks(_ suite: TestSuite) {
        let uninstaller = Fixture.Uninstaller()
        let brew = Fixture.Brew.shared
        let previousStatus = brew.operationStatus
        let previousOperation = brew.operation
        let previousUninstalled = brew.uninstalled
        let previousMessages = Fixture.HUD.messages
        defer {
            uninstaller.homebrewRemovalObservation?.cancel()
            brew.operationStatus = previousStatus
            brew.operation = previousOperation
            brew.uninstalled = previousUninstalled
            Fixture.HUD.messages = previousMessages
        }
        brew.operationStatus = nil
        brew.operation = nil
        brew.uninstalled = []
        Fixture.HUD.messages = []
        uninstaller.phase = .results
        for include in [true, false] {
            uninstaller.setAllIncluded(include)
            suite.expect(uninstaller.items.isEmpty && uninstaller.bulkSelection == .none
                         && uninstaller.selectedSize == 0 && uninstaller.totalSize == 0
                         && !uninstaller.canRemoveSelected,
                         "bulk selection leaves an empty result empty and cannot enable removal")
        }

        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("bulk-\(UUID())")
        defer { try? fm.removeItem(at: root) }
        let appURL = root.appendingPathComponent("Editor.app", isDirectory: true)
        do {
            try UninstallerTrashTests.writeBundle(at: appURL, id: "org.vorssaint.fixture.editor")
            uninstaller.targetSelection = UninstallerSupport.selection(for: appURL)
        } catch {
            suite.expect(false, "could not create the bulk selection fixture: \(error)")
            return
        }
        let original = [
            Fixture.Leftover(url: appURL, category: .app, size: 100),
            Fixture.Leftover(url: appURL.appendingPathExtension("support"), category: .support, size: 20),
            Fixture.Leftover(url: appURL.appendingPathExtension("cache"), category: .caches, size: 30,
                             confidence: .related, include: false),
            Fixture.Leftover(url: appURL.appendingPathExtension("plist"), category: .preferences, size: 40,
                             confidence: .related, include: false),
        ]
        uninstaller.items = original
        uninstaller.target = Fixture.Target(name: "Editor", bundleID: "org.vorssaint.fixture.editor",
                                            url: appURL, icon: NSImage())
        func expectSelection(_ flags: [Bool], _ state: Bulk, _ count: Int, _ size: Int64, _ context: String) {
            var expected = original
            for index in expected.indices { expected[index].include = flags[index] }
            // Fixture equality also checks IDs, paths, categories, sizes and confidence.
            suite.expect(uninstaller.items == expected,
                         "\(context) changes only the requested inclusion flags on the same rows")
            suite.expect(uninstaller.bulkSelection == state
                         && uninstaller.items.filter(\.include).count == count
                         && uninstaller.selectedSize == size && uninstaller.totalSize == 190,
                         "\(context) updates the mixed state, count and byte totals together")
        }
        expectSelection([true, true, false, false], .some, 2, 120, "initial mixed results")
        uninstaller.setAllIncluded(uninstaller.bulkSelection.nextInclude)
        expectSelection([true, true, true, true], .all, 4, 190, "selecting all including optional rows")
        uninstaller.setInclude(false, for: original[2].id)
        expectSelection([true, true, false, true], .some, 3, 160, "unchecking one optional exception")
        uninstaller.setAllIncluded(uninstaller.bulkSelection.nextInclude)
        expectSelection([true, true, true, true], .all, 4, 190, "selecting all after an exception")
        uninstaller.setAllIncluded(uninstaller.bulkSelection.nextInclude)
        expectSelection([false, false, false, false], .none, 0, 0, "clearing a full selection")
        suite.expect(!uninstaller.canRemoveSelected, "clearing every row disables removal")
        uninstaller.setAllIncluded(uninstaller.bulkSelection.nextInclude)
        expectSelection([true, true, true, true], .all, 4, 190, "selecting all from nothing")
        suite.expect(uninstaller.phase == .results && uninstaller.canRemoveSelected && brew.uninstalled.isEmpty,
                     "selection changes only prepare a removable selection and never start removal")

        let package = Fixture.Package(id: "editor")
        uninstaller.homebrewPackage = package
        for withHomebrew in [false, true] {
            uninstaller.items = original
            uninstaller.phase = withHomebrew ? .results : .removing
            brew.operationStatus = withHomebrew
                ? .init(action: .uninstall, package: package, result: .running) : nil
            suite.expect(uninstaller.isRemoving && uninstaller.isRemovingWithHomebrew == withHomebrew,
                         "the production guard recognizes \(withHomebrew ? "Homebrew" : "plain") removal")
            for include in [false, true] {
                uninstaller.setAllIncluded(include)
                expectSelection([true, true, false, false], .some, 2, 120,
                                "blocked bulk change during \(withHomebrew ? "Homebrew" : "plain") removal")
            }
            uninstaller.setInclude(false, for: original[0].id)
            expectSelection([true, true, false, false], .some, 2, 120, "blocked per-row change during removal")
        }
        uninstaller.phase = .results
        brew.operationStatus = nil
        uninstaller.setAllIncluded(false)
        expectSelection([false, false, false, false], .none, 0, 0, "editing again after removal stops")
        brew.operationStatus = .init(action: .uninstall, package: Fixture.Package(id: "another-app"), result: .running)
        uninstaller.setAllIncluded(true)
        expectSelection([true, true, true, true], .all, 4, 190, "selecting during another package's removal")
        suite.expect(!uninstaller.isRemoving, "another package's active operation does not lock this selection")
        brew.operationStatus = nil

        uninstaller.items = original
        guard let mixedConfirmation = uninstaller.homebrewRemovalConfirmation else {
            suite.expect(false, "the mixed app selection offers a Homebrew confirmation")
            return
        }
        uninstaller.setAllIncluded(true)
        suite.expect(uninstaller.canRemoveSelected && uninstaller.selectedHomebrewPackage == package,
                     "selecting extra rows keeps the same app and package removable")
        uninstaller.removeSelectedWithHomebrew(confirmation: mixedConfirmation)
        suite.expect(brew.uninstalled.isEmpty && Fixture.HUD.messages == ["Expired"],
                     "selecting extra rows invalidates the earlier Homebrew confirmation")
        guard let fullConfirmation = uninstaller.homebrewRemovalConfirmation else {
            suite.expect(false, "the full selection offers a new Homebrew confirmation")
            return
        }
        uninstaller.setAllIncluded(false)
        uninstaller.setInclude(true, for: original[0].id)
        suite.expect(uninstaller.canRemoveSelected && uninstaller.selectedHomebrewPackage == package,
                     "keeping only the app remains a legitimate Homebrew removal")
        uninstaller.removeSelectedWithHomebrew(confirmation: fullConfirmation)
        suite.expect(brew.uninstalled.isEmpty && Fixture.HUD.messages == ["Expired", "Expired"],
                     "clearing leftovers invalidates a confirmation even when the same app is selected again")
        guard let currentConfirmation = uninstaller.homebrewRemovalConfirmation else {
            suite.expect(false, "the revised selection can be confirmed again")
            return
        }
        uninstaller.removeSelectedWithHomebrew(confirmation: currentConfirmation)
        suite.expect(brew.uninstalled == [package.id] && Fixture.HUD.messages == ["Expired", "Expired"],
                     "an unchanged current confirmation starts exactly the intended package removal")
    }
}
