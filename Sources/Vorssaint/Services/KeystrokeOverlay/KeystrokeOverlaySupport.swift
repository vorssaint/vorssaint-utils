// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum KeystrokeOverlayStyle: String, CaseIterable, Identifiable, Equatable {
    case svelte
    case keycaps

    var id: String { rawValue }

    static func sanitized(_ raw: String?) -> KeystrokeOverlayStyle {
        guard let raw, let value = KeystrokeOverlayStyle(rawValue: raw) else {
            return .svelte
        }
        return value
    }
}

enum KeystrokeOverlayMode: String, CaseIterable, Identifiable, Equatable {
    case allKeys = "all"
    case shortcutsOnly = "shortcuts"

    var id: String { rawValue }

    static func sanitized(_ raw: String?) -> KeystrokeOverlayMode {
        guard let raw, let value = KeystrokeOverlayMode(rawValue: raw) else {
            return .allKeys
        }
        return value
    }
}

enum KeystrokeOverlayPosition: String, CaseIterable, Identifiable, Equatable {
    case bottomCenter
    case bottomLeft
    case bottomRight
    case topCenter
    case topLeft
    case topRight

    var id: String { rawValue }

    static func sanitized(_ raw: String?) -> KeystrokeOverlayPosition {
        guard let raw, let value = KeystrokeOverlayPosition(rawValue: raw) else {
            return .bottomCenter
        }
        return value
    }
}

enum KeystrokeOverlaySize: String, CaseIterable, Identifiable, Equatable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var fontSize: CGFloat {
        switch self {
        case .small: return 15
        case .medium: return 20
        case .large: return 26
        }
    }

    var minCapDimension: CGFloat {
        switch self {
        case .small: return 26
        case .medium: return 34
        case .large: return 42
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small: return 10
        case .medium: return 14
        case .large: return 18
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .small: return 7
        case .medium: return 9
        case .large: return 12
        }
    }

    var svelteBoxSize: CGSize {
        switch self {
        case .small: return CGSize(width: 172, height: 86)
        case .medium: return CGSize(width: 200, height: 100)
        case .large: return CGSize(width: 248, height: 124)
        }
    }

    var svelteModifierBarHeight: CGFloat {
        switch self {
        case .small: return 26
        case .medium: return 30
        case .large: return 36
        }
    }

    var svelteKeyFontSize: CGFloat {
        switch self {
        case .small: return 34
        case .medium: return 42
        case .large: return 52
        }
    }

    var svelteModifierFontSize: CGFloat {
        switch self {
        case .small: return 15
        case .medium: return 18
        case .large: return 22
        }
    }

    static func sanitized(_ raw: String?) -> KeystrokeOverlaySize {
        guard let raw, let value = KeystrokeOverlaySize(rawValue: raw) else {
            return .medium
        }
        return value
    }
}

struct KeystrokeOverlayConfig: Equatable {
    var enabled: Bool
    var style: KeystrokeOverlayStyle = .svelte
    var mode: KeystrokeOverlayMode
    var position: KeystrokeOverlayPosition
    var customOrigin: CGPoint? = nil
    var size: KeystrokeOverlaySize
    var durationSeconds: Double
    var showInCaptures: Bool = true

    static let defaultDurationSeconds: Double = 1.5
    static let durationRange: ClosedRange<Double> = 0.5...5.0

    static func sanitizedDuration(_ value: Double) -> Double {
        guard value.isFinite else { return defaultDurationSeconds }
        let clamped = min(max(value, durationRange.lowerBound), durationRange.upperBound)
        return (clamped * 10).rounded() / 10
    }

    static func showsInCaptures(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.keystrokeOverlayShowInCaptures) as? Bool ?? true
    }
}

struct KeystrokeOverlayItem: Identifiable, Equatable {
    let id: UUID
    var caps: [String]
    var repeatCount: Int
    var timestamp: TimeInterval

    init(id: UUID = UUID(), caps: [String], repeatCount: Int = 1, timestamp: TimeInterval) {
        self.id = id
        self.caps = caps
        self.repeatCount = max(1, repeatCount)
        self.timestamp = timestamp
    }

    var displayText: String {
        let base = caps.joined(separator: " ")
        return repeatCount > 1 ? "\(base) ×\(repeatCount)" : base
    }
}

struct KeystrokeOverlayBuffer: Equatable {
    static let maxVisibleItems = 5
    private static let repeatMergeWindow: TimeInterval = 0.85

    private(set) var items: [KeystrokeOverlayItem] = []

    mutating func reset() {
        items.removeAll()
    }

    mutating func prune(now: TimeInterval, duration: TimeInterval) {
        guard now.isFinite, duration > 0 else {
            items.removeAll()
            return
        }
        items.removeAll { now - $0.timestamp >= duration }
    }

    @discardableResult
    mutating func record(caps: [String],
                         now: TimeInterval,
                         duration: TimeInterval,
                         id: UUID = UUID()) -> [KeystrokeOverlayItem] {
        let cleaned = caps.filter { !$0.isEmpty }
        guard !cleaned.isEmpty, now.isFinite else { return items }
        prune(now: now, duration: duration)

        if let lastIndex = items.indices.last,
           items[lastIndex].caps == cleaned,
           now >= items[lastIndex].timestamp,
           now - items[lastIndex].timestamp <= Self.repeatMergeWindow {
            items[lastIndex].repeatCount += 1
            items[lastIndex].timestamp = now
            return items
        }

        items.append(KeystrokeOverlayItem(id: id, caps: cleaned, repeatCount: 1, timestamp: now))
        if items.count > Self.maxVisibleItems {
            items.removeFirst(items.count - Self.maxVisibleItems)
        }
        return items
    }
}

/// Rolling keystroke buffer for the KeyCastr "Svelte" theme box.
/// Keeps recent typed tokens inside the upper display area while the bottom
/// strip highlights held modifiers (`⇧`, `⌃`, `⌥`, `⌘`).
struct KeystrokeOverlaySvelteBuffer: Equatable {
    struct Token: Equatable {
        var text: String
        var isStandalone: Bool
        var timestamp: TimeInterval
    }

    static let maxRollingTokens = 6

    private(set) var tokens: [Token] = []
    private(set) var transientModifierText: String?

    var displayText: String {
        if !tokens.isEmpty {
            return tokens.map(\.text).joined()
        }
        return transientModifierText ?? ""
    }

    var isEmpty: Bool {
        tokens.isEmpty && (transientModifierText?.isEmpty ?? true)
    }

    mutating func reset() {
        tokens.removeAll()
        transientModifierText = nil
    }

    mutating func setTransientModifier(_ text: String?) {
        let cleaned = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleaned, !cleaned.isEmpty {
            transientModifierText = cleaned
            if tokens.last?.isStandalone == true {
                tokens.removeAll()
            }
        } else {
            transientModifierText = nil
        }
    }

    mutating func prune(now: TimeInterval, duration: TimeInterval) {
        guard now.isFinite, duration > 0 else {
            tokens.removeAll()
            return
        }
        tokens.removeAll { now - $0.timestamp >= duration }
    }

    @discardableResult
    mutating func record(token: String,
                         isStandalone: Bool,
                         now: TimeInterval,
                         duration: TimeInterval) -> String {
        guard !token.isEmpty, now.isFinite else { return displayText }
        prune(now: now, duration: duration)
        transientModifierText = nil

        if isStandalone || tokens.last?.isStandalone == true {
            tokens = [Token(text: token, isStandalone: isStandalone, timestamp: now)]
            return displayText
        }

        tokens.append(Token(text: token, isStandalone: false, timestamp: now))
        if tokens.count > Self.maxRollingTokens {
            tokens.removeFirst(tokens.count - Self.maxRollingTokens)
        }
        return displayText
    }
}

enum KeystrokeOverlaySupport {
    /// Order of the 4 modifier cells in the Svelte theme's bottom bar,
    /// matching KeyCastr's Svelte visualizer (`⇧`, `⌃`, `⌥`, `⌘`).
    static let svelteModifierCells: [(modifier: GlobalShortcutModifiers, symbol: String)] = [
        (.shift, "⇧"),
        (.control, "⌃"),
        (.option, "⌥"),
        (.command, "⌘"),
    ]

    static func isSuperChord(modifiers: GlobalShortcutModifiers, superKeyHeld: Bool = false) -> Bool {
        superKeyHeld || modifiers.intersection(.validMask) == .validMask
    }

    static func modifierPreviewLabel(modifiers: GlobalShortcutModifiers,
                                     superKeyHeld: Bool = false) -> String? {
        if isSuperChord(modifiers: modifiers, superKeyHeld: superKeyHeld) {
            return "Super"
        }
        let symbols = svelteModifierCells.compactMap { cell in
            modifiers.contains(cell.modifier) ? cell.symbol : nil
        }
        guard !symbols.isEmpty else { return nil }
        return symbols.joined(separator: " ")
    }

    static func keyCaps(keyCode: Int64,
                        modifiers: GlobalShortcutModifiers,
                        mode: KeystrokeOverlayMode,
                        isAutoRepeat: Bool,
                        secureInputActive: Bool,
                        typedCharacter: String? = nil,
                        superKeyHeld: Bool = false) -> [String]? {
        guard !secureInputActive, !isAutoRepeat else { return nil }
        let isSuperTrigger = Int(keyCode) == SuperKeySupport.triggerKeyCode
        if isSuperTrigger {
            return ["Super"]
        }
        let superActive = isSuperChord(modifiers: modifiers, superKeyHeld: superKeyHeld)
        if mode == .shortcutsOnly,
           !superActive,
           !modifiers.hasPrimaryModifier,
           !isStandaloneSpecialKey(keyCode) {
            return nil
        }
        guard let label = keyLabel(for: keyCode, modifiers: modifiers, typedCharacter: typedCharacter) else {
            return nil
        }
        if superActive {
            return ["Super", label]
        }
        var caps = modifiers.keyCaps
        // Ordinary shifted typing (like Shift+A or Shift+1) already shows the
        // shifted or uppercase character cap unless a primary modifier is held
        // or the key is a special non-character key (like Shift+Tab).
        if modifiers == [.shift], !isSpecialKey(keyCode), label.count == 1 {
            caps.removeAll { $0 == "⇧" }
        }
        caps.append(label)
        return caps
    }

    /// Formats a key press for the Svelte box's upper display area.
    static func svelteToken(keyCode: Int64,
                            modifiers: GlobalShortcutModifiers,
                            mode: KeystrokeOverlayMode,
                            isAutoRepeat: Bool,
                            secureInputActive: Bool,
                            typedCharacter: String? = nil,
                            superKeyHeld: Bool = false) -> (text: String, isStandalone: Bool)? {
        guard !secureInputActive, !isAutoRepeat else { return nil }
        if Int(keyCode) == SuperKeySupport.triggerKeyCode {
            return ("Super", true)
        }
        let superActive = isSuperChord(modifiers: modifiers, superKeyHeld: superKeyHeld)
        if mode == .shortcutsOnly,
           !superActive,
           !modifiers.hasPrimaryModifier,
           !isStandaloneSpecialKey(keyCode) {
            return nil
        }
        if Int(keyCode) == kVK_Tab, modifiers == [.shift], !superActive {
            return ("⇤", true)
        }
        guard let label = keyLabel(for: keyCode, modifiers: modifiers, typedCharacter: typedCharacter) else {
            return nil
        }
        if superActive {
            return ("Super \(label)", true)
        }
        if modifiers.hasPrimaryModifier {
            let prefix = svelteModifierCells.compactMap { cell in
                modifiers.contains(cell.modifier) ? cell.symbol : nil
            }.joined()
            return ("\(prefix)\(label)", true)
        }
        if modifiers == [.shift], isSpecialKey(keyCode) {
            return ("⇧\(label)", true)
        }
        let standalone = isStandaloneBreakKey(keyCode)
        return (label, standalone)
    }

    static func panelFrame(size: CGSize,
                           visibleFrame: CGRect,
                           position: KeystrokeOverlayPosition,
                           customOrigin: CGPoint? = nil,
                           margin: CGFloat = 28) -> CGRect {
        let width = min(max(size.width, 48), max(48, visibleFrame.width - margin * 2))
        let height = min(max(size.height, 32), max(32, visibleFrame.height - margin * 2))
        if let customOrigin, customOrigin.x.isFinite, customOrigin.y.isFinite {
            return CGRect(
                x: min(max(customOrigin.x.rounded(), visibleFrame.minX + 8), visibleFrame.maxX - width - 8),
                y: min(max(customOrigin.y.rounded(), visibleFrame.minY + 8), visibleFrame.maxY - height - 8),
                width: width,
                height: height
            )
        }
        let x: CGFloat
        switch position {
        case .bottomLeft, .topLeft:
            x = visibleFrame.minX + margin
        case .bottomCenter, .topCenter:
            x = (visibleFrame.midX - width / 2).rounded()
        case .bottomRight, .topRight:
            x = visibleFrame.maxX - width - margin
        }
        let y: CGFloat
        switch position {
        case .bottomLeft, .bottomCenter, .bottomRight:
            y = visibleFrame.minY + margin
        case .topLeft, .topCenter, .topRight:
            y = visibleFrame.maxY - height - margin
        }
        return CGRect(
            x: min(max(x, visibleFrame.minX + 8), visibleFrame.maxX - width - 8),
            y: min(max(y, visibleFrame.minY + 8), visibleFrame.maxY - height - 8),
            width: width,
            height: height
        )
    }

    static func isStandaloneSpecialKey(_ keyCode: Int64) -> Bool {
        switch Int(keyCode) {
        case kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
             kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
             kVK_Escape:
            return true
        default:
            return false
        }
    }

    static func isStandaloneBreakKey(_ keyCode: Int64) -> Bool {
        switch Int(keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape,
             kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
             kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20:
            return true
        default:
            return false
        }
    }

    static func isSpecialKey(_ keyCode: Int64) -> Bool {
        specialKeyLabel(for: keyCode) != nil
    }

    static func keyLabel(for keyCode: Int64,
                         modifiers: GlobalShortcutModifiers,
                         typedCharacter: String? = nil) -> String? {
        if let special = specialKeyLabel(for: keyCode) {
            return special
        }
        if !modifiers.hasPrimaryModifier,
           let typed = typedCharacter?.trimmingCharacters(in: .whitespacesAndNewlines),
           typed.count == 1,
           let scalar = typed.unicodeScalars.first,
           !CharacterSet.controlCharacters.contains(scalar) {
            return typed.uppercased()
        }
        if let layout = GlobalShortcut.layoutKeyLabel(for: keyCode,
                                                      usesCommand: modifiers.contains(.command),
                                                      usesShift: modifiers.contains(.shift) && !modifiers.hasPrimaryModifier) {
            return layout
        }
        let shortcut = GlobalShortcut(keyCode: keyCode, modifiers: modifiers)
        guard shortcut.hasPrintableKey else { return nil }
        return shortcut.keyCaps.last
    }

    private static func specialKeyLabel(for keyCode: Int64) -> String? {
        switch Int(keyCode) {
        case kVK_Return: return "↩"
        case kVK_ANSI_KeypadEnter: return "⌤"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "␣"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_CapsLock: return "⇪"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
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
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        default: return nil
        }
    }
}
