// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct FanControlSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = FanControlService.shared
    @AppStorage(DefaultsKey.fanControlMode) private var modeRaw = FanControlMode.system.rawValue
    @AppStorage(DefaultsKey.fanControlCoolingLevel) private var coolingLevel =
        FanControlPolicy.defaultCoolingLevel
    @AppStorage(DefaultsKey.fanControlCurves) private var curvesStorage =
        FanControlConfiguration.defaultCurvesStorage
    @AppStorage(DefaultsKey.fanControlResume) private var resume = false
    @AppStorage(DefaultsKey.fanControlManualMinutes) private var manualMinutes =
        FanControlManualDuration.untilChanged
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
                                  fallbackFanSpeeds: fallbackFanSpeeds,
                                  accessState: service.accessState,
                                  error: service.error,
                                  isWorking: service.isWorking,
                                  mode: modeBinding,
                                  coolingLevel: $coolingLevel,
                                  curves: curvesBinding,
                                  resume: $resume,
                                  manualMinutes: $manualMinutes,
                                  timedManual: service.timedManual,
                                  durationLabels: FanControlDurationLabels.labels(
                                      for: l10n.language, l10n.s, untilChanged: strings.untilChanged),
                                  temperatureUnit: displayTemperatureUnit,
                                  authorize: service.authorize,
                                  applyConfiguration: service.applyConfiguration,
                                  applyManual: service.applyManual,
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

    private var displayTemperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnit) ?? .celsius
    }
}

/// The duration chips' labels for one language: the Keep awake labels ("5m",
/// "∞") and the same durations spelled out for VoiceOver. Each label builds a
/// formatter, and the card refreshes on every heartbeat reply, so they are
/// formatted once per language instead of on every refresh.
struct FanControlDurationLabels {
    let language: AppLanguage
    let short: [Int: String]
    let spoken: [Int: String]

    private static var cached: FanControlDurationLabels?

    static func labels(for language: AppLanguage, _ s: Strings,
                       untilChanged: String) -> FanControlDurationLabels {
        if let cached, cached.language == language { return cached }
        var short: [Int: String] = [:]
        var spoken: [Int: String] = [:]
        for minutes in FanControlManualDuration.choices {
            guard minutes > 0 else {
                short[minutes] = "∞"
                spoken[minutes] = untilChanged
                continue
            }
            short[minutes] = DurationPicker.shortTitle(for: minutes, s, language)
            spoken[minutes] = DurationPicker.shortTitle(for: minutes, s, language, style: .full)
        }
        let labels = FanControlDurationLabels(language: language, short: short, spoken: spoken)
        cached = labels
        return labels
    }
}

struct FanControlCardContent: View {
    let strings: FanControlFeatureStrings
    let betaLabel: String
    let snapshot: FanControlSnapshot
    let fallbackFanSpeeds: [Double]
    let accessState: FanControlService.AccessState
    let error: FanControlErrorCode?
    let isWorking: Bool
    @Binding var mode: FanControlMode
    @Binding var coolingLevel: Int
    @Binding var curves: [FanControlCurve]
    @Binding var resume: Bool
    @Binding var manualMinutes: Int
    let timedManual: FanControlTimedManual?
    let durationLabels: FanControlDurationLabels
    let temperatureUnit: TemperatureUnit
    let authorize: () -> Void
    let applyConfiguration: (FanControlConfiguration) -> Void
    let applyManual: (Int, Int) -> Void
    let stopCooling: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusHeader

            if !fallbackFanSpeeds.isEmpty,
               snapshot.fans.isEmpty || error == .helperUnavailable {
                fallbackFanRows
            } else if !snapshot.fans.isEmpty {
                fanRows
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
                    manualDurationChips
                case .curve:
                    FanControlCurveEditor(strings: strings,
                                          curves: $curves,
                                          temperatures: snapshot.temperatures ?? [],
                                          temperatureUnit: temperatureUnit,
                                          disabled: isWorking)
                    if !curveCanRun {
                        Text(strings.curveUnavailable)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            action

            if let end = runningEnd {
                timedCountdown(until: end)
            }

            if canConfigure, mode != .system {
                Toggle(strings.resumeAfterRestart, isOn: $resume)
                    .font(.system(size: 10.5, weight: .medium))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            if controlsCanAppear {
                Text(controlEndsOnItsOwn ? strings.timedSafetyCaption : strings.safetyCaption)
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
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .disabled(isWorking)
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
    }

    /// The Keep awake chips, as a choice for the Apply button rather than a
    /// start: the speed above still has to be picked first. The menu bar
    /// panel shares its width evenly among the chips, so, like the Keep awake
    /// row, this folds into two rows of three when one row would truncate.
    private var manualDurationChips: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(strings.keepManualFor)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    ForEach(FanControlManualDuration.choices, id: \.self, content: durationChip)
                }
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(FanControlManualDuration.choices.prefix(3), id: \.self,
                                content: durationChip)
                    }
                    HStack(spacing: 4) {
                        ForEach(FanControlManualDuration.choices.dropFirst(3), id: \.self,
                                content: durationChip)
                    }
                }
            }
        }
    }

    private func durationChip(_ minutes: Int) -> some View {
        let selected = selectedManualMinutes == minutes
        return Button {
            manualMinutes = minutes
        } label: {
            // Every chip reserves the widest label, the way the Keep awake
            // chips reserve a full countdown: an even split then keeps one
            // row only when every label fits in its share.
            ZStack {
                ForEach(FanControlManualDuration.choices, id: \.self) { other in
                    Text(durationLabels.short[other] ?? "").hidden()
                }
                Text(durationLabels.short[minutes] ?? "")
            }
        }
        .buttonStyle(KeepAwakeChipStyle(isSelected: selected))
        .disabled(isWorking)
        .help(durationLabels.spoken[minutes] ?? "")
        .accessibilityLabel(durationLabels.spoken[minutes] ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The countdown keeps one line beside the button when both fit, and
    /// the button moves under it when they do not, as in a narrow panel
    /// with a long button label.
    private func timedCountdown(until end: Date) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                countdownLabel(until: end)
                    .fixedSize()
                Spacer(minLength: 4)
                // With System picked, the Apply row already offers this button.
                if mode != .system {
                    endEarlyButton
                        .fixedSize()
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                countdownLabel(until: end)
                    .fixedSize(horizontal: false, vertical: true)
                if mode != .system {
                    endEarlyButton
                }
            }
        }
    }

    private func countdownLabel(until end: Date) -> some View {
        // Reserves the longest countdown a timed speed shows, so the layout
        // chosen above holds while the time counts down. The longest choice
        // is an hour, already under "60:00" by the time the helper confirms
        // it, so the countdown stays in minutes and seconds.
        ZStack(alignment: .leading) {
            Label(String(format: strings.returnsToSystemFormat, "00:00"), systemImage: "timer")
                .hidden()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Label(String(format: strings.returnsToSystemFormat,
                             KeepAwakeCard.countdownText(until: end)),
                      systemImage: "timer")
            }
        }
        .font(.system(size: 10.5).monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private var endEarlyButton: some View {
        Button(strings.returnToSystem, action: stopCooling)
            .buttonStyle(KeepAwakeChipStyle())
            .disabled(isWorking)
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
                Text(statusText)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(snapshot.isCooling ? Color.cyan : Color.secondary)
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

    @ViewBuilder
    private var action: some View {
        if error == .noFans || error == .unsupportedHardware || error == .alreadyControlled {
            EmptyView()
        } else if accessState == .notRegistered, !snapshot.fans.isEmpty {
            Button(strings.allowControl, action: authorize)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        } else if accessState == .requiresApproval, !snapshot.fans.isEmpty {
            Button(strings.openSettings, action: authorize)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        } else if accessState == .enabled, controlsCanAppear {
            switch mode {
            case .system:
                if snapshot.isCooling {
                    Button(strings.returnToSystem, action: stopCooling)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isWorking)
                        .frame(maxWidth: .infinity)
                }
            case .manual:
                Button(strings.applyManual) {
                    coolingLevel = selectedCoolingLevel
                    applyManual(selectedCoolingLevel, selectedManualMinutes)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isWorking)
                .frame(maxWidth: .infinity)
            case .curve:
                Button(strings.applyCurve) {
                    applyConfiguration(.curve(curves))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isWorking || !curveCanRun)
                .frame(maxWidth: .infinity)
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

    private var selectedManualMinutes: Int {
        FanControlManualDuration.validated(manualMinutes)
    }

    private var runningEnd: Date? {
        FanControlManualDuration.runningEnd(timedManual, snapshot: snapshot)
    }

    private var controlEndsOnItsOwn: Bool {
        FanControlManualDuration.controlEndsOnItsOwn(runningEnd: runningEnd,
                                                     isCooling: snapshot.isCooling,
                                                     mode: mode, minutes: selectedManualMinutes)
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
