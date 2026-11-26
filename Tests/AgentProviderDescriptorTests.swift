// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One row describes each agent, and the store's transcript handling is keyed,
/// not wired to Cursor: a second provider that repeats responses across files
/// needs no field or branch of its own.
enum AgentProviderDescriptorTests {
    static func run(_ suite: TestSuite) {
        table(suite)
        keys(suite)
        secondTranscriptProvider(suite)
    }

    private static func table(_ suite: TestSuite) {
        let all = AgentProviderDescriptor.all
        suite.expect(all.count == AgentProvider.allCases.count,
                     "every agent has exactly one descriptor row")
        suite.expect(Set(all.map(\.id)) == Set(AgentProvider.allCases),
                     "the descriptors cover every agent and nothing else")
        suite.expect(Set(all.map(\.defaultsKey)).count == all.count,
                     "each agent keeps its own on/off preference")
        for provider in AgentProvider.allCases {
            let descriptor = provider.descriptor
            suite.expect(descriptor.id == provider && AgentProviderDescriptor.table[provider]?.id == provider,
                         "\(provider.rawValue) looks up its own row")
        }
        for descriptor in all {
            suite.expect(descriptor.makeReader().provider == descriptor.id,
                         "\(descriptor.id.rawValue)'s row makes its own harness reader")
            suite.expect(!descriptor.logSources.isEmpty,
                         "\(descriptor.id.rawValue)'s row names where its logs live")
        }
        let home = URL(fileURLWithPath: "/tmp/provider-descriptor-home")
        let roots = AgentLogRoot.all(home: home, providers: [.codex, .opencode, .copilot, .cursor])
        suite.expect(roots.map { $0.provider.rawValue } == ["codex", "codex", "opencode", "copilot", "cursor"],
                     "log roots follow the table in the providers' order")
        suite.expect(roots.prefix(2).map { $0.url.path } == [
            home.appending(path: ".codex/sessions").path,
            home.appending(path: ".codex/archived_sessions").path
        ], "the Codex row keeps both of its log folders")
    }

    private static func keys(_ suite: TestSuite) {
        let saved = AgentUsageKey.transcript(provider: .cursor, copy: "1:s:one")
        suite.expect(saved.rawValue == "cursor-transcript:1:s:one" && saved.isTranscript,
                     "a Cursor transcript key keeps the string already saved on disk")
        suite.expect(CursorReader.usageKey(session: "s", id: "one") == saved.rawValue,
                     "the Cursor reader builds the same key through the typed form")
        for provider in AgentProvider.allCases {
            let key = AgentUsageKey.transcript(provider: provider, copy: "2:ss:id")
            suite.expect(AgentUsageKey(key.rawValue) == key && key.isTranscript,
                         "a \(provider.rawValue) transcript key reads back as itself")
        }
        suite.expect(AgentUsageKey("other:key") == .other("other:key") && !AgentUsageKey("other:key").isTranscript
                        && AgentUsageKey("other:key").rawValue == "other:key",
                     "a key that is not a transcript keeps its text and stays one")
    }

    /// Claude never repeats responses across files; here it stands in for a
    /// second provider that does, to show the store needs nothing new for it.
    private static func secondTranscriptProvider(_ suite: TestSuite) {
        let store = AgentUsageStore()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let key = AgentUsageKey.transcript(provider: .claude, copy: "1:s:one").rawValue
        let first = "/tmp/second-provider/a.jsonl"
        let second = "/tmp/second-provider/b.jsonl"

        func record(_ output: Int) -> AgentUsageRecord {
            AgentUsageRecord(provider: .claude, date: date, model: "claude-test", project: "app", session: "s",
                             tokens: AgentTokens(input: 10, output: output), cost: 0, savings: 0)
        }
        func apply(_ output: Int, from file: String) {
            let record = record(output)
            store.apply([.usage(key: key, record: record, billable: AgentBillable(tokens: record.tokens))],
                        file: file, provider: .claude, tracksTurns: true, modified: date, now: date)
        }

        apply(100, from: first)
        apply(300, from: second)
        suite.expect(store.records.count == 1 && store.records[0].tokens.output == 300,
                     "a second provider's transcript copies keep one whole reading")
        suite.expect(store.transcriptUsageRevision(for: "s", provider: .claude) != 0,
                     "a second provider gets its own copy state in the store")

        store.forgetUsage(files: [second])
        suite.expect(store.records[0].tokens.output == 100,
                     "removing the chosen copy falls back to the other reading")

        let restored = AgentUsageStore(saved: store.saved)
        suite.expect(restored.transcriptUsageRevision(for: "s", provider: .claude) != 0
                        && restored.records.count == 1,
                     "a second provider's copy count survives a save and reload")
    }
}
