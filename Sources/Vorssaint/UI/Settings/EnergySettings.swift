// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Energy page: Keep Awake with its live status and options, the
/// displays' brightness and power, extra brightness on XDR panels, and
/// Bluetooth on sleep. One card per feature, opened by a row that names it,
/// says what it is doing right now and switches it.
struct EnergySettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var extraBrightness = ExtraBrightnessService.shared
    @ObservedObject private var brightness = BrightnessService.shared
    @AppStorage(DefaultsKey.brightnessControlEnabled) private var brightnessEnabled = false
    @AppStorage(DefaultsKey.brightnessKeysEnabled) private var brightnessKeysEnabled = false
    @AppStorage(DefaultsKey.brightnessOSDEnabled) private var brightnessOSDEnabled = false
    @AppStorage(DefaultsKey.extraBrightnessEnabled) private var extraBrightnessEnabled = false
    @AppStorage(DefaultsKey.extraBrightnessLevel) private var extraBrightnessLevel = 100
    @AppStorage(DefaultsKey.bluetoothSleepEnabled) private var bluetoothSleepEnabled = false
    @AppStorage(DefaultsKey.bluetoothSleepRestoreOnWake) private var bluetoothSleepRestoreOnWake = true
    @AppStorage(DefaultsKey.defaultDuration) private var defaultDuration = 0
    @AppStorage(DefaultsKey.batteryLimit) private var batteryLimit = 10
    @AppStorage(DefaultsKey.keepAwakeAutoStart) private var keepAwakeAutoStart = false
    @AppStorage(DefaultsKey.keepAwakeRightClickToggle) private var keepAwakeRightClickToggle = false
    @AppStorage(DefaultsKey.keepAwakeAllowDisplaySleep) private var keepAwakeAllowDisplaySleep = false
    @AppStorage(DefaultsKey.keepAwakePauseWhenLocked) private var keepAwakePauseWhenLocked = false
    @AppStorage(DefaultsKey.keepAwakeAutomationRequireAll) private var keepAwakeAutomationRequireAll = false
    @AppStorage(DefaultsKey.showCountdown) private var showCountdown = false
    @AppStorage(DefaultsKey.keepAwakeIconTint) private var keepAwakeIconTint = KeepAwakeIconTint.orange.rawValue
    @AppStorage(DefaultsKey.keepAwakeActiveIcon) private var keepAwakeActiveIcon = KeepAwakeActiveIcon.vorssaint.rawValue
    @AppStorage(DefaultsKey.keepAwakeMouseJiggleEnabled) private var keepAwakeMouseJiggle = false
    @AppStorage(DefaultsKey.keepAwakeMouseJiggleInterval) private var keepAwakeMouseJiggleInterval = 5
    @State private var brightnessOptionsExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(l10n.s.tabEnergy).font(.title2.bold())
                    Text(FeatureStrings.settingsPages(l10n.language).energyDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if AppFeature.keepAwake.isAvailable {
                    keepAwakeCard
                        .settingsSectionAnchor(.keepAwake, cornerRadius: 16)
                    keepAwakeOptionsCard
                }
                if AppFeature.brightness.isAvailable {
                    displaysCard
                        .settingsSectionAnchor(.brightness, cornerRadius: 16)
                }
                if AppFeature.extraBrightness.isAvailable {
                    extraBrightnessCard
                        .settingsSectionAnchor(.extraBrightness, cornerRadius: 16)
                }
                if AppFeature.bluetoothSleep.isAvailable {
                    bluetoothCard
                        .settingsSectionAnchor(.bluetoothSleep, cornerRadius: 16)
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        // Shared subviews draw plain toggles; outside a Form those would be
        // checkboxes, so the whole page asks for switches.
        .toggleStyle(.switch)
        .onAppear {
            defaultDuration = Defaults.sanitizedDefaultDuration(defaultDuration)
            batteryLimit = Defaults.sanitizedBatteryLimit(batteryLimit)
            keepAwakeIconTint = Defaults.sanitizedKeepAwakeIconTint(keepAwakeIconTint).rawValue
            keepAwakeActiveIcon = Defaults.sanitizedKeepAwakeActiveIcon(keepAwakeActiveIcon).rawValue
            keepAwakeMouseJiggleInterval = Defaults.sanitizedKeepAwakeMouseJiggleInterval(keepAwakeMouseJiggleInterval)
            awake.refreshPasswordlessStatus()
            // Displays may have changed since launch (docked, clamshell);
            // re-check so the section never shows a stale availability.
            ExtraBrightnessService.shared.syncWithPreferences()
            BrightnessService.shared.refresh()
        }
    }

    // MARK: - Keep awake

    /// The feature itself: what it is doing now, the switch, the default
    /// duration and the conditions that start it by themselves.
    private var keepAwakeCard: some View {
        SettingsCard {
            // A running countdown only while there is one to run down; an
            // automatic session names its condition instead, as in the panel.
            if awake.isActive, awake.sessionTrigger != .automation, let end = awake.endDate {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    sessionRow(status: "\(l10n.s.keepAwakeEndsIn) \(KeepAwakeCard.remainingText(until: end))")
                }
            } else {
                sessionRow(status: sessionStatus)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.s.defaultDurationLabel)
                    .font(.subheadline.weight(.medium))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
                    ForEach(DurationPicker.choices, id: \.self) { minutes in
                        durationChip(minutes)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(automationStrings.automationSection)
                    .font(.subheadline.weight(.medium))
                Text(automationStrings.caption(requireAll: keepAwakeAutomationRequireAll))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                KeepAwakeAutomationEditor()
            }
            SettingsRow(symbol: "lock.fill", title: automationStrings.pauseWhenLockedToggle,
                        caption: automationStrings.pauseWhenLockedCaption) {
                Toggle(automationStrings.pauseWhenLockedToggle, isOn: $keepAwakePauseWhenLocked)
                    .labelsHidden()
            }
        }
    }

    /// The feature's name, what it is doing right now and its switch.
    private func sessionRow(status: String) -> some View {
        SettingsRow(symbol: "moon.zzz.fill", title: l10n.s.keepAwakeTitle, caption: status) {
            Toggle(l10n.s.keepAwakeTitle, isOn: sessionBinding)
                .labelsHidden()
        }
    }

    private var sessionStatus: String {
        guard awake.isActive else { return l10n.s.keepAwakeNormalRules }
        if awake.sessionTrigger == .automation {
            return automationStrings.activeStatus(for: awake.activeAutomationConditions)
        }
        return l10n.s.keepAwakeUntilDisabled
    }

    private var sessionBinding: Binding<Bool> {
        Binding(
            get: { awake.isActive },
            set: { on in
                if on {
                    awake.activate(minutes: defaultDuration)
                } else if awake.isActive {
                    awake.toggle()
                }
            }
        )
    }

    private func durationChip(_ minutes: Int) -> some View {
        let selected = defaultDuration == minutes
        return Button {
            defaultDuration = minutes
        } label: {
            Text(DurationPicker.title(for: minutes, l10n.s))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Everything else Keep Awake can do, one row each.
    private var keepAwakeOptionsCard: some View {
        SettingsCard(title: l10n.s.keepAwakeOptions) {
            SettingsRow(symbol: "play.circle", title: l10n.s.keepAwakeAutoStart,
                        caption: l10n.s.keepAwakeAutoStartCaption) {
                Toggle(l10n.s.keepAwakeAutoStart, isOn: $keepAwakeAutoStart).labelsHidden()
            }
            SettingsRow(symbol: "cursorarrow.click.2", title: l10n.s.keepAwakeRightClickToggle,
                        caption: l10n.s.keepAwakeRightClickToggleCaption) {
                Toggle(l10n.s.keepAwakeRightClickToggle, isOn: $keepAwakeRightClickToggle).labelsHidden()
            }
            SettingsRow(symbol: "timer", title: l10n.s.showCountdown) {
                Toggle(l10n.s.showCountdown, isOn: $showCountdown).labelsHidden()
            }
            SettingsRow(symbol: "display", title: displaySleepStrings.allowDisplaySleep,
                        caption: displaySleepStrings.allowDisplaySleepCaption) {
                Toggle(displaySleepStrings.allowDisplaySleep, isOn: $keepAwakeAllowDisplaySleep).labelsHidden()
            }
            SettingsRow(symbol: "cursorarrow.motionlines", title: l10n.s.keepAwakeMouseJiggle,
                        caption: l10n.s.keepAwakeMouseJiggleCaption) {
                Toggle(l10n.s.keepAwakeMouseJiggle, isOn: $keepAwakeMouseJiggle).labelsHidden()
            }
            if keepAwakeMouseJiggle {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(l10n.s.keepAwakeMouseJiggleInterval)
                        Spacer()
                        KeepAwakeMouseJiggleIntervalPicker(selection: $keepAwakeMouseJiggleInterval)
                    }
                    if !permissions.accessibility {
                        PermissionRow(kind: .accessibility)
                    }
                }
                .padding(.leading, settingsRowTextInset)
            }
            Divider()
            KeepAwakeIconPicker(iconValue: $keepAwakeActiveIcon, tintValue: $keepAwakeIconTint)
            if PowerSampler.hasInternalBattery {
                Divider()
                SettingsRow(symbol: "battery.25percent", title: l10n.s.batteryDisableBelow,
                            caption: l10n.s.batteryProtectionCaption) {
                    Picker(l10n.s.batteryDisableBelow, selection: $batteryLimit) {
                        Text(l10n.s.batteryNever).tag(0)
                        Text("5%").tag(5)
                        Text("10%").tag(10)
                        Text("15%").tag(15)
                        Text("20%").tag(20)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
            Divider()
            SettingsRow(symbol: "laptopcomputer", title: l10n.s.clamshellTitle, caption: clamshellCaption) {
                Toggle(l10n.s.clamshellTitle, isOn: $awake.clamshellPreferred)
                    .labelsHidden()
                    .disabled(awake.clamshellSetupInProgress)
            }
            if awake.clamshellSetupFailed {
                Text(l10n.s.sudoersFailed)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, settingsRowTextInset)
            }
            if awake.clamshellPreferred {
                SettingsRow(symbol: "sun.min", title: l10n.s.dimScreenOnLidCloseTitle,
                            caption: l10n.s.dimScreenOnLidCloseCaption) {
                    Toggle(l10n.s.dimScreenOnLidCloseTitle, isOn: $awake.dimScreenOnLidClose)
                        .labelsHidden()
                }
                .padding(.leading, settingsRowTextInset)
            }
        }
    }

    private var clamshellCaption: String {
        awake.clamshellSetupInProgress ? l10n.s.configuring : l10n.s.clamshellExplanation
    }

    // MARK: - Displays

    private var displaysCard: some View {
        let strings = FeatureStrings.brightness(l10n.language)
        return SettingsCard {
            SettingsRow(symbol: "display.2", title: strings.enable, caption: strings.enableCaption) {
                Toggle(strings.enable, isOn: $brightnessEnabled)
                    .labelsHidden()
                    .onChange(of: brightnessEnabled) { _, _ in
                        BrightnessService.shared.syncWithPreferences()
                    }
            }
            if brightnessEnabled {
                Divider()
                if brightness.displays.isEmpty {
                    Text(strings.noDisplays)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(brightness.displays) { display in
                        displayRow(display)
                    }
                }
                if let failure = brightness.displayControlFailure {
                    Text(displayControlFailureText(failure, strings: strings))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup(isExpanded: $brightnessOptionsExpanded) {
                    VStack(alignment: .leading, spacing: 13) {
                        SettingsRow(symbol: "cursorarrow.rays", title: strings.keysToggle,
                                    caption: strings.keysCaption) {
                            Toggle(strings.keysToggle, isOn: $brightnessKeysEnabled)
                                .labelsHidden()
                                .onChange(of: brightnessKeysEnabled) { _, isOn in
                                    if isOn { Permissions.shared.requestAccessibility() }
                                    BrightnessService.shared.syncWithPreferences()
                                }
                        }
                        DisplayBrightnessShortcutControls()
                            .toggleStyle(TrailingSwitchToggleStyle())
                            .padding(.leading, settingsRowTextInset)
                        if brightness.brightnessOSDSupported {
                            SettingsRow(symbol: "sun.max", title: strings.osdToggle, caption: strings.osdCaption) {
                                Toggle(strings.osdToggle, isOn: $brightnessOSDEnabled)
                                    .labelsHidden()
                                    .onChange(of: brightnessOSDEnabled) { _, isOn in
                                        if isOn { Permissions.shared.requestAccessibility() }
                                        BrightnessService.shared.syncWithPreferences()
                                    }
                            }
                        }
                        if (brightnessKeysEnabled || brightnessOSDEnabled), !permissions.accessibility {
                            PermissionRow(kind: .accessibility)
                        }
                        Text(strings.externalCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 10)
                } label: {
                    Text(FeatureStrings.recorder(l10n.language).moreOptions)
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    private func displayRow(_ display: BrightnessDisplay) -> some View {
        HStack(spacing: 12) {
            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(display.isActive ? Color.accentColor : Color.secondary)
                .frame(width: 26, height: 26)
                .background((display.isActive ? Color.accentColor : Color.secondary).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(display.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 80, alignment: .leading)
            if display.isActive, display.method != nil {
                Slider(value: Binding(get: { display.brightness },
                                      set: { BrightnessService.shared.setBrightness(
                                          $0, for: display.id,
                                          showOSD: brightnessOSDEnabled) }),
                       in: 0...1)
                    .disabled(brightness.isDisplayPending(display.id))
                    .accessibilityLabel(display.name)
                Text("\(Int((display.brightness * 100).rounded()))%")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            } else {
                Spacer()
                if !display.isActive {
                    Text(FeatureStrings.brightness(l10n.language).displayOff)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
            SoftwareDimmingButton(display: display)
            DisplayPowerButton(display: display)
        }
    }

    // MARK: - Extra brightness

    private var extraBrightnessCard: some View {
        SettingsCard {
            if extraBrightness.supported {
                SettingsRow(symbol: "sun.max.fill", title: l10n.s.extraBrightnessName,
                            caption: l10n.s.extraBrightnessCaption) {
                    Toggle(l10n.s.extraBrightnessName, isOn: $extraBrightnessEnabled)
                        .labelsHidden()
                        .onChange(of: extraBrightnessEnabled) { _, _ in
                            ExtraBrightnessService.shared.syncWithPreferences()
                        }
                }
                if extraBrightnessEnabled {
                    HStack(spacing: 12) {
                        Text(l10n.s.extraBrightnessLevelLabel)
                        Slider(value: extraBrightnessLevelBinding, in: 10...100, step: 5)
                        Text("\(extraBrightnessLevel)%")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    .padding(.leading, settingsRowTextInset)
                }
            } else {
                SettingsRow(symbol: "sun.max.fill", title: l10n.s.extraBrightnessName,
                            caption: l10n.s.extraBrightnessUnsupported) {
                    EmptyView()
                }
            }
        }
    }

    private var extraBrightnessLevelBinding: Binding<Double> {
        Binding(get: { Double(extraBrightnessLevel) },
                set: { newValue in
                    extraBrightnessLevel = Int(newValue)
                    ExtraBrightnessService.shared.levelDidChange()
                })
    }

    // MARK: - Bluetooth on sleep

    private var bluetoothCard: some View {
        let strings = FeatureStrings.bluetoothSleep(l10n.language)
        return SettingsCard {
            if BluetoothSleepService.isSupported {
                SettingsRow(symbol: "dot.radiowaves.left.and.right", title: strings.enable,
                            caption: strings.enableCaption) {
                    Toggle(strings.enable, isOn: $bluetoothSleepEnabled)
                        .labelsHidden()
                        .onChange(of: bluetoothSleepEnabled) { _, _ in
                            BluetoothSleepService.shared.syncWithPreferences()
                        }
                }
                if bluetoothSleepEnabled {
                    SettingsRow(symbol: "arrow.counterclockwise", title: strings.restoreToggle,
                                caption: strings.restoreCaption) {
                        Toggle(strings.restoreToggle, isOn: $bluetoothSleepRestoreOnWake).labelsHidden()
                    }
                }
            } else {
                SettingsRow(symbol: "dot.radiowaves.left.and.right", title: strings.pageTitle,
                            caption: strings.unsupported) {
                    EmptyView()
                }
            }
        }
    }

    private var automationStrings: KeepAwakeAutomationStrings {
        FeatureStrings.keepAwakeAutomation(l10n.language)
    }

    private var displaySleepStrings: KeepAwakeDisplaySleepStrings {
        FeatureStrings.keepAwakeDisplaySleep(l10n.language)
    }
}
