// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure policy planning. Only literal minimum-length predicates are editable;
/// arbitrary content predicates must never be interpreted or discarded here.
enum PasswordLengthPolicy {
    static let category = "policyCategoryPasswordContent"
    static let identifier = "com.vorssaint.password.minimum-length"
    enum Failure: Error { case unsupported, conflict, invalid, unavailable }
    enum Scope: String, Codable { case account, global }
    enum Action: String, Codable { case disable, restore, enable }

    struct Entry {
        let scope: Scope
        let policy: [String: Any]
        var id: String { policy["policyIdentifier"] as? String ?? "" }
        func equals(_ other: Entry) -> Bool {
            scope == other.scope && NSDictionary(dictionary: policy).isEqual(to: other.policy)
        }
    }

    struct Snapshot: Codable {
        let user: String
        let guid: String
        let machine: String
        private let account: Data
        private let global: Data

        init(user: String, guid: String, machine: String, account: [String: Any], global: [String: Any]) throws {
            self.user = user
            self.guid = guid
            self.machine = machine
            self.account = try PropertyListSerialization.data(fromPropertyList: account, format: .binary, options: 0)
            self.global = try PropertyListSerialization.data(fromPropertyList: global, format: .binary, options: 0)
        }
        func accountDictionary() throws -> [String: Any] { try Self.dictionary(account) }
        func globalDictionary() throws -> [String: Any] { try Self.dictionary(global) }
        private static func dictionary(_ data: Data) throws -> [String: Any] {
            guard data.count <= 128 * 1024,
                  let value = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { throw Failure.invalid }
            return value
        }
        func rules() throws -> [Entry] {
            var entries: [Entry] = []
            for (scope, policies) in [(Scope.account, try accountDictionary()), (.global, try globalDictionary())] {
                guard let raw = policies[category] else { continue }
                guard let content = raw as? [[String: Any]] else { throw Failure.unsupported }
                var ids = Set<String>()
                for policy in content {
                    guard minimum(in: policy) != nil,
                          let id = policy["policyIdentifier"] as? String,
                          !id.isEmpty, id.count <= 255, ids.insert(id).inserted
                    else { throw Failure.unsupported }
                    entries.append(Entry(scope: scope, policy: policy))
                }
            }
            return entries
        }
        func equivalent(to other: Snapshot) throws -> Bool {
            guard user == other.user, guid == other.guid, machine == other.machine else { return false }
            func normalized(_ value: [String: Any]) -> [String: Any] {
                value.filter { !(( $0.value as? [Any])?.isEmpty ?? false) }
            }
            return try NSDictionary(dictionary: normalized(accountDictionary())).isEqual(to: normalized(other.accountDictionary()))
                && NSDictionary(dictionary: normalized(globalDictionary())).isEqual(to: normalized(other.globalDictionary()))
        }
    }

    struct Plan {
        var removals: [Entry] = []
        var additions: [Entry] = []
        func applying(to snapshot: Snapshot) throws -> Snapshot {
            var account = try snapshot.accountDictionary()
            var global = try snapshot.globalDictionary()
            func apply(_ dictionary: inout [String: Any], scope: Scope) {
                var rules = dictionary[category] as? [[String: Any]] ?? []
                for entry in removals where entry.scope == scope {
                    rules.removeAll { NSDictionary(dictionary: $0).isEqual(to: entry.policy) }
                }
                rules += additions.filter { $0.scope == scope }.map(\.policy)
                if rules.isEmpty { dictionary.removeValue(forKey: category) }
                else { dictionary[category] = rules }
            }
            apply(&account, scope: .account)
            apply(&global, scope: .global)
            return try Snapshot(user: snapshot.user, guid: snapshot.guid, machine: snapshot.machine, account: account, global: global)
        }
    }

    struct Request: Codable {
        let action: Action
        let expected: Snapshot
        let saved: Snapshot?
        let minimum: Int?
        func preparedPayload() throws -> String {
            let plan = try PasswordLengthPolicy.plan(current: expected, action: action, saved: saved, minimum: minimum)
            if action == .disable {
                // Include cancellation (nothing removed) and completed removal.
                // Every partial removal must remain recoverable too.
                for state in [expected, try plan.applying(to: expected)] {
                    _ = try Request(action: .restore, expected: state, saved: expected, minimum: nil).encoded()
                }
            }
            return try encoded()
        }
        func encoded() throws -> String {
            let encoded = try JSONEncoder().encode(self).base64EncodedString()
            guard encoded.utf8.count <= 128 * 1024 else { throw Failure.invalid }
            return encoded
        }
    }

    static func rule(minimum: Int) -> [String: Any] {
        ["policyIdentifier": identifier,
         "policyContent": "policyAttributePassword matches '.{\(minimum),}'",
         "policyParameters": ["minimumLength": minimum]]
    }

    static func minimum(in policy: [String: Any]) -> Int? {
        guard let content = policy["policyContent"] as? String,
              let regex = try? NSRegularExpression(pattern: #"^policyAttributePassword matches '(?:\.|\(\.\))\{([0-9]{1,4}),\}\+?'$"#),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content),
              let value = Int(content[range]), (0...1024).contains(value)
        else { return nil }
        if let raw = policy["policyParameters"] {
            guard let parameters = raw as? [String: Any] else { return nil }
            for key in ["minimumLength", "minimumChars"] {
                if let declared = parameters[key] {
                    guard let number = declared as? NSNumber,
                          CFGetTypeID(number) != CFBooleanGetTypeID(),
                          number.doubleValue == Double(value) else { return nil }
                }
            }
        }
        return value
    }

    static func plan(current: Snapshot, action: Action, saved: Snapshot?, minimum: Int?) throws -> Plan {
        let currentRules = try current.rules()
        switch action {
        case .disable:
            guard saved == nil, !currentRules.isEmpty else { throw Failure.invalid }
            return Plan(removals: currentRules)
        case .enable:
            guard saved == nil, currentRules.isEmpty,
                  let minimum, (1...64).contains(minimum) else { throw Failure.invalid }
            return Plan(additions: [Entry(scope: .account, policy: rule(minimum: minimum))])
        case .restore:
            guard let saved, saved.user == current.user, saved.guid == current.guid, saved.machine == current.machine else { throw Failure.conflict }
            let original = try saved.rules()
            guard !original.isEmpty,
                  currentRules.allSatisfy({ entry in original.contains { $0.equals(entry) } })
            else { throw Failure.conflict }
            return Plan(additions: original.filter { entry in !currentRules.contains { $0.equals(entry) } })
        }
    }

    static func containsManagedPassword(_ value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            if let type = dictionary["PayloadType"] as? String,
               ["com.apple.mobiledevice.passwordpolicy", "com.apple.configuration.passcode.settings"].contains(type) { return true }
            if dictionary["Type"] as? String == "com.apple.configuration.passcode.settings" { return true }
            return dictionary.values.contains(where: containsManagedPassword)
        }
        if let array = value as? [Any] { return array.contains(where: containsManagedPassword) }
        return false
    }
}
