// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Security

enum AuthenticatorStoreTests {
    static func run(expect: (Bool, String) -> Void) {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("AuthenticatorStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }
        let file = root.appendingPathComponent(AuthenticatorStore.fileName)

        var github = OTPAccount()
        github.issuer = "GitHub"
        github.label = "octocat"
        let githubEntry = OTPEntry(account: github, secret: Data("12345678901234567890".utf8))
        var counter = OTPAccount()
        counter.label = "counter"
        counter.kind = .hotp
        let counterEntry = OTPEntry(account: counter, secret: Data([1, 2, 3, 4, 5]))

        do {
            let secrets = MemorySecretStore()
            var store = AuthenticatorStore(directoryURL: root, secrets: secrets)
            try store.load()
            expect(store.accounts.isEmpty, "a fresh store starts empty")
            try store.add(githubEntry)
            try store.add(counterEntry)
            expect(store.accounts.map(\.id) == [github.id, counter.id], "accounts keep insertion order")
            expect(secrets.secrets[github.id] == githubEntry.secret, "the secret went to the secret store")
            let written = try Data(contentsOf: file)
            expect(!String(decoding: written, as: UTF8.self).contains("GEZDGNBV")
                    && !String(decoding: written, as: UTF8.self).contains("12345678901234567890"),
                   "the metadata file carries no secret")
            let mode = try manager.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
            expect(mode == 0o600, "the metadata file is private to its owner")

            var reloaded = AuthenticatorStore(directoryURL: root, secrets: secrets)
            try reloaded.load()
            expect(reloaded.accounts == store.accounts, "accounts survive a reload")
            expect(try reloaded.secret(for: github.id) == githubEntry.secret, "a secret reads back by id")

            try reloaded.advanceCounter(id: counter.id)
            expect(reloaded.accounts.first { $0.id == counter.id }?.counter == 1, "HOTP counters advance")
            try reloaded.advanceCounter(id: github.id)
            expect(reloaded.accounts.first { $0.id == github.id }?.counter == 0, "TOTP counters stay")

            expect(reloaded.isDuplicate(githubEntry), "the same account again is a duplicate")
            var renamed = githubEntry
            renamed.account.label = "someone-else"
            expect(!reloaded.isDuplicate(renamed), "a different label is not a duplicate")
            var otherSecret = githubEntry
            otherSecret.secret = Data("other".utf8)
            expect(!reloaded.isDuplicate(otherSecret), "a different secret is not a duplicate")

            try reloaded.reorder([counter.id, github.id])
            expect(reloaded.accounts.map(\.id) == [counter.id, github.id], "reordering persists")
            expect(reloaded.entries().map(\.secret) == [counterEntry.secret, githubEntry.secret],
                   "export pairs each account with its secret in order")

            try reloaded.remove(id: github.id)
            expect(reloaded.accounts.map(\.id) == [counter.id], "a removed account leaves the list")
            expect(secrets.secrets[github.id] == nil, "a removed account takes its secret along")

            secrets.failNextWrite = true
            do {
                try reloaded.add(githubEntry)
                expect(false, "a secret store refusal aborts the add")
            } catch let error as AuthenticatorStoreError {
                expect(error == .keychain(errSecIO), "the refusal carries its status")
                expect(reloaded.accounts.map(\.id) == [counter.id], "a refused add leaves no row")
            }
        } catch {
            expect(false, "the store works on a fresh directory: \(error)")
        }

        // An unreadable file blocks every write.
        do {
            try Data("{not json".utf8).write(to: file)
            var broken = AuthenticatorStore(directoryURL: root, secrets: MemorySecretStore())
            do {
                try broken.load()
                expect(false, "a corrupt file fails to load")
            } catch let error as AuthenticatorStoreError {
                expect(error == .unreadable, "a corrupt file is reported as unreadable")
            }
            do {
                try broken.add(githubEntry)
                expect(false, "a failed load blocks adding")
            } catch let error as AuthenticatorStoreError {
                expect(error == .cannotSave, "a failed load refuses to save")
            }
            expect(try Data(contentsOf: file) == Data("{not json".utf8), "the corrupt file is left alone")
        } catch {
            expect(false, "the corrupt-file check runs: \(error)")
        }
    }
}
