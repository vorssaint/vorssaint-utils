// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import Foundation

/// Exports the audio tracks of a selected movie to a new AAC/M4A file.
enum FinderAudioTools {
    private final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private var error: Error?
        func set(_ error: Error) { lock.lock(); self.error = error; lock.unlock() }
        func check() throws { lock.lock(); let value = error; lock.unlock(); if let value { throw value } }
    }

    static func extract(from input: URL, to destination: URL,
                        cancellation: FinderToolsCancellation) throws -> URL {
        let asset = AVURLAsset(url: input)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw FinderFileActionError.unsupported(input, "This media cannot be exported as M4A")
        }
        let staged = try MediaSupport.temporaryOutputURL(for: destination)
        defer { MediaSupport.discardStagedOutput(staged) }
        let finished = DispatchSemaphore(value: 0)
        let outcome = Outcome()
        cancellation.setHandler { exporter.cancelExport() }
        defer { cancellation.setHandler(nil) }
        try cancellation.check()
        Task {
            defer { finished.signal() }
            do {
                guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
                    throw FinderFileActionError.unsupported(input, "The media contains no audio track")
                }
                try cancellation.check()
                if #available(macOS 15.0, *) {
                    try await exporter.export(to: staged, as: .m4a)
                } else {
                    try await exportLegacy(exporter, to: staged)
                }
                try cancellation.check()
            } catch { outcome.set(error) }
        }
        finished.wait()
        try outcome.check()
        try cancellation.check()
        try MediaSupport.installStagedOutput(staged, at: destination, replacingExisting: false)
        return destination
    }

    /// The legacy callback reads the session only after AVFoundation finishes;
    /// the only concurrent access is AVFoundation's supported cancelExport().
    private struct LegacySession: @unchecked Sendable { let exporter: AVAssetExportSession }

    @available(macOS, introduced: 14.0, obsoleted: 15.0)
    private static func exportLegacy(_ exporter: AVAssetExportSession, to destination: URL) async throws {
        exporter.outputURL = destination
        exporter.outputFileType = .m4a
        let session = LegacySession(exporter: exporter)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                if session.exporter.status == .completed { continuation.resume() }
                else { continuation.resume(throwing: session.exporter.error ?? CocoaError(.fileWriteUnknown)) }
            }
        }
    }
}
