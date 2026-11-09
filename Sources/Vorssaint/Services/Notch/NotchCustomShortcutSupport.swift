// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import OSLog

enum NotchShortcutDestination: String, CaseIterable, Codable, Hashable, Identifiable {
    case islandButtons
    case controls
    case tools
    case shortcutsPage

    var id: String { rawValue }
}

struct NotchCustomShortcut: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var shortcutName: String
    var symbol: String
    var destinations: [NotchShortcutDestination]

    init(id: UUID = UUID(), name: String, shortcutName: String, symbol: String,
         destinations: [NotchShortcutDestination] = [.controls]) {
        self.id = id
        self.name = name
        self.shortcutName = shortcutName
        self.symbol = symbol
        self.destinations = Self.normalized(destinations)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, shortcutName, symbol, destinations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        shortcutName = try container.decode(String.self, forKey: .shortcutName)
        symbol = try container.decode(String.self, forKey: .symbol)
        // Previously every shortcut appeared in Controls and could be added
        // to the island's quick buttons; keep both placements after upgrade.
        destinations = Self.normalized(try container.decodeIfPresent(
            [NotchShortcutDestination].self, forKey: .destinations
        ) ?? [.controls, .islandButtons])
    }

    private static func normalized(_ values: [NotchShortcutDestination]) -> [NotchShortcutDestination] {
        NotchShortcutDestination.allCases.filter(values.contains)
    }
}

enum NotchCustomShortcutSupport {
    static let maximumCount = 6
    static let maximumNameLength = 40
    static let maximumShortcutNameLength = 128
    static let maximumSymbolLength = 64

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Vorssaint",
                                       category: "NotchShortcuts")

    static func isValid(name: String, shortcutName: String, symbol: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortcutName = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= maximumNameLength
            && !shortcutName.isEmpty && shortcutName.count <= maximumShortcutNameLength
            && !symbol.isEmpty && symbol.count <= maximumSymbolLength
            && !symbol.contains(where: \.isWhitespace)
            && NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
    }

    static func sanitized(_ shortcuts: [NotchCustomShortcut]) -> [NotchCustomShortcut] {
        var ids = Set<UUID>()
        return shortcuts.prefix(maximumCount).compactMap { shortcut in
            let name = shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let shortcutName = shortcut.shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
            let symbol = shortcut.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            guard ids.insert(shortcut.id).inserted,
                  isValid(name: name, shortcutName: shortcutName, symbol: symbol) else { return nil }
            return NotchCustomShortcut(id: shortcut.id, name: name, shortcutName: shortcutName, symbol: symbol,
                                       destinations: shortcut.destinations)
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> [NotchCustomShortcut] {
        guard let data = defaults.data(forKey: DefaultsKey.notchCustomShortcuts),
              !data.isEmpty, data.count <= 32_768,
              let shortcuts = try? JSONDecoder().decode([NotchCustomShortcut].self, from: data) else { return [] }
        return sanitized(shortcuts)
    }

    static func encoded(_ shortcuts: [NotchCustomShortcut]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(sanitized(shortcuts))) ?? Data()
    }

    static func shortcut(id: UUID, in defaults: UserDefaults = .standard) -> NotchCustomShortcut? {
        stored(in: defaults).first { $0.id == id }
    }

    static func controlsCount(in defaults: UserDefaults = .standard) -> Int {
        stored(in: defaults).filter { $0.destinations.contains(.controls) }.count
    }

    static func commandArguments(for name: String) -> [String] {
        ["run", name]
    }

    static func run(_ shortcut: NotchCustomShortcut) {
        let name = shortcut.shortcutName
        DispatchQueue.global(qos: .userInitiated).async {
            let result = BoundedProcessRunner.run("/usr/bin/shortcuts", commandArguments(for: name),
                                                  timeout: 60, maxOutputBytes: 8_192)
            guard result.status != 0 || result.timedOut else { return }
            let output = String(data: result.output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let reason: String
            if result.timedOut { reason = "timed out" }
            else if let output, !output.isEmpty { reason = output }
            else { reason = "exit status \(result.status)" }
            logger.error("Could not run Shortcut '\(name, privacy: .public)': \(reason, privacy: .public)")
        }
    }
}

enum NotchControlTile: Identifiable {
    case control(NotchControlItem)
    case customShortcut(NotchCustomShortcut)

    var id: String {
        switch self {
        case .control(let item): return "control.\(item.rawValue)"
        case .customShortcut(let shortcut): return "shortcut.\(shortcut.id.uuidString)"
        }
    }

    var symbol: String {
        switch self {
        case .control(let item): return item.symbol
        case .customShortcut(let shortcut): return shortcut.symbol
        }
    }

    func title(_ l10n: L10n) -> String {
        switch self {
        case .control(let item): return item.title(l10n)
        case .customShortcut(let shortcut): return shortcut.name
        }
    }
}
