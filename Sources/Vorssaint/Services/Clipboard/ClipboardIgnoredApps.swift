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
/// side of being wrong here. The same window names the app a copy came from,
/// but only when a single app held the front through it.
final class ClipboardIgnoredApps: ObservableObject {
    static let shared = ClipboardIgnoredApps()

    @Published private(set) var apps: [String] = []

    /// The same list as a set, for the question the history asks.
    private var lookup: Set<String> = []
    /// Every app that held the front since the history last looked at the
    /// pasteboard. Seeded with whoever is in front when the window opens.
    private var candidates: Set<String> = []
    private var activationObserver: NSObjectProtocol?
    /// True while the history itself is running, the only time the observer
    /// lives.
    private var historyIsRunning = false
    private let ownBundleID = Bundle.main.bundleIdentifier

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

    /// Follows the history: the observer is only installed while it runs.
    func setHistoryRunning(_ running: Bool) {
        guard historyIsRunning != running else { return }
        historyIsRunning = running
        if running {
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

    /// Whether a copy noticed right now could have come from a listed app, the
    /// app it came from when only one held the front, and opens the next
    /// window. Called once per pasteboard check, on the main thread, whether
    /// or not anything was actually copied, so the window never stretches
    /// past the check it belongs to. With two apps in the window either could
    /// have copied it, and naming none is better than naming the wrong one.
    /// An app that names itself on the pasteboard is believed over the
    /// guess, and Vorssaint's own writes, which never take the front, name
    /// no app at all.
    func sourceSinceLastCheck(declared: String?) -> (excluded: Bool, bundleID: String?) {
        guard historyIsRunning else { return (false, nil) }
        let guessed = candidates.count == 1 ? candidates.first : nil
        let source = (excluded: !candidates.isDisjoint(with: lookup),
                      bundleID: declared.map { $0 == ownBundleID ? nil : $0 } ?? guessed)
        candidates = Self.frontmostBundleID().map { [$0] } ?? []
        return source
    }

    private static func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
