// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where the credentials of saved logins are kept, one implementation per
/// provider. A copy is the provider's own bytes, verbatim.
protocol AgentCredentialCopies {
    /// Nil when there is no copy for the login.
    func read(_ id: AgentAccount.ID) throws -> Data?
    func write(_ data: Data, for id: AgentAccount.ID) throws
    /// Deleting a copy that is not there succeeds.
    func delete(_ id: AgentAccount.ID) throws
}

/// A copy could not be read or written. `message` is for logs and support.
struct AgentCredentialCopyError: Error, Equatable {
    let message: String
}

/// Claude logins sit in the Keychain, each under the saved login's id, and go
/// through the same `security` tool as the live one.
struct ClaudeCredentialCopies: AgentCredentialCopies {
    static let service = "Vorssaint Agent Account"

    let secrets: ClaudeSecretStore

    func read(_ id: AgentAccount.ID) throws -> Data? {
        try secrets.read(service: Self.service, account: id).map { Data($0.utf8) }
    }

    func write(_ data: Data, for id: AgentAccount.ID) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw AgentCredentialCopyError(message: "the credential is not text")
        }
        try secrets.write(text, service: Self.service, account: id)
    }

    func delete(_ id: AgentAccount.ID) throws {
        try secrets.delete(service: Self.service, account: id)
    }
}

/// Codex logins are files: `<directory>/<id>/auth.json`, owner-only. Each
/// login's folder doubles as its `CODEX_HOME` when Codex is asked for that
/// login's limits, so Codex may add files of its own there.
struct CodexCredentialCopies: AgentCredentialCopies {
    let directory: URL

    /// The folder Codex is pointed at for this login; nil for an id that
    /// could name a path outside `directory`.
    func home(for id: AgentAccount.ID) -> URL? {
        guard !id.isEmpty, id != ".", id != "..", !id.contains("/"), !id.contains("\0") else { return nil }
        return directory.appending(path: id, directoryHint: .isDirectory)
    }

    func read(_ id: AgentAccount.ID) throws -> Data? {
        let file = try file(for: id)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do { return try Data(contentsOf: file) } catch {
            throw AgentCredentialCopyError(message: "auth.json could not be read")
        }
    }

    func write(_ data: Data, for id: AgentAccount.ID) throws {
        let file = try file(for: id)
        guard PrivateFileStore.createDirectory(at: file.deletingLastPathComponent(), container: directory),
              PrivateFileStore.write(data, to: file) else {
            throw AgentCredentialCopyError(message: "auth.json could not be written")
        }
    }

    func delete(_ id: AgentAccount.ID) throws {
        let folder = try file(for: id).deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        do { try FileManager.default.removeItem(at: folder) } catch {
            throw AgentCredentialCopyError(message: "the saved login could not be removed")
        }
    }

    private func file(for id: AgentAccount.ID) throws -> URL {
        guard let home = home(for: id) else { throw AgentCredentialCopyError(message: "the login's id is not a name") }
        return home.appending(path: "auth.json", directoryHint: .notDirectory)
    }
}
