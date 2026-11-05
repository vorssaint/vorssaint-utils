// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Opens the Uninstaller on an app the moment it lands in the Trash, so
/// deleting an app in Finder offers to clean up what it left behind. Opt-in,
/// and it needs Full Disk Access: the Trash cannot be read without it, and
/// the scan it hands over would be shallow anyway.
///
/// Builds on the approach first proposed by ilim-cell in #3755.
final class TrashAppWatcher {
    static let shared = TrashAppWatcher()

    private let trash = UninstallerSupport.trashURL(home: FileManager.default.homeDirectoryForCurrentUser)
    private var source: DispatchSourceFileSystemObject?
    private var known = Set<String>()
    private var pendingCheck: DispatchWorkItem?

    private init() {}

    func syncWithPreferences() {
        precondition(Thread.isMainThread)
        let wanted = AppFeature.uninstaller.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.uninstallerWatchesTrash)
            && Permissions.shared.fullDiskAccess
        wanted ? start() : stop()
    }

    private func start() {
        guard source == nil else { return }
        let descriptor = open(trash.path, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return }
        // Whatever is in the Trash already was deleted before we looked.
        known = Set(UninstallerSupport.trashedApps(in: trash).map(\.standardizedFileURL.path))
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .revoke], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            if source.data.isDisjoint(with: [.delete, .rename, .revoke]) {
                self.scheduleCheck()
            } else {
                // The Trash folder itself went away; watch the new one.
                self.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.syncWithPreferences() }
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func stop() {
        pendingCheck?.cancel()
        pendingCheck = nil
        source?.cancel()
        source = nil
        known = []
    }

    /// Finder writes a deleted app in a few steps; look once it settles.
    private func scheduleCheck() {
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.check() }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func check() {
        guard source != nil else { return }
        // Every write to the Trash lands here, the Uninstaller's own removals
        // included; only app bundles are compared, and its target is skipped.
        let current = UninstallerSupport.trashedApps(in: trash)
        let arrived = UninstallerSupport.newlyTrashedApps(current: current, known: known)
        known = Set(current.map(\.standardizedFileURL.path))
        // Several apps at once (emptying a folder of apps) get one offer: the
        // Uninstaller reviews a single app at a time.
        if let app = arrived.first(where: shouldOffer) {
            appDelegate()?.openUninstaller(for: app)
        }
    }

    private func shouldOffer(_ app: URL) -> Bool {
        let uninstaller = AppUninstaller.shared
        guard !uninstaller.isRemoving,
              let selection = UninstallerSupport.selection(for: app) else { return false }
        // The Uninstaller trashing its own target lands here too.
        guard selection.bundleID != uninstaller.target?.bundleID else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return UninstallerSupport.trashedAppWasLastCopy(
            otherCopies: NSWorkspace.shared.urlsForApplications(withBundleIdentifier: selection.bundleID),
            home: home, fileExists: FileManager.default.fileExists(atPath:))
    }
}
