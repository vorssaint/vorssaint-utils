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
    @State private var normalSliderTint = Color(nsColor: .controlAccentColor)
    @State private var accentRevision = 0
    var collapsible = true

    var body: some View {
        PanelSection(.mixer, title: l10n.s.mixerSection, collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 8) {
                universalOutputPicker
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
            }
            .panelCard()
        }
        .onReceive(NSApplication.shared.publisher(for: \.effectiveAppearance, options: [.new])) { _ in
            refreshSliderTint()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NSSystemColorsDidChangeNotification"))) { _ in
            refreshSliderTint()
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

    private func refreshSliderTint() {
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
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
                NSWorkspace.shared.open(url)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: ResponsibleProcess.icon(for: app.ownerPid))
                        .resizable()
                        .frame(width: 18, height: 18)
                    if app.isPlaying {
                        Circle()
                            .fill(PanelMetricColor.green(for: colorScheme))
                            .frame(width: 6, height: 6)
                            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1))
                    }
                }

                Text(app.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                outputPicker
            }

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
