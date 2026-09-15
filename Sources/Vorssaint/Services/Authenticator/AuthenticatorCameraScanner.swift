// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation

/// Holds a phone up to the Mac's camera: a small window with the live
/// picture, closing itself the moment a QR code is read. Camera access is
/// asked for on first use, like the camera preview tool.
final class AuthenticatorCameraScanner: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    static let shared = AuthenticatorCameraScanner()

    private var panel: NSPanel?
    private var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "com.vorssaint.authenticator.camera")
    private var onPayload: ((String) -> Void)?
    private var finished = false

    private var strings: AuthenticatorFeatureStrings {
        FeatureStrings.authenticator(L10n.shared.language)
    }

    func show(onPayload: @escaping (String) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.show(onPayload: onPayload) }
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    Permissions.shared.refresh()
                    if granted { self?.show(onPayload: onPayload) }
                }
            }
            return
        default:
            Permissions.shared.requestCamera()
            return
        }
        self.onPayload = onPayload
        finished = false
        let panel = ensurePanel()
        startSession()
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        stopSession()
        panel?.orderOut(nil)
        onPayload = nil
    }

    // MARK: - Session

    private func startSession() {
        guard session == nil else { return }
        let session = AVCaptureSession()
        session.sessionPreset = .high
        self.session = session
        previewLayer?.session = session
        let output = AVCaptureMetadataOutput()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            session.beginConfiguration()
            if let device = AVCaptureDevice.default(for: .video),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                if output.availableMetadataObjectTypes.contains(.qr) {
                    output.metadataObjectTypes = [.qr]
                }
            }
            session.commitConfiguration()
            session.startRunning()
        }
    }

    private func stopSession() {
        guard let session else { return }
        self.session = nil
        sessionQueue.async {
            session.stopRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !finished else { return }
        let payloads = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
        guard let payload = payloads.first(where: { $0.lowercased().hasPrefix("otpauth") }) ?? payloads.first
        else { return }
        finished = true
        let handler = onPayload
        hide()
        handler?(payload)
    }

    // MARK: - Panel

    private final class ScannerPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = ScannerPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
                                 styleMask: [.titled, .closable, .utilityWindow],
                                 backing: .buffered,
                                 defer: false)
        panel.title = strings.scanCamera
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        let layer = AVCaptureVideoPreviewLayer()
        layer.videoGravity = .resizeAspectFill
        layer.frame = container.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        container.layer?.addSublayer(layer)
        previewLayer = layer

        let caption = NSTextField(labelWithString: strings.scanCameraHint)
        caption.textColor = .white
        caption.font = .systemFont(ofSize: 12)
        caption.alignment = .center
        caption.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(caption)
        NSLayoutConstraint.activate([
            caption.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            caption.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])
        panel.contentView = container
        panel.delegate = self
        self.panel = panel
        return panel
    }
}

extension AuthenticatorCameraScanner: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        stopSession()
        onPayload = nil
    }
}
