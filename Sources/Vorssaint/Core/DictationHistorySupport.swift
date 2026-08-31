// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DictationHistoryEntry: Codable, Equatable, Identifiable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let createdAt: Date
    let duration: TimeInterval
    let provider: DictationProvider
    let model: DictationModel
    let language: DictationLanguage
    let rawText: String
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
        self.audioFileName = audioFileName
        self.processingDuration = processingDuration
        self.failure = failure
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
