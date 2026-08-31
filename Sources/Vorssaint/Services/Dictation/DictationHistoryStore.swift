// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum DictationHistoryStoreError: Error {
    case unavailable
    case invalidAudio
    case manifestWriteFailed
}

/// Owns the dictation manifest and its private audio files. Callers never
/// construct paths from user input; audio names are generated here and all
/// deletions are bounded to the history directory.
final class DictationHistoryStore {
    static let shared = DictationHistoryStore()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func entries() -> [DictationHistoryEntry] {
        guard let manifestURL, let data = try? Data(contentsOf: manifestURL),
              let entries = try? decoder.decode([DictationHistoryEntry].self, from: data) else {
            return []
        }
        return entries.sorted { $0.createdAt > $1.createdAt }
    }

    func audioURL(for fileName: String) -> URL? {
        guard let directory = historyDirectory else { return nil }
        let url = directory.appendingPathComponent(fileName)
        guard isBoundedPath(url, within: directory), isSafeAudioFile(url) else { return nil }
        return url
    }

    @discardableResult
    func save(_ entry: DictationHistoryEntry, audioURL: URL?) throws -> DictationHistoryEntry {
        guard let directory = historyDirectory, let manifestURL else {
            throw DictationHistoryStoreError.unavailable
        }
        guard PrivateFileStore.createDirectory(at: directory) else {
            throw DictationHistoryStoreError.unavailable
        }
        let storedAudioName: String?
        if let audioURL {
            guard isSafeAudioFile(audioURL) else { throw DictationHistoryStoreError.invalidAudio }
            let name = "\(entry.id.uuidString).m4a"
            let destination = directory.appendingPathComponent(name)
            try? fileManager.removeItem(at: destination)
            try fileManager.copyItem(at: audioURL, to: destination)
            try? fileManager.setAttributes([.posixPermissions: 0o600],
                                           ofItemAtPath: destination.path)
            storedAudioName = name
        } else {
            storedAudioName = nil
        }
        let persisted = DictationHistoryEntry(
            id: entry.id,
            createdAt: entry.createdAt,
            duration: entry.duration,
            provider: entry.provider,
            model: entry.model,
            language: entry.language,
            rawText: entry.rawText,
            audioFileName: storedAudioName,
            processingDuration: entry.processingDuration,
            failure: entry.failure)
        var all = entries().filter { $0.id != persisted.id }
        all.append(persisted)
        guard let data = try? encoder.encode(all),
              PrivateFileStore.write(data, to: manifestURL) else {
            if let storedAudioName {
                try? fileManager.removeItem(at: directory.appendingPathComponent(storedAudioName))
            }
            throw DictationHistoryStoreError.manifestWriteFailed
        }
        return persisted
    }

    func remove(_ entry: DictationHistoryEntry) {
        guard let directory = historyDirectory else { return }
        if let audioFileName = entry.audioFileName {
            let audioURL = directory.appendingPathComponent(audioFileName)
            guard isBoundedPath(audioURL, within: directory) else { return }
            try? fileManager.removeItem(at: audioURL)
        }
        let remaining = entries().filter { $0.id != entry.id }
        write(remaining)
    }

    @discardableResult
    func removeExpired(now: Date = Date(), days: Int) -> Int {
        let all = entries()
        let expired = all.filter {
            DictationHistoryRetention.isExpired(createdAt: $0.createdAt,
                                                now: now,
                                                days: days)
        }
        expired.forEach(remove)
        return expired.count
    }

    private var historyDirectory: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("Dictation/History", isDirectory: true)
    }

    private var manifestURL: URL? {
        historyDirectory?.appendingPathComponent("manifest.json")
    }

    private func write(_ entries: [DictationHistoryEntry]) {
        guard let manifestURL, let data = try? encoder.encode(entries) else { return }
        _ = PrivateFileStore.write(data, to: manifestURL)
    }

    private func isSafeAudioFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              (values.fileSize ?? 0) > 0,
              (values.fileSize ?? 0) <= DictationMultipartBody.maximumAudioBytes else { return false }
        return true
    }

    private func isBoundedPath(_ url: URL, within directory: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.hasPrefix(directory.standardizedFileURL.path + "/")
    }
}
