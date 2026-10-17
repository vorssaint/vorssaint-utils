// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// Apps the user never wants open: each listed app is asked to quit as soon
/// as it launches. A copy already running when it is listed is left alone
/// until its next launch. Nothing watches launches while the list is empty or
/// the feature is off in the hub.
final class AppLaunchBlocker: ObservableObject {
    static let shared = AppLaunchBlocker()

    @Published private(set) var apps: [String] = []

    private var observers: [NSObjectProtocol] = []

    private init() {
        reload()
    }

    /// Vorssaint itself, and the system components under /System/Library
    /// (Finder, the Dock, loginwindow and friends), which launchd would
    /// relaunch in a loop or whose loss breaks the session. Apps in
    /// /System/Applications stay blockable. A backup can carry any id, so
    /// launches are checked too, not just the picker.
    static func isProtected(bundleID: String, bundleURL: URL?) -> Bool {
        let url = bundleURL ?? InstalledApps.url(for: bundleID)
        return bundleID.hasPrefix("com.vorssaint.")
            || url?.path.hasPrefix("/System/Library/") == true
    }

    func reload() {
        let defaults = UserDefaults.standard
        let raw = defaults.stringArray(forKey: DefaultsKey.appLaunchBlockBundleIDs) ?? []
        let sanitized = Defaults.sanitizedBundleIdentifierList(raw)
        if raw != sanitized {
            defaults.set(sanitized, forKey: DefaultsKey.appLaunchBlockBundleIDs)
        }
        apps = sanitized
    }

    func add(_ bundleID: String) {
        let bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty, !apps.contains(bundleID) else { return }
        UserDefaults.standard.set(apps + [bundleID], forKey: DefaultsKey.appLaunchBlockBundleIDs)
        reload()
        syncWithPreferences()
    }

    func remove(_ bundleID: String) {
        guard apps.contains(bundleID) else { return }
        UserDefaults.standard.set(apps.filter { $0 != bundleID }, forKey: DefaultsKey.appLaunchBlockBundleIDs)
        reload()
        syncWithPreferences()
    }

    func syncWithPreferences() {
        let center = NSWorkspace.shared.notificationCenter
        guard AppFeature.musicBlock.isAvailable, !apps.isEmpty else {
            for observer in observers { center.removeObserver(observer) }
            observers = []
            return
        }
        guard observers.isEmpty else { return }
        // Will-launch quits most apps before a window shows; did-launch
        // catches one that was not ready to take the request yet.
        observers = [NSWorkspace.willLaunchApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.handleLaunch(note)
            }
        }
    }

    private func handleLaunch(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              apps.contains(bundleID),
              !Self.isProtected(bundleID: bundleID, bundleURL: app.bundleURL) else { return }
        // A polite quit lets an app save documents it restored on launch; one
        // that refuses shows its own dialog instead of losing them.
        app.terminate()
    }
}
