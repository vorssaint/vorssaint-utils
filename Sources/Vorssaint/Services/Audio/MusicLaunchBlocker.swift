// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Keeps the system music app from opening on its own, which macOS does
/// whenever a media key is pressed with no other player around to take it.
///
/// While the option is on, every launch of the music app is terminated the
/// moment it starts, before its window appears, and an optional replacement
/// app opens instead. The user opts back into the music app by turning the
/// setting off. Nothing runs while the feature is off: no observers, no
/// timers, no cost.
final class MusicLaunchBlocker: ObservableObject {
    static let shared = MusicLaunchBlocker()

    /// The current and the legacy identifier of the system music app.
    static let blockedBundleIDs: Set<String> = ["com.apple.Music", "com.apple.iTunes"]

    private var observers: [NSObjectProtocol] = []
    /// One media key press produces both a will-launch and a did-launch
    /// notification; the replacement should open once, not twice.
    private var lastReplacementLaunch: TimeInterval = 0

    private init() {}

    func syncWithPreferences() {
        if AppFeature.musicBlock.isAvailable, UserDefaults.standard.bool(forKey: DefaultsKey.musicBlockEnabled) {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        // Will-launch usually wins the race before any window shows;
        // did-launch catches the rare launch that slips past it.
        observers = [NSWorkspace.willLaunchApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.handleLaunch(note)
            }
        }
    }

    func stop() {
        guard !observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers = []
    }

    private func handleLaunch(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              Self.blockedBundleIDs.contains(bundleID) else { return }
        if !app.forceTerminate() {
            app.terminate()
        }
        openReplacementIfConfigured()
    }

    private func openReplacementIfConfigured() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastReplacementLaunch > 1.0 else { return }
        lastReplacementLaunch = now

        let path = UserDefaults.standard.string(forKey: DefaultsKey.musicBlockReplacementPath) ?? ""
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        // The replacement must never be the app being blocked, or the two
        // settings would chase each other in a launch-and-kill loop.
        guard let replacementID = Bundle(url: url)?.bundleIdentifier,
              !Self.blockedBundleIDs.contains(replacementID),
              FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
