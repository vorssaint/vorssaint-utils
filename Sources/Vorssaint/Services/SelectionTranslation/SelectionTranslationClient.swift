// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct SelectionTranslationRequest: Sendable {
    let source: String
    let languages: SelectionTranslationLanguageSelection
    let prompts: SelectionTranslationPromptTemplates
    let provider: SelectionTranslationProviderConfiguration
}

enum SelectionTranslationClientError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int, String)
    case emptyTranslation
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The translation service returned an invalid response."
        case let .httpStatus(code, message): return "Translation service returned HTTP \(code): \(message)"
        case .emptyTranslation: return "The translation service returned no text."
        case .cancelled: return "Translation cancelled."
        }
    }
}

struct SelectionTranslationResult: Sendable {
    let text: String
    let usage: SelectionTranslationTokenUsage
}

final class SelectionTranslationClient {
    static let shared = SelectionTranslationClient()

    private init() {}

    func translate(_ request: SelectionTranslationRequest,
                   onText: @escaping @Sendable (String) -> Void) async throws -> SelectionTranslationResult {
        let urlRequest = try makeRequest(request, stream: true)
        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw SelectionTranslationClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = "Request failed"
            throw SelectionTranslationClientError.httpStatus(http.statusCode, message)
        }

        var aggregate = ""
        var usage = SelectionTranslationTokenUsage.zero
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let choices = object["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let piece = delta["content"] as? String, !piece.isEmpty {
                aggregate += piece
                onText(piece)
            }
            if let rawUsage = object["usage"] as? [String: Any] {
                usage = Self.usage(from: rawUsage)
            }
        }
        guard !aggregate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SelectionTranslationClientError.emptyTranslation
        }
        if usage.totalTokens == 0 { usage = SelectionTranslationTokenEstimator.estimate(inputText: request.source, outputText: aggregate) }
        return SelectionTranslationResult(text: aggregate, usage: usage)
    }

    func testConnection(_ request: SelectionTranslationRequest) async throws {
        var probe = request
        probe = SelectionTranslationRequest(source: "Hello", languages: request.languages,
                                            prompts: request.prompts, provider: request.provider)
        _ = try await translate(probe, onText: { _ in })
    }

    private func makeRequest(_ request: SelectionTranslationRequest, stream: Bool) throws -> URLRequest {
        var result = URLRequest(url: request.provider.chatCompletionsURL)
        result.httpMethod = "POST"
        result.setValue("Bearer \(request.provider.apiKey)", forHTTPHeaderField: "Authorization")
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let from = request.languages.source.displayName
        let to = request.languages.target.displayName
        let messages: [[String: String]] = [
            ["role": "system", "content": request.prompts.renderSystemPrompt(sourceLanguage: from, targetLanguage: to)],
            ["role": "user", "content": request.prompts.renderUserPrompt(source: request.source, sourceLanguage: from, targetLanguage: to)]
        ]
        result.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": request.provider.model, "messages": messages, "stream": stream
        ])
        return result
    }

    private static func usage(from object: [String: Any]) -> SelectionTranslationTokenUsage {
        func int(_ key: String) -> Int { (object[key] as? NSNumber)?.intValue ?? (object[key] as? Int ?? 0) }
        let input = int("prompt_tokens")
        let output = int("completion_tokens")
        let total = int("total_tokens")
        return SelectionTranslationTokenUsage(inputTokens: input, outputTokens: output,
                                              totalTokens: total == 0 ? input + output : total,
                                              isEstimated: false)
    }
}
