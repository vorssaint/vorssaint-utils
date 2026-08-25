// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

/// The keys an override can control. The system keys need a keyboard-level remap. The raw values are stored identities. F18 is not here because the Super key uses it.
enum KeyOverrideKey: String, CaseIterable, Codable {
    case missionControl, spotlight, dictation, focus, launchpad
    case f13, f14, f15, f16, f17, f19, f20

    /// The HID usage that the special key sends. Nil for keys that arrive as normal key events.
    var reclaimSource: UInt64? {
        switch self {
        case .missionControl: return 0xFF01_0000_0010 // Exposé All
        case .launchpad: return 0xFF01_0000_0004
        case .spotlight: return 0xC_0000_0221         // AC Search
        case .dictation: return 0xC_0000_00CF         // Voice Command
        case .focus: return 0x1_0000_009B             // System Do Not Disturb
        case .f13, .f14, .f15, .f16, .f17, .f19, .f20: return nil
        }
    }

    /// The keyboard-page usage of the plain function key on the same keycap.
    var reclaimDestination: UInt64? {
        switch self {
        case .missionControl: return 0x7_0000_003C // F3
        case .spotlight, .launchpad: return 0x7_0000_003D // F4
        case .dictation: return 0x7_0000_003E // F5
        case .focus: return 0x7_0000_003F // F6
        case .f13, .f14, .f15, .f16, .f17, .f19, .f20: return nil
        }
    }

    /// The virtual key code that the key sends after the remap.
    var keyCode: Int64 {
        switch self {
        case .missionControl: return Int64(kVK_F3)
        case .spotlight, .launchpad: return Int64(kVK_F4)
        case .dictation: return Int64(kVK_F5)
        case .focus: return Int64(kVK_F6)
        case .f13: return Int64(kVK_F13)
        case .f14: return Int64(kVK_F14)
        case .f15: return Int64(kVK_F15)
        case .f16: return Int64(kVK_F16)
        case .f17: return Int64(kVK_F17)
        case .f19: return Int64(kVK_F19)
        case .f20: return Int64(kVK_F20)
        }
    }

    /// The plain key as a shortcut. The hotkey registers this.
    var triggerShortcut: GlobalShortcut {
        GlobalShortcut(keyCode: keyCode, modifiers: [])
    }

    /// The label on the keycap, for example "F5". All languages use the same label.
    var functionKeyLabel: String {
        GlobalShortcut(keyCode: keyCode, modifiers: []).displayString
    }

    static func sanitized(_ raw: String?) -> KeyOverrideKey? {
        raw.flatMap(KeyOverrideKey.init(rawValue:))
    }
}

/// What the key does in place of its macOS function.
enum KeyOverrideActionKind: String, CaseIterable {
    /// Only the remap. The key types its plain function key. Apps receive it.
    case remapOnly
    /// Toggles the system-wide microphone mute.
    case micMute
    /// Presses a key combination. The key can operate any shortcut.
    case pressShortcut

    static func sanitized(_ raw: String?) -> KeyOverrideActionKind? {
        raw.flatMap(KeyOverrideActionKind.init(rawValue:))
    }
}

struct KeyOverrideAction: Equatable {
    var kind: KeyOverrideActionKind
    /// Only pressShortcut has one. Nil means not set. Then no hotkey registers.
    var shortcut: GlobalShortcut?

    static let remapOnly = KeyOverrideAction(kind: .remapOnly, shortcut: nil)
    static let micMute = KeyOverrideAction(kind: .micMute, shortcut: nil)
}

/// One override: a key and its action.
struct KeyOverride: Identifiable, Equatable {
    let id: UUID
    var key: KeyOverrideKey
    var action: KeyOverrideAction
    var isEnabled: Bool

    init(id: UUID = UUID(),
         key: KeyOverrideKey,
         action: KeyOverrideAction,
         isEnabled: Bool = true) {
        self.id = id
        self.key = key
        self.action = action
        self.isEnabled = isEnabled
    }
}

/// The pure logic: the storage codec, the remap and hotkey selection, and the mapping-table composition.
enum KeyOverrideSupport {
    // MARK: - Storage

    /// Stored as JSON. The list survives export, import, and manual edits.
    private struct StoredOverride: Codable {
        var id: String?
        var key: String
        var action: String
        var shortcut: String?
        var enabled: Bool?
    }

    /// Decodes a stored list. It removes entries that do not parse.
    static func decode(_ data: Data?) -> [KeyOverride] {
        guard let data,
              let stored = try? JSONDecoder().decode([StoredOverride].self, from: data)
        else { return [] }
        return sanitized(stored.compactMap { entry in
            guard let key = KeyOverrideKey.sanitized(entry.key),
                  let kind = KeyOverrideActionKind.sanitized(entry.action)
            else { return nil }
            let shortcut = kind == .pressShortcut
                ? entry.shortcut.flatMap(GlobalShortcut.init(storageValue:))
                : nil
            return KeyOverride(id: entry.id.flatMap(UUID.init(uuidString:)) ?? UUID(),
                               key: key,
                               action: KeyOverrideAction(kind: kind, shortcut: shortcut),
                               isEnabled: entry.enabled ?? true)
        })
    }

    static func encode(_ overrides: [KeyOverride]) -> Data? {
        let stored = overrides.map { override in
            StoredOverride(id: override.id.uuidString,
                           key: override.key.rawValue,
                           action: override.action.kind.rawValue,
                           shortcut: override.action.shortcut?.storageValue,
                           enabled: override.isEnabled)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(stored)
    }

    /// One override per key code. Spotlight and Launchpad share F4. The first entry wins.
    static func sanitized(_ overrides: [KeyOverride]) -> [KeyOverride] {
        var seenKeyCodes: Set<Int64> = []
        return overrides.filter { seenKeyCodes.insert($0.key.keyCode).inserted }
    }

    /// The default set. Dictation mutes the microphone. Spotlight and Focus become plain F4 and F6.
    static func commonOverrides() -> [KeyOverride] {
        [KeyOverride(key: .dictation, action: .micMute),
         KeyOverride(key: .spotlight, action: .remapOnly),
         KeyOverride(key: .focus, action: .remapOnly)]
    }

    // MARK: - What the list asks for

    /// The keys that need the keyboard-level remap. Every action needs it, remap-only included.
    static func reclaimedKeys(in overrides: [KeyOverride]) -> [KeyOverrideKey] {
        overrides.filter { $0.isEnabled && $0.key.reclaimSource != nil }.map(\.key)
    }

    /// The overrides that get a hotkey. Remap-only gets none. An empty shortcut gets none. A bare shortcut that equals an enabled override's trigger gets none, because posting it would fire that hotkey in a loop.
    static func boundOverrides(in overrides: [KeyOverride],
                               micMuteAvailable: Bool) -> [KeyOverride] {
        let triggerKeyCodes = Set(overrides.filter(\.isEnabled).map(\.key.keyCode))
        return overrides.filter { override in
            guard override.isEnabled else { return false }
            switch override.action.kind {
            case .remapOnly:
                return false
            case .micMute:
                return micMuteAvailable
            case .pressShortcut:
                guard let shortcut = override.action.shortcut else { return false }
                return !(shortcut.modifiers.isEmpty
                    && triggerKeyCodes.contains(shortcut.keyCode))
            }
        }
    }

    /// Only the synthetic key press needs the Accessibility permission.
    static func needsAccessibility(_ overrides: [KeyOverride]) -> Bool {
        overrides.contains {
            $0.isEnabled && $0.action.kind == .pressShortcut && $0.action.shortcut != nil
        }
    }

    // MARK: - The keyboard mapping table

    /// True for a mapping entry that this feature creates.
    static func isOwnedMapping(_ mapping: SuperKeyMapping) -> Bool {
        KeyOverrideKey.allCases.contains {
            $0.reclaimSource == mapping.source && $0.reclaimDestination == mapping.destination
        }
    }

    /// The table to write. Our entries come first. External entries stay unchanged, the Super key entry included.
    static func mappings(reclaiming keys: [KeyOverrideKey],
                         existing: [SuperKeyMapping]) -> [SuperKeyMapping] {
        let others = existing.filter { !isOwnedMapping($0) }
        var seenSources: Set<UInt64> = []
        let owned: [SuperKeyMapping] = keys.compactMap { key in
            guard let source = key.reclaimSource,
                  let destination = key.reclaimDestination,
                  seenSources.insert(source).inserted
            else { return nil }
            return SuperKeyMapping(source: source, destination: destination)
        }
        return owned + others
    }

    /// True when an external entry remaps a wanted key. The feature then refuses to start.
    static func hasMappingConflict(in existing: [SuperKeyMapping],
                                   reclaiming keys: [KeyOverrideKey]) -> Bool {
        let sources = Set(keys.compactMap(\.reclaimSource))
        return existing.contains { sources.contains($0.source) && !isOwnedMapping($0) }
    }

    /// Returns one table only when all keyboards report the same external mappings, through the Super key's shared core. The Super key's entries are the partner shape: ignored for the comparison, carried along in the write.
    static func consistentMappings(_ report: String,
                                   ownsExistingMapping: Bool) -> [SuperKeyMapping]? {
        SuperKeySupport.consistentMappings(
            report,
            property: SuperKeySupport.userMappingProperty,
            settingAside: ownsExistingMapping ? isOwnedMapping : { _ in false },
            propagating: SuperKeySupport.isOwnedMapping)
    }
}
