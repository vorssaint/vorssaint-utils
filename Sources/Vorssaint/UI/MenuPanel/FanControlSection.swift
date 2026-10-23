// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The pointing hand over a control that reacts to a click, which the panel's
/// native controls do not show on their own. Applied before `.disabled`, so a
/// control that cannot be used keeps the arrow.
struct PointingHandCursor: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside, isEnabled, !pushed {
                    NSCursor.pointingHand.push()
                    pushed = true
                } else if !inside, pushed {
                    release()
                }
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled, pushed { release() }
            }
            .onDisappear { if pushed { release() } }
    }

    private func release() {
        NSCursor.pop()
        pushed = false
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursor())
    }
}

struct FanControlSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = FanControlService.shared
    @AppStorage(DefaultsKey.fanControlMode) private var modeRaw = FanControlMode.system.rawValue
    @AppStorage(DefaultsKey.fanControlCoolingLevel) private var coolingLevel =
        FanControlPolicy.defaultCoolingLevel
    @AppStorage(DefaultsKey.fanControlCurves) private var curvesStorage =
        FanControlConfiguration.defaultCurvesStorage
    @AppStorage(DefaultsKey.fanControlResume) private var resume = false
    @AppStorage(DefaultsKey.fanControlAdaptiveSensitivity) private var adaptiveSensitivity =
        FanControlAdaptiveSettings.balanced.sensitivity.rawValue
    @AppStorage(DefaultsKey.fanControlAdaptiveSweetSpotLevel) private var adaptiveSweetSpotLevel =
        FanControlAdaptiveSettings.balanced.sweetSpotLevel
    @AppStorage(DefaultsKey.fanControlAdaptiveMaximumLevel) private var adaptiveMaximumLevel =
        FanControlAdaptiveSettings.balanced.maximumLevel
    @AppStorage(DefaultsKey.fanControlAdaptiveRampStartTemperature) private var adaptiveRampStartTemperature =
        FanControlAdaptiveSettings.balanced.rampStartTemperature
    @AppStorage(DefaultsKey.fanControlAdaptiveMaximumTemperature) private var adaptiveMaximumTemperature =
        FanControlAdaptiveSettings.balanced.maximumTemperature
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit =
        TemperatureUnit.celsius.rawValue
    var collapsible = true
    var fallbackFanSpeeds: [Double] = []

    private var strings: FanControlFeatureStrings {
        FeatureStrings.fanControl(l10n.language)
    }

    var body: some View {
        PanelSection(.fanControl, title: strings.title, collapsible: collapsible) {
            FanControlCardContent(strings: strings,
                                  betaLabel: l10n.s.betaBadge,
                                  snapshot: service.snapshot,
                                  history: service.history,
                                  fallbackFanSpeeds: fallbackFanSpeeds,
                                  accessState: service.accessState,
                                  error: service.error,
                                  isWorking: service.isWorking,
                                  mode: modeBinding,
                                  coolingLevel: $coolingLevel,
                                  curves: curvesBinding,
                                  resume: $resume,
                                  adaptiveSettings: adaptiveSettingsBinding,
                                  temperatureUnit: displayTemperatureUnit,
                                  authorize: service.authorize,
                                  applyConfiguration: service.applyConfiguration,
                                  stopCooling: service.returnToSystem)
                .panelCard()
                .onAppear { service.panelDidAppear() }
                .onDisappear { service.panelDidDisappear() }
                .onChange(of: resume) { _, _ in service.resumePreferenceDidChange() }
        }
    }

    private var modeBinding: Binding<FanControlMode> {
        Binding(
            get: { FanControlMode(rawValue: modeRaw) ?? .system },
            set: { modeRaw = $0.rawValue }
        )
    }

    private var curvesBinding: Binding<[FanControlCurve]> {
        Binding(
            get: {
                FanControlConfiguration.decodeCurves(curvesStorage)
                    ?? [FanControlConfiguration.defaultCurve]
            },
            set: { curves in
                if let encoded = FanControlConfiguration.encodeCurves(curves) {
                    curvesStorage = encoded
                }
            }
        )
    }

    private var adaptiveSettingsBinding: Binding<FanControlAdaptiveSettings> {
        Binding(
            get: {
                FanControlAdaptivePolicy.normalized(FanControlAdaptiveSettings(
                    sweetSpotLevel: adaptiveSweetSpotLevel,
                    maximumLevel: adaptiveMaximumLevel,
                    rampStartTemperature: adaptiveRampStartTemperature,
                    maximumTemperature: adaptiveMaximumTemperature,
                    sensitivity: FanControlAdaptiveSensitivity(rawValue: adaptiveSensitivity)
                        ?? .standard
                ))
            },
            set: { settings in
                guard FanControlAdaptivePolicy.validSettings(settings) else { return }
                adaptiveSweetSpotLevel = settings.sweetSpotLevel
                adaptiveMaximumLevel = settings.maximumLevel
                adaptiveRampStartTemperature = settings.rampStartTemperature
                adaptiveMaximumTemperature = settings.maximumTemperature
                adaptiveSensitivity = settings.sensitivity.rawValue
            }
        )
    }

    private var displayTemperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnit) ?? .celsius
    }
}

struct FanControlCardContent: View {
    let strings: FanControlFeatureStrings
    let betaLabel: String
    let snapshot: FanControlSnapshot
    let history: [FanControlHistorySample]
    let fallbackFanSpeeds: [Double]
    let accessState: FanControlService.AccessState
    let error: FanControlErrorCode?
    let isWorking: Bool
    @Binding var mode: FanControlMode
    @Binding var coolingLevel: Int
    @Binding var curves: [FanControlCurve]
    @Binding var resume: Bool
    @Binding var adaptiveSettings: FanControlAdaptiveSettings
    let temperatureUnit: TemperatureUnit
    let authorize: () -> Void
    let applyConfiguration: (FanControlConfiguration) -> Void
    let stopCooling: () -> Void
    @State private var showsAdaptiveAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusHeader

            if !fallbackFanSpeeds.isEmpty,
               snapshot.fans.isEmpty || error == .helperUnavailable {
                fallbackFanRows
            } else if !snapshot.fans.isEmpty {
                fanRows
            }

            if history.count >= 2 {
                adaptiveHistoryChart
            }

            if let message = stateMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(messageIsError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if canConfigure {
                modePicker
                switch mode {
                case .system:
                    EmptyView()
                case .manual:
                    manualControl
                case .curve:
                    FanControlCurveEditor(strings: strings,
                                          curves: $curves,
                                          temperatures: snapshot.temperatures ?? [],
                                          temperatureUnit: temperatureUnit,
                                          disabled: isWorking)
                        .help(strings.helpCurve)
                    if !curveCanRun {
                        Text(strings.curveUnavailable)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .adaptive:
                    adaptiveControl
                }
            }

            action

            if canConfigure, mode != .system {
                Toggle(strings.resumeAfterRestart, isOn: $resume)
                    .font(.system(size: 10.5, weight: .medium))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .pointingHandCursor()
                    .help(strings.helpResume)
            }

            if controlsCanAppear {
                Text(strings.safetyCaption)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.secondary.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var modePicker: some View {
        Picker(strings.mode, selection: $mode) {
            Text(strings.systemControl).tag(FanControlMode.system)
            Text(strings.manualControl).tag(FanControlMode.manual)
            Text(strings.customCurve).tag(FanControlMode.curve)
            Text(strings.adaptiveControl).tag(FanControlMode.adaptive)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .pointingHandCursor()
        .disabled(isWorking)
        .help(strings.helpMode)
    }

    private var manualControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(strings.coolingIntensity)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(selectedCoolingLevel)%")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
            }
            Slider(value: coolingLevelBinding,
                   in: Double(FanControlPolicy.minimumCoolingLevel)...Double(FanControlPolicy.maximumCoolingLevel),
                   step: Double(FanControlPolicy.coolingLevelStep))
                .controlSize(.small)
                .disabled(isWorking)
        }
        .help(strings.helpManual)
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot.isCooling ? "fanblades.fill" : "fanblades")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(snapshot.isCooling ? AnyShapeStyle(Color.cyan)
                                                     : AnyShapeStyle(Color.secondary))
                .symbolEffect(.variableColor.iterative, options: .repeating,
                              isActive: snapshot.isCooling)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(strings.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(betaLabel)
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                }
                HStack(spacing: 4) {
                    if snapshot.isCooling {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                    Text(statusText)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(snapshot.isCooling ? Color.cyan : Color.secondary)
                }
            }
            Spacer()
            if isWorking { ProgressView().controlSize(.small) }
        }
    }

    private var fanRows: some View {
        VStack(spacing: 5) {
            ForEach(snapshot.fans) { fan in
                HStack(spacing: 6) {
                    Text(String(format: strings.fanNameFormat, fan.index + 1))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(String(format: strings.currentRPMFormat,
                                    Int(fan.actualRPM.rounded())))
                            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        if fan.isManuallyControlled {
                            Text(String(format: strings.targetRPMFormat,
                                        Int(fan.targetRPM.rounded())))
                                .font(.system(size: 9.5).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 1)
    }

    private var fallbackFanRows: some View {
        VStack(spacing: 5) {
            ForEach(fallbackFanSpeeds.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    Text(String(format: strings.fanNameFormat, index + 1))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: strings.currentRPMFormat,
                                Int(fallbackFanSpeeds[index].rounded())))
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                }
            }
        }
        .padding(.vertical, 1)
    }

    private static let chartTemperatureFloor = 30.0

    private var adaptiveHistoryChart: some View {
        let floor = Self.chartTemperatureFloor
        let temperatures = history.map(\.temperature)
        let actualRPM = history.map(\.actualRPM)
        let targetRPM = history.map(\.targetRPM)
        let temperaturePeak = max(70, ceil((temperatures.max() ?? 70) / 10) * 10)
        let rpmPeak = max(2_500,
                          ceil(max(actualRPM.max() ?? 0, targetRPM.max() ?? 0) / 500) * 500)
        let latest = history[history.count - 1]
        let temperatureText = MetricFormat.temperature(latest.temperature, unit: temperatureUnit)
        let currentText = String(format: strings.currentRPMFormat,
                                 Int(latest.actualRPM.rounded()))
        let targetText = String(format: strings.targetRPMFormat,
                                Int(latest.targetRPM.rounded()))
        // The ramp thresholds of the running control, where the chart reaches them.
        let thresholds = (snapshot.configuration.map {
            [$0.adaptive.rampStartTemperature, $0.adaptive.maximumTemperature]
        } ?? []).map(Double.init).filter { $0 > floor && $0 < temperaturePeak }

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(temperatureText)
                    .foregroundStyle(.orange)
                Text(currentText)
                    .foregroundStyle(.cyan)
                Text(targetText)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            // One plot, each series on its own scale: the temperature from a
            // floor that leaves the working range its full height, the fan
            // speed from zero.
            ZStack {
                Sparkline(values: temperatures.map { max(0, $0 - floor) },
                          color: .orange,
                          maxValue: temperaturePeak - floor,
                          showsZeroBaseline: true)
                    .background {
                        GeometryReader { geometry in
                            Path { path in
                                for threshold in thresholds {
                                    let y = geometry.size.height
                                        * (1 - (threshold - floor) / (temperaturePeak - floor))
                                    path.move(to: CGPoint(x: 0, y: y))
                                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                                }
                            }
                            .stroke(Color.secondary.opacity(0.4),
                                    style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                Sparkline(values: targetRPM, color: .secondary, maxValue: rpmPeak,
                          fillOpacity: 0, lineWidth: 1)
                Sparkline(values: actualRPM, color: .cyan, maxValue: rpmPeak,
                          fillOpacity: 0)
            }
            .frame(height: 48)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(strings.adaptiveControl)
        .help(strings.helpChart)
        .accessibilityValue("\(temperatureText), \(currentText), \(targetText)")
    }

    private var adaptiveControl: some View {
        // Each stepper stops where the other value of its pair would no longer
        // leave the span a valid tuning needs.
        let policy = FanControlAdaptivePolicy.self
        let sweetSpotCeiling = adaptiveSettings.maximumLevel - policy.minimumLevelSpan
        let maximumLevelFloor = adaptiveSettings.sweetSpotLevel + policy.minimumLevelSpan
        let rampStartCeiling = adaptiveSettings.maximumTemperature - policy.minimumTemperatureSpan
        let maximumTemperatureFloor = adaptiveSettings.rampStartTemperature
            + policy.minimumTemperatureSpan
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(strings.adaptiveProfile)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker(strings.adaptiveProfile, selection: adaptiveProfileBinding) {
                    Text(strings.adaptiveProfileQuiet)
                        .tag(FanControlAdaptiveProfile?.some(.quiet))
                    Text(strings.adaptiveProfileBalanced)
                        .tag(FanControlAdaptiveProfile?.some(.balanced))
                    Text(strings.adaptiveProfilePerformance)
                        .tag(FanControlAdaptiveProfile?.some(.performance))
                    if FanControlAdaptiveProfile(matching: adaptiveSettings) == nil {
                        Text(strings.adaptiveProfileCustom)
                            .tag(FanControlAdaptiveProfile?.none)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
                .pointingHandCursor()
                .disabled(isWorking)
            }
            .help(strings.helpProfile)

            adaptiveAdvancedHeader

            if showsAdaptiveAdvanced {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(strings.adaptiveSensitivity)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Picker(strings.adaptiveSensitivity, selection: $adaptiveSettings.sensitivity) {
                            Text(strings.adaptiveSensitivityRelaxed).tag(FanControlAdaptiveSensitivity.relaxed)
                            Text(strings.adaptiveSensitivityStandard).tag(FanControlAdaptiveSensitivity.standard)
                            Text(strings.adaptiveSensitivityResponsive).tag(FanControlAdaptiveSensitivity.responsive)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.mini)
                        .fixedSize()
                        .pointingHandCursor()
                        .disabled(isWorking)
                    }
                    .help(strings.helpSensitivity)
                    adaptiveRow(strings.adaptiveSweetSpotLevel,
                                value: levelText(adaptiveSettings.sweetSpotLevel),
                                binding: $adaptiveSettings.sweetSpotLevel,
                                range: policy.sweetSpotLevelRange.lowerBound...sweetSpotCeiling,
                                step: policy.levelStep,
                                help: strings.helpSweetSpot)
                    adaptiveRow(strings.adaptiveMaximumLevel,
                                value: levelText(adaptiveSettings.maximumLevel),
                                binding: $adaptiveSettings.maximumLevel,
                                range: maximumLevelFloor...policy.maximumLevelRange.upperBound,
                                step: policy.levelStep,
                                help: strings.helpMaximum)
                    adaptiveRow(strings.adaptiveRampStartTemperature,
                                value: temperatureText(adaptiveSettings.rampStartTemperature),
                                binding: $adaptiveSettings.rampStartTemperature,
                                range: policy.minimumConfiguredTemperature...rampStartCeiling,
                                step: 1,
                                help: strings.helpRampStart)
                    adaptiveRow(strings.adaptiveMaximumTemperature,
                                value: temperatureText(adaptiveSettings.maximumTemperature),
                                binding: $adaptiveSettings.maximumTemperature,
                                range: maximumTemperatureFloor...policy.maximumConfiguredTemperature,
                                step: 1,
                                help: strings.helpMaximumTemperature)
                }
                .padding(.leading, 14)
            }
        }
    }

    /// The whole title toggles the settings, not just the disclosure arrow.
    private var adaptiveAdvancedHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { showsAdaptiveAdvanced.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .rotationEffect(.degrees(showsAdaptiveAdvanced ? 90 : 0))
                    .frame(width: 10)
                Text(strings.adaptiveAdvanced)
                    .font(.system(size: 10.5, weight: .medium))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .accessibilityAddTraits(showsAdaptiveAdvanced ? .isSelected : [])
    }

    private func adaptiveRow(_ label: String, value: String, binding: Binding<Int>,
                             range: ClosedRange<Int>, step: Int, help: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .lineLimit(1)
            Stepper(label, value: binding, in: range, step: step)
                .labelsHidden()
                .controlSize(.mini)
                .pointingHandCursor()
                .disabled(isWorking)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .help(help)
    }

    private var adaptiveProfileBinding: Binding<FanControlAdaptiveProfile?> {
        Binding(
            get: { FanControlAdaptiveProfile(matching: adaptiveSettings) },
            set: { profile in
                if let profile { adaptiveSettings = profile.settings }
            }
        )
    }

    /// A level with the speed it means on this Mac's first fan.
    private func levelText(_ level: Int) -> String {
        guard let fan = snapshot.fans.first,
              let rpm = FanControlPolicy.coolingTargetRPM(minimum: fan.minimumRPM,
                                                          maximum: fan.maximumRPM,
                                                          fraction: Double(level) / 100) else {
            return "\(level)%"
        }
        return "\(level)% · " + String(format: strings.rpmFormat, Int(rpm))
    }

    private func temperatureText(_ celsius: Int) -> String {
        MetricFormat.temperature(Double(celsius), unit: temperatureUnit)
    }

    private var adaptiveIsRunning: Bool {
        snapshot.isCooling && snapshot.configuration?.mode == .adaptive
    }

    @ViewBuilder
    private var adaptiveAction: some View {
        HStack(spacing: 8) {
            if adaptiveIsApplied {
                Label(strings.adaptiveActive, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .help(strings.helpActive)
            } else {
                Button(adaptiveIsRunning ? strings.applyChanges : strings.applyAdaptive) {
                    applyConfiguration(.adaptive(adaptiveSettings))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .pointingHandCursor()
                .disabled(isWorking)
                .frame(maxWidth: .infinity)
                .help(strings.helpApply)
            }
            if adaptiveIsRunning {
                Button(strings.returnToSystem, action: stopCooling)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .pointingHandCursor()
                    .disabled(isWorking)
                    .help(strings.helpReturn)
            }
        }
    }

    /// The tuning already running. Applying it again would change nothing.
    private var adaptiveIsApplied: Bool {
        snapshot.isCooling && snapshot.configuration == .adaptive(adaptiveSettings)
    }

    @ViewBuilder
    private var action: some View {
        if error == .noFans || error == .unsupportedHardware || error == .alreadyControlled {
            EmptyView()
        } else if accessState == .notRegistered, !snapshot.fans.isEmpty {
            Button(strings.allowControl, action: authorize)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .pointingHandCursor()
                .help(strings.helpAllow)
        } else if accessState == .requiresApproval, !snapshot.fans.isEmpty {
            Button(strings.openSettings, action: authorize)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .pointingHandCursor()
                .help(strings.helpAllow)
        } else if accessState == .enabled, controlsCanAppear {
            switch mode {
            case .system:
                if snapshot.isCooling {
                    Button(strings.returnToSystem, action: stopCooling)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .pointingHandCursor()
                        .disabled(isWorking)
                        .frame(maxWidth: .infinity)
                        .help(strings.helpReturn)
                }
            case .manual:
                Button(strings.applyManual) {
                    coolingLevel = selectedCoolingLevel
                    applyConfiguration(.manual(level: selectedCoolingLevel))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .pointingHandCursor()
                .disabled(isWorking)
                .frame(maxWidth: .infinity)
                .help(strings.helpApply)
            case .curve:
                Button(strings.applyCurve) {
                    applyConfiguration(.curve(curves))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .pointingHandCursor()
                .disabled(isWorking || !curveCanRun)
                .frame(maxWidth: .infinity)
                .help(strings.helpApply)
            case .adaptive:
                adaptiveAction
            }
        }
    }

    private var statusText: String {
        guard snapshot.isCooling else { return strings.systemControl }
        let level = snapshot.coolingLevel ?? FanControlPolicy.defaultCoolingLevel
        switch snapshot.configuration?.mode ?? .manual {
        case .system:
            return strings.systemControl
        case .manual:
            return "\(strings.manualControl) · \(level)%"
        case .curve:
            let activeCurves = snapshot.configuration?.curves ?? []
            let temperature = activeCurves.count == 1
                ? snapshot.temperatures?.first { $0.source == activeCurves[0].sensor }?.celsius
                : nil
            if let temperature {
                return "\(strings.customCurve) · \(MetricFormat.temperature(temperature, unit: temperatureUnit)) · \(level)%"
            }
            return "\(strings.customCurve) · \(level)%"
        case .adaptive:
            let target = snapshot.fans.map(\.targetRPM).max()
            let readings = snapshot.temperatures ?? []
            // Name the hotspot when it, not the average, is holding the fans up.
            if let target,
               FanControlAdaptivePolicy.hotspotLeads(
                   readings, settings: snapshot.configuration?.adaptive ?? .balanced),
               let hotspot = FanControlAdaptivePolicy.hotspotTemperature(from: readings) {
                return "\(strings.adaptiveControl) · \(strings.adaptiveHotspot) \(MetricFormat.temperature(hotspot, unit: temperatureUnit)) · \(Int(target.rounded())) RPM"
            }
            let temperature = FanControlAdaptivePolicy.controlTemperature(from: readings)
            if let temperature, let target {
                return "\(strings.adaptiveControl) · \(MetricFormat.temperature(temperature, unit: temperatureUnit)) · \(Int(target.rounded())) RPM"
            }
            if let target {
                return "\(strings.adaptiveControl) · \(Int(target.rounded())) RPM"
            }
            return strings.adaptiveControl
        }
    }

    private var stateMessage: String? {
        if error == .noFans { return strings.noFans }
        if accessState == .unavailable { return strings.unsupported }
        switch error {
        case .alreadyControlled: return strings.alreadyControlled
        case .unsupportedHardware: return strings.unsupported
        case .helperUnavailable: return strings.helperUnavailable
        case .controlFailed: return strings.failed
        case .authorizationRequired: return strings.approvalCaption
        case .noFans, .none: break
        }
        if accessState == .notRegistered, !snapshot.fans.isEmpty { return strings.approvalCaption }
        if accessState == .requiresApproval { return strings.approvalCaption }
        switch snapshot.stopReason {
        case .temperatureUnavailable: return strings.temperatureUnavailable
        case .timeLimit, .appDisconnected, .heartbeatLost, .hardwareChanged,
             .thermalPressure, .recovery:
            return strings.safetyStopped
        case .none:
            return nil
        }
    }

    private var messageIsError: Bool {
        switch error {
        case .alreadyControlled, .unsupportedHardware, .helperUnavailable, .controlFailed:
            return true
        default:
            return false
        }
    }

    private var controlsCanAppear: Bool {
        !snapshot.fans.isEmpty
            && (error == nil || error == .controlFailed || snapshot.isCooling)
    }

    private var canConfigure: Bool {
        controlsCanAppear && accessState == .enabled
    }

    private var selectedCoolingLevel: Int {
        let clamped = min(max(coolingLevel, FanControlPolicy.minimumCoolingLevel),
                          FanControlPolicy.maximumCoolingLevel)
        let remainder = clamped % FanControlPolicy.coolingLevelStep
        return remainder == 0 ? clamped : clamped + FanControlPolicy.coolingLevelStep - remainder
    }

    private var coolingLevelBinding: Binding<Double> {
        Binding(
            get: { Double(selectedCoolingLevel) },
            set: { coolingLevel = Int($0.rounded()) }
        )
    }

    private var curveCanRun: Bool {
        guard FanControlPolicy.validCurves(curves) else { return false }
        let available = Set((snapshot.temperatures ?? []).map(\.source))
        return curves.allSatisfy { available.contains($0.sensor) }
    }
}
