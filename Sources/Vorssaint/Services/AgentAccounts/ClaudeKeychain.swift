// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where Claude Code logins are kept: the live one Claude Code reads, and the
/// copies of saved accounts. A protocol so tests swap in a store in memory.
protocol ClaudeSecretStore {
    /// Nil when there is no such item.
    func read(service: String, account: String) throws -> String?
    func write(_ value: String, service: String, account: String) throws
    /// Deleting an item that is not there succeeds.
    func delete(service: String, account: String) throws
}

/// The Keychain could not be read or written. `message` is for logs and
/// support, not for the person.
struct ClaudeKeychainError: Error, Equatable {
    let message: String
}

/// Generic passwords through `/usr/bin/security`, never Security.framework.
///
/// Claude Code reads and writes its login with that tool, so the item's access
/// list names `security` and nothing else. Writing it with the framework would
/// add this app's signature to the list, and macOS would then ask "wants to use
/// your keychain" for Claude Code, and for Vorssaint after every re-sign. The
/// copies of saved accounts go the same way, so one rule covers both.
///
/// The approach, the exit code for a missing item and the limit on a line read
/// from stdin are findings of claude-swap (MIT, github.com/realiti4/claude-swap).
struct ClaudeKeychain: ClaudeSecretStore {
    /// `security` reports a missing item with this exit code.
    static let notFound: Int32 = 44
    /// Longer lines are cut by the tool's interactive reader.
    static let maximumLine = 4032
    static let timeout: TimeInterval = 5

    /// The tool to run; tests point it at a script.
    var tool = "/usr/bin/security"

    func read(service: String, account: String) throws -> String? {
        let result = try run(["find-generic-password", "-a", account, "-s", service, "-w"])
        if result.status == Self.notFound { return nil }
        guard result.status == 0, var text = String(data: result.output, encoding: .utf8) else {
            throw ClaudeKeychainError(message: "find-generic-password returned \(result.status)")
        }
        // The tool adds one newline; any other belongs to the value.
        if text.hasSuffix("\n") { text.removeLast() }
        return Self.decoded(text)
    }

    func write(_ value: String, service: String, account: String) throws {
        let hex = Data(value.utf8).map { String(format: "%02x", $0) }.joined()
        let line = Self.addCommand(service: service, account: account, hex: hex)
        // Over stdin the secret never shows in the process list. A value too
        // long for one line has no other way in than the arguments.
        let result = line.utf8.count <= Self.maximumLine
            ? try run(["-i"], input: Data(line.utf8))
            : try run(["add-generic-password", "-U", "-a", account, "-s", service, "-X", hex])
        // The interactive tool exits with 0 whatever its command returned, so
        // only reading the item back says that it was stored.
        guard result.status == 0, try read(service: service, account: account) == value else {
            throw ClaudeKeychainError(message: "add-generic-password did not store the item (\(result.status))")
        }
    }

    func delete(service: String, account: String) throws {
        let result = try run(["delete-generic-password", "-a", account, "-s", service])
        guard result.status == 0 || result.status == Self.notFound else {
            throw ClaudeKeychainError(message: "delete-generic-password returned \(result.status)")
        }
    }

    /// The names of the logins Claude Code keeps for a configuration folder
    /// of its own. `dump-keychain` without `-d` lists what each item is
    /// called and never a secret, so nothing here asks the person anything.
    /// Empty when the list could not be read.
    func claudeServices() -> Set<String> {
        guard let result = try? run(["dump-keychain"]), result.status == 0 else { return [] }
        return AgentLoginOutput.claudeServices(inDump: String(decoding: result.output, as: UTF8.self))
    }

    /// The line `security -i` reads to store a value given as hex.
    static func addCommand(service: String, account: String, hex: String) -> String {
        "add-generic-password -U -a \(quoted(account)) -s \(quoted(service)) -X \(hex)\n"
    }

    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// `security` prints a value with characters outside printable ASCII as
    /// hex. Everything kept here is JSON text, which never starts with a hex
    /// digit pair that is not also valid JSON on its own, so output that is
    /// all hex and does not open an object is that encoding.
    static func decoded(_ text: String) -> String {
        guard !text.hasPrefix("{"), !text.isEmpty, text.utf8.count.isMultiple(of: 2),
              text.utf8.allSatisfy({ $0.isHexDigit }) else { return text }
        var bytes = [UInt8]()
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return text }
            bytes.append(byte)
            index = next
        }
        return String(bytes: bytes, encoding: .utf8) ?? text
    }

    /// Runs the tool, giving it `input` on stdin, and ends it after the
    /// timeout: a Keychain prompt nobody answers must not hold the queue.
    private func run(_ arguments: [String], input: Data? = nil) throws -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch {
            throw ClaudeKeychainError(message: "security could not be started")
        }
        // Closing stdin is what ends the interactive tool.
        if let input { try? stdin.fileHandleForWriting.write(contentsOf: input) }
        try? stdin.fileHandleForWriting.close()

        let reader = stdout.fileHandleForReading
        let output = Output()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            output.set((try? reader.readToEnd()) ?? Data())
            drained.signal()
        }
        guard exited.wait(timeout: .now() + Self.timeout) == .success else {
            process.terminate()
            if exited.wait(timeout: .now() + 0.5) != .success { kill(process.processIdentifier, SIGKILL) }
            throw ClaudeKeychainError(message: "security timed out")
        }
        _ = drained.wait(timeout: .now() + 1)
        return (process.terminationStatus, output.value)
    }

    /// What the tool printed, handed from the reading thread to the caller.
    private final class Output: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        var value: Data { lock.withLock { data } }
        func set(_ value: Data) { lock.withLock { data = value } }
    }
}

private extension UInt8 {
    var isHexDigit: Bool {
        (48...57).contains(self) || (65...70).contains(self) || (97...102).contains(self)
    }
}
