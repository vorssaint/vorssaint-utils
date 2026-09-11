// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The environment `brew` runs with. An app launched from Finder gets launchd's
/// environment, not the one a Terminal has after `~/.zprofile`, so a proxy or a
/// mirror exported there never reached the brew this app runs (issue #1290).
/// The login shell is asked once per launch for its exports, and only the names
/// brew itself keeps (the filter in `bin/brew`) are handed on.
enum HomebrewEnvironment {
    /// The app's own environment plus the login shell's proxy and HOMEBREW_*
    /// exports. The first read runs the login shell and may take up to
    /// `loginShellTimeout`, so it belongs on a work queue; a shell that fails
    /// or stalls contributes nothing and brew runs as before.
    static let forBrew: [String: String] = ProcessInfo.processInfo.environment
        .merging(exportsFromLoginShell(shellPath: HomebrewCommandBuilder.currentShellPath)) { _, shell in shell }

    static let loginShellTimeout: TimeInterval = 10

    /// brew's own list: the lowercase proxy names curl and git read, the
    /// uppercase ones brew forwards, and every HOMEBREW_* setting.
    static let passedThroughNames: Set<String> = [
        "http_proxy", "https_proxy", "ftp_proxy", "no_proxy", "all_proxy",
        "HTTPS_PROXY", "FTP_PROXY", "ALL_PROXY",
    ]

    static func isPassedThrough(_ name: String) -> Bool {
        passedThroughNames.contains(name) || name.hasPrefix("HOMEBREW_")
    }

    static func passthrough(_ environment: [String: String]) -> [String: String] {
        environment.filter { isPassedThrough($0.key) }
    }

    /// A login shell reads the profile files a Terminal window reads, without
    /// the interactive startup; `env -0` ends each entry with NUL so a value
    /// may contain anything, newlines included.
    static func loginShellCommand(shellPath: String) -> HomebrewCommand {
        HomebrewCommand(executable: shellPath, arguments: ["-l", "-c", "/usr/bin/env -0"])
    }

    static func exportsFromLoginShell(shellPath: String,
                                      timeout: TimeInterval = loginShellTimeout) -> [String: String] {
        guard !shellPath.isEmpty else { return [:] }
        let command = loginShellCommand(shellPath: shellPath)
        let result = BoundedProcessRunner.run(command.executable, command.arguments,
                                              timeout: timeout, maxOutputBytes: 1024 * 1024)
        guard result.status == 0, !result.timedOut else { return [:] }
        return passthrough(parse(nullSeparated: result.output))
    }

    /// An entry whose name is not an identifier is dropped: that is what a
    /// startup file's greeting looks like once it is glued to the entry behind
    /// it, and stdout and stderr arrive on the one pipe.
    static func parse(nullSeparated data: Data) -> [String: String] {
        var environment: [String: String] = [:]
        for entry in data.split(separator: 0) {
            guard let separator = entry.firstIndex(of: UInt8(ascii: "=")) else { continue }
            let name = String(decoding: entry[entry.startIndex..<separator], as: UTF8.self)
            guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { continue }
            environment[name] = String(decoding: entry[entry.index(after: separator)...], as: UTF8.self)
        }
        return environment
    }
}
