// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import Foundation

struct ConversionRequest {
    let source: URL
    let sourceFormat: FileFormat
    let target: FileFormat
    let destination: URL
    let progress: (Double) -> Void
    var options = ConvertOptions()
}

protocol ConversionEngine {
    func supports(from: FileFormat, to: FileFormat) -> Bool
    func convert(_ request: ConversionRequest) async throws
}

enum Engines {
    static let all: [ConversionEngine] = [
        ImageEngine(),
        OCREngine(),
        AudioEngine(),
        VideoEngine(),
        DocumentEngine(),
        SubtitleEngine(),
        ArchiveEngine(),
    ]

    static func engine(from: FileFormat, to: FileFormat) -> ConversionEngine? {
        all.first { $0.supports(from: from, to: to) }
    }

    static func convert(_ request: ConversionRequest) async throws {
        guard let engine = engine(from: request.sourceFormat, to: request.target) else {
            DiagnosticLog.log("no engine for \(request.sourceFormat.rawValue) -> \(request.target.rawValue)")
            throw OpenTangerineError.unsupportedConversion(request.sourceFormat, request.target)
        }
        DiagnosticLog.log("engine \(type(of: engine)) \(request.sourceFormat.rawValue) -> \(request.target.rawValue) src=\(request.source.path)")
        let temp = request.destination.deletingLastPathComponent()
            .appendingPathComponent(".opentangerine-\(UUID().uuidString).\(request.destination.pathExtension)")
        let staged = ConversionRequest(
            source: request.source,
            sourceFormat: request.sourceFormat,
            target: request.target,
            destination: temp,
            progress: request.progress,
            options: request.options
        )
        do {
            try await engine.convert(staged)
            try Task.checkCancellation()
            DiagnosticLog.log("engine finished, staged=\(temp.lastPathComponent)")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: temp.path, isDirectory: &isDirectory) {
                // moveItem refuses an existing destination; never delete another file.
                try FileManager.default.moveItem(at: temp, to: request.destination)
            } else {
                throw OpenTangerineError.encodeFailed(request.destination.lastPathComponent)
            }
        } catch {
            DiagnosticLog.log("engine threw: \(error)")
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }
}

