// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import EventKit
import UserNotifications

/// One walk through every permission the app can use, so each system prompt
/// appears now rather than the first time a feature needs it. Prompts the
/// system can show come one at a time; the ones that only exist as a switch in
/// System Settings open that pane at the end, with a list of what is left.
extension Permissions {
    /// Launch with `--grant-permissions` to run the walk once at startup.
    static var launchRequestsEverything: Bool {
        CommandLine.arguments.contains("--grant-permissions")
    }

    /// Launch with `--dump-permissions` to write what is allowed to
    /// /tmp/vorssaint-permissions.txt, then quit. Never prompts.
    static var launchDumpsPermissions: Bool {
        CommandLine.arguments.contains("--dump-permissions")
    }

    func dumpPermissions() {
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
            DispatchQueue.global(qos: .userInitiated).async {
                let finder = Self.automationStatus(for: .finder)
                DispatchQueue.main.async {
                    var lines = [
                        "accessibility: \(self.accessibility)",
                        "screenRecording: \(self.screenRecording)",
                        "fullDiskAccess: \(self.fullDiskAccess)",
                        "microphone: \(self.microphone)",
                        "camera: \(self.camera)",
                        "notifications: \(self.notifications)",
                        "calendar: \(self.calendarAccess == .fullAccess ? "fullAccess" : "\(self.calendarAccess.rawValue)")",
                        "automationFinder: \(finder)",
                    ]
                    let fm = FileManager.default, home = NSHomeDirectory()
                    for folder in ["Desktop", "Documents", "Downloads"] {
                        let ok = (try? fm.contentsOfDirectory(atPath: (home as NSString).appendingPathComponent(folder))) != nil
                        lines.append("folder \(folder): \(ok)")
                    }
                    try? lines.joined(separator: "\n").write(toFile: "/tmp/vorssaint-permissions.txt", atomically: true, encoding: .utf8)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func requestEverything() {
        guard !Self.walkingThroughPermissions else { return }
        Self.walkingThroughPermissions = true
        NSApp.activate(ignoringOtherApps: true)
        let steps: [() -> Void] = [
            { self.requestAccessibility() },
            { self.requestScreenRecording() },
            { self.requestMicrophone() },
            { self.requestCamera() },
            { self.requestCalendar() },
            { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in } },
            { Self.touchProtectedFolders() },
            { Self.askAutomation() },
        ]
        for (index, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 2.5) { step() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(steps.count) * 2.5 + 1) { [weak self] in
            self?.finishWalk()
        }
    }

    private static var walkingThroughPermissions = false

    /// Reading these folders makes macOS ask for Files & Folders access.
    private static func touchProtectedFolders() {
        DispatchQueue.global(qos: .userInitiated).async {
            let home = NSHomeDirectory()
            for folder in ["Desktop", "Documents", "Downloads", "Library/Mobile Documents"] {
                _ = try? FileManager.default.contentsOfDirectory(atPath: (home as NSString).appendingPathComponent(folder))
            }
            for volume in (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? [] {
                _ = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes/" + volume)
            }
        }
    }

    /// Finder and System Events are always running, so they can be asked now.
    /// Music and Spotify are asked only if already open.
    private static func askAutomation() {
        DispatchQueue.global(qos: .userInitiated).async {
            var targets = ["com.apple.finder", "com.apple.systemevents"]
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            targets += ["com.apple.Music", "com.spotify.client"].filter(running.contains)
            for target in targets { AppleScriptRunner.consentToAutomate(bundleID: target) }
        }
    }

    private func finishWalk() {
        Self.walkingThroughPermissions = false
        refresh()
        var missing: [String] = []
        if !accessibility { missing.append("Accessibility") }
        if !screenRecording { missing.append("Screen Recording") }
        if !fullDiskAccess { missing.append("Full Disk Access") }
        if microphone != .granted { missing.append("Microphone") }
        if camera != .granted { missing.append("Camera") }
        if notifications != .granted { missing.append("Notifications") }
        if calendarAccess != .fullAccess { missing.append("Calendar") }

        // Full Disk Access, App Management and Audio Capture have no prompt:
        // they are switches in System Settings.
        let alert = NSAlert()
        alert.messageText = missing.isEmpty ? "Permissions are all set" : "Still to allow"
        alert.informativeText = (missing.isEmpty ? "" : missing.joined(separator: ", ") + ".\n\n")
            + "Full Disk Access, App Management and Audio Capture are switches in System Settings. "
            + "Turn Vorssaint on in each so every feature works."
        alert.addButton(withTitle: "Open Full Disk Access")
        alert.addButton(withTitle: "Open App Management")
        alert.addButton(withTitle: "Open Audio Capture")
        alert.addButton(withTitle: "Done")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: requestFullDiskAccess()
        case .alertSecondButtonReturn: openAppManagementSettings()
        case .alertThirdButtonReturn: openAudioCaptureSettings()
        default: break
        }
    }
}
