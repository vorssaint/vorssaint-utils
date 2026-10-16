// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure contracts for the herdr status integration: JSON envelope parsing,
/// binary discovery, polling cadence, dedup keys, machine-label validation
/// and badge gating. No subprocess, no herdr install, no UI.
enum HerdrStatusTests {
    static func run(_ suite: TestSuite) {
        // MARK: Envelope parsing

        let listJSON = """
        {"id":"cli:agent:list","result":{"type":"agent_list","agents":[\
        {"terminal_id":"t1","workspace_id":"w1","tab_id":"b1","pane_id":"p1",\
        "agent_status":"working","focused":true,"revision":7,\
        "name":"alpha","title":"build","cwd":"/tmp",\
        "tokens":{"foo":"bar"},"state_change_seq":3},\
        {"terminal_id":"t2","workspace_id":"w1","tab_id":"b1","pane_id":"p2",\
        "agent_status":"blocked","focused":false,"revision":2,\
        "state_change_seq":0}]}}
        """.data(using: .utf8)!

        switch HerdrStatusSupport.decode(listJSON) {
        case .success(let snapshot):
            suite.expect(snapshot.agents.count == 2,
                   "an agent_list envelope decodes both supervised agents")
            suite.expect(snapshot.agents[0].status == .working && snapshot.agents[0].focused
                   && snapshot.agents[0].revision == 7 && snapshot.agents[0].displayName == "alpha",
                   "the first agent keeps status, focus, revision and name")
            suite.expect(snapshot.agents[1].status == .blocked,
                   "a blocked agent keeps its blocked status")
            suite.expect(HerdrStatusSupport.needsAttention(snapshot),
                   "a snapshot holding a blocked agent needs attention")
            suite.expect(HerdrStatusSupport.agentKey(snapshot.agents[0]) == "w1:b1:p1",
                   "an agent key is workspace, tab and pane ids")
        case .failure(let error):
            suite.expect(false, "a valid agent_list envelope decodes, got \(error)")
        }

        let renamedJSON = """
        {"id":"1","result":{"type":"agent_list","agents":[\
        {"terminal_id":"t1","workspace_id":"w1","tab_id":"b1","pane_id":"p1",\
        "agent_status":"working","focused":false,"revision":8,\
        "name":"beta"}]}}
        """.data(using: .utf8)!
        if case .success(let renamed) = HerdrStatusSupport.decode(renamedJSON),
           case .success(let original) = HerdrStatusSupport.decode(listJSON) {
            suite.expect(HerdrStatusSupport.agentKey(renamed.agents[0])
                   == HerdrStatusSupport.agentKey(original.agents[0]),
                   "an agent key is stable across a rename because it carries ids, not names")
            suite.expect(HerdrStatusSupport.dedupeKey(renamed.agents[0])
                   != HerdrStatusSupport.dedupeKey(original.agents[0]),
                   "a revision bump produces a new dedupe key so the row updates")
            suite.expect(HerdrStatusSupport.dedupeKey(original.agents[0])
                   == HerdrStatusSupport.dedupeKey(original.agents[0]),
                   "the same pane, revision and status collapses to one dedupe key")
        } else {
            suite.expect(false, "rename fixtures decode so key stability can be checked")
        }

        let unknownJSON = """
        {"id":"1","result":{"type":"agent_list","agents":[\
        {"terminal_id":"t9","workspace_id":"w","tab_id":"b","pane_id":"p",\
        "agent_status":"daydreaming","focused":false,"revision":1}]}}
        """.data(using: .utf8)!
        if case .success(let unknown) = HerdrStatusSupport.decode(unknownJSON) {
            suite.expect(unknown.agents.first?.status == .unknown,
                   "an unrecognized status string becomes unknown instead of throwing")
        } else {
            suite.expect(false, "an unknown status string decodes as unknown")
        }

        let truncated = Data(listJSON.prefix(60))
        switch HerdrStatusSupport.decode(truncated) {
        case .success:
            suite.expect(false, "truncated JSON never decodes as a snapshot")
        case .failure(let error):
            suite.expect(error == .decode,
                   "truncated JSON fails as decode so the last good snapshot stays stale")
        }

        let stoppedJSON = """
        {"id":"cli:agent:list","error":{"code":"server_not_running",\
        "message":"no herdr server is running"}}
        """.data(using: .utf8)!
        switch HerdrStatusSupport.decode(stoppedJSON) {
        case .success:
            suite.expect(false, "a server error envelope never decodes as a snapshot")
        case .failure(let error):
            suite.expect(error == .serverStopped,
                   "a stopped server is its own empty state, not a decode failure")
        }

        let refusedJSON = """
        {"id":"1","error":{"code":"refused","message":"nope"}}
        """.data(using: .utf8)!
        if case .failure(let error) = HerdrStatusSupport.decode(refusedJSON) {
            suite.expect(error == .server(code: "refused"),
                   "an error envelope carries its code instead of showing raw output")
        } else {
            suite.expect(false, "a generic error envelope fails with its code")
        }

        // MARK: Machine labels

        suite.expect(HerdrStatusSupport.isValidMachineLabel("dev-mac_1.prod"),
               "a machine label with dots, dashes and underscores is accepted")
        for bad in ["", "has space", "semi;colon", "slash/x", String(repeating: "a", count: 65)] {
            suite.expect(!HerdrStatusSupport.isValidMachineLabel(bad),
                   "an empty, spaced, punctuated or overlong label is rejected: \(bad)")
        }
        suite.expect(HerdrStatusSupport.sanitizedMachines(" b, b ,a,,bad label,")
               == ["a", "b"],
               "saved machine labels trim, dedupe, drop invalid entries and sort")
        suite.expect(HerdrStatusSupport.sanitizedMachines(
            (1...10).map { "m\($0)" }.joined(separator: ",")) == (1...8).map { "m\($0)" },
               "saved machine labels cap at eight")

        // MARK: Discovery

        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let brew = HerdrDiscovery.candidates(home: home, searchPath: nil)
            .map(\.path)
        suite.expect(brew.first == "/Users/tester/.local/bin/herdr"
               && brew.contains("/opt/homebrew/bin/herdr")
               && brew.contains("/usr/local/bin/herdr"),
               "discovery checks the home bin first, then the Homebrew prefixes")
        suite.expect(HerdrDiscovery.candidates(
            home: home, searchPath: "/opt/other/bin:/relative:nope:/usr/x").map(\.path)
            .suffix(3) == ["/opt/other/bin/herdr", "/relative/herdr", "/usr/x/herdr"],
               "a shell PATH contributes only absolute folders")
        let env = HerdrDiscovery.environment(for: URL(fileURLWithPath: "/opt/homebrew/bin/herdr"),
                                            searchPath: nil)
        suite.expect((env["PATH"] ?? "").hasPrefix("/opt/homebrew/bin:"),
               "the child PATH leads with the binary's own folder")
        suite.expect(HerdrDiscovery.isSupported(version: "herdr 0.9.3"),
               "the floor version 0.9.3 is supported")
        suite.expect(HerdrDiscovery.isSupported(version: "1.0.0")
               && !HerdrDiscovery.isSupported(version: "0.8.9")
               && !HerdrDiscovery.isSupported(version: "nope")
               && !HerdrDiscovery.isSupported(version: nil),
               "newer versions pass, older or unreadable ones do not")

        // MARK: Polling cadence

        suite.expect(HerdrStatusSupport.cadence(visibleSurfaces: 0, hasBlockedAgent: false,
                                                lastError: nil) == nil,
               "nothing visible and nobody blocked stops the timer entirely")
        suite.expect(HerdrStatusSupport.cadence(visibleSurfaces: 1, hasBlockedAgent: false,
                                                lastError: nil) == 2.5,
               "an open surface polls fast")
        suite.expect(HerdrStatusSupport.cadence(visibleSurfaces: 0, hasBlockedAgent: true,
                                                lastError: nil) == 2.5,
               "a blocked agent keeps fast polling after the surface closes")
        suite.expect(HerdrStatusSupport.cadence(visibleSurfaces: 1, hasBlockedAgent: true,
                                                lastError: .serverStopped) == 60,
               "a stopped server backs off even with a surface open")
        suite.expect(HerdrStatusSupport.cadence(visibleSurfaces: 0, hasBlockedAgent: false,
                                                lastError: .serverStopped) == 60,
               "a stopped server retries slowly instead of stopping forever")
        suite.expect(HerdrStatusSupport.cadence(visibleSurfaces: 0, hasBlockedAgent: false,
                                                lastError: .decode) == 60,
               "a decode failure backs off to the slow cadence")
        suite.expect(HerdrStatusSupport.cadence(visibleSurfaces: 5, hasBlockedAgent: false,
                                                lastError: .unsupportedVersion) == nil,
               "an unsupported binary never spins the poller")

        // MARK: Badge

        if case .success(let snapshot) = HerdrStatusSupport.decode(listJSON) {
            suite.expect(HerdrStatusSupport.showsBadge(snapshot),
                   "a blocked agent raises the island badge")
            let idle = HerdrStatusSnapshot(agents: snapshot.agents.map {
                HerdrAgent(terminalID: $0.terminalID, workspaceID: $0.workspaceID,
                           tabID: $0.tabID, paneID: $0.paneID, focused: $0.focused,
                           revision: $0.revision, status: .idle, displayName: $0.displayName,
                           title: $0.title, cwd: $0.cwd, sequence: $0.sequence)
            }, fetchedAt: snapshot.fetchedAt)
            suite.expect(!HerdrStatusSupport.showsBadge(idle),
                   "the badge clears once every agent leaves blocked")
            suite.expect(!HerdrStatusSupport.showsBadge(
                HerdrStatusSnapshot(agents: [], fetchedAt: Date())),
                   "an empty snapshot never raises the badge")
        } else {
            suite.expect(false, "the list fixture decodes so the badge gate can be checked")
        }

        // MARK: Strings and registration

        for lang in AppLanguage.allCases {
            let strings = FeatureStrings.herdr(lang)
            suite.expect(!strings.title.isEmpty && !strings.notInstalled.isEmpty
                   && !strings.noServer.isEmpty && !strings.empty.isEmpty,
                   "herdr status copy is present in \(lang)")
            suite.expect(!strings.statusBlocked.isEmpty && !strings.statusUnknown.isEmpty,
                   "herdr status labels are present in \(lang)")
        }
        suite.expect(AppFeature.herdrStatus.group == .tools,
               "herdr status lives in the Tools hub group")
        suite.expect(AppFeature.herdrStatus.symbolName == "terminal",
               "herdr status keeps the terminal symbol")
        suite.expect(AppFeature.herdrStatus.enabledKeys.isEmpty
               && !AppFeature.herdrStatus.installedByDefault
               && AppFeature.herdrStatus.permissions.isEmpty
               && AppFeature.herdrStatus.onboardingPermissions.isEmpty,
               "herdr status is opt-in, on demand and permission free")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityHerdr] as? Bool == true,
               "the herdr panel row ships visible like its siblings and travels in backups")
    }
}
