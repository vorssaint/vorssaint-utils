// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Adding a login: what the sign-in tools print, the Keychain name Claude
/// Code files a sign-in under, and a flow run against a tool played here.
enum AgentAccountLoginTests {
    static func run(_ suite: TestSuite) {
        output(suite)
        keychainNames(suite)
        claudeFlow(suite)
        codexFlow(suite)
    }

    /// The tool's part: prints `prints` once started, then does what a test
    /// asks when a line is typed in or right away.
    private final class Tool: AgentLoginChild {
        var prints: [String] = []
        /// Called with the typed line, or nil at the start when `waits` is false.
        var answer: ((_ line: String?, _ command: AgentLoginCommand) -> Int32?)?
        var waits = true
        private(set) var command: AgentLoginCommand?
        private(set) var folderMode: Int?
        private(set) var typed: [String] = []
        private(set) var stopped = false
        private var exit: ((Int32) -> Void)?

        func start(_ command: AgentLoginCommand, output: @escaping (String) -> Void,
                   exit: @escaping (Int32) -> Void) throws -> AgentLoginChild {
            self.command = command
            self.exit = exit
            folderMode = AgentAccountTests.mode(command.directory)
            let prints = prints
            DispatchQueue.global().async { [self] in
                prints.forEach(output)
                if !waits, let status = answer?(nil, command) { exit(status) }
            }
            return self
        }

        func send(_ line: String) {
            typed.append(line)
            guard let command, let status = answer?(line, command) else { return }
            exit?(status)
        }

        func stop() { stopped = true }
    }

    private static func text(_ name: String) -> String {
        String(decoding: AgentAccountTests.fixture(name), as: UTF8.self)
    }

    private static func output(_ suite: TestSuite) {
        let claude = text("agent-accounts-claude-login.txt")
        let url = AgentLoginOutput.claudeURL(in: claude)
        suite.expect(url?.host == "claude.com" && url?.absoluteString.hasSuffix("&state=xyz") == true
                        && url?.absoluteString.contains("redirect_uri=https%3A%2F%2Fplatform.claude.com") == true,
                     "the page Claude Code asks for is read whole from its visit line")
        let half = String(claude.prefix(while: { $0 != "&" }))
        suite.expect(AgentLoginOutput.claudeURL(in: half) == nil && AgentLoginOutput.claudeURL(in: "Opening browser to sign in…\n") == nil,
                     "a link still being printed is not one to open")

        let codex = text("agent-accounts-codex-login.txt")
        let prompt = AgentLoginOutput.codexPrompt(in: codex)
        suite.expect(codex.contains("\u{1B}[") && prompt?.url.absoluteString == "https://auth.openai.com/codex/device"
                        && prompt?.code == "Q7ZK-4M2PX",
                     "Codex's link and one-time code are read through its colours")
        let beforeCode = codex.components(separatedBy: "2. Enter")[0]
        suite.expect(AgentLoginOutput.codexPrompt(in: beforeCode) == nil
                        && AgentLoginOutput.codexPrompt(in: beforeCode + "2. Enter this one-time code\r\n   Q7ZK-4M") == nil,
                     "Codex's step shows only once both the link and the whole code are printed")
        suite.expect(AgentLoginOutput.plain("\u{1B}]8;;https://example.com\u{1B}\\link\u{1B}]8;;\u{1B}\\ \u{1B}[1;31mred\u{1B}[0m") == "link red",
                     "terminal hyperlinks and colours are taken out of what a tool prints")
        suite.expect(AgentLoginOutput.lastLine(claude + "\n\u{1B}[31mLogin failed: invalid code\u{1B}[0m\n\n") == "Login failed: invalid code"
                        && AgentLoginOutput.lastLine(claude).hasPrefix("Opening browser"),
                     "the tool's last words leave out its prompt and its link")
    }

    private static func keychainNames(_ suite: TestSuite) {
        // SHA-256("abc") starts ba7816bf.
        suite.expect(AgentLoginOutput.keychainService(configDirectory: "abc") == "Claude Code-credentials-ba7816bf"
                        && AgentLoginOutput.keychainService(configDirectory: "/tmp/caf\u{65}\u{301}")
                            == AgentLoginOutput.keychainService(configDirectory: "/tmp/caf\u{E9}")
                        && AgentLoginOutput.keychainService(configDirectory: "/tmp/cafe") != AgentLoginOutput.keychainService(configDirectory: "/tmp/caf\u{E9}"),
                     "a sign-in's Keychain item is named after the hash of its folder's path in composed form")
        suite.expect(AgentLoginOutput.claudeServices(inDump: text("agent-accounts-keychain-dump.txt")) == ["Claude Code-credentials-1a2b3c4d"],
                     "only Claude Code's items for a folder of their own are picked from the Keychain's list")
    }

    /// A flow with the tool played by `tool`, saving into a store in `home`.
    private static func flow(_ provider: AgentProvider, tool: Tool, home: URL, secrets: AgentAccountTestSecrets,
                             services: @escaping () -> Set<String> = { [] },
                             timeouts: AgentLoginFlow.Timeouts = .init()) -> (AgentLoginFlow, AgentAccountStore) {
        let container = home.appending(path: "AgentAccounts", directoryHint: .isDirectory)
        let store = AgentAccountStore(directory: container, copies: [
            .claude: ClaudeCredentialCopies(secrets: secrets),
            .codex: CodexCredentialCopies(directory: container.appending(path: "codex", directoryHint: .isDirectory))])
        let flow = AgentLoginFlow(provider: provider, executable: URL(fileURLWithPath: "/usr/bin/true"),
                                  environment: ["PATH": "/usr/bin"], container: container, secrets: secrets,
                                  account: AgentAccountTests.user, services: services, runner: tool.start, timeouts: timeouts)
        return (flow, store)
    }

    private static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private static func signIn(_ name: String, in folder: URL) {
        try? Data(#"{"numStartups":1,"oauthAccount":\#(AgentAccountTests.claudeIdentity(name))}"#.utf8)
            .write(to: folder.appending(path: ".claude.json"))
    }

    private static func claudeFlow(_ suite: TestSuite) {
        let home = AgentAccountTests.temporaryFolder("login-claude")
        defer { try? FileManager.default.removeItem(at: home) }
        let user = AgentAccountTests.user
        let credential = String(decoding: AgentAccountTests.claudeCredential("new"), as: UTF8.self)

        // The sign-in works and its item sits under the expected name.
        var secrets = AgentAccountTestSecrets()
        secrets[ClaudeCodeLogin.service, user] = "live"
        var tool = Tool()
        tool.prints = [text("agent-accounts-claude-login.txt")]
        var (flow, store) = flow(.claude, tool: tool, home: home, secrets: secrets)
        let service = flow.keychainService
        tool.answer = { [secrets] _, command in
            signIn("new", in: command.directory)
            secrets[service, user] = credential
            return 0
        }
        var steps: [AgentLoginFlow.Step] = []
        var outcome = flow.run(progress: { [flow] step in
            steps.append(step)
            if case .claude = step { flow.submit("  code#state\n") }
        }, capture: { try store.capture($0, now: AgentAccountTests.now) })
        let saved = store.account("acct-new/org-new")
        suite.expect(outcome == .added("acct-new/org-new") && saved?.email == "new@example.com"
                        && secrets[ClaudeCredentialCopies.service, "acct-new/org-new"] == credential
                        && String(decoding: saved?.identity ?? Data(), as: UTF8.self) == AgentAccountTests.claudeIdentity("new"),
                     "a Claude sign-in in a folder of its own is saved like a live login")
        suite.expect(tool.command?.arguments == ["auth", "login", "--claudeai"]
                        && tool.command?.environment["CLAUDE_CONFIG_DIR"] == flow.directory.path
                        && tool.command?.environment["PATH"] == "/usr/bin" && tool.folderMode == 0o700
                        && flow.directory.lastPathComponent.hasPrefix("login-") && tool.typed == ["code#state"],
                     "Claude Code is pointed at an owner-only folder and typed the code without its spaces")
        suite.expect(steps.count == 3 && steps.last == .finishing && secrets[service, user] == nil && !exists(flow.directory)
                        && secrets[ClaudeCodeLogin.service, user] == "live" && !tool.stopped,
                     "the sign-in's Keychain item and folder are gone once the login is kept, and the live login untouched")

        // Claude Code refuses the code after it made an item.
        secrets = AgentAccountTestSecrets()
        tool = Tool()
        tool.prints = [text("agent-accounts-claude-login.txt")]
        (flow, store) = Self.flow(.claude, tool: tool, home: home, secrets: secrets)
        let refused = flow.keychainService
        tool.answer = { [secrets] _, _ in
            secrets[refused, user] = credential
            return 1
        }
        tool.prints.append("\nLogin failed: invalid code\n")
        var captured = 0
        outcome = flow.run(progress: { [flow] step in if case .claude = step { flow.submit("wrong") } }, capture: { _ in captured += 1 })
        suite.expect(outcome == .failed("Login failed: invalid code") && captured == 0 && secrets[refused, user] == nil
                        && !exists(flow.directory) && refused != service,
                     "a sign-in the tool gives up on says so in its words and leaves nothing behind")

        // A Claude Code that names its item some other way.
        secrets = AgentAccountTestSecrets()
        secrets["Claude Code-credentials-0ld0ld00", user] = "someone else's"
        tool = Tool()
        tool.prints = [text("agent-accounts-claude-login.txt")]
        var listed: Set<String> = ["Claude Code-credentials-0ld0ld00"]
        (flow, store) = Self.flow(.claude, tool: tool, home: home, secrets: secrets, services: { listed })
        tool.answer = { [secrets] _, command in
            signIn("other", in: command.directory)
            secrets["Claude Code-credentials-ffffffff", user] = credential
            listed.insert("Claude Code-credentials-ffffffff")
            return 0
        }
        outcome = flow.run(progress: { [flow] step in if case .claude = step { flow.submit("code") } },
                           capture: { try store.capture($0, now: AgentAccountTests.now) })
        suite.expect(outcome == .added("acct-other/org-other") && secrets["Claude Code-credentials-ffffffff", user] == nil
                        && secrets["Claude Code-credentials-0ld0ld00", user] == "someone else's",
                     "an item under another name is found as the one made since the sign-in began, and only that one is deleted")

        // The login cannot be kept.
        secrets = AgentAccountTestSecrets()
        tool = Tool()
        tool.waits = false
        (flow, store) = Self.flow(.claude, tool: tool, home: home, secrets: secrets)
        let unkept = flow.keychainService
        tool.answer = { [secrets] _, command in
            signIn("new", in: command.directory)
            secrets[unkept, user] = credential
            return 0
        }
        outcome = flow.run(progress: { _ in }, capture: { _ in throw AgentCredentialCopyError(message: "full") })
        var failed = false
        if case .failed = outcome { failed = true }
        suite.expect(failed && secrets[unkept, user] == nil && !exists(flow.directory),
                     "a login that cannot be saved is cleaned up all the same")

        // The person changes their mind, or never comes back.
        tool = Tool()
        tool.prints = [text("agent-accounts-claude-login.txt")]
        (flow, store) = Self.flow(.claude, tool: tool, home: home, secrets: secrets)
        outcome = flow.run(progress: { [flow] _ in flow.cancel() }, capture: { _ in captured += 1 })
        suite.expect(outcome == .cancelled && tool.stopped && tool.typed.isEmpty && !exists(flow.directory) && captured == 0,
                     "cancelling ends the tool and removes its folder")
        tool = Tool()
        (flow, store) = Self.flow(.claude, tool: tool, home: home, secrets: secrets, timeouts: .init(signIn: 0.1, afterCode: 0.1))
        outcome = flow.run(progress: { _ in }, capture: { _ in captured += 1 })
        suite.expect(outcome == .failed("timed out") && tool.stopped && !exists(flow.directory) && captured == 0,
                     "a sign-in nobody finishes is ended and cleaned up")
        _ = store
    }

    private static func codexFlow(_ suite: TestSuite) {
        let home = AgentAccountTests.temporaryFolder("login-codex")
        defer { try? FileManager.default.removeItem(at: home) }
        let secrets = AgentAccountTestSecrets()
        let auth = AgentAccountTests.codexAuth(account: "c0de-9", email: "nine@example.com", plan: "plus")
        let printed = text("agent-accounts-codex-login.txt")
        let cut = printed.index(printed.startIndex, offsetBy: printed.count / 2)

        var tool = Tool()
        tool.prints = [String(printed[..<cut]), String(printed[cut...])]
        tool.waits = false
        var existed = false
        tool.answer = { _, command in
            existed = exists(command.directory)
            try? auth.write(to: command.directory.appending(path: "auth.json"))
            return 0
        }
        var (flow, store) = flow(.codex, tool: tool, home: home, secrets: secrets)
        var steps: [AgentLoginFlow.Step] = []
        var outcome = flow.run(progress: { steps.append($0) }, capture: { try store.capture($0, now: AgentAccountTests.now) })
        let copy = home.appending(path: "AgentAccounts/codex/c0de-9/auth.json")
        suite.expect(outcome == .added("c0de-9") && store.account("c0de-9")?.organization == "plus"
                        && (try? Data(contentsOf: copy)) == auth && AgentAccountTests.mode(copy) == 0o600,
                     "a Codex sign-in lands as an owner-only copy among the saved logins")
        suite.expect(existed && tool.folderMode == 0o700 && tool.command?.arguments == ["login", "--device-auth"]
                        && tool.command?.environment["CODEX_HOME"] == flow.directory.path && !exists(flow.directory)
                        && steps.first == .codex(url: URL(string: "https://auth.openai.com/codex/device")!, code: "Q7ZK-4M2PX")
                        && steps.last == .finishing && secrets.items.isEmpty,
                     "Codex gets a folder that is already there, its code is shown once, and the folder goes afterwards")

        tool = Tool()
        tool.waits = false
        tool.answer = { _, _ in 0 }
        (flow, store) = Self.flow(.codex, tool: tool, home: home, secrets: secrets)
        outcome = flow.run(progress: { _ in }, capture: { try store.capture($0, now: AgentAccountTests.now) })
        suite.expect(outcome == .failed("the sign-in left no login") && !exists(flow.directory) && store.accounts.count == 1,
                     "a Codex that ends without a login saves nothing and leaves nothing")
    }
}
