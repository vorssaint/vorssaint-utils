// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Immutable context from the queue row the user actually chose. Native caches
/// may change before a queued command runs; they cannot replace this context.
struct NotchQueueSelection: Equatable {
    static let maximumItems = 20
    let requestID: UUID
    let pid: Int32
    let currentIdentifier: String
    let itemIdentifier: String
    let offset: Int

    var isValid: Bool {
        pid > 0 && (1...Self.maximumItems).contains(offset)
            && NotchPlaybackCommand.validIdentifier(currentIdentifier)
            && NotchPlaybackCommand.validIdentifier(itemIdentifier)
            && currentIdentifier != itemIdentifier
    }

    func matches(pid: Int32, currentIdentifier: String, itemIdentifier: String, offset: Int) -> Bool {
        isValid && self.pid == pid && self.currentIdentifier == currentIdentifier
            && self.itemIdentifier == itemIdentifier && self.offset == offset
    }
}

/// A bounded command shared by the UI process and its playback adapter.
enum NotchPlaybackCommand: Equatable {
    case toggle, next, previous
    case seek(Double)
    case queue(UUID), queueStop, queuePlay(NotchQueueSelection)
    static let maximumMessageBytes = 2048

    init?(message: String) {
        guard message.utf8.count <= Self.maximumMessageBytes else { return nil }
        switch message {
        case "toggle": self = .toggle
        case "next": self = .next
        case "previous": self = .previous
        case "queue-stop": self = .queueStop
        default:
            let parts = message.split(separator: " ", omittingEmptySubsequences: false)
            if parts.count == 2, parts[0] == "queue", let id = UUID(uuidString: String(parts[1])) {
                self = .queue(id); return
            }
            if parts.count == 6, parts[0] == "queue-play", let id = UUID(uuidString: String(parts[1])),
               let pid = Int32(parts[2]), let offset = Int(parts[3]),
               let currentData = Data(base64Encoded: String(parts[4])),
               let current = String(data: currentData, encoding: .utf8),
               let itemData = Data(base64Encoded: String(parts[5])), let item = String(data: itemData, encoding: .utf8) {
                let selected = NotchQueueSelection(requestID: id, pid: pid, currentIdentifier: current, itemIdentifier: item, offset: offset)
                guard selected.isValid else { return nil }
                self = .queuePlay(selected); return
            }
            guard message.hasPrefix("seek "),
                  let position = Double(message.dropFirst(5)), Self.validPosition(position) else { return nil }
            self = .seek(position)
        }
    }

    var queueRequest: UUID? {
        switch self {
        case .queue(let id): return id
        case .queuePlay(let selected): return selected.requestID
        default: return nil
        }
    }

    var message: String? {
        switch self {
        case .toggle: return "toggle"
        case .next: return "next"
        case .previous: return "previous"
        case .queue(let id): return "queue \(id.uuidString)"
        case .queueStop: return "queue-stop"
        case .queuePlay(let selected):
            guard selected.isValid else { return nil }
            return "queue-play \(selected.requestID.uuidString) \(selected.pid) \(selected.offset) \(Data(selected.currentIdentifier.utf8).base64EncodedString()) \(Data(selected.itemIdentifier.utf8).base64EncodedString())"
        case .seek(let position): return Self.validPosition(position) ? "seek \(position)" : nil
        }
    }

    static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512 && !value.contains("\0")
    }

    private static func validPosition(_ value: Double) -> Bool {
        value.isFinite && (0...604_800).contains(value)
    }
}

/// Pipe delivery can split one line or batch many. An oversized line is discarded
/// through its newline only; subsequent queue-stop and valid commands still run.
struct NotchPlaybackCommandFramer {
    private var line = Data()
    private var discarding = false

    mutating func append(_ data: Data) -> [NotchPlaybackCommand?] {
        var result: [NotchPlaybackCommand?] = []
        for byte in data {
            if byte == 0x0A {
                let command = discarding ? nil : String(data: line, encoding: .utf8).flatMap(NotchPlaybackCommand.init(message:))
                result.append(command)
                line.removeAll(keepingCapacity: true)
                discarding = false
            } else if !discarding {
                if line.count >= NotchPlaybackCommand.maximumMessageBytes {
                    line.removeAll(keepingCapacity: true)
                    discarding = true
                } else { line.append(byte) }
            }
        }
        return result
    }
}
