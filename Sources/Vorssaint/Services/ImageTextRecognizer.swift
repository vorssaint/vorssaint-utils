// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Vision

/// Offline text recognition on an image that is already in hand, for the
/// clipboard history's "Copy text" and for Watch in the island.
enum ImageTextRecognizer {
    /// What an image turned out to hold.
    enum Outcome: Equatable {
        case text(String)
        case empty
    }

    static func outcome(for image: CGImage,
                        removeLineBreaks: Bool,
                        fallbackLanguages: [String] = ["en-US"]) -> Outcome {
        var lines = recognizedLines(in: image,
                                    level: .accurate,
                                    automaticallyDetectLanguage: true,
                                    preferredLanguages: fallbackLanguages)
        if lines.isEmpty {
            // The fast path uses a different recognition model. It is a
            // separate second chance when the accurate model returns no text.
            lines = recognizedLines(in: image,
                                    level: .fast,
                                    automaticallyDetectLanguage: false,
                                    preferredLanguages: fallbackLanguages)
        }
        let text = QuickToolsSupport.joinedRecognizedText(lines,
                                                         removingLineBreaks: removeLineBreaks)
        return text.isEmpty ? .empty : .text(text)
    }

    private static func recognizedLines(
        in image: CGImage,
        level: VNRequestTextRecognitionLevel,
        automaticallyDetectLanguage: Bool,
        preferredLanguages: [String] = []
    ) -> [QuickToolsSupport.RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = automaticallyDetectLanguage
        if !preferredLanguages.isEmpty,
           let supported = try? request.supportedRecognitionLanguages() {
            let available = preferredLanguages.filter { supported.contains($0) }
            if !available.isEmpty { request.recognitionLanguages = available }
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }

        return (request.results ?? []).compactMap { observation -> QuickToolsSupport.RecognizedLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return QuickToolsSupport.RecognizedLine(text: candidate.string,
                                                    x: observation.boundingBox.minX,
                                                    y: observation.boundingBox.midY)
        }
    }

    static func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareVorssaintSource()
        pasteboard.setString(value, forType: .string)
    }
}
