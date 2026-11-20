// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A subagent's or swarm worker's transcript has no model line: the call that
/// started it, which agy keeps in its `messages` folder, says what it runs on.
enum AntigravityLaunchTests {
    static func run(_ suite: TestSuite) {
        swarmModelNames(suite)
        launchMessages(suite)
        modelsOfStartedConversations(suite)
    }

    // MARK: Swarm model names

    private static func swarmModelNames(_ suite: TestSuite) {
        let named: [(String, String?)] = [
            ("opus-5.5-max", "claude-opus-5.5"), ("fable-5.1-xhigh", "claude-fable-5.1"),
            ("gemini-4-argon-high", "gemini-4-argon"), ("gemini-3.5-flash-lite", "gemini-3.5-flash-lite"),
            ("Claude Opus 5.5 (High)", "Claude Opus 5.5 (High)"), ("auto", nil), ("  ", nil)
        ]
        for (name, model) in named {
            suite.expect(AgentAntigravityLaunch.model(named: name) == model,
                         "swarm model \(name) names \(model ?? "no model")")
        }
        suite.expect(AgentPricing.normalized(AgentAntigravityLaunch.model(named: "opus-5.5-max") ?? "") == "claude-opus-5-5"
                        && AgentPricing.displayName(AgentAntigravityLaunch.model(named: "gemini-4-argon-low") ?? "") == "Gemini 4 Argon",
                     "a swarm model's name is priced and shown as the model picker's name is")
    }

    // MARK: Launch messages

    private static func launchMessages(_ suite: TestSuite) {
        let parent = "11111111-1111-4111-8111-111111111111"
        func launch(_ tool: String, _ arguments: [String: Any], content: String = "work") -> AgentAntigravityLaunch.Launch? {
            AgentAntigravityLaunch.launch(fromMessage: message(from: parent, tool: tool, arguments: arguments,
                                                               content: content, at: "2026-11-11T19:08:54.016811Z"))
        }
        let inherit = launch("invoke_subagent", ["Model": "inherit", "Prompt": "work", "TypeName": "self"])
        suite.expect(inherit?.model == .inherited && inherit?.parent == parent
                        && inherit?.date == AgentTimestamp.parse("2026-11-11T19:08:54.016811Z"),
                     "a subagent started with inherit runs on its parent's model, from the launch's time")
        suite.expect(launch("invoke_subagent", ["Prompt": "work", "TypeName": "self"])?.model == .inherited,
                     "a subagent started without a model inherits its parent's")
        let tier = launch("invoke_subagent", ["Model": "flash", "Prompt": "work"])
        suite.expect(tier != nil && tier?.model == nil, "a tier names no model, so the subagent's stays unknown")
        suite.expect(launch("invoke_subagent", ["Subagents": [["Model": "inherit", "Prompt": "a"], ["Prompt": "b"]]])?.model
                        == .inherited,
                     "subagents started together with the same model all get it")
        let mixed: [[String: Any]] = [["Model": "pro", "Prompt": "a"], ["Model": "inherit", "Prompt": "work"]]
        suite.expect(launch("invoke_subagent", ["Subagents": mixed])?.model == .inherited
                        && launch("invoke_subagent", ["Subagents": mixed], content: "a").map { $0.model == nil } == true
                        && launch("invoke_subagent", ["Subagents": mixed], content: "other").map { $0.model == nil } == true,
                     "subagents started together with different models are told apart by their prompt")
        suite.expect(launch("swarm", ["action": "add", "name": "author", "model": "opus-5.5-max"])?.model
                        == .named("claude-opus-5.5")
                        && launch("swarm", ["action": "add", "name": "author"])?.model == .inherited
                        && launch("swarm", ["action": "add", "model": "auto"]).map { $0.model == nil } == true,
                     "a swarm worker runs on the model it was added with, or on the swarm's own")
        suite.expect(launch("swarm", ["action": "status"]) == nil && launch("send_message", ["Recipient": parent]) == nil
                        && launch("run_command", ["CommandLine": "ls"]) == nil
                        && AgentAntigravityLaunch.launch(fromMessage: Data(#"{"id":"m","content":"hi"}"#.utf8)) == nil
                        && AgentAntigravityLaunch.launch(fromMessage: Data("not json".utf8)) == nil,
                     "only the call that starts a conversation is a launch")
    }

    // MARK: Started conversations

    private static func modelsOfStartedConversations(_ suite: TestSuite) {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "vorssaint-agy-launch-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let brain = home.appending(path: ".gemini/antigravity/brain", directoryHint: .isDirectory)
        let start = Date().addingTimeInterval(-600)
        func stamp(_ seconds: TimeInterval) -> String { ISO8601DateFormatter().string(from: start.addingTimeInterval(seconds)) }
        func transcript(_ id: String) -> String { brain.appending(path: "\(id)/.system_generated/logs/transcript.jsonl").path }
        func write(_ id: String, _ lines: [[String: Any]], launches: [Data] = []) -> Bool {
            let folder = brain.appending(path: "\(id)/.system_generated", directoryHint: .isDirectory)
            do {
                try FileManager.default.createDirectory(at: folder.appending(path: "logs"), withIntermediateDirectories: true)
                try Data(lines.map { String(decoding: line($0), as: UTF8.self) + "\n" }.joined().utf8)
                    .write(to: URL(fileURLWithPath: transcript(id)))
                guard !launches.isEmpty else { return true }
                try FileManager.default.createDirectory(at: folder.appending(path: "messages"), withIntermediateDirectories: true)
                for (index, launch) in launches.enumerated() {
                    try launch.write(to: folder.appending(path: "messages/\(index).json"))
                }
                try Data(#"{"0":true}"#.utf8).write(to: folder.appending(path: "messages/read.json"))
                return true
            } catch {
                suite.expect(false, "Antigravity launch fixture: \(error)")
                return false
            }
        }
        func settings(_ model: String, at seconds: TimeInterval) -> [String: Any] {
            ["source": "USER_EXPLICIT", "type": "USER_INPUT", "status": "DONE", "created_at": stamp(seconds),
             "content": "<USER_REQUEST>\nwork\n</USER_REQUEST>\n<USER_SETTINGS_CHANGE>\nThe user changed setting "
                + "`Model Selection` from None to \(model). No need to comment on this change.\n</USER_SETTINGS_CHANGE>"]
        }
        func reply(at seconds: TimeInterval, step: Int) -> [String: Any] {
            ["step_index": step, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
             "created_at": stamp(seconds), "input_tokens": 1_000, "output_tokens": 200]
        }
        func started(by sender: String, at seconds: TimeInterval, step: Int) -> [String: Any] {
            ["step_index": step, "source": "SYSTEM", "type": "SYSTEM_MESSAGE", "status": "DONE", "created_at": stamp(seconds),
             "content": "<SYSTEM_MESSAGE>\n[Message] timestamp=\(stamp(seconds)) sender=\(sender) priority=HIGH content=work"]
        }
        let notice: [String: Any] = ["step_index": 0, "source": "SYSTEM_SDK", "type": "EPHEMERAL_MESSAGE", "status": "DONE",
                                     "created_at": stamp(60), "content": "A plugin needs to be configured."]
        func launch(_ tool: String, _ arguments: [String: Any], from parent: String, at seconds: TimeInterval) -> Data {
            message(from: parent, tool: tool, arguments: arguments, content: "work", at: stamp(seconds))
        }

        let root = "11111111-1111-4111-8111-111111111111"
        let child = "22222222-2222-4222-8222-222222222222"
        let grandchild = "33333333-3333-4333-8333-333333333333"
        let worker = "44444444-4444-4444-8444-444444444444"
        let tier = "55555555-5555-4555-8555-555555555555"
        let late = "66666666-6666-4666-8666-666666666666"
        // The root changes model after it started its first subagent.
        guard write(root, [settings("Gemini 4 Argon (High)", at: 0), reply(at: 10, step: 1),
                           settings("Claude Opus 5.5 (High)", at: 300), reply(at: 310, step: 3)]),
              write(child, [notice, started(by: root, at: 60, step: 1), reply(at: 70, step: 2), reply(at: 400, step: 3)],
                    launches: [launch("send_message", ["Recipient": child], from: root, at: 20),
                               launch("invoke_subagent", ["Model": "inherit", "Prompt": "work"], from: root, at: 60),
                               launch("send_message", ["Recipient": child], from: root, at: 390)]),
              write(grandchild, [started(by: child, at: 80, step: 0), reply(at: 90, step: 1)],
                    launches: [launch("invoke_subagent", ["Prompt": "work"], from: child, at: 80)]),
              write(worker, [started(by: root, at: 100, step: 0), reply(at: 110, step: 1)],
                    launches: [launch("swarm", ["action": "add", "name": "author", "model": "fable-5.1-max"], from: root, at: 100)]),
              write(tier, [started(by: root, at: 120, step: 0), reply(at: 130, step: 1)],
                    launches: [launch("invoke_subagent", ["Model": "flash", "Prompt": "work"], from: root, at: 120)]),
              write(late, [started(by: root, at: 320, step: 0), reply(at: 330, step: 1)],
                    launches: [launch("swarm", ["action": "add", "name": "reviewer"], from: root, at: 320)]) else { return }

        // The grandchild is read first: its model is two logs away.
        let host = AgentUsageReadTests.Host()
        for id in [grandchild, child, worker, tier, late, root] { host.read(transcript(id), provider: .antigravity) }
        func models(_ id: String) -> [String] { host.store.records.filter { $0.session == id }.map(\.model) }
        suite.expect(models(child) == ["Gemini 4 Argon (High)", "Gemini 4 Argon (High)"],
                     "a subagent keeps the model its parent ran on when it started it, after the parent changes model")
        suite.expect(models(grandchild) == ["Gemini 4 Argon (High)"],
                     "a subagent's subagent inherits through the subagent that started it")
        suite.expect(models(worker) == ["claude-fable-5.1"]
                        && host.store.records.first { $0.session == worker }?.cost != nil,
                     "a swarm worker is priced by the model it was added with")
        suite.expect(models(late) == ["Claude Opus 5.5 (High)"],
                     "a swarm worker added without a model runs on the swarm's own at that time")
        suite.expect(models(tier) == [""], "a subagent started on a tier keeps an unknown model")
        suite.expect(models(root) == ["Gemini 4 Argon (High)", "Claude Opus 5.5 (High)"]
                        && host.store.records.count == 8,
                     "reading a parent for its subagent counts its responses once")
        suite.expect(host.cursors[transcript(child)]?.state.antigravitySubagent == true
                        && host.cursors[transcript(child)]?.parent == transcript(root),
                     "a subagent whose transcript opens with a notice still counts toward its parent")
    }

    // MARK: Helpers

    private static func message(from parent: String, tool: String, arguments: [String: Any], content: String,
                                at timestamp: String) -> Data {
        let call: [String: Any] = ["id": "call", "name": tool,
                                   "argumentsJson": String(decoding: line(arguments), as: UTF8.self)]
        return line(["id": UUID().uuidString, "sender": parent, "timestamp": timestamp, "content": content,
                     "sourceMetadata": ["tool": ["conversationId": parent, "stepIndex": 1, "toolCall": call]]])
    }

    private static func line(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
