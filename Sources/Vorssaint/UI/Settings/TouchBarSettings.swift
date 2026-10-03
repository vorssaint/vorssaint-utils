// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct TouchBarSettings: View {
    @AppStorage(DefaultsKey.touchBarEnabled) private var enabled = false
    @AppStorage(DefaultsKey.touchBarShowKeepAwake) private var showKeepAwake = true
    @AppStorage(DefaultsKey.touchBarShowMicMute) private var showMicMute = true

    var body: some View {
        Form {
            Section("Touch Bar") {
                Toggle("Enable Vorssaint Touch Bar", isOn: $enabled)
            }

            Section("Controls") {
                Toggle("Keep Awake", isOn: $showKeepAwake)
                Toggle("Microphone Mute", isOn: $showMicMute)
            }
        }
        .formStyle(.grouped)
        .onChange(of: enabled) { _, _ in refreshTouchBar() }
        .onChange(of: showKeepAwake) { _, _ in refreshTouchBar() }
        .onChange(of: showMicMute) { _, _ in refreshTouchBar() }
    }

    private func refreshTouchBar() {
        TouchBarService.shared.syncWithPreferences()
    }
}
