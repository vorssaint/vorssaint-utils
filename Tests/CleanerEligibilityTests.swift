// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The generated methods are the real scan and removal guards. Only the
/// allowed root and installed-app lookup are replaced; no cleaning is performed.
enum CleanerEligibilityTests {
    struct Item {
        let url: URL
        let category = CleanerSupport.Category.leftovers
        let detail: String
        var fileIdentity: UninstallerSupport.FileIdentity? { UninstallerSupport.fileIdentity(at: url) }
    }
    static var fixtureRoot: URL?

    static func isDirectLeftoverRootChild(_ url: URL) -> Bool {
        fixtureRoot.map { CleanerSupport.isDirectChild(url, of: $0) } ?? false
    }

    static func hasLivingOwner(_ owner: String, installed: Set<String>) -> Bool {
        CleanerSupport.isOwned(candidate: owner, byInstalled: installed)
    }

    static func run(_ suite: TestSuite) {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("vorssaint-cleaner-\(UUID().uuidString)", isDirectory: true)
        fixtureRoot = root
        defer { fixtureRoot = nil; try? manager.removeItem(at: root) }
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            for name in ["logitec.localized", "Logitech.localized", "Vendor.LoCaLiZeD",
                         "com.vendor.editor.localized"] {
                let folder = root.appendingPathComponent(name, isDirectory: true)
                try manager.createDirectory(at: folder, withIntermediateDirectories: false)
                suite.expect(owner(folder) == nil,
                             "localized directory \(name) is not offered as an app leftover")
                suite.expect(!canRemove(Item(url: folder, detail: name)),
                             "a previously listed localized directory \(name) cannot be removed")
            }

            for id in ["com.vendor.editor", "com.vendor.localized.editor", "com.vendor.localized"] {
                let preference = root.appendingPathComponent(id + ".plist")
                try Data().write(to: preference)
                suite.expect(owner(preference) == id,
                             "a real preference file retains its exact owner \(id)")
                suite.expect(canRemove(Item(url: preference, detail: id)),
                             "an unowned preference for \(id) remains eligible after scanning")
                suite.expect(!canRemove(Item(url: preference, detail: id), installed: [id]),
                             "preferences for an installed owner \(id) remain protected")
            }

            let container = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try manager.createDirectory(at: container, withIntermediateDirectories: false)
            try PropertyListSerialization.data(fromPropertyList: [
                "MCMMetadataIdentifier": "com.vendor.localized",
            ], format: .xml, options: 0).write(to: container.appendingPathComponent(
                ".com.apple.containermanagerd.metadata.plist"))
            suite.expect(owner(container, metadata: true) == "com.vendor.localized"
                         && canRemove(Item(url: container, detail: "com.vendor.localized")),
                         "container metadata remains an identifier rather than a directory name")
        } catch {
            suite.expect(false, "cleaner eligibility fixture failed: \(error)")
        }
    }
}
