// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import Vision

/// Reads text out of pictures with macOS's own recognizer, on this Mac, with
/// the language found automatically. Used for picture to TXT, for scanned PDFs
/// and for the redact tool's text finding.
enum OCR {
    static func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }

    /// Normalised boxes (origin bottom left) of text, or of faces.
    static func regions(in image: CGImage, faces: Bool, text: Bool) async throws -> [CGRect] {
        try await Task.detached(priority: .userInitiated) {
            var boxes: [CGRect] = []
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            if faces {
                let request = VNDetectFaceRectanglesRequest()
                try handler.perform([request])
                boxes += (request.results ?? []).map(\.boundingBox)
            }
            if text {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .fast
                try handler.perform([request])
                boxes += (request.results ?? []).map(\.boundingBox)
            }
            return boxes
        }.value
    }
}

struct OCREngine: ConversionEngine {
    func supports(from: FileFormat, to: FileFormat) -> Bool {
        from.category == .image && from != .svg && to == .txt
    }

    func convert(_ request: ConversionRequest) async throws {
        let image = try ImageIOBridge.load(request.source)
        request.progress(0.2)
        let text = try await OCR.recognize(image)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenTangerineError.invalidInput("No text was found in this picture.")
        }
        try text.write(to: request.destination, atomically: true, encoding: .utf8)
        request.progress(1)
    }
}
