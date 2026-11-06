// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Darwin
import Foundation

/// What a provider's sign-in tool prints, read for the few things the app
/// shows: the link to open, the code to type, and why it gave up.
enum AgentLoginOutput {
    /// Colours, cursor moves and terminal hyperlinks, which Codex prints even
    /// into a pipe.
    private static let escapes = try? NSRegularExpression(
        pattern: "\u{1B}\\][^\u{07}\u{1B}]*(?:\u{07}|\u{1B}\\\\)|\u{1B}\\[[0-9;?]*[ -/]*[@-~]|\u{1B}[@-Z\\\\^_]")
    private static let link = try? NSRegularExpression(pattern: "https://[^\\s\"'<>]+")
    private static let deviceCode = try? NSRegularExpression(pattern: "(?<![A-Za-z0-9-])[A-Z0-9]{4}-[A-Z0-9]{4,6}(?![A-Za-z0-9-])")

    static func plain(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return (escapes?.stringByReplacingMatches(in: text, range: range, withTemplate: "") ?? text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// What has been printed up to its last line end: the tool may be half
    /// way through a line, and half a link is not one to open.
    static func completeLines(_ text: String) -> Substring {
        guard let end = text.lastIndex(of: "\n") else { return "" }
        return text[...end]
    }

    /// The page Claude Code asks the person to visit.
    static func claudeURL(in output: String) -> URL? {
        let text = String(completeLines(plain(output)))
        guard let marker = text.range(of: "visit:") else { return nil }
        return first(link, in: text, from: marker.upperBound).flatMap(URL.init(string:))
    }

    /// The page and the one-time code of Codex's device sign-in, once both
    /// are printed.
    static func codexPrompt(in output: String) -> (url: URL, code: String)? {
        let text = String(completeLines(plain(output)))
        guard let open = text.range(of: "Open this link"), let once = text.range(of: "one-time code"),
              let url = first(link, in: text, from: open.upperBound).flatMap(URL.init(string:)),
              let code = first(deviceCode, in: text, from: once.upperBound) else { return nil }
        return (url, code)
    }

    /// The tool's last words, for the person to read when it gave up. Empty
    /// when it said nothing but its prompts.
    static func lastLine(_ output: String) -> String {
        let line = plain(output).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last {
            !$0.isEmpty && !$0.contains("https://") && !$0.contains("Paste code here")
        }
        return String((line ?? "").prefix(200))
    }

    /// The Keychain item Claude Code keeps a login under when it runs with a
    /// configuration folder of its own: the usual name, then the start of the
    /// SHA-256 of that folder's path as it was given. A finding of
    /// claude-swap (MIT, github.com/realiti4/claude-swap).
    static func keychainService(configDirectory: String) -> String {
        let digest = SHA256.hash(data: Data(configDirectory.precomposedStringWithCanonicalMapping.utf8))
        return "\(ClaudeCodeLogin.service)-" + digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// The names of Claude Code's logins under a folder of their own, from
    /// what `security dump-keychain` lists. It lists names only, no secrets.
    static func claudeServices(inDump dump: String) -> Set<String> {
        let marker = "\"svce\"<blob>=\""
        return Set(dump.split(separator: "\n").compactMap { line -> String? in
            guard let start = line.range(of: marker)?.upperBound, let end = line[start...].lastIndex(of: "\"") else { return nil }
            let name = String(line[start..<end])
            return name.hasPrefix("\(ClaudeCodeLogin.service)-") ? name : nil
        })
    }

    private static func first(_ expression: NSRegularExpression?, in text: String, from start: String.Index) -> String? {
        guard let match = expression?.firstMatch(in: text, range: NSRange(start..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }
}

/// The sign-in tool to start.
struct AgentLoginCommand: Equatable {
    let executable: URL
    let arguments: [String]
    let environment: [String: String]
    /// The folder it runs in.
    let directory: URL
}

/// A sign-in tool that runs.
protocol AgentLoginChild: AnyObject {
    /// Types a line into it.
    func send(_ line: String)
    /// Ends it: asked first, then made to.
    func stop()
}

/// Starts a sign-in tool. `output` hears what it prints as it prints it and
/// `exit` its status once it is gone, both on a thread of their own. Tests
/// play the tool's part instead.
typealias AgentLoginRunner = (_ command: AgentLoginCommand, _ output: @escaping (String) -> Void,
                              _ exit: @escaping (Int32) -> Void) throws -> AgentLoginChild

/// The real tool, with one pipe for everything it prints and its input left
/// open for the code Claude Code waits for.
final class AgentLoginProcess: AgentLoginChild {
    private let process = Process()
    private let input = Pipe()

    static func start(_ command: AgentLoginCommand, output: @escaping (String) -> Void,
                      exit: @escaping (Int32) -> Void) throws -> AgentLoginChild {
        let child = AgentLoginProcess()
        let printed = Pipe()
        child.process.executableURL = command.executable
        child.process.arguments = command.arguments
        child.process.environment = command.environment
        child.process.currentDirectoryURL = command.directory
        child.process.standardInput = child.input
        child.process.standardOutput = printed
        child.process.standardError = printed
        // A tool that exits early fails a write instead of ending the app.
        _ = fcntl(child.input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let reader = printed.fileHandleForReading
        reader.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { output(String(decoding: chunk, as: UTF8.self)) }
        }
        child.process.terminationHandler = { process in
            // Its last words are still on their way through the pipe.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
                reader.readabilityHandler = nil
                exit(process.terminationStatus)
            }
        }
        do { try child.process.run() } catch {
            reader.readabilityHandler = nil
            throw error
        }
        return child
    }

    func send(_ line: String) {
        try? input.fileHandleForWriting.write(contentsOf: Data("\(line)\n".utf8))
    }

    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        let child = process
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }
}

/// Adds a login by running the provider's own sign-in tool in a private
/// folder of its own, so the login the tool uses meanwhile is neither read
/// nor written. The person signs in with the provider in their browser; what
/// the tool then leaves in that folder, and for Claude Code in a Keychain
/// item named after it, is handed to `capture` and removed again, whether
/// the sign-in worked or not.
///
/// `run` blocks until the sign-in ends: give it a thread of its own.
final class AgentLoginFlow {
    enum Step: Equatable {
        /// Claude Code opened this page and waits for the code it shows.
        case claude(url: URL)
        /// Codex waits for this code to be typed into this page.
        case codex(url: URL, code: String)
        /// The tool is done or has the code; the login is being read.
        case finishing
    }

    enum Outcome: Equatable {
        case added(AgentAccount.ID)
        /// The text is the tool's own last line, or says what was missing.
        case failed(String)
        case cancelled
    }

    struct Timeouts {
        /// How long the person has to sign in; Codex's code lasts as long.
        var signIn: TimeInterval = 15 * 60
        /// How long Claude Code has once it was given the code.
        var afterCode: TimeInterval = 2 * 60
    }

    let provider: AgentProvider
    /// The tool's configuration folder for this one sign-in.
    let directory: URL
    private let executable: URL
    private let environment: [String: String]
    private let container: URL
    private let secrets: ClaudeSecretStore
    private let account: String
    private let services: () -> Set<String>
    private let runner: AgentLoginRunner
    private let timeouts: Timeouts

    private let state = NSCondition()
    private var output = ""
    private var status: Int32?
    private var code: String?
    private var cancelled = false
    private var reported: Step?
    /// Keychain items the tool made that are not under the expected name.
    private var found: Set<String> = []

    /// `container` is the folder the saved logins live in; `services` lists
    /// the Keychain names of Claude Code's logins, see `claudeServices`.
    init(provider: AgentProvider, executable: URL, environment: [String: String], container: URL,
         secrets: ClaudeSecretStore, account: String = ClaudeCodeLogin.keychainAccount,
         services: @escaping () -> Set<String>, runner: @escaping AgentLoginRunner = AgentLoginProcess.start,
         timeouts: Timeouts = Timeouts()) {
        self.provider = provider
        self.executable = executable
        self.environment = environment
        self.container = container
        self.secrets = secrets
        self.account = account
        self.services = services
        self.runner = runner
        self.timeouts = timeouts
        directory = container.appending(path: "login-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    var command: AgentLoginCommand {
        var environment = environment
        let arguments: [String]
        switch provider {
        case .codex:
            environment["CODEX_HOME"] = directory.path
            // The plain sign-in listens on a port a running Codex may hold.
            arguments = ["login", "--device-auth"]
        default:
            environment["CLAUDE_CONFIG_DIR"] = directory.path
            arguments = ["auth", "login", "--claudeai"]
        }
        return AgentLoginCommand(executable: executable, arguments: arguments, environment: environment, directory: directory)
    }

    /// The Keychain item Claude Code files this sign-in under.
    var keychainService: String { AgentLoginOutput.keychainService(configDirectory: directory.path) }

    /// The code the browser showed, for Claude Code.
    func submit(_ code: String) {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        state.withLock {
            self.code = code
            state.broadcast()
        }
    }

    func cancel() {
        state.withLock {
            cancelled = true
            state.broadcast()
        }
    }

    /// Runs the sign-in to its end. `progress` hears each step once, on this
    /// thread or the tool's; `capture` saves the login that came of it.
    func run(progress: @escaping (Step) -> Void, capture: (AgentLiveLogin) throws -> Void) -> Outcome {
        defer { cleanUp() }
        // Codex refuses a folder that is not there.
        guard PrivateFileStore.createDirectory(at: directory, container: container) else {
            return .failed("the sign-in folder could not be made")
        }
        let before = provider == .claude ? services() : []
        guard !state.withLock({ cancelled }) else { return .cancelled }
        let child: AgentLoginChild
        do {
            child = try runner(command, { [weak self] in self?.heard($0, progress: progress) }, { [weak self] status in
                guard let self else { return }
                self.state.withLock {
                    self.status = status
                    self.state.broadcast()
                }
            })
        } catch {
            return .failed("the sign-in tool could not be started")
        }

        var deadline = Date().addingTimeInterval(timeouts.signIn)
        state.lock()
        while status == nil, !cancelled {
            if let code {
                self.code = nil
                state.unlock()
                child.send(code)
                progress(.finishing)
                state.lock()
                deadline = Date().addingTimeInterval(timeouts.afterCode)
                continue
            }
            if !state.wait(until: deadline) { break }
        }
        let status = status, cancelled = cancelled, output = output
        state.unlock()

        guard !cancelled else { child.stop(); return .cancelled }
        guard let status else { child.stop(); return .failed("timed out") }
        guard status == 0 else {
            let line = AgentLoginOutput.lastLine(output)
            return .failed(line.isEmpty ? "exit \(status)" : line)
        }
        progress(.finishing)
        do {
            guard let live = try provider == .claude ? claudeLogin(before: before) : codexLogin() else {
                return .failed("the sign-in left no login")
            }
            try capture(live)
            return .added(live.id)
        } catch {
            return .failed("\(error)")
        }
    }

    private func heard(_ chunk: String, progress: (Step) -> Void) {
        let step: Step? = state.withLock {
            output += chunk
            guard reported == nil else { return nil }
            switch provider {
            case .codex: reported = AgentLoginOutput.codexPrompt(in: output).map { .codex(url: $0.url, code: $0.code) }
            default: reported = AgentLoginOutput.claudeURL(in: output).map { .claude(url: $0) }
            }
            return reported
        }
        if let step { progress(step) }
    }

    private func claudeLogin(before: Set<String>) throws -> AgentLiveLogin? {
        var credential = try secrets.read(service: keychainService, account: account)
        if credential == nil {
            // Named some other way by this version of Claude Code: whatever
            // it filed since the sign-in began is the one.
            found = services().subtracting(before)
            credential = try found.lazy.compactMap { try self.secrets.read(service: $0, account: self.account) }.first
        }
        // Where Claude Code could not use the Keychain it keeps a file.
        let file = directory.appending(path: ".credentials.json", directoryHint: .notDirectory)
        guard let credential = credential.map({ Data($0.utf8) }) ?? (try? Data(contentsOf: file)),
              ClaudeCodeLogin.tokens(credential) != nil,
              let config = try? Data(contentsOf: directory.appending(path: ".claude.json", directoryHint: .notDirectory)),
              let identity = ClaudeCodeLogin.liveIdentity(in: config),
              let who = ClaudeCodeLogin.identity(identity) else { return nil }
        return AgentLiveLogin(id: who.id, provider: .claude, email: who.email, organization: who.organization,
                              identity: identity, credential: credential)
    }

    private func codexLogin() -> AgentLiveLogin? {
        guard let auth = try? Data(contentsOf: directory.appending(path: "auth.json", directoryHint: .notDirectory)),
              let who = CodexLogin.identity(auth) else { return nil }
        return AgentLiveLogin(id: who.id, provider: .codex, email: who.email, organization: who.plan,
                              identity: Data(), credential: auth)
    }

    /// Nothing of the sign-in stays behind: the saved copy is the only one.
    private func cleanUp() {
        if provider == .claude {
            for service in found.union([keychainService]) { try? secrets.delete(service: service, account: account) }
        }
        try? FileManager.default.removeItem(at: directory)
    }
}
