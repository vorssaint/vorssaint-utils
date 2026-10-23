// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Finds which features a CHANGELOG bullet is about, so the post-update
/// "What's new" window can show each person only the changes for the
/// features they use. Input is one bullet as ReleaseNotes cleans it (no
/// links, `**` or backticks) plus its `###` section title.
///
/// Rules, in the order they apply:
/// 1. Ignored phrases ("wheel notch", "Activity Monitor") are claimed first.
///    They look like an alias but mean something else, and never count as
///    island context.
/// 2. Aliases match whole words. A plain alias ignores letter case; `.exact`
///    must match its capitalization ("Watch" the feature, not "watch" the
///    verb). Longer aliases go first and claim their words, so "Dock
///    previews" is never also read as a shorter alias inside it.
/// 3. `.island` aliases count only in an island context: the section title
///    or the bullet says island, islands, notch, camera cutout or beside the
///    camera. "calendar", "timer" or "downloads" alone are too common.
/// 4. Family aliases ("System monitor", "mouse settings") name a whole
///    Settings page. They report every feature of the family, but only when
///    no feature of that page matched on its own.
/// 5. The section title is matched the same way, so "### Dynamic Island"
///    implies `.notch` and "### Added (switcher)" implies `.switcher`.
/// A bullet that matches nothing is app-wide (Settings, menu bar panel,
/// languages, updates). Dynamic Island extensions are reported as
/// themselves; the window rolls them up under the Dynamic Island row.
enum ReleaseChangeAliases {
    struct Alias: Hashable, ExpressibleByStringLiteral {
        let text: String
        let matchesCase: Bool
        let needsIsland: Bool

        init(_ text: String, matchesCase: Bool = false, needsIsland: Bool = false) {
            self.text = text
            self.matchesCase = matchesCase
            self.needsIsland = needsIsland
        }

        init(stringLiteral value: String) {
            self.init(value)
        }

        /// Matches only with this exact capitalization.
        static func exact(_ text: String) -> Alias { Alias(text, matchesCase: true) }

        /// Matches only when the bullet or its section is about the island.
        static func island(_ text: String) -> Alias { Alias(text, needsIsland: true) }
    }

    struct Family {
        let aliases: [Alias]
        let members: [AppFeature]
        /// Any of these matching on its own makes the family alias redundant.
        let suppressedBy: Set<AppFeature>
    }

    static func aliases(for feature: AppFeature) -> [Alias] {
        switch feature {
        case .switcher: return ["window switcher", "app switcher", "switcher"]
        case .dockPreview: return ["dock preview", "dock previews"]
        case .dockClick: return ["dock clicks", "dock click", "click the dock icon", "dock icon", "dock actions"]
        case .windowMaximizer: return ["maximize windows", "window maximizer", .exact("Maximize"),
            "green-button maximization", "green-button maximize"]
        case .windowLayout: return ["window layout", "window layouts", "snap areas", "edge snapping",
            "window snapping", "snap windows at screen edges", "window dragging", "move and resize by dragging",
            "maximize with margin", "window tools", "resizing windows by dragging"]
        case .autoQuit: return ["quit on close", "auto quit", "quit on last window close"]
        case .spacesOrder: return ["spaces order", "keep spaces in a fixed order"]
        case .scrollInverter: return ["scroll inverter", "invert mouse scrolling", "inverted mouse scrolling",
            "invert scrolling", "inverted scrolling", "scroll inversion"]
        case .scrollHorizontal: return ["scroll sideways", "horizontal scrolling"]
        case .focusFollowsMouse: return ["focus follows mouse", "focus follows the mouse"]
        case .smoothScroll: return ["smooth scrolling", "smooth scroll"]
        case .linearScroll: return ["linear scrolling", "linear scroll"]
        case .mouseAcceleration: return ["mouse acceleration", "pointer acceleration"]
        case .mouseNavigation: return ["mouse navigation", "side buttons", "side button", "side clicks",
            "back/forward mouse buttons"]
        case .mouseButtonShortcuts: return ["mouse button shortcuts", "button shortcuts"]
        case .middleClick: return ["middle click", "middle-click", "middle clicks"]
        case .mouseClickDebounce: return ["extra click filter", "extra-click filter", "click filter",
            "mouse debounce", "keyboard and mouse debounce", "worn-button click filtering", "extra clicks"]
        case .keyboardDebounce: return ["keyboard debounce", "key debounce", "debounce",
            "keyboard and mouse debounce"]
        case .textSnippets: return ["text snippets", "snippets", "snippet"]
        case .superKey: return ["super key"]
        case .quitWindowProtection: return ["quit protection", "quit & close protection",
            "quit and close protection", "command q and command w"]
        case .clipboardHistory: return ["clipboard history", .exact("Clipboard"), .island("clipboard"),
            "clear unpinned", "clipboard previews", "clipboard items"]
        case .pastePlain: return ["paste as plain text", "paste plain text"]
        case .finderCutPaste: return ["cut & paste", "cut and paste", "cut files", "finder cut", "cut operations"]
        case .finderRename: return ["finder shortcuts", "rename shortcut", "renames selected files"]
        case .shelf: return [.exact("Shelf"), .island("shelf"), "drop zone", "docked shelf", "temporary shelf",
            "on the shelf", "shelf files"]
        case .urlCleaner: return ["clean url", "url cleaner", "url cleaning"]
        case .diskImageInstaller: return ["disk image installer", "disk images", "disk image",
            "disk image installation"]
        case .mixer: return ["volume mixer", "sound mixer", "mixer", "per-app audio output", "per-app output",
            "app's volume"]
        case .soundOutputSwitcher: return ["output switcher", "sound output switcher"]
        case .audioPriority: return ["audio device priority"]
        case .micMute: return ["mute microphone", "mic mute", "microphone mute", "muting the microphone"]
        case .musicBlock: return ["music app blocker", "replacement for music", "music launch blocking",
            "music from opening", "unwanted music launches"]
        case .keepAwake: return ["keep awake", "closed lid mode", "keep going with lid closed", "keep-awake"]
        case .brightness: return [.exact("Displays"), "display brightness", "brightness keys",
            "brightness shortcuts", "control displays", "display controls", "extra dimming", "closed-lid dimming",
            "brightness overlay", "brightness panel"]
        case .extraBrightness: return ["extra brightness", "xdr"]
        case .bluetoothSleep: return ["bluetooth on sleep", "bluetooth power", "bluetooth off during sleep"]
        case .quickLauncher: return ["quick panel", "quick launcher"]
        case .quickToggles: return ["quick toggles"]
        case .colorPicker: return ["color picker"]
        case .screenOCR: return ["copy text from screen", "screen ocr"]
        case .cleaningMode: return ["cleaning mode"]
        case .mediaTools: return ["media tools", "image conversion", "video editor", "convert media",
            .exact("Media"), "image profiles", "video compression", "gif compression", "video and gif tools",
            "image converter"]
        case .cleaner: return [.exact("Cleaner")]
        case .uninstaller: return ["uninstaller"]
        case .homebrew: return ["homebrew", "package management", "package manager", "package updates",
            "package jobs"]
        case .appUpdates: return ["app updates", "app update"]
        case .screenshot: return ["screenshot", "screenshots", "screenshot editor", "screen capture",
            "screen captures", "recent captures", "window capture", .exact("Window captures"), "magnifier",
            "capture controls", "capture tool", "capture tools", "capture tool picker", "capture history",
            "capture guides", "capture links", "capture modes", "capture shortcut", "capture shortcuts"]
        case .cameraPreview: return ["camera preview", "camera mirror"]
        case .radialMenu: return ["radial menu", "radial menus"]
        case .scratchpad: return ["scratchpad"]
        case .commandBar: return ["command bar", "calculator"]
        case .selectionBar: return ["selection bar", "selection bars"]
        case .screenRecorder: return ["screen recording", "screen recordings", "recording", "recordings",
            "recorder", "recording editor", "gif export", "gif exports"]
        case .wallpaper: return [.exact("Wallpaper"), "wallpaper gallery", "wallpapers"]
        case .killProcess: return ["kill process", "force kill", "process tree"]
        case .portManager: return ["port manager"]
        case .notch: return ["dynamic island", "island", "islands", "notch", "volume keys", "volume key",
            "mute key", "volume feedback", "volume indicator", "volume notice", "new track indicator",
            "displays without a notch", "displays without a camera cutout"]
        case .notchCalendar: return [.island("calendar"), "event countdown", "event countdowns", "week numbers",
            "calendar indicator", .island("appointment"), .island("appointments"), .island("next event"),
            .island("upcoming event")]
        case .notchNotifications: return [.island("notifications"), .island("notification"), "notification banners",
            "system banner"]
        case .notchGestures: return ["dynamic island gestures", .island("gestures"), .island("gesture")]
        case .notchTimer: return [.exact("Timer"), .exact("Timers"), .island("timer"), .island("timers"),
            "pomodoro", "stopwatch", "focus cycles"]
        case .notchAccessories: return ["accessory alerts", "accessory notices", .island("accessory")]
        case .notchLyrics: return ["lyrics", "lyric"]
        case .notchQueue: return ["up next", .island("queue")]
        case .notchLiveEqualizer: return ["bars follow the music", "live music bars",
            "music bars that follow playback"]
        case .notchDownloads: return [.island("downloads"), .island("download"), "safari downloads",
            "downloads folder", "downloads page", "completed download", "completed downloads"]
        case .notchAgents: return ["ai agents", "ai agent", "claude code", "claude code timer", "codex", "ai usage",
            "opencode", "github copilot", .island("agent"), .island("agents")]
        case .notchWatch: return [.exact("Watch")]
        case .notchMascot: return ["companion"]
        case .monitorCPU: return ["cpu temperature", "cpu load", "cpu readings", "per core", "per-core",
            "processor temperature", "process breakdowns", "cpu alert", "cpu and gpu temperatures"]
        case .monitorGPU: return ["gpu usage", "gpu load", "gpu temperature", "gpu temperatures",
            "cpu and gpu temperatures"]
        case .monitorMemory: return ["memory usage", "memory pressure", "memory readouts", "swap memory",
            "compressed memory", "used memory", "ram metric", "ram usage"]
        case .monitorNetwork: return ["network speed", "network speeds", "network readings", "speed test",
            "speed tests", "network panel", "network menu bar metric"]
        case .monitorDisk: return ["disk usage", "disk space", .exact("Disks"), "disks panel", "drives tab",
            "eject all disks", "removable drive", "external drive"]
        case .monitorPower: return [.exact("Power"), "power reading", "battery time", "battery readings",
            "menu bar battery icon", "battery health", "battery section", "battery temperature",
            "battery temperatures"]
        case .connectedDevices: return ["connected devices", "usb devices"]
        case .fanControl: return ["fan control", "fan curves", "fan curve", "fan speed", "fan speeds",
            "cooling curve"]
        }
    }

    private static let mousePage: [AppFeature] = [.scrollInverter, .scrollHorizontal, .focusFollowsMouse,
        .smoothScroll, .linearScroll, .mouseAcceleration, .mouseNavigation, .mouseButtonShortcuts, .middleClick,
        .mouseClickDebounce]
    private static let monitorMetrics: [AppFeature] = [.monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork,
        .monitorDisk, .monitorPower]
    private static let monitorPage: [AppFeature] = monitorMetrics + [.connectedDevices, .fanControl]

    static let families: [Family] = [
        Family(
            aliases: ["system monitor", "monitor settings", .exact("Monitor"), "system panel", "system section",
            "system metrics", "menu bar readings", "menu bar metrics", "menu bar metric"],
            members: monitorMetrics,
            suppressedBy: Set(monitorPage)
        ),
        Family(
            aliases: ["temperature alerts", "temperature unit"],
            members: [.monitorCPU, .monitorGPU, .monitorPower],
            suppressedBy: Set(monitorPage)
        ),
        Family(
            aliases: ["mouse exceptions", "mouse feature exceptions", "mouse features", "mouse controls",
            "mouse settings", "apps to leave alone"],
            members: mousePage,
            suppressedBy: Set(mousePage)
        ),
    ]

    static let ignoredPhrases: [String] = ["wheel notch", "wheel notches", "shortcut recording",
        "recording a shortcut", "keeps recording", "incompatible recordings", "activity monitor", "media key",
        "media keys"]
    static let islandWords: [String] = ["island", "islands", "notch", "camera cutout", "beside the camera"]
    /// Parts of the app everyone has, whatever features are installed.
    static let appWidePhrases: [String] = ["menu bar panel", "settings sidebar", "settings window", "features page",
        "custom menu bar icon"]

    /// Features the bullet is about, in AppFeature declaration order.
    /// Empty means an app-wide change.
    static func features(inBullet text: String, section: String) -> [AppFeature] {
        let sectionMatch = match(section, islandContext: nil)
        let textMatch = match(text, islandContext: sectionMatch.islandContext ? true : nil)
        let specific = sectionMatch.features.union(textMatch.features)
        var found = specific
        for index in sectionMatch.families.union(textMatch.families).sorted() {
            let family = families[index]
            if specific.isDisjoint(with: family.suppressedBy) {
                found.formUnion(family.members)
            }
        }
        // Under a Dynamic Island section, other tools are named as a place
        // or a part of the island ("can carry the Command Bar out of the
        // island"), not as what changed.
        if sectionMatch.features.contains(.notch) {
            found = found.filter { $0.group == .dynamicIsland }
        }
        return AppFeature.allCases.filter { found.contains($0) }
    }

    /// Whether the bullet also changes something every person has.
    static func mentionsAppWide(_ text: String) -> Bool {
        let folded = Scalars(text).folded
        return appWidePatterns.contains { !ranges(of: $0.scalars, in: folded).isEmpty }
    }

    private struct Entry {
        let alias: Alias
        let pattern: Pattern
        var features: [AppFeature]
        let family: Int?
    }

    /// An alias as scalars, plus its first word: an alias can only match
    /// where that word stands on its own, so most aliases are ruled out by
    /// one set lookup instead of a scan.
    private struct Pattern {
        let scalars: [Unicode.Scalar]
        let firstWord: String

        init(_ alias: Alias) {
            let all = Array(alias.text.unicodeScalars)
            scalars = alias.matchesCase ? all : all.map(ReleaseChangeAliases.fold)
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars.prefix { ReleaseChangeAliases.isWordCharacter($0) })
            firstWord = String(view)
        }
    }

    /// Every alias once, longest first; ties keep declaration order.
    private static let entries: [Entry] = {
        var result: [Entry] = []
        var positions: [Alias: Int] = [:]
        func add(_ alias: Alias, _ features: [AppFeature], family: Int?) {
            if let position = positions[alias] {
                for feature in features where !result[position].features.contains(feature) {
                    result[position].features.append(feature)
                }
            } else {
                positions[alias] = result.count
                result.append(Entry(alias: alias, pattern: Pattern(alias), features: features, family: family))
            }
        }
        for feature in AppFeature.allCases {
            for alias in aliases(for: feature) { add(alias, [feature], family: nil) }
        }
        for (index, family) in families.enumerated() {
            for alias in family.aliases { add(alias, family.members, family: index) }
        }
        return result.enumerated().sorted { lhs, rhs in
            let left = lhs.element.pattern.scalars.count
            let right = rhs.element.pattern.scalars.count
            return left != right ? left > right : lhs.offset < rhs.offset
        }.map(\.element)
    }()

    private static let ignoredPatterns = ignoredPhrases.map { Pattern(Alias($0)) }
    private static let islandPatterns = islandWords.map { Pattern(Alias($0)) }
    private static let appWidePatterns = appWidePhrases.map { Pattern(Alias($0)) }

    /// The text as Unicode scalars, plus a copy with ASCII letters lowercased.
    /// Folding only ASCII keeps both copies the same length, and every alias
    /// is ASCII, so ranges from either copy line up.
    private struct Scalars {
        let original: [Unicode.Scalar]
        let folded: [Unicode.Scalar]
        let words: Set<String>
        let foldedWords: Set<String>

        init(_ text: String) {
            original = Array(text.unicodeScalars)
            folded = original.map(ReleaseChangeAliases.fold)
            words = Scalars.words(in: original)
            foldedWords = Scalars.words(in: folded)
        }

        func haystack(for alias: Alias) -> [Unicode.Scalar] { alias.matchesCase ? original : folded }

        func mayContain(_ pattern: Pattern, matchingCase: Bool) -> Bool {
            pattern.firstWord.isEmpty || (matchingCase ? words : foldedWords).contains(pattern.firstWord)
        }

        private static func words(in scalars: [Unicode.Scalar]) -> Set<String> {
            var result = Set<String>()
            var word = String.UnicodeScalarView()
            for scalar in scalars {
                if ReleaseChangeAliases.isWordCharacter(scalar) {
                    word.append(scalar)
                } else if !word.isEmpty {
                    result.insert(String(word))
                    word = String.UnicodeScalarView()
                }
            }
            if !word.isEmpty { result.insert(String(word)) }
            return result
        }
    }

    private static func fold(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        guard scalar.value >= 65, scalar.value <= 90, let lower = Unicode.Scalar(scalar.value + 32) else {
            return scalar
        }
        return lower
    }

    private static func match(_ string: String, islandContext forced: Bool?)
        -> (features: Set<AppFeature>, families: Set<Int>, islandContext: Bool) {
        let text = Scalars(string)
        var claimed = ignoredPatterns
            .filter { text.mayContain($0, matchingCase: false) }
            .flatMap { ranges(of: $0.scalars, in: text.folded) }
        let islandContext = forced ?? islandPatterns.contains { word in
            text.mayContain(word, matchingCase: false)
                && ranges(of: word.scalars, in: text.folded).contains { range in
                    !claimed.contains { $0.overlaps(range) }
                }
        }
        var features: Set<AppFeature> = []
        var familyHits: Set<Int> = []
        for entry in entries where (islandContext || !entry.alias.needsIsland)
            && text.mayContain(entry.pattern, matchingCase: entry.alias.matchesCase) {
            for range in ranges(of: entry.pattern.scalars, in: text.haystack(for: entry.alias))
            where !claimed.contains(where: { $0.overlaps(range) }) {
                claimed.append(range)
                if let family = entry.family {
                    familyHits.insert(family)
                } else {
                    features.formUnion(entry.features)
                }
            }
        }
        return (features, familyHits, islandContext)
    }

    /// Whole-word occurrences, scanning left to right without overlaps.
    private static func ranges(of pattern: [Unicode.Scalar], in text: [Unicode.Scalar]) -> [Range<Int>] {
        guard !pattern.isEmpty, pattern.count <= text.count else { return [] }
        var result: [Range<Int>] = []
        var start = 0
        let last = text.count - pattern.count
        while start <= last {
            var matches = true
            for offset in 0..<pattern.count where text[start + offset] != pattern[offset] {
                matches = false
                break
            }
            let end = start + pattern.count
            if matches,
               start == 0 || !isWordCharacter(text[start - 1]),
               end == text.count || !isWordCharacter(text[end]) {
                result.append(start..<end)
                start = end
            } else {
                start += 1
            }
        }
        return result
    }

    private static func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122: return true
        case 0..<128: return false
        default: return scalar.properties.isAlphabetic || scalar.properties.numericType != nil
        }
    }
}
