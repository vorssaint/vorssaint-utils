// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

enum OutputDeviceFeedback {
    private static let overlay = TransientOSD<OutputDeviceOSDView>()
    private static var playingSound: NSSound?

    static let sounds: [URL] = {
        let directory = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "aiff" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }()

    private static var isEnabled: Bool {
        AppFeature.mixer.isAvailable && AppFeature.soundOutputSwitcher.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.soundOutputOSDEnabled)
    }

    static func show(device: MixerOutputDevice) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { show(device: device) }
            return
        }
        guard isEnabled else { return }
        if let screen = NSScreen.withMouse ?? NSScreen.main {
            overlay.show(OutputDeviceOSDView(name: device.name, isHeadphones: device.isHeadphones),
                         on: screen, duration: 1.5)
        }
        playSound(UserDefaults.standard.string(forKey: DefaultsKey.soundOutputConfirmationSound) ?? "",
                  deviceUID: device.uid)
    }

    static func previewSound(_ selected: String) {
        playSound(selected, deviceUID: AppVolumeMixer.shared.currentOutputDeviceUID)
    }

    private static func playSound(_ selected: String, deviceUID: String?) {
        stopSound()
        guard isEnabled else { return }
        guard let url = sounds.first(where: { $0.lastPathComponent == selected }),
              let sound = NSSound(contentsOf: url, byReference: true) else { return }
        // Alert sounds normally follow the separate macOS sound-effects output.
        // This confirmation belongs on the output the user just selected.
        sound.playbackDeviceIdentifier = deviceUID
        playingSound = sound
        sound.play()
    }

    static func syncWithPreferences() {
        if !isEnabled { teardown() }
    }

    static func stopSound() {
        playingSound?.stop()
        playingSound = nil
    }

    static func teardown() {
        overlay.teardown()
        stopSound()
    }
}

struct OutputDeviceOSDView: View {
    let name: String
    let isHeadphones: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isHeadphones ? "headphones" : "speaker.wave.2.fill")
                .font(.system(size: 39))
                .foregroundStyle(.white.opacity(0.82))
                .frame(height: 44)
            Text(name)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 244)
        .frame(minHeight: 154)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}

struct OutputDeviceFeedbackControls: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.soundOutputOSDEnabled) private var enabled = false
    @AppStorage(DefaultsKey.soundOutputConfirmationSound) private var sound = ""

    var body: some View {
        Toggle(l10n.s.soundOutputOSDEnable, isOn: $enabled)
            .onChange(of: enabled) { _, _ in OutputDeviceFeedback.syncWithPreferences() }
        if enabled {
            HStack(spacing: 8) {
                Picker(l10n.s.soundOutputConfirmationSound, selection: Binding(
                    get: { sound },
                    set: { selected in
                        sound = selected
                        OutputDeviceFeedback.previewSound(selected)
                    }
                )) {
                    Text(l10n.s.shortcutNone).tag("")
                    ForEach(OutputDeviceFeedback.sounds, id: \.lastPathComponent) { url in
                        Text(url.deletingPathExtension().lastPathComponent).tag(url.lastPathComponent)
                    }
                }
                Button {
                    OutputDeviceFeedback.previewSound(sound)
                } label: {
                    Image(systemName: "play.circle")
                        .font(.system(size: 17))
                }
                .buttonStyle(.borderless)
                .help(l10n.s.actionPlay)
                .accessibilityLabel(l10n.s.actionPlay)
                .disabled(!OutputDeviceFeedback.sounds.contains { $0.lastPathComponent == sound })
            }
        }
    }
}
