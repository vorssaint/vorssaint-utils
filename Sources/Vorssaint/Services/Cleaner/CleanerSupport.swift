// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure decision logic for the junk cleaner, kept free of AppKit and the file
/// system so the unit tests can pin every safety rule.
///
/// The cleaner's promise is that it never touches anything whose owner might
/// still be around: a file only becomes a leftover candidate when its name
/// maps to a bundle identifier, that identifier is not Apple's, not this
/// app's, and no installed app owns it or any of its prefixes. Everything
/// else it cleans (caches, logs) is content the owning app can rebuild.
enum CleanerSupport {
    /// What the cleaner can find, in display order. New cases append at the
    /// end: the raw value is a stable identity.
    enum Category: Int, CaseIterable, Identifiable {
        case leftovers, loginItems, caches, logs, developer, trash, deviceBackups

        var id: Int { rawValue }
    }

    /// Cross product infrastructure that ships embedded in other vendors'
    /// apps (updaters, crash reporters, analytics): their folders belong to
    /// whatever installed apps carry them and can never be attributed to an
    /// uninstalled one, so they are never junk owners.
    static let sharedInfrastructurePrefixes = [
        "org.sparkle-project", "com.plausiblelabs", "com.crashlytics",
        "com.segment", "io.sentry", "com.amplitude", "com.rollbar",
        "com.google.keystone", "com.google.softwareupdate", "org.cups",
        "org.swift",
    ]

    /// Bundle identifiers that must never be treated as junk owners, no
    /// matter what the installed-apps oracle says: the operating system's
    /// own domains (in any wrapping, including team prefixed group names
    /// and systemgroup entries), this very app, and shared infrastructure.
    static func isProtectedBundleID(_ id: String) -> Bool {
        let lowered = id.lowercased()
        let wrapped = "." + lowered + "."
        if wrapped.contains(".com.apple.") || wrapped.contains(".com.vorssaint.")
            || wrapped.contains(".developer.apple.") || wrapped.contains(".is.workflow.") {
            return true
        }
        if lowered == "com.apple" || lowered.hasPrefix("vorss.") {
            return true
        }
        return sharedInfrastructurePrefixes.contains { lowered.hasPrefix($0) }
    }

    /// Whether a Library entry name is shaped like a reverse DNS bundle
    /// identifier (at least three dot separated components of plain
    /// identifier characters). Anything else, including a plain vendor folder,
    /// is never matched by name because it is too easy to hit living app data.
    static func looksLikeBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        for part in parts {
            guard !part.isEmpty else { return false }
            for scalar in part.unicodeScalars {
                let ok = (scalar >= "a" && scalar <= "z") || (scalar >= "A" && scalar <= "Z")
                    || (scalar >= "0" && scalar <= "9") || scalar == "-" || scalar == "_"
                guard ok else { return false }
            }
        }
        return true
    }

    /// Extracts the owning bundle identifier from a Library entry name:
    /// strips the well known wrappers (group. prefix) and payload suffixes
    /// (.plist, .savedState, .binarycookies) and validates the shape.
    /// Returns nil when the name does not clearly belong to one bundle.
    static func bundleIDCandidate(fromEntryName rawName: String) -> String? {
        // A UUID anywhere in the name (per host preferences, update stamps)
        // makes the owner unattributable; such entries are never candidates.
        guard !containsUUIDComponent(rawName) else { return nil }
        var name = rawName
        for suffix in [".plist", ".savedState", ".binarycookies"] where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        for prefix in ["group.", "systemgroup."] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        guard looksLikeBundleID(name) else { return nil }
        return name
    }

    /// Whether the name carries a dashed UUID (8-4-4-4-12 hex groups).
    static func containsUUIDComponent(_ name: String) -> Bool {
        let lengths = [8, 4, 4, 4, 12]
        let scalars = Array(name.unicodeScalars)
        var index = 0
        while index < scalars.count {
            var cursor = index
            var matched = true
            for (group, length) in lengths.enumerated() {
                for _ in 0..<length {
                    guard cursor < scalars.count, isHexDigit(scalars[cursor]) else { matched = false; break }
                    cursor += 1
                }
                guard matched else { break }
                if group < lengths.count - 1 {
                    guard cursor < scalars.count, scalars[cursor] == "-" else { matched = false; break }
                    cursor += 1
                }
            }
            if matched { return true }
            index += 1
        }
        return false
    }

    private static func isHexDigit(_ scalar: Unicode.Scalar) -> Bool {
        (scalar >= "0" && scalar <= "9") || (scalar >= "a" && scalar <= "f") || (scalar >= "A" && scalar <= "F")
    }

    /// Namespaces whose second component names a code hosting site, where
    /// unrelated developers share the prefix; two matching components mean
    /// nothing there.
    private static let hostingNamespaces: Set<String> = [
        "github", "gitlab", "bitbucket", "sourceforge", "googlecode",
    ]

    /// Whether a candidate shares a vendor namespace (its first two dot
    /// components) with any installed identifier. Vendors ship suites and
    /// updaters under one namespace with sibling identifiers that no exact
    /// family match can connect (an installed com.maker.editor keeps
    /// com.maker.updater alive), so the whole namespace counts as owned
    /// while anything of that vendor is installed.
    static func sharesVendorNamespace(candidate: String, withInstalled installed: Set<String>) -> Bool {
        guard let namespacePrefix = vendorNamespace(of: candidate.lowercased()) else { return false }
        return installed.contains { vendorNamespace(of: $0) == namespacePrefix }
    }

    private static func vendorNamespace(of id: String) -> String? {
        let parts = id.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let vendor = String(parts[1])
        guard !hostingNamespaces.contains(vendor) else { return nil }
        return parts[0] + "." + parts[1]
    }

    /// Whether an installed bundle identifier owns this candidate. Ownership
    /// is the exact id or a dot separated prefix in either direction, so
    /// com.maker.App keeps com.maker.App.helper (embedded helpers register
    /// no app of their own) and com.maker keeps com.maker.App.
    static func isOwned(candidate: String, byInstalled installed: Set<String>) -> Bool {
        let lowered = candidate.lowercased()
        if installed.contains(lowered) { return true }
        for id in installed {
            if lowered.hasPrefix(id + ".") || id.hasPrefix(lowered + ".") { return true }
        }
        return false
    }

    /// The executables a launchd property list points at, in the order they
    /// should be checked. A plist whose every referenced executable is gone
    /// is an orphan: the app that installed it no longer exists.
    static func executablePaths(inLaunchPlist plist: [String: Any]) -> [String] {
        var paths: [String] = []
        if let program = plist["Program"] as? String, !program.isEmpty {
            paths.append(program)
        }
        if let arguments = plist["ProgramArguments"] as? [Any],
           let first = arguments.first as? String, !first.isEmpty {
            paths.append(first)
        }
        // BundleProgram is relative to the bundle the plist ships in; when it
        // reaches the launchd folders it travels with an absolute sibling, so
        // a bare relative path cannot be resolved and is ignored here.
        if let bundleProgram = plist["BundleProgram"] as? String, bundleProgram.hasPrefix("/") {
            paths.append(bundleProgram)
        }
        return paths
    }

    /// Whether an orphaned launchd plist may be offered for cleaning at all.
    /// Apple's own agents are system state, and anything that does not name
    /// an executable is undecidable, so both stay untouched.
    static func launchPlistIsRemovableOrphan(label: String?,
                                             executables: [String],
                                             executableExists: (String) -> Bool) -> Bool {
        if let label, isProtectedBundleID(label) { return false }
        guard !executables.isEmpty else { return false }
        return !executables.contains(where: executableExists)
    }
}
