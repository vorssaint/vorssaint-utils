// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreAudio
import IOKit.pwr_mgt

/// Keeps the real menu bar in full-screen apps on the notched built-in
/// display, and lets it hide while the full-screen app plays video. Other
/// displays are never touched and keep the system setting.
///
/// The window server shows the bar on one display while this process holds
/// SkyLight's menu bar visibility override for it: the same reveal as moving
/// the pointer to the top, with no preference changed. Releasing it lets
/// macOS hide the bar again, as it does in full screen with *Automatically
/// hide and show the menu bar* on *In Full Screen Only* or *Always*. Passing
/// false does not force a hide where macOS shows the bar (measured on
/// macOS 27). The symbols are resolved at runtime; without them nothing runs.
///
/// Event driven: Space, screen, wake and app-quit notifications. Video can
/// start or stop without one, so a 1 s check runs only while an app is full
/// screen on the notched display. The override is sent again on events and
/// on a slow backstop: the window server can drop it after a display change
/// and it cannot be read back.
final class NotchFullscreenMenuBarService {
    static let shared = NotchFullscreenMenuBarService()

    private typealias Support = NotchFullscreenMenuBarSupport
    private var running = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var watchTimer: Timer?
    private var backstop: Timer?
    private var overridden: CGDirectDisplayID?
    /// Reads go off-main; a newer one supersedes a pending one.
    private let queue = DispatchQueue(label: "Vorssaint.NotchFullscreenMenuBar", qos: .utility)
    private var generation = 0
    private var reading = false
    private var pendingRead: Bool?
    /// The notched display while full-screen video has let the bar hide
    /// there; the island hides its content on it too.
    private var videoDisplay: CGDirectDisplayID?

    private init() {}

    private func setVideoDisplay(_ displayID: CGDirectDisplayID?) {
        guard displayID != videoDisplay else { return }
        videoDisplay = displayID
        // Async: stop() runs inside the island's own sync and stop.
        DispatchQueue.main.async { NotchService.shared.setFullscreenVideoDisplay(displayID) }
    }

    func syncWithPreferences() {
        guard Support.isEnabled(), MenuBarOverride.isAvailable else {
            stop()
            return
        }
        if !running { start() }
        evaluate(reassert: true)
    }

    func stop() {
        generation += 1
        reading = false
        pendingRead = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        watchTimer?.invalidate()
        watchTimer = nil
        backstop?.invalidate()
        backstop = nil
        release()
        setVideoDisplay(nil)
        running = false
    }

    private func start() {
        running = true
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.settle()
            }))
        }
        let center = NotificationCenter.default
        observers.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                     object: nil, queue: .main) { [weak self] _ in self?.settle() }))
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.evaluate(reassert: true) }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        backstop = timer
    }

    /// Check now, and again once the Space or full-screen animation is over.
    private func settle() {
        evaluate(reassert: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.evaluate(reassert: true) }
    }

    private func evaluate(reassert: Bool = false) {
        guard running else { return }
        if reading {
            pendingRead = (pendingRead ?? false) || reassert
            return
        }
        guard let screen = Self.notchedBuiltInScreen() else {
            release()
            setVideoDisplay(nil)
            setWatching(false)
            return
        }
        let displayID = screen.notchDisplayID
        let bounds = CGDisplayBounds(displayID)
        let displays = SpaceWindowBridge.displayIDsByUUID()
        let separateSpaces = NSScreen.screensHaveSeparateSpaces
        let hidesOnDesktop = UserDefaults.standard.bool(forKey: "_HIHideMenuBar")
        let generation = generation
        reading = true
        queue.async { [weak self] in
            let inputs = Self.readInputs(displayID: displayID, bounds: bounds, displays: displays,
                                         separateSpaces: separateSpaces, hidesOnDesktop: hidesOnDesktop)
            DispatchQueue.main.async {
                guard let self, self.running, generation == self.generation else { return }
                self.reading = false
                self.apply(Support.decide(inputs), on: displayID, reassert: reassert)
                let hides = Support.videoHidesBar(inputs, systemShowsBarInFullscreen: Support.systemShowsBarInFullscreen())
                self.setVideoDisplay(hides ? displayID : nil)
                self.setWatching(inputs.fullscreenApp != nil)
                if let pending = self.pendingRead {
                    self.pendingRead = nil
                    self.evaluate(reassert: pending)
                }
            }
        }
    }

    private func apply(_ decision: Support.Decision, on displayID: CGDirectDisplayID, reassert: Bool) {
        switch decision {
        case .show:
            if let old = overridden, old != displayID { MenuBarOverride.set(false, on: old) }
            if overridden != displayID || reassert { MenuBarOverride.set(true, on: displayID) }
            overridden = displayID
        case .release:
            release()
        }
    }

    private func release() {
        guard let old = overridden else { return }
        MenuBarOverride.set(false, on: old)
        overridden = nil
    }

    private func setWatching(_ on: Bool) {
        if on, watchTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.evaluate() }
            timer.tolerance = 0.3
            RunLoop.main.add(timer, forMode: .common)
            watchTimer = timer
        } else if !on, let timer = watchTimer {
            timer.invalidate()
            watchTimer = nil
        }
    }

    // MARK: - Reading the system

    static func notchedBuiltInScreen() -> NSScreen? {
        NSScreen.screens.first { CGDisplayIsBuiltin($0.notchDisplayID) != 0 && $0.safeAreaInsets.top > 0 }
    }

    /// The video and call checks run only once an app is full screen there,
    /// and the Accessibility read only when it would decide the outcome.
    private static func readInputs(displayID: CGDirectDisplayID, bounds: CGRect,
                                   displays: [String: CGDirectDisplayID], separateSpaces: Bool,
                                   hidesOnDesktop: Bool) -> Support.Inputs {
        var inputs = Support.Inputs(fullscreenApp: nil, playsVideo: false, microphoneInUse: false,
                                    appShowsOwnUI: nil, systemHidesBarOnDesktop: hidesOnDesktop)
        guard let topology = SpaceWindowBridge.topology(displayIDsByUUID: displays) else { return inputs }
        // Without separate Spaces one Space spans every display.
        let display = topology.displays.first { $0.displayID == displayID }
            ?? (separateSpaces ? nil : topology.displays.first)
        guard let app = display?.currentFullscreenOwner else { return inputs }
        inputs.fullscreenApp = app
        inputs.playsVideo = displayAwakeOwners().contains(app)
        guard inputs.playsVideo else { return inputs }
        inputs.microphoneInUse = microphoneInUse()
        guard !inputs.microphoneInUse else { return inputs }
        inputs.appShowsOwnUI = appShowsOwnUI(pid: app, display: bounds)
        return inputs
    }

    private static func displayAwakeOwners() -> Set<pid_t> {
        var snapshot: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&snapshot) == kIOReturnSuccess,
              let raw = snapshot?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        let byPID = Dictionary(raw.map { (pid_t($0.key.int32Value), $0.value) }, uniquingKeysWith: { $0 + $1 })
        return Support.displayAwakeOwners(byPID, owner: ResponsibleProcess.owner(of:))
    }

    /// Is any input device running, other than Vorssaint's own? The signal
    /// behind the orange privacy dot; reading it needs no permission.
    private static func microphoneInUse() -> Bool {
        func address(_ selector: AudioObjectPropertySelector,
                     _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var devicesAddress = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &devicesAddress, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &devicesAddress, 0, nil, &size, &devices) == noErr else { return false }
        return devices.contains { device in
            var streams = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
            var streamBytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamBytes) == noErr,
                  streamBytes > 0 else { return false }
            var running = address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            var value: UInt32 = 0
            var valueSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(device, &running, 0, nil, &valueSize, &value) == noErr, value != 0
            else { return false }
            var nameAddress = address(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let named = AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name) == noErr
            let deviceName = named ? name?.takeRetainedValue() as String? : nil
            return !MicMuteSupport.isOwnDevice(name: deviceName ?? "")
        }
    }

    /// Native Accessibility only, from each full-screen window covering most
    /// of the display. A video a browser plays full screen in a window of its
    /// own leaves the browser window on another Space, unlisted. nil without
    /// permission. While no window reports full screen yet, mid-animation,
    /// the bar is kept rather than flashed away.
    private static func appShowsOwnUI(pid: pid_t, display: CGRect) -> Bool? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        let deadline = Date().addingTimeInterval(0.25)
        let windows = (value(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        let fullscreen = windows.prefix(12).compactMap { window -> (AXUIElement, CGRect)? in
            guard (value(window, "AXFullScreen") as? Bool) == true, let windowFrame = frame(window) else { return nil }
            let overlap = windowFrame.intersection(display)
            guard !overlap.isNull, overlap.width * overlap.height >= display.width * display.height * 0.5
            else { return nil }
            return (window, windowFrame)
        }
        guard !fullscreen.isEmpty else { return true }
        return fullscreen.contains { window, windowFrame in
            let candidates = Support.edgeCandidates(
                of: window, frame: windowFrame,
                children: { (value($0, kAXChildrenAttribute) as? [AXUIElement]) ?? [] },
                role: { value($0, kAXRoleAttribute) as? String },
                frame: frame(_:),
                shouldContinue: { Date() < deadline })
            return Support.edgeBarsVisible(candidates, window: windowFrame, display: display)
        }
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let rawPosition = value(element, kAXPositionAttribute), CFGetTypeID(rawPosition) == AXValueGetTypeID(),
              let rawSize = value(element, kAXSizeAttribute), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(rawPosition, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(rawSize, to: AXValue.self), .cgSize, &size),
              point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite else { return nil }
        return CGRect(origin: point, size: size)
    }
}

/// SkyLight's per-display menu bar visibility override, resolved at runtime.
/// The override belongs to the calling connection and ends with the process.
private enum MenuBarOverride {
    private typealias ConnectionID = UInt32
    private typealias OverrideFunction = @convention(c) (ConnectionID, CGDirectDisplayID, Bool) -> Int32

    private static let bridge: (connection: ConnectionID, set: OverrideFunction)? = {
        func symbol(_ name: String) -> UnsafeMutableRawPointer? {
            dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, name)
        }
        guard let main = symbol("CGSMainConnectionID"),
              let set = symbol("SLSSetMenuBarVisibilityOverrideOnDisplay") else { return nil }
        let connection = unsafeBitCast(main, to: (@convention(c) () -> ConnectionID).self)()
        guard connection != 0 else { return nil }
        return (connection, unsafeBitCast(set, to: OverrideFunction.self))
    }()

    static var isAvailable: Bool { bridge != nil }

    static func set(_ visible: Bool, on displayID: CGDirectDisplayID) {
        guard let bridge else { return }
        _ = bridge.set(bridge.connection, displayID, visible)
    }
}
