// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchQueueItem: Equatable, Identifiable {
    let id: String
    let offset: Int
    let title: String
    let artist: String
    let duration: Double
}

struct NotchQueueSnapshot: Equatable {
    let requestID: UUID
    let currentIdentifier: String
    let pid: Int32
    let items: [NotchQueueItem]
    let canPlay: Bool
}

enum NotchQueueSupport {
    static let maximumItems = NotchQueueSelection.maximumItems

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchQueue.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchQueueEnabled)
            && NotchSupport.modules(in: defaults).contains(.music)
    }

    static func decode(_ object: [String: Any], requestID: UUID, playback: NotchPlayback) -> NotchQueueSnapshot? {
        guard object["queueRequest"] as? String == requestID.uuidString,
              let current = object["currentIdentifier"] as? String, NotchPlaybackCommand.validIdentifier(current),
              current == playback.itemIdentifier,
              let rawPID = object["pid"] as? NSNumber, CFGetTypeID(rawPID) != CFBooleanGetTypeID(),
              let pid = Int32(exactly: rawPID.doubleValue), pid > 0, pid == playback.track.appPID,
              object["queueAvailable"] as? Bool == true,
              let rows = object["queueItems"] as? [[String: Any]], rows.count <= maximumItems else { return nil }
        var ids = Set<String>()
        var offsets = Set<Int>()
        var items: [NotchQueueItem] = []
        for row in rows {
            guard let id = row["id"] as? String, NotchPlaybackCommand.validIdentifier(id),
                  id != current, ids.insert(id).inserted,
                  let offset = row["offset"] as? Int, (1...maximumItems).contains(offset), offsets.insert(offset).inserted,
                  let title = row["title"] as? String, !title.isEmpty, title.utf8.count <= 4096 else { return nil }
            let artist = String((row["artist"] as? String ?? "").prefix(1024))
            let duration = row["duration"] as? Double ?? 0
            guard duration.isFinite, (0...604_800).contains(duration) else { return nil }
            items.append(NotchQueueItem(id: id, offset: offset, title: title, artist: artist, duration: duration))
        }
        return NotchQueueSnapshot(requestID: requestID, currentIdentifier: current, pid: pid,
                                  items: items.sorted { $0.offset < $1.offset },
                                  canPlay: playback.canSendCommandsDirectly && object["queueCanPlay"] as? Bool == true)
    }
}
