// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The battery charge limit card on the Energy page: the same rounded card
/// and icon rows as the pages around it. The enforcing loop lives in the root
/// daemon; the card only transfers state and shows what the daemon answers.
struct BatteryLimitCard: View {
    var body: some View {
        SettingsCard {
            BatteryChargeLimitContent(style: .settings)
        }
    }
}

/// The interactive body, shared by the Settings card and the menu panel
/// section. Both draw the same state and call the same actions; only the
/// layout differs, so each surface keeps the look of its neighbours.
struct BatteryChargeLimitContent: View {
    enum Style {
        case settings
        case panel
    }

    let style: Style
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var battery = BatteryControlService.shared
    @State private var upper = BatteryControlCore.defaultUpper
    @State private var lowerDelta = BatteryControlCore.defaultLowerDelta
    @State private var enabled = false
    @State private var discharge = false
    @State private var loadedFromStorage = false

    private var strings: BatteryControlFeatureStrings {
        BatteryControlFeatureStrings.batteryControl(l10n.language)
    }

    var body: some View {
        Group {
            switch style {
            case .settings: settingsLayout
            case .panel: panelLayout
            }
        }
        .onAppear {
            if !loadedFromStorage {
                let stored = battery.storedConfiguration
                upper = stored.upper
                lowerDelta = stored.lowerDelta
                enabled = stored.enabled
                discharge = stored.discharge
                loadedFromStorage = true
            }
            battery.setObserved(true)
        }
        .onDisappear { battery.setObserved(false) }
    }

    // MARK: State

    private var current: BatteryLimitState {
        BatteryLimitState(enabled: enabled, upper: upper, lowerDelta: lowerDelta,
                          discharge: discharge)
    }

    /// The level charging resumes at, as the daemon will hold it.
    private var resume: Int { current.lower }

    /// The resume slider spans from the deepest band the daemon accepts up to
    /// the limit itself, so it grows the same way the limit slider does.
    private var resumeRange: ClosedRange<Double> {
        let lowest = max(BatteryControlCore.minimumLower,
                         upper - BatteryControlCore.maximumLowerDelta)
        return Double(lowest)...Double(max(lowest + 1, upper))
    }

    private var resumeAdjustable: Bool { upper > BatteryControlCore.minimumLower }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { enabled }, set: { newValue in
            enabled = newValue
            apply()
        })
    }

    private var upperBinding: Binding<Double> {
        Binding(get: { Double(upper) }, set: { newValue in
            let newUpper = Int(newValue.rounded())
            guard newUpper != upper else { return }
            upper = newUpper
            apply()
        })
    }

    private var resumeBinding: Binding<Double> {
        Binding(get: { Double(resume) }, set: { newValue in
            let newDelta = min(BatteryControlCore.maximumLowerDelta,
                               max(0, upper - Int(newValue.rounded())))
            guard newDelta != lowerDelta else { return }
            lowerDelta = newDelta
            apply()
        })
    }

    private var dischargeAvailable: Bool {
        !battery.hasLiveSnapshot || battery.snapshot.adapterKeyPresent
    }

    private var dischargeBinding: Binding<Bool> {
        Binding(get: { discharge && dischargeAvailable }, set: { newValue in
            discharge = newValue
            apply()
        })
    }

    private func apply() {
        battery.apply(current)
    }

    // MARK: Settings layout

    private var settingsLayout: some View {
        VStack(alignment: .leading, spacing: 13) {
            SettingsRow(symbol: "battery.75percent", title: strings.title,
                        caption: strings.safetyCaption) {
                Toggle(strings.engage, isOn: enabledBinding).labelsHidden()
            }
            if battery.accessState == .unavailable {
                Text(strings.helperUnavailable)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if battery.accessState != .enabled {
                Button(strings.approve) { battery.authorize() }
                    .buttonStyle(.borderedProminent)
                    .disabled(battery.isWorking)
            } else {
                Divider()
                SettingsRow(symbol: "target", title: strings.limitLabel) {
                    settingsSlider(upperBinding,
                                   in: Double(BatteryControlCore.minimumUpper)
                                       ... Double(BatteryControlCore.maximumUpper),
                                   value: "\(upper)%", label: strings.limitLabel)
                }
                SettingsRow(symbol: "arrow.counterclockwise", title: strings.hysteresisLabel) {
                    settingsSlider(resumeBinding, in: resumeRange,
                                   value: "\(resume)%", label: strings.hysteresisLabel,
                                   disabled: !resumeAdjustable)
                }
                SettingsRow(symbol: "arrow.down.circle", title: strings.dischargeLabel,
                            caption: dischargeAvailable ? strings.dischargeNote
                                                        : strings.dischargeUnavailable) {
                    Toggle(strings.dischargeLabel, isOn: dischargeBinding)
                        .labelsHidden()
                        .disabled(!enabled || !dischargeAvailable)
                }
                Divider()
                SettingsRow(symbol: statusIcon, title: statusText, caption: statusNote) {
                    EmptyView()
                }
            }
        }
        .toggleStyle(.switch)
    }

    /// The slider and its value, the way the other Settings sliders draw them.
    private func settingsSlider(_ binding: Binding<Double>, in range: ClosedRange<Double>,
                                value: String, label: String,
                                disabled: Bool = false) -> some View {
        HStack(spacing: 8) {
            Slider(value: binding, in: range, step: 1)
                .frame(width: 140)
                .disabled(!enabled || disabled)
                .accessibilityLabel(label)
                .accessibilityValue(value)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    // MARK: Panel layout

    private var panelLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(enabled ? Color.green : Color.secondary)
                    .frame(width: 24)
                Text(statusText)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Toggle(strings.engage, isOn: enabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            if battery.accessState == .unavailable {
                Text(strings.helperUnavailable)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if battery.accessState != .enabled {
                Text(strings.safetyCaption)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(strings.approve) { battery.authorize() }
                    .controlSize(.small)
                    .disabled(battery.isWorking)
            } else {
                panelSlider(strings.limitLabel, symbol: "target", binding: upperBinding,
                            in: Double(BatteryControlCore.minimumUpper)
                                ... Double(BatteryControlCore.maximumUpper),
                            value: "\(upper)%")
                panelSlider(strings.hysteresisLabel, symbol: "arrow.counterclockwise",
                            binding: resumeBinding, in: resumeRange, value: "\(resume)%",
                            disabled: !resumeAdjustable)
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(strings.dischargeLabel, isOn: dischargeBinding)
                        .font(.system(size: 10.5, weight: .medium))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .disabled(!enabled || !dischargeAvailable)
                    Text(dischargeAvailable ? strings.dischargeNote : strings.dischargeUnavailable)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let statusNote {
                    Text(statusNote)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Same row the brightness section draws: icon, label and value above a
    /// small slider.
    private func panelSlider(_ title: String, symbol: String, binding: Binding<Double>,
                             in range: ClosedRange<Double>, value: String,
                             disabled: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(value)
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: binding, in: range, step: 1)
                .controlSize(.small)
                .disabled(!enabled || disabled)
                .accessibilityLabel(title)
                .accessibilityValue(value)
        }
    }

    // MARK: Status

    private var statusIcon: String {
        if !enabled { return "battery.75percent" }
        return battery.snapshot.isCharging ? "battery.bolt" : "battery.100percent"
    }

    private var statusText: String {
        let snapshot = battery.snapshot
        // Wall power cut by cycle mode: the Mac is draining while plugged in.
        if enabled, snapshot.adapterConnected == false {
            return strings.phaseDischarging
        }
        if let percentage = snapshot.percentage, enabled,
           percentage >= snapshot.limits.upper {
            return String(format: strings.statusHeldFormat, percentage)
        }
        return enabled ? strings.statusIdle : strings.statusOff
    }

    /// Only a problem is worth a line: a Mac that cannot control charging, or
    /// a helper that did not answer.
    private var statusNote: String? {
        if battery.hasLiveSnapshot {
            return battery.snapshot.backend == .unsupported ? strings.unsupported : nil
        }
        return battery.error == .helperUnavailable ? strings.helperUnavailable : nil
    }
}
