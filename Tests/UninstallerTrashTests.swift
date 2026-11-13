// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The production offer, selection, matching and removal run in a disposable
/// home. Platform observations, confirmation, scheduling and Trash are local.
enum UninstallerTrashTests {
    typealias DispatchQueue = UninstallerFlowTests.Queue
    typealias HomebrewManager = UninstallerFlowTests.Brew
    typealias HomebrewPackage = UninstallerFlowTests.Package
    typealias QuickToolHUD = UninstallerFlowTests.HUD
    typealias AppFeature = UninstallerFlowTests.Feature

    static var fixtureHome: URL!
    static var fixtureGroups: [URL: Set<String>] = [:]
    static var fixtureSpotlightPaths: [String] = []
    static var afterMovingApp: (() throws -> Void)?

    static func fixtureSigningIdentity(at url: URL, requireValidSignature: Bool)
        -> (teamIDs: Set<String>, groupIDs: Set<String>) {
        ([], fixtureGroups[url] ?? [])
    }

    static func fixtureFolders(home: URL, darwinCache: URL?, darwinTemp: URL?) -> [UninstallerSupport.SearchFolder] {
        UninstallerSupport.searchFolders(home: home, darwinCache: nil, darwinTemp: nil)
            .filter { $0.url.path.hasPrefix(fixtureHome.path + "/") }
    }

    static func moveToFixtureTrash(_ item: URL) throws {
        let path = item.resolvingSymlinksInPath().path
        guard path.hasPrefix(fixtureHome.path + "/Library/") || path.hasPrefix(fixtureHome.path + "/Applications/") else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let trash = UninstallerSupport.trashURL(home: fixtureHome)
        try FileManager.default.moveItem(at: item, to: trash.appendingPathComponent(item.lastPathComponent))
        if item.pathExtension == "app" { try afterMovingApp?() }
    }

    enum InstalledApps {
        struct App { let url: URL; let bundleID: String? }
        static func installedApplications(includeSystemApplications: Bool, spotlightPaths: [String]) -> [App] {
            let folder = fixtureHome.appendingPathComponent("Applications")
            let apps = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return (apps + spotlightPaths.map { URL(fileURLWithPath: $0) }).map {
                App(url: $0, bundleID: UninstallerSupport.bundleIdentifier(of: $0))
            }
        }
    }
    final class NSRunningApplication {
        let bundleIdentifier: String
        let bundleURL: URL?
        init(_ id: String, url: URL? = nil) { bundleIdentifier = id; bundleURL = url }
        func terminate() { preconditionFailure("a Trash cleanup tried to terminate an app") }
        static func runningApplications(withBundleIdentifier id: String) -> [NSRunningApplication] {
            NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == id }
        }
    }
    final class NSWorkspace {
        static let shared = NSWorkspace()
        var frontmostApplication: NSRunningApplication?
        var runningApplications: [NSRunningApplication] = []
        var registered: [String: [URL]] = [:]
        func urlsForApplications(withBundleIdentifier id: String) -> [URL] { registered[id] ?? [] }
        func icon(forFile path: String) -> NSImage { NSImage() }
    }
    final class NSAlert {
        static var response = NSApplication.ModalResponse.alertFirstButtonReturn
        static var presentations = 0
        var messageText = ""
        var informativeText = ""
        func addButton(withTitle title: String) {}
        func runModal() -> NSApplication.ModalResponse {
            Self.presentations += 1
            return Self.response
        }
    }
    enum AppleScriptRunner {
        static func consentToAutomate(bundleID: String) -> Bool { preconditionFailure("unexpected Finder removal") }
        static func literal(_ value: String) -> String { value }
        static func run(_ source: String) -> Bool { false }
    }
    final class CommandBarService {
        static let shared = CommandBarService()
        static func spotlightApplicationPaths() -> [String] { fixtureSpotlightPaths }
        func hasStoredApplicationState(bundleID: String) -> Bool { false }
        func removeApplicationState(bundleIDs: Set<String>, urls: [URL], remainingBundleIDs: Set<String>) {}
    }
    final class SettingsRouter {
        enum Page { case uninstaller }
        static let shared = SettingsRouter()
        var page = Page.uninstaller
    }
    class WindowHost {
        var openings = 0
        func openSettingsWindow() { openings += 1 }
    }
    private static let delegate = Delegate()
    static func appDelegate() -> Delegate? { delegate }

    static func writeBundle(at url: URL, id: String) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": id, "CFBundlePackageType": url.pathExtension == "app" ? "APPL" : "XPC!",
                    "CFBundleName": url.deletingPathExtension().lastPathComponent]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
    }

    static func run(_ suite: TestSuite) {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("uninstaller-trash-\(UUID())", isDirectory: true)
        let model = AppUninstaller.shared
        let brew = HomebrewManager.shared
        let workspace = NSWorkspace.shared
        fixtureHome = home
        defer {
            DispatchQueue.pending = []
            brew.callback = nil
            brew.operation = nil
            brew.checkedURL = nil
            model.reset()
            workspace.registered = [:]
            workspace.frontmostApplication = nil
            workspace.runningApplications = []
            fixtureGroups = [:]
            fixtureSpotlightPaths = []
            afterMovingApp = nil
            fixtureHome = nil
            try? fm.removeItem(at: home)
        }
        do {
            let id = "org.fixture.editor"
            let helperID = "org.fixture.editor.extension"
            let groupID = "group.org.fixture.editor"
            let apps = home.appendingPathComponent("Applications", isDirectory: true)
            let trash = UninstallerSupport.trashURL(home: home)
            let original = apps.appendingPathComponent("Editor.app", isDirectory: true)
            let discarded = trash.appendingPathComponent("Editor.app", isDirectory: true)
            let other = apps.appendingPathComponent("Other.app", isDirectory: true)
            let component = "Contents/PlugIns/Extension.appex"
            let finder = NSRunningApplication("com.apple.finder")
            try fm.createDirectory(at: trash, withIntermediateDirectories: true)
            try writeBundle(at: original, id: id)
            try writeBundle(at: original.appendingPathComponent(component), id: helperID)
            try writeBundle(at: other, id: "org.fixture.other")
            try fm.moveItem(at: original, to: discarded)
            guard let identity = UninstallerSupport.fileIdentity(at: discarded) else {
                throw CocoaError(.fileReadUnknown)
            }
            func witnessed(from source: URL, destinationID: UInt64, destinationInode: UInt64) -> UninstallerSupport.TrashMove? {
                var events = UninstallerSupport.TrashRenames()
                _ = events.accept(source, inode: identity.inode, eventID: 100, home: home)
                return events.accept(discarded, inode: destinationInode, eventID: destinationID, home: home)
            }
            let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
            try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
            suite.expect(witnessed(from: downloads.appendingPathComponent("Editor.app"), destinationID: 101,
                                  destinationInode: identity.inode) == nil
                         && witnessed(from: original, destinationID: 103, destinationInode: identity.inode) == nil
                         && witnessed(from: original, destinationID: 101, destinationInode: identity.inode &+ 1) == nil,
                         "discarded downloads, intervening moves and unrelated inodes do not grant ownership")
            guard let move = witnessed(from: original, destinationID: 101, destinationInode: identity.inode) else {
                suite.expect(false, "a move between the temporary Applications folder and Trash must be recognized")
                return
            }
            suite.expect(!model.select(appURL: discarded) && model.refusal?.refusal == .unverifiedTrashMove,
                         "manual selection of a discarded app cannot open its data for removal")
            fixtureGroups[discarded] = [groupID]
            let prefs = home.appendingPathComponent("Library/Preferences/\(id).plist")
            let extPrefs = home.appendingPathComponent("Library/Preferences/\(helperID).plist")
            let named = home.appendingPathComponent("Library/Application Support/Editor", isDirectory: true)
            let group = home.appendingPathComponent("Library/Group Containers/\(groupID)", isDirectory: true)
            for url in [named, group, prefs.deletingLastPathComponent()] {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
            for url in [prefs, extPrefs] { try Data("fixture".utf8).write(to: url) }
            func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }
            func openReview() {
                model.reset()
                Watcher.offer(move)
                DispatchQueue.drain()
                brew.callback?(.success(nil))
            }
            func confirm() {
                model.setAllIncluded(true)
                NSAlert.response = .alertSecondButtonReturn
                model.removeSelected()
            }
            let initialOpenings = delegate.openings
            workspace.frontmostApplication = finder
            _ = model.select(appURL: other)
            Watcher.offer(move)
            DispatchQueue.drain()
            brew.callback?(.success(nil))
            model.setAllIncluded(false)
            let otherRows = model.items
            Watcher.offer(move)
            suite.expect(delegate.openings == initialOpenings && model.target?.url == other
                         && model.phase == .results && model.items == otherRows,
                         "another app arriving during a scan or manual review preserves the active target and choices")
            model.reset()
            workspace.frontmostApplication = NSRunningApplication("org.fixture.updater")
            Watcher.offer(move)
            workspace.frontmostApplication = finder
            workspace.runningApplications = [NSRunningApplication(id, url: original)]
            Watcher.offer(move)
            workspace.runningApplications = []
            let copy = downloads.appendingPathComponent("Editor Copy.app", isDirectory: true)
            try writeBundle(at: copy, id: id)
            workspace.registered[id] = [discarded, copy]
            Watcher.offer(move)
            suite.expect(delegate.openings == initialOpenings && model.phase == .empty,
                         "background moves, a running editor and a registered live copy do not open a review")
            try fm.removeItem(at: copy)
            workspace.registered[id] = [original, discarded]
            openReview()
            let paths = Set(model.items.map { $0.url.path })
            suite.expect(delegate.openings == initialOpenings + 1 && brew.checkedURL == original
                         && model.phase == .results && !model.canRemoveSelected
                         && paths == Set([prefs, extPrefs, named, group].map(\.path))
                         && model.items.allSatisfy { !$0.include && $0.category != .app },
                         "moving the last copy opens its data checklist, with every row unchecked and no app row")
            model.setAllIncluded(true)
            let selected = model.items
            Watcher.offer(move)
            suite.expect(delegate.openings == initialOpenings + 1 && model.items == selected,
                         "the watcher leaves an active checklist and its selection intact")
            NSAlert.response = .alertFirstButtonReturn
            model.removeSelected()
            DispatchQueue.drain()
            suite.expect(model.phase == .results && [prefs, extPrefs, named, group, discarded].allSatisfy(exists),
                         "cancelling the intent confirmation preserves the entire selection")
            confirm()
            brew.callback?(.failure(.unavailable))
            DispatchQueue.drain()
            suite.expect(model.phase == .done(freed: 0, failed: selected) && exists(prefs),
                         "a failed final package check preserves the data")
            openReview()
            confirm()
            brew.callback?(.success(HomebrewPackage(id: "editor")))
            DispatchQueue.drain()
            suite.expect(exists(prefs) && exists(named) && brew.checkedURL == original,
                         "a cask claiming the original install path at confirmation protects its files")
            openReview()
            confirm()
            brew.callback?(.success(nil))
            try writeBundle(at: original, id: id)
            DispatchQueue.drain()
            suite.expect([prefs, extPrefs, named, group, discarded].allSatisfy(exists),
                         "a replacement arriving after confirmation keeps its profile, old helpers and groups")
            try fm.removeItem(at: original)
            openReview()
            confirm()
            brew.callback?(.success(nil))
            try writeBundle(at: copy, id: id)
            fixtureSpotlightPaths = [copy.path]
            DispatchQueue.drain()
            suite.expect([prefs, extPrefs, named, group].allSatisfy(exists),
                         "an unregistered Spotlight copy keeps even name-only data associated with an old helper")
            try fm.removeItem(at: copy)
            fixtureSpotlightPaths = []
            openReview()
            confirm()
            // The other app keeps its original top-level plist and directory.
            // Its extension and group first appear after the review was built.
            try writeBundle(at: other.appendingPathComponent(component), id: helperID)
            fixtureGroups[other] = [groupID]
            brew.callback?(.success(nil))
            DispatchQueue.drain()
            suite.expect(exists(extPrefs) && exists(group) && exists(discarded)
                         && !exists(prefs) && !exists(named)
                         && exists(trash.appendingPathComponent(prefs.lastPathComponent))
                         && exists(trash.appendingPathComponent(named.lastPathComponent)),
                         "confirmation rereads nested owners and groups, and moves only exclusive data to the fixture Trash")

            model.reset()
            try fm.moveItem(at: discarded, to: original)
            try fm.moveItem(at: trash.appendingPathComponent(prefs.lastPathComponent), to: prefs)
            try fm.moveItem(at: trash.appendingPathComponent(named.lastPathComponent), to: named)
            _ = model.select(appURL: original)
            DispatchQueue.drain()
            brew.callback?(.success(nil))
            model.setAllIncluded(true)
            guard let appRow = model.items.first(where: { $0.category == .app }),
                  model.items.contains(where: { $0.url.path == named.path }) else {
                suite.expect(false, "a manually selected installation offers the app and its exclusive named data")
                return
            }
            model.setInclude(false, for: appRow.id)
            let manualRows = model.items.filter(\.include)
            model.removeSelected()
            try writeBundle(at: copy, id: id)
            fixtureSpotlightPaths = [copy.path]
            DispatchQueue.drain()
            suite.expect(model.phase == .done(freed: 0, failed: manualRows)
                         && [original, copy, prefs, extPrefs, named, group].allSatisfy(exists),
                         "manual confirmation preserves all selected data once another primary copy exists")
            try fm.removeItem(at: copy)
            fixtureSpotlightPaths = []
            for reinstall in [true, false] {
                model.reset()
                _ = model.select(appURL: original)
                DispatchQueue.drain()
                brew.callback?(.success(nil))
                model.setAllIncluded(true)
                afterMovingApp = reinstall ? { try writeBundle(at: original, id: id) } : nil
                model.removeSelected()
                DispatchQueue.drain()
                suite.expect(exists(original) == reinstall && exists(prefs) == reinstall && exists(named) == reinstall,
                             "manual removal rechecks the target between the app and data rows (reinstall: \(reinstall))")
                if reinstall {
                    try fm.moveItem(at: discarded, to: trash.appendingPathComponent("Previous Editor.app"))
                }
            }
        } catch {
            suite.expect(false, "Trash review fixture failed: \(error)")
        }
    }
}
