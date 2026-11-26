// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device transcript summarizer. Uses Apple's on-device FoundationModels
/// framework when available on macOS 26+ to follow the user's custom summary
/// prompt, and falls back seamlessly to local deterministic extractive
/// summarization on earlier macOS versions or when Apple Intelligence is off.
enum TranscriptSummarizer {
    struct SummaryResult: Equatable, Sendable {
        let text: String
        let usedOnDeviceLLM: Bool
    }

    static func summarize(transcript: String, prompt: String) async throws -> SummaryResult {
        try Task.checkCancellation()
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return SummaryResult(text: "", usedOnDeviceLLM: false)
        }
        let instructions = AudioTranscriptionSupport.resolvedSummaryPrompt(prompt)

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if let llmText = try await summarizeWithFoundationModels(
                transcript: cleaned,
                instructions: instructions
            ) {
                return SummaryResult(text: llmText, usedOnDeviceLLM: true)
            }
        }
        #endif

        let fallback = AudioTranscriptionSupport.fallbackExtractiveSummary(
            transcript: cleaned,
            prompt: instructions
        )
        return SummaryResult(text: fallback, usedOnDeviceLLM: false)
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func summarizeWithFoundationModels(transcript: String,
                                                      instructions: String) async throws -> String? {
        guard case .available = SystemLanguageModel.default.availability else {
            return nil
        }

        let chunks = AudioTranscriptionSupport.summaryChunks(for: transcript, maxCharacters: 8_000)
        guard !chunks.isEmpty else { return nil }

        do {
            if chunks.count == 1 {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: "Transcript:\n\n\(chunks[0])")
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }

            // Multi-chunk map-reduce for long meetings so context limits are never hit.
            var partials: [String] = []
            for (index, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                let mapSession = LanguageModelSession(
                    instructions: "Extract the key points, decisions, and action items from this transcript excerpt concisely."
                )
                let response = try await mapSession.respond(
                    to: "Transcript part \(index + 1) of \(chunks.count):\n\n\(chunk)"
                )
                let part = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !part.isEmpty { partials.append(part) }
            }
            guard !partials.isEmpty else { return nil }
            try Task.checkCancellation()

            let reduceSession = LanguageModelSession(instructions: instructions)
            let combined = partials.enumerated().map { "Part \($0.offset + 1):\n\($0.element)" }.joined(separator: "\n\n")
            let finalResponse = try await reduceSession.respond(to: "Transcript notes:\n\n\(combined)")
            let finalText = finalResponse.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return finalText.isEmpty ? nil : finalText
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Fall back cleanly if the on-device model hits a guardrail, context
            // limit, or transient unavailability.
            return nil
        }
    }
    #endif
}
