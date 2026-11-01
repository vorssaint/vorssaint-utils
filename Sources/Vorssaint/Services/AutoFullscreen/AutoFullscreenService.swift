// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics

/// Puts an app's first window in macOS full screen when the app launches.
/// Each launch gets a short series of looks at the app's main window, bounded
/// in time: the first standard window found is asked to enter full screen,
/// and the next look confirms it took or asks again.
///
/// Predictable by design: only launches seen while the feature runs are
/// touched, never windows opened later, only while the app is in front, and
/// any app can be left alone through the exception list. With the built-in
/// display option on, nothing happens while an external display is connected.
/// Requires Accessibility.
final class AutoFullscreenService: ObservableObject {
    static let shared = AutoFullscreenService()

    /// Bundle ids left alone; mirrors the persisted list for the UI.
    @Published private(set) var exceptions: [String] = []

    /// One launch being watched. A new token per launch lets a late answer
    /// from an earlier series, or from before a stop, recognize itself.
    private struct Series {
        let app: NSRunningApplication
        let startedAt: Date
        let token = UUID()
    }

    private var running = false
    private var launchToken: NSObjectProtocol?
    private var terminateToken: NSObjectProtocol?
    private var series: [pid_t: Series] = [:]
    private var pendingLooks: [pid_t: DispatchWorkItem] = [:]
    /// Accessibility calls wait on the launching app, which can be too busy to
    /// answer (a Keychain prompt, a slow first window). Off the main thread a
    /// stalled reply can never hold input or the interface (issue #189).
    private let accessibilityQueue = DispatchQueue(label: "com.vorssaint.auto-fullscreen",
                                                   qos: .userInitiated)

    private init() {
        reloadExceptions()
    }

    var isRunning: Bool { running }

    // MARK: - Lifecycle

    func syncWithPreferences() {
        let enabled = AppFeature.autoFullscreen.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.autoFullscreenEnabled)
        if enabled, Permissions.shared.accessibility {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard !running else { return }
        running = true
        objectWillChange.send()

        let center = NSWorkspace.shared.notificationCenter
        launchToken = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                         object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.handleLaunch(app)
        }
        terminateToken = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.endSeries(pid: app.processIdentifier)
        }
    }

    /// Force-stops every observer and pending look regardless of the
    /// preference. Used before the app resets its own permissions.
    func suspend() { stop() }

    private func stop() {
        guard running else { return }
        running = false
        objectWillChange.send()
        let center = NSWorkspace.shared.notificationCenter
        if let launchToken { center.removeObserver(launchToken) }
        if let terminateToken { center.removeObserver(terminateToken) }
        launchToken = nil
        terminateToken = nil
        for item in pendingLooks.values { item.cancel() }
        pendingLooks.removeAll()
        // A look already on the Accessibility queue finds its series gone
        // when it reports back, and stops there.
        series.removeAll()
    }

    // MARK: - Launches

    private func handleLaunch(_ app: NSRunningApplication) {
        guard running,
              AutoFullscreenSupport.shouldWatch(bundleIdentifier: app.bundleIdentifier,
                                                isRegularApp: app.activationPolicy == .regular,
                                                isOwnApp: app.processIdentifier == getpid(),
                                                exceptions: Self.savedExceptions()),
              displaysAllow()
        else { return }
        let launch = Series(app: app, startedAt: Date())
        endSeries(pid: app.processIdentifier)
        series[app.processIdentifier] = launch
        scheduleLook(launch, after: AutoFullscreenSupport.firstLookDelay)
    }

    private func endSeries(pid: pid_t) {
        pendingLooks.removeValue(forKey: pid)?.cancel()
        series.removeValue(forKey: pid)
    }

    private func isCurrent(_ launch: Series) -> Bool {
        running && series[launch.app.processIdentifier]?.token == launch.token
    }

    private func scheduleLook(_ launch: Series, after delay: TimeInterval) {
        let pid = launch.app.processIdentifier
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingLooks.removeValue(forKey: pid)
            self.look(launch)
        }
        pendingLooks[pid] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func look(_ launch: Series) {
        let app = launch.app
        // Every look re-checks what could have changed since the launch: a
        // display plugged in, the app hidden or quit, the list edited, or
        // Accessibility revoked (an AX call without it would stall).
        guard isCurrent(launch), !app.isTerminated, !app.isHidden,
              AXIsProcessTrusted(),
              !Self.savedExceptions().contains(app.bundleIdentifier ?? ""),
              displaysAllow()
        else { return endSeries(pid: app.processIdentifier) }

        accessibilityQueue.async { [weak self] in
            let found = Self.inspect(pid: app.processIdentifier)
            DispatchQueue.main.async {
                self?.decide(launch, window: found.window, state: found.state)
            }
        }
    }

    private func decide(_ launch: Series, window: AXUIElement?, state: AutoFullscreenSupport.WindowState) {
        guard isCurrent(launch) else { return }
        let app = launch.app
        let elapsed = Date().timeIntervalSince(launch.startedAt)
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        switch AutoFullscreenSupport.nextStep(for: state, appIsFrontmost: frontmost, elapsed: elapsed) {
        case .finish:
            endSeries(pid: app.processIdentifier)
        case .lookAgain:
            scheduleLook(launch, after: AutoFullscreenSupport.lookInterval)
        case .requestFullScreen:
            guard let window else { return endSeries(pid: app.processIdentifier) }
            accessibilityQueue.async {
                AXUIElementSetAttributeValue(window, Self.fullScreenAttribute, kCFBooleanTrue)
            }
            if AutoFullscreenSupport.hasTimeLeft(after: elapsed) {
                scheduleLook(launch, after: AutoFullscreenSupport.lookInterval)
            } else {
                endSeries(pid: app.processIdentifier)
            }
        }
    }

    private func displaysAllow() -> Bool {
        AutoFullscreenSupport.displaysAllow(
            builtInDisplayOnly: UserDefaults.standard.bool(forKey: DefaultsKey.autoFullscreenBuiltInDisplayOnly),
            builtInFlags: Self.onlineDisplayBuiltInFlags())
    }

    private static func onlineDisplayBuiltInFlags() -> [Bool]? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
        guard count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).map { CGDisplayIsBuiltin($0) != 0 }
    }

    // MARK: - Accessibility (on the Accessibility queue)

    private static let fullScreenAttribute = "AXFullScreen" as CFString
    /// Short enough that a launching app that does not answer costs a look,
    /// not the launch window.
    private static let messagingTimeout: Float = 0.35

    /// The main window, else the focused one, when it is a standard window.
    /// Sheets, panels and splash screens wait for the real window instead.
    /// The first call the app is too busy to answer ends the look, so one
    /// look never waits more than one timeout.
    private static func inspect(pid: pid_t) -> (window: AXUIElement?, state: AutoFullscreenSupport.WindowState) {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            var value: CFTypeRef?
            let read = AXUIElementCopyAttributeValue(appElement, attribute as CFString, &value)
            if read == .cannotComplete { return (nil, .none) }
            guard read == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { continue }
            let window = value as! AXUIElement
            AXUIElementSetMessagingTimeout(window, messagingTimeout)
            switch subrole(of: window) {
            case .busy: return (nil, .none)
            case .standard: return (window, state(of: window))
            case .other: continue
            }
        }
        return (nil, .none)
    }

    private enum Subrole { case standard, other, busy }

    private static func subrole(of window: AXUIElement) -> Subrole {
        var subrole: CFTypeRef?
        let read = AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
        if read == .cannotComplete { return .busy }
        guard read == .success, let value = subrole as? String else { return .other }
        return value == (kAXStandardWindowSubrole as String) || value == "AXFullScreenWindow"
            ? .standard : .other
    }

    /// A window too busy to answer reads as no window yet, so the next look
    /// asks again; only a clear answer settles that it cannot go full screen.
    private static func state(of window: AXUIElement) -> AutoFullscreenSupport.WindowState {
        var value: CFTypeRef?
        let read = AXUIElementCopyAttributeValue(window, fullScreenAttribute, &value)
        if read == .cannotComplete { return .none }
        guard read == .success, let value, CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return .fixed
        }
        if CFBooleanGetValue((value as! CFBoolean)) { return .fullScreen }
        var settable: DarwinBoolean = false
        let check = AXUIElementIsAttributeSettable(window, fullScreenAttribute, &settable)
        if check == .cannotComplete { return .none }
        return check == .success && settable.boolValue ? .windowed : .fixed
    }

    // MARK: - Exceptions

    /// Read at each launch rather than cached, so a restored backup needs no
    /// reload to take effect.
    private static func savedExceptions() -> [String] {
        Defaults.sanitizedBundleIdentifierList(
            UserDefaults.standard.stringArray(forKey: DefaultsKey.autoFullscreenExceptions) ?? [])
    }

    func reloadExceptions() {
        let raw = UserDefaults.standard.stringArray(forKey: DefaultsKey.autoFullscreenExceptions) ?? []
        let sanitized = Defaults.sanitizedBundleIdentifierList(raw)
        if raw != sanitized {
            UserDefaults.standard.set(sanitized, forKey: DefaultsKey.autoFullscreenExceptions)
        }
        exceptions = sanitized
    }

    func addException(_ bundleID: String) {
        let bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty, !exceptions.contains(bundleID) else { return }
        UserDefaults.standard.set(Defaults.sanitizedBundleIdentifierList(exceptions + [bundleID]),
                                  forKey: DefaultsKey.autoFullscreenExceptions)
        reloadExceptions()
    }

    func removeException(_ bundleID: String) {
        UserDefaults.standard.set(Defaults.sanitizedBundleIdentifierList(exceptions.filter { $0 != bundleID }),
                                  forKey: DefaultsKey.autoFullscreenExceptions)
        reloadExceptions()
    }
}
