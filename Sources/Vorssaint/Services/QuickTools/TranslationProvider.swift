// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import Foundation

/// A backend that turns recognized lines into translated ones. Apple's
/// on-device framework and Google's Cloud Translation REST API are the two
/// implementations; the live loop in LiveTranslationService only ever talks
/// to this protocol.
protocol TranslationProvider {
    /// Translates plain text, one entry per input, in the same order and
    /// count returned. The caller (LiveTranslationService) owns pairing
    /// these back up with bounding boxes - a provider has no reason to know
    /// about geometry at all.
    func translate(texts: [String], source: AppLanguage?, target: AppLanguage) async throws -> [String]
}

enum TranslationProviderError: Error {
    /// Apple: the target language's on-device model isn't installed.
    case notInstalled
    /// Apple: TranslationSession can only be vended by a SwiftUI
    /// `.translationTask`, so it isn't ready yet the instant a session
    /// starts - the overlay's hidden session host attaches it a beat later.
    case sessionNotReady
    /// Google: no API key saved in the Keychain.
    case missingAPIKey
    /// Google: the key was rejected or its quota is exhausted (HTTP 400/403).
    case invalidAPIKeyOrQuota
    /// Google: any other non-2xx response.
    case serverError(Int)
    case network(Error)
}

/// Wraps Apple's Translation framework. TranslationSession has no
/// standalone initializer before macOS 26 - every OS version this feature
/// supports must obtain one through a SwiftUI `.translationTask`, which is
/// why this provider is a thin forwarder to a handler the overlay's hidden
/// session-host view installs once its session is live (see
/// LiveTranslationSessionHost in the UI layer). This keeps the Service layer
/// itself free of any SwiftUI import: the handler is just a closure value.
struct AppleTranslationProvider: TranslationProvider {
    let requestHandler: ([String], AppLanguage?, AppLanguage) async throws -> [String]

    func translate(texts: [String], source: AppLanguage?, target: AppLanguage) async throws -> [String] {
        try await requestHandler(texts, source, target)
    }
}

/// Calls Google Cloud Translation's Basic (v2) REST API directly - no SDK,
/// consistent with the project's zero-dependency rule. The user supplies
/// their own key (Services/QuickTools/LiveTranslationKeyStore.swift); this
/// type never persists anything itself.
struct GoogleTranslationProvider: TranslationProvider {
    private static let endpoint = URL(string: "https://translation.googleapis.com/language/translate/v2")!

    func translate(texts: [String], source: AppLanguage?, target: AppLanguage) async throws -> [String] {
        guard !texts.isEmpty else { return [] }
        guard let key = LiveTranslationKeyStore.read(), !key.isEmpty else {
            throw TranslationProviderError.missingAPIKey
        }

        var body: [String: Any] = [
            "q": texts,
            "target": LiveTranslationSupport.googleLanguageTag(target),
            "format": "text",
        ]
        if let source { body["source"] = LiveTranslationSupport.googleLanguageTag(source) }

        // The key travels as a header, not a `?key=` query parameter: a
        // failing request's URL can end up in logs or crash reports (see the
        // batchTranslate/translate diagnostic logging in
        // LiveTranslationService), and a header never gets echoed there the
        // way a URL does. Google's REST APIs accept this as an equivalent to
        // the query parameter for API-key auth.
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranslationProviderError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranslationProviderError.network(URLError(.badServerResponse))
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 400 || http.statusCode == 403 {
                throw TranslationProviderError.invalidAPIKeyOrQuota
            }
            throw TranslationProviderError.serverError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(Envelope.self, from: data)
        let translations = decoded.data.translations
        return texts.indices.map { index in
            index < translations.count ? translations[index].translatedText : ""
        }
    }

    private struct Envelope: Decodable {
        struct TranslationData: Decodable {
            struct Translation: Decodable { let translatedText: String }
            let translations: [Translation]
        }
        let data: TranslationData
    }
}
