// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ChargeControlSection: View {
    let collapsible: Bool
    @ObservedObject private var service = ChargeControlService.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.chargeLimitEnabled) private var enabled = false
    @AppStorage(DefaultsKey.chargeLimitPercent) private var limit = ChargeLimitPolicy.defaultLimit
    @State private var energyRows: [ProcessUsage] = []
    @State private var energyExpanded = false
    @State private var energyLoading = false
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        let strings = ChargeControlStrings.current(l10n.language)
        PanelSection(.chargeControl, title: strings.title, collapsible: collapsible) {
            if enabled {
                VStack(alignment: .leading, spacing: 10) {
                    controls(strings)
                    if service.status == .approvalRequired || service.status == .helperUnavailable {
                        authorizationNotice(strings)
                    }
                    if service.status == .systemConflict {
                        conflictNotice(strings)
                    }
                    chargeBar
                    powerFlow
                    energyApps
                }
            } else {
                Toggle(strings.enable, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in service.syncWithPreferences() }
            }
        }
        .onAppear {
            service.syncWithPreferences()
            refreshEnergy(force: true)
        }
        .onReceive(refreshTimer) { _ in
            service.evaluate()
            refreshEnergy(force: false)
        }
    }

    private func conflictNotice(_ strings: ChargeControlStrings) -> some View {
        Button {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") else { return }
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(strings.status(.systemConflict))
                    .font(.system(size: 10.5, weight: .medium))
                Spacer(minLength: 4)
                Text(strings.resolveConflict)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 9)
            .frame(minHeight: 34)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func authorizationNotice(_ strings: ChargeControlStrings) -> some View {
        Button { service.authorize() } label: {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                Text(strings.status(service.status))
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text(strings.approveHelper)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 9)
            .frame(minHeight: 34)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func controls(_ strings: ChargeControlStrings) -> some View {
        HStack(spacing: 7) {
            Text(strings.limitValue(limit))
            .font(.system(size: 11, weight: .semibold))
            .frame(height: 27)

            Spacer(minLength: 0)
            actionButton(title: strings.discharge,
                         symbol: service.sessionAction == .dischargeToLimit ? "minus.circle.fill" : "minus.circle",
                         active: service.sessionAction == .dischargeToLimit,
                         enabled: service.sessionAction == .dischargeToLimit || service.canStartDischarge) {
                service.sessionAction == .dischargeToLimit
                    ? service.cancelDischarge() : service.startDischargeToLimit()
            }
            actionButton(title: strings.topUp,
                         symbol: service.sessionAction == .topUp ? "xmark.circle.fill" : "plus.circle",
                         active: service.sessionAction == .topUp,
                         enabled: service.sessionAction == .topUp || service.canStartTopUp) {
                service.sessionAction == .topUp ? service.cancelTopUp() : service.startTopUp()
            }
        }
    }

    private func actionButton(title: String, symbol: String, active: Bool, enabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title).lineLimit(1)
                Image(systemName: symbol)
            }
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 6)
            .frame(height: 27)
            .background(active ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private var chargeBar: some View {
        GeometryReader { geometry in
            let percent = CGFloat(service.percent ?? 0) / 100
            let target = CGFloat(limit) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(barColor).frame(width: geometry.size.width * percent)
                Rectangle().fill(Color.primary.opacity(0.55)).frame(width: 2, height: 25)
                    .offset(x: max(0, min(geometry.size.width - 2, geometry.size.width * target - 1)))
                Image(systemName: barSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
                    // The state belongs to the charged portion as a whole, not
                    // its moving edge, so keep it centered in the current fill.
                    .offset(x: max(6, min(geometry.size.width - 20,
                                          geometry.size.width * percent / 2 - 7)))
            }
        }
        .frame(height: 25)
        .accessibilityLabel(ChargeControlStrings.current(l10n.language)
            .batteryAccessibility(percent: service.percent ?? 0, limit: limit))
    }

    private var powerFlow: some View {
        let power = monitor.snapshot.power
        return HStack(spacing: 0) {
            Image(systemName: power?.externalConnected == true ? "powerplug.fill" : "powerplug")
                .frame(width: 48)
            Divider()
            VStack(spacing: 2) {
                Text(powerValue(power))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(powerCaption(power))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            Divider()
            Image(systemName: "laptopcomputer").frame(width: 48)
        }
        .frame(height: 62)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }

    private var energyApps: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                energyExpanded.toggle()
                if energyExpanded { refreshEnergy(force: true) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: energyExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                    Text(l10n.s.energyAppsTitle)
                        .font(.system(size: 10.5, weight: .semibold))
                    Spacer()
                    if let top = energyRows.first {
                        Text(top.name).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                    } else if energyLoading {
                        ProgressView().controlSize(.mini)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if energyExpanded {
                if energyRows.isEmpty, !energyLoading {
                    Text(l10n.s.energyAppsIdle).font(.system(size: 10)).foregroundStyle(.tertiary)
                } else {
                    ForEach(energyRows.prefix(5)) { row in
                        ProcessUsageRow(row: row, value: String(format: "%.1f%%", row.value),
                                        iconSize: 14, leadingPadding: 12)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private var barColor: Color {
        if service.status == .approvalRequired || service.status == .helperUnavailable
            || service.status == .controlFailed || service.status == .unsupportedHardware {
            return .gray
        }
        switch service.sessionAction {
        case .dischargeToLimit: return .orange
        case .topUp: return .green
        case .normal: return .accentColor
        }
    }

    private var barSymbol: String {
        switch service.status {
        case .approvalRequired, .helperUnavailable, .controlFailed, .unsupportedHardware:
            return "exclamationmark.triangle.fill"
        default: break
        }
        if service.sessionAction == .dischargeToLimit || service.status == .discharging {
            return "arrow.down"
        }
        switch service.status {
        case .paused: return "pause.fill"
        case .systemConflict: return "exclamationmark.triangle.fill"
        // Top Up is still a charging state even before IOKit refreshes.
        case .charging: return "bolt.fill"
        default: return service.sessionAction == .topUp ? "bolt.fill" : "battery.50percent"
        }
    }

    private func powerValue(_ power: PowerReading?) -> String {
        if let value = power?.systemWatts ?? power?.adapterWatts { return MetricFormat.watts(value) }
        if let value = power?.batteryWatts { return MetricFormat.watts(abs(value)) }
        return "—"
    }

    private func powerCaption(_ power: PowerReading?) -> String {
        guard let power else { return l10n.s.powerUnavailable }
        if service.status == .systemConflict {
            return ChargeControlStrings.current(l10n.language).status(.systemConflict)
        }
        if service.sessionAction == .dischargeToLimit || (power.batteryWatts ?? 0) < 0 {
            return l10n.s.powerOnBattery
        }
        if power.isCharging || service.sessionAction == .topUp { return l10n.s.powerCharging }
        return power.externalConnected ? l10n.s.powerPluggedIn : l10n.s.powerOnBattery
    }

    private func refreshEnergy(force: Bool) {
        if !force, let cached = ProcessUsageService.shared.cachedTop(.energy, limit: 5) {
            energyRows = cached
            return
        }
        guard !energyLoading else { return }
        energyLoading = energyRows.isEmpty
        DispatchQueue.global(qos: .utility).async {
            let rows = ProcessUsageService.shared.top(.energy, limit: 5)
            DispatchQueue.main.async {
                energyLoading = false
                energyRows = rows
            }
        }
    }
}
