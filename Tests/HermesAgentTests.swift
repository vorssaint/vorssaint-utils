// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Hermes reader's turns, straight from the rows its database reader hands
/// over.
enum HermesAgentTests {
    static func run(_ suite: TestSuite) {
        let reader = AgentProvider.hermes.reader
        let began = Date(timeIntervalSince1970: 1_790_088_000)
        var state = AgentLogState()
        let context = AgentLogEntry.turnContext(model: "nousresearch/hermes-4", project: "Fix the build")
        let prompt = line(#"{"id":"1","session_id":"s","role":"user","time_created":1790088000,"title":"Fix the build","model":"nousresearch/hermes-4"}"#)
        suite.expect(reader.parse(prompt, state: &state, now: began) == [context, .turnBegan(began)],
                     "a Hermes prompt opens its turn with the session's model and title")
        let tool = line(#"{"id":"2","session_id":"s","role":"tool","time_created":1790088020}"#)
        suite.expect(reader.parse(tool, state: &state, now: began)
                        == [context, .turnActive(Date(timeIntervalSince1970: 1_790_088_020))],
                     "a tool result keeps the turn going")
        let call = line(#"{"id":"3","session_id":"s","role":"assistant","time_created":1790088040,"finish":"tool_calls"}"#)
        suite.expect(reader.parse(call, state: &state, now: began).last
                        == .turnActive(Date(timeIntervalSince1970: 1_790_088_040)),
                     "a reply that calls a tool keeps the turn going")
        let done = line(#"{"id":"4","session_id":"s","role":"assistant","time_created":1790088100,"finish":"stop"}"#)
        suite.expect(reader.parse(done, state: &state, now: began).last
                        == .turnEnded(Date(timeIntervalSince1970: 1_790_088_100), completed: true, duration: 100),
                     "a finished reply ends the turn with its real duration")
        suite.expect(reader.parse(tool, state: &state, now: began).isEmpty,
                     "a tool result outside a turn is nothing")
        let streaming = line(#"{"id":"5","session_id":"s","role":"assistant","time_created":1790088200}"#)
        suite.expect(reader.parse(streaming, state: &state, now: began).last
                        == .turnBegan(Date(timeIntervalSince1970: 1_790_088_200)),
                     "a reply that arrives without a prompt, as one written when the reading began, opens a turn")
        let meta = line(#"{"id":"6","session_id":"s","role":"session_meta","time_created":1790088210}"#)
        suite.expect(reader.parse(meta, state: &state, now: began).isEmpty,
                     "session metadata holds no turn")
        let other = line(#"{"id":"7","session_id":"t","role":"user","time_created":1790088300,"directory":"/Users/me/code/app"}"#)
        suite.expect(reader.parse(other, state: &state, now: began).last == .turnBegan(Date(timeIntervalSince1970: 1_790_088_300))
                        && state.hermesSessions["t"]?.project == "app",
                     "a second session tracks its own turn beside the first, named by its folder")
        suite.expect(reader.parse(line(#"{"type":"reset"}"#), state: &state, now: began) == [.reset(began)]
                        && state.hermesSessions.isEmpty,
                     "a replaced database forgets its sessions")
    }

    private static func line(_ json: String) -> Data { Data(json.utf8) }
}
