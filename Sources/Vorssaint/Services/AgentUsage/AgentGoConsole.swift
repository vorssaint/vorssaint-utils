// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// The account's exact Go allowances from the OpenCode Console, read only
/// when the person turns the check on and pastes a Console API key. The key
/// lives in an owner-only file outside settings backups, never in a
/// preference, and the request carries nothing but the key itself.
enum AgentGoConsole {
    static let defaultEndpoint = "https://opencode.ai/zen/go/v1/usage"
    /// A reading this recent stands; a failed one is tried sooner.
    static let freshness: TimeInterval = 10 * 60
    static let retryAfter: TimeInterval = 60
    static let maximumSize = 64 * 1024

    enum Failure: Equatable {
        /// No key is saved yet, so nothing was asked.
        case missingKey
        /// The Console could not be reached, refused the key or answered
        /// something the parser does not recognize.
        case checkFailed
    }

    /// One allowance window as the Console reports it. The Console sends
    /// a used percent and a reset time; dollar caps travel only in the
    /// documented estimate shape, so both stay optional.
    struct Window: Equatable {
        var used: Double
        var limit: Double
        var percent: Double?
        var resetIn: TimeInterval?
        var resetAt: Date?
    }

    /// The three stacked windows, plus a per-model breakdown when the
    /// Console sends one.
    struct Reading: Equatable {
        var rolling: Window?
        var weekly: Window?
        var monthly: Window?
        var models: [String: Reading] = [:]
    }

    /// Window objects under the first key that holds one.
    private static func window(_ object: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let found = object[key] as? [String: Any] { return found }
        }
        return nil
    }

    private static func number(_ object: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = object[key] as? NSNumber { return value.doubleValue }
            if let text = object[key] as? String, let value = Double(text) { return value }
        }
        return nil
    }

    private static let isoFractionalSeconds: ISO8601DateFormatter = {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format
    }()

    private static let isoPlain: ISO8601DateFormatter = ISO8601DateFormatter()

    private static func resetDate(_ object: [String: Any]) -> Date? {
        guard let text = object["resetsAt"] as? String ?? object["resetAt"] as? String else { return nil }
        return isoFractionalSeconds.date(from: text) ?? isoPlain.date(from: text)
    }

    private static func parseWindow(_ object: [String: Any]?) -> Window? {
        guard let object else { return nil }
        let percent = number(object, keys: ["percent", "usedPercent", "usagePercent"])
        let limit = number(object, keys: ["limitDollars", "limit", "quota", "quotaDollars",
                                          "total", "totalDollars", "monthlyLimit"]) ?? 0
        guard percent != nil || limit > 0 else { return nil }
        let used = number(object, keys: ["usageDollars", "usage", "usedDollars", "used",
                                         "spent", "spentDollars", "consumed", "consumedDollars"]) ?? 0
        let resetIn = number(object, keys: ["resetInSec", "resetsIn", "resetSeconds", "resetIn",
                                            "resetAfterSec", "secondsUntilReset"])
        return Window(used: used, limit: limit, percent: percent,
                      resetIn: resetIn, resetAt: resetDate(object))
    }

    /// Reads the Console's shape tolerantly: window names, dollar fields
    /// and reset fields each come in several spellings, and unknown fields
    /// are ignored rather than failing the whole reading.
    static func decode(_ data: Data) -> Reading? {
        guard let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        // The live route nests the windows under "usage".
        let object = (top["usage"] as? [String: Any]) ?? top
        let rolling = parseWindow(window(object, keys: ["rolling5h", "rolling_5h", "rolling",
                                                        "fiveHour", "five_hour", "5h"]))
        let weekly = parseWindow(window(object, keys: ["weekly", "week", "weekWindow", "7d"]))
        let monthly = parseWindow(window(object, keys: ["monthly", "month", "monthWindow", "30d"]))
        var models: [String: Reading] = [:]
        if let breakdown = window(object, keys: ["models", "allowances", "breakdown"]) {
            for (name, entry) in breakdown {
                guard let entry = entry as? [String: Any] else { continue }
                let reading = Reading(
                    rolling: parseWindow(window(entry, keys: ["rolling5h", "rolling_5h", "rolling",
                                                               "fiveHour", "five_hour", "5h"])),
                    weekly: parseWindow(window(entry, keys: ["weekly", "week", "weekWindow", "7d"])),
                    monthly: parseWindow(window(entry, keys: ["monthly", "month", "monthWindow", "30d"])))
                guard reading.rolling != nil || reading.weekly != nil || reading.monthly != nil else { continue }
                models[name] = reading
            }
        }
        guard rolling != nil || weekly != nil || monthly != nil else { return nil }
        return Reading(rolling: rolling, weekly: weekly, monthly: monthly, models: models)
    }

    /// The island's windows from a Console reading. The exact percent wins
    /// over the dollar math wherever the Console sends one.
    static func limits(_ reading: Reading, observed: Date) -> AgentLimits? {
        func window(_ window: Window?, id: String, kind: AgentLimitWindow.Kind, minutes: Int) -> AgentLimitWindow? {
            guard let window else { return nil }
            let percent: Double
            if let exact = window.percent {
                percent = min(100, max(0, exact))
            } else {
                guard window.limit > 0 else { return nil }
                percent = AgentGoSupport.usedFraction(used: window.used, quota: window.limit) * 100
            }
            let reset = window.resetAt ?? window.resetIn.map { observed.addingTimeInterval(max(0, $0)) }
            return AgentLimitWindow(id: id, kind: kind, minutes: minutes, scope: nil,
                                    usedPercent: percent, resetsAt: reset)
        }
        let windows = [
            window(reading.rolling, id: "opencode.go.console.rolling", kind: .session, minutes: 300),
            window(reading.weekly, id: "opencode.go.console.weekly", kind: .weekly, minutes: 7 * 24 * 60),
            window(reading.monthly, id: "opencode.go.console.monthly", kind: .other, minutes: 30 * 24 * 60),
        ].compactMap { $0 }
        guard !windows.isEmpty else { return nil }
        return AgentLimits(provider: .opencode, windows: windows, observedAt: observed, source: .account)
    }

    // MARK: Key storage

    static let keyFileName = "go-console-key"

    static func keyFileURL(container: URL? = PrivateFileStore.containerURL) -> URL? {
        container?.appendingPathComponent(keyFileName, isDirectory: false)
    }

    /// The saved key or nil; empty files read as no key.
    static func readKey(container: URL? = PrivateFileStore.containerURL) -> String? {
        guard let url = keyFileURL(container: container),
              let data = try? Data(contentsOf: url),
              let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return nil }
        return key
    }

    /// Saves the key owner-only; an empty key removes the file instead.
    @discardableResult
    static func saveKey(_ key: String, container: URL? = PrivateFileStore.containerURL) -> Bool {
        guard let url = keyFileURL(container: container) else { return false }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return true
        }
        guard PrivateFileStore.createDirectory(at: url.deletingLastPathComponent(), container: container),
              let data = trimmed.data(using: .utf8) else { return false }
        return PrivateFileStore.write(data, to: url)
    }

    static func endpoint(in defaults: UserDefaults = .standard) -> URL? {
        let raw = (defaults.string(forKey: DefaultsKey.notchAgentsGoEndpoint) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = raw.isEmpty ? defaultEndpoint : raw
        guard let url = URL(string: text), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}

/// The Console's Go allowances for the AI page: checked when the page
/// shows, at most every few minutes, and only while the person keeps the
/// check on with a key saved.
final class AgentGoConsoleService: ObservableObject {
    static let shared = AgentGoConsoleService()

    @Published private(set) var limits: AgentLimits?
    @Published private(set) var reading: AgentGoConsole.Reading?
    @Published private(set) var failure: AgentGoConsole.Failure?
    @Published private(set) var checking = false

    private let queue = DispatchQueue(label: "com.vorssaint.go-console", qos: .userInitiated)
    private var attempted = Date.distantPast

    private init() {}

    /// Fresh enough to show: a reading younger than freshness, or nil.
    func currentLimits(now: Date = Date()) -> AgentLimits? {
        guard let limits, now.timeIntervalSince(limits.observedAt) < AgentGoConsole.freshness else { return nil }
        return limits
    }

    /// The fresh raw reading behind the limits, with its dollars, or nil.
    func currentReading(now: Date = Date()) -> (reading: AgentGoConsole.Reading, observed: Date)? {
        guard let limits, let reading,
              now.timeIntervalSince(limits.observedAt) < AgentGoConsole.freshness else { return nil }
        return (reading, limits.observedAt)
    }

    func refreshIfStale(now: Date = Date()) {
        let settled = failure != .checkFailed
        guard now.timeIntervalSince(attempted) >= (settled ? AgentGoConsole.freshness : AgentGoConsole.retryAfter) else { return }
        refresh()
    }

    /// The AI page appearing asks once; a preview never touches the network.
    func pageDidAppear(preview: Bool = false) {
        if !preview { refreshIfStale() }
    }

    func refresh() {
        guard !checking else { return }
        guard NotchAgentSupport.goConsole() else { return }
        guard let endpoint = AgentGoConsole.endpoint() else {
            set(failure: .missingKey, limits: nil, reading: nil)
            return
        }
        guard let key = AgentGoConsole.readKey() else {
            set(failure: .missingKey, limits: nil, reading: nil)
            return
        }
        checking = true
        attempted = Date()
        queue.async { [weak self] in
            GoConsoleDownload.get(endpoint, key: key) { data in
                guard let self else { return }
                guard let data, let reading = AgentGoConsole.decode(data),
                      let limits = AgentGoConsole.limits(reading, observed: Date()) else {
                    self.set(failure: .checkFailed, limits: nil, reading: nil)
                    return
                }
                self.set(failure: nil, limits: limits, reading: reading)
            }
        }
    }

    private func set(failure: AgentGoConsole.Failure?, limits: AgentLimits?, reading: AgentGoConsole.Reading? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.failure = failure
            self?.limits = limits
            self?.reading = reading
            self?.checking = false
        }
    }
}

/// One bounded request with the Console key and no cookies or cache, like
/// the price download: the key is the only thing sent.
private final class GoConsoleDownload: NSObject, URLSessionDataDelegate {
    private let limit: Int
    private let host: String?
    private var data = Data()
    private var status = 0
    private let completion: (Data?) -> Void

    private init(limit: Int, host: String?, completion: @escaping (Data?) -> Void) {
        self.limit = limit
        self.host = host
        self.completion = completion
    }

    static func get(_ url: URL, key: String, completion: @escaping (Data?) -> Void) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Vorssaint/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let delegate = GoConsoleDownload(limit: AgentGoConsole.maximumSize, host: url.host, completion: completion)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        session.dataTask(with: request).resume()
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let sameHost = request.url?.scheme == "https" && request.url?.host == host
        completionHandler(sameHost ? request : nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        status = (response as? HTTPURLResponse)?.statusCode ?? 0
        completionHandler(status == 200 ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        data.append(chunk)
        if data.count > limit { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        completion(error == nil && status == 200 && data.count <= limit ? data : nil)
    }
}
