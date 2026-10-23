// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchLimitVisibilityTests {
    static func run(_ suite: TestSuite) {
        preferences(suite)
        page(suite)
        lockScreen(suite)
        working(suite)
        strings(suite)
    }

    private static let now = AgentTimestamp.parse("2026-10-23T09:00:00Z")!
    private static let one = "11111111-1111-1111-1111-111111111111"
    private static let two = "22222222-2222-2222-2222-222222222222"
    private static let three = "33333333-3333-3333-3333-333333333333"

    private static func defaults() -> UserDefaults {
        let name = "com.vorssaint.tests.notch-limit-visibility-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private static func limits(_ used: Double) -> AgentLimits {
        AgentLimits(provider: .claude, windows: [AgentLimitWindow(
            id: "claude.fh", kind: .session, minutes: 300, scope: nil, usedPercent: used, resetsAt: nil)],
            observedAt: now, source: .account)
    }

    private static func seat(_ id: String, email: String, used: Double, active: Bool = false) -> ClaudeSeat {
        ClaudeSeat(id: id, directory: "/tmp/.claude-\(email)", account: "acct-" + email, organization: "org",
                   email: email, plan: "Team", limits: limits(used), active: active)
    }

    private static func snapshot() -> AgentUsageSnapshot {
        var snapshot = AgentUsageSnapshot(loaded: true, now: now)
        snapshot.claudeSeats = [seat(one, email: "dexter@caratos.co.in", used: 64, active: true),
                                seat(two, email: "shikhar@caratos.co.in", used: 96),
                                seat(three, email: "hello@caratos.co.in", used: 31)]
        snapshot.limits[.claude] = limits(64)
        snapshot.limits[.codex] = AgentLimits(provider: .codex, windows: [AgentLimitWindow(
            id: "codex.primary", kind: .session, minutes: 300, scope: nil, usedPercent: 20, resetsAt: nil)],
            observedAt: now, source: .account)
        snapshot.seen = [.claude, .codex]
        return snapshot
    }

    private static func preferences(_ suite: TestSuite) {
        let keys = [DefaultsKey.notchAgentsIslandHiddenAccounts, DefaultsKey.notchAgentsLockHiddenAccounts,
                    DefaultsKey.notchAgentsIslandHiddenProfiles, DefaultsKey.notchAgentsLockHiddenProfiles]
        suite.expect(keys.allSatisfy { Defaults.registeredDefaults[$0] as? String == "" },
                     "every visibility preference is registered, everything shown")
        suite.expect(SettingsBackupSupport.machineStateKeys.isSuperset(of: keys.suffix(2))
                        && SettingsBackupSupport.machineStateKeys.isDisjoint(with: keys.prefix(2)),
                     "profile ids stay on this Mac, the Claude API and Codex choices go with a backup")
        let store = defaults()
        suite.expect(NotchLimitPlace.allCases.allSatisfy { place in
            [NotchLimitAccount.claude, .claudeAPI, .codex, .profile(one)].allSatisfy {
                NotchLimitVisibility.shows($0, in: place, defaults: store)
            }
        }, "everything shows until the person turns it off")
        NotchLimitVisibility.set(.profile(one), in: .island, shown: false, defaults: store)
        NotchLimitVisibility.set(.profile(one), in: .island, shown: false, defaults: store)
        NotchLimitVisibility.set(.claudeAPI, in: .lockScreen, shown: false, defaults: store)
        suite.expect(!NotchLimitVisibility.shows(.profile(one), in: .island, defaults: store)
                        && NotchLimitVisibility.shows(.profile(one), in: .lockScreen, defaults: store)
                        && NotchLimitVisibility.shows(.profile(two), in: .island, defaults: store)
                        && !NotchLimitVisibility.shows(.claudeAPI, in: .lockScreen, defaults: store)
                        && store.string(forKey: DefaultsKey.notchAgentsIslandHiddenProfiles) == one,
                     "a switch hides one account in one place, saved once")
        suite.expect(NotchLimitVisibility.isChecked(.profile(one), defaults: store), "an account shown somewhere is checked")
        NotchLimitVisibility.set(.profile(one), in: .lockScreen, shown: false, defaults: store)
        suite.expect(!NotchLimitVisibility.isChecked(.profile(one), defaults: store), "an account shown nowhere is not checked")
        NotchLimitVisibility.set(.profile(one), in: .island, shown: true, defaults: store)
        suite.expect(NotchLimitVisibility.shows(.profile(one), in: .island, defaults: store),
                     "turning a switch back on shows the account again")
    }

    private static func page(_ suite: TestSuite) {
        let snapshot = snapshot()
        func tiles(_ store: UserDefaults, api: Bool = true, accounts: [String] = []) -> [NotchAgentTile] {
            NotchAgentSupport.pageTiles(snapshot, providers: [.claude, .codex], codexAccounts: accounts,
                                        claudeUsesAPI: api, defaults: store)
        }
        let store = defaults()
        let all = tiles(store)
        suite.expect(all.first?.seatCount == 3 && all.first?.seatsShowAPI == true,
                     "with every account on, the seats' card shows all three seats and the API key's figures")
        suite.expect(all == NotchAgentSupport.tiles(cards: NotchAgentSupport.cards(in: store, claudeSeats: true),
                                                    providers: [.claude, .codex], claudeUsesAPI: true, claudeSeats: 3),
                     "the page's tiles are the layout's, so the page and its height agree")
        NotchLimitVisibility.set(.profile(two), in: .island, shown: false, defaults: store)
        suite.expect(tiles(store).first?.seatCount == 2
                        && NotchLimitVisibility.seats(snapshot, in: .island, defaults: store).map(\.id) == [one, three],
                     "a hidden seat leaves the card, the others keep their order")
        NotchLimitVisibility.set(.profile(one), in: .island, shown: false, defaults: store)
        NotchLimitVisibility.set(.profile(three), in: .island, shown: false, defaults: store)
        suite.expect(tiles(store).first?.seatCount == 0 && tiles(store).first?.claudeSeats == true,
                     "with no seat on, the API key's figures keep the card's header")
        NotchLimitVisibility.set(.claudeAPI, in: .island, shown: false, defaults: store)
        let bare = tiles(store)
        suite.expect(!bare.contains { $0.provider == .claude }
                        && NotchAgentSupport.rows(bare, width: 600).first?.map(\.provider) == [.codex, nil],
                     "with nothing of Claude's on the card goes, and Codex pairs with the next card")
        NotchLimitVisibility.set(.codex, in: .island, shown: false, defaults: store)
        suite.expect(!tiles(store).contains { $0.card == .limits }, "a hidden Codex leaves no limits card")
        let homes = defaults()
        NotchLimitVisibility.set(.profile("work"), in: .island, shown: false, defaults: homes)
        suite.expect(tiles(homes, accounts: ["personal", "work"]).compactMap(\.accountID) == ["personal"]
                        && !tiles(homes, accounts: ["work"]).contains { $0.provider == .codex && $0.card == .limits },
                     "an added Codex home the island leaves out has no card, and none shown leaves Codex out")

        var plain = AgentUsageSnapshot(loaded: true, now: now)
        plain.seen = [.claude]
        let usual = defaults()
        func plainTiles() -> [NotchAgentTile] {
            NotchAgentSupport.pageTiles(plain, providers: [.claude], codexAccounts: [], claudeUsesAPI: true, defaults: usual)
        }
        suite.expect(plainTiles().first?.splitsBilling == true, "without seats the split card stays as it is")
        NotchLimitVisibility.set(.claudeAPI, in: .island, shown: false, defaults: usual)
        suite.expect(plainTiles().first.map { !$0.splitsBilling && !$0.claudeAPI } == true,
                     "hiding the API key leaves the plan's own card")
        NotchLimitVisibility.set(.claudeAPI, in: .island, shown: true, defaults: usual)
        NotchLimitVisibility.set(.claude, in: .island, shown: false, defaults: usual)
        suite.expect(plainTiles().filter { $0.card == .limits }.map(\.claudeAPI) == [true], "hiding the plan leaves the API key's half card")
    }

    private static func lockScreen(_ suite: TestSuite) {
        let store = defaults()
        store.set(ClaudeSeatProfile.encode([ClaudeSeatProfile(id: one, directory: "/tmp/.claude-seat1"),
                                            ClaudeSeatProfile(id: two, directory: "/tmp/.claude-seat2")]),
                  forKey: DefaultsKey.notchAgentsClaudeSeats)
        let widgets = NotchLockScreenWidgets.initial
        suite.expect(widgets.leavingOutHiddenLimits(store) == widgets, "with every account on, the lock screen is unchanged")
        NotchLimitVisibility.set(.profile(one), in: .lockScreen, shown: false, defaults: store)
        suite.expect(widgets.leavingOutHiddenLimits(store).shown(in: .ai).contains(.claude),
                     "one seat left on keeps Claude's widget")
        NotchLimitVisibility.set(.profile(two), in: .lockScreen, shown: false, defaults: store)
        NotchLimitVisibility.set(.codex, in: .lockScreen, shown: false, defaults: store)
        let left = widgets.leavingOutHiddenLimits(store)
        suite.expect(!left.shown(in: .ai).contains(.claude) && !left.shown(in: .ai).contains(.codex)
                        && left.order == widgets.order,
                     "with no seat on Claude's widget drops out, Codex's too, and the order is kept")
        let snapshot = snapshot()
        let lock = defaults()
        NotchLimitVisibility.set(.profile(one), in: .lockScreen, shown: false, defaults: lock)
        let shown = NotchLimitVisibility.applying(snapshot, in: .lockScreen, defaults: lock)
        suite.expect(shown.claudeSeats.map(\.id) == [two, three] && shown.limits[.claude]?.windows.first?.usedPercent == 96
                        && NotchLimitVisibility.applying(snapshot, in: .island, defaults: lock).claudeSeats.count == 3,
                     "each place keeps its own seats, and Claude's one reading is the first seat it shows")
        let usual = defaults()
        NotchLimitVisibility.set(.claude, in: .lockScreen, shown: false, defaults: usual)
        suite.expect(!widgets.leavingOutHiddenLimits(usual).shown(in: .ai).contains(.claude),
                     "without seats, hiding Claude drops its widget")
    }

    private static func working(_ suite: TestSuite) {
        var snapshot = snapshot()
        let session = AgentLiveSession(id: "/p/s1.jsonl", provider: .claude, started: now, lastActivity: now, model: "",
                                       project: "", tokens: AgentTokens(), cost: 0, place: .app)
        snapshot.live = [session]
        snapshot.claudeLiveSeats[session.id] = two
        let store = defaults()
        suite.expect(NotchAgentSupport.workingLimits(snapshot, provider: .claude, defaults: store)?
                        .windows.first?.usedPercent == 96, "a working session shows its seat's ring")
        NotchLimitVisibility.set(.profile(two), in: .island, shown: false, defaults: store)
        suite.expect(NotchAgentSupport.workingLimits(snapshot, provider: .claude, defaults: store) == nil,
                     "a session under a seat the island leaves out shows no ring, so its time shows")
        let rest = NotchAgentSupport.restingSequence(NotchLimitVisibility.applying(snapshot, in: .island, defaults: store),
                                                     layout: .cycle, providers: AgentProvider.allCases, hidden: [],
                                                     focus: .session, now: now)
        suite.expect(rest.compactMap(\.seat) == [one, three], "a seat the island leaves out leaves the resting rotation")
        NotchLimitVisibility.set(.profile(one), in: .island, shown: false, defaults: store)
        let single = NotchAgentSupport.restingSequence(NotchLimitVisibility.applying(snapshot, in: .island, defaults: store),
                                                       layout: .single, providers: [.claude], hidden: [],
                                                       focus: .session, now: now)
        suite.expect(single.first?.seat == three, "Single falls back to a seat the island shows")
    }

    private static func strings(_ suite: TestSuite) {
        let english = Mirror(reflecting: FeatureStrings.limitVisibility(.enUS)).children.count
        for language in AppLanguage.allCases {
            let text = FeatureStrings.limitVisibility(language)
            let values = Mirror(reflecting: text).children.compactMap { $0.value as? String }
            suite.expect(values.count == english && values.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                         "every limit visibility string is written in \(language.rawValue)")
            suite.expect(text.seatDetail("~/x").contains("~/x") && text.creditsLeft("$9").contains("$9"),
                         "the formatted strings keep their value in \(language.rawValue)")
        }
    }
}
