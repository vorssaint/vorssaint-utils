// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum HomebrewPackageKind: String, CaseIterable, Identifiable {
    case cask
    case formula

    var id: String { rawValue }
}

struct HomebrewPackage: Identifiable, Hashable {
    let kind: HomebrewPackageKind
    let name: String
    var displayName: String
    var desc: String?
    var installedVersion: String?
    var stableVersion: String?
    var homepage: String?
    var popularity: HomebrewPopularity?
    var update: HomebrewPackageUpdate?

    var id: String { "\(kind.rawValue):\(name)" }
    var isInstalled: Bool { installedVersion != nil }
    var hasUpdateAvailable: Bool { update != nil }
    var versionText: String? { installedVersion ?? stableVersion }
}

struct HomebrewPackageUpdate: Hashable {
    let kind: HomebrewPackageKind
    let name: String
    let installedVersions: [String]
    let currentVersion: String
    let isPinned: Bool

    var id: String { "\(kind.rawValue):\(name)" }

    var installedText: String {
        installedVersions.joined(separator: ", ")
    }

    var versionSummary: String {
        let installed = installedText
        return installed.isEmpty ? currentVersion : "\(installed) -> \(currentVersion)"
    }
}

struct HomebrewPopularity: Hashable {
    let count: Int
    let rank: Int?
    let days: Int

    var compactCount: String {
        HomebrewAnalytics.compactCount(count)
    }

    var decimalCount: String {
        HomebrewAnalytics.decimalCount(count)
    }
}

struct HomebrewCommand: Equatable {
    let executable: String
    let arguments: [String]
}

struct HomebrewOperation {
    enum Action {
        case install
        case uninstall
        case upgrade
        case upgradeAll
        case updateHomebrew

        var runningSystemImage: String {
            switch self {
            case .install:
                return "arrow.down.circle.fill"
            case .uninstall:
                return "trash.circle.fill"
            case .upgrade, .upgradeAll:
                return "arrow.up.circle.fill"
            case .updateHomebrew:
                return "arrow.triangle.2.circlepath"
            }
        }
    }

    let action: Action
    let package: HomebrewPackage?
}

enum HomebrewOperationPhase: Equatable {
    case preparing
    case downloading
    case installing
    case uninstalling
    case upgrading
    case finalizing
    case refreshing
}

enum HomebrewOperationResult: Equatable {
    case running
    case succeeded
    case failed
    case cancelled
    case needsTerminal
}

struct HomebrewOperationStatus: Equatable {
    var action: HomebrewOperation.Action
    var package: HomebrewPackage?
    var phase: HomebrewOperationPhase
    var result: HomebrewOperationResult
    var progressFraction: Double?
    var startedAt: Date
    var finishedAt: Date?
    var lastActivity: String?

    var isActive: Bool {
        result == .running
    }

    var targetID: String {
        package?.id ?? "homebrew:\(action)"
    }
}

struct HomebrewPendingAction {
    let action: HomebrewOperation.Action
    let package: HomebrewPackage?

    init(action: HomebrewOperation.Action, package: HomebrewPackage? = nil) {
        self.action = action
        self.package = package
    }
}

enum HomebrewCommandBuilder {
    static let candidatePaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    static let installerCommand = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#

    static func installed(brewPath: String) -> HomebrewCommand {
        HomebrewCommand(executable: brewPath, arguments: ["info", "--json=v2", "--installed"])
    }

    static func outdated(brewPath: String) -> HomebrewCommand {
        HomebrewCommand(executable: brewPath, arguments: ["outdated", "--json=v2"])
    }

    static func update(brewPath: String) -> HomebrewCommand {
        HomebrewCommand(executable: brewPath, arguments: ["update"])
    }

    static func search(brewPath: String, kind: HomebrewPackageKind, query: String) -> HomebrewCommand {
        let flag = kind == .formula ? "--formula" : "--cask"
        return HomebrewCommand(executable: brewPath, arguments: ["search", flag, query])
    }

    static func details(brewPath: String, package: HomebrewPackage) -> HomebrewCommand {
        let flag = package.kind == .formula ? "--formula" : "--cask"
        return HomebrewCommand(executable: brewPath, arguments: ["info", "--json=v2", flag, package.name])
    }

    static func install(brewPath: String, package: HomebrewPackage) -> HomebrewCommand {
        var args = ["install"]
        if package.kind == .cask { args.append("--cask") }
        args.append(package.name)
        return HomebrewCommand(executable: brewPath, arguments: args)
    }

    static func uninstall(brewPath: String, package: HomebrewPackage) -> HomebrewCommand {
        var args = ["uninstall"]
        if package.kind == .cask { args.append("--cask") }
        args.append(package.name)
        return HomebrewCommand(executable: brewPath, arguments: args)
    }

    static func upgrade(brewPath: String, package: HomebrewPackage) -> HomebrewCommand {
        var args = ["upgrade"]
        if package.kind == .cask { args.append("--cask") }
        args.append(package.name)
        return HomebrewCommand(executable: brewPath, arguments: args)
    }

    static func upgradeAll(brewPath: String) -> HomebrewCommand {
        HomebrewCommand(executable: brewPath, arguments: ["upgrade"])
    }

    static func isValidToken(_ token: String) -> Bool {
        guard !token.isEmpty,
              !token.hasPrefix("-"),
              !token.contains(".."),
              !token.contains("//") else { return false }
        return token.range(of: #"^[A-Za-z0-9][A-Za-z0-9._+@/-]*$"#,
                           options: .regularExpression) != nil
    }

    static func shellCommand(_ command: HomebrewCommand) -> String {
        ([command.executable] + command.arguments).map(shellQuote).joined(separator: " ")
    }

    static func needsTerminalFallback(output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("sudo:")
            || lower.contains("a terminal is required")
            || lower.contains("password is required")
            || lower.contains("password:")
            || lower.contains("administrator privileges")
    }

    static func shellQuote(_ value: String) -> String {
        if value.range(of: #"^[A-Za-z0-9._+@%/=:,-]+$"#, options: .regularExpression) != nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func shellEnvLine(brewPath: String) -> String {
        #"eval "$(\#(brewPath) shellenv)""#
    }

    static func shellProfilePath(homeDirectory: String = NSHomeDirectory(),
                                 shellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "") -> String {
        switch URL(fileURLWithPath: shellPath).lastPathComponent {
        case "bash":
            return "\(homeDirectory)/.bash_profile"
        case "zsh":
            return "\(homeDirectory)/.zprofile"
        default:
            return "\(homeDirectory)/.profile"
        }
    }

    static func shellProfilePathsToCheck(homeDirectory: String = NSHomeDirectory(),
                                         shellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "") -> [String] {
        let primary = shellProfilePath(homeDirectory: homeDirectory, shellPath: shellPath)
        let common = [
            "\(homeDirectory)/.zprofile",
            "\(homeDirectory)/.zshrc",
            "\(homeDirectory)/.bash_profile",
            "\(homeDirectory)/.bashrc",
            "\(homeDirectory)/.profile",
        ]
        return ([primary] + common).reduce(into: [String]()) { result, path in
            if !result.contains(path) {
                result.append(path)
            }
        }
    }

    static func shellConfigCommand(brewPath: String,
                                   homeDirectory: String = NSHomeDirectory(),
                                   shellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "") -> String {
        let profile = shellProfilePath(homeDirectory: homeDirectory, shellPath: shellPath)
        let line = shellEnvLine(brewPath: brewPath)
        let brew = shellQuote(brewPath)
        return [
            "PROFILE=\(shellQuote(profile))",
            "LINE=\(shellQuote(line))",
            #"/usr/bin/touch "$PROFILE""#,
            #"if /usr/bin/grep -qxF "$LINE" "$PROFILE" 2>/dev/null; then echo "Homebrew shell setup already exists in $PROFILE"; else { echo; echo "$LINE"; } >> "$PROFILE"; echo "Added Homebrew shell setup to $PROFILE"; fi"#,
            #"eval "$(\#(brew) shellenv)""#,
            "brew --version",
        ].joined(separator: "; ")
    }
}

enum HomebrewAnalytics {
    static let defaultDays = 30

    static func url(kind: HomebrewPackageKind, days: Int = defaultDays) -> URL {
        let category = kind == .formula ? "install-on-request/homebrew-core" : "cask-install/homebrew-cask"
        return URL(string: "https://formulae.brew.sh/api/analytics/\(category)/\(days)d.json")!
    }

    static func parse(_ data: Data,
                      kind: HomebrewPackageKind,
                      days: Int = defaultDays) throws -> [String: HomebrewPopularity] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        let counts = counts(from: root, kind: kind)
        let rankedTokens = counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }
        return Dictionary(uniqueKeysWithValues: rankedTokens.enumerated().map { index, element in
            (element.key, HomebrewPopularity(count: element.value, rank: index + 1, days: days))
        })
    }

    static func enrichAndSort(_ packages: [HomebrewPackage],
                              popularity: [String: HomebrewPopularity]) -> [HomebrewPackage] {
        packages
            .map { package in
                var copy = package
                copy.popularity = popularity[package.name]
                return copy
            }
            .sorted { lhs, rhs in
                switch (lhs.popularity?.count, rhs.popularity?.count) {
                case let (left?, right?) where left != right:
                    return left > right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
            }
    }

    static func compactCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            let value = Double(count) / 1_000_000
            return value >= 10 ? "\(Int(value.rounded()))M" : String(format: "%.1fM", value)
        }
        if count >= 1_000 {
            let value = Double(count) / 1_000
            return value >= 10 ? "\(Int(value.rounded()))K" : String(format: "%.1fK", value)
        }
        return "\(max(count, 0))"
    }

    static func decimalCount(_ count: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: max(count, 0)), number: .decimal)
    }

    private static func counts(from root: [String: Any],
                               kind: HomebrewPackageKind) -> [String: Int] {
        if let grouped = root["formulae"] as? [String: [[String: Any]]] {
            let nameKey = kind == .formula ? "formula" : "cask"
            return grouped.reduce(into: [String: Int]()) { result, entry in
                guard HomebrewCommandBuilder.isValidToken(entry.key) else { return }
                let count = countForGroupedRecords(entry.value, token: entry.key, nameKey: nameKey)
                if count > 0 {
                    result[entry.key] = count
                }
            }
        }

        if let items = root["items"] as? [[String: Any]] {
            let nameKey = kind == .formula ? "formula" : "cask"
            return items.reduce(into: [String: Int]()) { result, item in
                guard let token = item[nameKey] as? String,
                      HomebrewCommandBuilder.isValidToken(token),
                      let count = intCount(item["count"]) else { return }
                result[token, default: 0] += count
            }
        }

        return [:]
    }

    private static func countForGroupedRecords(_ records: [[String: Any]],
                                               token: String,
                                               nameKey: String) -> Int {
        if let exact = records.first(where: { ($0[nameKey] as? String) == token }),
           let count = intCount(exact["count"]) {
            return count
        }
        return records.reduce(0) { total, record in
            total + (intCount(record["count"]) ?? 0)
        }
    }

    private static func intCount(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        guard let string = value as? String else { return nil }
        let digits = string.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }
}

enum HomebrewProgressParser {
    static func progressFraction(in output: String) -> Double? {
        var latest: Double?
        let pattern = #"([0-9]{1,3}(?:\.[0-9]+)?)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        regex.enumerateMatches(in: output, range: range) { match, _, _ in
            guard let match,
                  let valueRange = Range(match.range(at: 1), in: output),
                  let value = Double(output[valueRange]) else { return }
            latest = min(max(value / 100, 0), 1)
        }
        return latest
    }

    static func phase(in output: String,
                      action: HomebrewOperation.Action) -> HomebrewOperationPhase? {
        let lower = stripANSI(output).lowercased()
        if lower.contains("downloading")
            || lower.contains("fetching")
            || lower.contains("downloaded") {
            return .downloading
        }
        if lower.contains("uninstalling")
            || lower.contains("zap")
            || lower.contains("purging") {
            return .uninstalling
        }
        if lower.contains("upgrading")
            || lower.contains("upgraded") {
            return .upgrading
        }
        if action == .updateHomebrew,
           (lower.contains("updating")
            || lower.contains("updated")
            || lower.contains("already up-to-date")
            || lower.contains("already up to date")) {
            return .refreshing
        }
        if lower.contains("installing")
            || lower.contains("pouring")
            || lower.contains("moving app")
            || lower.contains("linking") {
            switch action {
            case .uninstall:
                return .uninstalling
            case .upgrade, .upgradeAll:
                return .upgrading
            case .updateHomebrew:
                return .refreshing
            case .install:
                return .installing
            }
        }
        if lower.contains("cleanup")
            || lower.contains("cleaning")
            || lower.contains("caveats")
            || lower.contains("summary")
            || lower.contains("installed!")
            || lower.contains("uninstalled") {
            return .finalizing
        }
        return nil
    }

    static func activity(in output: String) -> String? {
        lines(in: output).reversed().first { line in
            let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !stripped.isEmpty,
                  !stripped.hasPrefix("$ "),
                  !isMostlyProgressSymbols(stripped) else { return false }
            return true
        }
    }

    static func visibleError(from output: String) -> String {
        let candidates = lines(in: output).filter { line in
            let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !stripped.isEmpty
                && !stripped.hasPrefix("$ ")
                && !isMostlyProgressSymbols(stripped)
        }
        return candidates.suffix(3).joined(separator: "\n")
    }

    private static func lines(in output: String) -> [String] {
        stripANSI(output)
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map(cleanLine)
    }

    private static func cleanLine(_ line: Substring) -> String {
        var value = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("==>") {
            value.removeFirst(3)
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        while value.hasPrefix("->") {
            value.removeFirst(2)
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    private static func stripANSI(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\u001B\[[0-9;?]*[ -/]*[@-~]"#) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: "")
    }

    private static func isMostlyProgressSymbols(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "#=-> .:%0123456789")
        let scalars = value.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard !scalars.isEmpty else { return true }
        let progressCount = scalars.filter { allowed.contains($0) }.count
        return Double(progressCount) / Double(scalars.count) > 0.85
    }
}

enum HomebrewParser {
    static func parseInfoJSON(_ data: Data) throws -> [HomebrewPackage] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let formulae = (root["formulae"] as? [[String: Any]] ?? []).compactMap(parseFormula)
        let casks = (root["casks"] as? [[String: Any]] ?? []).compactMap(parseCask)
        return (formulae + casks).sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .cask }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    static func parseInfoCommandOutput(_ output: String) throws -> [HomebrewPackage] {
        let data = Data(output.utf8)
        do {
            return try parseInfoJSON(data)
        } catch {
            for json in balancedJSONObjects(in: output) {
                let jsonData = Data(json.utf8)
                guard isInfoJSONObject(jsonData) else { continue }
                if let packages = try? parseInfoJSON(jsonData) {
                    return packages
                }
            }
            throw error
        }
    }

    static func parseSearchOutput(_ output: String,
                                  kind: HomebrewPackageKind,
                                  installed: [HomebrewPackage]) -> [HomebrewPackage] {
        let installedByID = Dictionary(uniqueKeysWithValues: installed.map { ($0.id, $0) })
        var seen: Set<String> = []
        return output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { HomebrewCommandBuilder.isValidToken($0) }
            .compactMap { token -> HomebrewPackage? in
                let id = "\(kind.rawValue):\(token)"
                guard seen.insert(id).inserted else { return nil }
                if let installedPackage = installedByID[id] { return installedPackage }
                return HomebrewPackage(kind: kind,
                                       name: token,
                                       displayName: token,
                                       desc: nil,
                                       installedVersion: nil,
                                       stableVersion: nil,
                                       homepage: nil)
            }
    }

    static func parseOutdatedJSON(_ data: Data) throws -> [String: HomebrewPackageUpdate] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        let formulae = (root["formulae"] as? [[String: Any]] ?? [])
            .compactMap { parseOutdatedItem($0, kind: .formula) }
        let casks = (root["casks"] as? [[String: Any]] ?? [])
            .compactMap { parseOutdatedItem($0, kind: .cask) }
        return Dictionary(uniqueKeysWithValues: (formulae + casks).map { ($0.id, $0) })
    }

    static func parseOutdatedCommandOutput(_ output: String) throws -> [String: HomebrewPackageUpdate] {
        let data = Data(output.utf8)
        do {
            return try parseOutdatedJSON(data)
        } catch {
            for json in balancedJSONObjects(in: output) {
                let jsonData = Data(json.utf8)
                guard isOutdatedJSONObject(jsonData) else { continue }
                if let updates = try? parseOutdatedJSON(jsonData) {
                    return updates
                }
            }
            throw error
        }
    }

    private static func parseFormula(_ item: [String: Any]) -> HomebrewPackage? {
        guard let name = item["name"] as? String,
              HomebrewCommandBuilder.isValidToken(name) else { return nil }
        let installed = item["installed"] as? [[String: Any]] ?? []
        let installedVersions = installed.compactMap { $0["version"] as? String }
        let stable = (item["versions"] as? [String: Any])?["stable"] as? String
        return HomebrewPackage(kind: .formula,
                               name: name,
                               displayName: item["full_name"] as? String ?? name,
                               desc: item["desc"] as? String,
                               installedVersion: installedVersions.isEmpty ? nil : installedVersions.joined(separator: ", "),
                               stableVersion: stable,
                               homepage: item["homepage"] as? String)
    }

    private static func parseCask(_ item: [String: Any]) -> HomebrewPackage? {
        guard let token = item["token"] as? String,
              HomebrewCommandBuilder.isValidToken(token) else { return nil }
        let displayName: String
        if let names = item["name"] as? [String], let first = names.first, !first.isEmpty {
            displayName = first
        } else {
            displayName = token
        }
        let installed = item["installed"] as? String
        return HomebrewPackage(kind: .cask,
                               name: token,
                               displayName: displayName,
                               desc: item["desc"] as? String,
                               installedVersion: installed?.isEmpty == false ? installed : nil,
                               stableVersion: item["version"] as? String,
                               homepage: item["homepage"] as? String)
    }

    private static func parseOutdatedItem(_ item: [String: Any],
                                          kind: HomebrewPackageKind) -> HomebrewPackageUpdate? {
        guard let name = (item["name"] as? String) ?? (item["token"] as? String),
              HomebrewCommandBuilder.isValidToken(name),
              let currentVersion = item["current_version"] as? String,
              !currentVersion.isEmpty else { return nil }
        let installedVersions = (item["installed_versions"] as? [String]) ?? []
        return HomebrewPackageUpdate(kind: kind,
                                     name: name,
                                     installedVersions: installedVersions,
                                     currentVersion: currentVersion,
                                     isPinned: item["pinned"] as? Bool ?? false)
    }

    private static func isInfoJSONObject(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return root["formulae"] != nil || root["casks"] != nil
    }

    private static func isOutdatedJSONObject(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        let formulae = root["formulae"] as? [[String: Any]]
        let casks = root["casks"] as? [[String: Any]]
        guard formulae != nil || casks != nil else { return false }
        let items = (formulae ?? []) + (casks ?? [])
        return items.isEmpty || items.contains { item in
            item["current_version"] != nil || item["installed_versions"] != nil
        }
    }

    private static func balancedJSONObjects(in output: String) -> [String] {
        var objects: [String] = []
        var start: String.Index?
        var depth = 0
        var inString = false
        var escaping = false

        var index = output.startIndex
        while index < output.endIndex {
            let character = output[index]

            if start == nil {
                if character == "{" {
                    start = index
                    depth = 1
                    inString = false
                    escaping = false
                }
                index = output.index(after: index)
                continue
            }

            if inString {
                if escaping {
                    escaping = false
                } else if character == "\\" {
                    escaping = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0, let objectStart = start {
                    let end = output.index(after: index)
                    objects.append(String(output[objectStart..<end]))
                    start = nil
                    depth = 0
                }
                if depth < 0 {
                    start = nil
                    depth = 0
                }
            }

            index = output.index(after: index)
        }

        return objects
    }
}
