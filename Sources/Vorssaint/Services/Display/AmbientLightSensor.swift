// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation
import IOKit

/// The ambient light sensor, read through the System Management Controller
/// (AppleSMC) the way the monitor already reads its temperatures. This is the
/// only genuinely new input source the brightness synchronizer adds: everything
/// else feeds off the built-in screen's own brightness, which macOS already
/// moves for both the ambient light and manual keys.
///
/// Most Macs expose the sensor as the six-byte `ALV0`/`ALV1` keys carrying a
/// `lux` reading. The older `LALS`/`RALS` float pair (left and right ambient
/// light, weighted toward whichever hand covers the keyboard) is read as a
/// fallback so Intel MacBook Pros and MacBook Airs are also covered. When no
/// key responds the sensor is simply absent and `isAvailable` is false; the
/// synchronizer then relies on the built-in screen alone, which is already the
/// common case for a laptop driving an external monitor.
final class AmbientLightSensor: ObservableObject {
    @Published private(set) var level: Double?
    /// True when the machine exposes an ambient light sensor this app can read.
    let isAvailable: Bool

    /// SMC key names this Mac reports for ambient light. `ALV0`/`ALV1` are
    /// `lux`; `LALS`/`RALS` are left/right floats on modern and older Macs.
    private let name: String?

    private let queue = DispatchQueue(label: "com.vorssaint.utils.ambient-sensor", qos: .utility)
    private let client: SMCClient
    private let floor: Double
    private let ceiling: Double
    private var timer: DispatchSourceTimer?

    init(client: SMCClient, floor: Double, ceiling: Double) {
        self.client = client
        self.floor = floor
        self.ceiling = ceiling
        self.name = Self.detectKey(using: client)
        self.isAvailable = name != nil
    }

    /// Locates the ambient light key this machine exposes, preferring the
    /// modern 6-byte `lux` one, then the legacy left/right float pair.
    private static func detectKey(using client: SMCClient) -> String? {
        if client.key(named: "ALV0")?.dataType == "lux " { return "ALV0" }
        if client.key(named: "ALV1")?.dataType == "lux " { return "ALV1" }
        if client.key(named: "LALS")?.dataType == "flt " { return "LALS" }
        if client.key(named: "RALS")?.dataType == "flt " { return "RALS" }
        return nil
    }

    func start() {
        guard isAvailable, timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: AmbientBrightnessSupport.refreshInterval)
        timer.setEventHandler { [weak self] in self?.sample() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Reads the sensor once and normalizes it onto the shared 0...1 scale.
    private func sample() {
        guard let name else { return }
        guard let key = client.key(named: name),
              let bytes = client.readBytes(key),
              let raww = SMCValueCodec.decode(bytes, type: key.dataType),
              raww.isFinite else {
            DispatchQueue.main.async { [weak self] in self?.level = nil }
            return
        }
        let value = AmbientBrightnessSupport.reference(
            forAmbientLevel: raww, floor: floor, ceiling: ceiling)
        DispatchQueue.main.async { [weak self] in self?.level = value }
    }
}