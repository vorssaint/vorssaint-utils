// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

final class DictationTranscriptionClient {
    private let redirectDelegate = HTTPSameHostRedirectDelegate()
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration,
                             delegate: redirectDelegate,
                             delegateQueue: nil)
    }

    func transcribe(file: URL,
                    provider: DictationProvider,
                    model: DictationModel,
                    apiKey: String,
                    language: DictationLanguage = .automatic,
                    fileName: String = "dictation.m4a",
                    mimeType: String = "audio/mp4") async throws -> String {
        guard model.provider == provider else { throw DictationFailure.invalidResponse }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DictationFailure.missingKey }
        guard let values = try? file.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size > 0,
              size <= DictationMultipartBody.maximumAudioBytes
        else {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            throw size > DictationMultipartBody.maximumAudioBytes
                ? DictationFailure.audioTooLarge : DictationFailure.noSpeech
        }

        let audio: Data
        do {
            audio = try Data(contentsOf: file, options: [.mappedIfSafe])
        } catch {
            throw DictationFailure.noSpeech
        }
        let multipart = try DictationMultipartBody(model: model.id,
                                                    language: language,
                                                    fileName: fileName,
                                                    mimeType: mimeType,
                                                    audio: audio)
        var request = URLRequest(url: provider.transcriptionURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(multipart.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(String(multipart.data.count), forHTTPHeaderField: "Content-Length")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, from: multipart.data)
        } catch is CancellationError {
            throw DictationFailure.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw DictationFailure.cancelled
        } catch {
            throw DictationFailure.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw DictationFailure.invalidResponse
        }
        if let failure = DictationHTTPErrorClassifier.failure(statusCode: http.statusCode) {
            throw DictationProviderError(failure: failure,
                                         statusCode: http.statusCode,
                                         detail: DictationProviderDiagnostic.message(from: data))
        }
        return try DictationResponseParser.transcript(from: data)
    }

    func testConfiguration(provider: DictationProvider,
                           apiKey: String) async throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DictationFailure.missingKey }
        var request = URLRequest(url: provider.modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw DictationFailure.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw DictationFailure.cancelled
        } catch {
            throw DictationFailure.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw DictationFailure.invalidResponse
        }
        if let failure = DictationHTTPErrorClassifier.failure(statusCode: http.statusCode) {
            throw DictationProviderError(failure: failure,
                                         statusCode: http.statusCode,
                                         detail: DictationProviderDiagnostic.message(from: data))
        }
        guard data.count <= DictationResponseParser.maximumResponseBytes,
              (try? JSONSerialization.jsonObject(with: data)) != nil
        else { throw DictationFailure.invalidResponse }
    }

    func enhance(text: String,
                 provider: DictationProvider,
                 apiKey: String,
                 language: DictationLanguage) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DictationFailure.missingKey }
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw DictationFailure.noSpeech }
        guard source.utf8.count <= DictationResponseParser.maximumTextBytes else {
            throw DictationFailure.invalidResponse
        }
        let languageInstruction = language == .automatic
            ? "preserve the language used in the input"
            : "write the result in \(language.displayName)"
        let body: [String: Any] = [
            "model": provider.enhancementModelID,
            "temperature": 0.1,
            "messages": [
                ["role": "system", "content": "You clean dictation text. \(languageInstruction). Correct only obvious transcription errors, add natural punctuation and paragraph breaks, and never invent, remove, or translate factual content. Return only the final text."],
                ["role": "user", "content": source],
            ],
        ]
        guard JSONSerialization.isValidJSONObject(body),
              let requestData = try? JSONSerialization.data(withJSONObject: body) else {
            throw DictationFailure.invalidResponse
        }
        var request = URLRequest(url: provider.enhancementURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = requestData
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw DictationFailure.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw DictationFailure.cancelled
        } catch {
            throw DictationFailure.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw DictationFailure.invalidResponse
        }
        if let failure = DictationHTTPErrorClassifier.failure(statusCode: http.statusCode) {
            throw DictationProviderError(failure: failure,
                                         statusCode: http.statusCode,
                                         detail: DictationProviderDiagnostic.message(from: data))
        }
        return try DictationResponseParser.enhancedText(from: data)
    }

    deinit {
        session.invalidateAndCancel()
    }
}

private final class HTTPSameHostRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme == "https",
              request.url?.host == task.originalRequest?.url?.host
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
