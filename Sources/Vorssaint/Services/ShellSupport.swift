// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreServices

enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

/// Runs a command with administrator privileges (system password prompt).
enum AdminShell {
    // Vorssaint is a menu-bar agent (LSUIElement), so it is rarely the active
    // app. SecurityAgent attaches its password dialog to the requesting process;
    // when that process is an inactive agent the dialog can open behind the
    // frontmost app and read as "no prompt appeared". Bringing the app forward
    // first — exactly what onboarding and the Dock Preview intro already do for
    // their own windows — makes the dialog surface in focus.
    //
    // `prompting` serializes the request: a second one while a dialog is already
    // up returns false instead of stacking another SecurityAgent dialog (what a
    // frustrated retry used to do, and what was linked to the instability in
    // issue #63). Every caller already treats false as "permission not granted".
    private static let promptLock = NSLock()
    private static var prompting = false

    static func runSync(_ command: String, prompt: String) -> Bool {
        promptLock.lock()
        if prompting {
            promptLock.unlock()
            return false
        }
        prompting = true
        promptLock.unlock()
        defer {
            promptLock.lock()
            prompting = false
            promptLock.unlock()
        }

        bringAppToFront()
        let source = "do shell script \(appleScriptString(command)) with administrator privileges with prompt \(appleScriptString(prompt))"
        return Shell.run("/usr/bin/osascript", ["-e", source]).status == 0
    }

    static func run(_ command: String, prompt: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            completion(runSync(command, prompt: prompt))
        }
    }

    /// Brings the app forward so the administrator dialog opens in focus. Safe
    /// from any thread: hops to the main thread when it is not already on it.
    private static func bringAppToFront() {
        if Thread.isMainThread {
            NSApp.activate(ignoringOtherApps: true)
        } else {
            DispatchQueue.main.sync {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        Thread.sleep(forTimeInterval: 0.12)
    }

    private static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// NOPASSWD rule restricted to `pmset disablesleep 0/1`, so closed-lid mode can
/// toggle without asking for the administrator password every time.
/// The password is asked once, when installing (or removing) the rule.
enum Sudoers {
    static let rulePath = "/etc/sudoers.d/vorssaint-clamshell"
    // Rule files written under earlier names; removed whenever the rule is
    // (re)installed or removed, so the closed-lid permission migrates without an
    // extra password prompt.
    private static let legacyRulePaths = [
        "/etc/sudoers.d/vorssaint-utils-clamshell",
        "/etc/sudoers.d/vorss-clamshell",
    ]

    private static var safeUser: String? {
        let user = NSUserName()
        let valid = user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
        return valid ? user : nil
    }

    /// Serializes every touch of the SleepDisabled state. The probe below
    /// re-applies the value it just read; racing it against a concurrent
    /// disable (launch recovery, a session ending) could resurrect a stale
    /// "1" after the flag was already cleared, leaving lid sleep off with
    /// nothing left to repair it.
    private static let sleepStateQueue = DispatchQueue(label: "com.vorssaint.utils.pmset-state")

    /// Proves the passwordless path by running it: re-applying the current
    /// SleepDisabled state through `sudo -n` changes nothing on the system and
    /// exercises the exact call the feature makes. Listing checks (`sudo -l`)
    /// reported the rule as ready on Macs where the real call still asked for
    /// a password, which put every toggle behind a prompt (issue #269).
    static func isConfigured() -> Bool {
        sleepStateQueue.sync {
            let report = Shell.run("/usr/bin/pmset", ["-g"])
            guard report.status == 0 else { return false }
            return pmsetDisableSleepOnQueue(SudoersSupport.sleepDisabled(inPmsetOutput: report.output))
        }
    }

    /// Whether any rule file (current or legacy name) is visible on disk.
    /// Uninstall offers the removal prompt from this instead of `isConfigured`,
    /// so a rule that stopped working still gets cleaned up.
    static var ruleFilesPresent: Bool {
        ([rulePath] + legacyRulePaths).contains { FileManager.default.fileExists(atPath: $0) }
    }

    static func install(completion: @escaping (Bool) -> Void) {
        guard let user = safeUser else {
            completion(false)
            return
        }
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 1, /usr/bin/pmset disablesleep 0"
        // Clear any earlier-named rule first, then write and validate the new one
        // (a failed check rolls back). Same password prompt either way.
        let legacy = legacyRulePaths.joined(separator: " ")
        let command = "mkdir -p /etc/sudoers.d && chmod 0755 /etc/sudoers.d && rm -f \(legacy) && echo '\(rule)' > \(rulePath) && chmod 0440 \(rulePath) && /usr/sbin/visudo -c -f \(rulePath) || { rm -f \(rulePath); exit 1; }"
        AdminShell.run(command, prompt: L10n.shared.s.adminPromptSudoersInstall) { ok in
            completion(ok && isConfigured())
        }
    }

    static func remove(completion: @escaping (Bool) -> Void) {
        // Also removes the rules left behind by earlier app names.
        let all = ([rulePath] + legacyRulePaths).joined(separator: " ")
        AdminShell.run("rm -f \(all)",
                       prompt: L10n.shared.s.adminPromptSudoersRemove) { ok in
            completion(ok)
        }
    }

    /// Toggles sleep through the password-free path. Fails silently
    /// (returns false) when the rule is not installed.
    @discardableResult
    static func pmsetDisableSleep(_ on: Bool) -> Bool {
        sleepStateQueue.sync { pmsetDisableSleepOnQueue(on) }
    }

    private static func pmsetDisableSleepOnQueue(_ on: Bool) -> Bool {
        Shell.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", on ? "1" : "0"]).status == 0
    }
}

/// Sends Apple Events to another app IN-PROCESS (via NSAppleScript) instead of
/// spawning `osascript`. The Automation consent is then attributed to THIS app —
/// so it stays granted across updates, is re-requested if it was lost, and the
/// first-run consent prompt is never killed by a watchdog. It is the same
/// per-target Automation permission the features already required; nothing new is
/// requested. Call these OFF the main thread, so a slow target never blocks the
/// UI or the event taps (the calls block their thread until the target replies).
enum AppleScriptRunner {
    /// True when this app may script `bundleID`. Undetermined → shows the system
    /// prompt (attributed to this app); granted → returns at once; denied →
    /// false without nagging.
    @discardableResult
    static func consentToAutomate(bundleID: String) -> Bool {
        var target = AEAddressDesc()
        let created = bundleID.withCString { ptr in
            AECreateDesc(typeApplicationBundleID, ptr, bundleID.utf8.count, &target)
        }
        guard created == noErr else { return false }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, true) == noErr
    }

    /// Runs the AppleScript in this process. Returns whether it succeeded and the
    /// result string (or the error message on failure). Sending the event in
    /// process itself triggers the Automation prompt when consent is undetermined.
    @discardableResult
    static func run(_ source: String) -> (ok: Bool, output: String) {
        let result = runDetailed(source)
        return (result.ok, result.ok ? result.output : result.message)
    }

    /// Same as `run`, keeping the AppleScript error number so callers can tell
    /// a declined Automation consent (-1743/-1744) apart from a real failure.
    @discardableResult
    static func runDetailed(_ source: String) -> (ok: Bool, errorNumber: Int?, message: String, output: String) {
        guard let script = NSAppleScript(source: source) else { return (false, nil, "", "") }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return (false,
                    error[NSAppleScript.errorNumber] as? Int,
                    (error[NSAppleScript.errorMessage] as? String) ?? "",
                    "")
        }
        return (true, nil, "", result.stringValue ?? "")
    }

    /// Escapes a value for embedding inside an AppleScript double-quoted string.
    static func literal(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
