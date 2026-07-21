// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Per-app volume sliders, the mixer macOS never shipped. Shows every app
/// holding an audio connection (a green dot marks the ones playing right now).
/// 100% is untouched passthrough; below it attenuates and above it (up to 200%)
/// boosts, with the slider and percentage turning amber in the boost range.
struct MixerSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @ObservedObject private var inputManager = AudioInputDeviceManager.shared
    @ObservedObject private var outputSwitcher = SoundOutputSwitcher.shared
    @AppStorage(DefaultsKey.mixerShowFinder)
    private var showFinder = true
    @AppStorage(DefaultsKey.mixerLowerVolumeOnHeadphonesDisconnect)
    private var lowerOnHeadphonesDisconnect = false
    @AppStorage(DefaultsKey.mixerHeadphonesDisconnectVolumePercent)
    private var headphonesDisconnectVolumePercent = Defaults.defaultMixerHeadphonesDisconnectVolumePercent
    @AppStorage(DefaultsKey.soundOutputSwitcherEnabled)
    private var soundOutputSwitcherEnabled = false
    @State private var soundOutputSwitcherUIDs: [String] = []
    @State private var normalSliderTint = Color(nsColor: .controlAccentColor)
    @State private var accentRevision = 0
    @State private var lastResolvedAccent: NSColor?
    var collapsible = true

    var body: some View {
        PanelSection(.mixer, title: l10n.s.mixerSection, collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 8) {
                universalOutputPicker
                headphoneDisconnectProtectionToggle
                if AppFeature.soundOutputSwitcher.isAvailable {
                    soundOutputSwitcherControls
                }
                microphonePicker
                if AppVolumeMixer.isSupported, (!mixer.apps.isEmpty || mixer.needsPermission) {
                    Divider()
                }

                if !AppVolumeMixer.isSupported {
                    emptyLabel(l10n.s.mixerUnavailable)
                } else if mixer.needsPermission {
                    permissionHint
                } else if mixer.apps.isEmpty {
                    emptyLabel(l10n.s.mixerEmpty)
                } else {
                    mixerRows
                }
                if AppVolumeMixer.isSupported {
                    Divider()
                    finderVisibilityToggle
                }
            }
            .panelCard()
        }
        .onReceive(NSApplication.shared.publisher(for: \.effectiveAppearance, options: [.new])) { _ in
            refreshSliderTint()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NSSystemColorsDidChangeNotification"))) { _ in
            refreshSliderTint()
        }
        .onAppear {
            soundOutputSwitcherUIDs = SoundOutputSwitcher.shared.selectedDeviceUIDs()
        }
    }

    private var universalOutputPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label {
                    Text(l10n.s.mixerSystemOutputTitle)
                        .font(.system(size: 11.5, weight: .medium))
                } icon: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .foregroundStyle(.secondary)

                Spacer(minLength: 6)

                Picker(l10n.s.mixerSystemOutputTooltip, selection: universalOutputSelectionBinding) {
                    if mixer.currentOutputDeviceUID == nil {
                        Text(l10n.s.mixerOutputUnavailable)
                            .tag(MixerRoutingSupport.systemDefaultSelectionID)
                    }
                    ForEach(universalOutputDevices) { device in
                        Text(outputDeviceTitle(device))
                            .tag(device.uid)
                    }
                    if let selected = mixer.currentOutputDeviceUID,
                       !universalOutputDevices.contains(where: { $0.uid == selected }) {
                        Text(l10n.s.mixerOutputUnavailable)
                            .tag(selected)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 164)
                .disabled(universalOutputDevices.isEmpty)
                .help(l10n.s.mixerSystemOutputTooltip)
            }

            if universalOutputDevices.isEmpty {
                inputMessage(l10n.s.mixerSystemOutputNoDevices, systemImage: "speaker.slash")
            } else if let outputSwitchError = mixer.outputSwitchError {
                inputMessage(String(format: l10n.s.mixerSystemOutputErrorFormat, outputSwitchError),
                             systemImage: "exclamationmark.triangle")
            }
        }
    }

    private var universalOutputDevices: [MixerOutputDevice] {
        mixer.outputDevices.filter(\.canBeDefaultOutput)
    }

    private var universalOutputSelectionBinding: Binding<String> {
        Binding(
            get: { mixer.currentOutputDeviceUID ?? MixerRoutingSupport.systemDefaultSelectionID },
            set: { selection in
                guard selection != MixerRoutingSupport.systemDefaultSelectionID else { return }
                mixer.setUniversalOutputDeviceUID(selection)
            }
        )
    }

    private var headphoneDisconnectProtectionToggle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(l10n.s.mixerLowerOnHeadphonesDisconnect,
                   isOn: $lowerOnHeadphonesDisconnect)
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5, weight: .medium))

            Text(l10n.s.mixerLowerOnHeadphonesDisconnectCaption)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if lowerOnHeadphonesDisconnect {
                HStack(spacing: 8) {
                    Stepper(value: headphonesDisconnectVolumeBinding,
                            in: Defaults.minimumMixerHeadphonesDisconnectVolumePercent...100,
                            step: 5) {
                        Text(l10n.s.mixerHeadphonesDisconnectVolume)
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .controlSize(.small)
                    Spacer(minLength: 6)
                    Text("\(headphonesDisconnectDisplayPercent)%")
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    private var headphonesDisconnectVolumeBinding: Binding<Int> {
        Binding(
            get: { Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(headphonesDisconnectVolumePercent) },
            set: { headphonesDisconnectVolumePercent = Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent($0) }
        )
    }

    private var headphonesDisconnectDisplayPercent: Int {
        Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(headphonesDisconnectVolumePercent)
    }

    private var soundOutputSwitcherControls: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(l10n.s.soundOutputSwitcherEnable, isOn: $soundOutputSwitcherEnabled)
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5, weight: .medium))
                .onChange(of: soundOutputSwitcherEnabled) { _, enabled in
                    if enabled, soundOutputSwitcherUIDs.isEmpty,
                       let current = mixer.currentOutputDeviceUID,
                       universalOutputDevices.contains(where: { $0.uid == current }) {
                        setSoundOutputSwitcherUIDs([current])
                    }
                    SoundOutputSwitcher.shared.syncWithPreferences()
                }

            Text(l10n.s.soundOutputSwitcherCaption)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if soundOutputSwitcherEnabled {
                ShortcutPreferenceRow(role: .soundOutputSwitcher,
                                      isEnabled: soundOutputSwitcherEnabled,
                                      additionalConflict: WindowLayoutService.shared.shortcutConflictTitle) {
                    SoundOutputSwitcher.shared.syncWithPreferences()
                }
                if outputSwitcher.registrationFailed {
                    inputMessage(l10n.s.shortcutUnavailable, systemImage: "keyboard.badge.ellipsis")
                }
                if outputSwitcher.lastSwitchFailed {
                    inputMessage(l10n.s.soundOutputSwitcherNoAvailableSelection,
                                 systemImage: "speaker.badge.exclamationmark")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.s.soundOutputSwitcherDevices)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)

                    if universalOutputDevices.isEmpty {
                        inputMessage(l10n.s.mixerSystemOutputNoDevices, systemImage: "speaker.slash")
                    } else {
                        ForEach(universalOutputDevices) { device in
                            Toggle(isOn: soundOutputSwitcherSelectionBinding(for: device.uid)) {
                                Text(outputDeviceTitle(device))
                                    .font(.system(size: 10.5))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func soundOutputSwitcherSelectionBinding(for uid: String) -> Binding<Bool> {
        Binding(
            get: { soundOutputSwitcherUIDs.contains(uid) },
            set: { selected in
                var next = soundOutputSwitcherUIDs
                if selected {
                    if !next.contains(uid) { next.append(uid) }
                } else {
                    next.removeAll { $0 == uid }
                }
                let visibleOrder = universalOutputDevices.map(\.uid)
                let visible = visibleOrder.filter { next.contains($0) }
                let unavailable = next.filter { !visibleOrder.contains($0) }
                setSoundOutputSwitcherUIDs(visible + unavailable)
            }
        )
    }

    private func setSoundOutputSwitcherUIDs(_ uids: [String]) {
        let sanitized = Defaults.sanitizedSoundOutputSwitcherDeviceUIDs(uids)
        soundOutputSwitcherUIDs = sanitized
        SoundOutputSwitcher.shared.setSelectedDeviceUIDs(sanitized)
    }

    private var microphonePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label {
                    Text(l10n.s.mixerInputTitle)
                        .font(.system(size: 11.5, weight: .medium))
                } icon: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .foregroundStyle(.secondary)

                Spacer(minLength: 6)

                Picker(l10n.s.mixerInputTooltip, selection: inputSelectionBinding) {
                    Text(l10n.s.mixerOutputDefault)
                        .tag(MixerRoutingSupport.systemDefaultSelectionID)
                    ForEach(inputManager.inputDevices) { device in
                        Text(inputDeviceTitle(device))
                            .tag(device.uid)
                    }
                    if let selected = inputManager.preferredInputDeviceUID,
                       inputManager.preferredUnavailable {
                        Text(l10n.s.mixerInputUnavailable)
                            .tag(selected)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 164)
                .disabled(inputManager.inputDevices.isEmpty)
                .help(l10n.s.mixerInputTooltip)
            }

            if inputManager.inputDevices.isEmpty {
                inputMessage(l10n.s.mixerInputNoDevices, systemImage: "mic.slash")
            } else if inputManager.preferredUnavailable {
                inputMessage(l10n.s.mixerInputFallback, systemImage: "mic.badge.xmark")
            } else if let lastError = inputManager.lastError {
                inputMessage(String(format: l10n.s.mixerInputErrorFormat, lastError),
                             systemImage: "exclamationmark.triangle")
            }
        }
    }

    private var inputSelectionBinding: Binding<String> {
        Binding(
            get: { inputManager.preferredInputDeviceUID ?? MixerRoutingSupport.systemDefaultSelectionID },
            set: { selection in
                inputManager.setPreferredInputDeviceUID(
                    selection == MixerRoutingSupport.systemDefaultSelectionID ? nil : selection)
            }
        )
    }

    private var finderVisibilityToggle: some View {
        HStack(spacing: 8) {
            Text(l10n.s.mixerShowFinder)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Toggle(l10n.s.mixerShowFinder, isOn: $showFinder)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(l10n.s.mixerShowFinder)
        }
        .onChange(of: showFinder) { _, _ in
            mixer.syncWithPreferences()
        }
    }

    private func inputDeviceTitle(_ device: MixerInputDevice) -> String {
        device.isDefault ? "\(device.name) (\(l10n.s.mixerOutputCurrent))" : device.name
    }

    private func outputDeviceTitle(_ device: MixerOutputDevice) -> String {
        device.isDefault ? "\(device.name) (\(l10n.s.mixerOutputCurrent))" : device.name
    }

    private func inputMessage(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var mixerRows: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                rowList
            }
        } else {
            rowList
        }
    }

    @ViewBuilder
    private var rowList: some View {
        ForEach(mixer.apps) { app in
            MixerRow(app: app,
                     normalTint: normalSliderTint,
                     accentRevision: accentRevision)
        }
    }

    /// Appearance KVO and the system-colors notification can fire in bursts
    /// without the accent actually changing, and every revision bump re-renders
    /// (and, before macOS 26, recreates) every slider row — so compare the
    /// accent resolved against the current appearance and only then re-tint.
    /// When the accent cannot be resolved this fails open (always re-tints),
    /// never closed: eating a real accent change would leave stale sliders.
    private func refreshSliderTint() {
        var resolved: NSColor?
        NSApplication.shared.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = NSColor.controlAccentColor.usingColorSpace(.sRGB)
        }
        if let resolved, let last = lastResolvedAccent, resolved == last { return }
        lastResolvedAccent = resolved
        normalSliderTint = Color(nsColor: .controlAccentColor)
        accentRevision += 1
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)
    }

    private var permissionHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l10n.s.mixerPermissionBody)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(l10n.s.permissionOpenSettings) {
                Permissions.shared.openAudioCaptureSettings()
            }
            .controlSize(.small)
        }
    }
}

private struct MixerRow: View {
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    let app: MixerApp
    let normalTint: Color
    let accentRevision: Int

    /// Warm accent to flag the boost range, darkened in Light Mode for contrast.
    private var boostColor: Color { PanelMetricColor.orange(for: colorScheme) }
    /// Tie the visual state to the displayed percentage, so "amber" and ">100%"
    /// always agree and the reset hides exactly when the row reads 100%.
    private var isBoosting: Bool { (app.volume * 100).rounded() > 100 }
    private var isAtUnity: Bool { (app.volume * 100).rounded() == 100 }

    /// SoundSource-sized icon spanning the row's two lines (issue #166); the
    /// bitmap must be requested at this size or the upscale looks blurry.
    private static let iconPointSize: CGFloat = 32

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: ResponsibleProcess.icon(for: app.ownerPid,
                                                       pointSize: Self.iconPointSize))
                    .resizable()
                    .frame(width: Self.iconPointSize, height: Self.iconPointSize)
                if app.isPlaying {
                    Circle()
                        .fill(PanelMetricColor.green(for: colorScheme))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.2))
                        .offset(x: -1, y: -1)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(app.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 4)

                    if !app.isBypassed {
                        outputPicker
                    }
                }

                if app.isBypassed {
                    // Zoom and pro audio apps are listed but never tapped
                    // (issue #177): the row explains itself instead of the
                    // app silently missing from the mixer.
                    Text(l10n.s.mixerBypassedCaption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 8) {
                        MixerVolumeSlider(value: volumeBinding,
                                          normalTint: normalTint,
                                          boostTint: boostColor,
                                          isBoosting: isBoosting,
                                          accentRevision: accentRevision,
                                          accessibilityLabel: app.name)

                        HStack(spacing: 2) {
                            if isBoosting {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(boostColor)
                            }
                            Text("\(Int((app.volume * 100).rounded()))%")
                                .font(.system(size: 10.5, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(isBoosting ? boostColor : Color.secondary)
                        }
                        .frame(width: 42, alignment: .trailing)

                        Button {
                            mixer.setVolume(1, for: app)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(isBoosting ? boostColor : Color.secondary)
                                .frame(width: 14)
                        }
                        .buttonStyle(.plain)
                        .help(l10n.s.mixerResetTooltip)
                        .opacity(isAtUnity ? 0 : 1)
                        .disabled(isAtUnity)

                        Button {
                            mixer.toggleMute(app)
                        } label: {
                            Image(systemName: app.volume <= 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(app.volume <= 0.001
                                                 ? PanelMetricColor.red(for: colorScheme)
                                                 : Color.secondary)
                                .frame(width: 16)
                        }
                        .buttonStyle(.plain)
                    }

                    if app.outputDeviceUnavailable {
                        Label(l10n.s.mixerOutputFallback, systemImage: "speaker.badge.exclamationmark")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { app.volume },
            set: { mixer.setVolume($0, for: app) }
        )
    }

    private var outputPicker: some View {
        Picker(l10n.s.mixerOutputTooltip, selection: outputSelectionBinding) {
            Text(l10n.s.mixerOutputDefault)
                .tag(MixerRoutingSupport.systemDefaultSelectionID)
            ForEach(mixer.outputDevices) { device in
                Text(outputDeviceTitle(device))
                    .tag(device.uid)
            }
            if let selected = app.selectedOutputDeviceUID, app.outputDeviceUnavailable {
                Text(l10n.s.mixerOutputUnavailable)
                    .tag(selected)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: 112)
        .help(l10n.s.mixerOutputTooltip)
    }

    private var outputSelectionBinding: Binding<String> {
        Binding(
            get: { app.selectedOutputDeviceUID ?? MixerRoutingSupport.systemDefaultSelectionID },
            set: { selection in
                mixer.setOutputDeviceUID(selection == MixerRoutingSupport.systemDefaultSelectionID ? nil : selection,
                                         for: app)
            }
        )
    }

    private func outputDeviceTitle(_ device: MixerOutputDevice) -> String {
        device.isDefault ? "\(device.name) (\(l10n.s.mixerOutputCurrent))" : device.name
    }
}

private struct MixerVolumeSlider: View {
    @Binding var value: Double
    let normalTint: Color
    let boostTint: Color
    let isBoosting: Bool
    let accentRevision: Int
    let accessibilityLabel: String

    private var activeTint: Color { isBoosting ? boostTint : normalTint }
    private var percentage: Int { Int((value * 100).rounded()) }

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                LiquidGlassMixerSlider(value: $value,
                                       tint: activeTint,
                                       isBoosting: isBoosting,
                                       accessibilityLabel: accessibilityLabel)
            } else {
                nativeSlider
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityValue("\(percentage)%")
            }
        }
    }

    private var nativeSlider: some View {
        Slider(value: $value, in: 0...AppVolumeMixer.maxVolume)
            .controlSize(.small)
            // Pass an explicit accent (not nil) for the normal state: on the
            // macOS slider, tint(nil) does not reliably clear a previously
            // applied colour, so the bar would stay amber after leaving boost.
            .tint(activeTint)
            .id(accentRevision)
    }
}

@available(macOS 26.0, *)
private struct LiquidGlassMixerSlider: View {
    @Binding var value: Double
    let tint: Color
    let isBoosting: Bool
    let accessibilityLabel: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    private let knobWidth: CGFloat = 24
    private let knobHeight: CGFloat = 15
    private let trackHeight: CGFloat = 5

    private var progress: CGFloat {
        let clamped = min(max(value, 0), AppVolumeMixer.maxVolume)
        return CGFloat(clamped / AppVolumeMixer.maxVolume)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, knobWidth)
            let amount = progress
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(trackOpacity))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(tint)
                    .frame(width: max(trackHeight, width * amount), height: trackHeight)
                    .shadow(color: tint.opacity(0.18), radius: 3)

                knob
                    .frame(width: knobWidth, height: knobHeight)
                    .offset(x: (width - knobWidth) * amount)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.16), value: amount)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        updateValue(at: gesture.location.x, width: width)
                    }
            )
        }
        .frame(height: knobHeight)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(Int((value * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(AppVolumeMixer.maxVolume, value + 0.05)
            case .decrement:
                value = max(0, value - 0.05)
            @unknown default:
                break
            }
        }
    }

    private var trackOpacity: Double {
        colorScheme == .light ? 0.11 : 0.16
    }

    private var knob: some View {
        ZStack {
            knobFill
            Capsule()
                .strokeBorder(tint.opacity(isBoosting ? 0.55 : 0.36), lineWidth: isBoosting ? 1.1 : 0.8)
            Capsule()
                .fill(
                    LinearGradient(colors: [
                        Color.white.opacity(colorScheme == .light ? 0.48 : 0.28),
                        Color.white.opacity(0.06)
                    ], startPoint: .top, endPoint: .bottom)
                )
                .blendMode(.screen)
                .padding(1)
        }
        .shadow(color: tint.opacity(isBoosting ? 0.24 : 0.16), radius: 3, x: 0, y: 0)
        .shadow(color: Color.black.opacity(colorScheme == .light ? 0.08 : 0.18), radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    private var knobFill: some View {
        if reduceTransparency {
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(Capsule().fill(tint.opacity(colorScheme == .light ? 0.10 : 0.16)))
        } else {
            Color.clear
                .glassEffect(.regular.tint(tint.opacity(isBoosting ? 0.18 : 0.10)).interactive(), in: Capsule())
        }
    }

    private func updateValue(at x: CGFloat, width: CGFloat) {
        let travel = max(width - knobWidth, 1)
        let normalized = min(max((x - knobWidth / 2) / travel, 0), 1)
        value = Double(normalized) * AppVolumeMixer.maxVolume
    }
}
