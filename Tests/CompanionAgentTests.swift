// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// runs the real check + question code vs fake cli tools in a temp home, no acct or network touched
enum CompanionAgentTests {
    private static func install(_ name: String, script: String, home: URL) {
        let folder = home.appending(path: ".local/bin")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: name)
        try? script.write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    }

    private static let claude = """
    #!/bin/sh
    if [ "$1" = auth ]; then
      if [ "$STUB_MODE" = loggedout ]; then echo '{"loggedIn": false}'; else echo '{"loggedIn": true}'; fi
      exit 0
    fi
    case "$STUB_MODE" in
      pwd) pwd; exit 0;;
      blocked) echo "Your organization has disabled Claude subscription access for Claude Code"; exit 1;;
      needskey) if [ -n "$ANTHROPIC_API_KEY" ]; then echo "ready via key"; exit 0; fi; echo "no subscription"; exit 1;;
    esac
    if [ -n "$ANTHROPIC_API_KEY" ]; then echo "used the key"; exit 0; fi
    echo "ready"
    """

    private static let codex = """
    #!/bin/sh
    if [ "$1" = login ]; then echo "Logged in using ChatGPT"; exit 0; fi
    out=""
    while [ $# -gt 0 ]; do if [ "$1" = "-o" ]; then out="$2"; fi; shift; done
    echo "OpenAI Codex banner"; echo "tokens used 5"
    if [ -n "$out" ]; then echo "the answer" > "$out"; fi
    """

    static func run(_ suite: TestSuite) {
        suite.run("companion-agent") {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: home) }
            install("claude", script: claude, home: home)
            install("codex", script: codex, home: home)
            let suiteName = "vorss.tests.companion-agent.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suiteName) else { suite.expect(false, "test defaults"); return }
            defer { defaults.removePersistentDomain(forName: suiteName) }
            func context(_ mode: String, key: Bool = false) -> CompanionContext {
                var env = ["STUB_MODE": mode]
                if key { env["ANTHROPIC_API_KEY"] = "test-key" }
                return CompanionContext(home: home, defaults: defaults, environment: env)
            }
            func verified() -> [String: Double] {
                defaults.dictionary(forKey: DefaultsKey.companionChatVerified) as? [String: Double] ?? [:]
            }
            func check(_ context: CompanionContext) -> CompanionHealth {
                CompanionAgent.claude.checkHealth(cancellation: BoundedProcessCancellation(), context: context)
            }

            suite.expect(check(context("ok")) == .ready && verified()["claude"] != nil,
                         "a signed-in tool that answers is ready and remembered")
            // a check that is stopped halfway says nothing about the tool: the saved pass stays
            let stopped = BoundedProcessCancellation()
            _ = CompanionAgent.claude.checkHealth(cancellation: stopped, context: context("blocked"),
                                                  onSignedIn: { stopped.cancel() })
            suite.expect(verified()["claude"] != nil, "a stopped check keeps an earlier pass instead of wiping it")
            defaults.removePersistentDomain(forName: suiteName)
            suite.expect(check(context("loggedout")) == .notSignedIn && verified()["claude"] == nil,
                         "a signed-out tool is not signed in and is not remembered")
            suite.expect(check(context("ok", key: true)) == .ready,
                         "the subscription is tried first: with a key set the stand-in is still run without it")
            suite.expect((try? CompanionAgent.claude.ask("hi", cancellation: BoundedProcessCancellation(),
                                                         context: context("ok", key: true))) == "ready",
                         "a question uses the subscription, never the key, when that works")
            suite.expect((try? CompanionAgent.claude.ask("hi", cancellation: BoundedProcessCancellation(),
                                                         context: context("needskey", key: true))) == "ready via key",
                         "the key is only the fallback when the subscription fails")
            suite.expect((try? CompanionAgent.claude.ask("hi", cancellation: BoundedProcessCancellation(),
                                                         context: context("needskey"))) == nil,
                         "no key and no subscription is a failure")
            defaults.removePersistentDomain(forName: suiteName)
            if case .noAnswer(let blocked, let reason) = check(context("blocked")) {
                suite.expect(blocked && reason.contains("organization has disabled"),
                             "an organization block is reported as blocked with the tool's own reason")
            } else { suite.expect(false, "a blocked subscription is no answer") }
            suite.expect(verified()["claude"] == nil, "a failed check is not remembered")

            let folder = try? CompanionAgent.claude.ask("hi", cancellation: BoundedProcessCancellation(), context: context("pwd"))
            suite.expect(folder?.hasSuffix("vorssaint-companion") == true && folder != "/",
                         "the tools run from an empty folder of their own, not the root of the disk")
            let answer = try? CompanionAgent.chatgpt.ask("hi", cancellation: BoundedProcessCancellation(), context: context("ok"))
            suite.expect(answer == "the answer", "Codex shows its final message only, without its banner or token log")
            suite.expect(CompanionAgent.chatgpt.checkHealth(cancellation: BoundedProcessCancellation(), context: context("ok")) == .ready,
                         "Codex is ready when signed in and answering")
            suite.expect(CompanionAgent.prompt(history: [], question: "q") == "q"
                         && CompanionAgent.prompt(history: [CompanionMessage(id: "1", isUser: true, text: "a")], question: "q")
                            .hasPrefix("Conversation so far:"), "earlier turns are folded into the prompt")
        }
    }
}
