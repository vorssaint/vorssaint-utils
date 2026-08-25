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
        guard let separator = storageValue.firstIndex(of: ":"),
              let keyCode = Int64(storageValue[storageValue.index(after: separator)...])
        else { return nil }
        var modifiers: GlobalShortcutModifiers = []
        for token in storageValue[..<separator].split(separator: "+") {
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

    /// Delete on its own means "take the shortcut off" while a shortcut field
    /// is listening, which is how every shortcut field on this system behaves.
    /// Held together with Control, Option or Command it is an ordinary key and
    /// records like any other.
    static func clearsShortcut(keyCode: Int64, modifiers: GlobalShortcutModifiers) -> Bool {
        guard keyCode == Int64(kVK_Delete) || keyCode == Int64(kVK_ForwardDelete)
        else { return false }
        return !modifiers.hasPrimaryModifier
    }

    static let keepAwakeDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_K),
                                                 modifiers: [.control, .option, .command])
    static let shelfDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_D),
                                             modifiers: [.control, .option, .command])
    static let switcherDefault = GlobalShortcut(keyCode: Int64(kVK_Tab),
                                                modifiers: [.command])
    static let switcherWindowDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_Grave),
                                                      modifiers: [.command])
    static let clipboardDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_V),
                                                 modifiers: [.control, .option, .command])
    static let soundOutputSwitcherDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_S),
                                                           modifiers: [.control, .option, .command])
    static let windowLayoutLeftDefault = GlobalShortcut(keyCode: Int64(kVK_LeftArrow),
                                                        modifiers: [.control, .option])
    static let windowLayoutRightDefault = GlobalShortcut(keyCode: Int64(kVK_RightArrow),
                                                         modifiers: [.control, .option])
    static let windowLayoutTopDefault = GlobalShortcut(keyCode: Int64(kVK_UpArrow),
                                                       modifiers: [.control, .option])
    static let windowLayoutBottomDefault = GlobalShortcut(keyCode: Int64(kVK_DownArrow),
                                                          modifiers: [.control, .option])
    static let windowLayoutTopLeftDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_U),
                                                           modifiers: [.control, .option])
    static let windowLayoutTopRightDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_I),
                                                            modifiers: [.control, .option])
    static let windowLayoutBottomLeftDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_J),
                                                              modifiers: [.control, .option])
    static let windowLayoutBottomRightDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_K),
                                                               modifiers: [.control, .option])
    static let windowLayoutMaximizeDefault = GlobalShortcut(keyCode: Int64(kVK_Return),
                                                            modifiers: [.control, .option])
    static let windowLayoutCenterDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_C),
                                                          modifiers: [.control, .option])
    static let windowLayoutRestoreDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_R),
                                                           modifiers: [.control, .option])
    static let windowLayoutLeftThirdDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_D),
                                                             modifiers: [.control, .option])
    static let windowLayoutCenterThirdDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_F),
                                                               modifiers: [.control, .option])
    static let windowLayoutRightThirdDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_G),
                                                              modifiers: [.control, .option])
    static let windowLayoutLeftTwoThirdsDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_E),
                                                                 modifiers: [.control, .option])
    static let windowLayoutRightTwoThirdsDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_T),
                                                                  modifiers: [.control, .option])
    static let windowLayoutNextDisplayDefault = GlobalShortcut(keyCode: Int64(kVK_RightArrow),
                                                               modifiers: [.control, .option, .command])
    static let windowDirectionalDefault = GlobalShortcut(keyCode: Int64(kVK_Space),
                                                         modifiers: [.control, .option])
    // Quick tools. Paste plain follows the universal "Paste and Match Style"
    // combination; the others use the free ⌃⌥⌘ letters.
    static let pastePlainDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_V),
                                                  modifiers: [.shift, .option, .command])
    static let finderRenameDefault = GlobalShortcut(keyCode: Int64(kVK_F2), modifiers: [])
    static let colorPickerDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_C),
                                                   modifiers: [.control, .option, .command])
    static let screenOCRDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_T),
                                                 modifiers: [.control, .option, .command])
    static let micMuteDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_M),
                                               modifiers: [.control, .option, .command])
    // W for webcam, on the same free control-option-command layer.
    static let cameraPreviewDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_W),
                                                     modifiers: [.control, .option, .command])
    // V for Vorssaint: the quick launcher's own combination.
    static let quickLauncherDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_V),
                                                     modifiers: [.control, .command])
    // Default screenshot shortcut on the available control-option-command layer.
    static let screenshotDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_4),
                                                  modifiers: [.control, .option, .command])
    // Full screen sits beside the selector's 4 and the recorder's 5.
    static let screenshotFullScreenDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_3),
                                                            modifiers: [.control, .option, .command])
    // E opens the latest capture in the editor, beside the capture shortcut.
    static let screenshotLastCaptureDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_E),
                                                             modifiers: [.control, .option, .command])
    // P opens a copied image in the editor, beside the other screenshot tools.
    static let screenshotClipboardDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_P),
                                                           modifiers: [.control, .option, .command])
    // Space for the wheel, on the same free control-option-command layer.
    static let radialMenuDefault = GlobalShortcut(keyCode: Int64(kVK_Space),
                                                  modifiers: [.control, .option, .command])
    // N for notes, on the same free control-option-command layer.
    static let scratchpadDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_N),
                                                  modifiers: [.control, .option, .command])
    // L for library (S already belongs to the sound output switcher), on the
    // same free control-option-command layer.
    static let snippetLibraryDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_L),
                                                      modifiers: [.control, .option, .command])
    // Option-Space, the combination mature launchers settled on: one thumb
    // and one finger, mirroring the system search's Command-Space without
    // fighting it for the key. Registered as a hotkey it never types the
    // narrow space some layouts put on that combination.
    static let commandBarDefault = GlobalShortcut(keyCode: Int64(kVK_Space),
                                                  modifiers: [.option])
    // Next to the screenshot's 4, on the same free control-option-command
    // layer, matching how the system numbers its own capture keys.
    static let screenRecorderDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_5),
                                                      modifiers: [.control, .option, .command])

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

    /// The range a virtual key code can occupy. A stored shortcut is just
    /// text, and it can arrive edited by hand or through an imported settings
    /// file, so the number is checked before anything converts it into the
    /// narrower types the system APIs take.
    static let keyCodeRange: ClosedRange<Int64> = 0...0xFFFF

    var hasUsableKeyCode: Bool { Self.keyCodeRange.contains(keyCode) }

    var isValid: Bool {
        hasUsableKeyCode && keyLabel != nil
            && (modifiers.hasPrimaryModifier || Self.standaloneFunctionKeys.contains(keyCode))
    }

    var displayString: String {
        let label = keyLabel ?? "Key \(keyCode)"
        let needsSeparator = label.count == 1
            && label.rangeOfCharacter(from: .alphanumerics) == nil
        return modifiers.keyCaps.joined() + (needsSeparator ? " " : "") + label
    }

    var keyCaps: [String] {
        modifiers.keyCaps + [keyLabel ?? "Key \(keyCode)"]
    }

    /// The shorter way to press a shortcut matching the configured Super key.
    func superKeyAlternative(capsLockLabel: String,
                             superKeyModifiers: GlobalShortcutModifiers) -> String? {
        guard superKeyModifiers.hasPrimaryModifier,
              modifiers == superKeyModifiers,
              let key = keyCaps.last else { return nil }
        return "\(capsLockLabel) + \(key)"
    }

    var carbonKeyCode: UInt32 {
        UInt32(exactly: keyCode) ?? 0
    }

    var carbonModifiers: UInt32 {
        modifiers.carbonFlags
    }

    /// Every flag a real press of this combination carries, for the places
    /// that have to synthesize one. The modifiers alone are not enough: the
    /// arrows, the F keys and the navigation block reach the system with the
    /// function flag on, the arrows and the keypad with the numeric pad flag
    /// on, and a synthesized press missing them matches no system-wide
    /// shortcut at all, even though the app in front still receives the key
    /// (issue #401, measured here: a shortcut on Control-Command-Right never
    /// fires without the function flag and always fires with it).
    var syntheticEventFlags: CGEventFlags {
        var flags = modifiers.cgFlags
        if Self.functionKeys.contains(keyCode) { flags.insert(.maskSecondaryFn) }
        if Self.numericPadKeys.contains(keyCode) { flags.insert(.maskNumericPad) }
        return flags
    }

    /// The function key group as this system defines it: the F row, the
    /// navigation block and the arrows.
    private static let functionKeys: Set<Int64> = Set(([
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        kVK_Help, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete,
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
    ] as [Int]).map(Int64.init))

    /// Function-row keys are safe without modifiers: unlike a bare letter,
    /// taking one never makes ordinary typing impossible. This also lets F2
    /// serve as Finder's familiar Rename key.
    private static let standaloneFunctionKeys: Set<Int64> = Set(([
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ] as [Int]).map(Int64.init))

    /// The keypad, plus the arrows, which this system counts as part of it.
    private static let numericPadKeys: Set<Int64> = Set(([
        kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4,
        kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9,
        kVK_ANSI_KeypadClear, kVK_ANSI_KeypadDecimal, kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadEnter,
        kVK_ANSI_KeypadEquals, kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadMultiply, kVK_ANSI_KeypadPlus,
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
    ] as [Int]).map(Int64.init))

    /// Paste as plain text ultimately posts the standard paste command. When
    /// that same command is its configured global shortcut, the registration
    /// must be released briefly or it catches the synthesized paste again.
    var isStandardPasteCommand: Bool {
        keyCode == Int64(kVK_ANSI_V) && modifiers == [.command]
    }

    /// `tolerating` lists modifiers that may be held beyond the shortcut's own
    /// without breaking the match. The switcher session passes its opening
    /// shortcut's modifiers here: they are necessarily still down while the
    /// panel is up, so a window shortcut like ⌥Tab must match even though ⌘ is
    /// held for the session (issue #187).
    func matches(event: CGEvent,
                 allowingExtraShift: Bool = false,
                 tolerating extra: GlobalShortcutModifiers = []) -> Bool {
        guard event.getIntegerValueField(.keyboardEventKeycode) == keyCode else { return false }
        return modifiersMatch(event: event, allowingExtraShift: allowingExtraShift, tolerating: extra)
    }

    func matches(keyCode: Int64, modifiers actual: GlobalShortcutModifiers) -> Bool {
        keyCode == self.keyCode && actual == modifiers
    }

    /// Layout-tolerant match: true when the pressed key would type the same
    /// character this shortcut displays. Key codes are positions on a US
    /// keyboard, so a default like ⌘` lands on a different position for ABNT2
    /// or German layouts, sometimes behind Shift or Option; the user goes by
    /// the character shown in Settings, not by the invisible ANSI position
    /// (issue #187). The character comes from the event itself, the same
    /// signal the switcher's search uses, so dead keys resolve identically.
    func matchesByCharacter(event: CGEvent,
                            tolerating extra: GlobalShortcutModifiers = []) -> Bool {
        let actual = GlobalShortcutModifiers(cgFlags: event.flags)
        // The shortcut's own modifiers must be down; Shift or Option on top is
        // tolerated because many layouts need them to produce the character,
        // and the caller may tolerate more (a session's held modifiers). Asked
        // before the label, since this runs for every key the tap sees.
        guard actual.intersection(modifiers) == modifiers,
              actual.subtracting(modifiers).subtracting([.shift, .option])
                  .subtracting(extra).isEmpty
        else { return false }
        guard let label = keyLabel, label.count == 1 else { return false }
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: chars.count,
                                       actualStringLength: &length,
                                       unicodeString: &chars)
        guard length > 0 else { return false }
        let typed = String(utf16CodeUnits: chars, count: length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !typed.isEmpty && typed.uppercased() == label.uppercased()
    }

    private func modifiersMatch(event: CGEvent,
                                allowingExtraShift: Bool,
                                tolerating extra: GlobalShortcutModifiers = []) -> Bool {
        var actual = GlobalShortcutModifiers(cgFlags: event.flags)
        guard actual.intersection(modifiers) == modifiers else { return false }
        actual.subtract(extra.subtracting(modifiers))
        if allowingExtraShift, !modifiers.contains(.shift) {
            return actual.subtracting(.shift) == modifiers
        }
        return actual == modifiers
    }

    func requiredModifiersHeld(in flags: CGEventFlags) -> Bool {
        let actual = GlobalShortcutModifiers(cgFlags: flags)
        return actual.intersection(modifiers) == modifiers
    }

    func requiredModifiersHeld(in flags: NSEvent.ModifierFlags) -> Bool {
        let actual = GlobalShortcutModifiers(eventFlags: flags)
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
        // Editing and navigation keys. They print as the caps the keyboard
        // itself carries, the same way the arrows above do: spelling them out
        // ("Page Down") would overflow the shortcut field on a full keyboard
        // combination, and these caps are what every menu on this system shows.
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_ANSI_KeypadEnter: return "⌤"
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
        // The upper function keys exist on full and external keyboards and are
        // rarely claimed by anything else, which makes them good shortcuts.
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        // The extra ISO key beside/above Tab (§ on British, ^ on German
        // keyboards) has no ANSI constant; without a label it could not be
        // recorded as a shortcut at all on ISO keyboards (issue #187).
        case kVK_ISO_Section: return Self.layoutKeyLabel(for: keyCode) ?? "§"
        default: return Self.layoutKeyLabel(for: keyCode)
        }
    }

    /// The character the current keyboard layout prints for a key, uppercased,
    /// so keys the static table does not know (ISO and JIS extras) still get a
    /// real cap. Returns nil for anything unprintable, keeping those invalid.
    ///
    /// Answered from the cache: deriving a label asks Text Input Services,
    /// which traps the process off the main thread, and the Switcher's tap
    /// asks for one on every key from its own (issue #578).
    private static func layoutKeyLabel(for keyCode: Int64) -> String? {
        if Thread.isMainThread {
            let label = derivedLayoutKeyLabel(for: keyCode)
            layoutLabelLock.withLock { layoutLabels[keyCode] = label }
            return label
        }
        return layoutLabelLock.withLock { layoutLabels[keyCode] }
    }

    private static let layoutLabelLock = NSLock()
    private static var layoutLabels: [Int64: String] = [:]

    /// Fills the cache before the Switcher's tap starts or after the layout
    /// changes. The service owns the observer so it exists only with the tap.
    static func refreshLayoutLabels() {
        guard let layoutData = currentLayoutData() else {
            layoutLabelLock.withLock { layoutLabels.removeAll() }
            return
        }
        var labels: [Int64: String] = [:]
        for keyCode in UInt16(0)...127 {
            if let label = derivedLayoutKeyLabel(for: keyCode, layoutData: layoutData) {
                labels[Int64(keyCode)] = label
            }
        }
        layoutLabelLock.withLock { layoutLabels = labels }
    }

    private static func derivedLayoutKeyLabel(for keyCode: Int64) -> String? {
        guard let code = UInt16(exactly: keyCode),
              let layoutData = currentLayoutData()
        else { return nil }
        return derivedLayoutKeyLabel(for: code, layoutData: layoutData)
    }

    private static func currentLayoutData() -> Data? {
        guard Thread.isMainThread,
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        return Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
    }

    private static func derivedLayoutKeyLabel(for code: UInt16,
                                              layoutData: Data) -> String? {
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> OSStatus in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress
            else { return OSStatus(paramErr) }
            return UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let label = String(utf16CodeUnits: chars, count: length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard label.count == 1,
              let scalar = label.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar)
        else { return nil }
        return label.uppercased()
    }
}

/// The sentence under a listening shortcut field. Built in one place so every
/// shortcut surface says the same thing, and so it only promises that Delete
/// clears where Delete can actually take the shortcut off.
enum ShortcutRecordingCaption {
    static func text(_ strings: Strings, canClear: Bool) -> String {
        let parts = canClear
            ? [strings.shortcutRecording, strings.shortcutEscapeHint, strings.shortcutDeleteHint]
            : [strings.shortcutRecording, strings.shortcutEscapeHint]
        return parts.joined(separator: " ")
    }
}

enum GlobalShortcutRole: CaseIterable, Identifiable {
    case keepAwake
    case shelf
    case switcher
    case switcherWindow
    case clipboard
    case soundOutputSwitcher
    case pastePlain
    case finderRename
    case colorPicker
    case screenOCR
    case micMute
    case quickLauncher
    case screenshot
    case screenshotFullScreen
    case screenshotLastCapture
    case screenshotClipboard
    case cameraPreview
    case radialMenu
    case scratchpad
    case snippetLibrary
    case commandBar
    case screenRecorder

    var id: String { storageKey }

    var storageKey: String {
        switch self {
        case .keepAwake: return DefaultsKey.keepAwakeShortcut
        case .shelf: return DefaultsKey.shelfShortcut
        case .switcher: return DefaultsKey.switcherShortcut
        case .switcherWindow: return DefaultsKey.switcherWindowShortcut
        case .clipboard: return DefaultsKey.clipboardHistoryShortcut
        case .soundOutputSwitcher: return DefaultsKey.soundOutputSwitcherShortcut
        case .pastePlain: return DefaultsKey.pastePlainShortcut
        case .finderRename: return DefaultsKey.finderRenameShortcut
        case .colorPicker: return DefaultsKey.colorPickerShortcut
        case .screenOCR: return DefaultsKey.screenOCRShortcut
        case .micMute: return DefaultsKey.micMuteShortcut
        case .quickLauncher: return DefaultsKey.quickLauncherShortcut
        case .screenshot: return DefaultsKey.screenshotShortcut
        case .screenshotFullScreen: return DefaultsKey.screenshotFullScreenShortcut
        case .screenshotLastCapture: return DefaultsKey.screenshotLastCaptureShortcut
        case .screenshotClipboard: return DefaultsKey.screenshotClipboardShortcut
        case .cameraPreview: return DefaultsKey.cameraPreviewShortcut
        case .radialMenu: return DefaultsKey.radialMenuShortcut
        case .scratchpad: return DefaultsKey.scratchpadShortcut
        case .snippetLibrary: return DefaultsKey.snippetLibraryShortcut
        case .commandBar: return DefaultsKey.commandBarShortcut
        case .screenRecorder: return DefaultsKey.recorderShortcut
        }
    }

    var defaultShortcut: GlobalShortcut {
        switch self {
        case .keepAwake: return .keepAwakeDefault
        case .shelf: return .shelfDefault
        case .switcher: return .switcherDefault
        case .switcherWindow: return .switcherWindowDefault
        case .clipboard: return .clipboardDefault
        case .soundOutputSwitcher: return .soundOutputSwitcherDefault
        case .pastePlain: return .pastePlainDefault
        case .finderRename: return .finderRenameDefault
        case .colorPicker: return .colorPickerDefault
        case .screenOCR: return .screenOCRDefault
        case .micMute: return .micMuteDefault
        case .quickLauncher: return .quickLauncherDefault
        case .screenshot: return .screenshotDefault
        case .screenshotFullScreen: return .screenshotFullScreenDefault
        case .screenshotLastCapture: return .screenshotLastCaptureDefault
        case .screenshotClipboard: return .screenshotClipboardDefault
        case .cameraPreview: return .cameraPreviewDefault
        case .radialMenu: return .radialMenuDefault
        case .scratchpad: return .scratchpadDefault
        case .snippetLibrary: return .snippetLibraryDefault
        case .commandBar: return .commandBarDefault
        case .screenRecorder: return .screenRecorderDefault
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
        case .switcherWindow: return strings.switcherShortcutHintWindows
        case .clipboard: return FeatureStrings.clipboard(L10n.shared.language).title
        case .soundOutputSwitcher: return strings.soundOutputSwitcherTitle
        case .pastePlain: return strings.pastePlainName
        case .finderRename: return FeatureStrings.finderRename(L10n.shared.language).hubTitle
        case .colorPicker: return strings.colorPickerName
        case .screenOCR: return strings.ocrName
        case .micMute: return strings.micMuteName
        case .quickLauncher: return strings.launcherName
        case .screenshot:
            return FeatureStrings.screenshot(L10n.shared.language).pageTitle
        case .screenshotFullScreen:
            return FeatureStrings.screenshot(L10n.shared.language).fullScreenShortcutTitle
        case .screenshotLastCapture:
            return FeatureStrings.screenshot(L10n.shared.language).editLastCapture
        case .screenshotClipboard:
            return FeatureStrings.screenshot(L10n.shared.language).editClipboardImage
        case .cameraPreview: return FeatureStrings.cameraPreview(L10n.shared.language).pageTitle
        case .radialMenu: return FeatureStrings.radialMenu(L10n.shared.language).pageTitle
        case .scratchpad: return FeatureStrings.scratchpad(L10n.shared.language).pageTitle
        case .snippetLibrary: return FeatureStrings.snippets(L10n.shared.language).libraryTitle
        case .commandBar: return FeatureStrings.commandBar(L10n.shared.language).pageTitle
        case .screenRecorder: return FeatureStrings.recorder(L10n.shared.language).pageTitle
        }
    }

    static func conflict(for shortcut: GlobalShortcut,
                         excluding role: GlobalShortcutRole?,
                         isOn: (String) -> Bool = { UserDefaults.standard.bool(forKey: $0) },
                         isAvailable: (AppFeature) -> Bool = { $0.isAvailable },
                         includeInactive: Bool = false) -> GlobalShortcutRole? {
        let candidates = includeInactive
            ? availableRoles(isAvailable: isAvailable)
            : activeRoles(isOn: isOn, isAvailable: isAvailable)
        return candidates.first { candidate in
            candidate != role && candidate.savedShortcut == shortcut
        }
    }

    /// The defaults keys that must ALL be true for this role's shortcut to be
    /// registered. Some shortcuts gate on their own toggle, some follow the
    /// feature switch, and the clipboard needs both the feature and its
    /// shortcut toggle.
    var requiredEnableKeys: [String] {
        switch self {
        case .keepAwake: return [DefaultsKey.hotkeyEnabled]
        case .shelf: return [DefaultsKey.shelfEnabled, DefaultsKey.shelfShortcutEnabled]
        case .switcher, .switcherWindow: return [DefaultsKey.switcherEnabled]
        case .clipboard: return [DefaultsKey.clipboardHistoryEnabled,
                                 DefaultsKey.clipboardHistoryShortcutEnabled]
        case .soundOutputSwitcher: return [DefaultsKey.soundOutputSwitcherEnabled]
        case .pastePlain: return [DefaultsKey.pastePlainEnabled]
        case .finderRename: return [DefaultsKey.finderRenameEnabled]
        case .colorPicker: return [DefaultsKey.colorPickerShortcutEnabled]
        case .screenOCR: return [DefaultsKey.screenOCRShortcutEnabled]
        case .micMute: return [DefaultsKey.micMuteShortcutEnabled]
        case .quickLauncher: return [DefaultsKey.quickLauncherShortcutEnabled]
        case .screenshot: return [DefaultsKey.screenshotShortcutEnabled]
        case .screenshotFullScreen: return [DefaultsKey.screenshotFullScreenShortcutEnabled]
        case .screenshotLastCapture: return [DefaultsKey.screenshotLastCaptureShortcutEnabled]
        case .screenshotClipboard: return [DefaultsKey.screenshotClipboardShortcutEnabled]
        case .cameraPreview: return [DefaultsKey.cameraPreviewShortcutEnabled]
        case .radialMenu: return [DefaultsKey.radialMenuEnabled]
        case .scratchpad: return [DefaultsKey.scratchpadShortcutEnabled]
        case .snippetLibrary: return [DefaultsKey.snippetLibraryEnabled]
        case .commandBar: return [DefaultsKey.commandBarShortcutEnabled]
        case .screenRecorder: return [DefaultsKey.recorderShortcutEnabled]
        }
    }

    /// The hub feature behind each shortcut; a feature switched off in the
    /// hub takes its shortcut off the overview page (the hotkey itself is
    /// already dead through the service's own availability guard).
    var feature: AppFeature {
        switch self {
        case .keepAwake: return .keepAwake
        case .shelf: return .shelf
        case .switcher, .switcherWindow: return .switcher
        case .clipboard: return .clipboardHistory
        case .soundOutputSwitcher: return .soundOutputSwitcher
        case .pastePlain: return .pastePlain
        case .finderRename: return .finderRename
        case .colorPicker: return .colorPicker
        case .screenOCR: return .screenOCR
        case .micMute: return .micMute
        case .quickLauncher: return .quickLauncher
        case .screenshot, .screenshotFullScreen, .screenshotLastCapture, .screenshotClipboard:
            return .screenshot
        case .cameraPreview: return .cameraPreview
        case .radialMenu: return .radialMenu
        case .scratchpad: return .scratchpad
        case .snippetLibrary: return .textSnippets
        case .commandBar: return .commandBar
        case .screenRecorder: return .screenRecorder
        }
    }

    /// Every capture role follows its own tool: the shortcut opens the shared
    /// chooser on that mode, so it lives and dies with the mode itself.
    var availabilityFeatures: [AppFeature] {
        [feature]
    }

    func isAvailable(using isAvailable: (AppFeature) -> Bool) -> Bool {
        availabilityFeatures.contains(where: isAvailable)
    }

    /// The features whose own shortcuts have to go quiet while the user is
    /// recording a new one, or the combination being typed fires the feature
    /// instead of landing in the field. Derived from the roles, so a shortcut
    /// added later is covered the day its role is added. Re-registering is a
    /// plain `FeatureRuntime.sync` of this same list.
    static var featuresToSilenceWhileRecording: [AppFeature] {
        var seen: Set<AppFeature> = []
        var features = allCases.compactMap { seen.insert($0.feature).inserted ? $0.feature : nil }
        // Window layout keeps one shortcut per action instead of a role, so it
        // is the one holder of global keys the list above cannot reach.
        if seen.insert(.windowLayout).inserted { features.append(.windowLayout) }
        return features
    }

    /// Roles whose shortcut is live given a defaults reader, for the keyboard
    /// shortcuts overview page. Injected readers so the harness can test the
    /// gating without touching real defaults.
    static func activeRoles(isOn: (String) -> Bool,
                            isAvailable: (AppFeature) -> Bool = { _ in true }) -> [GlobalShortcutRole] {
        allCases.filter { role in
            role.isAvailable(using: isAvailable) && role.requiredEnableKeys.allSatisfy(isOn)
        }
    }

    /// Every shortcut belonging to an installed feature, including choices
    /// that are currently switched off but can still be edited and kept for
    /// later on the central shortcuts page.
    static func availableRoles(isAvailable: (AppFeature) -> Bool = { $0.isAvailable })
        -> [GlobalShortcutRole] {
        allCases.filter { $0.isAvailable(using: isAvailable) }
    }

    /// The features whose shortcuts share one Screen capture group on the
    /// central shortcuts page.
    static let captureFeatures: [AppFeature] =
        [.screenshot, .screenRecorder, .screenOCR, .colorPicker]

    /// Chooser tools first, in chooser order, then the screenshot extras.
    static let captureDisplayOrder: [GlobalShortcutRole] = [
        .screenshot, .screenRecorder, .screenOCR, .colorPicker,
        .screenshotFullScreen, .screenshotLastCapture, .screenshotClipboard,
    ]

    /// The given roles narrowed to the capture group, in display order. The
    /// order list only sorts, so an unlisted role lands at the end instead of
    /// vanishing.
    static func captureRoles(in roles: [GlobalShortcutRole]) -> [GlobalShortcutRole] {
        roles.filter { captureFeatures.contains($0.feature) }
            .enumerated()
            .sorted { lhs, rhs in
                (captureDisplayOrder.firstIndex(of: lhs.element) ?? .max, lhs.offset)
                    < (captureDisplayOrder.firstIndex(of: rhs.element) ?? .max, rhs.offset)
            }
            .map(\.element)
    }
}

/// macOS answers its own shortcuts before an application hotkey ever sees the
/// key, and it does not consume it, so a combination shared with the system
/// fires both: the system screenshot picker opens and the app's own capture
/// starts behind it. The system list is the only one that can be inspected —
/// hotkeys other applications register are not published anywhere — so this
/// catches the collisions it can and leaves the rest to the registration
/// failure the shortcut rows already report.
extension GlobalShortcut {
    /// The system's shortcut list. Read fresh every time: it can change in
    /// System Settings while a shortcut field is open.
    static var systemSymbolicHotKeys: [String: Any]? {
        UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys")
    }

    var conflictsWithSystemShortcut: Bool {
        Self.matchesSystemShortcut(self, symbolicHotKeys: Self.systemSymbolicHotKeys)
    }

    /// Whether an enabled system shortcut uses exactly this combination. Entries
    /// store `[character, key code, modifier mask]`, with the mask in
    /// `NSEvent.ModifierFlags` bits, and a disabled entry is not in anyone's
    /// way. Anything that does not parse is ignored rather than guessed at: a
    /// wrong match would refuse a combination the user can legitimately take.
    static func matchesSystemShortcut(_ shortcut: GlobalShortcut,
                                      symbolicHotKeys: [String: Any]?) -> Bool {
        guard let symbolicHotKeys else { return false }
        return symbolicHotKeys.values.contains { entry in
            guard let entry = entry as? [String: Any],
                  (entry["enabled"] as? NSNumber)?.boolValue == true,
                  let value = entry["value"] as? [String: Any],
                  (value["type"] as? String) == "standard",
                  let parameters = value["parameters"] as? [NSNumber],
                  parameters.count >= 3
            else { return false }
            let keyCode = parameters[1].int64Value
            guard keyCode == shortcut.keyCode, keyCode != Self.noKeyCode else { return false }
            let flags = NSEvent.ModifierFlags(rawValue: UInt(parameters[2].uintValue))
            return GlobalShortcutModifiers(eventFlags: flags) == shortcut.modifiers
        }
    }

    /// The placeholder a system entry carries when it has no key assigned.
    private static let noKeyCode: Int64 = 0xFFFF
}
