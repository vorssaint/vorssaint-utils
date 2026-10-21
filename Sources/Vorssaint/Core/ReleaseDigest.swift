// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// How one change reads in the post-update window. The changelog section the
/// entry sits in decides it.
enum ReleaseChangeKind: Int, CaseIterable, Comparable {
    case new, changed, fixed

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// nil leaves the section out: the summary and credits, and sections that
    /// only restate notes found elsewhere ("Everything from 3.3.3", "Details").
    init?(section title: String) {
        let name = title.trimmingCharacters(in: .whitespaces).lowercased()
        if ["summary", "contributors", "docs", "details", "website", "links"].contains(name)
            || name.hasPrefix("everything from") {
            return nil
        }
        if name.hasPrefix("added") || name.hasSuffix("highlights") || name == "highlight" {
            self = .new
        } else if name == "fixed" || name == "hotfix" || name == "safety and reliability" {
            self = .fixed
        } else {
            self = .changed
        }
    }
}

/// One changelog entry with the features it is about.
struct ReleaseChange: Hashable {
    let text: String
    let kind: ReleaseChangeKind
    let version: String
    /// Empty for a change to the app as a whole.
    let features: [AppFeature]
    /// Names features and also something every person sees, such as the
    /// menu bar panel, so it is not hidden from people without the features.
    var alsoAppWide = false

    var isAppWide: Bool { features.isEmpty || alsoAppWide }

    /// The entry without its closing "Settings → …" path, and that path, so
    /// the window can show where an option lives on a line of its own. A path
    /// inside a sentence stays where it is.
    var parts: (text: String, settingsPath: String?) {
        Self.splitSettingsPath(text)
    }

    static func splitSettingsPath(_ text: String) -> (text: String, settingsPath: String?) {
        guard let start = text.range(of: "Settings →", options: .backwards) else { return (text, nil) }
        let before = text[..<start.lowerBound].trimmingCharacters(in: .whitespaces)
        guard !before.isEmpty, before.hasSuffix(".") else { return (text, nil) }
        var path = text[start.lowerBound...].trimmingCharacters(in: .whitespaces)
        if path.hasSuffix(".") { path.removeLast() }
        return (before, path)
    }
}

/// The changes between two installed versions, from the bundled changelog.
struct ReleaseDigest {
    let previousVersion: String?
    let version: String
    /// Versions whose notes are included, newest first.
    let versions: [String]
    /// The newest summary paragraph among those versions.
    let summary: String?
    /// Newest version first, in changelog order within a version.
    let changes: [ReleaseChange]

    /// Someone who skipped a long run of releases still gets a readable list.
    static let maximumVersions = 10

    /// Versions after `previous` up to and including `current`, newest first.
    /// A stable release restates its betas in short form, so a stable update
    /// reads only stable sections, and a beta update skips a stable section
    /// whose betas it already reads here or read before.
    static func versions(from previous: String, to current: String, among listed: [String]) -> [String] {
        typealias Version = UpdateServiceSupport.SemanticVersion
        guard let from = Version(raw: previous), let to = Version(raw: current), to > from else { return [] }
        func core(_ version: Version) -> [Int] { [version.major, version.minor, version.patch] }
        var seen: Set<String> = []
        let inRange = listed.compactMap { raw -> (raw: String, version: Version)? in
            guard let version = Version(raw: raw), from < version, version <= to,
                  seen.insert(raw).inserted else { return nil }
            return (raw, version)
        }
        let picked = inRange.filter { entry in
            guard entry.version.isPrerelease else {
                if !to.isPrerelease { return true }
                let readBefore = from.isPrerelease && core(from) == core(entry.version)
                let readHere = inRange.contains { $0.version.isPrerelease && core($0.version) == core(entry.version) }
                return !readBefore && !readHere
            }
            return to.isPrerelease
        }
        return picked.sorted { $0.version > $1.version }.prefix(maximumVersions).map(\.raw)
    }

    /// `includeUnreleased` adds the changelog's work in progress on top, for
    /// the Developer preview.
    static func make(from previous: String?, to current: String, changelog: String,
                     includeUnreleased: Bool = false) -> ReleaseDigest {
        // The changelog is split by version once; each version's notes are
        // then parsed from its own block instead of the whole file.
        var blocks: [String: String] = [:]
        var listed: [String] = []
        var block: (version: String, lines: [String])?
        func close() {
            guard let block, blocks[block.version] == nil else { return }
            blocks[block.version] = block.lines.joined(separator: "\n")
            listed.append(block.version)
        }
        for line in changelog.components(separatedBy: .newlines) {
            if line.hasPrefix("## ["), let end = line.dropFirst(4).firstIndex(of: "]") {
                close()
                block = (String(line[line.index(line.startIndex, offsetBy: 4)..<end]), [])
            }
            block?.lines.append(line)
        }
        close()
        var versions = previous.map {
            Self.versions(from: $0, to: current, among: listed.filter { $0 != "Unreleased" })
        } ?? []
        if includeUnreleased { versions.insert("Unreleased", at: 0) }
        let releases = versions
            .compactMap { version in blocks[version].map { ReleaseNotes.notes(for: version, changelog: $0) } }
            .filter { !$0.sections.isEmpty }
        var changes: [ReleaseChange] = []
        // A hotfix can repeat its base version's entries word for word; the
        // newest copy is enough.
        var seenTexts: Set<String> = []
        for release in releases {
            let names = release.sections.map { $0.title.trimmingCharacters(in: .whitespaces).lowercased() }
            // Next to its own Added or Dynamic Island entries, a highlights
            // list restates them in other words.
            let highlightsRepeat = names.contains { $0.hasPrefix("added") || $0 == "dynamic island" }
            for (section, name) in zip(release.sections, names) {
                // Everything after "Everything from 3.3.3" repeats that release.
                if name.hasPrefix("everything from") { break }
                if highlightsRepeat && (name.hasSuffix("highlights") || name == "highlight") { continue }
                guard let kind = ReleaseChangeKind(section: section.title) else { continue }
                for text in section.bulletItems where seenTexts.insert(text).inserted {
                    changes.append(ReleaseChange(
                        text: text, kind: kind, version: release.version,
                        features: ReleaseChangeAliases.features(inBullet: text, section: section.title),
                        alsoAppWide: ReleaseChangeAliases.mentionsAppWide(text)))
                }
            }
        }
        let summary = releases.lazy
            .compactMap { release in
                release.sections.first { $0.title.lowercased() == "summary" }?.paragraphItems
            }
            .first { !$0.isEmpty }?
            .joined(separator: "\n\n")
        return ReleaseDigest(previousVersion: previous, version: current,
                             versions: releases.map(\.version), summary: summary, changes: changes)
    }
}

/// When the post-update "What's New" window opens, and which features it
/// introduces as new.
enum WhatsNewInfo {
    /// The version the next window starts after, or nil when nothing waits.
    /// A window still waiting keeps its older starting point across a second
    /// update; a downgrade or reinstall drops it. A new one needs a real
    /// update from a known version, past the last one shown here, so a
    /// restored backup's older version cannot replay what was already seen.
    static func pendingVersion(current: String, previous: String?,
                               seen: String?, pending: String?) -> String? {
        typealias Version = UpdateServiceSupport.SemanticVersion
        guard let now = Version(raw: current) else { return nil }
        if let pending, let start = Version(raw: pending) {
            return now > start ? pending : nil
        }
        guard let previous, let before = Version(raw: previous) else { return nil }
        var start = (raw: previous, version: before)
        if let seen, let shown = Version(raw: seen), shown > before {
            start = (seen, shown)
        }
        return now > start.version ? start.raw : nil
    }

    /// The later of a stored version and the running one; one that cannot
    /// be read loses.
    static func later(_ stored: String?, _ current: String) -> String {
        typealias Version = UpdateServiceSupport.SemanticVersion
        guard let stored, let old = Version(raw: stored) else { return current }
        guard let new = Version(raw: current) else { return stored }
        return old > new ? stored : current
    }

    /// Every feature that existed when this window began telling new features
    /// apart. Frozen on purpose: a feature added later is new to anyone who
    /// updates from a version that never recorded what it knew.
    static let featuresBeforeTracking: Set<String> = [
        "switcher", "dockPreview", "dockClick", "windowMaximizer", "windowLayout", "autoQuit", "spacesOrder",
        "scrollInverter", "scrollHorizontal", "focusFollowsMouse", "smoothScroll", "linearScroll",
        "mouseAcceleration", "mouseNavigation", "mouseButtonShortcuts", "middleClick", "mouseClickDebounce",
        "keyboardDebounce", "textSnippets", "superKey", "quitWindowProtection",
        "clipboardHistory", "pastePlain", "finderCutPaste", "finderRename", "shelf", "urlCleaner",
        "diskImageInstaller",
        "mixer", "soundOutputSwitcher", "audioPriority", "micMute", "musicBlock",
        "keepAwake", "brightness", "extraBrightness", "bluetoothSleep",
        "quickLauncher", "quickToggles", "colorPicker", "screenOCR", "cleaningMode", "mediaTools",
        "cleaner", "uninstaller", "homebrew", "appUpdates", "screenshot", "cameraPreview", "radialMenu",
        "scratchpad", "commandBar", "screenRecorder", "wallpaper", "killProcess", "portManager",
        "notch", "notchCalendar", "notchNotifications", "notchGestures", "notchTimer", "notchAccessories",
        "notchLyrics", "notchQueue", "notchLiveEqualizer", "notchDownloads", "notchAgents", "notchWatch",
        "notchMascot",
        "monitorCPU", "monitorGPU", "monitorMemory", "monitorNetwork", "monitorDisk", "monitorPower",
        "connectedDevices", "fanControl",
    ]

    /// What to store once the window is done: every feature this version has.
    static var knownFeaturesValue: String {
        AppFeature.allCases.map(\.rawValue).joined(separator: ",")
    }

    /// Features this version added since the stored list, in catalog order.
    static func newFeatures(known: String?, isSupported: (AppFeature) -> Bool) -> [AppFeature] {
        let names = known.map { Set($0.split(separator: ",").map(String.init)) } ?? featuresBeforeTracking
        return AppFeature.allCases.filter { !names.contains($0.rawValue) && isSupported($0) }
    }
}
