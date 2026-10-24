// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import ScreenCaptureKit

/// The live picture of one pinned window: a ScreenCaptureKit stream of that
/// window alone, drawn into a sample-buffer layer the overlay hosts. The
/// stream delivers the window's own content even while other windows cover
/// it, which is what lets the overlay stand in for it.
///
/// Main thread, except the sample callback, which only hands frames to the
/// layer and counts them.
final class AlwaysOnTopCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let layer = AVSampleBufferDisplayLayer()

    /// Main thread, once per start, when the first frame is on screen.
    var onFirstFrame: (() -> Void)?
    /// Main thread: a started stream delivered nothing in time.
    var onStall: (() -> Void)?

    /// Whether the layer holds a frame. It keeps the last one after a stop,
    /// so a pin covered again shows something at once while the stream
    /// restarts.
    private(set) var hasFrame = false

    private let windowID: CGWindowID
    private let sampleQueue = DispatchQueue(label: "com.vorssaint.always-on-top.samples", qos: .userInteractive)
    private var stream: SCStream?
    private var starting = false
    private var wanted = false
    private var shareableWindow: SCWindow?
    private var pixelSize: (width: Int, height: Int) = (2, 2)
    private var awaitingFirstFrame = false
    private var stallCheck: DispatchWorkItem?
    private let frameLock = NSLock()
    private var frameDelivered = false

    init(windowID: CGWindowID) {
        self.windowID = windowID
        super.init()
        layer.videoGravity = .resize
    }

    func start(pixelSize: (width: Int, height: Int)) {
        wanted = true
        self.pixelSize = pixelSize
        guard stream == nil, !starting else { return }
        starting = true
        awaitingFirstFrame = true
        frameLock.withLock { frameDelivered = false }
        scheduleStallCheck()
        Task { @MainActor in
            defer { self.starting = false }
            do {
                if self.shareableWindow == nil {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                    self.shareableWindow = content.windows.first { $0.windowID == self.windowID }
                }
                guard let window = self.shareableWindow, self.wanted else { return }
                let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window),
                                      configuration: self.configuration(), delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.sampleQueue)
                try await stream.startCapture()
                guard self.wanted else {
                    try? await stream.stopCapture()
                    return
                }
                self.stream = stream
            } catch {
                // A window that left the shareable list since it was cached
                // is looked up again on the next start.
                self.shareableWindow = nil
            }
        }
    }

    func stop() {
        wanted = false
        awaitingFirstFrame = false
        stallCheck?.cancel()
        guard let stream else { return }
        self.stream = nil
        Task { try? await stream.stopCapture() }
    }

    func resize(pixelSize: (width: Int, height: Int)) {
        guard pixelSize != self.pixelSize else { return }
        self.pixelSize = pixelSize
        guard let stream else { return }
        let configuration = configuration()
        Task { try? await stream.updateConfiguration(configuration) }
    }

    private func configuration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = pixelSize.width
        configuration.height = pixelSize.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(AlwaysOnTopSupport.framesPerSecond))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.queueDepth = 4
        configuration.ignoreShadowsSingleWindow = true
        return configuration
    }

    private func scheduleStallCheck() {
        stallCheck?.cancel()
        let check = DispatchWorkItem { [weak self] in
            guard let self, self.wanted, !self.frameLock.withLock({ self.frameDelivered }) else { return }
            self.onStall?()
        }
        stallCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + AlwaysOnTopSupport.stallTimeout, execute: check)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer), Self.isCompleteFrame(sampleBuffer) else { return }
        Self.markForImmediateDisplay(sampleBuffer)
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sampleBuffer)
        let first = frameLock.withLock { () -> Bool in
            defer { frameDelivered = true }
            return !frameDelivered
        }
        guard first else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasFrame = true
            self.stallCheck?.cancel()
            guard self.awaitingFirstFrame else { return }
            self.awaitingFirstFrame = false
            self.onFirstFrame?()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.stream = nil
        }
    }

    /// Idle frames repeat the previous picture and carry no new pixels.
    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }

    /// Without this the layer waits for the buffer's presentation time
    /// against its own timebase, which a live stream never sets.
    private static func markForImmediateDisplay(_ sampleBuffer: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
              CFArrayGetCount(attachments) > 0 else { return }
        let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(dictionary,
                             Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                             Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }
}
