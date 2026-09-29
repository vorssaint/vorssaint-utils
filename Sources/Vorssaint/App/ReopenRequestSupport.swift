// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin

/// Tells a reopen the person asked for from one the system sent on its own.
///
/// Opening an app that is already running sends it a reopen event, and doing
/// that from Finder, the Dock, Spotlight, a launcher or Terminal is how the
/// person gets back in when the menu bar icon is missing. Using the Siri app
/// on macOS 27 also sends running apps a reopen on almost every interaction
/// (macOS 26's Shortcuts did the same), and each one opened the panel or
/// Settings.
enum ReopenRequestSupport {
    /// The process that asked macOS to open the app again.
    struct Sender: Equatable {
        /// Nil for a process LaunchServices does not list as an app.
        var bundleIdentifier: String?
        /// Nil once the process is gone: `open` exits right after asking.
        var executablePath: String?
        /// Whether LaunchServices lists the process as an app at all.
        var isApplication: Bool
    }

    /// Siri, Shortcuts and the services that run their actions. Only Apple's
    /// identifiers are matched: a launcher of another developer may carry
    /// the same words.
    private static let assistantIdentifierFragments = ["siri", "shortcut", "workflow"]
    /// Where the system keeps daemons and services that nobody starts by hand.
    private static let systemServiceDirectories = ["/System/", "/usr/libexec/", "/usr/sbin/", "/Library/Apple/"]

    static func isPersonOpeningApp(_ sender: Sender?) -> Bool {
        // Nothing to judge by keeps the way back in.
        guard let sender else { return true }
        if let identifier = sender.bundleIdentifier?.lowercased(), identifier.hasPrefix("com.apple."),
           assistantIdentifierFragments.contains(where: { identifier.contains($0) }) {
            return false
        }
        // A system process that is not an app, such as the App Intents daemon
        // or Siri's action runner, opens apps for its own reasons. Command-line
        // tools a person runs, such as `open` and `osascript`, stay accepted.
        if !sender.isApplication, let path = sender.executablePath,
           systemServiceDirectories.contains(where: { path.hasPrefix($0) }) {
            return false
        }
        return true
    }

    /// Names the sender in the app's log without a full path.
    static func logName(_ sender: Sender?) -> String {
        sender?.bundleIdentifier ?? sender?.executablePath.map { ($0 as NSString).lastPathComponent } ?? "unknown"
    }

    /// The sender of the Apple event being handled right now.
    static func currentSender() -> Sender? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let value = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value,
              value > 0 else { return nil }
        let pid = pid_t(value)
        let app = NSRunningApplication(processIdentifier: pid)
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let path = proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : nil
        return Sender(bundleIdentifier: app?.bundleIdentifier, executablePath: path, isApplication: app != nil)
    }
}
