// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The last files the converter wrote, newest first, kept so Settings can
/// show them and open them again. Paths only; nothing about the contents.
enum ConvertRecents {
    struct Entry: Codable, Identifiable, Equatable {
        let path: String
        let date: Date
        var id: String { path + String(date.timeIntervalSince1970) }
    }

    private static let limit = 30

    static func all() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.convertRecents),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }

    static func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let now = Date()
        var entries = urls.map { Entry(path: $0.path, date: now) } + all()
        entries = Array(entries.prefix(limit))
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: DefaultsKey.convertRecents) }
        NotificationCenter.default.post(name: .convertRecentsChanged, object: nil)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.convertRecents)
        NotificationCenter.default.post(name: .convertRecentsChanged, object: nil)
    }
}

extension Notification.Name {
    static let convertRecentsChanged = Notification.Name("convertRecentsChanged")
}
