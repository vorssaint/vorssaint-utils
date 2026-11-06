// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import IOKit

/// A pipe closes even on SIGKILL. The helper then removes only our exact HID
/// entries, preserving external mappings. No launch agent or driver remains.
enum KeyboardRemapGuard {
    static let cleanupArgument = "--keyboard-remap-cleanup"
    final class Handle {
        private let process: Process
        private let input: FileHandle
        private let finished = DispatchSemaphore(value: 0)
        init?(mappings: [SuperKeyMapping]) {
            guard let executable = Bundle.main.executableURL?.path else { return nil }
            process = Process()
            let pipe = Pipe()
            input = pipe.fileHandleForWriting
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "IFS= read -r _; exec \"$1\" \"$2\" \"$3\"",
                                 "sh", executable, cleanupArgument, KeyboardRemapSupport.storage(mappings)]
            process.standardInput = pipe
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let signal = finished
            process.terminationHandler = { _ in signal.signal() }
            do { try process.run() } catch { try? input.close(); return nil }
        }
        func stop() -> Bool {
            try? input.close()
            var done = finished.wait(timeout: .now() + 16) == .success
            if !done {
                process.terminate()
                done = finished.wait(timeout: .now() + 0.5) == .success
            }
            if !done {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.5)
            }
            return done && process.terminationStatus == EXIT_SUCCESS
        }
    }

    static func runIfRequestedAndExit() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: cleanupArgument) else { return }
        guard args.indices.contains(index + 1) else { exit(EXIT_FAILURE) }
        let owned = KeyboardRemapSupport.storedMappings(args[index + 1])
        guard !owned.isEmpty else { exit(EXIT_FAILURE) }
        exit(clear(owned: owned) ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    /// hidutil --get HIDKeyboardModifierMappingPairs can return null even
    /// when the keyboard filter has loaded mappings from its service properties.
    static func systemModifierMappings() -> [[SuperKeyMapping]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching("IOHIDEventService"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var tables: [[SuperKeyMapping]] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let properties = IORegistryEntryCreateCFProperty(service,
                "HIDEventServiceProperties" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
                let entries = properties["HIDKeyboardModifierMappingPairs"] as? [[String: NSNumber]] else { continue }
            tables.append(entries.compactMap {
                guard let source = $0["HIDKeyboardModifierMappingSrc"],
                      let destination = $0["HIDKeyboardModifierMappingDst"] else { return nil }
                return SuperKeyMapping(source: source.uint64Value, destination: destination.uint64Value)
            })
        }
        return tables
    }

    static func read() -> (status: Int32, output: String) {
        run(["property", "--matching", "keyboard", "--get", SuperKeySupport.userMappingProperty])
    }
    static func write(_ mappings: [SuperKeyMapping]) -> Bool {
        let write = run(["property", "--matching", "keyboard", "--set", KeyboardRemapSupport.storage(mappings)])
        guard write.status == 0 else { return false }
        let report = read()
        return report.status == 0 && SuperKeySupport.mappingReportConfirms(report.output, expected: mappings)
    }
    static func clear(owned: [SuperKeyMapping]) -> Bool {
        guard !owned.isEmpty else { return true }
        let report = read()
        guard report.status == 0,
              let remaining = KeyboardRemapSupport.remainingMappings(report.output, owned: owned) else { return false }
        if SuperKeySupport.mappingReportConfirms(report.output, expected: remaining) { return true }
        return write(remaining)
    }
    private static func run(_ args: [String]) -> (status: Int32, output: String) {
        let result = BoundedProcessRunner.run("/usr/bin/hidutil", args, timeout: 5, maxOutputBytes: 4 * 1024 * 1024)
        return (result.status, String(decoding: result.output, as: UTF8.self))
    }
}
