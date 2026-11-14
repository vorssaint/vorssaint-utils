// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Oh My Pi database rows as handed over by `AgentOhMyPiReader`.
/// Every session keeps its own turn and model tracking inside the shared
/// state. A prompt opens a turn, a reply that called tools keeps it going,
/// and a reply that stopped or failed ends it: Oh My Pi's statistics say
/// how each reply ended, so nothing has to be guessed from quiet spells.
struct OhMyPiReader: AgentHarnessReader {
    var provider: AgentProvider { .omp }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard AgentLogParser.contains(line, #""type":""#) else { return [] }
        guard let json = AgentLogParser.object(line) else { return [] }
        if json["type"] as? String == "reset" {
            state.ompSessions.removeAll()
            state.turnOpen = false
            return [.reset(now)]
        }
        let session = json["session"] as? String ?? ""
        let sessionID = session.isEmpty ? state.session : AgentLogParser.native(session)
        state.session = sessionID

        var sessionState = state.ompSessions[sessionID] ?? OhMyPiSessionState()
        if let folder = json["folder"] as? String, !folder.isEmpty {
            sessionState.project = Self.projectName(folder)
        }
        let date = AgentLogParser.seconds(json["timestamp"]) ?? now
        // Sessions are looked over only as a new one appears, as OpenCode's are.
        if state.ompSessions[sessionID] == nil {
            state.ompSessions = state.ompSessions.filter { _, kept in
                kept.turnOpen || date.timeIntervalSince(kept.lastActivity ?? date) < NotchAgentSupport.idleTurn
            }
        }
        let lastActivity = sessionState.lastActivity
        sessionState.lastActivity = max(lastActivity ?? date, date)

        switch json["type"] as? String {
        case "user":
            if let model = json["model"] as? String, !model.isEmpty {
                sessionState.model = AgentLogParser.native(model)
            }
            var entries: [AgentLogEntry] = []
            // A prompt after the session went quiet, with no reply that
            // ended the work, starts a task of its own: the one before
            // stopped without a word, as when Oh My Pi was killed.
            let quiet = lastActivity.map { date.timeIntervalSince($0) >= NotchAgentSupport.idleTurn } ?? false
            if sessionState.turnOpen && !quiet {
                entries.append(.turnActive(date))
            } else {
                if sessionState.turnOpen {
                    entries.append(.turnEnded(lastActivity, completed: false, duration: nil))
                }
                sessionState.turnOpen = true
                sessionState.turnStarted = date
                entries.append(.turnBegan(date))
            }
            state.ompSessions[sessionID] = sessionState
            state.project = sessionState.project
            state.model = sessionState.model
            state.turnOpen = true
            state.parentSession = ""
            return entries

        case "assistant":
            if let model = json["model"] as? String, !model.isEmpty {
                sessionState.model = AgentLogParser.native(model)
            }
            let agent = json["agent"] as? String ?? "main"
            state.parentSession = agent == "main" ? "" : sessionID
            var entries: [AgentLogEntry] = []
            if !sessionState.turnOpen {
                sessionState.turnOpen = true
                sessionState.turnStarted = date
                entries.append(.turnBegan(date))
            }
            let id = json["id"] as? String ?? ""
            if let usage = ohMyPiUsage(json, id: id, session: sessionID, date: date,
                                       model: sessionState.model, project: sessionState.project) {
                entries.append(usage)
            }
            let hasError = json["error"] as? Bool == true
            if json["stop"] as? String == "toolUse" && !hasError {
                entries.append(.turnActive(date))
            } else {
                var duration: TimeInterval?
                if let turnStarted = sessionState.turnStarted, date >= turnStarted {
                    duration = date.timeIntervalSince(turnStarted)
                }
                sessionState.turnOpen = false
                sessionState.turnStarted = nil
                entries.append(.turnEnded(date, completed: json["stop"] as? String == "stop" && !hasError,
                                          duration: duration))
            }
            state.ompSessions[sessionID] = sessionState
            state.project = sessionState.project
            state.model = sessionState.model
            state.turnOpen = sessionState.turnOpen
            return entries

        default:
            return []
        }
    }

    /// Oh My Pi names a session's folder after its working folder with the
    /// home folder left off and each path separator written as a dash, so
    /// the name it kept is rebuilt into a path and the project is its last
    /// folder. A folder written with a dash of its own reads as two folders;
    /// only its last one names the project either way. A value that already
    /// is a path is taken as it stands.
    static func projectName(_ folder: String) -> String {
        if folder.hasPrefix("/") { return AgentLogParser.projectName(folder) }
        var path = folder
        if path.hasPrefix("-") { path.removeFirst() }
        guard !path.isEmpty else { return "" }
        return AgentLogParser.projectName("/" + path.replacingOccurrences(of: "-", with: "/"))
    }

    /// What one Oh My Pi reply used, priced from the list when it knows the
    /// model; a model the list does not know costs what Oh My Pi recorded,
    /// which already counts its cache traffic. A reply Oh My Pi could not
    /// price, and the list cannot either, stays unpriced rather than free.
    private func ohMyPiUsage(_ json: [String: Any], id: String, session: String, date: Date,
                             model: String, project: String) -> AgentLogEntry? {
        let tokensDict = json["tokens"] as? [String: Any] ?? [:]
        let tokens = AgentTokens(input: AgentLogParser.int(tokensDict["input"]),
                                 cacheWrite: AgentLogParser.int(tokensDict["cacheWrite"]),
                                 cacheRead: AgentLogParser.int(tokensDict["cacheRead"]),
                                 output: AgentLogParser.int(tokensDict["output"]))
        let recordedCost = (json["cost"] as? NSNumber)?.doubleValue
        guard tokens.total > 0 || (recordedCost ?? 0) > 0 else { return nil }
        let billable = AgentBillable(tokens: tokens)
        let priced = AgentPricing.cost(billable, model: model)
        let cost: Double?
        let isReported: Bool
        if let calculated = priced.cost {
            cost = calculated
            isReported = false
        } else if let recordedCost, recordedCost > 0 {
            cost = recordedCost
            isReported = true
        } else if json["unpriced"] as? Bool == true {
            cost = nil
            isReported = false
        } else {
            // A local or free model records zero, which stays an estimate so
            // a price the list learns later still applies.
            cost = recordedCost
            isReported = false
        }
        let key = "omp:\(session):\(id.isEmpty ? "\(date.timeIntervalSince1970)" : id)"
        let record = AgentUsageRecord(provider: .omp, date: date, model: model, project: project,
                                      session: session, tokens: tokens, cost: cost, savings: priced.savings,
                                      reportedCost: isReported)
        return .usage(key: key, record: record, billable: billable)
    }
}
