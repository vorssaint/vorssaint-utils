// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation
import Network

/// The connection's health while the internet check is on: whether the Mac
/// has a usable interface (the system's path monitor, nothing sent), and
/// whether a tiny request reaches the internet, its round trip as latency and
/// the spread of recent round trips as jitter. It keeps running with the
/// panel closed, so the history shows a drop that happened while nobody
/// watched. That is also why it is off by default: unlike every other network
/// reading, it sends a request every few seconds.
///
/// Main thread only.
final class NetworkStatusService: NSObject, ObservableObject {
    static let shared = NetworkStatusService()

    static let probeIntervals: [Int] = [2, 5, 10, 30, 60]
    static let defaultProbeInterval = 5 // also the registered default
    /// The panel's history row: five minutes at the default interval.
    static let historyLength = 60
    private static let jitterWindow = 10
    private static let defaultEndpoint = URL(string: "\(SpeedTest.host)/__down?bytes=0")!

    @Published private(set) var interfaceUp: Bool?
    /// Every internet check, oldest first: whether it got through.
    @Published private(set) var history: [Bool] = []
    @Published private(set) var latencyMs: Double?
    @Published private(set) var jitterMs: Double?

    var internetUp: Bool? { history.last }

    private var session: URLSession!
    private var pathMonitor: NWPathMonitor?
    private var timer: Timer?
    private var task: URLSessionDataTask?
    private var lastEndpoint: URL?
    private var recentLatencies: [Double] = []
    private var generation = 0

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 3
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// The Settings controls and the feature's availability all call this.
    /// A new interval restarts the history, since its squares would no
    /// longer stand for the same span of time.
    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        guard AppFeature.monitorNetwork.isAvailable,
              defaults.bool(forKey: DefaultsKey.networkConnectivityCheck) else {
            stop()
            return
        }
        let interval = TimeInterval(Self.probeInterval(defaults.integer(forKey: DefaultsKey.networkConnectivityInterval)))
        if let timer, timer.timeInterval != interval { stop() }
        start(interval: interval)
    }

    /// A stored interval the picker no longer offers falls back to the default.
    static func probeInterval(_ stored: Int) -> Int {
        probeIntervals.contains(stored) ? stored : defaultProbeInterval
    }

    /// What the check requests for the host typed in Settings: a bare name or
    /// address goes over HTTPS, an http(s) URL is used as given. Empty means
    /// the speed test's Cloudflare endpoint; anything else unusable is nil.
    static func probeURL(host: String) -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultEndpoint }
        guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)"),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false else { return nil }
        return url
    }

    private func start(interval: TimeInterval) {
        guard timer == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.pathChanged(up: path.status == .satisfied) }
        }
        monitor.start(queue: .global(qos: .utility))
        pathMonitor = monitor

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.probe()
        }
        timer.tolerance = min(1, interval / 5)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        probe()
    }

    private func stop() {
        guard timer != nil else { return }
        generation += 1
        timer?.invalidate()
        timer = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        task?.cancel()
        task = nil
        lastEndpoint = nil
        recentLatencies = []
        interfaceUp = nil
        history = []
        latencyMs = nil
        jitterMs = nil
    }

    private func pathChanged(up: Bool) {
        guard pathMonitor != nil, interfaceUp != up else { return }
        interfaceUp = up
        // Joining or leaving a network is the moment the history should show.
        probe()
    }

    // ponytail: a round trip on a new connection (the first check, after a
    // network change) includes the TLS handshake; read URLSessionTaskMetrics
    // if that one high sample turns out to skew jitter.
    /// A check still waiting when the next is due lets that one pass, so
    /// checks never overlap.
    private func probe() {
        guard task == nil else { return }
        guard interfaceUp != false else {
            record(latency: nil)
            return
        }
        // Read on every check, so a host typed in Settings applies without a
        // restart. Round trips to another server are not comparable.
        let host = UserDefaults.standard.string(forKey: DefaultsKey.networkConnectivityHost) ?? ""
        let endpoint = Self.probeURL(host: host) ?? Self.defaultEndpoint
        if endpoint != lastEndpoint {
            lastEndpoint = endpoint
            recentLatencies = []
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "HEAD"
        let started = ProcessInfo.processInfo.systemUptime
        let generation = self.generation
        task = session.dataTask(with: request) { [weak self] _, response, error in
            let latency = (ProcessInfo.processInfo.systemUptime - started) * 1000
            // Any answer from the server proves the way out works, whatever its status.
            let reached = error == nil && response is HTTPURLResponse
            DispatchQueue.main.async {
                guard let self, self.generation == generation else { return }
                self.task = nil
                self.record(latency: reached ? latency : nil)
            }
        }
        task?.resume()
    }

    /// One check's result: its round trip in milliseconds, or nil when it did
    /// not get through.
    func record(latency: Double?) {
        history.append(latency != nil)
        if history.count > Self.historyLength {
            history.removeFirst(history.count - Self.historyLength)
        }
        latencyMs = latency
        if let latency {
            recentLatencies.append(latency)
            if recentLatencies.count > Self.jitterWindow {
                recentLatencies.removeFirst()
            }
        }
        jitterMs = latency == nil ? nil : Self.jitter(recentLatencies)
    }

    /// The mean change between consecutive round trips, as RFC 3550 defines
    /// jitter but without its smoothing: the short window already steadies it.
    static func jitter(_ latencies: [Double]) -> Double? {
        guard latencies.count >= 2 else { return nil }
        let changes = zip(latencies, latencies.dropFirst()).map { abs($1 - $0) }
        return changes.reduce(0, +) / Double(changes.count)
    }
}

extension NetworkStatusService: URLSessionTaskDelegate {
    /// A redirect is already an answer; following it would add a second
    /// round trip to the latency.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
