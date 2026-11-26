// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Multi-provider local transcript summarizer. Uses the user's configured
/// local CLI subscription (Claude Code, Codex, Gemini CLI), local Ollama,
/// Apple's on-device FoundationModels (macOS 26+), and deterministic local
/// extractive fallback when no generative provider is available.
enum TranscriptSummarizer {
    struct SummaryResult: Equatable, Sendable {
        let text: String
        let usedOnDeviceLLM: Bool
        let providerDisplayName: String?
    }

    static func summarize(transcript: String,
                          prompt: String,
                          provider: SummaryInferenceProvider = .auto,
                          model: String? = nil) async throws -> SummaryResult {
        try Task.checkCancellation()
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return SummaryResult(text: "", usedOnDeviceLLM: false, providerDisplayName: nil)
        }
        let instructions = AudioTranscriptionSupport.resolvedSummaryPrompt(prompt)
        let selectedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch provider {
        case .auto:
            let probed = await SummaryProviderManager.probeAllProviders()
            let availableCLIs = Set(
                [SummaryInferenceProvider.claude, .codex, .gemini].filter { probed[$0]?.isReady == true }
            )
            let ollamaReady = probed[.ollama]?.isReady == true
            let order = SummaryProviderSupport.autoResolutionOrder(
                availableCLIProviders: availableCLIs,
                ollamaReady: ollamaReady
            )
            for candidate in order {
                try Task.checkCancellation()
                if let result = try await tryProvider(
                    candidate,
                    probed: probed[candidate],
                    model: nil,
                    transcript: cleaned,
                    instructions: instructions,
                    throwOnError: false
                ) {
                    return result
                }
            }
            return extractiveFallback(transcript: cleaned, instructions: instructions)

        case .claude, .codex, .gemini, .ollama:
            let state = await SummaryProviderManager.probeSingleProvider(provider)
            if let result = try await tryProvider(
                provider,
                probed: state,
                model: selectedModel,
                transcript: cleaned,
                instructions: instructions,
                throwOnError: true
            ) {
                return result
            }
            throw SummaryProviderManager.InvocationError.providerUnavailable(
                SummaryProviderSupport.descriptor(for: provider).displayName
            )

        case .appleIntelligence:
            if let llmText = try await summarizeWithAppleIntelligence(
                transcript: cleaned,
                instructions: instructions
            ) {
                return SummaryResult(
                    text: llmText,
                    usedOnDeviceLLM: true,
                    providerDisplayName: SummaryProviderSupport.descriptor(for: .appleIntelligence).displayName
                )
            }
            return extractiveFallback(transcript: cleaned, instructions: instructions)
        }
    }

    private static func tryProvider(_ provider: SummaryInferenceProvider,
                                    probed: SummaryProviderManager.ProviderState?,
                                    model: String?,
                                    transcript: String,
                                    instructions: String,
                                    throwOnError: Bool) async throws -> SummaryResult? {
        let displayName = SummaryProviderSupport.descriptor(for: provider).displayName
        switch provider {
        case .claude, .codex, .gemini:
            guard let path = probed?.executablePath else {
                if throwOnError {
                    throw SummaryProviderManager.InvocationError.providerUnavailable(displayName)
                }
                return nil
            }
            do {
                let text = try await SummaryProviderManager.summarizeWithCLI(
                    provider: provider,
                    executablePath: path,
                    model: model,
                    transcript: transcript,
                    instructions: instructions
                )
                return SummaryResult(text: text, usedOnDeviceLLM: true, providerDisplayName: displayName)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if throwOnError { throw error }
                return nil
            }

        case .ollama:
            let resolvedModel: String
            if let m = model, !m.isEmpty {
                resolvedModel = m
            } else if let first = probed?.models.first(where: { !$0.id.isEmpty })?.id {
                resolvedModel = first
            } else {
                if throwOnError {
                    throw SummaryProviderManager.InvocationError.providerUnavailable(displayName)
                }
                return nil
            }
            do {
                let text = try await SummaryProviderManager.summarizeWithOllama(
                    model: resolvedModel,
                    transcript: transcript,
                    instructions: instructions
                )
                return SummaryResult(text: text, usedOnDeviceLLM: true, providerDisplayName: "\(displayName) (\(resolvedModel))")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if throwOnError { throw error }
                return nil
            }

        case .appleIntelligence:
            if let llmText = try await summarizeWithAppleIntelligence(
                transcript: transcript,
                instructions: instructions
            ) {
                return SummaryResult(text: llmText, usedOnDeviceLLM: true, providerDisplayName: displayName)
            }
            return nil

        case .auto:
            return nil
        }
    }

    private static func extractiveFallback(transcript: String, instructions: String) -> SummaryResult {
        let fallback = AudioTranscriptionSupport.fallbackExtractiveSummary(
            transcript: transcript,
            prompt: instructions
        )
        return SummaryResult(text: fallback, usedOnDeviceLLM: false, providerDisplayName: nil)
    }

    private static func summarizeWithAppleIntelligence(transcript: String,
                                                       instructions: String) async throws -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await summarizeWithFoundationModels(
                transcript: transcript,
                instructions: instructions
            )
        }
        #endif
        return nil
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
