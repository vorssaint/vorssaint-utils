// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CommonCrypto
import CryptoKit
import Foundation

/// The other files an authenticator can hand over: Aegis and 2FAS plain
/// exports, and this app's own password-protected backup. Everything comes
/// back as `OTPEntry`, the same shape `otpauth://` lines produce.
enum AuthenticatorInterchange {
    enum Format: Equatable {
        case otpauthText
        case aegis
        case twoFAS
        case backup
        case aegisEncrypted
        case twoFASEncrypted
    }

    enum ImportError: Error, Equatable {
        case unrecognised
        case encrypted(Format)
        case wrongPassword
        case malformed
    }

    /// Looks at a file's bytes and says which reader applies. Text with
    /// otpauth lines is the fallback so a renamed export still imports.
    static func detect(_ data: Data) -> Format? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if object["format"] as? String == Backup.formatName { return .backup }
            if let db = object["db"] {
                if db is String { return .aegisEncrypted }
                if let db = db as? [String: Any], db["entries"] is [Any] { return .aegis }
            }
            if object["services"] is [Any] { return .twoFAS }
            if object["servicesEncrypted"] != nil { return .twoFASEncrypted }
            return nil
        }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return text.lowercased().contains("otpauth") ? .otpauthText : nil
    }

    // MARK: - Aegis

    /// Aegis "Export (unencrypted)" JSON: `db.entries[]` with `type`,
    /// `name`, `issuer` and `info.{secret,algo,digits,period,counter}`.
    static func aegisEntries(_ data: Data) throws -> (entries: [OTPEntry], failures: Int) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let db = object["db"] as? [String: Any],
              let rows = db["entries"] as? [[String: Any]]
        else { throw ImportError.malformed }
        var entries: [OTPEntry] = []
        var failures = 0
        for row in rows {
            guard let info = row["info"] as? [String: Any],
                  let secretText = info["secret"] as? String,
                  let secret = OneTimePassword.base32Decode(secretText)
            else {
                failures += 1
                continue
            }
            var account = OTPAccount()
            account.label = row["name"] as? String ?? ""
            account.issuer = row["issuer"] as? String ?? ""
            switch (row["type"] as? String ?? "totp").lowercased() {
            case "totp": account.kind = .totp
            case "hotp": account.kind = .hotp
            case "steam": account.kind = .steam
            default:
                failures += 1
                continue
            }
            guard let algorithm = algorithm(named: info["algo"] as? String) else {
                failures += 1
                continue
            }
            account.algorithm = algorithm
            account.digits = info["digits"] as? Int ?? 6
            account.period = info["period"] as? Int ?? 30
            if let counter = info["counter"] as? Int { account.counter = UInt64(max(counter, 0)) }
            if account.kind == .steam { account.digits = OTPAccount.steamDigits }
            entries.append(OTPEntry(account: account, secret: secret))
        }
        return (entries, failures)
    }

    // MARK: - 2FAS

    /// 2FAS backup JSON: `services[]` with `name`, `secret` and
    /// `otp.{label,account,issuer,digits,period,algorithm,tokenType,counter}`.
    static func twoFASEntries(_ data: Data) throws -> (entries: [OTPEntry], failures: Int) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["services"] as? [[String: Any]]
        else { throw ImportError.malformed }
        var entries: [OTPEntry] = []
        var failures = 0
        for row in rows {
            guard let secretText = row["secret"] as? String,
                  let secret = OneTimePassword.base32Decode(secretText)
            else {
                failures += 1
                continue
            }
            let otp = row["otp"] as? [String: Any] ?? [:]
            var account = OTPAccount()
            account.issuer = otp["issuer"] as? String ?? row["name"] as? String ?? ""
            account.label = otp["account"] as? String ?? otp["label"] as? String ?? ""
            if account.label.isEmpty, account.issuer != row["name"] as? String ?? "" {
                account.label = row["name"] as? String ?? ""
            }
            switch (otp["tokenType"] as? String ?? "TOTP").uppercased() {
            case "TOTP": account.kind = .totp
            case "HOTP": account.kind = .hotp
            case "STEAM": account.kind = .steam
            default:
                failures += 1
                continue
            }
            guard let algorithm = algorithm(named: otp["algorithm"] as? String) else {
                failures += 1
                continue
            }
            account.algorithm = algorithm
            account.digits = otp["digits"] as? Int ?? 6
            account.period = otp["period"] as? Int ?? 30
            if let counter = otp["counter"] as? Int { account.counter = UInt64(max(counter, 0)) }
            if account.kind == .steam { account.digits = OTPAccount.steamDigits }
            entries.append(OTPEntry(account: account, secret: secret))
        }
        return (entries, failures)
    }

    private static func algorithm(named name: String?) -> OTPAccount.Algorithm? {
        switch (name ?? "SHA1").uppercased().replacingOccurrences(of: "-", with: "") {
        case "SHA1": return .sha1
        case "SHA256": return .sha256
        case "SHA512": return .sha512
        default: return nil
        }
    }

    // MARK: - Password-protected backup

    /// A small JSON envelope: the otpauth lines, AES-GCM sealed under a key
    /// derived from the password with PBKDF2-HMAC-SHA256. Salt and nonce
    /// are fresh per file; the round count travels with it so it can rise
    /// later without breaking old backups.
    enum Backup {
        static let formatName = "vorssaint-authenticator-backup"
        static let version = 1
        static let defaultRounds: UInt32 = 600_000
        static let fileExtension = "vorssaint-otp"

        struct Envelope: Codable {
            var format = formatName
            var version = Backup.version
            var kdf = "pbkdf2-hmac-sha256"
            var rounds: UInt32
            var salt: Data
            var nonce: Data
            var ciphertext: Data
            var tag: Data
        }

        static func encrypt(_ entries: [OTPEntry], password: String,
                            rounds: UInt32 = defaultRounds) throws -> Data {
            var salt = Data(count: 16)
            let saltStatus = salt.withUnsafeMutableBytes {
                SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!)
            }
            guard saltStatus == errSecSuccess else { throw ImportError.malformed }
            let key = try derive(password: password, salt: salt, rounds: rounds)
            let plaintext = Data(entries.map(OneTimePassword.uri(for:)).joined(separator: "\n").utf8)
            let sealed = try AES.GCM.seal(plaintext, using: key)
            let envelope = Envelope(rounds: rounds,
                                    salt: salt,
                                    nonce: Data(sealed.nonce),
                                    ciphertext: sealed.ciphertext,
                                    tag: sealed.tag)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(envelope)
        }

        static func decrypt(_ data: Data, password: String) throws -> [OTPEntry] {
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
                  envelope.format == formatName
            else { throw ImportError.malformed }
            let key = try derive(password: password, salt: envelope.salt, rounds: envelope.rounds)
            guard let nonce = try? AES.GCM.Nonce(data: envelope.nonce),
                  let box = try? AES.GCM.SealedBox(nonce: nonce,
                                                   ciphertext: envelope.ciphertext,
                                                   tag: envelope.tag)
            else { throw ImportError.malformed }
            guard let plaintext = try? AES.GCM.open(box, using: key) else {
                throw ImportError.wrongPassword
            }
            let text = String(decoding: plaintext, as: UTF8.self)
            return OneTimePassword.entries(inText: text).entries
        }

        /// Not private: the tests pin it to the published PBKDF2 vectors, so
        /// a wrong round count or a swapped argument goes red instead of
        /// round-tripping happily with itself.
        static func derive(password: String, salt: Data, rounds: UInt32) throws -> SymmetricKey {
            var derived = [UInt8](repeating: 0, count: 32)
            let passwordBytes = Array(password.utf8)
            let status = salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     passwordBytes.map { CChar(bitPattern: $0) }, passwordBytes.count,
                                     saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                                     &derived, derived.count)
            }
            guard status == kCCSuccess else { throw ImportError.malformed }
            return SymmetricKey(data: derived)
        }
    }
}
