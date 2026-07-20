// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import SwiftUI

/// The floating mirror: the live camera image with a camera picker that
/// appears on hover when more than one camera is around. Esc, a click
/// anywhere else or switching to the meeting app closes it.
struct CameraPreviewView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = CameraPreviewService.shared
    @State private var hovering = false

    private var strings: CameraPreviewFeatureStrings {
        FeatureStrings.cameraPreview(l10n.language)
    }

    var body: some View {
        ZStack {
            Color.black
            content
        }
        .frame(width: 320, height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        // The surface is always black, so the controls (spinner, menu,
        // buttons) must draw for a dark background in either system look.
        .environment(\.colorScheme, .dark)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var content: some View {
        switch service.state {
        case .running:
            if let session = service.session {
                CameraLayerView(session: session)
                    .overlay(alignment: .bottom) {
                        if hovering, service.devices.count > 1 {
                            cameraMenu
                                .padding(.bottom, 10)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: hovering)
            }
        case .idle, .waitingPermission, .starting:
            ProgressView()
                .controlSize(.small)
                .tint(.white)
        case .denied:
            statusMessage(icon: "video.slash", text: strings.deniedMessage) {
                Button(l10n.s.permissionOpenSettings) {
                    Permissions.shared.openCameraSettings()
                }
                .controlSize(.small)
            }
        case .noCamera:
            statusMessage(icon: "web.camera", text: strings.noCameraMessage) { EmptyView() }
        }
    }

    private var cameraMenu: some View {
        Menu {
            ForEach(service.devices, id: \.uniqueID) { device in
                Button {
                    service.selectCamera(device)
                } label: {
                    if device.uniqueID == service.selectedDeviceID {
                        Label(device.localizedName, systemImage: "checkmark")
                    } else {
                        Text(device.localizedName)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "web.camera")
                    .font(.system(size: 10, weight: .semibold))
                Text(currentCameraName)
                    .font(.caption)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.white)
        .background(.black.opacity(0.55), in: Capsule())
        .accessibilityLabel(strings.cameraMenuLabel)
    }

    private var currentCameraName: String {
        service.devices.first { $0.uniqueID == service.selectedDeviceID }?.localizedName
            ?? strings.cameraMenuLabel
    }

    private func statusMessage<Extra: View>(icon: String,
                                            text: String,
                                            @ViewBuilder extra: () -> Extra) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.55))
            Text(text)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            extra()
        }
        .padding(.horizontal, 28)
    }
}

/// Hosts the AVCaptureVideoPreviewLayer. The mirror flip lives on the layer's
/// connection, which only exists once the session has its input, so it is
/// (re)applied on every update.
private struct CameraLayerView: NSViewRepresentable {
    let session: AVCaptureSession

    final class LayerHostView: NSView {
        let previewLayer: AVCaptureVideoPreviewLayer

        init(session: AVCaptureSession) {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            previewLayer.videoGravity = .resizeAspectFill
            layer = previewLayer
            applyMirroring()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        /// A mirror shows what a mirror would: the image flipped, on every
        /// camera, the same thing Photo Booth does.
        func applyMirroring() {
            guard let connection = previewLayer.connection,
                  connection.isVideoMirroringSupported
            else { return }
            if connection.automaticallyAdjustsVideoMirroring {
                connection.automaticallyAdjustsVideoMirroring = false
            }
            if !connection.isVideoMirrored {
                connection.isVideoMirrored = true
            }
        }
    }

    func makeNSView(context: Context) -> LayerHostView {
        LayerHostView(session: session)
    }

    func updateNSView(_ view: LayerHostView, context: Context) {
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
        }
        view.applyMirroring()
    }
}
