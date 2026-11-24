// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads the account's monthly credits through Kiro CLI's own Agent Client
/// Protocol server, the same answer its `/usage` command shows. Kiro signs in
/// with its own credentials, which Vorssaint never reads, and no session,
/// prompt or tool is started: only `initialize` and the usage question.
///
/// The session logs cannot stand in for this: they hold only this Mac's
/// turns, across every billing month, while the allowance counts the whole
/// account for the current month.
enum AgentKiroServer {
    enum Failure: Error, Equatable {
        case missing, needsSignIn, outdated, unreachable
    }

    struct Summary: Equatable {
        let limits: AgentLimits
        let plan: AgentPlan?
    }

    static let timeout: TimeInterval = 25
    static let freshness: TimeInterval = 60
    static let backgroundFreshness: TimeInterval = 5 * 60
    static let retryAfter: TimeInterval = 5 * 60
    /// Only the person can install, update or sign in to Kiro CLI.
    static let settledRetry: TimeInterval = 30 * 60
    static let usageMethod = "_kiro/account/getUsage"
    /// What Kiro charges per credit past a plan's allowance
    /// (kiro.dev/docs/billing/add-on-credits), when an answer leaves it out.
    static let addOnPrice = 0.04
    /// The source of overage charges in the store: the account, never a log.
    /// The archive keeps what it gave though no log holds it.
    static let accountSource = "account:kiro"
    /// The account question exists only in Kiro's newer agent engine; the
    /// default one answers that the method is not found.
    static let arguments = ["acp", "--agent-engine", "v3"]

    static func interval(after failure: Failure?, pageVisible: Bool) -> TimeInterval {
        switch failure {
        case nil: return pageVisible ? freshness : backgroundFreshness
        case .unreachable?: return retryAfter
        case .missing?, .needsSignIn?, .outdated?: return settledRetry
        }
    }

    /// The installer links `kiro-cli` from `~/.local/bin` into the app, which
    /// is also where an app opened from Finder finds it without a PATH.
    static func candidates(home: URL, searchPath: String? = nil) -> [URL] {
        let bundled = URL(fileURLWithPath: "/Applications/Kiro CLI.app/Contents/MacOS/kiro-cli")
        let folders = [home.appending(path: ".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
            + (searchPath ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        return folders.map { URL(fileURLWithPath: $0, isDirectory: true).appending(path: "kiro-cli") } + [bundled]
    }

    static func executable(home: URL, searchPath: String? = nil) -> URL? {
        candidates(home: home, searchPath: searchPath).first {
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &directory) && !directory.boolValue
                && FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    /// The month's credits as one window. Kiro names the reset by its day
    /// only, without a time or zone, so it is placed at that day's start in UTC.
    static func summary(_ result: [String: Any], observed: Date) -> Result<Summary, Failure> {
        guard result["success"] as? Bool != false, let data = result["data"] as? [String: Any] else {
            let message = (result["message"] as? String ?? "").lowercased()
            return .failure(signInWords.contains(where: message.contains) ? .needsSignIn : .unreachable)
        }
        let breakdowns = data["usageBreakdowns"] as? [[String: Any]] ?? []
        guard let credit = breakdowns.first(where: { ($0["resourceType"] as? String)?.uppercased() == "CREDIT" }),
              let used = number(credit["used"]), let limit = number(credit["limit"]), limit > 0,
              credit["hasLimit"] as? Bool != false else { return .failure(.unreachable) }
        let overage = number(credit["currentOverages"]) ?? max(0, used - limit)
        let rate = number(credit["overageRate"]) ?? addOnPrice
        let credits = AgentCredits(used: used, limit: limit, overage: overage, overageRate: rate,
                                   overageCharges: number(credit["overageCharges"]) ?? overage * rate)
        let resets = (data["billingCycleReset"] as? String).flatMap(day)
        let window = AgentLimitWindow(id: "kiro.credits", kind: .other, minutes: nil, scope: nil,
                                      usedPercent: min(100, used / limit * 100), resetsAt: resets, credits: credits)
        return .success(Summary(limits: AgentLimits(provider: .kiro, windows: [window], observedAt: observed,
                                                    source: .account),
                                plan: (data["planName"] as? String).flatMap(plan)))
    }

    /// What the month's overage grew by since the charges already recorded
    /// for it, as spending at the moment it was read. Readings are minutes
    /// apart, so a charge lands within one check of when it was made; one
    /// already standing at the first reading of a month lands then.
    static func overage(_ limits: AgentLimits, recorded: [AgentUsageRecord]) -> AgentLogEntry? {
        guard let window = limits.windows.first(where: { $0.credits != nil }), let credits = window.credits,
              let resets = window.resetsAt else { return nil }
        let month = overageSession(resets: resets)
        let charged = recorded.reduce(0.0) { $1.provider == .kiro && $1.session == month ? $0 + ($1.cost ?? 0) : $0 }
        // Cents only: a charge read again to the last fraction is no news.
        let growth = ((credits.overageCharges - charged) * 100).rounded() / 100
        guard growth > 0 else { return nil }
        let observed = limits.observedAt
        return .usage(key: "kiro:\(month):\(Int(observed.timeIntervalSince1970))", record: AgentUsageRecord(
            provider: .kiro, date: observed, model: "", project: "", session: month, requests: 0,
            tokens: AgentTokens(), cost: growth, savings: 0, reportedCost: true),
            billable: AgentBillable(isAggregate: true))
    }

    /// The billing month an overage charge belongs to, named by its renewal.
    static func overageSession(resets: Date) -> String {
        overagePrefix + String(Int(resets.timeIntervalSince1970))
    }

    static let overagePrefix = "overage:"

    /// The account answer names the plan but not its price, so the monthly
    /// list prices Kiro publishes (kiro.dev/pricing) stand in. An enterprise
    /// contract may pay otherwise, which is why they read as list prices.
    static let listPrices: [String: Double] = ["FREE": 0, "PRO": 20, "PRO+": 40, "PRO MAX": 100, "POWER": 200]

    /// "KIRO POWER" reads as "Power", the name Kiro's plans go by.
    static func plan(_ name: String) -> AgentPlan? {
        var words = name.split(separator: " ").map(String.init)
        if words.first?.uppercased() == "KIRO" { words.removeFirst() }
        guard !words.isEmpty else { return nil }
        let title = words.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
        return AgentPlan(name: title, monthlyPrice: listPrices[words.joined(separator: " ").uppercased()])
    }

    /// Past its reset the month has started over; until it is read again
    /// nothing says what was spent since.
    static func current(_ reading: AgentLimits?, now: Date) -> AgentLimits? {
        guard var reading else { return nil }
        reading.windows.removeAll { $0.resetsAt.map { $0 <= now } ?? false }
        return reading.windows.isEmpty ? nil : reading
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0 else { return nil }
        return number.doubleValue
    }

    private static func day(_ text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return AgentTimestamp.parse(text) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// How Kiro words a missing or expired sign-in.
    private static let signInWords = ["auth", "login", "log in", "logged", "sign in", "signed", "token"]

    static func failure(_ error: Any?) -> Failure {
        let error = error as? [String: Any]
        let message = (error?["message"] as? String ?? "").lowercased()
        if (error?["code"] as? NSNumber)?.intValue == -32601 || message.contains("method not found") { return .outdated }
        if signInWords.contains(where: message.contains) { return .needsSignIn }
        return .unreachable
    }

    /// A cancellable, short-lived CLI invocation; pause/disable closes it too.
    final class Request {
        private let lock = NSLock()
        private var cancelled = false
        private var conversation: AgentCLIConversation?

        func cancel() {
            let active = lock.withLock { () -> AgentCLIConversation? in
                cancelled = true
                return conversation
            }
            active?.end()
        }

        func run(_ executable: URL, environment: [String: String],
                 timeout: TimeInterval = AgentKiroServer.timeout) -> Result<Summary, Failure> {
            guard !lock.withLock({ cancelled }),
                  let channel = AgentCLIConversation(executable, arguments: AgentKiroServer.arguments,
                                                     environment: environment, timeout: timeout)
            else { return .failure(.unreachable) }
            let accepted = lock.withLock { () -> Bool in
                guard !cancelled else { return false }
                conversation = channel
                return true
            }
            defer {
                channel.end()
                lock.withLock { conversation = nil }
            }
            guard accepted else { return .failure(.unreachable) }
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let client: [String: Any] = ["name": "vorssaint", "title": "Vorssaint", "version": version]
            return ask(channel, id: 1, method: "initialize",
                       params: ["protocolVersion": 1, "clientCapabilities": [String: Any](), "clientInfo": client])
                .flatMap { _ in self.ask(channel, id: 2, method: AgentKiroServer.usageMethod, params: [:]) }
                .flatMap { result in
                    guard !self.lock.withLock({ self.cancelled }) else { return .failure(.unreachable) }
                    return AgentKiroServer.summary(result, observed: Date())
                }
        }

        private func ask(_ channel: AgentCLIConversation, id: Int, method: String,
                         params: [String: Any]) -> Result<[String: Any], Failure> {
            guard channel.send(["jsonrpc": "2.0", "id": id, "method": method, "params": params]) else {
                return .failure(.unreachable)
            }
            while let message = channel.next() {
                // Notifications and the agent's own requests are not the answer.
                guard message["method"] == nil, (message["id"] as? NSNumber)?.intValue == id else { continue }
                if let result = message["result"] as? [String: Any] { return .success(result) }
                return .failure(AgentKiroServer.failure(message["error"]))
            }
            return .failure(.unreachable)
        }
    }
}
