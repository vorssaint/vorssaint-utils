// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum GoogleMigrationTests {
    static func run(expect: (Bool, String) -> Void) {
        // Hand-assembled from the wire format, independently of the writer:
        // one OtpParameters {secret "Hello!", name "Example:alice@google.com",
        // issuer "Example", SHA1, six digits, TOTP}, then version 1, batch 1/0.
        var parameters: [UInt8] = []
        parameters += [0x0a, 0x06] + Array("Hello!".utf8)
        parameters += [0x12, 0x18] + Array("Example:alice@google.com".utf8)
        parameters += [0x1a, 0x07] + Array("Example".utf8)
        parameters += [0x20, 0x01, 0x28, 0x01, 0x30, 0x02]
        var payload: [UInt8] = [0x0a, UInt8(parameters.count)] + parameters
        payload += [0x10, 0x01, 0x18, 0x01, 0x20, 0x00, 0x28, 0x2a]
        let base64 = Data(payload).base64EncodedString()
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!

        do {
            let entries = try GoogleMigration.decode(uri: "otpauth-migration://offline?data=" + base64)
            expect(entries.count == 1, "one parameter block decodes to one entry")
            if let entry = entries.first {
                expect(entry.secret == Data("Hello!".utf8), "the raw secret bytes come through")
                expect(entry.account.issuer == "Example" && entry.account.label == "alice@google.com",
                       "the issuer prefix is stripped from the name")
                expect(entry.account.kind == .totp && entry.account.digits == 6
                        && entry.account.algorithm == .sha1,
                       "SHA1, six digits and TOTP are read")
            }
        } catch {
            expect(false, "a hand-built payload decodes: \(error)")
        }

        // Raw base64 with "+" and "/" also arrives as a URL-safe variant.
        do {
            let urlSafe = Data(payload).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            let entries = try GoogleMigration.decode(uri: "otpauth-migration://offline?data=" + urlSafe)
            expect(entries.count == 1, "URL-safe base64 without padding decodes")
        } catch {
            expect(false, "URL-safe base64 decodes")
        }

        // Round trip through the writer, with every kind represented.
        var totp = OTPAccount()
        totp.issuer = "GitHub"
        totp.label = "octocat"
        totp.algorithm = .sha256
        totp.digits = 8
        var hotp = OTPAccount()
        hotp.label = "counter"
        hotp.kind = .hotp
        hotp.counter = 42
        var steam = OTPAccount()
        steam.issuer = "Steam"
        steam.label = "gamer"
        steam.kind = .steam
        steam.digits = 5
        let originals = [
            OTPEntry(account: totp, secret: Data("12345678901234567890".utf8)),
            OTPEntry(account: hotp, secret: Data([0xde, 0xad, 0xbe, 0xef])),
            OTPEntry(account: steam, secret: Data("steamsteamsteamsteam".utf8)),
        ]
        do {
            let decoded = try GoogleMigration.decode(payload: GoogleMigration.encode(originals))
            expect(decoded.count == 3, "three entries survive a round trip")
            expect(decoded.map(\.secret) == originals.map(\.secret), "secrets survive a round trip")
            expect(decoded[0].account.issuer == "GitHub" && decoded[0].account.label == "octocat"
                    && decoded[0].account.algorithm == .sha256 && decoded[0].account.digits == 8,
                   "a SHA256 eight digit account survives")
            expect(decoded[1].account.kind == .hotp && decoded[1].account.counter == 42,
                   "an HOTP counter survives")
            expect(decoded[2].account.kind == .steam && decoded[2].account.digits == 5,
                   "a Steam account is recognised on the way back")
        } catch {
            expect(false, "the writer's payload decodes: \(error)")
        }

        // Batching: eleven accounts become two codes, each parsable.
        let many = (0..<11).map { index -> OTPEntry in
            var account = OTPAccount()
            account.label = "user\(index)"
            return OTPEntry(account: account, secret: Data("secret\(index)".utf8))
        }
        let uris = GoogleMigration.uris(for: many)
        expect(uris.count == 2, "eleven accounts export as two codes")
        let reimported = uris.compactMap { try? GoogleMigration.decode(uri: $0) }
        expect(reimported.map(\.count) == [10, 1], "the batches hold ten and one")
        expect(GoogleMigration.uris(for: []).isEmpty, "nothing exports as no codes")

        // Unsupported entries are dropped, not mangled.
        var md5: [UInt8] = []
        md5 += [0x0a, 0x03, 0x61, 0x62, 0x63]
        md5 += [0x12, 0x01, 0x78]
        md5 += [0x20, 0x04, 0x28, 0x01, 0x30, 0x02]
        let md5Payload = Data([0x0a, UInt8(md5.count)] + md5)
        expect((try? GoogleMigration.decode(payload: md5Payload))?.isEmpty == true,
               "an MD5 entry is skipped")

        do {
            _ = try GoogleMigration.decode(uri: "otpauth://totp/x?secret=MFRGG")
            expect(false, "a plain otpauth URI is not a migration")
        } catch let error as GoogleMigration.DecodeError {
            expect(error == .notMigrationURI, "a plain otpauth URI is not a migration")
        } catch {
            expect(false, "a plain otpauth URI is not a migration")
        }
        expect((try? GoogleMigration.decode(payload: Data([0x0a, 0x50, 0x01]))) == nil,
               "a truncated payload is refused")
    }
}
