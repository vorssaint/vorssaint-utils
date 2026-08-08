// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum MenuBarOrganizerSection: String, CaseIterable, Codable, Identifiable {
    case visible
    case hidden
    case alwaysHidden

    var id: String { rawValue }
}

enum MenuBarOrganizerPresentationMode: String, CaseIterable {
    case automatic
    case menuBar
    case secondaryBar

    static func sanitized(_ raw: String?) -> Self {
        Self(rawValue: raw ?? "") ?? .menuBar
    }
}

enum MenuBarOrganizerRehideMode: String, CaseIterable {
    case never
    case afterDelay
    case focusedApp

    static func sanitized(_ raw: String?) -> Self {
        Self(rawValue: raw ?? "") ?? .afterDelay
    }
}

enum MenuBarOrganizerBarStyle: String, CaseIterable, Identifiable {
    case system
    case tinted
    case graphite
    case vibrant

    var id: String { rawValue }

    static func sanitized(_ raw: String?) -> Self {
        Self(rawValue: raw ?? "") ?? .system
    }
}

enum MenuBarOrganizerPresetSlot: String, CaseIterable, Codable, Identifiable {
    case work
    case home
    case presenting
    case minimal

    var id: String { rawValue }
}

enum MenuBarOrganizerGroupSlot: String, CaseIterable, Codable, Identifiable {
    case cloud
    case audio
    case work
    case custom

    var id: String { rawValue }
}

enum MenuBarOrganizerGroupReference: Hashable, Identifiable {
    case slot(MenuBarOrganizerGroupSlot)
    case custom(String)

    var id: String {
        switch self {
        case .slot(let slot): return "slot:\(slot.rawValue)"
        case .custom(let id): return "custom:\(id)"
        }
    }

    init?(storageValue: String) {
        if storageValue.hasPrefix("slot:") {
            let raw = String(storageValue.dropFirst("slot:".count))
            guard let slot = MenuBarOrganizerGroupSlot(rawValue: raw) else { return nil }
            self = .slot(slot)
        } else if storageValue.hasPrefix("custom:") {
            let id = String(storageValue.dropFirst("custom:".count))
            guard !id.isEmpty else { return nil }
            self = .custom(id)
        } else {
            return nil
        }
    }
}

struct MenuBarOrganizerPreset: Codable, Equatable, Identifiable {
    let slot: MenuBarOrganizerPresetSlot
    let savedAt: Date
    let visible: [MenuBarItemIdentity]
    let hidden: [MenuBarItemIdentity]
    let alwaysHidden: [MenuBarItemIdentity]

    var id: MenuBarOrganizerPresetSlot { slot }

    func items(in section: MenuBarOrganizerSection) -> [MenuBarItemIdentity] {
        switch section {
        case .visible: return visible
        case .hidden: return hidden
        case .alwaysHidden: return alwaysHidden
        }
    }
}

struct MenuBarOrganizerNamedPreset: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    let savedAt: Date
    let visible: [MenuBarItemIdentity]
    let hidden: [MenuBarItemIdentity]
    let alwaysHidden: [MenuBarItemIdentity]

    func items(in section: MenuBarOrganizerSection) -> [MenuBarItemIdentity] {
        switch section {
        case .visible: return visible
        case .hidden: return hidden
        case .alwaysHidden: return alwaysHidden
        }
    }
}

struct MenuBarOrganizerGroup: Codable, Equatable, Identifiable {
    let slot: MenuBarOrganizerGroupSlot
    let savedAt: Date
    var items: [MenuBarItemIdentity]

    var id: MenuBarOrganizerGroupSlot { slot }
}

struct MenuBarOrganizerCustomGroup: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var symbolName: String
    let savedAt: Date
    var items: [MenuBarItemIdentity]
}

struct MenuBarOrganizerCapabilities: Equatable {
    let canEnumerate: Bool
    let canMove: Bool
    let canCapture: Bool
    let hasPrivateFrameAPI: Bool

    var automaticEditorAvailable: Bool { canEnumerate && canMove }
}

struct MenuBarItemIdentity: Hashable, Codable {
    let bundleIdentifier: String
    let title: String
    let occurrence: Int

    var storageValue: String {
        [bundleIdentifier, title, String(occurrence)]
            .map { $0.replacingOccurrences(of: "|", with: "||") }
            .joined(separator: "|")
    }
}

struct ManagedMenuBarItem: Identifiable {
    let id: MenuBarItemIdentity
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let bundleIdentifier: String
    let title: String
    let frame: CGRect
    let section: MenuBarOrganizerSection
    let isMovable: Bool
    let isProtected: Bool
    let image: NSImage?

    var displayName: String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty, cleanTitle.caseInsensitiveCompare(ownerName) != .orderedSame {
            return "\(ownerName) — \(cleanTitle)"
        }
        return ownerName.isEmpty ? (cleanTitle.isEmpty ? "Menu bar item" : cleanTitle) : ownerName
    }
}

struct MenuBarOrganizerWindowRecord {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let bundleIdentifier: String
    let title: String
    let frame: CGRect
    let layer: Int
    let alpha: Double
}

enum MenuBarOrganizerSupport {
    static let allowedRehideDelays = [3, 5, 10, 15, 30, 60]
    static let allowedSpacerWidths = [8, 12, 16, 24, 32]

    static func sanitizedRehideDelay(_ value: Int) -> Int {
        allowedRehideDelays.min(by: { abs($0 - value) < abs($1 - value) }) ?? 10
    }

    static func sanitizedSpacerCount(_ value: Int) -> Int {
        min(max(value, 0), 6)
    }

    static func sanitizedSpacerWidth(_ value: Int) -> Int {
        allowedSpacerWidths.min(by: { abs($0 - value) < abs($1 - value) }) ?? 16
    }

    static func lowBatteryTriggerMatches(percent: Int?,
                                         isOnBattery: Bool,
                                         threshold: Int) -> Bool {
        guard let percent else { return false }
        return isOnBattery && percent <= min(max(threshold, 1), 100)
    }

    static func workHoursTriggerMatches(hour: Int,
                                        weekday: Int,
                                        startHour: Int,
                                        endHour: Int,
                                        weekdaysOnly: Bool) -> Bool {
        if weekdaysOnly, !(2...6).contains(weekday) { return false }
        let start = min(max(startHour, 0), 23)
        let end = min(max(endHour, 0), 23)
        if start == end { return true }
        if start < end {
            return hour >= start && hour < end
        }
        return hour >= start || hour < end
    }

    static func usesExactPreviews(preferenceEnabled: Bool,
                                  screenRecordingGranted: Bool) -> Bool {
        preferenceEnabled && screenRecordingGranted
    }

    static func shouldRegisterAlwaysHiddenShortcut(sectionEnabled: Bool,
                                                   shortcutEnabled: Bool) -> Bool {
        sectionEnabled && shortcutEnabled
    }

    static func preset(slot: MenuBarOrganizerPresetSlot,
                       items: [ManagedMenuBarItem],
                       now: Date = Date()) -> MenuBarOrganizerPreset {
        MenuBarOrganizerPreset(
            slot: slot,
            savedAt: now,
            visible: orderedItems(items, in: .visible).map(\.id),
            hidden: orderedItems(items, in: .hidden).map(\.id),
            alwaysHidden: orderedItems(items, in: .alwaysHidden).map(\.id))
    }

    static func decodePresets(_ raw: String?) -> [MenuBarOrganizerPresetSlot: MenuBarOrganizerPreset] {
        guard let raw, let data = raw.data(using: .utf8), !raw.isEmpty,
              let presets = try? JSONDecoder().decode([MenuBarOrganizerPreset].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: presets.map { ($0.slot, $0) })
    }

    static func encodePresets(_ presets: [MenuBarOrganizerPresetSlot: MenuBarOrganizerPreset]) -> String {
        let ordered = MenuBarOrganizerPresetSlot.allCases.compactMap { presets[$0] }
        guard let data = try? JSONEncoder().encode(ordered) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func sanitizedCustomName(_ value: String, fallback: String) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? fallback : String(clean.prefix(40))
    }

    static func namedPreset(name: String,
                            items: [ManagedMenuBarItem],
                            now: Date = Date(),
                            id: String = UUID().uuidString) -> MenuBarOrganizerNamedPreset {
        MenuBarOrganizerNamedPreset(
            id: id,
            name: sanitizedCustomName(name, fallback: "Preset"),
            savedAt: now,
            visible: orderedItems(items, in: .visible).map(\.id),
            hidden: orderedItems(items, in: .hidden).map(\.id),
            alwaysHidden: orderedItems(items, in: .alwaysHidden).map(\.id))
    }

    static func decodeNamedPresets(_ raw: String?) -> [MenuBarOrganizerNamedPreset] {
        guard let raw, let data = raw.data(using: .utf8), !raw.isEmpty,
              let presets = try? JSONDecoder().decode([MenuBarOrganizerNamedPreset].self, from: data)
        else { return [] }
        return presets
    }

    static func encodeNamedPresets(_ presets: [MenuBarOrganizerNamedPreset]) -> String {
        guard let data = try? JSONEncoder().encode(presets) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func group(slot: MenuBarOrganizerGroupSlot,
                      items: [MenuBarItemIdentity],
                      now: Date = Date()) -> MenuBarOrganizerGroup {
        var seen = Set<MenuBarItemIdentity>()
        let unique = items.filter { seen.insert($0).inserted }
        return MenuBarOrganizerGroup(slot: slot, savedAt: now, items: unique)
    }

    static func decodeGroups(_ raw: String?) -> [MenuBarOrganizerGroupSlot: MenuBarOrganizerGroup] {
        guard let raw, let data = raw.data(using: .utf8), !raw.isEmpty,
              let groups = try? JSONDecoder().decode([MenuBarOrganizerGroup].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: groups.map { ($0.slot, $0) })
    }

    static func encodeGroups(_ groups: [MenuBarOrganizerGroupSlot: MenuBarOrganizerGroup]) -> String {
        let ordered = MenuBarOrganizerGroupSlot.allCases.compactMap { groups[$0] }
        guard let data = try? JSONEncoder().encode(ordered) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func customGroup(name: String,
                            symbolName: String = "folder",
                            items: [MenuBarItemIdentity] = [],
                            now: Date = Date(),
                            id: String = UUID().uuidString) -> MenuBarOrganizerCustomGroup {
        var seen = Set<MenuBarItemIdentity>()
        let unique = items.filter { seen.insert($0).inserted }
        return MenuBarOrganizerCustomGroup(
            id: id,
            name: sanitizedCustomName(name, fallback: "Group"),
            symbolName: sanitizedSymbolName(symbolName),
            savedAt: now,
            items: unique)
    }

    static func sanitizedSymbolName(_ value: String) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "folder" : String(clean.prefix(48))
    }

    static func decodeCustomGroups(_ raw: String?) -> [MenuBarOrganizerCustomGroup] {
        guard let raw, let data = raw.data(using: .utf8), !raw.isEmpty,
              let groups = try? JSONDecoder().decode([MenuBarOrganizerCustomGroup].self, from: data)
        else { return [] }
        return groups
    }

    static func encodeCustomGroups(_ groups: [MenuBarOrganizerCustomGroup]) -> String {
        guard let data = try? JSONEncoder().encode(groups) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func visibleItemsToBorrowForNotch(visibleWidths: [CGFloat],
                                             hiddenWidth: CGFloat,
                                             availableWidth: CGFloat,
                                             minimumVisibleItems: Int = 1) -> Int {
        guard hiddenWidth > availableWidth, visibleWidths.count > minimumVisibleItems else { return 0 }
        let maxBorrowed = max(0, visibleWidths.count - minimumVisibleItems)
        var freed: CGFloat = 0
        var borrowed = 0
        for width in visibleWidths.prefix(maxBorrowed) {
            freed += max(width, 0)
            borrowed += 1
            if hiddenWidth - freed <= availableWidth { break }
        }
        return borrowed
    }

    static func searchScore(displayName: String,
                            bundleIdentifier: String,
                            ownerName: String,
                            title: String,
                            query: String) -> Int? {
        let terms = query.split(whereSeparator: \.isWhitespace)
            .map { $0.localizedLowercase }
        guard !terms.isEmpty else { return 0 }
        let display = displayName.localizedLowercase
        let owner = ownerName.localizedLowercase
        let itemTitle = title.localizedLowercase
        let bundle = bundleIdentifier.localizedLowercase
        let haystack = [display, owner, itemTitle, bundle].joined(separator: " ")
        guard terms.allSatisfy({ haystack.contains($0) }) else { return nil }

        var score = 100
        for term in terms {
            if display == term {
                score = min(score, 0)
            } else if display.hasPrefix(term) {
                score = min(score, 10)
            } else if owner.hasPrefix(term) {
                score = min(score, 20)
            } else if itemTitle.hasPrefix(term) {
                score = min(score, 30)
            } else if display.contains(term) || owner.contains(term) || itemTitle.contains(term) {
                score = min(score, 50)
            } else if bundle.contains(term) {
                score = min(score, 70)
            }
        }
        return score + max(0, display.count - query.count)
    }

    static func collapsedLength(screenWidths: [CGFloat]) -> CGFloat {
        let widest = screenWidths.max() ?? 2_048
        return min(max(widest * 2, 4_096), 16_384)
    }

    static func section(itemMidX: CGFloat,
                        hiddenDividerMidX: CGFloat?,
                        alwaysHiddenDividerMidX: CGFloat?) -> MenuBarOrganizerSection {
        guard let hiddenX = hiddenDividerMidX else { return .visible }
        if let alwaysX = alwaysHiddenDividerMidX, itemMidX < alwaysX {
            return .alwaysHidden
        }
        if itemMidX < hiddenX {
            return .hidden
        }
        return .visible
    }

    static func identities(for records: [MenuBarOrganizerWindowRecord]) -> [CGWindowID: MenuBarItemIdentity] {
        var occurrences: [String: Int] = [:]
        var result: [CGWindowID: MenuBarItemIdentity] = [:]
        for record in records.sorted(by: {
            if $0.bundleIdentifier != $1.bundleIdentifier {
                return $0.bundleIdentifier < $1.bundleIdentifier
            }
            if $0.title != $1.title { return $0.title < $1.title }
            // Window ids stay stable while an item is reordered. Using x here
            // would swap duplicate identities during the very move being
            // verified.
            return $0.windowID < $1.windowID
        }) {
            let key = "\(record.bundleIdentifier)\u{0}\(record.title)"
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            result[record.windowID] = MenuBarItemIdentity(bundleIdentifier: record.bundleIdentifier,
                                                          title: record.title,
                                                          occurrence: occurrence)
        }
        return result
    }

    static func isLikelyMenuBarWindow(_ record: MenuBarOrganizerWindowRecord,
                                      statusLevel: Int,
                                      screenTopEdges: [CGFloat]) -> Bool {
        guard record.layer == statusLevel,
              record.alpha > 0,
              record.frame.width > 0,
              record.frame.height > 0,
              record.frame.height <= 64
        else { return false }
        return screenTopEdges.contains { abs(record.frame.maxY - $0) <= 8 || abs(record.frame.minY - $0) <= 8 }
            || record.frame.minY <= 8
    }

    static func isSystemImmovable(bundleIdentifier: String, title: String) -> Bool {
        let normalized = title.lowercased()
        if bundleIdentifier == "com.apple.controlcenter" {
            return normalized.contains("clock") || normalized.contains("siri")
        }
        return bundleIdentifier == "com.apple.systemuiserver"
            && (normalized.contains("clock") || normalized.contains("notification"))
    }

    static func shouldUseSecondaryBar(mode: MenuBarOrganizerPresentationMode,
                                      hiddenWidth: CGFloat,
                                      availableWidth: CGFloat,
                                      hasNotch: Bool) -> Bool {
        switch mode {
        case .secondaryBar:
            return true
        case .menuBar:
            return false
        case .automatic:
            return hasNotch || hiddenWidth > max(availableWidth, 0)
        }
    }

    static func shouldUseSmartNotchMode(mode: MenuBarOrganizerPresentationMode,
                                        enabled: Bool,
                                        hasNotch: Bool) -> Bool {
        mode == .automatic && enabled && hasNotch
    }

    static func orderedItems(_ items: [ManagedMenuBarItem],
                             in section: MenuBarOrganizerSection) -> [ManagedMenuBarItem] {
        items.filter { $0.section == section }.sorted { $0.frame.minX < $1.frame.minX }
    }
}
