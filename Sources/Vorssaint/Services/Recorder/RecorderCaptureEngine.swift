// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import AppKit
import ScreenCaptureKit

/// Why a recording could not start, or why one ended on its own. Kept
/// separate from the system error so the surfaces have one small thing to
/// switch over instead of a numeric table.
enum RecorderFailure: Equatable {
    case permissionDenied
    case noContent
    case streamFailed
    case writerFailed
    case diskFull
}

protocol RecorderCaptureEngineDelegate: AnyObject {
    /// Called on the engine's own serial queue, never on the main thread.
    func captureEngine(_ engine: RecorderCaptureEngine,
                       didOutput sampleBuffer: CMSampleBuffer,
                       of kind: RecorderCaptureEngine.Kind)
    /// The stream ended without being asked to. Delivered on the main thread.
    func captureEngine(_ engine: RecorderCaptureEngine, didStopWith failure: RecorderFailure)
}

/// Owns the ScreenCaptureKit stream and nothing else: it acquires pixels and
/// system audio and hands them over untouched. No compositing happens here,
/// because everything the editor can change has to stay changeable after the
/// recording ends.
final class RecorderCaptureEngine: NSObject {

    enum Kind {
        case video
        case systemAudio
    }

    weak var delegate: RecorderCaptureEngineDelegate?

    private let queue = DispatchQueue(label: "com.vorssaint.recorder.capture",
                                      qos: .userInitiated)
    private var stream: SCStream?
    private var stopping = false

    /// The clock the stream timestamps against, so a source that is not
    /// ScreenCaptureKit (the microphone) can be lined up with the video.
    private(set) var synchronizationClock: CMClock?

    /// True while pixels are being delivered. Read from the main thread.
    private(set) var isRunning = false

    // MARK: - Lifecycle

    /// Builds the filter and starts the stream. Only capture-time chrome is
    /// excluded, so ordinary Vorssaint windows can still be recorded.
    func start(region: RecorderSupport.Region,
               frameRate: Int,
               capturesSystemAudio: Bool,
               excludedWindowNumbers: [Int]) async -> RecorderFailure? {
        guard stream == nil else { return .streamFailed }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
        } catch {
            return Self.failure(for: error)
        }

        guard let filter = Self.filter(for: region,
                                       in: content,
                                       excluding: excludedWindowNumbers)
        else { return .noContent }

        let configuration = SCStreamConfiguration()
        configuration.width = Int(region.pixelRect.width)
        configuration.height = Int(region.pixelRect.height)
        configuration.minimumFrameInterval = CMTime(value: 1,
                                                    timescale: CMTimeScale(frameRate))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        // An independent window keeps the output dimensions chosen when the
        // recording starts. Scaling it into that output makes later window
        // resizes follow the recording instead of leaving an empty frame.
        configuration.scalesToFit = region.windowID != nil
        configuration.preservesAspectRatio = true
        configuration.captureResolution = .best
        // The pointer is drawn by us afterwards, from the track the sampler
        // keeps, so it can be smoothed and pressed. Leaving the system one in
        // the frame would put two pointers in the video.
        configuration.showsCursor = false
        configuration.shouldBeOpaque = true
        // Shadows belong to the desktop, not to the thing being recorded, and
        // they would be baked into the frame the background is drawn behind.
        configuration.ignoreShadowsDisplay = true
        configuration.ignoreShadowsSingleWindow = true
        if region.windowID == nil {
            configuration.sourceRect = Self.sourceRect(for: region)
        }
        if capturesSystemAudio {
            configuration.capturesAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            // A HUD of ours making a sound has no business in the recording.
            configuration.excludesCurrentProcessAudio = true
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            if capturesSystemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            }
            try await stream.startCapture()
        } catch {
            return Self.failure(for: error)
        }

        self.stream = stream
        synchronizationClock = stream.synchronizationClock
        isRunning = true
        return nil
    }

    /// Stops the stream and waits for it, so the writer can finish knowing no
    /// further buffer is on its way.
    func stop() async {
        guard let stream else { return }
        stopping = true
        isRunning = false
        self.stream = nil
        synchronizationClock = nil
        try? await stream.stopCapture()
        stopping = false
    }

    // MARK: - Filter

    private static func filter(for region: RecorderSupport.Region,
                               in content: SCShareableContent,
                               excluding windowNumbers: [Int]) -> SCContentFilter? {
        if let windowID = region.windowID,
           let window = content.windows.first(where: { $0.windowID == windowID }) {
            return SCContentFilter(desktopIndependentWindow: window)
        }
        guard let display = content.displays.first(where: { $0.displayID == region.displayID })
        else { return nil }
        // Only this recording's own chrome is left out, and it is named window
        // by window. Excluding the whole application would be simpler, and it
        // was wrong: it also removed the menu panel, the settings and the
        // command bar, which are exactly the things somebody records when they
        // want to show what the app does.
        let excluded = Set(windowNumbers.map { CGWindowID($0) })
        let chrome = content.windows.filter { excluded.contains($0.windowID) }
        return SCContentFilter(display: display, excludingWindows: chrome)
    }

    /// The recorded area inside the display, in points with a top-left origin,
    /// which is the space ScreenCaptureKit reads `sourceRect` in.
    private static func sourceRect(for region: RecorderSupport.Region) -> CGRect {
        let scale = region.scale > 0 ? region.scale : 1
        return CGRect(x: region.pixelRect.origin.x / scale,
                      y: region.pixelRect.origin.y / scale,
                      width: region.pixelRect.width / scale,
                      height: region.pixelRect.height / scale)
    }

    // MARK: - Errors

    private static func failure(for error: Error) -> RecorderFailure {
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain,
              let code = SCStreamError.Code(rawValue: nsError.code)
        else { return .streamFailed }
        switch code {
        case .userDeclined:
            return .permissionDenied
        case .noWindowList, .noDisplayList, .noCaptureSource:
            return .noContent
        default:
            return .streamFailed
        }
    }
}

// MARK: - Stream callbacks

extension RecorderCaptureEngine: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard !stopping, CMSampleBufferIsValid(sampleBuffer) else { return }
        switch type {
        case .screen:
            guard Self.carriesPixels(sampleBuffer) else { return }
            delegate?.captureEngine(self, didOutput: sampleBuffer, of: .video)
        case .audio:
            delegate?.captureEngine(self, didOutput: sampleBuffer, of: .systemAudio)
        default:
            break
        }
    }

    /// A screen buffer only counts when the display actually changed and the
    /// buffer really carries an image. Appending an idle or blank frame would
    /// fault the writer, and the recording is written at a variable rate on
    /// purpose, so a still screen costs nothing.
    private static func carriesPixels(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return false }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete || status == .started
    }
}

extension RecorderCaptureEngine: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard !stopping else { return }
        isRunning = false
        self.stream = nil
        let failure = Self.failure(for: error)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.captureEngine(self, didStopWith: failure)
        }
    }
}
