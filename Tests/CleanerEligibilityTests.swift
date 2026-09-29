// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The generated methods are the real scan and removal guards. Only the
/// home directory, allowed root and installed-app lookup are replaced; no cleaning is performed.
enum CleanerEligibilityTests {
    struct Item {
        let url: URL
        let category: CleanerSupport.Category
        let size: Int64
        let recommended: Bool
        init(url: URL, category: CleanerSupport.Category = .leftovers, size: Int64 = 1,
             detail: String, recommended: Bool = false) {
            self.url = url
            self.category = category
            self.size = size
            self.detail = detail
            self.recommended = recommended
        }
        let detail: String
        var fileIdentity: UninstallerSupport.FileIdentity? { UninstallerSupport.fileIdentity(at: url) }
    }
    static var fixtureRoot: URL?
    static func NSHomeDirectory() -> String { fixtureRoot!.path }

    static func isDirectLeftoverRootChild(_ url: URL) -> Bool {
        fixtureRoot.map { CleanerSupport.isDirectChild(url, of: $0) } ?? false
    }

    static func hasLivingOwner(_ owner: String, installed: Set<String>) -> Bool {
        CleanerSupport.isOwned(candidate: owner, byInstalled: installed)
    }

    static var screenshotFolder: URL?
    static func isScreenshotFolderChild(_ url: URL) -> Bool {
        screenshotFolder.map { CleanerSupport.isDirectChild(url, of: $0) } ?? false
    }

    static func setAttribute(_ name: String, _ data: Data, on url: URL) {
        url.withUnsafeFileSystemRepresentation { path in
            _ = data.withUnsafeBytes { setxattr(path!, name, $0.baseAddress, data.count, 0, 0) }
        }
    }

    /// The exact bytes macOS writes for the flag and a last opened date.
    static let screenCaptureFlag = Data([0x62, 0x70, 0x6C, 0x69, 0x73, 0x74, 0x30, 0x30, 0x09, 0x08,
                                         0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1,
                                         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x09])

    static func lastUsedAttribute(_ date: Date) -> Data {
        var seconds = Int64(date.timeIntervalSince1970).littleEndian
        var data = Data(bytes: &seconds, count: 8)
        data.append(Data(count: 8))
        return data
    }

    static func runScreenshotRules(_ suite: TestSuite) {
        let home = "/Users/someone"
        suite.expect(CleanerSupport.screenshotFolder(location: nil, home: home) == home + "/Desktop"
                     && CleanerSupport.screenshotFolder(location: "  ", home: home) == home + "/Desktop"
                     && CleanerSupport.screenshotFolder(location: "~/Documents/Shots", home: home)
                        == home + "/Documents/Shots"
                     && CleanerSupport.screenshotFolder(location: "/Volumes/Work/Shots", home: home)
                        == "/Volumes/Work/Shots"
                     && CleanerSupport.screenshotFolder(location: "relative", home: home) == home + "/Desktop",
                     "the screenshot folder follows the system setting, the Desktop by default")
        suite.expect(CleanerSupport.isScreenCaptureFlag(screenCaptureFlag)
                     && !CleanerSupport.isScreenCaptureFlag(Data())
                     && !CleanerSupport.isScreenCaptureFlag(
                        try! PropertyListSerialization.data(fromPropertyList: false, format: .binary, options: 0)),
                     "only a true capture flag marks a screenshot")
        let opened = Date(timeIntervalSince1970: 1_781_716_463)
        suite.expect(CleanerSupport.lastUsedDate(fromAttribute: Data([0xEF, 0xD5, 0x32, 0x6A, 0, 0, 0, 0,
                                                                     0, 0, 0, 0, 0, 0, 0, 0])) == opened
                     && CleanerSupport.lastUsedDate(fromAttribute: Data([1, 2])) == nil,
                     "the last opened date reads the system timespec")
        let utc = TimeZone(identifier: "UTC")!
        let taken = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21 14:13:20 UTC
        suite.expect(CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 14.13.20.png",
                                                               created: taken, timeZone: utc)
                     && CleanerSupport.screenshotKeepsDefaultName("Captura de Tela 2026-09-21 às 14.13.20 (2).png",
                                                                  created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("button spacing.png",
                                                                   created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-03-01 at 09.00.00.png",
                                                                   created: taken, timeZone: utc),
                     "a renamed capture is no longer a default screenshot")
        let now = taken.addingTimeInterval(31 * 86_400)
        suite.expect(CleanerSupport.isForgottenScreenshot(created: taken, modified: taken, lastUsed: nil,
                                                          now: now, days: 30)
                     && !CleanerSupport.isForgottenScreenshot(created: taken, modified: taken,
                                                              lastUsed: now.addingTimeInterval(-86_400),
                                                              now: now, days: 30)
                     && !CleanerSupport.isForgottenScreenshot(created: taken, modified: nil, lastUsed: nil,
                                                              now: now, days: 60)
                     && !CleanerSupport.isForgottenScreenshot(created: taken, modified: nil, lastUsed: nil,
                                                              now: now, days: 0),
                     "a screenshot is forgotten only after the chosen days without being opened")
    }

    static func runScreenshotScan(_ suite: TestSuite, root: URL) throws {
        let manager = FileManager.default
        let folder = root.appendingPathComponent("Shots", isDirectory: true)
        try manager.createDirectory(at: folder.appendingPathComponent("Kept"), withIntermediateDirectories: true)
        screenshotFolder = folder
        defer { screenshotFolder = nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let old = Date().addingTimeInterval(-45 * 86_400)
        let oldName = "Screenshot \(formatter.string(from: old)) at 10.00.00.png"
        let newName = "Screenshot \(formatter.string(from: Date())) at 10.00.00.png"
        func capture(_ name: String, in dir: URL = folder, created: Date = old,
                     marked: Bool = true, opened: Date? = nil) throws -> URL {
            let url = dir.appendingPathComponent(name)
            try Data(repeating: 7, count: 8192).write(to: url)
            try manager.setAttributes([.creationDate: created, .modificationDate: created], ofItemAtPath: url.path)
            if marked { setAttribute(CleanerSupport.screenCaptureAttribute, screenCaptureFlag, on: url) }
            if let opened { setAttribute(CleanerSupport.lastUsedDateAttribute, lastUsedAttribute(opened), on: url) }
            return url
        }
        let forgotten = try capture(oldName)
        _ = try capture("plain " + oldName, marked: false)
        _ = try capture("button spacing.png")
        _ = try capture(newName, created: Date())
        _ = try capture(oldName.replacingOccurrences(of: ".png", with: " (2).png"),
                        opened: Date().addingTimeInterval(-86_400))
        let moved = try capture(oldName, in: folder.appendingPathComponent("Kept"))

        let found = scanScreenshots(in: [folder], days: 30)
        suite.expect(found.map { $0.url.resolvingSymlinksInPath().path }
                        == [forgotten.resolvingSymlinksInPath().path]
                     && found.allSatisfy { $0.category == .screenshots && !$0.recommended },
                     "only an old, unopened, marked capture under its own name is listed, unchecked")
        suite.expect(scanScreenshots(in: [folder], days: 60).isEmpty,
                     "a longer age leaves a younger capture alone")
        suite.expect(canRemove(Item(url: forgotten, category: .screenshots, detail: "")),
                     "a listed capture can be moved to the Trash")
        suite.expect(!canRemove(Item(url: moved, category: .screenshots, detail: "")),
                     "a capture outside the top of the screenshot folder is never removed")
        removexattr(forgotten.path, CleanerSupport.screenCaptureAttribute, 0)
        suite.expect(!canRemove(Item(url: forgotten, category: .screenshots, detail: "")),
                     "a file that no longer proves it is a capture is never removed")
    }

    static func run(_ suite: TestSuite) {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("vorssaint-cleaner-\(UUID().uuidString)", isDirectory: true)
        fixtureRoot = root
        defer { fixtureRoot = nil; try? manager.removeItem(at: root) }
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            for category in [CleanerSupport.Category.caches, .logs] {
                let dir = root.appendingPathComponent(category == .caches ? "Library/Caches" : "Library/Logs")
                try manager.createDirectory(at: dir, withIntermediateDirectories: true)
                for name in ["logitec.localized", "Vendor.LoCaLiZeD", "com.vendor.editor"] {
                    let folder = dir.appendingPathComponent(name)
                    try manager.createDirectory(at: folder, withIntermediateDirectories: true)
                    try Data(repeating: 1, count: 4096).write(to: folder.appendingPathComponent("data"))
                }
                var leftovers: [Item] = []
                appendLeftovers(in: dir.path, usesContainerMetadata: false,
                                installed: [], fm: manager, into: &leftovers)
                let claimed = Set(leftovers.map { $0.url.standardizedFileURL.path })
                let found = category == .caches ? scanCaches(excluding: claimed) : scanLogs(excluding: claimed)
                suite.expect(found.isEmpty,
                             "localized folders cannot return as recommended \(category) after leftover scanning")
                let normal = category == .caches ? scanCaches(excluding: []) : scanLogs(excluding: [])
                suite.expect(normal.contains { $0.detail == "com.vendor.editor" && $0.recommended },
                             "ordinary \(category) remain recommended")
                for name in ["logitec.localized", "Vendor.LoCaLiZeD"] {
                    suite.expect(!canRemove(Item(url: dir.appendingPathComponent(name),
                                                 category: category, detail: name, recommended: true)),
                                 "stale recommended \(category) cannot remove \(name)")
                }
            }
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

            runScreenshotRules(suite)
            try runScreenshotScan(suite, root: root)
        } catch {
            suite.expect(false, "cleaner eligibility fixture failed: \(error)")
        }
    }
}
