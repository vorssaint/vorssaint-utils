// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum PasswordLengthTests {
    static func run(_ suite: TestSuite) {
        let rule = PasswordLengthPolicy.rule(minimum: 8)
        suite.expect(PasswordLengthPolicy.minimum(in: rule) == 8, "recognizes generated minimum length")
        var custom = rule
        custom["policyContent"] = "policyAttributePassword matches '.*[A-Z].*'"
        suite.expect(PasswordLengthPolicy.minimum(in: custom) == nil, "does not mistake a complexity predicate for length")
        var mismatch = rule
        mismatch["policyParameters"] = ["minimumLength": 4]
        suite.expect(PasswordLengthPolicy.minimum(in: mismatch) == nil, "rejects misleading length metadata")
        func snapshot(_ account: [[String: Any]], _ global: [[String: Any]] = [], guid: String = "test-user", machine: String = "test-machine") -> PasswordLengthPolicy.Snapshot {
            try! .init(user: "tester", guid: guid, machine: machine,
                       account: [PasswordLengthPolicy.category: account, "policyCategoryAuthentication": [["policyIdentifier": "keep-me"]]],
                       global: [PasswordLengthPolicy.category: global])
        }
        let original = snapshot([rule], [PasswordLengthPolicy.rule(minimum: 4)])
        do {
            let removed = try PasswordLengthPolicy.plan(current: original, action: .disable, saved: nil, minimum: nil)
            suite.expect(removed.removals.count == 2 && removed.additions.isEmpty, "removes both account and system length rules")
            let disabled = try removed.applying(to: original)
            suite.expect(try disabled.rules().isEmpty, "no length rules remain")
            suite.expect(try disabled.accountDictionary()["policyCategoryAuthentication"] != nil, "authentication rules survive")
            let restoration = try PasswordLengthPolicy.plan(current: disabled, action: .restore, saved: original, minimum: nil)
            suite.expect(restoration.additions.count == 2 && restoration.removals.isEmpty, "restores both original scopes")
            suite.expect(try restoration.applying(to: disabled).equivalent(to: original), "round trip preserves exact policy dictionaries")
            let partial = snapshot([], [PasswordLengthPolicy.rule(minimum: 4)])
            suite.expect(try PasswordLengthPolicy.plan(current: partial, action: .restore, saved: original, minimum: nil).additions.count == 1, "recovers partial removal")
            let unrelated = try disabled.accountDictionary().merging(["policyCategoryPasswordChange": [["policyIdentifier": "new-expiry"]]]) { _, new in new }
            let changed = try PasswordLengthPolicy.Snapshot(user: "tester", guid: "test-user", machine: "test-machine", account: unrelated, global: disabled.globalDictionary())
            let restored = try PasswordLengthPolicy.plan(current: changed, action: .restore, saved: original, minimum: nil).applying(to: changed)
            suite.expect(try restored.accountDictionary()["policyCategoryPasswordChange"] != nil, "restoration preserves unrelated later changes")
            let enabled = try PasswordLengthPolicy.plan(current: disabled, action: .enable, saved: nil, minimum: 6)
            suite.expect(enabled.additions.count == 1 && enabled.additions[0].scope == .account, "new limit applies to current account only")
        } catch { suite.expect(false, "valid transitions failed: \(error)") }
        for invalid in [snapshot([custom]), snapshot([mismatch]), snapshot([rule, rule])] {
            suite.expect((try? invalid.rules()) == nil, "unknown, misleading and duplicate content policies fail closed")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = folder.appendingPathComponent("recovery.json")
            let recovery = try PasswordLengthRecovery(url: file)
            suite.expect((try? PasswordLengthRecovery(url: file)) == nil, "serializes journal writers across service instances")
            try recovery.create(original)
            suite.expect((try? recovery.create(snapshot([]))) == nil, "never overwrites an existing recovery record")
            suite.expect(try recovery.read()?.equivalent(to: original) == true, "failed stale write keeps original recovery")
            suite.expect((try? recovery.remove(matching: snapshot([]))) == nil, "does not delete a different transaction's recovery")
            try recovery.remove(matching: original)
            suite.expect(try recovery.read() == nil, "removes only the completed transaction")
        } catch { suite.expect(false, "recovery persistence failed: \(error)") }
        let off = snapshot([])
        suite.expect((try? PasswordLengthPolicy.plan(current: snapshot([PasswordLengthPolicy.rule(minimum: 12)]), action: .restore, saved: original, minimum: nil)) == nil, "does not overwrite a later length rule")
        suite.expect((try? PasswordLengthPolicy.plan(current: snapshot([], guid: "other-user"), action: .restore, saved: original, minimum: nil)) == nil, "rejects another account's recovery file")
        suite.expect((try? PasswordLengthPolicy.plan(current: snapshot([], machine: "other-machine"), action: .restore, saved: original, minimum: nil)) == nil, "rejects another machine's recovery file")
        do {
            let oversized = try PasswordLengthPolicy.Snapshot(user: "tester", guid: "test-user", machine: "test-machine", account: ["unrelated": String(repeating: "x", count: 120_000)], global: [:])
            let request = PasswordLengthPolicy.Request(action: .restore, expected: oversized, saved: original, minimum: nil)
            suite.expect((try? request.encoded()) == nil, "bounds command payload before authorization")
        } catch { suite.expect(false, "oversized fixture failed") }
        do {
            var largeRule = rule
            largeRule["description"] = String(repeating: "x", count: 50_000)
            let large = snapshot([largeRule])
            let request = PasswordLengthPolicy.Request(action: .disable, expected: large, saved: nil, minimum: nil)
            suite.expect((try? request.encoded()) != nil, "large removal fits by itself")
            suite.expect((try? request.preparedPayload()) == nil, "rejects removal when cancelled or partial recovery would exceed command bound")
        }
        for value in [0, -1, 65] {
            suite.expect((try? PasswordLengthPolicy.plan(current: off, action: .enable, saved: nil, minimum: value)) == nil, "rejects invalid new minimum")
        }
        suite.expect(PasswordLengthPolicy.containsManagedPassword(["PayloadType": "com.apple.mobiledevice.passwordpolicy"]), "detects password profile")
        suite.expect(!PasswordLengthPolicy.containsManagedPassword(["PayloadType": "com.apple.applicationaccess"]), "unrelated profiles do not block")
    }
}
