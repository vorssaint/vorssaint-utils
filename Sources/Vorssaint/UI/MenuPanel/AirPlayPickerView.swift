// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVKit
import SwiftUI

/// Embeds the native macOS AirPlay route picker view in SwiftUI.
///
/// Binds to `AirPlayRouteManager`'s shared output context so user selections
/// route system audio to the chosen HomePod, Apple TV, or AirPlay receiver.
struct AirPlayRoutePickerRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        if let picker = AirPlayRouteManager.shared.makeRoutePickerView() {
            picker.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(picker)
            NSLayoutConstraint.activate([
                picker.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                picker.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                picker.topAnchor.constraint(equalTo: container.topAnchor),
                picker.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// A compact AirPlay button suitable for the mixer panel header and output switcher.
struct AirPlayPickerButton: View {
    @ObservedObject private var manager = AirPlayRouteManager.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        if manager.isAvailable {
            AirPlayRoutePickerRepresentable()
                .frame(width: 24, height: 22)
                .help(manager.activeSpeakerName.map { String(format: l10n.s.mixerAirPlaySpeakerFormat, $0) }
                      ?? l10n.s.mixerAirPlayPickerTooltip)
        }
    }
}
