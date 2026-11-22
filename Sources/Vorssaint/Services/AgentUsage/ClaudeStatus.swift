// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What Claude Code hands its status line on every refresh: the model, the
/// context window, the session's cost and time, the lines it changed and more.
/// Vorssaint keeps the latest copy (see ClaudeStatusInstaller) and the AI
/// page's Claude card shows it.
struct ClaudeStatus: Equatable {
    var model: String?
    var directory: String?
    var branch: String?
    var contextPercent: Double?
    var contextSize: Int?
    var tokensIn: Int?
    var tokensOut: Int?
    var cacheRead: Int?
    var cost: Double?
    var wallMilliseconds: Int?
    var apiMilliseconds: Int?
    var linesAdded: Int?
    var linesRemoved: Int?
    var version: String?
    var outputStyle: String?
    var agent: String?
    /// The plan allowances Claude Code itself reports: five hours and the week.
    var fiveHourPercent: Double?
    var fiveHourResetsAt: Date?
    var weeklyPercent: Double?
    var weeklyResetsAt: Date?
    var observedAt: Date

    static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.vorssaint.utils/claude-status", isDirectory: true)
    }

    /// The most recent status, if one arrived in the last day.
    static func latest(now: Date = Date()) -> ClaudeStatus? {
        let url = directoryURL.appendingPathComponent("latest.json")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date, now.timeIntervalSince(modified) < 86_400,
              let data = try? Data(contentsOf: url), data.count < 1_048_576,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return ClaudeStatus(object, observedAt: modified)
    }

    init(_ object: [String: Any], observedAt: Date) {
        func dict(_ key: String, in source: [String: Any]) -> [String: Any]? { source[key] as? [String: Any] }
        func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
        func double(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
        let context = dict("context_window", in: object)
        let cost = dict("cost", in: object)
        model = dict("model", in: object)?["display_name"] as? String
        directory = dict("workspace", in: object)?["current_dir"] as? String ?? object["cwd"] as? String
        contextPercent = double(context?["used_percentage"])
        contextSize = int(context?["context_window_size"])
        tokensIn = int(context?["total_input_tokens"])
        tokensOut = int(context?["total_output_tokens"])
        cacheRead = int(dict("current_usage", in: context ?? [:])?["cache_read_input_tokens"])
        self.cost = double(cost?["total_cost_usd"])
        wallMilliseconds = int(cost?["total_duration_ms"])
        apiMilliseconds = int(cost?["total_api_duration_ms"])
        linesAdded = int(cost?["total_lines_added"])
        linesRemoved = int(cost?["total_lines_removed"])
        version = object["version"] as? String
        let style = dict("output_style", in: object)?["name"] as? String
        outputStyle = style == "default" ? nil : style
        agent = dict("agent", in: object)?["name"] as? String
        let rates = dict("rate_limits", in: object)
        let five = rates.flatMap { dict("five_hour", in: $0) }
        let week = rates.flatMap { dict("seven_day", in: $0) }
        fiveHourPercent = double(five?["used_percentage"])
        fiveHourResetsAt = double(five?["resets_at"]).map { Date(timeIntervalSince1970: $0) }
        weeklyPercent = double(week?["used_percentage"])
        weeklyResetsAt = double(week?["resets_at"]).map { Date(timeIntervalSince1970: $0) }
        self.observedAt = observedAt
        branch = directory.flatMap(Self.branch(in:))
    }

    /// Claude Code's own reading of the plan's allowances, as the page's limits.
    /// A window whose renewal has passed has spent an unknown amount since, so
    /// it is left out rather than shown stale.
    func limits(now: Date) -> AgentLimits? {
        var windows: [AgentLimitWindow] = []
        if let used = fiveHourPercent, fiveHourResetsAt.map({ $0 > now }) ?? true {
            windows.append(AgentLimitWindow(id: "claude.five_hour", kind: .session, minutes: 300, scope: nil,
                                            usedPercent: used, resetsAt: fiveHourResetsAt))
        }
        if let used = weeklyPercent, weeklyResetsAt.map({ $0 > now }) ?? true {
            windows.append(AgentLimitWindow(id: "claude.seven_day", kind: .weekly, minutes: 10_080, scope: nil,
                                            usedPercent: used, resetsAt: weeklyResetsAt))
        }
        guard !windows.isEmpty else { return nil }
        return AgentLimits(provider: .claude, windows: windows, observedAt: observedAt, source: .sessionLog)
    }

    /// The checked-out branch, read from the repository's HEAD file.
    private static func branch(in directory: String) -> String? {
        let head = URL(fileURLWithPath: directory).appendingPathComponent(".git/HEAD")
        guard let text = try? String(contentsOf: head, encoding: .utf8), text.hasPrefix("ref: refs/heads/") else { return nil }
        return String(text.dropFirst("ref: refs/heads/".count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Puts a small wrapper in front of the person's Claude Code status line. It
/// saves the JSON Claude Code sends, then runs the original command with the
/// same input, so the status line looks exactly as before. Turning the feature
/// off puts the original command back.
enum ClaudeStatusInstaller {
    private static let marker = "vorssaint-status-tee"

    private static var wrapperURL: URL { ClaudeStatus.directoryURL.appendingPathComponent("\(marker).pl") }
    private static var originalURL: URL { ClaudeStatus.directoryURL.appendingPathComponent("original-command.txt") }

    private static let script = """
    use strict;
    local $/; my $in = <STDIN>; $in = '' unless defined $in;
    my $dir = "$ENV{HOME}/Library/Application Support/com.vorssaint.utils/claude-status";
    mkdir $dir unless -d $dir;
    if (open(my $f, '>', "$dir/latest.json.tmp")) { print $f $in; close $f; rename "$dir/latest.json.tmp", "$dir/latest.json"; }
    open(my $o, '<', "$dir/original-command.txt") or exit 0;
    my $cmd = <$o>; close $o; $cmd = '' unless defined $cmd; $cmd =~ s/\\s+\\z//;
    exit 0 unless length $cmd;
    if (open(my $p, '|-', '/bin/sh', '-c', $cmd)) { print $p $in; close $p; }
    exit 0;
    """

    /// Wraps the status line in `settings`, keeping the original command.
    static func install(into settings: inout [String: Any]) throws {
        try FileManager.default.createDirectory(at: ClaudeStatus.directoryURL, withIntermediateDirectories: true)
        try script.write(to: wrapperURL, atomically: true, encoding: .utf8)
        var line = settings["statusLine"] as? [String: Any] ?? ["type": "command"]
        let current = line["command"] as? String ?? ""
        // Already wrapped: nothing more to do, and the original stays as saved.
        if !current.contains(marker) { try current.write(to: originalURL, atomically: true, encoding: .utf8) }
        line["type"] = "command"
        line["command"] = "/usr/bin/perl '\(wrapperURL.path)'"
        if line["refreshInterval"] == nil { line["refreshInterval"] = 60 }
        settings["statusLine"] = line
    }

    static func uninstall(from settings: inout [String: Any]) {
        guard var line = settings["statusLine"] as? [String: Any],
              (line["command"] as? String)?.contains(marker) == true else { return }
        let original = ((try? String(contentsOf: originalURL, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if original.isEmpty { settings["statusLine"] = nil } else { line["command"] = original; settings["statusLine"] = line }
    }
}
