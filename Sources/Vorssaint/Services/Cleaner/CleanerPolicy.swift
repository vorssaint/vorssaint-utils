// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Every judgment call of the cleaner in one place: what starts checked in
/// the review list and what never even appears. The rule of thumb is that a
/// find is pre checked only when the evidence is strong and rebuilding the
/// data is cheap; anything based on guessing starts unchecked and waits for
/// the user's eye.
enum CleanerPolicy {
    /// Leftovers are an educated guess against the installed apps oracle, so
    /// they start unchecked and the interface explains what they are.
    static let precheckLeftovers = false

    /// An orphaned startup item needs two independent signals (every
    /// executable gone AND no living owner for its label), so these start
    /// checked; they are the ghosts in Login Items and Extensions.
    static let precheckLoginItems = true

    /// Logs are diagnostic text apps rewrite freely.
    static let precheckLogs = true

    /// Build products and simulator caches regenerate on the next build.
    static let precheckDeveloper = true

    /// Relative to the home folder. Only ever offered when they exist. The
    /// DeviceSupport folders are debug symbol caches Xcode rebuilds on the
    /// next device connection; they quietly grow to tens of gigabytes and
    /// are a classic slice of the storage macOS files under "Other".
    static let developerJunkPaths: [String] = [
        "/Library/Developer/Xcode/DerivedData",
        "/Library/Developer/Xcode/DocumentationCache",
        "/Library/Developer/CoreSimulator/Caches",
        "/Library/Developer/Xcode/iOS DeviceSupport",
        "/Library/Developer/Xcode/watchOS DeviceSupport",
        "/Library/Developer/Xcode/tvOS DeviceSupport",
    ]

    /// Device backups are the user's safety net: enormous, ancient, and the
    /// other classic tenant of "Other" storage, but never a machine's call
    /// to delete. Every find waits unchecked for the user's eye.
    static let precheckDeviceBackups = false

    /// Cache folders that never appear in the list at all: this app's own
    /// data and entries known to break things when removed (audio output
    /// loss, blank Settings panels, service sign outs, plugin licensing),
    /// each learned the hard way by the cleaners that came before.
    private static let hiddenCachePrefixes = [
        "com.vorssaint",
        "CloudKit", "com.apple.bird",
        "com.apple.coreaudio", "com.apple.audio.", "coreaudiod",
        "com.apple.systempreferences", "com.apple.controlcenter",
        "com.apple.finder", "com.apple.dock",
        "com.apple.FontRegistry", "com.apple.ATS",
        "com.apple.akd", "com.apple.AuthKit",
        "com.paceap.", "com.native-instruments", "com.fabfilter",
    ]

    /// Third party caches whose content the user paid bandwidth or setup
    /// for (offline media, model and browser downloads): shown, never pre
    /// checked.
    private static let sensitiveCachePrefixes = [
        "com.spotify.client",
        "ms-playwright",
    ]

    static func isExcludedCacheEntry(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return hiddenCachePrefixes.contains { lowered.hasPrefix($0.lowercased()) }
    }

    /// Plain named cache folders known to be pure downloads or build junk;
    /// anything plain named outside this list stays unchecked because bare
    /// names cannot be attributed (some are the system's own, like the maps
    /// tile cache).
    private static let safePlainNameCaches: Set<String> = [
        "homebrew", "pip", "node-gyp", "yarn", "npm", "google",
        "electron", "cypress", "typescript", "puppeteer",
    ]

    /// Apple's own caches are safe to remove but the system rebuilds them
    /// eagerly (slower first launches, re indexing), so they are listed for
    /// the willing and pre checked for nobody. Third party caches start
    /// checked unless they hold content worth keeping, and plain named
    /// folders only when they are known download or build caches.
    static func precheckCacheEntry(_ name: String) -> Bool {
        let lowered = name.lowercased()
        if sensitiveCachePrefixes.contains(where: { lowered.hasPrefix($0.lowercased()) }) { return false }
        if CleanerSupport.looksLikeBundleID(name) {
            return !lowered.hasPrefix("com.apple.")
        }
        return safePlainNameCaches.contains(lowered)
    }
}
