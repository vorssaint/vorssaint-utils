// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Codex's banked resets: the answers its server gives, where the tool is
/// found, and whole conversations with a stand-in server.
enum AgentCodexResetTests {
    static func run(_ suite: TestSuite) {
        answers(suite)
        discovery(suite)
        conversations(suite)
    }

    private static func json(_ text: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    }

    // MARK: Answers

    private static func answers(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_790_629_708)
        // Shaped like a real answer, with the account left out.
        let read = json("""
        {"ordinaryUsageAllowed":true,
         "rateLimits":{"limitId":"codex","primary":{"usedPercent":89,"windowDurationMins":10080,"resetsAt":1791046700},"secondary":null},
         "rateLimitsByLimitId":{
           "codex":{"limitId":"codex","primary":{"usedPercent":89,"windowDurationMins":10080,"resetsAt":1791046700},
                    "secondary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1790640000}},
           "codex_other":{"limitId":"codex_other","primary":{"usedPercent":99,"windowDurationMins":10080}}},
         "rateLimitResetCredits":{"availableCount":3,"credits":[
           {"id":"late","resetType":"codexRateLimits","status":"available","grantedAt":1790109494,"expiresAt":1792701494,
            "title":"Full reset","description":"One free reset."},
           {"id":"soon","resetType":"codexRateLimits","status":"available","grantedAt":1788581960,"expiresAt":1791173960},
           {"id":"spent","status":"redeemed","expiresAt":1792701494},
           {"id":"gone","status":"available","expiresAt":1790000000}]},
         "accountId":null,"rateLimitUpsell":null}
        """)
        let summary = AgentCodexServer.summary(read, now: now)
        suite.expect(summary?.available == 3 && summary?.resets.map(\.id) == ["soon", "late"]
                        && summary?.nextExpiry == Date(timeIntervalSince1970: 1_791_173_960),
                     "resets list soonest to expire first, without used or expired ones, beside the account's count")
        let windows = summary?.limits?.windows
        suite.expect(summary?.limits?.source == .account && summary?.limits?.observedAt == now
                        && windows?.map(\.id) == ["codex.300", "codex.10080"] && windows?.map(\.kind) == [.session, .weekly]
                        && windows?.last?.usedPercent == 89
                        && windows?.last?.resetsAt == Date(timeIntervalSince1970: 1_791_046_700),
                     "the same answer's main allowance reads as the log's windows, and a model's own is left out")

        let single = AgentCodexServer.limits(json(#"{"rateLimits":{"limitId":null,"primary":{"usedPercent":5,"windowDurationMins":300}}}"#),
                                             observed: now)
        let other = AgentCodexServer.limits(json(#"{"rateLimits":{"limitId":"codex_other","primary":{"usedPercent":5}}}"#),
                                            observed: now)
        suite.expect(single?.windows.first?.id == "codex.300" && other == nil,
                     "an older answer's single allowance counts only when it is the main one")

        let business = AgentCodexServer.limits(json(#"{"rateLimits":{"limitId":"codex","primary":null,"secondary":null,"individualLimit":{"limit":"2500","used":"73.16","remainingPercent":97,"resetsAt":1793491201}}}"#),
                                               observed: now)
        suite.expect(business?.windows.map(\.id) == ["codex.individual"]
                        && business?.windows.first?.usedPercent == 3
                        && business?.windows.first?.resetsAt == Date(timeIntervalSince1970: 1793491201),
                     "a Business account's individual allowance is used when its legacy windows are empty")

        let countOnly = AgentCodexServer.summary(json(#"{"rateLimitResetCredits":{"availableCount":2,"credits":null}}"#), now: now)
        let none = AgentCodexServer.summary(json(#"{"rateLimitResetCredits":null}"#), now: now)
        suite.expect(countOnly?.available == 2 && countOnly?.resets.isEmpty == true && countOnly?.nextExpiry == nil
                        && none?.available == 0 && none?.limits == nil,
                     "a count without its list, or no resets at all, still reads")
        suite.expect(AgentCodexServer.summary(json(#"{"rateLimits":{}}"#), now: now) == nil,
                     "a Codex that does not report resets reads as one to update")

        suite.expect(AgentCodexServer.outcome(json(#"{"outcome":"reset"}"#)) == .reset
                        && AgentCodexServer.outcome(json(#"{"outcome":"nothingToReset"}"#)) == .nothingToReset
                        && AgentCodexServer.outcome(json(#"{"outcome":"alreadyRedeemed"}"#)) == .alreadyRedeemed
                        && AgentCodexServer.outcome(json(#"{"outcome":"somethingNew"}"#)) == nil,
                     "each outcome of a use reads, and an unknown one is not taken as done")
        suite.expect(AgentCodexServer.failure(json(#"{"code":-32600,"message":"Invalid request: unknown variant `account/rateLimitResetCredit/consume`, expected one of `initialize`"}"#)) == .outdated
                        && AgentCodexServer.failure(json(#"{"code":-32601,"message":"no"}"#)) == .outdated
                        && AgentCodexServer.failure(json(#"{"code":-32600,"message":"codex account authentication required to read rate limits"}"#)) == .needsSignIn
                        && AgentCodexServer.failure(json(#"{"code":-32603,"message":"backend error"}"#)) == .refused
                        && AgentCodexServer.failure(nil) == .refused,
                     "a question the server does not know asks for an update, a signed-out account for a sign-in, and any other answer is a refusal")
        suite.expect(AgentCodexServer.signInFailure(json(#"{"account":{"type":"chatgpt","planType":"pro"}}"#)) == nil
                        && AgentCodexServer.signInFailure(json(#"{"account":{"type":"apiKey"}}"#)) == .needsSignIn
                        && AgentCodexServer.signInFailure(json(#"{"account":{"type":"amazonBedrock"}}"#)) == .needsSignIn
                        && AgentCodexServer.signInFailure(json(#"{"account":null,"requiresOpenaiAuth":true}"#)) == .needsSignIn,
                     "only a plan's sign-in has resets")

        let store = AgentUsageStore()
        store.updateLimits(AgentLimits(provider: .codex, windows: [], observedAt: now, source: .account))
        store.apply([.limits(AgentLimits(provider: .codex, windows: [], observedAt: now.addingTimeInterval(-60),
                                         source: .sessionLog))],
                    file: "log", provider: .codex, tracksTurns: true, modified: now)
        let kept = store.limits[.codex]?.source
        store.apply([.limits(AgentLimits(provider: .codex, windows: [], observedAt: now.addingTimeInterval(60),
                                         source: .sessionLog))],
                    file: "log", provider: .codex, tracksTurns: true, modified: now)
        suite.expect(kept == .account && store.limits[.codex]?.source == .sessionLog,
                     "a log read late never replaces the account's newer reading, and a newer log line does")
    }

    // MARK: Discovery

    private static func discovery(_ suite: TestSuite) {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        let app = URL(fileURLWithPath: "/Applications/Agent.app", isDirectory: true)
        suite.expect(AgentCodexServer.candidates(apps: [app], home: home, searchPath: "/shell/bin:relative:/more").map(\.path)
                        == ["/Applications/Agent.app/Contents/Resources/codex-cli/bin/codex",
                            "/Applications/Agent.app/Contents/Resources/codex",
                            "/Users/someone/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                            "/shell/bin/codex", "/more/codex"],
                     "the desktop app's copy comes first, in its current then its earlier layout, then the installers' folders and the shell's")

        let root = FileManager.default.temporaryDirectory.appending(path: "vorss-codex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fakeHome = root.appending(path: "home")
        let fakeApp = root.appending(path: "Agent.app")
        let installed = fakeHome.appending(path: ".local/bin/codex")
        let bundled = fakeApp.appending(path: "Contents/Resources/codex-cli/bin/codex")
        func tool(_ url: URL, executable: Bool = true) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data("#!/bin/sh\n".utf8),
                                           attributes: [.posixPermissions: executable ? 0o755 : 0o644])
        }
        tool(installed)
        // A folder where the earlier layout kept the tool is not the tool.
        try? FileManager.default.createDirectory(at: fakeApp.appending(path: "Contents/Resources/codex"),
                                                 withIntermediateDirectories: true)
        tool(bundled, executable: false)
        suite.expect(AgentCodexServer.executable(apps: [fakeApp], home: fakeHome) == installed,
                     "a folder or a file that cannot run is passed over for the next place")
        tool(bundled)
        suite.expect(AgentCodexServer.executable(apps: [fakeApp], home: fakeHome) == bundled,
                     "the desktop app's own copy wins over an installed one")

        let environment = AgentCodexServer.environment(for: URL(fileURLWithPath: "/tool/bin/codex"), searchPath: nil,
                                                       base: ["PATH": "/usr/bin:/bin", "HOME": "/Users/someone"])
        let shell = AgentCodexServer.environment(for: URL(fileURLWithPath: "/tool/bin/codex"), searchPath: "/a:/b",
                                                 base: ["PATH": "/usr/bin:/bin"])
        suite.expect(environment["PATH"] == "/tool/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                        && environment["HOME"] == "/Users/someone" && shell["PATH"] == "/tool/bin:/a:/b:/usr/bin:/bin",
                     "the tool runs with its own folder and the usual ones on its PATH, which finds node for npm's copy")
    }

    // MARK: Conversations

    /// Answers each question by its method, with a notification, a request
    /// of its own and a line that is not JSON along the way, the way the real
    /// server can interleave them. `STAND_IN` picks the account it plays. It
    /// runs only as the server started without Codex's plugins.
    private static let standIn = #"""
        #!/bin/sh
        [ "$#" = 3 ] && [ "$1" = "-c" ] && [ "$2" = "features.plugins=false" ] && [ "$3" = "app-server" ] || exit 2
        [ "$STAND_IN" = "exits" ] && exit 0
        while IFS= read -r line; do
          [ "$STAND_IN" = "silent" ] && continue
          case "$line" in
            *'"method":"initialize"'*)
              printf '%s\n' '{"method":"remoteControl/status/changed","params":{}}' '{"id":1,"result":{"userAgent":"stand-in"}}' ;;
            *'"method":"account/read"'*)
              if [ "$STAND_IN" = "signedOut" ]; then
                printf '%s\n' '{"id":2,"result":{"account":null,"requiresOpenaiAuth":true}}'
              else
                printf '%s\n' '{"id":7,"method":"account/chatgptAuthTokens/refresh","params":{}}' '{"id":2,"result":{"account":{"type":"chatgpt","planType":"pro"}}}'
              fi ;;
            *'"method":"account/rateLimits/read"'*)
              if [ "$STAND_IN" = "old" ]; then
                printf '%s\n' '{"id":3,"result":{"rateLimits":{"limitId":"codex"}}}'
              else
                printf '%s\n' 'not json' '{"method":"account/rateLimits/updated","params":{}}' \
                  '{"id":3,"result":{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":0,"windowDurationMins":10080,"resetsAt":4102444800}}},"rateLimitResetCredits":{"availableCount":1,"credits":[{"id":"only","status":"available","expiresAt":4102444800}]}}}'
              fi ;;
            *'"method":"account/rateLimitResetCredit/consume"'*)
              case "$line" in
                *'"idempotencyKey":"use-1"'*'"creditId":"only"'* | *'"creditId":"only"'*'"idempotencyKey":"use-1"'*)
                  printf '%s\n' '{"id":2,"result":{"outcome":"reset"}}' ;;
                *) printf '%s\n' '{"id":2,"error":{"code":-32600,"message":"unexpected attempt"}}' ;;
              esac ;;
          esac
        done
        """#

    private static func conversations(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-codex-server-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let server = folder.appending(path: "codex")
        guard FileManager.default.createFile(atPath: server.path, contents: Data(standIn.utf8),
                                             attributes: [.posixPermissions: 0o755]) else {
            suite.expect(false, "the stand-in server is written")
            return
        }
        func environment(_ mode: String) -> [String: String] {
            AgentCodexServer.environment(for: server, searchPath: nil,
                                         base: ["PATH": "/usr/bin:/bin", "STAND_IN": mode])
        }

        let quiet = AgentCodexConversation(server, environment: environment("plan"), timeout: 5)
        let introduced = quiet?.start()
        quiet?.end()
        suite.expect(introduced.map { if case .success = $0 { return true }; return false } == true,
                     "a conversation starts Codex's server with its plugins off")

        let checked = AgentCodexServer.check(server, environment: environment("plan"))
        let summary = try? checked.get()
        suite.expect(summary?.available == 1 && summary?.resets.first?.id == "only"
                        && summary?.limits?.windows.first?.usedPercent == 0,
                     "a check introduces the app, asks for the account and then its resets, past other messages")
        suite.expect(AgentCodexServer.check(server, environment: environment("signedOut")) == .failure(.needsSignIn)
                        && AgentCodexServer.check(server, environment: environment("old")) == .failure(.outdated),
                     "a signed-out account and a Codex without resets say so")

        let used = AgentCodexServer.redeem(server, environment: environment("plan"), credit: "only", key: "use-1")
        suite.expect(used.outcome == .success(.reset) && used.summary?.available == 1,
                     "a use names its reset and its attempt, and reads the account again")
        let refused = AgentCodexServer.redeem(server, environment: environment("plan"), credit: nil, key: "use-2")
        suite.expect(refused.outcome == .failure(.refused) && refused.summary != nil,
                     "a use answered with an error reads as one, and the account is still read")

        let started = Date()
        let silent = AgentCodexConversation(server, environment: environment("silent"), timeout: 0.5)
        let unanswered = silent?.start()
        silent?.end()
        let exited = AgentCodexConversation(server, environment: environment("exits"), timeout: 5)
        let ended = exited?.start()
        exited?.end()
        suite.expect(unanswered.map { if case .failure(.unreachable) = $0 { return true }; return false } == true
                        && ended.map { if case .failure(.unreachable) = $0 { return true }; return false } == true
                        && Date().timeIntervalSince(started) < 4,
                     "a server that never answers costs the conversation's time, and one that exits ends it at once")
        suite.expect(AgentCodexConversation(folder.appending(path: "missing"), environment: [:], timeout: 1) == nil,
                     "a tool that cannot start gives no conversation")
    }
}
