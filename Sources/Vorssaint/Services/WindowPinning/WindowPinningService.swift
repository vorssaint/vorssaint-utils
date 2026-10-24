// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CoreGraphics
import Foundation
import os

enum WindowPinningSource: String {
    case menu, shortcut
}

/// Pins and unpins the focused window of other apps by showing a live clone
/// of it: a borderless floating panel fed by a ScreenCaptureKit stream of the
/// pinned window. The window server on current macOS will not let one process
/// lift another app's window (level changes and ordering are silently
/// ignored), while capturing the window and drawing the clone in our own
/// panel works with the permissions this feature already asks for. The gate,
/// the hotkey and the session observation follow FocusFollowsMouseService and
/// HotkeyManager: the feature runs only while wanted, trusted and on the
/// console, and every published change lands on the main thread.
final class WindowPinningService: ObservableObject {
    static let shared = WindowPinningService()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "window-pinning")

    @Published private(set) var pinnedCount: Int = 0
    /// True while the service runs: the feature is on, Accessibility is
    /// granted and the session is live. Settings reads this to decide between
    /// the controls and the "grant Accessibility" banner.
    @Published private(set) var pinningAvailable: Bool = false

    private var store = PinnedWindowStore.load(defaultsKey: DefaultsKey.windowPinnedWindows)
    private var isRunning = false
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var registeredShortcut: GlobalShortcut?
    private var reverifyTimer: Timer?
    private var workspaceObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    /// The last app that was frontmost besides us. Vorssaint's own settings
    /// and menu panels take focus while their pin buttons still mean "the
    /// window the user was just working in", so the toggle falls back to this
    /// when the current focus is ourselves.
    private var recentOtherFrontmostPID: pid_t?

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    func syncWithPreferences() {
        runOnMain {
            let wanted = AppFeature.windowPinning.isAvailable
                && UserDefaults.standard.bool(forKey: DefaultsKey.windowPinningEnabled)
            if SessionActivitySupport.tapShouldRun(
                featureWanted: wanted,
                accessibilityGranted: AXIsProcessTrusted(),
                sessionIsActive: SessionActivity.shared.isActive
            ) {
                self.start()
            } else {
                self.stop()
            }
        }
    }

    /// Pins the focused window of another app, or removes its clone when
    /// already pinned.
    func toggleFocusedWindow(source: WindowPinningSource) {
        runOnMain {
            self.toggleFocusedWindowOnMain(source: source)
        }
    }

    /// Closes every clone and forgets the pins, including entries whose
    /// windows have since closed.
    func unpinAll() {
        runOnMain {
            WindowPinningOverlayManager.shared.stopAll()
            self.store = PinnedWindowStore()
            self.store.save(defaultsKey: DefaultsKey.windowPinnedWindows)
            self.updatePinnedCount()
            self.stopReverifyTimer()
        }
    }

    // MARK: - Lifecycle

    private func start() {
        guard !isRunning else { return }
        isRunning = true
        pinningAvailable = true
        registerHotkey()
        WindowPinningOverlayManager.shared.onCloneClicked = { [weak self] entry in
            self?.raiseOriginal(of: entry)
        }
        reassertPersistedPins()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append((center, center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.reverifyPinnedWindows()
            }))
        workspaceObservers.append((center, center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.reverifyPinnedWindows()
            }))
        workspaceObservers.append((center, center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let self,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier
                else { return }
                self.recentOtherFrontmostPID = app.processIdentifier
            }))
    }

    private func stop() {
        guard isRunning else { return }
        isRunning = false
        pinningAvailable = false
        unregisterHotkey()
        stopReverifyTimer()
        WindowPinningOverlayManager.shared.stopAll()
        workspaceObservers.forEach { $0.center.removeObserver($0.token) }
        workspaceObservers.removeAll()
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func updatePinnedCount() {
        pinnedCount = store.count
    }

    // MARK: - Pin re-verification

    /// After launch: windows that survived relaunch get their clone back,
    /// windows whose owners quit while we were gone are pruned from the store.
    private func reassertPersistedPins() {
        let live = onScreenWindowInfosByID()
        let removed = store.prune(keeping: Set(live.keys))
        if !removed.isEmpty {
            store.save(defaultsKey: DefaultsKey.windowPinnedWindows)
            removed.forEach { WindowPinningOverlayManager.shared.stopOverlay(windowID: $0.windowID) }
        }
        var frames: [UInt32: CGRect] = [:]
        for entry in store.entries {
            if let info = live[entry.windowID], let frame = WindowServerSupport.bounds(from: info) {
                frames[entry.windowID] = frame
                startOverlayIfPossible(entry)
            }
        }
        WindowPinningOverlayManager.shared.syncFrames(frames)
        updatePinnedCount()
        startReverifyTimerIfNeeded()
    }

    /// The sweep that keeps pins honest while the feature runs: a window that
    /// vanished drops its clone and its entry; a survivor's clone follows the
    /// window's current frame and starts if it has not yet (for example once
    /// Screen Recording arrives after the pin).
    private func reverifyPinnedWindows() {
        guard isRunning else { return }
        let live = onScreenWindowInfosByID()
        let removed = store.prune(keeping: Set(live.keys))
        if !removed.isEmpty {
            store.save(defaultsKey: DefaultsKey.windowPinnedWindows)
            removed.forEach { WindowPinningOverlayManager.shared.stopOverlay(windowID: $0.windowID) }
        }
        var frames: [UInt32: CGRect] = [:]
        for entry in store.entries {
            if let info = live[entry.windowID], let frame = WindowServerSupport.bounds(from: info) {
                frames[entry.windowID] = frame
            }
            if !WindowPinningOverlayManager.shared.isActive(windowID: entry.windowID) {
                startOverlayIfPossible(entry)
            }
        }
        WindowPinningOverlayManager.shared.syncFrames(frames)
        updatePinnedCount()
        if store.count == 0 { stopReverifyTimer() }
    }

    private func onScreenWindowInfosByID() -> [UInt32: [String: Any]] {
        // Existence, not visibility: a pinned window parked on another Space
        // is off the on-screen list but must survive the prune, so the listing
        // keeps every window the server knows about.
        var result: [UInt32: [String: Any]] = [:]
        for info in CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [] {
            guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            result[id] = info
        }
        return result
    }

    /// The frame of the app's Accessibility focused window, when it exposes
    /// one: the exact window the user is working in, which beats guessing by
    /// z-order (tooltips and child panes outrank the main window there).
    private func axFocusedWindowFrame(pid: pid_t) -> CGRect? {
        let application = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value else { return nil }
        return Self.frame(of: window as! AXUIElement)
    }

    /// Brings a pinned window's original in front of whatever covered it, the
    /// way a click on it would if it were not hidden under its clone: the
    /// owner activates and the matching Accessibility window is raised. The
    /// AX window is matched by frame, the same key the toggle resolves with.
    private func raiseOriginal(of entry: PinnedWindowEntry) {
        NSRunningApplication(processIdentifier: entry.ownerPID)?.activate()
        guard let frame = WindowServerSupport.frame(ofWindowID: entry.windowID) else { return }
        let application = AXUIElementCreateApplication(entry.ownerPID)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement],
              let window = windows.first(where: { Self.frame(of: $0) == frame })
        else {
            Self.log.info("raise for window \(entry.windowID, privacy: .public): no matching AX window")
            return
        }
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard CFGetTypeID(positionRef) == AXValueGetTypeID(),
              AXValueGetValue(positionRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Overlays ask for Screen Recording; without it the pin stays recorded
    /// and the sweep retries, so granting the permission later heals the pin.
    private func startOverlayIfPossible(_ entry: PinnedWindowEntry) {
        let overlays = WindowPinningOverlayManager.shared
        guard overlays.hasScreenRecordingPermission else { return }
        overlays.startOverlay(for: entry)
    }

    private func startReverifyTimerIfNeeded() {
        guard isRunning, reverifyTimer == nil, store.count > 0 else { return }
        // 150 ms: the clone must track a dragged window closely or the pin
        // feels broken — and every desync beat exposes the (blanked) original
        // next to the clone. The sweep is cheap enough to hold that cadence
        // while a pin exists.
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.reverifyPinnedWindows()
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        reverifyTimer = timer
    }

    private func stopReverifyTimer() {
        reverifyTimer?.invalidate()
        reverifyTimer = nil
    }

    // MARK: - Toggle

    private func toggleFocusedWindowOnMain(source: WindowPinningSource) {
        guard isRunning else {
            Self.log.info("toggle \(source.rawValue, privacy: .public): service not running (enable the feature and grant Accessibility)")
            return
        }
        guard AXIsProcessTrusted() else {
            Self.log.info("toggle \(source.rawValue, privacy: .public): Accessibility not granted")
            return
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = WindowServerSupport.onScreenWindowInfo()
        // Accessibility names the focused app; when it answers with us (our
        // settings or menu panel holds focus) fall back to the frontmost app,
        // and when that is us too, to the app the user was last working in.
        let axPID = WindowPinningResolver.axFocusedAppPID()
        var targetPID = axPID.flatMap { ($0 > 0 && $0 != ownPID) ? $0 : nil }
        if targetPID == nil {
            if let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier,
               frontmost > 0, frontmost != ownPID {
                targetPID = frontmost
            } else if let recent = recentOtherFrontmostPID,
                      !WindowPinningResolver.filteredAppWindows(windows, ownerPID: recent).isEmpty {
                targetPID = recent
            }
        }
        guard let targetPID, targetPID > 0, targetPID != ownPID else {
            Self.log.info("toggle \(source.rawValue, privacy: .public): no other app to pin")
            return
        }
        guard let windowID = WindowPinningResolver.frontmostWindowID(
            ownPID: ownPID, windows: windows, focusedPID: targetPID,
            focusedWindowFrame: axFocusedWindowFrame(pid: targetPID)
        ) else {
            Self.log.info("toggle \(source.rawValue, privacy: .public): no resolvable window for pid \(targetPID, privacy: .public)")
            return
        }
        if let entry = store.remove(windowID: windowID) {
            unpin(entry)
        } else {
            pin(windowID: windowID, ownerPID: targetPID)
        }
    }

    private func pin(windowID: CGWindowID, ownerPID: pid_t) {
        let entry = PinnedWindowEntry(
            windowID: windowID,
            ownerPID: ownerPID,
            bundleID: NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier ?? "",
            pinnedAt: Date()
        )
        store.upsert(entry)
        store.save(defaultsKey: DefaultsKey.windowPinnedWindows)
        Self.log.info("pinned window \(windowID, privacy: .public) of pid \(ownerPID, privacy: .public)")
        if !WindowPinningOverlayManager.shared.startOverlay(for: entry) {
            Self.log.info("overlay did not start for window \(windowID, privacy: .public) (Screen Recording not granted?); the sweep retries")
        }
        updatePinnedCount()
        startReverifyTimerIfNeeded()
    }

    private func unpin(_ entry: PinnedWindowEntry) {
        WindowPinningOverlayManager.shared.stopOverlay(windowID: entry.windowID)
        store.save(defaultsKey: DefaultsKey.windowPinnedWindows)
        updatePinnedCount()
        if store.count == 0 { stopReverifyTimer() }
    }

    // MARK: - Hotkey

    /// Own Carbon registration, mirroring HotkeyManager: the dispatcher
    /// delivers every hotkey to every handler, so the callback answers only
    /// its own signature and id and hands everything else back.
    private func registerHotkey() {
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.windowPinningShortcut,
                                            fallback: .windowPinningDefault)
        if hotKeyRef != nil, registeredShortcut == shortcut { return }
        unregisterHotkey()
        if eventHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                if let event {
                    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                      EventParamType(typeEventHotKeyID), nil,
                                      MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                }
                guard hotKeyID.signature == 0x5650_494E, hotKeyID.id == 1
                else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<WindowPinningService>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    service.logHotkeyFired()
                    service.toggleFocusedWindow(source: .shortcut)
                }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        }
        let hotKeyID = EventHotKeyID(signature: 0x5650_494E, id: 1) // 'VPIN'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.carbonKeyCode,
                                         shortcut.carbonModifiers,
                                         hotKeyID,
                                         GetEventDispatcherTarget(),
                                         0,
                                         &ref)
        if status == noErr, let ref {
            hotKeyRef = ref
            registeredShortcut = shortcut
            SystemShortcutTakeover.claim(DefaultsKey.windowPinningShortcut, shortcut: shortcut)
        } else {
            hotKeyRef = nil
            registeredShortcut = nil
            Self.log.error("hotkey registration failed with status \(status, privacy: .public)")
        }
    }

    private func unregisterHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
            SystemShortcutTakeover.release(DefaultsKey.windowPinningShortcut)
        }
        registeredShortcut = nil
    }

    /// Separate named entry so the Carbon closure stays a one-liner.
    func logHotkeyFired() {
        Self.log.debug("hotkey fired")
    }
}
