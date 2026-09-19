// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import UniformTypeIdentifiers

enum NotchFileToolsSupport {
    static let dropSpacing: CGFloat = 12

    static func mediaDropArea(in geometry: NotchGeometry, size: CGSize) -> CGRect {
        let content = geometry.contentSize(for: size)
        return CGRect(x: size.width / 2 + dropSpacing / 2,
                      y: geometry.safeContentTop + NotchLayout.headerHeight + NotchLayout.spacing,
                      width: max(0, (content.width - dropSpacing) / 2), height: content.height)
    }

    static func optimizationTool(for urls: [URL]) -> MediaTool? {
        if accepts(urls, for: .imageCompressor) { return .imageCompressor }
        if accepts(urls, for: .videoCompressor) { return .videoCompressor }
        return nil
    }

    static func accepts(_ urls: [URL], for tool: MediaTool) -> Bool {
        guard !urls.isEmpty, urls.allSatisfy(\.isFileURL),
              tool == .imageCompressor || urls.count == 1 else { return false }
        let types: [UTType] = tool == .videoCompressor || tool == .gifMaker
            ? [.movie, .video] : [.image]
        return urls.allSatisfy { url in
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            return MediaSupport.inputMatchesTool(contentType: type, inputTypes: types)
        }
    }

    static func destinationIsOutsideInputs(_ destination: URL, inputs: [URL]) -> Bool {
        guard destination.isFileURL, !inputs.isEmpty, inputs.allSatisfy(\.isFileURL) else { return false }
        let destination = destination.resolvingSymlinksInPath().standardizedFileURL
        let manager = FileManager.default
        let existingDestination = (manager.fileExists(atPath: destination.path)
            ? destination : destination.deletingLastPathComponent()).resolvingSymlinksInPath()
        return inputs.allSatisfy { input in
            let source = input.resolvingSymlinksInPath().standardizedFileURL
            guard source.path != "/" else { return false }
            // Native file identity handles aliases and case-insensitive volumes;
            // comparing path spelling can put an archive inside its own input.
            var relationship = FileManager.URLRelationship.other
            do {
                try manager.getRelationship(&relationship, ofDirectoryAt: source, toItemAt: existingDestination)
                return relationship == .other
            } catch { return false }
        }
    }
}

/// Owns one requested archive operation; cancellation and installation share a lock
/// so a cancelled job cannot publish a partly written file over an existing item.
final class NotchArchiveOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?
    private let makeProcess: (URL, URL, Bool) -> Process

    init(makeProcess: ((URL, URL, Bool) -> Process)? = nil) {
        self.makeProcess = makeProcess ?? Self.archiver
    }

    func cancel(immediately: Bool = false) {
        lock.lock()
        cancelled = true
        let active = process
        if let active, active.isRunning {
            if immediately { kill(active.processIdentifier, SIGKILL) }
            else { active.terminate() }
        }
        lock.unlock()
        if let active, !immediately {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                if active.isRunning { kill(active.processIdentifier, SIGKILL) }
            }
        }
    }

    func archive(_ input: URL, to output: URL) throws {
        lock.lock()
        let mayStart = !cancelled
        lock.unlock()
        guard mayStart else { throw CancellationError() }
        guard input.isFileURL, output.isFileURL,
              NotchFileToolsSupport.destinationIsOutsideInputs(output, inputs: [input]) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true || values.isDirectory == true || values.isSymbolicLink == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let staged = try MediaSupport.temporaryOutputURL(for: output)
        defer { MediaSupport.discardStagedOutput(staged) }
        let child = makeProcess(input, staged, values.isDirectory == true)
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        child.terminationHandler = { _ in finished.signal() }
        lock.lock()
        guard !cancelled else { lock.unlock(); throw CancellationError() }
        do { try child.run(); process = child; lock.unlock() }
        catch { lock.unlock(); throw error }
        // At most one queued operation waits, off the UI thread. Cancellation
        // terminates (then kills) the owned child before the next job can start.
        finished.wait()
        lock.lock()
        defer { process = nil; lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        guard child.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        try MediaSupport.installStagedOutput(staged, at: output, replacingExisting: false)
    }

    private static func archiver(_ input: URL, _ output: URL, _ directory: Bool) -> Process {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        child.arguments = ["-c", "-k", "--sequesterRsrc"]
            + (directory ? ["--keepParent"] : [])
            + [input.path, output.path]
        return child
    }
}
