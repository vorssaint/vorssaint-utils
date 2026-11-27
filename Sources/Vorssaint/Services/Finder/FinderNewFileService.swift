// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import FinderSync

/// No watcher or polling is needed: Finder invokes the feature on demand.
enum FinderNewFileService {
    private static var isConfirming = false

    static var enabled: Bool {
        AppFeature.finderNewFile.isAvailable && UserDefaults.standard.bool(forKey: DefaultsKey.finderNewFileEnabled)
    }

    private static var kinds: [FinderNewFileKind] {
        FinderNewFileKind.selection(UserDefaults.standard.string(forKey: DefaultsKey.finderNewFileKinds))
    }

    static func syncWithPreferences() {
        publish(enabled: enabled)
    }

    static func suspend() {
        publish(enabled: false)
    }

    private static func publish(enabled: Bool) {
        let snapshot = FinderNewFileSnapshot(enabled: enabled,
            language: L10n.shared.language.rawValue, selection: kinds.map(\.rawValue).joined(separator: ","))
        do { try FinderNewFileExchange.publish(snapshot) }
        catch { NSLog("Vorssaint Finder menu preferences could not be shared: %@", error.localizedDescription) }
    }

    static func openExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    static func handle(_ url: URL) {
        guard enabled, FIFinderSyncController.isExtensionEnabled,
              let route = FinderNewFileRequest.route(url) else { return }
        let request: FinderNewFileRequest
        switch route {
        case .queued(let id):
            guard let queued = FinderNewFileExchange.consume(id) else { return }
            request = queued
        case .confirmation(let untrusted):
            guard kinds.contains(untrusted.kind), confirm(untrusted) else { return }
            request = untrusted
        }

        // Recheck after a confirmation dialog, and never accept an arbitrary
        // filename, template path, script or overwrite flag from the URL.
        guard enabled, FIFinderSyncController.isExtensionEnabled, kinds.contains(request.kind),
              request.isValid() else { return }
        do {
            _ = try FinderNewFileCreator.create(request.kind, in: request.directory,
                templates: Bundle.main.resourceURL?.appendingPathComponent("FinderNewFileTemplates", isDirectory: true))
        } catch {
            let strings = FinderNewFileStrings.localized(L10n.shared.language.rawValue)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = strings.error
            alert.informativeText = request.directory.path + "\n\n" + error.localizedDescription
            alert.addButton(withTitle: strings.cancel)
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    /// On local/legacy signing or macOS 14, a URL is never authorization for
    /// file creation. Show the exact directory and document type before writing.
    private static func confirm(_ request: FinderNewFileRequest) -> Bool {
        guard !isConfirming else { return false }
        isConfirming = true
        defer { isConfirming = false }
        let strings = FinderNewFileStrings.localized(L10n.shared.language.rawValue)
        let alert = NSAlert()
        alert.messageText = strings.title + ": " + request.kind.title(strings)
        alert.informativeText = strings.folder + ": " + request.directory.path
        alert.addButton(withTitle: strings.cancel)
        alert.addButton(withTitle: strings.confirm)
        alert.buttons.first?.keyEquivalent = "\r"
        alert.buttons.last?.keyEquivalent = ""
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }
}
