// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

enum OutputDeviceFeedback {
    private static let overlay = TransientOSD<OutputDeviceOSDView>()
    private static var playingSound: NSSound?

    private static var isAvailable: Bool {
        AppFeature.mixer.isAvailable && AppFeature.soundOutputSwitcher.isAvailable
    }

    static func show(device: MixerOutputDevice, playConfirmationSound: Bool = false) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { show(device: device, playConfirmationSound: playConfirmationSound) }
            return
        }
        guard isAvailable else { return }
        if UserDefaults.standard.bool(forKey: DefaultsKey.soundOutputOSDEnabled) {
            let notice = NotchNotice(event: .volume, title: device.name, detail: "",
                                     symbol: device.isHeadphones ? "headphones" : "speaker.wave.2.fill",
                                     isOutputDeviceChange: true)
            // Brightness feedback routes the same way. The island names the
            // device when it accepts the notice, and the centered popup covers
            // the moments it declines, such as while it stays hidden until hover.
            if NotchSupport.isEnabled(), NotchService.shared.show(notice) {
                overlay.teardown()
            } else if let screen = NSScreen.withMouse ?? NSScreen.main {
                overlay.show(OutputDeviceOSDView(name: device.name, isHeadphones: device.isHeadphones),
                             on: screen, duration: 1.5)
            }
        }
        if playConfirmationSound { playSound(deviceUID: device.uid) }
    }

    private static func playSound(deviceUID: String) {
        stopSound()
        guard UserDefaults.standard.bool(forKey: DefaultsKey.soundOutputConfirmationSoundEnabled) else { return }
        // Read the global preference each time so Sound settings changes apply
        // without restarting the app.
        let alertPath = CFPreferencesCopyValue("com.apple.sound.beep.sound" as CFString,
                                              kCFPreferencesAnyApplication,
                                              kCFPreferencesCurrentUser,
                                              kCFPreferencesAnyHost) as? String
        guard let alertPath,
              let sound = NSSound(contentsOfFile: (alertPath as NSString).expandingTildeInPath,
                                  byReference: false) else {
            NSSound.beep()
            return
        }
        // Alert sounds normally follow the separate macOS sound-effects output.
        // This confirmation belongs on the output the user just selected.
        sound.playbackDeviceIdentifier = deviceUID
        playingSound = sound
        sound.play()
    }

    static func syncWithPreferences() {
        if !isAvailable { teardown(); return }
        if NotchSupport.isEnabled()
            || !UserDefaults.standard.bool(forKey: DefaultsKey.soundOutputOSDEnabled) {
            overlay.teardown()
        }
        if !UserDefaults.standard.bool(forKey: DefaultsKey.soundOutputConfirmationSoundEnabled) {
            stopSound()
        }
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
    @AppStorage(DefaultsKey.soundOutputConfirmationSoundEnabled) private var soundEnabled = false

    var body: some View {
        Toggle(l10n.s.soundOutputOSDEnable, isOn: $enabled)
            .onChange(of: enabled) { _, _ in OutputDeviceFeedback.syncWithPreferences() }
        Toggle(l10n.s.soundOutputConfirmationSound, isOn: $soundEnabled)
            .onChange(of: soundEnabled) { _, _ in OutputDeviceFeedback.syncWithPreferences() }
    }
}
