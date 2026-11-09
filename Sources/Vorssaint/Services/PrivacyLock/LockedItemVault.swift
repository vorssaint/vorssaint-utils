// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Derived from Glance's FileVault (MIT, Copyright (c) Jonathan Zhou). See THIRD-PARTY-NOTICES.md.

import CommonCrypto
import CryptoKit
import Foundation
import Security

enum LockedItemError: LocalizedError {
    case notALockedItem
    case alreadyLocked
    case corrupt
    case wrongPassword
    case unsupported
    case archiveFailed

    var errorDescription: String? {
        switch self {
        case .notALockedItem: return "This is not an item locked by Vorssaint."
        case .alreadyLocked: return "This item is already locked."
        case .corrupt: return "The locked item is damaged or incomplete."
        case .wrongPassword: return "That password does not open this item."
        case .unsupported: return "Only files and folders can be locked."
        case .archiveFailed: return "The folder could not be packed or unpacked."
        }
    }
}

/// Locks a file or a folder behind a password of its own. The result is
/// `<name>.vslock`, encrypted with AES-256-GCM under a key derived from that
/// password (PBKDF2-HMAC-SHA256, 600,000 rounds, a fresh salt each time).
///
/// A folder is packed into one archive first, so a locked folder is one file
/// that shows nothing about what was inside it.
///
/// Container format (integers big-endian):
///
///     magic       8 bytes   "VSSLOCK1"
///     itemID      16 bytes  random; names this item in the remembered passwords
///     salt        16 bytes  random; PBKDF2 salt
///     iterations  4 bytes
///     chunk       4 bytes   plaintext chunk size used when writing (1 MiB)
///     frames      repeated  [length: 4][AES-GCM combined: nonce 12 + ciphertext + tag 16]
///
/// Frame 0 is JSON metadata (original name, kind, permissions, dates, size), so
/// the name is not visible on disk; later frames are the content. Every frame
/// authenticates the whole header, its own index and a "last frame" flag, so
/// reordering, truncation and tampering are all detected.
///
/// Blocking: run it off the main thread.
enum LockedItemVault {
    enum Kind: String, Codable { case file, folder }

    struct Metadata: Codable {
        var name: String
        var kind: Kind
        var permissions: Int?
        var modified: Double?
        var size: UInt64
    }

    struct Header {
        let itemID: Data
        let salt: Data
        let iterations: UInt32
        let chunkSize: UInt32
        /// Exactly the bytes on disk; authenticated into every frame.
        let raw: Data

        var itemIDHex: String { itemID.map { String(format: "%02x", $0) }.joined() }
    }

    private static let magic = Data("VSSLOCK1".utf8)
    private static let chunkSize = 1 << 20
    private static let maxChunkSize: UInt32 = 16 << 20
    private static let gcmOverhead = 28
    private static let pbkdf2Iterations: UInt32 = 600_000
    private static let maxIterations: UInt32 = 10_000_000

    // MARK: - Locking

    /// Step 1 of locking: writes `<name>.vslock` next to `source` and proves it
    /// opens with the password. The original is untouched; the caller removes
    /// it only once everything else about the lock has succeeded.
    static func createContainer(from source: URL, password: String, itemID: Data) throws -> URL {
        guard source.pathExtension != PrivacyLockSupport.fileExtension else { throw LockedItemError.alreadyLocked }
        let fm = FileManager.default
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey])
        let kind: Kind
        if values.isRegularFile == true { kind = .file }
        else if values.isDirectory == true { kind = .folder }
        else { throw LockedItemError.unsupported }

        let directory = source.deletingLastPathComponent()
        let workDirectory = directory.appendingPathComponent(".vss-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDirectory, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: workDirectory) }

        var plaintext = source
        if kind == .folder {
            plaintext = workDirectory.appendingPathComponent("folder.zip")
            try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, plaintext.path])
        }
        let temporary = workDirectory.appendingPathComponent("container")
        try encrypt(plaintext: plaintext, original: source, kind: kind, to: temporary, password: password, itemID: itemID)
        // Prove it opens before anything depends on it.
        let header = try readHeader(of: temporary)
        let key = try deriveKey(password: password, header: header)
        try read(container: temporary, header: header, key: key, onMetadata: { _ in }, onChunk: { _ in })

        let name = PrivacyLockSupport.uniqueName(PrivacyLockSupport.containerName(for: source.lastPathComponent)) {
            fm.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
        let destination = directory.appendingPathComponent(name)
        try fm.moveItem(at: temporary, to: destination)
        return destination
    }

    /// Removes the original once the container is safe. A folder goes whole.
    static func removeOriginal(_ source: URL) throws { try FileManager.default.removeItem(at: source) }

    static func discard(container: URL) { try? FileManager.default.removeItem(at: container) }

    // MARK: - Unlocking

    /// Restores the original (name, permissions, modification date) next to the
    /// container and removes the container. Returns where it landed.
    static func unlock(container: URL, password: String) throws -> (url: URL, name: String) {
        guard container.pathExtension == PrivacyLockSupport.fileExtension else { throw LockedItemError.notALockedItem }
        let fm = FileManager.default
        let directory = container.deletingLastPathComponent()
        let workDirectory = directory.appendingPathComponent(".vss-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDirectory, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: workDirectory) }

        let header = try readHeader(of: container)
        let key = try deriveKey(password: password, header: header)
        let temporary = workDirectory.appendingPathComponent("payload")

        var metadata: Metadata?
        var output: FileHandle?
        do {
            try read(container: container, header: header, key: key, onMetadata: { meta in
                metadata = meta
                _ = fm.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600])
                output = try FileHandle(forWritingTo: temporary)
            }, onChunk: { data in try output?.write(contentsOf: data) })
            try output?.close()
            output = nil
        } catch {
            try? output?.close()
            throw error
        }
        guard let metadata, let safeName = PrivacyLockSupport.safeComponent(metadata.name) else {
            throw LockedItemError.corrupt
        }
        let destinationName = PrivacyLockSupport.uniqueName(safeName) {
            fm.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
        let destination = directory.appendingPathComponent(destinationName)

        switch metadata.kind {
        case .file:
            var attributes: [FileAttributeKey: Any] = [:]
            if let permissions = metadata.permissions { attributes[.posixPermissions] = permissions }
            if let modified = metadata.modified { attributes[.modificationDate] = Date(timeIntervalSince1970: modified) }
            if !attributes.isEmpty { try fm.setAttributes(attributes, ofItemAtPath: temporary.path) }
            try fm.moveItem(at: temporary, to: destination)
        case .folder:
            let extracted = workDirectory.appendingPathComponent("extracted", isDirectory: true)
            try fm.createDirectory(at: extracted, withIntermediateDirectories: false)
            try run("/usr/bin/ditto", ["-x", "-k", temporary.path, extracted.path])
            let children = try fm.contentsOfDirectory(atPath: extracted.path)
            guard children.count == 1, let only = children.first else { throw LockedItemError.archiveFailed }
            try fm.moveItem(at: extracted.appendingPathComponent(only), to: destination)
        }
        try fm.removeItem(at: container)
        return (destination, destinationName)
    }

    // MARK: - Container writing

    private static func encrypt(plaintext: URL, original: URL, kind: Kind, to destination: URL,
                                password: String, itemID: Data) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: original.path)
        let payloadSize = (try FileManager.default.attributesOfItem(atPath: plaintext.path)[.size] as? NSNumber)?.uint64Value ?? 0
        let metadata = Metadata(name: original.lastPathComponent, kind: kind,
                                permissions: (attributes[.posixPermissions] as? NSNumber)?.intValue,
                                modified: (attributes[.modificationDate] as? Date)?.timeIntervalSince1970,
                                size: payloadSize)
        precondition(itemID.count == 16)
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw PrivacyLockKeychainError.status(status) }

        var iterations = pbkdf2Iterations.bigEndian
        var declaredChunk = UInt32(chunkSize).bigEndian
        let rawHeader = magic + itemID + salt + Data(bytes: &iterations, count: 4) + Data(bytes: &declaredChunk, count: 4)
        let header = Header(itemID: itemID, salt: salt, iterations: pbkdf2Iterations,
                            chunkSize: UInt32(chunkSize), raw: rawHeader)
        let key = try deriveKey(password: password, header: header)

        guard FileManager.default.createFile(atPath: destination.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let input = try FileHandle(forReadingFrom: plaintext)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        try output.write(contentsOf: rawHeader)
        try writeFrame(try JSONEncoder().encode(metadata), index: 0, isFinal: false, header: rawHeader, key: key, to: output)
        // One chunk of lookahead tells which frame is the last.
        var index: UInt64 = 1
        var current = try input.read(upToCount: chunkSize) ?? Data()
        while true {
            let next = try input.read(upToCount: chunkSize) ?? Data()
            let isFinal = next.isEmpty
            try writeFrame(current, index: index, isFinal: isFinal, header: rawHeader, key: key, to: output)
            if isFinal { break }
            current = next
            index += 1
        }
    }

    private static func writeFrame(_ plaintext: Data, index: UInt64, isFinal: Bool, header: Data,
                                   key: SymmetricKey, to output: FileHandle) throws {
        let sealed = try AES.GCM.seal(plaintext, using: key,
                                      authenticating: aad(header: header, index: index, isFinal: isFinal))
        guard let combined = sealed.combined else { throw LockedItemError.corrupt }
        var length = UInt32(combined.count).bigEndian
        try output.write(contentsOf: Data(bytes: &length, count: 4))
        try output.write(contentsOf: combined)
    }

    // MARK: - Container reading

    /// Just the header: enough to find a remembered password before decrypting.
    static func readHeader(of container: URL) throws -> Header {
        let input = try FileHandle(forReadingFrom: container)
        defer { try? input.close() }
        guard let magicData = try input.read(upToCount: 8), magicData == magic else {
            throw LockedItemError.notALockedItem
        }
        guard let itemID = try input.read(upToCount: 16), itemID.count == 16,
              let salt = try input.read(upToCount: 16), salt.count == 16,
              let iterationData = try input.read(upToCount: 4), iterationData.count == 4,
              let sizeData = try input.read(upToCount: 4), sizeData.count == 4 else {
            throw LockedItemError.corrupt
        }
        let iterations = iterationData.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
        let declaredChunk = sizeData.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
        // Bounds stop a hostile file from asking for absurd work or memory.
        guard iterations > 0, iterations <= maxIterations, declaredChunk > 0, declaredChunk <= maxChunkSize else {
            throw LockedItemError.corrupt
        }
        return Header(itemID: itemID, salt: salt, iterations: iterations, chunkSize: declaredChunk,
                      raw: magicData + itemID + salt + iterationData + sizeData)
    }

    private static func read(container: URL, header: Header, key: SymmetricKey,
                             onMetadata: (Metadata) throws -> Void, onChunk: (Data) throws -> Void) throws {
        let input = try FileHandle(forReadingFrom: container)
        defer { try? input.close() }
        try input.seek(toOffset: UInt64(header.raw.count))

        func readFrame() throws -> Data? {
            guard let lengthData = try input.read(upToCount: 4), !lengthData.isEmpty else { return nil }
            guard lengthData.count == 4 else { throw LockedItemError.corrupt }
            let length = lengthData.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
            guard Int(length) >= gcmOverhead, length <= header.chunkSize + UInt32(gcmOverhead) else {
                throw LockedItemError.corrupt
            }
            guard let body = try input.read(upToCount: Int(length)), body.count == Int(length) else {
                throw LockedItemError.corrupt
            }
            return body
        }

        guard var current = try readFrame() else { throw LockedItemError.corrupt }
        var index: UInt64 = 0
        while true {
            let next = try readFrame()
            let isFinal = next == nil
            let plaintext: Data
            do {
                let box = try AES.GCM.SealedBox(combined: current)
                plaintext = try AES.GCM.open(box, using: key, authenticating: aad(header: header.raw, index: index, isFinal: isFinal))
            } catch {
                // A wrong password and tampering look alike; frame 0 tells them apart usefully.
                throw index == 0 ? LockedItemError.wrongPassword : LockedItemError.corrupt
            }
            if index == 0 {
                guard let metadata = try? JSONDecoder().decode(Metadata.self, from: plaintext) else {
                    throw LockedItemError.corrupt
                }
                try onMetadata(metadata)
            } else {
                try onChunk(plaintext)
            }
            guard let next else { break }
            current = next
            index += 1
        }
    }

    // MARK: - Helpers

    private static func deriveKey(password: String, header: Header) throws -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: 32)
        let status = header.salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count,
                                 saltBytes.bindMemory(to: UInt8.self).baseAddress, header.salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), header.iterations,
                                 &derived, derived.count)
        }
        guard status == Int32(kCCSuccess) else { throw LockedItemError.corrupt }
        return SymmetricKey(data: derived)
    }

    private static func aad(header: Data, index: UInt64, isFinal: Bool) -> Data {
        var data = header
        var bigEndianIndex = index.bigEndian
        data.append(Data(bytes: &bigEndianIndex, count: 8))
        data.append(isFinal ? 1 : 0)
        return data
    }

    static func randomItemID() throws -> Data {
        var bytes = Data(count: 16)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw PrivacyLockKeychainError.status(status) }
        return bytes
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw LockedItemError.archiveFailed }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw LockedItemError.archiveFailed }
    }
}
