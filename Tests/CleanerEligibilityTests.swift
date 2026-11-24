// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

extension CleanerEligibilityTests.Item {
    init(url: URL, category: CleanerSupport.Category = .leftovers, detail: String, recommended: Bool = false) {
        self.init(url: url, category: category, size: 1, detail: detail, recommended: recommended)
    }
}

/// The generated scanners and removal guards use temporary home and system
/// libraries and a controlled app inventory. No cleaning is performed.
enum CleanerEligibilityTests {
    static var fixtureRoot: URL?
    static func NSHomeDirectory() -> String { fixtureRoot!.path }
    static var systemLibrary: String {
        fixtureRoot!.deletingLastPathComponent().appendingPathComponent("Library").path
    }

    struct NSWorkspace {
        static let shared = NSWorkspace()
        func urlForApplication(withBundleIdentifier _: String) -> URL? { nil }
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

    private static func leftovers(in directory: URL, installed: Set<String>, metadata: Bool = false) -> [Item] {
        var items: [Item] = []
        appendLeftovers(in: directory, usesContainerMetadata: metadata,
                        installed: installed, audioPluginIDs: [], fm: .default, into: &items)
        return items
    }

    private static func checkSupportDirectories(_ suite: TestSuite, home: URL) throws {
        let manager = FileManager.default
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let battle = support.appendingPathComponent("Battle.net", isDirectory: true)
        let versions = battle.appendingPathComponent("Versions", isDirectory: true)
        try manager.createDirectory(at: versions, withIntermediateDirectories: true)
        try manager.createDirectory(at: support.appendingPathComponent("Battle.net.plist"),
                                    withIntermediateDirectories: true)
        try Data([1]).write(to: support.appendingPathComponent("maker.com"))

        let other = home.deletingLastPathComponent()
            .appendingPathComponent("another-user/Library/Application Support/Battle.net", isDirectory: true)
        try manager.createDirectory(at: other, withIntermediateDirectories: true)
        let shared = URL(fileURLWithPath: systemLibrary, isDirectory: true)
            .appendingPathComponent("Application Support/Battle.net", isDirectory: true)
        try manager.createDirectory(at: shared, withIntermediateDirectories: true)
        let battlePath = battle.resolvingSymlinksInPath().path
        let sharedPath = shared.resolvingSymlinksInPath().path
        let otherPath = other.resolvingSymlinksInPath().path
        let before = scanLeftovers(installedApps: [], audioPluginIDs: [])
        suite.expect(!before.contains { $0.url.resolvingSymlinksInPath().path == otherPath }
                     && !canRemove(Item(url: other, detail: "Battle.net")),
                     "another user's support directory is outside the scan and removal roots")
        guard let row = before.first(where: { $0.url.resolvingSymlinksInPath().path == battlePath }),
              let sharedRow = before.first(where: { $0.url.resolvingSymlinksInPath().path == sharedPath }) else {
            suite.expect(false, "unowned support directories in both libraries are offered for review")
            return
        }
        suite.expect([row, sharedRow].allSatisfy { $0.detail == "Battle.net" && !$0.recommended && canRemove($0) },
                     "an uninstalled app's domain directories are optional leftovers")
        let installed: Set<String> = ["net.battle.app", "com.maker"]
        let found = scanLeftovers(installedApps: installed, audioPluginIDs: [])
        suite.expect(!found.contains { $0.url.lastPathComponent == "Battle.net" }
                     && !canRemove(row, installed: installed) && !canRemove(sharedRow, installed: installed),
                     "an installed Battle.net is protected in both libraries at scan and after a stale selection")
        suite.expect(Set(found.map { $0.url.lastPathComponent }) == ["Battle.net.plist", "maker.com"]
                     && found.allSatisfy { canRemove($0, installed: installed) },
                     "only the raw name of a support directory establishes reverse ownership")
    }

    private static func checkOrphanedAgents(_ suite: TestSuite, home: URL) throws {
        let agents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: agents, withIntermediateDirectories: true)
        let program = home.appendingPathComponent("agent-helper")
        func launchPlist(_ label: String, program: URL) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: ["Label": label, "Program": program.path],
                                              format: .xml, options: 0)
        }
        for label in ["test.editor", "editor.test"] {
            try launchPlist(label, program: program)
                .write(to: agents.appendingPathComponent(label + ".plist"))
        }
        let systemAgents = URL(fileURLWithPath: systemLibrary).appendingPathComponent("LaunchAgents")
        try manager.createDirectory(at: systemAgents, withIntermediateDirectories: true)
        let liveProgram = home.appendingPathComponent("live-agent-helper")
        try Data([1]).write(to: liveProgram)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: liveProgram.path)
        try launchPlist("test.editor", program: liveProgram)
            .write(to: systemAgents.appendingPathComponent("test.editor.plist"))

        let apps: Set<String> = ["editor.test"]
        let found = CleanerScanFlowTests.scanFixture(installedApps: apps).filter { $0.category == .loginItems }
        let orphan = agents.appendingPathComponent("test.editor.plist")
        guard found.count == 1, let item = found.first, item.url == orphan,
              item.detail == "test.editor", item.include else {
            suite.expect(false, "only the orphaned user plist is listed when a live system agent has the same label")
            return
        }

        func expectProtected(installed: Set<String>, _ reason: String) {
            let fresh = CleanerScanFlowTests.scanFixture(installedApps: installed)
            let (phase, actions) = CleanerScanFlowTests.cleanFixture(item, installedApps: installed)
            suite.expect(!fresh.contains { $0.url == item.url } && actions.isEmpty
                         && phase == .done(freed: 0, failed: 1),
                         "\(reason) protects the previously selected agent from bootout and Trash")
        }
        expectProtected(installed: apps.union(["test.editor.app"]), "installing its app")

        let plugin = home.appendingPathComponent("Library/Audio/Plug-Ins/Components/Editor.component")
        let contents = plugin.appendingPathComponent("Contents")
        try manager.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "test.editor.instrument"],
                                           format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        expectProtected(installed: apps, "installing its plugin")
        try manager.removeItem(at: plugin)

        try Data([1]).write(to: program)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: program.path)
        expectProtected(installed: apps, "restoring its executable")
        let moved = home.appendingPathComponent("moved-helper")
        try manager.moveItem(at: program, to: moved)

        let (phase, actions) = CleanerScanFlowTests.cleanFixture(item, installedApps: apps)
        suite.expect(actions == [.trash(orphan)] && phase == .done(freed: item.size, failed: 0),
                     "cleaning the orphaned plist preserves the service with the same label")

        let handle = try FileHandle(forWritingTo: item.url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: launchPlist(item.detail, program: moved))
        suite.expect(item.fileIdentity == UninstallerSupport.fileIdentity(at: item.url),
                     "updating Program in place preserves the selected plist's identity")
        expectProtected(installed: apps, "pointing the same plist at a living executable")
    }

    private static func checkUnresolvableAgentExecutable(_ suite: TestSuite, home: URL) throws {
        let directory = home.appendingPathComponent("helper-directory")
        let program = directory.appendingPathComponent("agent")
        let agents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let plist = agents.appendingPathComponent("local.fixture.plist")
        try PropertyListSerialization.data(fromPropertyList: ["Label": "local.fixture", "Program": program.path],
                                           format: .xml, options: 0).write(to: plist)
        guard let item = scanOrphanedLaunchPlists(installed: []).first(where: { $0.url == plist && $0.include }) else {
            suite.expect(false, "a confirmed missing executable makes the fixture eligible")
            return
        }

        // A loop in an ancestor makes the executable lookup fail even for a privileged test runner.
        try FileManager.default.createSymbolicLink(atPath: directory.path, withDestinationPath: directory.path)
        let fresh = scanOrphanedLaunchPlists(installed: [])
        let (phase, actions) = CleanerScanFlowTests.cleanFixture(item, installedApps: [])
        suite.expect(!fresh.contains { $0.url == plist } && actions.isEmpty && phase == .done(freed: 0, failed: 1),
                     "an unresolvable executable protects the agent on rescan and before any cleanup action")
    }

    /// Scan the same fixture before and after a plugin is installed. Leftovers
    /// claim paths first, then the cache and log scanners consider the rest.
    private static func checkAudioPlugins(_ suite: TestSuite, home: URL) throws {
        let manager = FileManager.default
        func plugin(_ path: String, id: String, in library: URL = home.appendingPathComponent("Library")) throws {
            let contents = library.appendingPathComponent(path).appendingPathComponent("Contents")
            try manager.createDirectory(at: contents, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id],
                                               format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
        }
        let apps: Set<String> = ["com.synthmaker.editor", "org.paper.canvas"]
        let synth = "com.synthmaker.Synth"
        let reverb = "com.reverbco.Reverb"
        let compressor = "io.github.compco.Compressor"
        let sibling = "com.reverbco.Delay"
        let family = [synth, synth + ".state", "com.synthmaker", reverb]
        let ordinary = ["com.synthmaker.Editor", synth + "Lab", "org.paper.Canvas", "Homebrew", "com.reverbco.2026"]
        let optional = ["ms-playwright", "PlainVendorFolder", "com.apple.Music"]
        let excluded = "CloudKit.fixture"
        let hostedLog = "io.github.compco.log"
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        for name in family + ordinary + optional + [sibling, excluded, hostedLog] {
            let folder = caches.appendingPathComponent(name, isDirectory: true)
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 7, count: 4096).write(to: folder.appendingPathComponent("license.fixture"))
        }
        let logs = home.appendingPathComponent("Library/Logs", isDirectory: true)
        let reports = logs.appendingPathComponent("DiagnosticReports", isDirectory: true)
        try manager.createDirectory(at: reports, withIntermediateDirectories: true)
        let vendorLogs = [sibling + ".log", reverb, reverb + ".log", reverb + ".helper.log", hostedLog]
        let commonLogs = ["installer.log", "org.paper.Canvas.log"]
        for name in vendorLogs + commonLogs + ["DiagnosticReports/report.ips"] {
            try Data(repeating: 7, count: 4096).write(to: logs.appendingPathComponent(name))
        }
        let systemLogs = URL(fileURLWithPath: systemLibrary).appendingPathComponent("Logs", isDirectory: true)
        try manager.createDirectory(at: systemLogs, withIntermediateDirectories: true)
        let systemLog = systemLogs.appendingPathComponent(sibling + ".log")
        try Data(repeating: 7, count: 4096).write(to: systemLog)
        let preferences = home.appendingPathComponent("Library/Preferences", isDirectory: true)
        try manager.createDirectory(at: preferences, withIntermediateDirectories: true)
        let preference = preferences.appendingPathComponent(reverb + ".plist")
        let orphan = preferences.appendingPathComponent("com.gonevendor.Delay.plist")
        try Data().write(to: preference)
        try Data().write(to: orphan)

        func matches(_ item: Item, _ url: URL) -> Bool {
            item.url.resolvingSymlinksInPath().path == url.resolvingSymlinksInPath().path
        }
        let before = CleanerScanFlowTests.scanFixture(installedApps: apps)
        guard let oldCache = before.first(where: { $0.category == .caches && $0.detail == synth }),
              let oldLeftoverCache = before.first(where: { matches($0, caches.appendingPathComponent(reverb)) }),
              let oldPreference = before.first(where: { matches($0, preference) }) else {
            suite.expect(false, "the fixture must offer the two caches and preference before plugin installation")
            return
        }
        suite.expect(oldCache.recommended && canRemove(oldCache, installed: apps),
                     "the Synth cache starts recommended while a same-vendor app is installed")
        suite.expect([oldLeftoverCache, oldPreference].allSatisfy {
            $0.category == .leftovers && !$0.recommended && canRemove($0, installed: apps)
        }, "without an installed Reverb, its cache and preference are optional leftovers")

        try plugin("Audio/Plug-Ins/Components/Synth.component", id: synth)
        try plugin("Audio/Plug-Ins/VST3/Vendor/Suite/Reverbs/Reverb.vst3", id: reverb,
                   in: URL(fileURLWithPath: systemLibrary))
        try plugin("Application Support/Avid/Audio/Plug-Ins/Comp.aaxplugin", id: compressor,
                   in: URL(fileURLWithPath: systemLibrary))
        try plugin("Audio/Plug-Ins/Components/Readme.txt.d", id: "com.ignored.NotAPlugin")
        let pluginIDs = installedAudioPluginBundleIDs()
        suite.expect(pluginIDs == [synth.lowercased(), reverb.lowercased(), compressor.lowercased()],
                     "the inventory includes deeply nested plugins and reads both libraries")

        let after = CleanerScanFlowTests.scanFixture(installedApps: apps)
        let manual = CleanerScanFlowTests.scanFixture(installedApps: apps, attended: true)
        suite.expect(before.contains { matches($0, systemLog) && $0.category == .leftovers
                         && !canRemove($0, installed: apps, audioPluginIDs: pluginIDs) }
                     && !after.contains { matches($0, systemLog) },
                     "system logs have no second scan and retain plugin ownership at removal")
        suite.expect(!after.contains { matches($0, preference) }
                     && after.contains { matches($0, orphan) && $0.category == .leftovers },
                     "only the uninstalled plugin's preference is offered")
        suite.expect(!canRemove(oldCache, installed: apps, audioPluginIDs: pluginIDs),
                     "installing Synth protects a stale recommended cache even in a cache-only selection")
        suite.expect([oldLeftoverCache, oldPreference].allSatisfy {
            !canRemove($0, installed: apps, audioPluginIDs: pluginIDs)
        }, "installing Reverb protects its cache and preference even after a stale leftover selection")
        let listedCaches = after.filter { CleanerSupport.isDirectChild($0.url, of: caches) }
        let vendorApps = apps.union([reverb.lowercased(), compressor.lowercased()])
        let withApp = CleanerScanFlowTests.scanFixture(installedApps: vendorApps)
        let vendorRows: [(CleanerSupport.Category, URL)] =
            [sibling, hostedLog].map { (.caches, caches.appendingPathComponent($0)) }
            + vendorLogs.map { (.logs, logs.appendingPathComponent($0)) }
        for (category, url) in vendorRows {
            let name = url.lastPathComponent
            let original = before.filter { matches($0, url) }
            let pluginOnly = after.filter { matches($0, url) }
            let reviewed = manual.filter { matches($0, url) }
            let vendorInstalled = withApp.filter { matches($0, url) }
            guard original.count == 1, var initial = original.first,
                  pluginOnly.count == 1, let automatic = pluginOnly.first,
                  reviewed.count == 1, var optional = reviewed.first,
                  vendorInstalled.count == 1, let recommended = vendorInstalled.first else {
                suite.expect(false, "every scan returns one row for \(category)/\(name)")
                continue
            }
            suite.expect([initial, automatic, optional].allSatisfy {
                $0.category == .leftovers && !$0.recommended && !$0.include
            }, "installing the plugin alone keeps \(category)/\(name) unchecked in manual and unattended scans")
            initial.include = true
            optional.include = true
            suite.expect(canRemove(initial, installed: apps, audioPluginIDs: pluginIDs),
                         "installing the plugin preserves the explicit selection of \(category)/\(name)")
            suite.expect(canRemove(optional, installed: apps, audioPluginIDs: pluginIDs),
                         "the freshly reviewed \(category)/\(name) is eligible for manual removal")
            suite.expect(!canRemove(optional, installed: vendorApps, audioPluginIDs: pluginIDs),
                         "installing the app invalidates the leftover selection of \(category)/\(name)")
            suite.expect(recommended.category == category && recommended.recommended && recommended.include
                         && canRemove(recommended, installed: vendorApps, audioPluginIDs: pluginIDs)
                         && !canRemove(recommended, installed: apps, audioPluginIDs: pluginIDs),
                         "removing the app invalidates the earlier recommendation for \(category)/\(name)")
        }
        for name in family + [excluded] {
            suite.expect(!listedCaches.contains { $0.url.lastPathComponent == name }
                         && !CleanerPolicy.precheckCacheEntry(name, audioPluginIDs: pluginIDs),
                         "neither leftovers nor recommended caches offer \(name)")
        }
        var appLookups = Set<String>()
        func currentApps(for name: String) -> Set<String> {
            appLookups.insert(name)
            return apps
        }
        for name in ordinary {
            suite.expect(listedCaches.contains {
                $0.detail == name && $0.category == .caches && $0.recommended && $0.include
                    && canRemove($0, installed: currentApps(for: name), audioPluginIDs: pluginIDs)
            }, "an ordinary cache remains selected in an unattended scan: \(name)")
        }
        for name in optional {
            suite.expect(listedCaches.contains { row in
                var selected = row
                selected.include = true
                return row.detail == name && row.category == .caches && !row.recommended && !row.include
                    && canRemove(selected, installed: currentApps(for: name), audioPluginIDs: pluginIDs)
            }, "a review-only cache remains unchecked and can be selected manually: \(name)")
        }
        for name in commonLogs + ["DiagnosticReports"] {
            let rows = after.filter { matches($0, logs.appendingPathComponent(name)) }
            suite.expect(rows.count == 1 && rows.allSatisfy {
                $0.category == .logs && $0.recommended && $0.include
                    && canRemove($0, installed: currentApps(for: name), audioPluginIDs: pluginIDs)
            }, "ordinary logs remain selected and removable: \(name)")
        }
        suite.expect(appLookups == ["com.synthmaker.Editor", synth + "Lab"],
                     "ordinary logs and caches skip the app inventory unless they share a plugin owner or vendor")
        for category in [CleanerSupport.Category.caches, .leftovers] {
            let stale = Item(url: caches.appendingPathComponent(excluded), category: category, detail: excluded)
            suite.expect(!canRemove(stale, installed: apps, audioPluginIDs: pluginIDs),
                         "an excluded cache cannot be removed through \(category)")
        }
    }

    static func run(_ suite: TestSuite) {
        var loads = 0
        for ids in [Set<String>(), ["com.fixture.editor"]] {
            let previousLoads = loads
            let installedApps = cachedAppLookup {
                loads += 1
                return ids
            }
            suite.expect(loads == previousLoads, "creating a cleanup leaves the app inventory unread")
            suite.expect(installedApps() == ids && installedApps() == ids && loads == previousLoads + 1,
                         "each cleanup reads its own inventory once, including an empty inventory")
        }
        let manager = FileManager.default
        let sandbox = manager.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("vorssaint-cleaner-\(UUID().uuidString)", isDirectory: true)
        let root = sandbox.appendingPathComponent("user", isDirectory: true)
        fixtureRoot = root
        defer { fixtureRoot = nil; try? manager.removeItem(at: sandbox) }
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            try checkSupportDirectories(suite, home: root)
            try checkOrphanedAgents(suite, home: root)
            try checkUnresolvableAgentExecutable(suite, home: root)
            let installed: Set<String> = ["editor.test"]
            for category in [CleanerSupport.Category.caches, .logs] {
                let dir = root.appendingPathComponent(category == .caches ? "Library/Caches" : "Library/Logs")
                try manager.createDirectory(at: dir, withIntermediateDirectories: true)
                for name in ["logitec.localized", "Vendor.LoCaLiZeD", "com.vendor.editor", "test.editor"] {
                    let folder = dir.appendingPathComponent(name)
                    try manager.createDirectory(at: folder, withIntermediateDirectories: true)
                    try Data(repeating: 1, count: 4096).write(to: folder.appendingPathComponent("data"))
                }
                let optional = leftovers(in: dir, installed: installed)
                suite.expect(optional.contains {
                    $0.detail == "test.editor" && !$0.recommended && canRemove($0, installed: installed)
                },
                             "a reversed id cannot promote an optional \(category) leftover to scheduled cleanup")
                let claimed = Set(optional.map { $0.url.standardizedFileURL.path })
                let found = category == .caches
                    ? scanCaches(excluding: claimed, audioPluginIDs: []) : scanLogs(excluding: claimed)
                suite.expect(found.isEmpty,
                             "localized and already claimed entries cannot return as recommended \(category)")
                let normal = category == .caches
                    ? scanCaches(excluding: [], audioPluginIDs: []) : scanLogs(excluding: [])
                suite.expect(normal.contains { $0.detail == "com.vendor.editor" && $0.recommended },
                             "ordinary \(category) remain recommended")
                for name in ["logitec.localized", "Vendor.LoCaLiZeD"] {
                    suite.expect(!canRemove(Item(url: dir.appendingPathComponent(name),
                                                 category: category, detail: name, recommended: true)),
                                 "stale recommended \(category) cannot remove \(name)")
                }
            }
            let preferences = root.appendingPathComponent("Library/Preferences", isDirectory: true)
            try manager.createDirectory(at: preferences, withIntermediateDirectories: true)
            for name in ["logitec.localized", "Logitech.localized", "Vendor.LoCaLiZeD",
                         "com.vendor.editor.localized"] {
                let folder = preferences.appendingPathComponent(name, isDirectory: true)
                try manager.createDirectory(at: folder, withIntermediateDirectories: false)
                suite.expect(owner(folder) == nil,
                             "localized directory \(name) is not offered as an app leftover")
                suite.expect(!canRemove(Item(url: folder, detail: name)),
                             "a previously listed localized directory \(name) cannot be removed")
            }

            for id in ["com.vendor.editor", "com.vendor.localized.editor", "com.vendor.localized", "io.app", "test.editor"] {
                let preference = preferences.appendingPathComponent(id + ".plist")
                try Data().write(to: preference)
                suite.expect(owner(preference) == id,
                             "a real preference file retains its exact owner \(id)")
                suite.expect(canRemove(Item(url: preference, detail: id), installed: installed),
                             "an unowned preference for \(id) remains eligible after scanning")
                suite.expect(!canRemove(Item(url: preference, detail: id), installed: [id]),
                             "preferences for an installed owner \(id) remain protected")
            }

            let containers = root.appendingPathComponent("Library/Containers", isDirectory: true)
            for id in ["com.vendor.localized", "test.editor", "editor.test"] {
                let container = containers.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try manager.createDirectory(at: container, withIntermediateDirectories: true)
                try PropertyListSerialization.data(fromPropertyList: ["MCMMetadataIdentifier": id],
                                                   format: .xml, options: 0)
                    .write(to: container.appendingPathComponent(".com.apple.containermanagerd.metadata.plist"))
            }
            let found = leftovers(in: containers, installed: installed, metadata: true)
            suite.expect(Set(found.map(\.detail)) == ["com.vendor.localized", "test.editor"]
                         && found.allSatisfy { canRemove($0, installed: installed) },
                         "container metadata protects the actual owner and keeps unrelated leftovers eligible")

            runScreenshotRules(suite)
            try runScreenshotScan(suite, root: root)
            try checkAudioPlugins(suite, home: root)
        } catch {
            suite.expect(false, "cleaner eligibility fixture failed: \(error)")
        }
    }
}
