// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import SwiftUI

struct NotchCameraView: View {
    let size: CGSize
    @ObservedObject private var service = CameraPreviewService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchActivityStrings { FeatureStrings.notchActivities(l10n.language) }

    var body: some View {
        Group {
            if service.isEmbeddedPresented {
                // The preview takes the whole page; its camera picker and stop
                // button sit in the island's top row, clear of the image.
                CameraPreviewView(size: NotchLayout.cameraPreviewSize(in: size), showsCameraMenu: false)
            } else {
                HStack(spacing: 16) {
                    Image(systemName: "web.camera").font(.system(size: 30, weight: .light))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                        .frame(width: 56, height: 56)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(text.cameraHint).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(text.startCamera, action: service.showEmbedded)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { service.hideEmbedded() }
    }
}

/// The camera the mirror shows, in the island's top row while it runs with
/// more than one camera around: the current one's name, cut short beside the
/// camera, over a native menu of them all.
struct NotchCameraChooser: View {
    @ObservedObject private var service = CameraPreviewService.shared
    @ObservedObject private var l10n = L10n.shared
    private var strings: CameraPreviewFeatureStrings { FeatureStrings.cameraPreview(l10n.language) }

    private var current: String {
        service.devices.first { $0.uniqueID == service.selectedDeviceID }?.localizedName ?? strings.cameraMenuLabel
    }

    var body: some View {
        if service.isEmbeddedPresented, service.state == .running, service.session != nil, service.devices.count > 1 {
            NotchMenuButton(title: strings.cameraMenuLabel, items: service.devices.map { device in
                NotchMenuItem(title: device.localizedName, checked: device.uniqueID == service.selectedDeviceID) {
                    service.selectCamera(device)
                }
            }, cornerRadius: 9) {
                NotchBandMenuLabel(title: current)
            }
            .help(current)
            .accessibilityValue(current)
        }
    }
}

/// Stops the mirror from the island's top row: a glyph beside the camera,
/// where a word may not fit, and the word itself across a full row.
struct NotchCameraStopButton: View {
    @ObservedObject private var service = CameraPreviewService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.notchBand) private var band

    var body: some View {
        if service.isEmbeddedPresented {
            let title = FeatureStrings.notchActivities(l10n.language).stopCamera
            if band.besideCamera {
                NotchIconButton(symbol: "video.slash", title: title, action: service.hideEmbedded)
            } else {
                NotchPillButton(title: title, prominent: true, action: service.hideEmbedded)
            }
        }
    }
}
