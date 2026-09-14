// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation

/// One authenticator account, everything but the secret. The secret lives
/// in the Keychain under `id` and is handed in when a code is computed, so
/// the metadata file never carries it.
struct OTPAccount: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case totp, hotp, steam
    }

    enum Algorithm: String, Codable, CaseIterable {
        case sha1, sha256, sha512
    }

    var id = UUID()
    var issuer = ""
    var label = ""
    var kind = Kind.totp
    var algorithm = Algorithm.sha1
    var digits = 6
    var period = 30
    var counter: UInt64 = 0
    var pinned = false

    /// What the list shows first: the issuer, or the label when there is none.
    var displayName: String {
        issuer.isEmpty ? label : issuer
    }

    /// The second line; empty when the issuer already said everything.
    var secondaryName: String {
        issuer.isEmpty ? "" : label
    }

    static let digitChoices = [6, 7, 8]
    static let steamDigits = 5
}

/// An account together with its secret, the shape imports and exports work
/// in. Never persisted as one piece.
struct OTPEntry: Equatable {
    var account: OTPAccount
    var secret: Data
}

enum OneTimePassword {
    static let steamAlphabet = Array("23456789BCDFGHJKMNPQRTVWXY")

    // MARK: - Codes

    static func code(for account: OTPAccount, secret: Data, at date: Date = Date()) -> String {
        switch account.kind {
        case .totp:
            return hotp(secret: secret, counter: totpCounter(for: account, at: date),
                        algorithm: account.algorithm, digits: account.digits)
        case .hotp:
            return hotp(secret: secret, counter: account.counter,
                        algorithm: account.algorithm, digits: account.digits)
        case .steam:
            return steam(secret: secret, counter: totpCounter(for: account, at: date))
        }
    }

    /// The code after the current one, for the palette's "next" action.
    static func nextCode(for account: OTPAccount, secret: Data, at date: Date = Date()) -> String {
        var later = account
        switch account.kind {
        case .hotp:
            later.counter &+= 1
            return code(for: later, secret: secret, at: date)
        case .totp, .steam:
            return code(for: account, secret: secret,
                        at: date.addingTimeInterval(TimeInterval(max(account.period, 1))))
        }
    }

    static func totpCounter(for account: OTPAccount, at date: Date) -> UInt64 {
        let period = max(account.period, 1)
        let seconds = max(date.timeIntervalSince1970, 0)
        return UInt64(seconds) / UInt64(period)
    }

    /// Seconds until the current TOTP code rolls over.
    static func secondsRemaining(for account: OTPAccount, at date: Date = Date()) -> Int {
        let period = max(account.period, 1)
        let elapsed = Int(max(date.timeIntervalSince1970, 0)) % period
        return period - elapsed
    }

    static func hotp(secret: Data, counter: UInt64, algorithm: OTPAccount.Algorithm, digits: Int) -> String {
        let truncated = dynamicTruncation(hmac(secret: secret, counter: counter, algorithm: algorithm))
        let digits = min(max(digits, 1), 9)
        let modulus = UInt32(pow(10, Double(digits)))
        let value = truncated % modulus
        let text = String(value)
        return String(repeating: "0", count: max(digits - text.count, 0)) + text
    }

    static func steam(secret: Data, counter: UInt64) -> String {
        var value = dynamicTruncation(hmac(secret: secret, counter: counter, algorithm: .sha1))
        var characters: [Character] = []
        for _ in 0..<OTPAccount.steamDigits {
            characters.append(steamAlphabet[Int(value % UInt32(steamAlphabet.count))])
            value /= UInt32(steamAlphabet.count)
        }
        return String(characters)
    }

    private static func hmac(secret: Data, counter: UInt64, algorithm: OTPAccount.Algorithm) -> [UInt8] {
        var message = Data(count: 8)
        var big = counter.bigEndian
        withUnsafeBytes(of: &big) { message.replaceSubrange(0..<8, with: $0) }
        let key = SymmetricKey(data: secret)
        switch algorithm {
        case .sha1: return Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: return Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: return Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }
    }

    /// RFC 4226 section 5.4.
    private static func dynamicTruncation(_ mac: [UInt8]) -> UInt32 {
        let offset = Int(mac[mac.count - 1] & 0x0f)
        return (UInt32(mac[offset] & 0x7f) << 24)
            | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8)
            | UInt32(mac[offset + 3])
    }

    /// Groups of three for six and nine digit codes, of four for eight, and
    /// a half split for the rest, the way phones show them.
    static func grouped(_ code: String) -> String {
        let size: Int
        switch code.count {
        case 6, 9: size = 3
        case 8: size = 4
        case 7: return String(code.prefix(3)) + " " + String(code.dropFirst(3))
        default: return code
        }
        var out = ""
        for (index, character) in code.enumerated() {
            if index > 0, index % size == 0 { out.append(" ") }
            out.append(character)
        }
        return out
    }

    // MARK: - Base32

    private static let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// Case insensitive, padding optional, spaces and dashes ignored. Nil for
    /// anything else, or for an empty secret.
    static func base32Decode(_ text: String) -> Data? {
        var bits: UInt32 = 0
        var bitCount = 0
        var out = Data()
        for scalar in text.uppercased().unicodeScalars {
            switch scalar {
            case " ", "-", "=", "\n", "\t": continue
            default: break
            }
            guard let value = base32Value(scalar) else { return nil }
            bits = (bits << 5) | UInt32(value)
            bitCount += 5
            if bitCount >= 8 {
                out.append(UInt8((bits >> UInt32(bitCount - 8)) & 0xff))
                bitCount -= 8
            }
        }
        return out.isEmpty ? nil : out
    }

    private static func base32Value(_ scalar: Unicode.Scalar) -> UInt8? {
        switch scalar.value {
        case 65...90: return UInt8(scalar.value - 65)
        case 50...55: return UInt8(scalar.value - 50 + 26)
        default: return nil
        }
    }

    static func base32Encode(_ data: Data) -> String {
        var out = ""
        var bits: UInt32 = 0
        var bitCount = 0
        for byte in data {
            bits = (bits << 8) | UInt32(byte)
            bitCount += 8
            while bitCount >= 5 {
                out.append(base32Alphabet[Int((bits >> UInt32(bitCount - 5)) & 0x1f)])
                bitCount -= 5
            }
        }
        if bitCount > 0 {
            out.append(base32Alphabet[Int((bits << UInt32(5 - bitCount)) & 0x1f)])
        }
        return out
    }

    /// What a typed secret looks like once spaces, dashes and case are
    /// normalised; the form stores this so the Keychain gets bytes and the
    /// person sees what they typed. Steam keys keep their case: they come
    /// out of a maFile as base64, which is case sensitive.
    static func sanitizedSecret(_ text: String, kind: OTPAccount.Kind = .totp) -> String {
        let stripped = text.filter { !" -\n\t".contains($0) }
        return kind == .steam ? stripped : stripped.uppercased().filter { $0 != "=" }
    }

    /// The bytes behind a typed key. Base32 for everything; Steam also takes
    /// the base64 `shared_secret` SteamGuard exports, since that is what
    /// people have.
    static func secretData(_ text: String, kind: OTPAccount.Kind) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if kind == .steam, trimmed.contains(where: { "abcdefghijklmnopqrstuvwxyz+/=".contains($0) }),
           let data = Data(base64Encoded: trimmed), !data.isEmpty {
            return data
        }
        return base32Decode(trimmed)
    }

    // MARK: - otpauth URIs

    enum URIError: Error, Equatable {
        case notOTPAuth
        case unsupportedType
        case missingSecret
        case invalidSecret
        case invalidParameter(String)
    }

    /// `otpauth://TYPE/LABEL?secret=…`. The query issuer wins over the label
    /// prefix; Steam is recognised by `encoder=steam` (2FAS, Aegis) or an
    /// issuer of "Steam".
    static func parse(uri: String) throws -> OTPEntry {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "otpauth"
        else { throw URIError.notOTPAuth }
        let type = (components.host ?? "").lowercased()
        var account = OTPAccount()
        switch type {
        case "totp": account.kind = .totp
        case "hotp": account.kind = .hotp
        // Aegis puts the kind in the host for Steam; others keep "totp"
        // and say so in the query, which the encoder check below catches.
        case "steam": account.kind = .steam
        default: throw URIError.unsupportedType
        }

        // Some generators leave the colon raw; URLComponents decodes the rest.
        let rawLabel = components.path.hasPrefix("/") ? String(components.path.dropFirst()) : components.path
        let labelText = rawLabel.removingPercentEncoding ?? rawLabel
        if let colon = labelText.firstIndex(of: ":") {
            account.issuer = String(labelText[..<colon]).trimmingCharacters(in: .whitespaces)
            account.label = String(labelText[labelText.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
        } else {
            account.label = labelText.trimmingCharacters(in: .whitespaces)
        }

        var secret: Data?
        var encoder = ""
        for item in components.queryItems ?? [] {
            let value = item.value ?? ""
            switch item.name.lowercased() {
            case "secret":
                guard let data = base32Decode(value) else { throw URIError.invalidSecret }
                secret = data
            case "issuer":
                if !value.isEmpty { account.issuer = value.trimmingCharacters(in: .whitespaces) }
            case "algorithm":
                switch value.uppercased().replacingOccurrences(of: "-", with: "") {
                case "SHA1": account.algorithm = .sha1
                case "SHA256": account.algorithm = .sha256
                case "SHA512": account.algorithm = .sha512
                default: throw URIError.invalidParameter("algorithm")
                }
            case "digits":
                guard let digits = Int(value), (5...9).contains(digits) else {
                    throw URIError.invalidParameter("digits")
                }
                account.digits = digits
            case "period":
                guard let period = Int(value), period > 0 else { throw URIError.invalidParameter("period") }
                account.period = period
            case "counter":
                guard let counter = UInt64(value) else { throw URIError.invalidParameter("counter") }
                account.counter = counter
            case "encoder", "representation":
                encoder = value.lowercased()
            default:
                break
            }
        }
        guard let secret else { throw URIError.missingSecret }
        let isSteam = account.kind == .steam
            || encoder == "steam" || encoder == "steamguard"
            || (account.kind == .totp && account.issuer.caseInsensitiveCompare("Steam") == .orderedSame)
        if isSteam {
            account.kind = .steam
            account.digits = OTPAccount.steamDigits
            account.algorithm = .sha1
            account.period = 30
        }
        return OTPEntry(account: account, secret: secret)
    }

    /// The inverse of `parse`, with parameters at their defaults left out.
    static func uri(for entry: OTPEntry) -> String {
        let account = entry.account
        // Aegis reads the kind from the host and 2FAS reads `encoder`;
        // writing both means either of them takes the line back.
        let type: String
        switch account.kind {
        case .totp: type = "totp"
        case .hotp: type = "hotp"
        case .steam: type = "steam"
        }
        var label = account.label
        if !account.issuer.isEmpty {
            label = account.issuer + ":" + label
        }
        var components = URLComponents()
        components.scheme = "otpauth"
        components.host = type
        components.path = "/" + label
        var items = [URLQueryItem(name: "secret", value: base32Encode(entry.secret))]
        if !account.issuer.isEmpty {
            items.append(URLQueryItem(name: "issuer", value: account.issuer))
        }
        if account.kind == .steam {
            items.append(URLQueryItem(name: "encoder", value: "steam"))
        } else {
            if account.algorithm != .sha1 {
                items.append(URLQueryItem(name: "algorithm", value: account.algorithm.rawValue.uppercased()))
            }
            if account.digits != 6 {
                items.append(URLQueryItem(name: "digits", value: String(account.digits)))
            }
        }
        if account.kind == .hotp {
            items.append(URLQueryItem(name: "counter", value: String(account.counter)))
        } else if account.period != 30 {
            items.append(URLQueryItem(name: "period", value: String(account.period)))
        }
        components.queryItems = items
        // URLComponents leaves ":" in the path alone and encodes the rest.
        return components.string ?? ""
    }

    /// Every otpauth or migration line in a blob of text, in order. Lines
    /// that are neither are skipped, so a pasted export with comments still
    /// imports.
    static func entries(inText text: String) -> (entries: [OTPEntry], failures: Int) {
        var entries: [OTPEntry] = []
        var failures = 0
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("otpauth-migration://") {
                do {
                    entries.append(contentsOf: try GoogleMigration.decode(uri: line))
                } catch {
                    failures += 1
                }
            } else if line.lowercased().hasPrefix("otpauth://") {
                do {
                    entries.append(try parse(uri: line))
                } catch {
                    failures += 1
                }
            }
        }
        return (entries, failures)
    }
}
