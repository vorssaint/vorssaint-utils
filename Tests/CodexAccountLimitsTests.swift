// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum CodexAccountLimitsTests {
    static func run(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let text = CodexAccountStrings.localized(language)
            let values = Mirror(reflecting: text).children.compactMap { $0.value as? String }
            suite.expect(values.count == 17 && values.allSatisfy { !$0.isEmpty }
                            && (language == .enUS || text.explanation != CodexAccountStrings.localized(.enUS).explanation),
                         "Codex account settings and feedback are localized for \(language.rawValue)")
        }
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("codex-accounts-" + UUID().uuidString)
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? manager.removeItem(at: root) }
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

    private static func boundaries(_ suite: TestSuite, root: URL, profiles: [CodexAccountProfile]) throws {
        let manager = FileManager.default
        let first = URL(fileURLWithPath: profiles[0].directory)
        suite.expect(CodexAccountProfile.decode(CodexAccountProfile.encode(profiles)) == profiles,
                     "Codex profile names, IDs and directories survive saving")
        suite.expect(CodexAccountProfile.discover(home: root).map(\.directory) == profiles.map(\.directory),
                     "local Codex homes are discovered without opening credential contents")
        let standard = root.appendingPathComponent(".codex")
        try manager.createDirectory(at: standard, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data().write(to: standard.appendingPathComponent("config.toml"))
        suite.expect(CodexAccountProfile.discover(home: root).first?.name == "Default",
                     "the ordinary .codex home can be explicitly selected alongside named accounts")
        let alias = root.appendingPathComponent(".codex-alias")
        try manager.createSymbolicLink(at: alias, withDestinationURL: first)
        let duplicate = CodexAccountProfile(id: UUID().uuidString, name: "Alias", directory: alias.path)
        suite.expect(CodexAccountProfile.decode(CodexAccountProfile.encode([profiles[0], duplicate])).count == 1
                        && CodexAccountProfile.discover(home: root).count == 3,
                     "symlink aliases of a home never create duplicate account cards")
        for path in ["", "relative", "/", manager.homeDirectoryForCurrentUser.path, root.appendingPathComponent("missing").path] {
            suite.expect(CodexAccountProfile(id: UUID().uuidString, name: "Invalid", directory: path).canonicalDirectory == nil,
                         "an ambiguous or missing Codex home is rejected: \(path)")
        }
        try manager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: first.path)
        suite.expect(profiles[0].canonicalDirectory == nil, "a writable-by-others Codex home is rejected")
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: first.path)
        let auth = first.appendingPathComponent("auth.json")
        // An empty fixture proves only metadata is inspected; it is not a credential.
        manager.createFile(atPath: auth.path, contents: Data(), attributes: [.posixPermissions: 0o600])
        suite.expect(profiles[0].canonicalDirectory != nil, "private file-backed Codex homes remain valid")
        try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: auth.path)
        suite.expect(profiles[0].canonicalDirectory == nil, "a credential artifact accessible to others is rejected")
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: auth.path)
        let linked = URL(fileURLWithPath: profiles[1].directory).appendingPathComponent("auth.json")
        try manager.linkItem(at: auth, to: linked)
        suite.expect(profiles.allSatisfy { $0.canonicalDirectory == nil }, "hard-linked credentials cannot collapse two account homes")
        try manager.removeItem(at: linked)
        try manager.createSymbolicLink(at: linked, withDestinationURL: auth)
        suite.expect(profiles[1].canonicalDirectory == nil, "a symlinked credential artifact is rejected")
        try manager.removeItem(at: linked)
        try manager.removeItem(at: auth)

        let cli = root.appendingPathComponent("codex")
        let overrides = ["CODEX_ACCESS_TOKEN", "CODEX_API_KEY", "OPENAI_API_KEY", "OPENAI_FEDERATION_RULE_ID",
                         "OPENAI_IDENTITY_TOKEN_FILE", "OPENAI_WORKLOAD_IDENTITY_CONTEXT", "CODEX_SQLITE_HOME",
                         "OPENAI_BASE_URL", "NODE_OPTIONS", "ANTHROPIC_API_KEY"]
        var base = Dictionary(uniqueKeysWithValues: overrides.map { ($0, "synthetic") })
        base["HOME"] = root.path; base["CODEX_HOME"] = profiles[1].directory; base["PATH"] = "/untrusted"
        base["HTTPS_PROXY"] = "synthetic-proxy"; base["DO_NOT_TRACK"] = "1"
        let env = CodexAccountUsageReader.environment(directory: first, executable: cli, base: base)
        suite.expect(overrides.allSatisfy { env[$0] == nil } && env["CODEX_HOME"] == first.path
                        && env["HOME"] == root.path && env["HTTPS_PROXY"] == "synthetic-proxy"
                        && env["DO_NOT_TRACK"] == "1" && env["PATH"]?.contains("/untrusted") == false,
                     "profile checks discard auth, provider and state overrides while preserving proxies and privacy opt-outs")
        let invalid = CodexAccountProfile(id: "invalid", name: "Bad", directory: first.path)
        let many = (0..<10).map { CodexAccountProfile(id: UUID().uuidString, name: "\($0)", directory: "/profiles/\($0)") }
        suite.expect(CodexAccountProfile.decode(CodexAccountProfile.encode([invalid])).isEmpty
                        && CodexAccountProfile.decode(CodexAccountProfile.encode(many)).count == 8
                        && CodexAccountProfile.decode(String(repeating: "x", count: 65_537)).isEmpty,
                     "malformed, oversized and excess profile preferences are bounded")
        let payload: [String: Any] = [SettingsBackupSupport.formatVersionKey: 1,
            SettingsBackupSupport.settingsKey: [DefaultsKey.notchAgentsCodexProfiles: CodexAccountProfile.encode(profiles)]]
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchAgentsCodexProfiles)
                        && SettingsBackupSupport.sanitizedSettings(from: payload)?[DefaultsKey.notchAgentsCodexProfiles] == nil,
                     "neither a settings export nor an import carries Codex account authority")
        let claude = ClaudeAccountProfile(id: profiles[0].id, name: "Claude", directory: "/claude")
        let tiles = NotchAgentSupport.tiles(cards: [.limits, .resets], providers: [.claude, .codex, .opencode],
                                           claudeProfiles: [claude], codexProfiles: profiles)
        suite.expect(tiles.map(\.profileID) == [claude.id, profiles[0].id, profiles[1].id, nil, nil]
                        && Set(tiles.map(\.id)).count == 5 && tiles.last?.card == .resets,
                     "each provider's account cards have independent identities and keep the default resets card separate")
    }

    private static let server = #"""
    #!/bin/sh
    [ "$1" = app-server ] || exit 1
    [ "$PWD" = / ] || exit 2
    [ -z "${OPENAI_API_KEY+x}${CODEX_ACCESS_TOKEN+x}${CODEX_SQLITE_HOME+x}" ] || exit 3
    case "$CODEX_HOME" in *.codex-personal) USED=14; WEEK=61; PLAN=plus;; *.codex-work) USED=100; WEEK=41; PLAN=business;; *) exit 4;; esac
    echo $$ > "$CODEX_HOME/server.pid"
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
        let token = BoundedProcessCancellation()
        let readings = try profiles.map { try CodexAccountUsageReader.read($0, executable: cli, cancellation: token, timeout: 3) }
        suite.expect(readings.map { $0.limits.windows.first?.usedPercent } == [14, 100]
                        && readings.map { $0.limits.windows.last?.usedPercent } == [61, 41]
                        && readings.map(\.plan) == ["Plus", "Business"],
                     "two official-protocol conversations keep their homes, plans and limits separate without requiring reset credits")
        for profile in profiles {
            let log = try String(contentsOf: URL(fileURLWithPath: profile.directory).appendingPathComponent("rpc.log"), encoding: .utf8)
            let methods = log.split(separator: "\n").compactMap {
                ((try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any])?["method"] as? String
            }
            suite.expect(methods == ["initialize", "initialized", "account/read", "account/rateLimits/read"],
                         "account checks send only initialization and status requests, never prompts or reset consumption")
        }
        let now = Date()
        let windows = [AgentLimitWindow(id: "session", kind: .session, minutes: 300, scope: nil, usedPercent: 14, resetsAt: now),
                       AgentLimitWindow(id: "week", kind: .weekly, minutes: 10_080, scope: nil, usedPercent: 61, resetsAt: now.addingTimeInterval(3600)),
                       AgentLimitWindow(id: "business", kind: .other, minutes: nil, scope: nil, usedPercent: 3, resetsAt: nil)]
        let state = CodexProfileLimitsState(profile: profiles[0], limits: AgentLimits(provider: .codex, windows: windows, observedAt: now, source: .account))
        suite.expect(state.currentLimits(at: now)?.windows.map(\.usedPercent) == [61, 3],
                     "expired limits disappear without showing zero or discarding an undated Business allowance")
        let first = URL(fileURLWithPath: profiles[0].directory)
        for (name, expected) in [("signed-out", AgentCodexServer.Failure.needsSignIn), ("failure", .outdated)] {
            let marker = first.appendingPathComponent(name)
            try Data().write(to: marker)
            do {
                _ = try CodexAccountUsageReader.read(profiles[0], executable: cli, cancellation: token, timeout: 2)
                suite.expect(false, "\(name) must not produce account limits")
            } catch { suite.expect(error as? AgentCodexServer.Failure == expected, "\(name) reports a safe actionable error") }
            try FileManager.default.removeItem(at: marker)
        }
        try Data().write(to: first.appendingPathComponent("silent"))
        let cancelling = BoundedProcessCancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { cancelling.cancel() }
        let start = Date()
        do {
            _ = try CodexAccountUsageReader.read(profiles[0], executable: cli, cancellation: cancelling, timeout: 10)
            suite.expect(false, "a cancelled account check cannot return limits")
        } catch {
            suite.expect(error as? CodexAccountUsageError == .cancelled && Date().timeIntervalSince(start) < 2,
                         "page cancellation interrupts a silent app-server without waiting for the network deadline")
        }
        let pidText = try String(contentsOf: first.appendingPathComponent("server.pid"), encoding: .utf8)
        if let pid = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            suite.expect(kill(pid, 0) == -1 && errno == ESRCH, "a cancelled account check leaves no server process behind")
        }
        let timeoutStart = Date()
        do {
            _ = try CodexAccountUsageReader.read(profiles[0], executable: cli, cancellation: BoundedProcessCancellation(), timeout: 0.1)
            suite.expect(false, "a silent app-server must time out")
        } catch { suite.expect(Date().timeIntervalSince(timeoutStart) < 2, "account checks have a bounded deadline") }
    }

    private final class Probe {
        private let lock = NSLock()
        private var ids: [String] = []
        private var slow = false
        var calls: [String] { lock.withLock { ids } }
        func delay() { lock.withLock { slow = true } }
        func read(_ profile: CodexAccountProfile, _ token: BoundedProcessCancellation) -> (limits: AgentLimits, plan: String?) {
            let wait = lock.withLock { ids.append(profile.id); return slow }
            if wait {
                let end = Date().addingTimeInterval(2)
                while !token.isCancelled && Date() < end { usleep(10_000) }
            }
            let window = AgentLimitWindow(id: "codex.300", kind: .session, minutes: 300, scope: nil, usedPercent: 42,
                                          resetsAt: Date().addingTimeInterval(3600))
            return (AgentLimits(provider: .codex, windows: [window], observedAt: Date(), source: .account), "Plus")
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
        defaults.register(defaults: Defaults.registeredDefaults)
        for feature in AppFeature.allCases { defaults.set(true, forKey: feature.availabilityKey) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(CodexAccountProfile.encode(profiles), forKey: DefaultsKey.notchAgentsCodexProfiles)
        let probe = Probe()
        let service = CodexProfileLimitsService(defaults: defaults, reader: probe.read)
        defer { service.pause() }
        service.synchronize(); service.refresh()
        suite.expect(probe.calls.isEmpty && service.states.count == 2, "saving profiles does not launch background account checks")
        service.refresh(force: true); service.refresh(force: true)
        wait { service.states.allSatisfy { !$0.checking } }
        suite.expect(probe.calls == profiles.map(\.id) && service.states.allSatisfy { $0.limits != nil },
                     "manual checks outside the page run sequentially and coalesce while in flight")
        service.pageDidAppear()
        suite.expect(probe.calls.count == 2, "opening the AI page reuses fresh account readings")
        service.refresh(id: profiles[1].id, force: true)
        wait { service.states.allSatisfy { !$0.checking } }
        suite.expect(probe.calls == [profiles[0].id, profiles[1].id, profiles[1].id],
                     "a card refresh checks only its own Codex home")
        service.pause(); service.refresh()
        suite.expect(probe.calls.count == 3, "closing or locking the page stops automatic checks")
        probe.delay()
        service.refresh(force: true)
        wait { probe.calls.count == 4 }
        defaults.set(CodexAccountProfile.encode([profiles[1]]), forKey: DefaultsKey.notchAgentsCodexProfiles)
        service.synchronize()
        wait { service.states.allSatisfy { !$0.checking } }
        suite.expect(service.states.map(\.id) == [profiles[1].id] && probe.calls.count == 4,
                     "removing an account cancels its generation, ignores late results and skips queued homes")
        defaults.set(false, forKey: DefaultsKey.notchAgentsCodex)
        service.synchronize(); service.pageDidAppear(); service.refresh(force: true)
        suite.expect(probe.calls.count == 4 && service.states.allSatisfy { !$0.checking },
                     "a disabled provider cannot launch even an explicit refresh")
    }
}
