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
            if display.isActive {
                DisplayResolutionRow(displayID: display.id)
            }
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
    @AppStorage(DefaultsKey.extraBrightnessLevel) private var level = 100

    private var levelBinding: Binding<Double> {
        Binding(
            get: { Double(level) },
            set: { newValue in
                level = Int(newValue)
                service.levelDidChange()
            }
        )
    }

    private var multiplierText: String {
        let mult = min(2.0, max(1.0, 1.0 + (Double(level) / 100.0)))
        return String(format: "%.2fx", locale: Locale(identifier: "en_US_POSIX"), mult)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(l10n.s.extraBrightnessName)
                .font(.system(size: 10.5, weight: .medium))

            Spacer(minLength: 4)

            if enabled && service.supported {
                Slider(value: levelBinding, in: 10...100, step: 5)
                    .tint(.orange)
                    .controlSize(.mini)
                    .frame(width: 80)

                Text(multiplierText)
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.orange)
                    .frame(width: 36, alignment: .trailing)
            }

            Toggle("", isOn: $enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!service.supported && !enabled)
                .help(service.supported ? l10n.s.extraBrightnessCaption : l10n.s.extraBrightnessUnsupported)
                .onChange(of: enabled) { _, _ in service.syncWithPreferences() }
                .onAppear { service.syncWithPreferences() }
        }
    }
}

/// Shared routing choice, on every surface that shows the display rows: the
/// slider is just as dead on the Energy page as in the panel, so the way out
/// has to be there too.
///
/// Offered only where the routing is genuinely ambiguous: a channel that takes
/// writes and answers no reads either drives the panel or swallows everything,
/// and the bus cannot tell which (issue #1589). Stays visible once chosen, or
/// there would be no way back to DDC.
struct SoftwareDimmingButton: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrightnessService.shared
    let display: BrightnessDisplay
    var compact = false

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }
    private var chosen: Bool { service.softwareDimmingPreferred.contains(display.id) }

    private var offered: Bool {
        guard display.isActive, !display.isBuiltIn else { return false }
        if chosen { return true }
        return display.method == .ddc && !display.readable
    }

    var body: some View {
        if offered {
            Button {
                service.setSoftwareDimmingPreferred(!chosen, for: display.id)
            } label: {
                HStack(spacing: compact ? 4 : 5) {
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                        .font(.system(size: compact ? 9.5 : 11, weight: .semibold))
                    Text(strings.softwareDimming)
                        .font(.system(size: compact ? 10 : 12, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(chosen ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(service.isDisplayPending(display.id))
            .accessibilityLabel("\(display.name): \(strings.softwareDimming)")
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

// MARK: - Display Resolution & HiDPI Controls

struct DisplayResolutionRow: View {
    @ObservedObject private var resolutionService = DisplayResolutionService.shared
    @ObservedObject private var recoveryManager = DisplayRecoveryManager.shared
    @ObservedObject private var l10n = L10n.shared
    let displayID: CGDirectDisplayID

    private var currentMode: DisplayResolutionMode? {
        resolutionService.currentModePerDisplay[displayID]
    }

    private var modes: [DisplayResolutionMode] {
        resolutionService.modesPerDisplay[displayID] ?? []
    }

    private var status: HiDPIStatus {
        resolutionService.hiDPIStatusPerDisplay[displayID] ?? .none
    }

    var body: some View {
        if let current = currentMode {
            HStack(spacing: 6) {
                // Resolution & Refresh rate menu
                Menu {
                    ForEach(modes) { mode in
                        Button {
                            resolutionService.applyMode(mode, for: displayID)
                        } label: {
                            HStack {
                                if mode.id == current.id {
                                    Image(systemName: "checkmark")
                                }
                                Text("\(mode.width) × \(mode.height)  ·  \(mode.refreshLabel)\(mode.isHiDPI ? " (HiDPI)" : "")")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("\(current.width) × \(current.height)")
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                        Text("· \(current.refreshLabel)")
                            .font(.system(size: 9.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(recoveryManager.awaitingConfirmation)

                Spacer(minLength: 4)

                // HiDPI Status Badge
                statusBadge(status)

                // Quick HiDPI Toggle Button
                Button {
                    resolutionService.toggleHiDPI(for: displayID)
                } label: {
                    Image(systemName: status != .none ? "sparkles.tv" : "tv")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(status != .none ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(recoveryManager.awaitingConfirmation)
                .help(l10n.s.toggleHiDPICaption)
            }
            .padding(.leading, 22)
            .padding(.top, 1)
            .onAppear {
                resolutionService.refresh()
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: HiDPIStatus) -> some View {
        switch status {
        case .native:
            Text(l10n.s.nativeHiDPI)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.accentColor))
        case .virtualMirror:
            Text(l10n.s.virtualHiDPI)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.purple))
        case .none:
            Text(l10n.s.standardResolution)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
    }
}
