// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

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
        timestamps(suite)
        summary(suite)
        limits(suite)
        strip(suite)
        liveTurns(suite)
        reading(suite)
        claudeApp(suite)
        preferences(suite)
        formatting(suite)
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
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var state = AgentLogState()
        let store = AgentUsageStore()
        store.reportsTransitions = true
        func feed(_ data: Data) -> [AgentUsageEvent] {
            store.apply(AgentLogParser.parseClaude(data, state: &state, now: now), file: "main", provider: .claude,
                        tracksTurns: true, modified: now)
        }
        suite.expect(feed(claudeUser(meta: true)).isEmpty && store.live.isEmpty, "a meta line starts no turn")
        _ = feed(claudeUser(time: "2026-09-21T23:40:00.000Z"))
        suite.expect(store.live.count == 1 && store.live.first?.started == AgentTimestamp.parse("2026-09-21T23:40:00.000Z"),
                     "a prompt starts a turn at its own time")
        _ = feed(claudeAssistant(stop: "tool_use"))
        suite.expect(AgentLogParser.parseClaude(claudeUser(toolResult: true), state: &state, now: now) == [.turnActive(nil)],
                     "a tool result inside a turn is not decoded")
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
        suite.expect(feed(line(#"{"type":"user","message":{"content":"[Request interrupted by user]"}}"#)).isEmpty
                        && store.live.isEmpty, "an interrupted turn ends without a notice")
        _ = feed(claudeUser(#"<command-name>/model</command-name>"#))
        _ = feed(line(#"{"type":"user","message":{"content":"<local-command-stdout>Set model</local-command-stdout>"}}"#))
        suite.expect(store.live.isEmpty, "a local command never leaves a turn working")
        let quiet = AgentUsageStore()
        var quietState = AgentLogState()
        let replay = [claudeUser(), claudeAssistant(stop: "end_turn")].flatMap {
            quiet.apply(AgentLogParser.parseClaude($0, state: &quietState, now: now), file: "main", provider: .claude,
                        tracksTurns: true, modified: now)
        }
        suite.expect(replay.isEmpty, "history read at start is not replayed as news")
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
                                  provider: .codex, tracksTurns: true, modified: now)
        }
        suite.expect(store.records.count == 1, "a response with its own record is not counted again from the totals")
        let usage = store.records.first
        suite.expect(usage?.tokens == AgentTokens(input: 11_943, cacheWrite: 0, cacheRead: 20_224, output: 156, reasoning: 7)
                        && usage?.model == "gpt-6-astra" && usage?.project == "web" && usage?.session == "s9",
                     "cached input is taken out of the input count and the turn's model is kept")
        suite.expectClose(usage?.cost ?? -1, (11_943 * 10 + 20_224 * 1 + 156 * 50) / 1_000_000,
                          "a response is priced at its model's list price")
        let window = store.limits[.codex]?.windows.first
        suite.expect(window?.kind == .weekly && window?.usedPercent == 72 && window?.minutes == 10_080
                        && window?.resetsAt == Date(timeIntervalSince1970: 1_790_390_402)
                        && store.codexPlan == "pro",
                     "the limits Codex logs arrive with their length, renewal and plan")
        suite.expect(events == [.finished(provider: .codex, duration: 458.431, cost: usage?.cost ?? 0,
                                          tokens: usage?.tokens.total ?? 0, project: "web")],
                     "a completed task reports the duration Codex measured")

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
            record(.claude, AgentTimestamp.parse("2026-09-22T15:05:00Z")!, cost: 1),
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
        suite.expect(snapshot.claudeBlock == AgentBlock(start: AgentTimestamp.parse("2026-09-22T15:00:00Z")!,
                                                        end: AgentTimestamp.parse("2026-09-22T20:00:00Z")!,
                                                        totals: { var totals = AgentTotals(); totals.add(records[2]); return totals }()),
                     "Claude's window starts on the hour of the first request after the last one ended")
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
        let late = AgentUsageSummary.currentBlock(Array(records.prefix(3)), now: AgentTimestamp.parse("2026-09-22T20:00:00Z")!,
                                                  calendar: calendar)
        suite.expect(late == nil, "a window that has ended is no longer current")
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
        let short = snapshot([session(.claude, startedAgo: 754)])
        let long = snapshot([session(.claude, startedAgo: 3723), session(.codex, startedAgo: 60)])
        suite.expect(NotchAgentSupport.stripReading(short, readout: .elapsed, display: .remaining, now: now) == "12:34"
                        && NotchAgentSupport.stripReading(long, readout: .elapsed, display: .remaining, now: now) == "1:02:03",
                     "the strip counts from the earliest turn still working")
        suite.expect(NotchAgentSupport.stripReading(short, readout: .cost, display: .remaining, now: now) == AgentFormat.cost(4.56)
                        && NotchAgentSupport.stripReading(long, readout: .tokens, display: .remaining, now: now)
                            == AgentFormat.tokens(600),
                     "cost and written tokens add up every turn that is working")
        let window = AgentLimitWindow(id: "w", kind: .weekly, minutes: 10_080, scope: nil, usedPercent: 79,
                                      resetsAt: now.addingTimeInterval(86_400))
        let limited = snapshot([session(.claude, startedAgo: 754)],
                               limits: [.claude: AgentLimits(provider: .claude, windows: [window], observedAt: now, source: .claudeApp)])
        suite.expect(NotchAgentSupport.stripReading(limited, readout: .limit, display: .remaining, now: now) == AgentFormat.percent(0.21)
                        && NotchAgentSupport.stripReading(limited, readout: .limit, display: .used, now: now) == AgentFormat.percent(0.79)
                        && NotchAgentSupport.stripReading(short, readout: .limit, display: .remaining, now: now) == "12:34",
                     "a limit reads as left or used, and falls back to the time while none is known")
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
        suite.expect(reading?.windows.first?.resetsAt == at("2026-09-23T19:00:00Z"),
                     "a session renews five hours after the hour its first reading above zero fell in")
        suite.expect(AgentClaudeAppUsage.limits(from: samples, now: now, sessionStart: at("2026-09-23T13:55:00Z"))?
                        .windows.first?.resetsAt == at("2026-09-23T18:00:00Z")
                        && AgentClaudeAppUsage.limits(from: samples, now: now, sessionStart: at("2026-09-23T13:40:00Z"))?
                        .windows.first?.resetsAt == at("2026-09-23T19:00:00Z"),
                     "Claude Code's first request places the session only inside the gap the readings leave")
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
        suite.expect(!NotchSupport.modules(in: defaults).contains(.agents) && !NotchAgentSupport.isEnabled(in: defaults)
                        && !NotchSupport.routes(.agents, in: defaults),
                     "the AI page stays off until it is chosen")
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
        suite.expect(NotchAgentSupport.cards(in: defaults) == [.trend, .spend, .limits, .live, .models],
                     "the saved order ignores unknown and repeated cards and appends new ones")
        defaults.set(false, forKey: DefaultsKey.notchAgentsCodex)
        suite.expect(NotchAgentSupport.providers(in: defaults) == [.claude], "an agent can be left out")
        defaults.set(false, forKey: DefaultsKey.notchAgentsFinishAlert)
        defaults.set(95.0, forKey: DefaultsKey.notchAgentsLimitThreshold)
        defaults.set(-4.0, forKey: DefaultsKey.notchAgentsDailyBudget)
        suite.expect(NotchAgentSupport.finishMinimum(in: defaults) == nil && NotchAgentSupport.limitThreshold(in: defaults) == 95
                        && NotchAgentSupport.dailyBudget(in: defaults) == nil,
                     "alerts follow their switches and a budget must be positive")

        let keys = [DefaultsKey.notchAgentsEnabled, DefaultsKey.notchAgentsClaude, DefaultsKey.notchAgentsCodex,
                    DefaultsKey.notchAgentsCardOrder, DefaultsKey.notchAgentsHiddenCards, DefaultsKey.notchAgentsPeriod,
                    DefaultsKey.notchAgentsLimitDisplay, DefaultsKey.notchAgentsLiveActivity, DefaultsKey.notchAgentsReadout,
                    DefaultsKey.notchAgentsFinishAlert, DefaultsKey.notchAgentsFinishMinimum, DefaultsKey.notchAgentsLimitAlert,
                    DefaultsKey.notchAgentsLimitThreshold, DefaultsKey.notchAgentsDailyBudget, DefaultsKey.notchAgentsPriceUpdates]
        suite.expect(keys.allSatisfy { Defaults.registeredDefaults[$0] != nil } && SettingsBackupSupport.exportKeys().isSuperset(of: keys)
                        && Defaults.registeredDefaults[DefaultsKey.notchAgentsEnabled] as? Bool == false
                        && Defaults.registeredDefaults[DefaultsKey.notchAgentsPriceUpdates] as? Bool == true,
                     "every AI preference is registered and travels in backups, with the page off and prices kept current")
        suite.expect(NotchAgentSupport.updatesPrices(in: defaults), "prices stay current unless turned off")
        defaults.set(false, forKey: DefaultsKey.notchAgentsPriceUpdates)
        suite.expect(!NotchAgentSupport.updatesPrices(in: defaults), "turning price updates off stops the download")
        suite.expect(AppFeature.notchAgents.group == .dynamicIsland && AppFeature.notchAgents.permissions.isEmpty
                        && AppFeature.availabilityDefaults[AppFeature.notchAgents.availabilityKey] as? Bool == true,
                     "the AI page is a Dynamic Island extension that needs no system permission")

        let limits = NotchAgentTile(card: .limits, provider: .claude)
        let codex = NotchAgentTile(card: .limits, provider: .codex)
        let spend = NotchAgentTile(card: .spend, provider: nil)
        let trend = NotchAgentTile(card: .trend, provider: nil)
        suite.expect(NotchAgentSupport.tiles(cards: [.limits, .trend], providers: [.claude, .codex]) == [limits, codex, trend],
                     "each agent gets its own limits card")
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
    }
}

private func * (count: Int, tokens: AgentTokens) -> AgentTokens {
    AgentTokens(input: tokens.input * count, cacheWrite: tokens.cacheWrite * count, cacheRead: tokens.cacheRead * count,
                output: tokens.output * count, reasoning: tokens.reasoning * count)
}
