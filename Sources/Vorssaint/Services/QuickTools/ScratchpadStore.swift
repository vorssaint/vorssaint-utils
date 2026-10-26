// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A failed read must never authorize a later autosave or migration cleanup.
struct ScratchpadStore {
    let directoryURL: URL?
    let defaults: UserDefaults
    private(set) var lastSavedDocument: ScratchpadDocument?
    private var canSave = false

    init(directoryURL: URL?, defaults: UserDefaults) {
        self.directoryURL = directoryURL
        self.defaults = defaults
    }

    mutating func load(defaultName: String,
                       retention: ScratchpadRetention,
                       now: Date) throws -> ScratchpadDocument {
        canSave = false
        lastSavedDocument = nil
        guard let directoryURL else { throw CocoaError(.fileReadUnknown) }
        let url = directoryURL.appendingPathComponent("Scratchpad-v2.json")
        let legacyURL = directoryURL.appendingPathComponent("Scratchpad.txt")
        let currentData = try Self.readIfPresent(at: url)
        let storedData = try currentData ?? Self.readIfPresent(at: directoryURL.appendingPathComponent("Scratchpad.json"))
        let preference = defaults.object(forKey: DefaultsKey.scratchpadDocument)
        let decoded: ScratchpadDocument

        if let storedData {
            decoded = try JSONDecoder().decode(ScratchpadDocument.self, from: storedData)
            if currentData != nil { lastSavedDocument = decoded }
        } else if let preference {
            guard let data = preference as? Data else { throw CocoaError(.fileReadCorruptFile) }
            decoded = try JSONDecoder().decode(ScratchpadDocument.self, from: data)
        } else if let data = try Self.readIfPresent(at: legacyURL) {
            guard let text = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: legacyURL.path)
            decoded = .initial(defaultName: defaultName, text: text,
                               modifiedAt: attributes[.modificationDate] as? Date)
        } else {
            decoded = .initial(defaultName: defaultName)
        }

        var loaded = decoded.sanitized(defaultName: defaultName)
        loaded.applyRetention(retention, now: now)
        canSave = true
        // Migration sources are recovery copies, including legacy preferences.
        _ = save(loaded)
        return loaded
    }

    @discardableResult
    mutating func save(_ document: ScratchpadDocument) -> Bool {
        guard canSave else { return false }
        if document == lastSavedDocument { return true }
        guard let directoryURL, let data = document.encoded() else { return false }
        let url = directoryURL.appendingPathComponent("Scratchpad-v2.json")
        guard PrivateFileStore.createDirectory(at: directoryURL),
              PrivateFileStore.write(data, to: url),
              (try? Data(contentsOf: url)) == data else { return false }
        lastSavedDocument = document
        return true
    }

    private static func readIfPresent(at url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }
}
