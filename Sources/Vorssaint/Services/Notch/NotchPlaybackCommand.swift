// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The adapter's recording revision travels with the user's action. A process
/// alone is not enough: it may start another recording before the pipe is read.
struct NotchPlaybackContext: Equatable {
    let pid: Int32
    let revision: UUID

    init(pid: Int32, revision: UUID) { self.pid = pid; self.revision = revision }

    init?(reply: [String: Any]) {
        guard let rawPID = reply["pid"] as? NSNumber, CFGetTypeID(rawPID) != CFBooleanGetTypeID(),
              let pid = Int32(exactly: rawPID.doubleValue), pid > 0,
              let rawRevision = reply["playbackRevision"] as? String,
              let revision = UUID(uuidString: rawRevision) else { return nil }
        self.init(pid: pid, revision: revision)
    }
}

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
    case validate(UUID, NotchPlaybackContext)
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
            if parts.count == 4, parts[0] == "validate", let id = UUID(uuidString: String(parts[1])),
               let pid = Int32(parts[2]), pid > 0, let revision = UUID(uuidString: String(parts[3])) {
                self = .validate(id, NotchPlaybackContext(pid: pid, revision: revision)); return
            }
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

    var requiresPlaybackContext: Bool {
        switch self {
        case .toggle, .next, .previous, .seek: return true
        case .queue, .queueStop, .queuePlay, .validate: return false
        }
    }

    var message: String? {
        switch self {
        case .toggle: return "toggle"
        case .next: return "next"
        case .previous: return "previous"
        case .queue(let id): return "queue \(id.uuidString)"
        case .queueStop: return "queue-stop"
        case .validate(let id, let context):
            guard context.pid > 0 else { return nil }
            return "validate \(id.uuidString) \(context.pid) \(context.revision.uuidString)"
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

/// Queue actions already carry their own immutable selection. Basic controls
/// also need a destination; a bare legacy command is never accepted by the pipe.
struct NotchPlaybackRequest: Equatable {
    let command: NotchPlaybackCommand
    let context: NotchPlaybackContext?

    init(command: NotchPlaybackCommand, context: NotchPlaybackContext? = nil) {
        self.command = command
        self.context = command.requiresPlaybackContext ? context : nil
    }

    init?(message: String) {
        guard message.utf8.count <= NotchPlaybackCommand.maximumMessageBytes else { return nil }
        if message.hasPrefix("play ") {
            let parts = message.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4, let pid = Int32(parts[1]), pid > 0,
                  let revision = UUID(uuidString: String(parts[2])),
                  let command = NotchPlaybackCommand(message: String(parts[3])), command.requiresPlaybackContext else { return nil }
            self.init(command: command, context: NotchPlaybackContext(pid: pid, revision: revision))
        } else {
            guard let command = NotchPlaybackCommand(message: message), !command.requiresPlaybackContext else { return nil }
            self.init(command: command)
        }
    }

    var message: String? {
        guard let message = command.message else { return nil }
        guard command.requiresPlaybackContext else { return message }
        guard let context, context.pid > 0 else { return nil }
        return "play \(context.pid) \(context.revision.uuidString) \(message)"
    }
}

/// Pipe delivery can split one line or batch many. An oversized line is discarded
/// through its newline only; subsequent queue-stop and valid commands still run.
struct NotchPlaybackCommandFramer {
    private var line = Data()
    private var discarding = false

    mutating func append(_ data: Data) -> [NotchPlaybackRequest?] {
        var result: [NotchPlaybackRequest?] = []
        for byte in data {
            if byte == 0x0A {
                let command = discarding ? nil : String(data: line, encoding: .utf8).flatMap(NotchPlaybackRequest.init(message:))
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
