// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The menu bar panel's Keep Awake card, as its own page of the island.
struct NotchKeepAwakePage: View {
    let size: CGSize

    var body: some View {
        NotchPanelPage(size: size) { KeepAwakeCard(collapsible: false) }
    }
}

/// The menu bar panel's Power card: the charge, what the Mac draws, the
/// battery's health and the accessories' batteries.
struct NotchBatteryPage: View {
    let size: CGSize

    var body: some View {
        NotchPanelPage(size: size) { PowerSection(collapsible: false) }
    }
}

/// A panel section inside the island, scrolling when it outgrows the page.
private struct NotchPanelPage<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .frame(width: size.width)
                .environment(\.colorScheme, .dark)
                .padding(.bottom, 4)
        }
        .scrollIndicators(.automatic)
        .notchScrollEdgeFade()
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

/// The microphone at a glance: one large switch for its mute, the input
/// level beside it and the microphone in use.
struct NotchMicrophonePage: View {
    let size: CGSize
    @ObservedObject private var mic = MicMuteService.shared
    @ObservedObject private var input = AudioInputDeviceManager.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { mic.isMuted ? NotchTopBarPalette.red : NotchTopBarPalette.green }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: mic.toggle) {
                VStack(spacing: 8) {
                    Image(systemName: mic.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(tint)
                        .contentTransition(.symbolEffect(.replace))
                        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: mic.isMuted)
                    Text(mic.isMuted ? l10n.s.micUnmuteName : l10n.s.micMuteName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    if let name = currentDevice?.name {
                        Text(name)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(14)
                .frame(width: 150, height: min(size.height, 150))
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 16))
            .accessibilityLabel(mic.isMuted ? l10n.s.micUnmuteName : l10n.s.micMuteName)

            VStack(alignment: .leading, spacing: 10) {
                if let volume = input.inputVolume {
                    Text(l10n.s.mixerInputTitle.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                    HStack(spacing: 10) {
                        NotchLevelSlider(value: Binding(get: { volume }, set: { input.setInputVolume($0) }),
                                         label: l10n.s.mixerInputTitle, tint: tint, trackThickness: 26)
                            .frame(height: 28)
                            .disabled(mic.isMuted)
                        Text("\(MixerRoutingSupport.displayPercent(forVolume: volume))%")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                if input.inputDevices.count > 1 {
                    NotchMenuButton(title: l10n.s.mixerInputTitle, items: input.inputDevices.map { device in
                        NotchMenuItem(title: device.name, checked: device.uid == currentDevice?.uid) {
                            input.setCurrentInputDeviceUID(device.uid)
                        }
                    }) {
                        HStack(spacing: 5) {
                            Text(currentDevice?.name ?? l10n.s.mixerInputTitle).lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private var currentDevice: MixerInputDevice? {
        input.inputDevices.first { $0.uid == (input.effectiveInputDeviceUID ?? input.currentInputDeviceUID) }
    }
}
