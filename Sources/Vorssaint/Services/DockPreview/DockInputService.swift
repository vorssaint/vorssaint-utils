// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// The active callback reads only cached geometry and queues bounded work.
/// AX reads happen on the timer, never while macOS waits for an input verdict.
final class DockInputService {
    static let shared = DockInputService()
    private let stateLock = NSLock()
    private struct Snapshot {
        var tiles: [Tile] = []
        var titleBar: (rect: CGRect, item: SwitcherItem)?
        var quickQuit = false, scroll = false, titleScroll = false
        var trigger = "hover", modifier: CGEventFlags = .maskAlternate
        var top: CGFloat = 0
        var dockPID: pid_t?
        var windows: [MouseAppExceptionSupport.Window] = []
        var exclusionFrames: [CGRect] = []
        var sampledAt: TimeInterval = 0
    }
    private var snapshot = Snapshot()
    private lazy var inputTap = WindowInputTap(mask: [CGEventType.rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .leftMouseDown, .leftMouseUp, .scrollWheel].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }) { [weak self] type, event in
        self?.handle(type, event) != nil
    }
    private var timer: Timer?
    private struct Tile { let rect: CGRect; let pid: pid_t; let bundleURL: URL? }
    private var tiles: [Tile] = []
    private var titleBar: (rect: CGRect, item: SwitcherItem)?
    private var quickQuit = false, scroll = false, titleScroll = false
    private var trigger = "hover", modifier: CGEventFlags = .maskAlternate
    private var lastScroll: TimeInterval = 0
    private init() {}
    func start() {
        refresh()
        if timer == nil {
            let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.refresh() }
            timer.tolerance = 0.05; RunLoop.main.add(timer, forMode: .common); self.timer = timer
        }
        inputTap.start()
    }
    private func refresh() {
        defer {
            var value = Snapshot(tiles: tiles, titleBar: titleBar, quickQuit: quickQuit, scroll: scroll, titleScroll: titleScroll, trigger: trigger, modifier: modifier, top: NSScreen.screens.first?.frame.maxY ?? 0)
            if !tiles.isEmpty {
                value.dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
                value.windows = WindowServerSupport.onScreenWindows()
                value.exclusionFrames = NSApp.windows.filter { $0.isVisible && !$0.ignoresMouseEvents }.map(\.frame)
                    + DockPreviewService.shared.inputExclusionFrames
                if let panel = DockWidgetService.shared.presentationWindow, panel.isVisible { value.exclusionFrames.append(panel.frame) }
            }
            value.sampledAt = ProcessInfo.processInfo.systemUptime
            stateLock.withLock { snapshot = value }
        }
        quickQuit = DockOption.quickQuit.bool; scroll = DockOption.dockScroll.bool
        titleScroll = DockOption.titleBarScroll.bool; trigger = DockOption.trigger.string
        modifier = DockLockService.modifier(DockOption.triggerModifier.string)
        let point = NSEvent.mouseLocation
        // Only query Dock tiles near its edge; no idle AX walk while working.
        let nearEdge = NSScreen.screens.contains { screen in
            guard screen.frame.contains(point) else { return false }
            switch DockAccessibility.orientation {
            case .bottom: return point.y < screen.frame.minY + 150
            case .left: return point.x < screen.frame.minX + 150
            case .right: return point.x > screen.frame.maxX - 150
            }
        }
        tiles = nearEdge ? DockAccessibility.items().compactMap { item in
            guard let app = DockAccessibility.application(for: item), app.processIdentifier != getpid() else { return nil }
            return Tile(rect: item.frame, pid: app.processIdentifier, bundleURL: app.bundleURL)
        } : []
        titleBar = nil
        if titleScroll, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, nearTitleBar(point, pid: pid),
           let item = WindowEnumerator.listWindowsForDockPreview(for: pid).first(where: { $0.isOnScreen && !$0.isMinimized && !$0.isFullscreen }) {
            let frame = DockAccessibility.appKit(item.frame)
            let bar = CGRect(x: frame.minX, y: frame.maxY - 28, width: frame.width, height: 28)
            if bar.contains(point) { titleBar = (bar, item) }
        }
    }
    private func nearTitleBar(_ point: CGPoint, pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let entry = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }),
              let bounds = entry[kCGWindowBounds as String] as? [String: Any], let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
        let frame = DockAccessibility.appKit(rect)
        return CGRect(x: frame.minX, y: frame.maxY - 28, width: frame.width, height: 28).contains(point)
    }
    private var swallowedButton: CGEventType?
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard SessionActivity.shared.isActive else { return Unmanaged.passUnretained(event) }
        if let button = swallowedButton,
           (button == .rightMouseDown && type == .rightMouseUp) || (button == .otherMouseDown && type == .otherMouseUp) || (button == .leftMouseDown && type == .leftMouseUp) {
            swallowedButton = nil; return nil
        }
        let cached = stateLock.withLock { snapshot }
        let point = CGPoint(x: event.location.x, y: cached.top - event.location.y)
        let dockOwnsPoint = cached.dockPID.map { pid in
            !cached.exclusionFrames.contains { $0.contains(point) }
                && DockClickSupport.dockOwnsPoint(event.location, windows: cached.windows,
                    dockProcessID: pid, dockLayer: Int(CGWindowLevelForKey(.dockWindow)),
                    ownProcessID: getpid(), accessibilityHitProcessID: { nil })
        } ?? false
        if type == .scrollWheel {
            guard event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 else { return Unmanaged.passUnretained(event) }
            let delta = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            let horizontal = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
            guard abs(delta) + abs(horizontal) > 0 else { return Unmanaged.passUnretained(event) }
            let now = ProcessInfo.processInfo.systemUptime
            if dockOwnsPoint, cached.scroll, let tile = cached.tiles.first(where: { $0.rect.contains(point) }) {
                if now - lastScroll > 0.15 {
                    lastScroll = now
                    DispatchQueue.main.async { [weak self] in
                        guard self?.valid(tile, at: point, sampledAt: cached.sampledAt) == true, DockOption.dockScroll.bool, let app = NSRunningApplication(processIdentifier: tile.pid) else { return }
                        if DockOption.mediaWidget.bool, DockWidgetService.shared.isMediaApp(tile.pid), let volume = AppVolumeMixer.systemOutputVolumeSnapshot() {
                            _ = AppVolumeMixer.setSystemOutputVolume(volume + (delta > 0 ? 0.04 : -0.04))
                        } else if delta > 0 { _ = app.unhide(); app.activate(options: []) }
                        else if delta < 0 { _ = app.hide() }
                    }
                }
                return nil
            }
            if cached.titleScroll, let bar = cached.titleBar, bar.rect.contains(point) {
                if now - lastScroll > 0.3 {
                    lastScroll = now
                    let spaces = event.flags.contains(.maskAlternate) || abs(horizontal) > abs(delta)
                    DispatchQueue.main.async { [weak self] in
                        guard self?.inputTap.isRunning == true, DockOption.titleBarScroll.bool,
                              NSWorkspace.shared.frontmostApplication?.processIdentifier == bar.item.pid,
                              WindowActivator.focusedWindowID(for: bar.item.pid) == bar.item.windowID else { return }
                        if spaces, let shortcut = SpaceWindowBridge.spaceShortcut((horizontal != 0 ? horizontal : delta) > 0 ? .left : .right) { SpaceWindowBridge.pressSpaceShortcut(shortcut) }
                        else { _ = WindowEnhancementActions.perform(delta > 0 ? .maximize : .center, on: bar.item) }
                    }
                }
                return nil
            }
        }
        guard dockOwnsPoint, let tile = cached.tiles.first(where: { $0.rect.contains(point) }) else { return Unmanaged.passUnretained(event) }
        if cached.quickQuit, type == .rightMouseDown, event.flags.contains(.maskCommand) {
            let force = event.flags.contains(.maskAlternate)
            swallowedButton = type
            DispatchQueue.main.async { [weak self] in
                guard self?.valid(tile, at: point, sampledAt: cached.sampledAt) == true, DockOption.quickQuit.bool, let app = NSRunningApplication(processIdentifier: tile.pid) else { return }
                if force { _ = app.forceTerminate() } else { _ = app.terminate() }
            }
            return nil
        }
        if (cached.trigger == "middle" && type == .otherMouseDown && event.getIntegerValueField(.mouseEventButtonNumber) == 2)
            || (cached.trigger == "modifier" && type == .leftMouseDown && event.flags.contains(cached.modifier)) {
            swallowedButton = type
            DispatchQueue.main.async { [weak self] in
                guard self?.valid(tile, at: point, sampledAt: cached.sampledAt) == true, DockOption.trigger.string == cached.trigger, let app = NSRunningApplication(processIdentifier: tile.pid) else { return }
                DockPreviewService.shared.show(for: app, anchor: tile.rect)
            }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
    private func valid(_ tile: Tile, at point: CGPoint, sampledAt: TimeInterval) -> Bool {
        guard inputTap.isRunning, SessionActivity.shared.isActive, AppFeature.dockPreview.isAvailable,
              AXIsProcessTrusted(), ProcessInfo.processInfo.systemUptime - sampledAt < 0.5,
              UserDefaults.standard.bool(forKey: DefaultsKey.dockPreviewEnabled),
              let app = NSRunningApplication(processIdentifier: tile.pid) else { return false }
        guard !app.isTerminated, app.bundleURL == tile.bundleURL,
              !NSApp.windows.contains(where: { $0.isVisible && !$0.ignoresMouseEvents && $0.frame.contains(point) }),
              !DockPreviewService.shared.inputExclusionFrames.contains(where: { $0.contains(point) }),
              !DockWidgetService.shared.panelCovers(point),
              let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else { return false }
        let axPoint = DockAccessibility.quartz(point)
        guard DockClickSupport.dockOwnsPoint(axPoint, windows: WindowServerSupport.onScreenWindows(),
            dockProcessID: dockPID, dockLayer: Int(CGWindowLevelForKey(.dockWindow)), ownProcessID: getpid(),
            accessibilityHitProcessID: {
                let root = AXUIElementCreateSystemWide()
                _ = AXUIElementSetMessagingTimeout(root, 0.04)
                var hit: AXUIElement?, pid: pid_t = 0
                guard AXUIElementCopyElementAtPosition(root, Float(axPoint.x), Float(axPoint.y), &hit) == .success,
                      let hit, AXUIElementGetPid(hit, &pid) == .success else { return nil }
                return pid
            }), let item = DockAccessibility.items().first(where: { $0.frame.contains(point) }),
            let fresh = DockAccessibility.application(for: item) else { return false }
        return fresh.processIdentifier == tile.pid && fresh.bundleURL == tile.bundleURL
    }
    func stop() {
        timer?.invalidate(); timer = nil
        inputTap.stop()
        tiles = []; titleBar = nil
        stateLock.withLock { snapshot = Snapshot() }
    }
}
