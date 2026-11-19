// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreFoundation
import Foundation

/// Kimi Code's China and international services have separate credentials.
enum KimiRegion: String, CaseIterable, Identifiable {
    case china, international

    var id: String { rawValue }
    var usageURL: URL {
        URL(string: "https://api.kimi.\(self == .china ? "com" : "ai")/coding/v1/usages")!
    }
    var consoleURL: URL {
        URL(string: "https://www.kimi.\(self == .china ? "com" : "ai")/code/console")!
    }

    static func stored(in defaults: UserDefaults = .standard) -> Self {
        if let raw = defaults.string(forKey: DefaultsKey.notchAgentsKimiRegion),
           let region = Self(rawValue: raw) {
            return region
        }
        // The CLI's config names its service region; follow it until the
        // person chooses one explicitly.
        return KimiCLIAuth.configuredRegion() ?? .china
    }
}

struct KimiUsageReading: Equatable {
    let limits: AgentLimits
    let plan: AgentPlan?
}

enum KimiUsageError: Error, Equatable {
    case expiredCredential, unauthorized, unavailable, invalidResponse, cancelled
}

/// Both generations of the usages response: absolute request counts and the
/// newer ratio pools. Percentages, not token or request estimates, are kept.
enum KimiUsageParser {
    static func reading(_ data: Data, observedAt: Date) -> KimiUsageReading? {
        guard data.count <= 64 * 1024,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        var windows: [String: AgentLimitWindow] = [:]

        if let usage = root["usage"] as? [String: Any],
           let window = countedWindow(usage, id: "kimi.7d", kind: .weekly, minutes: 10_080) {
            windows[window.id] = window
        }
        for item in root["limits"] as? [[String: Any]] ?? [] {
            guard let descriptor = item["window"] as? [String: Any],
                  let minutes = durationMinutes(descriptor),
                  let detail = item["detail"] as? [String: Any]
            else { continue }
            let kind: AgentLimitWindow.Kind = minutes == 300 ? .session : minutes == 10_080 ? .weekly : .other
            let id = kind == .session ? "kimi.5h" : kind == .weekly ? "kimi.7d" : "kimi.\(minutes)m"
            if let window = countedWindow(detail, id: id, kind: kind, minutes: minutes) {
                merge(window, into: &windows)
            }
        }
        let pools = root["usages"] as? [String: Any] ?? [:]
        for (name, value) in pools {
            // Code is a share of the account-wide monthly pool, not another cap.
            if name == "limit_month_code", pools["limit_month_total"] != nil { continue }
            guard let pool = value as? [String: Any], let ratio = number(pool["used_ratio"]), ratio >= 0,
                  let descriptor = ratioWindow(name)
            else { continue }
            let reset = (pool["reset_time"] as? String).flatMap(AgentTimestamp.parse)
            let window = AgentLimitWindow(id: descriptor.id, kind: descriptor.kind, minutes: descriptor.minutes,
                                          scope: descriptor.scope, usedPercent: ratio * 100, resetsAt: reset)
            merge(window, into: &windows)
        }
        guard !windows.isEmpty else { return nil }
        let order = ["kimi.5h", "kimi.7d", "kimi.month.total", "kimi.month.code"]
        let sorted = windows.values.sorted {
            let left = order.firstIndex(of: $0.id) ?? order.count
            let right = order.firstIndex(of: $1.id) ?? order.count
            return left != right ? left < right : $0.id < $1.id
        }
        let membership = (root["membership"] as? [String: Any])?["level"] as? String
            ?? ((root["user"] as? [String: Any])?["membership"] as? [String: Any])?["level"] as? String
        let plan = membership.flatMap { level -> AgentPlan? in
            let name = level.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 40 else { return nil }
            return AgentPlan(name: name.capitalized, monthlyPrice: nil)
        }
        return KimiUsageReading(limits: AgentLimits(provider: .kimi, windows: sorted, observedAt: observedAt,
                                                    source: .account), plan: plan)
    }

    private static func countedWindow(_ detail: [String: Any], id: String, kind: AgentLimitWindow.Kind,
                                      minutes: Int) -> AgentLimitWindow? {
        guard let limit = number(detail["limit"]), limit > 0, let used = number(detail["used"]), used >= 0
        else { return nil }
        return AgentLimitWindow(id: id, kind: kind, minutes: minutes, scope: nil,
                                usedPercent: used / limit * 100,
                                resetsAt: (detail["resetTime"] as? String).flatMap(AgentTimestamp.parse))
    }

    private static func ratioWindow(_ name: String) -> (id: String, kind: AgentLimitWindow.Kind,
                                                        minutes: Int?, scope: String?)? {
        switch name {
        case "limit_5h": return ("kimi.5h", .session, 300, nil)
        case "limit_7d", "limit_week", "limit_weekly": return ("kimi.7d", .weekly, 10_080, nil)
        case "limit_month_total": return ("kimi.month.total", .monthly, nil, nil)
        case "limit_month_code": return ("kimi.month.code", .monthly, nil, "Kimi Code")
        default: return nil
        }
    }

    private static func durationMinutes(_ descriptor: [String: Any]) -> Int? {
        guard let duration = number(descriptor["duration"]), duration > 0,
              let unit = descriptor["timeUnit"] as? String
        else { return nil }
        let seconds: Double
        switch unit {
        case "TIME_UNIT_MINUTE": seconds = duration * 60
        case "TIME_UNIT_HOUR": seconds = duration * 3600
        case "TIME_UNIT_SECOND": seconds = duration
        default: return nil
        }
        let minutes = seconds / 60
        return minutes.rounded() == minutes && minutes <= Double(Int.max) ? Int(minutes) : nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let string = value as? String { return Double(string).flatMap { $0.isFinite ? $0 : nil } }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite
        else { return nil }
        return number.doubleValue
    }

    private static func merge(_ window: AgentLimitWindow, into windows: inout [String: AgentLimitWindow]) {
        guard let previous = windows[window.id] else { windows[window.id] = window; return }
        let matchingReset = previous.resetsAt == nil || window.resetsAt == nil
            || abs(previous.resetsAt!.timeIntervalSince(window.resetsAt!)) <= 2
        guard matchingReset else { return }
        windows[window.id] = window.usedPercent > previous.usedPercent ? window : previous
    }
}

/// A bounded, cookie-free request. Authorization never follows a redirect to
/// another host, and responses stay small enough to be quota metadata only.
private final class KimiUsageDownload: NSObject, URLSessionDataDelegate {
    private let host: String?
    private let completion: (Result<Data, KimiUsageError>) -> Void
    private var data = Data()
    private var status = 0
    private var responseFailure: KimiUsageError?
    private var finished = false

    init(host: String?, completion: @escaping (Result<Data, KimiUsageError>) -> Void) {
        self.host = host
        self.completion = completion
    }

    static func start(authentication: KimiAuthentication, region: KimiRegion,
                      completion: @escaping (Result<Data, KimiUsageError>) -> Void) -> URLSessionTask {
        var request = URLRequest(url: region.usageURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(authentication.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Vorssaint/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        for (name, value) in authentication.identityHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let delegate = KimiUsageDownload(host: region.usageURL.host, completion: completion)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        task.resume()
        session.finishTasksAndInvalidate()
        return task
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let allowed = request.url?.scheme == "https" && request.url?.host == host
        if !allowed { responseFailure = .unavailable }
        completionHandler(allowed ? request : nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let allowed = status == 200 || status == 401 || status == 403
        if !allowed { responseFailure = .unavailable }
        completionHandler(allowed ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        data.append(chunk)
        if data.count > 64 * 1024 {
            responseFailure = .invalidResponse
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        finished = true
        if let responseFailure { completion(.failure(responseFailure)); return }
        if (error as? URLError)?.code == .cancelled { completion(.failure(.cancelled)); return }
        guard error == nil, data.count <= 64 * 1024 else { completion(.failure(.unavailable)); return }
        if status == 401 || status == 403 { completion(.failure(.unauthorized)); return }
        guard status == 200 else { completion(.failure(.unavailable)); return }
        completion(.success(data))
    }
}

enum KimiUsageClient {
    static func fetch(authentication: KimiAuthentication, region: KimiRegion,
                      completion: @escaping (Result<KimiUsageReading, KimiUsageError>) -> Void) -> URLSessionTask {
        KimiUsageDownload.start(authentication: authentication, region: region) { result in
            completion(result.flatMap { data in
                guard let reading = KimiUsageParser.reading(data, observedAt: Date()) else {
                    return .failure(.invalidResponse)
                }
                return .success(reading)
            })
        }
    }
}
