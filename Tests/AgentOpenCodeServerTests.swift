// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// OpenCode's own answer for the Console workspace's Go allowance, and the
/// loopback service it is asked of.
enum AgentOpenCodeServerTests {
    static func run(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_794_743_000)
        let resetDate = Date(timeIntervalSince1970: 1_794_748_400)
        func meter(_ percent: Any, reset: Any = 1_794_748_400_000) -> [String: Any] {
            ["percent": percent, "limited": false, "resetsAt": reset]
        }
        func answer(_ go: [String: Any]?) -> [String: Any] {
            var data: [String: Any] = ["workspace": ["id": "org_1", "usageURL": "https://opencode.ai/console"],
                                       "budgets": [] as [Any]]
            if let go { data["go"] = go }
            return ["location": ["directory": "/Users/me"], "data": data]
        }
        let go: [String: Any] = ["rolling": meter(3), "weekly": meter(27), "monthly": meter(13)]
        let limits = AgentOpenCodeServer.limits(answer(go), observed: now)
        suite.expect(limits?.provider == .opencode && limits?.source == .account && limits?.observedAt == now
                        && limits?.windows.map(\.id) == ["opencode.rolling", "opencode.weekly"]
                        && limits?.windows.map(\.kind) == [.session, .weekly]
                        && limits?.windows.map(\.minutes) == [300, 10_080]
                        && limits?.windows.map(\.usedPercent) == [3, 27]
                        && limits?.windows.allSatisfy { $0.scope == nil && $0.resetsAt == resetDate } == true,
                     "OpenCode's answer gives the rolling and weekly allowance as the windows Codex reports")
        suite.expect(AgentOpenCodeServer.limits(["data": NSNull()], observed: now) == nil
                        && AgentOpenCodeServer.limits(answer(nil), observed: now) == nil
                        && AgentOpenCodeServer.limits(["data": ["go": [:], "workspace": [:], "budgets": []]],
                                                      observed: now) == nil,
                     "a workspace that is signed out or has no Go allowance invents no limits")
        let partial = AgentOpenCodeServer.limits(answer(["rolling": meter("3"), "weekly": meter(27)]), observed: now)
        suite.expect(partial?.windows.map(\.id) == ["opencode.weekly"],
                     "a meter that is not a number is left out instead of reading as no use")
        suite.expect(AgentOpenCodeServer.limits(answer(["rolling": meter(-4), "weekly": meter(130)]),
                                                observed: now)?.windows.map(\.usedPercent) == [0, 100],
                     "a percentage outside 0 to 100 is clamped as every account reading is")
        let renewed = AgentOpenCodeServer.limits(answer(["rolling": meter(50, reset: 1_794_740_000_000),
                                                         "weekly": meter(27)]), observed: now)
        suite.expect(renewed?.windows.map(\.id) == ["opencode.weekly"],
                     "a meter renewed before the reading is dropped instead of claiming zero use")
        suite.expect(AgentOpenCodeServer.limits(answer(["rolling": meter(50, reset: 1_794_740_000_000)]),
                                                observed: now) == nil,
                     "a reading whose every window renewed says nothing at all")
        suite.expect(limits.map { $0.windows.allSatisfy { !$0.usedPercent.isNaN } } == true
                        && AgentOpenCodeServer.limits(answer(["rolling": meter(Double.infinity), "weekly": meter(27)]),
                                                      observed: now)?.windows.map(\.id) == ["opencode.weekly"],
                     "an infinite percentage cannot reach the island")
        suite.expect(AgentOpenCodeServer.interval(after: nil, pageVisible: true) == 60
                        && AgentOpenCodeServer.interval(after: nil, pageVisible: false) == 300
                        && AgentOpenCodeServer.interval(after: .unreachable, pageVisible: true) == 300
                        && AgentOpenCodeServer.interval(after: .noAllowance, pageVisible: true) == 1_800,
                     "OpenCode is asked every minute only while the AI page shows, and rarely after a plan that cannot change")
        service(suite)
    }

    /// The state folder OpenCode writes, and the request built from it.
    private static func service(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorssaint-opencode-service-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            let file = AgentOpenCodeServer.serviceFile(home: folder)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            func save(_ json: [String: Any]) throws {
                try JSONSerialization.data(withJSONObject: json).write(to: file)
            }
            try save(["url": "http://127.0.0.1:49374", "password": "pw"])
            let found = AgentOpenCodeServer.service(home: folder)
            let request = found.map { AgentOpenCodeServer.request($0) }
            suite.expect(found?.url.absoluteString == "http://127.0.0.1:49374" && found?.password == "pw"
                            && request?.url?.path == "/api/experimental/usage/limits"
                            && request?.value(forHTTPHeaderField: "Authorization")
                                == "Basic " + Data("opencode:pw".utf8).base64EncodedString(),
                         "the server is asked on OpenCode's usage route with the loopback password it keeps")
            for wrong in [["url": "http://example.com:49374", "password": "pw"],
                          ["url": "ftp://127.0.0.1:49374", "password": "pw"],
                          ["url": "http://127.0.0.1:49374"],
                          ["url": "http://127.0.0.1:49374", "password": ""]] {
                try save(wrong)
                suite.expect(AgentOpenCodeServer.service(home: folder) == nil,
                             "a service file that is not a local server with a password is never used")
            }
            try FileManager.default.removeItem(at: file)
            suite.expect(AgentOpenCodeServer.service(home: folder) == nil,
                         "an OpenCode that is not running is not mistaken for a signed-out workspace")
        } catch { suite.expect(false, "OpenCode service fixture: \(error)") }
    }
}
