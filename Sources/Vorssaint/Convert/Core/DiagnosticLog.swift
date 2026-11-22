// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import Foundation

/// Diagnostics are explicitly opt-in because converter errors may contain filenames.
enum DiagnosticLog {
    static let enabled = ProcessInfo.processInfo.environment["OPEN_TANGERINE_DEBUG"] == "1"
    static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenTangerine-Diagnostics")
    static let logFile = directory.appendingPathComponent("debug.log")
    private static let queue = DispatchQueue(label: "com.sintaxerror.opentangerine.log")
    static func start() {}
    static func flush() {}
    static func log(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
        guard enabled else { return }
        let entry = Data((String(message().prefix(4000)) + "\n").utf8)
        queue.sync {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let size = try? logFile.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1_000_000 {
                try? Data().write(to: logFile)
            }
            if !FileManager.default.fileExists(atPath: logFile.path) { try? Data().write(to: logFile) }
            if let handle = try? FileHandle(forWritingTo: logFile) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: entry)
            }
        }
    }
}
