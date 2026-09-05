// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct FanControlSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = FanControlService.shared
    @AppStorage(DefaultsKey.fanControlMode) private var modeRaw = FanControlMode.system.rawValue
    @AppStorage(DefaultsKey.fanControlCoolingLevel) private var coolingLevel =
        FanControlPolicy.defaultCoolingLevel
    @AppStorage(DefaultsKey.fanControlCurves) private var curvesStorage =
        FanControlConfiguration.defaultCurvesStorage
    @AppStorage(DefaultsKey.fanControlManualDuration) private var manualDurationRaw =
        FanControlManualDuration.untilChanged.rawValue
    @AppStorage(DefaultsKey.fanControlProfiles) private var profilesStorage = "[]"
    @AppStorage(DefaultsKey.fanControlActiveProfileID) private var activeProfileID = ""
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit =
        TemperatureUnit.celsius.rawValue
    var collapsible = true

    private var strings: FanControlFeatureStrings {
        FeatureStrings.fanControl(l10n.language)
    }

    var body: some View {
        PanelSection(.fanControl, title: strings.title, collapsible: collapsible) {
            FanControlCardContent(strings: strings,
                                  betaLabel: l10n.s.betaBadge,
                                  snapshot: service.snapshot,
                                  accessState: service.accessState,
                                  error: service.error,
                                  isWorking: service.isWorking,
                                  mode: modeBinding,
                                  coolingLevel: $coolingLevel,
                                  manualDuration: manualDurationBinding,
                                  curves: curvesBinding,
                                  profiles: profiles,
                                  temperatureUnit: displayTemperatureUnit,
                                  authorize: service.authorize,
                                  applyConfiguration: service.applyConfiguration,
                                  stopCooling: service.restoreAutomatic,
                                  applyProfile: apply(_:),
                                  saveCurrentAsProfile: saveCurrentAsProfile)
                .panelCard()
                .onAppear { service.panelDidAppear() }
                .onDisappear { service.panelDidDisappear() }
        }
    }

    private var modeBinding: Binding<FanControlMode> {
        Binding(
            get: { FanControlMode(rawValue: modeRaw) ?? .system },
            set: { modeRaw = $0.rawValue }
        )
    }

    private var manualDurationBinding: Binding<FanControlManualDuration> {
        Binding(
            get: { FanControlManualDuration(rawValue: manualDurationRaw) ?? .untilChanged },
            set: { manualDurationRaw = $0.rawValue }
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

    private var profiles: [FanProfile] {
        FanProfile.decodeArray(profilesStorage)
    }

    /// Applies a profile exactly through the same path a hand-set mode/level/
    /// duration/curve would take: fill the pending controls with what the
    /// profile represents, remember it as the last explicit selection, then
    /// hand the resulting configuration to `applyConfiguration` — the panel's
    /// one-click switch.
    private func apply(_ profile: FanProfile) {
        let configuration = profile.configuration
        modeRaw = configuration.mode.rawValue
        coolingLevel = configuration.manualLevel
        manualDurationRaw = configuration.manualDuration.rawValue
        if configuration.mode == .curve, let encoded = FanControlConfiguration.encodeCurves(configuration.curves) {
            curvesStorage = encoded
        }
        activeProfileID = profile.id
        service.applyConfiguration(configuration)
    }

    /// "Save as profile…": prompts for a name with a native text-field alert,
    /// then stores the currently pending mode/level/duration/curve as a new
    /// custom profile. No window is required — this panel is a popover, not
    /// a sheet-owning window — so a modal `runModal()` alert matches how the
    /// rest of the app already asks quick yes/no questions from the menu bar.
    private func saveCurrentAsProfile() {
        let field = NSTextField(string: "")
        field.placeholderString = strings.profileNamePlaceholder
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        let alert = NSAlert()
        alert.messageText = strings.profileNamePrompt
        alert.accessoryView = field
        alert.addButton(withTitle: strings.saveProfileButton)
        alert.addButton(withTitle: strings.cancelButton)
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let configuration = FanControlConfiguration(mode: modeBinding.wrappedValue,
                                                    manualLevel: coolingLevel,
                                                    curves: curvesBinding.wrappedValue,
                                                    manualDuration: manualDurationBinding.wrappedValue)
        let profile = FanProfile.makeCustom(name: name, from: configuration)
        var updated = profiles
        updated.append(profile)
        if let encoded = FanProfile.encodeArray(updated) {
            profilesStorage = encoded
        }
        activeProfileID = profile.id
    }
}

struct FanControlCardContent: View {
    let strings: FanControlFeatureStrings
    let betaLabel: String
    let snapshot: FanControlSnapshot
    let accessState: FanControlService.AccessState
    let error: FanControlErrorCode?
    let isWorking: Bool
    @Binding var mode: FanControlMode
    @Binding var coolingLevel: Int
    @Binding var manualDuration: FanControlManualDuration
    @Binding var curves: [FanControlCurve]
    let profiles: [FanProfile]
    let temperatureUnit: TemperatureUnit
    let authorize: () -> Void
    let applyConfiguration: (FanControlConfiguration) -> Void
    let stopCooling: () -> Void
    let applyProfile: (FanProfile) -> Void
    let saveCurrentAsProfile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusHeader

            if !snapshot.fans.isEmpty { fanRows }

            if let message = stateMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(messageIsError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if canConfigure {
                profilesRow
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
                    if !curveCanRun {
                        Text(strings.curveUnavailable)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            action

            if controlsCanAppear {
                Text(strings.safetyCaption)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.secondary.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What the pending (not-yet-applied) controls currently represent, used
    /// to highlight the matching profile chip. Built the same way the
    /// `applyConfiguration` calls below build it — `.manual`/system-shaped
    /// configurations always carry an empty `curves`, matching what
    /// `FanProfile.configuration` produces for those kinds — so a profile in
    /// manual or system mode can match regardless of whatever curve was last
    /// edited, instead of comparing against a `curves` array that mode never
    /// actually sends.
    private var pendingConfiguration: FanControlConfiguration {
        switch mode {
        case .system:
            return FanControlConfiguration(mode: .system,
                                           manualLevel: FanControlPolicy.defaultCoolingLevel,
                                           curves: [], manualDuration: .untilChanged)
        case .manual:
            return .manual(level: coolingLevel, duration: manualDuration)
        case .curve:
            return .curve(curves)
        }
    }

    /// A one-click row of saved profiles above the mode picker. A compact
    /// menu picker is used once there are more than four profiles — a
    /// segmented control stops reading well as a single row past that count —
    /// but either way this is a native `Picker`, never a custom dropdown.
    @ViewBuilder
    private var profilesRow: some View {
        if !profiles.isEmpty {
            let selection = Binding<String?>(
                get: { FanProfile.activeProfile(matching: pendingConfiguration, in: profiles)?.id },
                set: { newID in
                    guard let newID, let profile = profiles.first(where: { $0.id == newID }) else { return }
                    applyProfile(profile)
                }
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(strings.profilesLabel)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: saveCurrentAsProfile) {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .help(strings.saveAsProfile)
                    .disabled(isWorking)
                }
                Group {
                    if profiles.count > 4 {
                        Picker(strings.profilesLabel, selection: selection) {
                            ForEach(profiles) { profile in
                                Text(profile.displayName(strings)).tag(Optional(profile.id))
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        Picker(strings.profilesLabel, selection: selection) {
                            ForEach(profiles) { profile in
                                Text(profile.displayName(strings)).tag(Optional(profile.id))
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .disabled(isWorking)
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

            HStack {
                Text(strings.duration)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker(strings.duration, selection: $manualDuration) {
                    ForEach(FanControlManualDuration.allCases) { option in
                        Text(strings.durationLabel(for: option)).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .disabled(isWorking)
                .fixedSize()
            }

            if isManualSessionActive {
                HStack {
                    if let remainingMinutes {
                        Text(String(format: strings.minutesRemainingFormat, remainingMinutes))
                            .font(.system(size: 9.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(strings.returnToSystem, action: stopCooling)
                        .buttonStyle(.plain)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .disabled(isWorking)
                }
            }
        }
    }

    /// A manual session considered "active" for the quick return-to-automatic
    /// control, independent of whichever mode the picker currently shows —
    /// flipping the segmented control back to System should not be the only
    /// way to cancel a running manual override.
    private var isManualSessionActive: Bool {
        snapshot.isCooling && snapshot.configuration?.mode == .manual
    }

    private var remainingMinutes: Int? {
        FanControlPolicy.remainingManualMinutes(until: snapshot.endsAt, now: Date())
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
                    applyConfiguration(.manual(level: selectedCoolingLevel, duration: manualDuration))
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
            let base = "\(strings.manualControl) · \(level)%"
            guard let remainingMinutes else { return base }
            return "\(base) · \(String(format: strings.minutesRemainingFormat, remainingMinutes))"
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
