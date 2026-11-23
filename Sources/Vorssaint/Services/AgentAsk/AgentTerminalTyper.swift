// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Answers Claude Code's prompt in the terminal it is waiting in, for an
/// answer clicked on the island. The tab is found by its tty. iTerm2 takes the
/// keys straight into that session; Terminal brings the tab forward and the
/// keys are typed into it, and only once Terminal is frontmost, so nothing is
/// ever typed into another app.
enum AgentTerminalTyper {
    private static let iTerm = "com.googlecode.iterm2"
    private static let terminal = "com.apple.Terminal"

    /// Off the main thread: talking to the terminal waits on it.
    static func send(_ keys: [AgentTerminalKey], tty: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let sent = sendITerm(keys, tty: tty) || sendTerminal(keys, tty: tty)
            DispatchQueue.main.async { completion(sent) }
        }
    }

    /// Brings the tab forward without typing, for answering there by hand.
    static func focus(tty: String, completion: @escaping (Bool) -> Void = { _ in }) {
        DispatchQueue.global(qos: .userInitiated).async {
            let found = focusITerm(tty: tty) || focusTerminal(tty: tty)
            DispatchQueue.main.async { completion(found) }
        }
    }

    private static func running(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    // MARK: iTerm2

    private static func sendITerm(_ keys: [AgentTerminalKey], tty: String) -> Bool {
        guard running(iTerm) else { return false }
        // Each key as its own write, a moment apart, as typing would arrive.
        let writes = keys.map { key -> String in
            let text: String
            switch key {
            case .down: return "tell s to write text ((character id 27) & \"[B\") newline no\ndelay 0.06"
            case .enter: text = "(character id 13)"
            case .escape: text = "(character id 27)"
            }
            return "tell s to write text \(text) newline no\ndelay 0.06"
        }.joined(separator: "\n")
        let script = """
        tell application id "\(iTerm)"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is \(AppleScriptRunner.literal(tty)) then
                            \(writes)
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "missing"
        """
        let result = AppleScriptRunner.run(script)
        return result.ok && result.output == "ok"
    }

    private static func focusITerm(tty: String) -> Bool {
        guard running(iTerm) else { return false }
        let script = """
        tell application id "\(iTerm)"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is \(AppleScriptRunner.literal(tty)) then
                            select w
                            select t
                            select s
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "missing"
        """
        let result = AppleScriptRunner.run(script)
        return result.ok && result.output == "ok"
    }

    // MARK: Terminal

    private static func focusTerminal(tty: String) -> Bool {
        guard running(terminal) else { return false }
        let script = """
        tell application id "\(terminal)"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is \(AppleScriptRunner.literal(tty)) then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return "ok"
                    end if
                end repeat
            end repeat
        end tell
        return "missing"
        """
        let result = AppleScriptRunner.run(script)
        return result.ok && result.output == "ok"
    }

    private static func sendTerminal(_ keys: [AgentTerminalKey], tty: String) -> Bool {
        guard focusTerminal(tty: tty) else { return false }
        // Typed only once Terminal is in front, never into whatever was there before.
        let deadline = Date().addingTimeInterval(1.5)
        while NSWorkspace.shared.frontmostApplication?.bundleIdentifier != terminal {
            guard Date() < deadline else { return false }
            usleep(50_000)
        }
        usleep(150_000)
        for key in keys {
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == terminal else { return false }
            post(key)
            usleep(70_000)
        }
        return true
    }

    private static func post(_ key: AgentTerminalKey) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: down)
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
    }
}
