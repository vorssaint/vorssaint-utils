// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import IOKit.hidsystem

/// Central place to check, request and watch the TCC permissions the app uses.
/// Accessibility powers the scroll inverter and the switcher's event tap;
/// Screen Recording powers window titles and thumbnails in the switcher.
final class Permissions: ObservableObject {
    static let shared = Permissions()

    @Published private(set) var accessibility = false
    @Published private(set) var screenRecording = false
    @Published private(set) var inputMonitoring = false
    /// Optional — only used to make the uninstaller's scan more thorough by
    /// reaching protected locations. There is no API prompt for it; the user
    /// grants it in System Settings.
    @Published private(set) var fullDiskAccess = false

    private var activePermissionTimer: Timer?
    private var activationObserver: NSObjectProtocol?

    private init() {
        refresh()
        // Cheap always-on watch for Accessibility, Input Monitoring and Screen
        // Recording: those are pure in-process status checks (no file access) and
        // can be granted while the app runs, so features come alive moments after
        // the toggle flips.
        // Full Disk Access is deliberately NOT polled here: it can only change
        // across a relaunch (a running process never gains or is meant to lose
        // it mid-session), and probing it touches protected paths, so polling it
        // would just be repeated denied accesses for no gain.
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.refreshActivePermissions()
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        activePermissionTimer = timer
        // Re-check everything the instant the user returns from System Settings
        // (e.g. after relaunching for Full Disk Access), so the state reflects
        // immediately instead of waiting for the next launch.
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        activePermissionTimer?.invalidate()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }

    /// Full refresh including Full Disk Access. Runs at launch and on activation.
    func refresh() {
        let fda = Self.probeFullDiskAccess()
        refreshActivePermissions()
        DispatchQueue.main.async {
            if self.fullDiskAccess != fda { self.fullDiskAccess = fda }
        }
    }

    /// Accessibility, Input Monitoring and Screen Recording only — free, side-effect-free checks
    /// suitable for frequent polling.
    private func refreshActivePermissions() {
        let ax = AXIsProcessTrusted()
        let im = CGPreflightListenEventAccess()
        let sr = CGPreflightScreenCaptureAccess()
        DispatchQueue.main.async {
            if self.accessibility != ax { self.accessibility = ax }
            if self.inputMonitoring != im { self.inputMonitoring = im }
            if self.screenRecording != sr { self.screenRecording = sr }
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

    /// Shows the system Accessibility prompt (once per TCC reset).
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Shows the system Screen Recording prompt (once per TCC reset).
    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    func requestInputMonitoring() {
        CGRequestListenEventAccess()
    }

    func openAccessibilitySettings() {
        open(pane: "Privacy_Accessibility")
    }

    func openScreenRecordingSettings() {
        open(pane: "Privacy_ScreenCapture")
    }

    func openInputMonitoringSettings() {
        open(pane: "Privacy_ListenEvent")
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

    private func open(pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        NSWorkspace.shared.open(url)
    }
}
