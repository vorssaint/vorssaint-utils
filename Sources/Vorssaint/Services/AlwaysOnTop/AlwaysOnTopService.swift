// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Keeps chosen windows of other apps visible above everything else.
///
/// macOS honours a window level only from the window's own app, so another
/// app's window cannot be lifted for real (measured on macOS 26 and 27: the
/// level calls succeed and change nothing). Instead each pin gets an overlay
/// of Vorssaint's own, placed over the window, that shows a live picture of
/// it while other windows cover it; reaching for the picture brings the real
/// window forward. Pins live in memory only and end on quit, when the feature
/// is turned off, or when their window closes.
final class AlwaysOnTopService: ObservableObject {
    static let shared = AlwaysOnTopService()

    @Published private(set) var shortcutRegistrationFailed = false
    @Published private(set) var pinCount = 0

    private let hotkey = QuickToolHotkey(id: 82)
    private var pins: [CGWindowID: AlwaysOnTopPin] = [:]
    private var checkTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    private init() {
        hotkey.onPress = { [weak self] in self?.togglePinForFrontWindow() }
    }

    private var isEnabled: Bool {
        AppFeature.alwaysOnTop.isAvailable && UserDefaults.standard.bool(forKey: DefaultsKey.alwaysOnTopEnabled)
    }

    func syncWithPreferences() {
        let enabled = isEnabled
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled,
                                                  shortcut: GlobalShortcutRole.alwaysOnTop.savedShortcut,
                                                  storageKey: DefaultsKey.alwaysOnTopShortcut)
        // A revoked permission ends every pin: without Accessibility the
        // overlay cannot follow the window, without Screen Recording it has
        // nothing to show.
        guard enabled, AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else {
            unpinAll()
            return
        }
        for pin in pins.values where isExcluded(NSRunningApplication(processIdentifier: pin.appPID)) {
            unpin(pin)
        }
        pins.values.forEach { $0.applyBorder() }
    }

    /// Stops the shortcut and ends every pin, for quitting and uninstalling.
    func suspend() {
        hotkey.unregister()
        unpinAll()
    }

    // MARK: - Pinning

    func togglePinForFrontWindow() {
        guard isEnabled else { return }
        let text = FeatureStrings.alwaysOnTop(L10n.shared.language)
        guard AXIsProcessTrusted() else {
            QuickToolHUD.show(icon: "exclamationmark.triangle", message: text.needsAccessibility)
            Permissions.shared.requestAccessibility()
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            QuickToolHUD.show(icon: "exclamationmark.triangle", message: text.needsScreenRecording)
            Permissions.shared.requestScreenRecording()
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let axWindow = Self.focusedWindow(of: app.processIdentifier),
              let windowID = AXWindowResolver.windowID(for: axWindow) else {
            QuickToolHUD.show(icon: "pin.slash", message: text.noWindow)
            return
        }
        let name = app.localizedName ?? ""
        if let pin = pins[windowID] {
            unpin(pin)
            QuickToolHUD.show(icon: "pin.slash", message: String(format: text.unpinned, name))
            return
        }
        guard !isExcluded(app) else {
            QuickToolHUD.show(icon: "pin.slash", message: String(format: text.excluded, name))
            return
        }
        let list = windowList()
        guard let frame = list.entry(for: windowID)?.bounds ?? AlwaysOnTopWindowList.bounds(of: windowID) else {
            QuickToolHUD.show(icon: "pin.slash", message: text.noWindow)
            return
        }
        let pin = AlwaysOnTopPin(windowID: windowID, appPID: app.processIdentifier,
                                 ownerPID: list.entry(for: windowID)?.pid ?? app.processIdentifier,
                                 appName: name, axWindow: axWindow, frame: frame, service: self)
        pins[windowID] = pin
        pinCount = pins.count
        startWatching()
        QuickToolHUD.show(icon: "pin.fill", message: String(format: text.pinned, name))
        _ = pin.update(with: list)
    }

    func unpin(_ pin: AlwaysOnTopPin) {
        guard pins.removeValue(forKey: pin.windowID) != nil else { return }
        pin.tearDown()
        pinCount = pins.count
        if pins.isEmpty { stopWatching() }
    }

    private func unpinAll() {
        pins.values.forEach { unpin($0) }
    }

    private func isExcluded(_ app: NSRunningApplication?) -> Bool {
        AlwaysOnTopExcludedApps.shared.contains(bundleID: app?.bundleIdentifier,
                                                executablePath: app?.executableURL?.path)
    }

    private static func focusedWindow(of pid: pid_t) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    // MARK: - Checking

    func windowList() -> AlwaysOnTopWindowList {
        AlwaysOnTopWindowList.current()
    }

    /// One window list for every pin, on a short timer while anything is
    /// pinned and right after anything that can change what covers what.
    /// Nothing reports a window being covered, so the timer is the backstop.
    func checkPins() {
        guard !pins.isEmpty else { return }
        let list = windowList()
        for pin in Array(pins.values) where !pin.update(with: list) {
            unpin(pin)
        }
    }

    private func startWatching() {
        guard checkTimer == nil else { return }
        let timer = Timer(timeInterval: AlwaysOnTopSupport.pollInterval, repeats: true) { [weak self] _ in
            self?.checkPins()
        }
        RunLoop.main.add(timer, forMode: .common)
        checkTimer = timer
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.checkPins()
                // The new order can land a beat after the notification.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.checkPins() }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                    .processIdentifier else { return }
            self.pins.values.filter { $0.appPID == pid || $0.ownerPID == pid }.forEach { self.unpin($0) }
        })
    }

    private func stopWatching() {
        checkTimer?.invalidate()
        checkTimer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }
}

/// One pass over the window server's on-screen list, front to back.
struct AlwaysOnTopWindowList {
    let entries: [AlwaysOnTopWindowEntry]
    private let positions: [CGWindowID: Int]

    init(entries: [AlwaysOnTopWindowEntry]) {
        self.entries = entries
        positions = Dictionary(entries.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func current() -> AlwaysOnTopWindowList {
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                             kCGNullWindowID) as? [[String: Any]] ?? []
        return AlwaysOnTopWindowList(entries: raw.compactMap(entry))
    }

    /// The frame of a window that is not on screen, such as one on another
    /// Space, or nil once the window no longer exists.
    static func bounds(of windowID: CGWindowID) -> CGRect? {
        guard let raw = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let first = raw.first else { return nil }
        return entry(first)?.bounds
    }

    func entry(for windowID: CGWindowID) -> AlwaysOnTopWindowEntry? {
        positions[windowID].map { entries[$0] }
    }

    func contains(_ windowID: CGWindowID) -> Bool {
        positions[windowID] != nil
    }

    func coverage(of windowID: CGWindowID, isParked: Bool) -> AlwaysOnTopCoverage {
        AlwaysOnTopSupport.coverage(of: windowID, onScreen: entries, isParked: isParked,
                                    ownPID: ProcessInfo.processInfo.processIdentifier,
                                    ignoredPIDs: Self.dockPID.map { [$0] } ?? [],
                                    systemLevel: Int(CGWindowLevelForKey(.dockWindow)))
    }

    private static var cachedDockPID: pid_t?

    /// The Dock keeps a transparent window the size of the screen at its own
    /// level; it is never a window covering a pin.
    private static var dockPID: pid_t? {
        if let pid = cachedDockPID, NSRunningApplication(processIdentifier: pid)?.isTerminated == false {
            return pid
        }
        cachedDockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier
        return cachedDockPID
    }

    private static func entry(_ info: [String: Any]) -> AlwaysOnTopWindowEntry? {
        guard let number = info[kCGWindowNumber as String] as? Int,
              let pid = info[kCGWindowOwnerPID as String] as? Int,
              let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else { return nil }
        return AlwaysOnTopWindowEntry(id: CGWindowID(number), pid: pid_t(pid),
                                      layer: info[kCGWindowLayer as String] as? Int ?? 0,
                                      bounds: bounds,
                                      alpha: info[kCGWindowAlpha as String] as? Double ?? 1)
    }
}
