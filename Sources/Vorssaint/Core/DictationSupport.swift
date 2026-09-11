// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum DictationProvider: String, CaseIterable, Identifiable, Codable {
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

    var enhancementURL: URL {
        switch self {
        case .openAI: return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .groq: return URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        }
    }

    /// Chat-capable model used only for optional text cleanup. Transcription
    /// models are deliberately not reused because providers expose different
    /// model families for audio and text requests.
    var enhancementModelID: String {
        switch self {
        case .openAI: return "gpt-4o-mini"
        case .groq: return "llama-3.3-70b-versatile"
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

enum DictationOutputMode: String, CaseIterable, Identifiable, Codable {
    case raw
    case enhanced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .raw: return "Transcrição crua"
        case .enhanced: return "Aprimorada"
        }
    }
}

enum DictationMediaPlayback: Equatable {
    case playing
    case paused
    case stopped
    case unknown
}

enum DictationMediaAction: Equatable {
    case none
    case pause
    case resume
}

struct DictationMediaDecision: Equatable {
    let action: DictationMediaAction
    let shouldResume: Bool
}

enum DictationMediaPolicy {
    static func begin(enabled: Bool,
                      playback: DictationMediaPlayback) -> DictationMediaDecision {
        guard enabled, playback == .playing else {
            return DictationMediaDecision(action: .none, shouldResume: false)
        }
        return DictationMediaDecision(action: .pause, shouldResume: true)
    }

    static func end(enabled: Bool,
                    shouldResume: Bool,
                    playback: DictationMediaPlayback) -> DictationMediaAction {
        guard enabled, shouldResume, playback == .paused else { return .none }
        return .resume
    }

    static func sanitizedDelay(_ value: Int) -> Int {
        min(5, max(0, value))
    }
}

/// Language hint sent to the provider. Automatic detection remains available,
/// while an explicit ISO-639-1 hint improves recognition for multilingual users.
enum DictationLanguage: String, CaseIterable, Identifiable, Codable {
    case automatic
    case portugueseBrazil = "pt"
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case japanese = "ja"
    case korean = "ko"
    case chinese = "zh"

    var id: String { rawValue }

    var apiCode: String? {
        self == .automatic ? nil : rawValue
    }

    var displayName: String {
        switch self {
        case .automatic: return "Automático"
        case .portugueseBrazil: return "Português (Brasil)"
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .chinese: return "中文"
        }
    }
}

struct DictationModel: Equatable, Hashable, Identifiable, Codable {
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

/// HTTP context kept separate from the user-facing failure taxonomy. The
/// status is safe to show (it never contains an API key or response body) and
/// makes provider configuration/quota errors diagnosable without logging data.
struct DictationProviderError: Error {
    let failure: DictationFailure
    let statusCode: Int
    /// Short diagnostic returned by the provider. It is parsed defensively and
    /// bounded before reaching UI; neither the request nor audio is retained.
    let detail: String?
}

/// A recording must contain both media bytes and a measurable duration before
/// it can be sent to a remote transcription provider.
enum DictationRecordedAudio {
    static let minimumDuration: TimeInterval = 0.05

    static func isUsable(fileSize: Int?, duration: TimeInterval) -> Bool {
        guard let fileSize, fileSize > 0 else { return false }
        return duration >= minimumDuration
    }
}

enum DictationProviderDiagnostic {
    static let maximumLength = 180

    static func message(from data: Data) -> String? {
        guard data.count <= DictationResponseParser.maximumResponseBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let value = (object["error"] as? [String: Any])?["message"] as? String
            ?? object["message"] as? String
        guard let value else { return nil }
        let compact = value
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return nil }
        return String(compact.prefix(maximumLength))
    }
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

    static func decide(accessibilityGranted: Bool) -> DictationInsertionDecision {
        guard accessibilityGranted else { return .copy(.accessibilityRequiredCopied) }
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
    static let maximumTextBytes = 128 * 1_024

    static func transcript(from data: Data) throws -> String {
        guard data.count <= maximumResponseBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String
        else { throw DictationFailure.invalidResponse }
        return text
    }

    static func enhancedText(from data: Data) throws -> String {
        guard data.count <= maximumResponseBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= maximumTextBytes else {
            throw DictationFailure.invalidResponse
        }
        return text
    }
}

struct DictationMultipartBody {
    static let maximumAudioBytes = 25 * 1_024 * 1_024

    let boundary: String
    let data: Data

    init(model: String,
         language: DictationLanguage = .automatic,
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
        if let languageCode = language.apiCode {
            body.appendUTF8("\r\n--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            body.appendUTF8(languageCode)
        }
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
