// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What `vors` accepts and what it says to the running app. Pure logic so the
/// harness can pin down the parsing and the messages any local process can send.
enum CommandLineSupport {
    static let toolName = "vors"
    static let keepAwakeCommand = "keepawake"
    /// A year. Only there to stop a typo from becoming an unreachable end date.
    static let maximumMinutes = 525_600

    static let usage = """
        usage: vors keepawake [on]        start the last used session
               vors keepawake -m MINUTES  keep awake for MINUTES, 0 for no end time
               vors keepawake off         end the session
               vors keepawake status      show the session
               vors help                  show this message
        """

    enum KeepAwakeAction: Equatable {
        case start
        case minutes(Int)
        case off
        case status
    }

    enum Command: Equatable {
        case help
        case invalid(String)
        case keepAwake(KeepAwakeAction)
    }

    /// nil when these arguments belong to the app itself. Under its own name
    /// the tool answers everything, so a mistyped command never opens a second
    /// copy of the app.
    static func command(in arguments: [String]) -> Command? {
        let isTool = arguments.first.map { ($0 as NSString).lastPathComponent == toolName } ?? false
        let words = Array(arguments.dropFirst())
        if words.first == keepAwakeCommand { return parseKeepAwake(Array(words.dropFirst())) }
        guard isTool else { return nil }
        guard let word = words.first, !["help", "-h", "--help"].contains(word) else { return .help }
        return .invalid("unknown command '\(word)'")
    }

    private static func parseKeepAwake(_ words: [String]) -> Command {
        switch words.first {
        case nil, "on":
            return words.count <= 1 ? .keepAwake(.start) : .invalid("unexpected '\(words[1])'")
        case "off":
            return words.count == 1 ? .keepAwake(.off) : .invalid("unexpected '\(words[1])'")
        case "status":
            return words.count == 1 ? .keepAwake(.status) : .invalid("unexpected '\(words[1])'")
        case "-m", "--minutes":
            guard words.count >= 2 else { return .invalid("\(words[0]) needs a number of minutes") }
            guard let minutes = Int(words[1]), isValid(minutes: minutes) else {
                return .invalid("minutes must be a whole number from 0 to \(maximumMinutes)")
            }
            return words.count == 2 ? .keepAwake(.minutes(minutes)) : .invalid("unexpected '\(words[2])'")
        case let word?:
            return .invalid("unknown keepawake option '\(word)'")
        }
    }

    private static func isValid(minutes: Int) -> Bool {
        (0...maximumMinutes).contains(minutes)
    }

    /// nil for a preset. `activate(minutes:)` turns any other length into an
    /// indefinite session, so a typed number has to become an end time.
    static func endDate(forMinutes minutes: Int, now: Date) -> Date? {
        Defaults.allowedDurations.contains(minutes) ? nil : now.addingTimeInterval(TimeInterval(minutes) * 60)
    }

    // MARK: - Messages to the running app

    static func requestName(bundleIdentifier: String) -> Notification.Name {
        Notification.Name("\(bundleIdentifier).commandLine.request")
    }

    static func answerName(bundleIdentifier: String) -> Notification.Name {
        Notification.Name("\(bundleIdentifier).commandLine.answer")
    }

    /// Any local process can post this, so the app reads it as untrusted input.
    struct Request: Equatable {
        var id: String
        var action: KeepAwakeAction

        init(id: String, action: KeepAwakeAction) {
            self.id = id
            self.action = action
        }

        init?(userInfo: [AnyHashable: Any]?) {
            guard let id = userInfo?["id"] as? String, let name = userInfo?["action"] as? String else { return nil }
            self.id = id
            switch name {
            case "start": action = .start
            case "off": action = .off
            case "status": action = .status
            case "minutes":
                guard let minutes = userInfo?["minutes"] as? Int, isValid(minutes: minutes) else { return nil }
                action = .minutes(minutes)
            default: return nil
            }
        }

        var userInfo: [String: Any] {
            switch action {
            case .start: return ["id": id, "action": "start"]
            case .off: return ["id": id, "action": "off"]
            case .status: return ["id": id, "action": "status"]
            case .minutes(let minutes): return ["id": id, "action": "minutes", "minutes": minutes]
            }
        }
    }

    struct Answer: Equatable {
        var id: String
        var isAvailable: Bool
        var isActive: Bool
        var endDate: Date? // nil = indefinite

        init(id: String, isAvailable: Bool, isActive: Bool, endDate: Date?) {
            self.id = id
            self.isAvailable = isAvailable
            self.isActive = isActive
            self.endDate = endDate
        }

        init?(userInfo: [AnyHashable: Any]?) {
            guard let id = userInfo?["id"] as? String,
                  let isAvailable = userInfo?["available"] as? Bool,
                  let isActive = userInfo?["active"] as? Bool else { return nil }
            self.init(id: id, isAvailable: isAvailable, isActive: isActive,
                      endDate: (userInfo?["end"] as? Double).map(Date.init(timeIntervalSinceReferenceDate:)))
        }

        var userInfo: [String: Any] {
            var info: [String: Any] = ["id": id, "available": isAvailable, "active": isActive]
            if let endDate { info["end"] = endDate.timeIntervalSinceReferenceDate }
            return info
        }
    }
}
