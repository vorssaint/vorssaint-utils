// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Security

/// The API key lives in the Keychain, never in preferences: preferences are
/// backed up and exported, a key must not travel with them.
enum AIBarKeychain {
    private static let service = "Vorssaint AIBar"
    private static let account = "api-key"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(base as CFDictionary)
        guard !trimmed.isEmpty else { return true }
        var item = base
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

/// A client for any `/chat/completions` endpoint that speaks the OpenAI
/// shape: Ollama, LM Studio, OpenAI, OpenRouter and the like. It sends the
/// prompt it is given and nothing else, holds no connection between requests
/// and keeps no history.
enum AIBarClient {
    enum Failure: Error, Equatable {
        case notConfigured
        case insecureEndpoint
        case network(String)
        case status(Int)
        case malformed
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    static func requestBody(model: String, system: String, user: String) -> Data? {
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "temperature": 0,
            "stream": false,
            "max_tokens": 600
        ]
        return try? JSONSerialization.data(withJSONObject: body)
    }

    static func reply(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        return content
    }

    static func modelNames(from data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["data"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["id"] as? String }.sorted()
    }

    private static func request(_ url: URL, method: String, body: Data?, key: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let key, !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                throw Failure.status(status)
            }
            return data
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.network((error as NSError).localizedDescription)
        }
    }

    static func complete(endpoint: String, model: String, key: String?, system: String, user: String) async throws -> String {
        guard !model.trimmingCharacters(in: .whitespaces).isEmpty else { throw Failure.notConfigured }
        guard AIBarEndpoint.isTransportAcceptable(endpoint),
              let url = AIBarEndpoint.chatCompletionsURL(endpoint) else { throw Failure.insecureEndpoint }
        guard let body = requestBody(model: model, system: system, user: user) else { throw Failure.malformed }
        let data = try await send(request(url, method: "POST", body: body, key: key))
        guard let text = reply(from: data) else { throw Failure.malformed }
        return text
    }

    static func listModels(endpoint: String, key: String?) async throws -> [String] {
        guard AIBarEndpoint.isTransportAcceptable(endpoint),
              let chat = AIBarEndpoint.chatCompletionsURL(endpoint),
              let url = URL(string: chat.absoluteString.replacingOccurrences(of: "/chat/completions", with: "/models"))
        else { throw Failure.insecureEndpoint }
        return modelNames(from: try await send(request(url, method: "GET", body: nil, key: key)))
    }
}
