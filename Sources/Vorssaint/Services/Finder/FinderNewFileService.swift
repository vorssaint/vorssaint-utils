// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import FinderSync
import Carbon
import Security

/// No watcher or polling is needed: Finder invokes the feature on demand.
enum FinderNewFileService {
    private static var replayGuard = FinderNewFileReplayGuard()
    // Main-thread state: don't accept a queued Finder action while permissions
    // or the app itself are being removed.
    private static var tearingDown = false

    static var enabled: Bool {
        !tearingDown && AppFeature.finderNewFile.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.finderNewFileEnabled)
    }

    static var items: [FinderNewFileItem] { configuredItems() }

    static func configuredItems(raw: String? = nil, defaults: UserDefaults = .standard) -> [FinderNewFileItem] {
        FinderNewFileItem.items(raw ?? defaults.string(forKey: DefaultsKey.finderNewFileItems) ?? "",
            legacySelection: defaults.string(forKey: DefaultsKey.finderNewFileKinds),
            legacyCustom: defaults.string(forKey: DefaultsKey.finderNewFileCustomItems) ?? "[]")
    }

    static func syncWithPreferences() {
        publish(enabled: enabled)
    }

    static func suspend() {
        publish(enabled: false)
    }

    static func beginSystemTeardown() {
        tearingDown = true
        suspend()
    }

    static func endSystemTeardown() {
        tearingDown = false
        syncWithPreferences()
    }

    /// Finder Sync enablement is a PlugInKit user election, not a TCC grant.
    /// Only an explicit Clear all permissions/uninstall may change it.
    static func clearExtensionPermission() -> Bool {
        #if VORSSAINT_DEVELOPMENT
        let id = "com.vorssaint.utils.dev.finder-new-file"
        #else
        let id = "com.vorssaint.utils.finder-new-file"
        #endif
        // Use the exact identifier and verify the system election, rather
        // than relying on a potentially stale FinderSync enablement query.
        let result = Shell.run("/usr/bin/pluginkit", ["-e", "ignore", "-i", id])
        let state = Shell.run("/usr/bin/pluginkit", ["-m", "-Av", "-i", id])
        guard result.status == 0, state.status == 0,
              FinderNewFileExtensionElection.isIgnored(state.output, identifier: id) else {
            NSLog("Vorssaint Finder extension reset could not be confirmed (change=%d, query=%d): %@ %@",
                  result.status, state.status, result.output, state.output)
            return false
        }
        return true
    }

    private static func publish(enabled: Bool) {
        let language = L10n.shared.language
        let strings = FeatureStrings.finderNewFile(language)
        let snapshot = FinderNewFileSnapshot(enabled: enabled, language: language.rawValue,
            entries: enabled ? items.filter(\.isEnabled).map { $0.menuItem(strings) } : [])
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
        guard enabled, extensionEnabled,
              let id = request.customID ?? request.kind?.itemID,
              let item = items.first(where: { $0.id == id && $0.isEnabled }),
              replayGuard.accept(request) else { return }
        do {
            _ = try FinderNewFileCreator.create(item, in: request.directory,
                templateDirectory: FinderNewFileTemplateStore.directory,
                bundledTemplates: Bundle.main.resourceURL?.appendingPathComponent("FinderNewFileTemplates", isDirectory: true))
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
