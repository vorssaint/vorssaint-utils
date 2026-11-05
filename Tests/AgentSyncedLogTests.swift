// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation

/// Logs Codex compressed and logs synced from another computer: decoded
/// exactly, counted as usage, and never followed as work going on here.
enum AgentSyncedLogTests {
    static func run(_ suite: TestSuite) {
        decoding(suite)
        damage(suite)
        roots(suite)
        projectNames(suite)
        folders(suite)
        let folder = AgentLogRoot.canonical(FileManager.default.temporaryDirectory)
            .appending(path: "vorss-synced-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { suite.expect(false, "the synced log fixture creates its folder: \(error)"); return }
        compressedLogs(suite, folder: folder)
        syncedLogs(suite, folder: folder)
        startup(suite, folder: folder)
    }

    private static let fixtures = URL(fileURLWithPath: "Tests/Fixtures/AgentZstd")

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A frame of stored blocks: enough of the format to write any log
    /// compressed, as the tests need, without an encoder.
    static func stored(_ data: Data) -> Data {
        // No content size, and a 128 KiB window.
        var frame = Data([0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x38])
        var offset = 0
        repeat {
            let size = min(AgentZstd.blockMaximum, data.count - offset)
            let header = size << 3 | (offset + size == data.count ? 1 : 0)
            frame.append(contentsOf: [UInt8(header & 0xFF), UInt8(header >> 8 & 0xFF), UInt8(header >> 16 & 0xFF)])
            frame.append(data.subdata(in: offset..<offset + size))
            offset += size
        } while offset < data.count
        return frame
    }

    private static func write(_ text: String, to file: URL, compressed: Bool = false) -> Bool {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = Data(text.utf8)
            try (compressed ? stored(data) : data).write(to: file)
            return true
        } catch { return false }
    }

    // MARK: Decoding

    private static func decoding(_ suite: TestSuite) {
        // Written by the reference encoder: a log-like text with a 4 KiB
        // window, incompressible bytes, repeats, a tiny frame, and two frames
        // around a skippable one.
        let cases: [(name: String, count: Int, digest: String)] = [
            ("text", 170_648, "94dda4531edb6e3b7e7e8801e104059ceb75055bf273420fb296cf49f99a833b"),
            ("random", 20_000, "b02e06e294b865f5dbfb3bfa829a47633732824bf6db8647d74103c5e8a1d936"),
            ("zeros", 200_000, "4cbbd9be0cba685835755f827758705db5a413c5494c34262cd25946a73e7582"),
            ("small", 12, "7a7c5e8d4ca612fd27d2bd63dca6d85cb759b6366abf6556cbcd483db9416aac"),
            ("frames", 200_012, "f7d55e9934da98152f729c5566d0bda916b64be25d227d6b2bb6a17b4855996e"),
        ]
        for item in cases {
            let url = fixtures.appending(path: "\(item.name).zst")
            guard let data = try? Data(contentsOf: url) else {
                suite.expect(false, "the \(item.name) fixture is readable")
                continue
            }
            let whole = try? AgentZstd.decompress(data)
            suite.expect(whole?.count == item.count && whole.map(digest) == item.digest,
                         "\(item.name): decodes to exactly what the reference encoder compressed")
            // Small pieces slide the window many times over.
            var pieces = Data()
            var calls = 0
            let finished = try? AgentZstd.decode(file: url.path, piece: 1000) { piece in
                pieces.append(contentsOf: piece)
                calls += 1
            }
            // The text's 4 KiB window makes blocks of at most 4 KiB.
            suite.expect(finished == true && digest(pieces) == item.digest && (item.name != "text" || calls > 10),
                         "\(item.name): decodes the same from its file, handed over in pieces")
        }
        var pieces = 0
        let stopped = try? AgentZstd.decode(file: fixtures.appending(path: "text.zst").path, piece: 1000,
                                            shouldContinue: { pieces < 3 }) { _ in pieces += 1 }
        suite.expect(stopped == false, "a stop ends decoding before the end")
        let sample = Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ $0 >> 9) })
        suite.expect((try? AgentZstd.decompress(stored(sample))) == sample && (try? AgentZstd.decompress(stored(Data()))) == Data(),
                     "stored blocks decode across several blocks, and to nothing when empty")
    }

    private static func damage(_ suite: TestSuite) {
        guard let text = try? Data(contentsOf: fixtures.appending(path: "text.zst")) else {
            suite.expect(false, "the text fixture is readable")
            return
        }
        for cut in [1, 3, 5, 9, 100, text.count / 2, text.count - 1] {
            var failed = false
            do { _ = try AgentZstd.decompress(text.prefix(cut)) } catch { failed = true }
            suite.expect(failed, "a log cut to \(cut) bytes fails rather than ending early")
        }
        // Damage anywhere either fails or decodes something; it never
        // reads or writes outside the buffers.
        var damaged = 0
        for index in 0..<400 {
            var bad = text
            let at = 4 + (index &* 7919) % (text.count - 4)
            bad[at] ^= UInt8(1 + index % 255)
            if (try? AgentZstd.decompress(bad)) == nil { damaged += 1 }
        }
        suite.expect(damaged > 0, "damaged frames are refused, without a crash")
        suite.expect((try? AgentZstd.decompress(Data("not zstd at all".utf8))) == nil, "data that is not Zstandard is refused")
        var unsupported: AgentZstd.Failure?
        do { _ = try AgentZstd.decompress(Data([0x28, 0xB5, 0x2F, 0xFD, 0x01, 0x38, 0x07, 0x01, 0x00, 0x00])) }
        catch { unsupported = error as? AgentZstd.Failure }
        suite.expect(unsupported == .unsupported, "a frame that needs a dictionary is refused as unsupported")
        // A frame claiming less content than its window, then writing more.
        var shortClaim = Data([0x28, 0xB5, 0x2F, 0xFD, 0x40, 0x38, 0x00, 0x00])
        for block in 0..<4 {
            let size = AgentZstd.blockMaximum
            let header = size << 3 | (block == 3 ? 1 : 0)
            shortClaim.append(contentsOf: [UInt8(header & 0xFF), UInt8(header >> 8 & 0xFF), UInt8(header >> 16 & 0xFF)])
            shortClaim.append(Data(repeating: UInt8(block), count: size))
        }
        suite.expect((try? AgentZstd.decompress(shortClaim))?.count == 4 * AgentZstd.blockMaximum,
                     "output past the size a frame claims stays inside the buffer")
    }

    // MARK: Folders

    private static func roots(_ suite: TestSuite) {
        let home = URL(fileURLWithPath: "/Users/someone")
        guard let codex = AgentLogRoot.all(home: home).first(where: { $0.provider == .codex }),
              let claude = AgentLogRoot.all(home: home).first(where: { $0.provider == .claude }) else {
            suite.expect(false, "the agents have log roots")
            return
        }
        let day = codex.url.appending(path: "2026/10/01")
        suite.expect(codex.accepts(day.appending(path: "rollout-a.jsonl.zst").path)
                        && codex.accepts(day.appending(path: "rollout-a.jsonl").path),
                     "Codex's folder admits its logs, compressed or not")
        suite.expect(!claude.accepts(claude.url.appending(path: "project/session.jsonl.zst").path)
                        && !codex.accepts(day.appending(path: "rollout-a.zst").path),
                     "only Codex's compressed session logs are admitted")

        let synced = AgentLogRoot.synced(["/Volumes/Sync/pc", "/Volumes/Sync/pc/", " ", "/"])
        suite.expect(synced.count == 2 && synced.allSatisfy(\.synced) && Set(synced.map(\.provider)) == [.claude, .codex],
                     "a synced folder stands for Claude Code and Codex once, and the disk's root never does")
        let syncedCodex = synced.first { $0.provider == .codex }
        let syncedClaude = synced.first { $0.provider == .claude }
        let base = "/Volumes/Sync/pc/"
        let rollout = base + "codex-sessions/2026/10/01/rollout-2026-10-01T10-00-00-abc.jsonl"
        let session = base + "claude-projects/C--code-app/0b1c.jsonl"
        let subagent = base + "claude-projects/C--code-app/0b1c/subagents/agent-1.jsonl"
        suite.expect(syncedCodex?.accepts(rollout) == true && syncedCodex?.accepts(rollout + ".zst") == true
                        && syncedClaude?.accepts(rollout) == false && syncedClaude?.accepts(rollout + ".zst") == false,
                     "a synced folder's Codex logs are told apart by their rollout names")
        suite.expect(syncedClaude?.accepts(session) == true && syncedClaude?.accepts(subagent) == true
                        && syncedCodex?.accepts(session) == false,
                     "a synced folder's other logs are Claude Code's, subagents included")
        suite.expect(AgentLogReader.isLog(rollout + ".zst") && !AgentLogReader.isLog(base + "notes.zst"),
                     "file events for compressed logs are read")
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

    private static let codexLines: [String] = {
        let time = Date().timeIntervalSince1970
        return [
            #"{"type":"session_meta","timestamp":\#(time),"payload":{"id":"pc","cwd":"C:\\code\\CaratOS"}}"#,
            #"{"type":"turn_context","timestamp":\#(time),"payload":{"model":"gpt-5.2-codex"}}"#,
            #"{"type":"event_msg","timestamp":\#(time),"payload":{"type":"task_started"}}"#,
            #"{"type":"response_item","timestamp":\#(time),"payload":{"type":"function_call","call_id":"c1","name":"shell"}}"#,
            #"{"type":"token_usage_record","timestamp":\#(time),"payload":{"response_id":"r1","usage":{"input_tokens":10,"output_tokens":2}}}"#,
            #"{"type":"token_usage_record","timestamp":\#(time),"payload":{"response_id":"r1","usage":{"input_tokens":10,"output_tokens":5}}}"#,
            #"{"type":"event_msg","timestamp":\#(time),"payload":{"type":"token_count","rate_limits":{"plan_type":"pro","primary":{"used_percent":42,"window_minutes":300}}}}"#,
        ]
    }()

    private static let claudeLines: [String] = {
        let time = Date().timeIntervalSince1970
        return [
            #"{"type":"user","timestamp":\#(time),"sessionId":"pc","cwd":"C:\\code\\veda-muse","message":{"content":"work"}}"#,
            #"{"type":"assistant","timestamp":\#(time),"sessionId":"pc","cwd":"C:\\code\\veda-muse","requestId":"q","message":{"id":"m","model":"claude-opus-5-5","stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":5}}}"#,
        ]
    }()

    private static func compressedLogs(_ suite: TestSuite, folder: URL) {
        let text = codexLines.joined(separator: "\n") + "\n"
        let plain = folder.appending(path: "plain/rollout-plain.jsonl")
        let compressed = folder.appending(path: "zst/rollout-zst.jsonl.zst")
        guard write(text, to: plain), write(text, to: compressed, compressed: true) else {
            suite.expect(false, "the compressed log fixture writes its logs")
            return
        }
        let live = AgentUsageReadTests.Host()
        live.store.reportsTransitions = true
        live.read(plain.path, provider: .codex)
        let host = AgentUsageReadTests.Host()
        host.store.reportsTransitions = true
        suite.expect(host.read(compressed.path, provider: .codex), "a compressed Codex log gives its usage")
        suite.expect(host.store.records == live.store.records && host.store.records.count == 1
                        && host.store.records.first?.project == "CaratOS",
                     "a compressed log counts what the same log uncompressed does, its duplicate lines merged")
        suite.expect(!live.store.turns.isEmpty && host.store.turns.isEmpty && host.store.waiting.isEmpty
                        && host.store.attention.isEmpty && host.events.isEmpty && host.starts.isEmpty
                        && host.store.limits.isEmpty && host.store.codexPlan == nil,
                     "a compressed log is history: no turn, wait, sound or limit of its own")
        let size = (try? FileManager.default.attributesOfItem(atPath: compressed.path)[.size] as? Int) ?? -1
        suite.expect(host.cursors[compressed.path]?.history == true && host.cursors[compressed.path]?.offset == UInt64(size),
                     "a compressed log is read whole, once")
        suite.expect(!host.read(compressed.path, provider: .codex), "an unchanged compressed log is not read again")

        // Cut short, as while it is still being written.
        let cut = folder.appending(path: "zst/rollout-cut.jsonl.zst")
        let cutData = stored(Data(text.utf8)).prefix(40)
        guard (try? cutData.write(to: cut)) != nil else {
            suite.expect(false, "the damaged log fixture writes")
            return
        }
        let damaged = AgentUsageReadTests.Host()
        damaged.read(cut.path, provider: .codex)
        suite.expect(damaged.cursors[cut.path]?.offset == UInt64(cutData.count) && !damaged.read(cut.path, provider: .codex),
                     "a damaged compressed log is left alone until it changes")
        guard (try? stored(Data(text.utf8)).write(to: cut)) != nil else { return }
        suite.expect(damaged.read(cut.path, provider: .codex) && damaged.store.records.count == 1,
                     "once complete, the same log is read again and counted once")
    }

    private static func syncedLogs(_ suite: TestSuite, folder: URL) {
        let synced = folder.appending(path: "remote/pc")
        let claude = synced.appending(path: "claude-projects/C--code-veda-muse/pc.jsonl")
        let codex = synced.appending(path: "codex-sessions/2026/11/02/rollout-pc.jsonl")
        guard write(claudeLines.joined(separator: "\n") + "\n", to: claude),
              write(codexLines.joined(separator: "\n") + "\n", to: codex) else {
            suite.expect(false, "the synced log fixture writes its logs")
            return
        }
        let host = AgentUsageReadTests.Host()
        host.store.reportsTransitions = true
        host.syncedRoots = AgentLogRoot.synced([synced.path])
        suite.expect(host.read(claude.path, provider: .claude) && host.read(codex.path, provider: .codex),
                     "synced logs give their usage")
        suite.expect(host.store.records.count == 2 && Set(host.store.records.map(\.project)) == ["veda-muse", "CaratOS"],
                     "synced usage keeps the projects its Windows folders name")
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

    /// The page shows once this Mac's logs are read; synced and compressed
    /// history joins after.
    private static func startup(_ suite: TestSuite, folder: URL) {
        let home = folder.appending(path: "home")
        let synced = folder.appending(path: "startup-remote")
        let time = Date().timeIntervalSince1970
        let localLine = #"{"type":"assistant","timestamp":\#(time),"sessionId":"mac","requestId":"mq","message":{"id":"mm","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":7}}}"#
        guard write(localLine + "\n", to: home.appending(path: ".claude/projects/app/mac.jsonl")),
              write(claudeLines.joined(separator: "\n") + "\n", to: synced.appending(path: "projects/pc.jsonl")),
              write(codexLines.joined(separator: "\n") + "\n",
                    to: home.appending(path: ".codex/sessions/2026/11/02/rollout-old.jsonl.zst"), compressed: true) else {
            suite.expect(false, "the startup fixture writes its logs")
            return
        }
        let host = AgentUsageReadTests.Host()
        host.home = home
        host.start(session: 1, providers: [.claude, .codex], synced: [synced.path], cancellation: AgentUsageReadTests.Cancellation())
        let first = host.publications.first
        suite.expect(first?.loaded == true && first.map { $0.usage(.today).total.requests } == 1,
                     "the page shows with this Mac's own logs before any history is decoded")
        suite.expect(host.store.records.count == 3 && host.store.turns.isEmpty,
                     "compressed and synced history is read after, as usage only")
        suite.expect(Set(host.watchedRoots.map(\.url.path)).contains(AgentLogRoot.canonical(synced).path),
                     "synced folders are watched for what arrives later")
    }
}
