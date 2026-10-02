// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

enum NotchAgentTests {
    static func run(_ suite: TestSuite) {
        // Prices come from the list the app ships, the same file the project publishes.
        let previous = AgentPricing.list
        let shipped = (try? Data(contentsOf: URL(fileURLWithPath: "Resources/agent-prices.json"))).flatMap(AgentPriceList.decode)
        suite.expect(shipped != nil, "the price list that ships with the app is valid")
        AgentPricing.install(shipped ?? .empty)
        defer { AgentPricing.install(previous) }
        priceList(suite, shipped: shipped ?? .empty)
        pricing(suite)
        claudeParsing(suite)
        claudeTurns(suite)
        codexParsing(suite)
        openCodeParsing(suite)
        timestamps(suite)
        summary(suite)
        AgentUsageSummaryCacheTests.run(suite)
        limits(suite)
        strip(suite)
        liveTurns(suite)
        reading(suite)
        AgentUsageReadTests.run(suite)
        AgentUsageArchiveTests.run(suite)
        AgentUsageArchiveSettleTests.run(suite)
        AgentUsageArchiveSaveTests.run(suite)
        claudeApp(suite)
        AgentCodexResetTests.run(suite)
        preferences(suite)
        formatting(suite)
        AgentUsageEventDeliveryTests.run(suite)
        AgentSessionBoardTests.run(suite)
        NotchAgentAnimationTests.run { suite.expect($0, $1) }
    }

    private static func line(_ json: String) -> Data { Data(json.utf8) }

    private static func claudeAssistant(id: String = "msg_1", request: String = "req_1", model: String = "claude-opus-5-5",
                                        stop: String = "tool_use", output: Int = 225, time: String = "2026-09-21T23:42:45.078Z",
                                        sidechain: Bool = false, cwd: String = "/Users/me/code/app") -> Data {
        line("""
        {"parentUuid":"p","isSidechain":\(sidechain),"type":"assistant","timestamp":"\(time)","sessionId":"s1","cwd":"\(cwd)",\
        "version":"2.1.280","requestId":"\(request)","message":{"id":"\(id)","model":"\(model)","role":"assistant",\
        "stop_reason":"\(stop)","content":[{"type":"text","text":"\\"type\\":\\"assistant\\""}],\
        "usage":{"input_tokens":2,"cache_creation_input_tokens":17218,"cache_read_input_tokens":43134,\
        "output_tokens":\(output),"output_tokens_details":{"thinking_tokens":32},\
        "cache_creation":{"ephemeral_1h_input_tokens":17218,"ephemeral_5m_input_tokens":0},\
        "server_tool_use":{"web_search_requests":0},"speed":"standard","inference_geo":"not_available"}}}
        """)
    }

    private static func claudeUser(_ content: String = "Fix the build", time: String = "2026-09-21T23:40:00.000Z",
                                   meta: Bool = false, toolResult: Bool = false) -> Data {
        let body = toolResult ? #"[{"type":"tool_result","content":"ok"}]},"toolUseResult":{"stdout":"ok"}"#
            : "\"\(content)\"}"
        return line(#"{"type":"user","timestamp":"\#(time)","sessionId":"s1","cwd":"/Users/me/code/app","isMeta":\#(meta),"message":{"role":"user","content":\#(body)}"#)
    }

    // MARK: Pricing

    private static func pricing(_ suite: TestSuite) {
        var billable = AgentBillable(tokens: AgentTokens(input: 1000, cacheWrite: 10_000, cacheRead: 100_000, output: 2000))
        billable.longCacheWrite = 6000
        let opus = AgentPricing.cost(billable, model: "claude-opus-5-5")
        suite.expectClose(opus.cost ?? -1, 0.132, "Opus 5.5 bills input, both cache writes, cache reads and output",
                          tol: 0.000001)
        suite.expectClose(opus.savings, 100_000 * (4 - 0.2) / 1_000_000, "cache reads save the input price they avoid")
        suite.expect(AgentPricing.price(for: "claude-opus-5-5")?.input == 4 && AgentPricing.price(for: "claude-opus-5")?.input == 5,
                     "a point release never inherits the price of the version it extends")
        suite.expect(AgentPricing.price(for: "claude-opus-4-1-20250805")?.input == 15
                        && AgentPricing.price(for: "claude-opus-4-5-20251101")?.input == 5
                        && AgentPricing.price(for: "us.anthropic.claude-sonnet-4-5-20250929-v1:0")?.input == 3
                        && AgentPricing.price(for: "claude-haiku-4-5@20251001")?.output == 5
                        && AgentPricing.price(for: "claude-sonnet-4-5[1m]")?.input == 3,
                     "snapshot dates, cloud prefixes and context tags keep the family's price")
        suite.expect(AgentPricing.price(for: "gpt-5.2-codex")?.input == 1.75 && AgentPricing.price(for: "gpt-5")?.input == 1.25
                        && AgentPricing.price(for: "gpt-6-astra")?.output == 50,
                     "a family matches at a word boundary, so gpt-5 is not gpt-5.2")
        suite.expect(AgentPricing.price(for: "gpt-6-astra-mini") == nil && AgentPricing.price(for: "gpt-reserve") == nil
                        && AgentPricing.price(for: "gpt-6-astra-deep-research") == nil && AgentPricing.price(for: "gpt-6-sol-cyber") == nil
                        && AgentPricing.price(for: "codex-auto-review") == nil
                        && AgentPricing.cost(AgentBillable(tokens: AgentTokens(input: 10)), model: "gpt-reserve").cost == nil,
                     "an unlisted model or sibling has no price rather than a borrowed one")
        suite.expect(AgentPricing.price(for: "claude-opus-5-6") == nil && AgentPricing.price(for: "claude-sonnet-5-5") == nil
                        && AgentPricing.price(for: "claude-opus-6") == nil && AgentPricing.price(for: "gpt-7") == nil
                        && AgentPricing.price(for: "gpt-6-sol-2") == nil,
                     "a version the list does not name yet has no price rather than its predecessor's")
        suite.expect(AgentPricing.price(for: "claude-opus-5-20260101")?.input == 5
                        && AgentPricing.price(for: "claude-3-5-sonnet-latest")?.input == 3
                        && AgentPricing.price(for: "gpt-6-astra-2026-10-01")?.input == 10
                        && AgentPricing.price(for: "gpt-5-2025-08-07")?.input == 1.25,
                     "a dated snapshot or an alias keeps its model's price")
        suite.expect(AgentPricing.price(for: "gpt-5.5-cyber")?.input == 12.5 && AgentPricing.price(for: "gpt-5.4-mini")?.input == 0.75
                        && AgentPricing.price(for: "claude-mythos-preview")?.output == 125
                        && AgentPricing.price(for: "gpt-daybreak-red-latest")?.output == 75
                        && AgentPricing.price(for: "gpt-4o-2024-05-13")?.input == 5 && AgentPricing.price(for: "gpt-4o-2024-08-06")?.input == 2.5,
                     "specialized models, aliases and snapshots priced apart get their own price")
        let writes = AgentBillable(tokens: AgentTokens(cacheWrite: 100_000))
        suite.expect(abs((AgentPricing.cost(writes, model: "gpt-6-astra").cost ?? 0) - 1.25) < 0.000001
                        && abs((AgentPricing.cost(writes, model: "gpt-5.5").cost ?? 0) - 0.5) < 0.000001,
                     "cache writes bill at their own rate where a model has one, and as input otherwise")
        var longFast = AgentBillable(tokens: AgentTokens(input: 300_000, output: 1000))
        longFast.fast = true
        suite.expectClose(AgentPricing.cost(longFast, model: "gpt-6-astra").cost ?? -1,
                          (300_000 * 10 * 4 + 1000 * 50 * 3) / 1_000_000,
                          "a long prompt on the fast tier pays both premiums")
        suite.expectClose(AgentPricing.cost(AgentBillable(tokens: AgentTokens(input: 272_000)), model: "gpt-6-astra").cost ?? -1,
                          2.72, "the long-context premium starts past its threshold")
        let plain = AgentBillable(tokens: AgentTokens(input: 1_000_000))
        var fast = plain
        fast.fast = true
        var domestic = plain
        domestic.domestic = true
        suite.expect(AgentPricing.cost(fast, model: "claude-opus-5").cost == 10
                        && AgentPricing.cost(fast, model: "claude-opus-4-7").cost == 5
                        && abs((AgentPricing.cost(domestic, model: "claude-opus-5").cost ?? 0) - 5.5) < 0.0001,
                     "fast mode doubles where it is sold and US-only inference costs a tenth more")
        let long = AgentBillable(tokens: AgentTokens(input: 250_000, output: 1000))
        suite.expectClose(AgentPricing.cost(long, model: "claude-sonnet-4-5").cost ?? -1,
                          (250_000 * 6 + 1000 * 22.5) / 1_000_000, "older 1M models bill a long prompt at the premium")
        suite.expectClose(AgentPricing.cost(long, model: "claude-sonnet-4-6").cost ?? -1,
                          (250_000 * 3 + 1000 * 15) / 1_000_000, "newer models keep one price across the window")
        var search = AgentBillable()
        search.webSearches = 3
        suite.expectClose(AgentPricing.cost(search, model: "claude-opus-5").cost ?? -1, 0.03, "each web search bills a cent")
        suite.expect(AgentPricing.displayName("claude-opus-5-5") == "Opus 5.5"
                        && AgentPricing.displayName("claude-3-5-sonnet-20241022") == "Sonnet 3.5"
                        && AgentPricing.displayName("claude-sonnet-4-5-20250929") == "Sonnet 4.5"
                        && AgentPricing.displayName("gpt-6-astra") == "GPT-6 Astra"
                        && AgentPricing.displayName("gpt-5.1-codex-max") == "GPT-5.1 Codex Max"
                        && AgentPricing.displayName("gpt-6-astra-2026-10-01") == "GPT-6 Astra"
                        && AgentPricing.displayName("gpt-5-2025-08-07") == "GPT-5"
                        && AgentPricing.displayName("claude-mythos-preview") == "Mythos Preview"
                        && AgentPricing.displayName("claude-3-5-sonnet-latest") == "Sonnet 3.5"
                        && AgentPricing.displayName("gpt-daybreak-red-latest") == "GPT Daybreak Red",
                     "model names read the way people say them, without snapshot dates")
        suite.expect(AgentPricing.displayName("gpt-7") == "GPT-7" && AgentPricing.displayName("claude-opus-6") == "Opus 6"
                        && AgentPricing.displayName("gpt-7-codex") == "GPT-7 Codex",
                     "a model no list knows yet still reads well")
        suite.expect(AgentPlans.claude(organizationType: "claude_max", rateLimitTier: "default_claude_max_20x")
                        == AgentPlan(name: "Max 20×", monthlyPrice: 200)
                        && AgentPlans.claude(organizationType: "claude_pro", rateLimitTier: nil)?.monthlyPrice == 20
                        && AgentPlans.claude(organizationType: nil, rateLimitTier: nil) == nil
                        && AgentPlans.codex(planType: "pro") == AgentPlan(name: "Pro", monthlyPrice: 200)
                        && AgentPlans.codex(planType: "business") == AgentPlan(name: "Business", monthlyPrice: nil)
                        && AgentPlans.claude(organizationType: "claude_ultra", rateLimitTier: "default_claude_ultra")
                        == AgentPlan(name: "Ultra", monthlyPrice: nil),
                     "plans are recognized, and an unknown one keeps its name without a price")
    }

    private static func priceJSON(schema: String = "1", updated: String = "2026-09-22",
                                  claude: String = #"{"id":"claude-opus-5","input":5,"output":25,"cacheRead":0.5,"cacheWrite":6.25,"cacheWriteLong":10}"#,
                                  codex: String = #"{"id":"gpt-6-astra","input":10,"output":50,"cacheRead":1}"#,
                                  extra: String = "") -> Data {
        Data(#"{"schema":\#(schema),"updated":"\#(updated)"\#(extra),"claude":{"webSearch":0.01,"usOnlyMultiplier":1.1,"models":[\#(claude)],"plans":[{"match":"max_20x","name":"Max 20×","monthly":200}]},"codex":{"models":[\#(codex)],"plans":[{"match":"plus","name":"Plus","monthly":20}]}}"#.utf8)
    }

    private static func priceList(_ suite: TestSuite, shipped: AgentPriceList) {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let first = utc.date(from: DateComponents(year: 2026, month: 9, day: 22)) ?? .distantFuture
        suite.expect(shipped.updated >= first && shipped.updated <= Date().addingTimeInterval(86_400)
                        && shipped.claude.count >= 23 && shipped.codex.count >= 69 && shipped.claudePlans.count >= 6,
                     "the shipped list carries a real day, both agents' models and the plans")
        let minimal = AgentPriceList.decode(priceJSON(extra: #","notes":"a field from a later list""#))
        let long = AgentPriceList.decode(priceJSON(codex: #"{"id":"gpt-6-astra","input":10,"output":50,"cacheRead":1,"longContext":{"above":272000,"inputMultiplier":2,"outputMultiplier":1.5}}"#))
        suite.expect(long?.codex.first?.price.longContext == AgentLongContext(above: 272_000, input: 2, output: 1.5),
                     "a model can carry its own long-context threshold and premium")
        suite.expect(minimal?.codex.first?.price == AgentPrice(input: 10, output: 50, cacheRead: 1, cacheWrite: 10, cacheWriteLong: 10)
                        && minimal?.codexPlans == [AgentPriceList.Plan(match: "plus", name: "Plus", monthly: 20)],
                     "unknown fields are ignored and a model without cache writes bills them as input")
        let refused = [
            priceJSON(schema: "2"), priceJSON(updated: "2026-13-40"), priceJSON(schema: "true"),
            priceJSON(claude: #"{"id":"claude-opus-5","input":-5,"output":25,"cacheRead":0.5}"#),
            priceJSON(claude: #"{"id":"claude-opus-5","input":true,"output":25,"cacheRead":0.5}"#),
            priceJSON(claude: #"{"id":"gpt-6","input":5,"output":25,"cacheRead":0.5}"#),
            priceJSON(codex: #"{"id":"claude-opus-5","input":5,"output":25,"cacheRead":0.5}"#),
            priceJSON(codex: #"{"id":"GPT 6","input":5,"output":25,"cacheRead":0.5}"#),
            priceJSON(claude: #"{"id":"claude-opus-5","input":5,"output":25,"cacheRead":0.5},{"id":"claude-opus-5","input":6,"output":30,"cacheRead":0.6}"#),
            priceJSON(claude: #"{"id":"claude-opus-5","input":5,"output":25,"cacheRead":0.5,"fastMultiplier":50}"#),
            priceJSON(codex: #"{"id":"gpt-6-astra","input":10,"output":50,"cacheRead":1,"longContext":{"above":5,"inputMultiplier":2,"outputMultiplier":1.5}}"#),
            priceJSON(codex: #"{"id":"gpt-6-astra","input":10,"output":50,"cacheRead":1,"longContext":true}"#),
            Data("not json".utf8), Data(repeating: 0x20, count: AgentPriceList.maximumSize + 1),
        ]
        suite.expect(refused.allSatisfy { AgentPriceList.decode($0) == nil },
                     "a list that breaks a rule is refused whole: schema, day, prices, names, repeats and size")
        let early = AgentPriceList.decode(priceJSON(updated: "2026-09-22"))
        let late = AgentPriceList.decode(priceJSON(updated: "2026-10-01"))
        suite.expect(AgentPriceList.newer(early, late) == late && AgentPriceList.newer(late, early) == late
                        && AgentPriceList.newer(nil, early) == early && AgentPriceList.newer(early, nil) == early,
                     "the newer of the shipped and downloaded lists wins")
        suite.expect(!AgentPricing.install(shipped), "installing the list in use changes nothing")

        // A newer list prices the history again.
        let store = AgentUsageStore()
        var state = AgentLogState()
        store.apply(AgentLogParser.parseClaude(claudeAssistant(), state: &state, now: Date(timeIntervalSince1970: 0)),
                    file: "a", provider: .claude, tracksTurns: false, modified: Date(timeIntervalSince1970: 0))
        let before = store.records.first?.cost
        let doubled = AgentPriceList(updated: shipped.updated.addingTimeInterval(86_400),
                                     claude: shipped.claude.map { model in
                                        guard model.id == "claude-opus-5-5" else { return model }
                                        let price = model.price
                                        return AgentPriceList.Model(id: model.id, price: AgentPrice(
                                            input: price.input * 2, output: price.output * 2, cacheRead: price.cacheRead * 2,
                                            cacheWrite: price.cacheWrite * 2, cacheWriteLong: price.cacheWriteLong * 2))
                                     },
                                     codex: shipped.codex, claudePlans: shipped.claudePlans, codexPlans: shipped.codexPlans,
                                     webSearch: shipped.webSearch, usOnlyMultiplier: shipped.usOnlyMultiplier)
        AgentPricing.install(doubled)
        store.reprice()
        let after = store.records.first?.cost
        AgentPricing.install(shipped)
        store.reprice()
        suite.expect(before != nil && after.map { abs($0 - 2 * (before ?? 0)) < 0.000001 } == true
                        && store.records.first?.cost == before,
                     "a new list reprices every response already read")
    }

    // MARK: Claude Code logs

    private static func claudeParsing(_ suite: TestSuite) {
        var state = AgentLogState()
        let now = Date(timeIntervalSince1970: 0)
        let entries = AgentLogParser.parseClaude(claudeAssistant(cwd: "/Users/me/code/app/.claude/worktrees/fix-1"),
                                                 state: &state, now: now)
        guard case .usage(let key, let record, let billable)? = entries.first(where: {
            if case .usage = $0 { return true }
            return false
        }) else {
            suite.expect(false, "an assistant reply yields its usage")
            return
        }
        suite.expect(key == "claude:msg_1:req_1" && record.model == "claude-opus-5-5" && record.session == "s1"
                        && record.project == "app",
                     "a reply is keyed by message and request, and a worktree belongs to its repository")
        suite.expect(record.tokens == AgentTokens(input: 2, cacheWrite: 17_218, cacheRead: 43_134, output: 225, reasoning: 32)
                        && billable.longCacheWrite == 17_218,
                     "input, both cache kinds, output and thinking are read from the reply")
        var synthetic = AgentLogState()
        suite.expect(!AgentLogParser.parseClaude(claudeAssistant(model: "<synthetic>"), state: &synthetic, now: now)
                        .contains { if case .usage = $0 { return true }; return false },
                     "a synthetic reply bills nothing")
        suite.expect(AgentLogParser.parseClaude(line(#"{"type":"summary","summary":"\"type\":\"assistant\""}"#),
                                                state: &synthetic, now: now).isEmpty,
                     "an escaped key inside a value never passes for structure")

        // Streamed replies are logged once per block with the output so far.
        let store = AgentUsageStore()
        for (output, file) in [(8, "a"), (334, "a"), (334, "b")] {
            var local = AgentLogState()
            store.apply(AgentLogParser.parseClaude(claudeAssistant(output: output), state: &local, now: now),
                        file: file, provider: .claude, tracksTurns: false, modified: now)
        }
        suite.expect(store.records.count == 1 && store.records.first?.tokens.output == 334,
                     "duplicate lines across blocks and files count once, at their final output")
        let expected = AgentPricing.cost(AgentBillable(tokens: AgentTokens(input: 2, cacheWrite: 17_218, cacheRead: 43_134,
                                                                          output: 334, reasoning: 32),
                                                       longCacheWrite: 17_218), model: "claude-opus-5-5").cost
        suite.expect(store.records.first?.cost == expected, "a merged reply is priced from its merged counts")
        store.dropRecords(before: Date(timeIntervalSince1970: 2_000_000_000))
        var later = AgentLogState()
        store.apply(AgentLogParser.parseClaude(claudeAssistant(output: 400), state: &later, now: now),
                    file: "a", provider: .claude, tracksTurns: false, modified: now)
        suite.expect(store.records.count == 1 && store.records.first?.tokens.output == 400,
                     "dropping old history keeps later lookups consistent")
    }

    private static func claudeTurns(_ suite: TestSuite) {
        let now = AgentTimestamp.parse("2026-09-21T23:45:00.000Z")!
        var state = AgentLogState()
        let store = AgentUsageStore()
        store.reportsTransitions = true
        func feed(_ data: Data) -> [AgentUsageEvent] {
            store.apply(AgentLogParser.parseClaude(data, state: &state, now: now), file: "main", provider: .claude,
                        tracksTurns: true, modified: now, now: now)
        }
        suite.expect(feed(claudeUser(meta: true)).isEmpty && store.live.isEmpty, "a meta line starts no turn")
        var side = AgentLogState()
        let sidePrompt = line(#"{"type":"user","isSidechain":true,"timestamp":"2026-09-21T23:41:00.000Z","sessionId":"s1","message":{"role":"user","content":"Explore the repo"}}"#)
        suite.expect(AgentLogParser.parseClaude(sidePrompt, state: &side, now: now).isEmpty && !side.turnOpen,
                     "a subagent's own prompt never opens a turn")
        _ = feed(claudeUser(time: "2026-09-21T23:40:00.000Z"))
        suite.expect(store.live.count == 1 && store.live.first?.started == AgentTimestamp.parse("2026-09-21T23:40:00.000Z"),
                     "a prompt starts a turn at its own time")
        _ = feed(claudeAssistant(stop: "tool_use"))
        suite.expect(AgentLogParser.parseClaude(claudeUser(toolResult: true), state: &state, now: now) == [.turnActive(nil)],
                     "a tool result inside a turn is not decoded")
        let quoted = line(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"if contains(line, \"[Request interrupted by user\") || contains(line, \"<local-command-stdout>\")"}]}}"#)
        suite.expect(AgentLogParser.parseClaude(quoted, state: &state, now: now) == [.turnActive(nil)] && store.live.count == 1,
                     "a tool result quoting an interruption does not end the turn")
        _ = feed(claudeAssistant(id: "msg_2", request: "req_2", stop: "end_turn", sidechain: true))
        suite.expect(store.live.count == 1, "a subagent finishing does not finish the turn it serves")
        let finished = feed(claudeAssistant(id: "msg_3", request: "req_3", stop: "end_turn", time: "2026-09-21T23:44:30.000Z"))
        guard case .finished(let provider, let duration, let cost, let tokens, let project)? = finished.first else {
            suite.expect(false, "the end of a turn is reported")
            return
        }
        suite.expect(provider == .claude && duration == 270 && project == "app" && store.live.isEmpty,
                     "a finished turn reports its length and project, and stops working")
        suite.expect(cost > 0 && tokens == 3 * AgentTokens(input: 2, cacheWrite: 17_218, cacheRead: 43_134, output: 225).total,
                     "a finished turn carries what its replies spent")
        _ = feed(claudeUser())
        suite.expect(feed(line(#"{"type":"user","message":{"content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#)).isEmpty
                        && store.live.isEmpty, "an interrupted turn ends without a notice")
        _ = feed(claudeUser(#"<command-name>/model</command-name>"#))
        _ = feed(line(#"{"type":"user","message":{"content":"<local-command-stdout>Set model</local-command-stdout>"}}"#))
        suite.expect(store.live.isEmpty, "a local command never leaves a turn working")
        // Claude Code 2.1.280 writes the output as a system line, not a user one.
        var cleared = AgentLogState()
        let clear = AgentLogParser.parseClaude(claudeUser("<command-name>/clear</command-name>\\n<command-message>clear</command-message>"),
                                               state: &cleared, now: now)
        let output = AgentLogParser.parseClaude(line(#"{"type":"system","subtype":"local_command","content":"<local-command-stdout></local-command-stdout>"}"#),
                                                state: &cleared, now: now)
        suite.expect(clear.isEmpty && output.isEmpty && !cleared.turnOpen,
                     "a local command whose output is a system line never opens a turn")
        _ = feed(claudeUser())
        _ = feed(claudeUser("<command-name>/compact</command-name>"))
        suite.expect(store.live.isEmpty, "a local command typed while a turn reads as open ends it")
        var interrupted = AgentLogState(turnOpen: true)
        suite.expect(AgentLogParser.parseClaude(line(#"{"type":"user","message":{"content":"[Request interrupted by user]"}}"#),
                                                state: &interrupted, now: now)
                        == [.turnEnded(nil, completed: false, duration: nil, failed: false)],
                     "an interruption is not an error")
        var errored = AgentLogState(turnOpen: true)
        let failure = AgentLogParser.parseClaude(claudeAssistant(model: "<synthetic>", stop: "stop_sequence"), state: &errored, now: now)
        suite.expect(failure.contains(.turnEnded(AgentTimestamp.parse("2026-09-21T23:42:45.078Z"), completed: false,
                                                 duration: nil, failed: true)),
                     "an error written in place of a reply ends the turn as failed")
        _ = feed(claudeUser())
        suite.expect(feed(claudeAssistant(id: "msg_4", request: "req_4", model: "<synthetic>", stop: "stop_sequence",
                                          time: "2026-09-21T23:44:40.000Z")).isEmpty && store.live.isEmpty,
                     "an error written in place of a reply ends the turn without a finish notice")
        let quiet = AgentUsageStore()
        var quietState = AgentLogState()
        let replay = [claudeUser(), claudeAssistant(stop: "end_turn")].flatMap {
            quiet.apply(AgentLogParser.parseClaude($0, state: &quietState, now: now), file: "main", provider: .claude,
                        tracksTurns: true, modified: now)
        }
        suite.expect(replay.isEmpty, "history read at start is not replayed as news")
        let late = AgentUsageStore()
        late.reportsTransitions = true
        var lateState = AgentLogState()
        let found = [claudeUser(), claudeAssistant(stop: "end_turn", time: "2026-09-21T23:44:30.000Z")].flatMap {
            late.apply(AgentLogParser.parseClaude($0, state: &lateState, now: now), file: "archived", provider: .claude,
                       tracksTurns: true, modified: now, now: now.addingTimeInterval(AgentUsageStore.lateEnd + 60))
        }
        suite.expect(found.isEmpty && late.live.isEmpty,
                     "a turn that ended long before its log was found, like an archived session, is not news")
        _ = feed(claudeUser(time: "2026-09-21T23:50:00.000Z"))
        store.closeIdleTurns(now: AgentTimestamp.parse("2026-09-22T00:05:00.000Z")!, after: NotchAgentSupport.idleTurn)
        suite.expect(store.live.isEmpty, "a turn that has written nothing for a while stops showing as working")
    }

    // MARK: Codex logs

    private static func codexParsing(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 0)
        var state = AgentLogState()
        let meta = line(#"{"timestamp":"2026-09-22T14:44:23.705Z","type":"session_meta","payload":{"id":"s9","cwd":"/Users/me/code/web"}}"#)
        let context = line(#"{"timestamp":"2026-09-22T14:44:24.000Z","type":"turn_context","payload":{"model":"gpt-6-astra","cwd":"/Users/me/code/web"}}"#)
        let started = line(#"{"timestamp":"2026-09-22T14:44:25.000Z","type":"event_msg","payload":{"type":"task_started","started_at":1790088265}}"#)
        let record = line(#"{"timestamp":"2026-09-22T14:44:53.847Z","type":"token_usage_record","payload":{"session_id":"s9","response_id":"resp_1","usage":{"input_tokens":32167,"cached_input_tokens":20224,"cache_write_input_tokens":0,"output_tokens":156,"reasoning_output_tokens":7,"total_tokens":32323}}}"#)
        let count = line(#"{"timestamp":"2026-09-22T14:44:53.977Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":32167,"cached_input_tokens":20224,"output_tokens":156,"total_tokens":32323},"last_token_usage":{"input_tokens":32167,"cached_input_tokens":20224,"output_tokens":156,"total_tokens":32323}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":72.0,"window_minutes":10080,"resets_at":1790390402},"secondary":null,"plan_type":"pro"}}}"#)
        let complete = line(#"{"timestamp":"2026-09-22T14:52:00.000Z","type":"event_msg","payload":{"type":"task_complete","completed_at":1790088720,"duration_ms":458431}}"#)
        let store = AgentUsageStore()
        store.reportsTransitions = true
        var events: [AgentUsageEvent] = []
        for data in [meta, context, started, record, count, complete] {
            events += store.apply(AgentLogParser.parseCodex(data, state: &state, now: now), file: "main",
                                  provider: .codex, tracksTurns: true, modified: now,
                                  now: Date(timeIntervalSince1970: 1_790_088_730))
        }
        suite.expect(store.records.count == 1, "a response with its own record is not counted again from the totals")
        let usage = store.records.first
        suite.expect(usage?.tokens == AgentTokens(input: 11_943, cacheWrite: 0, cacheRead: 20_224, output: 156, reasoning: 7)
                        && usage?.model == "gpt-6-astra" && usage?.project == "web" && usage?.session == "s9",
                     "cached input is taken out of the input count and the turn's model is kept")
        // One typed term per line: Swift 6.0.3 cannot infer this literal arithmetic in time.
        let inputCost: Double = 11_943 * 10
        let cacheReadCost: Double = 20_224 * 1
        let outputCost: Double = 156 * 50
        let listPriceCost: Double = (inputCost + cacheReadCost + outputCost) / 1_000_000
        suite.expectClose(usage?.cost ?? -1, listPriceCost,
                          "a response is priced at its model's list price")
        let window = store.limits[.codex]?.windows.first
        suite.expect(window?.kind == .weekly && window?.usedPercent == 72 && window?.minutes == 10_080
                        && window?.resetsAt == Date(timeIntervalSince1970: 1_790_390_402)
                        && store.codexPlan == "pro",
                     "the limits Codex logs arrive with their length, renewal and plan")
        suite.expect(events == [.finished(provider: .codex, duration: 458.431, cost: usage?.cost ?? 0,
                                          tokens: usage?.tokens.total ?? 0, project: "web")],
                     "a completed task reports the duration Codex measured")

        // A model with an allowance of its own logs it under another id.
        var sparkState = AgentLogState()
        let spark = line(#"{"timestamp":"2026-09-22T14:53:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex_spark","limit_name":"GPT-5.3-Codex-Spark","primary":{"used_percent":3.0,"window_minutes":300,"resets_at":1790100000},"secondary":{"used_percent":1.0,"window_minutes":10080,"resets_at":1790390402},"plan_type":"pro"}}}"#)
        let sparkEntries = AgentLogParser.parseCodex(spark, state: &sparkState, now: now)
        store.apply(sparkEntries, file: "main", provider: .codex, tracksTurns: true, modified: now)
        suite.expect(!sparkEntries.contains { if case .limits = $0 { return true }; return false }
                        && store.limits[.codex]?.windows.map(\.usedPercent) == [72],
                     "a model's own allowance never takes the place of the main one")
        suite.expect(AgentLogParser.isMainBucket([:]) && AgentLogParser.isMainBucket(["limit_id": "codex"])
                        && !AgentLogParser.isMainBucket(["limit_id": "codex_spark"]),
                     "a reading without an id, as older logs write, is the main allowance")

        // An archived session read later holds an older plan than the one in use.
        var archivedState = AgentLogState()
        let archived = line(#"{"timestamp":"2026-08-01T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","primary":{"used_percent":5.0,"window_minutes":10080,"resets_at":1786000000},"secondary":null,"plan_type":"plus"}}}"#)
        let archivedEntries = AgentLogParser.parseCodex(archived, state: &archivedState, now: now)
        let archivedDate = AgentTimestamp.parse("2026-08-01T10:00:00.000Z")!
        store.apply(archivedEntries, file: "archived", provider: .codex, tracksTurns: true, modified: now)
        suite.expect(archivedEntries.contains(.plan("plus", observedAt: archivedDate)) && store.codexPlan == "pro"
                        && store.limits[.codex]?.windows.map(\.usedPercent) == [72],
                     "an older session read later changes neither the plan nor the limits in use")
        let upgraded = AgentTimestamp.parse("2026-09-22T15:00:00.000Z")!
        store.apply([.plan("business", observedAt: upgraded)], file: "main", provider: .codex, tracksTurns: true,
                    modified: now)
        suite.expect(store.codexPlan == "business", "a newer reading changes the plan")

        // A thread on the fast tier bills every response at its premium.
        var fastState = AgentLogState()
        let fastStore = AgentUsageStore()
        let settings = line(#"{"timestamp":"2026-09-22T14:44:24.500Z","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"service_tier":"fast","model":"gpt-6-astra"}}}"#)
        for data in [meta, context, settings, record] {
            fastStore.apply(AgentLogParser.parseCodex(data, state: &fastState, now: now), file: "fast", provider: .codex,
                            tracksTurns: false, modified: now)
        }
        suite.expectClose(fastStore.records.first?.cost ?? -1, 2 * (usage?.cost ?? 0),
                          "the fast tier Codex records doubles the response's price")
        suite.expect(AgentLogParser.fastTier("priority") && AgentLogParser.fastTier("Fast") && !AgentLogParser.fastTier("default")
                        && !AgentLogParser.fastTier("flex"),
                     "fast mode is recognized by both of its names")

        // Older logs carry running totals only.
        var legacy = AgentLogState()
        let legacyStore = AgentUsageStore()
        func total(_ input: Int, _ output: Int, last: Bool) -> Data {
            let lastPart = last ? #","last_token_usage":{"input_tokens":\#(input - 100),"output_tokens":\#(output - 10)}"# : ""
            return line(#"{"timestamp":"2026-09-22T15:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"output_tokens":\#(output)}\#(lastPart)}}}"#)
        }
        for data in [total(100, 10, last: false), total(100, 10, last: false), total(300, 40, last: false), total(450, 60, last: true)] {
            legacyStore.apply(AgentLogParser.parseCodex(data, state: &legacy, now: now), file: "old", provider: .codex,
                              tracksTurns: false, modified: now)
        }
        suite.expect(legacyStore.records.map(\.tokens.input) == [100, 200, 350]
                        && legacyStore.records.map(\.tokens.output) == [10, 30, 50],
                     "running totals count the growth once and prefer the logged last response")

        let slots = AgentLogParser.codexWindows([
            "primary": ["used_percent": 40.0, "window_minutes": 10_080, "resets_in_seconds": 60],
            "secondary": ["used_percent": 12.5, "window_minutes": 300, "resets_at": 1_790_000_000],
        ], observed: Date(timeIntervalSince1970: 1_000))
        suite.expect(slots?.map(\.kind) == [.session, .weekly] && slots?.last?.resetsAt == Date(timeIntervalSince1970: 1_060),
                     "windows are told apart by length, and a relative renewal counts from the reading")
        var aborted = AgentLogState(turnOpen: true)
        suite.expect(AgentLogParser.parseCodex(line(#"{"timestamp":"2026-09-22T15:00:00.000Z","type":"event_msg","payload":{"type":"turn_aborted","duration_ms":10961}}"#),
                                               state: &aborted, now: now)
                        == [.turnEnded(AgentTimestamp.parse("2026-09-22T15:00:00.000Z"), completed: false, duration: 10.961)],
                     "an aborted turn ends without counting as finished")
        let event = line(#"{"timestamp":"2026-09-22T15:00:00.000Z","ordinal":3,"type":"event_msg","payload":{"type":"token_count","info":null}}"#)
        let kind = AgentLogParser.firstType(event)
        suite.expect(kind?.name == "event_msg" && AgentLogParser.firstType(event, from: kind?.end ?? 0)?.name == "token_count",
                     "a Codex line's own type is found first, then its event's")
        // Compacted history and tool output quote whole records, keys and all.
        let quoted = #"{"type":"event_msg","payload":{"type":"task_complete","duration_ms":1}}"#
        let history = String(repeating: quoted, count: 20_000)
        var quiet = AgentLogState(turnOpen: true)
        suite.expect(AgentLogParser.parseCodex(line(#"{"timestamp":"2026-09-22T15:00:00.000Z","type":"compacted","payload":{"replacement_history":[\#(history)]}}"#),
                                               state: &quiet, now: now).isEmpty
                        && AgentLogParser.parseCodex(line(#"{"timestamp":"2026-09-22T15:00:00.000Z","type":"event_msg","payload":{"type":"item_completed","item":\#(quoted)}}"#),
                                                     state: &quiet, now: now).isEmpty
                        && quiet == AgentLogState(turnOpen: true),
                     "records quoted inside another line's payload are not read as the line's own")
    }

    // MARK: OpenCode logs

    private static func openCodeParsing(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 0)
        var state = AgentLogState()

        // 1. User turn began
        let userMsg = line("""
        {"session_id":"s_oc_1","time_created":1790088000,"directory":"/Users/me/code/backend","role":"user","parts":[{"type":"text","text":"Implement feature"}]}
        """)
        let userEntries = AgentLogParser.parseOpenCode(userMsg, state: &state, now: now)
        let beganDate = Date(timeIntervalSince1970: 1_790_088_000)
        suite.expect(userEntries == [.turnBegan(beganDate)], "a user message in OpenCode marks the turn began")

        // 2. Assistant message in progress (tool-calls) with reported cost and exact tokens
        let assistantActive = line("""
        {"id":"msg_1","session_id":"s_oc_1","time_created":1790088005,"directory":"/Users/me/code/backend","role":"assistant","model_id":"stealth/ox-alpha","provider_id":"relay","cost":0.0042,"tokens":{"total":1250,"input":1000,"output":200,"reasoning":50,"cache":{"read":50,"write":0}},"finish":"tool-calls"}
        """)
        let activeEntries = AgentLogParser.parseOpenCode(assistantActive, state: &state, now: now)
        guard case .usage(let key, let record, _)? = activeEntries.first(where: {
            if case .usage = $0 { return true }
            return false
        }) else {
            suite.expect(false, "an OpenCode assistant reply yields its usage")
            return
        }
        suite.expect(key == "opencode:s_oc_1:msg_1" && record.model == "stealth/ox-alpha"
                        && record.project == "backend" && record.session == "s_oc_1"
                        && record.cost == 0.0042,
                     "OpenCode uses exact reported cost and keeps project, session and model")
        suite.expect(record.tokens == AgentTokens(input: 1000, cacheWrite: 0, cacheRead: 50, output: 250, reasoning: 50),
                     "exact token breakdowns are parsed from OpenCode tokens dictionary")
        let activeDate = Date(timeIntervalSince1970: 1_790_088_005)
        suite.expect(activeEntries.contains(.turnActive(activeDate)),
                     "an in-progress or tool-calling assistant message reports the turn active")

        // 3. Assistant message completed (finish: stop)
        let assistantStop = line("""
        {"id":"msg_2","session_id":"s_oc_1","time_created":1790088020,"directory":"/Users/me/code/backend","role":"assistant","model_id":"stealth/ox-alpha","provider_id":"relay","cost":0.0015,"tokens":{"total":500,"input":400,"output":100,"reasoning":0,"cache":{"read":0,"write":0}},"finish":"stop"}
        """)
        let stopEntries = AgentLogParser.parseOpenCode(assistantStop, state: &state, now: now)
        let stopDate = Date(timeIntervalSince1970: 1_790_088_020)
        suite.expect(stopEntries.contains(.turnEnded(stopDate, completed: true, duration: 20)),
                     "a finished response computes duration from user turn start")

        // 4. Store application and event emission
        let store = AgentUsageStore()
        store.reportsTransitions = true
        var storeEvents: [AgentUsageEvent] = []
        for entries in [userEntries, activeEntries, stopEntries] {
            storeEvents += store.apply(entries, file: "opencode.db#s_oc_1", provider: .opencode,
                                       tracksTurns: true, modified: now, now: stopDate)
        }
        suite.expect(store.records.count == 2, "OpenCode records are stored in AgentUsageStore")
        let totalCost = store.records.filter { $0.provider == .opencode }.compactMap(\.cost).reduce(0, +)
        suite.expect(abs(totalCost - 0.0057) < 0.000001,
                     "OpenCode total cost aggregates reported costs")
        suite.expect(storeEvents == [.finished(provider: .opencode, duration: 20, cost: 0.0057,
                                              tokens: 1800, project: "backend")],
                     "OpenCode turn finish generates .finished usage event with accumulated turn cost and tokens")

        // 5. Model pricing fallback: unpriced vs list price fallback
        var fallbackState = AgentLogState()
        let unpricedMsg = line("""
        {"id":"msg_3","session_id":"s_oc_2","time_created":1790088030,"directory":"/Users/me/code/web","role":"assistant","model_id":"unknown-local-model","cost":0,"tokens":{"total":100,"input":80,"output":20,"reasoning":0,"cache":{"read":0,"write":0}},"finish":"stop"}
        """)
        let unpricedEntries = AgentLogParser.parseOpenCode(unpricedMsg, state: &fallbackState, now: now)
        if case .usage(_, let rec, _)? = unpricedEntries.first(where: { if case .usage = $0 { return true }; return false }) {
            suite.expect(rec.cost == 0 && !rec.reportedCost,
                         "a zero OpenCode recorded for a model the list does not know is that reply's cost")
        } else {
            suite.expect(false, "an unpriced response still records usage")
        }

        let pricedFallback = line("""
        {"id":"msg_4","session_id":"s_oc_3","time_created":1790088040,"directory":"/Users/me/code/web","role":"assistant","model_id":"gpt-6-astra","cost":0,"tokens":{"total":100,"input":80,"output":20,"reasoning":0,"cache":{"read":0,"write":0}},"finish":"stop"}
        """)
        let pricedEntries = AgentLogParser.parseOpenCode(pricedFallback, state: &fallbackState, now: now)
        if case .usage(_, let rec, _)? = pricedEntries.first(where: { if case .usage = $0 { return true }; return false }) {
            suite.expectClose(rec.cost ?? -1, 0.0018, "a zero cost with a listed model calculates from list price",
                              tol: 0.000001)
        } else {
            suite.expect(false, "a listed model with zero reported cost calculates from price list")
        }

        // 6. Display names
        suite.expect(AgentPricing.displayName("relay/vendor/claude-opus-5-5") == "Opus 5.5"
                        && AgentPricing.displayName("relay/claude-opus-5.5") == "Opus 5.5"
                        && AgentPricing.displayName("stealth/ox-alpha") == "ox-alpha",
                     "a router's prefixes are dropped and a dotted version reads like a dashed one")

        // 7. SQLite reader with temporary database
        let tmpDir = FileManager.default.temporaryDirectory.appending(path: "vorss-opencode-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let dbPath = tmpDir.appending(path: "opencode.db").path

        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK, let db else {
            suite.expect(false, "temporary OpenCode database opens")
            return
        }
        sqlite3_exec(db, """
        CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, time_created INTEGER, time_updated INTEGER);
        CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
        """, nil, nil, nil)
        sqlite3_exec(db, """
        INSERT INTO session VALUES ('s1', '/Users/me/code/app', 1790088000000, 1790088020000);
        INSERT INTO message VALUES ('m1', 's1', 1790088000000, 1790088000000, '{"role":"user","parts":[{"type":"text","text":"hello"}]}');
        INSERT INTO message VALUES ('m2', 's1', 1790088005000, 1790088005000, '{"role":"assistant","model_id":"stealth/ox-alpha","cost":0.001,"tokens":{"total":100,"input":80,"output":20,"reasoning":0,"cache":{"read":0,"write":0}},"finish":"stop"}');
        """, nil, nil, nil)
        sqlite3_close(db)

        let cursor = AgentLogCursor(path: dbPath, provider: .opencode)
        var linesRead: [String] = []
        AgentOpenCodeReader.readAppended(cursor) { data in
            linesRead.append(String(decoding: data, as: UTF8.self))
        }
        suite.expect(linesRead.count == 2 && cursor.offset == 2,
                     "OpenCode reader retrieves messages in order and moves past the last row read")

        // Incremental check: add message m3
        var db2: OpaquePointer?
        guard sqlite3_open(dbPath, &db2) == SQLITE_OK, let db2 else {
            suite.expect(false, "re-opening OpenCode database")
            return
        }
        sqlite3_exec(db2, """
        INSERT INTO message VALUES ('m3', 's1', 1790088010000, 1790088010000, '{"role":"user","parts":[{"type":"text","text":"next"}]}');
        """, nil, nil, nil)
        sqlite3_close(db2)

        linesRead.removeAll()
        AgentOpenCodeReader.readAppended(cursor) { data in
            linesRead.append(String(decoding: data, as: UTF8.self))
        }
        suite.expect(linesRead.count == 1 && linesRead.first?.contains("m3") == true && cursor.offset == 3,
                     "incremental read only returns messages saved after the previous read")

        // User message metadata updates (e.g. summary diffs) are ignored on incremental reads
        var db3: OpaquePointer?
        guard sqlite3_open(dbPath, &db3) == SQLITE_OK, let db3 else {
            suite.expect(false, "re-opening OpenCode database for user update test")
            return
        }
        sqlite3_exec(db3, """
        UPDATE message SET time_updated = 1790088015000, data = '{"role":"user","summary":{"diffs":[]}}' WHERE id = 'm3';
        """, nil, nil, nil)
        sqlite3_close(db3)

        linesRead.removeAll()
        AgentOpenCodeReader.readAppended(cursor) { data in
            linesRead.append(String(decoding: data, as: UTF8.self))
        }
        suite.expect(linesRead.isEmpty, "incremental read ignores subsequent updates to user message metadata")

        // Cancellation check
        linesRead.removeAll()
        AgentOpenCodeReader.readAppended(cursor, shouldContinue: { false }) { data in
            linesRead.append(String(decoding: data, as: UTF8.self))
        }
        suite.expect(linesRead.isEmpty, "cancellation avoids reading entries")

        // 8. Multi-session turn concurrency and isolation
        var multiState = AgentLogState()
        let sAUser = line(#"{"session_id":"s_A","time_created":1790089000,"directory":"/projA","role":"user","parts":[{"type":"text","text":"A"}]}"#)
        let sBUser = line(#"{"session_id":"s_B","time_created":1790089005,"directory":"/projB","role":"user","parts":[{"type":"text","text":"B"}]}"#)
        let entriesA1 = AgentLogParser.parseOpenCode(sAUser, state: &multiState, now: now)
        let entriesB1 = AgentLogParser.parseOpenCode(sBUser, state: &multiState, now: now)
        suite.expect(entriesA1 == [.turnBegan(Date(timeIntervalSince1970: 1_790_089_000))],
                     "session A begins its turn")
        suite.expect(entriesB1 == [.turnBegan(Date(timeIntervalSince1970: 1_790_089_005))],
                     "session B begins its turn without ending session A's turn")

        let sAStop = line(#"{"id":"mA","session_id":"s_A","time_created":1790089020,"directory":"/projA","role":"assistant","cost":0.002,"tokens":{"total":100,"input":80,"output":20},"finish":"stop"}"#)
        let entriesA2 = AgentLogParser.parseOpenCode(sAStop, state: &multiState, now: now)
        suite.expect(entriesA2.contains(.turnEnded(Date(timeIntervalSince1970: 1_790_089_020), completed: true, duration: 20)),
                     "session A ends with duration calculated from session A start")
        suite.expect(multiState.openCodeSessions["s_B"]?.turnOpen == true,
                     "session B remains open while session A completes")

        let sBStop = line(#"{"id":"mB","session_id":"s_B","time_created":1790089035,"directory":"/projB","role":"assistant","cost":0.003,"tokens":{"total":200,"input":150,"output":50},"finish":"stop"}"#)
        let entriesB2 = AgentLogParser.parseOpenCode(sBStop, state: &multiState, now: now)
        suite.expect(entriesB2.contains(.turnEnded(Date(timeIntervalSince1970: 1_790_089_035), completed: true, duration: 30)),
                     "session B ends with duration calculated from session B start")
        suite.expect(multiState.openCodeSessions["s_B"]?.turnOpen == false,
                     "session B is now closed")

        // 9. Cost preservation when assistant rows are updated in place
        let updateStore = AgentUsageStore()
        var uState = AgentLogState()
        let msgInitial = line(#"{"id":"m_up","session_id":"s_u","time_created":1790089100,"directory":"/p","role":"assistant","model_id":"stealth/ox-alpha","cost":0.002,"tokens":{"total":100,"input":80,"output":20}}"#)
        updateStore.apply(AgentLogParser.parseOpenCode(msgInitial, state: &uState, now: now),
                          file: "db#s_u", provider: .opencode, tracksTurns: true, modified: now)
        suite.expect(updateStore.records.first?.cost == 0.002, "initial reported cost is recorded")

        let msgMoreTokens = line(#"{"id":"m_up","session_id":"s_u","time_created":1790089100,"time_updated":1790089105,"directory":"/p","role":"assistant","model_id":"stealth/ox-alpha","cost":0.0035,"tokens":{"total":200,"input":150,"output":50}}"#)
        updateStore.apply(AgentLogParser.parseOpenCode(msgMoreTokens, state: &uState, now: now),
                          file: "db#s_u", provider: .opencode, tracksTurns: true, modified: now)
        suite.expect(updateStore.records.count == 1 && updateStore.records.first?.cost == 0.0035
                        && updateStore.records.first?.tokens.total == 200,
                     "updating row with more tokens updates and preserves reported cost")

        let msgFinalCost = line(#"{"id":"m_up","session_id":"s_u","time_created":1790089100,"time_updated":1790089110,"directory":"/p","role":"assistant","model_id":"stealth/ox-alpha","cost":0.004,"tokens":{"total":200,"input":150,"output":50},"finish":"stop"}"#)
        updateStore.apply(AgentLogParser.parseOpenCode(msgFinalCost, state: &uState, now: now),
                          file: "db#s_u", provider: .opencode, tracksTurns: true, modified: now)
        suite.expect(updateStore.records.count == 1 && updateStore.records.first?.cost == 0.004,
                     "final cost adjustment with identical tokens preserves reported cost")

        // 10. WAL modification discovery
        let walDir = FileManager.default.temporaryDirectory.appending(path: "vorss-wal-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: walDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: walDir) }
        let root = AgentLogRoot.canonical(walDir)
        let oldDb = root.appending(path: "opencode.db")
        let recentWal = root.appending(path: "opencode.db-wal")
        FileManager.default.createFile(atPath: oldDb.path, contents: Data())
        FileManager.default.createFile(atPath: recentWal.path, contents: Data())
        let oldDate = Date().addingTimeInterval(-14 * 7 * 86_400)
        try? FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldDb.path)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: recentWal.path)
        let discovered = AgentLogReader.discover([AgentLogRoot(provider: .opencode, url: root)],
                                                since: Date().addingTimeInterval(-13 * 7 * 86_400))
        suite.expect(discovered.map(\.path) == [oldDb.path],
                     "an OpenCode database whose main file is older than horizon is admitted when its WAL was recently modified")

        // 11. User message update after assistant finish does not re-open turn
        var postFinishState = AgentLogState()
        let uMsg = line(#"{"id":"usr_1","session_id":"s_pf","time_created":1790089200,"directory":"/p","role":"user","parts":[{"type":"text","text":"go"}]}"#)
        let aMsg = line(#"{"id":"ast_1","parentID":"usr_1","session_id":"s_pf","time_created":1790089205,"directory":"/p","role":"assistant","finish":"stop"}"#)
        _ = AgentLogParser.parseOpenCode(uMsg, state: &postFinishState, now: now)
        let stopParsed = AgentLogParser.parseOpenCode(aMsg, state: &postFinishState, now: now)
        suite.expect(stopParsed.contains(.turnEnded(Date(timeIntervalSince1970: 1_790_089_205), completed: true, duration: 5)),
                     "assistant finishes the turn")
        suite.expect(postFinishState.openCodeSessions["s_pf"]?.turnOpen == false, "turn is closed")

        // Simulate OpenCode updating usr_1 with summary diffs after assistant finished
        let uMsgUpdated = line(#"{"id":"usr_1","session_id":"s_pf","time_created":1790089200,"time_updated":1790089206,"directory":"/p","role":"user","summary":{"diffs":[]}}"#)
        let updateParsed = AgentLogParser.parseOpenCode(uMsgUpdated, state: &postFinishState, now: now)
        suite.expect(updateParsed.isEmpty, "re-reading updated user message does not emit events")
        suite.expect(postFinishState.openCodeSessions["s_pf"]?.turnOpen == false, "turn remains closed after user message update")

        // 12. Aborted assistant turn (Ctrl+C / MessageAbortedError) ends turn with completed: false
        var abortState = AgentLogState()
        let uMsgAbort = line(#"{"id":"usr_ab","session_id":"s_ab","time_created":1790089300,"directory":"/p","role":"user"}"#)
        _ = AgentLogParser.parseOpenCode(uMsgAbort, state: &abortState, now: now)
        suite.expect(abortState.openCodeSessions["s_ab"]?.turnOpen == true, "turn opened")

        let aMsgAbort = line(#"{"id":"ast_ab","parentID":"usr_ab","session_id":"s_ab","time_created":1790089305,"directory":"/p","role":"assistant","error":{"name":"MessageAbortedError","data":{"message":"Aborted"}}}"#)
        let abortParsed = AgentLogParser.parseOpenCode(aMsgAbort, state: &abortState, now: now)
        suite.expect(abortParsed.contains(.turnEnded(Date(timeIntervalSince1970: 1_790_089_305), completed: false, duration: 5)),
                     "aborted turn ends with completed: false")
        suite.expect(abortState.openCodeSessions["s_ab"]?.turnOpen == false, "turn is closed after abort")

        // 14. Model names
        suite.expect(AgentPricing.displayName("relay/claude-sonnet-5.1:deep") == "Sonnet 5.1",
                     "a router's tag after a Claude model names a mode of the same model")
        suite.expect(AgentPricing.displayName("q7") == "q7" && AgentPricing.displayName("q7-mini") == "q7-mini",
                     "names that start with neither claude nor gpt show as written")
        suite.expect(AgentPricing.displayName("gpt-astra:20b") == "GPT Astra:20B"
                        && AgentPricing.displayName("gpt-astra:120b") == "GPT Astra:120B",
                     "a size after a colon stays in the name, so each build keeps a row of its own")

        // 15. Repricing keeps OpenCode's recorded cost
        let beforeCost = store.records.first { $0.provider == .opencode }?.cost
        suite.expect(beforeCost != nil, "OpenCode record has cost before reprice")
        store.reprice()
        suite.expect(store.records.first { $0.provider == .opencode }?.cost == beforeCost,
                     "repricing keeps OpenCode's recorded cost")

        // 16. Fallback model string representation in json["model"]
        var modelFallbackState = AgentLogState()
        let stringModelMsg = line(#"{"id":"ast_str_m","session_id":"s_sm","time_created":1790089400,"directory":"/p","role":"assistant","model":"relay/claude-opus-5.5","tokens":{"input":10,"output":5}}"#)
        let stringModelEntries = AgentLogParser.parseOpenCode(stringModelMsg, state: &modelFallbackState, now: now)
        if case .usage(_, let rec, _)? = stringModelEntries.first(where: { if case .usage = $0 { return true }; return false }) {
            suite.expect(rec.model == "relay/claude-opus-5.5", "json['model'] as String is picked up as model")
        } else {
            suite.expect(false, "string model message yields usage")
        }

        // 17. Completion timestamp uses completed/updated time, and emits .finished event on store
        var finishDateState = AgentLogState()
        let uMsg17 = line(#"{"id":"u17","session_id":"s17","time_created":1790089400,"directory":"/p","role":"user"}"#)
        let aMsg17 = line(#"{"id":"a17","parentID":"u17","session_id":"s17","time_created":1790089405,"time_updated":1790089425,"time":{"completed":1790089425000},"directory":"/p","role":"assistant","cost":0.01,"tokens":{"total":500,"input":400,"output":100},"finish":"stop"}"#)
        let store17 = AgentUsageStore()
        store17.reportsTransitions = true
        let uEntries = AgentLogParser.parseOpenCode(uMsg17, state: &finishDateState, now: now)
        _ = store17.apply(uEntries, file: "db#s17", provider: .opencode, tracksTurns: true, modified: now, now: now)
        let aEntries = AgentLogParser.parseOpenCode(aMsg17, state: &finishDateState, now: now)
        suite.expect(aEntries.contains(.turnEnded(Date(timeIntervalSince1970: 1_790_089_425), completed: true, duration: 25)),
                     "completion date uses time.completed timestamp")
        let appliedEvents = store17.apply(aEntries, file: "db#s17", provider: .opencode, tracksTurns: true, modified: now,
                                          now: Date(timeIntervalSince1970: 1_790_089_425))
        suite.expect(appliedEvents == [.finished(provider: .opencode, duration: 25, cost: 0.01, tokens: 500, project: "p")],
                     "store emits .finished event when OpenCode assistant turn stops")

        // Reading the database, cost sources and repricing, subagents, and
        // the turns OpenCode's own rows keep going, end or leave behind.
        openCodeReasoningTokens(suite, now: now)
        openCodeMillisecondDedup(suite)
        openCodeLifecycleIdempotence(suite, now: now)
        openCodeRepricing(suite, now: now)
        openCodeSubagents(suite, now: now)
        openCodeDatabaseReplacement(suite, now: now)
        openCodeReadWindow(suite, now: now)
        openCodeNullColumns(suite)
        openCodeValues(suite)
        openCodeDiscovery(suite)
        openCodeEmptyReplies(suite, now: now)
        openCodeFinishes(suite, now: now)
        openCodeAgentPrompts(suite, now: now)
        openCodeParts(suite, now: now)
        openCodeLongHistory(suite)
        openCodeRevert(suite)
        openCodeOpenReplies(suite)
        openCodeStoppedLoops(suite, now: now)
        openCodeQuietSessions(suite, now: now)
    }

    private static func openCodeReasoningTokens(_ suite: TestSuite, now: Date) {
        var reasoningState = AgentLogState()
        // gpt-6-astra is in agent-prices.json: input: $10/M, output: $50/M
        let reasoningMsg = line("""
        {"id":"msg_rsn","session_id":"s_rsn","time_created":1790089500,"directory":"/Users/me/code/backend","role":"assistant","model_id":"gpt-6-astra","cost":0,"tokens":{"total":1500,"input":1000,"output":300,"reasoning":200,"cache":{"read":0,"write":0}},"finish":"stop"}
        """)
        let entries = AgentLogParser.parseOpenCode(reasoningMsg, state: &reasoningState, now: now)
        guard case .usage(_, let rec, _)? = entries.first(where: {
            if case .usage = $0 { return true }; return false
        }) else {
            suite.expect(false, "a response with reasoning tokens yields usage")
            return
        }
        suite.expect(rec.tokens.output == 500, "tokens.output includes output + reasoning (300 + 200 = 500)")
        suite.expect(rec.tokens.reasoning == 200, "tokens.reasoning retains reasoning tokens (200)")
        suite.expect(rec.tokens.total == 1500, "tokens.total includes input, cache, and output + reasoning (1000 + 500 = 1500)")
        // Expected list price: (1000 * 10 + 500 * 50) / 1_000_000 = (10_000 + 25_000) / 1_000_000 = 0.035
        suite.expectClose(rec.cost ?? -1, 0.035,
                          "when list-priced, output price is calculated using output + reasoning",
                          tol: 0.000001)
    }

    private static func openCodeMillisecondDedup(_ suite: TestSuite) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "vorss-boundary-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbPath = dir.appending(path: "opencode.db").path

        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK, let db else {
            suite.expect(false, "boundary database opens")
            return
        }
        sqlite3_exec(db, """
        CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, time_created INTEGER, time_updated INTEGER);
        CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
        INSERT INTO session VALUES ('s_bd', '/p', 1790088000000, 1790088000000);
        INSERT INTO message VALUES ('m1', 's_bd', 1790088000000, 1790088000000, '{"role":"user","parts":[{"type":"text","text":"start"}]}');
        """, nil, nil, nil)
        sqlite3_close(db)

        let cursor = AgentLogCursor(path: dbPath, provider: .opencode)
        var linesRead: [String] = []
        AgentOpenCodeReader.readAppended(cursor) { data in
            linesRead.append(String(decoding: data, as: UTF8.self))
        }
        suite.expect(linesRead.count == 1 && cursor.offset == 1, "an initial read returns m1")

        // Commit 1: Insert assistant message m2 committed in same-millisecond timestamp
        var db2: OpaquePointer?
        guard sqlite3_open(dbPath, &db2) == SQLITE_OK, let db2 else {
            suite.expect(false, "re-opening boundary database for commit 1")
            return
        }
        let sameMs: Int64 = 1_790_088_005_000
        sqlite3_exec(db2, """
        INSERT INTO message VALUES ('m2', 's_bd', \(sameMs), \(sameMs), '{"role":"assistant","tokens":{"input":10,"output":5}}');
        """, nil, nil, nil)
        sqlite3_close(db2)

        linesRead.removeAll()
        AgentOpenCodeReader.readAppended(cursor) { data in
            linesRead.append(String(decoding: data, as: UTF8.self))
        }
        suite.expect(linesRead.count == 1 && linesRead.first?.contains(#""id":"m2"#) == true && cursor.offset == 2,
                     "a reply still being written is read when saved")

        // Commit 2: Within the SAME millisecond timestamp (time_created & time_updated unchanged),
        // update the same assistant message m2 with new tokens and final finish status, and insert m3
        var db3: OpaquePointer?
        guard sqlite3_open(dbPath, &db3) == SQLITE_OK, let db3 else {
            suite.expect(false, "re-opening boundary database for commit 2")
            return
        }
        sqlite3_exec(db3, """
        UPDATE message SET data = '{"role":"assistant","tokens":{"input":30,"output":15},"finish":"stop"}' WHERE id = 'm2';
        INSERT INTO message VALUES ('m3', 's_bd', \(sameMs), \(sameMs), '{"role":"assistant","tokens":{"input":20,"output":10},"finish":"stop"}');
        """, nil, nil, nil)
        sqlite3_close(db3)

        linesRead.removeAll()
        AgentOpenCodeReader.readAppended(cursor) { data in
            linesRead.append(String(decoding: data, as: UTF8.self))
        }
        suite.expect(linesRead.count == 2
                        && linesRead.contains { $0.contains(#""id":"m2"#) && $0.contains(#""finish":"stop"#) && $0.contains(#""input":30"#) }
                        && linesRead.contains { $0.contains(#""id":"m3"#) }
                        && cursor.offset == 3,
                     "a reply updated within the same millisecond is read again, and a new message is read")

        // Third read with no new messages does not duplicate m2 or m3
        linesRead.removeAll()
        AgentOpenCodeReader.readAppended(cursor) { data in
            linesRead.append(String(decoding: data, as: UTF8.self))
        }
        suite.expect(linesRead.isEmpty, "third read with no new messages does not duplicate m2 or m3")
    }

    private static func openCodeLifecycleIdempotence(_ suite: TestSuite, now: Date) {
        // Ordering 1: Turn 1 starts with usr_1, ast_1 finishes turn 1. Turn 2 starts with usr_2.
        // An update to ast_1 arrives: Turn 2 remains open and active (turnOpen == true),
        // and ast_1 does not close Turn 2. Then ast_2 arrives and properly closes Turn 2.
        var o1State = AgentLogState()
        let o1User1 = line(#"{"id":"usr_1","session_id":"s_o1","time_created":1790089600,"directory":"/p","role":"user","parts":[{"type":"text","text":"do 1"}]}"#)
        let o1Ast1 = line(#"{"id":"ast_1","parentID":"usr_1","session_id":"s_o1","time_created":1790089605,"directory":"/p","role":"assistant","finish":"stop","tokens":{"input":100,"output":50}}"#)
        let o1User2 = line(#"{"id":"usr_2","session_id":"s_o1","time_created":1790089610,"directory":"/p","role":"user","parts":[{"type":"text","text":"do 2"}]}"#)

        _ = AgentLogParser.parseOpenCode(o1User1, state: &o1State, now: now)
        let o1Ast1Entries = AgentLogParser.parseOpenCode(o1Ast1, state: &o1State, now: now)
        suite.expect(o1Ast1Entries.contains { if case .turnEnded = $0 { return true }; return false },
                     "ast_1 finishes Turn 1")
        suite.expect(o1State.openCodeSessions["s_o1"]?.turnOpen == false, "Turn 1 is closed")

        let o1User2Entries = AgentLogParser.parseOpenCode(o1User2, state: &o1State, now: now)
        suite.expect(o1User2Entries.contains { if case .turnBegan = $0 { return true }; return false },
                     "usr_2 begins Turn 2")
        suite.expect(o1State.openCodeSessions["s_o1"]?.turnOpen == true, "Turn 2 is open")

        // Update to ast_1 arrives (e.g. updated token counts or time_updated)
        let o1Ast1Update = line(#"{"id":"ast_1","parentID":"usr_1","session_id":"s_o1","time_created":1790089605,"time_updated":1790089612,"directory":"/p","role":"assistant","finish":"stop","tokens":{"input":120,"output":60}}"#)
        let o1Ast1UpdateEntries = AgentLogParser.parseOpenCode(o1Ast1Update, state: &o1State, now: now)
        suite.expect(!o1Ast1UpdateEntries.contains { if case .turnEnded = $0 { return true }; return false }
                        && !o1Ast1UpdateEntries.contains { if case .turnBegan = $0 { return true }; return false },
                     "update to completed ast_1 does not emit turnEnded or turnBegan")
        suite.expect(o1State.openCodeSessions["s_o1"]?.turnOpen == true,
                     "Turn 2 remains open and active after update to completed ast_1")

        // ast_2 arrives and properly closes Turn 2
        let o1Ast2 = line(#"{"id":"ast_2","parentID":"usr_2","session_id":"s_o1","time_created":1790089615,"directory":"/p","role":"assistant","finish":"stop","tokens":{"input":80,"output":40}}"#)
        let o1Ast2Entries = AgentLogParser.parseOpenCode(o1Ast2, state: &o1State, now: now)
        suite.expect(o1Ast2Entries.contains { if case .turnEnded = $0 { return true }; return false },
                     "ast_2 properly closes Turn 2")
        suite.expect(o1State.openCodeSessions["s_o1"]?.turnOpen == false, "Turn 2 is now closed")

        // Ordering 2: Turn 1 starts with usr_1. Before ast_1 arrives, user sends usr_2.
        // When ast_1 (with parentID: usr_1, finish: stop) arrives, it does NOT close Turn 2
        // (matchesActivePrompt is false). Turn 2 stays open until ast_2 arrives.
        var o2State = AgentLogState()
        let o2User1 = line(#"{"id":"usr_1","session_id":"s_o2","time_created":1790089700,"directory":"/p","role":"user","parts":[{"type":"text","text":"first"}]}"#)
        let o2User2 = line(#"{"id":"usr_2","session_id":"s_o2","time_created":1790089705,"directory":"/p","role":"user","parts":[{"type":"text","text":"second"}]}"#)
        let o2Ast1 = line(#"{"id":"ast_1","parentID":"usr_1","session_id":"s_o2","time_created":1790089710,"directory":"/p","role":"assistant","finish":"stop","tokens":{"input":50,"output":25}}"#)
        let o2Ast2 = line(#"{"id":"ast_2","parentID":"usr_2","session_id":"s_o2","time_created":1790089715,"directory":"/p","role":"assistant","finish":"stop","tokens":{"input":60,"output":30}}"#)

        _ = AgentLogParser.parseOpenCode(o2User1, state: &o2State, now: now)
        suite.expect(o2State.openCodeSessions["s_o2"]?.activeUserMessageID == "usr_1", "activeUserMessageID is usr_1")
        _ = AgentLogParser.parseOpenCode(o2User2, state: &o2State, now: now)
        suite.expect(o2State.openCodeSessions["s_o2"]?.activeUserMessageID == "usr_2", "activeUserMessageID is now usr_2")
        suite.expect(o2State.openCodeSessions["s_o2"]?.turnOpen == true, "Turn 2 is open")

        let o2Ast1Entries = AgentLogParser.parseOpenCode(o2Ast1, state: &o2State, now: now)
        suite.expect(!o2Ast1Entries.contains { if case .turnEnded = $0 { return true }; return false },
                     "ast_1 with parentID usr_1 does not close Turn 2 (matchesActivePrompt is false)")
        suite.expect(o2State.openCodeSessions["s_o2"]?.turnOpen == true,
                     "Turn 2 stays open when ast_1 from earlier prompt arrives")

        let o2Ast2Entries = AgentLogParser.parseOpenCode(o2Ast2, state: &o2State, now: now)
        suite.expect(o2Ast2Entries.contains { if case .turnEnded = $0 { return true }; return false },
                     "ast_2 with parentID usr_2 closes Turn 2")
        suite.expect(o2State.openCodeSessions["s_o2"]?.turnOpen == false, "Turn 2 is closed")

        // Duplicate/repeated assistant updates for already completed turn do not emit .turnBegan or .turnEnded
        let o2Ast2Dup = line(#"{"id":"ast_2","parentID":"usr_2","session_id":"s_o2","time_created":1790089715,"time_updated":1790089720,"directory":"/p","role":"assistant","finish":"stop","tokens":{"input":70,"output":35}}"#)
        let o2DupEntries = AgentLogParser.parseOpenCode(o2Ast2Dup, state: &o2State, now: now)
        suite.expect(!o2DupEntries.contains { if case .turnBegan = $0 { return true }; return false }
                        && !o2DupEntries.contains { if case .turnEnded = $0 { return true }; return false },
                     "duplicate assistant update for completed turn does not emit turnBegan or turnEnded")
    }

    private static func openCodeRepricing(_ suite: TestSuite, now: Date) {
        let store = AgentUsageStore()
        var state = AgentLogState()

        // 1. Record with reported cost (unknown model with explicit reported cost)
        let reportedMsg = line("""
        {"id":"m_rep","session_id":"s_rp","time_created":1790089800,"directory":"/p","role":"assistant","model_id":"stealth/ox-alpha","cost":0.005,"tokens":{"input":1000,"output":200}}
        """)
        let repEntries = AgentLogParser.parseOpenCode(reportedMsg, state: &state, now: now)
        _ = store.apply(repEntries, file: "db#s_rp", provider: .opencode, tracksTurns: false, modified: now, now: now)

        // 2. Record with list-derived cost (known model, e.g. claude-3-5-sonnet)
        let listMsg = line("""
        {"id":"m_list","session_id":"s_rp","time_created":1790089810,"directory":"/p","role":"assistant","model_id":"claude-3-5-sonnet","cost":0,"tokens":{"input":1000,"output":200}}
        """)
        let listEntries = AgentLogParser.parseOpenCode(listMsg, state: &state, now: now)
        _ = store.apply(listEntries, file: "db#s_rp", provider: .opencode, tracksTurns: false, modified: now, now: now)

        // 3. Unpriced record for an unlisted model
        let unpricedMsg = line("""
        {"id":"m_unp","session_id":"s_rp","time_created":1790089820,"directory":"/p","role":"assistant","model_id":"custom-nova-1","cost":0,"tokens":{"input":1000,"output":200}}
        """)
        let unpEntries = AgentLogParser.parseOpenCode(unpricedMsg, state: &state, now: now)
        _ = store.apply(unpEntries, file: "db#s_rp", provider: .opencode, tracksTurns: false, modified: now, now: now)

        suite.expect(store.records.count == 3, "three OpenCode records stored")
        let repRec = store.records.first { $0.session == "s_rp" && $0.model == "stealth/ox-alpha" }
        let listRec = store.records.first { $0.session == "s_rp" && $0.model == "claude-3-5-sonnet" }
        let unpRec = store.records.first { $0.session == "s_rp" && $0.model == "custom-nova-1" }

        suite.expect(repRec?.reportedCost == true && repRec?.cost == 0.005,
                     "reported record has reportedCost: true and preserved exact cost")
        suite.expect(listRec?.reportedCost == false && abs((listRec?.cost ?? 0) - 0.006) < 0.000001,
                     "list-derived record calculates cost from price list (input 3, output 15 -> 0.006)")
        suite.expect(unpRec?.reportedCost == false && unpRec?.cost == 0,
                     "an unlisted model OpenCode recorded at zero starts at zero")

        // Now install an updated price list with doubled prices for claude-3-5-sonnet and a new price for custom-nova-1
        let prevList = AgentPricing.list
        var newClaudeModels = prevList.claude.filter { $0.id != "claude-3-5-sonnet" }
        newClaudeModels.append(AgentPriceList.Model(id: "claude-3-5-sonnet",
                                                    price: AgentPrice(input: 6, output: 30, cacheRead: 0.6, cacheWrite: 7.5, cacheWriteLong: 12)))
        var newCodexModels = prevList.codex
        newCodexModels.append(AgentPriceList.Model(id: "custom-nova-1",
                                                   price: AgentPrice(input: 4, output: 20, cacheRead: 0.4, cacheWrite: 4, cacheWriteLong: 4)))

        let updatedList = AgentPriceList(updated: Date(), claude: newClaudeModels, codex: newCodexModels,
                                         claudePlans: prevList.claudePlans, codexPlans: prevList.codexPlans,
                                         webSearch: prevList.webSearch, usOnlyMultiplier: prevList.usOnlyMultiplier)
        AgentPricing.install(updatedList)
        defer { AgentPricing.install(prevList) }

        store.reprice()

        let repAfter = store.records.first { $0.session == "s_rp" && $0.model == "stealth/ox-alpha" }
        let listAfter = store.records.first { $0.session == "s_rp" && $0.model == "claude-3-5-sonnet" }
        let unpAfter = store.records.first { $0.session == "s_rp" && $0.model == "custom-nova-1" }

        suite.expect(repAfter?.cost == 0.005,
                     "store.reprice() preserves reported cost unchanged")
        suite.expectClose(listAfter?.cost ?? -1, 0.012,
                          "store.reprice() updates list-derived cost using new price (input 6, output 30 -> 0.012)",
                          tol: 0.000001)
        suite.expectClose(unpAfter?.cost ?? -1, 0.008,
                          "store.reprice() calculates cost for previously unpriced model that gained a price",
                          tol: 0.000001)
        let local = AgentLogParser.parseOpenCode(line(#"{"id":"m_loc","session_id":"s_rp","time_created":1790089830,"role":"assistant","model_id":"custom-ember-1","cost":0,"tokens":{"input":10,"output":2}}"#),
                                                 state: &state, now: now)
        store.apply(local, file: "db#s_rp", provider: .opencode, tracksTurns: false, modified: now, now: now)
        store.reprice()
        suite.expect(store.records.first { $0.model == "custom-ember-1" }?.cost == 0,
                     "a zero recorded for a model the list still does not know stays its cost")

        // a) Record with reported cost updated with list-derived cost estimate -> reported cost and source are preserved
        let repEstimateUpdate = AgentLogEntry.usage(
            key: "opencode:s_rp:m_rep",
            record: AgentUsageRecord(provider: .opencode, date: now, model: "stealth/ox-alpha", project: "p",
                                     session: "s_rp", tokens: AgentTokens(input: 1000, output: 200),
                                     cost: 0.015, savings: 0, reportedCost: false),
            billable: AgentBillable(tokens: AgentTokens(input: 1000, output: 200))
        )
        store.apply([repEstimateUpdate], file: "db#s_rp", provider: .opencode, tracksTurns: false, modified: now, now: now)
        let repAfterEstimate = store.records.first { $0.session == "s_rp" && $0.model == "stealth/ox-alpha" }
        suite.expect(repAfterEstimate?.cost == 0.005 && repAfterEstimate?.reportedCost == true,
                     "record with reported cost updated with list-derived cost estimate preserves reported cost and source")

        // b) Record with list-derived cost updated with same tokens and same cost but source changed to reported
        let listReportedUpdate = AgentLogEntry.usage(
            key: "opencode:s_rp:m_list",
            record: AgentUsageRecord(provider: .opencode, date: now, model: "claude-3-5-sonnet", project: "p",
                                     session: "s_rp", tokens: AgentTokens(input: 1000, output: 200),
                                     cost: 0.012, savings: 0, reportedCost: true),
            billable: AgentBillable(tokens: AgentTokens(input: 1000, output: 200))
        )
        store.apply([listReportedUpdate], file: "db#s_rp", provider: .opencode, tracksTurns: false, modified: now, now: now)
        let listAfterReported = store.records.first { $0.session == "s_rp" && $0.model == "claude-3-5-sonnet" }
        suite.expect(listAfterReported?.cost == 0.012 && listAfterReported?.reportedCost == true,
                     "record with list-derived cost updated with same tokens and same cost but source changed to reported updates reportedCost to true")

        // c) Record with reported cost updated with new reported cost -> updates cost and keeps reportedCost: true
        let repNewCostUpdate = AgentLogEntry.usage(
            key: "opencode:s_rp:m_rep",
            record: AgentUsageRecord(provider: .opencode, date: now, model: "stealth/ox-alpha", project: "p",
                                     session: "s_rp", tokens: AgentTokens(input: 1000, output: 200),
                                     cost: 0.008, savings: 0, reportedCost: true),
            billable: AgentBillable(tokens: AgentTokens(input: 1000, output: 200))
        )
        store.apply([repNewCostUpdate], file: "db#s_rp", provider: .opencode, tracksTurns: false, modified: now, now: now)
        let repAfterNewCost = store.records.first { $0.session == "s_rp" && $0.model == "stealth/ox-alpha" }
        suite.expect(repAfterNewCost?.cost == 0.008 && repAfterNewCost?.reportedCost == true,
                     "record with reported cost updated with new reported cost updates cost and keeps reportedCost true")
    }

    private static func openCodeSubagents(_ suite: TestSuite, now: Date) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "vorss-subagent-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbPath = dir.appending(path: "opencode.db").path

        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK, let db else {
            suite.expect(false, "subagent database opens")
            return
        }
        sqlite3_exec(db, """
        CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, time_created INTEGER, time_updated INTEGER, parent_id TEXT);
        CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
        INSERT INTO session VALUES ('s_parent', '/Users/me/code/proj', 1790088000000, 1790088050000, NULL);
        INSERT INTO session VALUES ('s_child', '/Users/me/code/sub_proj', 1790088005000, 1790088030000, 's_parent');
        """, nil, nil, nil)

        // Parent starts turn
        sqlite3_exec(db, """
        INSERT INTO message VALUES ('m_p1', 's_parent', 1790088000000, 1790088000000, '{"role":"user","parts":[{"type":"text","text":"parent prompt"}]}');
        """, nil, nil, nil)
        sqlite3_close(db)

        let cursor = AgentLogCursor(path: dbPath, provider: .opencode)
        let store = AgentUsageStore()
        store.reportsTransitions = true
        var collectedEvents: [AgentUsageEvent] = []

        func readAndApply() {
            AgentOpenCodeReader.readAppended(cursor) { lineData in
                let entries = AgentLogParser.parseOpenCode(lineData, state: &cursor.state, now: now)
                guard !entries.isEmpty else { return }
                let isSubagent = !cursor.state.parentSession.isEmpty
                let turnFile = !cursor.state.session.isEmpty ? "\(dbPath)#\(cursor.state.session)" : dbPath
                let tracksTurns = isSubagent ? false : cursor.tracksTurns
                let parent = isSubagent ? "\(dbPath)#\(cursor.state.parentSession)" : cursor.parent
                let finished = store.apply(entries, file: turnFile, provider: .opencode,
                                           tracksTurns: tracksTurns, parent: parent, modified: now, now: now)
                collectedEvents += finished
            }
        }

        readAndApply()
        suite.expect(store.turns["\(dbPath)#s_parent"] != nil, "parent turn is open")

        // Child session emits usage and finish (finish: stop)
        var db2: OpaquePointer?
        guard sqlite3_open(dbPath, &db2) == SQLITE_OK, let db2 else {
            suite.expect(false, "re-opening subagent database for child")
            return
        }
        sqlite3_exec(db2, """
        INSERT INTO message VALUES ('m_c1', 's_child', 1790088010000, 1790088010000, '{"role":"assistant","model_id":"stealth/ox-alpha","cost":0.002,"tokens":{"total":100,"input":80,"output":20},"finish":"stop"}');
        """, nil, nil, nil)
        sqlite3_close(db2)

        readAndApply()

        // Verify child usage rolls into parent turn and child finish does not emit .finished event
        let parentTurnAfterChild = store.turns["\(dbPath)#s_parent"]
        suite.expect(parentTurnAfterChild?.tokens.total == 100 && abs((parentTurnAfterChild?.cost ?? 0) - 0.002) < 0.000001,
                     "child usage rolls into parent turn tokens and cost")
        suite.expect(collectedEvents.isEmpty,
                     "child finish does NOT emit .finished event for child")

        // Parent finishes turn
        var db3: OpaquePointer?
        guard sqlite3_open(dbPath, &db3) == SQLITE_OK, let db3 else {
            suite.expect(false, "re-opening subagent database for parent finish")
            return
        }
        sqlite3_exec(db3, """
        INSERT INTO message VALUES ('m_p2', 's_parent', 1790088020000, 1790088020000, '{"id":"m_p2","parentID":"m_p1","role":"assistant","model_id":"stealth/ox-alpha","cost":0.003,"tokens":{"total":200,"input":150,"output":50},"finish":"stop"}');
        """, nil, nil, nil)
        sqlite3_close(db3)

        readAndApply()

        // Verify parent finish emits single .finished event with combined tokens and parent project/model
        suite.expect(collectedEvents == [.finished(provider: .opencode, duration: 20, cost: 0.005,
                                                   tokens: 300, project: "proj")],
                     "parent finish emits single .finished event with combined tokens, cost, and parent project")
        suite.expect(store.turns["\(dbPath)#s_parent"] == nil, "parent turn is closed after parent finish")
    }

    private static func openCodeDatabaseReplacement(_ suite: TestSuite, now: Date) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "vorss-replace-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let activePath = dir.appending(path: "opencode.db").path
        let altPath = dir.appending(path: "opencode_alt.db").path

        // 1. Create db1 at activePath with session s1 having an open live turn
        var db1: OpaquePointer?
        guard sqlite3_open(activePath, &db1) == SQLITE_OK, let db1 else {
            suite.expect(false, "db1 opens")
            return
        }
        sqlite3_exec(db1, """
        CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, time_created INTEGER, time_updated INTEGER);
        CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
        INSERT INTO session VALUES ('s1', '/proj1', 1790088000000, 1790088000000);
        INSERT INTO message VALUES ('m1', 's1', 1790088000000, 1790088000000, '{"role":"user","parts":[{"type":"text","text":"start 1"}]}');
        """, nil, nil, nil)
        sqlite3_close(db1)

        let cursor = AgentLogCursor(path: activePath, provider: .opencode)
        let store = AgentUsageStore()
        store.reportsTransitions = true

        func readActive() {
            AgentOpenCodeReader.readAppended(cursor) { lineData in
                let entries = AgentLogParser.parseOpenCode(lineData, state: &cursor.state, now: now)
                let turnFile = !cursor.state.session.isEmpty ? "\(activePath)#\(cursor.state.session)" : activePath
                _ = store.apply(entries, file: turnFile, provider: .opencode, tracksTurns: true, modified: now, now: now)
            }
        }

        readActive()
        suite.expect(store.turns["\(activePath)#s1"] != nil, "db1 has session s1 with an open live turn")

        // 2. Create db2 at altPath with session s2 having an open live turn
        var db2: OpaquePointer?
        guard sqlite3_open(altPath, &db2) == SQLITE_OK, let db2 else {
            suite.expect(false, "db2 opens")
            return
        }
        sqlite3_exec(db2, """
        CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, time_created INTEGER, time_updated INTEGER);
        CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
        INSERT INTO session VALUES ('s2', '/proj2', 1790088010000, 1790088010000);
        INSERT INTO message VALUES ('m2', 's2', 1790088010000, 1790088010000, '{"role":"user","parts":[{"type":"text","text":"start 2"}]}');
        """, nil, nil, nil)
        sqlite3_close(db2)

        // Replace db1 with db2 (removes old file and moves new file with different inode)
        try? FileManager.default.removeItem(atPath: activePath)
        try? FileManager.default.moveItem(atPath: altPath, toPath: activePath)

        // Read cursor again
        readActive()

        // Verify db1's live turn s1 was retired/forgotten, and only db2's session s2 is present
        suite.expect(store.turns["\(activePath)#s1"] == nil,
                     "database replacement retires and forgets old db1 live turn s1")
        suite.expect(store.turns["\(activePath)#s2"] != nil,
                     "only db2 session s2 is present in live turns after database replacement")
    }

    // MARK: OpenCode database helpers

    /// A database laid out like OpenCode's, in a folder of its own.
    static func openCodeDatabase(_ sql: String) -> (folder: URL, path: String)? {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-opencode-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appending(path: "opencode.db").path
        guard openCodeExec(path, """
        CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, parent_id TEXT, time_created INTEGER, time_updated INTEGER);
        CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
        CREATE TABLE part (id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
        \(sql)
        """) else { return nil }
        return (folder, path)
    }

    @discardableResult
    static func openCodeExec(_ path: String, _ sql: String) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private static func openCodeRead(_ cursor: AgentLogCursor, since horizon: Date = .distantPast) -> [[String: Any]] {
        var rows: [[String: Any]] = []
        AgentOpenCodeReader.readAppended(cursor, since: horizon) { data in
            if let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { rows.append(row) }
        }
        return rows
    }

    private static func ended(_ entries: [AgentLogEntry]) -> Bool {
        entries.contains { if case .turnEnded = $0 { return true }; return false }
    }

    private static func usage(_ entries: [AgentLogEntry]) -> Bool {
        entries.contains { if case .usage = $0 { return true }; return false }
    }

    // MARK: OpenCode reading window

    private static func openCodeReadWindow(_ suite: TestSuite, now: Date) {
        guard let (folder, path) = openCodeDatabase("""
        INSERT INTO session VALUES ('s_a', '/code/a', NULL, 1780000000000, 1780000000000);
        INSERT INTO session VALUES ('s_b', '/code/b', NULL, 1790088000000, 1790088000000);
        INSERT INTO message VALUES ('m_old', 's_a', 1780000000000, 1780000000000, '{"role":"assistant","tokens":{"input":10,"output":5},"finish":"stop"}');
        INSERT INTO message VALUES ('m_new', 's_b', 1790088000000, 1790088000000, '{"role":"user"}');
        """) else {
            suite.expect(false, "window database opens")
            return
        }
        defer { try? FileManager.default.removeItem(at: folder) }

        let cursor = AgentLogCursor(path: path, provider: .opencode)
        let first = openCodeRead(cursor, since: Date(timeIntervalSince1970: 1_789_000_000))
        suite.expect(first.map { $0["id"] as? String } == ["m_new"] && cursor.offset == 2,
                     "a first read starts at the horizon instead of the database's first message")

        openCodeExec(path, """
        INSERT INTO message VALUES ('m_b1', 's_b', 1790088010000, 1790088010000, '{"role":"assistant","parentID":"m_new","tokens":{"input":10,"output":5}}');
        """)
        let second = openCodeRead(cursor, since: Date(timeIntervalSince1970: 1_789_000_000))
        suite.expect(second.map { $0["id"] as? String } == ["m_b1"] && cursor.offset == 3,
                     "a newer row from another session moves the cursor on")

        // Stamped long before it is saved, as when its attachments take a while.
        openCodeExec(path, """
        INSERT INTO message VALUES ('p_a', 's_a', 1790087000000, 1790088012000, '{"role":"user"}');
        """)
        let late = openCodeRead(cursor, since: Date(timeIntervalSince1970: 1_789_000_000))
        suite.expect(late.map { $0["id"] as? String } == ["p_a"],
                     "a prompt saved after a newer row was read is still read, and nothing already read repeats")
        var state = AgentLogState()
        let entries = late.compactMap { try? JSONSerialization.data(withJSONObject: $0) }
            .flatMap { AgentLogParser.parseOpenCode($0, state: &state, now: now) }
        suite.expect(entries == [.turnBegan(Date(timeIntervalSince1970: 1_790_087_000))]
                        && state.openCodeSessions["s_a"]?.turnOpen == true,
                     "the late prompt opens its session's turn")
        suite.expect(openCodeRead(cursor, since: Date(timeIntervalSince1970: 1_789_000_000)).isEmpty,
                     "a read with nothing new hands over nothing")
    }

    private static func openCodeNullColumns(_ suite: TestSuite) {
        guard let (folder, path) = openCodeDatabase("""
        INSERT INTO session VALUES ('s_n', NULL, NULL, 1790088000000, 1790088000000);
        INSERT INTO message VALUES (NULL, 's_n', 1790088000000, 1790088000000, '{"role":"user"}');
        INSERT INTO message VALUES ('n_data', 's_n', 1790088001000, 1790088001000, NULL);
        INSERT INTO message VALUES ('n_created', 's_n', NULL, 1790088002000, '{"role":"user"}');
        INSERT INTO message VALUES ('n_updated', 's_n', 1790088003000, NULL, '{"role":"user"}');
        INSERT INTO message VALUES ('n_garbled', 's_n', 1790088004000, 1790088004000, 'not json');
        INSERT INTO message VALUES ('n_ok', 's_n', 1790088005000, 1790088005000, '{"role":"assistant","tokens":{"input":1}}');
        """) else {
            suite.expect(false, "null column database opens")
            return
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let rows = openCodeRead(AgentLogCursor(path: path, provider: .opencode))
        suite.expect(rows.map { $0["id"] as? String } == ["n_updated", "n_ok"]
                        && rows.allSatisfy { $0["directory"] as? String == "" },
                     "rows missing a value are skipped, an empty folder or update time reads as none")
    }

    private static func openCodeValues(_ suite: TestSuite) {
        guard let (folder, path) = openCodeDatabase("""
        INSERT INTO session VALUES ('s_v', '/code/v', NULL, 1790088000000, 1790088000000);
        INSERT INTO message VALUES ('v_reply', 's_v', 1790088000000, 1790088000000, '{"role":"assistant","model":{"modelID":"model-v"},"tokens":{"input":3,"cache":{"read":2,"write":1}},"path":{"cwd":"/code/v/app","root":"/code/v"},"error":{"name":"Stopped","data":{"message":"private words"}},"summary":{"body":"private words"}}');
        INSERT INTO message VALUES ('v_plain', 's_v', 1790088001000, 1790088001000, '{"role":"assistant","error":null}');
        """) else {
            suite.expect(false, "values database opens")
            return
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        var payloads: [String] = []
        AgentOpenCodeReader.readAppended(AgentLogCursor(path: path, provider: .opencode)) { payloads.append(String(decoding: $0, as: UTF8.self)) }
        let rows = payloads.compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
        suite.expect(rows.count == 2 && (rows[0]["model"] as? [String: Any])?["modelID"] as? String == "model-v"
                        && ((rows[0]["tokens"] as? [String: Any])?["cache"] as? [String: Any])?["read"] as? Int == 2
                        && (rows[0]["path"] as? [String: String]) == ["cwd": "/code/v/app"]
                        && rows[0]["error"] as? Bool == true && rows[1]["error"] == nil,
                     "a reply hands over its model, tokens, working folder and whether it failed")
        suite.expect(!payloads.contains { $0.contains("private words") || $0.contains("\"root\"") },
                     "no message text and no other path leaves the database")
    }

    private static func openCodeDiscovery(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-discover-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = AgentLogRoot(provider: .opencode, url: folder)
        let nested = folder.appending(path: "snapshot/project/opencode.db")
        try? FileManager.default.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: nested.path, contents: Data())
        let horizon = Date().addingTimeInterval(-86_400)
        suite.expect(AgentLogReader.discover([root], since: horizon).isEmpty,
                     "a database inside the data folder's other contents is not OpenCode's")
        let database = AgentLogRoot.canonical(folder).appending(path: "opencode.db")
        FileManager.default.createFile(atPath: database.path, contents: Data())
        let found = AgentLogReader.discover([AgentLogRoot(provider: .opencode, url: AgentLogRoot.canonical(folder))],
                                            since: horizon)
        suite.expect(found.map(\.path) == [database.path] && found.first?.provider == .opencode,
                     "OpenCode's database is found at its known path")
    }

    // MARK: OpenCode turns

    private static func openCodeEmptyReplies(_ suite: TestSuite, now: Date) {
        var state = AgentLogState()
        let store = AgentUsageStore()
        let prompt = AgentLogParser.parseOpenCode(line(#"{"id":"u_sh","session_id":"s_e","time_created":1790090000,"role":"user"}"#),
                                                  state: &state, now: now)
        let started = AgentLogParser.parseOpenCode(line(#"{"id":"a_sh","parentID":"u_sh","session_id":"s_e","time_created":1790090001,"role":"assistant","model_id":"claude-3-5-sonnet","cost":0,"tokens":{"input":0,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":1790090001000}}"#),
                                                   state: &state, now: now)
        suite.expect(started == [.turnActive(Date(timeIntervalSince1970: 1_790_090_001))],
                     "a reply saved before its answer arrives is activity without usage")
        let shell = AgentLogParser.parseOpenCode(line(#"{"id":"a_sh","parentID":"u_sh","session_id":"s_e","time_created":1790090001,"role":"assistant","model_id":"claude-3-5-sonnet","cost":0,"tokens":{"input":0,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":1790090001000,"completed":1790090004000}}"#),
                                                 state: &state, now: now)
        suite.expect(shell == [.turnEnded(Date(timeIntervalSince1970: 1_790_090_004), completed: true, duration: 4)],
                     "a shell command's reply completes without a finish and ends the turn without usage")

        _ = AgentLogParser.parseOpenCode(line(#"{"id":"u_f","session_id":"s_e","time_created":1790090010,"role":"user"}"#),
                                         state: &state, now: now)
        let failed = AgentLogParser.parseOpenCode(line(#"{"id":"a_f","parentID":"u_f","session_id":"s_e","time_created":1790090011,"role":"assistant","cost":0,"tokens":{"input":0,"output":0},"error":{"name":"APIError"},"time":{"completed":1790090012000}}"#),
                                                  state: &state, now: now)
        suite.expect(failed == [.turnEnded(Date(timeIntervalSince1970: 1_790_090_012), completed: false, duration: 2)],
                     "a failed request ends the turn unfinished and stores nothing")

        for entries in [prompt, started, shell, failed] {
            store.apply(entries, file: "db#s_e", provider: .opencode, tracksTurns: true, modified: now, now: now)
        }
        suite.expect(store.records.isEmpty, "replies without tokens or cost leave no usage record")
        suite.expect(AgentPricing.cost(AgentBillable(), model: "claude-3-5-sonnet").cost == 0,
                     "the shared price list prices no tokens at zero, as for Claude and Codex")
    }

    private static func openCodeFinishes(_ suite: TestSuite, now: Date) {
        func turn(_ finish: String, extra: String = "") -> [AgentLogEntry] {
            var state = AgentLogState()
            _ = AgentLogParser.parseOpenCode(line(#"{"id":"u","session_id":"s_f","time_created":1790090100,"role":"user"}"#),
                                             state: &state, now: now)
            return AgentLogParser.parseOpenCode(line(#"{"id":"a","parentID":"u","session_id":"s_f","time_created":1790090101,"role":"assistant","tokens":{"input":10,"output":5},"finish":"\#(finish)"\#(extra),"time":{"completed":1790090105000}}"#),
                                                state: &state, now: now)
        }
        suite.expect(turn("length").contains(.turnEnded(Date(timeIntervalSince1970: 1_790_090_105), completed: true, duration: 5)),
                     "a reply cut at the output limit ends the turn")
        suite.expect(ended(turn("content-filter")) && ended(turn("other")) && ended(turn("stop")),
                     "every finish but tool calls and unknown ends the turn")
        suite.expect(!ended(turn("tool-calls")) && !ended(turn("unknown")),
                     "tool calls and an unknown finish keep the turn going")
        suite.expect(!ended(turn("stop", extra: #","tool_calls":true"#)),
                     "a reply that still holds tool calls keeps the turn going whatever its finish")
    }

    private static func openCodeAgentPrompts(_ suite: TestSuite, now: Date) {
        // An automatic compaction in the middle of a task: OpenCode asks for
        // it, saves the summary with a normal finish and asks to continue.
        var state = AgentLogState()
        let store = AgentUsageStore()
        store.reportsTransitions = true
        var events: [AgentUsageEvent] = []
        var all: [AgentLogEntry] = []
        func feed(_ json: String, at seconds: TimeInterval) -> [AgentLogEntry] {
            let entries = AgentLogParser.parseOpenCode(line(json), state: &state, now: now)
            all += entries
            events += store.apply(entries, file: "db#s_c", provider: .opencode, tracksTurns: true, modified: now,
                                  now: Date(timeIntervalSince1970: seconds))
            return entries
        }
        _ = feed(#"{"id":"p","session_id":"s_c","time_created":1790090200,"directory":"/code/app","role":"user"}"#, at: 1_790_090_200)
        _ = feed(#"{"id":"a1","parentID":"p","session_id":"s_c","time_created":1790090201,"role":"assistant","cost":0.01,"tokens":{"input":100,"output":10},"finish":"tool-calls"}"#, at: 1_790_090_205)
        let request = feed(#"{"id":"c","session_id":"s_c","time_created":1790090210,"role":"user"}"#, at: 1_790_090_210)
        suite.expect(request == [.turnActive(Date(timeIntervalSince1970: 1_790_090_210))],
                     "OpenCode's own compaction request inside a turn is activity")
        let summary = feed(#"{"id":"s","parentID":"c","session_id":"s_c","time_created":1790090211,"role":"assistant","summary":true,"auto_compaction":true,"cost":0.02,"tokens":{"input":200,"output":20},"finish":"stop","time":{"completed":1790090220000}}"#, at: 1_790_090_220)
        suite.expect(!ended(summary), "the summary of an automatic compaction does not end the task")
        let follow = feed(#"{"id":"u","session_id":"s_c","time_created":1790090221,"role":"user"}"#, at: 1_790_090_221)
        suite.expect(follow == [.turnActive(Date(timeIntervalSince1970: 1_790_090_221))],
                     "the follow up asking to continue is activity")
        let reply = feed(#"{"id":"r","parentID":"u","session_id":"s_c","time_created":1790090222,"role":"assistant","cost":0.03,"tokens":{"input":300,"output":30},"finish":"stop","time":{"completed":1790090230000}}"#, at: 1_790_090_230)
        suite.expect(reply.contains(.turnEnded(Date(timeIntervalSince1970: 1_790_090_230), completed: true, duration: 30)),
                     "the reply to the follow up ends the whole task")
        suite.expect(all.filter { if case .turnBegan = $0 { return true }; return false }.count == 1,
                     "a compaction in the middle of a task keeps one turn")
        suite.expect(events.count == 1 && events.first.map {
            if case .finished(_, let duration, let cost, let tokens, _) = $0 {
                return duration == 30 && abs(cost - 0.06) < 0.000001 && tokens == 660
            }
            return false
        } == true, "one finish notice counts the whole task")

        // A manual compaction is a turn of its own, ended by its summary.
        var manual = AgentLogState()
        _ = AgentLogParser.parseOpenCode(line(#"{"id":"mc","session_id":"s_m","time_created":1790090300,"role":"user"}"#),
                                         state: &manual, now: now)
        let manualSummary = AgentLogParser.parseOpenCode(line(#"{"id":"ms","parentID":"mc","session_id":"s_m","time_created":1790090301,"role":"assistant","summary":true,"tokens":{"input":10,"output":5},"finish":"stop"}"#),
                                                         state: &manual, now: now)
        suite.expect(ended(manualSummary), "the summary of a compaction asked for by hand ends that turn")

        // A command's subtask: the reply holding it has no usage and calls a
        // tool, then OpenCode asks for a summary of what it returned.
        var command = AgentLogState()
        var commandEntries: [AgentLogEntry] = []
        for json in [
            #"{"id":"cp","session_id":"s_t","time_created":1790090400,"role":"user"}"#,
            #"{"id":"ct","parentID":"cp","session_id":"s_t","time_created":1790090401,"role":"assistant","tokens":{"input":0,"output":0},"finish":"tool-calls","time":{"completed":1790090420000}}"#,
            #"{"id":"cq","session_id":"s_t","time_created":1790090421,"role":"user"}"#,
            #"{"id":"cr","parentID":"cq","session_id":"s_t","time_created":1790090422,"role":"assistant","tokens":{"input":50,"output":5},"finish":"stop","time":{"completed":1790090430000}}"#,
        ] {
            let entries = AgentLogParser.parseOpenCode(line(json), state: &command, now: now)
            if json.contains(#""id":"ct""#) {
                suite.expect(!ended(entries) && !usage(entries), "the reply holding a subtask neither ends the turn nor counts usage")
            }
            if json.contains(#""id":"cq""#) {
                suite.expect(entries == [.turnActive(Date(timeIntervalSince1970: 1_790_090_421))],
                             "the summary prompt after a command's subtask is activity")
            }
            commandEntries += entries
        }
        suite.expect(commandEntries.filter { if case .turnEnded = $0 { return true }; return false }
                        == [.turnEnded(Date(timeIntervalSince1970: 1_790_090_430), completed: true, duration: 30)],
                     "a command subtask in the middle of a task ends only with the task")

        // A prompt sent while OpenCode works joins the running loop.
        var queued = AgentLogState()
        _ = AgentLogParser.parseOpenCode(line(#"{"id":"q1","session_id":"s_q","time_created":1790090500,"role":"user"}"#),
                                         state: &queued, now: now)
        let second = AgentLogParser.parseOpenCode(line(#"{"id":"q2","session_id":"s_q","time_created":1790090505,"role":"user"}"#),
                                                  state: &queued, now: now)
        let early = AgentLogParser.parseOpenCode(line(#"{"id":"qa","parentID":"q1","session_id":"s_q","time_created":1790090506,"role":"assistant","tokens":{"input":5},"finish":"stop"}"#),
                                                 state: &queued, now: now)
        let last = AgentLogParser.parseOpenCode(line(#"{"id":"qb","parentID":"q2","session_id":"s_q","time_created":1790090510,"role":"assistant","tokens":{"input":5},"finish":"stop"}"#),
                                                state: &queued, now: now)
        suite.expect(second == [.turnActive(Date(timeIntervalSince1970: 1_790_090_505))] && !ended(early)
                        && last.contains(.turnEnded(Date(timeIntervalSince1970: 1_790_090_510), completed: true, duration: 10)),
                     "a prompt sent while the agent works joins its turn, which ends with the reply to it")
    }

    private static func openCodeParts(_ suite: TestSuite, now: Date) {
        guard let (folder, path) = openCodeDatabase("""
        INSERT INTO session VALUES ('s_p', '/code/app', NULL, 1790090600000, 1790090600000);
        INSERT INTO message VALUES ('u1', 's_p', 1790090600000, 1790090600000, '{"role":"user"}');
        INSERT INTO message VALUES ('a_tool', 's_p', 1790090601000, 1790090601000, '{"role":"assistant","parentID":"u1","finish":"stop"}');
        INSERT INTO message VALUES ('a_provider', 's_p', 1790090602000, 1790090602000, '{"role":"assistant","parentID":"u1","finish":"stop"}');
        INSERT INTO message VALUES ('a_orphan', 's_p', 1790090603000, 1790090603000, '{"role":"assistant","parentID":"u1","finish":"stop"}');
        INSERT INTO message VALUES ('a_calls', 's_p', 1790090604000, 1790090604000, '{"role":"assistant","parentID":"u1","finish":"tool-calls"}');
        INSERT INTO message VALUES ('c_auto', 's_p', 1790090605000, 1790090605000, '{"role":"user"}');
        INSERT INTO message VALUES ('s_auto', 's_p', 1790090606000, 1790090606000, '{"role":"assistant","parentID":"c_auto","summary":true,"finish":"stop"}');
        INSERT INTO message VALUES ('c_hand', 's_p', 1790090607000, 1790090607000, '{"role":"user"}');
        INSERT INTO message VALUES ('s_hand', 's_p', 1790090608000, 1790090608000, '{"role":"assistant","parentID":"c_hand","summary":true,"finish":"stop"}');
        INSERT INTO part VALUES ('p0', 'a_tool', 's_p', 0, 0, 'not json');
        INSERT INTO part VALUES ('p1', 'a_tool', 's_p', 0, 0, '{"type":"tool","state":{"status":"completed"}}');
        INSERT INTO part VALUES ('p2', 'a_provider', 's_p', 0, 0, '{"type":"tool","metadata":{"providerExecuted":true},"state":{"status":"completed"}}');
        INSERT INTO part VALUES ('p3', 'a_orphan', 's_p', 0, 0, '{"type":"tool","state":{"status":"error","metadata":{"interrupted":true}}}');
        INSERT INTO part VALUES ('p4', 'a_calls', 's_p', 0, 0, '{"type":"tool","state":{"status":"running"}}');
        INSERT INTO part VALUES ('p5', 'c_auto', 's_p', 0, 0, '{"type":"compaction","auto":true}');
        INSERT INTO part VALUES ('p6', 'c_hand', 's_p', 0, 0, '{"type":"compaction","auto":false}');
        """) else {
            suite.expect(false, "parts database opens")
            return
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let rows = openCodeRead(AgentLogCursor(path: path, provider: .opencode))
        let flags = Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            (row["id"] as? String).map { ($0, (row["tool_calls"] as? Bool == true, row["auto_compaction"] as? Bool == true)) }
        })
        suite.expect(rows.count == 9, "every message is read beside a part that is not JSON")
        suite.expect(flags["a_tool"]?.0 == true && flags["a_provider"]?.0 == false && flags["a_orphan"]?.0 == false,
                     "a finished reply still holding a tool call is told apart from provider and abandoned calls")
        suite.expect(flags["s_auto"]?.1 == true && flags["s_hand"]?.1 == false,
                     "a summary of an automatic compaction is told apart from one asked for by hand")
    }

    // MARK: OpenCode history

    private static func openCodeLongHistory(_ suite: TestSuite) {
        guard let (folder, path) = openCodeDatabase("""
        INSERT INTO session VALUES ('s_h', '/code/app', NULL, 1780000000000, 1790088000000);
        WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 5000)
        INSERT INTO message SELECT 'old' || i, 's_h', 1780000000000 + i * 1000, 1780000000000 + i * 1000,
            '{"role":"assistant","tokens":{"input":1},"finish":"stop","time":{"completed":1}}' FROM n;
        INSERT INTO message VALUES ('u1', 's_h', 1790088000000, 1790088000000, '{"role":"user"}');
        INSERT INTO message VALUES ('a1', 's_h', 1790088001000, 1790088002000, '{"role":"assistant","parentID":"u1","tokens":{"input":5},"finish":"stop","time":{"completed":1790088002000}}');
        """) else {
            suite.expect(false, "history database opens")
            return
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let horizon = Date(timeIntervalSince1970: 1_789_000_000)
        let cursor = AgentLogCursor(path: path, provider: .opencode)
        suite.expect(openCodeRead(cursor, since: horizon).map { $0["id"] as? String } == ["u1", "a1"]
                        && cursor.offset == 5002,
                     "a first read over a long history starts at the horizon")
        openCodeExec(path, """
        UPDATE message SET time_updated = 1790088003000, data = '{"role":"user","summary":{"diffs":[]}}' WHERE id = 'u1';
        UPDATE message SET time_updated = 1790088003000 WHERE id = 'old1';
        INSERT INTO message VALUES ('u2', 's_h', 1790088010000, 1790088010000, '{"role":"user"}');
        """)
        suite.expect(openCodeRead(cursor, since: horizon).map { $0["id"] as? String } == ["u2"],
                     "a later read hands over only the new row, not a prompt saved again or an old row touched")
        suite.expect(openCodeRead(cursor, since: horizon).isEmpty, "a read with nothing new hands over nothing")
    }

    private static func openCodeRevert(_ suite: TestSuite) {
        guard let (folder, path) = openCodeDatabase("""
        INSERT INTO session VALUES ('s_r', '/code/app', NULL, 1790088000000, 1790088000000);
        INSERT INTO message VALUES ('u1', 's_r', 1790088000000, 1790088000000, '{"role":"user"}');
        INSERT INTO message VALUES ('a1', 's_r', 1790088001000, 1790088002000, '{"role":"assistant","parentID":"u1","finish":"stop","time":{"completed":1790088002000}}');
        """) else {
            suite.expect(false, "revert database opens")
            return
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let cursor = AgentLogCursor(path: path, provider: .opencode)
        _ = openCodeRead(cursor)
        // A revert deletes the newest messages; the next prompt takes the rowid a1 had.
        openCodeExec(path, """
        DELETE FROM message WHERE id = 'a1';
        INSERT INTO message VALUES ('u2', 's_r', 1790088010000, 1790088010000, '{"role":"user"}');
        """)
        suite.expect(openCodeRead(cursor).map { $0["id"] as? String } == ["u2"],
                     "a prompt saved in the place of reverted messages is read")
        openCodeExec(path, """
        DELETE FROM message;
        INSERT INTO message VALUES ('u3', 's_r', 1790088020000, 1790088020000, '{"role":"user"}');
        """)
        let rows = openCodeRead(cursor)
        suite.expect(rows.first?["type"] as? String == "reset" && rows.dropFirst().map { $0["id"] as? String } == ["u3"],
                     "when every row read last is gone, reading starts over and says so")
    }

    private static func openCodeOpenReplies(_ suite: TestSuite) {
        guard let (folder, path) = openCodeDatabase("""
        INSERT INTO session VALUES ('s_o', '/code/app', NULL, 1790088000000, 1790088000000);
        INSERT INTO message VALUES ('u1', 's_o', 1790088000000, 1790088000000, '{"role":"user"}');
        INSERT INTO message VALUES ('a1', 's_o', 1790088001000, 1790088001000, '{"role":"assistant","parentID":"u1","time":{"created":1790088001000}}');
        """) else {
            suite.expect(false, "open reply database opens")
            return
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let cursor = AgentLogCursor(path: path, provider: .opencode)
        _ = openCodeRead(cursor)
        suite.expect(openCodeRead(cursor).isEmpty, "a reply still being written is skipped while it is unchanged")
        openCodeExec(path, """
        UPDATE message SET time_updated = 1790088005000, data = '{"role":"assistant","parentID":"u1","tokens":{"input":5},"time":{"created":1790088001000}}' WHERE id = 'a1';
        """)
        suite.expect(openCodeRead(cursor).map { $0["id"] as? String } == ["a1"], "a reply being written is read when it changes")
        openCodeExec(path, """
        UPDATE message SET time_updated = 1790088009000, data = '{"role":"assistant","parentID":"u1","tokens":{"input":9},"finish":"stop","time":{"created":1790088001000,"completed":1790088009000}}' WHERE id = 'a1';
        """)
        suite.expect(openCodeRead(cursor).first?["finish"] as? String == "stop", "its completion is read")
        openCodeExec(path, "UPDATE message SET time_updated = 1790088012000 WHERE id = 'a1';")
        suite.expect(openCodeRead(cursor).isEmpty, "a completed reply is not looked up again")
    }

    // MARK: OpenCode stopped loops

    private static func openCodeStoppedLoops(_ suite: TestSuite, now: Date) {
        func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

        // A tool call rejected: the step completes with tool calls and the
        // loop stops. A new prompt comes a couple of minutes later.
        var state = AgentLogState()
        let store = AgentUsageStore()
        store.reportsTransitions = true
        var events: [AgentUsageEvent] = []
        func feed(_ json: String, at seconds: TimeInterval) -> [AgentLogEntry] {
            let entries = AgentLogParser.parseOpenCode(line(json), state: &state, now: now)
            events += store.apply(entries, file: "db#s_x", provider: .opencode, tracksTurns: true, modified: now,
                                  now: at(seconds))
            return entries
        }
        _ = feed(#"{"id":"u1","session_id":"s_x","time_created":1790091000,"role":"user"}"#, at: 1_790_091_000)
        let rejected = feed(#"{"id":"a1","parentID":"u1","session_id":"s_x","time_created":1790091001,"role":"assistant","cost":0.05,"tokens":{"input":500,"output":50},"finish":"tool-calls","time":{"created":1790091001000,"completed":1790091005000}}"#, at: 1_790_091_005)
        suite.expect(rejected.contains(.turnSettled(at(1_790_091_005))) && store.live.count == 1,
                     "a step that completed with tool calls leaves the turn waiting for the next step")
        suite.expect(!store.closeSettledTurns(now: at(1_790_091_010)) && store.live.count == 1,
                     "the turn goes on while the next step can still start")
        suite.expect(store.closeSettledTurns(now: at(1_790_091_040)) && store.live.isEmpty && events.isEmpty,
                     "with no next step the loop stopped, and its turn ends without a notice")
        let prompt = feed(#"{"id":"u2","session_id":"s_x","time_created":1790091120,"role":"user"}"#, at: 1_790_091_120)
        suite.expect(prompt == [.turnEnded(at(1_790_091_005), completed: false, duration: nil), .turnBegan(at(1_790_091_120))],
                     "a later prompt closes the stopped task quietly and opens its own")
        let answer = feed(#"{"id":"a2","parentID":"u2","session_id":"s_x","time_created":1790091121,"role":"assistant","cost":0.01,"tokens":{"input":100,"output":10},"finish":"stop","time":{"created":1790091121000,"completed":1790091130000}}"#, at: 1_790_091_130)
        suite.expect(answer.contains(.turnEnded(at(1_790_091_130), completed: true, duration: 10))
                        && events == [.finished(provider: .opencode, duration: 10, cost: 0.01, tokens: 110, project: "")],
                     "the new task's notice counts from its own prompt and only its own cost")

        // OpenCode's own request right after a step is no new task.
        var own = AgentLogState()
        _ = AgentLogParser.parseOpenCode(line(#"{"id":"u1","session_id":"s_y","time_created":1790091200,"role":"user"}"#), state: &own, now: now)
        _ = AgentLogParser.parseOpenCode(line(#"{"id":"a1","parentID":"u1","session_id":"s_y","time_created":1790091201,"role":"assistant","tokens":{"input":5},"finish":"tool-calls","time":{"completed":1790091205000}}"#), state: &own, now: now)
        suite.expect(AgentLogParser.parseOpenCode(line(#"{"id":"c1","session_id":"s_y","time_created":1790091206,"role":"user"}"#), state: &own, now: now)
                        == [.turnActive(at(1_790_091_206))],
                     "a prompt OpenCode writes right after a step is activity")

        // OpenCode killed in the middle of a reply, then started again.
        var killed = AgentLogState()
        _ = AgentLogParser.parseOpenCode(line(#"{"id":"u1","session_id":"s_k","time_created":1790091300,"role":"user"}"#), state: &killed, now: now)
        _ = AgentLogParser.parseOpenCode(line(#"{"id":"a1","parentID":"u1","session_id":"s_k","time_created":1790091301,"role":"assistant","tokens":{"input":5}}"#), state: &killed, now: now)
        let later = AgentLogParser.parseOpenCode(line(#"{"id":"u2","session_id":"s_k","time_created":1790178000,"role":"user"}"#), state: &killed, now: now)
        let restarted = AgentLogParser.parseOpenCode(line(#"{"id":"a2","parentID":"u2","session_id":"s_k","time_created":1790178001,"role":"assistant","tokens":{"input":5},"finish":"stop","time":{"completed":1790178010000}}"#), state: &killed, now: now)
        suite.expect(later == [.turnActive(at(1_790_178_000))]
                        && restarted.starts(with: [.turnEnded(nil, completed: false, duration: nil), .turnBegan(at(1_790_178_000))])
                        && restarted.contains(.turnEnded(at(1_790_178_010), completed: true, duration: 10)),
                     "a reply to a newer prompt while an older reply never completed starts the task over from that prompt")

        // A prompt sent during a long command joins the task.
        var long = AgentLogState()
        var all: [AgentLogEntry] = []
        for json in [
            #"{"id":"u1","session_id":"s_l","time_created":1790091400,"role":"user"}"#,
            #"{"id":"a1","parentID":"u1","session_id":"s_l","time_created":1790091401,"role":"assistant","tokens":{"input":5}}"#,
            #"{"id":"u2","session_id":"s_l","time_created":1790092300,"role":"user"}"#,
            #"{"id":"a1","parentID":"u1","session_id":"s_l","time_created":1790091401,"role":"assistant","tokens":{"input":9},"finish":"tool-calls","time":{"completed":1790092400000}}"#,
            #"{"id":"a2","parentID":"u2","session_id":"s_l","time_created":1790092401,"role":"assistant","tokens":{"input":5},"finish":"stop","time":{"completed":1790092410000}}"#,
        ] {
            all += AgentLogParser.parseOpenCode(line(json), state: &long, now: now)
        }
        suite.expect(all.filter { if case .turnBegan = $0 { return true }; return false }.count == 1
                        && all.filter { if case .turnEnded = $0 { return true }; return false }
                            == [.turnEnded(at(1_790_092_410), completed: true, duration: 1010)],
                     "a prompt sent while a long command runs joins the task, which ends once")
    }

    // MARK: OpenCode quiet sessions

    private static func openCodeQuietSessions(_ suite: TestSuite, now: Date) {
        func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
        var state = AgentLogState()
        let store = AgentUsageStore()
        store.reportsTransitions = true
        var events: [AgentUsageEvent] = []
        func feed(_ json: String, at seconds: TimeInterval) -> [AgentLogEntry] {
            let entries = AgentLogParser.parseOpenCode(line(json), state: &state, now: now)
            events += store.apply(entries, file: "db#\(state.session)", provider: .opencode, tracksTurns: true,
                                  modified: now, now: at(seconds))
            return entries
        }
        _ = feed(#"{"id":"u1","session_id":"s_d","time_created":1790092000,"directory":"/code/app","role":"user"}"#, at: 1_790_092_000)
        _ = feed(#"{"id":"a1","parentID":"u1","session_id":"s_d","time_created":1790092001,"directory":"/code/app","role":"assistant","tokens":{"input":5},"finish":"stop","time":{"completed":1790092005000}}"#, at: 1_790_092_005)
        _ = feed(#"{"id":"w1","session_id":"s_w","time_created":1790092010,"role":"user"}"#, at: 1_790_092_010)
        _ = feed(#"{"id":"wa","parentID":"w1","session_id":"s_w","time_created":1790092011,"role":"assistant","tokens":{"input":5},"time":{"created":1790092011000}}"#, at: 1_790_092_011)
        // Another session starts well after both went quiet.
        _ = feed(#"{"id":"n1","session_id":"s_n","time_created":1790093000,"role":"user"}"#, at: 1_790_093_000)
        suite.expect(state.openCodeSessions["s_d"] == nil && state.openCodeSessions["s_w"] != nil
                        && state.openCodeSessions["s_n"] != nil,
                     "a quiet session is let go as another one starts, unless a reply is still being written")
        let prompt = feed(#"{"id":"u2","session_id":"s_d","time_created":1790093100,"directory":"/code/app","role":"user"}"#, at: 1_790_093_100)
        let reply = feed(#"{"id":"a2","parentID":"u2","session_id":"s_d","time_created":1790093101,"directory":"/code/app","role":"assistant","model_id":"stealth/ox-alpha","cost":0.01,"tokens":{"input":100,"output":10},"finish":"stop","time":{"completed":1790093110000}}"#, at: 1_790_093_110)
        suite.expect(prompt == [.turnBegan(at(1_790_093_100))]
                        && reply.contains(.turnEnded(at(1_790_093_110), completed: true, duration: 10))
                        && events.count == 2
                        && events.last == AgentUsageEvent.finished(provider: .opencode, duration: 10, cost: 0.01,
                                                                   tokens: 110, project: "app")
                        && store.records.filter { $0.session == "s_d" }.count == 2,
                     "a later prompt in a session let go opens its own turn, which counts only its own reply")

        // Sessions one after another keep only the one still going.
        var many = AgentLogState()
        for index in 0..<200 {
            let start = 1_790_100_000 + index * 700
            _ = AgentLogParser.parseOpenCode(line(#"{"id":"u","session_id":"s\#(index)","time_created":\#(start),"role":"user"}"#),
                                             state: &many, now: now)
            _ = AgentLogParser.parseOpenCode(line(#"{"id":"a","parentID":"u","session_id":"s\#(index)","time_created":\#(start + 1),"role":"assistant","tokens":{"input":5},"finish":"stop","time":{"completed":\#((start + 5) * 1000)}}"#),
                                             state: &many, now: now)
        }
        suite.expect(many.openCodeSessions.count == 1, "sessions that went quiet one after another are not kept")
    }

    private static func timestamps(_ suite: TestSuite) {
        suite.expectClose(AgentTimestamp.parse("2026-09-21T23:42:45.078Z")?.timeIntervalSince1970 ?? 0, 1_790_034_165.078,
                          "the usual log time parses without a formatter", tol: 0.00001)
        suite.expectClose(AgentTimestamp.parse("2026-09-22T22:00:00.123456+00:00")?.timeIntervalSince1970 ?? 0,
                          1_790_114_400.123456, "a long fraction and an offset parse", tol: 0.00001)
        suite.expect(AgentTimestamp.parse("2026-09-22T19:00:00-03:00") == AgentTimestamp.parse("2026-09-22T22:00:00Z"),
                     "an offset moves the time to UTC")
        suite.expect(AgentTimestamp.parse("yesterday") == nil && AgentTimestamp.parse("2026-13-01T00:00:00Z") == nil,
                     "anything else is refused")
    }

    // MARK: Summaries

    private static func record(_ provider: AgentProvider, _ date: Date, cost: Double?, tokens: Int = 1000,
                               model: String = "claude-opus-5", project: String = "app") -> AgentUsageRecord {
        AgentUsageRecord(provider: provider, date: date, model: model, project: project, session: "s",
                         tokens: AgentTokens(input: tokens), cost: cost, savings: 0)
    }

    private static func summary(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = AgentTimestamp.parse("2026-09-22T16:40:00Z")!
        let records = [
            record(.claude, AgentTimestamp.parse("2026-09-22T10:12:00Z")!, cost: 2),
            record(.claude, AgentTimestamp.parse("2026-09-22T11:30:00Z")!, cost: 5, model: "claude-sonnet-5"),
            record(.claude, AgentTimestamp.parse("2026-09-22T15:20:00Z")!, cost: 1),
            record(.codex, AgentTimestamp.parse("2026-09-22T16:30:00Z")!, cost: 4, model: "gpt-6-astra", project: "web"),
            record(.codex, AgentTimestamp.parse("2026-09-18T09:00:00Z")!, cost: 10, model: "gpt-6-astra", project: "web"),
            record(.claude, AgentTimestamp.parse("2026-09-01T09:00:00Z")!, cost: 100),
            record(.claude, AgentTimestamp.parse("2026-01-01T09:00:00Z")!, cost: 1000),
        ]
        let snapshot = AgentUsageSummary.snapshot(records: records, limits: [:], live: [], plans: [:],
                                                  providers: [.claude, .codex], now: now, calendar: calendar)
        suite.expect(snapshot.usage(.today).total.cost == 12 && snapshot.usage(.week).total.cost == 22
                        && snapshot.usage(.month).total.cost == 122,
                     "today, a week and thirty days each add what falls inside them")
        suite.expect(snapshot.days.count == AgentUsageSnapshot.dayCount && snapshot.days.last?.start == calendar.startOfDay(for: now)
                        && snapshot.days.reduce(0.0) { $0 + $1.total.cost } == 122,
                     "the daily history ends today and leaves out what is older")
        suite.expect(snapshot.hours.count == 24 && snapshot.hours[10].total.cost == 2 && snapshot.hours[16].total.cost == 4,
                     "today's hours hold each response in its hour")
        suite.expect(snapshot.usage(.today).models.map(\.name) == ["Sonnet 5", "GPT-6 Astra", "Opus 5"]
                        && snapshot.usage(.today).projects.map(\.name) == ["app", "web"],
                     "models and projects are ranked by what they cost")
        suite.expect(snapshot.claudeBlock == AgentBlock(start: AgentTimestamp.parse("2026-09-22T15:20:00Z")!,
                                                        end: AgentTimestamp.parse("2026-09-22T20:20:00Z")!,
                                                        totals: { var totals = AgentTotals(); totals.add(records[2]); return totals }()),
                     "Claude's window starts at the first request after the last one ended")
        suite.expect(snapshot.burnRate[.codex]?.cost == 8 && snapshot.burnRate[.claude] == nil,
                     "the last half hour is scaled to an hour")
        suite.expect(snapshot.lastActivity[.codex] == records[3].date && snapshot.seen == [.claude, .codex],
                     "each agent's latest activity is kept")
        let unpriced = AgentUsageSummary.snapshot(records: [record(.codex, now, cost: nil, tokens: 500)] + records.prefix(1),
                                                  limits: [:], live: [], plans: [:], providers: [.claude, .codex],
                                                  now: now, calendar: calendar)
        suite.expect(!unpriced.usage(.today).fullyPriced && unpriced.usage(.today).total.unpriced == 1
                        && unpriced.usage(.today).models.first?.name == "Opus 5",
                     "an unpriced model makes totals a minimum and ranks fall back to tokens")
        let claudeOnly = AgentUsageSummary.snapshot(records: records, limits: [:], live: [], plans: [:],
                                                    providers: [.claude], now: now, calendar: calendar)
        suite.expect(claudeOnly.usage(.today).total.cost == 8 && !claudeOnly.seen.contains(.codex),
                     "an agent turned off leaves every total")
        let late = AgentUsageSummary.currentBlock(Array(records.prefix(3)), now: AgentTimestamp.parse("2026-09-22T20:20:00Z")!)
        suite.expect(late == nil, "a window that has ended is no longer current")

        // Steady work from morning to evening: the chain of windows starts
        // with the day's first request, at its own minute even where the
        // clock sits half an hour off.
        let morning = AgentTimestamp.parse("2026-09-22T06:10:00Z")!
        let steps: [Int] = Array(0...34)
        let steady: [AgentUsageRecord] = steps.map { step in
            record(.claude, morning.addingTimeInterval(TimeInterval(step) * 1200), cost: 1)
        }
        var kolkata = Calendar(identifier: .gregorian)
        kolkata.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let evening = AgentTimestamp.parse("2026-09-22T17:30:00Z")!
        let steadyDay = AgentUsageSummary.snapshot(records: steady, limits: [:], live: [], plans: [:], providers: [.claude],
                                                   now: evening, calendar: kolkata)
        suite.expect(steadyDay.claudeBlock?.start == AgentTimestamp.parse("2026-09-22T16:10:00Z")
                        && steadyDay.claudeBlock?.end == AgentTimestamp.parse("2026-09-22T21:10:00Z"),
                     "a day of steady work keeps the window its first request placed, to the minute")

        // A snapshot is made again only when time alone would change it.
        let noon = AgentTimestamp.parse("2026-09-22T12:00:00Z")!
        let hourOn = noon.addingTimeInterval(3600)
        let nextDay = AgentTimestamp.parse("2026-09-23T00:00:30Z")!
        let resting = AgentUsageSummary.snapshot(records: [record(.codex, noon.addingTimeInterval(-7200), cost: 1)],
                                                 limits: [:], live: [], plans: [:], providers: [.claude, .codex],
                                                 now: noon, calendar: calendar)
        suite.expect(!AgentUsageSummary.movesWithClock(resting, now: hourOn, calendar: calendar)
                        && AgentUsageSummary.movesWithClock(resting, now: nextDay, calendar: calendar),
                     "a snapshot with nothing recent holds until a new day moves every total")
        let burning = AgentUsageSummary.snapshot(records: [record(.codex, noon.addingTimeInterval(-600), cost: 1)],
                                                 limits: [:], live: [], plans: [:], providers: [.claude, .codex],
                                                 now: noon, calendar: calendar)
        let windowOpen = AgentUsageSummary.snapshot(records: [record(.claude, noon.addingTimeInterval(-5400), cost: 1)],
                                                    limits: [:], live: [], plans: [:], providers: [.claude, .codex],
                                                    now: noon, calendar: calendar)
        suite.expect(AgentUsageSummary.movesWithClock(burning, now: hourOn, calendar: calendar)
                        && windowOpen.burnRate.isEmpty && windowOpen.claudeBlock != nil
                        && AgentUsageSummary.movesWithClock(windowOpen, now: hourOn, calendar: calendar),
                     "the last half hour and an open Claude window move with the clock")
        suite.expect(AgentUsageSummary.movesWithClock(AgentUsageSnapshot(), now: noon), "the first snapshot is always made")
        suite.expect(AgentUsageSummary.index(of: now, in: [now.addingTimeInterval(-10), now, now.addingTimeInterval(10)]) == 1
                        && AgentUsageSummary.index(of: now.addingTimeInterval(-20), in: [now]) == nil,
                     "a time falls in the last bucket that starts at or before it")
    }

    private static func limits(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let week = 10_080
        func window(_ used: Double, resetsIn: TimeInterval, id: String = "w", minutes: Int = week) -> AgentLimitWindow {
            AgentLimitWindow(id: id, kind: .weekly, minutes: minutes, scope: nil, usedPercent: used,
                             resetsAt: now.addingTimeInterval(resetsIn))
        }
        let half = 3.5 * 86_400
        suite.expect(AgentLimitSupport.pace(for: window(75, resetsIn: half), now: now)?.elapsed == 0.5
                        && AgentLimitSupport.pace(for: window(25, resetsIn: 7 * 86_400 - 60), now: now)?.elapsed == 60.0 / (7 * 86_400),
                     "the pace mark sits where the window's time has reached")
        suite.expect(AgentLimitSupport.pace(for: window(25, resetsIn: -1), now: now) == nil
                        && AgentLimitSupport.pace(for: window(25, resetsIn: 8 * 86_400), now: now) == nil,
                     "a renewed window, or one read before it began, has no pace mark")
        let renewed = AgentLimitSupport.current(window(90, resetsIn: -1), at: now)
        suite.expect(renewed.usedPercent == 0 && renewed.resetsAt == nil, "a window past its renewal has nothing spent")
        let reading = AgentLimits(provider: .codex, windows: [window(40, resetsIn: 100, id: "a"), window(60, resetsIn: 50, id: "b")],
                                  observedAt: now, source: .sessionLog)
        suite.expect(AgentLimitSupport.binding(reading, now: now)?.id == "b", "the most spent window binds")
        func limits(_ used: Double, resets: TimeInterval) -> AgentLimits {
            AgentLimits(provider: .codex, windows: [window(used, resetsIn: resets)], observedAt: now, source: .sessionLog)
        }
        suite.expect(AgentLimitSupport.crossings(previous: limits(70, resets: 100), current: limits(85, resets: 100), threshold: 80).count == 1
                        && AgentLimitSupport.crossings(previous: limits(85, resets: 100), current: limits(90, resets: 100), threshold: 80).isEmpty
                        && AgentLimitSupport.crossings(previous: limits(85, resets: 100), current: limits(85, resets: 9000), threshold: 80).count == 1
                        && AgentLimitSupport.crossings(previous: nil, current: limits(99, resets: 100), threshold: 80).isEmpty,
                     "a warning comes once per crossing, again after a renewal, never for the first reading")
    }

    // MARK: Reading files

    private static func liveTurns(_ suite: TestSuite) {
        let start = Date(timeIntervalSince1970: 3_000_000)
        let tokens = AgentTokens(input: 1000, cacheWrite: 0, cacheRead: 9000, output: 200)
        let record = AgentUsageRecord(provider: .codex, date: start.addingTimeInterval(10), model: "gpt-6-sol",
                                      project: "app", session: "s", tokens: tokens, cost: 0.5, savings: 0)
        let entries: [AgentLogEntry] = [.turnBegan(start), .usage(key: "codex:r1", record: record, billable: AgentBillable(tokens: tokens))]
        let store = AgentUsageStore()
        store.apply(entries, file: "/logs/a.jsonl", provider: .codex, tracksTurns: true, modified: start)
        // The same log replaced by a longer copy is read again from its start.
        store.apply(entries, file: "/logs/a.jsonl", provider: .codex, tracksTurns: true, modified: start)
        let turn = store.live.first
        suite.expect(store.live.count == 1 && turn?.model == "gpt-6-sol" && turn?.project == "app"
                        && turn?.tokens.total == 10_200 && turn?.started == start,
                     "a log rewritten in place keeps the running turn's model, project and tokens")
        store.apply([.turnBegan(start.addingTimeInterval(60))], file: "/logs/a.jsonl", provider: .codex,
                    tracksTurns: true, modified: start)
        suite.expect(store.live.first?.tokens.total == 0, "a new turn in the same log starts from nothing")
        suite.expect(store.forget(file: "/logs/a.jsonl") && store.live.isEmpty && !store.forget(file: "/logs/a.jsonl"),
                     "a removed log, like a deleted chat, stops showing as working")

        // A turn that goes quiet, as while it waits for an approval, comes
        // back when its work resumes and finishes as the whole turn.
        let quiet = AgentUsageStore()
        quiet.reportsTransitions = true
        let waitingLog = "/logs/b.jsonl"
        quiet.apply([.turnBegan(start)], file: waitingLog, provider: .codex, tracksTurns: true, modified: start, now: start)
        quiet.closeIdleTurns(now: start.addingTimeInterval(1200), after: NotchAgentSupport.idleTurn)
        suite.expect(quiet.live.isEmpty && quiet.waiting[waitingLog]?.started == start,
                     "a quiet turn stops showing as working and waits aside")
        let resumedAt = start.addingTimeInterval(1210)
        let resumed = AgentUsageRecord(provider: .codex, date: resumedAt, model: "gpt-6-sol", project: "app",
                                       session: "s", tokens: tokens, cost: 0.5, savings: 0)
        quiet.apply([.usage(key: "codex:r2", record: resumed, billable: AgentBillable(tokens: tokens))], file: waitingLog,
                    provider: .codex, tracksTurns: true, modified: resumedAt, now: resumedAt)
        suite.expect(quiet.live.first?.started == start && quiet.waiting.isEmpty, "work that resumes brings the turn back")
        let endedAt = start.addingTimeInterval(1300)
        let ended = quiet.apply([.turnEnded(endedAt, completed: true, duration: nil)], file: waitingLog, provider: .codex,
                                tracksTurns: true, modified: endedAt, now: endedAt)
        let whole = AgentUsageEvent.finished(provider: .codex, duration: 1300, cost: 0.5, tokens: tokens.total, project: "app")
        suite.expect(ended == [whole] && quiet.live.isEmpty, "a turn that waited finishes as the whole turn, with what it spent")
        quiet.apply([.turnBegan(endedAt)], file: waitingLog, provider: .codex, tracksTurns: true, modified: endedAt)
        quiet.closeIdleTurns(now: endedAt.addingTimeInterval(1200), after: NotchAgentSupport.idleTurn)
        let nextStart = endedAt.addingTimeInterval(1500)
        quiet.apply([.turnBegan(nextStart)], file: waitingLog, provider: .codex, tracksTurns: true, modified: nextStart)
        suite.expect(quiet.waiting.isEmpty && quiet.live.first?.started == nextStart, "a new turn replaces one that went quiet")
        quiet.closeIdleTurns(now: nextStart.addingTimeInterval(AgentUsageStore.resumeWindow(for: .codex)),
                             after: NotchAgentSupport.idleTurn)
        suite.expect(quiet.live.isEmpty && quiet.waiting.isEmpty, "a turn quiet for hours is over")
        let claudeLog = "/logs/c.jsonl"
        quiet.apply([.turnBegan(start)], file: claudeLog, provider: .claude, tracksTurns: true, modified: start, now: start)
        quiet.closeIdleTurns(now: start.addingTimeInterval(1200), after: NotchAgentSupport.idleTurn)
        let claudeWait = AgentUsageStore.resumeWindow(for: .claude)
        quiet.closeIdleTurns(now: start.addingTimeInterval(claudeWait + 1), after: NotchAgentSupport.idleTurn)
        suite.expect(quiet.waiting.isEmpty && claudeWait < AgentUsageStore.resumeWindow(for: .codex),
                     "a Claude turn that a killed session left open stops waiting sooner")
        sessionProcesses(suite, start: start)

        // A Claude subagent's responses count toward the turn it works for.
        let sessionLog = "/x/p/s1.jsonl"
        let helper = AgentLogCursor(path: "/x/p/s1/subagents/agent-a1.jsonl", provider: .claude)
        let team = AgentUsageStore()
        team.apply([.turnBegan(start)], file: sessionLog, provider: .claude, tracksTurns: true, modified: start)
        let own = AgentUsageRecord(provider: .claude, date: start.addingTimeInterval(5), model: "claude-opus-5-5",
                                   project: "app", session: "s1", tokens: tokens, cost: 1, savings: 0)
        team.apply([.usage(key: "claude:m1:r1", record: own, billable: AgentBillable(tokens: tokens))], file: sessionLog,
                   provider: .claude, tracksTurns: true, modified: start)
        let delegatedAt = start.addingTimeInterval(30)
        let delegated = AgentUsageRecord(provider: .claude, date: delegatedAt, model: "claude-haiku-4-5",
                                         project: "tools", session: "s1", tokens: tokens, cost: 0.25, savings: 0)
        team.apply([.usage(key: "claude:m2:r2", record: delegated, billable: AgentBillable(tokens: tokens))],
                   file: helper.path, provider: .claude, tracksTurns: helper.tracksTurns, parent: helper.parent,
                   modified: start)
        let served = team.live.first
        suite.expect(helper.parent == sessionLog && team.live.count == 1 && served?.cost == 1.25
                        && served?.lastActivity == delegatedAt,
                     "a subagent's spend and activity count toward the turn it works for")
        suite.expect(served?.model == "claude-opus-5-5" && served?.project == "app",
                     "the turn keeps the model and project the session chose")
    }

    private static func strip(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 2_000_000)
        func session(_ provider: AgentProvider, startedAgo: TimeInterval) -> AgentLiveSession {
            AgentLiveSession(id: provider.rawValue, provider: provider, started: now.addingTimeInterval(-startedAgo),
                             lastActivity: now, model: "claude-opus-5-5", project: "app",
                             tokens: AgentTokens(input: 1200, cacheWrite: 0, cacheRead: 0, output: 300), cost: 4.56)
        }
        func snapshot(_ live: [AgentLiveSession], limits: [AgentProvider: AgentLimits] = [:]) -> AgentUsageSnapshot {
            AgentUsageSummary.snapshot(records: [], limits: limits, live: live, plans: [:],
                                       providers: [.claude, .codex], now: now)
        }
        suite.expect(NotchAgentReadout.elapsed.advancesWithClock && NotchAgentReadout.limit.advancesWithClock
                        && !NotchAgentReadout.tokens.advancesWithClock && !NotchAgentReadout.cost.advancesWithClock,
                     "only elapsed and expiring-limit readouts require clock-driven updates")
        let short = snapshot([session(.claude, startedAgo: 754)])
        let long = snapshot([session(.claude, startedAgo: 3723), session(.codex, startedAgo: 60)])
        suite.expect(NotchAgentSupport.stripReading(short, readout: .elapsed, display: .remaining, now: now) == "12:34"
                        && NotchAgentSupport.stripReading(long, readout: .elapsed, display: .remaining, now: now) == "1:02:03",
                     "the strip counts from the earliest turn still working")
        suite.expect(NotchAgentSupport.stripReading(short, readout: .cost, display: .remaining, now: now) == AgentFormat.cost(4.56)
                        && NotchAgentSupport.stripReading(long, readout: .tokens, display: .remaining, now: now)
                            == AgentFormat.tokens(600),
                     "cost and written tokens add up every turn that is working")
        for readout in [NotchAgentReadout.tokens, .cost] {
            suite.expect(NotchAgentSupport.stripReading(short, readout: readout, display: .remaining, now: now)
                            == NotchAgentSupport.stripReading(short, readout: readout, display: .remaining,
                                                             now: now.addingTimeInterval(60)),
                         "time alone never changes the \(readout.rawValue) reading")
            suite.expect(NotchAgentSupport.stripReading(short, readout: readout, display: .remaining, now: now)
                            != NotchAgentSupport.stripReading(long, readout: readout, display: .remaining, now: now),
                         "a new usage snapshot still changes the \(readout.rawValue) reading")
        }
        let window = AgentLimitWindow(id: "w", kind: .weekly, minutes: 10_080, scope: nil, usedPercent: 79,
                                      resetsAt: now.addingTimeInterval(86_400))
        let limited = snapshot([session(.claude, startedAgo: 754)],
                               limits: [.claude: AgentLimits(provider: .claude, windows: [window], observedAt: now, source: .claudeApp)])
        suite.expect(NotchAgentSupport.stripReading(limited, readout: .limit, display: .remaining, now: now) == AgentFormat.percent(0.21)
                        && NotchAgentSupport.stripReading(limited, readout: .limit, display: .used, now: now) == AgentFormat.percent(0.79)
                        && NotchAgentSupport.stripReading(short, readout: .limit, display: .remaining, now: now) == "12:34",
                     "a limit reads as left or used, and falls back to the time while none is known")
        let both = AgentLimits(provider: .claude, windows: [
            AgentLimitWindow(id: "s", kind: .session, minutes: 300, scope: nil, usedPercent: 22,
                             resetsAt: now.addingTimeInterval(3_600)),
            window,
            AgentLimitWindow(id: "o", kind: .weekly, minutes: 10_080, scope: "Opus", usedPercent: 95,
                             resetsAt: now.addingTimeInterval(86_400))], observedAt: now, source: .claudeApp)
        let working = snapshot([session(.claude, startedAgo: 754)], limits: [.claude: both])
        suite.expect(NotchAgentSupport.stripReading(working, readout: .limit, display: .used, now: now) == AgentFormat.percent(0.95)
                        && NotchAgentSupport.stripReading(working, readout: .limit, display: .used, focus: .session, now: now)
                            == AgentFormat.percent(0.22)
                        && NotchAgentSupport.stripReading(working, readout: .limit, display: .used, focus: .weekly, now: now)
                            == AgentFormat.percent(0.79),
                     "the closed island shows the chosen window, and a model's own allowance never stands for the week")
        suite.expect(NotchAgentSupport.stripReading(working, readout: .limit, display: .used, focus: .session,
                                                    now: now.addingTimeInterval(3_601)) == AgentFormat.percent(0),
                     "a chosen session that renewed reads as unspent")
        suite.expect(NotchAgentSupport.stripReading(limited, readout: .limit, display: .used, focus: .session, now: now)
                        == AgentFormat.percent(0.79),
                     "without the chosen window the closed island shows the one closest to running out")
        let codexWeek = AgentLimits(provider: .codex, windows: [
            AgentLimitWindow(id: "cw", kind: .weekly, minutes: 10_080, scope: nil, usedPercent: 70,
                             resetsAt: now.addingTimeInterval(86_400))], observedAt: now, source: .sessionLog)
        let resting = snapshot([], limits: [.claude: both, .codex: codexWeek])
        suite.expect(NotchAgentSupport.restingLimit(resting, focus: .session, now: now)
                        .map { $0.provider == .claude && $0.window.usedPercent == 22 } == true,
                     "the resting island compares only the chosen windows while any account reports one")
        suite.expect(NotchAgentSupport.restingLimit(snapshot([], limits: [.codex: codexWeek]), focus: .session, now: now)
                        .map { $0.provider == .codex && $0.window.usedPercent == 70 } == true
                        && NotchAgentSupport.restingLimit(resting, focus: .mostUsed, now: now)
                            .map { $0.provider == .claude && $0.window.usedPercent == 95 } == true,
                     "the resting island falls back to the most used window only when no account reports the chosen one")
        let expiredAt = now.addingTimeInterval(86_401)
        suite.expect(NotchAgentSupport.stripReading(limited, readout: .limit, display: .remaining, now: expiredAt)
                        == AgentFormat.percent(1),
                     "a limit that renews without a new snapshot still updates from the clock")
        suite.expect(NotchAgentSupport.readingShape("12:34") == NotchAgentSupport.readingShape("59:59")
                        && NotchAgentSupport.readingShape("9:59") != NotchAgentSupport.readingShape("10:00")
                        && NotchAgentSupport.readingShape("$4,56") == "$0,00",
                     "only a reading that gains or loses a character changes the strip's width")
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                                     cameraWidth: 185, layout: .spacious, compactSideRoom: 300)
        suite.expect(geometry.compactAgentGeometry(wing: 57.2).compactActivityWingWidth == 58
                        && geometry.compactAgentGeometry(wing: 57.2).compactActivitySize.width == 185 + 116,
                     "the wings take the width the reading needs, with the camera between them")
        suite.expect(geometry.compactAgentGeometry(wing: 12).compactActivityWingWidth == 44
                        && geometry.compactAgentGeometry(wing: 300).compactActivityWingWidth == 80,
                     "a wing is never narrower than the music strip's nor wider than the menus allow")
        var crowded = geometry
        crowded.compactSideRoom = 30
        suite.expect(crowded.compactAgentGeometry(wing: 57).compactActivityWingWidth == 0
                        && !crowded.compactAgentGeometry(wing: 57).compactActivityUsesFooter,
                     "without room beside the camera the strip keeps to the cutout, never below it")
    }

    /// A Claude session quit or killed mid-turn ends the turn by its process
    /// record, not after the quiet wait.
    private static func sessionProcesses(_ suite: TestSuite, start: Date) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-agent-sessions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func write(_ name: String, _ text: String) {
            FileManager.default.createFile(atPath: folder.appending(path: name).path, contents: Data(text.utf8))
        }
        write("100.json", #"{"pid":100,"sessionId":"quit","cwd":"/p/app","name":"app-1","status":"busy","startedAt":1790000000000,"statusUpdatedAt":1790000060000}"#)
        write("200.json", #"{"pid":200,"sessionId":"killed"}"#)
        write("300.json", #"{"pid":300,"sessionId":"killed"}"#)
        write("300.abc.key", "{}")
        write("500.json", #"{"pid":500,"sessionId":"contained","pidDomain":"linux:4f2ac19e:4026531836"}"#)
        write(".heartbeat", "1")
        let running: Set<Int32> = [100, 300]
        var registry = AgentSessionRegistry.read([folder, folder.appending(path: "missing")]) { running.contains($0) }
        suite.expect(registry.running == ["quit", "killed"] && registry.ended.isEmpty && registry.complete && registry.listed,
                     "a session with a running process reads as running, even beside a killed one's record, and a container's record proves nothing")
        let quitRecord = AgentSessionRecord(pid: 100, session: "quit", cwd: "/p/app", name: "app-1", status: .busy,
                                            started: Date(timeIntervalSince1970: 1_790_000_000),
                                            statusChanged: Date(timeIntervalSince1970: 1_790_000_060))
        suite.expect(registry.records["quit"] == quitRecord && registry.records["killed"]?.pid == 300
                        && registry.records["killed"]?.status == nil && registry.records["contained"] == nil
                        && registry.records.count == 2,
                     "a running session keeps its folder, name, status and times; one without a status proves nothing")
        write("400.json", #"{"pid":"#)
        registry = AgentSessionRegistry.read([folder]) { $0 == 100 }
        suite.expect(registry.running == ["quit"] && registry.ended == ["killed"] && !registry.complete,
                     "a killed process's record reads as ended, and a record being written leaves the list incomplete")

        let store = AgentUsageStore()
        for name in ["quit", "killed", "other", "partial"] {
            store.apply([.turnBegan(start)], file: "/p/\(name).jsonl", provider: .claude, tracksTurns: true, modified: start)
        }
        store.apply([.turnBegan(start)], file: "/p/quit-codex.jsonl", provider: .codex, tracksTurns: true, modified: start)
        store.closeEndedTurns(AgentSessionRegistry(running: ["quit", "partial"], ended: [], complete: true))
        suite.expect(store.live.count == 5, "turns with a running process, or with no record at all, keep working")
        store.closeEndedTurns(AgentSessionRegistry(running: [], ended: [], complete: false))
        suite.expect(store.live.count == 5, "a record missing from an incomplete read proves nothing")
        let closed = store.closeEndedTurns(AgentSessionRegistry(running: ["partial"], ended: ["killed"], complete: true))
        suite.expect(closed && Set(store.live.map(\.id)) == ["/p/other.jsonl", "/p/partial.jsonl", "/p/quit-codex.jsonl"]
                        && store.waiting.isEmpty,
                     "a session whose process quit or was killed stops working at once, without waiting aside")
        store.closeEndedTurns(AgentSessionRegistry(running: [], ended: [], complete: true))
        suite.expect(store.live.count == 2 && !store.live.contains { $0.id == "/p/partial.jsonl" },
                     "a record that disappears ends the turn it was running")
        suite.expect(AgentSessionRegistry.read([folder.appending(path: "missing")]) { _ in true }
                        == AgentSessionRegistry(running: [], ended: [], complete: true, listed: false),
                     "without a sessions folder the records say nothing")

        // Relaunched after a session quit mid-turn: its log still reads as
        // working, and nothing was ever seen running.
        let relaunched = AgentUsageStore()
        for name in ["gone", "alive"] {
            relaunched.apply([.turnBegan(start)], file: "/p/\(name).jsonl", provider: .claude, tracksTurns: true, modified: start)
        }
        relaunched.closeEndedTurns(AgentSessionRegistry(running: ["alive"], ended: [], complete: true), atLaunch: true)
        suite.expect(relaunched.live.count == 2, "at launch, a Claude Code that keeps no records leaves turns to the quiet wait")
        relaunched.closeEndedTurns(AgentSessionRegistry(running: ["alive"], ended: [], complete: false, listed: true), atLaunch: true)
        suite.expect(relaunched.live.count == 2, "at launch, an incomplete read ends nothing")
        relaunched.closeEndedTurns(AgentSessionRegistry(running: ["alive"], ended: [], complete: true, listed: true))
        suite.expect(relaunched.live.count == 2, "after launch, a record never seen running ends nothing")
        let ended = relaunched.closeEndedTurns(AgentSessionRegistry(running: ["alive"], ended: [], complete: true, listed: true),
                                               atLaunch: true)
        suite.expect(ended && relaunched.live.map(\.id) == ["/p/alive.jsonl"],
                     "at launch, a turn left open by a session that quit ends at once")
    }

    private static func reading(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-agent-logs-\(UUID().uuidString)")
        let file = folder.appending(path: "session.jsonl")
        defer { try? FileManager.default.removeItem(at: folder) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: Data("{\"a\":1}\n{\"b\":".utf8))
        let cursor = AgentLogCursor(path: file.path, provider: .claude)
        var lines: [String] = []
        AgentLogReader.readAppended(cursor) { lines.append(String(decoding: $0, as: UTF8.self)) }
        suite.expect(lines == ["{\"a\":1}"], "a line being written waits for its end")
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data("2}\n".utf8))
            try? handle.close()
        }
        lines.removeAll()
        AgentLogReader.readAppended(cursor) { lines.append(String(decoding: $0, as: UTF8.self)) }
        suite.expect(lines == ["{\"b\":2}"], "only what was appended is read again")
        FileManager.default.createFile(atPath: file.path, contents: Data("{\"c\":3}\n".utf8))
        lines.removeAll()
        AgentLogReader.readAppended(cursor) { lines.append(String(decoding: $0, as: UTF8.self)) }
        suite.expect(lines == ["{\"c\":3}"], "a rewritten file is read from its start")
        suite.expect(!AgentLogCursor(path: "/x/s1/subagents/agent-1.jsonl", provider: .claude).tracksTurns
                        && AgentLogCursor(path: "/x/s1.jsonl", provider: .claude).tracksTurns
                        && !AgentLogCursor(path: "/x/rollout-2026-09-21T08-17-14-a_b.jsonl", provider: .codex).tracksTurns,
                     "subagents and side threads never own a turn")
        let root = AgentLogRoot.canonical(folder)
        let found = AgentLogReader.discover([AgentLogRoot(provider: .codex, url: root)], since: .distantPast)
        suite.expect(found.map(\.path) == [root.appending(path: "session.jsonl").path] && found.first?.provider == .codex,
                     "log files are found under a root")
        suite.expect(root.path.hasPrefix("/private/") && AgentLogRoot.canonical(folder.appending(path: "missing")).path
                        == folder.appending(path: "missing").path,
                     "roots are watched by the real path file events report, and a missing one keeps its name")
        let subagents = folder.appending(path: "session/subagents")
        try? FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        let helperLog = subagents.appending(path: "agent-1.jsonl")
        FileManager.default.createFile(atPath: helperLog.path, contents: Data("{}\n".utf8))
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)],
                                               ofItemAtPath: helperLog.path)
        let sessionPath = root.appending(path: "session.jsonl").path
        let ordered = AgentLogReader.discover([AgentLogRoot(provider: .claude, url: root)], since: .distantPast)
        suite.expect(ordered.map(\.path) == [sessionPath, root.appending(path: "session/subagents/agent-1.jsonl").path]
                        && AgentLogCursor(path: ordered.last?.path ?? "", provider: .claude).parent == sessionPath,
                     "a subagent is read after the session it works for, even when it finished first")

        let large = folder.appending(path: "large.jsonl")
        for count in [AgentLogReader.maximumLine, AgentLogReader.maximumLine + 1,
                      AgentLogReader.maximumLine + AgentLogReader.chunkSize + 1] {
            autoreleasepool {
                var data = Data(repeating: 0x78, count: count)
                data.append(contentsOf: "\nok\n".utf8)
                try? data.write(to: large)
                let cursor = AgentLogCursor(path: large.path, provider: .claude)
                var sizes: [Int] = []
                AgentLogReader.readAppended(cursor) { sizes.append($0.count) }
                suite.expect(sizes == (count <= AgentLogReader.maximumLine ? [count, 2] : [2]),
                             "log line limit applies across chunk boundaries, including a newline in the next chunk (\(count) bytes)")
                suite.expect(cursor.pending.isEmpty && !cursor.discarding,
                             "an oversized log line never consumes the valid line after it")
            }
        }

        // An invalid line may keep growing over several file-change events.
        // None of its later fragments may become a pending valid line.
        try? Data(repeating: 0x78, count: AgentLogReader.maximumLine + 1).write(to: large)
        let discarded = AgentLogCursor(path: large.path, provider: .claude)
        var recovered: [String] = []
        func readDiscarded() {
            AgentLogReader.readAppended(discarded) { recovered.append(String(decoding: $0, as: UTF8.self)) }
        }
        func appendDiscarded(_ data: Data) {
            guard let handle = try? FileHandle(forWritingTo: large) else {
                suite.expect(false, "the oversized-line fixture opens for appending")
                return
            }
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
            readDiscarded()
        }
        readDiscarded()
        suite.expect(discarded.discarding && discarded.pending.isEmpty && recovered.isEmpty,
                     "an unterminated oversized line enters discard mode")
        for _ in 0..<3 {
            appendDiscarded(Data(repeating: 0x78, count: AgentLogReader.chunkSize))
            suite.expect(discarded.discarding && discarded.pending.isEmpty && recovered.isEmpty,
                         "later fragments of a discarded line are never retained between reads")
        }
        appendDiscarded(Data("\nok\npar".utf8))
        suite.expect(!discarded.discarding && discarded.pending == Data("par".utf8) && recovered == ["ok"],
                     "the discarded line's end preserves the next complete line and its valid partial successor")
        appendDiscarded(Data("tial\n".utf8))
        suite.expect(discarded.pending.isEmpty && recovered == ["ok", "partial"],
                     "a valid partial line after discard mode completes normally")

        var chunked = Data("head\n".utf8)
        chunked.append(Data(repeating: 0x78, count: AgentLogReader.chunkSize))
        chunked.append(contentsOf: "\ntail\n".utf8)
        try? chunked.write(to: large)
        let cancelled = AgentLogCursor(path: large.path, provider: .claude)
        var sizes: [Int] = []
        AgentLogReader.readAppended(cancelled, shouldContinue: { false }) { sizes.append($0.count) }
        suite.expect(cancelled.offset == 0 && sizes.isEmpty,
                     "a cancelled log read consumes no file data")
        AgentLogReader.readAppended(cancelled, shouldContinue: { sizes.isEmpty }) { sizes.append($0.count) }
        suite.expect(cancelled.offset == UInt64(AgentLogReader.chunkSize)
                        && sizes == [4] && cancelled.pending.count == AgentLogReader.chunkSize - 5,
                     "disabling agents during a large read stops at the next chunk boundary")
        sizes.removeAll()
        AgentLogReader.readAppended(cancelled) { sizes.append($0.count) }
        suite.expect(sizes == [AgentLogReader.chunkSize, 4] && cancelled.offset == UInt64(chunked.count),
                     "an interrupted log resumes its partial line without losing or replaying completed lines")
    }

    private static func history(_ samples: [(String, String?, [String: Any])], version: Int = 2) -> Data {
        let entries: [[String: Any]] = samples.map { time, organization, used in
            var entry: [String: Any] = ["t": (AgentTimestamp.parse(time)?.timeIntervalSince1970 ?? 0) * 1_000]
            entry["org"] = organization ?? NSNull()
            if version == 1 { entry.merge(used) { $1 } } else { entry["u"] = used }
            return entry
        }
        return (try? JSONSerialization.data(withJSONObject: ["version": version, "samples": entries])) ?? Data()
    }

    private static func claudeApp(_ suite: TestSuite) {
        let at = { (time: String) in AgentTimestamp.parse(time)! }
        let file = history([("2026-09-23T14:20:00Z", "o", ["fh": 6, "sd": 42, "cw": 3]),
                            ("2026-09-23T13:50:00Z", "o", ["fh": 0, "sd": 40]),
                            ("2026-09-23T14:05:00Z", "o", ["fh": 3, "sd": 41, "so": true])])
        let samples = AgentClaudeAppUsage.samples(from: file) ?? []
        suite.expect(samples.map(\.date) == [at("2026-09-23T13:50:00Z"), at("2026-09-23T14:05:00Z"), at("2026-09-23T14:20:00Z")]
                        && samples.last?.used == ["fh": 6, "sd": 42] && samples[1].used == ["fh": 3, "sd": 41],
                     "readings come oldest first, with the known windows and nothing that is not a number")
        let now = at("2026-09-23T14:30:00Z")
        let reading = AgentClaudeAppUsage.limits(from: samples, now: now)
        suite.expect(reading?.source == .claudeApp && reading?.observedAt == at("2026-09-23T14:20:00Z")
                        && reading?.windows.map(\.kind) == [.session, .weekly]
                        && reading?.windows.map(\.usedPercent) == [6, 42] && reading?.windows.last?.resetsAt == nil,
                     "the latest reading gives the session and the week, and a week with no renewal seen has no date")
        suite.expect(reading?.windows.first?.resetsAt == at("2026-09-23T19:05:00Z"),
                     "a session renews five hours after its first reading above zero")
        suite.expect(AgentClaudeAppUsage.limits(from: samples, now: now, sessionStart: at("2026-09-23T13:55:00Z"))?
                        .windows.first?.resetsAt == at("2026-09-23T18:55:00Z")
                        && AgentClaudeAppUsage.limits(from: samples, now: now, sessionStart: at("2026-09-23T13:40:00Z"))?
                        .windows.first?.resetsAt == at("2026-09-23T19:05:00Z"),
                     "Claude Code's first request places the session only inside the gap the readings leave")
        let requests = [record(.claude, at("2026-09-23T13:55:00Z"), cost: 1), record(.claude, at("2026-09-23T18:58:00Z"), cost: 1)]
        let placed = AgentClaudeAppUsage.sessionStart(requests, samples: samples)
        let ended = at("2026-09-23T19:00:00Z")
        suite.expect(placed == at("2026-09-23T13:55:00Z")
                        && AgentClaudeAppUsage.limits(from: samples, now: at("2026-09-23T18:50:00Z"), sessionStart: placed)?
                        .windows.first?.resetsAt == at("2026-09-23T18:55:00Z")
                        && AgentClaudeAppUsage.limits(from: samples, now: ended, sessionStart: placed)?.windows.map(\.kind) == [.weekly],
                     "the session the newest reading saw keeps its renewal after it ends, even once a new one began")
        let renewed = AgentClaudeAppUsage.samples(from: history([
            ("2026-09-16T19:50:00Z", "o", ["fh": 10, "sd": 95]), ("2026-09-16T20:05:00Z", "o", ["fh": 0, "sd": 1]),
            ("2026-09-23T14:00:00Z", "x", ["fh": 90, "sd": 2]), ("2026-09-23T14:10:00Z", "x", ["fh": 0, "sd": 99]),
            ("2026-09-23T14:20:00Z", "o", ["fh": 6, "sd": 42])])) ?? []
        suite.expect(AgentClaudeAppUsage.limits(from: renewed, now: now)?.windows.last?.resetsAt == at("2026-09-23T20:00:00Z"),
                     "a week renews seven days after the last drop, on the hour, counting only the same account")
        let later = AgentClaudeAppUsage.limits(from: samples, now: at("2026-09-23T20:30:00Z"))
        suite.expect(later?.windows.map(\.kind) == [.weekly] && AgentClaudeAppUsage.limits(from: samples, now: at("2026-10-01T15:00:00Z")) == nil,
                     "an old reading drops the session it can no longer speak for, and a week-old file is ignored")
        let afterRenewal = AgentClaudeAppUsage.samples(from: history([
            ("2026-09-16T19:50:00Z", "o", ["fh": 10, "sd": 95]), ("2026-09-16T20:05:00Z", "o", ["fh": 0, "sd": 1]),
            ("2026-09-23T21:00:00Z", "o", ["fh": 2, "sd": 3])])) ?? []
        suite.expect(AgentClaudeAppUsage.limits(from: samples, now: at("2026-09-24T15:00:00Z")) == nil
                        && AgentClaudeAppUsage.limits(from: afterRenewal, now: at("2026-09-25T15:00:00Z"))?.windows
                        .map(\.resetsAt) == [at("2026-09-30T20:00:00Z")],
                     "a day-old week is kept only when its next renewal is known")
        suite.expect(AgentClaudeAppUsage.limits(from: renewed, now: at("2026-09-24T15:00:00Z")) == nil,
                     "a week that renewed after the reading is not shown with its old use")
        let accounts = AgentClaudeAppUsage.samples(from: history([
            ("2026-09-23T14:10:00Z", "o", ["fh": 30, "sd": 50]), ("2026-09-23T14:20:00Z", "x", ["fh": 90, "sd": 95])])) ?? []
        suite.expect(AgentClaudeAppUsage.limits(from: accounts, now: now, organization: "o")?.windows.map(\.usedPercent) == [30, 50]
                        && AgentClaudeAppUsage.limits(from: accounts, now: now, organization: "z") == nil
                        && AgentClaudeAppUsage.limits(from: accounts, now: now)?.windows.map(\.usedPercent) == [90, 95],
                     "limits follow the account Claude Code signs in to, not whichever one the app shows")
        let continuous = AgentClaudeAppUsage.samples(from: history([
            ("2026-09-23T10:05:00Z", "o", ["fh": 3, "sd": 10]), ("2026-09-23T14:55:00Z", "o", ["fh": 85, "sd": 20]),
            ("2026-09-23T15:05:00Z", "o", ["fh": 4, "sd": 21]), ("2026-09-23T15:20:00Z", "o", ["fh": 12, "sd": 22])])) ?? []
        let working = AgentClaudeAppUsage.limits(from: continuous, now: at("2026-09-23T15:25:00Z"))
        suite.expect(working?.windows.first?.kind == .session
                        && working?.windows.first?.resetsAt == at("2026-09-23T20:05:00Z"),
                     "a session that renews during continuous use starts again at the drop")
        let first = AgentClaudeAppUsage.samples(from: history([("2026-09-23T14:20:00Z", nil, ["fh": 5, "sd": 20])], version: 1))
        suite.expect(first?.first?.used == ["fh": 5, "sd": 20] && AgentClaudeAppUsage.samples(from: history([], version: 3)) == nil
                        && AgentClaudeAppUsage.samples(from: Data("[]".utf8)) == nil,
                     "both versions of the file are read, and an unknown one is left alone")
        let home = FileManager.default.temporaryDirectory.appending(path: "vorss-claude-app-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let url = AgentClaudeAppUsage.historyURL(home: home)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? file.write(to: url)
        suite.expect(AgentClaudeAppUsage.lastCheck(home: home) == at("2026-09-23T14:20:00Z")
                        && AgentClaudeAppUsage.lastCheck(home: home.appending(path: "none")) == nil,
                     "the settings read when the Claude app last checked, straight from its file")
    }

    // MARK: Preferences and layout

    private static func preferences(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-agents"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for feature in AppFeature.allCases { defaults.set(true, forKey: feature.availabilityKey) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        suite.expect(NotchAgentSupport.isEnabled(in: defaults), "installed AI agents start enabled in the island")
        defaults.set(false, forKey: DefaultsKey.notchAgentsEnabled)
        suite.expect(!NotchSupport.modules(in: defaults).contains(.agents) && !NotchAgentSupport.isEnabled(in: defaults)
                        && !NotchSupport.routes(.agents, in: defaults),
                     "turning AI agents off removes their page and notices")
        defaults.set(true, forKey: DefaultsKey.notchAgentsEnabled)
        suite.expect(NotchSupport.modules(in: defaults).last == .agents && NotchAgentSupport.isEnabled(in: defaults)
                        && NotchSupport.routes(.agents, in: defaults) && NotchAgentSupport.showsLiveActivity(in: defaults),
                     "choosing it adds the page, its notices and its live strip")
        defaults.set(false, forKey: AppFeature.notchAgents.availabilityKey)
        suite.expect(!NotchAgentSupport.isEnabled(in: defaults) && !NotchSupport.modules(in: defaults).contains(.agents),
                     "uninstalling the feature removes the page")
        defaults.set(true, forKey: AppFeature.notchAgents.availabilityKey)
        defaults.set(NotchIdleContent.agents.rawValue, forKey: DefaultsKey.notchIdleContent)
        suite.expect(NotchSupport.idleContent(in: defaults) == .agents, "the resting island can show AI limits")
        defaults.set(false, forKey: DefaultsKey.notchAgentsEnabled)
        suite.expect(NotchSupport.idleContent(in: defaults) == .none, "resting AI limits leave with the page")
        suite.expect(NotchSupport.compactActivity(timer: false, downloads: true, agents: true, music: true) == .downloads
                        && NotchSupport.compactActivity(timer: false, downloads: false, agents: true, music: true) == .agents
                        && NotchCompactActivity.agents.module == .agents,
                     "a working agent outranks music but not a download")

        defaults.set("trend,unknown,trend,spend", forKey: DefaultsKey.notchAgentsCardOrder)
        defaults.set("activity,projects", forKey: DefaultsKey.notchAgentsHiddenCards)
        suite.expect(NotchAgentSupport.cards(in: defaults) == [.trend, .spend, .limits, .live, .resume, .models, .resets],
                     "the saved order ignores unknown and repeated cards and appends new ones")
        defaults.set(false, forKey: DefaultsKey.notchAgentsCodex)
        suite.expect(NotchAgentSupport.providers(in: defaults) == [.claude, .opencode], "an agent can be left out")
        defaults.set(false, forKey: DefaultsKey.notchAgentsOpenCode)
        suite.expect(NotchAgentSupport.providers(in: defaults) == [.claude], "multiple agents can be left out")
        defaults.set("unknown", forKey: DefaultsKey.notchAgentsLimitFocus)
        suite.expect(NotchAgentSupport.limitFocus(in: defaults) == .mostUsed, "an unknown limit choice shows the most used")
        defaults.set(NotchAgentLimitFocus.weekly.rawValue, forKey: DefaultsKey.notchAgentsLimitFocus)
        suite.expect(NotchAgentSupport.limitFocus(in: defaults) == .weekly, "the chosen limit is kept")
        defaults.set(false, forKey: DefaultsKey.notchAgentsFinishAlert)
        defaults.set(95.0, forKey: DefaultsKey.notchAgentsLimitThreshold)
        defaults.set(-4.0, forKey: DefaultsKey.notchAgentsDailyBudget)
        suite.expect(NotchAgentSupport.finishMinimum(in: defaults) == nil && NotchAgentSupport.limitThreshold(in: defaults) == 95
                        && NotchAgentSupport.dailyBudget(in: defaults) == nil,
                     "alerts follow their switches and a budget must be positive")

        let keys = [DefaultsKey.notchAgentsEnabled, DefaultsKey.notchAgentsClaude, DefaultsKey.notchAgentsCodex,
                    DefaultsKey.notchAgentsOpenCode,
                    DefaultsKey.notchAgentsCardOrder, DefaultsKey.notchAgentsHiddenCards, DefaultsKey.notchAgentsPeriod,
                    DefaultsKey.notchAgentsLimitDisplay, DefaultsKey.notchAgentsLimitFocus, DefaultsKey.notchAgentsLiveActivity, DefaultsKey.notchAgentsReadout,
                    DefaultsKey.notchAgentsFinishAlert, DefaultsKey.notchAgentsFinishMinimum, DefaultsKey.notchAgentsLimitAlert,
                    DefaultsKey.notchAgentsLimitThreshold, DefaultsKey.notchAgentsDailyBudget, DefaultsKey.notchAgentsPriceUpdates]
        suite.expect(keys.allSatisfy { Defaults.registeredDefaults[$0] != nil } && SettingsBackupSupport.exportKeys().isSuperset(of: keys)
                        && Defaults.registeredDefaults[DefaultsKey.notchAgentsEnabled] as? Bool == true
                        && Defaults.registeredDefaults[DefaultsKey.notchAgentsPriceUpdates] as? Bool == true,
                     "every AI preference is registered and travels in backups, with the page on and prices kept current")
        suite.expect(NotchAgentSupport.updatesPrices(in: defaults), "prices stay current unless turned off")
        defaults.set(false, forKey: DefaultsKey.notchAgentsPriceUpdates)
        suite.expect(!NotchAgentSupport.updatesPrices(in: defaults), "turning price updates off stops the download")
        suite.expect(AppFeature.notchAgents.group == .dynamicIsland && AppFeature.notchAgents.permissions == [.automationTerminal]
                        && AppFeature.availabilityDefaults[AppFeature.notchAgents.availabilityKey] as? Bool == true,
                     "the AI page is a Dynamic Island extension that only asks to script Terminal")

        let limits = NotchAgentTile(card: .limits, provider: .claude)
        let codex = NotchAgentTile(card: .limits, provider: .codex)
        let spend = NotchAgentTile(card: .spend, provider: nil)
        let trend = NotchAgentTile(card: .trend, provider: nil)
        suite.expect(NotchAgentSupport.tiles(cards: [.limits, .trend], providers: [.claude, .codex]) == [limits, codex, trend],
                     "each agent gets its own limits card")
        let resets = NotchAgentTile(card: .resets, provider: .codex)
        suite.expect(NotchAgentSupport.tiles(cards: [.resets, .spend], providers: [.claude, .codex]) == [resets, spend]
                        && NotchAgentSupport.tiles(cards: [.resets, .spend], providers: [.claude]) == [spend],
                     "the resets card belongs to Codex and leaves with it")
        suite.expect(NotchAgentSupport.rows([limits, codex, spend, trend], width: 424) == [[limits, codex], [spend], [trend]]
                        && NotchAgentSupport.rows([limits, trend, codex], width: 424) == [[limits], [trend], [codex]],
                     "cards pair in reading order, and charts and lone cards take the row")
        suite.expect(NotchAgentSupport.rows([limits, codex], width: 330) == [[limits], [codex]],
                     "a narrow island stacks every card")
        suite.expect(NotchAgentSupport.contentHeight([[limits, codex], [trend]])
                        == NotchAgentSupport.cardHeight + NotchAgentSupport.spacing + NotchAgentSupport.chartHeight
                        && NotchAgentSupport.contentHeight([]) == 0,
                     "the page is as tall as its rows")
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                                     cameraWidth: 185, layout: .spacious, compactSideRoom: 200)
        suite.expect(geometry.expandedSize(module: .agents, agentsHeight: 96).height
                        == geometry.headerTopInset + geometry.headerChromeHeight + 96
                        && geometry.expandedSize(module: .agents, agentsHeight: 900).height
                        == geometry.headerTopInset + geometry.headerChromeHeight + geometry.contentBudget
                        && geometry.expandedSize(module: .agents, agentsHeight: 0).height
                        == geometry.headerTopInset + geometry.headerChromeHeight + NotchLayout.emptyHeight,
                     "a short set of cards leaves a short island and a long one scrolls inside the budget")
        let strip = geometry.compactAgentGeometry(wing: 72)
        suite.expect(!strip.compactActivityUsesFooter && strip.compactActivityWingWidth == 72,
                     "a working agent stays beside the camera")
    }

    private static func formatting(_ suite: TestSuite) {
        let english = Locale(identifier: "en_US")
        let portuguese = Locale(identifier: "pt_BR")
        suite.expect(AgentFormat.tokens(950, locale: english) == "950" && AgentFormat.tokens(4_280, locale: english) == "4.2K"
                        && AgentFormat.tokens(48_900, locale: english) == "48K"
                        && AgentFormat.tokens(1_234_567, locale: english) == "1.2M"
                        && AgentFormat.tokens(4_280, locale: portuguese) == "4,2K",
                     "token counts shorten without rounding up, with the region's decimal mark")
        suite.expect(AgentFormat.cost(12.4, locale: english) == "$12.40" && AgentFormat.cost(1234, locale: english) == "$1,234"
                        && AgentFormat.cost(12_345, locale: english) == "$12K" && AgentFormat.cost(0.42, locale: portuguese) == "$0,42",
                     "costs keep cents while they matter")
        suite.expect(AgentFormat.clock(42) == "0:42" && AgentFormat.clock(3725) == "1:02:05" && AgentFormat.clock(-5) == "0:00",
                     "elapsed time reads like a stopwatch")
        suite.expect(AgentFormat.day(Date(timeIntervalSince1970: 1_790_035_200), locale: english) == "Sep 22, 2026",
                     "the price list's day reads the same in every time zone")

        func openCodeCardCost(unpriced: Int, cost: Double) -> String {
            if unpriced > 0 {
                return cost > 0 ? "≥ " + AgentFormat.cost(cost, locale: english) : "—"
            }
            return AgentFormat.cost(cost, locale: english)
        }
        suite.expect(openCodeCardCost(unpriced: 0, cost: 12.5) == "$12.50"
                        && openCodeCardCost(unpriced: 1, cost: 12.5) == "≥ $12.50"
                        && openCodeCardCost(unpriced: 2, cost: 0) == "—"
                        && openCodeCardCost(unpriced: 0, cost: 0) == "$0.00",
                     "OpenCode limits card formats unpriced costs as lower bound or em dash")
    }
}

private func * (count: Int, tokens: AgentTokens) -> AgentTokens {
    AgentTokens(input: tokens.input * count, cacheWrite: tokens.cacheWrite * count, cacheRead: tokens.cacheRead * count,
                output: tokens.output * count, reasoning: tokens.reasoning * count)
}
