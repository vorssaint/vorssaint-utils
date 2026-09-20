// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchCameraView: View {
    let size: CGSize
    @ObservedObject private var service = CameraPreviewService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchActivityStrings { FeatureStrings.notchActivities(l10n.language) }

    var body: some View {
        Group {
            if service.isEmbeddedPresented {
                // The preview takes the height the island leaves beside its
                // stop button and keeps the camera's own proportions.
                let previewHeight = max(80, size.height - 28 - NotchLayout.rowSpacing)
                VStack(spacing: NotchLayout.rowSpacing) {
                    CameraPreviewView(size: CGSize(width: min(size.width, previewHeight * 4 / 3),
                                                   height: previewHeight), showsCameraMenu: true)
                    Button(text.stopCamera, action: service.hideEmbedded)
                        .buttonStyle(.bordered).controlSize(.small)
                }
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
