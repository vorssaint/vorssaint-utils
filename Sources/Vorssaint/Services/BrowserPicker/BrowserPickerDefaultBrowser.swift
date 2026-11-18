// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Makes this app the system's web browser, so clicked links reach the picker,
/// and gives the role back to the browser that had it before.
///
/// macOS asks the person to confirm each change, so every call can end without
/// the change; the state is always read back from the system, never assumed.
enum BrowserPickerDefaultBrowser {
    static let schemes = ["http", "https"]
    private static let probe = URL(string: "https://example.com")!

    /// The app macOS currently opens web links with.
    static var currentHandler: URL? {
        NSWorkspace.shared.urlForApplication(toOpen: probe)
    }

    static var isThisApp: Bool {
        guard let handler = currentHandler else { return false }
        return Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// The browser links go back to: the one that was default before this app
    /// took over, while it is still installed, or Safari.
    static func previousBrowser(defaults: UserDefaults = .standard) -> URL? {
        if let bundleID = defaults.string(forKey: DefaultsKey.browserPickerPreviousBrowser),
           !BrowserPickerBrowsers.isVorssaint(bundleID),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
    }

    /// Remembers the current browser, then asks macOS to make this app the
    /// default. `completion` runs on the main queue with the resulting state.
    static func makeThisAppDefault(defaults: UserDefaults = .standard, completion: @escaping (Bool) -> Void) {
        if let handler = currentHandler, let bundleID = Bundle(url: handler)?.bundleIdentifier,
           !BrowserPickerBrowsers.isVorssaint(bundleID) {
            defaults.set(bundleID, forKey: DefaultsKey.browserPickerPreviousBrowser)
        }
        setDefault(Bundle.main.bundleURL) { completion(isThisApp) }
    }

    /// Hands web links back to the previous browser. Does nothing when another
    /// browser already took over in the meantime.
    static func restorePrevious(defaults: UserDefaults = .standard, completion: @escaping (Bool) -> Void) {
        guard isThisApp, let previous = previousBrowser(defaults: defaults) else {
            completion(true)
            return
        }
        setDefault(previous) { completion(!isThisApp) }
    }

    /// One scheme at a time: macOS shows its confirmation for the first and
    /// may apply the answer to both, so the second is asked only if needed.
    private static func setDefault(_ appURL: URL, schemes: ArraySlice<String> = ArraySlice(schemes),
                                   completion: @escaping () -> Void) {
        guard let scheme = schemes.first else {
            DispatchQueue.main.async(execute: completion)
            return
        }
        let current = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "\(scheme)://example.com")!)
        guard current?.standardizedFileURL != appURL.standardizedFileURL else {
            setDefault(appURL, schemes: schemes.dropFirst(), completion: completion)
            return
        }
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme) { error in
            DispatchQueue.main.async {
                // A declined confirmation leaves the rest alone too.
                guard error == nil else { return completion() }
                setDefault(appURL, schemes: schemes.dropFirst(), completion: completion)
            }
        }
    }
}
