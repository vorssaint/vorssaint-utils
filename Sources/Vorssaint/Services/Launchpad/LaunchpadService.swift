// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// A full-screen, always-key panel — borderless and non-activating like
/// `CommandBarService`'s own panel, but sized to the whole screen instead
/// of a centered content-fit rect. There is no "outside" to click on a
/// full-screen panel, so unlike Command Bar's panel this needs no
/// click-outside monitor: `LaunchpadView`'s own background tap gesture
/// handles dismissal, and only Escape needs a key monitor here.
private final class LaunchpadPanel: OverlayPanel {
    override var canBecomeKey: Bool { true }
}

/// An arrow key with the command modifier's state, or Return — read off a
/// raw `NSEvent` here rather than through SwiftUI's `.onKeyPress`, since a
/// focused `TextField` (the search field is always focused) claims arrow
/// keys for its own cursor before SwiftUI's key-press modifiers would ever
/// see them. `CommandBarService` handles its own arrow keys the same way.
enum LaunchpadKeyAction {
    case arrow(LaunchpadArrowDirection, commandHeld: Bool)
    case launch
}

/// Owns Launchpad Classic's global hotkey and its full-screen panel.
final class LaunchpadService {
    static let shared = LaunchpadService()

    /// A trackpad swipe that crossed the paging threshold; `LaunchpadView`
    /// applies it to its own page index.
    let pageStep = PassthroughSubject<Int, Never>()
    /// Sent every time the panel is shown. The view is created once and
    /// reused (`ensurePanel()` caches it), so SwiftUI's own `onAppear` only
    /// fires on the very first open — this is what refreshes the layout and
    /// search focus on every open after that.
    let didShow = PassthroughSubject<Void, Never>()
    let keyAction = PassthroughSubject<LaunchpadKeyAction, Never>()

    private let hotkey = QuickToolHotkey(id: 61)
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var swipeCumulativeX: CGFloat = 0

    /// The four-finger pinch that opens the panel. Runs independently of the
    /// hotkey's own enabled state and needs no Accessibility permission: it
    /// only reads raw contacts, unlike `MiddleClickService`'s tap, which also
    /// synthesizes clicks through an event tap.
    private let pinchQueue = DispatchQueue(label: "com.vorssaint.utils.launchpad.pinch", qos: .userInteractive)
    private var pinchDeviceList: CFArray?
    private let pinchStateLock = NSLock()
    private var pinchStartSpread: Float?
    private var pinchStartUptime: TimeInterval?
    private var pinchMinSpread: Float?

    private init() {
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    func syncWithPreferences() {
        let available = AppFeature.launchpad.isAvailable
        let enabled = available && UserDefaults.standard.bool(forKey: DefaultsKey.launchpadShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.launchpadShortcut, fallback: .launchpadDefault)
        _ = hotkey.sync(enabled: enabled, shortcut: shortcut, storageKey: DefaultsKey.launchpadShortcut)
        let pinchEnabled = available && UserDefaults.standard.bool(forKey: DefaultsKey.launchpadPinchEnabled)
        if pinchEnabled { startPinchTracking() } else { stopPinchTracking() }
        if !available { hide() }
    }

    func suspend() {
        hotkey.unregister()
        stopPinchTracking()
        hide()
    }

    // MARK: - Four-finger pinch to open

    private func startPinchTracking() {
        pinchQueue.async { [weak self] in
            guard let self, self.pinchDeviceList == nil, Multitouch.available,
                  let list = Multitouch.deviceList()
            else { return }
            self.pinchDeviceList = list
            for index in 0..<CFArrayGetCount(list) {
                guard let device = CFArrayGetValueAtIndex(list, index) else { continue }
                Multitouch.register(UnsafeMutableRawPointer(mutating: device), launchpadPinchContactCallback)
                Multitouch.start(UnsafeMutableRawPointer(mutating: device))
            }
        }
    }

    private func stopPinchTracking() {
        pinchQueue.async { [weak self] in
            guard let self, let list = self.pinchDeviceList else { return }
            for index in 0..<CFArrayGetCount(list) {
                guard let device = CFArrayGetValueAtIndex(list, index) else { continue }
                Multitouch.stop(UnsafeMutableRawPointer(mutating: device))
                Multitouch.register(UnsafeMutableRawPointer(mutating: device), nil)
            }
            self.pinchDeviceList = nil
        }
        pinchStateLock.withLock {
            pinchStartSpread = nil
            pinchStartUptime = nil
            pinchMinSpread = nil
        }
    }

    /// Runs on the multitouch callback thread. Tracks the shrinking spread
    /// while four or more fingers rest on the pad and judges a close once
    /// they lift, the same "evaluate on release" shape `MiddleClickService`
    /// already uses for its own tap gesture.
    fileprivate func pinchContactFrame(fingerCount count: Int, touches: UnsafeMutableRawPointer?) {
        let now = ProcessInfo.processInfo.systemUptime
        guard count >= 4, let geometry = Multitouch.touchGeometry(touches: touches, count: count) else {
            let closed: Bool = pinchStateLock.withLock {
                defer { pinchStartSpread = nil; pinchStartUptime = nil; pinchMinSpread = nil }
                guard let startSpread = pinchStartSpread, let startUptime = pinchStartUptime,
                      let minSpread = pinchMinSpread else { return false }
                return LaunchpadPinchSupport.isPinchClose(startSpread: startSpread, endSpread: minSpread,
                                                          duration: now - startUptime)
            }
            if closed { DispatchQueue.main.async { [weak self] in self?.toggle() } }
            return
        }
        pinchStateLock.withLock {
            if pinchStartSpread == nil {
                pinchStartSpread = geometry.spread
                pinchStartUptime = now
                pinchMinSpread = geometry.spread
            } else {
                pinchMinSpread = min(pinchMinSpread ?? geometry.spread, geometry.spread)
            }
        }
    }

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        LaunchpadAppCatalog.shared.refresh()
        NSApp.activate(ignoringOtherApps: true)
        let panel = ensurePanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        installMonitors()
        didShow.send()
    }

    func hide() {
        removeMonitors()
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = LaunchpadPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.title = "Launchpad Classic"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        // .modalPanel sits above every ordinary window (Settings included)
        // without reaching the Dock's or menu bar's own level, so both stay
        // visible on top of the grid.
        panel.level = .modalPanel
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        // .fullScreenUI is the material AppKit documents for exactly this:
        // a blurred backdrop behind a full-screen app-picking surface. It
        // needs .behindWindow blending, which is why the panel stays
        // non-opaque with a clear background instead of drawing its own fill.
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]

        let host = NSHostingView(rootView: LaunchpadView(onDismiss: { [weak self] in self?.hide() }))
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        blur.addSubview(host)

        panel.contentView = blur
        self.panel = panel
        return panel
    }

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            let commandHeld = event.modifierFlags.contains(.command)
            switch Int(event.keyCode) {
            case kVK_Escape:
                self.hide()
                return nil
            case kVK_LeftArrow:
                self.keyAction.send(.arrow(.left, commandHeld: commandHeld))
                return nil
            case kVK_RightArrow:
                self.keyAction.send(.arrow(.right, commandHeld: commandHeld))
                return nil
            case kVK_UpArrow:
                self.keyAction.send(.arrow(.up, commandHeld: commandHeld))
                return nil
            case kVK_DownArrow:
                self.keyAction.send(.arrow(.down, commandHeld: commandHeld))
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                self.keyAction.send(.launch)
                return nil
            default:
                return event
            }
        }
        swipeCumulativeX = 0
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            if event.phase.contains(.began) { self.swipeCumulativeX = 0 }
            self.swipeCumulativeX += event.scrollingDeltaX
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                let step = LaunchpadPagingSupport.pageStep(cumulativeX: self.swipeCumulativeX)
                self.swipeCumulativeX = 0
                if step != 0 { self.pageStep.send(step) }
            }
            return event
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        keyMonitor = nil
        scrollMonitor = nil
    }
}

private func launchpadPinchContactCallback(_ device: UnsafeMutableRawPointer?,
                                           _ touches: UnsafeMutableRawPointer?,
                                           _ count: Int32,
                                           _ timestamp: Double,
                                           _ frame: Int32) -> Int32 {
    LaunchpadService.shared.pinchContactFrame(fingerCount: Int(count), touches: touches)
    return 0
}
