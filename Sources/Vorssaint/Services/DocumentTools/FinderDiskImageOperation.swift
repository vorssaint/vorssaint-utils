// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Darwin

/// A password is supplied through stdin, never through argv, preferences or logs.
enum FinderDiskImageOperation {
    static func create(from folder: URL, to destination: URL, password: String?,
                       cancellation: FinderToolsCancellation) throws -> URL {
        guard try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
              NotchFileToolsSupport.destinationIsOutsideInputs(destination, inputs: [folder]) else {
            throw FinderFileActionError.invalidRequest("Choose a folder and a destination outside it.")
        }
        if let password {
            guard !password.isEmpty, password.utf8.count <= 1024, !password.contains("\n"), !password.contains("\0") else {
                throw FinderFileActionError.invalidRequest("Enter a password without line breaks, up to 1,024 bytes.")
            }
        }
        let staged = try MediaSupport.temporaryOutputURL(for: destination)
        defer { MediaSupport.discardStagedOutput(staged) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["create", "-srcfolder", folder.path, "-format", "UDZO", "-o", staged.path]
        if password != nil { process.arguments! += ["-encryption", "AES-256", "-stdinpass"] }
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try cancellation.check()
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                if finished.wait(timeout: .now() + 1) == .timedOut {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    finished.wait()
                }
            }
        }
        cancellation.setHandler {
            if process.isRunning { process.terminate() }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        defer { cancellation.setHandler(nil) }
        if let password { try input.fileHandleForWriting.write(contentsOf: Data((password + "\0").utf8)) }
        try input.fileHandleForWriting.close()
        if finished.wait(timeout: .now() + 1800) == .timedOut {
            if process.isRunning { process.terminate() }
            if finished.wait(timeout: .now() + 1) == .timedOut {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                finished.wait()
            }
            throw FinderFileActionError.operationFailed(operation: "create disk image", url: folder, reason: "The operation timed out.")
        }
        try cancellation.check()
        guard process.terminationStatus == 0 else {
            throw FinderFileActionError.operationFailed(operation: "create disk image", url: folder,
                reason: "hdiutil exited with status \(process.terminationStatus).")
        }
        try MediaSupport.installStagedOutput(staged, at: destination, replacingExisting: false)
        return destination
    }
}
