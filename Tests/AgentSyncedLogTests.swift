// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Claude Code logs synced from another computer: found however deep they
/// sit, counted once as usage, and never followed as work going on here.
enum AgentSyncedLogTests {
    static func run(_ suite: TestSuite) {
        roots(suite)
        projectNames(suite)
        folders(suite)
        let folder = AgentLogRoot.canonical(FileManager.default.temporaryDirectory)
            .appending(path: "vorss-synced-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { suite.expect(false, "the synced log fixture creates its folder: \(error)"); return }
        syncedLogs(suite, folder: folder)
        profiles(suite, folder: folder)
        startup(suite, folder: folder)
    }

    private static func write(_ text: String, to file: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
            return true
        } catch { return false }
    }

    // MARK: Folders

    private static func roots(_ suite: TestSuite) {
        let home = URL(fileURLWithPath: "/Users/someone")
        let all = AgentLogRoot.all(home: home)
        suite.expect(all.count == 2 && all.allSatisfy { $0.provider == .claude && !$0.synced },
                     "Claude Code's own folders are the only log roots")
        guard let claude = all.first else { return }
        suite.expect(claude.accepts(claude.url.appending(path: "project/session.jsonl").path)
                        && !claude.accepts(claude.url.appending(path: "project/session.jsonl.zst").path)
                        && !claude.accepts(claude.url.appending(path: "project/notes.txt").path),
                     "only Claude Code's session logs are admitted")

        let synced = AgentLogRoot.synced(["/Volumes/Sync/pc", "/Volumes/Sync/pc/", " ", "/"])
        suite.expect(synced.count == 1 && synced.allSatisfy(\.synced) && synced.first?.provider == .claude,
                     "a synced folder stands for Claude Code once, and the disk's root never does")
        guard let root = synced.first else { return }
        let base = "/Volumes/Sync/pc/"
        let session = base + "claude-projects/C--code-app/0b1c.jsonl"
        let subagent = base + "claude-projects/C--code-app/0b1c/subagents/agent-1.jsonl"
        let profile = base + ".claude-seat1/projects/C--code-app/0b1c.jsonl"
        let version = base + ".stversions/.claude/projects/C--code-app/0b1c~20261101-120000.jsonl"
        let marker = base + ".claude/projects/.stfolder/0b1c.jsonl"
        suite.expect(root.accepts(session) && root.accepts(subagent) && root.accepts(profile),
                     "a synced folder's logs are Claude Code's, subagents and every profile's tree included")
        suite.expect(!root.accepts(version) && !root.accepts(marker) && !root.accepts(base + "notes.txt"),
                     "a sync tool's own folders and other files are left out")
        suite.expect(AgentLogReader.isLog(session) && !AgentLogReader.isLog(session + ".zst"),
                     "file events are read only for session logs")
    }

    private static func projectNames(_ suite: TestSuite) {
        let names = [
            ("C:\\Users\\me\\code\\CaratOS", "CaratOS"),
            ("C:\\Users\\me\\code\\app\\", "app"),
            ("D:\\work\\app\\.claude\\worktrees\\fix-1", "app"),
            ("C:/Users/me/code/veda-muse", "veda-muse"),
            ("\\\\server\\share\\mpm", "mpm"),
            ("C:\\", ""),
            ("/Users/me/code/app", "app"),
            ("/Users/me/code/app/.claude/worktrees/fix", "app"),
            ("/Users/me/odd\\name", "odd\\name"),
        ]
        for (path, name) in names {
            suite.expect(AgentLogParser.projectName(path) == name, "the project of \(path) is “\(name)”")
        }
    }

    private static func folders(_ suite: TestSuite) {
        suite.expect(NotchAgentSupport.parseSyncedFolders("") == [], "no synced folders by default")
        suite.expect(NotchAgentSupport.parseSyncedFolders(" /a \n\n/b\r\n/a\n") == ["/a", "/b"],
                     "saved folders are trimmed, kept in order and listed once")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchAgentsSyncedFolders] as? String == "",
                     "the synced folders start empty and are backed up with the other settings")
    }

    // MARK: Reading

    private static let claudeLines: [String] = {
        let time = Date().timeIntervalSince1970
        return [
            #"{"type":"user","timestamp":\#(time),"sessionId":"pc","cwd":"C:\\code\\veda-muse","message":{"content":"work"}}"#,
            #"{"type":"assistant","timestamp":\#(time),"sessionId":"pc","cwd":"C:\\code\\veda-muse","requestId":"q","message":{"id":"m","model":"claude-opus-5-5","stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":5}}}"#,
        ]
    }()

    private static func syncedLogs(_ suite: TestSuite, folder: URL) {
        let synced = folder.appending(path: "remote/pc")
        let claude = synced.appending(path: ".claude/projects/C--code-veda-muse/pc.jsonl")
        guard write(claudeLines.joined(separator: "\n") + "\n", to: claude) else {
            suite.expect(false, "the synced log fixture writes its log")
            return
        }
        let host = AgentUsageReadTests.Host()
        host.store.reportsTransitions = true
        host.syncedRoots = AgentLogRoot.synced([synced.path])
        suite.expect(host.read(claude.path, provider: .claude), "synced logs give their usage")
        suite.expect(host.store.records.count == 1 && host.store.records.first?.project == "veda-muse",
                     "synced usage keeps the project its Windows folder names")
        suite.expect(host.store.turns.isEmpty && host.store.waiting.isEmpty && host.store.attention.isEmpty
                        && host.events.isEmpty && host.starts.isEmpty && host.store.limits.isEmpty,
                     "a session on another computer never shows as running on this Mac")

        let local = AgentUsageReadTests.Host()
        local.store.reportsTransitions = true
        let here = folder.appending(path: "local/pc.jsonl")
        guard write(claudeLines.joined(separator: "\n") + "\n", to: here) else { return }
        local.read(here.path, provider: .claude)
        suite.expect(!local.store.turns.isEmpty, "the same lines in this Mac's own log are work going on")
    }

    /// One synced folder holding several Claude profiles' `projects` trees,
    /// as when each profile is its own Syncthing folder under one parent.
    private static func profiles(_ suite: TestSuite, folder: URL) {
        let synced = folder.appending(path: "profiles")
        let usual = synced.appending(path: ".claude/projects/C--code-veda-muse/s1.jsonl")
        let seat = synced.appending(path: ".claude-seat1/projects/C--code-veda-muse/s2.jsonl")
        // The same session synced a second time, from another profile's folder.
        let again = synced.appending(path: ".claude-dexter/projects/C--code-veda-muse/s1.jsonl")
        let version = synced.appending(path: ".stversions/.claude/projects/C--code-veda-muse/s1~20261101-120000.jsonl")
        let time = Date().timeIntervalSince1970
        let seatLine = #"{"type":"assistant","timestamp":\#(time),"sessionId":"s2","cwd":"C:\\code\\veda-muse","requestId":"q2","message":{"id":"m2","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":7}}}"#
        let lines = claudeLines.joined(separator: "\n") + "\n"
        guard write(lines, to: usual), write(seatLine + "\n", to: seat), write(lines, to: again),
              write(lines, to: version) else {
            suite.expect(false, "the profiles fixture writes its logs")
            return
        }
        let roots = AgentLogRoot.synced([synced.path])
        let found = AgentLogReader.discover(roots, since: .distantPast).map(\.path)
        suite.expect(Set(found) == [usual.path, seat.path, again.path] && found.count == 3,
                     "every profile's tree in a synced folder is found, however deep, and a sync tool's old versions are not")
        let host = AgentUsageReadTests.Host()
        host.syncedRoots = roots
        for path in found { host.read(path, provider: .claude) }
        suite.expect(host.store.records.count == 2
                        && host.store.records.map(\.tokens.total).reduce(0, +) == 25,
                     "a response two synced logs hold, by its message and request ids, counts once")
        suite.expect(host.store.files(sharingWith: [usual.path]) == [usual.path, again.path],
                     "the response remembers both logs that hold it")
    }

    /// The page shows once this Mac's logs are read; synced history joins after.
    private static func startup(_ suite: TestSuite, folder: URL) {
        let home = folder.appending(path: "home")
        let synced = folder.appending(path: "startup-remote")
        let time = Date().timeIntervalSince1970
        let localLine = #"{"type":"assistant","timestamp":\#(time),"sessionId":"mac","requestId":"mq","message":{"id":"mm","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":7}}}"#
        guard write(localLine + "\n", to: home.appending(path: ".claude/projects/app/mac.jsonl")),
              write(claudeLines.joined(separator: "\n") + "\n", to: synced.appending(path: "projects/pc.jsonl")) else {
            suite.expect(false, "the startup fixture writes its logs")
            return
        }
        let host = AgentUsageReadTests.Host()
        host.home = home
        host.start(session: 1, providers: [.claude], synced: [synced.path], cancellation: AgentUsageReadTests.Cancellation())
        let first = host.publications.first
        suite.expect(first?.loaded == true && first.map { $0.usage(.today).total.requests } == 1,
                     "the page shows with this Mac's own logs before any synced history is read")
        suite.expect(host.store.records.count == 2 && host.store.turns.isEmpty,
                     "synced history is read after, as usage only")
        suite.expect(Set(host.watchedRoots.map(\.url.path)).contains(AgentLogRoot.canonical(synced).path),
                     "synced folders are watched for what arrives later")
    }
}
