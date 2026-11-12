// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AntigravityTests {
    static func run(_ suite: TestSuite) {
        transcripts(suite)
        quotaFailures(suite)
        metadata(suite)
        subprocess(suite)
        logDiscovery(suite)
        lifecycle(suite)
        for language in AppLanguage.allCases {
            LocalizationTests.check(FeatureStrings.antigravityAccount(language),
                against: FeatureStrings.antigravityAccount(.enUS), name: "Antigravity \(language)", suite: suite)
            suite.expect(!FeatureStrings.notchAgents(language).confirmationAlert.isEmpty,
                         "confirmation notices are translated in \(language)")
        }
    }

    private static func transcripts(_ suite: TestSuite) {
        let reader = AntigravityReader()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var state = AgentLogState()
        state.session = "session"
        let user = Data(#"{"type":"USER_INPUT","source":"USER_EXPLICIT","cwd":"/tmp/project"}"#.utf8)
        suite.expect(reader.parse(user, state: &state, now: now) == [.turnBegan(now), .turnContext(model: "", project: "project")]
                     && state.project == "project", "an explicit AGY prompt opens its project turn")
        suite.expect(reader.parse(user, state: &state, now: now) == [
            .turnEnded(now, completed: false, duration: nil), .turnBegan(now), .turnContext(model: "", project: "project")],
                     "a new AGY request abandons the previous unfinished turn without announcing completion")
        let response = Data(#"{"type":"PLANNER_RESPONSE","step_index":1,"model":"unknown-model","input_tokens":100,"cache_read_tokens":30,"output_tokens":20,"tool_calls":[{"name":"run_command"}]}"#.utf8)
        let entries = reader.parse(response, state: &state, now: now)
        suite.expect(entries.last == .turnActive(now) && state.turnOpen,
                     "an AGY tool call keeps the turn active")
        let store = AgentUsageStore()
        for file in ["transcript.jsonl", "transcript_full.jsonl"] {
            store.apply(entries, file: file, provider: .antigravity, tracksTurns: true, modified: now, now: now)
        }
        suite.expect(store.records.count == 1 && store.records.first?.tokens.input == 70
                     && store.records.first?.tokens.cacheRead == 30 && store.records.first?.tokens.output == 20
                     && store.records.first?.cost == nil,
                     "duplicate AGY transcripts count one response, separate cached input and preserve unknown pricing")
        let final = Data(#"{"type":"PLANNER_RESPONSE","status":"DONE"}"#.utf8)
        suite.expect(reader.parse(final, state: &state, now: now) == [.turnEnded(now, completed: true, duration: nil)]
                     && !state.turnOpen && state.runningCommands.isEmpty,
                     "a final AGY reply ends the turn and clears running tools")
        let fallback = Data(#"{"type":"PLANNER_RESPONSE","input_tokens":10,"output_tokens":2}"#.utf8)
        let first = reader.parse(fallback, state: &state, now: now)
        let second = reader.parse(fallback, state: &state, now: now)
        suite.expect(first == second, "AGY replies without step indexes retain a stable identity")
        let malformed = Data(#"{"type":"PLANNER_RESPONSE","input_tokens":-10,"cache_read_tokens":300,"output_tokens":-1}"#.utf8)
        suite.expect(!reader.parse(malformed, state: &state, now: now).contains {
            if case .usage = $0 { return true }; return false
        }, "damaged cached input cannot invent a usage record")
        suite.expect(reader.parse(Data("not JSON".utf8), state: &state, now: now).isEmpty,
                     "malformed AGY lines are ignored")
        state.turnOpen = true
        let failed = Data(#"{"type":"PLANNER_RESPONSE","status":"ERROR","tool_calls":[{"name":"run_command"}]}"#.utf8)
        suite.expect(reader.parse(failed, state: &state, now: now).last == .turnEnded(now, completed: false, duration: nil)
                     && !state.turnOpen, "an AGY error ends the turn without completion even when tools remain in the response")

    }

    private static func metadata(_ suite: TestSuite) {
        var state = AgentLogState()
        let reader = AntigravityReader()
        func parse(_ content: String) {
            let json: [String: Any] = ["type": "USER_INPUT", "source": "USER_EXPLICIT", "content": content]
            _ = reader.parse(try! JSONSerialization.data(withJSONObject: json), state: &state, now: Date())
        }
        let selection = "The user changed setting `Model Selection` from None to Gemini 3.8 Flash (Medium). No need to comment."
        parse("<USER_REQUEST><USER_SETTINGS_CHANGE>" + selection + "</USER_SETTINGS_CHANGE></USER_REQUEST>")
        suite.expect(state.model.isEmpty, "a model selection quoted inside the request never chooses AGY's model")
        parse("<USER_REQUEST>Continue</USER_REQUEST><USER_SETTINGS_CHANGE>" + selection + "</USER_SETTINGS_CHANGE>")
        suite.expect(state.model == "Gemini 3.8 Flash (Medium)", "AGY 1.5 model changes come from its settings metadata")
        let change = selection.replacingOccurrences(of: "Gemini 3.8 Flash (Medium)", with: "Claude Sonnet 5.5")
        parse("<USER_REQUEST>Continue</USER_REQUEST><ADDITIONAL_METADATA>" + change + "</ADDITIONAL_METADATA>")
        suite.expect(state.model == "Claude Sonnet 5.5", "older metadata also updates AGY's model for the next response")
        let quoted: [String: Any] = ["type": "PLANNER_RESPONSE", "status": "RUNNING", "content": "<USER_SETTINGS_CHANGE>" + selection + "</USER_SETTINGS_CHANGE>"]
        _ = reader.parse(try! JSONSerialization.data(withJSONObject: quoted), state: &state, now: Date())
        suite.expect(state.model == "Claude Sonnet 5.5", "a model reply quoting settings metadata cannot change the recorded model")
        let running = Data(#"{"type":"PLANNER_RESPONSE","status":"RUNNING"}"#.utf8)
        suite.expect(reader.parse(running, state: &state, now: Date()).contains {
            if case .turnActive = $0 { return true }; return false
        } && state.turnOpen, "an unfinished AGY response without tools keeps its turn open")
    }

    private static func subprocess(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorssaint-agy-cli-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let executable = folder.appending(path: "agy")
        let script = "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo 1.1.10; exit 0; fi\nexit 99\n"
        try? Data(script.utf8).write(to: executable)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        do {
            _ = try AntigravityQuotaService.read(executable: executable)
            suite.expect(false, "an old AGY must never receive /usage")
        } catch {
            suite.expect(error as? AntigravityQuotaService.Failure == .incompatibleCLI,
                         "the real subprocess path rejects an old AGY before executing /usage")
        }
    }

    private static func quotaFailures(_ suite: TestSuite) {
        func failure(_ status: Int32, _ timeout: Bool, _ output: String) -> AntigravityQuotaService.Failure? {
            do { _ = try AntigravityQuotaService.response(status: status, timedOut: timeout, output: Data(output.utf8)); return nil }
            catch { return error as? AntigravityQuotaService.Failure }
        }
        suite.expect(failure(0, true, "{}") == .timeout && failure(28, false, "{}") == .timeout,
                     "AGY request timeouts remain distinct from malformed responses")
        suite.expect(failure(22, false, "{}") == .request && failure(0, false, "[]") == .invalidResponse,
                     "failed HTTP requests and unexpected JSON never become valid quotas")
        let buckets: [[String: Any]] = [
            ["id": "bool", "remaining_fraction": true],
            ["id": "nan", "remaining_fraction": Double.nan],
            ["id": "negative", "remaining_fraction": -0.1],
            ["id": "empty", "remaining_fraction": 1.1],
            ["id": "valid", "remaining_fraction": 0.5],
            ["id": "valid", "remaining_fraction": 0.0],
        ]
        let limits = AntigravityQuotaService.decode(["status": "SUCCESS", "command": ["name": "usage", "data": ["groups": [["buckets": buckets]]]]], now: Date())
        suite.expect(limits?.windows.count == 1 && limits?.windows.first?.usedPercent == 50,
                     "AGY rejects booleans and out-of-range quotas and deduplicates bucket IDs")
        suite.expect(!AntigravityQuotaService.supportsUsage("1.1.10")
                     && !AntigravityQuotaService.supportsUsage("unknown")
                     && AntigravityQuotaService.supportsUsage("1.1.11")
                     && AntigravityQuotaService.supportsUsage("1.5.5\n"),
                     "AGY gates /usage on versions that handle it locally instead of sending a prompt")
    }

    private static func logDiscovery(_ suite: TestSuite) {
        let home = FileManager.default.temporaryDirectory.appending(path: "vorssaint-agy-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = AgentLogRoot.all(home: home).filter { $0.provider == .antigravity }
        suite.expect(roots.count == 3, "AGY discovers the CLI and both IDE brain roots")
        for root in roots {
            let logs = root.url.appending(path: "session/.system_generated/logs")
            try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            for name in ["transcript.jsonl", "transcript_full.jsonl"] {
                let path = logs.appending(path: name)
                try? Data().write(to: path)
                suite.expect(root.accepts(path.path) && AgentLogCursor(path: path.path, provider: .antigravity).state.session == "session",
                             "AGY recognizes its transcript layout and derives the conversation identity")
            }
            suite.expect(!root.accepts(root.url.appending(path: "session/transcript.jsonl").path)
                         && !root.accepts(root.url.appending(path: ".hidden/.system_generated/logs/transcript.jsonl").path),
                         "AGY ignores unrelated and hidden conversation files")
        }
        let existingRoots = AgentLogRoot.all(home: home).filter { $0.provider == .antigravity }
        let discovered = AgentLogReader.discover(existingRoots, since: .distantPast)
        suite.expect(discovered.count == 6 && discovered.allSatisfy { $0.provider == .antigravity },
                     "AGY shallow discovery reaches both transcript names inside hidden system log folders")
        let info = AntigravityLogInfo.read(home: home)
        suite.expect(info.conversations == 1 && info.folder?.path == roots.first.map { AgentLogRoot.canonical($0.url).path },
                     "AGY Settings counts conversations with transcripts once across CLI and IDE copies")
        let store = AgentUsageStore()
        store.reportsTransitions = true
        let now = Date()
        suite.expect(store.apply([.confirmationNeeded(now.addingTimeInterval(-301), project: "p", detail: "old"),
                                  .confirmationNeeded(now.addingTimeInterval(10), project: "p", detail: "future")],
                                 file: "f", provider: .antigravity, tracksTurns: true, modified: now, now: now).isEmpty,
                     "AGY does not replay stale or future-dated confirmation requests")
    }

    private static func lifecycle(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.antigravity-quota"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults { defaults.set(value, forKey: key) }
        for feature in AppFeature.allCases { defaults.set(true, forKey: feature.availabilityKey) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(true, forKey: DefaultsKey.notchAgentsEnabled)
        let began = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let cancellationSeen = DispatchSemaphore(value: 0)
        let service = AntigravityQuotaService(defaults: defaults) { cancellation in
            began.signal()
            _ = release.wait(timeout: .now() + 2)
            let cancelled = cancellation.isCancelled
            if cancelled { cancellationSeen.signal() }
            finished.signal()
            return .failure(cancelled ? .timeout : .request)
        }
        service.appear()
        suite.expect(began.wait(timeout: .now() + 2) == .success && service.checking && service.timer != nil,
                     "a visible AGY Limits card starts one quota check and polling timer")
        defaults.set(false, forKey: DefaultsKey.notchAgentsAntigravity)
        service.synchronize()
        suite.expect(!service.checking && service.timer == nil, "disabling AGY ends polling and its current check")
        release.signal()
        suite.expect(finished.wait(timeout: .now() + 2) == .success
                     && cancellationSeen.wait(timeout: .now() + 2) == .success,
                     "disabling AGY cancels its quota subprocess")
        let until = Date(timeIntervalSinceNow: 0.05)
        while Date() < until { _ = RunLoop.main.run(mode: .default, before: until) }
        suite.expect(service.failure == nil && service.limits == nil,
                     "a cancelled AGY result cannot replace the last visible account state")
        service.refresh(force: true)
        suite.expect(!service.checking, "a manual check cannot launch AGY while the provider is off")
        defaults.set(true, forKey: DefaultsKey.notchAgentsAntigravity)
        defaults.set("limits", forKey: DefaultsKey.notchAgentsHiddenCards)
        service.appear()
        suite.expect(!service.checking && service.timer == nil, "hidden AGY Limits cards launch no background checks")
        defaults.set("", forKey: DefaultsKey.notchAgentsHiddenCards)
        service.synchronize()
        suite.expect(service.timer != nil, "re-enabling a visible AGY Limits card restores polling")
        service.pause()
    }
}
