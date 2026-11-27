// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import FinderSync
import Carbon
import Security

/// No watcher or polling is needed: Finder invokes the feature on demand.
enum FinderNewFileService {
    private static var replayGuard = FinderNewFileReplayGuard()

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

    /// Reports the system's enablement state, not whether Finder has launched the extension process.
    static var extensionEnabled: Bool { FIFinderSyncController.isExtensionEnabled }

    static func openExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    /// Capture the OS sender synchronously, before leaving the Apple event.
    static func handleOpenURLs(_ urls: [URL]) {
        guard enabled else { return }
        let requests = urls.compactMap { FinderNewFileRequest.decode($0) }
        guard !requests.isEmpty else { return }
        guard FinderNewFileSender.isEmbeddedExtension() else {
            NSLog("Vorssaint Finder New File: rejected unauthenticated Apple event")
            return
        }
        for request in requests {
            DispatchQueue.main.async { handle(request) }
        }
    }

    private static func handle(_ request: FinderNewFileRequest) {
        guard enabled, extensionEnabled, kinds.contains(request.kind),
              replayGuard.accept(request) else { return }
        do {
            _ = try FinderNewFileCreator.create(request.kind, in: request.directory,
                templates: Bundle.main.resourceURL?.appendingPathComponent("FinderNewFileTemplates", isDirectory: true))
        } catch {
            let strings = FeatureStrings.finderNewFile(L10n.shared.language)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = strings.error
            alert.informativeText = request.directory.path + "\n\n" + error.localizedDescription
            alert.addButton(withTitle: strings.cancel)
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

}

/// Authenticate the sender while AppKit is still handling the Apple event.
/// A bundle identifier or a PID supplied in a URL is not proof of identity.
/// The read-only sender audit token is supplied by the OS, and the running
/// code must match the exact signed extension embedded in this installation.
/// This works with stable local, ad-hoc and Developer ID signatures alike.
enum FinderNewFileSender {
    static func isEmbeddedExtension() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let token = event.attributeDescriptor(forKeyword: AEKeyword(keySenderAuditTokenAttr))?.data,
              token.count == 32,
              let plugIns = Bundle.main.builtInPlugInsURL else { return false }
        let extensionURL = plugIns.appendingPathComponent("VorssaintFinderNewFile.appex", isDirectory: true)
        let flags = SecCSFlags(rawValue: 0)
        var expected: SecStaticCode?
        guard SecStaticCodeCreateWithPath(extensionURL as CFURL, flags, &expected) == errSecSuccess,
              let expected,
              SecStaticCodeCheckValidity(expected, flags, nil) == errSecSuccess else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(expected, SecCSFlags(rawValue: kSecCSSigningInformation),
                                             &info) == errSecSuccess,
              let hash = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data,
              !hash.isEmpty else { return false }
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(("cdhash H\"\(hex)\"" as CFString), flags, &requirement) == errSecSuccess,
              let requirement else { return false }
        var sender: SecCode?
        let attributes = [kSecGuestAttributeAudit as String: token] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, flags, &sender) == errSecSuccess,
              let sender else { return false }
        return SecCodeCheckValidity(sender, flags, requirement) == errSecSuccess
    }
}
