// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Connects Claude Code to the "needs you" state on the person's request: a
/// small script next to Claude Code's files, run by hooks in its user
/// settings. Every other setting and hook in that file is kept, a copy is
/// saved before the first change, and a file that is not valid JSON is never
/// touched. Removing takes out only the entries marked as Vorssaint's.
enum ClaudeHookSetup {
    enum Status: Equatable {
        case connected
        /// Entries or the script are missing or from an older version.
        case notConnected
        /// Claude Code's settings could not be read as JSON.
        case unreadable
    }

    enum Failure: Error, Equatable {
        case unreadableSettings, writeFailed
    }

    /// Ends every command Vorssaint adds, so its entries are found again
    /// without touching anyone else's.
    static let marker = "# vorssaint-needs-input"

    /// The events and what the script does on each. A question or a
    /// permission prompt sets the wait; an answer, a tool finishing or the
    /// turn or session ending clears it.
    static let entries: [(event: String, matcher: String?, action: String)] = [
        ("PreToolUse", "AskUserQuestion", "set"),
        ("PermissionRequest", nil, "set"),
        ("Notification", nil, "set"),
        ("PostToolUse", nil, "clear"),
        ("PostToolUseFailure", nil, "clear"),
        ("UserPromptSubmit", nil, "clear"),
        ("Stop", nil, "clear"),
        ("SessionEnd", nil, "clear"),
    ]

    static func settingsURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: ".claude/settings.json")
    }

    static func scriptURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: ".claude/vorssaint/needs-input-hook.sh")
    }

    static func command(script: URL, action: String) -> String {
        "'\(script.path.replacingOccurrences(of: "'", with: "'\\''"))' \(action) \(marker)"
    }

    // MARK: Settings, as JSON objects

    static func isOurs(_ hook: Any) -> Bool {
        ((hook as? [String: Any])?["command"] as? String)?.hasSuffix(marker) == true
    }

    /// Whether every entry is present with this script.
    static func isConnected(_ settings: [String: Any], script: URL) -> Bool {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        return entries.allSatisfy { entry in
            let wanted = command(script: script, action: entry.action)
            return (hooks[entry.event] as? [Any] ?? []).contains { group in
                guard let group = group as? [String: Any],
                      (group["matcher"] as? String) == entry.matcher else { return false }
                return (group["hooks"] as? [Any] ?? []).contains {
                    ($0 as? [String: Any])?["command"] as? String == wanted
                }
            }
        }
    }

    /// The settings without any of Vorssaint's entries; a group left empty
    /// and an event left empty go too, nothing else changes.
    static func removing(from settings: [String: Any]) -> [String: Any] {
        var result = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in hooks {
            guard let groups = value as? [Any] else { continue }
            var kept: [Any] = []
            var changed = false
            for group in groups {
                guard var object = group as? [String: Any], let list = object["hooks"] as? [Any] else {
                    kept.append(group)
                    continue
                }
                let others = list.filter { !isOurs($0) }
                if others.count == list.count { kept.append(group); continue }
                changed = true
                if !others.isEmpty {
                    object["hooks"] = others
                    kept.append(object)
                }
            }
            guard changed else { continue }
            if kept.isEmpty { hooks[event] = nil } else { hooks[event] = kept }
        }
        if hooks.isEmpty { result["hooks"] = nil } else { result["hooks"] = hooks }
        return result
    }

    /// The settings with Vorssaint's entries, replacing any older ones.
    static func adding(to settings: [String: Any], script: URL) -> [String: Any] {
        var result = removing(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        for entry in entries {
            var group: [String: Any] = ["hooks": [["type": "command",
                                                   "command": command(script: script, action: entry.action),
                                                   "timeout": 5]]]
            if let matcher = entry.matcher { group["matcher"] = matcher }
            hooks[entry.event] = (hooks[entry.event] as? [Any] ?? []) + [group]
        }
        result["hooks"] = hooks
        return result
    }

    // MARK: Files

    /// Reads Claude Code's settings; an absent file reads as empty.
    static func readSettings(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else {
            return FileManager.default.fileExists(atPath: url.path) ? nil : [:]
        }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func status(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Status {
        guard let settings = readSettings(at: settingsURL(home: home)) else { return .unreadable }
        let script = scriptURL(home: home)
        let current = (try? String(contentsOf: script, encoding: .utf8)) == scriptSource
        return current && isConnected(settings, script: script) ? .connected : .notConnected
    }

    static func connect(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let url = settingsURL(home: home)
        guard let settings = readSettings(at: url) else { throw Failure.unreadableSettings }
        let script = scriptURL(home: home)
        do {
            try FileManager.default.createDirectory(at: script.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try scriptSource.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            try backUpOnce(url)
            try write(adding(to: settings, script: script), to: url)
        } catch {
            throw Failure.writeFailed
        }
    }

    static func disconnect(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let url = settingsURL(home: home)
        guard let settings = readSettings(at: url) else { throw Failure.unreadableSettings }
        let cleaned = removing(from: settings)
        do {
            if !NSDictionary(dictionary: cleaned).isEqual(to: settings) {
                try backUpOnce(url)
                try write(cleaned, to: url)
            }
            try? FileManager.default.removeItem(at: scriptURL(home: home))
            // Any wait still on disk would otherwise linger for six hours.
            try? FileManager.default.removeItem(at: AgentInputSupport.folder(home: home))
        } catch {
            throw Failure.writeFailed
        }
    }

    /// The person's own settings as they were before Vorssaint first changed
    /// them; later changes leave that copy alone.
    private static func backUpOnce(_ url: URL) throws {
        let backup = url.deletingLastPathComponent().appending(path: "settings.json.before-vorssaint")
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path), !fileManager.fileExists(atPath: backup.path) else { return }
        try fileManager.copyItem(at: url, to: backup)
    }

    private static func write(_ settings: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (data + Data("\n".utf8)).write(to: url, options: .atomic)
    }

    /// The script Claude Code runs. It reads the event from its input,
    /// writes or removes one file named after the session, and always exits
    /// 0 so it can never hold Claude Code up. It never stores a prompt.
    static let scriptSource = #"""
    #!/bin/bash
    # Written by Vorssaint: tells it when Claude Code waits for an answer or a
    # permission. Remove it from Vorssaint's AI settings (Remove), not by hand.
    # Stores only the session id, reason, tool name, folder, app id and time.
    DIR="$HOME/.claude/vorssaint/needs-input"
    INPUT=$(cat)
    field() { printf '%s' "$INPUT" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null; }
    SESSION=$(field session_id)
    [[ "$SESSION" =~ ^[0-9a-fA-F-]{36}$ ]] || exit 0
    FILE="$DIR/$SESSION.json"
    case "${1:-}" in
      clear)
        [ -e "$FILE" ] && rm -f "$FILE"
        ;;
      set)
        EVENT=$(field hook_event_name)
        TOOL=$(field tool_name)
        if [ "$EVENT" = "Notification" ]; then
          MESSAGE=$(field message)
          case "$MESSAGE" in *permission*) ;; *) exit 0 ;; esac
          case "$MESSAGE" in *AskUserQuestion*) TOOL="AskUserQuestion" ;; esac
          [ -e "$FILE" ] && exit 0
        fi
        REASON=permission
        [ "$TOOL" = "AskUserQuestion" ] && REASON=question
        mkdir -p "$DIR"
        TMP="$DIR/.$SESSION.tmp"
        rm -f "$TMP"
        # plutil ships with every Mac; it builds a plist, then writes it as JSON.
        /usr/bin/plutil -create xml1 "$TMP" 2>/dev/null \
          && /usr/bin/plutil -insert session_id -string "$SESSION" "$TMP" \
          && /usr/bin/plutil -insert reason -string "$REASON" "$TMP" \
          && /usr/bin/plutil -insert tool -string "$TOOL" "$TMP" \
          && /usr/bin/plutil -insert cwd -string "$(field cwd)" "$TMP" \
          && /usr/bin/plutil -insert app -string "${__CFBundleIdentifier:-}" "$TMP" \
          && /usr/bin/plutil -insert since -float "$(date +%s)" "$TMP" \
          && /usr/bin/plutil -convert json "$TMP" \
          && mv -f "$TMP" "$FILE"
        rm -f "$TMP"
        ;;
    esac
    exit 0
    """# + "\n"
}
