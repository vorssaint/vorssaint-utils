// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine

/// Production selection and command-bar transitions run with controlled scan
/// callbacks. Files are disposable bundles; no installed apps or Trash are used.
enum UninstallerFlowTests {
    struct Leftover: Equatable {
        let id = UUID()
        let url: URL
        var include = true
    }
    struct Target {
        let name: String
        let bundleID: String?
        let url: URL
        let icon: NSImage
    }
    final class Observation {
        var canceled = false
        func cancel() { canceled = true }
    }
    enum Queue {
        enum QoS { case userInitiated }
        static var pending: [() -> Void] = []
        static var main: Queue.Type { Self.self }
        static func global(qos: QoS) -> Queue.Type { Self.self }
        static func async(execute: @escaping () -> Void) { pending.append(execute) }
        static func drain() {
            while !pending.isEmpty { pending.removeFirst()() }
        }
    }
    struct Package: Equatable {
        let id: String
        var displayName: String { id }
    }
    final class Brew {
        struct Status {
            enum Action { case uninstall }
            enum Result { case running, succeeded }
            let action: Action
            let package: Package?
            let result: Result
        }
        static let shared = Brew()
        var callback: ((Package?) -> Void)?
        @Published var operationStatus: Status?
        var operation: Status?
        var uninstalled: [String] = []
        func packageManagingApplication(at url: URL, completion: @escaping (Package?) -> Void) {
            callback = completion
        }
        func clearLog() {}
        func uninstall(_ package: Package) { uninstalled.append(package.id) }
    }
    enum HUD {
        static var messages: [String] = []
        static func show(icon: String, message: String) { messages.append(message) }
    }
    class UninstallerState {
        typealias DispatchQueue = Queue
        typealias HomebrewManager = Brew
        typealias HomebrewPackage = Package
        typealias QuickToolHUD = HUD
        typealias L10n = Localization
        var phase: Phase = .empty
        var target: Target?
        var homebrewPackage: Package?
        var homebrewRemovalSize: Int64 = 0
        var homebrewRemovedApplication = false
        var homebrewRemovalObservation: AnyCancellable?
        var targetFileIdentity: UninstallerSupport.FileIdentity?
        var targetInfoIdentity: UninstallerSupport.FileIdentity?
        var allowedRemovalPaths = Set<String>()
        var items: [Leftover] = []
        var isRemovingWithHomebrew = false
        var selectedHomebrewPackage: Package? { homebrewPackage }
        static func allBundleIDs(in url: URL, fm: FileManager) -> Set<String> { [] }
        static func knownApplicationURLs(candidateBundleIDs: Set<String>) -> [URL] { [] }
        static func applicationBundleIdentifiers(in urls: [URL]) -> [String] { [] }
        static func exclusiveOwnedBundleIDs(in url: URL, candidates: Set<String>, knownApplicationIDs: [String]) -> Set<String> { [] }
        static func signingIdentity(in url: URL, requireValidSignature: Bool) -> (teamIDs: Set<String>, groupIDs: Set<String>) { ([], []) }
        static func exclusiveGroupIDs(_ ids: Set<String>, selectedURL: URL, knownApplications: [URL]) -> Set<String> { [] }
        static func collect(appURL: URL, primaryBundleID: String, exclusiveBundleIDs: Set<String>, teamIDs: Set<String>, exclusiveGroupIDs: Set<String>) -> [Leftover] {
            [Leftover(url: appURL)]
        }
        static func applicationIdentityMatches(_ url: URL, appIdentity: UninstallerSupport.FileIdentity?, infoIdentity: UninstallerSupport.FileIdentity?) -> Bool {
            UninstallerSupport.fileIdentity(at: url) == appIdentity
                && UninstallerSupport.fileIdentity(at: url.appendingPathComponent("Contents/Info.plist")) == infoIdentity
        }
        func removeSelected() { if !items.isEmpty { phase = .removing } }
        func finishRemovalAfterHomebrew(package: Package) {}
    }
    enum Feature {
        case uninstaller
        static var available = true
        var isAvailable: Bool { Self.available }
    }
    final class Preferences {
        static let standard = Preferences()
        var enabled = true
        func bool(forKey: String) -> Bool { enabled }
    }
    final class Localization {
        static let shared = Localization()
        let s = Text()
        struct Text {
            let uninstallerRemoving = "Removing"
            let uninstallerSelectionUnavailable = "Unavailable"
            let uninstallerConfirmationExpired = "Expired"
        }
    }
    enum Permission {
        enum Target { case finder }
        enum Status { case granted, undetermined, denied }
        static var status: Status = .undetermined
        static func automationStatus(for target: Target) -> Status { status }
    }
    enum Script {
        static var requests = 0
        static var reads = 0
        static func consentToAutomate(bundleID: String) -> Bool {
            requests += 1
            return Permission.status == .granted
        }
        static func run(_ source: String) -> (ok: Bool, output: String) {
            reads += 1
            return (true, "/Applications/Fixture.app\n")
        }
    }
    enum Finder {
        typealias Permissions = Permission
        typealias AppleScriptRunner = Script
        static let finderBundleID = "com.apple.finder"
    }
    class ServiceState {
        typealias AppUninstaller = Uninstaller
        typealias AppFeature = Feature
        typealias UserDefaults = Preferences
        typealias L10n = Localization
        var mode: Mode = .search
        var uninstallWarning: String?
        var uninstallFinderRequestID: UUID?
        var queryBeforeCompletion: String?
        var completedQuery: String?
        var savedQuery = ""
        var aliasWarning: String?
        var activeCategory: String?
        var isPeekingHome = false
        var cachedApps: [InstalledApps.InstalledApp] = []
        struct Entry { let uninstallAppURL: URL? }
        var uninstallSelectionEntries: [Entry] = []
        func rebuildRunningEntries() {}
        var submissions = 0
        func refreshResults() {}
        func refreshPanelLayout() {}
        func entry(withID: String) -> (id: String, other: Bool)? { nil }
        func leaveActions() { mode = .search }
        func endCapturingShortcut() {}
        func setCategory(_ value: String?) { activeCategory = value }
        func hide() { mode = .search }
        func runSelected() { submissions += 1 }
    }

    static func run(_ suite: TestSuite) {
        for status in [Permission.Status.undetermined, .denied] {
            Permission.status = status
            suite.expect(Finder.selectionURLs(requestPermission: false).isEmpty
                         && Script.requests == 0 && Script.reads == 0,
                         "passive Finder lookup never asks for missing consent")
        }
        Permission.status = .granted
        suite.expect(Finder.selectionURLs(requestPermission: false).count == 1
                     && Script.requests == 0 && Script.reads == 1,
                     "existing Finder permission allows the contextual selection")
        _ = Finder.selectionURLs(requestPermission: true)
        suite.expect(Script.requests == 1, "explicit Finder action is the consent boundary")
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("uninstaller-flow-\(UUID())")
        defer {
            Queue.pending = []
            Brew.shared.callback = nil
            Uninstaller.shared.isRemovingWithHomebrew = false
            Uninstaller.shared.phase = .empty
            Uninstaller.shared.reset()
            try? fm.removeItem(at: root)
        }
        do {
            func makeApp(_ name: String) throws -> URL {
                let url = root.appendingPathComponent(name + ".app", isDirectory: true)
                let contents = url.appendingPathComponent("Contents", isDirectory: true)
                try fm.createDirectory(at: contents, withIntermediateDirectories: true)
                let data = try PropertyListSerialization.data(fromPropertyList: [
                    "CFBundleIdentifier": "org.vorssaint.fixture.\(name)",
                    "CFBundlePackageType": "APPL", "CFBundleName": name,
                ], format: .xml, options: 0)
                try data.write(to: contents.appendingPathComponent("Info.plist"))
                return url
            }
            let a = try makeApp("First")
            let b = try makeApp("Second")
            let uninstaller = Uninstaller.shared
            let service = Service()
            service.query = "First"
            service.beginUninstallReview(appURL: a, entryID: "a")
            suite.expect(service.mode == .uninstallReview(entryID: "a") && uninstaller.phase == .scanning,
                         "accepted selection opens its review")
            Queue.drain()
            let lateScan = Brew.shared.callback
            service.stepBack()
            lateScan?(nil)
            suite.expect(uninstaller.phase == .empty && uninstaller.target == nil,
                         "canceling while scanning prevents its late result from returning")
            service.beginUninstallReview(appURL: a, entryID: "a")
            Queue.drain()
            Brew.shared.callback?(nil)
            suite.expect(uninstaller.phase == .results && uninstaller.items.count == 1,
                         "current scan delivers the accepted app")
            uninstaller.phase = .removing
            let originalItems = uninstaller.items
            service.stepBack()
            service.beginUninstallReview(appURL: b, entryID: "b")
            suite.expect(service.mode == .search && service.uninstallWarning == "Removing"
                         && uninstaller.target?.url == a && uninstaller.items == originalItems,
                         "choosing another app after leaving a removal preserves the active operation")
            uninstaller.reset()
            suite.expect(uninstaller.phase == .removing && uninstaller.target?.url == a,
                         "other surfaces cannot reset an active plain removal")
            uninstaller.setInclude(false, for: originalItems[0].id)
            suite.expect(uninstaller.items == originalItems, "an active removal keeps its captured selection")
            uninstaller.phase = .results
            uninstaller.isRemovingWithHomebrew = true
            uninstaller.homebrewPackage = Package(id: "first")
            let observation = Observation()
            uninstaller.homebrewRemovalObservation = AnyCancellable(observation.cancel)
            service.beginUninstallReview(appURL: b, entryID: "b")
            uninstaller.reset()
            suite.expect(!observation.canceled && uninstaller.target?.url == a && uninstaller.homebrewPackage?.id == "first",
                         "a new selection or reset cannot discard package cleanup in progress")
            uninstaller.isRemovingWithHomebrew = false
            uninstaller.phase = .done(freed: 1, failed: [])
            uninstaller.reset()
            suite.expect(uninstaller.phase == .empty && observation.canceled,
                         "a finished operation can be dismissed normally")
            service.beginUninstallReview(appURL: root.appendingPathComponent("Missing.app"), entryID: "missing")
            suite.expect(service.mode == .search && service.uninstallWarning == "Unavailable",
                         "a vanished application reports rejection without opening an empty review")
            let link = root.appendingPathComponent("Link.app")
            try fm.createSymbolicLink(at: link, withDestinationURL: b)
            suite.expect(!uninstaller.select(appURL: link), "a symlink cannot be accepted as a removable bundle")
            service.beginUninstallReview(appURL: b, entryID: "b")
            service.mode = .uninstallHomebrewConfirm(entryID: "b")
            service.uninstallFinderRequestID = UUID()
            service.query = "A new search"
            suite.expect(service.mode == .search && uninstaller.phase == .empty && service.query == "A new search",
                         "typing or pasting a new query leaves both uninstall steps and preserves that query")
            suite.expect(service.uninstallFinderRequestID == nil,
                         "new search cancels a pending explicit Finder action")
            for key in [kVK_Tab, kVK_Space, kVK_UpArrow, kVK_DownArrow] {
                suite.expect(!service.handleUninstallKey(key, searchFieldFocused: false),
                             "checklist key \(key) reaches the native control")
            }
            suite.expect(!service.handleUninstallKey(kVK_Return, searchFieldFocused: false)
                         && service.submissions == 0,
                         "Return on a focused control cannot submit removal instead")
            suite.expect(service.handleUninstallKey(kVK_Return, searchFieldFocused: true)
                         && service.submissions == 1,
                         "Return in the search field retains the review action")
            service.mode = .uninstallHomebrewConfirm(entryID: "b")
            suite.expect(service.handleUninstallKey(kVK_Escape, searchFieldFocused: false)
                         && service.mode == .uninstallReview(entryID: "b"),
                         "Escape cancels just the package confirmation")
            service.mode = .search
            Preferences.standard.enabled = false
            service.beginUninstallReview(appURL: b, entryID: "b")
            suite.expect(service.mode == .search, "disabling the toggle rejects a previously offered row")
            Preferences.standard.enabled = true
            Feature.available = false
            service.beginUninstallReview(appURL: b, entryID: "b")
            suite.expect(service.mode == .search, "uninstalling the feature rejects a previously offered row")
            Feature.available = true
            uninstaller.reset()
            _ = uninstaller.select(appURL: a)
            Queue.drain()
            Brew.shared.callback?(Package(id: "first"))
            if let confirmation = uninstaller.homebrewRemovalConfirmation, let app = uninstaller.items.first {
                uninstaller.setInclude(false, for: app.id)
                uninstaller.removeSelectedWithHomebrew(confirmation: confirmation)
                uninstaller.setInclude(true, for: app.id)
                uninstaller.homebrewPackage = Package(id: "second")
                uninstaller.removeSelectedWithHomebrew(confirmation: confirmation)
                uninstaller.homebrewPackage = Package(id: "first")
                let shownTarget = uninstaller.target
                uninstaller.target = Target(name: "Second", bundleID: nil, url: b, icon: NSImage())
                uninstaller.removeSelectedWithHomebrew(confirmation: confirmation)
                uninstaller.target = shownTarget
                suite.expect(Brew.shared.uninstalled.isEmpty && HUD.messages.count == 3,
                             "a Homebrew confirmation for other rows, another package or another app runs nothing, found \(Brew.shared.uninstalled)")
                uninstaller.removeSelectedWithHomebrew(confirmation: confirmation)
                suite.expect(Brew.shared.uninstalled == ["first"],
                             "an unchanged Homebrew confirmation runs its package")
            } else {
                suite.expect(false, "a Homebrew-managed app offers a package confirmation")
            }
            service.cachedApps = [a, b].map {
                InstalledApps.InstalledApp(id: $0.path, name: $0.lastPathComponent,
                                          bundleID: nil, url: $0, isSystem: false)
            }
            service.uninstallSelectionEntries = [ServiceState.Entry(uninstallAppURL: b)]
            _ = uninstaller.select(appURL: b)
            uninstaller.phase = .done(freed: 0, failed: [Leftover(url: b)])
            service.finishUninstallReview()
            suite.expect(service.cachedApps.count == 2 && service.uninstallSelectionEntries.count == 1,
                         "failed removals keep the still-installed app in both lists")
            _ = uninstaller.select(appURL: b)
            try fm.removeItem(at: b)
            uninstaller.phase = .done(freed: 1, failed: [])
            service.finishUninstallReview()
            suite.expect(service.cachedApps.map(\.url) == [a] && service.uninstallSelectionEntries.isEmpty,
                         "a confirmed removal disappears from the browse list and Finder shortcut")
            suite.expect(Defaults.registeredDefaults[DefaultsKey.uninstallerCommandBarEnabled] as? Bool == false,
                         "the integration starts off")
            suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.uninstallerCommandBarEnabled),
                         "backup includes the command-bar preference")
        } catch {
            suite.expect(false, "uninstaller fixture failed: \(error)")
        }
    }
}
