// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreImage

/// Each visible surface owns its streams. Ending one preview cannot stop the
/// switcher's or a detached panel's captures. No audio or cursor is captured.
final class LiveWindowPreviews {
    private var streams: [SCStream] = []
    private var outputs: [Output] = []
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func start(_ items: [SwitcherItem], excludedAppsKey: String, update: @escaping (CGWindowID, CGImage) -> Void) {
        stop()
        guard Permissions.shared.screenRecording, !WindowPreviewProvider.captureIsPaused(excludedAppsKey: excludedAppsKey), SessionActivity.shared.isActive else { return }
        let excluded = Set(Defaults.sanitizedBundleIdentifierList(UserDefaults.standard.stringArray(forKey: excludedAppsKey) ?? []))
        let eligible = items.filter { $0.previewWindowID != nil && !$0.isMinimized && !$0.isOnHiddenSpace && !excluded.contains(NSRunningApplication(processIdentifier: $0.pid)?.bundleIdentifier ?? "") }
        let requested = generation
        task = Task { @MainActor [weak self] in
            guard let self, let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false), self.generation == requested else { return }
            for item in eligible.prefix(12) {
                guard !Task.isCancelled, self.generation == requested, let id = item.previewWindowID,
                      let window = content.windows.first(where: { $0.windowID == id }) else { continue }
                let config = SCStreamConfiguration()
                let limit = min(max(DockOption.liveQuality.int, 320), 2048)
                let scale = min(2, Double(limit) / max(window.frame.width, window.frame.height, 1))
                config.width = max(1, Int(window.frame.width * scale)); config.height = max(1, Int(window.frame.height * scale))
                config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(min(max(DockOption.liveFrameRate.int, 5), 120)))
                config.pixelFormat = kCVPixelFormatType_32BGRA; config.showsCursor = false
                config.capturesAudio = false; config.queueDepth = 3
                let output = Output { [weak self] image in
                    guard let self, self.generation == requested else { return }
                    guard Permissions.shared.screenRecording, SessionActivity.shared.isActive,
                          !WindowPreviewProvider.captureIsPaused(excludedAppsKey: excludedAppsKey) else { self.stop(); return }
                    update(id, image)
                }
                let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: nil)
                do {
                    try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
                    try await stream.startCapture()
                    guard self.generation == requested, !Task.isCancelled else { try? await stream.stopCapture(); return }
                    self.streams.append(stream); self.outputs.append(output)
                } catch { continue }
            }
        }
    }
    func stop() {
        generation = UUID(); task?.cancel(); task = nil
        let old = streams; streams = []; outputs = []
        if !old.isEmpty { Task { for stream in old { try? await stream.stopCapture() } } }
    }
    deinit { stop() }

    private final class Output: NSObject, SCStreamOutput {
        let queue = DispatchQueue(label: "com.vorssaint.window-preview.frames", qos: .userInitiated)
        private static let sharedContext = CIContext(options: [.cacheIntermediates: false])
        private let update: (CGImage) -> Void
        private let lock = NSLock()
        private var pending: CGImage?
        private var scheduled = false
        init(update: @escaping (CGImage) -> Void) { self.update = update }
        func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
            guard type == .screen, CMSampleBufferIsValid(buffer),
                  let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
                  let pixel = CMSampleBufferGetImageBuffer(buffer) else { return }
            let image = CIImage(cvPixelBuffer: pixel)
            guard let cgImage = Self.sharedContext.createCGImage(image, from: image.extent) else { return }
            let schedule = lock.withLock { () -> Bool in
                pending = cgImage
                guard !scheduled else { return false }
                scheduled = true; return true
            }
            if schedule {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let image = self.lock.withLock { () -> CGImage? in
                        defer { self.pending = nil; self.scheduled = false }
                        return self.pending
                    }
                    if let image { self.update(image) }
                }
            }
        }
    }
}
