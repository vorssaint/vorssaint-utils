// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import CoreFoundation
import Foundation

/// Asks AGY's local /usage command. No prompt or model request is sent.
final class AntigravityQuotaService: ObservableObject {
    enum Failure: Error, Equatable {
        case missingCLI, incompatibleCLI, request, timeout, invalidResponse
    }

    typealias Reader = (BoundedProcessCancellation) -> Result<AgentLimits, Failure>
    static let shared = AntigravityQuotaService()
    @Published private(set) var limits: AgentLimits?
    @Published private(set) var checking = false
    @Published private(set) var failure: Failure?
    private var attempted = Date.distantPast
    private(set) var timer: Timer?
    private var visible = false
    private let defaults: UserDefaults
    private let reader: Reader
    private let queue = DispatchQueue(label: "com.vorssaint.antigravity-quota", qos: .utility)
    private var running: BoundedProcessCancellation?

    init(defaults: UserDefaults = .standard, reader: Reader? = nil) {
        self.defaults = defaults
        self.reader = reader ?? { cancellation in
            do { return .success(try Self.read(cancellation: cancellation)) }
            catch { return .failure((error as? Failure) ?? .request) }
        }
    }

    var isEnabled: Bool {
        NotchAgentSupport.isEnabled(in: defaults)
            && NotchAgentSupport.providers(in: defaults).contains(.antigravity)
            && NotchAgentSupport.cards(in: defaults).contains(.limits)
    }

    func synchronize() {
        guard isEnabled else {
            // Keep whether the page is showing, so switching the provider
            // back on restores polling without making the person reopen it.
            timer?.invalidate()
            timer = nil
            cancelCheck()
            return
        }
        if visible { appear() }
    }

    /// Quotas are checked only while the real page shows its Limits card.
    func appear() {
        guard isEnabled else { return }
        visible = true
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func disappear() {
        visible = false
        timer?.invalidate()
        timer = nil
    }

    /// Disabling the provider, sleeping or locking also ends a check in flight.
    func pause() {
        disappear()
        cancelCheck()
    }

    private func cancelCheck() {
        running?.cancel()
        running = nil
        checking = false
    }

    func refresh(force: Bool = false, now: Date = Date()) {
        guard isEnabled, visible || force, !checking,
              force || now.timeIntervalSince(attempted) >= 60 else { return }
        attempted = now
        checking = true
        let cancellation = BoundedProcessCancellation()
        running = cancellation
        queue.async { [weak self, reader] in
            guard !cancellation.isCancelled else { return }
            let result = reader(cancellation)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running === cancellation else { return }
                self.running = nil
                self.checking = false
                switch result {
                case .success(let limits):
                    self.failure = nil
                    self.limits = limits
                case .failure(let error):
                    // Keep the last reading visible, with the failed check noted.
                    self.failure = error
                }
            }
        }
    }

    static func decode(_ json: [String: Any], now: Date) -> AgentLimits? {
        guard json["status"] as? String == "SUCCESS",
              let command = json["command"] as? [String: Any], command["name"] as? String == "usage",
              let data = command["data"] as? [String: Any],
              let groups = data["groups"] as? [[String: Any]] else { return nil }
        var windows: [AgentLimitWindow] = []
        var seen: Set<String> = []
        for group in groups {
            let scope = (group["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            for bucket in group["buckets"] as? [[String: Any]] ?? [] {
                guard let number = bucket["remaining_fraction"] as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(),
                      case let fraction = number.doubleValue,
                      fraction.isFinite, (0...1).contains(fraction),
                      let id = bucket["id"] as? String, !id.isEmpty,
                      seen.insert(id).inserted else { continue }
                let window = bucket["window"] as? String ?? ""
                let weekly = window == "weekly"
                let session = ["five_hour", "five-hour", "5h", "session", "fiveHour", "five_hours"].contains(window)
                windows.append(AgentLimitWindow(id: id, kind: weekly ? .weekly : session ? .session : .other,
                    minutes: weekly ? 10080 : session ? 300 : nil, scope: scope, usedPercent: (1 - fraction) * 100,
                    resetsAt: AgentLogParser.timestamp(bucket["reset_time"])))
            }
        }
        guard !windows.isEmpty else { return nil }
        return AgentLimits(provider: .antigravity, windows: windows, observedAt: now, source: .account)
    }

    static func executable(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           searchPath: String = ProcessInfo.processInfo.environment["PATH"] ?? "") -> URL? {
        var folders = [home.appending(path: ".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
        folders += searchPath.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        return folders.map { URL(fileURLWithPath: $0).appending(path: "agy") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Older releases may interpret /usage as a model prompt. Never ask those.
    static func supportsUsage(_ version: String) -> Bool {
        let parts = version.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 3 else { return false }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3, numbers.allSatisfy({ $0 >= 0 }) else { return false }
        return !numbers.lexicographicallyPrecedes([1, 1, 11])
    }

    static func response(status: Int32, timedOut: Bool, output: Data) throws -> [String: Any] {
        if timedOut || status == 28 { throw Failure.timeout }
        guard status == 0 else { throw Failure.request }
        guard let json = AgentLogParser.object(output) else { throw Failure.invalidResponse }
        return json
    }

    static func read(executable: URL? = executable(),
                     cancellation: BoundedProcessCancellation = BoundedProcessCancellation()) throws -> AgentLimits {
        guard let executable else { throw Failure.missingCLI }
        let environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("ANTIGRAVITY_") }
        let version = BoundedProcessRunner.run(executable.path, ["--version"], timeout: 5, maxOutputBytes: 4096,
            environment: environment, cancellation: cancellation)
        guard !version.timedOut else { throw Failure.timeout }
        guard version.status == 0 else { throw Failure.request }
        guard supportsUsage(String(decoding: version.output, as: UTF8.self)) else { throw Failure.incompatibleCLI }
        let result = BoundedProcessRunner.run(executable.path,
            ["-p", "/usage", "--output-format", "json", "--print-timeout", "20s"],
            timeout: 25, maxOutputBytes: 2 << 20, environment: environment, cancellation: cancellation)
        let json = try response(status: result.status, timedOut: result.timedOut, output: result.output)
        guard let limits = decode(json, now: Date()) else { throw Failure.invalidResponse }
        return limits
    }
}
