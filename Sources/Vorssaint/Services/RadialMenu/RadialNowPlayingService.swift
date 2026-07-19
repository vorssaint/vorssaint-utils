// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin
import Foundation
import SwiftUI

/// A session-scoped view of macOS Now Playing. MediaRemote is private, so the
/// bridge resolves every entry point dynamically and treats missing symbols,
/// timeouts and malformed metadata exactly like an empty playback session.
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

private final class MediaRemoteNowPlayingBridge {
    private typealias InfoCallback = @convention(block) (NSDictionary?) -> Void
    private typealias InfoFunction = @convention(c) (DispatchQueue, @escaping InfoCallback) -> Void
    private typealias PIDCallback = @convention(block) (Int32) -> Void
    private typealias PIDFunction = @convention(c) (DispatchQueue, @escaping PIDCallback) -> Void
    private typealias DisplayIDCallback = @convention(block) (NSString?) -> Void
    private typealias DisplayIDFunction = @convention(c) (DispatchQueue, @escaping DisplayIDCallback) -> Void
    private typealias IsPlayingCallback = @convention(block) (Bool) -> Void
    private typealias IsPlayingFunction = @convention(c) (DispatchQueue, @escaping IsPlayingCallback) -> Void

    private let queue = DispatchQueue(label: "com.vorssaint.radial-now-playing", qos: .userInitiated)
    private let handle: UnsafeMutableRawPointer?
    private let getInfo: InfoFunction?
    private let getPID: PIDFunction?
    private let getDisplayID: DisplayIDFunction?
    private let getIsPlaying: IsPlayingFunction?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        self.handle = handle
        getInfo = Self.function(handle, "MRMediaRemoteGetNowPlayingInfo", as: InfoFunction.self)
        getPID = Self.function(handle, "MRMediaRemoteGetNowPlayingApplicationPID", as: PIDFunction.self)
        getDisplayID = Self.function(handle, "MRMediaRemoteGetNowPlayingApplicationDisplayID",
                                     as: DisplayIDFunction.self)
        getIsPlaying = Self.function(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying",
                                     as: IsPlayingFunction.self)
    }

    deinit {
        if let handle { dlclose(handle) }
    }

    func fetch(completion: @escaping (RadialNowPlayingSnapshot?) -> Void) {
        guard let getInfo else {
            completion(nil)
            return
        }
        let result = FetchResult(completion: completion)
        let group = DispatchGroup()

        group.enter()
        getInfo(queue) { info in
            result.setInfo(info as? [String: Any] ?? [:])
            group.leave()
        }
        if let getPID {
            group.enter()
            getPID(queue) { pid in
                result.setPID(pid)
                group.leave()
            }
        }
        if let getDisplayID {
            group.enter()
            getDisplayID(queue) { identifier in
                result.setDisplayID(identifier as String?)
                group.leave()
            }
        }
        if let getIsPlaying {
            group.enter()
            getIsPlaying(queue) { isPlaying in
                result.setRemoteIsPlaying(isPlaying)
                group.leave()
            }
        }

        group.notify(queue: queue) { result.finish() }
        queue.asyncAfter(deadline: .now() + 0.75) { result.finish() }
    }

    private static func function<T>(_ handle: UnsafeMutableRawPointer?,
                                    _ name: String,
                                    as type: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    private final class FetchResult {
        private let lock = NSLock()
        private var info: [String: Any] = [:]
        private var pid: Int32 = 0
        private var displayID: String?
        private var remoteIsPlaying: Bool?
        private var finished = false
        private let completion: (RadialNowPlayingSnapshot?) -> Void

        init(completion: @escaping (RadialNowPlayingSnapshot?) -> Void) {
            self.completion = completion
        }

        func setInfo(_ info: [String: Any]) {
            lock.withLock { self.info = info }
        }

        func setPID(_ pid: Int32) {
            lock.withLock { self.pid = pid }
        }

        func setDisplayID(_ displayID: String?) {
            lock.withLock { self.displayID = displayID }
        }

        func setRemoteIsPlaying(_ remoteIsPlaying: Bool) {
            lock.withLock { self.remoteIsPlaying = remoteIsPlaying }
        }

        func finish() {
            let values: ([String: Any], Int32, String?, Bool?)? = lock.withLock {
                guard !finished else { return nil }
                finished = true
                return (info, pid, displayID, remoteIsPlaying)
            }
            guard let (info, pid, displayID, remoteIsPlaying) = values else { return }
            let isPlaying = RadialNowPlayingSupport.playbackIsActive(
                remoteIsPlaying: remoteIsPlaying, info: info)
            completion(RadialNowPlayingSupport.snapshot(info: info,
                                                        isPlaying: isPlaying,
                                                        appBundleIdentifier: displayID,
                                                        appPID: pid))
        }
    }
}
