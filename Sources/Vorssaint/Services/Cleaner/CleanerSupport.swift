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
        case leftovers, loginItems, caches, logs, developer, trash, deviceBackups, screenshots

        var id: Int { rawValue }
    }

    /// Cancellation for one scan. The main thread cancels it; the scan's
    /// background loop reads it between categories and stops early instead
    /// of walking every location for a result nobody is waiting for.
    final class ScanCancellation {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
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
        // A domain ends at a dot: com.segment covers com.segment.analytics,
        // not the unrelated com.segmentfault.
        return sharedInfrastructurePrefixes.contains { lowered == $0 || lowered.hasPrefix($0 + ".") }
    }

    /// Whether a Library entry name is shaped like a reverse DNS bundle
    /// identifier (at least two dot separated components of plain
    /// identifier characters). Anything else, including a plain vendor folder,
    /// is never matched by name because it is too easy to hit living app data.
    static func looksLikeBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
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

    /// Apple team identifiers are ten uppercase letters and digits. Used to
    /// drop a leading team prefix so a group container names the app, not
    /// the developer account.
    static func isTeamIdentifier(_ raw: String) -> Bool {
        let value = raw.uppercased()
        guard raw == value, value.count == 10 else { return false }
        return value.unicodeScalars.allSatisfy {
            ($0 >= "A" && $0 <= "Z") || ($0 >= "0" && $0 <= "9")
        }
    }

    /// Extracts the owning bundle identifier from a Library entry name:
    /// strips the well known wrappers (group. prefix, a leading team ID)
    /// and payload suffixes (.plist, .savedState, .binarycookies, preference
    /// panes, plugins, a trailing ByHost UUID) and validates the shape.
    /// Returns nil when the name does not clearly belong to one bundle.
    static func bundleIDCandidate(fromEntryName rawName: String) -> String? {
        var name = rawName
        // An entry has one extension. Removing every match in turn also took
        // an identifier's last component when it is spelled like one, so
        // com.vendor.Service.plist was credited to com.vendor.
        let lowered = name.lowercased()
        if let suffix = [".plist", ".savedState", ".binarycookies", ".prefPane",
                         ".qlgenerator", ".mdimporter", ".service", ".appex",
                         ".plugin", ".webplugin", ".saver", ".colorPicker",
                         ".wdgt", ".app", ".framework", ".component", ".vst",
                         ".vst3", ".clap", ".dpm", ".aaxplugin", ".dictionary",
                         ".safariextz", ".mailbundle"].first(where: { lowered.hasSuffix($0.lowercased()) }) {
            name.removeLast(suffix.count)
        }
        name = strippingTrailingUUIDComponent(name)
        for prefix in ["group.", "systemgroup."] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        let parts = name.split(separator: ".")
        if parts.count >= 3, isTeamIdentifier(String(parts[0])) {
            name = parts.dropFirst().joined(separator: ".")
        }
        return isAttributableBundleID(name) ? name : nil
    }

    /// An owner an entry can be credited to: dotted, every component naming
    /// something, and no UUID left in it (update stamps, mid-name hosts).
    /// Checked again before removal on the owner itself, which may end in a
    /// word an entry name would carry as its extension, as io.app does.
    static func isAttributableBundleID(_ name: String) -> Bool {
        !containsUUIDComponent(name) && looksLikeBundleID(name)
            && name.split(separator: ".").allSatisfy { part in
                part.unicodeScalars.contains {
                    ($0 >= "a" && $0 <= "z") || ($0 >= "A" && $0 <= "Z")
                }
            }
    }

    static func isDirectChild(_ url: URL, of root: URL) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent().path
            == root.standardizedFileURL.path
    }

    /// Last path component of a ByHost preference: the Mac's UUID, not the
    /// owner. Dropped only when it is the whole trailing component.
    static func strippingTrailingUUIDComponent(_ name: String) -> String {
        guard let lastDot = name.lastIndex(of: ".") else { return name }
        let last = String(name[name.index(after: lastDot)...])
        guard last.count == 36, containsUUIDComponent(last) else { return name }
        return String(name[..<lastDot])
    }

    /// Shared-container wrappers need signed entitlement evidence. The
    /// general Cleaner has no selected signature, so it leaves them alone.
    static func hasSharedContainerWrapper(_ rawName: String) -> Bool {
        let lowered = rawName.lowercased()
        if lowered.hasPrefix("group.") || lowered.hasPrefix("systemgroup.") {
            return true
        }
        guard let first = rawName.split(separator: ".").first else { return false }
        return isTeamIdentifier(String(first))
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
    /// A bare command such as `sh` runs from launchd's search path, which
    /// this app cannot see from its own folder; it says nothing about an app
    /// being gone, so only absolute paths count.
    static func executablePaths(inLaunchPlist plist: [String: Any]) -> [String] {
        var paths: [String] = []
        if let program = plist["Program"] as? String, program.hasPrefix("/") {
            paths.append(program)
        }
        if let arguments = plist["ProgramArguments"] as? [Any],
           let first = arguments.first as? String, first.hasPrefix("/") {
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

    // MARK: - Forgotten screenshots

    /// Written by macOS on every capture it saves (a binary property list
    /// holding true). A file proves it is a screenshot with this, so nothing
    /// is ever guessed from a name, and a random image beside it never counts.
    static let screenCaptureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"

    /// Where macOS keeps a file's last opened date (the Spotlight
    /// kMDItemLastUsedDate): a timespec, seconds then nanoseconds.
    static let lastUsedDateAttribute = "com.apple.lastuseddate#PS"

    /// The folder macOS saves screenshots to: the location picked in the
    /// Screenshot app, which may start with a tilde, or the Desktop when it
    /// was never changed.
    static func screenshotFolder(location: String?, home: String) -> String {
        let trimmed = location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return home + "/Desktop" }
        if trimmed == "~" { return home }
        if trimmed.hasPrefix("~/") { return home + trimmed.dropFirst() }
        guard trimmed.hasPrefix("/") else { return home + "/Desktop" }
        return trimmed
    }

    static func isScreenCaptureFlag(_ data: Data) -> Bool {
        guard let value = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
            return false
        }
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.intValue == 1 }
        return false
    }

    static func lastUsedDate(fromAttribute data: Data) -> Date? {
        guard data.count >= 16 else { return nil }
        var seconds: Int64 = 0
        var nanoseconds: Int64 = 0
        for index in 0..<8 {
            seconds |= Int64(data[data.startIndex + index]) << (8 * index)
            nanoseconds |= Int64(data[data.startIndex + 8 + index]) << (8 * index)
        }
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanoseconds) / 1e9)
    }

    /// The clock time macOS ends a capture name with, its hour, and whatever
    /// follows: on a twelve hour Mac the day period, and otherwise nothing.
    /// The tail is captured whole rather than as non-digits, because a few
    /// locales write a day period that carries a digit of its own.
    private static let captureTimePattern = try? NSRegularExpression(
        pattern: #"(\d{1,2})\.\d{2}\.\d{2}(.*)$"#)

    /// The spaces macOS puts before a day period. Only these are dropped when
    /// comparing: treating the whole whitespace class as blank would swallow
    /// a zero width character somebody pasted into a name and leave the empty
    /// tail of a file nobody touched.
    private static let captureSpaces = CharacterSet(charactersIn: " \u{00A0}\u{202F}")

    /// Every day period macOS could have written into a capture name, in any
    /// language it offers, reduced so that "p. m." and "p.m." compare equal.
    /// Asking the system for them is what separates a real day period from a
    /// short word somebody typed: "ui" and "ok" are not in here.
    private static let dayPeriodSymbols: Set<String> = {
        var symbols: Set<String> = []
        for identifier in Locale.availableIdentifiers {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: identifier)
            if let morning = formatter.amSymbol { symbols.insert(comparableDayPeriod(morning)) }
            if let afternoon = formatter.pmSymbol { symbols.insert(comparableDayPeriod(afternoon)) }
        }
        symbols.remove("")
        return symbols
    }()

    /// Lowercased with the spacing removed, and nothing else: one locale
    /// writes "p. m." where another writes "p.m.", so spaces cannot count,
    /// while every other mark has to survive. Dropping punctuation here would
    /// erase the very thing a rename adds, and a file ending in "!" or an
    /// emoji would reduce to the empty tail of an untouched name.
    static func comparableDayPeriod(_ text: String) -> String {
        text.lowercased().unicodeScalars.reduce(into: "") { result, scalar in
            if !captureSpaces.contains(scalar) { result.unicodeScalars.append(scalar) }
        }
    }

    /// Whether what trails the capture time is a day period macOS writes after
    /// that particular hour, or nothing at all. A day period only exists on a
    /// twelve hour clock, so an hour past twelve has to end on the time
    /// itself; without that, a single letter that some locale happens to use
    /// for morning would pass as a suffix on a twenty four hour name.
    static func isCaptureDayPeriod(_ text: String, hour: Int) -> Bool {
        let comparable = comparableDayPeriod(text)
        if comparable.isEmpty { return true }
        guard (1...12).contains(hour) else { return false }
        return dayPeriodSymbols.contains(comparable)
    }

    /// The collision suffix macOS appends when a name is already taken.
    private static let captureCopyIndexPattern = try? NSRegularExpression(
        pattern: #"\s*\(\d+\)$"#)

    /// Whether a capture still carries the name macOS gave it, which always
    /// holds the capture day and ends on the capture time. A renamed file is a
    /// decision the user made about it, so it never counts as forgotten, and
    /// that has to include a rename that keeps the original name and adds to
    /// it, which is what duplicating a capture in Finder produces
    /// ("... 14.13.20 copy.png"). What follows the time therefore has to be a
    /// day period macOS itself writes, asked of the system rather than guessed
    /// at by length, so "14.13.20 ui.png" is a rename like any other. The
    /// check stays deliberately narrow: a capture saved without a date and a
    /// time in its name is simply skipped.
    static func screenshotKeepsDefaultName(_ name: String, created: Date,
                                           timeZone: TimeZone = .current) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard name.contains(formatter.string(from: created)) else { return false }

        let base = strippingCaptureCopyIndex((name as NSString).deletingPathExtension)
        guard let captureTimePattern else { return true }
        let range = NSRange(base.startIndex..<base.endIndex, in: base)
        guard let match = captureTimePattern.firstMatch(in: base, range: range),
              NSMaxRange(match.range) == range.length,
              let hourRange = Range(match.range(at: 1), in: base),
              let hour = Int(base[hourRange]),
              let trailing = Range(match.range(at: 2), in: base) else { return false }
        return isCaptureDayPeriod(String(base[trailing]), hour: hour)
    }

    static func strippingCaptureCopyIndex(_ name: String) -> String {
        guard let captureCopyIndexPattern else { return name }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard let match = captureCopyIndexPattern.firstMatch(in: name, range: range),
              NSMaxRange(match.range) == range.length,
              let suffix = Range(match.range, in: name) else { return name }
        return String(name[name.startIndex..<suffix.lowerBound])
    }

    /// A capture is forgotten when nothing happened to it for `days`: not
    /// taken, changed or opened since then.
    static func isForgottenScreenshot(created: Date, modified: Date?, lastUsed: Date?,
                                      now: Date, days: Int) -> Bool {
        guard days > 0 else { return false }
        let latest = [created, modified, lastUsed].compactMap { $0 }.max() ?? created
        return now.timeIntervalSince(latest) >= TimeInterval(days) * 86_400
    }

}
