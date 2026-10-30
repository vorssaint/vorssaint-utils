// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Keeps `mailto:` links from opening Mail by holding the scheme while the
/// option is on, then doing what the user chose with each link. Turning the
/// option off gives the scheme back to the app that had it. Nothing is
/// observed or terminated, so a Mail window opened on purpose is never
/// touched, and no permission is needed.
final class MailLinkBlocker: ObservableObject {
    static let shared = MailLinkBlocker()

    /// Whether Launch Services sends email links here right now.
    @Published private(set) var isHandlingLinks = false

    private static let probeURL = URL(string: "mailto:")!
    private let ownBundleID = Bundle.main.bundleIdentifier
    /// The last link passed on to the chosen app, to recognize it coming back.
    private var lastPassedOn: (url: URL, at: TimeInterval)?

    private init() {}

    private var isEnabled: Bool {
        AppFeature.mailBlock.isAvailable && UserDefaults.standard.bool(forKey: DefaultsKey.mailBlockEnabled)
    }

    func syncWithPreferences() {
        let current = NSWorkspace.shared.urlForApplication(toOpen: Self.probeURL)
        let holdsScheme = current.map(isOwnApp) ?? false
        if isEnabled {
            isHandlingLinks = holdsScheme
            guard !holdsScheme else { return }
            UserDefaults.standard.set(current?.path ?? "", forKey: DefaultsKey.mailBlockPreviousHandlerPath)
            setHandler(Bundle.main.bundleURL)
        } else {
            isHandlingLinks = false
            guard holdsScheme else { return }
            setHandler(restoreTarget()) { succeeded in
                if succeeded {
                    UserDefaults.standard.set("", forKey: DefaultsKey.mailBlockPreviousHandlerPath)
                }
            }
        }
    }

    /// Every `mailto:` link Launch Services sends here. A link that arrives
    /// while the option is off goes on to the handler it would have reached.
    func handle(_ url: URL) {
        guard MailLinkSupport.isMailLink(url) else { return }
        guard isEnabled else {
            if let target = restoreTarget() { open(url, with: target) }
            syncWithPreferences()
            return
        }
        switch MailLinkSupport.Action.sanitized(
            UserDefaults.standard.string(forKey: DefaultsKey.mailBlockAction)) {
        case .ignore:
            return
        case .openApp:
            let path = UserDefaults.standard.string(forKey: DefaultsKey.mailBlockAppPath) ?? ""
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }
            let app = URL(fileURLWithPath: path)
            guard MailLinkSupport.canOpenLinks(bundleID: Bundle(url: app)?.bundleIdentifier,
                                               ownBundleID: ownBundleID) else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard !MailLinkSupport.isReturnedLink(url, now: now, lastPassedOn: lastPassedOn?.url,
                                                  passedOnAt: lastPassedOn?.at) else {
                lastPassedOn = nil
                return
            }
            lastPassedOn = (url, now)
            open(url, with: app)
        case .copyAddress:
            let recipients = MailLinkSupport.recipients(in: url)
            guard !recipients.isEmpty else { return }
            let text = recipients.joined(separator: ", ")
            GeneralPasteboardAccess.shared.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                NSPasteboard.general.declareVorssaintSource()
            }
            QuickToolHUD.show(icon: "envelope", message: FeatureStrings.mailBlock(L10n.shared.language).copied)
        }
    }

    private func isOwnApp(_ url: URL) -> Bool {
        Bundle(url: url)?.bundleIdentifier == ownBundleID
    }

    /// The handler saved when the option took the scheme, or Mail.
    private func restoreTarget() -> URL? {
        let saved = MailLinkSupport.restoreTarget(
            savedPath: UserDefaults.standard.string(forKey: DefaultsKey.mailBlockPreviousHandlerPath),
            ownBundleID: ownBundleID,
            bundleID: { Bundle(path: $0)?.bundleIdentifier },
            exists: { FileManager.default.fileExists(atPath: $0) })
        if let saved { return URL(fileURLWithPath: saved) }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: MailLinkSupport.mailBundleID)
    }

    private func setHandler(_ app: URL?, completion: ((Bool) -> Void)? = nil) {
        guard let app else {
            completion?(false)
            return
        }
        NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: MailLinkSupport.scheme) { error in
            DispatchQueue.main.async {
                let current = NSWorkspace.shared.urlForApplication(toOpen: Self.probeURL)
                self.isHandlingLinks = self.isEnabled && (current.map(self.isOwnApp) ?? false)
                completion?(error == nil)
            }
        }
    }

    private func open(_ url: URL, with app: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration)
    }
}
