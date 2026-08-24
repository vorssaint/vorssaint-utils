// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// Apps whose copies never reach the clipboard history (issue #423).
///
/// The pasteboard says what was copied, never who copied it, so the app has to
/// be worked out from who had the screen at the time. The history reads the
/// pasteboard on a timer, which means a copy is only ever noticed some time
/// after it happened, and by then the person may already be in the app they
/// went to paste into. Asking only who is in front at that moment would name
/// the wrong app exactly in the case this list exists for, since the windows
/// that hold passwords usually close themselves the instant something is
/// copied.
///
/// So instead of one guess, every app that came to the front since the last
/// look is kept, and the copy is left out when any of them is on the list. The
/// window is under a second, and leaving out one copy too many is the harmless
/// side of being wrong here.
///
/// Nothing is watched while the list is empty, which is the normal case: no
/// notification is subscribed and every question is answered without work.
final class ClipboardIgnoredApps: ObservableObject {
    static let shared = ClipboardIgnoredApps()

    @Published private(set) var apps: [String] = []

    /// The same list as a set, for the question the history asks.
    private var lookup: Set<String> = []
    /// Every app that held the front since the history last looked at the
    /// pasteboard. Seeded with whoever is in front when the window opens.
    private var candidates: Set<String> = []
    private var activationObserver: NSObjectProtocol?
    /// True while the history itself is running; the observer only lives when
    /// the history is on AND there is at least one app to look for.
    private var historyIsRunning = false

    private init() {
        reload()
    }

    // MARK: - The list

    func reload() {
        let defaults = UserDefaults.standard
        let raw = defaults.stringArray(forKey: DefaultsKey.clipboardHistoryIgnoredApps) ?? []
        let sanitized = Defaults.sanitizedBundleIdentifierList(raw)
        if raw != sanitized {
            defaults.set(sanitized, forKey: DefaultsKey.clipboardHistoryIgnoredApps)
        }
        apps = sanitized
        lookup = Set(sanitized)
        syncObserver()
    }

    func add(_ bundleID: String) {
        let bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty, !apps.contains(bundleID) else { return }
        UserDefaults.standard.set(apps + [bundleID], forKey: DefaultsKey.clipboardHistoryIgnoredApps)
        reload()
    }

    func remove(_ bundleID: String) {
        guard apps.contains(bundleID) else { return }
        UserDefaults.standard.set(apps.filter { $0 != bundleID },
                                  forKey: DefaultsKey.clipboardHistoryIgnoredApps)
        reload()
    }

    // MARK: - Watching

    /// Follows the history: the observer is only installed while the history
    /// is running and there is something to look for.
    func setHistoryRunning(_ running: Bool) {
        guard historyIsRunning != running else { return }
        historyIsRunning = running
        syncObserver()
    }

    private var shouldWatch: Bool {
        historyIsRunning && !lookup.isEmpty
    }

    private func syncObserver() {
        if shouldWatch {
            guard activationObserver == nil else { return }
            candidates = Self.frontmostBundleID().map { [$0] } ?? []
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let app = notification
                    .userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                    let bundleID = app.bundleIdentifier else { return }
                self?.candidates.insert(bundleID)
            }
        } else if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
            candidates = []
        }
    }

    // MARK: - The question the history asks

    /// Whether a copy noticed right now could have come from a listed app, and
    /// opens the next window. Called once per pasteboard check, on the main
    /// thread, whether or not anything was actually copied, so the window
    /// never stretches past the check it belongs to.
    func excludedSourceSinceLastCheck() -> Bool {
        guard shouldWatch else { return false }
        let excluded = !candidates.isDisjoint(with: lookup)
        candidates = Self.frontmostBundleID().map { [$0] } ?? []
        return excluded
    }

    private static func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
