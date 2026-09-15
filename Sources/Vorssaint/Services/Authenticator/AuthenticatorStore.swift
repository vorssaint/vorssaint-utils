// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Security

/// Where secrets go. The live store is the Keychain; tests hand in a
/// dictionary. Every call answers with an `OSStatus` so a refusal can be
/// shown as the number the person can look up.
protocol AuthenticatorSecretStore {
    func read(id: UUID) -> (status: OSStatus, secret: Data?)
    func write(id: UUID, secret: Data) -> OSStatus
    func delete(id: UUID) -> OSStatus
    /// Called once after the account list is read, with every id it holds,
    /// so a store can fold older layouts in at one go.
    func prepare(ids: [UUID])
}

extension AuthenticatorSecretStore {
    func prepare(ids: [UUID]) {}
}

/// One generic password under a service of the bundle id holding every
/// secret as JSON, this device only. One item means the Keychain asks once
/// ("Always allow") rather than once per account and per rebuild; the
/// creating app is trusted on its own item as long as its signing identity
/// stays the same. Developer and official installations never see each
/// other's entries. Accounts stored one item each by an earlier build are
/// folded in the first time they are read.
final class KeychainSecretStore: AuthenticatorSecretStore {
    let service: String
    private static let blobAccount = "secrets"
    private var cache: [String: Data]?
    /// A refusal ("Deny" on the Keychain prompt, or a locked keychain) is
    /// remembered for the launch: asking again every second would turn one
    /// prompt into a storm.
    private var failure: OSStatus?

    init(bundleID: String = Bundle.main.bundleIdentifier ?? "com.vorssaint.utils") {
        service = bundleID + ".authenticator"
    }

    private func identity(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword,
         kSecAttrService: service,
         kSecAttrAccount: account]
    }

    private func readItem(_ account: String) -> (status: OSStatus, data: Data?) {
        var query = identity(account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }

    private func writeItem(_ account: String, _ data: Data) -> OSStatus {
        var attributes = identity(account)
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecValueData] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecDuplicateItem else { return status }
        return SecItemUpdate(identity(account) as CFDictionary, [kSecValueData: data] as CFDictionary)
    }

    private func deleteItem(_ account: String) -> OSStatus {
        let status = SecItemDelete(identity(account) as CFDictionary)
        return status == errSecItemNotFound ? errSecSuccess : status
    }

    /// The whole blob, read once per launch.
    private func loadBlob() -> (status: OSStatus, blob: [String: Data]) {
        if let cache { return (errSecSuccess, cache) }
        if let failure { return (failure, [:]) }
        let result = readItem(Self.blobAccount)
        switch result.status {
        case errSecSuccess:
            guard let data = result.data,
                  let decoded = try? JSONDecoder().decode([String: Data].self, from: data)
            else {
                failure = errSecDecode
                return (errSecDecode, [:])
            }
            cache = decoded
            return (errSecSuccess, decoded)
        case errSecItemNotFound:
            cache = [:]
            return (errSecSuccess, [:])
        default:
            failure = result.status
            return (result.status, [:])
        }
    }

    /// Folds every account still stored one item each into the blob, in a
    /// single pass, so the Keychain asks about each old item once and never
    /// again. An item the person refuses stays where it is for next time.
    func prepare(ids: [UUID]) {
        let loaded = loadBlob()
        guard loaded.status == errSecSuccess else { return }
        var blob = loaded.blob
        var migrated: [String] = []
        for id in ids where blob[id.uuidString] == nil {
            let legacy = readItem(id.uuidString)
            guard legacy.status == errSecSuccess, let secret = legacy.data else { continue }
            blob[id.uuidString] = secret
            migrated.append(id.uuidString)
        }
        guard !migrated.isEmpty, saveBlob(blob) == errSecSuccess else { return }
        for account in migrated {
            _ = deleteItem(account)
        }
    }

    private func saveBlob(_ blob: [String: Data]) -> OSStatus {
        guard let data = try? JSONEncoder().encode(blob) else { return errSecParam }
        let status = writeItem(Self.blobAccount, data)
        if status == errSecSuccess { cache = blob }
        return status
    }

    func read(id: UUID) -> (status: OSStatus, secret: Data?) {
        let loaded = loadBlob()
        guard loaded.status == errSecSuccess else { return (loaded.status, nil) }
        guard let secret = loaded.blob[id.uuidString] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, secret)
    }

    func write(id: UUID, secret: Data) -> OSStatus {
        let loaded = loadBlob()
        guard loaded.status == errSecSuccess else { return loaded.status }
        var blob = loaded.blob
        blob[id.uuidString] = secret
        return saveBlob(blob)
    }

    func delete(id: UUID) -> OSStatus {
        let loaded = loadBlob()
        guard loaded.status == errSecSuccess else { return loaded.status }
        var blob = loaded.blob
        blob[id.uuidString] = nil
        let status = saveBlob(blob)
        _ = deleteItem(id.uuidString)
        return status
    }
}

final class MemorySecretStore: AuthenticatorSecretStore {
    var secrets: [UUID: Data] = [:]
    var failNextWrite = false

    func read(id: UUID) -> (status: OSStatus, secret: Data?) {
        guard let secret = secrets[id] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, secret)
    }

    func write(id: UUID, secret: Data) -> OSStatus {
        if failNextWrite {
            failNextWrite = false
            return errSecIO
        }
        secrets[id] = secret
        return errSecSuccess
    }

    func delete(id: UUID) -> OSStatus {
        secrets[id] = nil
        return errSecSuccess
    }
}

enum AuthenticatorStoreError: Error, Equatable {
    case keychain(OSStatus)
    case cannotSave
    case unreadable
}

/// Account metadata in `Authenticator.json`, secrets in the secret store.
/// A failed read never authorises a later write, so a file the app cannot
/// parse is left for the person to move aside rather than overwritten.
struct AuthenticatorStore {
    struct Document: Codable, Equatable {
        var version = 1
        var accounts: [OTPAccount] = []
    }

    static let fileName = "Authenticator.json"

    let directoryURL: URL?
    let secrets: AuthenticatorSecretStore
    private(set) var accounts: [OTPAccount] = []
    private(set) var canSave = false

    init(directoryURL: URL?, secrets: AuthenticatorSecretStore) {
        self.directoryURL = directoryURL
        self.secrets = secrets
    }

    private var fileURL: URL? {
        directoryURL?.appendingPathComponent(Self.fileName)
    }

    // MARK: - Loading and saving

    mutating func load() throws {
        canSave = false
        accounts = []
        guard let fileURL else { throw AuthenticatorStoreError.unreadable }
        do {
            let data = try Data(contentsOf: fileURL)
            accounts = try JSONDecoder().decode(Document.self, from: data).accounts
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // First run: nothing to read is not a failure.
        } catch {
            throw AuthenticatorStoreError.unreadable
        }
        canSave = true
        secrets.prepare(ids: accounts.map(\.id))
    }

    private func save() throws {
        guard canSave, let directoryURL, let fileURL else { throw AuthenticatorStoreError.cannotSave }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Document(accounts: accounts))
        guard PrivateFileStore.createDirectory(at: directoryURL),
              PrivateFileStore.write(data, to: fileURL),
              (try? Data(contentsOf: fileURL)) == data
        else { throw AuthenticatorStoreError.cannotSave }
    }

    // MARK: - Accounts

    /// The secret goes in first: a metadata row without a secret would show
    /// a broken account, a secret without a row is invisible and harmless.
    mutating func add(_ entry: OTPEntry) throws {
        guard canSave else { throw AuthenticatorStoreError.cannotSave }
        let status = secrets.write(id: entry.account.id, secret: entry.secret)
        guard status == errSecSuccess else { throw AuthenticatorStoreError.keychain(status) }
        var account = entry.account
        if account.kind == .steam { account.digits = OTPAccount.steamDigits }
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
        do {
            try save()
        } catch {
            accounts.removeAll { $0.id == account.id }
            _ = secrets.delete(id: account.id)
            throw error
        }
    }

    /// Metadata only; the secret stays as it was.
    mutating func update(_ account: OTPAccount) throws {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let previous = accounts[index]
        accounts[index] = account
        do {
            try save()
        } catch {
            accounts[index] = previous
            throw error
        }
    }

    mutating func reorder(_ ids: [UUID]) throws {
        let byID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        var ordered = ids.compactMap { byID[$0] }
        let seen = Set(ids)
        ordered.append(contentsOf: accounts.filter { !seen.contains($0.id) })
        let previous = accounts
        accounts = ordered
        do {
            try save()
        } catch {
            accounts = previous
            throw error
        }
    }

    mutating func remove(id: UUID) throws {
        let previous = accounts
        accounts.removeAll { $0.id == id }
        do {
            try save()
        } catch {
            accounts = previous
            throw error
        }
        _ = secrets.delete(id: id)
    }

    func secret(for id: UUID) throws -> Data {
        let result = secrets.read(id: id)
        guard result.status == errSecSuccess, let secret = result.secret else {
            throw AuthenticatorStoreError.keychain(result.status)
        }
        return secret
    }

    /// Advances an HOTP counter after a code was used.
    mutating func advanceCounter(id: UUID) throws {
        guard var account = accounts.first(where: { $0.id == id }), account.kind == .hotp else { return }
        account.counter &+= 1
        try update(account)
    }

    // MARK: - Import and export

    /// Whether the same account is already here: same issuer and label,
    /// case aside, holding the same secret.
    func isDuplicate(_ entry: OTPEntry) -> Bool {
        accounts.contains { existing in
            existing.issuer.caseInsensitiveCompare(entry.account.issuer) == .orderedSame
                && existing.label.caseInsensitiveCompare(entry.account.label) == .orderedSame
                && (try? secret(for: existing.id)) == entry.secret
        }
    }

    func entries(for ids: [UUID]? = nil) -> [OTPEntry] {
        accounts.compactMap { account in
            if let ids, !ids.contains(account.id) { return nil }
            guard let secret = try? secret(for: account.id) else { return nil }
            return OTPEntry(account: account, secret: secret)
        }
    }
}
