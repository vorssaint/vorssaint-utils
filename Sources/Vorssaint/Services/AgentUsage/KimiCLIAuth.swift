// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

struct KimiAuthentication {
    let token: String
    let identityHeaders: [String: String]
}

/// Read-only reuse of the official CLI's sign-in. Refresh tokens never leave
/// this file: the official CLI remains responsible for renewing its access token.
enum KimiCLIAuth {
    static let safetyMargin: TimeInterval = 60

    static func home(environment: [String: String] = ProcessInfo.processInfo.environment,
                     fileManager: FileManager = .default) -> URL {
        if let override = cleaned(environment["KIMI_CODE_HOME"]) {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".kimi-code", isDirectory: true)
    }

    static func hasCredential(region: KimiRegion,
                              environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        readCredentials(region: region, environment: environment).contains {
            !$0.accessToken.isEmpty || !$0.refreshToken.isEmpty
        }
    }

    /// The service region the CLI's `config.toml` points at. The credential
    /// file itself carries no issuer, so this is the only reliable sign of
    /// which endpoint a token belongs to.
    static func configuredRegion(environment: [String: String] = ProcessInfo.processInfo.environment) -> KimiRegion? {
        let config = home(environment: environment).appendingPathComponent("config.toml", isDirectory: false)
        guard let contents = try? String(contentsOf: config, encoding: .utf8) else { return nil }
        for raw in contents.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("base_url") || line.hasPrefix("oauth_host") else { continue }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            let unquoted = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard let host = URL(string: unquoted)?.host else { continue }
            if host.hasSuffix("kimi.ai") { return .international }
            if host.hasSuffix("kimi.com") { return .china }
        }
        return nil
    }

    static func authentication(region: KimiRegion, now: Date = Date(),
                               environment: [String: String] = ProcessInfo.processInfo.environment) -> KimiAuthentication? {
        let threshold = now.addingTimeInterval(safetyMargin).timeIntervalSince1970
        let credential = readCredentials(region: region, environment: environment)
            .filter { $0.expiresAt.map { $0.isFinite && $0 > threshold } == true && !$0.accessToken.isEmpty }
            .max { ($0.expiresAt ?? 0) < ($1.expiresAt ?? 0) }
        guard let credential else { return nil }
        return KimiAuthentication(token: credential.accessToken,
                                  identityHeaders: identityHeaders(environment: environment))
    }

    private struct Credential {
        let accessToken: String
        let refreshToken: String
        let expiresAt: TimeInterval?
    }

    private static func readCredentials(region: KimiRegion,
                                        environment: [String: String]) -> [Credential] {
        // The credential file does not identify its issuer; the CLI's
        // config.toml does. Never forward the token to an explicitly overridden
        // endpoint or to a service region the CLI is not configured for.
        guard !["KIMI_CODE_BASE_URL", "KIMI_CODE_OAUTH_HOST", "KIMI_OAUTH_HOST"].contains(where: {
                  cleaned(environment[$0]) != nil
              }),
              configuredRegion(environment: environment) == region
        else { return [] }
        let folder = home(environment: environment).appendingPathComponent("credentials", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter {
            $0 == "kimi-code.json" || ($0.hasPrefix("kimi-code-") && $0.hasSuffix(".json"))
        }.sorted().compactMap { readCredential(folder.appendingPathComponent($0, isDirectory: false)) }
    }

    private static func readCredential(_ url: URL) -> Credential? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o077 == 0,
              (attributes[.referenceCount] as? NSNumber)?.intValue == 1,
              let data = try? Data(contentsOf: url), data.count <= 64 * 1024,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        return Credential(accessToken: cleaned(root["access_token"] as? String) ?? "",
                          refreshToken: cleaned(root["refresh_token"] as? String) ?? "",
                          expiresAt: timestamp(root["expires_at"]))
    }

    static func identityHeaders(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let architecture: String
        #if arch(arm64)
        architecture = "arm64"
        #elseif arch(x86_64)
        architecture = "x86_64"
        #else
        architecture = "unknown"
        #endif
        return [
            "User-Agent": "Vorssaint/\(AppInfo.version)",
            "X-Msh-Platform": "kimi_code_cli",
            "X-Msh-Version": AppInfo.version,
            "X-Msh-Device-Name": ascii(ProcessInfo.processInfo.hostName),
            "X-Msh-Device-Model": "macOS \(version) \(architecture)",
            "X-Msh-Os-Version": version,
            "X-Msh-Device-Id": deviceID(environment: environment),
        ]
    }

    private static func deviceID(environment: [String: String]) -> String {
        let home = home(environment: environment)
        let url = home.appendingPathComponent("device_id", isDirectory: false)
        if let existing = cleaned(try? String(contentsOf: url, encoding: .utf8)) { return existing }
        let identifier = UUID().uuidString.lowercased()
        do {
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try identifier.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // The official client also treats persistence as best-effort.
        }
        return identifier
    }

    private static func timestamp(_ value: Any?) -> TimeInterval? {
        if let string = value as? String { return TimeInterval(string) }
        guard let number = value as? NSNumber, number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func ascii(_ raw: String) -> String {
        var filtered = ""
        for scalar in raw.unicodeScalars where (0x20...0x7e).contains(scalar.value) {
            filtered.unicodeScalars.append(scalar)
        }
        let value = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "unknown" : value
    }
}
