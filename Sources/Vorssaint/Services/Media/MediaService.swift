// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import Vision

struct MediaVideoOptions: Equatable {
    var start: Double
    var end: Double
    var quality: Double
    var maxDimension: Int
    var fps: Double
    var keepAudio: Bool
    var codec: MediaVideoCodec
}

struct MediaGIFOptions: Equatable {
    var start: Double
    var end: Double
    var quality: Double
    var width: Int
    var fps: Double
    var loops: Bool
}

struct MediaImageOptions: Equatable {
    var quality: Double
    var maxDimension: Int
    var format: MediaImageFormat
    var stripMetadata: Bool
}

struct MediaTextOptions: Equatable {
    var accurate: Bool
    var languageCorrection: Bool
    var recognitionLanguages: [String]
}

struct MediaResult: Identifiable, Equatable {
    let id = UUID()
    let tool: MediaTool
    let inputURL: URL
    let outputURL: URL?
    let originalBytes: Int64
    let outputBytes: Int64
    let elapsed: TimeInterval
    let text: String?
}

enum MediaFailure: Equatable {
    case noInput
    case noVideoTrack
    case sameOutput
    case unsupported
    case cancelled
    case failed(String)
}

enum MediaServiceState: Equatable {
    case idle
    case ready
    case running(progress: Double, message: String)
    case completed(MediaResult)
    case failed(MediaFailure)
    case cancelled
}

private final class MediaCancellationToken {
    private let lock = NSLock()
    private var _isCancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }

    func cancel() {
        lock.lock()
        _isCancelled = true
        lock.unlock()
    }
}

final class MediaService: ObservableObject {
    static let shared = MediaService()

    @Published private(set) var state: MediaServiceState = .idle

    private let queue = DispatchQueue(label: "com.vorssaint.media", qos: .userInitiated)
    private let lock = NSLock()
    private var operationID: UUID?
    private var token: MediaCancellationToken?
    private var activeProcess: Process?
    private var activeVisionRequest: VNRequest?

    private init() {}

    func reset() {
        cancel()
        publish(.idle)
    }

    func cancel() {
        lock.lock()
        token?.cancel()
        activeProcess?.terminate()
        activeVisionRequest?.cancel()
        operationID = nil
        activeProcess = nil
        activeVisionRequest = nil
        lock.unlock()
        publish(.cancelled)
    }

    func compressVideo(inputURL: URL, outputURL: URL, options: MediaVideoOptions) {
        run(.videoCompressor) { [weak self] id, token in
            try self?.compressVideoWork(inputURL: inputURL, outputURL: outputURL, options: options,
                                        operationID: id, token: token)
        }
    }

    func makeGIF(inputURL: URL, outputURL: URL, options: MediaGIFOptions) {
        run(.gifMaker) { [weak self] id, token in
            try self?.makeGIFWork(inputURL: inputURL, outputURL: outputURL, options: options,
                                  operationID: id, token: token)
        }
    }

    func compressImage(inputURL: URL, outputURL: URL, options: MediaImageOptions) {
        run(.imageCompressor) { [weak self] id, token in
            try self?.compressImageWork(inputURL: inputURL, outputURL: outputURL, options: options,
                                        operationID: id, token: token)
        }
    }

    func extractText(inputURL: URL, outputURL: URL?, options: MediaTextOptions) {
        run(.textExtractor) { [weak self] id, token in
            try self?.extractTextWork(inputURL: inputURL, outputURL: outputURL, options: options,
                                      operationID: id, token: token)
        }
    }

    private func run(_ tool: MediaTool,
                     _ work: @escaping (UUID, MediaCancellationToken) throws -> Void) {
        let id = UUID()
        let token = MediaCancellationToken()
        lock.lock()
        self.operationID = id
        self.token = token
        self.activeProcess = nil
        self.activeVisionRequest = nil
        lock.unlock()
        publish(.running(progress: 0, message: tool.rawValue), operationID: id)

        queue.async { [weak self] in
            do {
                try work(id, token)
            } catch let failure as MediaFailureBox {
                self?.publish(.failed(failure.failure), operationID: id)
            } catch {
                if token.isCancelled {
                    self?.publish(.cancelled, operationID: id)
                } else {
                    self?.publish(.failed(.failed(error.localizedDescription)), operationID: id)
                }
            }
        }
    }

    private func compressVideoWork(inputURL: URL, outputURL: URL, options: MediaVideoOptions,
                                   operationID: UUID, token: MediaCancellationToken) throws {
        let started = Date()
        try prepareOutput(inputURL: inputURL, outputURL: outputURL)
        let asset = AVURLAsset(url: inputURL)
        let metadata = try loadVideoMetadata(from: asset, includeDisplaySize: true)
        let trim = MediaSupport.sanitizedTrim(start: options.start,
                                              end: options.end,
                                              assetDuration: metadata.duration)
        guard trim.duration > 0 else { throw MediaFailureBox(.unsupported) }

        let outSize = MediaSupport.scaledVideoSize(source: metadata.displaySize,
                                                   maxDimension: options.maxDimension)
        let preset = avconvertPreset(codec: options.codec,
                                     maxDimension: max(Int(outSize.width), Int(outSize.height)),
                                     quality: options.quality)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/avconvert")
        process.arguments = [
            "--source", inputURL.path,
            "--preset", preset,
            "--output", outputURL.path,
            "--replace",
            "--progress",
            "--start", String(format: "%.3f", trim.start),
            "--duration", String(format: "%.3f", trim.duration),
        ]
        if options.quality >= 0.82 {
            process.arguments?.append("--multiPass")
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        var log = ""
        let logLock = NSLock()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            logLock.lock()
            log.append(chunk)
            if log.count > 8_000 { log.removeFirst(log.count - 8_000) }
            logLock.unlock()
        }
        setActive(process: process)
        try process.run()
        while process.isRunning {
            try checkCancellation(token)
            let elapsed = Date().timeIntervalSince(started)
            let estimate = max(1, trim.duration * 0.75)
            publish(.running(progress: min(0.95, elapsed / estimate), message: "video"), operationID: operationID)
            Thread.sleep(forTimeInterval: 0.08)
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        if token.isCancelled {
            process.terminate()
            throw MediaFailureBox(.cancelled)
        }
        guard process.terminationStatus == 0 else {
            logLock.lock()
            let message = log.trimmingCharacters(in: .whitespacesAndNewlines)
            logLock.unlock()
            throw MediaFailureBox(.failed(message.isEmpty ? "avconvert failed." : message))
        }
        publish(.running(progress: 1, message: "video"), operationID: operationID)
        let result = MediaResult(tool: .videoCompressor,
                                 inputURL: inputURL,
                                 outputURL: outputURL,
                                 originalBytes: fileSize(inputURL),
                                 outputBytes: fileSize(outputURL),
                                 elapsed: Date().timeIntervalSince(started),
                                 text: nil)
        publish(.completed(result), operationID: operationID)
    }

    private func makeGIFWork(inputURL: URL, outputURL: URL, options: MediaGIFOptions,
                             operationID: UUID, token: MediaCancellationToken) throws {
        let started = Date()
        try prepareOutput(inputURL: inputURL, outputURL: outputURL)
        let asset = AVURLAsset(url: inputURL)
        let metadata = try loadVideoMetadata(from: asset, includeDisplaySize: false)
        let trim = MediaSupport.sanitizedTrim(start: options.start,
                                              end: options.end,
                                              assetDuration: metadata.duration)
        guard trim.duration > 0 else { throw MediaFailureBox(.unsupported) }
        let fps = MediaSupport.sanitizedFPS(options.fps, fallback: 12, maxFPS: 30)
        let frameCount = max(1, Int((trim.duration * fps).rounded(.up)))
        let delay = 1 / fps
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL,
                                                               UTType.gif.identifier as CFString,
                                                               frameCount,
                                                               nil) else {
            throw MediaFailureBox(.unsupported)
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: options.loops ? 0 : 1,
            ],
        ] as CFDictionary)

        for index in 0..<frameCount {
            try checkCancellation(token)
            let second = min(trim.end, trim.start + Double(index) / fps)
            let image = try generateCGImage(from: generator, at: seconds(second))
            let resized = resize(image, maxDimension: options.width) ?? image
            CGImageDestinationAddImage(destination, resized, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                ],
                kCGImageDestinationLossyCompressionQuality: MediaSupport.sanitizedQuality(options.quality),
            ] as CFDictionary)
            publish(.running(progress: Double(index + 1) / Double(frameCount), message: "gif"),
                    operationID: operationID)
        }

        guard CGImageDestinationFinalize(destination) else { throw MediaFailureBox(.unsupported) }
        let result = MediaResult(tool: .gifMaker,
                                 inputURL: inputURL,
                                 outputURL: outputURL,
                                 originalBytes: fileSize(inputURL),
                                 outputBytes: fileSize(outputURL),
                                 elapsed: Date().timeIntervalSince(started),
                                 text: nil)
        publish(.completed(result), operationID: operationID)
    }

    private func compressImageWork(inputURL: URL, outputURL: URL, options: MediaImageOptions,
                                   operationID: UUID, token: MediaCancellationToken) throws {
        let started = Date()
        try prepareOutput(inputURL: inputURL, outputURL: outputURL)
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw MediaFailureBox(.unsupported)
        }
        try checkCancellation(token)
        let maxPixel = MediaSupport.sanitizedPixelDimension(Double(options.maxDimension), fallback: 1600)
        let imageOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, imageOptions as CFDictionary) else {
            throw MediaFailureBox(.unsupported)
        }
        let type = typeIdentifier(for: options.format)
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, type as CFString, 1, nil) else {
            throw MediaFailureBox(.unsupported)
        }
        var outputProperties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: MediaSupport.sanitizedQuality(options.quality),
        ]
        if !options.stripMetadata {
            outputProperties.merge(properties) { current, _ in current }
        }
        CGImageDestinationAddImage(destination, image, outputProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw MediaFailureBox(.unsupported) }
        let result = MediaResult(tool: .imageCompressor,
                                 inputURL: inputURL,
                                 outputURL: outputURL,
                                 originalBytes: fileSize(inputURL),
                                 outputBytes: fileSize(outputURL),
                                 elapsed: Date().timeIntervalSince(started),
                                 text: nil)
        publish(.completed(result), operationID: operationID)
    }

    private func extractTextWork(inputURL: URL, outputURL: URL?, options: MediaTextOptions,
                                 operationID: UUID, token: MediaCancellationToken) throws {
        let started = Date()
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else {
            throw MediaFailureBox(.unsupported)
        }
        try checkCancellation(token)
        publish(.running(progress: 0.2, message: "ocr"), operationID: operationID)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = options.accurate ? .accurate : .fast
        request.usesLanguageCorrection = options.languageCorrection
        if let supported = try? request.supportedRecognitionLanguages(), !supported.isEmpty {
            let desired = options.recognitionLanguages.filter { supported.contains($0) }
            if !desired.isEmpty { request.recognitionLanguages = desired }
        }
        setActiveVisionRequest(request)
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        try checkCancellation(token)
        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        if let outputURL {
            try prepareTextOutput(inputURL: inputURL, outputURL: outputURL)
            try text.write(to: outputURL, atomically: true, encoding: .utf8)
        }
        let result = MediaResult(tool: .textExtractor,
                                 inputURL: inputURL,
                                 outputURL: outputURL,
                                 originalBytes: fileSize(inputURL),
                                 outputBytes: outputURL.map(fileSize) ?? Int64(text.utf8.count),
                                 elapsed: Date().timeIntervalSince(started),
                                 text: text)
        publish(.completed(result), operationID: operationID)
    }

    private func prepareOutput(inputURL: URL, outputURL: URL) throws {
        guard inputURL.standardizedFileURL.path != outputURL.standardizedFileURL.path else {
            throw MediaFailureBox(.sameOutput)
        }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
    }

    private func prepareTextOutput(inputURL: URL, outputURL: URL) throws {
        guard inputURL.standardizedFileURL.path != outputURL.standardizedFileURL.path else {
            throw MediaFailureBox(.sameOutput)
        }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
    }

    private func resize(_ image: CGImage, maxDimension: Int) -> CGImage? {
        let size = MediaSupport.scaledEvenSize(source: CGSize(width: image.width, height: image.height),
                                               maxDimension: maxDimension)
        guard Int(size.width) != image.width || Int(size.height) != image.height else { return image }
        guard let context = CGContext(data: nil,
                                      width: Int(size.width),
                                      height: Int(size.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    private func avconvertPreset(codec: MediaVideoCodec, maxDimension: Int, quality: Double) -> String {
        let quality = MediaSupport.sanitizedQuality(quality)
        if quality < 0.4 {
            return "PresetLowQuality"
        }
        if codec == .hevc {
            if quality >= 0.82 { return "PresetHEVCHighestQuality" }
            if maxDimension <= 1920 { return "PresetHEVC1920x1080" }
            if maxDimension <= 3840 { return "PresetHEVC3840x2160" }
            return "PresetHEVCHighestQuality"
        }
        if quality >= 0.82 { return "PresetHighestQuality" }
        if quality < 0.58 { return "PresetMediumQuality" }
        if maxDimension <= 640 { return "Preset640x480" }
        if maxDimension <= 960 { return "Preset960x540" }
        if maxDimension <= 1280 { return "Preset1280x720" }
        if maxDimension <= 1920 { return "Preset1920x1080" }
        return "PresetHighestQuality"
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: 600)
    }

    private struct VideoMetadata {
        let duration: Double
        let displaySize: CGSize
    }

    private func loadVideoMetadata(from asset: AVAsset,
                                   includeDisplaySize: Bool) throws -> VideoMetadata {
        try runAsync {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { throw MediaFailureBox(.noVideoTrack) }

            let duration = try await asset.load(.duration).seconds
            guard includeDisplaySize else {
                return VideoMetadata(duration: duration, displaySize: .zero)
            }

            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            let transformed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
            let displaySize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
            return VideoMetadata(duration: duration, displaySize: displaySize)
        }
    }

    private func generateCGImage(from generator: AVAssetImageGenerator,
                                 at time: CMTime) throws -> CGImage {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<CGImage, Error>?

        generator.generateCGImageAsynchronously(for: time) { image, _, error in
            if let image {
                result = .success(image)
            } else {
                result = .failure(error ?? MediaFailureBox(.failed("Video frame unavailable.")))
            }
            semaphore.signal()
        }

        semaphore.wait()
        guard let result else {
            throw MediaFailureBox(.failed("Video frame unavailable."))
        }
        return try result.get()
    }

    private func runAsync<T>(_ operation: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?

        Task {
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()
        guard let result else {
            throw MediaFailureBox(.failed("Video metadata unavailable."))
        }
        return try result.get()
    }

    private func typeIdentifier(for format: MediaImageFormat) -> String {
        switch format {
        case .jpeg: return UTType.jpeg.identifier
        case .heic: return UTType.heic.identifier
        case .png: return UTType.png.identifier
        }
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func checkCancellation(_ token: MediaCancellationToken) throws {
        if token.isCancelled { throw MediaFailureBox(.cancelled) }
    }

    private func setActive(process: Process) {
        lock.lock()
        activeProcess = process
        lock.unlock()
    }

    private func setActiveVisionRequest(_ request: VNRequest) {
        lock.lock()
        activeVisionRequest = request
        lock.unlock()
    }

    private func clearOperation(_ id: UUID) {
        lock.lock()
        if operationID == id {
            operationID = nil
            token = nil
            activeProcess = nil
            activeVisionRequest = nil
        }
        lock.unlock()
    }

    private func publish(_ state: MediaServiceState, operationID: UUID? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let operationID {
                self.lock.lock()
                let isCurrent = self.operationID == operationID
                self.lock.unlock()
                guard isCurrent else { return }
            }
            self.state = state
            if let operationID, state.isTerminal {
                self.clearOperation(operationID)
            }
        }
    }
}

private extension MediaServiceState {
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .idle, .ready, .running:
            return false
        }
    }
}

private struct MediaFailureBox: Error {
    let failure: MediaFailure

    init(_ failure: MediaFailure) {
        self.failure = failure
    }
}
