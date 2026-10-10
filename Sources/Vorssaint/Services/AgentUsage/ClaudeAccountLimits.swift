// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

struct ClaudeAccountProfile: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    let directory: String

    static func decode(_ value: String) -> [Self] {
        guard value.utf8.count <= 64 * 1024,
              let decoded = try? JSONDecoder().decode([Self].self, from: Data(value.utf8)) else { return [] }
        var ids = Set<String>(), paths = Set<String>()
        return decoded.prefix(8).filter {
            UUID(uuidString: $0.id) != nil && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.name.count <= 40 && $0.directory.hasPrefix("/")
                && ids.insert($0.id).inserted
                && paths.insert(URL(fileURLWithPath: $0.directory).resolvingSymlinksInPath().path).inserted
        }
    }

    static func encode(_ profiles: [Self]) -> String {
        (try? JSONEncoder().encode(profiles)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Only metadata is examined. Authentication belongs to the official CLI.
    var canonicalDirectory: URL? {
        let url = URL(fileURLWithPath: directory, isDirectory: true).resolvingSymlinksInPath()
        guard url.path != "/", url.path != FileManager.default.homeDirectoryForCurrentUser.path,
              let root = try? FileManager.default.attributesOfItem(atPath: url.path),
              root[.type] as? FileAttributeType == .typeDirectory,
              (root[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let mode = root[.posixPermissions] as? NSNumber, mode.intValue & 0o022 == 0,
              FileManager.default.fileExists(atPath: url.appendingPathComponent(".claude.json").path)
        else { return nil }
        return url
    }

    static func discover(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Self] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []
        return folders.filter { $0.lastPathComponent.hasPrefix(".claude-") }.sorted { $0.path < $1.path }.compactMap {
            let name = String($0.lastPathComponent.dropFirst(".claude-".count)).capitalized
            let profile = Self(id: UUID().uuidString, name: name, directory: $0.path)
            return profile.canonicalDirectory == nil ? nil : profile
        }
    }
}

enum ClaudeAccountUsageParser {
    /// Screen-reader output from the official /usage command, without prompts,
    /// replies, activity statistics or authentication material.
    static func plainText(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{1B}\\][^\u{7}\u{1B}]*(?:\u{7}|\u{1B}\\\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{1B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{1B}[()][A-Za-z0-9]|\u{1B}[78]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r", with: "")
    }

    static func limits(_ output: String, now: Date) -> AgentLimits? {
        let lines = plainText(output).components(separatedBy: .newlines)
        var windows: [String: AgentLimitWindow] = [:]
        for index in lines.indices {
            let heading = lines[index].trimmingCharacters(in: .whitespaces)
            let kind: AgentLimitWindow.Kind
            let scope: String?
            if heading == "Current session" { kind = .session; scope = nil }
            else if heading == "Current week (all models)" { kind = .weekly; scope = nil }
            else if heading.hasPrefix("Current week ("), heading.hasSuffix(")") {
                kind = .weekly; scope = String(heading.dropFirst(14).dropLast())
            } else { continue }
            let id = "claude." + (kind == .session ? "session" : "weekly") + (scope.map { "." + $0 } ?? "")
            windows.removeValue(forKey: id)
            // A partial repaint must not borrow a percentage from the next window.
            let block = lines.dropFirst(index + 1).prefix(3)
            guard let usedLine = block.first(where: { $0.contains("% used") }),
                  let range = usedLine.range(of: #"\d+(?:\.\d+)?% used"#, options: .regularExpression),
                  let percent = Double(usedLine[range].dropLast(6)), (0...100).contains(percent),
                  let resetLine = block.first(where: { $0.hasPrefix("Resets ") }),
                  let reset = resetDate(String(resetLine.dropFirst(7)), now: now), reset > now,
                  reset.timeIntervalSince(now) <= (kind == .session ? 5 * 3600 : 7 * 86_400) + 300 else { continue }
            windows[id] = AgentLimitWindow(id: id, kind: kind, minutes: kind == .session ? 300 : 10_080,
                                           scope: scope, usedPercent: percent, resetsAt: reset)
        }
        guard windows["claude.session"] != nil, windows["claude.weekly"] != nil else { return nil }
        return AgentLimits(provider: .claude, windows: windows.values.sorted { $0.id < $1.id },
                           observedAt: now, source: .account)
    }

    static func resetDate(_ text: String, now: Date) -> Date? {
        guard let open = text.lastIndex(of: "("), text.hasSuffix(")"),
              let zone = TimeZone(identifier: String(text[text.index(after: open)..<text.index(before: text.endIndex)]))
        else { return nil }
        let value = String(text[..<open]).trimmingCharacters(in: .whitespaces).lowercased()
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = zone
        let dated = value.contains(" at ")
        for format in dated ? ["MMM d 'at' h:mma", "MMM d 'at' ha", "MMM d 'at' HH:mm"] : ["h:mma", "ha", "HH:mm"] {
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: value) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            let time = calendar.dateComponents([.month, .day, .hour, .minute], from: parsed)
            if dated { components.month = time.month; components.day = time.day }
            components.hour = time.hour; components.minute = time.minute; components.second = 0
            guard var date = calendar.date(from: components) else { continue }
            if date <= now {
                guard let next = calendar.date(byAdding: dated ? .year : .day, value: 1, to: date) else { continue }
                date = next
            }
            return date
        }
        return nil
    }
}

enum ClaudeAccountUsageError: Error {
    case invalidProfile, missingCLI, signedOut, unavailable, cancelled
}

enum ClaudeAccountUsageReader {
    static let refreshInterval: TimeInterval = 5 * 60

    static func executable(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        [home.appendingPathComponent(".local/bin/claude"), URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
         URL(fileURLWithPath: "/usr/local/bin/claude")].first {
            let url = $0.resolvingSymlinksInPath()
            guard ["claude", "claude.exe"].contains(url.lastPathComponent),
                  FileManager.default.isExecutableFile(atPath: url.path),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let permissions = attributes[.posixPermissions] as? NSNumber,
                  permissions.intValue & 0o022 == 0,
                  let owner = attributes[.ownerAccountID] as? NSNumber,
                  owner.uint32Value == 0 || owner.uint32Value == getuid() else { return false }
            return true
        }?.resolvingSymlinksInPath()
    }

    static func environment(directory: URL, base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        // Do not inherit API keys, provider routes or another profile's auth overrides.
        var result = base.filter {
            ["HOME", "USER", "LOGNAME", "TMPDIR", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
             "http_proxy", "https_proxy", "all_proxy", "no_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR",
             "NODE_EXTRA_CA_CERTS", "DISABLE_TELEMETRY", "DO_NOT_TRACK",
             "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"].contains($0.key)
        }
        result["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        result["CLAUDE_CONFIG_DIR"] = directory.path
        result["CLAUDE_SECURESTORAGE_CONFIG_DIR"] = directory.path
        result["LANG"] = "en_US.UTF-8"; result["TZ"] = "UTC"; result["TERM"] = "xterm-256color"
        // /usage needs the CLI's feature configuration. Preserve the user's
        // own opt-outs rather than silently overriding them; disabling feature
        // fetching can leave the CLI with only an old cached allowance.
        result["DISABLE_ERROR_REPORTING"] = "1"
        result["DISABLE_AUTOUPDATER"] = "1"
        return result
    }

    static func read(_ profile: ClaudeAccountProfile, executable: URL,
                     workspace: URL, cancellation: BoundedProcessCancellation,
                     timeout: TimeInterval = 35) throws -> (limits: AgentLimits, plan: String?) {
        guard let directory = profile.canonicalDirectory else { throw ClaudeAccountUsageError.invalidProfile }
        let env = environment(directory: directory)
        guard !cancellation.isCancelled else { throw ClaudeAccountUsageError.cancelled }
        let status = BoundedProcessRunner.runInNewSession(executable.path, ["auth", "status", "--json"], timeout: 10,
                                                         maxOutputBytes: 64 * 1024, environment: env)
        guard !cancellation.isCancelled else { throw ClaudeAccountUsageError.cancelled }
        guard status.status == 0,
              let account = try? JSONSerialization.jsonObject(with: status.output) as? [String: Any]
        else { throw ClaudeAccountUsageError.unavailable }
        guard account["loggedIn"] as? Bool == true, account["authMethod"] as? String == "claude.ai"
        else { throw ClaudeAccountUsageError.signedOut }
        let plan = (account["subscriptionType"] as? String).flatMap {
            ["pro", "max", "team", "enterprise"].contains($0) ? $0.capitalized : nil
        }
        // This private, empty directory is the only workspace the CLI may trust.
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let metadata = try workspace.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard metadata.isSymbolicLink != true, metadata.isDirectory == true,
              (try FileManager.default.contentsOfDirectory(atPath: workspace.path)).isEmpty else {
            throw ClaudeAccountUsageError.unavailable
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: workspace.path)
        var master: Int32 = -1, slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { throw ClaudeAccountUsageError.unavailable }
        defer { close(master); close(slave) }
        _ = fcntl(master, F_SETFL, O_NONBLOCK)
        var size = winsize(ws_row: 60, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(slave, TIOCSWINSZ, &size)
        let process = Process()
        process.executableURL = executable; process.environment = env; process.currentDirectoryURL = workspace
        process.arguments = ["--safe-mode", "--restricted", "--permission-mode", "plan", "--tools", "",
                             "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}", "--settings",
                             "{\"disableAllHooks\":true}", "--ax-screen-reader", "/usage"]
        let terminal = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        process.standardInput = terminal; process.standardOutput = terminal; process.standardError = terminal
        guard !cancellation.isCancelled else { throw ClaudeAccountUsageError.cancelled }
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                let until = Date().addingTimeInterval(0.3)
                while process.isRunning, Date() < until { usleep(10_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        var output = Data(), buffer = [UInt8](repeating: 0, count: 8192), trusted = false
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while process.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
            guard !cancellation.isCancelled else { throw ClaudeAccountUsageError.cancelled }
            let count = Darwin.read(master, &buffer, buffer.count)
            if count > 0 {
                output.append(contentsOf: buffer.prefix(count))
                guard output.count <= 256 * 1024 else { throw ClaudeAccountUsageError.unavailable }
                let plain = ClaudeAccountUsageParser.plainText(String(decoding: output, as: UTF8.self))
                if !trusted, plain.contains("Enter y/n:"), plain.contains(workspace.path),
                   plain.contains("Permission Required: Accessing workspace:") {
                    // The CLI's raw terminal treats carriage return as Enter.
                    let answer = Array("y\r".utf8)
                    _ = answer.withUnsafeBytes { Darwin.write(master, $0.baseAddress, $0.count) }
                    trusted = true
                }
                if let limits = ClaudeAccountUsageParser.limits(plain, now: Date()) { return (limits, plan) }
            } else { usleep(50_000) }
        }
        throw ClaudeAccountUsageError.unavailable
    }
}
