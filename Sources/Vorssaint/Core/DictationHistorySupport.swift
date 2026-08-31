// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DictationHistoryEntry: Codable, Equatable, Identifiable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let id: UUID
    let createdAt: Date
    let duration: TimeInterval
    let provider: DictationProvider
    let model: DictationModel
    let language: DictationLanguage
    let rawText: String
    let enhancedText: String?
    let outputMode: DictationOutputMode
    let sourceEntryID: UUID?
    let audioFileName: String?
    let processingDuration: TimeInterval?
    let failure: String?

    init(id: UUID = UUID(),
         createdAt: Date,
         duration: TimeInterval,
         provider: DictationProvider,
         model: DictationModel,
         language: DictationLanguage,
         rawText: String,
         enhancedText: String? = nil,
         outputMode: DictationOutputMode = .raw,
         sourceEntryID: UUID? = nil,
         audioFileName: String?,
         processingDuration: TimeInterval?,
         failure: String?) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.createdAt = createdAt
        self.duration = max(0, duration)
        self.provider = provider
        self.model = model
        self.language = language
        self.rawText = rawText
        self.enhancedText = enhancedText
        self.outputMode = outputMode
        self.sourceEntryID = sourceEntryID
        self.audioFileName = audioFileName
        self.processingDuration = processingDuration
        self.failure = failure
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, createdAt, duration, provider, model, language,
             rawText, enhancedText, outputMode, sourceEntryID, audioFileName,
             processingDuration, failure
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try values.decode(UUID.self, forKey: .id)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        duration = max(0, try values.decode(TimeInterval.self, forKey: .duration))
        provider = try values.decode(DictationProvider.self, forKey: .provider)
        model = try values.decode(DictationModel.self, forKey: .model)
        language = try values.decode(DictationLanguage.self, forKey: .language)
        rawText = try values.decode(String.self, forKey: .rawText)
        enhancedText = try values.decodeIfPresent(String.self, forKey: .enhancedText)
        outputMode = try values.decodeIfPresent(DictationOutputMode.self, forKey: .outputMode) ?? .raw
        sourceEntryID = try values.decodeIfPresent(UUID.self, forKey: .sourceEntryID)
        audioFileName = try values.decodeIfPresent(String.self, forKey: .audioFileName)
        processingDuration = try values.decodeIfPresent(TimeInterval.self, forKey: .processingDuration)
        failure = try values.decodeIfPresent(String.self, forKey: .failure)
    }
}

enum DictationHistoryRetention {
    static func sanitizedDays(_ value: Int) -> Int {
        min(365, max(0, value))
    }

    static func isExpired(createdAt: Date, now: Date, days: Int) -> Bool {
        now.timeIntervalSince(createdAt) >= TimeInterval(sanitizedDays(days)) * 86_400
    }
}
