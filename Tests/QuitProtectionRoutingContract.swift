// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The complete production service runs against isolated preferences, a silent
/// HUD and fake applications. No event tap is installed and no app is quit.
enum QuitProtectionRoutingContract {
    enum UserDefaults {
        static let standard = Foundation.UserDefaults(suiteName: "vorss.tests.quit-routing")!
    }
    enum AppFeature {
        case quitWindowProtection
        var isAvailable: Bool { true }
    }
    final class SessionActivity {
        static let shared = SessionActivity()
        let isActive = true
        func onChange(_ action: @escaping (Bool) -> Void) {}
    }
    final class AppSwitcher {
        static let shared = AppSwitcher()
        var keyboardInputOwnership: (isOwned: Bool, generation: UInt64) = (false, 0)
    }
    enum SymbolicHotKeys {
        static var snapshot: [LiveSystemShortcut]?
        static var readCount = 0
        static var requestedIDs: Set<Int32> = []
        static func entries(for ids: Set<Int32>) -> [LiveSystemShortcut]? {
            readCount += 1
            requestedIDs = ids
            return snapshot?.filter { ids.contains($0.id) }
        }
    }
    enum GlobalShortcut {
        static var keyLabels: [Int64: String] = [12: "q", 13: "w", 47: "."]
        static func layoutKeyLabel(for keyCode: Int64, usesCommand: Bool) -> String? {
            keyLabels[keyCode]
        }
    }
    final class NSRunningApplication {
        static var terminated: [pid_t] = []
        let processIdentifier: pid_t
        let bundleIdentifier: String? = "com.google.Chrome"
        init?(processIdentifier: pid_t) { self.processIdentifier = processIdentifier }
        func terminate() -> Bool {
            Self.terminated.append(processIdentifier)
            return true
        }
    }
    final class NSWorkspace {
        static let shared = NSWorkspace()
        static let didActivateApplicationNotification = Notification.Name("fixture.activate")
        static let applicationUserInfoKey = "application"
        let notificationCenter = NotificationCenter()
        var frontmostApplication: NSRunningApplication? { NSRunningApplication(processIdentifier: 100) }
    }
    final class QuitProtectionHUD {
        private(set) var visible = false
        func show(title: String, detail: String, holdDeadline: Date? = nil, on screen: NSScreen? = nil) {
            visible = true
        }
        func hide() { visible = false }
    }
}
