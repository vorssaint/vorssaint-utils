// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum DictationProvider: String, CaseIterable, Identifiable {
    case openAI
    case groq

    var id: String { rawValue }

    var transcriptionURL: URL {
        switch self {
        case .openAI: return URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        case .groq: return URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
        }
    }

    var modelsURL: URL {
        switch self {
        case .openAI: return URL(string: "https://api.openai.com/v1/models")!
        case .groq: return URL(string: "https://api.groq.com/openai/v1/models")!
        }
    }

    var models: [DictationModel] {
        switch self {
        case .openAI:
            return [
                DictationModel(id: "gpt-4o-mini-transcribe", provider: self),
                DictationModel(id: "gpt-4o-transcribe", provider: self),
                DictationModel(id: "whisper-1", provider: self),
            ]
        case .groq:
            return [
                DictationModel(id: "whisper-large-v3-turbo", provider: self),
                DictationModel(id: "whisper-large-v3", provider: self),
            ]
        }
    }

    var defaultModel: DictationModel { models[0] }

    func sanitizedModel(_ raw: String?) -> DictationModel {
        models.first { $0.id == raw } ?? defaultModel
    }
}

struct DictationModel: Equatable, Hashable, Identifiable {
    let id: String
    let provider: DictationProvider
}

enum DictationState: Equatable {
    case idle
    case listening
    case processing
    case failure(DictationFailure)
}

enum DictationFailure: Error, Equatable {
    case missingKey
    case keychain
    case microphoneDenied
    case microphoneUnavailable
    case audioTooLarge
    case noSpeech
    case invalidKey
    case rateLimited
    case network
    case server
    case requestRejected
    case invalidResponse
    case accessibilityRequiredCopied
    case focusChangedCopied
    case pasteFailedCopied
    case cancelled
}

enum DictationLifecycleEvent: Equatable {
    case begin
    case stop
    case cancel
    case disable
    case transcriptionCompleted(hasText: Bool)
    case failed(DictationFailure)
    case reset
}

enum DictationLifecycleEffect: Equatable {
    case startCapture
    case stopCapture
    case upload
    case insert
    case cancelAll
    case discardAudio
    case showHUD
    case hideHUD
    case showFailure(DictationFailure)
}

struct DictationLifecycleTransition: Equatable {
    let state: DictationState
    let effects: [DictationLifecycleEffect]
}

enum DictationLifecycle {
    static func transition(from state: DictationState,
                           event: DictationLifecycleEvent) -> DictationLifecycleTransition {
        switch (state, event) {
        case (.idle, .begin), (.failure, .begin):
            return DictationLifecycleTransition(state: .listening,
                                                effects: [.startCapture, .showHUD])
        case (.listening, .stop):
            return DictationLifecycleTransition(state: .processing,
                                                effects: [.stopCapture, .upload, .showHUD])
        case (.processing, .transcriptionCompleted(hasText: true)):
            return DictationLifecycleTransition(state: .processing, effects: [.insert])
        case (.processing, .transcriptionCompleted(hasText: false)):
            return DictationLifecycleTransition(state: .failure(.noSpeech),
                                                effects: [.discardAudio, .showFailure(.noSpeech)])
        case (_, .cancel), (_, .disable):
            return DictationLifecycleTransition(state: .idle,
                                                effects: [.cancelAll, .discardAudio, .hideHUD])
        case (_, .failed(let failure)):
            return DictationLifecycleTransition(state: .failure(failure),
                                                effects: [.discardAudio, .showFailure(failure)])
        case (_, .reset):
            return DictationLifecycleTransition(state: .idle, effects: [.hideHUD])
        default:
            return DictationLifecycleTransition(state: state, effects: [])
        }
    }
}

enum DictationInsertionDecision: Equatable {
    case paste
    case copy(DictationFailure)

    static func decide(accessibilityGranted: Bool,
                       originalTargetIsFocused: Bool) -> DictationInsertionDecision {
        guard accessibilityGranted else { return .copy(.accessibilityRequiredCopied) }
        guard originalTargetIsFocused else { return .copy(.focusChangedCopied) }
        return .paste
    }
}

enum DictationHTTPErrorClassifier {
    static func failure(statusCode: Int) -> DictationFailure? {
        switch statusCode {
        case 200...299: return nil
        case 401: return .invalidKey
        case 403: return .requestRejected
        case 429: return .rateLimited
        case 500...599: return .server
        default: return .requestRejected
        }
    }
}

enum DictationResponseParser {
    static let maximumResponseBytes = 256 * 1_024

    static func transcript(from data: Data) throws -> String {
        guard data.count <= maximumResponseBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String
        else { throw DictationFailure.invalidResponse }
        return text
    }
}

struct DictationMultipartBody {
    static let maximumAudioBytes = 25 * 1_024 * 1_024

    let boundary: String
    let data: Data

    init(model: String,
         fileName: String,
         mimeType: String,
         audio: Data,
         boundary: String = "Vorssaint-\(UUID().uuidString)") throws {
        guard !audio.isEmpty, audio.count <= Self.maximumAudioBytes else {
            throw audio.isEmpty ? DictationFailure.noSpeech : DictationFailure.audioTooLarge
        }
        self.boundary = boundary
        var body = Data()
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.appendUTF8(model)
        body.appendUTF8("\r\n--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        body.appendUTF8("json")
        body.appendUTF8("\r\n--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        body.appendUTF8("Content-Type: \(mimeType)\r\n\r\n")
        body.append(audio)
        body.appendUTF8("\r\n--\(boundary)--\r\n")
        data = body
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
