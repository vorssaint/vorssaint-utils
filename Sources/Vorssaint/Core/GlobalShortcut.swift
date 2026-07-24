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
    // Quick tools. Paste plain follows the universal "Paste and Match Style"
    // combination; the others use the free ⌃⌥⌘ letters.
    static let pastePlainDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_V),
                                                  modifiers: [.shift, .option, .command])
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
        hasUsableKeyCode && modifiers.hasPrimaryModifier && keyLabel != nil
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

    var carbonKeyCode: UInt32 {
        UInt32(exactly: keyCode) ?? 0
    }

    var carbonModifiers: UInt32 {
        modifiers.carbonFlags
    }

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

    /// Layout-tolerant match: true when the pressed key would type the same
    /// character this shortcut displays. Key codes are positions on a US
    /// keyboard, so a default like ⌘` lands on a different position for ABNT2
    /// or German layouts, sometimes behind Shift or Option; the user goes by
    /// the character shown in Settings, not by the invisible ANSI position
    /// (issue #187). The character comes from the event itself, the same
    /// signal the switcher's search uses, so dead keys resolve identically.
    func matchesByCharacter(event: CGEvent,
                            tolerating extra: GlobalShortcutModifiers = []) -> Bool {
        guard let label = keyLabel, label.count == 1 else { return false }
        let actual = GlobalShortcutModifiers(cgFlags: event.flags)
        // The shortcut's own modifiers must be down; Shift or Option on top is
        // tolerated because many layouts need them to produce the character,
        // and the caller may tolerate more (a session's held modifiers).
        guard actual.intersection(modifiers) == modifiers,
              actual.subtracting(modifiers).subtracting([.shift, .option])
                  .subtracting(extra).isEmpty
        else { return false }
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
    private static func layoutKeyLabel(for keyCode: Int64) -> String? {
        guard let code = UInt16(exactly: keyCode),
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> OSStatus in
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
    case colorPicker
    case screenOCR
    case micMute
    case quickLauncher
    case screenshot
    case cameraPreview
    case radialMenu
    case scratchpad
    case snippetLibrary

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
        case .colorPicker: return DefaultsKey.colorPickerShortcut
        case .screenOCR: return DefaultsKey.screenOCRShortcut
        case .micMute: return DefaultsKey.micMuteShortcut
        case .quickLauncher: return DefaultsKey.quickLauncherShortcut
        case .screenshot: return DefaultsKey.screenshotShortcut
        case .cameraPreview: return DefaultsKey.cameraPreviewShortcut
        case .radialMenu: return DefaultsKey.radialMenuShortcut
        case .scratchpad: return DefaultsKey.scratchpadShortcut
        case .snippetLibrary: return DefaultsKey.snippetLibraryShortcut
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
        case .colorPicker: return .colorPickerDefault
        case .screenOCR: return .screenOCRDefault
        case .micMute: return .micMuteDefault
        case .quickLauncher: return .quickLauncherDefault
        case .screenshot: return .screenshotDefault
        case .cameraPreview: return .cameraPreviewDefault
        case .radialMenu: return .radialMenuDefault
        case .scratchpad: return .scratchpadDefault
        case .snippetLibrary: return .snippetLibraryDefault
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
        case .clipboard: return "Clipboard"
        case .soundOutputSwitcher: return strings.soundOutputSwitcherTitle
        case .pastePlain: return strings.pastePlainName
        case .colorPicker: return strings.colorPickerName
        case .screenOCR: return strings.ocrName
        case .micMute: return strings.micMuteName
        case .quickLauncher: return strings.launcherName
        case .screenshot: return FeatureStrings.screenshot(L10n.shared.language).pageTitle
        case .cameraPreview: return FeatureStrings.cameraPreview(L10n.shared.language).pageTitle
        case .radialMenu: return FeatureStrings.radialMenu(L10n.shared.language).pageTitle
        case .scratchpad: return FeatureStrings.scratchpad(L10n.shared.language).pageTitle
        case .snippetLibrary: return FeatureStrings.snippets(L10n.shared.language).libraryTitle
        }
    }

    static func conflict(for shortcut: GlobalShortcut, excluding role: GlobalShortcutRole) -> GlobalShortcutRole? {
        allCases.first { candidate in
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
        case .colorPicker: return [DefaultsKey.colorPickerShortcutEnabled]
        case .screenOCR: return [DefaultsKey.screenOCRShortcutEnabled]
        case .micMute: return [DefaultsKey.micMuteShortcutEnabled]
        case .quickLauncher: return [DefaultsKey.quickLauncherShortcutEnabled]
        case .screenshot: return [DefaultsKey.screenshotShortcutEnabled]
        case .cameraPreview: return [DefaultsKey.cameraPreviewShortcutEnabled]
        case .radialMenu: return [DefaultsKey.radialMenuEnabled]
        case .scratchpad: return [DefaultsKey.scratchpadShortcutEnabled]
        case .snippetLibrary: return [DefaultsKey.snippetLibraryEnabled]
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
        case .colorPicker: return .colorPicker
        case .screenOCR: return .screenOCR
        case .micMute: return .micMute
        case .quickLauncher: return .quickLauncher
        case .screenshot: return .screenshot
        case .cameraPreview: return .cameraPreview
        case .radialMenu: return .radialMenu
        case .scratchpad: return .scratchpad
        case .snippetLibrary: return .textSnippets
        }
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
            isAvailable(role.feature) && role.requiredEnableKeys.allSatisfy(isOn)
        }
    }
}
