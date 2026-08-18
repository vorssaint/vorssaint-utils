// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What a tap of the super key on its own does, when no other key was pressed
/// while it was held.
enum SuperKeySoloAction: String, CaseIterable, Identifiable {
    case none, capsLock, escape

    var id: String { rawValue }

    static func sanitized(_ raw: String?) -> SuperKeySoloAction {
        guard let raw, let action = SuperKeySoloAction(rawValue: raw) else { return .none }
        return action
    }
}

/// One entry of the keyboard's key mapping table: a source key that arrives as
/// a destination key, both written as HID usage values.
struct SuperKeyMapping: Equatable {
    let source: UInt64
    let destination: UInt64
}

/// The pure half of the super key: which keys are involved, how the mapping
/// table is read and written, and the small state machine that decides what to
/// do with each key event while the key is held.
///
/// Caps Lock cannot be held: the keyboard reports it as a lock that flips on
/// one press and off on the next, so no software above the driver ever sees it
/// go down and up. The mapping table below turns it into an ordinary key
/// first, which is what makes holding it possible at all.
enum SuperKeySupport {
    static let defaultModifiers: GlobalShortcutModifiers = .validMask

    static var defaultModifierStorageValue: String {
        storageValue(for: defaultModifiers)
    }

    static func modifiers(from storedValue: String?) -> GlobalShortcutModifiers {
        guard let storedValue else { return defaultModifiers }
        var modifiers: GlobalShortcutModifiers = []
        for token in storedValue.split(separator: "+", omittingEmptySubsequences: false) {
            switch token {
            case "control": modifiers.insert(.control)
            case "option": modifiers.insert(.option)
            case "shift": modifiers.insert(.shift)
            case "command": modifiers.insert(.command)
            default: return defaultModifiers
            }
        }
        return modifiers.hasPrimaryModifier ? modifiers : defaultModifiers
    }

    static func storageValue(for modifiers: GlobalShortcutModifiers) -> String {
        let sanitized = modifiers.intersection(.validMask)
        return (sanitized.hasPrimaryModifier ? sanitized : defaultModifiers)
            .storageTokens.joined(separator: "+")
    }

    /// HID usage values (page 7, keyboard) of the two keys involved.
    static let capsLockUsage: UInt64 = 0x700000039
    /// Modifier Keys represents “No Action” with this sentinel.
    static let noActionUsage = UInt64.max
    /// F18 is the destination: a key defined by the standard, so the system
    /// delivers it like any other, and one no portable keyboard carries.
    static let triggerUsage: UInt64 = 0x70000006D

    /// Virtual key codes of the same two keys, as they arrive in key events.
    static let triggerKeyCode: Int64 = 79
    static let capsLockKeyCode: Int64 = 57

    // MARK: - Key mapping table

    /// The table to write for the wanted state. A mapping the user set up
    /// elsewhere stays as it is; only the entries created for this feature are
    /// removed when it is turned off.
    static func mappings(enablingSuperKey enabled: Bool,
                         existing: [SuperKeyMapping],
                         includeNoAction: Bool = false) -> [SuperKeyMapping] {
        let others = existing.filter {
            $0.source != capsLockUsage
                && !($0.source == noActionUsage && $0.destination == triggerUsage)
        }
        guard enabled else { return others }
        var owned = [SuperKeyMapping(source: capsLockUsage, destination: triggerUsage)]
        if includeNoAction, !others.contains(where: { $0.source == noActionUsage }) {
            owned.append(SuperKeyMapping(source: noActionUsage, destination: triggerUsage))
        }
        return owned + others
    }

    /// “No Action” has one shared sentinel after Modifier Keys. It is safe to
    /// recover only when Caps Lock is the sole modifier using that sentinel.
    static func canMapNoAction(from modifierMappings: [SuperKeyMapping]) -> Bool {
        let disabledSources = Set(
            modifierMappings.lazy
                .filter { $0.destination == noActionUsage }
                .map(\.source)
        )
        return disabledSources == [capsLockUsage]
    }

    /// The mapping table as the command line takes it.
    static func mappingArgument(_ mappings: [SuperKeyMapping]) -> String {
        let entries = mappings.map {
            "{\"HIDKeyboardModifierMappingSrc\":\($0.source),\"HIDKeyboardModifierMappingDst\":\($0.destination)}"
        }
        return "{\"UserKeyMapping\":[\(entries.joined(separator: ","))]}"
    }

    /// Reads the mapping table back. The report lists one block per keyboard,
    /// so the same entry shows up once per device and is kept once.
    static func parseMappings(_ report: String) -> [SuperKeyMapping] {
        var result: [SuperKeyMapping] = []
        for block in report.components(separatedBy: "{").dropFirst() {
            let body = block.components(separatedBy: "}").first ?? ""
            guard let source = number(after: "HIDKeyboardModifierMappingSrc", in: body),
                  let destination = number(after: "HIDKeyboardModifierMappingDst", in: body)
            else { continue }
            let mapping = SuperKeyMapping(source: source, destination: destination)
            if !result.contains(mapping) { result.append(mapping) }
        }
        return result
    }

    private static func number(after field: String, in body: String) -> UInt64? {
        guard let range = body.range(of: field) else { return nil }
        let rest = body[range.upperBound...].drop {
            $0 == " " || $0 == "=" || $0 == "\""
        }
        let token = rest.prefix { $0.isNumber || $0 == "-" }
        if let value = UInt64(token) { return value }
        guard let value = Int64(token) else { return nil }
        return UInt64(bitPattern: value)
    }

    // MARK: - What each event means

    /// A key event, reduced to the only distinctions the decision needs.
    enum Event: Equatable {
        /// The key the super key arrives as, pressed (or repeating while held).
        case triggerDown(isRepeat: Bool)
        case triggerUp
        /// Any other key going down or up.
        case otherKey
        /// A real Caps Lock, which means that keyboard is not mapped yet.
        case capsLock
        /// Any other modifier changing state.
        case otherModifier
    }

    enum Decision: Equatable {
        /// The event belongs to the super key and goes no further.
        case swallow
        /// The configured modifiers ride along with this key.
        case addModifiers
        /// The event carries on untouched.
        case pass
        /// The key was tapped with nothing else, so its solo action runs.
        case soloTap
        /// A raw Caps Lock is kept out while its keyboard mapping is repaired.
        case interceptAndRemap
    }

    /// Holding the key is the whole feature, so the state is just whether it is
    /// down and whether anything else has happened since it went down.
    struct State: Equatable {
        private(set) var isHeld = false
        private(set) var isAlone = false

        mutating func decide(_ event: Event) -> Decision {
            switch event {
            case .triggerDown(let isRepeat):
                // A key that repeats is being held, not tapped.
                if isRepeat {
                    isAlone = false
                } else if !isHeld {
                    isAlone = true
                }
                isHeld = true
                return .swallow
            case .triggerUp:
                let wasAlone = isHeld && isAlone
                isHeld = false
                isAlone = false
                return wasAlone ? .soloTap : .swallow
            case .otherKey:
                guard isHeld else { return .pass }
                isAlone = false
                return .addModifiers
            case .otherModifier:
                if isHeld { isAlone = false }
                return .pass
            case .capsLock:
                return .interceptAndRemap
            }
        }

        /// Forgets the press in progress. Used when the tap goes away, so a key
        /// held across a teardown cannot leave the state stuck down.
        mutating func reset() {
            isHeld = false
            isAlone = false
        }
    }
}
