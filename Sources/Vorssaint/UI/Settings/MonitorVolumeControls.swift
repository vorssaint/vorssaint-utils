// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct MonitorVolumeSettingsRow: View {
    let name: String
    let setup: MonitorVolumeSupport.Setup
    let strings: BrightnessFeatureStrings
    let change: (Bool, Int?) -> Void
    @State private var enteredPercent = ""

    private var reference: Int? {
        let text = enteredPercent.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return setup.reference }
        guard let value = Int(text), (1...100).contains(value) else { return nil }
        return value
    }

    var body: some View {
        SettingsRow(symbol: "display", title: strings.monitorToggle,
                    caption: setup.writeOnly ? "\(name)\n\(strings.manualVolumeCaption)" : name) {
            if setup.writeOnly, !setup.enabled {
                TextField(setup.reference.map { "\($0)%" } ?? "1–100%", text: $enteredPercent)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 68)
                    .accessibilityLabel("\(name) \(strings.volumeLabel)")
            }
            Toggle(name, isOn: Binding(get: { setup.enabled }, set: { enabled in
                change(enabled, reference)
                enteredPercent = ""
            }))
            .labelsHidden()
            .disabled(setup.writeOnly && !setup.enabled && reference == nil)
        }
    }
}
