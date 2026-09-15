// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchCameraView: View {
    let size: CGSize
    @ObservedObject private var service = CameraPreviewService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchActivityStrings { FeatureStrings.notchActivities(l10n.language) }

    var body: some View {
        VStack(spacing: 14) {
            if service.isEmbeddedPresented {
                CameraPreviewView(size: CGSize(width: size.width,
                    height: max(80, min(size.width * 0.75, size.height - 50))), showsCameraMenu: true)
                Button(text.stopCamera, action: service.hideEmbedded)
                    .buttonStyle(.bordered)
            } else {
                Spacer(minLength: 0)
                Image(systemName: "web.camera").font(.system(size: 34, weight: .light))
                    .foregroundStyle(.secondary).accessibilityHidden(true)
                Text(text.cameraHint).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button(text.startCamera, action: service.showEmbedded)
                    .buttonStyle(.borderedProminent)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { service.hideEmbedded() }
    }
}
