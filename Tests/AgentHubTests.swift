// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentHubTests {
    static func run(_ suite: TestSuite) {
        strings(suite)
        addresses(suite)
        refusals(suite)
        listing(suite)
        usage(suite)
        client(suite)
        tiles(suite)
        store(suite)
        lifecycle(suite)
    }

    private static let hubURL = "https://hub.example.net:8317"

    private static func strings(_ suite: TestSuite) {
        // The app speaks to the person formally in Russian and Ukrainian.
        let informal: [AppLanguage: String] = [
            .ru: #"(?i)\b(выбери|войди|обнови|попробуй|ты|тебе|тебя|твой|твоя|добавь|задай)\b"#,
            .uk: #"(?i)\b(вибери|увійди|онови|спробуй|ти|тобі|тебе|твій|твоя|додай|задай)\b"#]
        for (language, pattern) in informal {
            let text = Mirror(reflecting: FeatureStrings.agentHubs(language)).children.compactMap { $0.value as? String }
            suite.expect(!text.isEmpty && text.allSatisfy { $0.range(of: pattern, options: .regularExpression) == nil },
                         "hub text uses the formal register in \(language.rawValue)")
        }
        for language in AppLanguage.allCases {
            let text = FeatureStrings.agentHubs(language)
            let values = Mirror(reflecting: text).children.compactMap { $0.value as? String }
            suite.expect(values.allSatisfy { !$0.isEmpty } && text.state(.failed(status: 502)).contains("502")
                            && text.state(.failed(status: 0)) == text.cardFailed,
                         "hub text is complete in \(language.rawValue) and names a hub's HTTP status")
        }
    }

    private static func addresses(_ suite: TestSuite) {
        suite.expect(AgentHub.normalizedURL("hub.example.net:8317") == hubURL
                        && AgentHub.normalizedURL("  HTTPS://Hub.Example.NET:8317/management.html?x=1 ") == hubURL
                        && AgentHub.normalizedURL("http://192.168.1.10:8317/v0/management") == "http://192.168.1.10:8317"
                        && AgentHub.normalizedURL("https://hub.example.net") == "https://hub.example.net",
                     "a hub address keeps its scheme, host and port, with https when none is typed")
        suite.expect(["", "ftp://hub.example.net", "https://user:secret@hub.example.net", "https://"].allSatisfy {
                        AgentHub.normalizedURL($0) == nil },
                     "an address with another scheme, a sign-in or no host is refused")
        suite.expect(AgentHub.normalizedKey(" abc123\n") == "abc123" && AgentHub.normalizedKey("") == nil
                        && AgentHub.normalizedKey("two words") == nil && AgentHub.normalizedKey("line\nbreak") == nil,
                     "a pasted key loses its surrounding space but must be one printable word")
        let hub = AgentHub(url: hubURL, label: "", key: "k")
        suite.expect(hub.name == "hub.example.net" && AgentHub(url: hubURL, label: "Home", key: "k").name == "Home"
                        && hub.management("auth-files")?.absoluteString == hubURL + "/v0/management/auth-files",
                     "a hub without a name shows its host, and management calls go to its root")
    }

    private static func body(_ json: String) -> Data { Data(json.utf8) }

    private static func refusals(_ suite: TestSuite) {
        let cases: [(Int, String, AgentHubState)] = [
            (401, #"{"error":"invalid management key"}"#, .wrongKey),
            (401, #"{"error":"missing management key"}"#, .wrongKey),
            (403, #"{"error":"IP banned due to too many failed attempts. Try again in 29m0s"}"#, .blocked),
            (403, #"{"error":"remote management disabled"}"#, .remoteDisabled),
            (403, #"{"error":"remote management key not set"}"#, .managementOff),
            (404, "", .managementOff),
            (403, #"{"error":"forbidden"}"#, .failed(status: 403)),
            (500, "oops", .failed(status: 500))]
        suite.expect(cases.allSatisfy { AgentHubParser.state(status: $0.0, body: body($0.1)) == $0.2 },
                     "each management refusal CLIProxyAPI words maps to its own fix")
        suite.expect([AgentHubState.wrongKey, .blocked, .remoteDisabled, .managementOff, .insecure].allSatisfy(\.refusesHub)
                        && ![AgentHubState.unreachable, .failed(status: 500), .ready(accounts: 1), .checking]
                            .contains(where: \.refusesHub),
                     "only a refusal of the key or this Mac stops the rest of a reading")
    }

    private static let listingBody = #"""
    {"files":[
      {"auth_index":"c2","provider":"codex","type":"codex","account_type":"oauth","email":"b@example.com","label":"b@example.com",
       "name":"codex-b.json","disabled":false,"id_token":{"chatgpt_account_id":"ws-1","plan_type":"pro"}},
      {"auth_index":"a1","provider":"claude","type":"claude","account_type":"oauth","email":"a@example.com","label":"",
       "name":"claude-a.json","disabled":false},
      {"auth_index":"x9","provider":"claude","account_type":"oauth","email":"off@example.com","disabled":true},
      {"auth_index":"k1","provider":"claude","account_type":"api_key","label":"Key"},
      {"auth_index":"g1","provider":"gemini","account_type":"oauth","email":"g@example.com"},
      {"auth_index":"a1","provider":"claude","account_type":"oauth","email":"dup@example.com"},
      {"auth_index":7,"type":"claude","name":"claude-file.json"}
    ]}
    """#

    private static func listing(_ suite: TestSuite) {
        let accounts = AgentHubParser.accounts(body(listingBody), hub: hubURL) ?? []
        suite.expect(accounts.map(\.index) == ["a1", "7", "c2"] && accounts.map(\.provider) == [.claude, .claude, .codex],
                     "only enabled Claude and Codex sign-ins are read, each once, Claude first")
        suite.expect(accounts.map(\.name) == ["a@example.com", "claude-file", "b@example.com"],
                     "an account shows the hub's label, else its email, else its file name")
        suite.expect(accounts[2].chatGPTAccount == "ws-1" && accounts[0].chatGPTAccount == nil
                        && Set(accounts.map(\.id)).count == 3 && accounts.allSatisfy { $0.id.hasPrefix("hub." + hubURL) },
                     "a Codex account keeps its workspace, and every card has an id of its own")
        suite.expect(AgentHubParser.accounts(body(#"{"files":{}}"#), hub: hubURL) == nil
                        && AgentHubParser.accounts(body("[]"), hub: hubURL) == nil
                        && AgentHubParser.accounts(body(#"{"files":[]}"#), hub: hubURL) == [],
                     "a listing in another shape is not mistaken for an empty hub")
    }

    private static func usage(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        // Anthropic's answer while no session window is open, with its
        // microsecond renewal times.
        let claude = AgentHubParser.claudeLimits(body(#"""
            {"five_hour":null,"seven_day":{"utilization":63.0,"resets_at":"2026-11-23T16:00:00.069458+00:00"},
             "limits":[{"kind":"weekly_all","percent":63}]}
            """#), observed: now)
        suite.expect(claude?.windows.count == 1 && claude?.windows.first?.kind == .weekly
                        && claude?.windows.first?.usedPercent == 63
                        && claude?.windows.first?.resetsAt.map { abs($0.timeIntervalSince1970 - 1_795_449_600) < 1 } == true
                        && claude?.provider == .claude && claude?.observedAt == now,
                     "a Claude account's weekly window is read from Anthropic's usage answer")
        let session = AgentHubParser.claudeLimits(body(#"""
            {"five_hour":{"utilization":12,"resets_at":"2026-11-18T14:00:00Z"},"seven_day":{"utilization":40,"resets_at":null}}
            """#), observed: now)
        suite.expect(session?.windows.map(\.kind) == [.session, .weekly] && session?.windows.first?.usedPercent == 12,
                     "a Claude account's session window comes first")
        suite.expect(AgentHubParser.claudeLimits(body(#"{"five_hour":null,"seven_day":null}"#), observed: now) == nil
                        && AgentHubParser.claudeLimits(body("not json"), observed: now) == nil,
                     "an answer without windows is no reading")

        let codex = AgentHubParser.codexLimits(body(#"""
            {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":604800,
             "reset_after_seconds":467327,"reset_at":1795345789},"secondary_window":null}}
            """#), observed: now)
        suite.expect(codex?.limits.windows.count == 1 && codex?.limits.windows.first?.kind == .weekly
                        && codex?.limits.windows.first?.minutes == 10_080 && codex?.limits.windows.first?.usedPercent == 8
                        && codex?.limits.windows.first?.resetsAt == Date(timeIntervalSince1970: 1_795_345_789)
                        && codex?.plan == AgentPlans.codex(planType: "pro")?.name,
                     "a Codex account with only a weekly window reads it by its length, not its slot")
        let pair = AgentHubParser.codexLimits(body(#"""
            {"rate_limit":{"primary_window":{"used_percent":30,"limit_window_seconds":18000,"reset_after_seconds":600},
             "secondary_window":{"used_percent":55,"limit_window_seconds":604800,"reset_at":1795345789}}}
            """#), observed: now)
        suite.expect(pair?.limits.windows.map(\.kind) == [.session, .weekly]
                        && pair?.limits.windows.first?.resetsAt == now.addingTimeInterval(600) && pair?.plan == nil,
                     "a renewal given only as a delay counts from the reading")
        let business = AgentHubParser.codexLimits(body(#"""
            {"plan_type":"self_serve_business_prolite","rate_limit":{"primary_window":{"used_percent":100,
             "limit_window_seconds":604800,"reset_at":1795345789}}}
            """#), observed: now)
        suite.expect(business?.limits.windows.count == 1 && business?.plan == nil,
                     "a plan type Vorssaint does not know shows no chip rather than its raw name")
        suite.expect(AgentHubParser.codexLimits(body(#"{"rate_limit":null}"#), observed: now) == nil
                        && AgentHubParser.codexLimits(body(#"{"rate_limit":{"primary_window":null}}"#), observed: now) == nil,
                     "a Codex answer without windows is no reading")
        suite.expect(AgentHubParser.proxied(body(#"{"status_code":200,"header":{},"body":"{\"a\":1}"}"#))?.status == 200
                        && AgentHubParser.proxied(body(#"{"error":"x"}"#)) == nil,
                     "the provider's answer is unwrapped from the hub's api-call")
    }

    /// A scripted hub. It answers the listing and each account's proxied
    /// usage call, and records what it was sent.
    private final class FakeHub: @unchecked Sendable {
        private let lock = NSLock()
        private var log: [(path: String, key: String?, body: [String: Any])] = []
        let listing: (Int, String)
        let usage: [String: (Int, String)]

        init(listing: (Int, String), usage: [String: (Int, String)] = [:]) {
            self.listing = listing
            self.usage = usage
        }

        var requests: [(path: String, key: String?, body: [String: Any])] { lock.withLock { log } }

        func send(_ request: URLRequest, _ key: String) async -> AgentHubClient.Outcome {
            let body = request.httpBody.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
            lock.withLock { log.append((request.url?.path ?? "", key, body)) }
            if request.url?.path == "/v0/management/auth-files" {
                return .success(.init(status: listing.0, body: Data(listing.1.utf8)))
            }
            guard let index = body["auth_index"] as? String, let answer = usage[index] else {
                return .success(.init(status: 500, body: Data()))
            }
            return .success(.init(status: answer.0, body: Data(answer.1.utf8)))
        }
    }

    private final class Box<T>: @unchecked Sendable {
        var value: T?
    }

    private static func blocking<T>(_ body: @escaping @Sendable () async -> T) -> T? {
        let box = Box<T>()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.value = await body()
            done.signal()
        }
        return done.wait(timeout: .now() + 5) == .success ? box.value : nil
    }

    private static func proxied(_ status: Int, _ json: String) -> (Int, String) {
        let wrapped = try? JSONSerialization.data(withJSONObject: ["status_code": status, "header": [:], "body": json])
        return (200, String(data: wrapped ?? Data(), encoding: .utf8) ?? "")
    }

    private static func client(_ suite: TestSuite) {
        let hub = AgentHub(url: hubURL, label: "", key: "secret-key")
        let fake = FakeHub(listing: (200, listingBody), usage: [
            "a1": proxied(200, #"{"seven_day":{"utilization":20,"resets_at":"2030-01-01T00:00:00Z"}}"#),
            "7": proxied(500, "upstream"),
            "c2": proxied(401, #"{"error":"token expired"}"#)])
        let reading = blocking { await AgentHubClient.read(hub, send: { await fake.send($0, $1) }) }
        let accounts = reading?.accounts ?? []
        suite.expect(reading?.state == .ready(accounts: 3) && accounts.count == 3
                        && accounts[0].limits?.windows.first?.usedPercent == 20 && accounts[0].failure == nil
                        && accounts[1].failure == .unavailable && accounts[1].limits == nil
                        && accounts[2].failure == .signIn,
                     "each account's reading or failure stays its own")
        let calls = fake.requests.filter { $0.path == "/v0/management/api-call" }
        let codex = calls.first { $0.body["auth_index"] as? String == "c2" }
        let header = codex?.body["header"] as? [String: String]
        suite.expect(fake.requests.allSatisfy { $0.key == "secret-key" } && calls.count == 3
                        && header?["Authorization"] == "Bearer $TOKEN$" && header?["Chatgpt-Account-Id"] == "ws-1"
                        && codex?.body["url"] as? String == AgentHubClient.codexUsage
                        && calls.first { $0.body["auth_index"] as? String == "a1" }?.body["url"] as? String
                            == AgentHubClient.claudeUsage,
                     "the hub puts each account's own token in the provider call, and the Mac sends only the hub's key")

        let wrongKey = FakeHub(listing: (401, #"{"error":"invalid management key"}"#))
        let refused = blocking { await AgentHubClient.read(hub, send: { await wrongKey.send($0, $1) }) }
        suite.expect(refused == AgentHubClient.Reading(state: .wrongKey, accounts: nil) && wrongKey.requests.count == 1,
                     "a refused key ends the reading at the listing")

        // Ten accounts whose usage calls the hub refuses as a wrong key, as
        // when the key is replaced on the hub after the listing.
        let many = (0..<10).map { #"{"auth_index":"n\#($0)","provider":"claude","email":"n\#($0)@example.com"}"# }
        let revoked = FakeHub(listing: (200, #"{"files":["# + many.joined(separator: ",") + "]}"),
                              usage: Dictionary(uniqueKeysWithValues: (0..<10).map {
                                  ("n\($0)", (401, #"{"error":"invalid management key"}"#)) }))
        let stopped = blocking { await AgentHubClient.read(hub, send: { await revoked.send($0, $1) }) }
        suite.expect(stopped == AgentHubClient.Reading(state: .wrongKey, accounts: nil)
                        && revoked.requests.count <= 1 + AgentHubClient.concurrency,
                     "a key refused mid-reading sends no further batch, staying under the hub's ban of five")

        // A reading stopped while the hub answers still sees its 401, at the
        // listing or at an account. The fake gives up when its own task is
        // cancelled, as URLSession does.
        let listing = Data(#"{"files":[{"auth_index":"a1","provider":"claude","email":"a@example.com"}]}"#.utf8)
        for slowPath in ["/v0/management/auth-files", "/v0/management/api-call"] {
            let slow: AgentHubClient.Sender = { request, _ in
                if request.url?.path == slowPath {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if Task.isCancelled { return .failure(.unreachable) }
                    return .success(.init(status: 401, body: Data(#"{"error":"invalid management key"}"#.utf8)))
                }
                return .success(.init(status: 200, body: listing))
            }
            let interrupted = blocking { () async -> AgentHubClient.Reading in
                let reading = Task { await AgentHubClient.read(hub, send: slow) }
                try? await Task.sleep(nanoseconds: 50_000_000)
                reading.cancel()
                return await reading.value
            }
            suite.expect(interrupted?.state == .wrongKey && interrupted?.accounts == nil,
                         "a wrong key the hub answers after the reading stopped is still seen at \(slowPath)")
        }

        let untouched = FakeHub(listing: (200, listingBody))
        let early = blocking { () async -> AgentHubClient.Reading in
            await Task { () async -> AgentHubClient.Reading in
                withUnsafeCurrentTask { $0?.cancel() }
                return await AgentHubClient.read(hub, send: { await untouched.send($0, $1) })
            }.value
        }
        suite.expect(early == AgentHubClient.Reading(state: .checking, accounts: nil) && untouched.requests.isEmpty,
                     "a reading stopped before it began sends nothing")

        let offline: AgentHubClient.Sender = { _, _ in .failure(.unreachable) }
        suite.expect(blocking { await AgentHubClient.read(hub, send: offline) }
                        == AgentHubClient.Reading(state: .unreachable, accounts: nil),
                     "an unreachable hub lists nothing")
    }

    private static func account(_ index: String, _ provider: AgentProvider) -> AgentHubAccount {
        AgentHubAccount(hub: hubURL, index: index, provider: provider, name: index, chatGPTAccount: nil)
    }

    private static func tiles(_ suite: TestSuite) {
        let hub = [account("a", .claude), account("b", .codex), account("c", .codex)]
        let plain = NotchAgentSupport.tiles(cards: [.limits, .resets], providers: [.claude, .codex, .opencode], hubAccounts: hub)
        suite.expect(plain.map(\.accountID) == [hub[0].id, hub[1].id, hub[2].id, nil, nil]
                        && plain.map(\.provider) == [.claude, .codex, .codex, .opencode, .codex]
                        && plain.last?.namesDefaultAccount == true && Set(plain.map(\.id)).count == 5,
                     "a hub's accounts take the place of each agent's default card, and the Resets card names its account")
        let ids = [UUID().uuidString]
        let added = NotchAgentSupport.tiles(cards: [.limits], providers: [.claude, .codex], codexAccounts: ids,
                                            claudeAccount: "profile", hubAccounts: hub)
        suite.expect(added.map(\.accountID) == ["profile", hub[0].id, ids[0], hub[1].id, hub[2].id],
                     "accounts added on this Mac keep their cards, and the hub's follow them")
        suite.expect(NotchAgentSupport.tiles(cards: [.limits], providers: [.codex], hubAccounts: [hub[0]])
                        == NotchAgentSupport.tiles(cards: [.limits], providers: [.codex]),
                     "a hub's Claude accounts leave Codex's default card alone")

        let domain = "com.vorssaint.tests.agent-hubs.tiles." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(false, forKey: DefaultsKey.notchAgentsCodex)
        suite.expect(NotchAgentSupport.shownHubProviders(in: defaults) == [.claude],
                     "an agent that is off shows no hub account")
        defaults.set(NotchAgentCard.limits.rawValue, forKey: DefaultsKey.notchAgentsHiddenCards)
        suite.expect(NotchAgentSupport.shownHubProviders(in: defaults).isEmpty
                        && !NotchAgentSupport.showsHubAccounts(in: defaults),
                     "a hidden Limits card hides every hub account")
    }

    private static func store(_ suite: TestSuite) {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("agent-hubs-" + UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        let hubs = [AgentHub(url: hubURL, label: "Home", key: "secret"),
                    AgentHub(url: "http://192.168.1.10:8317", label: "", key: "other")]
        let file = root.appendingPathComponent("agent-hubs.json")
        let saved = AgentHubStore.save(hubs, to: root)
        let mode = (try? manager.attributesOfItem(atPath: file.path))?[.posixPermissions] as? NSNumber
        suite.expect(saved && AgentHubStore.load(from: root) == hubs && mode?.intValue == 0o600,
                     "hubs and their keys are kept in an owner-only file")
        let tampered = #"[{"url":"https://hub.example.net:8317/x","label":"","key":"k"},"#
            + #"{"url":"https://ok.example.net","label":"","key":"two words"},"#
            + #"{"url":"https://ok.example.net","label":"","key":"fine"},{"url":"https://ok.example.net","label":"","key":"again"}]"#
        try? Data(tampered.utf8).write(to: file)
        suite.expect(AgentHubStore.load(from: root) == [AgentHub(url: "https://ok.example.net", label: "", key: "fine")],
                     "a hand-edited file keeps only well-formed hubs, each address once")
        suite.expect(AgentHubStore.save([], to: root) && !manager.fileExists(atPath: file.path)
                        && AgentHubStore.load(from: root).isEmpty,
                     "removing the last hub removes the file and its key")
    }

    private static func wait(until condition: () -> Bool) {
        let end = Date().addingTimeInterval(3)
        while !condition() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

    private final class Reader: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var next: AgentHubClient.Reading
        var delay: UInt64 = 0
        /// As when the hub already answered: cancellation changes nothing.
        var ignoresCancellation = false

        init(_ next: AgentHubClient.Reading) { self.next = next }

        var reads: Int { lock.withLock { count } }

        func read(_ hub: AgentHub) async -> AgentHubClient.Reading {
            let answer = lock.withLock { () -> AgentHubClient.Reading in
                count += 1
                return next
            }
            if delay > 0, ignoresCancellation {
                let delay = delay
                await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(delay))) { done.resume() }
                }
            } else if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            // The client's answer to a reading stopped before it learned anything.
            if Task.isCancelled && !ignoresCancellation { return .init(state: .checking, accounts: nil) }
            return answer
        }
    }

    private static func lifecycle(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.agent-hubs." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for feature in AppFeature.allCases { defaults.set(true, forKey: feature.availabilityKey) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(true, forKey: DefaultsKey.notchAgentsEnabled)

        let now = Date()
        var claude = account("a", .claude)
        claude.limits = AgentLimits(provider: .claude, windows: [
            AgentLimitWindow(id: "claude.sd", kind: .weekly, minutes: 10_080, scope: nil, usedPercent: 40,
                             resetsAt: now.addingTimeInterval(86_400))], observedAt: now, source: .account)
        let reader = Reader(.init(state: .ready(accounts: 1), accounts: [claude]))
        var saved: [AgentHub] = [AgentHub(url: hubURL, label: "", key: "secret")]
        let service = AgentHubLimitsService(defaults: defaults, reader: { await reader.read($0) }, load: { saved },
                                            store: { saved = $0; return true })
        service.synchronize()
        suite.expect(service.hubs.count == 1 && reader.reads == 0 && service.timer == nil,
                     "saved hubs load without being asked while the page is closed")
        service.pageDidAppear()
        wait { service.hubs.first?.state != nil }
        suite.expect(reader.reads == 1 && service.hubs.first?.state == .ready(accounts: 1)
                        && service.accounts.first?.limits?.windows.first?.usedPercent == 40 && service.timer != nil,
                     "opening the page asks a hub once and keeps its timer while it shows")
        service.refresh()
        suite.expect(reader.reads == 1, "a hub asked a moment ago is not asked again")

        // A failed check of one account keeps its last reading.
        var failed = account("a", .claude)
        failed.failure = .unavailable
        reader.next = .init(state: .ready(accounts: 1), accounts: [failed])
        service.refresh(force: true)
        wait { !(service.hubs.first?.checking ?? true) }
        suite.expect(reader.reads == 2 && service.accounts.first?.failure == .unavailable
                        && service.accounts.first?.limits?.windows.first?.usedPercent == 40,
                     "an account whose check failed keeps its last reading and says so")

        reader.next = .init(state: .wrongKey, accounts: nil)
        service.refresh(force: true)
        wait { service.hubs.first?.state == .wrongKey }
        service.refresh(force: true)
        service.refresh(now: now.addingTimeInterval(86_400))
        suite.expect(reader.reads == 3 && service.accounts.count == 1
                        && service.hubs.first?.isDue(at: now.addingTimeInterval(86_400)) == false,
                     "a wrong key is never sent again, even when asked, and the cards keep their readings")

        reader.next = .init(state: .ready(accounts: 1), accounts: [claude])
        suite.expect(service.add(AgentHub(url: hubURL, label: "Home", key: "new-key"))
                        && saved.map(\.key) == ["new-key"] && service.hubs.count == 1,
                     "adding the hub again replaces its key in place")
        wait { service.hubs.first?.state == .ready(accounts: 1) }
        suite.expect(reader.reads == 4, "a hub added again is asked at once")

        // A reading under way when the island goes away stops, and the hub is
        // asked again once the page shows.
        reader.delay = 300_000_000
        service.refresh(force: true)
        service.pause()
        wait { service.hubs.first?.checking == false }
        suite.expect(reader.reads == 5 && service.hubs.first?.attempted == nil
                        && service.hubs.first?.state == .ready(accounts: 1) && service.timer == nil,
                     "pausing stops a reading under way without taking it for news")
        reader.delay = 0

        defaults.set(NotchAgentCard.limits.rawValue, forKey: DefaultsKey.notchAgentsHiddenCards)
        service.pageDidAppear()
        suite.expect(!service.isEnabled && reader.reads == 5 && service.timer == nil,
                     "a hidden Limits card asks no hub")
        defaults.set("", forKey: DefaultsKey.notchAgentsHiddenCards)

        suite.expect(service.remove(id: hubURL) && saved.isEmpty && service.hubs.isEmpty && service.accounts.isEmpty,
                     "removing a hub removes its key and its cards")
        service.pause()
        refusal(suite, defaults: defaults)

        // Five readings settle a status: renewed windows ask sooner, refusals later.
        var status = AgentHubStatus(hub: AgentHub(url: hubURL, label: "", key: "k"))
        status.attempted = now
        status.state = .ready(accounts: 0)
        suite.expect(!status.isDue(at: now.addingTimeInterval(299)) && status.isDue(at: now.addingTimeInterval(300)),
                     "a hub that answered is asked every five minutes")
        var renewing = claude
        renewing.limits?.windows = [AgentLimitWindow(id: "claude.fh", kind: .session, minutes: 300, scope: nil,
                                                     usedPercent: 90, resetsAt: now.addingTimeInterval(30))]
        status.accounts = [renewing]
        suite.expect(status.isDue(at: now.addingTimeInterval(61)), "a window that renewed asks a minute later")
        status.accounts = []
        status.state = .blocked
        suite.expect(!status.isDue(at: now.addingTimeInterval(1_799)) && status.isDue(at: now.addingTimeInterval(1_800)),
                     "a hub that refuses this Mac is asked again after half an hour")
    }

    /// A key the hub refused is never sent again on its own: not by a reading
    /// that was stopped after the hub counted it, nor after the app relaunches.
    private static func refusal(_ suite: TestSuite, defaults: UserDefaults) {
        let reader = Reader(.init(state: .wrongKey, accounts: nil))
        reader.delay = 300_000_000
        reader.ignoresCancellation = true
        var saved = [AgentHub(url: hubURL, label: "", key: "revoked")]
        let service = AgentHubLimitsService(defaults: defaults, reader: { await reader.read($0) }, load: { saved },
                                            store: { saved = $0; return true })
        service.pageDidAppear()
        service.pause()
        service.pageDidAppear()
        wait { service.hubs.first?.checking == false }
        suite.expect(reader.reads == 1, "a reading stopped by the island going away is not started over while it ends")
        service.refresh(force: true)
        service.pageDidAppear()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        suite.expect(reader.reads == 1 && service.hubs.first?.state == .wrongKey && saved.first?.keyRefused == true,
                     "a refusal that arrives after the island went away still stops the key, and is saved")
        service.pause()

        let relaunched = AgentHubLimitsService(defaults: defaults, reader: { await reader.read($0) }, load: { saved },
                                               store: { saved = $0; return true })
        relaunched.pageDidAppear()
        relaunched.refresh(force: true)
        // A reading starts on the main actor a moment later.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        suite.expect(reader.reads == 1 && relaunched.hubs.first?.state == .wrongKey && relaunched.hubs.first?.checking == false,
                     "after a relaunch the refused key is still not sent")
        reader.delay = 0
        reader.next = .init(state: .ready(accounts: 0), accounts: [])
        suite.expect(relaunched.add(AgentHub(url: hubURL, label: "", key: "replacement"))
                        && saved.first?.keyRefused == false, "adding the hub again with a key clears the refusal")
        wait { relaunched.hubs.first?.state == .ready(accounts: 0) }
        suite.expect(reader.reads == 2, "the new key is asked at once")
        relaunched.pause()
        // A refusal that could not be saved is saved at the next sync, and
        // the key is not sent meanwhile.
        let flaky = Reader(.init(state: .wrongKey, accounts: nil))
        var failing = true
        var kept = [AgentHub(url: hubURL, label: "", key: "flaky")]
        let unsaved = AgentHubLimitsService(defaults: defaults, reader: { await flaky.read($0) }, load: { kept },
                                            store: { hubs in
                                                guard !failing else { return false }
                                                kept = hubs
                                                return true })
        unsaved.pageDidAppear()
        wait { unsaved.hubs.first?.state == .wrongKey }
        unsaved.refresh(force: true)
        suite.expect(flaky.reads == 1 && kept.first?.keyRefused == false, "a refusal the file could not take stays in memory")
        failing = false
        unsaved.synchronize()
        suite.expect(kept.first?.keyRefused == true && flaky.reads == 1, "the refusal is saved once the file can take it")
        unsaved.pause()

        let decoded = try? JSONDecoder().decode([AgentHub].self, from: Data(#"[{"url":"https://a.example","label":"","key":"k"}]"#.utf8))
        suite.expect(decoded?.first?.keyRefused == false, "a hub saved without the refusal flag loads as not refused")
    }
}
