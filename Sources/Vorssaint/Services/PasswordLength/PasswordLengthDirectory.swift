// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import OpenDirectory
import Darwin

/// No password is read, checked or changed. Elevated operations only add/remove
/// validated content rules; authentication and expiration policies stay intact.
final class PasswordLengthDirectory {
    static let commandFlag = "--password-length-policy"
    private let user: String
    private let node: ODNode
    private let record: ODRecord
    private let guid: String

    init(user: String) throws {
        guard !user.isEmpty, user.count <= 256, !user.contains("/"), !user.contains("\0") else {
            throw PasswordLengthPolicy.Failure.invalid
        }
        self.user = user
        node = try ODNode(session: ODSession.default(), name: "/Local/Default")
        record = try node.record(withRecordType: kODRecordTypeUsers, name: user, attributes: nil)
        guard let guid = try record.values(forAttribute: kODAttributeTypeGUID).first as? String,
              UUID(uuidString: guid) != nil,
              let uidText = try record.values(forAttribute: kODAttributeTypeUniqueID).first as? String,
              let uid = UInt32(uidText), uid >= 500
        else { throw PasswordLengthPolicy.Failure.unavailable }
        self.guid = guid
    }

    func snapshot() throws -> PasswordLengthPolicy.Snapshot {
        // The Objective-C wrapper throws nilError for a legitimate absent policy.
        // CF distinguishes a nil dictionary with no error from a failed read.
        var error: Unmanaged<CFError>?
        guard let rawNode = ODNodeCreateWithName(nil, nil, "/Local/Default" as CFString, &error) else {
            throw error?.takeRetainedValue() as Error? ?? PasswordLengthPolicy.Failure.unavailable
        }
        let cfNode = rawNode.takeRetainedValue()
        guard let rawRecord = ODNodeCopyRecord(cfNode, kODRecordTypeUsers, user as CFString, nil, &error) else {
            throw error?.takeRetainedValue() as Error? ?? PasswordLengthPolicy.Failure.unavailable
        }
        let cfRecord = rawRecord.takeRetainedValue()
        let global = ODNodeCopyAccountPolicies(cfNode, &error)
        if let error { throw error.takeRetainedValue() }
        let account = ODRecordCopyAccountPolicies(cfRecord, &error)
        if let error { throw error.takeRetainedValue() }
        var host = UUID().uuid
        var timeout = timespec(tv_sec: 1, tv_nsec: 0)
        guard gethostuuid(&host, &timeout) == 0 else { throw PasswordLengthPolicy.Failure.unavailable }
        return try .init(user: user, guid: guid, machine: UUID(uuid: host).uuidString,
                         account: account as? [String: Any] ?? [:],
                         global: global as? [String: Any] ?? [:])
    }

    static func checkManagement() throws {
        let enrollment = Shell.run("/usr/bin/profiles", ["status", "-type", "enrollment"])
        guard enrollment.status == 0,
              enrollment.output.contains("Enrolled via DEP: No"),
              enrollment.output.contains("MDM enrollment: No") else {
            throw PasswordLengthPolicy.Failure.unsupported
        }
        let profiles = Shell.run("/usr/bin/profiles", ["list", "-type", "configuration", "-output", "stdout-xml"])
        guard profiles.status == 0, let data = profiles.output.data(using: .utf8),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
              value is [String: Any], !PasswordLengthPolicy.containsManagedPassword(value)
        else { throw PasswordLengthPolicy.Failure.unsupported }
    }

    private func change(_ entry: PasswordLengthPolicy.Entry, adding: Bool) throws {
        let category = PasswordLengthPolicy.category
        switch (entry.scope, adding) {
        case (.account, true): try record.addAccountPolicy(entry.policy, toCategory: category)
        case (.account, false): try record.removeAccountPolicy(entry.policy, fromCategory: category)
        case (.global, true): try node.addAccountPolicy(entry.policy, toCategory: category)
        case (.global, false): try node.removeAccountPolicy(entry.policy, fromCategory: category)
        }
    }

    func apply(_ request: PasswordLengthPolicy.Request) throws {
        guard geteuid() == 0 else { throw PasswordLengthPolicy.Failure.unavailable }
        try Self.checkManagement() // root sees system profiles unavailable to the caller
        var expected = try snapshot()
        guard try expected.equivalent(to: request.expected) else { throw PasswordLengthPolicy.Failure.conflict }
        let plan = try PasswordLengthPolicy.plan(current: expected, action: request.action,
                                                 saved: request.saved, minimum: request.minimum)
        for (adding, entries) in [(false, plan.removals), (true, plan.additions)] {
            for entry in entries {
                guard try snapshot().equivalent(to: expected) else { throw PasswordLengthPolicy.Failure.conflict }
                try change(entry, adding: adding)
                let step = adding ? PasswordLengthPolicy.Plan(additions: [entry]) : PasswordLengthPolicy.Plan(removals: [entry])
                expected = try step.applying(to: expected)
            }
        }
        guard try snapshot().equivalent(to: expected) else { throw PasswordLengthPolicy.Failure.conflict }
    }

    /// Intercepted before Defaults, recovery guards or NSApplication can run as root.
    static func runCommandIfRequested() {
        let args = CommandLine.arguments
        guard args.contains(commandFlag) else { return }
        do {
            guard args.count == 3, args[1] == commandFlag, geteuid() == 0,
                  args[2].utf8.count <= 128 * 1024,
                  let data = Data(base64Encoded: args[2]) else { throw PasswordLengthPolicy.Failure.invalid }
            let request = try JSONDecoder().decode(PasswordLengthPolicy.Request.self, from: data)
            // Serializes this app's elevated invocations across users and variants.
            let fd = open("/var/run/com.vorssaint.password-length.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw PasswordLengthPolicy.Failure.unavailable }
            defer { close(fd) }
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_uid == 0,
                  info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
                  flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw PasswordLengthPolicy.Failure.unavailable }
            defer { _ = flock(fd, LOCK_UN) }
            try PasswordLengthDirectory(user: request.expected.user).apply(request)
            exit(0)
        } catch {
            fputs("Password length policy operation failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
