// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where the herdr binary lives and which runtimes it speaks. Follows the
/// `AgentCodexServer.candidates` precedent: fixed install folders first,
/// then the shell's PATH, probed with `isExecutableFile`. Discovery runs
/// lazily on first open, never at launch, and the answer is cached for the
/// life of the process. A missing binary is availability, not failure: the
/// surface renders an install hint and never logs the miss as an error.
enum HerdrDiscovery {
    /// Lowest CLI this integration speaks. Checked against `herdr
    /// --version`; older stays "installed but unsupported" with its own UI
    /// line instead of failing every verb.
    static let minimumVersion = (major: 0, minor: 9, patch: 3)

    static func candidates(home: URL, searchPath: String? = nil) -> [URL] {
        let folders = [home.appending(path: ".local/bin").path,
                       "/opt/homebrew/bin", "/usr/local/bin"]
            + (searchPath ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        return folders.map { URL(fileURLWithPath: $0, isDirectory: true).appending(path: "herdr") }
    }

    static func resolve(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                        searchPath: String? = ProcessInfo.processInfo.environment["PATH"]) -> URL? {
        candidates(home: home, searchPath: searchPath).first { url in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
                && !directory.boolValue
                && FileManager.default.isExecutableFile(atPath: url.path)
        }
    }

    /// An app opened from Finder has only system folders on its PATH, so the
    /// child inherits a PATH that leads with the binary's own folder.
    static func environment(for executable: URL, searchPath: String?,
                            base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        let folders = [executable.deletingLastPathComponent().path]
            + (searchPath.map { [$0] } ?? ["/opt/homebrew/bin", "/usr/local/bin"])
            + [base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]
        environment["PATH"] = folders.joined(separator: ":")
        return environment
    }

    /// Accepts `herdr 0.9.3`, a bare `0.9.3`, or a longer version line; the
    /// check is numeric per component, so 0.10.0 outranks 0.9.3.
    static func isSupported(version: String?) -> Bool {
        guard let version else { return false }
        let numbers = version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count >= 3 else { return false }
        let got = (numbers[0], numbers[1], numbers[2])
        let want = minimumVersion
        if got.0 != want.major { return got.0 > want.major }
        if got.1 != want.minor { return got.1 > want.minor }
        return got.2 >= want.patch
    }
}
