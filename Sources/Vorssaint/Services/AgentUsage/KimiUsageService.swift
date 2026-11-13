// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Kimi Code plan limits, checked only while the AI page uses them. The last
/// good reading survives a network failure; rejected credentials do not.
final class KimiUsageService: ObservableObject {
    static let shared = KimiUsageService()

    @Published private(set) var configured = false
    @Published private(set) var checking = false
    @Published private(set) var failure: KimiUsageError?
    @Published private(set) var reading: KimiUsageReading?

    private static let refreshInterval: TimeInterval = 5 * 60
    private static let renewedInterval: TimeInterval = 60
    private static let retryInterval: TimeInterval = 5 * 60
    private static let settledRetry: TimeInterval = 30 * 60

    private var timer: Timer?
    private var task: URLSessionTask?
    private var request = 0
    private var attempted = Date.distantPast
    private var visible = false

    private init() {
        configured = KimiCLIAuth.hasCredential(region: KimiRegion.stored())
    }

    var region: KimiRegion { KimiRegion.stored() }

    var isEnabled: Bool {
        configured && NotchAgentSupport.isEnabled() && NotchAgentSupport.providers().contains(.kimi)
    }

    private func authentication() -> KimiAuthentication? {
        KimiCLIAuth.authentication(region: region)
    }

    func synchronize() {
        let previous = configured
        configured = KimiCLIAuth.hasCredential(region: region)
        if previous != configured {
            cancel()
            reading = nil
            AgentUsageService.shared.clearKimiAccount()
        }
        guard isEnabled else {
            cancel()
            failure = nil
            reading = nil
            AgentUsageService.shared.clearKimiAccount()
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
        guard isEnabled, task == nil, force || NotchAgentSupport.limitsInUse(pageShown: visible) else { return }
        if !force {
            let renewed = reading.map { reading in
                reading.limits.windows.contains {
                    $0.resetsAt.map { $0 > reading.limits.observedAt && $0 <= now } ?? false
                }
            } ?? false
            let wait: TimeInterval
            switch failure {
            case nil: wait = renewed ? Self.renewedInterval : Self.refreshInterval
            case .unavailable?, .cancelled?: wait = Self.retryInterval
            case .expiredCredential?, .unauthorized?, .invalidResponse?: wait = Self.settledRetry
            }
            guard now.timeIntervalSince(attempted) >= wait else { return }
        }
        attempted = now
        guard let authentication = authentication() else {
            failure = .expiredCredential
            return
        }
        start(authentication)
    }

    private func start(_ authentication: KimiAuthentication) {
        checking = true
        request += 1
        let request = request
        let region = region
        task = KimiUsageClient.fetch(authentication: authentication, region: region) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.request == request else { return }
                self.task = nil
                self.checking = false
                switch result {
                case .success(let reading):
                    self.reading = reading
                    self.failure = nil
                    AgentUsageService.shared.noteKimiAccount(reading)
                case .failure(.cancelled):
                    self.attempted = .distantPast
                case .failure(.unauthorized):
                    self.reject(.unauthorized)
                case .failure(let failure):
                    self.failure = failure
                }
            }
        }
    }

    private func reject(_ failure: KimiUsageError) {
        self.failure = failure
        reading = nil
        AgentUsageService.shared.clearKimiAccount()
    }

    func regionDidChange() {
        cancel()
        failure = nil
        reading = nil
        AgentUsageService.shared.clearKimiAccount()
        synchronize()
        refresh(force: true)
    }

    func currentLimits(at now: Date) -> AgentLimits? {
        guard var limits = reading?.limits else { return nil }
        limits.windows.removeAll { $0.resetsAt.map { $0 <= now } ?? false }
        return limits.windows.isEmpty ? nil : limits
    }

    private func cancel() {
        request += 1
        task?.cancel()
        task = nil
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
