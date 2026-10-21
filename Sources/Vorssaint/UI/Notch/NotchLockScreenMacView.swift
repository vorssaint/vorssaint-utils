// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import EventKit
import SwiftUI

/// The This Mac page left of the lock screen's player: the battery, four
/// system tiles with their temperatures, today's events, storage and the
/// accessories' batteries, on the AI page's cards. Read-only, never
/// scrolled, and nothing in it names a device, a disk or a network.
struct NotchLockScreenMacPage: View {
    let size: CGSize
    let hidesEventTitles: Bool
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var keepAwake = KeepAwakeManager.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit = TemperatureUnit.celsius.rawValue

    private typealias Layout = NotchLockScreenLayout

    var body: some View {
        let snapshot = monitor.snapshot
        // With the Calendar section on the card stays, saying so when the
        // app may not read calendars, rather than leaving a gap to explain.
        let showsCalendar = NotchCalendarSupport.isEnabled()
        let plan = Layout.macPlan(height: size.height, calendar: showsCalendar)
        let text = FeatureStrings.notchLockScreen(l10n.language)
        VStack(spacing: Layout.macSpacing) {
            NotchLockScreenPowerCard(power: snapshot.power, history: snapshot.systemPowerHistory,
                                     keepAwake: keepAwake.isActive, keepAwakeEnd: keepAwake.endDate)
                .frame(height: Layout.macBattery)
            HStack(spacing: Layout.macSpacing) {
                NotchLockScreenMetricTile(
                    title: l10n.s.cpuLabel, symbol: "cpu", tint: .cyan,
                    pill: snapshot.cpuTemperature.map(temperature), value: snapshot.cpuUsage.map(MetricFormat.percent),
                    caption: text.inUse, bars: snapshot.cpuHistory.map { [$0] }, ceiling: 1, tints: [.cyan]) {
                    fans(snapshot.fanSpeeds, text: text)
                }
                NotchLockScreenMetricTile(
                    title: l10n.s.gpuLabel, symbol: "square.stack.3d.up", tint: .purple,
                    pill: snapshot.gpuTemperature.map(temperature), value: snapshot.gpuUsage.map(MetricFormat.percent),
                    caption: text.inUse, bars: snapshot.gpuHistory.map { [$0] }, ceiling: 1, tints: [.purple]) {
                    EmptyView()
                }
            }
            .frame(height: plan.tile)
            HStack(spacing: Layout.macSpacing) {
                NotchLockScreenMemoryTile(snapshot: snapshot)
                network(snapshot)
            }
            .frame(height: plan.tile)
            if showsCalendar {
                NotchLockScreenEventsCard(events: calendar.events, hidesTitles: hidesEventTitles,
                                          access: permissions.calendarAccess)
                    .frame(height: plan.calendar)
            }
            if plan.storage {
                NotchLockScreenStorageCard(disk: snapshot.disk).frame(height: Layout.macStorage)
            }
            if plan.accessories {
                NotchLockScreenAccessoriesCard(devices: snapshot.peripheralBatteries).frame(height: Layout.macAccessories)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .environment(\.locale, l10n.language.formattingLocale())
    }

    private func temperature(_ celsius: Double) -> String {
        MetricFormat.temperatureCompact(celsius, unit: TemperatureUnit(rawValue: temperatureUnit) ?? .celsius)
    }

    @ViewBuilder private func fans(_ speeds: [Double], text: NotchLockScreenStrings) -> some View {
        if !speeds.isEmpty {
            let average = Int((speeds.reduce(0, +) / Double(speeds.count)).rounded())
            HStack(spacing: 4) {
                Image(systemName: "fan").font(.system(size: 8.5, weight: .semibold))
                Text(text.fans)
                Spacer(minLength: 4)
                Text(String(format: FeatureStrings.fanControl(l10n.language).rpmFormat, average)).monospacedDigit()
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private func network(_ snapshot: SystemSnapshot) -> some View {
        let down = snapshot.netDownHistory, up = snapshot.netUpHistory
        let count = min(down.count, up.count)
        let bars = (0..<count).map { [down[down.count - count + $0], up[up.count - count + $0]] }
        let ceiling = max(1, bars.map { $0.reduce(0, +) }.max() ?? 1)
        return NotchLockScreenMetricTile(
            title: l10n.s.networkSection, symbol: "arrow.up.arrow.down", tint: .green, pill: nil,
            value: snapshot.netDownBytesPerSec.map { MetricFormat.networkRate($0) },
            caption: l10n.s.networkDownload.lowercased(with: l10n.language.formattingLocale()),
            bars: bars, ceiling: ceiling, tints: [.green, .yellow]) {
            if let rate = snapshot.netUpBytesPerSec {
                HStack(spacing: 4) {
                    Circle().fill(.yellow).frame(width: 5, height: 5)
                    Text(l10n.s.networkUpload)
                    Spacer(minLength: 4)
                    Text(MetricFormat.networkRate(rate)).monospacedDigit()
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// A short reading for each card: a dash until the monitor has one.
private let notchLockScreenMissing = "—"

/// The battery, or on a Mac without one the power it draws, with Keep
/// Awake underneath.
private struct NotchLockScreenPowerCard: View {
    let power: PowerReading?
    let history: [Double]
    let keepAwake: Bool
    let keepAwakeEnd: Date?
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let s = l10n.s
        let island = FeatureStrings.notch(l10n.language)
        let charge = power?.chargePercent
        let hasBattery = power?.hasBattery ?? PowerSampler.hasInternalBattery
        let tint: Color = power?.isCharging == true ? .green : (charge ?? 100) <= 20 ? .red : .white
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 8) {
                NotchAgentCardHeader(title: hasBattery ? s.powerBattery : s.powerSection,
                                     symbol: hasBattery ? "battery.75percent" : "bolt", tint: tint) {
                    if let status = status(island: island) {
                        Text(status)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(tint.opacity(0.18), in: Capsule())
                            .foregroundStyle(tint == .white ? Color.white.opacity(0.85) : tint)
                    }
                }
                if hasBattery {
                    HStack(spacing: 16) {
                        ring(charge, tint: tint)
                        VStack(alignment: .leading, spacing: 3) {
                            headline
                            rows
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    desktop.frame(maxHeight: .infinity)
                }
                Divider().overlay(.white.opacity(0.1))
                HStack(spacing: 6) {
                    Image(systemName: keepAwake ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(keepAwake ? .cyan : .secondary)
                    Text(s.keepAwakeTitle)
                    Spacer(minLength: 4)
                    Group {
                        if keepAwake, let keepAwakeEnd {
                            Text(s.keepAwakeUntilLabel + " ")
                                + Text(keepAwakeEnd, format: .dateTime.hour().minute())
                        } else {
                            Text(keepAwake ? "∞" : notchLockScreenMissing)
                        }
                    }
                    .foregroundStyle(keepAwake ? .cyan : .secondary)
                    .monospacedDigit()
                }
                .font(.system(size: 10, weight: .semibold))
            }
        }
    }

    private func status(island: NotchStrings) -> String? {
        guard let power, power.hasBattery else { return power?.externalConnected == true ? l10n.s.powerPluggedIn : nil }
        if power.isCharging { return l10n.s.powerCharging }
        if !power.externalConnected { return (power.chargePercent ?? 100) <= 20 ? island.lowBattery : l10n.s.powerOnBattery }
        return power.chargePercent == 100 ? island.charged : l10n.s.powerPluggedIn
    }

    private func ring(_ charge: Int?, tint: Color) -> some View {
        let fraction = Double(charge ?? 0) / 100
        return ZStack {
            Circle().stroke(.white.opacity(0.13), lineWidth: 7)
            Circle().trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(charge.map { "\($0)%" } ?? notchLockScreenMissing)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
        }
        .frame(width: 72, height: 72)
        .accessibilityElement(children: .combine)
    }

    /// What the battery will do next: the time left on battery, or the power
    /// going in while it charges.
    @ViewBuilder private var headline: some View {
        let text = FeatureStrings.notchLockScreen(l10n.language)
        if let seconds = power?.timeRemainingSeconds, let time = BatteryTimeSupport.formatted(seconds: seconds) {
            (Text(time).font(.system(size: 17, weight: .medium))
             + Text(" " + text.remaining).font(.system(size: 9.5, weight: .medium)).foregroundColor(.secondary))
                .monospacedDigit()
        } else if let watts = power?.batteryWatts, power?.isCharging == true, watts > 0.5 {
            (Text("+" + MetricFormat.watts(watts)).font(.system(size: 17, weight: .medium))
             + Text(" " + l10n.s.powerCharging.lowercased(with: l10n.language.formattingLocale()))
                .font(.system(size: 9.5, weight: .medium)).foregroundColor(.secondary))
                .monospacedDigit()
        }
    }

    @ViewBuilder private var rows: some View {
        let s = l10n.s
        if let watts = power?.systemWatts { row(s.powerSystem, MetricFormat.watts(watts)) }
        if power?.externalConnected == true, let adapter = power?.adapterWatts {
            row(s.powerAdapter, MetricFormat.watts(adapter)
                + (power?.adapterMaxWatts.map { " · " + String(format: s.powerAdapterMaxFormat, MetricFormat.watts($0)) } ?? ""))
        } else if let battery = power?.batteryWatts {
            row(s.powerBattery, MetricFormat.watts(battery))
        }
        if let health = power?.healthPercent { row(s.powerHealth, "\(Int(health.rounded()))%") }
        if let cycles = power?.cycleCount { row(s.powerCycles, "\(cycles)") }
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(name).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).monospacedDigit()
        }
        .font(.system(size: 10, weight: .medium))
        .lineLimit(1)
    }

    private var desktop: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(power?.systemWatts.map(MetricFormat.watts) ?? notchLockScreenMissing)
                .font(.system(size: 22, weight: .medium))
                .monospacedDigit()
            NotchLockScreenBars(bars: history.map { [$0] }, ceiling: max(1, history.max() ?? 1), tints: [.green])
        }
    }
}

/// One system tile: its temperature in the corner, the reading, its recent
/// history as bars and a footer line.
private struct NotchLockScreenMetricTile<Footer: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    let pill: String?
    let value: String?
    let caption: String
    let bars: [[Double]]
    let ceiling: Double
    let tints: [Color]
    @ViewBuilder let footer: Footer

    var body: some View {
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: title, symbol: symbol, tint: tint) {
                    if let pill { NotchLockScreenPill(text: pill, tint: tint) }
                }
                NotchLockScreenReading(value: value, caption: caption)
                NotchLockScreenBars(bars: bars, ceiling: ceiling, tints: tints)
                footer
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct NotchLockScreenMemoryTile: View {
    let snapshot: SystemSnapshot
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let s = l10n.s
        let text = FeatureStrings.notchLockScreen(l10n.language)
        let total = Double(snapshot.memoryTotal ?? 0)
        let parts: [(Double, Color)] = [
            (Double(snapshot.memoryAppUsed ?? snapshot.memoryUsed ?? 0), .blue),
            (Double(snapshot.memoryCompressed ?? 0), .blue.opacity(0.55)),
            (Double(snapshot.memoryCached ?? 0), .white.opacity(0.35))
        ]
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: s.memorySection, symbol: "memorychip", tint: .blue) {
                    if let tint = pressureTint { NotchLockScreenPill(text: s.memoryPressure, tint: tint) }
                }
                NotchLockScreenReading(value: snapshot.memoryUsed.map(MetricFormat.bytes),
                                       caption: snapshot.memoryTotal.map { String(format: text.ofTotal, MetricFormat.bytes($0)) } ?? "")
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(parts.indices, id: \.self) { index in
                            Capsule().fill(parts[index].1)
                                .frame(width: total > 0 ? max(0, proxy.size.width * parts[index].0 / total - 2) : 0)
                        }
                        Capsule().fill(.white.opacity(0.13))
                    }
                }
                .frame(height: 6)
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    legend(s.memoryCompressed, snapshot.memoryCompressed, tint: .blue.opacity(0.55))
                    legend(s.memoryCachedFiles, snapshot.memoryCached, tint: .white.opacity(0.35))
                    legend(s.memorySwapUsed, snapshot.memorySwapUsed, tint: .clear)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Pressure as a color, the way Activity Monitor draws it.
    private var pressureTint: Color? {
        switch snapshot.memoryPressure {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .unknown: return nil
        }
    }

    private func legend(_ name: String, _ bytes: UInt64?, tint: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5).fill(tint).frame(width: 5, height: 5)
            Text(name).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(bytes.map(MetricFormat.bytes) ?? notchLockScreenMissing).monospacedDigit()
        }
        .font(.system(size: 9.5, weight: .medium))
        .lineLimit(1)
    }
}

/// Today from now on: the next event large, then the rest as lines.
private struct NotchLockScreenEventsCard: View {
    let events: [NotchCalendarEvent]
    let hidesTitles: Bool
    let access: EKAuthorizationStatus
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let text = FeatureStrings.notchCalendar(l10n.language)
        let locked = FeatureStrings.notchLockScreen(l10n.language)
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let today = NotchCalendarSupport.events(events, on: now).filter { !$0.allDay && $0.end > now }
            NotchAgentCardChrome {
                VStack(alignment: .leading, spacing: 8) {
                    NotchAgentCardHeader(title: text.today, symbol: "calendar", tint: .red) {
                        Text(now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    if access != .fullAccess {
                        message(access == .denied || access == .restricted ? text.denied : text.permission)
                    } else if let next = today.first {
                        nextEvent(next, now: now, text: text)
                        GeometryReader { proxy in
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(today.dropFirst().prefix(max(0, Int(proxy.size.height / 20)))) { event in
                                    line(event, untitled: text.untitled)
                                }
                            }
                        }
                    } else {
                        message(locked.nothingElse)
                    }
                }
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func title(_ event: NotchCalendarEvent, untitled: String) -> String {
        hidesTitles ? FeatureStrings.notchLockScreen(l10n.language).busy
            : NotchCalendarStrip.displayTitle(event, untitled: untitled)
    }

    private func nextEvent(_ event: NotchCalendarEvent, now: Date, text: NotchCalendarStrings) -> some View {
        let ongoing = event.start <= now
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(event.color.color).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(ongoing ? text.ongoing : text.next)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title(event, untitled: text.untitled))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text((ongoing ? event.end : event.start).formatted(.relative(presentation: .named)
                    .locale(l10n.language.formattingLocale())))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.cyan)
                Text(event.start, format: .dateTime.hour().minute()) + Text(" – ") + Text(event.end, format: .dateTime.hour().minute())
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func line(_ event: NotchCalendarEvent, untitled: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(event.color.color).frame(width: 5, height: 5)
            Text(event.start, format: .dateTime.hour().minute())
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 58, alignment: .leading)
            Text(title(event, untitled: untitled)).lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium))
        .frame(height: 20)
    }
}

/// The built-in disk: free space, what fills it and how the drive is. An
/// external drive is only counted, since its name could say whose it is.
private struct NotchLockScreenStorageCard: View {
    let disk: DiskReading?
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit = TemperatureUnit.celsius.rawValue

    var body: some View {
        let s = l10n.s
        let text = FeatureStrings.notchLockScreen(l10n.language)
        let devices = disk?.devices ?? []
        let builtIn = devices.first { $0.isInternal && $0.mountPath == "/" } ?? devices.first { $0.isInternal }
        let externals = devices.filter { !$0.isInternal }.count
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 8) {
                NotchAgentCardHeader(title: s.diskStorageSettings, symbol: "internaldrive", tint: .secondary) {
                    if let status = builtIn?.smart?.status, !status.isEmpty {
                        NotchLockScreenPill(text: status, tint: .green)
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        NotchLockScreenReading(value: builtIn.map { MetricFormat.diskBytes($0.freeBytes) },
                                               caption: builtIn.map { String(format: text.freeOf, MetricFormat.diskBytes($0.totalBytes)) } ?? "")
                        if let builtIn { usage(builtIn) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Divider().overlay(.white.opacity(0.12))
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                        GridRow {
                            detail(s.diskRead, builtIn?.readBytesPerSec.map(MetricFormat.bytesPerSec))
                            detail(s.diskWrite, builtIn?.writeBytesPerSec.map(MetricFormat.bytesPerSec))
                        }
                        GridRow {
                            detail(s.diskHealth, builtIn?.smart?.healthPercent.map { "\($0)%" })
                            detail(s.diskTemperature, builtIn?.smart?.temperatureCelsius.map {
                                MetricFormat.temperature($0, unit: TemperatureUnit(rawValue: temperatureUnit) ?? .celsius)
                            })
                        }
                        GridRow {
                            detail(s.diskTotalWritten, (builtIn?.smart?.totalWrittenBytes ?? builtIn?.totalWrittenBytes)
                                .map(MetricFormat.diskBytesPrecise))
                            detail(s.diskExternal, "\(externals)")
                        }
                    }
                    .frame(width: 170, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func usage(_ device: DiskDeviceReading) -> some View {
        let total = Double(max(1, device.totalBytes))
        let purgeable = Double(device.purgeableBytes ?? 0)
        let used = Double(device.usedBytes)
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Capsule().fill(.white.opacity(0.65)).frame(width: max(0, proxy.size.width * used / total - 2))
                    Capsule().fill(.white.opacity(0.3)).frame(width: max(0, proxy.size.width * purgeable / total - 2))
                    Capsule().fill(.white.opacity(0.13))
                }
            }
            .frame(height: 6)
            HStack(spacing: 8) {
                Text(MetricFormat.diskBytes(device.usedBytes) + " " + l10n.s.diskUsed)
                if let bytes = device.purgeableBytes, bytes > 0 {
                    Text(MetricFormat.diskBytes(bytes) + " " + l10n.s.diskPurgeable)
                }
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private func detail(_ name: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value ?? notchLockScreenMissing)
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
        }
        .lineLimit(1)
    }
}

/// Each accessory by its kind alone, since a Bluetooth name can carry a
/// person's name.
private struct NotchLockScreenAccessoriesCard: View {
    let devices: [PeripheralBatteryDevice]
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let shown = Array(PeripheralBatterySupport.sorted(devices).prefix(4))
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 8) {
                NotchAgentCardHeader(title: FeatureStrings.notchLockScreen(l10n.language).accessories,
                                     symbol: "dot.radiowaves.left.and.right", tint: .secondary)
                if shown.isEmpty {
                    Text(l10n.s.peripheralBatteryNoDevices)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: 8) {
                        ForEach(shown) { device in
                            let tint: Color = device.percent <= 20 ? .red : .white
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 5) {
                                    Image(systemName: Self.symbol(device.kind))
                                        .font(.system(size: 10, weight: .semibold))
                                    Spacer(minLength: 2)
                                    Text("\(device.percent)%")
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(tint)
                                }
                                NotchAgentMeter(value: Double(device.percent) / 100, tint: tint, height: 4)
                                    .frame(height: 4)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
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
}

private struct NotchLockScreenReading: View {
    let value: String?
    let caption: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value ?? notchLockScreenMissing)
                .font(.system(size: 20, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct NotchLockScreenPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }
}

/// Recent samples as bars, newest on the right; each bar stacks its parts
/// from the bottom in `tints` order.
private struct NotchLockScreenBars: View {
    let bars: [[Double]]
    let ceiling: Double
    let tints: [Color]
    static let count = 30

    var body: some View {
        let shown = Array(bars.suffix(Self.count))
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<Self.count, id: \.self) { index in
                    let offset = index - (Self.count - shown.count)
                    VStack(spacing: 1) {
                        Spacer(minLength: 0)
                        if offset >= 0 {
                            ForEach(Array(shown[offset].enumerated().reversed()), id: \.offset) { part in
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(tints[min(part.offset, tints.count - 1)])
                                    .frame(height: max(1, proxy.size.height * min(1, part.element / max(ceiling, .leastNonzeroMagnitude))))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}
