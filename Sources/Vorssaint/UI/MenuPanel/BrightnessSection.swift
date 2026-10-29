// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Panel section with one brightness slider per adjustable display. Values
/// refresh whenever the section appears, so changes made with the keyboard,
/// in System Settings or on the monitor itself are picked up.
struct BrightnessSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrightnessService.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.brightnessOSDEnabled) private var brightnessOSDEnabled = false
    @AppStorage(DefaultsKey.brightnessKeysEnabled) private var brightnessKeysEnabled = false
    @AppStorage(DefaultsKey.brightnessShowAllDisplayModes) private var showAllDisplayModes = false
    @State private var optionsExpanded = false
    var collapsible = true

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }

    var body: some View {
        PanelSection(.brightness, title: strings.pageTitle, collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 10) {
                if service.displays.isEmpty {
                    Text(strings.noDisplays)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(service.displays) { display in
                        row(display)
                    }
                }
                if let failure = service.displayControlFailure {
                    Text(displayControlFailureText(failure, strings: strings))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                }
                if service.keyboardLightEnabled != nil {
                    Divider()
                    keyboardLightRow
                }
                if service.brightnessOSDSupported {
                    Divider()
                    Toggle(strings.osdToggle, isOn: $brightnessOSDEnabled)
                        .font(.system(size: 10.5, weight: .medium))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .help(strings.osdCaption)
                        .onChange(of: brightnessOSDEnabled) { _, isOn in
                            if isOn { permissions.requestAccessibility() }
                            service.syncWithPreferences()
                        }
                }
                if AppFeature.extraBrightness.isAvailable {
                    Divider()
                    ExtraBrightnessPanelToggle()
                }
                Divider()
                optionsDisclosure
            }
            .panelCard()
            .onAppear {
                service.refresh()
                service.refreshKeyboardLight()
            }
        }
    }

    private var optionsDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                optionsExpanded.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .rotationEffect(.degrees(optionsExpanded ? 90 : 0))
                    Text(l10n.s.keepAwakeOptions)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if optionsExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(strings.keysToggle, isOn: $brightnessKeysEnabled)
                        .onChange(of: brightnessKeysEnabled) { _, isOn in
                            if isOn { permissions.requestAccessibility() }
                            service.syncWithPreferences()
                        }
                    Text(strings.keysCaption)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if brightnessKeysEnabled, !permissions.accessibility {
                        Button {
                            permissions.openAccessibilitySettings()
                        } label: {
                            Label(l10n.s.permissionOpenSettings, systemImage: "hand.raised")
                        }
                        .buttonStyle(.link)
                    }
                    Toggle(strings.showAllResolutions, isOn: $showAllDisplayModes)
                    Text(strings.showAllResolutionsCaption)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    DisplayBrightnessShortcutControls()
                }
                .font(.system(size: 11.5, weight: .medium))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .padding(.leading, 19)
            }
        }
    }

    private func row(_ display: BrightnessDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(display.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if display.isActive, display.method != nil {
                    Text("\(Int((display.brightness * 100).rounded()))%")
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if !display.isActive {
                    Text(strings.displayOff)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                DisplayPowerButton(display: display, compact: true)
            }
            if display.isActive, display.method != nil {
                Slider(value: brightnessBinding(display), in: 0...1)
                    .controlSize(.small)
                    .disabled(service.isDisplayPending(display.id))
                    .accessibilityLabel(display.name)
            }
            DisplayResolutionSlider(display: display, compact: true)
            SoftwareDimmingButton(display: display, compact: true)
        }
    }

    /// Sits with the display sliders because it is the same control. The
    /// Quick toggles switch stays the place to flip it off and back on, and
    /// the slider reaches 0, so the row carries no switch of its own.
    private var keyboardLightRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(strings.keyboardLight)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(Int(((service.keyboardLightLevel ?? 0) * 100).rounded()))%")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: keyboardLightBinding, in: 0...1,
                   onEditingChanged: service.keyboardLightDragChanged)
                .controlSize(.small)
                .accessibilityLabel(strings.keyboardLight)
        }
    }

    private var keyboardLightBinding: Binding<Double> {
        Binding(get: { Double(service.keyboardLightLevel ?? 0) },
                set: { service.setKeyboardLightLevel(Float($0)) })
    }

    private func brightnessBinding(_ display: BrightnessDisplay) -> Binding<Double> {
        Binding(get: { display.brightness },
                set: { service.setBrightness($0, for: display.id,
                                             showOSD: brightnessOSDEnabled) })
    }
}

private struct ExtraBrightnessPanelToggle: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ExtraBrightnessService.shared
    @AppStorage(DefaultsKey.extraBrightnessEnabled) private var enabled = false

    var body: some View {
        Toggle(l10n.s.extraBrightnessName, isOn: $enabled)
            .font(.system(size: 10.5, weight: .medium))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(!service.supported && !enabled)
            .help(service.supported ? l10n.s.extraBrightnessCaption : l10n.s.extraBrightnessUnsupported)
            .onChange(of: enabled) { _, _ in service.syncWithPreferences() }
            .onAppear { service.syncWithPreferences() }
    }
}

/// Shared routing choice, on every surface that shows the display rows: the
/// slider is just as dead on the Energy page as in the panel, so the way out
/// has to be there too.
///
/// On readable DDC displays, the choice extends the slider below the panel's
/// hardware minimum and is offered in Settings. On write-only DDC paths, it
/// keeps the existing fallback to software control on both surfaces (issue
/// #1589). Either choice stays visible until cleared.
struct SoftwareDimmingButton: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrightnessService.shared
    let display: BrightnessDisplay
    var compact = false

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }
    private var extendedChosen: Bool { service.extendedDimmingPreferred.contains(display.id) }
    private var softwareChosen: Bool { service.softwareDimmingPreferred.contains(display.id) }
    private var chosen: Bool { extendedChosen || softwareChosen }
    private var usesExtendedDimming: Bool {
        !softwareChosen && (extendedChosen || (display.method == .ddc && display.readable))
    }

    private var offered: Bool {
        guard display.isActive, !display.isBuiltIn, display.canChooseDimming else { return false }
        if chosen { return true }
        guard display.method == .ddc else { return false }
        // The panel keeps only the write-only way out; extra dimming is
        // offered in Settings and joins the panel once it is on.
        return !(compact && display.readable)
    }

    var body: some View {
        if offered {
            Button {
                if usesExtendedDimming {
                    service.setExtendedDimmingPreferred(!extendedChosen, for: display.id)
                } else {
                    service.setSoftwareDimmingPreferred(!softwareChosen, for: display.id)
                }
            } label: {
                HStack(spacing: compact ? 4 : 5) {
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                        .font(.system(size: compact ? 9.5 : 11, weight: .semibold))
                    Text(usesExtendedDimming ? strings.extendedDimming : strings.softwareDimming)
                        .font(.system(size: compact ? 10 : 12, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(chosen ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(service.isDisplayPending(display.id))
            .accessibilityLabel("\(display.name): \(usesExtendedDimming ? strings.extendedDimming : strings.softwareDimming)")
        }
    }
}

/// Shared resolution and refresh-rate menu used by Settings and the menu bar
/// panel. Only shown when an active display exposes more than one usable mode.
struct DisplayModePicker: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrightnessService.shared
    @AppStorage(DefaultsKey.brightnessShowAllDisplayModes) private var showAllDisplayModes = false
    let display: BrightnessDisplay
    var compact = false
    var showsLabel = true

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }

    private var modes: [BrightnessSupport.DisplayModeOption] {
        BrightnessSupport.curatedDisplayModes(
            from: display.modes,
            currentModeID: display.selectedModeID,
            showAll: showAllDisplayModes
        )
    }

    private var includeRefreshRate: Bool {
        BrightnessSupport.showsRefreshRate(in: modes)
    }

    var body: some View {
        let offeredModes = modes
        if display.isActive, offeredModes.count > 1,
           let selectedID = display.selectedModeID ?? offeredModes.first?.id {
            HStack(spacing: compact ? 6 : 8) {
                if compact, showsLabel {
                    Text(strings.resolutionLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                }
                Picker(strings.resolutionLabel, selection: Binding(
                    get: { selectedID },
                    set: { service.setDisplayMode($0, for: display.id) }
                )) {
                    ForEach(offeredModes) { mode in
                        Text(BrightnessSupport.formattedDisplayMode(
                            mode,
                            hiDPILabel: strings.hiDPIBadge,
                            hertzUnit: strings.hertzUnit,
                            includeRefreshRate: includeRefreshRate
                        ))
                        .tag(mode.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(compact ? .mini : .small)
                .frame(maxWidth: compact ? 180 : 210, alignment: .trailing)
                .disabled(service.isDisplayPending(display.id))
                .accessibilityLabel("\(display.name): \(strings.resolutionLabel)")
            }
        }
    }
}

/// Stepped resolution bar alongside the brightness bar: drags smoothly across
/// the 10% curated scaling steps and commits on release.
struct DisplayResolutionSlider: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrightnessService.shared
    let display: BrightnessDisplay
    var compact = false
    @State private var previewModeID: Int32?

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }

    private var steps: [BrightnessSupport.DisplayModeOption] {
        BrightnessSupport.sliderDisplayModes(from: display.modes, currentModeID: display.selectedModeID)
    }

    var body: some View {
        let sliderSteps = steps
        if display.isActive, sliderSteps.count > 1 {
            let activeID = previewModeID ?? display.selectedModeID ?? sliderSteps.last?.id
            let activeMode = sliderSteps.first(where: { $0.id == activeID })
                ?? display.modes.first(where: { $0.id == activeID })
                ?? sliderSteps.last
            let scalePercent = activeMode.flatMap {
                BrightnessSupport.displayModeScalePercent($0, in: display.modes)
            }
            let currentIndex = Double(
                sliderSteps.firstIndex(where: { $0.id == activeID }) ?? (sliderSteps.count - 1)
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "aspectratio")
                        .font(.system(size: compact ? 10 : 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: compact ? 16 : 26)
                    Text(strings.resolutionLabel)
                        .font(.system(size: compact ? 10.5 : 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let scalePercent {
                        Text("\(scalePercent)%")
                            .font(.system(size: compact ? 10.5 : 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    DisplayModePicker(display: display, compact: compact, showsLabel: false)
                }
                Slider(
                    value: Binding(
                        get: { currentIndex },
                        set: { newValue in
                            let index = min(max(Int(newValue.rounded()), 0), sliderSteps.count - 1)
                            previewModeID = sliderSteps[index].id
                        }
                    ),
                    in: 0...Double(sliderSteps.count - 1),
                    step: 1
                ) { editing in
                    if !editing, let targetID = previewModeID {
                        previewModeID = nil
                        service.setDisplayMode(targetID, for: display.id)
                    }
                }
                .controlSize(.small)
                .disabled(service.isDisplayPending(display.id))
                .accessibilityLabel("\(display.name): \(strings.resolutionLabel)")
                .onChange(of: display.selectedModeID) { _, _ in previewModeID = nil }
            }
        }
    }
}

/// Shared power affordance used by Settings and the menu bar panel. It stays
/// icon-only in the row, with a localized tooltip and accessibility label.
struct DisplayPowerButton: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrightnessService.shared
    let display: BrightnessDisplay
    var compact = false

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }
    private var pending: Bool { service.isDisplayPending(display.id) }
    private var enabled: Bool { service.canToggleDisplay(display) }

    private var label: String {
        if !service.displaySwitchingAvailable { return strings.switchUnavailable }
        if display.isActive, !enabled { return strings.lastDisplayCaption }
        return display.isActive ? strings.turnOffDisplay : strings.turnOnDisplay
    }

    var body: some View {
        Group {
            if pending {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: compact ? 16 : 20, height: 18)
                    .accessibilityLabel(label)
            } else {
                Button {
                    service.toggleDisplay(display)
                } label: {
                    Image(systemName: display.isActive ? "power" : "power.circle.fill")
                        .font(.system(size: compact ? 10.5 : 12, weight: .semibold))
                        .foregroundStyle(display.isActive ? AnyShapeStyle(.secondary)
                                                         : AnyShapeStyle(.green))
                        .frame(width: compact ? 16 : 20, height: 18)
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .help(label)
                .accessibilityLabel(label)
            }
        }
    }
}

func displayControlFailureText(_ failure: BrightnessService.DisplayControlFailure,
                               strings: BrightnessFeatureStrings) -> String {
    switch failure {
    case .unavailable: return strings.switchUnavailable
    case .lastActive: return strings.lastDisplayCaption
    case .failed: return strings.switchFailed
    case .closedLid: return strings.openLidToEnable
    }
}
