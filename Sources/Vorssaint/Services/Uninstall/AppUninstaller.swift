// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreServices
import Darwin
import Security

/// Finds the files an app leaves around — caches, preferences, logs, support
/// folders, containers, preference panes, plugins — and removes only what you
/// pick. Ordinary files go to the Trash; after an extra confirmation, a
/// package-managed app is delegated to its package manager before the remaining
/// choices go to the Trash.
final class AppUninstaller: ObservableObject {
    static let shared = AppUninstaller()

    enum Phase: Equatable {
        case empty
        case scanning
        case results
        case removing
        case done(freed: Int64, failed: [Leftover])
    }

    struct Target: Equatable {
        let name: String
        let bundleID: String?
        let url: URL
        let icon: NSImage

        static func == (lhs: Target, rhs: Target) -> Bool { lhs.url == rhs.url }
    }

    enum Category: Int, CaseIterable {
        case app, support, caches, preferences, containers, logs, state, other

        var sortRank: Int { rawValue }
    }

    struct Leftover: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let category: Category
        let size: Int64
        let ownerBundleID: String?
        let ownerGroupID: String?
        let evidenceBundleID: String?
        let confidence: UninstallerSupport.LeftoverMatch
        let fileIdentity: UninstallerSupport.FileIdentity
        var include: Bool = true

        var name: String { url.lastPathComponent }

        static func == (lhs: Leftover, rhs: Leftover) -> Bool {
            lhs.id == rhs.id && lhs.include == rhs.include
        }
    }

    @Published private(set) var phase: Phase = .empty
    @Published private(set) var target: Target?
    @Published private(set) var homebrewPackage: HomebrewPackage?
    @Published private(set) var homebrewCheckFailed = false
    /// The app the last selection turned down, so the empty state can say
    /// why instead of springing back in silence (#1582). An accepted
    /// selection or a reset clears it.
    @Published private(set) var refusal: UninstallerSupport.RefusedApp?
    @Published var items: [Leftover] = []
    private var allowedRemovalPaths = Set<String>()
    private var targetSelection: UninstallerSupport.Selection?
    private var targetTrashMove: UninstallerSupport.TrashMove?
    private var homebrewRemovalSize: Int64 = 0
    private var homebrewRemovedApplication = false
    private var homebrewRemovalObservation: AnyCancellable?
    private var scanCancellation: UninstallerSupport.ScanCancellation?

    private struct ScanCandidate {
        let url: URL
        let category: Category
        let ownerBundleID: String?
        let ownerGroupID: String?
        let evidenceBundleID: String?
        let confidence: UninstallerSupport.LeftoverMatch
        var include: Bool
    }

    private init() {}

    var selectedSize: Int64 { items.filter(\.include).reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedHomebrewPackage: HomebrewPackage? {
        guard items.contains(where: { $0.category == .app && $0.include }) else { return nil }
        return homebrewPackage
    }
    var isRemovingWithHomebrew: Bool {
        guard let package = selectedHomebrewPackage,
              let status = HomebrewManager.shared.operationStatus else { return false }
        return status.action == .uninstall
            && status.package?.id == package.id
            && status.isActive
    }

    /// An unsolicited offer must not replace a checklist the person is using.
    func canOfferTrashCleanup(of move: UninstallerSupport.TrashMove) -> Bool {
        switch phase {
        case .empty, .done:
            return targetSelection?.identity != move.selection.identity && Self.trashMoveIsCurrent(move)
        case .scanning, .results, .removing:
            return false
        }
    }

    private static func trashMoveIsCurrent(_ move: UninstallerSupport.TrashMove) -> Bool {
        let id = move.selection.bundleID
        return move.isLastCopy(registered: NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id),
                               running: !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty,
                               home: FileManager.default.homeDirectoryForCurrentUser)
    }

    var isRemoving: Bool {
        phase == .removing || isRemovingWithHomebrew
    }

    var canRemoveSelected: Bool {
        phase == .results && !isRemoving && !homebrewCheckFailed
            && items.contains(where: \.include)
    }

    /// What the Homebrew confirmation showed, since the panel, Settings and the
    /// command bar share this uninstaller and can change it while it is open.
    struct HomebrewRemovalConfirmation {
        let package: HomebrewPackage
        let targetURL: URL
        let selectedIDs: Set<UUID>
    }

    var homebrewRemovalConfirmation: HomebrewRemovalConfirmation? {
        guard canRemoveSelected,
              let package = selectedHomebrewPackage, let target else { return nil }
        return HomebrewRemovalConfirmation(package: package, targetURL: target.url,
                                           selectedIDs: Set(items.filter(\.include).map(\.id)))
    }

    // MARK: - Selection & scan

    /// Reads an app bundle and starts scanning for its leftovers.
    @discardableResult
    func select(appURL: URL, trashMove: UninstallerSupport.TrashMove? = nil) -> Bool {
        guard !isRemoving else { return false }
        let selection: UninstallerSupport.Selection
        switch UninstallerSupport.evaluate(appURL) {
        case let .success(accepted):
            selection = accepted
        case let .failure(reason):
            refusal = UninstallerSupport.RefusedApp(name: UninstallerSupport.appName(at: appURL),
                                                    refusal: reason)
            return false
        }
        refusal = nil
        let bundleID = selection.bundleID
        let selectedURL = selection.url
        let name = UninstallerSupport.appName(at: appURL)
        let isTrashed = UninstallerSupport.isInTrash(selectedURL, home: FileManager.default.homeDirectoryForCurrentUser)
        if isTrashed || trashMove != nil {
            guard let trashMove, trashMove.selection == selection,
                  HomebrewManager.shared.operation == nil, Self.trashMoveIsCurrent(trashMove) else {
                refusal = UninstallerSupport.RefusedApp(name: name, refusal: .unverifiedTrashMove)
                return false
            }
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)

        target = Target(name: name, bundleID: bundleID, url: selectedURL, icon: icon)
        targetSelection = selection
        targetTrashMove = trashMove
        homebrewPackage = nil
        homebrewCheckFailed = false
        homebrewRemovalSize = 0
        homebrewRemovedApplication = false
        homebrewRemovalObservation?.cancel()
        homebrewRemovalObservation = nil
        items = []
        allowedRemovalPaths = []
        // A new selection supersedes any scan still running, even for the
        // same app, so only this scan can deliver results.
        scanCancellation?.cancel()
        let cancellation = UninstallerSupport.ScanCancellation()
        scanCancellation = cancellation
        phase = .scanning

        // Homebrew takes about as long to answer as the scan, so both start
        // now and the results show once each has finished, in either order.
        // Both callbacks run on the main queue, so these need no lock.
        var scanned: [Leftover]?
        var ownership: Result<HomebrewPackage?, HomebrewOwnershipError>?
        let deliverWhenReady = { [weak self] in
            // Drop the result if the user picked a different app (or reset)
            // while this scan was running — never show A's files under B.
            guard let self, let found = scanned, let result = ownership,
                  !cancellation.isCancelled,
                  self.phase == .scanning, self.target?.url == selectedURL else { return }
            guard selection.isCurrent else {
                self.reset()
                return
            }
            if let trashMove {
                guard Self.trashMoveIsCurrent(trashMove),
                      HomebrewManager.shared.operation == nil else {
                    self.reset()
                    self.refusal = UninstallerSupport.RefusedApp(name: name, refusal: .unverifiedTrashMove)
                    return
                }
                // A cask still owning the original installation path may be
                // updating or waiting to reinstall its app. Keep its data.
                if case .success(.some) = result {
                    self.reset()
                    self.refusal = UninstallerSupport.RefusedApp(name: name, refusal: .unverifiedTrashMove)
                    return
                }
            }
            self.items = found
            switch result {
            case let .success(package):
                self.homebrewPackage = package
                self.homebrewCheckFailed = false
            case .failure:
                self.homebrewPackage = nil
                self.homebrewCheckFailed = true
            }
            self.allowedRemovalPaths = Set(found.map { $0.url.standardizedFileURL.path })
            self.scanCancellation = nil
            self.phase = .results
        }
        HomebrewManager.shared.packageManagingApplication(at: trashMove?.originalURL ?? selectedURL) { result in
            ownership = result
            deliverWhenReady()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            guard !cancellation.isCancelled else { return }
            let ownedBundleIDs = Self.allBundleIDs(in: selectedURL, fm: .default)
            let trusted = trashMove != nil || UninstallerSupport.applicationIsInTrustedInstallRoot(
                selectedURL, home: FileManager.default.homeDirectoryForCurrentUser)
            let knownApplications = trusted
                ? Self.knownApplicationURLs(candidateBundleIDs: ownedBundleIDs)
                : []
            let knownApplicationIDs = Self.applicationBundleIdentifiers(in: knownApplications)
            // If the primary app survives, even an old exclusive helper must
            // not claim its live parent's profile through a display-name match.
            let mayClaimSharedData = trusted && UninstallerSupport.sharedDataIsExclusive(
                selectedURL: selectedURL, bundleID: bundleID, knownApplications: knownApplicationIDs)
            let exclusiveBundleIDs = mayClaimSharedData
                ? Self.exclusiveOwnedBundleIDs(
                    in: selectedURL, candidates: ownedBundleIDs,
                    knownApplicationIDs: knownApplicationIDs)
                : []
            guard !cancellation.isCancelled else { return }
            let signing = Self.signingIdentity(in: selectedURL, requireValidSignature: true)
            let exclusiveGroupIDs = mayClaimSharedData
                ? Self.exclusiveGroupIDs(
                    signing.groupIDs, selectedURL: selectedURL,
                    knownApplications: knownApplications)
                : []
            let found = Self.collect(appURL: selectedURL,
                                     primaryBundleID: bundleID,
                                     exclusiveBundleIDs: exclusiveBundleIDs,
                                     teamIDs: signing.teamIDs,
                                     exclusiveGroupIDs: exclusiveGroupIDs,
                                     cancellation: cancellation)
            guard !cancellation.isCancelled else { return }
            DispatchQueue.main.async {
                scanned = found
                deliverWhenReady()
            }
        }
        return true
    }

    func setInclude(_ include: Bool, for id: UUID) {
        guard !isRemoving else { return }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].include = include
    }

    /// What the select-all checkbox above the results shows for the rows.
    var bulkSelection: UninstallerSupport.BulkSelection {
        UninstallerSupport.BulkSelection(included: items.filter(\.include).count, total: items.count)
    }

    /// Checks or clears every detected file at once. Like a single row, it
    /// refuses to change a removal that already started.
    func setAllIncluded(_ include: Bool) {
        guard !isRemoving else { return }
        var updated = items
        for index in updated.indices {
            updated[index].include = include
        }
        items = updated
    }

    func retryHomebrewCheck() {
        guard phase == .results, homebrewCheckFailed, let target else { return }
        select(appURL: target.url, trashMove: targetTrashMove)
    }

    /// Drops the refusal note, for an uninstaller view that opens or closes.
    func clearRefusal() {
        refusal = nil
    }

    func reset() {
        guard !isRemoving else { return }
        refusal = nil
        scanCancellation?.cancel()
        scanCancellation = nil
        target = nil
        targetSelection = nil
        targetTrashMove = nil
        homebrewPackage = nil
        homebrewCheckFailed = false
        homebrewRemovalSize = 0
        homebrewRemovedApplication = false
        homebrewRemovalObservation?.cancel()
        homebrewRemovalObservation = nil
        items = []
        allowedRemovalPaths = []
        phase = .empty
    }

    // MARK: - Removal

    func removeSelected() {
        guard canRemoveSelected, selectedHomebrewPackage == nil else { return }
        let chosen = items.filter(\.include)
        guard !chosen.isEmpty, let selection = targetSelection else { return }
        if let move = targetTrashMove {
            guard HomebrewManager.shared.operation == nil, Self.trashMoveIsCurrent(move) else {
                phase = .done(freed: 0, failed: chosen)
                return
            }
            // The rename has no author. During a non-atomic update the install
            // path can still be empty, just as it is after an uninstall.
            let alert = NSAlert()
            alert.messageText = target?.name ?? move.selection.url.lastPathComponent
            alert.informativeText = L10n.shared.s.uninstallerConfirmTrashCleanup
            alert.addButton(withTitle: L10n.shared.s.uninstallerCancel)
            alert.addButton(withTitle: L10n.shared.s.uninstallerRemove)
            guard alert.runModal() == .alertSecondButtonReturn,
                  canRemoveSelected, targetTrashMove == move, items.filter(\.include) == chosen else { return }
            phase = .removing
            HomebrewManager.shared.packageManagingApplication(at: move.originalURL) { [weak self] result in
                guard let self else { return }
                guard case .success(nil) = result, HomebrewManager.shared.operation == nil,
                      Self.trashMoveIsCurrent(move) else {
                    self.phase = .done(freed: 0, failed: chosen)
                    return
                }
                self.remove(chosen, selection: selection, trashMove: move)
            }
            return
        }
        phase = .removing
        remove(chosen, selection: selection, trashMove: nil)
    }

    private func remove(_ chosen: [Leftover], selection: UninstallerSupport.Selection,
                        trashMove: UninstallerSupport.TrashMove?) {
        let targetURL = selection.url
        let targetBundleID = selection.bundleID
        // Quit the app and any background app embedded inside it before the
        // bundle moves. Embedded helpers do not always share the main bundle ID.
        if trashMove == nil, selection.isCurrent {
            for app in NSWorkspace.shared.runningApplications where
                app.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == targetURL
                || UninstallerSupport.isNestedBundle(app.bundleURL, in: targetURL) {
                app.terminate()
            }
        }

        let allowedPaths = allowedRemovalPaths
        let candidateBundleIDs = Set(chosen.compactMap(\.ownerBundleID))
        let candidateGroupIDs = Set(chosen.compactMap(\.ownerGroupID))
        let evidenceBundleIDs = Set(chosen.compactMap(\.evidenceBundleID))
        let alreadyFreed = homebrewRemovalSize
        let packageRemovedApplication = homebrewRemovedApplication

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) { [weak self] in
            let fm = FileManager.default
            var freed = alreadyFreed
            var stubborn: [Leftover] = []
            var failed: [Leftover] = []
            let targetIsOriginal = selection.isCurrent
            let targetWasRemovedByPackageManager = packageRemovedApplication
                && UninstallerSupport.isConfirmedAbsent(at: targetURL)
            let mayClaimSharedData = (targetIsOriginal || targetWasRemovedByPackageManager)
                && (!candidateBundleIDs.isEmpty || !candidateGroupIDs.isEmpty)
            let lookupBundleIDs = candidateBundleIDs.union(evidenceBundleIDs).union([targetBundleID])
            // Only the shared-data claims below read this roster, and building
            // it opens every installed app. Same gate `select()` already uses.
            let knownApplications = mayClaimSharedData
                ? Self.knownApplicationURLs(candidateBundleIDs: lookupBundleIDs)
                : []
            let knownApplicationIDs = Self.applicationBundleIdentifiers(in: knownApplications)
            let canRemoveData = mayClaimSharedData && UninstallerSupport.sharedDataIsExclusive(
                selectedURL: targetURL, bundleID: targetBundleID, knownApplications: knownApplicationIDs)
            let exclusiveBundleIDs = canRemoveData ? Self.exclusiveOwnedBundleIDs(
                in: targetURL, candidates: candidateBundleIDs, knownApplicationIDs: knownApplicationIDs,
                requiresCurrentOwnership: !targetWasRemovedByPackageManager) : []
            let exclusiveEvidenceBundleIDs = canRemoveData ? UninstallerSupport.exclusiveBundleIDs(
                evidenceBundleIDs, selectedURL: targetURL, knownApplications: knownApplicationIDs) : []
            let currentGroupIDs: Set<String>
            if targetIsOriginal && !candidateGroupIDs.isEmpty {
                currentGroupIDs = Self.signingIdentity(
                    in: targetURL, requireValidSignature: true).groupIDs
                    .intersection(candidateGroupIDs)
            } else if targetWasRemovedByPackageManager {
                currentGroupIDs = candidateGroupIDs
            } else {
                currentGroupIDs = []
            }
            let exclusiveGroupIDs = canRemoveData ? Self.exclusiveGroupIDs(
                currentGroupIDs, selectedURL: targetURL, knownApplications: knownApplications) : []
            var removedTarget = targetWasRemovedByPackageManager
            func targetAllowsRemoval(of item: Leftover) -> Bool {
                if let trashMove {
                    return item.category != .app && Self.trashMoveIsCurrent(trashMove)
                }
                // A replacement can arrive during the inventory or between
                // rows. Only this uninstall's own move can explain an absence.
                if removedTarget && item.category != .app {
                    return UninstallerSupport.isConfirmedAbsent(at: targetURL)
                }
                return selection.isCurrent
            }
            for item in chosen {
                guard targetAllowsRemoval(of: item) else {
                    failed.append(item)
                    continue
                }
                if item.category != .app {
                    let keepsOwnership: Bool
                    if let groupID = item.ownerGroupID {
                        keepsOwnership = exclusiveGroupIDs.contains(groupID)
                    } else if let bundleID = item.ownerBundleID {
                        let evidenceIsExclusive = item.evidenceBundleID.map(
                            exclusiveEvidenceBundleIDs.contains) ?? true
                        keepsOwnership = exclusiveBundleIDs.contains(bundleID)
                            && evidenceIsExclusive
                    } else {
                        keepsOwnership = false
                    }
                    guard keepsOwnership else {
                        failed.append(item)
                        continue
                    }
                }
                guard Self.removalIsStillSafe(item.url,
                                              expectedIdentity: item.fileIdentity,
                                              allowedPaths: allowedPaths,
                                              targetURL: targetURL) else {
                    // The package manager or another pass may have taken the path.
                    // Only a confirmed absence counts as success; a still-present
                    // path, or one we can no longer read, stays a failure.
                    if UninstallerSupport.isConfirmedAbsent(at: item.url) {
                        freed += item.size
                    } else {
                        failed.append(item)
                    }
                    continue
                }
                do {
                    try fm.trashItem(at: item.url, resultingItemURL: nil)
                    if item.category == .app { removedTarget = true }
                    freed += item.size
                } catch {
                    if UninstallerSupport.isConfirmedAbsent(at: item.url) {
                        freed += item.size
                    } else if trashMove == nil, fm.fileExists(atPath: item.url.path) {
                        // Finder can wait indefinitely at an admin prompt. Only
                        // delegate a regular uninstall; a replacement may appear
                        // while Finder is waiting on a Trash cleanup.
                        stubborn.append(item)
                    } else {
                        failed.append(item)
                    }
                }
            }

            // Items we lack rights for (root-owned apps, /Library files) go
            // through Finder, which shows the administrator prompt and moves
            // them to the Trash exactly like a drag would. One batch, one
            // prompt; afterwards whatever still exists counts as failed.
            if !stubborn.isEmpty {
                let stillSafe = stubborn.filter {
                    targetAllowsRemoval(of: $0)
                        && Self.removalIsStillSafe($0.url,
                                                   expectedIdentity: $0.fileIdentity,
                                                   allowedPaths: allowedPaths,
                                                   targetURL: targetURL)
                }
                failed.append(contentsOf: stubborn.filter { item in
                    !stillSafe.contains(where: { $0.id == item.id })
                })
                Self.trashViaFinder(stillSafe.map(\.url))
                for item in stillSafe {
                    if UninstallerSupport.isConfirmedAbsent(at: item.url) {
                        freed += item.size
                    } else {
                        failed.append(item)
                    }
                }
            }

            DispatchQueue.main.async {
                // The user may have dismissed the flow while files moved.
                guard let self, self.phase == .removing else { return }
                self.items = []
                self.phase = .done(freed: freed, failed: failed)
                if trashMove == nil {
                    Self.removeCommandBarState(ofRemovedAppAt: targetURL, bundleID: targetBundleID)
                }
            }
        }
    }

    /// After Homebrew has removed its package receipt and app artifact, clean
    /// only the other items the person selected. The app itself is excluded so
    /// this flow never tries to remove the same bundle twice.
    func removeSelectedWithHomebrew(confirmation: HomebrewRemovalConfirmation) {
        guard canRemoveSelected,
              target?.url == confirmation.targetURL,
              targetSelection?.isCurrent == true,
              selectedHomebrewPackage?.id == confirmation.package.id,
              Set(items.filter(\.include).map(\.id)) == confirmation.selectedIDs else {
            QuickToolHUD.show(icon: "exclamationmark.circle",
                              message: L10n.shared.s.uninstallerConfirmationExpired)
            return
        }
        let package = confirmation.package
        let manager = HomebrewManager.shared
        guard manager.operation == nil else { return }
        homebrewRemovalObservation?.cancel()
        homebrewRemovalObservation = manager.$operationStatus
            .dropFirst()
            .compactMap { $0 }
            .filter { $0.action == .uninstall && $0.package?.id == package.id }
            .sink { [weak self] status in
                guard status.result != .running else { return }
                self?.homebrewRemovalObservation?.cancel()
                self?.homebrewRemovalObservation = nil
                if status.result == .succeeded {
                    self?.finishRemovalAfterHomebrew(package: package)
                }
            }
        manager.uninstall(package, fromUninstaller: true)
        if manager.operation == nil { homebrewRemovalObservation = nil }
    }

    private func finishRemovalAfterHomebrew(package: HomebrewPackage) {
        guard phase == .results,
              homebrewPackage?.id == package.id,
              let app = items.first(where: { $0.category == .app && $0.include }),
              let targetURL = target?.url else { return }
        // Completion is published before the stored status stops reading as
        // active. Clear the package before changing the guarded selection,
        // and credit the app only after its absence is confirmed.
        homebrewRemovedApplication = true
        homebrewPackage = nil
        setInclude(false, for: app.id)
        if UninstallerSupport.isConfirmedAbsent(at: targetURL) {
            homebrewRemovalSize = app.size
        } else if FileManager.default.fileExists(atPath: targetURL.path) {
            // Package removal succeeded but left the bundle. Re-select only the
            // app so removeSelected can finish it under the package flag,
            // counting size once when it is actually gone.
            homebrewRemovalSize = 0
            setInclude(true, for: app.id)
        } else {
            // A failed lookup is not proof of removal. Keep the failure visible.
            homebrewRemovalSize = 0
            homebrewRemovedApplication = false
            setInclude(true, for: app.id)
            phase = .done(freed: 0, failed: [app])
            return
        }
        if items.contains(where: \.include) {
            removeSelected()
        } else {
            phase = .done(freed: homebrewRemovalSize, failed: [])
            Self.removeCommandBarState(ofRemovedAppAt: targetURL, bundleID: target?.bundleID)
        }
    }

    /// A remaining copy keeps the preferences shared under its bundle ID.
    /// Only apps with shared preferences need the folder and Spotlight scan;
    /// path-specific state can go without it, even while the bar is disabled.
    private static func removeCommandBarState(ofRemovedAppAt url: URL, bundleID: String?) {
        let bundleIDs: Set<String> = bundleID.map {
            CommandBarService.shared.hasStoredApplicationState(bundleID: $0) ? [$0] : []
        } ?? []
        DispatchQueue.global(qos: .utility).async {
            guard UninstallerSupport.isConfirmedAbsent(at: url) else { return }
            let remaining: Set<String> = bundleIDs.isEmpty ? [] : Set(InstalledApps.installedApplications(
                includeSystemApplications: true,
                spotlightPaths: CommandBarService.spotlightApplicationPaths())
                .compactMap(\.bundleID))
            DispatchQueue.main.async {
                // A reinstall while the scan was pending must keep its state.
                guard UninstallerSupport.isConfirmedAbsent(at: url) else { return }
                CommandBarService.shared.removeApplicationState(
                    bundleIDs: bundleIDs, urls: [url], remainingBundleIDs: remaining)
            }
        }
    }

    /// Asks Finder to trash `urls` in one batch. Finder owns the privilege
    /// elevation (the standard administrator prompt) and the result is a
    /// reversible move to the Trash, never a permanent delete. Waits until the
    /// user answers the prompt; a cancel simply leaves the items in place.
    private static func trashViaFinder(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard AppleScriptRunner.consentToAutomate(bundleID: "com.apple.finder") else { return }
        // In-process Apple Events (see AppleScriptRunner): the Finder Automation
        // consent is attributed to this app and re-requested if it was lost,
        // instead of a fragile osascript subprocess. Paths are embedded as
        // escaped string literals (no argv).
        let targets = urls
            .map { "set end of targets to POSIX file \(AppleScriptRunner.literal($0.path))" }
            .joined(separator: "\n")
        let source = """
        set targets to {}
        \(targets)
        tell application "Finder" to delete targets
        """
        _ = AppleScriptRunner.run(source)
    }

    // MARK: - Scanning

    private static func collect(appURL: URL,
                                primaryBundleID: String,
                                exclusiveBundleIDs: Set<String>,
                                teamIDs: Set<String>,
                                exclusiveGroupIDs: Set<String>,
                                cancellation: UninstallerSupport.ScanCancellation) -> [Leftover] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        // The target header already identifies the trashed app. Keep the
        // bundle out of the checklist, including Select All and space totals.
        let appAlreadyTrashed = UninstallerSupport.isInTrash(
            appURL, home: fm.homeDirectoryForCurrentUser)
        var paths = appAlreadyTrashed ? [] : [ScanCandidate(url: appURL, category: .app,
                                   ownerBundleID: nil, ownerGroupID: nil,
                                   evidenceBundleID: nil,
                                   confidence: .exact, include: true)]
        let info = UninstallerSupport.infoDictionary(of: appURL)
        var displayNames = UninstallerSupport.displayNames(
            localizedName: fm.displayName(atPath: appURL.path),
            fileName: appURL.lastPathComponent,
            bundleName: info?["CFBundleName"] as? String,
            bundleDisplayName: info?["CFBundleDisplayName"] as? String
        )
        if let executable = info?["CFBundleExecutable"] as? String {
            displayNames.append(executable)
        }
        let identity = UninstallerSupport.identity(
            primaryBundleID: primaryBundleID,
            bundleIDs: exclusiveBundleIDs,
            displayNames: displayNames,
            teamIDs: teamIDs,
            groupIDs: exclusiveGroupIDs
        )
        let allowedRoots = scanRoots(home: home)

        let folders = UninstallerSupport.searchFolders(
            home: URL(fileURLWithPath: home, isDirectory: true),
            darwinCache: darwinUserDirectory(_CS_DARWIN_USER_CACHE_DIR),
            darwinTemp: darwinUserDirectory(_CS_DARWIN_USER_TEMP_DIR)
        )
        // Each folder is listed and matched on its own, and Spotlight is one
        // more lookup, so they all run side by side. Matches keep the order
        // they had one after another: the folders in turn, then Spotlight.
        var matches = [[ScanCandidate]](repeating: [], count: folders.count + 1)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: folders.count + 1) { index in
            guard !cancellation.isCancelled else { return }
            var found: [ScanCandidate] = []
            if index < folders.count {
                appendMatches(in: folders[index], identity: identity, fm: FileManager(), into: &found)
            } else {
                appendSpotlightMatches(identity: identity, roots: spotlightRoots(home: home),
                                       fm: FileManager(), into: &found)
            }
            lock.lock()
            matches[index] = found
            lock.unlock()
        }
        guard !cancellation.isCancelled else { return [] }
        paths += matches.joined()

        // Last line of defense: nothing outside the scanned roots (or the app
        // bundle itself) may ever reach the removal list.
        let appPath = appURL.standardizedFileURL.path
        let safe = dedupe(paths).filter { candidate in
            let path = candidate.url.standardizedFileURL.path
            if path == appPath {
                return !UninstallerSupport.isSymbolicLink(candidate.url)
            }
            guard let root = allowedRoots.first(where: { path.hasPrefix($0.path + "/") }) else {
                return false
            }
            return UninstallerSupport.removalPathIsSafe(candidate.url, within: root)
        }
        return safe
            .compactMap { candidate -> Leftover? in
                // Sizing walks every folder found; stop there too.
                guard !cancellation.isCancelled,
                      let fileIdentity = UninstallerSupport.fileIdentity(at: candidate.url) else {
                    return nil
                }
                return Leftover(url: candidate.url, category: candidate.category,
                                size: directorySize(of: candidate.url, fm: fm),
                                ownerBundleID: candidate.ownerBundleID,
                                ownerGroupID: candidate.ownerGroupID,
                                evidenceBundleID: candidate.evidenceBundleID,
                                confidence: candidate.confidence,
                                fileIdentity: fileIdentity,
                                include: !appAlreadyTrashed && candidate.include)
            }
            .sorted { ($0.category.sortRank, -$0.size) < ($1.category.sortRank, -$1.size) }
    }

    private static func appendMatches(in folder: UninstallerSupport.SearchFolder,
                                      identity: UninstallerSupport.Identity,
                                      fm: FileManager,
                                      into paths: inout [ScanCandidate]) {
        let listings = dirListings(at: folder.url, remainingDepth: folder.extraChildDepth, fm: fm)
        guard !listings.isEmpty else { return }
        let category = category(for: folder.kind)
        let matchingIdentity: UninstallerSupport.Identity
        if folder.requiresSignedGroup {
            matchingIdentity = UninstallerSupport.Identity(
                bundleIDs: [], nameTokens: [], teamIDs: [], groupIDs: identity.groupIDs)
        } else {
            matchingIdentity = folder.allowsNameMatches
                ? identity : UninstallerSupport.technicalIdentity(identity)
        }
        var claimed = Set<String>()
        for hit in UninstallerSupport.leftoverHitRecords(
            listings: listings,
            identity: matchingIdentity,
            extraChildDepth: folder.extraChildDepth,
            crashReporter: folder.crashReporter
        ) {
            claimed.insert(hit.path)
            appendHit(hit, folder: folder.url, category: category, identity: matchingIdentity,
                      crashReporter: folder.crashReporter, into: &paths)
        }
        guard folder.readsContainerMetadata else { return }
        for listing in listings where !claimed.contains(listing.name) {
            let url = folder.url.appendingPathComponent(listing.name)
            guard let identifier = containerMetadataIdentifier(at: url) else { continue }
            let match = UninstallerSupport.containerMetadataMatches(identifier, identity: matchingIdentity)
            guard match != .none else { continue }
            claimed.insert(listing.name)
            let groupID = UninstallerSupport.matchingGroupID(identifier, identity: matchingIdentity)
                ?? UninstallerSupport.matchingGroupID(listing.name, identity: matchingIdentity)
            let owner = groupID == nil
                ? (UninstallerSupport.ownerBundleID(for: identifier, identity: matchingIdentity)
                    ?? UninstallerSupport.ownerBundleID(for: listing.name, identity: matchingIdentity)
                    ?? matchingIdentity.bundleIDs.min(by: { $0.count < $1.count }))
                : nil
            guard owner != nil || groupID != nil else { continue }
            let evidence = groupID == nil
                ? UninstallerSupport.verifiedBundleID(identifier) : nil
            paths.append(ScanCandidate(url: url, category: category,
                                       ownerBundleID: owner, ownerGroupID: groupID,
                                       evidenceBundleID: evidence,
                                       confidence: match, include: match == .exact))
        }
    }

    private static func appendHit(_ hit: UninstallerSupport.Hit,
                                  folder: URL,
                                  category: Category,
                                  identity: UninstallerSupport.Identity,
                                  crashReporter: Bool,
                                  into paths: inout [ScanCandidate]) {
        let relative = hit.path
        let name = (relative as NSString).lastPathComponent
        let identifier = hit.bundleIdentifier
            ?? CleanerSupport.bundleIDCandidate(fromEntryName: name)
        let groupID = identifier.flatMap {
            UninstallerSupport.matchingGroupID($0, identity: identity)
        } ?? UninstallerSupport.matchingGroupID(name, identity: identity)
        let owner = groupID == nil
            ? (identifier.flatMap { UninstallerSupport.ownerBundleID(for: $0, identity: identity) }
                ?? UninstallerSupport.ownerBundleID(for: name, identity: identity,
                                                crashReporter: crashReporter)
                ?? identity.bundleIDs.min(by: { $0.count < $1.count }))
            : nil
        guard owner != nil || groupID != nil else { return }
        let url = relative.split(separator: "/").reduce(folder) {
            $0.appendingPathComponent(String($1))
        }
        paths.append(ScanCandidate(url: url, category: category,
                                   ownerBundleID: owner, ownerGroupID: groupID,
                                   evidenceBundleID: groupID == nil ? identifier : nil,
                                   confidence: hit.confidence,
                                   include: hit.confidence == .exact))
    }

    private static func dirListings(at url: URL,
                                    remainingDepth: Int,
                                    fm: FileManager) -> [UninstallerSupport.DirListing] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let entries = try? fm.contentsOfDirectory(at: url,
                                                        includingPropertiesForKeys: Array(keys),
                                                        options: []) else { return [] }
        return entries.compactMap { entry -> UninstallerSupport.DirListing? in
            let name = entry.lastPathComponent
            guard !name.hasPrefix(".") else { return nil }
            let values = try? entry.resourceValues(forKeys: keys)
            guard values?.isSymbolicLink != true else { return nil }
            var children: [UninstallerSupport.DirListing] = []
            if remainingDepth > 0, values?.isDirectory == true {
                children = dirListings(at: entry, remainingDepth: remainingDepth - 1, fm: fm)
            }
            let bundleIdentifier = packageExtensions.contains(entry.pathExtension.lowercased())
                ? UninstallerSupport.verifiedBundleID(UninstallerSupport.bundleIdentifier(of: entry))
                : nil
            return UninstallerSupport.DirListing(name: name, children: children,
                                                  bundleIdentifier: bundleIdentifier)
        }
    }

    private static func containerMetadataIdentifier(at url: URL) -> String? {
        let metadata = url.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
        guard let dict = NSDictionary(contentsOf: metadata) as? [String: Any] else { return nil }
        return dict["MCMMetadataIdentifier"] as? String
    }

    private static func appendSpotlightMatches(identity: UninstallerSupport.Identity,
                                               roots: [URL],
                                               fm: FileManager,
                                               into paths: inout [ScanCandidate]) {
        guard let expression = UninstallerSupport.leftoverSpotlightExpression(identity: identity)
        else { return }
        let scopes = roots.map(\.path).filter { fm.fileExists(atPath: $0) }
        guard !scopes.isEmpty,
              let query = MDQueryCreate(kCFAllocatorDefault, expression as CFString, nil, nil)
        else { return }
        MDQuerySetMaxCount(query, 200)
        MDQuerySetSearchScope(query, scopes as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return }
        let count = min(MDQueryGetResultCount(query), 200)
        var added = 0
        for index in 0..<count {
            guard added < 80,
                  let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = unsafeBitCast(raw, to: MDItem.self)
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String,
                  UninstallerSupport.leftoverSpotlightPathIsAllowed(path, roots: roots)
            else { continue }
            let url = URL(fileURLWithPath: path)
            let matchingIdentity = UninstallerSupport.spotlightIdentity(for: path, identity: identity)
            let match = UninstallerSupport.leftoverMatch(
                url.lastPathComponent, identity: matchingIdentity)
            guard match != .none else { continue }
            let groupID = UninstallerSupport.matchingGroupID(
                url.lastPathComponent, identity: matchingIdentity)
            let evidence = groupID == nil
                ? CleanerSupport.bundleIDCandidate(fromEntryName: url.lastPathComponent) : nil
            let owner = groupID == nil
                ? (UninstallerSupport.ownerBundleID(
                    for: evidence ?? url.lastPathComponent, identity: matchingIdentity)
                    ?? matchingIdentity.bundleIDs.min(by: { $0.count < $1.count }))
                : nil
            guard owner != nil || groupID != nil else { continue }
            paths.append(ScanCandidate(url: url, category: category(forPath: path),
                                       ownerBundleID: owner, ownerGroupID: groupID,
                                       evidenceBundleID: evidence,
                                       confidence: match, include: false))
            added += 1
        }
    }

    private static func category(forPath path: String) -> Category {
        if path.contains("/Caches") { return .caches }
        if path.contains("/Preferences") { return .preferences }
        if path.contains("/Group Containers") || path.contains("/Containers") { return .containers }
        if path.contains("/Logs") { return .logs }
        if path.contains("/Saved Application State") { return .state }
        if path.contains("/Application Support") { return .support }
        return .other
    }

    private static func codeSigningIdentity(at appURL: URL,
                                            requireValidSignature: Bool)
        -> (teamIDs: Set<String>, groupIDs: Set<String>) {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return ([], []) }
        if requireValidSignature,
           SecStaticCodeCheckValidity(staticCode, [], nil) != errSecSuccess {
            return ([], [])
        }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let info else { return ([], []) }
        let dict = info as NSDictionary
        var teamIDs: Set<String> = []
        if let team = dict[kSecCodeInfoTeamIdentifier] as? String {
            teamIDs.insert(team)
        }
        var groupIDs: Set<String> = []
        if let entitlements = dict[kSecCodeInfoEntitlementsDict] as? [String: Any],
           let groups = entitlements["com.apple.security.application-groups"] as? [String] {
            groupIDs.formUnion(groups.filter { !$0.isEmpty })
        }
        return (teamIDs, groupIDs)
    }

    /// Main app plus owned executable extensions. Resource bundles and
    /// arbitrary nested apps are excluded because their identifiers may be
    /// shared by unrelated products.
    private static func signingIdentity(in appURL: URL,
                                        requireValidSignature: Bool)
        -> (teamIDs: Set<String>, groupIDs: Set<String>) {
        if requireValidSignature, !codeSignatureIsValid(at: appURL) {
            return ([], [])
        }
        var result = codeSigningIdentity(at: appURL,
                                         requireValidSignature: requireValidSignature)
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = fm.enumerator(at: appURL,
                                             includingPropertiesForKeys: Array(keys),
                                             options: [.skipsHiddenFiles],
                                             errorHandler: nil) else { return result }
        var inspected = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values?.isDirectory == true,
                  ownedEmbeddedCode(url, in: appURL) else { continue }
            inspected += 1
            guard inspected <= 256 else { break }
            let nested = codeSigningIdentity(at: url,
                                             requireValidSignature: requireValidSignature)
            result.teamIDs.formUnion(nested.teamIDs)
            result.groupIDs.formUnion(nested.groupIDs)
        }
        return result
    }

    private static func codeSignatureIsValid(at url: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }
        return SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess
    }

    private static func category(for kind: UninstallerSupport.Kind) -> Category {
        switch kind {
        case .support: return .support
        case .caches: return .caches
        case .preferences: return .preferences
        case .containers: return .containers
        case .logs: return .logs
        case .state: return .state
        case .other: return .other
        }
    }

    private static func knownApplicationURLs(candidateBundleIDs: Set<String>) -> [URL] {
        var urls = InstalledApps.installedApplications(
            includeSystemApplications: true, spotlightPaths: CommandBarService.spotlightApplicationPaths()).map(\.url)
        urls += NSWorkspace.shared.runningApplications.compactMap(\.bundleURL)
        for id in candidateBundleIDs {
            urls += NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id)
        }
        var seen = Set<String>()
        return urls.compactMap { url in
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
                  FileManager.default.fileExists(atPath: resolved.path),
                  seen.insert(resolved.path).inserted else { return nil }
            return resolved
        }
    }

    private static func exclusiveOwnedBundleIDs(in selectedURL: URL,
                                                candidates: Set<String>,
                                                knownApplicationIDs: [(url: URL, bundleID: String)],
                                                requiresCurrentOwnership: Bool = true) -> Set<String> {
        var eligible = candidates
        if requiresCurrentOwnership {
            let current = allBundleIDs(in: selectedURL, fm: .default)
            eligible = Set(candidates.filter { candidate in
                current.contains(where: {
                    $0.caseInsensitiveCompare(candidate) == .orderedSame
                })
            })
        }
        return UninstallerSupport.exclusiveBundleIDs(eligible,
                                                     selectedURL: selectedURL,
                                                     knownApplications: knownApplicationIDs)
    }

    private static func applicationBundleIdentifiers(in applications: [URL])
        -> [(url: URL, bundleID: String)] {
        // Walking every installed app's bundle is most of a scan's time.
        // Each walk is independent, so they run side by side.
        var bundleIDs = [Set<String>](repeating: [], count: applications.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: applications.count) { index in
            // An extension or login item can change without modifying its
            // parent's Info.plist. Ownership must include the current children.
            let ids = allBundleIDs(in: applications[index], fm: FileManager())
            lock.lock()
            bundleIDs[index] = ids
            lock.unlock()
        }
        return zip(applications, bundleIDs).flatMap { url, ids in ids.map { (url, $0) } }
    }

    private static func exclusiveGroupIDs(_ candidates: Set<String>,
                                          selectedURL: URL,
                                          knownApplications: [URL]) -> Set<String> {
        guard !candidates.isEmpty else { return [] }
        let selectedPath = selectedURL.resolvingSymlinksInPath().standardizedFileURL.path
        var claimedElsewhere = Set<String>()
        for url in knownApplications {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard path != selectedPath, !path.hasPrefix(selectedPath + "/") else { continue }
            let groups = signingIdentity(in: url, requireValidSignature: false).groupIDs
            claimedElsewhere.formUnion(groups.intersection(candidates))
            if claimedElsewhere == candidates { break }
        }
        return candidates.subtracting(claimedElsewhere)
    }

    private static func removalIsStillSafe(_ url: URL,
                                           expectedIdentity: UninstallerSupport.FileIdentity,
                                           allowedPaths: Set<String>,
                                           targetURL: URL?) -> Bool {
        let path = url.standardizedFileURL.path
        guard allowedPaths.contains(path), let targetURL,
              UninstallerSupport.fileIdentity(at: url) == expectedIdentity else { return false }
        if path == targetURL.standardizedFileURL.path {
            return !UninstallerSupport.isSymbolicLink(url)
        }
        guard let root = scanRoots(home: NSHomeDirectory()).first(where: {
            path.hasPrefix($0.path + "/")
        }) else { return false }
        return UninstallerSupport.removalPathIsSafe(url, within: root)
    }

    private static func allBundleIDs(in appURL: URL, fm: FileManager) -> Set<String> {
        var result = Set<String>()
        if let primary = UninstallerSupport.verifiedBundleID(UninstallerSupport.bundleIdentifier(of: appURL)) {
            result.insert(primary)
        }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = fm.enumerator(at: appURL,
                                             includingPropertiesForKeys: Array(keys),
                                             options: [.skipsHiddenFiles],
                                             errorHandler: nil) else { return result }
        var inspected = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values?.isDirectory == true,
                  ownedEmbeddedCode(url, in: appURL),
                  let id = UninstallerSupport.verifiedBundleID(UninstallerSupport.bundleIdentifier(of: url))
            else { continue }
            inspected += 1
            guard inspected <= 256 else { break }
            result.insert(id)
        }
        return result
    }

    private static func ownedEmbeddedCode(_ url: URL, in appURL: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "appex", "xpc":
            return true
        case "app":
            let loginItems = appURL.appendingPathComponent(
                "Contents/Library/LoginItems", isDirectory: true).standardizedFileURL.path
            return url.standardizedFileURL.path.hasPrefix(loginItems + "/")
        default:
            return false
        }
    }

    private static let packageExtensions: Set<String> = [
        "app", "appex", "bundle", "framework", "plugin", "webplugin",
        "prefpane", "qlgenerator", "mdimporter", "service", "saver",
        "colorpicker", "wdgt", "component", "vst", "vst3", "clap", "dpm",
        "aaxplugin", "dictionary", "action", "workflow", "mailbundle",
    ]

    private static func scanRoots(home: String) -> [URL] {
        var roots = [
            URL(fileURLWithPath: home + "/Library", isDirectory: true),
            URL(fileURLWithPath: "/Library", isDirectory: true),
            URL(fileURLWithPath: home + "/.config", isDirectory: true),
            URL(fileURLWithPath: home + "/.cache", isDirectory: true),
            URL(fileURLWithPath: home + "/.local/share", isDirectory: true),
            URL(fileURLWithPath: "/private/var/db/receipts", isDirectory: true),
            URL(fileURLWithPath: "/Users/Shared/Library", isDirectory: true),
        ]
        if let cache = darwinUserDirectory(_CS_DARWIN_USER_CACHE_DIR) { roots.append(cache) }
        if let temp = darwinUserDirectory(_CS_DARWIN_USER_TEMP_DIR) { roots.append(temp) }
        return roots.map(\.standardizedFileURL)
    }

    private static func spotlightRoots(home: String) -> [URL] {
        [
            URL(fileURLWithPath: home + "/Library", isDirectory: true),
            URL(fileURLWithPath: "/Library", isDirectory: true),
            URL(fileURLWithPath: "/Users/Shared/Library", isDirectory: true),
        ].map(\.standardizedFileURL)
    }

    private static func darwinUserDirectory(_ name: Int32) -> URL? {
        let length = confstr(name, nil, 0)
        guard length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(name, &buffer, length) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer), isDirectory: true).standardizedFileURL
    }

    /// Drops exact duplicates and any path nested inside another already found.
    /// An exact match upgrades a related one already recorded at the same path.
    private static func dedupe(_ paths: [ScanCandidate]) -> [ScanCandidate] {
        var seen = Set<String>()
        var roots: [String] = []
        var out: [ScanCandidate] = []
        let exactPaths = paths.filter { $0.confidence == .exact }
            .map { $0.url.standardizedFileURL.path }
        for candidate in paths.sorted(by: { $0.url.path.count < $1.url.path.count }) {
            let path = candidate.url.standardizedFileURL.path
            if candidate.confidence == .related,
               exactPaths.contains(where: { $0.hasPrefix(path + "/") }) {
                continue
            }
            if let index = out.firstIndex(where: { $0.url.standardizedFileURL.path == path }) {
                let include = out[index].include || candidate.include
                if out[index].confidence != .exact, candidate.confidence == .exact {
                    out[index] = candidate
                }
                out[index].include = include
                continue
            }
            if seen.contains(path) { continue }
            if roots.contains(where: { path.hasPrefix($0 + "/") }) { continue }
            seen.insert(path)
            roots.append(path)
            out.append(candidate)
        }
        return out
    }

    private static func directorySize(of url: URL, fm: FileManager) -> Int64 {
        if UninstallerSupport.isSymbolicLink(url) { return fileSize(url) }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return fileSize(url) }

        var total: Int64 = 0
        if let enumerator = fm.enumerator(at: url,
                                          includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
                                          options: [], errorHandler: nil) {
            for case let item as URL in enumerator {
                if UninstallerSupport.isSymbolicLink(item) {
                    enumerator.skipDescendants()
                    continue
                }
                total += fileSize(item)
            }
        }
        return total
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }
}
