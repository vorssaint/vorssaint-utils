// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Locks and unlocks files and folders from the right-click menu.
///
/// Finder lists what an app offers under Services. Two entries are declared in
/// Info.plist, "Lock with Vorssaint…" and "Unlock with Vorssaint…", and this
/// object answers them. Double-clicking a locked item opens it the same way.
/// A request returns to Finder at once and the questions are asked afterwards,
/// so Finder never waits on a password prompt.
@MainActor
final class FileLockController: NSObject {
    static let shared = FileLockController()

    private var isBusy = false
    private var text: PrivacyLockFeatureStrings { FeatureStrings.privacyLock(L10n.shared.language) }

    private override init() { super.init() }

    // MARK: - Lifecycle

    var isActive: Bool { FileLockSupport.isEnabled() }

    func syncWithPreferences() {
        if isActive {
            NSApp.servicesProvider = self
            NSUpdateDynamicServices()
        } else if (NSApp.servicesProvider as AnyObject?) === self {
            NSApp.servicesProvider = nil
        }
    }

    // MARK: - Service entry points (named in Info.plist as NSMessage)

    @objc func lockItems(_ pboard: NSPasteboard, userData: String,
                         error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard isActive else { error.pointee = text.serviceOff as NSString; return }
        let urls = Self.fileURLs(from: pboard)
        DispatchQueue.main.async { [weak self] in self?.handle(.lockItems, urls) }
    }

    @objc func unlockItems(_ pboard: NSPasteboard, userData: String,
                           error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard isActive else { error.pointee = text.serviceOff as NSString; return }
        let urls = Self.fileURLs(from: pboard)
        DispatchQueue.main.async { [weak self] in self?.unlock(urls) }
    }

    /// Locked items opened from Finder, and the links the Quick Actions open.
    func open(_ urls: [URL]) {
        for url in urls where url.scheme == PrivacyLockLink.scheme {
            if let request = PrivacyLockLink.parse(url) { handle(request.action, request.paths) }
        }
        let locked = urls.filter { $0.isFileURL && $0.pathExtension == PrivacyLockSupport.fileExtension }
        guard !locked.isEmpty else { return }
        guard isActive else { PrivacyLockPrompts.showError(text.serviceOff); return }
        unlock(locked)
    }

    /// One Quick Action, arrived as a link. Everything but a plain lock asks for proof first.
    private func handle(_ action: PrivacyLockLinkAction, _ urls: [URL]) {
        guard AppFeature.privacyLock.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.privacyLockEnabled) else {
            PrivacyLockPrompts.showError(text.serviceOff)
            return
        }
        switch action {
        case .lockItems:
            // An app picked with the file action is locked as an app.
            let apps = urls.filter { $0.pathExtension == "app" }
            if !apps.isEmpty { AppLockService.shared.lock(appsAt: apps) }
            guard isActive else { if apps.isEmpty { PrivacyLockPrompts.showError(text.serviceOff) }; return }
            lock(urls.filter { $0.pathExtension != "app" })
        case .unlockItems:
            guard isActive else { PrivacyLockPrompts.showError(text.serviceOff); return }
            unlock(urls)
        case .lockApps:
            AppLockService.shared.lock(appsAt: urls)
        case .unlockApps:
            Task { await AppLockService.shared.unlock(appsAt: urls) }
        case .toggleApps:
            Task { await AppLockService.shared.toggle(appsAt: urls) }
        }
    }

    private static func fileURLs(from pboard: NSPasteboard) -> [URL] {
        (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    // MARK: - Locking

    func lock(_ urls: [URL]) {
        guard !isBusy else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let items = urls.filter { $0.pathExtension != PrivacyLockSupport.fileExtension
            && PrivacyLockSupport.isLockable($0, home: home) }
        guard !items.isEmpty else { return }
        isBusy = true
        let canRemember = UserDefaults.standard.bool(forKey: DefaultsKey.fileLockRemember)
        Task {
            defer { isBusy = false }
            var shared: PrivacyLockPrompts.NewPassword?
            var made: [URL] = []
            for (index, item) in items.enumerated() {
                let choice: PrivacyLockPrompts.NewPassword
                if let shared { choice = shared }
                else {
                    guard let asked = PrivacyLockPrompts.askNewPassword(
                        itemName: item.lastPathComponent, canRemember: canRemember,
                        hasMore: index < items.count - 1) else { break }
                    choice = asked
                    if asked.applyToRest { shared = asked }
                }
                do {
                    let record = try await Task.detached(priority: .userInitiated) {
                        try Self.lockOne(item, password: choice.password, remember: choice.remember)
                    }.value
                    LockedItemIndex.shared.add(record)
                    made.append(record.url)
                } catch {
                    PrivacyLockPrompts.showError(String(format: text.lockFailedFormat,
                                                        item.lastPathComponent, error.localizedDescription))
                }
            }
            if !made.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(made) }
        }
    }

    /// Container first, verified; then the remembered password; the original
    /// last, so a failure at any step leaves the original in place.
    nonisolated private static func lockOne(_ source: URL, password: String,
                                            remember: Bool) throws -> LockedItemIndex.Record {
        let isFolder = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let itemID = try LockedItemVault.randomItemID()
        let container = try LockedItemVault.createContainer(from: source, password: password, itemID: itemID)
        let idHex = itemID.map { String(format: "%02x", $0) }.joined()
        if remember {
            do { try PrivacyLockKeychain.rememberPassword(password, forItem: idHex) }
            catch { LockedItemVault.discard(container: container); throw error }
        }
        do { try LockedItemVault.removeOriginal(source) }
        catch {
            // The copy is good but the original stays; keep both rather than lose either.
            throw error
        }
        return LockedItemIndex.Record(id: idHex, originalName: source.lastPathComponent, isFolder: isFolder,
                                      path: container.path, lockedAt: Date(), remembered: remember)
    }

    // MARK: - Unlocking

    func unlock(_ urls: [URL]) {
        guard !isBusy else { return }
        let items = urls.filter { $0.pathExtension == PrivacyLockSupport.fileExtension }
        guard !items.isEmpty else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            var restored: [URL] = []
            for item in items {
                if let url = await unlockOne(item) { restored.append(url) }
            }
            LockedItemIndex.shared.pruneMissing()
            if !restored.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(restored) }
        }
    }

    private func unlockOne(_ container: URL) async -> URL? {
        let header = try? LockedItemVault.readHeader(of: container)
        let idHex = header?.itemIDHex
        var attempt: String?

        if let idHex, PrivacyLockKeychain.hasRememberedPassword(forItem: idHex) {
            do {
                try await PrivacyLockAuthenticator.authenticate(
                    reason: String(format: text.touchIDReasonFormat, container.deletingPathExtension().lastPathComponent),
                    allowPassword: true)
                attempt = try PrivacyLockKeychain.rememberedPassword(forItem: idHex)
            } catch {
                // Falls through to asking for the password.
            }
        }
        var wrong = false
        while true {
            let password: String
            if let attempt { password = attempt }
            else if let asked = PrivacyLockPrompts.askPassword(
                itemName: container.deletingPathExtension().lastPathComponent, wrong: wrong) { password = asked }
            else { return nil }
            attempt = nil
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try LockedItemVault.unlock(container: container, password: password)
                }.value
                if let idHex {
                    PrivacyLockKeychain.forgetPassword(forItem: idHex)
                    LockedItemIndex.shared.remove(id: idHex)
                }
                return result.url
            } catch LockedItemError.wrongPassword {
                wrong = true
            } catch {
                PrivacyLockPrompts.showError(String(format: text.unlockFailedFormat,
                                                    container.lastPathComponent, error.localizedDescription))
                return nil
            }
        }
    }
}

enum FileLockSupport {
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        AppFeature.privacyLock.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.privacyLockEnabled)
            && defaults.bool(forKey: DefaultsKey.fileLockEnabled)
    }
}
