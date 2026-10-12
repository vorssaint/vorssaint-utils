// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

final class DockLockService {
    static let shared = DockLockService()
    private let stateLock = NSLock()
    private var cachedZones: [DockLockSupport.Zone] = []
    private var cachedBypass: CGEventFlags = .maskAlternate
    private var relocationCanceled = false
    private var lastPhysicalMovement: TimeInterval = 0
    private lazy var inputTap = WindowInputTap(mask: [CGEventType.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }) { [weak self] type, event in
        guard let self else { return true }
        if event.getIntegerValueField(.eventSourceUserData) == DockLockService.marker { return true }
        let state = self.stateLock.withLock { () -> ([DockLockSupport.Zone], CGEventFlags) in
            self.relocationCanceled = true; self.lastPhysicalMovement = ProcessInfo.processInfo.systemUptime
            return (self.cachedZones, self.cachedBypass)
        }
        guard type == .mouseMoved else { return true }
        let flags = event.flags.union(CGEventSource.flagsState(.combinedSessionState))
        if !flags.contains(state.1), !Self.buttonsPressed, let zone = state.0.first(where: { $0.rect.contains(event.location) }) {
            event.location = CGPoint(x: event.location.x + zone.dx, y: event.location.y + zone.dy)
        }
        return true
    }
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var relocation = UUID()
    private var relocating = false
    private var attemptedPlacement: String?
    private var relocationOrigin: CGPoint?
    private var geometryFingerprint = ""
    private var bypass: CGEventFlags = .maskAlternate
    private static var buttonsPressed: Bool {
        (0..<32).contains { CGEventSource.buttonState(.combinedSessionState, button: CGMouseButton(rawValue: UInt32($0))!) }
    }
    private static let marker: Int64 = 0x56535344
    private var zones: [DockLockSupport.Zone] = []
    private init() {}
    static func identifier(_ screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }
    static func modifier(_ name: String) -> CGEventFlags {
        switch name { case "command": return .maskCommand; case "control": return .maskControl; case "shift": return .maskShift; default: return .maskAlternate }
    }
    func syncWithPreferences() {
        guard AppFeature.dockLock.isAvailable, DockOption.lockEnabled.bool,
              Permissions.shared.accessibility, SessionActivity.shared.isActive else { stop(); return }
        refresh()
        if timer == nil {
            let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in self?.relocateIfNeeded() }
            timer.tolerance = 0.15; self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        }
        inputTap.start()
    }
    private func refresh() {
        defer { stateLock.withLock { cachedZones = zones; cachedBypass = bypass } }
        bypass = Self.modifier(DockOption.lockModifier.string)
        let screens = NSScreen.screens
        let requested = DockOption.lockDisplay.string
        let fingerprint = requested + DockAccessibility.orientation.rawValue + screens.map { String(describing: $0.frame) }.joined()
        if fingerprint != geometryFingerprint { attemptedPlacement = nil; geometryFingerprint = fingerprint }
        let index = requested == "main" ? screens.indices.first : screens.firstIndex(where: { Self.identifier($0) == requested })
        guard let index else { zones = []; return }
        let top = screens.first?.frame.maxY ?? 0
        let frames = screens.map { CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
        zones = DockLockSupport.zones(screens: frames, locked: index, orientation: DockAccessibility.orientation)
    }
    private func relocateIfNeeded() {
        guard ProcessInfo.processInfo.systemUptime - stateLock.withLock({ lastPhysicalMovement }) > 1 else { return }
        if CGEventSource.flagsState(.combinedSessionState).contains(bypass) { attemptedPlacement = nil; return }
        guard inputTap.isRunning, !relocating, !zones.isEmpty, SessionActivity.shared.isActive, AXIsProcessTrusted(),
              !Self.buttonsPressed else { return }
        refresh()
        let screens = NSScreen.screens, requested = DockOption.lockDisplay.string
        guard let target = requested == "main" ? screens.first : screens.first(where: { Self.identifier($0) == requested }),
              let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier,
              let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let bounds = entries.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == dockPID && ($0[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.dockWindow)) })?[kCGWindowBounds as String] as? [String: Any],
              let dockFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return }
        let appKitDock = DockAccessibility.appKit(dockFrame)
        if target.frame.contains(appKitDock.dockCenter) { attemptedPlacement = nil; return }
        let key = requested + ":" + String(dockPID) + ":" + String(describing: NSScreen.screens.first(where: { $0.frame.contains(appKitDock.dockCenter) })?.frame)
        guard attemptedPlacement != key, let original = CGEvent(source: nil)?.location else { return }
        attemptedPlacement = key
        let top = screens.first?.frame.maxY ?? 0
        let frames = screens.map { CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
        guard let index = screens.firstIndex(of: target),
              let path = DockLockSupport.relocationPath(frame: frames[index], screens: frames, orientation: DockAccessibility.orientation) else { return }
        stateLock.withLock { relocationCanceled = false }
        relocationOrigin = original
        relocating = true; let token = UUID(); relocation = token
        postRelocationStep(0, path: path, original: original, token: token)
    }
    private func postRelocationStep(_ step: Int, path: (CGPoint, CGPoint), original: CGPoint, token: UUID) {
        guard relocation == token, relocating, inputTap.isRunning else { return }
        if stateLock.withLock({ relocationCanceled }) || Self.buttonsPressed || CGEventSource.flagsState(.combinedSessionState).contains(bypass) { relocation = UUID(); relocating = false; relocationOrigin = nil; attemptedPlacement = nil; return }
        let fraction = min(1, CGFloat(step) / 8)
        let point = CGPoint(x: path.0.x + (path.1.x - path.0.x) * fraction, y: path.0.y + (path.1.y - path.0.y) * fraction)
        let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        event?.setIntegerValueField(.eventSourceUserData, value: DockLockService.marker)
        if step >= 8 {
            switch DockAccessibility.orientation {
            case .bottom: event?.setIntegerValueField(.mouseEventDeltaY, value: 8)
            case .left: event?.setIntegerValueField(.mouseEventDeltaX, value: -8)
            case .right: event?.setIntegerValueField(.mouseEventDeltaX, value: 8)
            }
        }
        event?.post(tap: .cghidEventTap)
        if step < 14 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in self?.postRelocationStep(step + 1, path: path, original: original, token: token) }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, self.relocation == token, self.relocating else { return }
                if self.stateLock.withLock({ self.relocationCanceled }) || Self.buttonsPressed || CGEventSource.flagsState(.combinedSessionState).contains(self.bypass) { self.relocating = false; self.relocationOrigin = nil; self.attemptedPlacement = nil; return }
                self.relocating = false; self.relocationOrigin = nil
                if NSScreen.screens.contains(where: { $0.frame.contains(DockAccessibility.appKit(CGRect(origin: original, size: .zero)).origin) }) { CGWarpMouseCursorPosition(original) }
            }
        }
    }
    func stop() {
        if relocating, !stateLock.withLock({ relocationCanceled }),
           !Self.buttonsPressed, !CGEventSource.flagsState(.combinedSessionState).contains(bypass),
           let origin = relocationOrigin { CGWarpMouseCursorPosition(origin) }
        relocation = UUID(); relocating = false; relocationOrigin = nil; attemptedPlacement = nil
        timer?.invalidate(); timer = nil
        inputTap.stop()
        stateLock.withLock { cachedZones = []; relocationCanceled = true }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil; zones = []
    }
}
