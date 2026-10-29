// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum CodexAccountLimitsTests {
    static func run(_ suite: TestSuite) {
        strings(suite)
        rules(suite)
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("codex-accounts-" + UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let profiles = try [".codex-personal", ".codex-work"].map { name -> CodexAccountProfile in
                let directory = root.appendingPathComponent(name)
                try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try Data().write(to: directory.appendingPathComponent("config.toml"))
                return CodexAccountProfile(id: UUID().uuidString, name: name, directory: directory.path)
            }
            try boundaries(suite, root: root, profiles: profiles)
            try conversations(suite, root: root, profiles: profiles)
            lifecycle(suite, profiles: profiles)
        } catch { suite.expect(false, "Codex account contract: \(error)") }
    }

    private static func strings(_ suite: TestSuite) {
        // The app speaks to the person formally in Russian and Ukrainian.
        let informal: [AppLanguage: String] = [
            .ru: #"(?i)\b(выбери|войди|обнови|попробуй|ты|тебе|тебя|твой|твоя)\b"#,
            .uk: #"(?i)\b(вибери|увійди|онови|спробуй|ти|тобі|тебе|твій|твоя)\b"#]
        for (language, pattern) in informal {
            let text = Mirror(reflecting: FeatureStrings.codexAccounts(language)).children.compactMap { $0.value as? String }
            suite.expect(!text.isEmpty && text.allSatisfy { $0.range(of: pattern, options: .regularExpression) == nil },
                         "Codex account text uses the formal register in \(language.rawValue)")
        }
    }

    private static func rules(_ suite: TestSuite) {
        suite.expect(CodexAccountUsageReader.interval(after: nil, renewed: false) == 300
                        && CodexAccountUsageReader.interval(after: nil, renewed: true) == 60
                        && CodexAccountUsageReader.interval(after: .unavailable, renewed: false) == 300
                        && [CodexAccountUsageError.missingCLI, .needsSignIn, .outdated, .invalidProfile].allSatisfy {
                            CodexAccountUsageReader.interval(after: $0, renewed: true) == 1_800 },
                     "a Codex account is asked every five minutes, and after a failure only the person can fix every half hour")
        let now = Date()
        func reading(_ provider: AgentProvider, age: TimeInterval, source: AgentLimits.Source) -> AgentLimits {
            AgentLimits(provider: provider, windows: [], observedAt: now.addingTimeInterval(-age), source: source)
        }
        suite.expect(!NotchAgentSupport.limitsAreStale(reading(.codex, age: 31 * 60, source: .sessionLog),
                                                       provider: .codex, account: false, now: now)
                        && !NotchAgentSupport.limitsAreStale(reading(.codex, age: 31 * 60, source: .account),
                                                             provider: .codex, account: false, now: now)
                        && NotchAgentSupport.limitsAreStale(reading(.claude, age: 31 * 60, source: .claudeApp),
                                                            provider: .claude, account: false, now: now)
                        && !NotchAgentSupport.limitsAreStale(reading(.claude, age: 60, source: .account),
                                                             provider: .claude, account: false, now: now),
                     "a default card dims only an old Claude reading, as before Codex accounts")
        suite.expect(NotchAgentSupport.limitsAreStale(reading(.codex, age: 11 * 60, source: .account),
                                                      provider: .codex, account: true, now: now)
                        && !NotchAgentSupport.limitsAreStale(reading(.codex, age: 9 * 60, source: .account),
                                                             provider: .codex, account: true, now: now),
                     "an account card dims a reading that missed its checks")

        let ids = [UUID().uuidString, UUID().uuidString]
        let tiles = NotchAgentSupport.tiles(cards: [.limits, .resets], providers: [.claude, .codex, .opencode], codexAccounts: ids)
        suite.expect(tiles.map(\.accountID) == [nil, ids[0], ids[1], nil, nil]
                        && tiles.map(\.provider) == [.claude, .codex, .codex, .opencode, .codex]
                        && Set(tiles.map(\.id)).count == 5 && tiles.last?.card == .resets,
                     "each Codex account has a card of its own in place of the logs' one, and the Resets card stays")
        suite.expect(NotchAgentSupport.tiles(cards: [.limits, .resets], providers: [.claude, .codex], codexAccounts: [])
                        == NotchAgentSupport.tiles(cards: [.limits, .resets], providers: [.claude, .codex])
                        && NotchAgentSupport.height(of: [tiles[1], tiles[2]]) == NotchAgentSupport.accountCardHeight
                        && NotchAgentSupport.height(of: [tiles[0], tiles[3]]) == NotchAgentSupport.cardHeight,
                     "without accounts the page is unchanged, and a row with an account card makes room for its time")
        suite.expect(tiles.last?.namesDefaultAccount == true
                        && NotchAgentSupport.height(of: [tiles[4]]) == NotchAgentSupport.accountCardHeight,
                     "the Resets card beside accounts makes room for the account it names")
        func notes(windows: Bool, checking: Bool = false, failure: String?) -> (placeholder: String?, caption: String?) {
            NotchAgentSupport.accountNotes(hasWindows: windows, checking: checking, failure: failure, hint: "Refresh",
                                           loading: "Loading", updated: windows ? "Updated" : nil)
        }
        let failedEmpty = notes(windows: false, failure: "Failed"), failedShown = notes(windows: true, failure: "Failed")
        suite.expect(failedEmpty.placeholder == "Failed" && failedEmpty.caption == nil
                        && failedShown.placeholder == nil && failedShown.caption == "Failed"
                        && notes(windows: true, failure: nil).caption == "Updated"
                        && notes(windows: false, checking: true, failure: "Failed").placeholder == "Loading"
                        && notes(windows: false, failure: nil).placeholder == "Refresh",
                     "a failed account card says so once, in place of its windows or under them")
        let home = URL(fileURLWithPath: "/Users/someone")
        suite.expect(CodexAccountProfile.name(for: home.appending(path: ".codex"), defaultName: "Padrão") == "Padrão"
                        && CodexAccountProfile.name(for: home.appending(path: ".codex-work"), defaultName: "Padrão") == "Work"
                        && CodexAccountProfile.name(for: home.appending(path: "accounts/team"), defaultName: "Padrão") == "Team",
                     "an added Codex home is named after its folder, and the usual one in the app's language")
    }

    private static func boundaries(_ suite: TestSuite, root: URL, profiles: [CodexAccountProfile]) throws {
        let manager = FileManager.default
        let first = URL(fileURLWithPath: profiles[0].directory)
        suite.expect(CodexAccountProfile.decode(CodexAccountProfile.encode(profiles)) == profiles,
                     "Codex account names, identifiers and folders survive saving")
        suite.expect(CodexAccountProfile.discover(home: root, defaultName: "Default").map(\.directory) == profiles.map(\.directory)
                        && CodexAccountProfile.discover(home: root, defaultName: "Default").map(\.name) == ["Personal", "Work"],
                     "local Codex homes are found by their folders alone")
        let standard = root.appendingPathComponent(".codex")
        try manager.createDirectory(at: standard, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data().write(to: standard.appendingPathComponent("config.toml"))
        suite.expect(CodexAccountProfile.discover(home: root, defaultName: "Standard").first?.name == "Standard",
                     "the usual .codex home can have a card beside the others")
        let alias = root.appendingPathComponent(".codex-alias")
        try manager.createSymbolicLink(at: alias, withDestinationURL: first)
        let duplicate = CodexAccountProfile(id: UUID().uuidString, name: "Alias", directory: alias.path)
        suite.expect(CodexAccountProfile.decode(CodexAccountProfile.encode([profiles[0], duplicate])).count == 1
                        && CodexAccountProfile.discover(home: root, defaultName: "Default").count == 3,
                     "a link to a Codex home never makes a second card for it")
        for path in ["", "relative", "/", manager.homeDirectoryForCurrentUser.path, root.appendingPathComponent("missing").path] {
            suite.expect(CodexAccountProfile(id: UUID().uuidString, name: "Invalid", directory: path).canonicalDirectory == nil,
                         "an ambiguous or missing Codex home is refused: \(path)")
        }
        try manager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: first.path)
        suite.expect(profiles[0].canonicalDirectory == nil, "a Codex home others can write to is refused")
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: first.path)
        let auth = first.appendingPathComponent("auth.json")
        // Empty, so only its metadata can matter; it holds no sign-in.
        manager.createFile(atPath: auth.path, contents: Data(), attributes: [.posixPermissions: 0o600])
        suite.expect(profiles[0].canonicalDirectory != nil, "a Codex home with a private sign-in file is valid")
        try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: auth.path)
        suite.expect(profiles[0].canonicalDirectory == nil, "a sign-in file others can read is refused")
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: auth.path)
        let linked = URL(fileURLWithPath: profiles[1].directory).appendingPathComponent("auth.json")
        try manager.linkItem(at: auth, to: linked)
        suite.expect(profiles.allSatisfy { $0.canonicalDirectory == nil }, "a hard-linked sign-in cannot make two homes one account")
        try manager.removeItem(at: linked)
        try manager.createSymbolicLink(at: linked, withDestinationURL: auth)
        suite.expect(profiles[1].canonicalDirectory == nil, "a linked sign-in file is refused")
        try manager.removeItem(at: linked)
        try manager.removeItem(at: auth)

        // Homebrew's cask links `codex` to a binary named for its platform;
        // account cards find Codex the way the Resets card does.
        let tools = root.appendingPathComponent("home/.local/bin")
        let cask = root.appendingPathComponent("Caskroom/codex/1.0/codex-aarch64-apple-darwin")
        try manager.createDirectory(at: tools, withIntermediateDirectories: true)
        try manager.createDirectory(at: cask.deletingLastPathComponent(), withIntermediateDirectories: true)
        manager.createFile(atPath: cask.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        try manager.createSymbolicLink(at: tools.appendingPathComponent("codex"), withDestinationURL: cask)
        suite.expect(AgentCodexServer.executable(apps: [], home: root.appendingPathComponent("home"))?.path
                        == tools.appendingPathComponent("codex").path,
                     "a Codex linked to a binary of another name is found")

        let cli = root.appendingPathComponent("codex")
        let overrides = ["CODEX_ACCESS_TOKEN", "CODEX_API_KEY", "OPENAI_API_KEY", "OPENAI_FEDERATION_RULE_ID",
                         "OPENAI_IDENTITY_TOKEN_FILE", "OPENAI_WORKLOAD_IDENTITY_CONTEXT", "CODEX_SQLITE_HOME",
                         "OPENAI_BASE_URL", "NODE_OPTIONS", "ANTHROPIC_API_KEY"]
        var base = Dictionary(uniqueKeysWithValues: overrides.map { ($0, "synthetic") })
        base["HOME"] = root.path; base["CODEX_HOME"] = profiles[1].directory; base["PATH"] = "/untrusted"
        base["HTTPS_PROXY"] = "synthetic-proxy"; base["DO_NOT_TRACK"] = "1"
        let env = CodexAccountUsageReader.environment(directory: first, executable: cli, searchPath: nil, base: base)
        let shell = CodexAccountUsageReader.environment(directory: first, executable: cli, searchPath: "/shell/bin", base: base)
        suite.expect(overrides.allSatisfy { env[$0] == nil } && env["CODEX_HOME"] == first.path
                        && env["HOME"] == root.path && env["HTTPS_PROXY"] == "synthetic-proxy"
                        && env["DO_NOT_TRACK"] == "1" && env["PATH"]?.contains("/untrusted") == false
                        && shell["PATH"]?.contains("/shell/bin") == true,
                     "an account check drops inherited sign-ins, providers and state, and keeps proxies and opt-outs")
        let invalid = CodexAccountProfile(id: "invalid", name: "Bad", directory: first.path)
        let many = (0..<10).map { CodexAccountProfile(id: UUID().uuidString, name: "\($0)", directory: "/profiles/\($0)") }
        suite.expect(CodexAccountProfile.decode(CodexAccountProfile.encode([invalid])).isEmpty
                        && CodexAccountProfile.decode(CodexAccountProfile.encode(many)).count == CodexAccountProfile.maximum
                        && CodexAccountProfile.decode(String(repeating: "x", count: 65_537)).isEmpty,
                     "malformed, oversized and extra saved accounts are bounded")
        let payload: [String: Any] = [SettingsBackupSupport.formatVersionKey: 1,
            SettingsBackupSupport.settingsKey: [DefaultsKey.notchAgentsCodexProfiles: CodexAccountProfile.encode(profiles)]]
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchAgentsCodexProfiles)
                        && SettingsBackupSupport.sanitizedSettings(from: payload)?[DefaultsKey.notchAgentsCodexProfiles] == nil,
                     "neither a settings export nor an import carries Codex account folders")
    }

    /// Plays one server per home, and logs what each is asked there. A
    /// marker file in the home makes it signed out, too old or silent. A
    /// silent one leaves a child holding its output open, as npm's launcher
    /// can, so that output does not end when the server is stopped.
    private static let server = #"""
    #!/bin/sh
    [ "$1" = -c ] && [ "$2" = features.plugins=false ] && [ "$3" = app-server ] || exit 1
    [ "$PWD" = / ] || exit 2
    [ -z "${OPENAI_API_KEY+x}${CODEX_ACCESS_TOKEN+x}${CODEX_SQLITE_HOME+x}" ] || exit 3
    case "$CODEX_HOME" in *.codex-personal) USED=14; WEEK=61; PLAN=plus;; *.codex-work) USED=100; WEEK=41; PLAN=business;; *) exit 4;; esac
    echo $$ > "$CODEX_HOME/server.pid"
    [ -f "$CODEX_HOME/silent" ] && { sleep 30 & echo $! >> "$CODEX_HOME/holder.pid"; }
    while IFS= read -r line; do
        printf '%s\n' "$line" >> "$CODEX_HOME/rpc.log"
        [ -f "$CODEX_HOME/silent" ] && continue
        case "$line" in
            *'"method":"initialize"'*) printf '%s\n' '{"id":1,"result":{}}';;
            *'"method":"initialized"'*) ;;
            *'"method":"account/read"'*)
                case "$line" in *'"refreshToken":false'*) ;; *) exit 5;; esac
                if [ -f "$CODEX_HOME/signed-out" ]; then
                    printf '%s\n' '{"id":2,"result":{"account":{"type":"apiKey"}}}'
                else
                    printf '{"id":2,"result":{"account":{"type":"chatgpt","planType":"%s"}}}\n' "$PLAN"
                fi;;
            *'"method":"account/rateLimits/read"'*)
                if [ -f "$CODEX_HOME/failure" ]; then
                    printf '%s\n' '{"id":3,"error":{"code":-32601,"message":"method not found"}}'
                else
                    printf '{"id":3,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":%s,"windowDurationMins":300,"resetsAt":4102444800},"secondary":{"usedPercent":%s,"windowDurationMins":10080,"resetsAt":4102444800}}}}\n' "$USED" "$WEEK"
                fi;;
            *) exit 6;;
        esac
    done
    """#

    private static func conversations(_ suite: TestSuite, root: URL, profiles: [CodexAccountProfile]) throws {
        let cli = root.appendingPathComponent("codex")
        try server.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        func read(_ profile: CodexAccountProfile, _ cancellation: BoundedProcessCancellation = BoundedProcessCancellation(),
                  timeout: TimeInterval = 3) -> Result<CodexAccountReading, CodexAccountUsageError> {
            CodexAccountUsageReader.read(profile, executable: cli, searchPath: nil, cancellation: cancellation, timeout: timeout)
        }
        let readings = profiles.map { try? read($0).get() }
        suite.expect(readings.map { $0?.limits.windows.first?.usedPercent } == [14, 100]
                        && readings.map { $0?.limits.windows.last?.usedPercent } == [61, 41]
                        && readings.map { $0?.plan } == ["Plus", "Business"],
                     "two Codex homes keep their own plans and limits, with no reset count needed")
        for profile in profiles {
            let log = try String(contentsOf: URL(fileURLWithPath: profile.directory).appendingPathComponent("rpc.log"), encoding: .utf8)
            let methods = log.split(separator: "\n").compactMap {
                ((try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any])?["method"] as? String
            }
            suite.expect(methods == ["initialize", "initialized", "account/read", "account/rateLimits/read"],
                         "an account check asks only for the account and its limits, never for a prompt or a reset")
        }
        let now = Date()
        let windows = [AgentLimitWindow(id: "session", kind: .session, minutes: 300, scope: nil, usedPercent: 14, resetsAt: now),
                       AgentLimitWindow(id: "week", kind: .weekly, minutes: 10_080, scope: nil, usedPercent: 61, resetsAt: now.addingTimeInterval(3600)),
                       AgentLimitWindow(id: "business", kind: .other, minutes: nil, scope: nil, usedPercent: 3, resetsAt: nil)]
        let state = CodexProfileLimitsState(profile: profiles[0], limits: AgentLimits(provider: .codex, windows: windows,
                                                                                      observedAt: now, source: .account))
        suite.expect(state.currentLimits(at: now)?.windows.map(\.usedPercent) == [61, 3],
                     "a renewed window disappears without reading as zero, and an undated allowance stays")
        // A window renewing after the reading asks sooner; one Codex already
        // reported as renewed does not keep asking.
        let renewing = AgentLimits(provider: .codex, windows: [windows[0]], observedAt: now.addingTimeInterval(-30), source: .account)
        let renewed = AgentLimits(provider: .codex, windows: [windows[0]], observedAt: now.addingTimeInterval(30), source: .account)
        let checked = now.addingTimeInterval(-10)
        suite.expect(CodexProfileLimitsState(profile: profiles[0], limits: renewing, attempted: checked).isDue(at: now.addingTimeInterval(55))
                        && !CodexProfileLimitsState(profile: profiles[0], limits: renewed, attempted: checked).isDue(at: now.addingTimeInterval(55))
                        && !CodexProfileLimitsState(profile: profiles[0], limits: renewing, failure: .needsSignIn, attempted: checked)
                            .isDue(at: now.addingTimeInterval(55)),
                     "a window that renews after the reading is asked about a minute later, once")
        let first = URL(fileURLWithPath: profiles[0].directory)
        for (name, expected) in [("signed-out", CodexAccountUsageError.needsSignIn), ("failure", .outdated)] {
            let marker = first.appendingPathComponent(name)
            try Data().write(to: marker)
            suite.expect(read(profiles[0], timeout: 2) == .failure(expected), "\(name) reports what the person can do about it")
            try FileManager.default.removeItem(at: marker)
        }
        try Data().write(to: first.appendingPathComponent("silent"))
        let cancelling = BoundedProcessCancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { cancelling.cancel() }
        let start = Date()
        suite.expect(read(profiles[0], cancelling, timeout: 10) == .failure(.cancelled) && Date().timeIntervalSince(start) < 2,
                     "a cancelled account check stops a silent server without waiting out its deadline")
        let pidText = try String(contentsOf: first.appendingPathComponent("server.pid"), encoding: .utf8)
        if let pid = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            suite.expect(kill(pid, 0) == -1 && errno == ESRCH, "a cancelled account check leaves no server behind")
        }
        let timeoutStart = Date()
        suite.expect(read(profiles[0], timeout: 0.1) == .failure(.unavailable) && Date().timeIntervalSince(timeoutStart) < 2,
                     "an account check ends at its deadline")
        let holders = (try? String(contentsOf: first.appendingPathComponent("holder.pid"), encoding: .utf8)) ?? ""
        for pid in holders.split(separator: "\n").compactMap({ Int32($0) }) { kill(pid, SIGKILL) }
        try FileManager.default.removeItem(at: first.appendingPathComponent("silent"))
    }

    /// Stands in for the Codex tool, one home at a time, and can hold a
    /// check until it is let go or cancelled.
    private final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [(id: String, path: String?)] = []
        private var stopped: [String] = []
        private var holding = false
        private var failures: [String: CodexAccountUsageError] = [:]
        var calls: [String] { lock.withLock { asked.map(\.id) } }
        var paths: [String?] { lock.withLock { asked.map(\.path) } }
        /// The checks that ended because they were cancelled.
        var cancelled: [String] { lock.withLock { stopped } }
        func hold(_ on: Bool) { lock.withLock { holding = on } }
        func fail(_ id: String, _ failure: CodexAccountUsageError?) { lock.withLock { failures[id] = failure } }

        func read(_ profile: CodexAccountProfile, _ path: String?,
                  _ cancellation: BoundedProcessCancellation) -> Result<CodexAccountReading, CodexAccountUsageError> {
            lock.withLock { asked.append((profile.id, path)) }
            let end = Date().addingTimeInterval(3)
            while lock.withLock({ holding }), !cancellation.isCancelled, Date() < end { usleep(5_000) }
            if cancellation.isCancelled {
                lock.withLock { stopped.append(profile.id) }
                return .failure(.cancelled)
            }
            if let failure = lock.withLock({ failures[profile.id] }) { return .failure(failure) }
            let window = AgentLimitWindow(id: "codex.300", kind: .session, minutes: 300, scope: nil, usedPercent: 42,
                                          resetsAt: Date().addingTimeInterval(3600))
            return .success(CodexAccountReading(limits: AgentLimits(provider: .codex, windows: [window], observedAt: Date(),
                                                                    source: .account), plan: "Plus"))
        }
    }

    private static func wait(until condition: () -> Bool) {
        let end = Date().addingTimeInterval(3)
        while !condition() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

    private static func lifecycle(_ suite: TestSuite, profiles: [CodexAccountProfile]) {
        let domain = "com.vorssaint.tests.codex-accounts." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        // The registration domain is shared with other suites, so this one
        // keeps its values in a domain of its own.
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for feature in AppFeature.allCases { defaults.set(true, forKey: feature.availabilityKey) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(true, forKey: DefaultsKey.notchAgentsEnabled)

        let empty = CodexProfileLimitsService(defaults: defaults, reader: Probe().read, loginShellPath: { nil })
        empty.pageDidAppear()
        suite.expect(empty.isEnabled && empty.states.isEmpty && empty.timer == nil,
                     "the page runs no account timer when no account was added")
        empty.pause()

        defaults.set(CodexAccountProfile.encode(profiles), forKey: DefaultsKey.notchAgentsCodexProfiles)
        let probe = Probe()
        let shellLookups = NSLock()
        var lookups = 0
        let service = CodexProfileLimitsService(defaults: defaults, reader: probe.read, loginShellPath: {
            shellLookups.withLock { lookups += 1 }
            return "/shell/bin"
        })
        defer { service.pause() }
        let first = profiles[0].id, second = profiles[1].id
        func state(_ id: String) -> CodexProfileLimitsState? { service.states.first { $0.id == id } }
        func settled() { wait { service.states.allSatisfy { !$0.checking } } }

        service.synchronize(); service.refresh()
        suite.expect(probe.calls.isEmpty && service.states.count == 2 && service.timer == nil,
                     "adding accounts checks none until the page shows them")
        service.pageDidAppear(preview: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        suite.expect(probe.calls.isEmpty && service.timer == nil,
                     "the Settings preview of the page shows account cards without checking them")
        service.refresh(force: true); service.refresh(force: true)
        settled()
        suite.expect(probe.calls == [first, second] && service.states.allSatisfy { $0.limits != nil },
                     "checks asked for by hand run one at a time, once each")
        service.pageDidAppear()
        suite.expect(probe.calls.count == 2 && service.timer != nil,
                     "opening the page reuses fresh readings and keeps checking while it shows")

        probe.hold(true)
        service.refresh(id: first, force: true)
        wait { probe.calls.count == 3 }
        service.refresh(id: second, force: true)
        let queued = state(second)?.checking == true && probe.calls.count == 3
        probe.hold(false)
        settled()
        suite.expect(queued && probe.calls == [first, second, first, second],
                     "a card refreshed while another check runs shows it waiting and is checked next")

        probe.hold(true)
        service.refresh(now: Date().addingTimeInterval(301))
        wait { probe.calls.count == 5 }
        service.pageDidDisappear()
        let dropped = state(second)?.checking == false && state(first)?.checking == true
        probe.hold(false)
        settled()
        let afterClose = probe.calls.count
        let finished = state(first)?.attempted != nil && state(first)?.limits != nil
        service.pageDidAppear()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        suite.expect(dropped && finished && afterClose == 5 && probe.calls.count == 5,
                     "closing the page lets a check under way finish, and opening it again does not start it over")

        probe.fail(first, .unavailable); probe.fail(second, .missingCLI)
        service.refresh(force: true)
        settled()
        let failed = probe.calls.count
        service.refresh(now: Date().addingTimeInterval(301))
        settled()
        let soon = Array(probe.calls.dropFirst(failed))
        service.refresh(now: Date().addingTimeInterval(1_801))
        settled()
        let later = Array(probe.calls.dropFirst(failed + soon.count))
        suite.expect(soon == [first] && later == [first, second] && state(second)?.failure == .missingCLI,
                     "a failed check is asked again after five minutes, and after half an hour when only the person can fix it")
        suite.expect(probe.paths.allSatisfy { $0 == nil } && shellLookups.withLock({ lookups }) == 0,
                     "a check the page asks for never runs the login shell")
        service.refresh(id: second, force: true)
        settled()
        service.refresh(id: second, force: true)
        settled()
        suite.expect(probe.paths.suffix(2) == ["/shell/bin", "/shell/bin"] && shellLookups.withLock({ lookups }) == 1,
                     "refreshing a card that could not find Codex looks along the login shell's PATH once")
        probe.fail(first, nil); probe.fail(second, nil)

        probe.hold(true)
        service.refresh(id: first, force: true)
        wait { state(first)?.checking == true && probe.calls.last == first }
        var renamed = profiles
        renamed[0].name = "Renamed"
        defaults.set(CodexAccountProfile.encode(renamed), forKey: DefaultsKey.notchAgentsCodexProfiles)
        service.synchronize()
        let kept = state(first)?.checking == true && state(first)?.profile.name == "Renamed"
        let beforeRename = probe.calls.count
        probe.hold(false)
        settled()
        suite.expect(kept && probe.calls.count == beforeRename && state(first)?.failure == nil,
                     "renaming an account keeps its check under way and its reading")

        probe.hold(true)
        service.refresh(id: second, force: true)
        wait { probe.calls.last == second && state(second)?.checking == true }
        defaults.set(CodexAccountProfile.encode([renamed[0]]), forKey: DefaultsKey.notchAgentsCodexProfiles)
        service.synchronize()
        // Still held, so only the cancellation can end it.
        wait { probe.cancelled == [second] }
        let stopped = probe.cancelled == [second]
        probe.hold(false)
        settled()
        suite.expect(stopped && service.states.map(\.id) == [first],
                     "removing an account stops its check and leaves its late answer unused")

        probe.hold(true)
        service.refresh(id: first, force: true)
        wait { probe.calls.last == first && state(first)?.checking == true }
        service.pause()
        let paused = state(first)?.checking == false && state(first)?.attempted == nil && service.timer == nil
        probe.hold(false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let beforeOpen = probe.calls.count
        service.pageDidAppear()
        wait { probe.calls.count > beforeOpen }
        settled()
        suite.expect(paused && probe.calls.count == beforeOpen + 1,
                     "locking the Mac stops a check under way, and the page asks again when it shows")

        let hidden = defaults.string(forKey: DefaultsKey.notchAgentsHiddenCards) ?? ""
        defaults.set(NotchAgentCard.limits.rawValue, forKey: DefaultsKey.notchAgentsHiddenCards)
        service.synchronize(); service.pageDidAppear(); service.refresh(force: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        suite.expect(!service.isEnabled && probe.calls.count == beforeOpen + 1 && service.timer == nil,
                     "with the Limits card hidden no account is checked, even when asked")
        defaults.set(hidden, forKey: DefaultsKey.notchAgentsHiddenCards)

        defaults.set(false, forKey: DefaultsKey.notchAgentsCodex)
        service.synchronize(); service.pageDidAppear(); service.refresh(force: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        suite.expect(probe.calls.count == beforeOpen + 1 && service.timer == nil && service.states.allSatisfy { !$0.checking },
                     "with Codex turned off no account is checked, even when asked")
    }
}
