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
    /// exports. The first read runs the login shell and may take up to twice
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

    /// Printed immediately before the dump so the startup files' own output
    /// can be told from it. Startup writes no trailing NUL, so without this the
    /// greeting and the first entry arrive as one NUL-terminated run and that
    /// entry is lost, and the first entry can be the proxy or mirror setting.
    static let dumpMarker = "__VORSSAINT_ENV_DUMP__"

    /// Set for both runs so a startup file can tell it is only being read for
    /// its exports and skip slow or interactive work, the way editors that
    /// resolve the shell environment do (VS Code sets
    /// VSCODE_RESOLVING_ENVIRONMENT): `[[ -n $VORSSAINT_RESOLVING_ENVIRONMENT ]]`.
    /// The run is a child of this app, so a protected folder a startup file
    /// touches asks for access in Vorssaint's name, and `~/.zlogout` runs too.
    static let resolvingVariable = "VORSSAINT_RESOLVING_ENVIRONMENT"

    /// A login shell reads `~/.zprofile`; an interactive one also reads
    /// `~/.zshrc`, which is where a proxy line is just as likely to live, so a
    /// Terminal window's environment needs both. `env -0` ends each entry with
    /// NUL so a value may contain anything, newlines included.
    static func loginShellCommand(shellPath: String, interactive: Bool = true) -> HomebrewCommand {
        HomebrewCommand(executable: shellPath,
                        arguments: (interactive ? ["-l", "-i"] : ["-l"])
                            + ["-c", "printf %s \(dumpMarker); /usr/bin/env -0"])
    }

    static func loginShellEnvironment(base: [String: String]) -> [String: String] {
        base.merging([resolvingVariable: "1"]) { _, resolving in resolving }
    }

    /// A `.zshrc` that takes the shell over, a multiplexer autostart that
    /// fails without a terminal and exits or an `exec` into another shell,
    /// ends the interactive run before the marker. The plain login run still
    /// finds the `~/.zprofile` exports then, so it is tried whenever the
    /// interactive one gives no dump.
    static func exportsFromLoginShell(shellPath: String,
                                      timeout: TimeInterval = loginShellTimeout,
                                      baseEnvironment: [String: String] = ProcessInfo.processInfo.environment)
        -> [String: String] {
        guard !shellPath.isEmpty else { return [:] }
        let environment = loginShellEnvironment(base: baseEnvironment)
        for interactive in [true, false] {
            let command = loginShellCommand(shellPath: shellPath, interactive: interactive)
            let result = BoundedProcessRunner.run(command.executable, command.arguments,
                                                  timeout: timeout, maxOutputBytes: 1024 * 1024,
                                                  environment: environment)
            guard result.status == 0, !result.timedOut,
                  result.output.range(of: Data(dumpMarker.utf8)) != nil else { continue }
            return passthrough(parse(nullSeparated: result.output))
        }
        return [:]
    }

    /// Everything up to and including the marker is whatever the startup files
    /// wrote: a greeting, a warning about a tool that is gone, or a shell's own
    /// "no job control" line, since stdout and stderr arrive on the one pipe.
    /// The last occurrence is the real one: an earlier one can only be startup
    /// echoing it, which belongs to the part being dropped. An entry whose name
    /// is not an identifier is still dropped, which is what is left of a
    /// greeting from a shell that never reached the marker at all.
    static func parse(nullSeparated data: Data) -> [String: String] {
        var environment: [String: String] = [:]
        var dump = data[...]
        if let marker = data.range(of: Data(dumpMarker.utf8), options: .backwards) {
            dump = data[marker.upperBound...]
        }
        for entry in dump.split(separator: 0) {
            guard let separator = entry.firstIndex(of: UInt8(ascii: "=")) else { continue }
            let name = String(decoding: entry[entry.startIndex..<separator], as: UTF8.self)
            guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { continue }
            environment[name] = String(decoding: entry[entry.index(after: separator)...], as: UTF8.self)
        }
        return environment
    }
}
