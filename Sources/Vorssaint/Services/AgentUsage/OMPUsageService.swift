// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Runs Oh My Pi's own quota command. Oh My Pi keeps and refreshes provider
/// credentials; Vorssaint receives only the bounded JSON usage report.
enum OMPUsageClient {
    static let timeout: TimeInterval = 30

    static func fetch(executable: URL, cancellation: BoundedProcessCancellation) -> Result<[OMPUsageReading], OMPUsageError> {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ([executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"]
            + [environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        let result = BoundedProcessRunner.run(executable.path,
            ["usage", "--json", "--no-extensions"], timeout: timeout, maxOutputBytes: 4 * 1024 * 1024,
            environment: environment, cancellation: cancellation)
        if cancellation.isCancelled { return .failure(.cancelled) }
        guard !result.timedOut, result.status == 0 else { return .failure(.unavailable) }
        guard let readings = OMPUsageParser.readings(result.output, observedAt: Date()) else {
            return .failure(.invalidResponse)
        }
        return .success(readings)
    }
}

/// Account limits checked only while the AI page uses them. The last good
/// readings survive a command or network failure, as Kimi's reading does.
final class OMPUsageService: ObservableObject {
    static let shared = OMPUsageService()

    @Published private(set) var configured = false
    @Published private(set) var checking = false
    @Published private(set) var failure: OMPUsageError?
    @Published private(set) var readings: [OMPUsageReading] = []

    private static let refreshInterval: TimeInterval = 5 * 60
    private static let renewedInterval: TimeInterval = 60
    private static let retryInterval: TimeInterval = 5 * 60
    private static let settledRetry: TimeInterval = 30 * 60

    private let queue = DispatchQueue(label: "com.vorssaint.omp-limits", qos: .utility)
    private var timer: Timer?
    private var cancellation: BoundedProcessCancellation?
    private var request = 0
    private var attempted = Date.distantPast
    private var visible = false

    private init() {
        configured = OMPCLI.executable() != nil
    }

    var isEnabled: Bool {
        configured && NotchAgentSupport.isEnabled() && NotchAgentSupport.providers().contains(.omp)
    }

    func synchronize() {
        let previous = configured
        configured = OMPCLI.executable() != nil
        if previous != configured {
            cancel()
            readings = []
            failure = nil
            AgentUsageService.shared.clearOMPAccounts()
        }
        guard isEnabled else {
            cancel()
            failure = configured ? nil : .missing
            readings = []
            AgentUsageService.shared.clearOMPAccounts()
            syncTimer()
            return
        }
        syncTimer()
        if visible { refresh() }
    }

    func pageDidAppear(preview: Bool = false) {
        if !preview { visible = true }
        synchronize()
        syncTimer()
        if !preview { refresh() }
    }

    func pageDidDisappear() {
        visible = false
        syncTimer()
    }

    func pause() {
        visible = false
        cancel()
        syncTimer()
    }

    func refresh(force: Bool = false, now: Date = Date()) {
        guard isEnabled, !checking, force || NotchAgentSupport.limitsInUse(pageShown: visible) else { return }
        if !force {
            let renewed = readings.contains { reading in
                reading.limits.windows.contains {
                    $0.resetsAt.map { $0 > reading.limits.observedAt && $0 <= now } ?? false
                }
            }
            let wait: TimeInterval
            switch failure {
            case nil: wait = renewed ? Self.renewedInterval : Self.refreshInterval
            case .unavailable?, .cancelled?: wait = Self.retryInterval
            case .missing?, .invalidResponse?: wait = Self.settledRetry
            }
            guard now.timeIntervalSince(attempted) >= wait else { return }
        }
        attempted = now
        guard let executable = OMPCLI.executable() else {
            configured = false
            failure = .missing
            return
        }
        start(executable)
    }

    private func start(_ executable: URL) {
        checking = true
        failure = nil
        request += 1
        let request = request
        let cancellation = BoundedProcessCancellation()
        self.cancellation = cancellation
        queue.async { [weak self] in
            let result = OMPUsageClient.fetch(executable: executable, cancellation: cancellation)
            DispatchQueue.main.async {
                guard let self, self.request == request else { return }
                self.cancellation = nil
                self.checking = false
                switch result {
                case .success(let readings):
                    self.readings = readings
                    self.failure = nil
                    AgentUsageService.shared.noteOMPAccounts(readings)
                case .failure(.cancelled):
                    self.attempted = .distantPast
                case .failure(let failure):
                    self.failure = failure
                }
            }
        }
    }

    private func cancel() {
        request += 1
        cancellation?.cancel()
        cancellation = nil
        checking = false
        attempted = .distantPast
    }

    private func syncTimer() {
        guard visible, isEnabled else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
