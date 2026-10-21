// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Executes only a script file explicitly chosen and confirmed in the workspace.
/// Selected paths are individual arguments, never interpolated into source code.
enum FinderScriptOperation {
    static func run(_ script: URL, selection: [URL], directory: URL?,
                    cancellation: FinderToolsCancellation) throws -> String {
        let executable: URL
        switch script.pathExtension.lowercased() {
        case "sh", "zsh": executable = URL(fileURLWithPath: "/bin/zsh")
        case "scpt", "applescript": executable = URL(fileURLWithPath: "/usr/bin/osascript")
        case "py": executable = URL(fileURLWithPath: "/usr/bin/python3")
        default: throw FinderFileActionError.unsupported(script, "Choose a shell, AppleScript or Python script")
        }
        guard FileManager.default.fileExists(atPath: executable.path) else {
            throw FinderFileActionError.unsupported(script, "The requested script interpreter is not installed")
        }
        let token = BoundedProcessCancellation()
        cancellation.setHandler { token.cancel() }
        defer { cancellation.setHandler(nil) }
        try cancellation.check()
        let workingDirectory = directory ?? script.deletingLastPathComponent()
        // The wrapper source is constant. Every external value is an argv entry.
        let result = BoundedProcessRunner.run("/bin/sh", ["-c", "cd -- \"$1\" && shift && exec \"$@\" < /dev/null",
            "vorssaint-script", workingDirectory.path, executable.path, script.path] + selection.map(\.path),
            timeout: 60, maxOutputBytes: FinderToolsExecutor.maximumTextBytes, cancellation: token)
        try cancellation.check()
        let text = String(decoding: result.output, as: UTF8.self)
        guard !result.timedOut, result.status == 0 else {
            throw FinderFileActionError.operationFailed(operation: "run script", url: script,
                reason: result.timedOut ? "The script exceeded its 60-second limit." : "Exit status \(result.status).\n\(text)")
        }
        return text
    }
}
