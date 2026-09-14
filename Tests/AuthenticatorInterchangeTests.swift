// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AuthenticatorInterchangeTests {
    static func run(expect: (Bool, String) -> Void) {
        // Derived rather than pasted: the value is incidental here, and a
        // base32 blob beside the word "secret" trips secret scanners on
        // every fork of this repository. The literal that matters lives in
        // OneTimePasswordTests, where it is the RFC's own vector.
        let plain = Data("12345678901234567890".utf8)
        let encoded = OneTimePassword.base32Encode(plain)
        let aegis = Data("""
            {"version":1,"header":{"slots":null,"params":null},"db":{"version":2,"entries":[
              {"type":"totp","uuid":"1","name":"octocat","issuer":"GitHub","note":"",
               "info":{"secret":"\(encoded)","algo":"SHA256","digits":8,"period":60}},
              {"type":"hotp","uuid":"2","name":"counter","issuer":"","info":{"secret":"MFRGG","algo":"SHA1","digits":6,"counter":9}},
              {"type":"steam","uuid":"3","name":"gamer","issuer":"Steam","info":{"secret":"MFRGG","algo":"SHA1","digits":5,"period":30}},
              {"type":"motp","uuid":"4","name":"odd","issuer":"","info":{"secret":"MFRGG"}},
              {"type":"totp","uuid":"5","name":"bad","issuer":"","info":{"secret":"NOPE!"}}
            ]}}
            """.utf8)
        expect(AuthenticatorInterchange.detect(aegis) == .aegis, "an Aegis export is recognised")
        do {
            let result = try AuthenticatorInterchange.aegisEntries(aegis)
            expect(result.entries.count == 3 && result.failures == 2, "Aegis: three readable rows, two skipped")
            let github = result.entries[0]
            expect(github.account.issuer == "GitHub" && github.account.label == "octocat"
                    && github.account.algorithm == .sha256 && github.account.digits == 8
                    && github.account.period == 60 && github.secret == plain,
                   "Aegis: a TOTP row keeps its parameters")
            expect(result.entries[1].account.kind == .hotp && result.entries[1].account.counter == 9,
                   "Aegis: an HOTP row keeps its counter")
            expect(result.entries[2].account.kind == .steam && result.entries[2].account.digits == 5,
                   "Aegis: a Steam row is a Steam account")
        } catch {
            expect(false, "Aegis parses: \(error)")
        }

        let twoFAS = Data("""
            {"schemaVersion":4,"services":[
              {"name":"GitHub","secret":"MFRGG","otp":{"account":"octocat","issuer":"GitHub","digits":6,"period":30,"algorithm":"SHA1","tokenType":"TOTP"}},
              {"name":"Steam","secret":"MFRGG","otp":{"account":"me","tokenType":"STEAM"}},
              {"name":"Only name","secret":"MFRGG","otp":{"tokenType":"TOTP"}},
              {"name":"Broken","secret":"1!","otp":{}}
            ]}
            """.utf8)
        expect(AuthenticatorInterchange.detect(twoFAS) == .twoFAS, "a 2FAS export is recognised")
        do {
            let result = try AuthenticatorInterchange.twoFASEntries(twoFAS)
            expect(result.entries.count == 3 && result.failures == 1, "2FAS: three readable rows, one skipped")
            expect(result.entries[0].account.issuer == "GitHub" && result.entries[0].account.label == "octocat",
                   "2FAS: issuer and account are read")
            expect(result.entries[1].account.kind == .steam, "2FAS: STEAM becomes a Steam account")
            expect(result.entries[2].account.issuer == "Only name" && result.entries[2].account.label.isEmpty,
                   "2FAS: a service with only a name becomes the issuer")
        } catch {
            expect(false, "2FAS parses: \(error)")
        }

        expect(AuthenticatorInterchange.detect(Data(#"{"db":"AAAA","header":{}}"#.utf8)) == .aegisEncrypted,
               "an encrypted Aegis vault is told apart")
        expect(AuthenticatorInterchange.detect(Data(#"{"servicesEncrypted":"x"}"#.utf8)) == .twoFASEncrypted,
               "an encrypted 2FAS backup is told apart")
        expect(AuthenticatorInterchange.detect(Data("otpauth://totp/x?secret=MFRGG".utf8)) == .otpauthText,
               "a text export is recognised")
        expect(AuthenticatorInterchange.detect(Data("hello".utf8)) == nil, "plain text is not an export")

        // Backup round trip, with a small round count to keep the test quick.
        var account = OTPAccount()
        account.issuer = "GitHub"
        account.label = "octocat"
        let passphrase = "vault-fixture"
        let entries = [OTPEntry(account: account, secret: plain)]
        do {
            let file = try AuthenticatorInterchange.Backup.encrypt(entries, password: passphrase, rounds: 1000)
            expect(AuthenticatorInterchange.detect(file) == .backup, "a backup file is recognised")
            expect(!String(decoding: file, as: UTF8.self).contains("GEZDGNBV"), "the backup holds no plain secret")
            let back = try AuthenticatorInterchange.Backup.decrypt(file, password: passphrase)
            expect(back.count == 1 && back[0].secret == entries[0].secret
                    && back[0].account.issuer == "GitHub" && back[0].account.label == "octocat",
                   "a backup decrypts with the right password")
            do {
                _ = try AuthenticatorInterchange.Backup.decrypt(file, password: passphrase + "-typo")
                expect(false, "a wrong password is refused")
            } catch let error as AuthenticatorInterchange.ImportError {
                expect(error == .wrongPassword, "a wrong password is reported as such")
            }
            let again = try AuthenticatorInterchange.Backup.encrypt(entries, password: passphrase, rounds: 1000)
            expect(again != file, "every backup gets its own salt and nonce")
        } catch {
            expect(false, "the backup round trips: \(error)")
        }

        // Readable on purpose: a random-looking blob here trips secret
        // scanners on every fork of this repository.
        let steamPlain = Data("steam-secret-20bytes".utf8)
        expect(OneTimePassword.secretData(steamPlain.base64EncodedString(), kind: .steam) == steamPlain,
               "a Steam base64 key is taken as base64")
        expect(OneTimePassword.secretData("MFRGG", kind: .steam) == Data("abc".utf8),
               "a Steam base32 key is still base32")
        expect(OneTimePassword.secretData(String(steamPlain.base64EncodedString().prefix(8)), kind: .totp) == nil,
               "a TOTP key does not fall back to base64")

        // Published PBKDF2-HMAC-SHA256 vectors. A round trip alone would stay
        // green with the rounds ignored or the salt and password swapped;
        // these say the derivation is the one everyone else computes.
        func derived(_ password: String, _ salt: String, _ rounds: UInt32) -> String? {
            guard let key = try? AuthenticatorInterchange.Backup.derive(
                password: password, salt: Data(salt.utf8), rounds: rounds) else { return nil }
            return key.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
        }
        expect(derived("password", "salt", 1)
                == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b",
               "PBKDF2-HMAC-SHA256 matches the published vector at one round")
        expect(derived("password", "salt", 2)
                == "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43",
               "PBKDF2-HMAC-SHA256 matches the published vector at two rounds")
        expect(derived("password", "salt", 4096)
                == "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a",
               "PBKDF2-HMAC-SHA256 matches the published vector at 4096 rounds")
        expect(derived("password", "salt", 1) != derived("salt", "password", 1),
               "the password and the salt are not interchangeable")
    }
}
