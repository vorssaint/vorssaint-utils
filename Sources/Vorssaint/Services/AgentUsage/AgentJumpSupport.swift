// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The terminal a session runs in, by how it can be brought forward.
enum AgentTerminalKind: Equatable {
    /// Scriptable by tty: the exact tab is selected.
    case terminal, iTerm2
    /// Scriptable by working folder: the first terminal in it is focused.
    case ghostty
    /// The window whose title names the session's folder comes forward;
    /// VS Code exposes nothing that tells its terminal tabs apart.
    case vscode
    case other

    init(bundleIdentifier: String?) {
        switch bundleIdentifier {
        case "com.apple.Terminal": self = .terminal
        case "com.googlecode.iterm2": self = .iTerm2
        case "com.mitchellh.ghostty": self = .ghostty
        case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92": self = .vscode
        default: self = .other
        }
    }
}

/// A running `codex` process, as the kernel reports it.
struct AgentSessionProcess: Equatable {
    let pid: Int32
    let cwd: String?
    let started: Date
}

enum AgentJumpSupport {
    /// The folder and start time of a Codex rollout, from its first line.
    static func codexMeta(firstLine: Data) -> (cwd: String, started: Date)? {
        guard let json = (try? JSONSerialization.jsonObject(with: firstLine)) as? [String: Any],
              json["type"] as? String == "session_meta",
              let cwd = (json["payload"] as? [String: Any])?["cwd"] as? String, !cwd.isEmpty,
              let started = AgentLogParser.timestamp(json["timestamp"])
        else { return nil }
        return (cwd, started)
    }

    /// Codex keeps no pid, so the process in the rollout's folder that started
    /// closest to it wins.
    // ponytail: two codex in one folder resuming the same rollout are indistinguishable
    // without a pid in the rollout.
    static func codexProcess(cwd: String, started: Date, among processes: [AgentSessionProcess]) -> AgentSessionProcess? {
        let folder = (cwd as NSString).standardizingPath
        return processes.filter { $0.cwd.map { ($0 as NSString).standardizingPath } == folder }
            .min { abs($0.started.timeIntervalSince(started)) < abs($1.started.timeIntervalSince(started)) }
    }

    /// `devname` output such as `ttys002`; anything else never reaches a script.
    static func isTTYName(_ name: String) -> Bool {
        name.range(of: #"^tty[a-z]?[0-9A-Za-z]{1,8}$"#, options: .regularExpression) != nil
    }

    /// The VS Code window for a folder: its title (`file — folder — VS Code`
    /// by default) names the workspace root, which is the folder or one of its
    /// parents, so the deepest folder named wins.
    static func vsCodeWindow(titles: [String], cwd: String) -> Int? {
        let segments = titles.map { Set($0.components(separatedBy: " — ").map { $0.trimmingCharacters(in: .whitespaces) }) }
        var folder = (cwd as NSString).standardizingPath
        while folder != "/", folder != NSHomeDirectory(), !folder.isEmpty {
            let name = (folder as NSString).lastPathComponent
            if let index = segments.firstIndex(where: { $0.contains(name) }) { return index }
            folder = (folder as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Every script answers "yes" when it found the session, "no" otherwise.
    static func script(for kind: AgentTerminalKind, tty: String?, cwd: String?) -> String? {
        switch kind {
        case .terminal:
            guard let tty, isTTYName(tty) else { return nil }
            return """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "/dev/\(tty)" then
                            set selected of t to true
                            set frontmost of w to true
                            activate
                            return "yes"
                        end if
                    end repeat
                end repeat
                return "no"
            end tell
            """
        case .iTerm2:
            guard let tty, isTTYName(tty) else { return nil }
            return """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "/dev/\(tty)" then
                                select s
                                select t
                                select w
                                activate
                                return "yes"
                            end if
                        end repeat
                    end repeat
                end repeat
                return "no"
            end tell
            """
        case .ghostty:
            // ponytail: two terminals in one folder pick the first; Ghostty exposes no tty.
            guard let cwd, !cwd.isEmpty else { return nil }
            return """
            tell application "Ghostty"
                set found to (terminals whose working directory is \(AppleScriptRunner.literal(cwd)))
                if found is {} then return "no"
                focus item 1 of found
                activate
                return "yes"
            end tell
            """
        case .vscode, .other:
            return nil
        }
    }
}
