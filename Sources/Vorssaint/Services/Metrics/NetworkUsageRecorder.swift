// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Darwin
import Foundation

/// Records daily network usage in the background, independent of whether the
/// panel is open, and keeps it in `network-usage.json` inside the app's private
/// Application Support container.
///
/// One cheap counter read a minute. Ledger state is only touched on `queue`;
/// the published copy is for the UI on the main thread.
final class NetworkUsageRecorder: ObservableObject {
    static let shared = NetworkUsageRecorder()

    @Published private(set) var ledger = NetworkUsageLedger()

    private let queue = DispatchQueue(label: "com.vorssaint.utils.network-usage", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var state = NetworkUsageLedger()
    private var loaded = false
    private var dirty = false
    private var lastSave = Date.distantPast

    private static let interval: TimeInterval = 60
    private static let saveInterval: TimeInterval = 300

    private static var fileURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("network-usage.json")
    }

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            loadIfNeeded()
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + 2, repeating: Self.interval, leeway: .seconds(10))
            source.setEventHandler { [weak self] in self?.tick() }
            timer = source
            source.resume()
        }
    }

    /// Saves what is pending. Synchronous so it completes before the app quits.
    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
            tick()
            save(force: true)
        }
    }

    /// Reads the counters now, so an opened panel shows up-to-date numbers.
    func refresh() {
        queue.async { [self] in
            guard timer != nil else { return }
            tick()
        }
    }

    func reset() {
        queue.async { [self] in
            state.resetUsage()
            dirty = true
            save(force: true)
            publish()
        }
    }

    private func tick() {
        loadIfNeeded()
        guard AppFeature.monitorNetwork.isAvailable,
              let counters = NetworkSampler.readCounters() else { return }
        let now = Date()
        state.record(received: counters.received, sent: counters.sent,
                     interfaces: counters.interfaces, bootTime: Self.bootTime(),
                     day: NetworkUsageLedger.dayKey(now))
        state.prune(today: now)
        dirty = true
        save(force: false)
        publish()
    }

    private func publish() {
        let snapshot = state
        DispatchQueue.main.async { self.ledger = snapshot }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let url = Self.fileURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(NetworkUsageLedger.self, from: data) {
            state = decoded
        }
        publish()
    }

    private func save(force: Bool) {
        guard dirty, force || Date().timeIntervalSince(lastSave) >= Self.saveInterval,
              let url = Self.fileURL,
              PrivateFileStore.createDirectory(at: url.deletingLastPathComponent()),
              let data = try? JSONEncoder().encode(state),
              PrivateFileStore.write(data, to: url) else { return }
        dirty = false
        lastSave = Date()
    }

    /// When this boot started, from `kern.boottime`.
    private static func bootTime() -> TimeInterval? {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &time, &size, nil, 0) == 0, time.tv_sec > 0 else { return nil }
        return TimeInterval(time.tv_sec)
    }
}
