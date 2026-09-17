// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Completes the on-disk rename for installs carried over from a pre-2.5 build.
///
/// The in-app updater shipped in those builds installs the new version AT THE
/// OLD PATH ("/Applications/Vorssaint Utils.app"), so right after updating the
/// app is running from a bundle still named "Vorssaint Utils.app". We rename
/// that bundle to "Vorssaint.app" through a detached helper that runs only after
/// we quit (so a running bundle is never mutated), then relaunch. The bundle id
/// is unchanged, so granted permissions follow the bundle to its new path.
///
/// When we are already running as "Vorssaint.app", we instead retire a stray
/// old-named bundle left beside us (e.g. after a manual drag-install). That path
/// is safe by construction: the names differ, so the candidate can never be us.
///
/// Safety is the whole point of this file: every branch either renames in place
/// (an atomic same-volume move) or reopens an existing app. No branch can leave
/// the user without an app. An earlier version compared bundle URLs directly and
/// could mistake the just-updated app for a leftover; that is fixed by routing
/// the old-name case to a rename and comparing canonical paths everywhere else.
enum BundleMigration {
    private static let oldName = "Vorssaint Utils.app"
    private static let newName = "Vorssaint.app"

    /// Returns true when the app is about to quit and relaunch under the new
    /// name; the caller should then skip the rest of startup.
    @discardableResult
    static func run() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.lastPathComponent == oldName {
            return renameSelfAndRelaunch(from: bundleURL)
        }
        retireStrayOldBundle(running: bundleURL)
        return false
    }

    /// Renames our own bundle to the new name from a detached helper, then quits.
    private static func renameSelfAndRelaunch(from old: URL) -> Bool {
        let parent = old.deletingLastPathComponent()
        let oldPath = old.path
        let newPath = parent.appendingPathComponent(newName).path
        guard oldPath != newPath,
              FileManager.default.isWritableFile(atPath: parent.path) else { return false }

        let pid = ProcessInfo.processInfo.processIdentifier
        // Wait for us to quit, then rename in place (or, if the new name already
        // exists, drop the old one). ALWAYS reopen something at the end, so a
        // failed move can never leave the user with no app.
        let script = """
        #!/bin/sh
        OLD="$1"; NEW="$2"; PID="$3"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        if [ -d "$NEW" ]; then
            TRASH="$HOME/.Trash"
            /bin/mkdir -p "$TRASH" 2>/dev/null || true
            BASE="$(basename "$OLD")"
            DEST="$TRASH/$BASE"
            n=2
            while [ -e "$DEST" ]; do DEST="$TRASH/${BASE%.app} $n.app"; n=$((n+1)); done
            /bin/mv "$OLD" "$DEST" 2>/dev/null || true
            /usr/bin/open "$NEW"
        elif /bin/mv "$OLD" "$NEW" 2>/dev/null; then
            /usr/bin/open "$NEW"
        else
            /usr/bin/open "$OLD"
        fi
        /bin/rm -f "$0"
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-rename-\(pid)-\(UUID().uuidString).sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            // Its own session: the script waits for this app to exit before it
            // renames the bundle, which it can only do from outside our session.
            try DetachedProcess.spawn("/bin/sh", [scriptURL.path, oldPath, newPath, "\(pid)"])
        } catch {
            try? FileManager.default.removeItem(at: scriptURL)
            return false   // could not stage the rename; keep running as we are
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
        return true
    }

    /// Trashes a leftover old-named bundle next to us or in /Applications, only
    /// when it carries our bundle id and is provably not the running app.
    private static func retireStrayOldBundle(running: URL) {
        guard let myID = Bundle.main.bundleIdentifier else { return }
        let runningPath = running.resolvingSymlinksInPath().standardizedFileURL.path
        let dirs = Set([running.deletingLastPathComponent().path, "/Applications"])

        for dir in dirs {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(oldName)
            let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
            guard candidatePath != runningPath,                       // never ourselves
                  FileManager.default.fileExists(atPath: candidate.path),
                  Bundle(url: candidate)?.bundleIdentifier == myID else { continue }
            try? FileManager.default.trashItem(at: candidate, resultingItemURL: nil)
        }
    }
}
