// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import UserNotifications

/// Central place to check, request and watch the TCC permissions the app uses.
/// Accessibility powers the scroll inverter and the switcher's event tap;
/// Screen Recording powers window titles and thumbnails in the switcher.
final class Permissions: ObservableObject {
    static let shared = Permissions()

    @Published private(set) var accessibility = false
    @Published private(set) var screenRecording = false
    /// Optional — only used to make the uninstaller's scan more thorough by
    /// reaching protected locations. There is no API prompt for it; the user
    /// grants it in System Settings.
    @Published private(set) var fullDiskAccess = false
    /// Refreshed inside refresh() only (launch and activation); notifications
    /// have no cheap poll and the portal calls refresh() when it appears.
    @Published private(set) var notifications: NotificationPermissionState = .unknown

    enum NotificationPermissionState {
        case granted, denied, undetermined, unknown
    }

    private var activePermissionTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var resignObserver: NSObjectProtocol?
    private var currentPollInterval: TimeInterval = 0

    private init() {
        refresh()
        // Watch for Accessibility and Screen Recording flips so features come
        // alive moments after the toggle flips. Both checks are TCC daemon
        // round-trips, so the cadence adapts: fast only while a flip is
        // plausible (the app is active — Settings, onboarding or the panel is
        // up — or a grant is still missing, meaning the user may be in System
        // Settings right now); slow in the steady state where everything is
        // granted and the app sits in the background, which is where the app
        // spends nearly its whole life.
        // Full Disk Access is deliberately NOT polled here: it can only change
        // across a relaunch (a running process never gains or is meant to lose
        // it mid-session), and probing it touches protected paths, so polling it
        // would just be repeated denied accesses for no gain.
        scheduleActivePermissionPolling()
        // Re-check everything the instant the user returns from System Settings
        // (e.g. after relaunching for Full Disk Access), so the state reflects
        // immediately instead of waiting for the next poll.
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
            self?.scheduleActivePermissionPolling()
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.scheduleActivePermissionPolling()
        }
    }

    deinit {
        activePermissionTimer?.invalidate()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    private var desiredPollInterval: TimeInterval {
        if NSApp.isActive { return 2.5 }
        if !accessibility || !screenRecording { return 2.5 }
        return 60
    }

    private func scheduleActivePermissionPolling() {
        let interval = desiredPollInterval
        guard interval != currentPollInterval else { return }
        currentPollInterval = interval
        activePermissionTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshActivePermissions()
        }
        timer.tolerance = interval * 0.4
        RunLoop.main.add(timer, forMode: .common)
        activePermissionTimer = timer
    }

    /// Full refresh including Full Disk Access. Runs at launch and on activation.
    func refresh() {
        let fda = Self.probeFullDiskAccess()
        refreshActivePermissions()
        refreshNotificationPermission()
        DispatchQueue.main.async {
            if self.fullDiskAccess != fda { self.fullDiskAccess = fda }
        }
    }

    private func refreshNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let state: NotificationPermissionState
            switch settings.authorizationStatus {
            case .authorized, .provisional: state = .granted
            case .denied: state = .denied
            case .notDetermined: state = .undetermined
            @unknown default: state = .unknown
            }
            DispatchQueue.main.async {
                if self?.notifications != state { self?.notifications = state }
            }
        }
    }

    /// Accessibility and Screen Recording only — free, side-effect-free checks
    /// suitable for frequent polling.
    private func refreshActivePermissions() {
        let ax = AXIsProcessTrusted()
        let sr = CGPreflightScreenCaptureAccess()
        DispatchQueue.main.async {
            if self.accessibility != ax { self.accessibility = ax }
            if self.screenRecording != sr { self.screenRecording = sr }
            // A flip can change which cadence applies (e.g. the last grant
            // landed while the app was in the background).
            self.scheduleActivePermissionPolling()
        }
    }

    /// Detects Full Disk Access without a prompt. Reading the TCC database is the
    /// classic signal, but that file is absent on some macOS versions (so a
    /// missing file would read as "no access" forever, even once granted). The
    /// dependable fallback is to list a protected directory that exists: that
    /// listing is denied without Full Disk Access and succeeds with it.
    private static func probeFullDiskAccess() -> Bool {
        let home = NSHomeDirectory()
        let fm = FileManager.default

        // Preferred when present: the TCC database is readable only with access.
        let tccDB = (home as NSString)
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        if let handle = FileHandle(forReadingAtPath: tccDB) {
            let ok = (try? handle.read(upToCount: 1)) != nil
            try? handle.close()
            if ok { return true }
        }

        // Works on every version: each of these is gated by Full Disk Access, so
        // a successful listing (even of an empty directory) means it is granted.
        let gatedDirs = [
            "Library/Safari",
            "Library/Mail",
            "Library/Messages",
            "Library/Cookies",
            "Library/Suggestions",
            "Library/Application Support/MobileSync",
        ].map { (home as NSString).appendingPathComponent($0) }
        return gatedDirs.contains { (try? fm.contentsOfDirectory(atPath: $0)) != nil }
    }

    /// Shows the system Accessibility prompt (once per TCC reset) and floats
    /// the little guide card for the System Settings round trip.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        if !accessibility {
            PermissionGuideOverlay.shared.show(for: .accessibility)
        }
    }

    /// Shows the system Screen Recording prompt (once per TCC reset) and
    /// floats the guide card, like the Accessibility path.
    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        if !screenRecording {
            PermissionGuideOverlay.shared.show(for: .screenRecording)
        }
    }

    func openAccessibilitySettings() {
        open(pane: "Privacy_Accessibility")
    }

    func openScreenRecordingSettings() {
        open(pane: "Privacy_ScreenCapture")
    }

    func openFullDiskAccessSettings() {
        open(pane: "Privacy_AllFiles")
    }

    /// Full Disk Access has no prompt API, and an app only shows up (toggled
    /// off) in its System Settings list once it has attempted to read a
    /// protected location. Touch likely protected paths to register the app,
    /// then open the pane after a short delay so tccd has recorded the denial
    /// before System Settings reads the list. If it still does not appear, the
    /// user can add the app with the list's "+" button.
    func requestFullDiskAccess() {
        DispatchQueue.global(qos: .userInitiated).async {
            let home = NSHomeDirectory()
            let fm = FileManager.default
            // The TCC database is the classic trigger when present. Some macOS
            // versions omit it, so the protected directories below are the
            // fallback registration attempts.
            let tccDB = (home as NSString)
                .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
            _ = try? Data(contentsOf: URL(fileURLWithPath: tccDB), options: .mappedIfSafe)
            if let handle = FileHandle(forReadingAtPath: tccDB) {
                _ = try? handle.read(upToCount: 1)
                try? handle.close()
            }
            // A few more protected locations, harmless when absent.
            let dirs = [
                "Library/Application Support/com.apple.TCC",
                "Library/Safari",
                "Library/Mail",
                "Library/Messages",
                "Library/Cookies",
                "Library/Application Support/MobileSync",
            ].map { (home as NSString).appendingPathComponent($0) }
            for path in dirs { _ = try? fm.contentsOfDirectory(atPath: path) }

            // Let tccd persist the denial before the pane loads its list.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                self.openFullDiskAccessSettings()
            }
        }
    }

    func openNotificationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    func openAutomationSettings() {
        open(pane: "Privacy_Automation")
    }

    func openAudioCaptureSettings() {
        open(pane: "Privacy_AudioCapture")
    }

    private func open(pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Automation (Apple Events)

    enum AutomationTarget: String, CaseIterable {
        case finder = "com.apple.finder"
        case terminal = "com.apple.Terminal"
    }

    enum AutomationStatus {
        case granted, denied, undetermined, notDeterminable
    }

    /// Never prompts (askUserIfNeeded false). A target that is not running
    /// cannot be checked and reads as notDeterminable. Call off the main
    /// thread; the check can block briefly.
    static func automationStatus(for target: AutomationTarget) -> AutomationStatus {
        var descriptor = AEAddressDesc()
        let bundleID = target.rawValue
        let created = bundleID.withCString { pointer in
            AECreateDesc(typeApplicationBundleID, pointer, bundleID.utf8.count, &descriptor)
        }
        guard created == noErr else { return .notDeterminable }
        defer { AEDisposeDesc(&descriptor) }
        switch AEDeterminePermissionToAutomateTarget(&descriptor, typeWildCard, typeWildCard, false) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .undetermined
        default: return .notDeterminable
        }
    }
}
