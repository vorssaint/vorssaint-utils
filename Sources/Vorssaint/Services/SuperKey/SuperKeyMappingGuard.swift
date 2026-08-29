// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Keeps the selected key recoverable if the app is killed before normal
/// termination can remove its HID mapping. A tiny shell waits on a pipe owned
/// by the app, then replaces itself with this executable's cleanup mode when
/// the pipe closes. The kernel closes it on both ordinary exit and SIGKILL.
enum SuperKeyMappingGuard {
    static let cleanupArgument = "--super-key-mapping-cleanup"
    private static let commandTimeout: TimeInterval = 5

    final class Handle {
        let source: SuperKeySource

        private let process: Process
        private let input: FileHandle
        private let finished: DispatchSemaphore

        fileprivate init?(source: SuperKeySource) {
            guard let executable = Bundle.main.executableURL?.path else { return nil }

            let process = Process()
            let inputPipe = Pipe()
            let finished = DispatchSemaphore(value: 0)
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [
                "-c",
                "IFS= read -r _; exec \"$1\" \"$2\" \"$3\"",
                "sh", executable, cleanupArgument, source.rawValue,
            ]
            process.standardInput = inputPipe
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in finished.signal() }

            do {
                try process.run()
            } catch {
                try? inputPipe.fileHandleForWriting.close()
                return nil
            }

            self.source = source
            self.process = process
            self.input = inputPipe.fileHandleForWriting
            self.finished = finished
        }

        /// Closing the pipe asks the guard to clean now. The app has already
        /// attempted the same clear; this bounded second pass covers a failed
        /// command without ever holding termination indefinitely.
        func stop() -> Bool {
            try? input.close()
            var didFinish = finished.wait(
                timeout: .now() + SuperKeyMappingGuard.commandTimeout + 1
            ) == .success
            if !didFinish {
                process.terminate()
                didFinish = finished.wait(timeout: .now() + 0.5) == .success
            }
            if !didFinish {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.5)
            }
            return didFinish && process.terminationStatus == EXIT_SUCCESS
        }
    }

    static func start(source: SuperKeySource) -> Handle? {
        Handle(source: source)
    }

    /// Runs before NSApplication is created when the waiting guard observes
    /// that its parent disappeared.
    static func runIfRequestedAndExit() {
        let arguments = CommandLine.arguments
        guard arguments.contains(cleanupArgument) else { return }
        guard let source = cleanupSource(in: arguments) else { exit(EXIT_FAILURE) }
        exit(clear(source: source) ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    static func cleanupSource(in arguments: [String]) -> SuperKeySource? {
        guard let index = arguments.firstIndex(of: cleanupArgument),
              arguments.indices.contains(index + 1)
        else { return nil }
        return SuperKeySource(rawValue: arguments[index + 1])
    }

    /// The report is reduced to the table that remains after this feature's
    /// exact source-to-F18 entry is removed. Different external tables are
    /// refused instead of copying one keyboard's mappings onto another.
    static func mappingsAfterCleanup(_ report: String,
                                     source: SuperKeySource) -> [SuperKeyMapping]? {
        SuperKeySupport.consistentMappings(
            report,
            property: SuperKeySupport.userMappingProperty,
            ownedSource: source
        )
    }

    private static func clear(source: SuperKeySource) -> Bool {
        let report = runHID(
            ["property", "--matching", "keyboard",
             "--get", SuperKeySupport.userMappingProperty]
        )
        guard report.status == 0,
              let remaining = mappingsAfterCleanup(report.output, source: source)
        else { return false }
        if SuperKeySupport.mappingReportConfirms(report.output, expected: remaining) {
            return true
        }

        let write = runHID(
            ["property", "--matching", "keyboard",
             "--set", SuperKeySupport.mappingArgument(remaining)]
        )
        guard write.status == 0 else { return false }
        let readback = runHID(
            ["property", "--matching", "keyboard",
             "--get", SuperKeySupport.userMappingProperty]
        )
        return readback.status == 0
            && SuperKeySupport.mappingReportConfirms(readback.output, expected: remaining)
    }

    private static func runHID(_ arguments: [String]) -> (status: Int32, output: String) {
        let result = BoundedProcessRunner.run(
            "/usr/bin/hidutil",
            arguments,
            timeout: commandTimeout,
            maxOutputBytes: 4 * 1024 * 1024
        )
        return (result.status, String(decoding: result.output, as: UTF8.self))
    }
}
