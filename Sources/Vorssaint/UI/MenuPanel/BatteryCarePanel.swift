// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct BatteryCarePanel: View {
    @ObservedObject private var service = BatteryControlService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var limit = 80.0
    @State private var editingLimit = false
    @State private var confirmingCalibration = false
    private func text(_ key: String) -> String { BatteryControlStrings.text(key, l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(text("title"), systemImage: "battery.100.bolt")
                Spacer()
                Text("\(service.configuration.limit)%").monospacedDigit()
            }
            if let response = service.response {
                Text(text(response.state.rawValue)).foregroundStyle(.secondary)
            }
            if service.configuration.enabled {
                HStack {
                    Text(text("limit"))
                    Slider(value: $limit, in: 20...100, step: 1) { editing in
                        editingLimit = editing
                        if !editing { service.action(.setLimit, value: Int(limit)) }
                    }.accessibilityLabel(text("limit"))
                    Text("\(Int(limit))%").monospacedDigit().frame(width: 34, alignment: .trailing)
                }.disabled(service.busy)
                HStack {
                    Button(text("topUp")) { service.action(.topUp) }
                    let paused = service.response?.mode == .paused
                    Button(text(paused ? "resume" : "pause")) { service.action(paused ? .resume : .pause) }
                    Menu {
                        Button(text("discharge")) { service.action(.discharge) }
                            .disabled(service.response?.supportsDischarge != true)
                        Button(text("calibrate")) { confirmingCalibration = true }
                            .disabled(service.response?.supportsDischarge != true)
                        Button(text("cancel")) { service.action(.cancel) }
                        Divider()
                        Button(text("lowPowerOn")) { service.action(.lowPowerOn) }
                        Button(text("lowPowerOff")) { service.action(.lowPowerOff) }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel(FeatureStrings.recorder(l10n.language).moreOptions)
                }.disabled(service.busy)
            }
            if let error = service.error {
                Text(text(error)).foregroundStyle(.red).font(.caption)
            }
        }
        .font(.system(size: 11))
        .onAppear { limit = Double(service.configuration.limit); service.appear() }
        .onReceive(service.$response) { response in
            if !editingLimit, let response { limit = Double(response.configuration.limit) }
        }
        .onDisappear { service.disappear() }
        .confirmationDialog(text("calibrationCaption"), isPresented: $confirmingCalibration, titleVisibility: .visible) {
            Button(text("calibrate")) { service.action(.calibrate) }
        }
    }
}
