// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// This Mac's rail left of the stage: CPU, GPU, Memory and Network as two
/// big rings each, the accessories' batteries and the Mac's own, as many as
/// are shown and where the layout puts them. It takes no input, and nothing
/// in it names a device or a network.
struct NotchLockScreenMacRail: View {
    let size: CGSize
    /// Each widget's frame from the rail's top left. The gauges take the
    /// rail's spare height, and one without a partner its whole width.
    let widgets: [NotchLockScreenPlacement]
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var keepAwake = KeepAwakeManager.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit = TemperatureUnit.celsius.rawValue
    /// Wi-Fi or Ethernet, looked up now and then rather than every frame.
    @State private var connection: NotchLockScreenSystemInfo.Connection?

    private typealias Layout = NotchLockScreenLayout
    private typealias Tile = NotchLockScreenTile

    var body: some View {
        let snapshot = monitor.snapshot
        let text = FeatureStrings.notchLockScreenWidgets(l10n.language)
        ZStack(alignment: .topLeading) {
            ForEach(widgets, id: \.widget) { placed in
                card(placed.widget, size: placed.frame.size, snapshot: snapshot, text: text)
                    .frame(width: placed.frame.width, height: placed.frame.height)
                    .padding(.leading, placed.frame.minX)
                    .padding(.top, placed.frame.minY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .environment(\.locale, l10n.language.formattingLocale())
        .task(id: widgets.contains { $0.widget == .network }) {
            // Only the Network card names the connection.
            guard widgets.contains(where: { $0.widget == .network }) else { return }
            while !Task.isCancelled {
                connection = NotchLockScreenSystemInfo.connection()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    @ViewBuilder private func card(_ widget: NotchLockScreenWidget, size: CGSize, snapshot: SystemSnapshot,
                                   text: NotchLockScreenWidgetStrings) -> some View {
        let wide = size.width > Layout.halfCard
        switch widget {
        case .cpu: cpu(snapshot, text: text, height: size.height, wide: wide)
        case .gpu: gpu(snapshot, text: text, height: size.height, wide: wide)
        case .memory: memory(snapshot, text: text, height: size.height, wide: wide)
        case .network: network(snapshot, text: text, height: size.height, wide: wide)
        case .accessories: NotchLockScreenAccessoriesCard(devices: snapshot.peripheralBatteries)
        case .battery:
            NotchLockScreenBatteryCard(power: snapshot.power, keepAwake: keepAwake.isActive, keepAwakeEnd: keepAwake.endDate)
        default: EmptyView()
        }
    }

    // MARK: Gauges

    private var unit: TemperatureUnit { TemperatureUnit(rawValue: temperatureUnit) ?? .celsius }

    private func use(_ fraction: Double?, text: NotchLockScreenWidgetStrings) -> NotchLockScreenGauge.Ring {
        guard let fraction else { return .missing(caption: text.inUse) }
        return NotchLockScreenGauge.Ring(value: MetricFormat.percent(fraction), caption: text.inUse,
                                         fill: fraction,
                                         tint: Tile.color(NotchLockScreenSupport.loadLevel(fraction)))
    }

    private func temperature(_ celsius: Double?, text: NotchLockScreenWidgetStrings) -> NotchLockScreenGauge.Ring {
        guard let celsius else { return .missing(caption: text.temp) }
        return NotchLockScreenGauge.Ring(value: MetricFormat.temperatureCompact(celsius, unit: unit), caption: text.temp,
                                         fill: NotchLockScreenSupport.temperatureFill(celsius),
                                         tint: Tile.color(NotchLockScreenSupport.temperatureLevel(celsius)))
    }

    /// The highest use the history holds.
    private func peak(_ history: [Double], text: NotchLockScreenWidgetStrings) -> String {
        history.max().map { String(format: text.peakFormat, MetricFormat.percent($0)) } ?? ""
    }

    private func cpu(_ snapshot: SystemSnapshot, text: NotchLockScreenWidgetStrings, height: CGFloat,
                     wide: Bool) -> some View {
        let fans = snapshot.fanSpeeds
        let footer = fans.isEmpty ? "" : String(format: text.fansFormat, String(
            format: FeatureStrings.fanControl(l10n.language).rpmFormat,
            Int((fans.reduce(0, +) / Double(fans.count)).rounded())))
        return NotchLockScreenGauge(
            title: l10n.s.cpuLabel, note: String(format: text.coresFormat, NotchLockScreenSystemInfo.cpuCores),
            rings: [use(snapshot.cpuUsage, text: text), temperature(snapshot.cpuTemperature, text: text)],
            footer: (footer, peak(snapshot.cpuHistory, text: text)), height: height, wide: wide)
    }

    private func gpu(_ snapshot: SystemSnapshot, text: NotchLockScreenWidgetStrings, height: CGFloat,
                     wide: Bool) -> some View {
        let seconds = snapshot.gpuHistory.count * monitor.intervalSeconds
        return NotchLockScreenGauge(
            title: l10n.s.gpuLabel, note: NotchLockScreenSystemInfo.gpuCores.map { String(format: text.coresFormat, $0) } ?? "",
            rings: [use(snapshot.gpuUsage, text: text), temperature(snapshot.gpuTemperature, text: text)],
            footer: (seconds >= 60 ? String(format: text.lastMinutesFormat, seconds / 60) : "",
                     peak(snapshot.gpuHistory, text: text)),
            height: height, wide: wide)
    }

    private func memory(_ snapshot: SystemSnapshot, text: NotchLockScreenWidgetStrings, height: CGFloat,
                        wide: Bool) -> some View {
        let used = snapshot.memoryUsed, total = snapshot.memoryTotal
        let fraction = used.flatMap { used in total.flatMap { $0 > 0 ? Double(used) / Double($0) : nil } }
        let pressure: NotchLockScreenGauge.Ring
        if let level = Self.level(snapshot.memoryPressure) {
            let (name, fill): (String, Double) = switch level {
            case .good: (text.pressureLow, 1.0 / 3)
            case .warning: (text.pressureMedium, 2.0 / 3)
            case .critical: (text.pressureHigh, 1)
            }
            pressure = NotchLockScreenGauge.Ring(value: name, caption: text.pressure, fill: fill, tint: Tile.color(level))
        } else {
            pressure = .missing(caption: text.pressure)
        }
        let note = used.flatMap { used in total.map { MetricFormat.bytes(used) + " " + String(
            format: FeatureStrings.notchLockScreen(l10n.language).ofTotal, MetricFormat.bytes($0)) } } ?? ""
        return NotchLockScreenGauge(
            title: l10n.s.memorySection, note: note, rings: [use(fraction, text: text), pressure],
            footer: (snapshot.memoryCompressed.map { String(format: text.compressedFormat, MetricFormat.bytes($0)) } ?? "",
                     snapshot.memorySwapUsed.map { String(format: text.swapFormat, MetricFormat.bytes($0)) } ?? ""),
            height: height, wide: wide)
    }

    /// Pressure as the kernel reports it: Low, Medium and High in green,
    /// yellow and red, as Activity Monitor draws it.
    static func level(_ pressure: MemoryPressure) -> NotchLockScreenLevel? {
        switch pressure {
        case .normal: return .good
        case .warning: return .warning
        case .critical: return .critical
        case .unknown: return nil
        }
    }

    /// Each direction's rate against the busiest the history holds, so the
    /// rings move with the traffic whatever the line's speed.
    private func network(_ snapshot: SystemSnapshot, text: NotchLockScreenWidgetStrings, height: CGFloat,
                         wide: Bool) -> some View {
        let peak = max(1, (snapshot.netDownHistory + snapshot.netUpHistory).max() ?? 1)
        func rate(_ bytes: Double?, caption: String, tint: Color) -> NotchLockScreenGauge.Ring {
            guard let bytes else { return .missing(caption: caption) }
            let reading = MetricFormat.networkRate(bytes)
            let parts = reading.split(separator: " ", maxSplits: 1).map(String.init)
            return NotchLockScreenGauge.Ring(value: parts.first ?? reading, unit: parts.count > 1 ? parts[1] : nil,
                                             caption: caption, fill: bytes / peak, tint: tint)
        }
        let total = snapshot.netTotalDown.flatMap { down in snapshot.netTotalUp.map { down &+ $0 } }
        let top = snapshot.netDownHistory.max()
        return NotchLockScreenGauge(
            title: l10n.s.networkSection,
            note: connection.map { $0 == .wifi ? text.wifi : text.ethernet } ?? "",
            rings: [rate(snapshot.netDownBytesPerSec, caption: text.down, tint: Tile.down),
                    rate(snapshot.netUpBytesPerSec, caption: text.up, tint: Tile.up)],
            footer: (total.map { String(format: text.totalFormat, MetricFormat.bytes($0)) } ?? "",
                     top.map { String(format: text.peakFormat, MetricFormat.networkRate($0)) } ?? ""),
            height: height, wide: wide)
    }
}

/// A gauge card: its name and a note, two big rings with their readings
/// inside, and a footer line.
struct NotchLockScreenGauge: View {
    struct Ring {
        var value: String
        var unit: String?
        var caption: String
        var fill: Double
        var tint: Color

        init(value: String, unit: String? = nil, caption: String, fill: Double, tint: Color) {
            self.value = value
            self.unit = unit
            self.caption = caption
            self.fill = fill
            self.tint = tint
        }

        /// A dash on the track until the monitor has a reading.
        static func missing(caption: String) -> Ring {
            Ring(value: "—", caption: caption, fill: 0, tint: .clear)
        }
    }

    let title: String
    let note: String
    let rings: [Ring]
    let footer: (String, String)
    let height: CGFloat
    /// The whole rail wide, with no gauge beside it: each ring centred in
    /// its half rather than pushed to the card's edges.
    var wide = false

    /// The rings take what the card's other lines leave, within reason.
    private var diameter: CGFloat { min(86, max(56, height - 98)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            NotchLockScreenSection(title: title) { Text(note) }
            HStack(spacing: wide ? 0 : nil) {
                ForEach(rings.indices, id: \.self) { index in
                    if wide {
                        ring(rings[index]).frame(maxWidth: .infinity)
                    } else {
                        if index > 0 { Spacer(minLength: 4) }
                        ring(rings[index])
                    }
                }
            }
            .frame(maxHeight: .infinity)
            HStack {
                Text(footer.0)
                Spacer(minLength: 4)
                Text(footer.1)
            }
            .font(.system(size: 10, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(NotchLockScreenTile.dim)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .lockScreenTile(horizontal: 17, vertical: 14)
        .accessibilityElement(children: .combine)
    }

    private func ring(_ ring: Ring) -> some View {
        let size = diameter * (ring.value.count > 4 ? 0.26 : 0.32)
        return VStack(spacing: 5) {
            NotchLockScreenRing(fill: ring.fill, tint: ring.tint, diameter: diameter) {
                VStack(spacing: 2) {
                    Text(ring.value)
                        .font(NotchLockScreenTile.rounded(size))
                        .tracking(-0.5)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let unit = ring.unit {
                        Text(unit)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(NotchLockScreenTile.dim)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, diameter * 0.1)
            }
            Text(ring.caption.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(NotchLockScreenTile.dim)
                .lineLimit(1)
        }
    }
}

/// Up to four accessories' batteries as rings, each by its kind alone,
/// since a Bluetooth name can carry a person's name.
private struct NotchLockScreenAccessoriesCard: View {
    let devices: [PeripheralBatteryDevice]
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let text = FeatureStrings.notchLockScreenWidgets(l10n.language)
        let shown = Array(PeripheralBatterySupport.sorted(devices).prefix(4))
        VStack(alignment: .leading, spacing: 8) {
            NotchLockScreenSection(title: FeatureStrings.notchLockScreen(l10n.language).accessories,
                                   symbol: "dot.radiowaves.left.and.right") {
                if !devices.isEmpty { Text(String(format: text.connectedFormat, devices.count)) }
            }
            if shown.isEmpty {
                Text(l10n.s.peripheralBatteryNoDevices)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchLockScreenTile.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        if index < shown.count {
                            accessory(shown[index], text: text)
                        } else {
                            Color.clear
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .lockScreenTile(horizontal: 20, vertical: 12)
        .accessibilityElement(children: .combine)
    }

    private func accessory(_ device: PeripheralBatteryDevice, text: NotchLockScreenWidgetStrings) -> some View {
        let level = NotchLockScreenSupport.chargeLevel(device.percent)
        return VStack(spacing: 5) {
            NotchLockScreenRing(fill: Double(device.percent) / 100, tint: NotchLockScreenTile.color(level),
                                diameter: 60, lineWidth: 5.5) {
                VStack(spacing: 0) {
                    Image(systemName: Self.symbol(device.kind))
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(device.percent)%")
                        .font(NotchLockScreenTile.rounded(14))
                        .monospacedDigit()
                        .foregroundStyle(level == .critical ? NotchLockScreenTile.light(.critical) : NotchLockScreenTile.text)
                }
            }
            Text(Self.name(device.kind, text: text).uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(NotchLockScreenTile.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    static func symbol(_ kind: PeripheralBatteryKind) -> String {
        switch kind {
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .audio: return "headphones"
        case .device: return "battery.100"
        }
    }

    static func name(_ kind: PeripheralBatteryKind, text: NotchLockScreenWidgetStrings) -> String {
        switch kind {
        case .keyboard: return text.keyboard
        case .mouse: return text.mouse
        case .trackpad: return text.trackpad
        case .audio: return text.headphones
        case .device: return text.device
        }
    }
}

/// The battery: its charge in a ring, the time left in big numbers or the
/// power going in, then what it draws, its health and Keep Awake. A Mac
/// without one shows what the whole system draws.
private struct NotchLockScreenBatteryCard: View {
    let power: PowerReading?
    let keepAwake: Bool
    let keepAwakeEnd: Date?
    @ObservedObject private var l10n = L10n.shared

    private typealias Tile = NotchLockScreenTile

    /// Keep Awake's own red, as its eye in the island.
    private static let awake = Color(red: 1, green: 0x8A / 255, blue: 0x80 / 255)

    var body: some View {
        let s = l10n.s
        let hasBattery = power?.hasBattery ?? PowerSampler.hasInternalBattery
        VStack(alignment: .leading, spacing: 8) {
            NotchLockScreenSection(title: hasBattery ? s.powerBattery : s.powerSection,
                                   symbol: hasBattery ? "battery.75percent" : "bolt") {
                if let badge = badge { NotchLockScreenBadge(text: badge.0, level: badge.1) }
            }
            HStack(spacing: 16) {
                if hasBattery {
                    let charge = power?.chargePercent
                    NotchLockScreenRing(fill: Double(charge ?? 0) / 100,
                                        tint: charge.map { Tile.color(NotchLockScreenSupport.chargeLevel($0)) } ?? .clear,
                                        diameter: 72, lineWidth: 7) {
                        Text(charge.map { "\($0)%" } ?? "—")
                            .font(Tile.rounded(21))
                            .monospacedDigit()
                    }
                }
                headline
                    .frame(width: hasBattery ? 112 : 180, alignment: .leading)
                Rectangle().fill(Tile.rule).frame(width: 1).frame(maxHeight: .infinity)
                rows
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .lockScreenTile(horizontal: 20, vertical: 12)
        .accessibilityElement(children: .combine)
    }

    private var level: NotchLockScreenLevel? { power?.chargePercent.map(NotchLockScreenSupport.chargeLevel) }

    private var badge: (String, NotchLockScreenLevel?)? {
        let s = l10n.s
        let island = FeatureStrings.notch(l10n.language)
        guard let power, power.hasBattery else { return power?.externalConnected == true ? (s.powerPluggedIn, nil) : nil }
        if power.isCharging { return (s.powerCharging, .good) }
        if !power.externalConnected {
            return (power.chargePercent ?? 100) < 20 ? (island.lowBattery, .critical) : (s.powerOnBattery, nil)
        }
        return (power.chargePercent == 100 ? island.charged : s.powerPluggedIn, nil)
    }

    /// The time left at this rate, or the power going in while it charges.
    private var headline: some View {
        let text = FeatureStrings.notchLockScreenWidgets(l10n.language)
        let big: String
        let caption: String
        if power?.hasBattery == false || (power == nil && !PowerSampler.hasInternalBattery) {
            big = power?.systemWatts.map(MetricFormat.watts) ?? "—"
            caption = l10n.s.powerSystem
        } else if power?.isCharging == true, let watts = power?.batteryWatts, watts > 0.5 {
            big = MetricFormat.watts(watts)
            caption = l10n.s.powerCharging.lowercased(with: l10n.language.formattingLocale())
        } else if let seconds = power?.timeRemainingSeconds, let time = BatteryTimeSupport.formatted(seconds: seconds) {
            big = time
            caption = text.leftAtRate
        } else if power?.externalConnected == true {
            // On power and not charging: held where it is, or full.
            big = power?.chargePercent == 100 ? FeatureStrings.notch(l10n.language).charged : l10n.s.powerPluggedIn
            caption = power?.adapterWatts.map(MetricFormat.watts) ?? ""
        } else {
            big = "—"
            caption = text.leftAtRate
        }
        return VStack(alignment: .leading, spacing: 1) {
            Text(big)
                .font(Tile.rounded(28))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Tile.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var rows: some View {
        let s = l10n.s
        let text = FeatureStrings.notchLockScreenWidgets(l10n.language)
        return VStack(spacing: 5) {
            if power?.isCharging == true || (power?.hasBattery == false && power?.externalConnected == true),
               let adapter = power?.adapterWatts {
                row(s.powerAdapter, MetricFormat.watts(adapter) + (power?.adapterMaxWatts.map {
                    " " + String(format: FeatureStrings.notchLockScreen(l10n.language).ofTotal, MetricFormat.watts($0))
                } ?? ""), tint: power?.hasBattery == true ? Tile.light(.good) : Tile.text)
            } else if power?.hasBattery != false,
                      let watts = power?.systemWatts ?? power?.batteryWatts.map(abs) {
                row(text.using, MetricFormat.watts(watts), tint: level == .critical ? Tile.light(.critical) : Tile.text)
            }
            if let health = power?.healthPercent {
                row(s.powerHealth, "\(Int(health.rounded()))%"
                    + (power?.cycleCount.map { " · " + String(format: text.cyclesFormat, $0) } ?? ""), tint: Tile.text)
            } else if let cycles = power?.cycleCount {
                row(s.powerCycles, "\(cycles)", tint: Tile.text)
            }
            if keepAwake {
                row(text.awakeUntil, keepAwakeEnd.map { $0.formatted(.dateTime.hour().minute()) } ?? "∞", tint: Self.awake)
            }
        }
    }

    private func row(_ name: String, _ value: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(name).foregroundStyle(Tile.dim)
            Spacer(minLength: 4)
            Text(value).foregroundStyle(tint)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}
