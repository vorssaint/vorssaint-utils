// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import Combine
import Foundation

/// Private text/audio lives in Application Support, outside preference backups.
/// Writes are serialized; a late Add cannot resurrect an entry after Clear.
final class DictationHistoryStore: ObservableObject {
    static let shared = DictationHistoryStore()
    @Published private(set) var entries: [DictationEntry] = []
    @Published private(set) var error: String?
    private let queue = DispatchQueue(label: "com.vorssaint.dictation.history", qos: .utility)
    private var player: AVAudioPlayer?
    private var loadFailed = false
    var directory: URL? { PrivateFileStore.containerURL?.appendingPathComponent("Dictation/History", isDirectory: true) }
    private var indexURL: URL? { directory?.appendingPathComponent("history.json") }

    private init() {
        if let indexURL, FileManager.default.fileExists(atPath: indexURL.path) {
            do { entries = try JSONDecoder().decode([DictationEntry].self, from: Data(contentsOf: indexURL)) }
            catch { loadFailed = true; self.error = "Speech history could not be read. The original file has been preserved." }
        }
    }

    func syncWithPreferences() {
        guard !loadFailed else { return }
        let previous = entries
        let defaults = UserDefaults.standard
        let kept = DictationSupport.retained(entries, limit: defaults.integer(forKey: DefaultsKey.dictationHistoryLimit))
        let keptIDs = Set(kept.map(\.id))
        deleteAudio(entries.filter { !keptIDs.contains($0.id) })
        let days = defaults.integer(forKey: DefaultsKey.dictationRetainAudio)
        entries = kept.map { entry in
            var copy = entry
            if copy.audioFilename != nil, DictationSupport.audioExpired(copy.createdAt, days: days) {
                deleteAudio([copy]); copy.audioFilename = nil
            }
            return copy
        }
        if entries != previous { save() }
    }

    func add(_ entry: DictationEntry, recording: URL?) {
        guard !loadFailed else { return }
        var entry = entry
        if let recording, UserDefaults.standard.integer(forKey: DefaultsKey.dictationRetainAudio) > 0,
           UserDefaults.standard.integer(forKey: DefaultsKey.dictationHistoryLimit) > 0,
           let directory, PrivateFileStore.createDirectory(at: directory) {
            let filename = entry.id.uuidString + ".caf"
            do {
                try FileManager.default.copyItem(at: recording, to: directory.appendingPathComponent(filename))
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: directory.appendingPathComponent(filename).path)
                entry.audioFilename = filename
            } catch { self.error = "The transcript was saved, but its recording could not be kept: \(error.localizedDescription)" }
        }
        entries.insert(entry, at: 0)
        syncWithPreferences()
        save()
    }

    func favorite(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isFavorite.toggle()
        syncWithPreferences()
        save()
    }

    func update(_ id: UUID, text: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].text = text
        save()
    }

    func remove(_ id: UUID) {
        deleteAudio(entries.filter { $0.id == id })
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        player?.stop(); player = nil
        deleteAudio(entries)
        entries.removeAll()
        error = nil
        loadFailed = false
        save()
    }

    func audioURL(_ entry: DictationEntry) -> URL? {
        guard let directory, let url = DictationSupport.safeAudioURL(filename: entry.audioFilename, directory: directory),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func play(_ entry: DictationEntry) {
        player?.stop()
        guard let url = audioURL(entry) else { return }
        do { player = try AVAudioPlayer(contentsOf: url); player?.play() }
        catch { self.error = error.localizedDescription }
    }

    private func deleteAudio(_ entries: [DictationEntry]) {
        guard let directory else { return }
        let urls = entries.compactMap { DictationSupport.safeAudioURL(filename: $0.audioFilename, directory: directory) }
        queue.async { for url in urls { try? FileManager.default.removeItem(at: url) } }
    }

    private func save() {
        guard !loadFailed, let directory, let indexURL,
              let data = try? JSONEncoder().encode(entries) else { return }
        queue.async {
            guard PrivateFileStore.createDirectory(at: directory), PrivateFileStore.write(data, to: indexURL) else {
                DispatchQueue.main.async { self.error = "Speech history could not be saved." }
                return
            }
        }
    }

    func flush() { queue.sync {} }
}
