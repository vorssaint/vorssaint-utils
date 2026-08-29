// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import WidgetKit

/// Feeds the desktop widgets, and only while they exist.
///
/// The monitor's whole design is that nothing samples unless something on
/// screen needs it. Widgets are off screen, so the trigger is whether the user
/// has actually placed one: `WidgetCenter` reports the installed
/// configurations, and until one shows up this publisher keeps the monitor
/// exactly as idle as it is today. No setting to find, nothing to switch on —
/// dropping a widget on the desktop is the switch.
/// Main-thread only, like the monitor that drives it.
final class WidgetSnapshotPublisher {
    static let shared = WidgetSnapshotPublisher()

    /// True while at least one Vorssaint widget is placed. Read by the monitor
    /// when it builds its sampling plan.
    private(set) var widgetsInstalled = false

    /// Widget timelines are budgeted by the system; reloading faster than this
    /// spends that budget without ever reaching the screen.
    private static let minimumPublishInterval: TimeInterval = 30

    private var lastPublishedAt: Date?
    private var lastPublished: WidgetSnapshot?

    private init() {}

    /// Starts listening for a widget announcing itself. A widget that is placed
    /// while the app is already running would otherwise sit on "open Vorssaint"
    /// until the next time the app happened to ask.
    func startObservingWidgetPresence() {
        DistributedNotificationCenter.default().addObserver(
            forName: WidgetPresenceSignal.name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.widgetsInstalled else { return }
            self.refreshInstalledWidgets()
        }
    }

    /// Re-checks whether any widget is placed. Cheap, but not free: call it on
    /// app launch and when the app comes back to the foreground, not per tick.
    func refreshInstalledWidgets(completion: (() -> Void)? = nil) {
        WidgetCenter.shared.getCurrentConfigurations { [weak self] result in
            let installed: Bool
            switch result {
            case .success(let configurations): installed = !configurations.isEmpty
            // The extension may be missing entirely (a build without it, or a
            // damaged bundle). Treating that as "no widgets" keeps the monitor
            // idle rather than sampling for a consumer that cannot exist.
            case .failure: installed = false
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.widgetsInstalled = installed
                SystemMonitor.shared.setWidgetsActive(installed)
                completion?()
            }
        }
    }

    /// Called from the monitor's publish step. Drops the sampled values into
    /// the shared file and nudges WidgetKit, throttled and change-gated.
    func publish(_ snapshot: SystemSnapshot) {
        guard widgetsInstalled else { return }
        let now = Date()
        if let last = lastPublishedAt, now.timeIntervalSince(last) < Self.minimumPublishInterval {
            return
        }

        let bootVolume = snapshot.disk?.devices.first { $0.mountPath == "/" }
        var next = WidgetSnapshot(capturedAt: now)
        next.cpuUsage = snapshot.cpuUsage
        next.gpuUsage = snapshot.gpuUsage
        next.memoryUsed = snapshot.memoryUsed
        next.memoryTotal = snapshot.memoryTotal
        next.memoryPressure = Self.pressureName(snapshot.memoryPressure)
        next.diskUsed = bootVolume?.usedBytes
        next.diskTotal = bootVolume?.totalBytes

        // `capturedAt` always differs, so compare the values that get drawn:
        // an unchanged reading must not spend a timeline reload.
        if var previous = lastPublished {
            previous.capturedAt = now
            if previous == next { return }
        }

        guard WidgetSnapshotStore.write(next) else { return }
        lastPublished = next
        lastPublishedAt = now
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func pressureName(_ pressure: MemoryPressure) -> String? {
        switch pressure {
        case .normal: return "normal"
        case .warning: return "warning"
        case .critical: return "critical"
        case .unknown: return nil
        }
    }
}
