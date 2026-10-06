// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The single write path for the Dock preferences the quick toggles own.
///
/// An `enum` rather than a class: there is exactly one Dock preference domain
/// and nothing to configure, so a stored instance would only be a second object
/// for the two features to disagree about. Every method is a static call and
/// nothing here outlives the call that made it.
///
/// Every write is a round trip, not a fire: read, write, commit, restart the
/// Dock, read back and confirm. A preference write the app never verifies is a
/// write that silently does nothing, and the row would report a change that
/// never reached the Dock. Reporting `false` instead lets the caller say so.
///
/// `UserDefaults(suiteName:)` is deliberately not used. It caches the
/// preference file at launch and only sees its own writes, so a read-back
/// straight after a write answers the cache rather than the disk — exactly the
/// confirmation this type exists to provide. CoreFoundation goes to the file
/// every time.
///
/// Nothing here can leave a half-applied preference. The value is committed to
/// disk before the Dock is touched, so a crash at any point leaves a complete,
/// valid system preference the user can always change back in System Settings.
enum DockPreferenceWriter {
    /// Reads one Dock preference after forcing a synchronise first, or nil when
    /// the key is unset or unreadable.
    static func read(_ key: String) -> Any? {
        let domain = QuickTogglesSupport.dockDomain as CFString
        // Force the on-disk file into the cache first. Without this the read
        // answers whatever was cached when the process started, which is how a
        // confirmation ends up confirming nothing at all.
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            return nil
        }
        return CFPreferencesCopyValue(key as CFString,
                                      domain,
                                      kCFPreferencesCurrentUser,
                                      kCFPreferencesAnyHost)
    }

    /// Writes, commits, restarts the Dock, then reads back and reports whether
    /// the value the Dock will actually use is the one we wrote.
    @discardableResult
    static func write(_ key: String, number value: Int) -> Bool {
        write(key, value: NSNumber(value: value))
    }

    /// The reveal delay is a fraction of a second, so it needs the same round
    /// trip with a value that survives the truncation the integer overload
    /// would apply. A stored `0` and a written `0` are the same delay, but a
    /// stored `0.2` written as `0` is not, which is the one case that matters.
    @discardableResult
    static func write(_ key: String, seconds value: Double) -> Bool {
        write(key, value: NSNumber(value: value))
    }

    private static func write(_ key: String, value: NSNumber) -> Bool {
        let domain = QuickTogglesSupport.dockDomain as CFString
        let name = key as CFString

        // A key a configuration profile owns cannot be changed by writing over
        // it: the profile wins on the next sync and the user is left with an
        // error they have no way to fix. Refuse instead, and let the row report
        // the failure honestly.
        guard !CFPreferencesAppValueIsForced(name, domain) else { return false }

        CFPreferencesSetValue(name, value, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        // Commit to disk. This has to succeed and has to happen before the
        // restart: a value only in the cache is lost if the Dock is killed while
        // it is still there, which would leave the toggle claiming a change the
        // system never made.
        guard CFPreferencesAppSynchronize(domain) else { return false }

        // Last, and nothing above it can trap: the Dock is the last thing told.
        // A preference the Dock reads only at launch stays a file edit until
        // the process restarts, and a terminated Dock is relaunched by the
        // system, so this is the whole of "apply now". It runs even when the
        // stored value already matched, because the running Dock can still be
        // holding an older one.
        restartDock()

        // Read back only after the commit and the restart: confirming earlier
        // would be checking the app's own cache, which is the one thing the
        // round trip exists to avoid.
        return confirms(key, wrote: value)
    }

    /// Whether the value the Dock will read is the one that was written. The
    /// preference layer hands a number back as an NSNumber, a Double or a
    /// decimal string depending on what wrote it, so the comparison goes
    /// through the same parser the toggle reads state with.
    private static func confirms(_ key: String, wrote: NSNumber) -> Bool {
        guard let written = QuickTogglesSupport.dockNumber(wrote) else { return false }
        guard let stored = QuickTogglesSupport.dockNumber(read(key)) else { return false }
        return stored == written
    }

    /// A terminated Dock counts as an unexpected exit, so the system starts it
    /// again by itself; a clean quit would leave it closed.
    private static func restartDock() {
        _ = Shell.run("/usr/bin/killall", ["Dock"])
    }
}
