// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation
import GameController

enum ControllerFeature: CaseIterable {
    case haptics, lightBar, motion, adaptiveTriggers, touchpad
}

struct ControllerInfo: Identifiable, Equatable {
    let id: String
    var name: String
    var category: String?
    var batteryLevel: Double?
    var chargeState: ControllerChargeState
    var chargeEstimate: TimeInterval?
    var connectedAt: Date
    /// True when the controller was already connected as Vorssaint started, so
    /// the time since `connectedAt` is a minimum.
    var connectionIsLowerBound: Bool
    var transport: String?
    var firmware: String?
    var features: [ControllerFeature]
}

/// Watches the game controllers macOS has connected. It only listens while
/// the feature is installed, and only polls while a controller is connected.
final class GameControllerService: ObservableObject {
    static let shared = GameControllerService()

    @Published private(set) var controllers: [ControllerInfo] = []

    private struct Tracked {
        let controller: GCController
        let connectedAt: Date
        let connectionIsLowerBound: Bool
        var history = ControllerChargeHistory()
        var hardware: ControllerHardwareEntry?
        var firmware: String?
    }

    private static let pollInterval: TimeInterval = 30
    private var tracked: [ObjectIdentifier: Tracked] = [:]
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private let firmwareQueue = DispatchQueue(label: "com.vorssaint.utils.controller-firmware", qos: .utility)

    var isAvailable: Bool { AppFeature.gameController.isAvailable }

    func syncWithPreferences() {
        if isAvailable { start() } else { stop() }
    }

    /// Re-reads every battery now, for a panel that has just opened.
    func refresh() {
        guard isAvailable else { return }
        rebuild()
    }

    private func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
                guard let controller = note.object as? GCController else { return }
                self?.add(controller, alreadyConnected: false)
            },
            center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
                guard let controller = note.object as? GCController else { return }
                self?.remove(controller)
            },
        ]
        GCController.controllers().forEach { add($0, alreadyConnected: true) }
    }

    private func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        timer?.invalidate()
        timer = nil
        tracked = [:]
        controllers = []
    }

    private func add(_ controller: GCController, alreadyConnected: Bool) {
        let key = ObjectIdentifier(controller)
        guard tracked[key] == nil else { return }
        tracked[key] = Tracked(controller: controller, connectedAt: Date(),
                               connectionIsLowerBound: alreadyConnected)
        attachHardware(to: key)
        updatePolling()
        rebuild()
    }

    private func remove(_ controller: GCController) {
        tracked[ObjectIdentifier(controller)] = nil
        updatePolling()
        rebuild()
    }

    private func updatePolling() {
        guard !tracked.isEmpty else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in self?.rebuild() }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Pairs the framework's controller with its IORegistry entry by name and
    /// reads the firmware of a DualSense once, off the main thread.
    private func attachHardware(to key: ObjectIdentifier) {
        guard let item = tracked[key] else { return }
        let name = item.controller.vendorName
        let claimed = Set(tracked.values.compactMap { $0.hardware?.registryID })
        let candidates = GameControllerHardware.attached().filter { !claimed.contains($0.registryID) }
        guard let entry = candidates.first(where: { $0.name == name })
                ?? (candidates.count == 1 && controllersWithoutHardware() == 1 ? candidates.first : nil)
        else { return }
        tracked[key]?.hardware = entry
        guard GameControllerSupport.isDualSense(vendorID: entry.vendorID, productID: entry.productID) else { return }
        firmwareQueue.async { [weak self] in
            let firmware = GameControllerHardware.readDualSenseFirmware(registryID: entry.registryID)
                .map(GameControllerSupport.firmwareText)
            DispatchQueue.main.async {
                guard let self, self.tracked[key] != nil else { return }
                self.tracked[key]?.firmware = firmware
                self.rebuild()
            }
        }
    }

    private func controllersWithoutHardware() -> Int {
        tracked.values.filter { $0.hardware == nil }.count
    }

    private func rebuild() {
        let now = ProcessInfo.processInfo.systemUptime
        for key in tracked.keys {
            guard let battery = tracked[key]?.controller.battery,
                  battery.batteryLevel.isFinite else { continue }
            tracked[key]?.history.record(level: Double(battery.batteryLevel),
                                         state: Self.chargeState(battery.batteryState), at: now)
        }
        controllers = tracked
            .map { Self.info(for: $0.key, $0.value) }
            .sorted { ($0.connectedAt, $0.id) < ($1.connectedAt, $1.id) }
    }

    private static func chargeState(_ state: GCDeviceBattery.State) -> ControllerChargeState {
        switch state {
        case .charging: return .charging
        case .discharging: return .discharging
        case .full: return .full
        case .unknown: return .unknown
        @unknown default: return .unknown
        }
    }

    private static func info(for key: ObjectIdentifier, _ item: Tracked) -> ControllerInfo {
        let controller = item.controller
        let level = controller.battery.map { Double($0.batteryLevel) }
        return ControllerInfo(
            id: "\(key.hashValue)",
            name: controller.vendorName ?? controller.productCategory,
            category: controller.productCategory,
            batteryLevel: level.flatMap { GameControllerSupport.percent($0) == nil ? nil : $0 },
            chargeState: controller.battery.map { chargeState($0.batteryState) } ?? .unknown,
            chargeEstimate: item.history.estimate,
            connectedAt: item.connectedAt,
            connectionIsLowerBound: item.connectionIsLowerBound,
            transport: item.hardware?.transport,
            firmware: item.firmware,
            features: features(of: controller))
    }

    private static func features(of controller: GCController) -> [ControllerFeature] {
        var found: [ControllerFeature] = []
        if controller.haptics != nil { found.append(.haptics) }
        if controller.light != nil { found.append(.lightBar) }
        if controller.motion != nil { found.append(.motion) }
        if controller.extendedGamepad is GCDualSenseGamepad { found.append(.adaptiveTriggers) }
        if controller.extendedGamepad is GCDualSenseGamepad || controller.extendedGamepad is GCDualShockGamepad {
            found.append(.touchpad)
        }
        return found
    }
}
