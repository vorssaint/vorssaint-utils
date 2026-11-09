// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum KeyboardRemappingTapStatus: Equatable {
    case inactive
    case starting
    case active
    case failed

    static func afterTapCreation(succeeded: Bool) -> KeyboardRemappingTapStatus {
        succeeded ? .active : .failed
    }
}

struct KeyboardRemappingChord: Codable, Equatable, Identifiable {
    var id = UUID()
    var keyCode: Int64 = -1
    var modifierMask = 0

    var modifiers: GlobalShortcutModifiers {
        GlobalShortcutModifiers(rawValue: modifierMask).intersection(.validMask)
    }

    var isValid: Bool {
        (0..<128).contains(keyCode)
            && modifierMask >= 0
            && GlobalShortcutModifiers(rawValue: modifierMask).intersection(.validMask).rawValue == modifierMask
    }

    var canPersist: Bool {
        (keyCode == -1 || (0..<128).contains(keyCode))
            && modifierMask >= 0
            && GlobalShortcutModifiers(rawValue: modifierMask).intersection(.validMask).rawValue == modifierMask
    }
}

enum KeyboardRemappingActionKind: String, Codable, CaseIterable, Identifiable {
    case keySequence
    case typeText
    case openLink
    case openApp
    case disabled

    var id: String { rawValue }
}

enum KeyboardRemappingOutputAction: Equatable {
    case consume
    case sendKeySequence
    case typeText
    case openLink
    case openApp

    static func forKeyDown(_ kind: KeyboardRemappingActionKind,
                           isInitial: Bool,
                           isRepeat: Bool) -> Self {
        guard isInitial || isRepeat else { return .consume }
        switch kind {
        case .keySequence: return .sendKeySequence
        case .typeText: return .typeText
        case .openLink: return isInitial ? .openLink : .consume
        case .openApp: return isInitial ? .openApp : .consume
        case .disabled: return .consume
        }
    }

    static func shouldSuppressKeyUp(hasHeldMapping: Bool) -> Bool {
        hasHeldMapping
    }
}

enum KeyboardRemappingRisk: Equatable {
    case modifier
    case letter
    case number

    static func forSourceKeyCode(_ keyCode: Int64) -> Self? {
        if [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode) {
            return .modifier
        }
        if letterKeyCodes.contains(keyCode) { return .letter }
        if numberKeyCodes.contains(keyCode) { return .number }
        return nil
    }

    static func modifierForSourceKeyCode(_ keyCode: Int64) -> GlobalShortcutModifiers? {
        switch keyCode {
        case Int64(kVK_Command), Int64(kVK_RightCommand): return .command
        case Int64(kVK_Shift), Int64(kVK_RightShift): return .shift
        case Int64(kVK_Option), Int64(kVK_RightOption): return .option
        case Int64(kVK_Control), Int64(kVK_RightControl): return .control
        default: return nil
        }
    }

    static func handles(eventType: CGEventType, keyCode: Int64) -> Bool {
        eventType == .keyDown || eventType == .keyUp
            || (eventType == .flagsChanged && forSourceKeyCode(keyCode) == .modifier)
    }

    private static let letterKeyCodes: Set<Int64> = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11,
        12, 13, 14, 15, 16, 17,
        31, 32, 33, 34, 35, 37, 38, 39, 40, 45, 46,
    ]

    private static let numberKeyCodes: Set<Int64> = [18, 19, 20, 21, 22, 23, 25, 26, 28, 29]
}

struct KeyboardRemappingRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var enabled = true
    var sourceKeyCode: Int64 = -1
    var sourceModifierMask = 0
    var output: [KeyboardRemappingChord] = []
    var bundleIdentifier = ""
    var actionKind: KeyboardRemappingActionKind?
    var text = ""
    var link = ""
    var appBundleIdentifier = ""

    init(id: UUID = UUID(), enabled: Bool = true, sourceKeyCode: Int64 = -1,
         sourceModifierMask: Int = 0, output: [KeyboardRemappingChord] = [],
         bundleIdentifier: String = "", actionKind: KeyboardRemappingActionKind? = nil,
         text: String = "", link: String = "", appBundleIdentifier: String = "") {
        self.id = id
        self.enabled = enabled
        self.sourceKeyCode = sourceKeyCode
        self.sourceModifierMask = sourceModifierMask
        self.output = output
        self.bundleIdentifier = bundleIdentifier
        self.actionKind = actionKind
        self.text = text
        self.link = link
        self.appBundleIdentifier = appBundleIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, sourceKeyCode, sourceModifierMask, output, bundleIdentifier
        case actionKind, text, link, appBundleIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        sourceKeyCode = try container.decodeIfPresent(Int64.self, forKey: .sourceKeyCode) ?? -1
        sourceModifierMask = try container.decodeIfPresent(Int.self, forKey: .sourceModifierMask) ?? 0
        output = try container.decodeIfPresent([KeyboardRemappingChord].self, forKey: .output) ?? []
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier) ?? ""
        actionKind = try container.decodeIfPresent(KeyboardRemappingActionKind.self, forKey: .actionKind)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        link = try container.decodeIfPresent(String.self, forKey: .link) ?? ""
        appBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .appBundleIdentifier) ?? ""
    }

    var resolvedActionKind: KeyboardRemappingActionKind {
        actionKind ?? (output.isEmpty ? .disabled : .keySequence)
    }

    var sourceModifiers: GlobalShortcutModifiers {
        GlobalShortcutModifiers(rawValue: sourceModifierMask).intersection(.validMask)
    }

    var sourceRisk: KeyboardRemappingRisk? {
        KeyboardRemappingRisk.forSourceKeyCode(sourceKeyCode)
    }

    var hasValidBundleIdentifier: Bool {
        bundleIdentifier.utf8.count <= KeyboardRemappingConfig.maximumBundleIdentifierLength
            && (bundleIdentifier.isEmpty
                || bundleIdentifier.range(of: #"^[A-Za-z0-9][A-Za-z0-9.-]*$"#,
                                          options: .regularExpression) != nil)
    }

    var isValid: Bool {
        (0..<128).contains(sourceKeyCode)
            && sourceModifierMask >= 0
            && GlobalShortcutModifiers(rawValue: sourceModifierMask).intersection(.validMask).rawValue
                == sourceModifierMask
            && output.count <= KeyboardRemappingConfig.maximumOutputChords
            && output.allSatisfy(\.isValid)
            && hasValidBundleIdentifier
            && hasValidAction
    }

    var canPersist: Bool {
        (sourceKeyCode == -1 || (0..<128).contains(sourceKeyCode))
            && sourceModifierMask >= 0
            && GlobalShortcutModifiers(rawValue: sourceModifierMask).intersection(.validMask).rawValue
                == sourceModifierMask
            && output.count <= KeyboardRemappingConfig.maximumOutputChords
            && output.allSatisfy(\.canPersist)
            && bundleIdentifier.utf8.count <= KeyboardRemappingConfig.maximumBundleIdentifierLength
            && text.utf8.count <= KeyboardRemappingConfig.maximumTextBytes
            && link.utf8.count <= KeyboardRemappingConfig.maximumLinkBytes
            && appBundleIdentifier.utf8.count <= KeyboardRemappingConfig.maximumBundleIdentifierLength
    }

    private var hasValidAction: Bool {
        switch resolvedActionKind {
        case .keySequence:
            return !output.isEmpty
        case .typeText:
            return !text.isEmpty && text.utf8.count <= KeyboardRemappingConfig.maximumTextBytes
        case .openLink:
            guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host?.isEmpty == false else { return false }
            return link.utf8.count <= KeyboardRemappingConfig.maximumLinkBytes
        case .openApp:
            return appBundleIdentifier.range(of: #"^[A-Za-z0-9][A-Za-z0-9.-]*$"#,
                                             options: .regularExpression) != nil
        case .disabled:
            return true
        }
    }
}

enum KeyboardRemappingConfig {
    static let maximumRules = 128
    static let maximumOutputChords = 8
    static let maximumBundleIdentifierLength = 255
    static let maximumTextBytes = 4_096
    static let maximumLinkBytes = 2_048
    static let maximumEncodedBytes = 65_536

    static func decode(_ raw: String) -> [KeyboardRemappingRule] {
        guard raw.utf8.count <= maximumEncodedBytes,
              let data = raw.data(using: .utf8),
              let rules = try? JSONDecoder().decode([KeyboardRemappingRule].self, from: data)
        else { return [] }

        var seen = Set<String>()
        return rules.prefix(maximumRules).filter { rule in
            guard rule.canPersist else { return false }
            guard rule.isValid else { return true }
            let bundle = rule.bundleIdentifier.lowercased()
            let identity = "\(bundle):\(rule.sourceKeyCode):\(rule.sourceModifierMask)"
            return seen.insert(identity).inserted
        }
    }

    static func encode(_ rules: [KeyboardRemappingRule]) -> String {
        let persistableRules = Array(rules.filter(\.canPersist).prefix(maximumRules))
        guard let data = try? JSONEncoder().encode(persistableRules),
              data.count <= maximumEncodedBytes,
              let string = String(data: data, encoding: .utf8)
        else { return "[]" }
        return string
    }

    static func matchingRule(keyCode: Int64,
                             modifiers: GlobalShortcutModifiers,
                             bundleIdentifier: String?,
                             rules: [KeyboardRemappingRule]) -> KeyboardRemappingRule? {
        let activeBundle = bundleIdentifier?.lowercased()
        return rules
            .filter { $0.enabled && $0.sourceKeyCode == keyCode && $0.isValid }
            .filter {
                $0.bundleIdentifier.isEmpty
                    || $0.bundleIdentifier.lowercased() == activeBundle
            }
            .sorted {
                let firstScore = ($0.bundleIdentifier.isEmpty ? 0 : 2)
                    + ($0.sourceModifiers.isEmpty ? 0 : 1)
                let secondScore = ($1.bundleIdentifier.isEmpty ? 0 : 2)
                    + ($1.sourceModifiers.isEmpty ? 0 : 1)
                return firstScore > secondScore
            }
            .first {
                $0.sourceModifiers.isEmpty || $0.sourceModifiers == modifiers
            }
    }

    static func outputModifiers(for chord: KeyboardRemappingChord,
                                matching rule: KeyboardRemappingRule,
                                incoming: GlobalShortcutModifiers) -> GlobalShortcutModifiers {
        rule.sourceModifiers.isEmpty ? chord.modifiers.union(incoming) : chord.modifiers
    }
}
