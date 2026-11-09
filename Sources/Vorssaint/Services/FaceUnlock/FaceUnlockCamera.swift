// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Derived from Glance (MIT, Copyright (c) Jonathan Zhou). See THIRD-PARTY-NOTICES.md.

@preconcurrency import AVFoundation
import AppKit
import Combine
import CoreImage

/// One frame from the camera. `source` is a lazy Core Image recipe, not
/// rendered pixels, so holding it costs nothing until a crop is drawn.
struct FaceUnlockFrame {
    let id: UInt64
    let image: CGImage
    let source: CIImage
    let sourceSize: CGSize
}

struct FaceUnlockCameraDevice: Identifiable, Hashable {
    let id: String // AVCaptureDevice.uniqueID
    let name: String
}

enum FaceUnlockCameraError: Equatable {
    case denied
    case restricted
    case noDevice
    case formatUnavailable
}

/// Owns the capture session while a scan or an enrollment is running, and
/// publishes the newest frame. The session runs only between `start()` and
/// `stop()`: the camera light is on exactly while Vorssaint is looking.
@MainActor
final class FaceUnlockCamera: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var currentFrame: FaceUnlockFrame?
    @Published private(set) var error: FaceUnlockCameraError?

    /// Exposed so a preview layer can attach to the same session.
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.vorssaint.utils.face-unlock.camera")
    private let publisher = FramePublisher()
    private var isConfigured = false
    private var currentInput: AVCaptureDeviceInput?

    override init() {
        super.init()
        publisher.owner = self
    }

    static func availableDevices() -> [FaceUnlockCameraDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified)
            .devices.map { FaceUnlockCameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// The chosen camera, else the Mac's own front camera, else anything.
    static func resolvedDevice(in defaults: UserDefaults = .standard) -> AVCaptureDevice? {
        if let id = defaults.string(forKey: DefaultsKey.faceUnlockCameraID), !id.isEmpty,
           let chosen = AVCaptureDevice(uniqueID: id) {
            return chosen
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
    }

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { error = .denied; return }
        case .restricted: error = .restricted; return
        default: error = .denied; return
        }
        error = nil
        configureIfNeeded()
        reconcileDevice()
        guard error == nil else { return }
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
        isRunning = true
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        isRunning = false
        currentFrame = nil
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        session.beginConfiguration()
        session.sessionPreset = .high
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(publisher, queue: sessionQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        session.commitConfiguration()
    }

    /// Run on every start, so a camera chosen in Settings applies at once.
    private func reconcileDevice() {
        guard let device = Self.resolvedDevice() else { error = .noDevice; return }
        guard device.uniqueID != currentInput?.device.uniqueID else { return }
        session.beginConfiguration()
        if let currentInput { session.removeInput(currentInput) }
        if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
            currentInput = input
            selectLargestFormat(of: device)
        } else {
            currentInput = nil
            error = .noDevice
        }
        session.commitConfiguration()
    }

    /// Detection works from a downscaled frame; the largest format only gives
    /// the liveness crops more detail to read.
    private func selectLargestFormat(of device: AVCaptureDevice) {
        let largest = device.formats.max { lhs, rhs in
            let l = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let r = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            return Int(l.width) * Int(l.height) < Int(r.width) * Int(r.height)
        }
        guard let largest else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = largest
            device.unlockForConfiguration()
        } catch {
            self.error = .formatUnavailable
        }
    }

    fileprivate func publish(_ frame: FaceUnlockFrame) {
        currentFrame = frame
    }

    /// A native resolution crop of `imageRect` (top-left origin, in the working
    /// frame's pixels), for the pixel detail the downscaled frame throws away.
    nonisolated static func renderCrop(from frame: FaceUnlockFrame, imageRect: CGRect,
                                       maxEdge: CGFloat = 448) -> CGImage? {
        let workingWidth = CGFloat(frame.image.width)
        let workingHeight = CGFloat(frame.image.height)
        guard workingWidth > 0, workingHeight > 0 else { return nil }
        let scaleX = frame.sourceSize.width / workingWidth
        let scaleY = frame.sourceSize.height / workingHeight

        // Widened so a device's edges are in the crop for the texture cues.
        let expanded = imageRect.insetBy(dx: -imageRect.width * 0.15, dy: -imageRect.height * 0.15)
        // From the top-left, y-down rect to Core Image's bottom-left, y-up.
        var native = CGRect(x: expanded.origin.x * scaleX,
                            y: frame.sourceSize.height - (expanded.origin.y + expanded.height) * scaleY,
                            width: expanded.width * scaleX, height: expanded.height * scaleY)
        native = native.intersection(CGRect(origin: .zero, size: frame.sourceSize))
        guard !native.isEmpty else { return nil }

        var cropped = frame.source.cropped(to: native)
            .transformed(by: CGAffineTransform(translationX: -native.minX, y: -native.minY))
        let longEdge = max(native.width, native.height)
        if longEdge > maxEdge {
            let scale = maxEdge / longEdge
            cropped = cropped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return cropContext.createCGImage(cropped, from: cropped.extent)
    }

    private nonisolated static let cropContext = CIContext()

    /// Sample buffers arrive on the session queue; convert there, then hop.
    private final class FramePublisher: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        weak var owner: FaceUnlockCamera?
        private let context = CIContext()
        private let maxLongEdge: CGFloat = 640
        private var nextID: UInt64 = 0

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                           from connection: AVCaptureConnection) {
            guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let source = CIImage(cvPixelBuffer: pixels)
            let size = source.extent.size
            var working = source
            let longEdge = max(working.extent.width, working.extent.height)
            if longEdge > maxLongEdge {
                let scale = maxLongEdge / longEdge
                working = working.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
            guard let image = context.createCGImage(working, from: working.extent) else { return }
            nextID &+= 1
            let frame = FaceUnlockFrame(id: nextID, image: image, source: source, sourceSize: size)
            Task { @MainActor [weak owner] in owner?.publish(frame) }
        }
    }
}
