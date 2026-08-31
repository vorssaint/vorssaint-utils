// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Best-effort answer to "which app was this copied from?", shown as metadata
/// on a saved entry.
///
/// The pasteboard never carries who wrote it, so the only available answer is
/// who held the screen while the copy happened. The history reads the
/// pasteboard on a timer, and copying is usually followed straight away by
/// switching to the app the text is going into, so whoever is in front when a
/// copy is finally noticed is often already the destination, not the source.
///
/// So the whole window between two checks is kept, with the moment each app
/// came to the front, and the app that held the front longest inside that
/// window is the one named. This is a label, never a decision: when nothing is
/// known the entry simply carries no source, and `ClipboardIgnoredApps` still
/// answers the question that actually withholds a copy.
final class ClipboardSourceApp {
    static let shared = ClipboardSourceApp()

    private var window: [ClipboardSourceCandidate] = []
    private var activationObserver: NSObjectProtocol?
    private var historyIsRunning = false

    /// The last ordinary app other than this one to come to the front, for
    /// whoever needs a paste target rather than a copy source. It rides the
    /// same activation notification as the source window instead of a second
    /// observer, but keeps its own filter: a paste has to go to an app with a
    /// UI, while a copy can come from an accessory or a background agent.
    private(set) var lastRegularFrontApp: NSRunningApplication?

    private init() {}

    /// Follows the history: nothing is watched while the history is off.
    func setHistoryRunning(_ running: Bool) {
        guard historyIsRunning != running else { return }
        historyIsRunning = running
        syncObserver()
    }

    /// The likeliest source of a copy noticed right now, and opens the next
    /// window. Called once per pasteboard check, on the main thread, so the
    /// window it answers for always ends here.
    func sourceSinceLastCheck(now: Date = Date()) -> ClipboardEntrySource? {
        guard historyIsRunning else { return nil }
        let source = ClipboardSourceSelection.longestHeld(in: window, until: now)
        window = Self.currentFront(at: now).map { [$0] } ?? []
        return source
    }

    private func syncObserver() {
        if historyIsRunning {
            guard activationObserver == nil else { return }
            window = Self.currentFront(at: Date()).map { [$0] } ?? []
            lastRegularFrontApp = NSWorkspace.shared.frontmostApplication.flatMap(Self.pasteTarget)
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let app = notification
                    .userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                else { return }
                self?.append(app, at: Date())
                if let target = Self.pasteTarget(app) { self?.lastRegularFrontApp = target }
            }
        } else if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
            window = []
            lastRegularFrontApp = nil
        }
    }

    private func append(_ app: NSRunningApplication, at date: Date) {
        guard let candidate = Self.candidate(for: app, at: date) else { return }
        // A window that spans a long idle stretch would otherwise grow with
        // every app switch; only the front runners can win it anyway.
        if window.count > 32 { window.removeFirst(window.count - 32) }
        window.append(candidate)
    }

    /// An app worth pasting into: not this one, and one that owns a normal UI
    /// to receive the keystroke.
    private static func pasteTarget(_ app: NSRunningApplication) -> NSRunningApplication? {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier,
              app.activationPolicy == .regular
        else { return nil }
        return app
    }

    private static func currentFront(at date: Date) -> ClipboardSourceCandidate? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return candidate(for: app, at: date)
    }

    private static func candidate(for app: NSRunningApplication,
                                  at date: Date) -> ClipboardSourceCandidate? {
        guard let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier
        else { return nil }
        return ClipboardSourceCandidate(source: ClipboardEntrySource(bundleID: bundleID,
                                                                     name: app.localizedName ?? bundleID),
                                        frontSince: date)
    }
}
