// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The ChatGPT limits Hermes reads keep the Codex card current while Codex
/// itself does not run.
enum HermesLimitsTests {
    static func run(_ suite: TestSuite) {
        parsing(suite)
        codexCard(suite)
        transport(suite)
        if ProcessInfo.processInfo.environment["VORSSAINT_HERMES_LIVE_CHECK"] == "1" {
            if case .success(let reading) = AgentHermesLimits.fetch(home: AgentLogRoot.hermesHome(),
                                                                    provider: AgentHermesLimits.codexProvider),
               let limits = AgentHermesLimits.codexLimits(reading) {
                for window in limits.windows {
                    print("LIVE HERMES CODEX LIMIT: \(window.id) used=\(window.usedPercent)% reset=\(window.resetsAt?.description ?? "unknown")")
                }
                suite.expect(!limits.windows.isEmpty, "opt-in live check: Hermes returns the Codex windows")
            } else { suite.expect(false, "opt-in live check: the Codex limits are available through Hermes") }
        }
    }

    private static func transport(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "hermes-cli-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cli = folder.appending(path: "hermes")
        let json = String(decoding: document(), as: UTF8.self)
        let script = "#!/bin/sh\n[ \"$1\" = usage ] && [ \"$2\" = --json ] && [ \"$3\" = --provider ] && [ \"$4\" = openai-codex ] || exit 3\nprintf '%s' '\(json)'\n"
        try? Data(script.utf8).write(to: cli)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        suite.expect(AgentHermesLimits.executable(home: folder, environment: ["PATH": folder.path]) == cli,
                     "a GUI launch finds Hermes on PATH without a shell")
        let cancellation = BoundedProcessCancellation()
        if case .success(let reading) = AgentHermesLimits.fetch(home: folder, provider: AgentHermesLimits.codexProvider,
                                                                executable: cli, cancellation: cancellation) {
            suite.expect(reading.provider == "openai-codex", "Hermes is asked for its ChatGPT account by name")
        } else { suite.expect(false, "the ChatGPT account is asked for by name") }
        if case .failure(.unavailable) = AgentHermesLimits.fetch(home: folder, executable: cli) {
            suite.expect(true, "without a provider, Hermes answers for its default account instead")
        } else { suite.expect(false, "the default account is not asked for when Codex is wanted") }
        cancellation.cancel()
        if case .failure(.cancelled) = AgentHermesLimits.fetch(home: folder, provider: AgentHermesLimits.codexProvider,
                                                               executable: cli, cancellation: cancellation) {
            suite.expect(true, "a cancelled request does not launch")
        } else { suite.expect(false, "a cancelled request must not return limits") }
        try? Data("#!/bin/sh\nexec /bin/sleep 10\n".utf8).write(to: cli)
        if case .failure(.timedOut) = AgentHermesLimits.fetch(home: folder, provider: AgentHermesLimits.codexProvider,
                                                              executable: cli, timeout: 0.1) {
            suite.expect(true, "a stalled CLI is bounded")
        } else { suite.expect(false, "a stalled CLI must time out") }
    }

    private static func parsing(_ suite: TestSuite) {
        let reading = AgentHermesLimits.parse(document())
        suite.expect(reading?.provider == "openai-codex" && reading?.plan == "Plus",
                     "the CLI names the account it read and its plan")
        suite.expect(reading?.limits.observedAt.timeIntervalSince1970 == 1_792_497_600.125
                        && reading?.limits.windows.last?.resetsAt?.timeIntervalSince1970 == 1_793_102_400.5,
                     "fractional ISO 8601 times are kept")
        for value in ["-1", "101", "true", "null", #""NaN""#, "1e400"] {
            let invalid = AgentHermesLimits.parse(document(windows: "[{\"label\":\"Weekly\",\"used_percent\":\(value)}]"))
            suite.expect(invalid?.limits.windows.isEmpty != false, "an invalid percentage \(value) is no limit")
        }
        suite.expect(AgentHermesLimits.parse(Data("{}".utf8)) == nil && AgentHermesLimits.parse(Data("not json".utf8)) == nil,
                     "malformed documents are refused")
    }

    private static func codexCard(_ suite: TestSuite) {
        guard let limits = AgentHermesLimits.parse(document()).flatMap(AgentHermesLimits.codexLimits) else {
            suite.expect(false, "Hermes' ChatGPT reading becomes Codex limits"); return
        }
        suite.expect(limits.provider == .codex && limits.source == .account,
                     "the reading belongs to the Codex card, as an account check")
        suite.expect(limits.windows.map(\.id) == ["codex.300", "codex.10080"]
                        && limits.windows.map(\.kind) == [.session, .weekly]
                        && limits.windows.map(\.minutes) == [300, 10_080]
                        && limits.windows.map(\.usedPercent) == [7, 16],
                     "the windows take the names Codex's own logs give them")
        let other = AgentHermesLimits.parse(document(provider: "anthropic"))
        suite.expect(other.flatMap(AgentHermesLimits.codexLimits) == nil, "another account's reading is never Codex's")
        let unavailable = AgentHermesLimits.parse(document(unavailable: #""No credential""#))
        suite.expect(unavailable.flatMap(AgentHermesLimits.codexLimits) == nil, "an unavailable reading changes nothing")
        let extra = AgentHermesLimits.parse(document(windows: #"[{"label":"Credits","used_percent":3}]"#))
        suite.expect(extra.flatMap(AgentHermesLimits.codexLimits) == nil, "a reading without the plan windows changes nothing")

        let store = AgentUsageStore()
        let older = AgentLimits(provider: .codex, windows: [], observedAt: limits.observedAt.addingTimeInterval(-60), source: .sessionLog)
        store.updateLimits(older)
        store.updateLimits(limits)
        suite.expect(store.limits[.codex] == limits, "a newer reading through Hermes replaces what Codex last logged")
        let newer = AgentLimits(provider: .codex, windows: [], observedAt: limits.observedAt.addingTimeInterval(60), source: .sessionLog)
        store.updateLimits(newer)
        store.updateLimits(limits)
        suite.expect(store.limits[.codex] == newer, "what Codex logs later wins over an older reading")
    }

    static func document(provider: String = "openai-codex",
                         windows: String = #"[{"label":"Session","used_percent":7,"resets_at":"2026-10-20T15:00:00Z"},{"label":"Weekly","used_percent":16,"resets_at":"2026-10-27T12:00:00.500Z"}]"#,
                         unavailable: String = "null") -> Data {
        Data("""
        {"provider":"\(provider)","plan":"Plus","fetched_at":"2026-10-20T12:00:00.125+00:00",
         "windows":\(windows),"details":[],"unavailable_reason":\(unavailable)}
        """.utf8)
    }
}
