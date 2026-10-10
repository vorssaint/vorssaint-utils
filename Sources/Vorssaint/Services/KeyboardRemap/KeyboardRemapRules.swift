// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import CoreGraphics
import Foundation

struct KeyboardRemapKey: Identifiable, Equatable {
    let id: String
    let label: String
    let usage: UInt64
    let code: Int64
    var displayLabel: String {
        if isModifier, id.hasPrefix("left") || id.hasPrefix("right") {
            let side = id.hasPrefix("left") ? "left" : "right"
            return KeyboardRemapStrings.text(side) + " " + (label.split(separator: " ").last.map(String.init) ?? label)
        }
        if (0x700000004...0x700000038).contains(usage), code != Int64(kVK_CapsLock) {
            return GlobalShortcut.layoutKeyLabel(for: code, usesCommand: true) ?? label
        }
        return label
    }
    var readableLabel: String {
        switch id {
        case "home": return KeyboardRemapStrings.text("homeKey")
        case "end": return KeyboardRemapStrings.text("endKey")
        case "leftArrow": return KeyboardRemapStrings.text("leftArrowKey")
        case "rightArrow": return KeyboardRemapStrings.text("rightArrowKey")
        case "leftCommand", "rightCommand", "leftControl", "rightControl", "leftOption", "rightOption", "leftShift", "rightShift":
            let side = id.hasPrefix("left") ? "left" : "right"
            let name = String(id.dropFirst(side.count)).lowercased() + "Key"
            return KeyboardRemapStrings.text(side) + " " + KeyboardRemapStrings.text(name)
        default: return displayLabel
        }
    }
    var isModifier: Bool { (0x7000000E0...0x7000000E7).contains(usage) || id == "fn" }
    static func named(_ id: String) -> Self? { all.first { $0.id == id } }
    static func at(_ code: Int64) -> Self? { all.first { $0.code == code } }

    static let all: [Self] = {
        var keys: [Self] = [
            .init(id: "fn", label: "Fn / 🌐", usage: 0xFF00000003, code: Int64(kVK_Function)),
            .init(id: "capsLock", label: "Caps Lock", usage: 0x700000039, code: Int64(kVK_CapsLock)),
        ]
        let modifiers: [(String, String, Int64)] = [
            ("leftControl", "Left ⌃", Int64(kVK_Control)), ("leftShift", "Left ⇧", Int64(kVK_Shift)),
            ("leftOption", "Left ⌥", Int64(kVK_Option)), ("leftCommand", "Left ⌘", Int64(kVK_Command)),
            ("rightControl", "Right ⌃", Int64(kVK_RightControl)), ("rightShift", "Right ⇧", Int64(kVK_RightShift)),
            ("rightOption", "Right ⌥", Int64(kVK_RightOption)), ("rightCommand", "Right ⌘", Int64(kVK_RightCommand)),
        ]
        keys += modifiers.enumerated().map { i, item in
            .init(id: item.0, label: item.1, usage: 0x7000000E0 + UInt64(i), code: item.2)
        }
        let letters: [Int64] = [0,11,8,2,14,3,5,4,34,38,40,37,46,45,31,35,12,15,1,17,32,9,13,7,16,6]
        keys += letters.enumerated().map { i, code in
            let letter = String(UnicodeScalar(65 + i)!)
            return .init(id: letter.lowercased(), label: letter, usage: 0x700000004 + UInt64(i), code: code)
        }
        let numbers: [Int64] = [18,19,20,21,23,22,26,28,25,29]
        keys += numbers.enumerated().map { i, code in
            let number = String((i + 1) % 10)
            return .init(id: number, label: number, usage: 0x70000001E + UInt64(i), code: code)
        }
        let other: [(String, String, UInt64, Int64)] = [
            ("return", "↩", 0x28, 36), ("escape", "Esc", 0x29, 53), ("delete", "⌫", 0x2A, 51),
            ("tab", "⇥", 0x2B, 48), ("space", "Space", 0x2C, 49),
            ("minus", "−", 0x2D, 27), ("equal", "=", 0x2E, 24),
            ("leftBracket", "[", 0x2F, 33), ("rightBracket", "]", 0x30, 30),
            ("backslash", "\\", 0x31, 42), ("semicolon", ";", 0x33, 41),
            ("quote", "'", 0x34, 39), ("grave", "`", 0x35, 50),
            ("comma", ",", 0x36, 43), ("period", ".", 0x37, 47), ("slash", "/", 0x38, 44),
            ("home", "Home", 0x4A, 115), ("pageUp", "Page ↑", 0x4B, 116),
            ("forwardDelete", "⌦", 0x4C, 117), ("end", "End", 0x4D, 119), ("pageDown", "Page ↓", 0x4E, 121),
            ("rightArrow", "→", 0x4F, 124), ("leftArrow", "←", 0x50, 123),
            ("downArrow", "↓", 0x51, 125), ("upArrow", "↑", 0x52, 126),
        ]
        keys += other.map { .init(id: $0.0, label: $0.1, usage: 0x700000000 + $0.2, code: $0.3) }
        let functions: [Int64] = [122,120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80,90]
        keys += functions.enumerated().map { i, code in
            .init(id: "f\(i + 1)", label: "F\(i + 1)", usage: i < 12 ? 0x70000003A + UInt64(i) : 0x700000068 + UInt64(i - 12), code: code)
        }
        return keys
    }()
}

/// Unlike global app shortcuts, remap rules also accept bare keys and Shift.
struct KeyboardRemapChord: Codable, Equatable {
    var keyCode: Int64
    var modifiers: Int
    /// Optional logical character matched through the layout's Command table.
    /// Recorded rules instead match the captured physical key code.
    var character: String?
    init(_ key: Int64, _ modifiers: GlobalShortcutModifiers = [], character: String? = nil) {
        keyCode = key; self.modifiers = modifiers.rawValue; self.character = character
    }
    var shortcut: GlobalShortcut { .init(keyCode: keyCode, modifiers: .init(rawValue: modifiers)) }
    var label: String {
        if let character { return shortcut.modifiers.keyCaps.joined() + character.uppercased() }
        if let key = KeyboardRemapKey.at(keyCode), key.id == "capsLock" || key.isModifier {
            return shortcut.modifiers.keyCaps.joined() + key.displayLabel
        }
        return shortcut.displayString
    }
    /// Plain key names for previews, avoiding ambiguous Home/End/arrow glyphs.
    var readableLabel: String {
        let modifiers = shortcut.modifiers
        var parts: [String] = []
        for (flag, name): (GlobalShortcutModifiers, String) in [(.control, "controlKey"), (.option, "optionKey"), (.shift, "shiftKey"), (.command, "commandKey")] {
            if modifiers.contains(flag) { parts.append(KeyboardRemapStrings.text(name)) }
        }
        parts.append(character?.uppercased() ?? KeyboardRemapKey.at(keyCode)?.readableLabel ?? label)
        return parts.joined(separator: " + ")
    }
    var isQuitShortcut: Bool {
        shortcut.modifiers == .command
            && (character?.lowercased() == "q" || (character == nil
                && GlobalShortcut.layoutKeyLabel(for: keyCode, usesCommand: true)?.lowercased() == "q"))
    }
    var outputLabel: String {
        isQuitShortcut ? KeyboardRemapStrings.text("quitApp") + " (" + readableLabel + ")" : readableLabel
    }
    func matches(key: Int64, flags: CGEventFlags, commandLabel: String?) -> Bool {
        shortcut.modifiers == GlobalShortcutModifiers(cgFlags: flags)
            && (character.map { $0.lowercased() == commandLabel?.lowercased() } ?? (keyCode == key))
    }
}

enum KeyboardRemapTarget: Codable, Equatable {
    case key(String)
    case shortcut(KeyboardRemapChord)
    case none, inputSource, capsLock
    case application(String) // bundle identifier, not a machine-specific path

    var kind: String {
        switch self {
        case .key: "key"
        case .shortcut: "shortcut"
        case .none: "none"
        case .inputSource: "inputSource"
        case .capsLock: "capsLock"
        case .application: "application"
        }
    }
    var label: String {
        switch self {
        case .key(let id): KeyboardRemapKey.named(id)?.displayLabel ?? id
        case .shortcut(let chord): chord.outputLabel
        case .none: KeyboardRemapStrings.text("doNothing")
        case .inputSource: KeyboardRemapStrings.text("nextLanguage")
        case .capsLock: KeyboardRemapStrings.text("toggleCaps")
        case .application(let id): id
        }
    }
}

struct KeyboardRemapKeyRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var enabled = true
    var source: String
    var target: KeyboardRemapTarget
    init(_ source: String, _ target: KeyboardRemapTarget) { self.source = source; self.target = target }
}

struct KeyboardRemapShortcutRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var enabled = true
    var source: KeyboardRemapChord
    var target: KeyboardRemapTarget
    init(_ source: KeyboardRemapChord, _ target: KeyboardRemapTarget) { self.source = source; self.target = target }
}

struct KeyboardRemapConfiguration: Equatable {
    var keyRules: [KeyboardRemapKeyRule] = []
    var shortcutRules: [KeyboardRemapShortcutRule] = []
    init() {}
    init(defaults: UserDefaults) {
        keyRules = Self.decode(defaults.string(forKey: DefaultsKey.keyboardRemapKeyRules) ?? "[]") ?? []
        shortcutRules = Self.decode(defaults.string(forKey: DefaultsKey.keyboardRemapShortcutRules) ?? "[]") ?? []
    }
    static func decode<T: Decodable>(_ value: String) -> T? {
        guard let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
    func save(to defaults: UserDefaults) {
        defaults.set(Self.encode(keyRules), forKey: DefaultsKey.keyboardRemapKeyRules)
        defaults.set(Self.encode(shortcutRules), forKey: DefaultsKey.keyboardRemapShortcutRules)
    }

    /// Virtual triggers make lock/modifier keys usable for actions. F18 stays
    /// reserved for Super Key. Trigger assignment is deterministic per config.
    static let triggerKeys = ["f19", "f20", "f17", "f16", "f15", "f14", "f13"].compactMap(KeyboardRemapKey.named)
    var actionSources: [KeyboardRemapKey] {
        var result = keyRules.filter(\.enabled).compactMap { rule -> KeyboardRemapKey? in
            if case .key = rule.target { return nil }
            return KeyboardRemapKey.named(rule.source)
        }
        for rule in shortcutRules where rule.enabled {
            if let key = KeyboardRemapKey.at(rule.source.keyCode), key.id == "capsLock",
               !keyRules.contains(where: { $0.enabled && $0.source == key.id }),
               !result.contains(key) { result.append(key) }
        }
        return result
    }
    private var availableTriggers: [KeyboardRemapKey] {
        var occupied = Set<Int64>()
        for rule in keyRules where rule.enabled {
            if let source = KeyboardRemapKey.named(rule.source) { occupied.insert(source.code) }
            if case .key(let id) = rule.target, let target = KeyboardRemapKey.named(id) { occupied.insert(target.code) }
            if case .shortcut(let chord) = rule.target { occupied.insert(chord.keyCode) }
        }
        for rule in shortcutRules where rule.enabled {
            occupied.insert(rule.source.keyCode)
            if case .shortcut(let chord) = rule.target { occupied.insert(chord.keyCode) }
        }
        return Self.triggerKeys.filter { !occupied.contains($0.code) }
    }
    var triggers: [(source: KeyboardRemapKey, trigger: KeyboardRemapKey)] {
        Array(zip(actionSources, availableTriggers)).map { ($0.0, $0.1) }
    }
    var mappings: [SuperKeyMapping] {
        let plain = keyRules.filter(\.enabled).compactMap { rule -> SuperKeyMapping? in
            guard case .key(let id) = rule.target, let from = KeyboardRemapKey.named(rule.source),
                  let to = KeyboardRemapKey.named(id) else { return nil }
            return .init(source: from.usage, destination: to.usage)
        }
        return plain + triggers.map { .init(source: $0.source.usage, destination: $0.trigger.usage) }
    }
    var validationKey: String? {
        if Set(keyRules.map(\.id)).count != keyRules.count
            || Set(shortcutRules.map(\.id)).count != shortcutRules.count { return "duplicateRule" }
        let activeKeys = keyRules.filter(\.enabled)
        let activeShortcuts = shortcutRules.filter(\.enabled)
        if Set(activeKeys.map(\.source)).count != activeKeys.count { return "duplicateRule" }
        for (i, rule) in activeShortcuts.enumerated() {
            if activeShortcuts.prefix(i).contains(where: { Self.overlap($0.source, rule.source) }) { return "duplicateRule" }
        }
        if actionSources.count > Self.triggerKeys.count { return "tooManyActions" }
        if actionSources.count > availableTriggers.count { return "reservedKey" }
        for rule in activeKeys {
            guard KeyboardRemapKey.named(rule.source) != nil else { return "invalidRule" }
            if case .key(let id) = rule.target {
                if KeyboardRemapKey.named(id) == nil || id == rule.source { return "invalidRule" }
            }
            if !valid(rule.target, keyRule: true) { return "invalidRule" }
        }
        for rule in activeShortcuts {
            if rule.source.keyCode == Int64(kVK_CapsLock),
               let existing = activeKeys.first(where: { $0.source == "capsLock" }),
               case .key = existing.target { return "sourceRemapped" }
            if !valid(rule.target, keyRule: false) || !valid(rule.source, source: true) { return "invalidRule" }
            if case .shortcut(let chord) = rule.target, chord == rule.source { return "invalidRule" }
        }
        let reserved = Set(triggers.map { $0.trigger.id })
        if activeKeys.contains(where: { rule in
            if reserved.contains(rule.source) { return true }
            if case .key(let id) = rule.target { return reserved.contains(id) }
            return false
        }) { return "reservedKey" }
        if activeShortcuts.contains(where: { rule in
            guard let id = KeyboardRemapKey.at(rule.source.keyCode)?.id else { return false }
            if reserved.contains(id) { return true }
            if case .shortcut(let chord) = rule.target,
               let destination = KeyboardRemapKey.at(chord.keyCode) { return reserved.contains(destination.id) }
            return false
        }) { return "reservedKey" }
        return nil
    }
    private func valid(_ chord: KeyboardRemapChord, source: Bool = false) -> Bool {
        guard let key = KeyboardRemapKey.at(chord.keyCode),
              !key.isModifier || (source && actionSources.contains(key)),
              chord.modifiers & ~GlobalShortcutModifiers.validMask.rawValue == 0 else { return false }
        return chord.character == nil || chord.character?.count == 1
    }
    private func valid(_ target: KeyboardRemapTarget, keyRule: Bool) -> Bool {
        switch target {
        case .application(let id): return !id.isEmpty
        case .shortcut(let chord): return valid(chord) && chord.keyCode != Int64(kVK_CapsLock)
        case .key(let id): return keyRule && KeyboardRemapKey.named(id) != nil
        default: return true
        }
    }
    var isEmpty: Bool { !keyRules.contains(where: \.enabled) && !shortcutRules.contains(where: \.enabled) }

    /// Append only missing suggestions, preserving every custom rule and choice.
    mutating func addSuggestion(_ preset: KeyboardRemapPreset) {
        let suggestion = preset.configuration
        for rule in suggestion.keyRules where !keyRules.contains(where: { $0.source == rule.source }) { keyRules.append(rule) }
        for rule in suggestion.shortcutRules where !shortcutRules.contains(where: { Self.overlap($0.source, rule.source) }) {
            if rule.source.keyCode == Int64(kVK_CapsLock),
               let existing = keyRules.first(where: { $0.enabled && $0.source == "capsLock" }),
               case .key = existing.target { continue }
            shortcutRules.append(rule)
        }
    }

    private static func overlap(_ first: KeyboardRemapChord, _ second: KeyboardRemapChord) -> Bool {
        first.modifiers == second.modifiers && (first.keyCode == second.keyCode
            || (first.character != nil && first.character == second.character))
    }

}

/// Focused alternatives, never installed automatically or combined as a default.
enum KeyboardRemapPreset: String, CaseIterable, Identifiable {
    case capsEscape, capsControl, lineNavigation, saferQuit, fnLanguages
    var id: String { rawValue }
    var titleKey: String { "preset_" + rawValue }
    var noteKey: String { titleKey + "_note" }
    var configuration: KeyboardRemapConfiguration {
        var result = KeyboardRemapConfiguration()
        switch self {
        case .capsEscape:
            result.keyRules = [.init("capsLock", .key("escape"))]
        case .capsControl:
            result.keyRules = [.init("capsLock", .key("leftControl"))]
        case .lineNavigation:
            for modifiers: GlobalShortcutModifiers in [[], .shift] {
                result.shortcutRules.append(.init(.init(Int64(kVK_Home), modifiers),
                    .shortcut(.init(Int64(kVK_LeftArrow), modifiers.union(.command)))))
                result.shortcutRules.append(.init(.init(Int64(kVK_End), modifiers),
                    .shortcut(.init(Int64(kVK_RightArrow), modifiers.union(.command)))))
            }
        case .saferQuit:
            result.shortcutRules = [
                .init(.init(12, .command, character: "q"), .none),
                .init(.init(12, .option, character: "q"), .shortcut(.init(12, .command, character: "q")))
            ]
        case .fnLanguages:
            result.keyRules = [.init("fn", .key("leftCommand")), .init("capsLock", .inputSource)]
            result.shortcutRules = [.init(.init(Int64(kVK_CapsLock), .shift), .capsLock)]
        }
        return result
    }
}
