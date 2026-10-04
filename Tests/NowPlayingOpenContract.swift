// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Opening the player from the island's cover or the radial Now Playing card
/// runs as shipped against doubles that never activate, unhide or launch an
/// app. Both are non-activating panels, so Vorssaint rarely holds activation
/// of its own, and a bare request left the player where it was.
enum NowPlayingOpenContract {
    static var events: [String] = []
    static var cooperativeActivation = true
    static var running: App?
    static var installed: [String: URL] = [:]
    static var windowOnScreen = true

    final class App {
        static let current = App(processIdentifier: 1)
        let processIdentifier: pid_t
        let isHidden: Bool
        let activationPolicy: NSApplication.ActivationPolicy
        let bundleURL: URL? = URL(fileURLWithPath: "/Applications/Player.app")
        init(processIdentifier: pid_t, isHidden: Bool = false,
             activationPolicy: NSApplication.ActivationPolicy = .regular) {
            self.processIdentifier = processIdentifier
            self.isHidden = isHidden
            self.activationPolicy = activationPolicy
        }
        func unhide() { events.append("unhide:\(processIdentifier)") }
        @discardableResult func activate(from source: App, options: NSApplication.ActivationOptions) -> Bool {
            events.append("activate:\(processIdentifier):\(source.processIdentifier):\(options.contains(.activateAllWindows))")
            return cooperativeActivation
        }
        @discardableResult func activate(options: NSApplication.ActivationOptions) -> Bool {
            events.append("fallback:\(processIdentifier):\(options.contains(.activateAllWindows))")
            return true
        }
    }
    enum Handoff {
        static func yield(to app: App) { events.append("yield:\(app.processIdentifier)") }
    }
    final class Workspace {
        final class OpenConfiguration {
            var activates = true
            var addsToRecentItems = true
            var promptsUserIfNeeded = true
        }
        static let shared = Workspace()
        func urlForApplication(withBundleIdentifier identifier: String) -> URL? { installed[identifier] }
        func openApplication(at url: URL, configuration: OpenConfiguration) {
            // A reopen shows a window without taking activation from the handoff.
            let quiet = !configuration.activates && !configuration.addsToRecentItems && !configuration.promptsUserIfNeeded
            events.append("\(quiet ? "reopen" : "launch"):\(url.lastPathComponent)")
        }
    }
    static var tabSelections: [String] = []
    enum TabFocus {
        static func select(trackTitle: String?, in application: App) {
            tabSelections.append("\(trackTitle ?? "nil"):\(application.processIdentifier)")
        }
    }
    enum Application {
        typealias NSRunningApplication = App
        typealias ActivationHandoff = Handoff
        typealias NSWorkspace = Workspace
        typealias NowPlayingTabFocus = TabFocus
        static func runningApplication(for snapshot: RadialNowPlayingSnapshot) -> App? { running }
        static func hasWindowOnScreen(pid: pid_t) -> Bool { windowOnScreen }
    }

    static func run(_ suite: TestSuite) {
        let track = RadialNowPlayingSnapshot(title: "Track", artist: nil, album: nil, artworkData: nil,
                                             appBundleIdentifier: "org.example.player", appPID: 20)
        func open(_ app: App?, cooperative: Bool = true, installedAt url: URL? = nil, window: Bool = true) {
            events = []
            tabSelections = []
            running = app
            windowOnScreen = window
            cooperativeActivation = cooperative
            installed = url.map { ["org.example.player": $0] } ?? [:]
            Application.open(track)
        }
        open(App(processIdentifier: 20))
        suite.expect(events == ["yield:20", "activate:20:1:true"],
                     "the cover hands Vorssaint's activation to the player before asking for all its windows")
        suite.expect(tabSelections == ["Track:20"],
                     "a running player also gets its playing tab selected, by the track's title")
        open(App(processIdentifier: 20), cooperative: false)
        suite.expect(events == ["yield:20", "activate:20:1:true", "fallback:20:true"],
                     "a refused cooperative request still falls back to a direct one")
        open(App(processIdentifier: 20, isHidden: true))
        suite.expect(events == ["unhide:20", "yield:20", "activate:20:1:true"],
                     "a hidden player is shown before it is activated")
        for policy in [NSApplication.ActivationPolicy.accessory, .prohibited] {
            open(App(processIdentifier: 20, activationPolicy: policy),
                 installedAt: URL(fileURLWithPath: "/Applications/Player.app"))
            suite.expect(events.isEmpty && tabSelections.isEmpty,
                         "a helper that takes no activation leaves Vorssaint inactive and launches nothing")
        }
        open(App(processIdentifier: 20), window: false)
        suite.expect(events == ["yield:20", "activate:20:1:true", "reopen:Player.app"],
                     "a player playing with its window closed shows one again, like a Dock click")
        open(App(processIdentifier: 20, isHidden: true), window: false)
        suite.expect(events == ["unhide:20", "yield:20", "activate:20:1:true"],
                     "a hidden player's own windows come back with it, so no reopen is sent")
        open(nil, installedAt: URL(fileURLWithPath: "/Applications/Player.app"))
        suite.expect(events == ["launch:Player.app"] && tabSelections.isEmpty,
                     "a player that has quit opens again from its bundle, with no tab to select yet")
        open(nil)
        suite.expect(events.isEmpty, "a player that is neither running nor installed is left alone")
    }
}
