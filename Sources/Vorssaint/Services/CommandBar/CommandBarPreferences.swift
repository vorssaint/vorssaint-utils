// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A kind of result the bar can offer. Raw values are storage ids for the
/// list of sources the person switched off, so they never change.
enum CommandBarSource: String, CaseIterable, Identifiable {
    /// What Vorssaint itself can do. Always on: it is what the bar is for.
    case actions
    case apps
    case menus
    case windows
    case quitApps
    case settingsPages
    /// The Mac's own Settings panes, which are not Vorssaint's and can be
    /// switched off on their own.
    case macSettings
    case snippets
    case clipboard
    case emoji
    case folders
    case answers
    case calculator
    /// What the person had selected when the bar opened.
    case selection
    /// The links, folders and searches the person saved themselves.
    case links
    /// Files found by name in the folders the person named. Last, because it
    /// is the one source that has to go and look.
    case files

    var id: String { rawValue }

    /// The one source that cannot be switched off, because switching it off
    /// would leave an empty bar and no way back.
    var isAlwaysOn: Bool { self == .actions }

    var symbolName: String {
        switch self {
        case .actions: return "wand.and.rays"
        case .apps: return "square.grid.2x2"
        case .menus: return "filemenu.and.selection"
        case .windows: return "macwindow"
        case .quitApps: return "xmark.circle"
        case .settingsPages: return "gearshape"
        case .macSettings: return "gearshape.2"
        case .snippets: return "text.append"
        case .clipboard: return "doc.on.clipboard"
        case .emoji: return "face.smiling"
        case .folders: return "folder"
        case .answers: return "info.circle"
        case .calculator: return "equal.square"
        case .selection: return "text.cursor"
        case .links: return "bookmark"
        case .files: return "doc.text.magnifyingglass"
        }
    }

    /// The row ids this source owns. The catalog keeps to these prefixes.
    var idPrefix: String? {
        switch self {
        case .actions: return nil
        case .apps: return "app."
        case .menus: return "menu."
        case .windows: return "window."
        case .quitApps: return "quit."
        case .settingsPages: return "settings."
        case .macSettings: return "macsettings."
        case .snippets: return "snippet."
        case .clipboard: return "clipboard."
        case .emoji: return "emoji."
        case .folders: return "folder."
        case .answers: return "answer."
        case .calculator: return nil
        case .selection: return "selection."
        case .links: return "link."
        case .files: return "file."
        }
    }
}

/// Everything the person decides about the bar: which kinds of result it may
/// offer, the names they gave things, and what they pinned. Pure, so the
/// rules are pinned by tests and the service only has to read them.
enum CommandBarPreferences {
    /// Row shortcuts persist ids, so this one must never drift.
    static let emojiBrowserRowID = "emoji.browse"

    // MARK: - Sources

    static func disabledSources(from raw: String) -> Set<CommandBarSource> {
        Set(raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap(CommandBarSource.init(rawValue:))
            .filter { !$0.isAlwaysOn })
    }

    /// Sorted so the same set always writes the same string.
    static func storageValue(for sources: Set<CommandBarSource>) -> String {
        sources.filter { !$0.isAlwaysOn }.map(\.rawValue).sorted().joined(separator: ",")
    }

    static func isEnabled(_ source: CommandBarSource, disabledRaw: String) -> Bool {
        source.isAlwaysOn || !disabledSources(from: disabledRaw).contains(source)
    }

    /// The source a row belongs to, decided by its id. Rows with no prefix of
    /// their own are the app's own actions.
    static func source(ofRowID id: String) -> CommandBarSource {
        for source in CommandBarSource.allCases {
            if let prefix = source.idPrefix, id.hasPrefix(prefix) { return source }
        }
        return .actions
    }

    /// What a kind of row is worth before a single letter of it is read.
    ///
    /// What this Mac holds (the apps, Vorssaint's own actions, the Settings
    /// pages) is what people mean; the menu commands of whatever app happens
    /// to be in front are borrowed, and one submenu of history can hold a
    /// dozen rows with the same words in them. So a borrowed row sits under an
    /// owned one whenever the match is just as good. Small on purpose: a menu
    /// command that IS what was typed still beats an app that merely contains
    /// it.
    static func rankBias(for source: CommandBarSource) -> Int {
        switch source {
        case .menus: return -80
        // A file is the deepest and most numerous thing the bar can find, and
        // a bar is for running things first. So a file has to be a plainly
        // better match than a command to lead the list, never merely as good.
        case .files: return -40
        // What is currently selected is what the person is already looking
        // at, so an action on it should lead a same-quality settings-page
        // match rather than lose to one on a title technicality (a page
        // titled "Quarantine Manager" gets a prefix-match bonus over a row
        // titled "Remove Quarantine" for the query "quarantine" that a flat
        // rankBias of 0 does not make up for). 250 clears that gap.
        case .selection: return 250
        case .actions, .apps, .windows, .quitApps, .settingsPages, .macSettings, .snippets,
             .clipboard, .emoji, .folders, .answers, .calculator, .links:
            return 0
        }
    }

    // MARK: - Aliases

    /// Names the person gave to rows: "codex" for the chat app they think of
    /// that way. Several words are allowed and each one finds the row.
    static func decodeAliases(_ raw: String?) -> [String: String] {
        guard let raw, let data = raw.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map.compactMapValues { value in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : clean
        }
    }

    static func encodeAliases(_ aliases: [String: String]) -> String? {
        guard let data = try? JSONEncoder().encode(aliases) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// An alias is only worth keeping on a row whose id survives: a menu item
    /// or a window is a different thing every time the app changes, and a name
    /// pinned to one would silently point somewhere else tomorrow.
    static func acceptsAlias(rowID: String) -> Bool {
        switch source(ofRowID: rowID) {
        case .menus, .windows, .clipboard, .selection, .files: return false
        case .actions, .apps, .quitApps, .settingsPages, .macSettings, .snippets, .emoji,
             .folders, .answers, .calculator, .links:
            return true
        }
    }

    static func settingAlias(_ alias: String,
                             for rowID: String,
                             in aliases: [String: String]) -> [String: String] {
        var next = aliases
        let clean = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            next.removeValue(forKey: rowID)
        } else {
            next[rowID] = String(clean.prefix(60))
        }
        return next
    }

    /// How well what was typed names this alias. A name the person gave has
    /// to outrank the app's own titles, or "codex" keeps opening the editor
    /// whose name merely looks similar; a name being typed ranks just under a
    /// finished one.
    enum AliasHit: Int {
        case exact = 2400
        case prefix = 1100
    }

    static func aliasHit(_ alias: String, query: String) -> AliasHit? {
        let normalizedQuery = CommandBarSearch.normalized(query)
        guard !normalizedQuery.isEmpty else { return nil }
        var best: AliasHit?
        for word in CommandBarSearch.normalized(alias).split(separator: " ").map(String.init)
        where !word.isEmpty {
            if word == normalizedQuery { return .exact }
            if word.hasPrefix(normalizedQuery) { best = .prefix }
        }
        return best
    }

    static func aliasMatches(_ alias: String, query: String) -> Bool {
        aliasHit(alias, query: query) != nil
    }

    /// Another row already answers to this name. Silently moving it would be
    /// worse than saying so, which is a mistake shipped by tools much older
    /// than this one.
    static func rowUsingAlias(_ alias: String,
                              in aliases: [String: String],
                              excluding key: String) -> String? {
        let wanted = Set(CommandBarSearch.normalized(alias).split(separator: " ").map(String.init))
        guard !wanted.isEmpty else { return nil }
        for (rowKey, value) in aliases where rowKey != key {
            let words = Set(CommandBarSearch.normalized(value).split(separator: " ").map(String.init))
            if !words.isDisjoint(with: wanted) { return rowKey }
        }
        return nil
    }

    // MARK: - Pins

    /// A pin only means anything on a row that can lead the empty bar. A menu
    /// command, a quit row, an emoji or a clipboard item is not offered there,
    /// so pinning one would be stored, listed in Settings and never seen
    /// again, which reads as the pin being broken.
    static func acceptsPin(rowID: String) -> Bool {
        switch source(ofRowID: rowID) {
        case .menus, .quitApps, .clipboard, .emoji, .selection, .files: return false
        case .actions, .apps, .windows, .settingsPages, .macSettings, .snippets, .folders,
             .links, .answers, .calculator:
            return true
        }
    }

    static func decodePins(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func encodePins(_ pins: [String]) -> String {
        pins.joined(separator: "\n")
    }

    /// Pinning is a toggle: the same gesture puts a row at the top and takes
    /// it back off. New pins go last, so the order the person built stays.
    static func togglingPin(_ rowID: String, in pins: [String]) -> [String] {
        var next = pins
        if let index = next.firstIndex(of: rowID) {
            next.remove(at: index)
        } else {
            next.append(rowID)
            if next.count > 30 { next.removeFirst(next.count - 30) }
        }
        return next
    }

    /// What a pin is worth on a typed query: enough to win a tie between two
    /// equally good matches, never enough to jump over a better one. A pin
    /// that overrode the ranking would make the list feel stale, which is the
    /// classic failure of favorites done as a global override.
    static let pinTieBreak = 60

    /// On the empty bar the pins lead, in the order they were made, because
    /// there is no ranking to respect yet.
    static func leadingPins(_ pins: [String], available: Set<String>) -> [String] {
        pins.filter { available.contains($0) }
    }

    // MARK: - Rows the person never wants to see

    static func decodeHidden(_ raw: String) -> Set<String> {
        Set(raw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }

    static func encodeHidden(_ hidden: Set<String>) -> String {
        hidden.sorted().joined(separator: "\n")
    }

    static func togglingHidden(_ key: String, in hidden: Set<String>) -> Set<String> {
        var next = hidden
        if next.contains(key) { next.remove(key) } else { next.insert(key) }
        return next
    }

    // MARK: - Position

    /// How far the person dragged the bar from the spot it opens on by
    /// default, stored as an offset rather than a place: "a hand's width
    /// lower and to the left" means the same thing on every display, and
    /// a place remembered from a monitor that is no longer plugged in
    /// would put the bar where nobody can see it.
    static func decodePositionOffset(_ raw: String) -> CGSize {
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let width = Double(parts[0]), width.isFinite,
              let height = Double(parts[1]), height.isFinite
        else { return .zero }
        return CGSize(width: width, height: height)
    }

    static func encodePositionOffset(_ offset: CGSize) -> String {
        let rounded = CGSize(width: offset.width.rounded(), height: offset.height.rounded())
        guard rounded != .zero else { return "" }
        guard let width = Int(exactly: rounded.width),
              let height = Int(exactly: rounded.height)
        else { return "" }
        return "\(width),\(height)"
    }

    static func clampedPanelOrigin(size: CGSize, in visibleFrame: CGRect,
                                   offset: CGSize) -> CGPoint {
        let margin: CGFloat = 16
        let wanted = CGPoint(x: visibleFrame.midX - size.width / 2 + offset.width,
                             y: visibleFrame.minY + visibleFrame.height * 0.72
                                - size.height + offset.height)
        let minX = visibleFrame.minX + margin
        let maxX = max(minX, visibleFrame.maxX - size.width - margin)
        let minY = visibleFrame.minY + margin
        let maxY = max(minY, visibleFrame.maxY - size.height - margin)
        return CGPoint(x: min(max(wanted.x, minX), maxX),
                       y: min(max(wanted.y, minY), maxY))
    }
}
