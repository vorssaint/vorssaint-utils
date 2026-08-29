// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

enum SuperKeySource: String, CaseIterable, Identifiable {
    case capsLock, rightCommand, rightOption, rightControl, rightShift

    var id: String { rawValue }

    static func sanitized(_ raw: String?) -> SuperKeySource {
        raw.flatMap(SuperKeySource.init(rawValue:)) ?? .capsLock
    }

    var usage: UInt64 {
        switch self {
        case .capsLock: 0x700000039
        case .rightControl: 0x7000000E4
        case .rightShift: 0x7000000E5
        case .rightOption: 0x7000000E6
        case .rightCommand: 0x7000000E7
        }
    }

    var systemImage: String {
        switch self {
        case .capsLock: "capslock"
        case .rightCommand: "command"
        case .rightOption: "option"
        case .rightControl: "control"
        case .rightShift: "shift"
        }
    }

    var keyCode: Int64 {
        switch self {
        case .capsLock: Int64(kVK_CapsLock)
        case .rightCommand: Int64(kVK_RightCommand)
        case .rightOption: Int64(kVK_RightOption)
        case .rightControl: Int64(kVK_RightControl)
        case .rightShift: Int64(kVK_RightShift)
        }
    }

    var symbol: String? {
        switch self {
        case .capsLock: nil
        case .rightCommand: "⌘"
        case .rightOption: "⌥"
        case .rightControl: "⌃"
        case .rightShift: "⇧"
        }
    }
}

/// What a tap of the super key on its own does, when no other key was pressed
/// while it was held.
enum SuperKeySoloAction: String, CaseIterable, Identifiable {
    case none, capsLock, inputSource, escape

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

/// Why the key mapping could not be applied. Every refusal carries one, so
/// the feature can say what stopped it instead of switching itself back off
/// with nothing on screen.
enum SuperKeyMappingFailure: Equatable, CaseIterable {
    /// Another app's key mapping is in the way.
    case foreignMapping
    /// hidutil refused the read, the write, or the readback.
    case systemRefused
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

    /// F18 is the destination: a key defined by the standard, so the system
    /// delivers it like any other, and one no portable keyboard carries.
    static let triggerUsage: UInt64 = 0x70000006D
    static let userMappingProperty = "UserKeyMapping"

    /// Virtual key code of the destination key, as it arrives in key events.
    static let triggerKeyCode: Int64 = 79

    // MARK: - Key mapping table

    /// The table to write for the wanted state. A mapping the user set up
    /// elsewhere stays as it is; only the entries created for this feature are
    /// removed when it is turned off.
    static func mappings(enablingSuperKey enabled: Bool,
                         existing: [SuperKeyMapping],
                         source: SuperKeySource = .capsLock,
                         ownedSource: SuperKeySource? = nil) -> [SuperKeyMapping] {
        guard enabled || ownedSource != nil else { return existing }
        let others = existing.filter { !isOwnedMapping($0, source: ownedSource) }
        guard enabled else { return others }
        guard !hasMappingConflict(in: existing, source: source, ownedSource: ownedSource)
        else { return existing }
        return [SuperKeyMapping(source: source.usage, destination: triggerUsage)] + others
    }

    /// The source can have only one destination. A mapping shaped like ours is
    /// owned only when the persistent marker says a prior confirmed write made
    /// it; otherwise activation is refused instead of claiming external state.
    static func hasMappingConflict(in mappings: [SuperKeyMapping],
                                   source: SuperKeySource = .capsLock,
                                   ownedSource: SuperKeySource? = nil) -> Bool {
        mappings.contains {
            $0.source == source.usage
                && ($0.destination != triggerUsage || source != ownedSource)
        }
    }

    static func mappingsMatch(_ lhs: [SuperKeyMapping], _ rhs: [SuperKeyMapping]) -> Bool {
        lhs.count == rhs.count && lhs.allSatisfy(rhs.contains)
    }

    /// Returns one safe table only when every matched keyboard has the same
    /// external mappings. A newly connected keyboard may differ solely by the
    /// entries this feature already owns; those are removed before comparison
    /// so repair and cleanup can still converge without copying someone else's
    /// device-specific mapping onto every keyboard.
    static func consistentMappings(_ report: String,
                                   property: String,
                                   ownedSource: SuperKeySource? = nil) -> [SuperKeyMapping]? {
        let tables = mappingTables(report, property: property).map { mappings in
            mappings.filter { !isOwnedMapping($0, source: ownedSource) }
        }
        guard let first = tables.first,
              tables.dropFirst().allSatisfy({ mappingsMatch($0, first) }) else { return nil }
        return first
    }

    static func mappingTables(_ report: String,
                              property: String) -> [[SuperKeyMapping]] {
        var tables: [[SuperKeyMapping]] = []
        var currentBlock = ""
        for line in report.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let fields = trimmed.split(whereSeparator: \.isWhitespace)
            let startsKeyboardBlock = fields.count >= 2 && fields[1] == property
            if startsKeyboardBlock {
                if !currentBlock.isEmpty { tables.append(parseMappings(currentBlock)) }
                currentBlock = line
            } else if !currentBlock.isEmpty {
                currentBlock += "\n" + line
            }
        }
        if !currentBlock.isEmpty { tables.append(parseMappings(currentBlock)) }
        return tables
    }

    /// `hidutil --matching keyboard` reports one table per keyboard. A merged
    /// set is insufficient: one mapped keyboard and one empty table must not be
    /// accepted as a successful global write.
    static func mappingReportConfirms(_ report: String,
                                      expected: [SuperKeyMapping]) -> Bool {
        let tables = mappingTables(report, property: userMappingProperty)
        return !tables.isEmpty && tables.allSatisfy { mappingsMatch($0, expected) }
    }

    /// An unconfirmed clear never changes the write-ahead machine-state
    /// marker, so a failed clear remains eligible for retry.
    static func mappingMarkerAfterClear(previous: Bool,
                                        readbackConfirmed: Bool) -> Bool {
        readbackConfirmed ? false : previous
    }

    static func mappingRequestIsAuthorized(requestGeneration: UInt,
                                           currentGeneration: UInt,
                                           tapIsCurrent: Bool,
                                           stopping: Bool) -> Bool {
        requestGeneration == currentGeneration && tapIsCurrent && !stopping
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

    private static func isOwnedMapping(_ mapping: SuperKeyMapping,
                                       source: SuperKeySource?) -> Bool {
        guard let source else { return false }
        return mapping.source == source.usage && mapping.destination == triggerUsage
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

    static func soloEffect(action: SuperKeySoloAction,
                           longHold: Bool,
                           repeated: Bool) -> SuperKeySoloAction {
        switch action {
        case .none:
            return .none
        case .escape:
            return repeated ? .none : .escape
        case .capsLock:
            return repeated ? .none : .capsLock
        case .inputSource:
            return longHold ? .capsLock : .inputSource
        }
    }

    static func nextInputSourceID(currentID: String?, enabledIDs: [String]) -> String? {
        guard enabledIDs.count > 1 else { return nil }
        guard let currentID, let index = enabledIDs.firstIndex(of: currentID) else {
            return enabledIDs.first
        }
        return enabledIDs[(index + 1) % enabledIDs.count]
    }

    // MARK: - What each event means

    /// A key event, reduced to the only distinctions the decision needs.
    enum Event: Equatable {
        /// The key the super key arrives as, pressed (or repeating while held).
        case triggerDown(isRepeat: Bool, hasPrimaryModifiers: Bool, timestamp: UInt64)
        case triggerUp(timestamp: UInt64)
        /// Any other key going down or up.
        case otherKey
        /// The raw source key, which means that keyboard is not mapped yet.
        case sourceKey
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
        case soloTap(repeated: Bool)
        /// The key was held on its own long enough for its hold action.
        case soloHold(repeated: Bool)
        /// A raw source key is kept out while its keyboard mapping is repaired.
        case interceptAndRemap
    }

    /// Holding the key is the whole feature, so the state tracks whether it is
    /// down, whether anything else has happened and when it went down.
    struct State: Equatable {
        static let soloHoldThresholdNanoseconds: UInt64 = 500_000_000

        private(set) var isHeld = false
        private(set) var isAlone = false
        private var triggerDownTimestamp: UInt64?
        private var didRepeat = false

        mutating func decide(_ event: Event) -> Decision {
            switch event {
            case .triggerDown(let isRepeat, let hasPrimaryModifiers, let timestamp):
                guard isHeld || !isRepeat else { return .swallow }
                if !isHeld {
                    isAlone = !hasPrimaryModifiers
                    triggerDownTimestamp = hasPrimaryModifiers ? nil : timestamp
                    didRepeat = false
                } else if isRepeat {
                    didRepeat = true
                }
                isHeld = true
                return .swallow
            case .triggerUp(let timestamp):
                let wasAlone = isHeld && isAlone
                let wasLong = wasAlone && triggerDownTimestamp.map {
                    timestamp >= $0
                        && timestamp - $0 >= Self.soloHoldThresholdNanoseconds
                } == true
                let repeated = didRepeat
                isHeld = false
                isAlone = false
                triggerDownTimestamp = nil
                didRepeat = false
                if wasLong { return .soloHold(repeated: repeated) }
                return wasAlone ? .soloTap(repeated: repeated) : .swallow
            case .otherKey:
                guard isHeld else { return .pass }
                isAlone = false
                triggerDownTimestamp = nil
                didRepeat = false
                return .addModifiers
            case .otherModifier:
                if isHeld {
                    isAlone = false
                    triggerDownTimestamp = nil
                    didRepeat = false
                }
                return .pass
            case .sourceKey:
                return .interceptAndRemap
            }
        }

        /// Forgets the press in progress. Used when the tap goes away, so a key
        /// held across a teardown cannot leave the state stuck down.
        mutating func reset() {
            isHeld = false
            isAlone = false
            triggerDownTimestamp = nil
            didRepeat = false
        }
    }
}
