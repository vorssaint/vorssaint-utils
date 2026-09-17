// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
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
        let panel = NSPanel(contentRect: .zero,
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

    static func runningApplication(for snapshot: RadialNowPlayingSnapshot) -> NSRunningApplication? {
        if let bundleIdentifier = snapshot.appBundleIdentifier,
           let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier).first(where: { !$0.isTerminated }) {
            return application
        }
        if let pid = snapshot.appPID {
            return NSRunningApplication(processIdentifier: pid_t(pid))
        }
        return nil
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

    static func open(_ snapshot: RadialNowPlayingSnapshot) {
        if let application = runningApplication(for: snapshot) {
            application.activate(options: [.activateAllWindows])
            return
        }
        guard let identifier = snapshot.appBundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
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
