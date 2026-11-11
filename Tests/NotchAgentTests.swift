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
        offlineTurns(suite)
        HarnessReaderContractTests.run(suite)
        AgentAttentionTests.run(suite)
        timestamps(suite)
        summary(suite)
        AgentUsageSummaryCacheTests.run(suite)
        limits(suite)
        strip(suite)
        NotchAgentLimitReadingTests.run(suite)
        liveTurns(suite)
        reading(suite)
        AgentUsageReadTests.run(suite)
        AgentSyncedLogTests.run(suite)
        AgentUsagePollingTests.run(suite)
        AgentUsageArchiveTests.run(suite)
        AgentUsageArchiveSettleTests.run(suite)
        AgentUsageArchiveSaveTests.run(suite)
        claudeApp(suite)
        AgentClaudeServerTests.run(suite)
        AgentClaudeBillingTests.run(suite)
        AgentSessionPlaceTests.run(suite)
        ClaudeSeatTests.run(suite)
        AppSoundTests.run(suite)
        NotchLimitVisibilityTests.run(suite)
        preferences(suite)
        restingMeters(suite)
        activity(suite)
        limitUse(suite)
        agentDefaults(suite)
        formatting(suite)
        AgentUsageEventDeliveryTests.run(suite)
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
        // Sonnet 5.5 cache reads cost $0.10/MTok: https://platform.claude.com/docs/en/models/sonnet-5-5/overview
        let sonnet = AgentPricing.cost(AgentBillable(tokens: AgentTokens(input: 1000, cacheRead: 100_000, output: 2000)),
                                      model: "claude-sonnet-5-5")
        suite.expectClose(sonnet.cost ?? -1, 0.032, "Sonnet 5.5 bills cache reads at five percent of input")
        suite.expectClose(sonnet.savings, 0.19, "Sonnet 5.5 cache savings use its reduced read rate")
        // Haiku 5.5 counts every prompt token and charges 5x past 100K: https://platform.claude.com/docs/en/about-claude/pricing
        var haiku = AgentBillable(tokens: AgentTokens(input: 1000, cacheWrite: 4000, cacheRead: 95_000, output: 2000))
        haiku.longCacheWrite = 3000
        suite.expectClose(AgentPricing.cost(haiku, model: "anthropic.claude-haiku-5-5").cost ?? -1,
                          0.002775, "Haiku 5.5 keeps base rates at exactly 100K prompt tokens", tol: 0.00000001)
        haiku.tokens.input += 1
        suite.expectClose(AgentPricing.cost(haiku, model: "claude-haiku-5-5").cost ?? -1,
                          0.0138755, "Haiku 5.5 charges five times every token rate above 100K", tol: 0.00000001)
        haiku.isAggregate = true
        suite.expectClose(AgentPricing.cost(haiku, model: "claude-haiku-5-5").cost ?? -1,
                          0.0027751, "Haiku 5.5 session totals do not imply a long individual prompt", tol: 0.00000001)
        suite.expect(AgentPricing.price(for: "claude-opus-5-5")?.input == 4
                        && AgentPricing.price(for: "claude-opus-5.5")?.input == 4
                        && AgentPricing.price(for: "claude-opus-5")?.input == 5,
                     "point releases, including a router's dotted spelling, keep their own price")
        suite.expect(AgentPricing.price(for: "claude-opus-4-1-20250805")?.input == 15
                        && AgentPricing.price(for: "claude-opus-4-5-20251101")?.input == 5
                        && AgentPricing.price(for: "us.anthropic.claude-sonnet-4-5-20250929-v1:0")?.input == 3
                        && AgentPricing.price(for: "claude-haiku-4-5@20251001")?.output == 5
                        && AgentPricing.price(for: "claude-sonnet-4-5[1m]")?.input == 3,
                     "snapshot dates, cloud prefixes and context tags keep the family's price")
        suite.expect(AgentPricing.price(for: "claude-opus-5-5-mini") == nil && AgentPricing.price(for: "claude-reserve") == nil
                        && AgentPricing.price(for: "gpt-6-astra") == nil
                        && AgentPricing.cost(AgentBillable(tokens: AgentTokens(input: 10)), model: "gpt-reserve").cost == nil,
                     "an unlisted model, a sibling or another maker's model has no price rather than a borrowed one")
        // Sonnet 5.5 now has published prices: https://platform.claude.com/docs/en/models/sonnet-5-5/overview
        suite.expect(AgentPricing.price(for: "claude-opus-5-6") == nil && AgentPricing.price(for: "claude-sonnet-5-6") == nil
                        && AgentPricing.price(for: "claude-opus-6") == nil,
                     "a version the list does not name yet has no price rather than its predecessor's")
        suite.expect(AgentPricing.price(for: "claude-opus-5-20260101")?.input == 5
                        && AgentPricing.price(for: "claude-3-5-sonnet-latest")?.input == 3,
                     "a dated snapshot or an alias keeps its model's price")
        suite.expect(AgentPricing.price(for: "claude-mythos-preview")?.output == 125,
                     "specialized models priced apart get their own price")
        // Fable 5.2 and Mythos 5.2: https://platform.claude.com/docs/en/about-claude/pricing
        let fable = AgentPricing.price(for: "claude-fable-5-2")
        suite.expect(fable == AgentPrice(input: 8, output: 40, cacheRead: 0.2, cacheWrite: 10, cacheWriteLong: 16,
                                         fastMultiplier: 2)
                        && AgentPricing.price(for: "claude-mythos-5-2") == fable,
                     "Fable 5.2 and Mythos 5.2 carry their published prices, not 5.1's")
        suite.expect(AgentPricing.price(for: "claude-fable-5-2-20261101") == fable
                        && AgentPricing.price(for: "claude-fable-5-2[1m]") == fable
                        && AgentPricing.price(for: "claude-mythos-5-2-20261101[1m]") == fable
                        && AgentPricing.price(for: "claude-fable-5.2") == fable
                        && AgentPricing.price(for: "us.anthropic.claude-fable-5-2-20261101-v1:0") == fable,
                     "a dated, tagged or prefixed Fable 5.2 id is the same model")
        suite.expect(AgentPricing.price(for: "claude-fable-5-1")?.input == 10 && AgentPricing.price(for: "claude-fable-5")?.cacheRead == 1
                        && AgentPricing.price(for: "claude-fable-5-3") == nil,
                     "5.2 leaves 5.1 and 5 their own prices, and a later version waits for the list")
        suite.expect(AgentPricing.displayName("claude-fable-5-2") == "Fable 5.2"
                        && AgentPricing.displayName("claude-mythos-5-2") == "Mythos 5.2"
                        && AgentPricing.displayName("claude-fable-5-2-20261101") == "Fable 5.2"
                        && AgentPricing.displayName("claude-fable-5-2[1m]") == "Fable 5.2"
                        && AgentPricing.displayName("claude-fable-5-3") == "Fable 5.3",
                     "Fable 5.2 and Mythos 5.2 read by name, and so does a version no list knows")
        // A model the list does not know keeps a row and its tokens.
        func share(_ name: String, cost: Double, tokens: Int, unpriced: Int = 0) -> AgentShare {
            AgentShare(id: "claude:" + name, name: name, provider: .claude,
                       totals: AgentTotals(tokens: AgentTokens(input: tokens), cost: cost, requests: 1, unpriced: unpriced))
        }
        let known = [share("Opus 5.5", cost: 900, tokens: 9_000), share("Sonnet 5.5", cost: 40, tokens: 800),
                     share("Haiku 5.5", cost: 3, tokens: 700), share("Opus 4.8", cost: 1, tokens: 20),
                     share("Sonnet 5", cost: 0.5, tokens: 10)]
        let newer = share("Fable 5.3", cost: 0, tokens: 50, unpriced: 12)
        suite.expect(NotchAgentSupport.spendModels(known).map(\.name) == ["Opus 5.5", "Sonnet 5.5", "Haiku 5.5", "Opus 4.8"],
                     "priced models rank by cost, four to the card")
        suite.expect(NotchAgentSupport.spendModels(known + [newer]).map(\.name)
                        == ["Opus 5.5", "Sonnet 5.5", "Haiku 5.5", "Fable 5.3"]
                        && NotchAgentSupport.spendModels([newer] + known).last?.name == "Fable 5.3",
                     "a model without a price keeps a row however little it weighs")
        suite.expect(NotchAgentSupport.spendModels([newer, share("Aaa 9", cost: 0, tokens: 90, unpriced: 1),
                                                    share("Bbb 9", cost: 0, tokens: 5, unpriced: 1)] + known).map(\.name)
                        == ["Opus 5.5", "Sonnet 5.5", "Aaa 9", "Fable 5.3"],
                     "at most two unpriced rows, the most tokens first, and the priced ones give them room")
        suite.expect(NotchAgentSupport.spendModels([share("Idle", cost: 0, tokens: 0)]).isEmpty
                        && NotchAgentSupport.isUnpriced(newer.totals) && !NotchAgentSupport.isUnpriced(known[0].totals)
                        && !NotchAgentSupport.isUnpriced(share("Mixed", cost: 2, tokens: 5, unpriced: 3).totals),
                     "a model with nothing counted has no row, and one partly priced still shows its value")
        suite.expect(NotchAgentSupport.costText(newer.totals, locale: Locale(identifier: "en_US")) == "≥ $0.00"
                        && NotchAgentSupport.costText(known[1].totals, locale: Locale(identifier: "en_US")) == "$40.00"
                        && NotchAgentSupport.costText(share("Mixed", cost: 2, tokens: 5, unpriced: 3).totals,
                                                      locale: Locale(identifier: "en_US")) == "≥ $2.00",
                     "an amount with unpriced work behind it reads as a minimum")
        let unknownCost = AgentPricing.cost(AgentBillable(tokens: AgentTokens(input: 1_000, output: 500)), model: "claude-fable-5-3")
        var unknownTotals = AgentTotals()
        unknownTotals.add(AgentUsageRecord(provider: .claude, date: Date(timeIntervalSince1970: 1_800_000_000),
                                           model: "claude-fable-5-3", project: "", session: "s",
                                           tokens: AgentTokens(input: 1_000, output: 500),
                                           cost: unknownCost.cost, savings: unknownCost.savings))
        suite.expect(unknownCost.cost == nil && unknownTotals.unpriced == 1 && unknownTotals.tokens.total == 1_500
                        && unknownTotals.cost == 0 && NotchAgentSupport.isUnpriced(unknownTotals),
                     "an unknown model's response has no cost, and its tokens and its response still count")
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
                        && AgentPricing.displayName("claude-mythos-preview") == "Mythos Preview"
                        && AgentPricing.displayName("claude-3-5-sonnet-latest") == "Sonnet 3.5",
                     "model names read the way people say them, without snapshot dates")
        suite.expect(AgentPricing.displayName("claude-opus-6") == "Opus 6" && AgentPricing.displayName("gpt-6-astra") == "gpt-6-astra",
                     "a model no list knows yet still reads well, and another maker's keeps its id")
        suite.expect(AgentPlans.claude(organizationType: "claude_max", rateLimitTier: "default_claude_max_20x")
                        == AgentPlan(name: "Max 20×", monthlyPrice: 200)
                        && AgentPlans.claude(organizationType: "claude_pro", rateLimitTier: nil)?.monthlyPrice == 20
                        && AgentPlans.claude(organizationType: nil, rateLimitTier: nil) == nil
                        && AgentPlans.claude(organizationType: "claude_ultra", rateLimitTier: "default_claude_ultra")
                        == AgentPlan(name: "Ultra", monthlyPrice: nil),
                     "plans are recognized, and an unknown one keeps its name without a price")
    }

    private static func priceJSON(schema: String = "1", updated: String = "2026-09-22",
                                  claude: String = #"{"id":"claude-opus-5","input":5,"output":25,"cacheRead":0.5,"cacheWrite":6.25,"cacheWriteLong":10}"#,
                                  extra: String = "") -> Data {
        Data(#"{"schema":\#(schema),"updated":"\#(updated)"\#(extra),"claude":{"webSearch":0.01,"usOnlyMultiplier":1.1,"models":[\#(claude)],"plans":[{"match":"max_20x","name":"Max 20×","monthly":200}]}}"#.utf8)
    }

    private static func priceList(_ suite: TestSuite, shipped: AgentPriceList) {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let first = utc.date(from: DateComponents(year: 2026, month: 9, day: 22)) ?? .distantFuture
        suite.expect(shipped.updated >= first && shipped.updated <= Date().addingTimeInterval(86_400)
                        && shipped.claude.count >= 23 && shipped.claudePlans.count >= 6,
                     "the shipped list carries a real day, Claude's models and the plans")
        // A list published for older builds still carries other agents' prices, which are ignored.
        let minimal = AgentPriceList.decode(priceJSON(
            claude: #"{"id":"claude-opus-5","input":5,"output":25,"cacheRead":0.5}"#,
            extra: #","notes":"a field from a later list","other":{"models":[{"id":"gpt-6-astra","input":10,"output":50,"cacheRead":1}],"plans":[]}"#))
        let long = AgentPriceList.decode(priceJSON(claude: #"{"id":"claude-opus-5","input":5,"output":25,"cacheRead":0.5,"longContext":{"above":272000,"inputMultiplier":2,"outputMultiplier":1.5}}"#))
        suite.expect(long?.claude.first?.price.longContext == AgentLongContext(above: 272_000, input: 2, output: 1.5),
                     "a model can carry its own long-context threshold and premium")
        suite.expect(minimal?.claude.first?.price == AgentPrice(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 5, cacheWriteLong: 5)
                        && minimal?.claudePlans == [AgentPriceList.Plan(match: "max_20x", name: "Max 20×", monthly: 200)],
                     "unknown fields and other agents are ignored, and a model without cache writes bills them as input")
        let refused = [
            priceJSON(schema: "2"), priceJSON(updated: "2026-13-40"), priceJSON(schema: "true"),
            priceJSON(claude: #"{"id":"claude-opus-5","input":-5,"output":25,"cacheRead":0.5}"#),
            priceJSON(claude: #"{"id":"claude-opus-5","input":true,"output":25,"cacheRead":0.5}"#),
            priceJSON(claude: #"{"id":"gpt-6","input":5,"output":25,"cacheRead":0.5}"#),
            priceJSON(claude: #"{"id":"Claude Opus","input":5,"output":25,"cacheRead":0.5}"#),
            priceJSON(claude: #"{"id":"claude-opus-5","input":5,"output":25,"cacheRead":0.5},{"id":"claude-opus-5","input":6,"output":30,"cacheRead":0.6}"#),
            priceJSON(claude: #"{"id":"claude-opus-5","input":5,"output":25,"cacheRead":0.5,"fastMultiplier":50}"#),
            priceJSON(claude: #"{"id":"claude-opus-5","input":5,"output":25,"cacheRead":0.5,"longContext":{"above":5,"inputMultiplier":2,"outputMultiplier":1.5}}"#),
            priceJSON(claude: #"{"id":"claude-opus-5","input":5,"output":25,"cacheRead":0.5,"longContext":true}"#),
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
                                     claudePlans: shipped.claudePlans,
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

    private static func offlineTurns(_ suite: TestSuite) {
        let now = AgentTimestamp.parse("2026-09-21T23:45:00.000Z")!
        let drop = AgentTimestamp.parse("2026-09-21T23:43:00.000Z")!
        let grace = AgentUsageStore.offlineGrace
        var state = AgentLogState()
        let store = AgentUsageStore()
        store.reportsTransitions = true
        func feed(_ data: Data) -> [AgentUsageEvent] {
            store.apply(AgentLogParser.parseClaude(data, state: &state, now: now), file: "main", provider: .claude,
                        tracksTurns: true, modified: now, now: now)
        }
        func finished(_ events: [AgentUsageEvent], _ wanted: AgentProvider) -> Bool {
            events.contains { if case .finished(let provider, _, _, _, _) = $0 { provider == wanted } else { false } }
        }
        _ = feed(claudeUser())
        _ = feed(claudeAssistant(stop: "tool_use"))
        suite.expect(!store.closeOfflineTurns(since: drop, lasting: grace - 1) && store.live.count == 1,
                     "a short drop, as when the Mac changes networks, ends no turn")
        suite.expect(store.closeOfflineTurns(since: drop, lasting: grace) && store.live.isEmpty,
                     "a Claude turn ends once the Mac stays offline")
        suite.expect(feed(claudeAssistant(id: "msg_2", request: "req_2", stop: "tool_use", time: "2026-09-21T23:44:00.000Z")).isEmpty
                        && store.live.first { $0.provider == .claude }?.started == AgentTimestamp.parse("2026-09-21T23:44:00.000Z"),
                     "a retry that gets through opens a turn of its own")
        let retried = store.live.first { $0.provider == .claude }
        suite.expect(retried?.tokens.total == AgentTokens(input: 2, cacheWrite: 17_218, cacheRead: 43_134, output: 225).total
                        && (retried?.cost ?? 0) > 0,
                     "the reply that gets through counts toward the turn it opens")
        suite.expect(!store.closeOfflineTurns(since: drop, lasting: grace + 60) && store.live.contains { $0.provider == .claude },
                     "a turn whose model replied since the drop, as a model on the Mac does, keeps working offline")
        store.closeIdleTurns(now: now, after: 0)
        store.closeOfflineTurns(since: AgentTimestamp.parse("2026-09-21T23:44:10.000Z")!, lasting: grace)
        _ = feed(claudeAssistant(id: "msg_3", request: "req_3", stop: "tool_use", time: "2026-09-21T23:44:30.000Z"))
        suite.expect(store.live.first { $0.provider == .claude }?.started == AgentTimestamp.parse("2026-09-21T23:44:30.000Z"),
                     "a quiet turn ends offline too, so a later retry does not take it up again")

        func call(_ tool: String, _ id: String) -> Data {
            line(#"{"type":"assistant","timestamp":"2026-09-21T23:44:40.000Z","sessionId":"s1","message":{"id":"msg_\#(id)","model":"<synthetic>","stop_reason":"tool_use","content":[{"type":"tool_use","id":"\#(id)","name":"\#(tool)","input":{}}]}}"#)
        }
        func result(_ id: String) -> Data {
            line(#"{"type":"user","sessionId":"s1","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\#(id)","content":"ok"}]}}"#)
        }
        // After the last reply, so only the command keeps the turn.
        let late = AgentTimestamp.parse("2026-09-21T23:44:45.000Z")!
        _ = feed(call("WebFetch", "toolu_web"))
        _ = feed(call("Bash", "toolu_sh"))
        suite.expect(state.runningCommands == ["toolu_sh"], "only a shell command counts as work on the Mac")
        suite.expect(!store.closeOfflineTurns(since: late, lasting: grace, keeping: ["main"])
                        && store.live.contains { $0.provider == .claude },
                     "a turn waiting on a shell command keeps working offline")
        _ = feed(result("toolu_web"))
        suite.expect(state.runningCommands == ["toolu_sh"], "another tool's result leaves the command running")
        _ = feed(line(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_web","content":"The pending command is toolu_sh"}]}}"#))
        suite.expect(state.runningCommands == ["toolu_sh"],
                     "another tool's output quoting the shell call does not complete it")
        _ = feed(line(#"{"type":"user","isSidechain":true,"message":{"content":[{"type":"tool_result","tool_use_id":"toolu_sh","content":"ok"}]}}"#))
        suite.expect(state.runningCommands == ["toolu_sh"],
                     "a subagent's tool result cannot complete the main turn's command")
        _ = feed(line(#"{"type":"user","isMeta":true,"message":{"content":[{"type":"tool_result","tool_use_id":"toolu_sh","content":"ok"}]}}"#))
        suite.expect(state.runningCommands == ["toolu_sh"],
                     "a meta tool result cannot complete the main turn's command")
        _ = feed(result("toolu_sh"))
        suite.expect(state.runningCommands.isEmpty, "the command's result means the next step needs the network")
        suite.expect(store.closeOfflineTurns(since: late, lasting: grace) && !store.live.contains { $0.provider == .claude },
                     "once its command is done, a turn ends offline")
        _ = feed(call("Bash", "toolu_left"))
        _ = feed(line(#"{"type":"user","message":{"content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#))
        _ = feed(claudeUser(time: "2026-09-21T23:44:50.000Z"))
        suite.expect(state.runningCommands.isEmpty, "a new prompt forgets a command the last turn left")

        // A session killed in the middle of a command leaves its turn open
        // in the log; resumed there, its next prompt reads as work going on.
        var killed = AgentLogState()
        for data in [claudeUser(), call("Bash", "toolu_killed"), claudeUser(meta: true),
                     line(#"{"type":"user","isSidechain":true,"sessionId":"s1","message":{"role":"user","content":"Explore the repo"}}"#)] {
            _ = AgentLogParser.parseClaude(data, state: &killed, now: now)
        }
        suite.expect(killed.runningCommands == ["toolu_killed"], "a meta line or a subagent's prompt leaves a command running")
        _ = AgentLogParser.parseClaude(claudeUser("Go on", time: "2026-09-21T23:44:55.000Z"), state: &killed, now: now)
        suite.expect(killed.turnOpen && killed.runningCommands.isEmpty,
                     "a prompt typed into a turn left open forgets the command a killed session left")

        let blip = AgentUsageStore()
        blip.reportsTransitions = true
        var blipState = AgentLogState()
        func feedBlip(_ data: Data) -> [AgentUsageEvent] {
            blip.apply(AgentLogParser.parseClaude(data, state: &blipState, now: now), file: "blip", provider: .claude,
                       tracksTurns: true, modified: now, now: now)
        }
        _ = feedBlip(claudeUser())
        _ = feedBlip(claudeAssistant(stop: "tool_use"))
        blip.closeOfflineTurns(since: drop, lasting: grace - 1)
        suite.expect(finished(feedBlip(claudeAssistant(id: "msg_9", request: "req_9", stop: "end_turn",
                                                       time: "2026-09-21T23:44:55.000Z")), .claude),
                     "a turn that reconnects after a short drop still reports its finish")
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
        _ = feed(claudeUser())
        _ = feed(claudeAssistant(id: "msg_5", request: "req_5", stop: "tool_use", time: "2026-09-21T23:40:10.000Z"))
        let structured = feed(line(#"{"type":"user","timestamp":"2026-09-21T23:40:15.000Z","sessionId":"s1","message":{"role":"user","content":[{"type":"tool_result","content":"Structured output provided successfully"}]},"toolUseResult":"Structured output provided successfully","toolEndsTurn":true}"#))
        suite.expect(store.live.isEmpty && structured.contains { if case .finished = $0 { true } else { false } },
                     "a tool that ends the turn finishes it without waiting for a reply")
        suite.expect(feed(line(#"{"type":"user","timestamp":"2026-09-21T23:40:16.000Z","message":{"content":[{"type":"tool_result","content":"ok"}]},"toolEndsTurn":true}"#)).isEmpty
                        && store.live.isEmpty, "a turn-ending tool result alone never opens a turn")
        _ = feed(claudeUser())
        _ = feed(claudeAssistant(id: "msg_6", request: "req_6", stop: "tool_use"))
        _ = feed(line(#"{"type":"user","timestamp":"2026-09-21T23:43:00.000Z","message":{"content":[{"type":"tool_result","content":"\"toolEndsTurn\":true"}]},"toolEndsTurn":false}"#))
        suite.expect(store.live.count == 1, "a tool result quoting the marker keeps the turn working")
        // A subagent's own turn-ending tool, and a structured tool result
        // that holds the marker deeper down, both leave the main turn open.
        _ = feed(line(#"{"type":"user","isSidechain":true,"timestamp":"2026-09-21T23:43:01.000Z","message":{"content":[{"type":"tool_result","content":"done"}]},"toolEndsTurn":true}"#))
        suite.expect(store.live.count == 1, "a subagent's turn-ending tool keeps the main turn working")
        _ = feed(line(#"{"type":"user","timestamp":"2026-09-21T23:43:02.000Z","message":{"content":[{"type":"tool_result","content":"ok"}]},"toolUseResult":{"result":{"toolEndsTurn":true}}}"#))
        suite.expect(store.live.count == 1, "a marker nested in a structured tool result keeps the turn working")
        _ = feed(line(#"{"type":"user","message":{"content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#))
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
            record(.claude, AgentTimestamp.parse("2026-09-22T16:30:00Z")!, cost: 4, model: "claude-haiku-5", project: "web"),
            record(.claude, AgentTimestamp.parse("2026-09-18T09:00:00Z")!, cost: 10, model: "claude-haiku-5", project: "web"),
            record(.claude, AgentTimestamp.parse("2026-09-01T09:00:00Z")!, cost: 100),
            record(.claude, AgentTimestamp.parse("2026-01-01T09:00:00Z")!, cost: 1000),
        ]
        let snapshot = AgentUsageSummary.snapshot(records: records, limits: [:], live: [], plans: [:],
                                                  providers: [.claude], now: now, calendar: calendar)
        suite.expect(snapshot.usage(.today).total.cost == 12 && snapshot.usage(.week).total.cost == 22
                        && snapshot.usage(.month).total.cost == 122,
                     "today, a week and thirty days each add what falls inside them")
        suite.expect(snapshot.days.count == AgentUsageSnapshot.dayCount && snapshot.days.last?.start == calendar.startOfDay(for: now)
                        && snapshot.days.reduce(0.0) { $0 + $1.total.cost } == 122,
                     "the daily history ends today and leaves out what is older")
        suite.expect(snapshot.hours.count == 24 && snapshot.hours[10].total.cost == 2 && snapshot.hours[16].total.cost == 4,
                     "today's hours hold each response in its hour")
        suite.expect(snapshot.usage(.today).models.map(\.name) == ["Sonnet 5", "Haiku 5", "Opus 5"]
                        && snapshot.usage(.today).projects.map(\.name) == ["app", "web"],
                     "models and projects are ranked by what they cost")
        suite.expect(snapshot.claudeBlock == AgentBlock(start: AgentTimestamp.parse("2026-09-22T15:20:00Z")!,
                                                        end: AgentTimestamp.parse("2026-09-22T20:20:00Z")!,
                                                        totals: { var totals = AgentTotals(); totals.add(records[2]); totals.add(records[3]); return totals }()),
                     "Claude's window starts at the first request after the last one ended")
        suite.expect(snapshot.burnRate[.claude]?.cost == 8, "the last half hour is scaled to an hour")
        suite.expect(snapshot.lastActivity[.claude] == records[3].date && snapshot.seen == [.claude],
                     "the latest activity is kept")
        let unpriced = AgentUsageSummary.snapshot(records: [record(.claude, now, cost: nil, tokens: 500, model: "claude-unknown")]
                                                    + records.prefix(1),
                                                  limits: [:], live: [], plans: [:], providers: [.claude],
                                                  now: now, calendar: calendar)
        suite.expect(!unpriced.usage(.today).fullyPriced && unpriced.usage(.today).total.unpriced == 1
                        && unpriced.usage(.today).models.first?.name == "Opus 5",
                     "an unpriced model makes totals a minimum and ranks fall back to tokens")
        let off = AgentUsageSummary.snapshot(records: records, limits: [:], live: [], plans: [:],
                                             providers: [], now: now, calendar: calendar)
        suite.expect(off.usage(.today).total.cost == 0 && off.seen.isEmpty, "with Claude off nothing counts")
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

        // A Team plan's session can renew before the chain's five hours are
        // up: once the readings show it, the window leaves the earlier spend.
        let renewed = AgentLimits(provider: .claude, windows: [
            AgentLimitWindow(id: "claude.fh", kind: .session, minutes: 300, scope: nil, usedPercent: 0, resetsAt: nil,
                             renewedAfter: AgentTimestamp.parse("2026-09-22T16:55:00Z")!)],
            observedAt: evening, source: .claudeApp)
        let teamDay = AgentUsageSummary.snapshot(records: steady, limits: [.claude: renewed], live: [], plans: [:],
                                                 providers: [.claude], now: evening, calendar: kolkata)
        suite.expect(teamDay.claudeBlock?.start == AgentTimestamp.parse("2026-09-22T17:10:00Z")
                        && teamDay.claudeBlock?.totals.cost == 2,
                     "a session the readings saw renew counts only what came after it")
        let exact = AgentLimits(provider: .claude, windows: [
            AgentLimitWindow(id: "claude.five_hour", kind: .session, minutes: 300, scope: nil, usedPercent: 10,
                             resetsAt: AgentTimestamp.parse("2026-09-22T21:20:00Z")!)],
            observedAt: evening, source: .account)
        suite.expect(AgentUsageSummary.snapshot(records: steady, limits: [.claude: exact], live: [], plans: [:],
                                                providers: [.claude], now: evening, calendar: kolkata)
                        .claudeBlock?.start == AgentTimestamp.parse("2026-09-22T16:30:00Z"),
                     "an exact renewal leaves out what came more than five hours before it")

        // A snapshot is made again only when time alone would change it.
        let noon = AgentTimestamp.parse("2026-09-22T12:00:00Z")!
        let hourOn = noon.addingTimeInterval(3600)
        let nextDay = AgentTimestamp.parse("2026-09-23T00:00:30Z")!
        let resting = AgentUsageSummary.snapshot(records: [record(.claude, noon.addingTimeInterval(-6 * 3600), cost: 1)],
                                                 limits: [:], live: [], plans: [:], providers: [.claude],
                                                 now: noon, calendar: calendar)
        suite.expect(!AgentUsageSummary.movesWithClock(resting, now: hourOn, calendar: calendar)
                        && AgentUsageSummary.movesWithClock(resting, now: nextDay, calendar: calendar),
                     "a snapshot with nothing recent holds until a new day moves every total")
        let burning = AgentUsageSummary.snapshot(records: [record(.claude, noon.addingTimeInterval(-600), cost: 1)],
                                                 limits: [:], live: [], plans: [:], providers: [.claude],
                                                 now: noon, calendar: calendar)
        let windowOpen = AgentUsageSummary.snapshot(records: [record(.claude, noon.addingTimeInterval(-5400), cost: 1)],
                                                    limits: [:], live: [], plans: [:], providers: [.claude],
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
        let reading = AgentLimits(provider: .claude, windows: [window(40, resetsIn: 100, id: "a"), window(60, resetsIn: 50, id: "b")],
                                  observedAt: now, source: .claudeApp)
        suite.expect(AgentLimitSupport.binding(reading, now: now)?.id == "b", "the most spent window binds")
        func limits(_ used: Double, resets: TimeInterval, observed: TimeInterval = 0) -> AgentLimits {
            AgentLimits(provider: .claude, windows: [window(used, resetsIn: resets)], observedAt: now.addingTimeInterval(observed),
                        source: .claudeApp)
        }
        suite.expect(AgentLimitSupport.crossings(previous: limits(70, resets: 100), current: limits(85, resets: 100), threshold: 80).count == 1
                        && AgentLimitSupport.crossings(previous: limits(85, resets: 100), current: limits(90, resets: 100), threshold: 80).isEmpty
                        && AgentLimitSupport.crossings(previous: limits(85, resets: 100), current: limits(85, resets: 9000, observed: 200),
                                                       threshold: 80).count == 1
                        && AgentLimitSupport.crossings(previous: nil, current: limits(99, resets: 100), threshold: 80).isEmpty,
                     "a warning comes once per crossing, again after a renewal, never for the first reading")
        suite.expect(AgentLimitSupport.crossings(previous: limits(85, resets: 100), current: limits(90, resets: 520, observed: 50),
                                                 threshold: 80).isEmpty
                        && AgentLimitSupport.crossings(previous: limits(95, resets: 100), current: limits(85, resets: 100, observed: 50),
                                                       threshold: 80).count == 1,
                     "a later renewal read before the old one goes by is the same window, and usage that fell is a new one")
    }

    // MARK: Reading files

    private static func liveTurns(_ suite: TestSuite) {
        let start = Date(timeIntervalSince1970: 3_000_000)
        let tokens = AgentTokens(input: 1000, cacheWrite: 0, cacheRead: 9000, output: 200)
        let record = AgentUsageRecord(provider: .claude, date: start.addingTimeInterval(10), model: "claude-opus-5-5",
                                      project: "app", session: "s", tokens: tokens, cost: 0.5, savings: 0)
        let entries: [AgentLogEntry] = [.turnBegan(start), .usage(key: "claude:m1:r1", record: record, billable: AgentBillable(tokens: tokens))]
        let store = AgentUsageStore()
        store.apply(entries, file: "/logs/a.jsonl", provider: .claude, tracksTurns: true, modified: start)
        // The same log replaced by a longer copy is read again from its start.
        store.apply(entries, file: "/logs/a.jsonl", provider: .claude, tracksTurns: true, modified: start)
        let turn = store.live.first
        suite.expect(store.live.count == 1 && turn?.model == "claude-opus-5-5" && turn?.project == "app"
                        && turn?.tokens.total == 10_200 && turn?.started == start,
                     "a log rewritten in place keeps the running turn's model, project and tokens")
        store.apply([.turnBegan(start.addingTimeInterval(60))], file: "/logs/a.jsonl", provider: .claude,
                    tracksTurns: true, modified: start)
        suite.expect(store.live.first?.tokens.total == 0, "a new turn in the same log starts from nothing")
        suite.expect(store.forget(file: "/logs/a.jsonl") && store.live.isEmpty && !store.forget(file: "/logs/a.jsonl"),
                     "a removed log, like a deleted chat, stops showing as working")

        // A turn that goes quiet, as while it waits for an approval, comes
        // back when its work resumes and finishes as the whole turn.
        let quiet = AgentUsageStore()
        quiet.reportsTransitions = true
        let waitingLog = "/logs/b.jsonl"
        quiet.apply([.turnBegan(start)], file: waitingLog, provider: .claude, tracksTurns: true, modified: start, now: start)
        quiet.closeIdleTurns(now: start.addingTimeInterval(1200), after: NotchAgentSupport.idleTurn)
        suite.expect(quiet.live.isEmpty && quiet.waiting[waitingLog]?.started == start,
                     "a quiet turn stops showing as working and waits aside")
        let resumedAt = start.addingTimeInterval(1210)
        let resumed = AgentUsageRecord(provider: .claude, date: resumedAt, model: "claude-opus-5-5", project: "app",
                                       session: "s", tokens: tokens, cost: 0.5, savings: 0)
        quiet.apply([.usage(key: "claude:m2:r2", record: resumed, billable: AgentBillable(tokens: tokens))], file: waitingLog,
                    provider: .claude, tracksTurns: true, modified: resumedAt, now: resumedAt)
        suite.expect(quiet.live.first?.started == start && quiet.waiting.isEmpty, "work that resumes brings the turn back")
        let endedAt = start.addingTimeInterval(1300)
        let ended = quiet.apply([.turnEnded(endedAt, completed: true, duration: nil)], file: waitingLog, provider: .claude,
                                tracksTurns: true, modified: endedAt, now: endedAt)
        let whole = AgentUsageEvent.finished(provider: .claude, duration: 1300, cost: 0.5, tokens: tokens.total, project: "app")
        suite.expect(ended == [whole] && quiet.live.isEmpty, "a turn that waited finishes as the whole turn, with what it spent")
        quiet.apply([.turnBegan(endedAt)], file: waitingLog, provider: .claude, tracksTurns: true, modified: endedAt)
        quiet.closeIdleTurns(now: endedAt.addingTimeInterval(1200), after: NotchAgentSupport.idleTurn)
        let nextStart = endedAt.addingTimeInterval(1500)
        quiet.apply([.turnBegan(nextStart)], file: waitingLog, provider: .claude, tracksTurns: true, modified: nextStart)
        suite.expect(quiet.waiting.isEmpty && quiet.live.first?.started == nextStart, "a new turn replaces one that went quiet")
        quiet.closeIdleTurns(now: nextStart.addingTimeInterval(AgentUsageStore.resumeWindow),
                             after: NotchAgentSupport.idleTurn)
        suite.expect(quiet.live.isEmpty && quiet.waiting.isEmpty && AgentUsageStore.resumeWindow == 3600,
                     "a turn quiet for an hour, as one a killed session left open, is over")
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
                                       providers: [.claude], now: now)
        }
        suite.expect(NotchAgentReadout.elapsed.advancesWithClock && NotchAgentReadout.limit.advancesWithClock
                        && !NotchAgentReadout.tokens.advancesWithClock && !NotchAgentReadout.cost.advancesWithClock,
                     "only elapsed and expiring-limit readouts require clock-driven updates")
        for provider in AgentProvider.allCases {
            for focus in NotchAgentLimitFocus.allCases {
                let empty = AgentUsageSnapshot()
                let sample = NotchAgentSupport.stripSampleSnapshot(empty, provider: provider, focus: focus, now: now)
                let used = focus == .session ? 0.32 : 0.57
                suite.expect(NotchAgentSupport.stripReading(sample, readout: .limit, display: .used, focus: focus, now: now)
                                == AgentFormat.percent(used),
                             "\(provider.rawValue) settings preview illustrates the selected \(focus.rawValue) limit without account data")
                suite.expect(NotchAgentSupport.stripReading(sample, readout: .limit, display: .remaining, focus: focus, now: now)
                                == AgentFormat.percent(1 - used),
                             "settings limit preview respects remaining versus used")
                suite.expect(empty.live.isEmpty && empty.limits.isEmpty,
                             "preview examples never populate the real usage snapshot")
                suite.expect(NotchAgentSupport.stripReading(sample, readout: .elapsed, display: .remaining, now: now) == "12:34"
                                && NotchAgentSupport.stripReading(sample, readout: .cost, display: .remaining, now: now) == AgentFormat.cost(4.56)
                                && NotchAgentSupport.stripReading(sample, readout: .tokens, display: .remaining, now: now) == AgentFormat.tokens(20_000),
                             "settings preview still illustrates time, cost and written tokens")
            }
        }
        let short = snapshot([session(.claude, startedAgo: 754)])
        let long = snapshot([session(.claude, startedAgo: 3723), session(.claude, startedAgo: 60)])
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
        suite.expect(NotchAgentSupport.limitShare(window, display: .remaining, text: .enUS)
                        == "\(AgentFormat.percent(0.21)) left"
                        && NotchAgentSupport.limitShare(window, display: .used, text: .enUS)
                            == "\(AgentFormat.percent(0.79)) used",
                     "a limit on the card says whether its share is left or used")
        suite.expect(NotchAgentSupport.stripSampleSnapshot(limited, provider: .claude, focus: .weekly, now: now) == limited,
                     "settings preview preserves an active provider's real allowance")
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
        let weekOnly = AgentLimits(provider: .claude, windows: [
            AgentLimitWindow(id: "cw", kind: .weekly, minutes: 10_080, scope: nil, usedPercent: 70,
                             resetsAt: now.addingTimeInterval(86_400))], observedAt: now, source: .account)
        let resting = snapshot([], limits: [.claude: both])
        suite.expect(NotchAgentSupport.restingLimit(resting, focus: .session, now: now)
                        .map { $0.provider == .claude && $0.window.usedPercent == 22 } == true,
                     "the resting island shows the chosen window while the account reports one")
        suite.expect(NotchAgentSupport.restingLimit(snapshot([], limits: [.claude: weekOnly]), focus: .session, now: now)
                        .map { $0.provider == .claude && $0.window.usedPercent == 70 } == true
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
        write("100.json", #"{"pid":100,"sessionId":"quit","cwd":"/p"}"#)
        write("200.json", #"{"pid":200,"sessionId":"killed"}"#)
        write("300.json", #"{"pid":300,"sessionId":"killed"}"#)
        write("300.abc.key", "{}")
        write("500.json", #"{"pid":500,"sessionId":"contained","pidDomain":"linux:4f2ac19e:4026531836"}"#)
        write(".heartbeat", "1")
        let running: Set<Int32> = [100, 300]
        var registry = AgentSessionRegistry.read([folder, folder.appending(path: "missing")]) { running.contains($0) }
        suite.expect(registry == AgentSessionRegistry(running: ["quit", "killed"], ended: [], complete: true, listed: true),
                     "a session with a running process reads as running, even beside a killed one's record, and a container's record proves nothing")
        write("400.json", #"{"pid":"#)
        registry = AgentSessionRegistry.read([folder]) { $0 == 100 }
        suite.expect(registry.running == ["quit"] && registry.ended == ["killed"] && !registry.complete,
                     "a killed process's record reads as ended, and a record being written leaves the list incomplete")

        let store = AgentUsageStore()
        for name in ["quit", "killed", "other", "partial"] {
            store.apply([.turnBegan(start)], file: "/p/\(name).jsonl", provider: .claude, tracksTurns: true, modified: start)
        }
        store.closeEndedTurns(AgentSessionRegistry(running: ["quit", "partial"], ended: [], complete: true))
        suite.expect(store.live.count == 4, "turns with a running process, or with no record at all, keep working")
        store.closeEndedTurns(AgentSessionRegistry(running: [], ended: [], complete: false))
        suite.expect(store.live.count == 4, "a record missing from an incomplete read proves nothing")
        let closed = store.closeEndedTurns(AgentSessionRegistry(running: ["partial"], ended: ["killed"], complete: true))
        suite.expect(closed && Set(store.live.map(\.id)) == ["/p/other.jsonl", "/p/partial.jsonl"]
                        && store.waiting.isEmpty,
                     "a session whose process quit or was killed stops working at once, without waiting aside")
        store.closeEndedTurns(AgentSessionRegistry(running: [], ended: [], complete: true))
        suite.expect(store.live.count == 1 && !store.live.contains { $0.id == "/p/partial.jsonl" },
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
                        && AgentLogCursor(path: "/x/s1.jsonl", provider: .claude).tracksTurns,
                     "Claude subagents report to the turn their session tracks")
        let history = AgentLogCursor(path: "/x/s1.jsonl", provider: .claude)
        history.history = true
        suite.expect(!history.tracksTurns, "a synced log is only counted, never followed as a turn")
        let home = AgentLogRoot.all(home: folder)
        suite.expect(home.map(\.url.path) == [folder.appending(path: ".claude/projects").path,
                                              folder.appending(path: ".config/claude/projects").path]
                        && home.allSatisfy { $0.provider == .claude && !$0.synced },
                     "Claude Code's own folders are the local roots")
        let root = AgentLogRoot.canonical(folder)
        let found = AgentLogReader.discover([AgentLogRoot(provider: .claude, url: root)], since: .distantPast)
        suite.expect(found.map(\.path) == [root.appending(path: "session.jsonl").path] && found.first?.provider == .claude,
                     "log files are found under a root")
        let versions = root.appending(path: ".stversions/session~20261108-120000.jsonl").path
        suite.expect(!AgentLogRoot(provider: .claude, url: root).accepts(versions)
                        && !AgentLogRoot(provider: .claude, url: root).accepts(root.appending(path: "session.jsonl.zst").path)
                        && AgentLogRoot(provider: .claude, url: root).accepts(root.appending(path: "p/.claude/projects/a/s.jsonl").path),
                     "only Claude logs count, never Syncthing's old versions, and a profile folder deep inside is searched")
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
        let teamPlan = AgentClaudeAppUsage.samples(from: history([
            ("2026-10-21T10:28:00Z", "o", ["fh": 16]), ("2026-10-21T10:43:00Z", "o", ["fh": 29]),
            ("2026-10-21T10:58:00Z", "o", ["fh": 9]), ("2026-10-21T11:55:00Z", "o", ["fh": 19]),
            ("2026-10-21T12:00:00Z", "o", ["fh": 0])])) ?? []
        suite.expect(AgentClaudeAppUsage.limits(from: Array(teamPlan.prefix(4)), now: at("2026-10-21T11:56:00Z"))?
                        .windows.first?.renewedAfter == at("2026-10-21T10:43:00Z")
                        && AgentClaudeAppUsage.limits(from: teamPlan, now: at("2026-10-21T12:01:00Z"))?
                        .windows.first?.renewedAfter == at("2026-10-21T11:55:00Z"),
                     "a drop or a zero marks the session's renewal after the reading before it")
        // Readings hours apart leave the start anywhere between them, and the
        // first one above zero is only the latest it can have been.
        let slept = AgentClaudeAppUsage.samples(from: history([
            ("2026-10-12T12:26:00Z", "o", ["fh": 2, "sd": 9]), ("2026-10-12T19:03:00Z", "o", ["fh": 4, "sd": 11])])) ?? []
        let sleptReset = AgentClaudeAppUsage.limits(from: slept, now: at("2026-10-12T19:04:00Z"))?.windows.first?.estimatedResetsAt
        suite.expect(sleptReset == at("2026-10-12T21:33:00Z"),
                     "a session first read after sleep estimates the midpoint instead of the latest possible renewal")
        let overnight = AgentClaudeAppUsage.samples(from: history([
            ("2026-10-11T23:00:00Z", "o", ["fh": 0, "sd": 40]), ("2026-10-12T11:59:00Z", "o", ["fh": 29, "sd": 41])])) ?? []
        let overnightReset = AgentClaudeAppUsage.limits(from: overnight, now: at("2026-10-12T12:32:00Z"))?.windows.first?.estimatedResetsAt
        suite.expect(overnightReset == at("2026-10-12T14:29:00Z"),
                     "an overnight gap keeps the renewal between the reading and five hours after it")
        let lone = AgentClaudeAppUsage.samples(from: history([("2026-10-12T19:03:00Z", "o", ["fh": 4, "sd": 11])])) ?? []
        suite.expect(AgentClaudeAppUsage.limits(from: lone, now: at("2026-10-12T19:04:00Z"))?.windows.first?.resetsAt
                        == at("2026-10-13T00:03:00Z"),
                     "a file that starts with the session has nothing before it to bracket the start")
        let gap = AgentClaudeAppUsage.samples(from: history([
            ("2026-10-12T00:00:00Z", "o", ["fh": 0]), ("2026-10-12T08:00:00Z", "o", ["fh": 90]),
            ("2026-10-12T08:10:00Z", "o", ["fh": 95]), ("2026-10-12T10:40:00Z", "o", ["fh": 100])])) ?? []
        let beforeEstimate = AgentClaudeAppUsage.limits(from: Array(gap.prefix(3)), now: at("2026-10-12T08:10:00Z"))
        let afterEstimate = AgentClaudeAppUsage.limits(from: gap, now: at("2026-10-12T10:40:00Z"))
        if let window = afterEstimate?.windows.first, let warned = beforeEstimate?.windows.first {
            let now = at("2026-10-12T10:40:00Z")
            suite.expect(window.usedPercent == 100 && AgentLimitSupport.current(window, at: now).usedPercent == 100,
                         "fresh increasing usage survives the estimated renewal in the reader and the display")
            suite.expect(window.estimatedResetsAt == at("2026-10-12T10:30:00Z")
                            && AgentLimitSupport.displayedReset(window, now: now) == nil
                            && AgentLimitSupport.pace(for: window, now: now) == nil,
                         "an elapsed estimate hides the countdown and pace without clearing usage")
            suite.expect(warned.resetsAt == at("2026-10-12T13:00:00Z") && window.resetsAt == warned.resetsAt,
                         "a warning keeps the latest possible renewal, so the midpoint cannot send a reset alert")
            suite.expect(AgentLimitSupport.crossings(previous: beforeEstimate, current: afterEstimate!, threshold: 90).isEmpty,
                         "continuing usage after the midpoint does not become another threshold crossing")
            suite.expect(AgentLimitSupport.displayedReset(warned, now: at("2026-10-12T09:00:00Z"))
                            == at("2026-10-12T10:30:00Z"),
                         "the card still shows the useful midpoint while it is in the future")
        } else {
            suite.expect(false, "fresh observed session usage must remain present after its estimated renewal")
        }
        suite.expect(AgentClaudeAppUsage.limits(from: Array(gap.prefix(3)), now: at("2026-10-12T10:40:00Z"))?
                        .windows.first?.usedPercent == 95,
                     "the midpoint alone cannot discard a reading between Claude app checks")
        let placedGap = AgentClaudeAppUsage.limits(from: gap, now: at("2026-10-12T10:40:00Z"),
                                                   sessionStart: at("2026-10-12T07:55:00Z"))?.windows.first
        suite.expect(placedGap?.resetsAt == at("2026-10-12T12:55:00Z") && placedGap?.estimatedResetsAt == nil,
                     "a first request within the gap replaces the presentation estimate with its known start")
        suite.expect(AgentClaudeAppUsage.limits(from: gap, now: at("2026-10-12T13:00:00Z")) == nil,
                     "an estimated window still expires at its latest possible renewal")
        let dropped = gap + [AgentClaudeAppUsage.Sample(date: at("2026-10-12T10:50:00Z"), organization: "o", used: ["fh": 0]),
                             AgentClaudeAppUsage.Sample(date: at("2026-10-12T11:00:00Z"), organization: "o", used: ["fh": 2])]
        let newSession = AgentClaudeAppUsage.limits(from: dropped, now: at("2026-10-12T11:00:00Z"))?.windows.first
        suite.expect(newSession?.usedPercent == 2 && newSession?.estimatedResetsAt == nil
                        && newSession?.resetsAt == at("2026-10-12T16:00:00Z"),
                     "an observed renewal starts a new window without retaining the old estimate")
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
        let weeks: [(String, String?, [String: Any])] = [
            ("2026-09-19T11:56:00Z", "o", ["sd": 100]), ("2026-09-19T12:01:00Z", "o", ["sd": 0]),
            ("2026-09-26T11:56:00Z", "o", ["sd": 100]), ("2026-09-26T12:01:00Z", "o", ["sd": 0]),
            ("2026-10-01T08:48:00Z", "o", ["sd": 100]), ("2026-10-01T08:53:00Z", "o", ["sd": 0]),
            ("2026-10-01T10:00:00Z", "o", ["fh": 5, "sd": 4])]
        let banked = AgentClaudeAppUsage.samples(from: history(weeks)) ?? []
        suite.expect(AgentClaudeAppUsage.limits(from: banked, now: at("2026-10-01T10:05:00Z"))?.windows.last?.resetsAt
                        == at("2026-10-03T12:00:00Z"),
                     "a reset used mid-week empties the week without moving its renewal")
        // Drops whose spans only touch at a reading do not share a moment.
        let touching = AgentClaudeAppUsage.samples(from: history([
            ("2026-09-19T11:55:00Z", "o", ["sd": 100]), ("2026-09-19T12:00:00Z", "o", ["sd": 0]),
            ("2026-09-26T12:00:00Z", "o", ["sd": 100]), ("2026-09-26T12:05:00Z", "o", ["sd": 0]),
            ("2026-10-01T08:48:00Z", "o", ["sd": 100]), ("2026-10-01T08:53:00Z", "o", ["sd": 0]),
            ("2026-10-01T10:00:00Z", "o", ["fh": 5, "sd": 4])])) ?? []
        suite.expect(AgentClaudeAppUsage.limits(from: touching, now: at("2026-10-01T10:05:00Z"))?.windows.last?.resetsAt
                        == at("2026-10-08T08:53:00Z"),
                     "drops whose spans only touch at a reading confirm no schedule, so the last drop stands")
        let wideConfirmed = AgentClaudeAppUsage.samples(from: history([
            ("2026-09-19T11:56:00Z", "o", ["sd": 100]), ("2026-09-19T12:01:00Z", "o", ["sd": 0]),
            ("2026-09-26T01:00:00Z", "o", ["sd": 100]), ("2026-09-26T13:00:00Z", "o", ["sd": 0]),
            ("2026-10-01T08:48:00Z", "o", ["sd": 100]), ("2026-10-01T08:53:00Z", "o", ["sd": 0]),
            ("2026-10-01T10:00:00Z", "o", ["fh": 5, "sd": 4])])) ?? []
        suite.expect(AgentClaudeAppUsage.limits(from: wideConfirmed, now: at("2026-10-01T10:05:00Z"))?.windows.last?.resetsAt
                        == at("2026-10-03T12:00:00Z"),
                     "a confirmed drop renews inside what its confirming drops allow, not at the start of its own span")
        let afterDays = AgentClaudeAppUsage.samples(from: history([
            ("2026-09-19T11:56:00Z", "o", ["sd": 100]), ("2026-09-19T12:01:00Z", "o", ["sd": 0]),
            ("2026-09-26T11:56:00Z", "o", ["sd": 100]), ("2026-09-26T12:01:00Z", "o", ["sd": 0]),
            ("2026-10-03T12:00:00Z", "o", ["sd": 100]), ("2026-10-04T13:00:00Z", "o", ["sd": 0]),
            ("2026-10-04T14:00:00Z", "o", ["fh": 5, "sd": 4])])) ?? []
        suite.expect(AgentClaudeAppUsage.limits(from: afterDays, now: at("2026-10-04T14:05:00Z"))?.windows.last?.resetsAt
                        == at("2026-10-10T12:00:00Z"),
                     "a drop read only after days without readings does not move a schedule two drops already confirm")
        let movedWeeks: [(String, String?, [String: Any])] = [
            ("2026-09-19T11:56:00Z", "o", ["sd": 100]), ("2026-09-19T12:01:00Z", "o", ["sd": 0]),
            ("2026-09-26T11:56:00Z", "o", ["sd": 100]), ("2026-09-26T12:01:00Z", "o", ["sd": 0]),
            ("2026-09-30T10:35:00Z", "o", ["sd": 60]), ("2026-09-30T10:40:00Z", "o", ["sd": 5]),
            ("2026-10-03T11:55:00Z", "o", ["sd": 40]), ("2026-10-03T12:05:00Z", "o", ["fh": 5, "sd": 41])]
        let moved = AgentClaudeAppUsage.samples(from: history(movedWeeks)) ?? []
        suite.expect(AgentClaudeAppUsage.limits(from: moved, now: at("2026-10-03T12:10:00Z"))?.windows.last?.resetsAt
                        == at("2026-10-07T10:40:00Z"),
                     "a schedule whose renewal went by in plain sight without a drop has moved, so the last drop stands")
        // The Mac was off for the first renewal the old schedule places; the next one shows the move.
        let away = AgentClaudeAppUsage.samples(from: history(Array(movedWeeks.prefix(6)) + [
            ("2026-10-02T20:00:00Z", "o", ["sd": 30]),
            ("2026-10-10T11:55:00Z", "o", ["sd": 50]), ("2026-10-10T12:05:00Z", "o", ["fh": 5, "sd": 51])])) ?? []
        suite.expect(AgentClaudeAppUsage.limits(from: away, now: at("2026-10-10T12:10:00Z"))?.windows.last?.resetsAt
                        == at("2026-10-14T10:40:00Z"),
                     "a renewal seen going by without a drop moves the schedule even after an earlier one went unseen")
        // A reading without the week between the two hides the drop from the history, not the renewal.
        let gapped = AgentClaudeAppUsage.samples(from: history(Array(movedWeeks.dropLast()) + [
            ("2026-10-03T12:05:00Z", "o", ["fh": 5]), ("2026-10-03T12:10:00Z", "o", ["fh": 5, "sd": 0])])) ?? []
        suite.expect(AgentClaudeAppUsage.limits(from: gapped, now: at("2026-10-03T12:15:00Z"))?.windows.last?.resetsAt
                        == at("2026-10-10T12:00:00Z"),
                     "a renewal read across a reading without the week still counts as seen")
        let late = AgentClaudeAppUsage.samples(from: history(movedWeeks + [
            ("2026-10-03T12:25:00Z", "o", ["fh": 5, "sd": 0])])) ?? []
        suite.expect(AgentClaudeAppUsage.limits(from: late, now: at("2026-10-03T12:30:00Z"))?.windows.last?.resetsAt
                        == at("2026-10-10T12:00:00Z"),
                     "a renewal first read within the hour after its time keeps the schedule")
        // Emptying a week that was barely used reads as no drop at all.
        let light = AgentClaudeAppUsage.samples(from: history([
            ("2026-09-19T11:56:00Z", "o", ["sd": 100]), ("2026-09-19T12:01:00Z", "o", ["sd": 0]),
            ("2026-09-26T11:56:00Z", "o", ["sd": 100]), ("2026-09-26T12:01:00Z", "o", ["sd": 0]),
            ("2026-09-30T10:35:00Z", "o", ["sd": 60]), ("2026-09-30T10:40:00Z", "o", ["sd": 0]),
            ("2026-10-03T11:55:00Z", "o", ["sd": 1]), ("2026-10-03T12:05:00Z", "o", ["fh": 5, "sd": 0])])) ?? []
        suite.expect(AgentClaudeAppUsage.limits(from: light, now: at("2026-10-03T12:10:00Z"))?.windows.last?.resetsAt
                        == at("2026-10-10T12:00:00Z"),
                     "a renewal a barely used week could not show does not move a confirmed schedule")
        // The newer partner alone would allow 11:00; the older one narrows the renewal to 12:00.
        let partners = AgentClaudeAppUsage.samples(from: history([
            ("2026-09-19T11:57:00Z", "o", ["sd": 100]), ("2026-09-19T12:02:00Z", "o", ["sd": 0]),
            ("2026-09-26T10:40:00Z", "o", ["sd": 100]), ("2026-09-26T12:10:00Z", "o", ["sd": 0]),
            ("2026-10-03T10:30:00Z", "o", ["sd": 100]), ("2026-10-03T12:05:00Z", "o", ["sd": 0]),
            ("2026-10-07T08:48:00Z", "o", ["sd": 100]), ("2026-10-07T08:53:00Z", "o", ["sd": 0]),
            ("2026-10-07T10:00:00Z", "o", ["fh": 5, "sd": 4])])) ?? []
        suite.expect(AgentClaudeAppUsage.limits(from: partners, now: at("2026-10-07T10:05:00Z"))?.windows.last?.resetsAt
                        == at("2026-10-10T12:00:00Z"),
                     "a drop several partners confirm renews where all of them agree")
        let disagreeing = AgentClaudeAppUsage.samples(from: history([
            ("2026-09-19T08:30:00Z", "o", ["sd": 70]), ("2026-09-19T08:40:00Z", "o", ["sd": 0]),
            ("2026-09-26T11:57:00Z", "o", ["sd": 100]), ("2026-09-26T12:02:00Z", "o", ["sd": 0]),
            ("2026-10-03T08:00:00Z", "o", ["sd": 100]), ("2026-10-03T12:05:00Z", "o", ["sd": 0]),
            ("2026-10-07T08:48:00Z", "o", ["sd": 100]), ("2026-10-07T08:53:00Z", "o", ["sd": 0]),
            ("2026-10-07T10:00:00Z", "o", ["fh": 5, "sd": 4])])) ?? []
        suite.expect(AgentClaudeAppUsage.limits(from: disagreeing, now: at("2026-10-07T10:05:00Z"))?.windows.last?.resetsAt
                        == at("2026-10-10T12:00:00Z"),
                     "partners that disagree leave the newest of them to place the renewal")
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

    private static func restingMeters(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 2_000_000)
        func window(_ kind: AgentLimitWindow.Kind, _ used: Double, scope: String? = nil,
                    resetsIn: TimeInterval = 3_600) -> AgentLimitWindow {
            AgentLimitWindow(id: kind.rawValue + (scope ?? ""), kind: kind, minutes: kind == .session ? 300 : 10_080,
                             scope: scope, usedPercent: used, resetsAt: now.addingTimeInterval(resetsIn))
        }
        func limits(_ provider: AgentProvider, _ windows: [AgentLimitWindow]) -> AgentLimits {
            AgentLimits(provider: provider, windows: windows, observedAt: now, source: .account)
        }
        func snapshot(_ limits: [AgentProvider: AgentLimits],
                      providers: Set<AgentProvider> = Set(AgentProvider.allCases)) -> AgentUsageSnapshot {
            AgentUsageSummary.snapshot(records: [], limits: limits, live: [], plans: [:], providers: providers, now: now)
        }
        let claude = limits(.claude, [window(.session, 30), window(.weekly, 79), window(.weekly, 99, scope: "Opus")])
        let all = snapshot([.claude: claude])
        func meters(_ snapshot: AgentUsageSnapshot, hidden: Set<AgentProvider> = [],
                    focus: NotchAgentLimitFocus = .mostUsed) -> [NotchAgentRestingMeter] {
            NotchAgentSupport.restingMeters(snapshot, providers: AgentProvider.allCases, hidden: hidden, focus: focus, now: now)
        }
        let shown = meters(all)
        suite.expect(shown.map(\.provider) == [.claude] && shown.first?.window.kind == .weekly
                        && shown.first?.window.usedPercent == 79,
                     "a model's own allowance never stands for the week at rest")
        let renewed = snapshot([.claude: limits(.claude, [window(.session, 90, resetsIn: -60), window(.weekly, 40)])])
        suite.expect(meters(renewed).first?.window.kind == .weekly && meters(renewed).first?.window.usedPercent == 40,
                     "a session that renewed rests as unspent, so the week is the tighter limit")
        suite.expect(meters(all, hidden: [.claude]).isEmpty && meters(snapshot([.claude: claude], providers: [])).isEmpty,
                     "Claude left out at rest, or switched off, never rests")

        // The session is the tighter window until "Limit to show" picks one.
        let mixed = snapshot([.claude: limits(.claude, [window(.session, 70), window(.weekly, 20)])])
        func shownLimits(_ shown: [NotchAgentRestingMeter]) -> [String] {
            shown.map { "\($0.window.kind.rawValue) \(Int($0.window.usedPercent))" }
        }
        suite.expect(shownLimits(meters(mixed)) == ["session 70"] && shownLimits(meters(mixed, focus: .weekly)) == ["weekly 20"]
                        && shownLimits(meters(mixed, focus: .session)) == ["session 70"],
                     "Most used shows the tighter limit, and a focus shows its own: \(shownLimits(meters(mixed)))")
        let weekOnly = snapshot([.claude: limits(.claude, [window(.weekly, 45), window(.session, 99, scope: "Opus")])])
        suite.expect(shownLimits(meters(weekOnly, focus: .session)) == ["weekly 45"],
                     "an account reporting no plan-wide window of the focused kind keeps its tighter one: "
                        + "\(shownLimits(meters(weekOnly, focus: .session)))")
        let tied = snapshot([.claude: limits(.claude, [window(.session, 50, resetsIn: 3_600),
                                                       window(.weekly, 50, resetsIn: 86_400 * 3)])])
        suite.expect(meters(tied).first?.window.kind == .weekly,
                     "of two limits as spent, the one renewing later is the one that stops you longer")
        func sequence(_ layout: NotchAgentRestingLayout, hidden: Set<AgentProvider> = []) -> [AgentProvider] {
            NotchAgentSupport.restingSequence(all, layout: layout, providers: AgentProvider.allCases, hidden: hidden,
                                              focus: .mostUsed, now: now).map(\.provider)
        }
        suite.expect(sequence(.split) == [.claude] && sequence(.cycle) == [.claude] && sequence(.single) == [.claude]
                        && sequence(.cycle, hidden: [.claude]).isEmpty && sequence(.single, hidden: [.claude]).isEmpty,
                     "every layout shows Claude, and none shows it once it is left out")
        let single = NotchAgentSupport.singleRestingMeter(all, hidden: [], focus: .session, now: now)
        let working = NotchAgentSupport.focusedLimit(all.limits[.claude], focus: .session, now: now)
        suite.expect(single?.provider == .claude && single?.window.kind == .session && single?.window.usedPercent == 30
                        && single?.window == working,
                     "Single shows the limit the focus picks, the one the working strip's ring shows")
        suite.expect(NotchAgentSupport.restingCycleIndex(at: Date(timeIntervalSinceReferenceDate: 0), count: 3) == 0
                        && NotchAgentSupport.restingCycleIndex(at: Date(timeIntervalSinceReferenceDate: 4), count: 3) == 1
                        && NotchAgentSupport.restingCycleIndex(at: Date(timeIntervalSinceReferenceDate: 13), count: 3) == 0,
                     "Rotate turns every four seconds on one clock for both wings")

        suite.expect(NotchAgentSupport.restingStatus(usedFraction: 0.799) == .normal
                        && NotchAgentSupport.restingStatus(usedFraction: 0.80) == .low
                        && NotchAgentSupport.restingStatus(usedFraction: 0.95) == .almostOut,
                     "a limit turns yellow at 80% used and red at 95%")

        // The reset time under every number: the clock time within the day,
        // the weekday further off, the date beyond a week.
        let locale = Locale(identifier: "en_US")
        let soon = window(.session, 40, resetsIn: 3_600)
        let soonReset = NotchAgentSupport.restingReset(soon, now: now, locale: locale)
        suite.expect(soonReset.map { !$0.full.contains("M") && $0.full.contains(":") && $0.full == $0.short } == true,
                     "within the day the reset reads as a 24-hour clock time in both lengths: \(String(describing: soonReset))")
        let week = window(.weekly, 40, resetsIn: 86_400 * 3)
        let weekReset = NotchAgentSupport.restingReset(week, now: now, locale: locale)
        let weekDate = now.addingTimeInterval(86_400 * 3)
        suite.expect(weekReset?.full == AgentFormat.resetTime(weekDate, now: now, locale: locale)
                        && weekReset?.short == weekDate.formatted(Date.FormatStyle().weekday(.abbreviated).locale(locale)),
                     "later in the week the reset reads as the weekday and time, or the weekday alone: \(String(describing: weekReset))")
        let far = NotchAgentSupport.restingReset(window(.other, 40, resetsIn: 86_400 * 20), now: now, locale: locale)
        suite.expect(far != nil && far?.full == far?.short,
                     "a reset beyond the week reads as its date in both lengths")
        var estimated = window(.weekly, 40, resetsIn: 86_400 * 3)
        estimated.estimatedResetsAt = now.addingTimeInterval(86_400 * 2)
        let estimate = NotchAgentSupport.restingReset(estimated, now: now, locale: locale)
        suite.expect(estimate?.full.hasPrefix("≈") == true && estimate?.short.hasPrefix("≈") == true,
                     "an estimated reset is marked as one")
        suite.expect(NotchAgentSupport.restingReset(window(.session, 40, resetsIn: -60), now: now, locale: locale) == nil
                        && NotchAgentSupport.restingReset(AgentLimitWindow(id: "s", kind: .session, minutes: 300, scope: nil,
                                                                           usedPercent: 40, resetsAt: nil),
                                                          now: now, locale: locale) == nil,
                     "a reset already past or never reported shows no time")

        let overrides = NotchAgentSupport.parseSimulatedRestingUsage("claude.weekly=0.86, claude.session=1.7,bad,gemini.weekly=1,claude.other=1")
        suite.expect(overrides.count == 1 && overrides[.claude]?[.weekly] == 0.86 && overrides[.claude]?[.session] == 1,
                     "stand-in usage skips anything malformed or unknown and stays within a whole window")
        let simulated = meters(NotchAgentSupport.applyingSimulation(all, [.claude: [.weekly: 0.86]]))
        suite.expect(simulated.first?.window.usedPercent == 86 && all.limits[.claude]?.windows[1].usedPercent == 79,
                     "stand-in usage changes copies of the windows, never the snapshot")
        let domain = "com.vorssaint.tests.notch-agents-resting"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("claude.session=0.9", forKey: DefaultsKey.simulateRestingUsage)
        suite.expect(NotchAgentSupport.simulatedRestingUsage(in: defaults, developer: false).isEmpty
                        && NotchAgentSupport.simulatedRestingUsage(in: defaults, developer: true)[.claude]?[.session] == 0.9,
                     "only the Developer build reads stand-in usage")

        let text = FeatureStrings.notchAgents(.enUS)
        let hour = AgentFormat.resetTime(now.addingTimeInterval(3_600), now: now, locale: locale)
        let seat = NotchAgentRestingMeter(provider: .claude, window: window(.weekly, 100), seat: "s", email: "a@b.c")
        let speech = NotchAgentSupport.restingSpeech([simulated[0], seat], used: false, text: text, locale: locale, now: now)
        suite.expect(speech == "Claude: Week: 14% left, resets \(hour), low; Claude · a@b.c: Week: 0% left, resets \(hour), almost out",
                     "VoiceOver reads each limit shown, when it renews, and a word once it runs low: \(speech)")
        let usedSpeech = NotchAgentSupport.restingSpeech([simulated[0]], used: true, text: text, locale: locale, now: now)
        suite.expect(usedSpeech == "Claude: Week: " + text.usedShare("86%") + ", resets \(hour), low",
                     "VoiceOver says used, though the island no longer draws the word: \(usedSpeech)")
        for (language, _) in LocalizationTests.languages {
            let strings = FeatureStrings.notchAgents(language)
            suite.expect(strings.restingFocusCaption.contains(strings.limitFocus)
                            && strings.restingResets("X").contains("X"),
                         "\(language.rawValue): the At rest caption names its own “Limit to show”, and the reset is spoken")
        }
    }

    /// The year of activity: the ledger's daily values laid out as GitHub
    /// draws contributions.
    private static func activity(_ suite: TestSuite) {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // A Wednesday afternoon.
        let now = AgentTimestamp.parse("2026-09-23T15:00:00Z")!
        let today = utc.startOfDay(for: now)
        func day(_ back: Int) -> Date { utc.date(byAdding: .day, value: -back, to: today)! }
        // Eight active days worth 1 to 8, and one older than the year.
        let values = (0..<8).map { AgentDayValue(start: day($0), cost: Double($0 + 1)) }
            + [AgentDayValue(start: day(400), cost: 100)]
        let grid = NotchAgentSupport.activityGrid(values, now: now, calendar: utc)
        let todayRow = utc.component(.weekday, from: today) - 1
        suite.expect(grid.weeks.count == NotchAgentSupport.activityWeeks && grid.weeks.allSatisfy { $0.count == 7 }
                        && todayRow == 3,
                     "the year is 53 columns of seven days, Sunday on top")
        let last = grid.weeks[NotchAgentSupport.activityWeeks - 1]
        suite.expect(last[todayRow]?.start == today && last[todayRow]?.isToday == true
                        && last[(todayRow + 1)...].allSatisfy { $0 == nil }
                        && last[..<todayRow].allSatisfy { $0 != nil && $0?.isToday == false },
                     "the last column ends with today, and the days after it stay empty")
        suite.expect(grid.weeks[0][0]?.start == day((NotchAgentSupport.activityWeeks - 1) * 7 + todayRow)
                        && utc.component(.weekday, from: grid.weeks[0][0]?.start ?? today) == 1,
                     "the first column starts on a Sunday 52 weeks before today's")
        suite.expect(grid.total == 36 && grid.activeDays == 8,
                     "the year adds what its days were worth and counts the active ones, leaving older days out")
        func level(_ back: Int) -> Int? {
            grid.weeks.joined().compactMap { $0 }.first { $0.start == day(back) }?.level
        }
        suite.expect(level(0) == 1 && level(3) == 2 && level(5) == 3 && level(7) == 4 && level(20) == 0,
                     "each day takes one of five levels by the quartiles of the active days")
        suite.expect((12...14).contains(grid.months.count)
                        && grid.months.allSatisfy { month in
                            month.column == 0 || grid.weeks[month.column - 1][0].map {
                                utc.component(.month, from: $0.start) != utc.component(.month, from: month.start)
                            } == true
                        }
                        && grid.months.allSatisfy { grid.weeks[$0.column][0]?.start == $0.start },
                     "each month is named over the first week that begins in it")
        // A day whose only work has no known price is still a day of work.
        let unknown = NotchAgentSupport.activityGrid(
            values + [AgentDayValue(start: day(30), cost: 0, unpriced: 4), AgentDayValue(start: day(2), cost: 3, unpriced: 1)],
            now: now, calendar: utc)
        let quiet = unknown.weeks.joined().compactMap { $0 }.first { $0.start == day(30) }
        suite.expect(quiet?.level == 1 && quiet?.unpriced == true && quiet?.cost == 0
                        && unknown.activeDays == 9 && unknown.total == 39 && unknown.unpriced
                        && unknown.weeks.joined().compactMap { $0 }.first { $0.start == day(2) }?.unpriced == false
                        && !grid.unpriced && grid.weeks.joined().compactMap { $0 }.allSatisfy { !$0.unpriced },
                     "a day of unpriced work is active at the lowest level, and makes the year's total a minimum")
        let empty = NotchAgentSupport.activityGrid([], now: now, calendar: utc)
        suite.expect(empty.total == 0 && empty.activeDays == 0
                        && empty.weeks.joined().allSatisfy { $0 == nil || $0?.level == 0 },
                     "a year without use is all empty days")

        // The ledger keeps each day's value for the year.
        let records = [record(.claude, now.addingTimeInterval(-3600), cost: 2),
                       record(.claude, now.addingTimeInterval(-86_400 * 2), cost: 5)]
        let snapshot = AgentUsageSummary.snapshot(records: records, limits: [:], live: [], plans: [:],
                                                  providers: [.claude], now: now, calendar: utc)
        let ledger = AgentUsageLedger(url: nil)
        ledger.merge(snapshot, calendar: utc)
        let year = ledger.dailyCosts(providers: [.claude], days: AgentUsageSnapshot.yearDayCount, now: now, calendar: utc)
        suite.expect(AgentUsageSnapshot.yearDayCount == 371 && year.count == 371 && year.last?.start == today
                        && year.first?.start == day(370) && year.last?.cost == 2 && year[year.count - 3].cost == 5
                        && year.reduce(0.0) { $0 + $1.cost } == 7,
                     "the ledger gives the year's days oldest first, ending with today")
        suite.expect(ledger.dailyCosts(providers: [], days: 371, now: now, calendar: utc).allSatisfy { $0.cost == 0 },
                     "without Claude the year holds nothing")
    }

    private static func agentDefaults(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.agent-defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }

        Defaults.migrateNotchAgentsOptIn(in: defaults, domainName: domain)
        Defaults.migrateExistingNotchDefaults(in: defaults, domainName: domain)
        Defaults.migrateNotchAgentsOptIn(in: defaults, domainName: domain)
        let fresh = defaults.persistentDomain(forName: domain) ?? [:]
        suite.expect(fresh[DefaultsKey.notchAgentsEnabled] == nil
                     && Defaults.registeredDefaults[DefaultsKey.notchAgentsEnabled] as? Bool == false
                     && fresh[DefaultsKey.notchInitialExtensionsInstalled] == nil,
                     "fresh profiles keep Agents off on later launches and still install the other island extensions")
        AppFeature.notchAgents.enableOnFirstInstall(in: defaults, savedValues: fresh)
        suite.expect(defaults.bool(forKey: DefaultsKey.notchAgentsEnabled),
                     "explicitly installing Agents enables it on a fresh profile")

        defaults.removePersistentDomain(forName: domain)
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        Defaults.migrateNotchAgentsOptIn(in: defaults, domainName: domain)
        Defaults.migrateExistingNotchDefaults(in: defaults, domainName: domain)
        suite.expect(defaults.persistentDomain(forName: domain)?[DefaultsKey.notchAgentsEnabled] as? Bool == false,
                     "an older island profile keeps the off default supplied by its original migration")

        defaults.removePersistentDomain(forName: domain)
        defaults.set(true, forKey: DefaultsKey.notchDefaultProfileInitialized)
        Defaults.migrateNotchAgentsOptIn(in: defaults, domainName: domain)
        suite.expect(defaults.persistentDomain(forName: domain)?[DefaultsKey.notchAgentsEnabled] as? Bool == true,
                     "an existing profile keeps its formerly implicit on choice")
        defaults.set(false, forKey: DefaultsKey.notchAgentsEnabled)
        Defaults.migrateNotchAgentsOptIn(in: defaults, domainName: domain)
        suite.expect(!defaults.bool(forKey: DefaultsKey.notchAgentsEnabled),
                     "migration never turns Agents back on after a later opt-out")

        for choice in [false, true] {
            defaults.removePersistentDomain(forName: domain)
            defaults.set(true, forKey: DefaultsKey.notchDefaultProfileInitialized)
            defaults.set(choice, forKey: DefaultsKey.notchAgentsEnabled)
            Defaults.migrateNotchAgentsOptIn(in: defaults, domainName: domain)
            suite.expect(defaults.bool(forKey: DefaultsKey.notchAgentsEnabled) == choice,
                         "migration preserves the explicit Agents choice \(choice)")
        }
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchAgentsOptInMigrated),
                     "the local migration marker never travels in settings backups")
    }

    /// Only what the person shows or is alerted about asks for the limits.
    private static func limitUse(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-agent-limits"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for feature in AppFeature.allCases { defaults.set(true, forKey: feature.availabilityKey) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(true, forKey: DefaultsKey.notchAgentsEnabled)
        func used(page: Bool) -> Bool { NotchAgentSupport.limitsInUse(pageShown: page, in: defaults) }
        let alerts = used(page: false)
        defaults.set(false, forKey: DefaultsKey.notchAgentsLimitAlert)
        let unused = !used(page: false)
        let card = used(page: true) && NotchAgentSupport.limitsOnScreen(pageShown: true, in: defaults)
            && !NotchAgentSupport.limitsOnScreen(pageShown: false, in: defaults)
        defaults.set(NotchAgentReadout.limit.rawValue, forKey: DefaultsKey.notchAgentsReadout)
        let readout = used(page: false)
        defaults.set(false, forKey: DefaultsKey.notchAgentsLiveActivity)
        let liveOff = !used(page: false)
        defaults.set(NotchIdleContent.agents.rawValue, forKey: DefaultsKey.notchIdleContent)
        suite.expect(alerts && unused && card && readout && liveOff && used(page: false),
                     "limits are in use for their alerts, a live limit reading, the resting island or the page, and only then")
    }

    private static func preferences(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-agents"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for feature in AppFeature.allCases { defaults.set(true, forKey: feature.availabilityKey) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        suite.expect(!NotchAgentSupport.isEnabled(in: defaults), "installing the island alone leaves AI agents off")
        defaults.set(false, forKey: DefaultsKey.notchAgentsEnabled)
        suite.expect(!NotchSupport.modules(in: defaults).contains(.agents) && !NotchAgentSupport.isEnabled(in: defaults)
                        && !NotchSupport.routes(.agents, in: defaults),
                     "turning AI agents off removes their page and notices")
        defaults.set(true, forKey: DefaultsKey.notchAgentsEnabled)
        suite.expect(NotchSupport.modules(in: defaults).contains(.agents) && NotchAgentSupport.isEnabled(in: defaults)
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

        defaults.set("unknown", forKey: DefaultsKey.notchAgentsLimitFocus)
        suite.expect(NotchAgentSupport.limitFocus(in: defaults) == .mostUsed, "an unknown limit choice shows the most used")
        defaults.set(NotchAgentLimitFocus.weekly.rawValue, forKey: DefaultsKey.notchAgentsLimitFocus)
        suite.expect(NotchAgentSupport.limitFocus(in: defaults) == .weekly, "the chosen limit is kept")
        defaults.removeObject(forKey: DefaultsKey.notchAgentsRestingLayout)
        let missing = NotchAgentSupport.restingLayout(in: defaults)
        defaults.set("all", forKey: DefaultsKey.notchAgentsRestingLayout)
        suite.expect(missing == .single && NotchAgentSupport.restingLayout(in: defaults) == .single,
                     "a missing or unknown resting layout rests as Single")
        defaults.set(NotchAgentRestingLayout.cycle.rawValue, forKey: DefaultsKey.notchAgentsRestingLayout)
        suite.expect(NotchAgentSupport.restingLayout(in: defaults) == .cycle, "the chosen resting layout is kept")
        defaults.set("claude,gemini,unknown", forKey: DefaultsKey.notchAgentsRestingHidden)
        suite.expect(NotchAgentSupport.restingHidden(in: defaults) == [.claude],
                     "agents left out at rest ignore unknown names")
        defaults.set(false, forKey: DefaultsKey.notchAgentsFinishAlert)
        defaults.set(95.0, forKey: DefaultsKey.notchAgentsLimitThreshold)
        defaults.set(-4.0, forKey: DefaultsKey.notchAgentsDailyBudget)
        suite.expect(NotchAgentSupport.finishMinimum(in: defaults) == nil && NotchAgentSupport.limitThreshold(in: defaults) == 95
                        && NotchAgentSupport.dailyBudget(in: defaults) == nil,
                     "alerts follow their switches and a budget must be positive")

        let keys = [DefaultsKey.notchAgentsEnabled, DefaultsKey.notchAgentsPeriod,
                    DefaultsKey.notchAgentsLimitDisplay, DefaultsKey.notchAgentsLimitFocus, DefaultsKey.notchAgentsLiveActivity, DefaultsKey.notchAgentsReadout,
                    DefaultsKey.notchAgentsFinishAlert, DefaultsKey.notchAgentsFinishMinimum, DefaultsKey.notchAgentsLimitAlert,
                    DefaultsKey.notchAgentsLimitThreshold, DefaultsKey.notchAgentsDailyBudget, DefaultsKey.notchAgentsPriceUpdates,
                    DefaultsKey.notchAgentsRestingLayout, DefaultsKey.notchAgentsRestingHidden]
        suite.expect(keys.allSatisfy { Defaults.registeredDefaults[$0] != nil } && SettingsBackupSupport.exportKeys().isSuperset(of: keys)
                        && Defaults.registeredDefaults[DefaultsKey.notchAgentsEnabled] as? Bool == false
                        && Defaults.registeredDefaults[DefaultsKey.notchAgentsPriceUpdates] as? Bool == true,
                     "AI preferences travel in backups, with Agents opt-in and prices kept current when enabled")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchAgentsRestingSession] == nil
                        && Defaults.registeredDefaults[DefaultsKey.notchAgentsRestingWeekly] == nil,
                     "the resting ring's retired switches are no longer settings")
        let retired = ["notchAgentsClaude", "notchAgentsCodex", "notchAgentsCodexProfiles", "notchAgentsOpenCode",
                       "notchAgentsCopilot", "notchAgentsCardOrder", "notchAgentsHiddenCards"]
        let retiredName = "com.vorssaint.tests.retired-agent-settings.\(UUID().uuidString)"
        let retiredDefaults = UserDefaults(suiteName: retiredName)!
        defer { retiredDefaults.removePersistentDomain(forName: retiredName) }
        for key in retired { retiredDefaults.set(false, forKey: key) }
        retiredDefaults.set(true, forKey: DefaultsKey.notchAgentsEnabled)
        Defaults.removeRetiredAgentSettings(in: retiredDefaults)
        suite.expect(retired.allSatisfy { retiredDefaults.object(forKey: $0) == nil && Defaults.registeredDefaults[$0] == nil }
                        && retiredDefaults.bool(forKey: DefaultsKey.notchAgentsEnabled),
                     "the other agents' switches and accounts and the cards' order go, and the section's own switch stays")
        // Whoever kept only the session ring or the weekly bar keeps that limit.
        for (session, weekly, chosen, expected) in [(true as Bool?, false as Bool?, nil as String?, "session"),
                                                    (false, nil, nil, "weekly"),
                                                    (false, false, nil, "mostUsed"),
                                                    (true, false, "weekly", "weekly"),
                                                    (nil, nil, nil, "mostUsed")] {
            let suiteName = "com.vorssaint.tests.resting-windows.\(UUID().uuidString)"
            let migrated = UserDefaults(suiteName: suiteName)!
            defer { migrated.removePersistentDomain(forName: suiteName) }
            session.map { migrated.set($0, forKey: DefaultsKey.notchAgentsRestingSession) }
            weekly.map { migrated.set($0, forKey: DefaultsKey.notchAgentsRestingWeekly) }
            chosen.map { migrated.set($0, forKey: DefaultsKey.notchAgentsLimitFocus) }
            Defaults.migrateRestingWindows(in: migrated)
            suite.expect(NotchAgentSupport.limitFocus(in: migrated).rawValue == expected
                            && migrated.object(forKey: DefaultsKey.notchAgentsRestingSession) == nil
                            && migrated.object(forKey: DefaultsKey.notchAgentsRestingWeekly) == nil,
                         "session \(String(describing: session)), week \(String(describing: weekly)), chosen "
                            + "\(chosen ?? "none"): the resting ring shows \(expected)")
        }
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.simulateRestingUsage)
                        && Defaults.registeredDefaults[DefaultsKey.simulateRestingUsage] == nil,
                     "the Developer build's stand-in usage never travels in backups")
        suite.expect(NotchAgentSupport.updatesPrices(in: defaults), "prices stay current unless turned off")
        defaults.set(false, forKey: DefaultsKey.notchAgentsPriceUpdates)
        suite.expect(!NotchAgentSupport.updatesPrices(in: defaults), "turning price updates off stops the download")
        suite.expect(AppFeature.notchAgents.group == .dynamicIsland && AppFeature.notchAgents.permissions.isEmpty
                        && AppFeature.availabilityDefaults[AppFeature.notchAgents.availabilityKey] as? Bool == true,
                     "the AI page is a Dynamic Island extension that needs no system permission")

        let spacing = NotchAgentSupport.spacing
        let wide = NotchAgentSupport.pageLayout(width: 600, claudeSeats: nil, claudeUsesAPI: false, live: [])
        suite.expect(wide.limits == NotchAgentSupport.sessionCardHeight && wide.square == (600 - spacing) / 2
                        && wide.activity == NotchAgentSupport.activityHeight(width: 600)
                        && wide.total == wide.limits + wide.square + wide.activity + 2 * spacing,
                     "the page stacks Claude's limits, two square cards side by side and the year's activity")
        suite.expect(NotchAgentSupport.pageLayout(width: 600, claudeSeats: nil, claudeUsesAPI: true, live: []).limits
                        == NotchAgentSupport.splitHeight
                        && NotchAgentSupport.pageLayout(width: 330, claudeSeats: nil, claudeUsesAPI: true, live: []).limits
                        == NotchAgentSupport.stackedSplitHeight,
                     "the API key's spending sits beside the plan's limits, or under them where the island is narrow")
        suite.expect(NotchAgentSupport.seatColumns(3, width: 600) == 3 && NotchAgentSupport.seatColumns(4, width: 500) == 2
                        && NotchAgentSupport.seatColumns(2, width: 330) == 1
                        && NotchAgentSupport.pageLayout(width: 600, claudeSeats: 3, claudeUsesAPI: false, live: []).limits
                        == NotchAgentSupport.seatsBaseHeight + NotchAgentSupport.seatRowHeight
                        && NotchAgentSupport.pageLayout(width: 500, claudeSeats: 4, claudeUsesAPI: false, live: []).limits
                        == NotchAgentSupport.seatsBaseHeight + 2 * NotchAgentSupport.seatRowHeight
                        && NotchAgentSupport.seatsCardHeight(2, width: 330, api: true)
                        == NotchAgentSupport.stackedSeatsBaseHeight + 2 * NotchAgentSupport.stackedSeatHeight
                            + NotchAgentSupport.stackedAPILineHeight,
                     "every seat takes a column while they fit, and they stack where the island is narrow")
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let working = (0..<4).map {
            AgentLiveSession(id: "s-\($0)", provider: .claude, started: started, lastActivity: started,
                             model: "claude-opus-4-1", project: "p\($0)", tokens: AgentTokens(), cost: 0,
                             place: $0 < 2 ? .app : .terminal)
        }
        suite.expect(NotchAgentSupport.sessionRows(place: .app, live: []) == 1
                        && NotchAgentSupport.sessionRows(place: .terminal, live: working) == 2
                        && NotchAgentSupport.sessionGrowth(live: working, stacked: false) == NotchAgentSupport.sessionRowHeight
                        && NotchAgentSupport.sessionGrowth(live: working, stacked: true) == 2 * NotchAgentSupport.sessionRowHeight
                        && NotchAgentSupport.pageLayout(width: 600, claudeSeats: nil, claudeUsesAPI: false, live: working).limits
                        == NotchAgentSupport.sessionCardHeight + NotchAgentSupport.sessionRowHeight,
                     "the limits card grows a row for every session past a slot's first, by both slots where they stack")
        let cell = NotchAgentSupport.activityCell(width: 600)
        suite.expect(cell * CGFloat(NotchAgentSupport.activityWeeks)
                        + NotchAgentSupport.activityGap * CGFloat(NotchAgentSupport.activityWeeks - 1)
                        <= 600 - 24 - NotchAgentSupport.activityLabelWidth + 0.001
                        && NotchAgentSupport.activityHeight(width: 600)
                        == NotchAgentSupport.activityChrome + 7 * cell + 6 * NotchAgentSupport.activityGap,
                     "a year of weeks fills the activity card's width, and the card is as tall as seven days")
        suite.expect(NotchAgentSupport.pageLayout(AgentUsageSnapshot(), width: 600, claudeUsesAPI: false, defaults: defaults) == wide,
                     "the island and the page lay out the same snapshot alike")
        NotchLimitVisibility.set(.claudeAPI, in: .island, shown: false, defaults: defaults)
        suite.expect(NotchAgentSupport.pageLayout(AgentUsageSnapshot(), width: 600, claudeUsesAPI: true, defaults: defaults) == wide,
                     "the API key's spending the island leaves out takes no room")
        suite.expect(NotchAgentCard.allCases == [.limits, .trend, .spend, .activity],
                     "the page's cards are fixed: limits, Trend, Spending and Activity")
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
