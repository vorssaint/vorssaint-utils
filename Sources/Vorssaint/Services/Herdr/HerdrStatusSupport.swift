// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One supervised agent row from `herdr agent list`. Mirrors the socket
/// schema's AgentInfo (required ids, status, focus, revision) and drops the
/// `tokens` view-field registry, which is not usage data.
struct HerdrAgent: Equatable, Identifiable {
    var id: String { paneID }
    enum Status: String {
        case idle, working, blocked, done, unknown
    }

    let terminalID: String
    let workspaceID: String
    let tabID: String
    let paneID: String
    let focused: Bool
    let revision: UInt64
    let status: Status
    let displayName: String?
    let title: String?
    let cwd: String?
    let sequence: UInt64
}

/// One decoded `agent_list` answer.
struct HerdrStatusSnapshot: Equatable {
    let agents: [HerdrAgent]
    let fetchedAt: Date
}

/// Why a refresh produced no snapshot. `serverStopped` is an expected empty
/// state with its own UI line and slow retry, never an alert.
enum HerdrStatusError: Error, Equatable {
    case decode
    case server(code: String)
    case serverStopped
    case nonzeroExit(status: Int32, message: String)
    case timeout
    case missingBinary
    case unsupportedVersion
}

/// Decision-shaped herdr logic: envelope decoding, identity keys, machine
/// labels, polling cadence and badge gating. Pure static funcs over value
/// types so tests call them without the app.
enum HerdrStatusSupport {
    static func agentKey(_ agent: HerdrAgent) -> String {
        "\(agent.workspaceID):\(agent.tabID):\(agent.paneID)"
    }

    /// Polling shape shared with `PermissionPollingSupport`: nil while
    /// nothing needs watching, fast while a surface is open or a blocked
    /// agent wants attention, slow otherwise. A stopped server backs off
    /// even with a surface open; an unsupported binary never spins.
    static let fastInterval: TimeInterval = 2.5
    static let slowInterval: TimeInterval = 60

    static func cadence(visibleSurfaces: Int, hasBlockedAgent: Bool,
                        lastError: HerdrStatusError?) -> TimeInterval? {
        // An unsupported binary never spins the poller; a missing one is
        // availability the surface reports, not a failure to retry.
        if lastError == .unsupportedVersion || lastError == .missingBinary {
            return nil
        }
        // Any failure backs off instead of stopping: the next tick is how a
        // restarted server is noticed. A stopped server always backs off,
        // even with a blocked agent on record: that flag is stale history
        // from before the server died, and fast-polling a dead socket is
        // the spin the slow cadence exists to prevent.
        if lastError != nil {
            if lastError == .serverStopped { return slowInterval }
            return hasBlockedAgent ? fastInterval : slowInterval
        }
        guard visibleSurfaces > 0 || hasBlockedAgent else { return nil }
        return fastInterval
    }

    static func decode(_ data: Data) -> Result<HerdrStatusSnapshot, HerdrStatusError> {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.decode)
        }
        if let error = json["error"] as? [String: Any] {
            let code = error["code"] as? String ?? ""
            return .failure(code == "server_not_running" ? .serverStopped : .server(code: code))
        }
        guard let result = json["result"] as? [String: Any],
              let agents = result["agents"] as? [[String: Any]] else {
            return .failure(.decode)
        }
        var decoded: [HerdrAgent] = []
        for raw in agents {
            guard let terminalID = raw["terminal_id"] as? String,
                  let workspaceID = raw["workspace_id"] as? String,
                  let tabID = raw["tab_id"] as? String,
                  let paneID = raw["pane_id"] as? String,
                  let focused = raw["focused"] as? Bool,
                  let revision = (raw["revision"] as? NSNumber)?.uint64Value else {
                continue
            }
            let status = HerdrAgent.Status(rawValue: raw["agent_status"] as? String ?? "") ?? .unknown
            let title = raw["title"] as? String ?? raw["terminal_title"] as? String
            decoded.append(HerdrAgent(
                terminalID: terminalID,
                workspaceID: workspaceID,
                tabID: tabID,
                paneID: paneID,
                focused: focused,
                revision: revision,
                status: status,
                displayName: raw["name"] as? String ?? raw["agent"] as? String,
                title: title,
                cwd: raw["cwd"] as? String ?? raw["foreground_cwd"] as? String,
                sequence: (raw["state_change_seq"] as? NSNumber)?.uint64Value ?? 0
            ))
        }
        return .success(HerdrStatusSnapshot(agents: decoded, fetchedAt: Date()))
    }

    /// Identity is the pane's coordinates, never its name: a rename while
    /// running must not duplicate the row or drop its attention flag.

    /// One row update per status change: the pane, its monotonic revision
    /// and the status together. `state_change_seq` alone is not enough; it
    /// stays zero for non-status events that still carry a real status.
    static func dedupeKey(_ agent: HerdrAgent) -> String {
        "\(agent.paneID):\(agent.revision):\(agent.status.rawValue)"
    }

    static func needsAttention(_ snapshot: HerdrStatusSnapshot) -> Bool {
        snapshot.agents.contains { $0.status == .blocked }
    }

    /// The island badge reads only live status: a blocked agent raises it,
    /// and it clears the moment none is blocked. Empty is quiet.
    static func showsBadge(_ snapshot: HerdrStatusSnapshot) -> Bool {
        needsAttention(snapshot)
    }

    /// Remote labels ride `herdr --machine <label>` as one arg pair, so a
    /// label with a space or shell metacharacter must never reach the call.
    static func isValidMachineLabel(_ label: String) -> Bool {
        guard (1...64).contains(label.count) else { return false }
        return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
    }

    /// Saved labels: trimmed, deduped, invalid ones dropped, capped at
    /// eight, sorted so the stored string is stable.
    static func sanitizedMachines(_ raw: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for piece in raw.split(separator: ",") {
            let label = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidMachineLabel(label), seen.insert(label).inserted else { continue }
            result.append(label)
            if result.count >= 8 { break }
        }
        return result.sorted()
    }
}
