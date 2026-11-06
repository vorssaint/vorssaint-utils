// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Live herdr status: discovers the binary, runs `herdr agent list` off the
/// main thread through `BoundedProcessRunner`, decodes the JSON envelope and
/// polls while a surface is visible or a blocked agent wants attention. The
/// service never touches the UI thread except to publish; decode failures
/// keep the last good snapshot behind a stale flag.
final class HerdrStatusService: ObservableObject {
    static let shared = HerdrStatusService()

    /// Fast while a surface is open or an agent is blocked, slow otherwise.
    static let localTimeout: TimeInterval = 5
    static let remoteTimeout: TimeInterval = 8
    static let maxOutputBytes = 256 * 1024
    static let versionTimeout: TimeInterval = 2

    @Published private(set) var snapshot: HerdrStatusSnapshot?
    @Published private(set) var lastError: HerdrStatusError?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isStale = false

    private var resolvedBinary: URL?
    private var didProbe = false
    private var versionOK = false
    private var timer: DispatchSourceTimer?
    private var inFlight: BoundedProcessCancellation?
    private let queue = DispatchQueue(label: "HerdrStatusService.poll", qos: .utility)

    /// Nil until first discovery runs; a missing binary is availability the
    /// surface reads, not a failure the service logs.
    var isInstalled: Bool {
        if !didProbe { return HerdrDiscovery.resolve() != nil }
        return resolvedBinary != nil
    }

    var hasBlockedAgent: Bool {
        snapshot.map(HerdrStatusSupport.needsAttention) ?? false
    }

    func syncWithPreferences() {
        // On-demand and permission-free: nothing to start or stop until a
        // surface opens. A closed surface with no blocked agent drops the
        // timer so an invisible feature never wakes the CPU.
        if !AppFeature.herdrStatus.isAvailable {
            stopPolling()
            return
        }
        rearmTimer(visibleSurfaces: 0)
    }

    /// A surface opened or closed: recompute the cadence from visibility,
    /// blocked agents and the last failure.
    func surfaceDidChange(visibleSurfaces: Int) {
        rearmTimer(visibleSurfaces: visibleSurfaces)
    }

    func refresh(machine: String? = nil, visibleSurfaces: Int = 1) {
        guard AppFeature.herdrStatus.isAvailable else { return }
        if let machine, !HerdrStatusSupport.isValidMachineLabel(machine) { return }
        queue.async { [weak self] in
            self?.runRefresh(machine: machine, visibleSurfaces: visibleSurfaces)
        }
    }

    func stopPolling() {
        timer?.cancel()
        timer = nil
        inFlight?.cancel()
        inFlight = nil
        DispatchQueue.main.async { [weak self] in self?.isRefreshing = false }
    }

    // MARK: Refresh

    private func runRefresh(machine: String?, visibleSurfaces: Int) {
        if !didProbe {
            resolvedBinary = HerdrDiscovery.resolve()
            didProbe = true
            if let binary = resolvedBinary {
                versionOK = probeVersion(binary)
            }
        }
        guard let binary = resolvedBinary else {
            publish(error: .missingBinary, snapshot: nil)
            return
        }
        guard versionOK else {
            publish(error: .unsupportedVersion, snapshot: nil)
            return
        }
        DispatchQueue.main.async { [weak self] in self?.isRefreshing = true }
        let cancellation = BoundedProcessCancellation()
        inFlight?.cancel()
        inFlight = cancellation
        var args = machine.map { ["--machine", $0] } ?? []
        args += ["agent", "list"]
        let environment = HerdrDiscovery.environment(
            for: binary, searchPath: ProcessInfo.processInfo.environment["PATH"])
        let result = BoundedProcessRunner.run(
            binary.path, args,
            timeout: machine == nil ? Self.localTimeout : Self.remoteTimeout,
            maxOutputBytes: Self.maxOutputBytes,
            environment: environment, cancellation: cancellation)
        guard !cancellation.isCancelled else { return }
        if result.timedOut {
            publish(error: .timeout, snapshot: nil)
            rearmTimer(visibleSurfaces: visibleSurfaces)
            return
        }
        switch HerdrStatusSupport.decode(result.output) {
        case .success(let fresh):
            publish(error: nil, snapshot: fresh)
        case .failure(let error):
            if result.status != 0, error == .decode {
                let message = String(data: result.output.prefix(160), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                publish(error: .nonzeroExit(status: result.status, message: message), snapshot: nil)
            } else {
                publish(error: error, snapshot: nil)
            }
        }
        rearmTimer(visibleSurfaces: visibleSurfaces)
    }

    private func probeVersion(_ binary: URL) -> Bool {
        let environment = HerdrDiscovery.environment(
            for: binary, searchPath: ProcessInfo.processInfo.environment["PATH"])
        let result = BoundedProcessRunner.run(
            binary.path, ["--version"],
            timeout: Self.versionTimeout, maxOutputBytes: 64 * 1024,
            environment: environment)
        guard !result.timedOut, result.status == 0 else { return false }
        let text = String(data: result.output, encoding: .utf8)
        return HerdrDiscovery.isSupported(version: text)
    }

    private func publish(error: HerdrStatusError?, snapshot fresh: HerdrStatusSnapshot?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastError = error
            if let fresh {
                self.snapshot = fresh
                self.isStale = false
            } else if self.snapshot != nil, error != nil {
                self.isStale = true
            }
            self.isRefreshing = false
        }
    }

    private func rearmTimer(visibleSurfaces: Int) {
        let blocked = hasBlockedAgent
        let error = lastError
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            guard let interval = HerdrStatusSupport.cadence(
                visibleSurfaces: visibleSurfaces, hasBlockedAgent: blocked, lastError: error) else {
                return
            }
            let next = DispatchSource.makeTimerSource(queue: self.queue)
            next.schedule(deadline: .now() + interval, repeating: interval)
            next.setEventHandler { [weak self] in
                self?.runRefresh(machine: nil, visibleSurfaces: visibleSurfaces)
            }
            next.resume()
            self.timer = next
        }
    }
}
