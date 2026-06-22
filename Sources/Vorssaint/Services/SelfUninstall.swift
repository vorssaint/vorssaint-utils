// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ServiceManagement

/// Clears the app's own footprint on the system, for a clean uninstall.
///
/// Security note: every operation here is scoped to THIS app and nothing else.
/// The bundle id is a constant identifier (never user input), so the `tccutil`
/// call cannot be steered elsewhere; the login item and sudoers rule are the
/// app's own; the preference and saved-state paths are built from the app's own
/// bundle id; and the only thing deleted is the app's own bundle, which is moved
/// to the Trash (reversible). Nothing leaves the machine.
enum SelfUninstall {
    private static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.vorssaint.utils" }

    /// Resets every TCC permission the app holds, drops the login item and the
    /// optional closed-lid sudoers rule, and leaves the app in place. Calls back
    /// on the main queue. Used by "Clear all permissions".
    static func clearPermissions(completion: @escaping () -> Void) {
        // Stop every input interceptor FIRST (on the main thread), then revoke.
        // Revoking Accessibility while a tap is live makes the tap callback hang
        // on an AX call and freezes the whole machine's input — see the note on
        // `suspendInputInterceptors`.
        DispatchQueue.main.async {
            suspendInputInterceptors()
            DispatchQueue.global(qos: .userInitiated).async {
                detachFromSystem()
                removeSudoersRuleIfPresent {           // may show one admin prompt
                    resetTCC()
                    DispatchQueue.main.async(execute: completion)
                }
            }
        }
    }

    /// Clears permissions, removes preferences and saved state, sends the app
    /// bundle to the Trash and quits. Used by "Uninstall Vorssaint completely".
    static func uninstallCompletely() {
        DispatchQueue.main.async {
            suspendInputInterceptors()
            DispatchQueue.global(qos: .userInitiated).async {
                detachFromSystem()
                removeSudoersRuleIfPresent {
                    resetTCC()
                    removePreferences()
                    DispatchQueue.main.async { trashOwnBundleAndQuit() }
                }
            }
        }
    }

    // MARK: - Steps (each scoped to this app only)

    /// Tears down every Accessibility-backed input interceptor. MUST run on the
    /// main thread and BEFORE permissions are reset: otherwise revoking
    /// Accessibility while an event tap is still live makes the tap's callback
    /// block on an AX call, which stalls the OS input queue and freezes the
    /// keyboard and clicks (only the mouse cursor keeps moving). Each `stop`/
    /// `suspend`/`deactivate` is idempotent, so calling it when a service is
    /// already off is a no-op.
    private static func suspendInputInterceptors() {
        ScrollInverter.shared.suspend()
        WindowMaximizer.shared.stop()
        AppSwitcher.shared.suspend()
        DockPreviewService.shared.stop()
        AutoQuitService.shared.suspend()
        FinderCutPaste.shared.suspend()
        CleaningModeManager.shared.deactivate()
    }

    private static func detachFromSystem() {
        // Restore normal sleep if a closed-lid session left it disabled.
        if UserDefaults.standard.bool(forKey: DefaultsKey.sleepDisabledFlag) {
            _ = Sudoers.pmsetDisableSleep(false)
        }
        // Unregister the login item (scoped to our bundle id).
        try? SMAppService.mainApp.unregister()
    }

    private static func removeSudoersRuleIfPresent(then: @escaping () -> Void) {
        guard Sudoers.isConfigured() else { then(); return }
        Sudoers.remove { _ in then() }            // shows the admin password prompt
    }

    /// `tccutil reset All <bundle id>` clears Accessibility, Screen Recording,
    /// Full Disk Access, Automation and the rest, for this app only. The bundle
    /// id is a constant, so there is nothing to inject.
    private static func resetTCC() {
        _ = Shell.run("/usr/bin/tccutil", ["reset", "All", bundleID])
    }

    private static func removePreferences() {
        let id = bundleID
        UserDefaults.standard.removePersistentDomain(forName: id)
        let home = NSHomeDirectory()
        try? FileManager.default.removeItem(atPath: "\(home)/Library/Preferences/\(id).plist")
        try? FileManager.default.removeItem(atPath: "\(home)/Library/Saved Application State/\(id).savedState")
    }

    /// Moves the app's own bundle to the Trash after it quits, then quits. The
    /// path is the running app's own location, checked to be an `.app`, so this
    /// can only ever remove this app. A detached helper does the move so the
    /// bundle is not mutated while it is running.
    private static func trashOwnBundleAndQuit() {
        let app = Bundle.main.bundlePath
        guard app.hasSuffix(".app"), app != "/" else { NSApp.terminate(nil); return }
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/sh
        APP="$1"; PID="$2"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        TRASH="$HOME/.Trash"
        /bin/mkdir -p "$TRASH" 2>/dev/null || true
        BASE="$(basename "$APP")"
        DEST="$TRASH/$BASE"
        n=2
        while [ -e "$DEST" ]; do DEST="$TRASH/${BASE%.app} $n.app"; n=$((n+1)); done
        # Reversible move to the Trash. If a direct move fails, ask Finder to do
        # the same Trash operation so it can present the standard admin prompt.
        if ! /bin/mv "$APP" "$DEST" 2>/dev/null; then
            /usr/bin/osascript - "$APP" <<'APPLESCRIPT'
        on run argv
            tell application "Finder" to delete POSIX file (item 1 of argv)
        end run
        APPLESCRIPT
        fi
        if [ -d "$APP" ]; then /usr/bin/open "$APP" 2>/dev/null; fi
        /bin/rm -f "$0"
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-uninstall-\(pid)-\(UUID().uuidString).sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = [scriptURL.path, app, "\(pid)"]
            try task.run()
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: scriptURL)
        }
    }
}
