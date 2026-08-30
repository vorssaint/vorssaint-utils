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
                    apiKey: String) async throws -> String {
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
                                                    fileName: "dictation.m4a",
                                                    mimeType: "audio/mp4",
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
            throw failure
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
            throw failure
        }
        guard data.count <= DictationResponseParser.maximumResponseBytes,
              (try? JSONSerialization.jsonObject(with: data)) != nil
        else { throw DictationFailure.invalidResponse }
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
