// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Darwin
import Foundation
import WidgetKit

/// Feeds the WidgetKit extension and, in the other direction, wakes the system
/// monitor only while a desktop widget is actually asking for updates.
///
/// Adding a widget is the only switch: there is no preference to turn on. A
/// widget's timeline provider writes a heartbeat each time the system asks it
/// for a timeline, and WidgetKit reports the widgets that are configured. The
/// app treats either signal as a reason to sample CPU, GPU, memory, disk and
/// network. With no widget on screen the timer stays off, exactly like the rest
/// of the monitor.
final class WidgetBridge {
    static let shared = WidgetBridge()

    private var cancellable: AnyCancellable?
    private var languageCancellable: AnyCancellable?
    private var timer: Timer?
    private var storageWatcher: DispatchSourceFileSystemObject?
    private var configuredKinds: Set<String> = []
    private var activeKinds: Set<VorssaintWidgetKind> = []
    private var lastConfigurationCheck: TimeInterval = 0
    private var lastPublish: TimeInterval = 0
    private var lastPublishedReadingKinds: Set<VorssaintWidgetKind> = []
    private var lastAddressRead: TimeInterval = 0
    private var cachedInterface: String?
    private var cachedAddress: String?

    private let publishInterval: TimeInterval = 5
    private let activityInterval: TimeInterval = 15

    private init() {}

    // MARK: - Lifecycle

    /// Called once at launch. The activity poll runs for the life of the app so
    /// a widget added later is noticed without relaunching; sampling itself
    /// only starts once a widget asks for a timeline.
    func start() {
        guard cancellable == nil else { return }
        WidgetSharedData.prepareStorage()
        WidgetSharedData.setLanguage(L10n.shared.language)
        languageCancellable = L10n.shared.$language
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { language in
                WidgetSharedData.setLanguage(language)
                // Every widget re-reads the shared language file, so all of
                // them need a fresh timeline when the app language changes.
                for kind in VorssaintWidgetKind.allCases {
                    WidgetCenter.shared.reloadTimelines(ofKind: kind.rawValue)
                }
            }
        cancellable = SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.publish(snapshot)
            }
        let timer = Timer(timeInterval: activityInterval, repeats: true) { [weak self] _ in
            self?.refreshActivity()
        }
        timer.tolerance = activityInterval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        startWatchingStorage()
        refreshActivity()
    }

    /// A widget that is added writes a heartbeat as soon as WidgetKit asks it
    /// for a timeline. Watching the shared folder turns that write into an
    /// immediate first publish instead of waiting for the next activity poll.
    private func startWatchingStorage() {
        guard storageWatcher == nil,
              let directory = WidgetSharedData.storageDirectory() else { return }
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write],
            queue: .main)
        source.setEventHandler { [weak self] in
            self?.refreshActivity()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        storageWatcher = source
    }

    // MARK: - Activity

    /// WidgetKit's configuration list is authoritative while it answers; the
    /// heartbeats keep working on builds where `getCurrentConfigurations`
    /// cannot see the local extension. Either one means a widget is on a
    /// desktop, which is what keeps the monitor sampling.
    private func refreshActivity() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastConfigurationCheck >= 45 {
            lastConfigurationCheck = now
            WidgetCenter.shared.getCurrentConfigurations { [weak self] result in
                guard let self else { return }
                DispatchQueue.main.async {
                    if case let .success(configurations) = result {
                        self.configuredKinds = Set(configurations.map(\.kind))
                    }
                    self.updateActiveKinds()
                }
            }
        }
        updateActiveKinds()
    }

    private func updateActiveKinds() {
        let heartbeats = VorssaintWidgetKind.allCases.filter {
            WidgetSharedData.isKindActive($0)
        }
        let configured = VorssaintWidgetKind.allCases.filter {
            configuredKinds.contains($0.rawValue)
        }
        let kinds = Set(heartbeats).union(configured)
        let kindsChanged = activeKinds != kinds
        activeKinds = kinds
        SystemMonitor.shared.setWidgetsActive(!kinds.isEmpty)
        if kindsChanged {
            publish(SystemMonitor.shared.snapshot, force: true)
        }
    }

    // MARK: - Publishing

    private func publish(_ snapshot: SystemSnapshot, force: Bool = false) {
        guard !activeKinds.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let widgetSnapshot = makeSnapshot(from: snapshot)
        // CPU shares and GPU usage appear on the first sample after the
        // monitor wakes, which can leave the first published snapshot short of
        // a reading. Publishing again as soon as the set grows fills the widget
        // in right away instead of waiting out the normal cadence.
        let readings = Set(VorssaintWidgetKind.readings.filter {
            widgetSnapshot.hasReading(for: $0)
        })
        let gainedReadings = readings != lastPublishedReadingKinds
        guard force || gainedReadings || now - lastPublish >= publishInterval else { return }
        lastPublish = now
        lastPublishedReadingKinds = readings

        WidgetSharedData.writeSnapshot(widgetSnapshot)
        for kind in activeKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind.rawValue)
        }
    }

    private func makeSnapshot(from snapshot: SystemSnapshot) -> WidgetSnapshot {
        WidgetSnapshot(
            capturedAt: Date(),
            cpu: cpuReading(snapshot),
            gpu: gpuReading(snapshot),
            memory: memoryReading(snapshot),
            disk: diskReading(snapshot),
            network: networkReading(snapshot)
        )
    }

    private func cpuReading(_ snapshot: SystemSnapshot) -> WidgetCPUReading? {
        guard let system = snapshot.cpuSystem,
              let user = snapshot.cpuUser,
              let idle = snapshot.cpuIdle else { return nil }
        return WidgetCPUReading(total: min(1, max(0, system + user)),
                                system: min(1, max(0, system)),
                                user: min(1, max(0, user)),
                                idle: min(1, max(0, idle)))
    }

    private func gpuReading(_ snapshot: SystemSnapshot) -> WidgetGPUReading? {
        guard let usage = snapshot.gpuUsage else { return nil }
        return WidgetGPUReading(usage: min(1, max(0, usage)),
                                renderer: snapshot.gpuRenderer.map { min(1, max(0, $0)) },
                                tiler: snapshot.gpuTiler.map { min(1, max(0, $0)) })
    }

    private func memoryReading(_ snapshot: SystemSnapshot) -> WidgetMemoryReading? {
        guard let used = snapshot.memoryUsed,
              let total = snapshot.memoryTotal,
              total > 0 else { return nil }
        return WidgetMemoryReading(used: used,
                                   total: total,
                                   app: snapshot.memoryAppUsed ?? used,
                                   pressureLevel: pressureLevel(snapshot.memoryPressure))
    }

    private func diskReading(_ snapshot: SystemSnapshot) -> WidgetDiskReading? {
        guard let device = rootDisk(in: snapshot.disk), device.totalBytes > 0 else {
            return nil
        }
        return WidgetDiskReading(used: min(device.usedBytes, device.totalBytes),
                                 free: device.freeBytes,
                                 total: device.totalBytes)
    }

    private func networkReading(_ snapshot: SystemSnapshot) -> WidgetNetworkReading? {
        guard snapshot.netDownBytesPerSec != nil || snapshot.netUpBytesPerSec != nil else {
            return nil
        }
        refreshAddressIfNeeded()
        return WidgetNetworkReading(
            downBytesPerSec: snapshot.netDownBytesPerSec ?? 0,
            upBytesPerSec: snapshot.netUpBytesPerSec ?? 0,
            isConnected: cachedAddress != nil,
            usesBits: UserDefaults.standard.string(forKey: DefaultsKey.networkSpeedUnit)
                == NetworkSpeedUnit.bits.rawValue,
            interfaceName: cachedInterface,
            localAddress: cachedAddress
        )
    }

    /// The root volume is what the Disk widget speaks for. A mounted external
    /// disk never displaces the startup disk.
    private func rootDisk(in reading: DiskReading?) -> DiskDeviceReading? {
        guard let devices = reading?.devices, !devices.isEmpty else { return nil }
        if let root = devices.first(where: { $0.mountPath == "/" }) { return root }
        return devices.first(where: \.isInternal) ?? devices.first
    }

    private func refreshAddressIfNeeded() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastAddressRead >= 30 else { return }
        lastAddressRead = now
        let addresses = NetworkAddressService.readLocalAddresses()
        guard let first = addresses.first else {
            cachedAddress = nil
            cachedInterface = nil
            return
        }
        if let opening = first.firstIndex(of: "("),
           let closing = first.lastIndex(of: ")"),
           opening < closing {
            cachedAddress = String(first[..<opening]).trimmingCharacters(in: .whitespaces)
            cachedInterface = String(first[first.index(after: opening)..<closing])
        } else {
            cachedAddress = first
            cachedInterface = nil
        }
    }

    private func pressureLevel(_ pressure: MemoryPressure) -> Int {
        switch pressure {
        case .normal: return 1
        case .warning: return 2
        case .critical: return 4
        case .unknown: return 0
        }
    }
}
