// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// One pinned window: its overlay, its live picture and the reveal that
/// hands the user the real window. Decisions come from
/// `AlwaysOnTopSupport.reduce`; this object carries out the effects.
/// Main thread.
final class AlwaysOnTopPin {
    let windowID: CGWindowID
    let appPID: pid_t
    let ownerPID: pid_t
    let appName: String

    private weak var service: AlwaysOnTopService?
    private let axWindow: AXUIElement
    private let capture: AlwaysOnTopCapture
    private let overlay: AlwaysOnTopOverlay
    private(set) var phase: AlwaysOnTopPhase = .uncovered
    /// Window-server coordinates.
    private var frame: CGRect
    private var isMinimized = false
    private var missingChecks = 0
    private var axObserver: AXObserver?
    private var mirrorWanted = false

    private var hoverTimer: Timer?
    private var coolTimer: Timer?
    private var messageTimer: Timer?
    private var handOverTimer: Timer?
    private var handOverStarted: Date?
    private var handOverTimeout: TimeInterval = AlwaysOnTopSupport.handOverTimeout
    /// The app that was in front when a reveal began; a peek or a failed
    /// reveal gives focus back to it.
    private var sourcePID: pid_t?
    private var peekMonitor: Any?

    init(windowID: CGWindowID, appPID: pid_t, ownerPID: pid_t, appName: String,
         axWindow: AXUIElement, frame: CGRect, service: AlwaysOnTopService) {
        self.windowID = windowID
        self.appPID = appPID
        self.ownerPID = ownerPID
        self.appName = appName
        self.axWindow = axWindow
        self.frame = frame
        self.service = service
        capture = AlwaysOnTopCapture(windowID: windowID)
        overlay = AlwaysOnTopOverlay(displayLayer: capture.layer)
        overlay.onClick = { [weak self] in self?.handle(.click) }
        overlay.onPointerEntered = { [weak self] in
            guard let self else { return }
            self.handle(.pointerEntered(onViewedSpace: self.service?.windowList().contains(self.windowID) == true))
        }
        overlay.onPointerExited = { [weak self] in self?.handle(.pointerExited) }
        capture.onFirstFrame = { [weak self] in
            guard let self else { return }
            self.clearStallMessage()
            if self.mirrorWanted { self.overlay.show() }
        }
        capture.onStall = { [weak self] in
            guard let self, self.mirrorWanted else { return }
            // Nothing to draw, but the pin says why it shows nothing.
            self.showMessage(self.text.captureStalled, for: nil)
            self.overlay.show()
        }
        placeOverlay()
        applyBorder()
        observeWindow()
    }

    func applyBorder() {
        let color = AlwaysOnTopBorder.savedColorHex.map { hex -> NSColor in
            let rgb = MenuBarUsageBarSupport.rgb(for: hex, fallback: hex)
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        }
        overlay.setBorder(width: AlwaysOnTopBorder.saved.width, color: color)
    }

    private var text: AlwaysOnTopStrings { FeatureStrings.alwaysOnTop(L10n.shared.language) }

    // MARK: - Following the window

    /// Called with one window list per check, shared by every pin. Returns
    /// false once the window is gone.
    func update(with list: AlwaysOnTopWindowList) -> Bool {
        if phase.isHandingOver { return true }
        if let entry = list.entry(for: windowID) {
            follow(entry.bounds)
        } else if let bounds = AlwaysOnTopWindowList.bounds(of: windowID) {
            follow(bounds)
        } else {
            missingChecks += 1
            return missingChecks < AlwaysOnTopSupport.missingChecksBeforeClosed
        }
        missingChecks = 0
        let hidden = NSRunningApplication(processIdentifier: appPID)?.isHidden == true
        handle(.coverage(list.coverage(of: windowID, isParked: isMinimized || hidden)))
        return true
    }

    private func follow(_ bounds: CGRect) {
        guard bounds != frame, bounds.width > 0, bounds.height > 0 else { return }
        let resized = bounds.size != frame.size
        frame = bounds
        placeOverlay()
        if resized { capture.resize(pixelSize: pixelSize) }
    }

    private func placeOverlay() {
        guard let primary = NSScreen.screens.first else { return }
        overlay.setFrame(AlwaysOnTopSupport.appKitFrame(windowServerFrame: frame,
                                                       primaryScreenMaxY: primary.frame.maxY),
                         display: false)
    }

    private var pixelSize: (width: Int, height: Int) {
        let scale = NSScreen.screens.first { $0.frame.intersects(overlay.frame) }?.backingScaleFactor ?? 2
        return AlwaysOnTopSupport.streamPixelSize(for: frame, scale: scale)
    }

    private func observeWindow() {
        var observer: AXObserver?
        guard AXObserverCreate(ownerPID, alwaysOnTopAXCallback, &observer) == .success, let observer else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXMovedNotification, kAXResizedNotification, kAXWindowMiniaturizedNotification,
                     kAXWindowDeminiaturizedNotification, kAXUIElementDestroyedNotification] {
            AXObserverAddNotification(observer, axWindow, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        axObserver = observer
    }

    fileprivate func windowChanged(_ notification: String) {
        switch notification {
        case kAXUIElementDestroyedNotification:
            service?.unpin(self)
            return
        case kAXWindowMiniaturizedNotification:
            isMinimized = true
        case kAXWindowDeminiaturizedNotification:
            isMinimized = false
        default:
            break
        }
        // Geometry follows at once; the regular check would lag a tenth of a
        // second behind a drag.
        service?.checkPins()
    }

    // MARK: - Decisions

    func handle(_ event: AlwaysOnTopEvent) {
        let (next, effects) = AlwaysOnTopSupport.reduce(phase, event, reveal: .saved)
        phase = next
        effects.forEach(perform)
    }

    private func perform(_ effect: AlwaysOnTopEffect) {
        switch effect {
        case .showMirror:
            mirrorWanted = true
            if capture.hasFrame { overlay.show() }
        case .hideMirror(let fade):
            mirrorWanted = false
            overlay.hide(fade: fade)
        case .startCapture:
            coolTimer?.invalidate()
            capture.start(pixelSize: pixelSize)
        case .coolCapture:
            coolTimer?.invalidate()
            coolTimer = Timer.scheduledTimer(withTimeInterval: AlwaysOnTopSupport.coolDown, repeats: false) { [weak self] _ in
                guard let self, !self.mirrorWanted else { return }
                self.capture.stop()
            }
        case .stopCapture:
            coolTimer?.invalidate()
            capture.stop()
            clearStallMessage()
        case .startHoverDelay:
            hoverTimer?.invalidate()
            hoverTimer = Timer.scheduledTimer(withTimeInterval: AlwaysOnTopSupport.hoverDelay, repeats: false) { [weak self] _ in
                self?.handle(.hoverDelayElapsed)
            }
        case .cancelHoverDelay:
            hoverTimer?.invalidate()
        case .beginHandOver:
            beginHandOver()
        case .cancelHandOver:
            endHandOver()
            if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
               front == appPID || front == ownerPID {
                giveFocusBack()
            }
        case .showNotForward:
            showMessage(String(format: text.notForward, appName), for: 3)
        case .watchPeek:
            watchPeek()
        case .stopWatchingPeek:
            stopWatchingPeek()
        case .returnFocus:
            giveFocusBack()
        }
    }

    // MARK: - Reveal

    private func beginHandOver() {
        let list = service?.windowList()
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        sourcePID = front == appPID || front == ownerPID ? nil : front
        handOverTimeout = list?.contains(windowID) == false
            ? AlwaysOnTopSupport.spaceHandOverTimeout
            : AlwaysOnTopSupport.handOverTimeout
        handOverStarted = Date()
        // The same activation the switcher uses: it fronts this exact window,
        // and travels to its Space first when the window lives elsewhere.
        WindowActivator.activate(pid: appPID, windowID: windowID, appName: appName,
                                 retry: true, handoffSourcePID: sourcePID)
        handOverTimer?.invalidate()
        handOverTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            self?.checkHandOver()
        }
    }

    private func checkHandOver() {
        guard let service, let started = handOverStarted else { return }
        let list = service.windowList()
        let confirmed = AlwaysOnTopSupport.handOverConfirmed(
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            appPID: appPID, ownerPID: ownerPID,
            focusedWindowID: WindowActivator.focusedWindowID(for: ownerPID),
            windowID: windowID,
            coverage: list.coverage(of: windowID, isParked: false))
        if confirmed {
            endHandOver()
            if let entry = list.entry(for: windowID) { follow(entry.bounds) }
            handle(.handOverConfirmed)
        } else if Date().timeIntervalSince(started) > handOverTimeout {
            handle(.handOverTimedOut)
        }
    }

    private func endHandOver() {
        handOverTimer?.invalidate()
        handOverTimer = nil
        handOverStarted = nil
    }

    private func giveFocusBack() {
        guard let pid = sourcePID,
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
        WindowActivator.activate(pid: pid, windowID: nil, appName: app.localizedName ?? "", retry: false)
    }

    private func watchPeek() {
        stopWatchingPeek()
        // Seeing a click or a keypress in another app needs Accessibility,
        // which pinning already requires.
        peekMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            self?.peekEvent(event)
        }
    }

    private func stopWatchingPeek() {
        if let peekMonitor { NSEvent.removeMonitor(peekMonitor) }
        peekMonitor = nil
    }

    private func peekEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown:
            handle(.peekInput)
        default:
            // A few points of slack, so leaving along the window's own edge
            // does not end the peek early.
            if !overlay.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) {
                handle(.peekPointerLeft)
            }
        }
    }

    // MARK: - Messages

    private var showsStallMessage = false

    private func showMessage(_ message: String, for duration: TimeInterval?) {
        messageTimer?.invalidate()
        overlay.setMessage(message)
        showsStallMessage = duration == nil
        guard let duration else { return }
        messageTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.overlay.setMessage(nil)
        }
    }

    private func clearStallMessage() {
        guard showsStallMessage else { return }
        showsStallMessage = false
        overlay.setMessage(nil)
    }

    // MARK: - Ending

    func tearDown() {
        hoverTimer?.invalidate()
        coolTimer?.invalidate()
        messageTimer?.invalidate()
        endHandOver()
        stopWatchingPeek()
        capture.stop()
        if let axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes)
        }
        axObserver = nil
        overlay.orderOut(nil)
    }
}

private extension AlwaysOnTopPhase {
    var isHandingOver: Bool {
        if case .handingOver = self { return true }
        return false
    }
}

private func alwaysOnTopAXCallback(_ observer: AXObserver, _ element: AXUIElement,
                                   _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    Unmanaged<AlwaysOnTopPin>.fromOpaque(refcon).takeUnretainedValue().windowChanged(notification as String)
}
