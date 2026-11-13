// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum KimiCLIAuthTests {
    static func run(_ suite: TestSuite) {
        let home = FileManager.default.temporaryDirectory.appending(path: "vorss-kimi-auth-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let environment = ["KIMI_CODE_HOME": home.path]
        let now = Date(timeIntervalSince1970: 1_000)
        write(home: home, access: "cli-test-token", refresh: "refresh-token", expiry: 1_061, suite: suite)
        writeConfig(home: home, host: "api.kimi.com", suite: suite)

        suite.expect(KimiCLIAuth.home(environment: environment).path == home.path
                        && KimiCLIAuth.hasCredential(region: .china, environment: environment),
                     "Kimi Code's custom home and existing CLI credential are found")
        let authentication = KimiCLIAuth.authentication(region: .china, now: now, environment: environment)
        suite.expect(authentication?.token == "cli-test-token"
                        && authentication?.identityHeaders["X-Msh-Platform"] == "kimi_code_cli"
                        && authentication?.identityHeaders["X-Msh-Device-Id"] != nil,
                     "a fresh CLI access token supplies the request and its device identity")
        suite.expect(KimiCLIAuth.authentication(region: .china, now: now, environment: environment)?
                        .identityHeaders["X-Msh-Device-Id"] == authentication?.identityHeaders["X-Msh-Device-Id"],
                     "the device id is stable across requests")
        let deviceURL = home.appending(path: "device_id")
        let permissions = try? FileManager.default.attributesOfItem(atPath: deviceURL.path)[.posixPermissions] as? NSNumber
        suite.expect(permissions?.intValue == 0o600, "a newly persisted device id is private")

        suite.expect(KimiCLIAuth.authentication(region: .china, now: now.addingTimeInterval(2), environment: environment) == nil
                        && KimiCLIAuth.hasCredential(region: .china, environment: environment),
                     "an expiring access token is refused while the CLI-owned credential still explains the sign-in")
        suite.expect(KimiCLIAuth.authentication(region: .international, now: now, environment: environment) == nil
                        && !KimiCLIAuth.hasCredential(region: .international, environment: environment),
                     "a China credential is never forwarded to the international endpoint")
        let overridden = ["KIMI_CODE_HOME": home.path, "KIMI_CODE_BASE_URL": "https://example.com/coding/v1"]
        suite.expect(KimiCLIAuth.authentication(region: .china, now: now, environment: overridden) == nil,
                     "an endpoint override disables CLI credential forwarding")

        write(home: home, access: "string-expiry-token", refresh: "", expiry: "2000", suite: suite)
        suite.expect(KimiCLIAuth.authentication(region: .china, now: now, environment: environment)?.token
                        == "string-expiry-token",
                     "the CLI's string-valued expiry is accepted")
        let credential = home.appending(path: "credentials/kimi-code.json")
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: credential.path)
        suite.expect(!KimiCLIAuth.hasCredential(region: .china, environment: environment),
                     "a credential readable by other users is not imported")
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credential.path)
        write(home: home, access: "older-environment-token", refresh: "", expiry: 2_000,
              name: "kimi-code-env-old.json", suite: suite)
        write(home: home, access: "fresh-environment-token", refresh: "", expiry: 3_000,
              name: "kimi-code-env-new.json", suite: suite)
        suite.expect(KimiCLIAuth.authentication(region: .china, now: now, environment: environment)?.token
                        == "fresh-environment-token",
                     "environment-specific CLI credentials are discovered and the freshest access token wins")

        writeConfig(home: home, host: "api.kimi.ai", suite: suite)
        suite.expect(KimiCLIAuth.hasCredential(region: .international, environment: environment)
                        && KimiCLIAuth.authentication(region: .international, now: now, environment: environment)?.token
                            == "fresh-environment-token",
                     "an international config supplies its own region's endpoint")
        suite.expect(!KimiCLIAuth.hasCredential(region: .china, environment: environment)
                        && KimiCLIAuth.authentication(region: .china, now: now, environment: environment) == nil,
                     "an international credential is never forwarded to the China endpoint")
        let noConfig = ["KIMI_CODE_HOME": home.path]
        try? FileManager.default.removeItem(at: home.appending(path: "config.toml"))
        suite.expect(KimiCLIAuth.configuredRegion(environment: noConfig) == nil
                        && !KimiCLIAuth.hasCredential(region: .china, environment: noConfig)
                        && !KimiCLIAuth.hasCredential(region: .international, environment: noConfig),
                     "without a config.toml no region can be trusted to forward the credential to")
    }

    private static func write(home: URL, access: String, refresh: String, expiry: Any,
                              name: String = "kimi-code.json", suite: TestSuite) {
        let credentials = home.appending(path: "credentials", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: credentials, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let object: [String: Any] = ["access_token": access, "refresh_token": refresh, "expires_at": expiry]
            let data = try JSONSerialization.data(withJSONObject: object)
            let url = credentials.appending(path: name)
            try data.write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            suite.expect(false, "Kimi CLI credential fixture: \(error)")
        }
    }

    private static func writeConfig(home: URL, host: String, suite: TestSuite) {
        do {
            let config = "base_url = \"https://\(host)/coding/v1\"\n"
            try config.write(to: home.appending(path: "config.toml"), atomically: true, encoding: .utf8)
        } catch {
            suite.expect(false, "Kimi CLI config.toml fixture: \(error)")
        }
    }
}
