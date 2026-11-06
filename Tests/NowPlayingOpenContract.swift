// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Resolving and opening the player from the island's cover or the radial
/// Now Playing card runs as shipped against doubles for process discovery,
/// responsibility and activation. No app is activated, unhidden or launched.
enum NowPlayingOpenContract {
    static var events: [String] = []
    static var cooperativeActivation = true
    static var running: [App] = []
    static var owners: [pid_t: pid_t] = [:]
    static var ownerLookups: [pid_t] = []
    static var installed: [String: URL] = [:]
    static var windowOnScreen = true

    final class App {
        static let current = App(pid: 1)
        let processIdentifier: pid_t
        let bundleIdentifier: String
        let isTerminated = false
        let isHidden: Bool
        let activationPolicy: NSApplication.ActivationPolicy
        let bundleURL: URL? = URL(fileURLWithPath: "/Applications/Player.app")
        init(pid: pid_t, bundleIdentifier: String = "org.example.player", isHidden: Bool = false,
             activationPolicy: NSApplication.ActivationPolicy = .regular) {
            self.processIdentifier = pid
            self.bundleIdentifier = bundleIdentifier
            self.isHidden = isHidden
            self.activationPolicy = activationPolicy
        }
        convenience init?(processIdentifier pid: pid_t) {
            guard let app = running.first(where: { $0.processIdentifier == pid }) else { return nil }
            self.init(pid: pid, bundleIdentifier: app.bundleIdentifier,
                      isHidden: app.isHidden, activationPolicy: app.activationPolicy)
        }
        static func runningApplications(withBundleIdentifier identifier: String) -> [App] {
            running.filter { $0.bundleIdentifier == identifier }
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
    enum Responsibility {
        static func regularAppOwner(of pid: pid_t) -> App? {
            ownerLookups.append(pid)
            return owners[pid].flatMap(App.init(processIdentifier:))
        }
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
    enum Application {
        typealias NSRunningApplication = App
        typealias ActivationHandoff = Handoff
        typealias ResponsibleProcess = Responsibility
        typealias NSWorkspace = Workspace
        static func hasWindowOnScreen(pid: pid_t) -> Bool { windowOnScreen }
    }

    static func run(_ suite: TestSuite) {
        let track = RadialNowPlayingSnapshot(title: "Track", artist: nil, album: nil, artworkData: nil,
                                             appBundleIdentifier: "org.example.player", appPID: 20)
        func open(_ app: App?, cooperative: Bool = true, installedAt url: URL? = nil, window: Bool = true) {
            events = []
            running = app.map { [$0] } ?? []
            owners = [:]
            ownerLookups = []
            windowOnScreen = window
            cooperativeActivation = cooperative
            installed = url.map { ["org.example.player": $0] } ?? [:]
            Application.open(track)
        }
        open(App(pid: 20))
        suite.expect(events == ["yield:20", "activate:20:1:true"],
                     "the cover hands Vorssaint's activation to the player before asking for all its windows")
        open(App(pid: 20), cooperative: false)
        suite.expect(events == ["yield:20", "activate:20:1:true", "fallback:20:true"],
                     "a refused cooperative request still falls back to a direct one")
        open(App(pid: 20, isHidden: true))
        suite.expect(events == ["unhide:20", "yield:20", "activate:20:1:true"],
                     "a hidden player is shown before it is activated")
        for policy in [NSApplication.ActivationPolicy.accessory, .prohibited] {
            open(App(pid: 20, activationPolicy: policy),
                 installedAt: URL(fileURLWithPath: "/Applications/Player.app"))
            suite.expect(events.isEmpty,
                         "a helper that takes no activation leaves Vorssaint inactive and launches nothing")
        }
        open(App(pid: 20), window: false)
        suite.expect(events == ["yield:20", "activate:20:1:true", "reopen:Player.app"],
                     "a player playing with its window closed shows one again, like a Dock click")
        open(App(pid: 20, isHidden: true), window: false)
        suite.expect(events == ["unhide:20", "yield:20", "activate:20:1:true"],
                     "a hidden player's own windows come back with it, so no reopen is sent")
        open(nil, installedAt: URL(fileURLWithPath: "/Applications/Player.app"))
        suite.expect(events == ["launch:Player.app"], "a player that has quit opens again from its bundle")
        open(nil)
        suite.expect(events.isEmpty, "a player that is neither running nor installed is left alone")

        checkWebKitPlayers(suite)
    }

    private static func checkWebKitPlayers(_ suite: TestSuite) {
        let bundle = "com.apple.WebKit.GPU"
        let safari = App(pid: 1479, bundleIdentifier: "com.apple.Safari")
        let other = App(pid: 900, bundleIdentifier: "org.example.browser")
        let helper = App(pid: 1490, bundleIdentifier: bundle, activationPolicy: .prohibited)
        let otherHelper = App(pid: 27306, bundleIdentifier: bundle, activationPolicy: .prohibited)
        owners = [1490: 1479, 27306: 900]
        cooperativeActivation = true
        windowOnScreen = true
        installed = [bundle: URL(fileURLWithPath: "/Applications/Helper.app")]
        defer {
            running = []
            owners = [:]
            ownerLookups = []
            installed = [:]
            events = []
        }

        // Go through the adapter decoder and snapshot builder, including their
        // normalization of missing and nonpositive pids, before resolving/opening.
        func reading(pid: Int32?, bundle: String?) -> RadialNowPlayingSnapshot? {
            var fields: [String: Any] = [RadialNowPlayingSupport.titleKey: "Track", "isPlaying": true]
            if let pid { fields["pid"] = pid }
            if let bundle { fields["displayID"] = bundle }
            guard let data = try? JSONSerialization.data(withJSONObject: fields),
                  let reply = RadialNowPlayingSupport.adapterReply(from: data) else { return nil }
            return RadialNowPlayingSupport.snapshot(info: reply.info,
                isPlaying: RadialNowPlayingSupport.playbackIsActive(remoteIsPlaying: reply.isPlaying, info: reply.info),
                appBundleIdentifier: reply.displayID, appPID: reply.pid)
        }

        for helpers in [[otherHelper, helper], [helper, otherHelper]] {
            running = helpers + [safari, other]
            for pid: Int32? in [nil, 0, -1] {
                guard let snapshot = reading(pid: pid, bundle: bundle) else {
                    suite.expect(false, "a WebKit reading without a usable pid keeps its metadata")
                    continue
                }
                events = []
                ownerLookups = []
                let application = Application.runningApplication(for: snapshot)
                Application.open(snapshot)
                suite.expect(snapshot.appPID == nil && application?.processIdentifier == helpers[0].processIdentifier,
                             "without a reading pid either shared helper remains the unresolved fallback")
                suite.expect(ownerLookups.isEmpty && events.isEmpty,
                             "an ambiguous helper neither resolves an owner nor activates or launches another app")
            }
        }

        running = [otherHelper, helper, safari, other]
        let players: [(Int32?, String?, pid_t)] = [
            (1490, bundle, 1479), (27306, bundle, 900),
            (1490, nil, 1479), (1479, bundle, 1479), (nil, safari.bundleIdentifier, 1479),
        ]
        for (pid, identifier, expected) in players {
            guard let snapshot = reading(pid: pid, bundle: identifier) else {
                suite.expect(false, "an identified player reading decodes")
                continue
            }
            events = []
            ownerLookups = []
            Application.open(snapshot)
            suite.expect(events == ["yield:\(expected)", "activate:\(expected):1:true"],
                         "a helper's own pid or a regular player's identity opens the intended app")
        }

        let orphan = App(pid: 4242, bundleIdentifier: bundle, activationPolicy: .prohibited)
        running.append(orphan)
        guard let snapshot = reading(pid: 4242, bundle: bundle) else {
            suite.expect(false, "an ownerless helper reading decodes")
            return
        }
        events = []
        let application = Application.runningApplication(for: snapshot)
        Application.open(snapshot)
        suite.expect(application?.processIdentifier == 4242 && events.isEmpty,
                     "a helper with no owner stays itself and opens no other WebKit app")
    }
}
