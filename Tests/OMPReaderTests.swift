// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum OMPReaderTests {
    static func run(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        var state = AgentLogState()
        let reader = OMPReader()
        let session = Data(#"{"type":"session","id":"s","timestamp":"2027-01-15T09:20:00.000Z","cwd":"/tmp/app"}"#.utf8)
        suite.expect(reader.parse(session, state: &state, now: now).isEmpty
                        && state.session == "s" && state.project == "app",
                     "Oh My Pi session metadata names its session and project without opening a turn")
        let model = Data(#"{"type":"model_change","id":"m","model":"private/model","timestamp":"2027-01-15T09:20:01.000Z"}"#.utf8)
        suite.expect(reader.parse(model, state: &state, now: now).isEmpty && state.model == "private/model",
                     "Oh My Pi's selected model supplies turn context")

        let prompt = Data(#"{"id":"u","message":{"role":"user","content":[{"type":"text","text":"private"}],"timestamp":1799998802000},"timestamp":"2027-01-15T09:20:02.000Z","type":"message"}"#.utf8)
        let began = Date(timeIntervalSince1970: 1_800_004_802)
        suite.expect(reader.parse(prompt, state: &state, now: now) == [
            .turnBegan(began), .turnContext(model: "private/model", project: "app")
        ] && state.turnOpen, "an Oh My Pi prompt opens a live turn with its current context")

        let step = Data(#"{"type":"message","id":"a1","timestamp":"2027-01-15T09:20:03.000Z","message":{"role":"assistant","provider":"private","model":"private/model","stopReason":"toolUse","error":null,"usage":{"input":100,"output":20,"cacheRead":30,"cacheWrite":10,"cost":{"total":0.42}}}}"#.utf8)
        let entries = reader.parse(step, state: &state, now: now)
        suite.expect(entries.count == 2 && entries.last == .turnActive(Date(timeIntervalSince1970: 1_800_004_803))
                        && state.turnOpen,
                     "an Oh My Pi tool-use reply counts usage and keeps its turn open")
        guard case .usage(let key, let record, _)? = entries.first else {
            suite.expect(false, "the Oh My Pi tool-use reply has a usage record")
            return
        }
        suite.expect(key == "omp:s:a1" && record.provider == .omp && record.session == "s"
                        && record.project == "app" && record.model == "private/model"
                        && record.tokens == AgentTokens(input: 100, cacheWrite: 10, cacheRead: 30, output: 20)
                        && record.cost == 0.42 && record.reportedCost,
                     "Oh My Pi usage keeps tokens and its recorded price for a model the list does not know")
        let saved = AgentUsageStore.Saved(records: [
            AgentUsageStore.Saved.Record(key: key, record: record,
                                         billable: AgentBillable(tokens: record.tokens), sources: ["omp"]),
        ])
        let archive = AgentUsageArchive.encode(AgentUsageArchive.Contents(providers: [.omp], store: saved, cursors: []),
                                               build: "test")
        suite.expect(AgentUsageArchive.decode(archive, build: "test")?.store.records.first?.record.reportedCost == true,
                     "Oh My Pi reported cost survives the usage archive")

        let result = Data(#"{"type":"message","id":"t","timestamp":"2027-01-15T09:20:04.000Z","message":{"role":"toolResult","content":"private","timestamp":1799998804000}}"#.utf8)
        suite.expect(reader.parse(result, state: &state, now: now) == [.turnActive(Date(timeIntervalSince1970: 1_800_004_804))],
                     "an Oh My Pi tool result is activity but not a model request")
        let finish = Data(#"{"type":"message","id":"a2","timestamp":"2027-01-15T09:20:05.000Z","message":{"role":"assistant","model":"private/model","stopReason":"stop","error":null,"usage":{"input":1,"output":2,"cacheRead":0,"cacheWrite":0,"cost":{"total":0.01}}}}"#.utf8)
        let finished = reader.parse(finish, state: &state, now: now)
        suite.expect(finished.count == 2 && finished.last == .turnEnded(Date(timeIntervalSince1970: 1_800_004_805),
                                                                          completed: true, duration: nil) && !state.turnOpen,
                     "an Oh My Pi final reply closes its turn after counting the reply")

        let background = Data(#"{"type":"model_usage","id":"bg","timestamp":"2027-01-15T09:20:06.000Z","provider":"private","model":"private/model","purpose":"title","stopReason":"stop","usage":{"input":5,"output":6,"cacheRead":0,"cacheWrite":0,"cost":{"total":0.02}}}"#.utf8)
        let side = reader.parse(background, state: &state, now: now)
        suite.expect(side.count == 1 && !state.turnOpen,
                     "Oh My Pi side-channel usage is counted without reopening the main turn")

        let main = "/tmp/sessions/project/2027-01-15T09-20-00-000Z_123e4567-e89b-42d3-a456-426614174000.jsonl"
        let sessionFolder = String(main.dropLast(".jsonl".count))
        let advisor = sessionFolder + "/__advisor.jsonl"
        let named = sessionFolder + "/nested/NamedAgent.jsonl"
        suite.expect(OMPReader.isMainSession(main) && !OMPReader.isMainSession(advisor) && !OMPReader.isMainSession(named)
                        && OMPReader.parent(of: advisor) == main && OMPReader.parent(of: named) == main
                        && AgentLogCursor(path: main, provider: .omp).tracksTurns
                        && !AgentLogCursor(path: named, provider: .omp).tracksTurns
                        && AgentLogCursor(path: named, provider: .omp).parent == main,
                     "only Oh My Pi main sessions own turns, while nested sidecars report usage to their parent")
    }
}
