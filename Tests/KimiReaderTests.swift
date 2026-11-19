// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum KimiReaderTests {
    static func run(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ms = Int(now.timeIntervalSince1970 * 1000)
        var state = AgentLogState()
        let reader = KimiReader()

        let metadata = Data(#"{"type":"metadata","protocol_version":"1.5","created_at":\#(ms)}"#.utf8)
        suite.expect(reader.parse(metadata, state: &state, now: now).isEmpty,
                     "Kimi's session metadata opens no turn")

        let started = Data(#"{"type":"agent.turn.started","agentId":"main","turnId":0,"time":\#(ms)}"#.utf8)
        suite.expect(reader.parse(started, state: &state, now: now) == [.turnBegan(now)],
                     "Kimi's turn start opens the turn at its own time")

        let request = Data(#"{"type":"llm.request","agentId":"main","model":"k3.1-pro","modelAlias":"kimi-code/k3.1-pro","time":\#(ms)}"#.utf8)
        let requestEntries = reader.parse(request, state: &state, now: now)
        suite.expect(requestEntries.contains(.turnActive(now))
                        && requestEntries.contains(.turnContext(model: "k3.1-pro", project: "")),
                     "Kimi's request keeps the turn alive and names its model")

        let step = Data(#"{"type":"context.append_loop_event","agentId":"main","event":{"type":"step.begin"},"time":\#(ms)}"#.utf8)
        suite.expect(reader.parse(step, state: &state, now: now) == [.turnActive(now)],
                     "Kimi's loop activity keeps the turn alive")

        let completed = Data(#"{"type":"turn.ended","agentId":"main","turnId":0,"reason":"completed","durationMs":300000,"time":\#(ms)}"#.utf8)
        suite.expect(reader.parse(completed, state: &state, now: now) == [.turnEnded(now, completed: true, duration: 300)],
                     "a completed Kimi turn closes and reports a finished task")

        let leftover = Data(#"{"type":"token_counting.turn_recorded","agentId":"main","time":\#(ms)}"#.utf8)
        suite.expect(reader.parse(leftover, state: &state, now: now).isEmpty,
                     "records left after a turn ends do not reopen it")

        let cancelled = Data(#"{"type":"turn.ended","agentId":"main","turnId":1,"reason":"cancelled","durationMs":120000,"time":\#(ms)}"#.utf8)
        suite.expect(reader.parse(cancelled, state: &state, now: now) == [.turnEnded(now, completed: false, duration: 120)],
                     "a cancelled Kimi turn closes without a finished notice")

        let untimed = Data(#"{"type":"config.update","agentId":"main","thinkingEffort":"high"}"#.utf8)
        suite.expect(reader.parse(untimed, state: &state, now: now).isEmpty,
                     "an untimed Kimi record is not activity")
    }
}
