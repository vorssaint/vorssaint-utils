// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The saved logins: who they are in `accounts.json`, and each one's
/// credential wherever its provider's copies live. Nothing here goes into
/// preferences or a settings backup; a login belongs to this Mac.
///
/// Not safe to share between threads: the service keeps it on its queue.
final class AgentAccountStore {
    static let version = 1
    static let fileName = "accounts.json"

    private struct File: Codable {
        let version: Int
        let accounts: [AgentAccount]
    }

    /// A provider without copies here cannot have its logins saved.
    struct Unsupported: Error {}

    private let directory: URL
    private let copies: [AgentProvider: AgentCredentialCopies]
    private(set) var accounts: [AgentAccount] = []

    init(directory: URL, copies: [AgentProvider: AgentCredentialCopies]) {
        self.directory = directory
        self.copies = copies
        load()
    }

    private var fileURL: URL { directory.appending(path: Self.fileName, directoryHint: .notDirectory) }

    /// A file from a newer version reads as no logins and is left alone until
    /// the person saves one here, which is theirs to decide.
    func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL), let file = try? decoder.decode(File.self, from: data),
              file.version == Self.version else {
            accounts = []
            return
        }
        accounts = file.accounts
    }

    func account(_ id: AgentAccount.ID) -> AgentAccount? {
        accounts.first { $0.id == id }
    }

    /// Saves the live login, or brings a saved one up to date: its tokens,
    /// its name, and the mark that it needed a new login.
    @discardableResult
    func capture(_ live: AgentLiveLogin, now: Date = Date()) throws -> AgentAccount {
        try write(live.credential, for: live.id, provider: live.provider)
        var account = self.account(live.id) ?? AgentAccount(id: live.id, provider: live.provider, email: live.email,
                                                       organization: live.organization, label: "", added: now,
                                                       savedAt: now, needsLogin: false, identity: live.identity)
        account.email = live.email
        account.organization = live.organization
        account.identity = live.identity
        account.savedAt = now
        account.needsLogin = false
        try put(account)
        return account
    }

    func credential(for id: AgentAccount.ID) throws -> Data? {
        guard let account = self.account(id), let copies = copies[account.provider] else { return nil }
        return try copies.read(id)
    }

    /// Stores tokens a provider handed out for a saved login.
    func storeCredential(_ data: Data, for id: AgentAccount.ID, now: Date = Date()) throws {
        guard var account = self.account(id) else { return }
        try write(data, for: id, provider: account.provider)
        account.savedAt = now
        try put(account)
    }

    /// Forgets a saved login and its copy. The live login is never touched.
    func remove(_ id: AgentAccount.ID) throws {
        guard let account = self.account(id) else { return }
        try copies[account.provider]?.delete(id)
        accounts.removeAll { $0.id == id }
        try save()
    }

    func rename(_ id: AgentAccount.ID, label: String) throws {
        guard var account = self.account(id) else { return }
        account.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        try put(account)
    }

    func setNeedsLogin(_ id: AgentAccount.ID, _ needsLogin: Bool) throws {
        guard var account = self.account(id), account.needsLogin != needsLogin else { return }
        account.needsLogin = needsLogin
        try put(account)
    }

    private func write(_ data: Data, for id: AgentAccount.ID, provider: AgentProvider) throws {
        guard let copies = copies[provider] else { throw Unsupported() }
        try copies.write(data, for: id)
    }

    private func put(_ account: AgentAccount) throws {
        let previous = accounts
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        guard accounts != previous else { return }
        try save()
    }

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(File(version: Self.version, accounts: accounts))
        guard PrivateFileStore.createDirectory(at: directory, container: directory),
              PrivateFileStore.write(data, to: fileURL) else {
            throw AgentCredentialCopyError(message: "\(Self.fileName) could not be written")
        }
    }
}
