// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The HDR card on the Energy page: the switch that shows the HDR switches,
/// then one row per display that can run HDR in its current mode.
struct HDRControlSettingsCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = HDRControlService.shared
    @AppStorage(DefaultsKey.hdrControlEnabled) private var enabled = false

    var body: some View {
        let strings = FeatureStrings.hdrControl(l10n.language)
        SettingsCard {
            if HDRControlService.isSupported {
                SettingsRow(symbol: "sparkles.rectangle.stack", title: strings.enable,
                            caption: strings.enableCaption) {
                    Toggle(strings.enable, isOn: $enabled)
                        .labelsHidden()
                        .onChange(of: enabled) { _, _ in service.syncWithPreferences() }
                }
                if enabled {
                    if service.displays.isEmpty {
                        SettingsRow(symbol: "display", title: strings.pageTitle, caption: strings.noDisplays) {
                            EmptyView()
                        }
                    }
                    ForEach(service.displays) { display in
                        displayRow(display, strings: strings)
                    }
                }
            } else {
                SettingsRow(symbol: "sparkles.rectangle.stack", title: strings.pageTitle,
                            caption: strings.unsupported) {
                    EmptyView()
                }
            }
        }
        .onAppear { service.syncWithPreferences() }
    }

    private func displayRow(_ display: HDRDisplay, strings: HDRControlStrings) -> some View {
        let failed = service.failedIDs.contains(display.id)
        let working = service.workingIDs.contains(display.id)
        return SettingsRow(symbol: "display", title: display.name,
                           caption: failed ? strings.failedNote : strings.displayCaption) {
            HStack(spacing: 8) {
                if working { ProgressView().controlSize(.small) }
                Toggle(strings.tileTitle, isOn: Binding(
                    get: { display.isEnabled },
                    set: { service.setHDR($0, for: display.id) }
                ))
                .labelsHidden()
                .disabled(working)
            }
        }
    }
}
