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
    // The real ones read this Mac's temporary folder and processes.
    static var launchCopyFixture: String?
    static var runningExecutables: [String] = []
    static func launchCopyRoot() -> String? { launchCopyFixture }
    static func runningExecutablePaths() -> [String] { runningExecutables }
    static var browserLaunches: [String: [Date?]] = [:]
    static func launchDates(of owner: String) -> [Date?] { browserLaunches[owner] ?? [] }
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
        // A rename that keeps the name macOS gave it and adds to it is still a
        // rename. Duplicating a capture in Finder is the everyday case, and the
        // day period on a twelve hour Mac has to survive the same check.
        suite.expect(CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 2.13.20\u{202F}PM.png",
                                                               created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 14.13.20 copy.png",
                                                                   created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 2.13.20\u{202F}PM copy.png",
                                                                   created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 14.13.20 ui.png",
                                                                   created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 14.13.20 ok.png",
                                                                   created: taken, timeZone: utc)
                     // A mark is a rename too, and must not reduce to the empty
                     // tail that an untouched twenty four hour name carries.
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 14.13.20 !.png",
                                                                   created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 14.13.20 \u{1F525}.png",
                                                                   created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 2.13.20\u{202F}PM!.png",
                                                                   created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 2.13.20\u{202F}PM \u{2B50}.png",
                                                                   created: taken, timeZone: utc)
                     // A single letter is a day period in some locale, so only
                     // a twelve hour clock may carry one: 14.13.20 cannot.
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 14.13.20 M.png",
                                                                   created: taken, timeZone: utc)
                     // An invisible character is not the absence of a suffix.
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 14.13.20 \u{200B}.png",
                                                                   created: taken, timeZone: utc)
                     // The day periods themselves keep working, spacing and all.
                     && CleanerSupport.screenshotKeepsDefaultName("Captura de pantalla 2026-09-21 a las 2.13.20 p. m..png",
                                                                  created: taken, timeZone: utc)
                     && CleanerSupport.screenshotKeepsDefaultName("\u{622A}\u{5C4F}2026-09-21 2.13.20\u{4E0B}\u{5348}.png",
                                                                  created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("button spacing 2026-09-21.png",
                                                                   created: taken, timeZone: utc),
                     "a capture renamed by adding to its name is no longer a default screenshot")
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

    /// Copies of one browser as Chromium leaves them (#3612): one the running
    /// browser executes from, two of an old version, each an APFS clone.
    static func runLaunchCopies(_ suite: TestSuite, root: URL) throws {
        let manager = FileManager.default
        let x = root.appendingPathComponent("X", isDirectory: true)
        let owner = x.appendingPathComponent("com.example.Browser.code_sign_clone", isDirectory: true)
        launchCopyFixture = x.path
        defer { launchCopyFixture = nil; runningExecutables = []; browserLaunches = [:] }
        let original = root.appendingPathComponent("Original.bin")
        try Data((0..<600_000).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: original)
        func copy(_ name: String, created: Date) throws -> URL {
            let url = owner.appendingPathComponent("code_sign_clone." + name, isDirectory: true)
            let contents = url.appendingPathComponent("Browser.app.bundle/Contents", isDirectory: true)
            try manager.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleName": "Browser",
                                                                  "CFBundleShortVersionString": "9.1"],
                                               format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            // copyItem clones on APFS, so the copies share their blocks.
            try manager.copyItem(at: original, to: contents.appendingPathComponent("MacOS/Browser"))
            try manager.setAttributes([.creationDate: created], ofItemAtPath: url.path)
            return url
        }
        let older = try copy("aaaaaa", created: Date(timeIntervalSinceNow: -7_200))
        let newer = try copy("bbbbbb", created: Date(timeIntervalSinceNow: -3_600))
        let inUse = try copy("cccccc", created: Date(timeIntervalSinceNow: -10_800))
        try manager.createDirectory(at: owner.appendingPathComponent("unrelated"), withIntermediateDirectories: true)
        runningExecutables = ["/private" + inUse.path + "/Browser.app.bundle/Contents/MacOS/Browser"]

        let found = scanLaunchCopies()
        suite.expect(found.map(\.url.path) == [older.path, newer.path]
                && found.allSatisfy { $0.category == .launchCopies && $0.recommended && $0.detail == "Browser 9.1" },
               "leftover launch copies are listed oldest first, without the one a browser runs from")
        suite.expect(found.first?.size ?? 0 > 500_000 && (found.last?.size ?? 1) < found.first?.size ?? 0,
               "copies sharing one version count it once instead of once per copy: \(found.map(\.size))")
        suite.expect(canRemove(Item(url: older, category: .launchCopies, detail: "")),
               "a leftover launch copy can be moved to the Trash")
        suite.expect(!canRemove(Item(url: inUse, category: .launchCopies, detail: "")),
               "the copy a running browser executes from is never removed, under either spelling of its path")
        runningExecutables = [older.path + "/Browser.app.bundle/Contents/MacOS/Browser"]
        suite.expect(!canRemove(Item(url: older, category: .launchCopies, detail: "")),
               "a browser launched from a copy after the scan keeps it")
        // The browser running, without saying which copy it runs from: copies
        // made since it launched are kept, older ones are leftovers.
        runningExecutables = []
        browserLaunches = ["com.example.Browser": [Date(timeIntervalSinceNow: -5_000)]]
        suite.expect(scanLaunchCopies().map(\.url.path) == [inUse.path, older.path]
                && canRemove(Item(url: older, category: .launchCopies, detail: ""))
                && !canRemove(Item(url: newer, category: .launchCopies, detail: "")),
               "a copy made since its browser launched is kept even when no process names it")
        browserLaunches = ["com.example.Browser": [nil]]
        suite.expect(scanLaunchCopies().isEmpty && !canRemove(Item(url: older, category: .launchCopies, detail: "")),
               "a running browser whose launch cannot be read keeps all its copies")
        browserLaunches = [:]
        suite.expect(CleanerSupport.launchCopyMayBelongToRunningBrowser(created: nil, browserLaunches: [Date()])
                && !CleanerSupport.launchCopyMayBelongToRunningBrowser(created: Date(), browserLaunches: [])
                && CleanerSupport.launchCopyMayBelongToRunningBrowser(
                    created: Date(timeIntervalSinceNow: -30), browserLaunches: [Date()]),
               "an unreadable date keeps a copy, a browser not running keeps none, a minute's slack before launch")
        suite.expect(!canRemove(Item(url: owner, category: .launchCopies, detail: ""))
                && !canRemove(Item(url: owner.appendingPathComponent("unrelated"), category: .launchCopies, detail: "")),
               "only a copy itself is ever removed, never its browser's folder or anything else in it")
        let unique = root.appendingPathComponent("Unique", isDirectory: true)
        try manager.createDirectory(at: unique, withIntermediateDirectories: true)
        try Data((0..<600_000).map { UInt8(truncatingIfNeeded: $0 &* 17) }).write(to: unique.appendingPathComponent("data"))
        let alone = exclusiveSize(of: unique, fm: manager)
        try manager.copyItem(at: unique.appendingPathComponent("data"), to: unique.appendingPathComponent("clone"))
        suite.expect(alone >= 600_000 && exclusiveSize(of: unique, fm: manager) < alone,
               "a file's own blocks count until a clone shares them: \(alone)")
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

            for id in ["com.vendor.editor", "com.vendor.localized.editor", "com.vendor.localized", "io.app"] {
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
            try runLaunchCopies(suite, root: root)
        } catch {
            suite.expect(false, "cleaner eligibility fixture failed: \(error)")
        }
    }
}
