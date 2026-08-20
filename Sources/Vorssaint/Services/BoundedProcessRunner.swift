// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

private final class BoundedProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        let available = max(0, limit - data.count)
        if available > 0 { data.append(chunk.prefix(available)) }
    }

    func value() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

enum BoundedProcessRunner {
    struct Result {
        let status: Int32
        let output: Data
        let timedOut: Bool
    }

    static func run(_ path: String,
                    _ arguments: [String],
                    timeout: TimeInterval,
                    maxOutputBytes: Int,
                    input: Data? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        if input != nil {
            process.standardInput = Pipe()
        }

        let output = BoundedProcessOutput(limit: maxOutputBytes)
        let drained = DispatchSemaphore(value: 0)
        let reader = pipe.fileHandleForReading
        reader.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                drained.signal()
            } else {
                // Keep draining after the retained prefix is full so the child
                // can never block on a full pipe or turn output into memory use.
                output.append(chunk)
            }
        }

        do {
            try process.run()
        } catch {
            reader.readabilityHandler = nil
            try? reader.close()
            return Result(status: -1, output: Data(), timedOut: false)
        }

        if let input, let stdin = process.standardInput as? Pipe {
            stdin.fileHandleForWriting.write(input)
            stdin.fileHandleForWriting.closeFile()
        }

        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            finished.signal()
        }

        var didFinish = finished.wait(timeout: .now() + max(0, timeout)) == .success
        let timedOut = !didFinish
        if timedOut {
            process.terminate()
            didFinish = finished.wait(timeout: .now() + 0.5) == .success
            if !didFinish {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.5)
            }
        }

        // A child may inherit stdout after the command itself exits. Give an
        // ordinary EOF a moment to deliver the tail, then close our descriptor
        // so that inherited handle cannot leave a reader alive indefinitely.
        _ = drained.wait(timeout: .now() + 0.2)
        reader.readabilityHandler = nil
        try? reader.close()

        return Result(status: timedOut ? -1 : process.terminationStatus,
                      output: output.value(),
                      timedOut: timedOut)
    }
}
