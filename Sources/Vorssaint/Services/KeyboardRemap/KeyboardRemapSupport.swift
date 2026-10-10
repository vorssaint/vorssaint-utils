// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum KeyboardRemapSupport {
    static let capsTriggerUsage: UInt64 = 0x70000006E // F19, separate from Super Key's F18
    static let capsTriggerKey: Int64 = Int64(kVK_F19)

    static func storage(_ mappings: [SuperKeyMapping]) -> String {
        SuperKeySupport.mappingArgument(mappings)
    }

    static func storedMappings(_ value: String) -> [SuperKeyMapping] {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["UserKeyMapping"] as? [[String: NSNumber]] else { return [] }
        return entries.compactMap {
            guard let source = $0["HIDKeyboardModifierMappingSrc"],
                  let destination = $0["HIDKeyboardModifierMappingDst"] else { return nil }
            return SuperKeyMapping(source: source.uint64Value, destination: destination.uint64Value)
        }
    }

    /// Remove only exact entries we installed. All devices must agree on the
    /// external remainder before writing a global table.
    static func remainingMappings(_ report: String, owned: [SuperKeyMapping]) -> [SuperKeyMapping]? {
        let tables = SuperKeySupport.mappingTables(report, property: SuperKeySupport.userMappingProperty)
            .map { $0.filter { !owned.contains($0) } }
        guard let first = tables.first,
              tables.dropFirst().allSatisfy({ SuperKeySupport.mappingsMatch(first, $0) }) else { return nil }
        return first
    }

    static func mergedMappings(_ report: String, owned: [SuperKeyMapping],
                               wanted: [SuperKeyMapping]) -> [SuperKeyMapping]? {
        guard let remaining = remainingMappings(report, owned: owned),
              !remaining.contains(where: { external in
                  wanted.contains { $0.source == external.source || $0.destination == external.source
                      || $0.source == external.destination || $0.destination == external.destination }
              }) else { return nil }
        return remaining + wanted
    }

    /// macOS applies Modifier Keys before UserKeyMapping. A table readback
    /// cannot verify physical sources while an earlier mapping consumes them
    /// or routes another physical key into one of our sources.
    static func hasModifierConflict(_ tables: [[SuperKeyMapping]], wanted: [SuperKeyMapping]) -> Bool {
        func normalized(_ usage: UInt64) -> UInt64 {
            usage == 0xFF0100000003 ? 0xFF00000003 : usage
        }
        let sources = Set(wanted.map { normalized($0.source) })
        return tables.joined().contains {
            let source = normalized($0.source), destination = normalized($0.destination)
            return source != destination && (sources.contains(source) || sources.contains(destination))
        }
    }

    enum Action: Equatable {
        case pass, swallow, inputSource, capsLock
        case application(String)
        case key(Int64, CGEventFlags)
    }

    /// Remember the incoming physical down until its up, even after its
    /// modifiers change. Each event is translated once, so A→B and B→C rules
    /// never recurse into one another.
    struct State {
        private var presses: [Int64: Action] = [:]
        mutating func reset() { presses.removeAll() }
        mutating func decide(key: Int64, down: Bool, repeatKey: Bool,
                             flags: CGEventFlags, commandLabel: String?,
                             config: KeyboardRemapConfiguration) -> Action {
            if let held = presses[key] {
                if !down { presses.removeValue(forKey: key) }
                switch held {
                case .key: return held
                default: return .swallow
                }
            }
            guard down else { return .pass }
            let trigger = config.triggers.first { $0.trigger.code == key }
            let logicalKey = trigger?.source.code ?? key
            let rule = config.shortcutRules.first {
                $0.enabled && $0.source.matches(key: logicalKey, flags: flags, commandLabel: commandLabel)
            }
            var target = rule?.target
            if target == nil, let trigger,
               GlobalShortcutModifiers(cgFlags: flags).isEmpty {
                target = config.keyRules.first { $0.enabled && $0.source == trigger.source.id }?.target
                if target == nil, trigger.source.id == "capsLock" { target = .capsLock }
            }
            guard let target else {
                if trigger != nil { presses[key] = .swallow; return .swallow }
                return .pass
            }
            let result: Action
            switch target {
            case .none: result = .swallow
            case .inputSource: result = .inputSource
            case .capsLock: result = .capsLock
            case .application(let id): result = .application(id)
            case .key(let id):
                guard let destination = KeyboardRemapKey.named(id) else { return .pass }
                result = .key(destination.code, flags)
            case .shortcut(let chord):
                // A suggested Option-Q → Command-Q follows the same logical Q
                // position in non-US layouts. Recorded rules use physical codes.
                let destination = chord.character != nil && chord.character == rule?.source.character
                    ? key : chord.keyCode
                result = .key(destination, chord.shortcut.modifiers.cgFlags)
            }
            presses[key] = result
            return repeatKey ? .swallow : result
        }
    }
}
