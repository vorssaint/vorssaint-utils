// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftUI

/// A session-scoped view of macOS Now Playing. The read itself lives in the
/// bridge below, out of process; a failed run, a timeout and malformed
/// metadata all arrive here as an empty playback session.
/// Nothing here is required for the radial menu itself to work.
final class RadialNowPlayingService {
    static let shared = RadialNowPlayingService()

    private let bridge = MediaRemoteNowPlayingBridge()
    private var generation = 0
    private(set) var state = RadialNowPlayingState.nothingPlaying
    private var pendingPresentationAnchor: CGPoint?
    private var panel: NSPanel?
    private var eventMonitors: [Any] = []
    private var activationObserver: NSObjectProtocol?

    private init() {}

    func refresh(update: @escaping (RadialNowPlayingState) -> Void) {
        generation += 1
        let requestedGeneration = generation
        state = .loading
        update(.loading)
        bridge.fetch { [weak self] snapshot in
            DispatchQueue.main.async {
                guard let self, self.generation == requestedGeneration else { return }
                let nextState = snapshot.map(RadialNowPlayingState.playing) ?? .nothingPlaying
                self.state = nextState
                update(nextState)
                guard let anchor = self.pendingPresentationAnchor else { return }
                self.pendingPresentationAnchor = nil
                if case let .playing(snapshot) = nextState {
                    self.showCard(snapshot: snapshot, at: anchor)
                }
            }
        }
    }

    func presentDetails(at anchor: CGPoint) {
        switch state {
        case let .playing(snapshot):
            showCard(snapshot: snapshot, at: anchor)
        case .loading:
            pendingPresentationAnchor = anchor
        case .nothingPlaying:
            break
        }
    }

    func dismissDetails() {
        pendingPresentationAnchor = nil
        removeMonitors()
        panel?.orderOut(nil)
    }

    private func showCard(snapshot: RadialNowPlayingSnapshot, at anchor: CGPoint) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.showCard(snapshot: snapshot, at: anchor) }
            return
        }
        dismissDetails()
        let card = RadialNowPlayingCard(snapshot: snapshot) { [weak self] in
            self?.dismissDetails()
            RadialNowPlayingApplication.open(snapshot)
        }
        let host = NSHostingController(rootView: card)
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize
        let panel = ensurePanel()
        panel.contentViewController = host

        let visibleFrame = NSScreen.screens.first(where: { $0.frame.contains(anchor) })?.visibleFrame
            ?? NSScreen.pointerVisibleFrame
        let x = min(max(anchor.x - size.width / 2, visibleFrame.minX + 12),
                    visibleFrame.maxX - size.width - 12)
        let y = min(max(anchor.y - size.height / 2, visibleFrame.minY + 12),
                    visibleFrame.maxY - size.height - 12)
        panel.setFrame(NSRect(origin: CGPoint(x: x, y: y), size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        installMonitors(for: panel)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = OverlayPanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered,
                                 defer: false)
        panel.title = "Now Playing"
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        self.panel = panel
        return panel
    }

    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self, weak panel] event in
            guard let self, let panel else { return event }
            if event.window !== panel { self.dismissDetails() }
            return event
        }) { eventMonitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            DispatchQueue.main.async { self?.dismissDetails() }
        }) { eventMonitors.append(monitor) }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.dismissDetails()
        }
    }

    private func removeMonitors() {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors = []
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }
}

private struct RadialNowPlayingCard: View {
    let snapshot: RadialNowPlayingSnapshot
    let openApplication: () -> Void

    @ObservedObject private var l10n = L10n.shared

    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    private var appName: String {
        RadialNowPlayingApplication.name(for: snapshot) ?? text.mediaNowPlaying
    }
    private var title: String { snapshot.title ?? appName }

    var body: some View {
        Button(action: openApplication) {
            HStack(alignment: .center, spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    if let album = snapshot.album {
                        Text(album)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let artist = snapshot.artist {
                        Text(artist)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 5) {
                        if let icon = RadialNowPlayingApplication.icon(for: snapshot) {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 14, height: 14)
                        }
                        Text(String(format: text.mediaOpenAppFormat, appName))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 320, alignment: .leading)
            .background(HUDBackdrop(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(String(format: text.mediaOpenAppFormat, appName))
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = snapshot.artworkData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.spaceGradient)
                .frame(width: 76, height: 76)
                .overlay {
                    if let icon = RadialNowPlayingApplication.icon(for: snapshot) {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 42, height: 42)
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
        }
    }
}

enum RadialNowPlayingApplication {
    private static var icons: [String: NSImage] = [:]
    private static var missingIcons = Set<String>()

    /// A browser plays web media from a helper process with no windows of its
    /// own. When the adapter cannot name the browser, the reported process is
    /// that helper, so a background process resolves to the app that owns it.
    static func runningApplication(for snapshot: RadialNowPlayingSnapshot) -> NSRunningApplication? {
        let reported = snapshot.appBundleIdentifier.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).first(where: { !$0.isTerminated })
        } ?? snapshot.appPID.flatMap { NSRunningApplication(processIdentifier: pid_t($0)) }
        guard let reported, reported.activationPolicy != .regular else { return reported }
        let pid = snapshot.appPID.map { pid_t($0) } ?? reported.processIdentifier
        return ResponsibleProcess.regularAppOwner(of: pid) ?? reported
    }

    static func name(for snapshot: RadialNowPlayingSnapshot) -> String? {
        if let name = runningApplication(for: snapshot)?.localizedName, !name.isEmpty { return name }
        guard let identifier = snapshot.appBundleIdentifier else { return nil }
        return identifier.split(separator: ".").last.map(String.init)
    }

    static func icon(for snapshot: RadialNowPlayingSnapshot) -> NSImage? {
        let key = snapshot.appBundleIdentifier ?? snapshot.appPID.map { "pid:\($0)" } ?? ""
        if let icon = icons[key] { return icon }
        if missingIcons.contains(key) { return nil }
        let icon: NSImage?
        if let runningIcon = runningApplication(for: snapshot)?.icon {
            icon = runningIcon
        } else if let identifier = snapshot.appBundleIdentifier,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = nil
        }
        if let icon {
            icons[key] = icon
        } else {
            missingIcons.insert(key)
        }
        return icon
    }

    /// The island and the radial card are non-activating panels, so Vorssaint
    /// rarely holds activation when one is clicked. Since macOS 14 a bare
    /// request from an inactive app is refused, and the player stayed behind.
    static func open(_ snapshot: RadialNowPlayingSnapshot) {
        if let application = runningApplication(for: snapshot) {
            // A helper takes no activation; the handoff would leave Vorssaint in front.
            guard application.activationPolicy == .regular else { return }
            // Read before the unhide below: a hidden player's windows come back with it.
            let showsNoWindow = !application.isHidden && !hasWindowOnScreen(pid: application.processIdentifier)
            if application.isHidden { application.unhide() }
            ActivationHandoff.yield(to: application)
            if !application.activate(from: NSRunningApplication.current, options: [.activateAllWindows]) {
                application.activate(options: [.activateAllWindows])
            }
            // Like a Dock click, a player that keeps playing with its window
            // closed shows one again, the way the App Switcher reopens a
            // windowless app. Activation alone would leave nothing to see.
            if showsNoWindow, let url = application.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                configuration.addsToRecentItems = false
                configuration.promptsUserIfNeeded = false
                NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            }
            NowPlayingTabFocus.select(trackTitle: snapshot.title, in: application)
            return
        }
        guard let identifier = snapshot.appBundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Whether the player has a window on the current Space. One on another
    /// Space reads as none, and the reopen that follows is harmless there.
    private static func hasWindowOnScreen(pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                 kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }
    }
}

/// Activation brings a browser's front window forward, which may show a
/// different tab from the one playing. With Accessibility, this finds the tab
/// whose title carries the track, selects it and raises its window. It tries
/// three ways, cheapest first. A tab strip the browser exposes gets its tab
/// pressed. A window whose title already shows the track only gets raised.
/// A Firefox-family browser that hides its tabs, as Zen does in compact mode,
/// gets Control-Page Down until its window title shows the track. Without
/// Accessibility or a match, the app stays as activation left it.
private enum NowPlayingTabFocus {
    private static let queue = DispatchQueue(label: "com.vorssaint.now-playing-tab", qos: .userInitiated)
    private static let maximumElements = 1_500
    private static let maximumCycledTabs = 50

    static func select(trackTitle: String?, in application: NSRunningApplication) {
        guard let trackTitle, Permissions.shared.accessibility else { return }
        queue.async {
            let pid = application.processIdentifier
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.25)
            let windows: [AXUIElement] = attribute(kAXWindowsAttribute, of: app) ?? []
            var tabs: [(tab: AXUIElement, window: AXUIElement)] = []
            for window in windows {
                tabs += tabButtons(in: window).map { ($0, window) }
            }
            let tabTitles = tabs.map { attribute(kAXTitleAttribute, of: $0.tab) ?? "" }
            if let index = RadialNowPlayingSupport.playingTabIndex(tabTitles: tabTitles, trackTitle: trackTitle) {
                AXUIElementPerformAction(tabs[index].tab, kAXPressAction as CFString)
                raise(tabs[index].window, in: app)
                return
            }
            let windowTitles = windows.map { attribute(kAXTitleAttribute, of: $0) ?? "" }
            if let index = RadialNowPlayingSupport.playingTabIndex(tabTitles: windowTitles, trackTitle: trackTitle) {
                raise(windows[index], in: app)
                return
            }
            guard tabs.isEmpty,
                  RadialNowPlayingSupport.keyboardTabCyclingBrowsers.contains(application.bundleIdentifier ?? ""),
                  waitUntilActive(application) else { return }
            for window in windows where attribute(kAXMinimizedAttribute, of: window) != true {
                raise(window, in: app)
                if cycleTabs(of: window, pid: pid, trackTitle: trackTitle) { return }
            }
            if let front = windows.first { raise(front, in: app) }
        }
    }

    private static func raise(_ window: AXUIElement, in app: AXUIElement) {
        if attribute(kAXMinimizedAttribute, of: window) == true {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(app, kAXMainWindowAttribute as CFString, window)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    /// Keystrokes land in the browser's key window, so they wait until the
    /// activation that `open` asked for has taken effect.
    private static func waitUntilActive(_ application: NSRunningApplication) -> Bool {
        for _ in 0..<25 {
            if application.isActive { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return application.isActive
    }

    /// Steps through the window's tabs until its title shows the track. It
    /// stops back on the first tab, and also after two presses that change
    /// nothing, since the window then has one tab or ignores the shortcut.
    private static func cycleTabs(of window: AXUIElement, pid: pid_t, trackTitle: String) -> Bool {
        guard let start: String = attribute(kAXTitleAttribute, of: window) else { return false }
        var current = start
        var unchanged = 0
        for _ in 0..<maximumCycledTabs {
            pressNextTab(pid: pid)
            guard let next = titleChange(of: window, from: current) else {
                unchanged += 1
                if unchanged == 2 { return false }
                continue
            }
            unchanged = 0
            current = next
            switch RadialNowPlayingSupport.tabCycleStep(startTitle: start, currentTitle: current, trackTitle: trackTitle) {
            case .found: return true
            case .wrapped: return false
            case .next: continue
            }
        }
        return false
    }

    private static func pressNextTab(pid: pid_t) {
        let source = CGEventSource(stateID: .privateState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_PageDown),
                                      keyDown: keyDown) else { return }
            event.flags = .maskControl
            event.postToPid(pid)
        }
    }

    private static func titleChange(of window: AXUIElement, from title: String) -> String? {
        for _ in 0..<15 {
            Thread.sleep(forTimeInterval: 0.02)
            if let current: String = attribute(kAXTitleAttribute, of: window), current != title { return current }
        }
        return nil
    }

    /// Chrome, Safari and Firefox all expose a tab as a radio button inside a
    /// tab group, sometimes a level or two further down. The walk reads breadth
    /// first and never enters a web page.
    private static func tabButtons(in window: AXUIElement) -> [AXUIElement] {
        var pending: [(element: AXUIElement, inTabGroup: Bool)] = [(window, false)]
        var tabs: [AXUIElement] = []
        var visited = 0
        while !pending.isEmpty, visited < maximumElements {
            let (element, inTabGroup) = pending.removeFirst()
            visited += 1
            let role: String? = attribute(kAXRoleAttribute, of: element)
            if role == "AXWebArea" { continue }
            if inTabGroup, role == kAXRadioButtonRole {
                tabs.append(element)
                continue
            }
            let children: [AXUIElement] = attribute(kAXChildrenAttribute, of: element) ?? []
            pending += children.map { ($0, inTabGroup || role == kAXTabGroupRole) }
        }
        return tabs
    }

    private static func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}

/// Reads Now Playing through `/usr/bin/perl` loading the adapter library
/// (`Sources/NowPlayingAdapter`). Since macOS 15.4 MediaRemote answers only
/// processes carrying Apple's signature; perl is one, the app is not. A
/// missing script or library, a failed run, a timeout and malformed output
/// all read as an empty playback session.
private final class MediaRemoteNowPlayingBridge {
    private let queue = DispatchQueue(label: "com.vorssaint.radial-now-playing", qos: .userInitiated)
    /// 2 s: a cold perl load measured 500 ms with no session playing, and a
    /// real reply adds the MediaRemote round trip plus up to 16 MB of base64
    /// artwork through the pipe. A kill reads as nothing playing, so a deadline
    /// that is too tight empties the first wheel after login (#1280). The wheel
    /// shows `.loading` and holds the card anchor while it waits, so the extra
    /// second costs nothing on screen.
    private static let replyTimeout: TimeInterval = 2.0

    func fetch(completion: @escaping (RadialNowPlayingSnapshot?) -> Void) {
        guard let script = Bundle.main.url(forResource: "now-playing", withExtension: "pl"),
              let library = Bundle.main.privateFrameworksURL?
                .appendingPathComponent("libVorssaintNowPlaying.dylib"),
              FileManager.default.fileExists(atPath: library.path) else {
            completion(nil)
            return
        }
        queue.async {
            let result = BoundedProcessRunner.run("/usr/bin/perl", [script.path, library.path],
                                                  timeout: Self.replyTimeout,
                                                  maxOutputBytes: RadialNowPlayingSupport.maximumAdapterReplyBytes)
            guard result.status == 0, !result.timedOut,
                  let reply = RadialNowPlayingSupport.adapterReply(from: result.output) else {
                completion(nil)
                return
            }
            let isPlaying = RadialNowPlayingSupport.playbackIsActive(
                remoteIsPlaying: reply.isPlaying, info: reply.info)
            completion(RadialNowPlayingSupport.snapshot(info: reply.info,
                                                        isPlaying: isPlaying,
                                                        appBundleIdentifier: reply.displayID,
                                                        appPID: reply.pid))
        }
    }
}
