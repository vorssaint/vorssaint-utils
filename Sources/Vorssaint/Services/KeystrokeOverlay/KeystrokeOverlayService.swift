// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CoreGraphics
import SwiftUI

/// KeyCastr-style keystroke visualizer: listens passively to physical key events
/// and modifier flags via a `.listenOnly` event tap and displays a draggable
/// floating overlay on screen ("Svelte" box or "Keycaps" pills).
final class KeystrokeOverlayService: ObservableObject {
    static let shared = KeystrokeOverlayService()

    @Published private(set) var isRunning = false
    @Published private(set) var style: KeystrokeOverlayStyle = .svelte
    @Published private(set) var items: [KeystrokeOverlayItem] = []
    @Published private(set) var svelteText: String = ""
    @Published private(set) var activeModifiers: GlobalShortcutModifiers = []
    @Published private(set) var size: KeystrokeOverlaySize = .medium
    @Published private(set) var hasCustomPosition = false

    private let eventLock = NSLock()
    private let lifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingStartAfterStop = false
    private var lifecycleGeneration: UInt = 0

    private var config = KeystrokeOverlayConfig(
        enabled: false,
        style: .svelte,
        mode: .allKeys,
        position: .bottomCenter,
        customOrigin: nil,
        size: .medium,
        durationSeconds: KeystrokeOverlayConfig.defaultDurationSeconds
    )
    private var buffer = KeystrokeOverlayBuffer()
    private var svelteBuffer = KeystrokeOverlaySvelteBuffer()
    private var physicalModifiers: GlobalShortcutModifiers = []
    private var superKeyHeld = false
    private var superModifiers: GlobalShortcutModifiers = []
    private var recentKeyModifiers: GlobalShortcutModifiers = []
    private var lastActivityTimestamp: TimeInterval = 0
    private var isDraggingPanel = false
    private var panel: KeystrokeOverlayPanel?
    private var pruneTimer: Timer?
    private var hideGeneration = 0

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let customOrigin = Self.storedCustomOrigin(in: defaults)
        let nextConfig = KeystrokeOverlayConfig(
            enabled: AppFeature.keystrokeOverlay.isAvailable
                && defaults.bool(forKey: DefaultsKey.keystrokeOverlayEnabled),
            style: KeystrokeOverlayStyle.sanitized(
                defaults.string(forKey: DefaultsKey.keystrokeOverlayStyle)
            ),
            mode: KeystrokeOverlayMode.sanitized(
                defaults.string(forKey: DefaultsKey.keystrokeOverlayMode)
            ),
            position: KeystrokeOverlayPosition.sanitized(
                defaults.string(forKey: DefaultsKey.keystrokeOverlayPosition)
            ),
            customOrigin: customOrigin,
            size: KeystrokeOverlaySize.sanitized(
                defaults.string(forKey: DefaultsKey.keystrokeOverlaySize)
            ),
            durationSeconds: KeystrokeOverlayConfig.sanitizedDuration(
                defaults.object(forKey: DefaultsKey.keystrokeOverlayDuration) as? Double
                    ?? KeystrokeOverlayConfig.defaultDurationSeconds
            ),
            showInCaptures: KeystrokeOverlayConfig.showsInCaptures(in: defaults)
        )
        eventLock.withLock {
            config = nextConfig
        }
        let applyUI = { [weak self] in
            guard let self else { return }
            self.style = nextConfig.style
            self.size = nextConfig.size
            self.hasCustomPosition = customOrigin != nil
            self.panel?.sharingType = nextConfig.showInCaptures ? .readOnly : .none
            if self.panel?.isVisible == true {
                self.updatePanelFrame()
            }
        }
        if Thread.isMainThread {
            applyUI()
        } else {
            DispatchQueue.main.async(execute: applyUI)
        }

        if SessionActivitySupport.tapShouldRun(featureWanted: nextConfig.enabled,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            GlobalShortcut.startObservingKeyboardLayout()
            start()
        } else {
            stop()
        }
    }

    func suspend() {
        stop()
    }

    @MainActor
    var captureVisibleWindowIDs: Set<CGWindowID> {
        guard let panel, panel.isVisible, panel.windowNumber > 0,
              eventLock.withLock({ config.showInCaptures }) else { return [] }
        return [CGWindowID(panel.windowNumber)]
    }

    @MainActor
    var captureExcludedWindowIDs: Set<CGWindowID> {
        guard let panel, panel.windowNumber > 0,
              !eventLock.withLock({ config.showInCaptures }) else { return [] }
        return [CGWindowID(panel.windowNumber)]
    }

    /// Ensures the overlay panel exists on screen (invisible and click-through
    /// while idle) before ScreenCaptureKit builds its `SCContentFilter`, so
    /// Vorssaint's own Screen Recorder includes it in `exceptingWindows` when
    /// "Show in screen recordings and screenshots" is enabled.
    @MainActor
    func prepareForScreenRecording() {
        let currentConfig = eventLock.withLock { config }
        guard currentConfig.enabled, currentConfig.showInCaptures else { return }
        let panel = ensurePanel()
        panel.sharingType = .readOnly
        if !panel.isVisible {
            updatePanelFrame()
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
            panel.orderFrontRegardless()
        }
    }

    func resetCustomPosition() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: DefaultsKey.keystrokeOverlayCustomX)
        defaults.removeObject(forKey: DefaultsKey.keystrokeOverlayCustomY)
        syncWithPreferences()
    }

    /// Called by `SuperKeyService` when the remapped Super key is pressed or released.
    func noteSuperKeyState(isHeld: Bool, modifiers: GlobalShortcutModifiers) {
        let work = { [weak self] in
            guard let self else { return }
            self.superKeyHeld = isHeld
            self.superModifiers = isHeld ? modifiers : []
            let currentConfig = self.eventLock.withLock { self.config }
            guard currentConfig.enabled, !IsSecureEventInputEnabled() else {
                if !isHeld {
                    self.refreshActiveModifiers()
                }
                return
            }
            self.refreshActiveModifiers()
            if isHeld {
                let now = ProcessInfo.processInfo.systemUptime
                self.lastActivityTimestamp = now
                self.svelteBuffer.setTransientModifier("Super")
                self.svelteText = self.svelteBuffer.displayText
                self.items = self.buffer.record(caps: ["Super"], now: now, duration: currentConfig.durationSeconds)
                self.presentOverlayPanel()
            } else {
                self.svelteBuffer.setTransientModifier(nil)
                self.schedulePruneTimer()
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// Shows a sample keystroke combination (including Space, Shift and Super)
    /// so the user can preview the active theme and drag the overlay to any
    /// spot on screen.
    func showPreview() {
        guard AppFeature.keystrokeOverlay.isAvailable else { return }
        let defaults = UserDefaults.standard
        let previewStyle = KeystrokeOverlayStyle.sanitized(
            defaults.string(forKey: DefaultsKey.keystrokeOverlayStyle)
        )
        let previewSize = KeystrokeOverlaySize.sanitized(
            defaults.string(forKey: DefaultsKey.keystrokeOverlaySize)
        )
        let previewPosition = KeystrokeOverlayPosition.sanitized(
            defaults.string(forKey: DefaultsKey.keystrokeOverlayPosition)
        )
        let customOrigin = Self.storedCustomOrigin(in: defaults)
        let previewDuration = KeystrokeOverlayConfig.sanitizedDuration(
            defaults.object(forKey: DefaultsKey.keystrokeOverlayDuration) as? Double
                ?? KeystrokeOverlayConfig.defaultDurationSeconds
        )
        eventLock.withLock {
            config.style = previewStyle
            config.size = previewSize
            config.position = previewPosition
            config.customOrigin = customOrigin
            config.durationSeconds = previewDuration
        }
        style = previewStyle
        size = previewSize
        hasCustomPosition = customOrigin != nil

        let now = ProcessInfo.processInfo.systemUptime
        lastActivityTimestamp = now
        recentKeyModifiers = [.shift, .control, .option, .command]
        refreshActiveModifiers()

        buffer.reset()
        _ = buffer.record(caps: ["␣"], now: now, duration: previewDuration)
        _ = buffer.record(caps: ["⇧"], now: now + 0.01, duration: previewDuration)
        _ = buffer.record(caps: ["Super"], now: now + 0.02, duration: previewDuration)
        items = buffer.record(caps: ["⌘", "K"], now: now + 0.03, duration: previewDuration)

        svelteBuffer.reset()
        svelteText = svelteBuffer.record(
            token: "␣ ⇧ Super",
            isStandalone: true,
            now: now,
            duration: previewDuration
        )

        presentOverlayPanel()
    }

    private static func storedCustomOrigin(in defaults: UserDefaults) -> CGPoint? {
        guard defaults.object(forKey: DefaultsKey.keystrokeOverlayCustomX) != nil,
              defaults.object(forKey: DefaultsKey.keystrokeOverlayCustomY) != nil else {
            return nil
        }
        let x = defaults.double(forKey: DefaultsKey.keystrokeOverlayCustomX)
        let y = defaults.double(forKey: DefaultsKey.keystrokeOverlayCustomY)
        guard x.isFinite, y.isFinite else { return nil }
        return CGPoint(x: x, y: y)
    }

    private func saveCustomOrigin(_ origin: CGPoint) {
        guard origin.x.isFinite, origin.y.isFinite else { return }
        let defaults = UserDefaults.standard
        defaults.set(Double(origin.x.rounded()), forKey: DefaultsKey.keystrokeOverlayCustomX)
        defaults.set(Double(origin.y.rounded()), forKey: DefaultsKey.keystrokeOverlayCustomY)
        eventLock.withLock {
            config.customOrigin = CGPoint(x: origin.x.rounded(), y: origin.y.rounded())
        }
        hasCustomPosition = true
    }

    // MARK: - Event tap lifecycle

    private func start() {
        let startState = lifecycleLock.withLock { () -> (thread: Thread?, publishRunning: Bool, generation: UInt) in
            if tapThread != nil {
                if shouldStopTapThread {
                    pendingStartAfterStop = true
                    return (nil, false, lifecycleGeneration)
                }
                return (nil, true, lifecycleGeneration)
            }
            shouldStopTapThread = false
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            let generation = lifecycleGeneration
            let thread = Thread { [weak self] in
                self?.runEventTap(generation: generation)
            }
            thread.name = "Vorssaint Keystroke Overlay"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return (thread, false, generation)
        }

        if let thread = startState.thread {
            thread.start()
        } else if startState.publishRunning {
            publishRunning(true, generation: startState.generation)
        }
    }

    private func stop() {
        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool, generation: UInt) in
            shouldStopTapThread = true
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            return (tapRunLoop, tap, tapThread != nil, lifecycleGeneration)
        }

        if let tap = snapshot.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            lifecycleLock.withLock {
                shouldStopTapThread = false
                tapThread = nil
            }
        }
        publishRunning(false, generation: snapshot.generation)
        if Thread.isMainThread {
            clearOverlayImmediately()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.clearOverlayImmediately()
            }
        }
    }

    private func runEventTap(generation: UInt) {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock {
                tapRunLoop = runLoop
            }

            let shouldStopBeforeCreatingTap = lifecycleLock.withLock {
                shouldStopTapThread
            }
            guard !shouldStopBeforeCreatingTap else {
                if clearEventTapThread() {
                    start()
                } else {
                    publishRunning(false, generation: generation)
                }
                return
            }

            let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
                | (CGEventMask(1) << CGEventType.keyUp.rawValue)
                | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<KeystrokeOverlayService>.fromOpaque(userInfo).takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearEventTapThread()
                publishRunning(false, generation: generation)
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock {
                self.tap = tap
                runLoopSource = source
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            let shouldStop = lifecycleLock.withLock {
                shouldStopTapThread
            }
            if shouldStop {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                publishRunning(true, generation: generation)
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            if clearEventTapThread() {
                start()
            } else {
                publishRunning(false, generation: generation)
            }
        }
    }

    private func clearEventTapThread() -> Bool {
        lifecycleLock.withLock {
            let shouldRestart = pendingStartAfterStop
            tap = nil
            runLoopSource = nil
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingStartAfterStop = false
            return shouldRestart
        }
    }

    private func publishRunning(_ running: Bool, generation: UInt) {
        let update = { [weak self] in
            guard let self else { return }
            let isCurrent = self.lifecycleLock.withLock {
                generation == self.lifecycleGeneration
            }
            guard isCurrent else { return }
            self.isRunning = running
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let currentTap = lifecycleLock.withLock { shouldStopTapThread ? nil : tap }
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let currentTap {
                CGEvent.tapEnable(tap: currentTap, enable: true)
            } else if currentTap != nil {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            return Unmanaged.passUnretained(event)
        }

        guard !OwnKeyEvent.isPosted(event) else {
            return Unmanaged.passUnretained(event)
        }

        let currentConfig = eventLock.withLock { config }
        guard currentConfig.enabled else {
            return Unmanaged.passUnretained(event)
        }

        let modifiers = GlobalShortcutModifiers(cgFlags: event.flags)
        let secure = IsSecureEventInputEnabled()

        if type == .flagsChanged {
            DispatchQueue.main.async { [weak self] in
                self?.handleFlagsChanged(modifiers: modifiers, secureInputActive: secure)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyUp {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if Int(keyCode) == SuperKeySupport.triggerKeyCode {
                DispatchQueue.main.async { [weak self] in
                    self?.noteSuperKeyState(isHeld: false, modifiers: [])
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let superActive = SuperKeyService.shared.isHeld

        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: chars.count,
                                       actualStringLength: &length,
                                       unicodeString: &chars)
        let typed = length > 0 ? String(utf16CodeUnits: chars, count: length) : nil

        let caps = KeystrokeOverlaySupport.keyCaps(
            keyCode: keyCode,
            modifiers: modifiers,
            mode: currentConfig.mode,
            isAutoRepeat: isRepeat,
            secureInputActive: secure,
            typedCharacter: typed,
            superKeyHeld: superActive
        )
        let svelteToken = KeystrokeOverlaySupport.svelteToken(
            keyCode: keyCode,
            modifiers: modifiers,
            mode: currentConfig.mode,
            isAutoRepeat: isRepeat,
            secureInputActive: secure,
            typedCharacter: typed,
            superKeyHeld: superActive
        )
        guard caps != nil || svelteToken != nil else {
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async { [weak self] in
            self?.presentKeystroke(
                caps: caps,
                svelteToken: svelteToken,
                modifiers: modifiers,
                superActive: superActive
            )
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Overlay presentation

    private func handleFlagsChanged(modifiers: GlobalShortcutModifiers, secureInputActive: Bool) {
        physicalModifiers = modifiers
        let currentConfig = eventLock.withLock { config }
        let combined = physicalModifiers.union(superKeyHeld ? superModifiers : [])
        guard !secureInputActive else {
            refreshActiveModifiers()
            return
        }
        if !combined.isEmpty {
            recentKeyModifiers = combined
            refreshActiveModifiers()
            let shouldPresent = currentConfig.mode == .allKeys
                || combined.hasPrimaryModifier
                || KeystrokeOverlaySupport.isSuperChord(modifiers: combined, superKeyHeld: superKeyHeld)
            guard shouldPresent else { return }

            let now = ProcessInfo.processInfo.systemUptime
            lastActivityTimestamp = now
            if let label = KeystrokeOverlaySupport.modifierPreviewLabel(
                modifiers: combined,
                superKeyHeld: superKeyHeld
            ) {
                svelteBuffer.setTransientModifier(label)
                svelteText = svelteBuffer.displayText
                let modCaps = KeystrokeOverlaySupport.isSuperChord(modifiers: combined, superKeyHeld: superKeyHeld)
                    ? ["Super"]
                    : KeystrokeOverlaySupport.svelteModifierCells.compactMap {
                        combined.contains($0.modifier) ? $0.symbol : nil
                    }
                if !modCaps.isEmpty {
                    items = buffer.record(caps: modCaps, now: now, duration: currentConfig.durationSeconds)
                }
            }
            presentOverlayPanel()
        } else {
            recentKeyModifiers = []
            refreshActiveModifiers()
            svelteBuffer.setTransientModifier(nil)
            schedulePruneTimer()
        }
    }

    private func presentKeystroke(caps: [String]?,
                                  svelteToken: (text: String, isStandalone: Bool)?,
                                  modifiers: GlobalShortcutModifiers,
                                  superActive: Bool) {
        let currentConfig = eventLock.withLock { config }
        style = currentConfig.style
        size = currentConfig.size
        let now = ProcessInfo.processInfo.systemUptime
        lastActivityTimestamp = now

        let effectiveModifiers = modifiers.union(superActive ? SuperKeyService.shared.modifiers : [])
        recentKeyModifiers = effectiveModifiers
        refreshActiveModifiers()

        if let caps {
            items = buffer.record(caps: caps, now: now, duration: currentConfig.durationSeconds)
        }
        if let svelteToken {
            svelteText = svelteBuffer.record(
                token: svelteToken.text,
                isStandalone: svelteToken.isStandalone,
                now: now,
                duration: currentConfig.durationSeconds
            )
        }
        presentOverlayPanel()
    }

    private func refreshActiveModifiers() {
        activeModifiers = physicalModifiers
            .union(superKeyHeld ? superModifiers : [])
            .union(recentKeyModifiers)
    }

    private func presentOverlayPanel() {
        let currentConfig = eventLock.withLock { config }
        style = currentConfig.style
        size = currentConfig.size
        let hasContent = currentConfig.style == .svelte
            ? (!svelteText.isEmpty || !activeModifiers.isEmpty)
            : !items.isEmpty
        guard hasContent else { return }

        let panel = ensurePanel()
        panel.sharingType = currentConfig.showInCaptures ? .readOnly : .none
        panel.ignoresMouseEvents = false
        if !isDraggingPanel {
            updatePanelFrame()
        }
        hideGeneration &+= 1
        if !panel.isVisible || panel.alphaValue < 1 {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        schedulePruneTimer()
    }

    private func schedulePruneTimer() {
        pruneTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.tickPrune()
        }
        timer.tolerance = 0.05
        pruneTimer = timer
    }

    private func tickPrune() {
        guard !isDraggingPanel else { return }
        let held = physicalModifiers.union(superKeyHeld ? superModifiers : [])
        if !held.isEmpty {
            lastActivityTimestamp = ProcessInfo.processInfo.systemUptime
            return
        }

        let currentConfig = eventLock.withLock { config }
        let now = ProcessInfo.processInfo.systemUptime
        let previousItems = buffer.items
        let previousSvelte = svelteBuffer.displayText

        buffer.prune(now: now, duration: currentConfig.durationSeconds)
        svelteBuffer.prune(now: now, duration: currentConfig.durationSeconds)

        if now - lastActivityTimestamp >= currentConfig.durationSeconds {
            recentKeyModifiers = []
            svelteBuffer.setTransientModifier(nil)
            refreshActiveModifiers()
        }

        if buffer.items != previousItems {
            items = buffer.items
        }
        if svelteBuffer.displayText != previousSvelte {
            svelteText = svelteBuffer.displayText
        }

        let isEmptyNow = currentConfig.style == .svelte
            ? (svelteBuffer.isEmpty && activeModifiers.isEmpty)
            : items.isEmpty

        if isEmptyNow {
            pruneTimer?.invalidate()
            pruneTimer = nil
            fadeOutPanel()
        } else if buffer.items != previousItems && currentConfig.style == .keycaps {
            updatePanelFrame()
        }
    }

    private func fadeOutPanel() {
        guard let panel, panel.isVisible else { return }
        hideGeneration &+= 1
        let currentGeneration = hideGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.hideGeneration == currentGeneration else { return }
            panel.orderOut(nil)
        })
    }

    private func clearOverlayImmediately() {
        pruneTimer?.invalidate()
        pruneTimer = nil
        buffer.reset()
        svelteBuffer.reset()
        items = []
        svelteText = ""
        physicalModifiers = []
        superKeyHeld = false
        superModifiers = []
        recentKeyModifiers = []
        activeModifiers = []
        isDraggingPanel = false
        hideGeneration &+= 1
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> KeystrokeOverlayPanel {
        if let panel { return panel }
        let panel = KeystrokeOverlayPanel(contentRect: .zero,
                                          styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered,
                                          defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = eventLock.withLock { config.showInCaptures } ? .readOnly : .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.onDragStateChanged = { [weak self] dragging in
            guard let self else { return }
            self.isDraggingPanel = dragging
            if dragging {
                self.hideGeneration &+= 1
                self.panel?.alphaValue = 1
            } else {
                self.lastActivityTimestamp = ProcessInfo.processInfo.systemUptime
                self.schedulePruneTimer()
            }
        }
        panel.onDragEnded = { [weak self] origin in
            self?.saveCustomOrigin(origin)
        }
        let host = NSHostingController(rootView: KeystrokeOverlayView(service: self))
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    private func updatePanelFrame() {
        guard let panel, let view = panel.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        let currentConfig = eventLock.withLock { config }
        let fittingSize = currentConfig.style == .svelte
            ? CGSize(width: currentConfig.size.svelteBoxSize.width + 16,
                     height: currentConfig.size.svelteBoxSize.height + 16)
            : view.fittingSize
        let frame = KeystrokeOverlaySupport.panelFrame(
            size: fittingSize,
            visibleFrame: NSScreen.pointerVisibleFrame,
            position: currentConfig.position,
            customOrigin: currentConfig.customOrigin
        )
        panel.setFrame(frame, display: true)
    }
}

/// Non-activating overlay panel that supports click-and-drag repositioning
/// anywhere on screen without stealing focus from the active application.
final class KeystrokeOverlayPanel: OverlayPanel {
    var onDragStateChanged: ((Bool) -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?

    private var dragStartMouseLocation: CGPoint?
    private var dragStartOrigin: CGPoint?
    private var didMoveDuringDrag = false

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragStartMouseLocation = NSEvent.mouseLocation
            dragStartOrigin = frame.origin
            didMoveDuringDrag = false
            NSCursor.closedHand.push()
            onDragStateChanged?(true)
        case .leftMouseDragged:
            guard let startMouse = dragStartMouseLocation,
                  let startOrigin = dragStartOrigin else {
                super.sendEvent(event)
                return
            }
            let currentMouse = NSEvent.mouseLocation
            let deltaX = currentMouse.x - startMouse.x
            let deltaY = currentMouse.y - startMouse.y
            if abs(deltaX) > 1 || abs(deltaY) > 1 {
                didMoveDuringDrag = true
            }
            let targetOrigin = CGPoint(x: startOrigin.x + deltaX, y: startOrigin.y + deltaY)
            let clamped = KeystrokeOverlaySupport.panelFrame(
                size: frame.size,
                visibleFrame: NSScreen.pointerVisibleFrame,
                position: .bottomCenter,
                customOrigin: targetOrigin
            )
            setFrameOrigin(clamped.origin)
        case .leftMouseUp:
            if dragStartMouseLocation != nil {
                NSCursor.pop()
                if didMoveDuringDrag {
                    onDragEnded?(frame.origin)
                }
                dragStartMouseLocation = nil
                dragStartOrigin = nil
                didMoveDuringDrag = false
                onDragStateChanged?(false)
            }
        default:
            super.sendEvent(event)
        }
    }
}
