// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum OneTimePasswordTests {
    static func run(expect: (Bool, String) -> Void) {
        let sha1Secret = Data("12345678901234567890".utf8)
        let sha256Secret = Data("12345678901234567890123456789012".utf8)
        let sha512Secret = Data("1234567890123456789012345678901234567890123456789012345678901234".utf8)

        // RFC 4226 appendix D.
        let hotpCodes = ["755224", "287082", "359152", "969429", "338314",
                         "254676", "287922", "162583", "399871", "520489"]
        for (counter, code) in hotpCodes.enumerated() {
            expect(OneTimePassword.hotp(secret: sha1Secret, counter: UInt64(counter),
                                        algorithm: .sha1, digits: 6) == code,
                   "HOTP counter \(counter) matches RFC 4226")
        }

        // RFC 6238 appendix B, eight digits, period 30.
        let times: [TimeInterval] = [59, 1_111_111_109, 1_111_111_111, 1_234_567_890, 2_000_000_000, 20_000_000_000]
        let vectors: [(OTPAccount.Algorithm, Data, [String])] = [
            (.sha1, sha1Secret, ["94287082", "07081804", "14050471", "89005924", "69279037", "65353130"]),
            (.sha256, sha256Secret, ["46119246", "68084774", "67062674", "91819424", "90698825", "77737706"]),
            (.sha512, sha512Secret, ["90693936", "25091201", "99943326", "93441116", "38618901", "47863826"]),
        ]
        for (algorithm, secret, codes) in vectors {
            var account = OTPAccount()
            account.algorithm = algorithm
            account.digits = 8
            for (time, code) in zip(times, codes) {
                let actual = OneTimePassword.code(for: account, secret: secret,
                                                  at: Date(timeIntervalSince1970: time))
                expect(actual == code, "TOTP \(algorithm.rawValue) at \(Int(time)) matches RFC 6238")
            }
        }

        var six = OTPAccount()
        expect(OneTimePassword.code(for: six, secret: sha1Secret, at: Date(timeIntervalSince1970: 59)) == "287082",
               "six digits keep the low digits of the eight digit code")
        expect(OneTimePassword.secondsRemaining(for: six, at: Date(timeIntervalSince1970: 59)) == 1,
               "one second left at the end of a period")
        expect(OneTimePassword.secondsRemaining(for: six, at: Date(timeIntervalSince1970: 60)) == 30,
               "a full period at its start")
        expect(OneTimePassword.nextCode(for: six, secret: sha1Secret, at: Date(timeIntervalSince1970: 59))
                == OneTimePassword.code(for: six, secret: sha1Secret, at: Date(timeIntervalSince1970: 89)),
               "the next code is the one a period later")
        six.kind = .hotp
        six.counter = 3
        expect(OneTimePassword.nextCode(for: six, secret: sha1Secret) == "338314",
               "the next HOTP code is the next counter")

        var steam = OTPAccount()
        steam.kind = .steam
        let steamCode = OneTimePassword.code(for: steam, secret: sha1Secret, at: Date(timeIntervalSince1970: 59))
        expect(steamCode.count == 5 && steamCode.allSatisfy { OneTimePassword.steamAlphabet.contains($0) },
               "a Steam code is five characters of the Steam alphabet")
        expect(steamCode == OneTimePassword.code(for: steam, secret: sha1Secret, at: Date(timeIntervalSince1970: 45)),
               "a Steam code holds for its period")

        // Base32.
        expect(OneTimePassword.base32Encode(sha1Secret) == "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
               "base32 encodes the RFC secret")
        expect(OneTimePassword.base32Decode("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ") == sha1Secret,
               "base32 decodes the RFC secret")
        expect(OneTimePassword.base32Decode("gezd gnbv-gy3t qojq gezd gnbv gy3t qojq====") == sha1Secret,
               "base32 ignores case, spaces, dashes and padding")
        expect(OneTimePassword.base32Decode("MFRGG") == Data("abc".utf8), "base32 handles a short tail")
        expect(OneTimePassword.base32Decode("ABC1") == nil, "base32 rejects a digit outside the alphabet")
        expect(OneTimePassword.base32Decode("") == nil, "base32 rejects an empty secret")
        expect(OneTimePassword.sanitizedSecret(" ab cd-ef ") == "ABCDEF", "a typed secret is normalised")

        // Grouping.
        expect(OneTimePassword.grouped("123456") == "123 456", "six digits split in threes")
        expect(OneTimePassword.grouped("12345678") == "1234 5678", "eight digits split in fours")
        expect(OneTimePassword.grouped("1234567") == "123 4567", "seven digits split three and four")
        expect(OneTimePassword.grouped("ABCDE") == "ABCDE", "Steam codes stay whole")

        // otpauth URIs.
        do {
            let entry = try OneTimePassword.parse(
                uri: "otpauth://totp/Example:alice%40example.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Example")
            expect(entry.account.issuer == "Example" && entry.account.label == "alice@example.com",
                   "issuer and label come out of the path")
            expect(entry.secret == sha1Secret && entry.account.kind == .totp && entry.account.digits == 6
                    && entry.account.period == 30 && entry.account.algorithm == .sha1,
                   "defaults fill in for a minimal URI")
            expect(OneTimePassword.uri(for: entry)
                    == "otpauth://totp/Example:alice@example.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Example",
                   "a default account serialises without noise")

            let queryWins = try OneTimePassword.parse(
                uri: "otpauth://totp/Old:bob?secret=MFRGG&issuer=New&algorithm=SHA256&digits=8&period=60")
            expect(queryWins.account.issuer == "New" && queryWins.account.label == "bob",
                   "the query issuer wins over the label prefix")
            expect(queryWins.account.algorithm == .sha256 && queryWins.account.digits == 8
                    && queryWins.account.period == 60,
                   "algorithm, digits and period are read")
            var back = try OneTimePassword.parse(uri: OneTimePassword.uri(for: queryWins))
            back.account.id = queryWins.account.id
            expect(back == queryWins, "a non-default account round trips")

            let hotp = try OneTimePassword.parse(uri: "otpauth://hotp/bob?secret=MFRGG&counter=7")
            expect(hotp.account.kind == .hotp && hotp.account.counter == 7, "HOTP keeps its counter")
            expect(OneTimePassword.uri(for: hotp) == "otpauth://hotp/bob?secret=MFRGG&counter=7",
                   "HOTP writes its counter and no period")

            // The three ways a Steam account is written in the wild.
            let steamURI = try OneTimePassword.parse(uri: "otpauth://totp/Steam:me?secret=MFRGG&issuer=Steam")
            expect(steamURI.account.kind == .steam && steamURI.account.digits == 5,
                   "a Steam issuer becomes a Steam account")
            let encoder = try OneTimePassword.parse(uri: "otpauth://totp/x?secret=MFRGG&encoder=steam")
            expect(encoder.account.kind == .steam, "encoder=steam becomes a Steam account")
            let host = try OneTimePassword.parse(uri: "otpauth://steam/Steam:me?secret=MFRGG")
            expect(host.account.kind == .steam && host.account.digits == 5,
                   "Aegis's steam host becomes a Steam account")
            let representation = try OneTimePassword.parse(
                uri: "otpauth://totp/x?secret=MFRGG&representation=steamguard")
            expect(representation.account.kind == .steam,
                   "representation=steamguard becomes a Steam account")
            let writtenSteam = OneTimePassword.uri(for: steamURI)
            expect(writtenSteam.hasPrefix("otpauth://steam/") && writtenSteam.contains("encoder=steam"),
                   "a Steam account is written so either reader takes it")
            expect(try OneTimePassword.parse(uri: writtenSteam).account.kind == .steam,
                   "and it reads back as Steam")

            let spaced = try OneTimePassword.parse(uri: "otpauth://totp/Acme%20Inc:a%20b?secret=MFRGG")
            expect(spaced.account.issuer == "Acme Inc" && spaced.account.label == "a b",
                   "percent-encoded spaces decode")
        } catch {
            expect(false, "valid URIs parse: \(error)")
        }

        func rejects(_ uri: String, _ expected: OneTimePassword.URIError, _ label: String) {
            do {
                _ = try OneTimePassword.parse(uri: uri)
                expect(false, label)
            } catch let error as OneTimePassword.URIError {
                expect(error == expected, label)
            } catch {
                expect(false, label)
            }
        }
        rejects("https://example.com", .notOTPAuth, "a web link is not otpauth")
        rejects("otpauth://ocra/x?secret=MFRGG", .unsupportedType, "an unknown type is refused")
        rejects("otpauth://totp/x?issuer=Y", .missingSecret, "a URI without a secret is refused")
        rejects("otpauth://totp/x?secret=1!", .invalidSecret, "a bad secret is refused")
        rejects("otpauth://totp/x?secret=MFRGG&digits=3", .invalidParameter("digits"), "three digits are refused")
        rejects("otpauth://totp/x?secret=MFRGG&algorithm=MD5", .invalidParameter("algorithm"), "MD5 is refused")

        let mixed = OneTimePassword.entries(inText: """
            # exported
            otpauth://totp/A?secret=MFRGG
            not a line
            otpauth://totp/B?secret=NOPE!
            otpauth://hotp/C?secret=MFRGG&counter=1
            """)
        expect(mixed.entries.count == 2 && mixed.failures == 1,
               "a text export imports its valid lines and counts the bad one")
    }
}
