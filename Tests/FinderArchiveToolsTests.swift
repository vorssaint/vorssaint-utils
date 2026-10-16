// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Darwin

enum FinderArchiveToolsTests {
    static func run(_ suite: TestSuite) {
        suite.run("Finder disk images") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: root) }
                let source = try FinderFileActions.createFolder(in: root, named: "Input")
                let original = try FinderFileActions.createFile(in: source, named: "document.txt", contents: Data("fixture".utf8))
                let password = "synthetic-test-passphrase"
                let destination = root.appendingPathComponent("encrypted.dmg")
                let output = try FinderDiskImageOperation.create(from: source, to: destination, password: password,
                                                                  cancellation: FinderToolsCancellation())
                suite.expect(output == destination && FileManager.default.fileExists(atPath: output.path),
                             "encrypted image is published at the requested destination")
                suite.expect(try verify(output, password: password), "hdiutil verifies the encrypted image with the original password")
                let bytes = try Data(contentsOf: original)
                suite.expect(bytes == Data("fixture".utf8), "disk image creation leaves the source unchanged")
                let existingBytes = try Data(contentsOf: destination)
                do {
                    _ = try FinderDiskImageOperation.create(from: source, to: destination, password: nil,
                                                            cancellation: FinderToolsCancellation())
                    suite.expect(false, "creating at an existing destination must fail")
                } catch {
                    let after = try Data(contentsOf: destination)
                    suite.expect(after == existingBytes, "an existing disk image is never replaced")
                }
            } catch { suite.expect(false, "disk image fixture failed: \(error)") }
        }
    }

    private static func verify(_ url: URL, password: String) throws -> Bool {
        let process = Process()
        let input = Pipe()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["verify", "-stdinpass", url.path]
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        // Preserve hdiutil diagnostics so a failed integration check can be
        // distinguished from a bad password, unavailable device or timeout.
        process.standardError = FileHandle.standardError
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL); finished.wait() }
        }
        try input.fileHandleForWriting.write(contentsOf: Data((password + "\0").utf8))
        try input.fileHandleForWriting.close()
        guard finished.wait(timeout: .now() + 30) == .success else { return false }
        return process.terminationStatus == 0
    }
}
