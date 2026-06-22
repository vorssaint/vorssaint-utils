// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

struct GlobalShortcutModifiers: OptionSet, Hashable {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let control = GlobalShortcutModifiers(rawValue: 1 << 0)
    static let option = GlobalShortcutModifiers(rawValue: 1 << 1)
    static let shift = GlobalShortcutModifiers(rawValue: 1 << 2)
    static let command = GlobalShortcutModifiers(rawValue: 1 << 3)

    static let validMask: GlobalShortcutModifiers = [.control, .option, .shift, .command]

    var hasPrimaryModifier: Bool {
        contains(.control) || contains(.option) || contains(.command)
    }

    var cgFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.command) { flags.insert(.maskCommand) }
        return flags
    }

    var carbonFlags: UInt32 {
        var flags = UInt32(0)
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }

    var keyCaps: [String] {
        var caps: [String] = []
        if contains(.control) { caps.append("⌃") }
        if contains(.option) { caps.append("⌥") }
        if contains(.shift) { caps.append("⇧") }
        if contains(.command) { caps.append("⌘") }
        return caps
    }

    var storageTokens: [String] {
        var tokens: [String] = []
        if contains(.control) { tokens.append("control") }
        if contains(.option) { tokens.append("option") }
        if contains(.shift) { tokens.append("shift") }
        if contains(.command) { tokens.append("command") }
        return tokens
    }

    init(cgFlags: CGEventFlags) {
        var modifiers: GlobalShortcutModifiers = []
        if cgFlags.contains(.maskControl) { modifiers.insert(.control) }
        if cgFlags.contains(.maskAlternate) { modifiers.insert(.option) }
        if cgFlags.contains(.maskShift) { modifiers.insert(.shift) }
        if cgFlags.contains(.maskCommand) { modifiers.insert(.command) }
        self = modifiers
    }

    init(eventFlags: NSEvent.ModifierFlags) {
        var modifiers: GlobalShortcutModifiers = []
        if eventFlags.contains(.control) { modifiers.insert(.control) }
        if eventFlags.contains(.option) { modifiers.insert(.option) }
        if eventFlags.contains(.shift) { modifiers.insert(.shift) }
        if eventFlags.contains(.command) { modifiers.insert(.command) }
        self = modifiers
    }
}

struct GlobalShortcut: Equatable, Hashable {
    let keyCode: Int64
    let modifiers: GlobalShortcutModifiers

    init(keyCode: Int64, modifiers: GlobalShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.validMask)
    }

    init?(storageValue: String) {
        let parts = storageValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let keyCode = Int64(parts[1]) else { return nil }
        var modifiers: GlobalShortcutModifiers = []
        for token in parts[0].split(separator: "+") {
            switch token {
            case "control": modifiers.insert(.control)
            case "option": modifiers.insert(.option)
            case "shift": modifiers.insert(.shift)
            case "command": modifiers.insert(.command)
            default: return nil
            }
        }
        self.init(keyCode: keyCode, modifiers: modifiers)
        guard isValid else { return nil }
    }

    init?(event: NSEvent) {
        let shortcut = GlobalShortcut(keyCode: Int64(event.keyCode),
                                      modifiers: GlobalShortcutModifiers(eventFlags: event.modifierFlags))
        guard shortcut.isValid else { return nil }
        self = shortcut
    }

    static let keepAwakeDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_K),
                                                 modifiers: [.control, .option, .command])
    static let shelfDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_D),
                                             modifiers: [.control, .option, .command])
    static let switcherDefault = GlobalShortcut(keyCode: Int64(kVK_Tab),
                                                modifiers: [.command])

    static func saved(for key: String, fallback: GlobalShortcut) -> GlobalShortcut {
        if let raw = UserDefaults.standard.string(forKey: key),
           let shortcut = GlobalShortcut(storageValue: raw) {
            return shortcut
        }
        return fallback
    }

    var storageValue: String {
        "\(modifiers.storageTokens.joined(separator: "+")):\(keyCode)"
    }

    var isValid: Bool {
        modifiers.hasPrimaryModifier && keyLabel != nil
    }

    var displayString: String {
        keyCaps.joined()
    }

    var keyCaps: [String] {
        modifiers.keyCaps + [keyLabel ?? "Key \(keyCode)"]
    }

    var carbonKeyCode: UInt32 {
        UInt32(keyCode)
    }

    var carbonModifiers: UInt32 {
        modifiers.carbonFlags
    }

    func matches(event: CGEvent, allowingExtraShift: Bool = false) -> Bool {
        guard event.getIntegerValueField(.keyboardEventKeycode) == keyCode else { return false }
        let actual = GlobalShortcutModifiers(cgFlags: event.flags)
        if allowingExtraShift, !modifiers.contains(.shift) {
            return actual.subtracting(.shift) == modifiers
        }
        return actual == modifiers
    }

    func requiredModifiersHeld(in flags: CGEventFlags) -> Bool {
        let actual = GlobalShortcutModifiers(cgFlags: flags)
        return actual.intersection(modifiers) == modifiers
    }

    var shiftIsNavigationModifier: Bool {
        !modifiers.contains(.shift)
    }

    private var keyLabel: String? {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Tab: return "Tab"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Escape: return "Esc"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return nil
        }
    }
}

enum GlobalShortcutRole: CaseIterable, Identifiable {
    case keepAwake
    case shelf
    case switcher

    var id: String { storageKey }

    var storageKey: String {
        switch self {
        case .keepAwake: return DefaultsKey.keepAwakeShortcut
        case .shelf: return DefaultsKey.shelfShortcut
        case .switcher: return DefaultsKey.switcherShortcut
        }
    }

    var defaultShortcut: GlobalShortcut {
        switch self {
        case .keepAwake: return .keepAwakeDefault
        case .shelf: return .shelfDefault
        case .switcher: return .switcherDefault
        }
    }

    var savedShortcut: GlobalShortcut {
        GlobalShortcut.saved(for: storageKey, fallback: defaultShortcut)
    }

    func title(_ strings: Strings) -> String {
        switch self {
        case .keepAwake: return strings.keepAwakeTitle
        case .shelf: return strings.shelfName
        case .switcher: return strings.switcherSection
        }
    }

    static func conflict(for shortcut: GlobalShortcut, excluding role: GlobalShortcutRole) -> GlobalShortcutRole? {
        allCases.first { candidate in
            candidate != role && candidate.savedShortcut == shortcut
        }
    }
}
