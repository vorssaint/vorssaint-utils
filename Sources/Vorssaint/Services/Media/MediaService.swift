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
    var sizing: MediaSizingMode = .resolution
    var targetBytes: Int64 = 0
}

struct MediaGIFOptions: Equatable {
    var start: Double
    var end: Double
    var quality: Double
    var width: Int
    var fps: Double
    var loops: Bool
    var sizing: MediaSizingMode = .resolution
    var targetBytes: Int64 = 0
}

struct MediaTextOptions: Equatable {
    var accurate: Bool
    var languageCorrection: Bool
    var recognitionLanguages: [String]
}

struct MediaImageBatchItemResult: Identifiable, Equatable {
    let id = UUID()
    let inputURL: URL
    let outputURL: URL?
    let originalBytes: Int64
    let outputBytes: Int64
    let failure: MediaFailure?
}

struct MediaResult: Identifiable, Equatable {
    let id = UUID()
    let tool: MediaTool
    let inputURL: URL
    let outputURL: URL?
    let outputURLs: [URL]
    let originalBytes: Int64
    let outputBytes: Int64
    let elapsed: TimeInterval
    let text: String?
    let imageBatchItems: [MediaImageBatchItemResult]

    init(tool: MediaTool,
         inputURL: URL,
         outputURL: URL?,
         outputURLs: [URL]? = nil,
         originalBytes: Int64,
         outputBytes: Int64,
         elapsed: TimeInterval,
         text: String?,
         imageBatchItems: [MediaImageBatchItemResult] = []) {
        self.tool = tool
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.outputURLs = outputURLs ?? outputURL.map { [$0] } ?? []
        self.originalBytes = originalBytes
        self.outputBytes = outputBytes
        self.elapsed = elapsed
        self.text = text
        self.imageBatchItems = imageBatchItems
    }

    var processedCount: Int {
        imageBatchItems.isEmpty ? (outputURL == nil && text == nil ? 0 : 1) : imageBatchItems.filter { $0.outputURL != nil }.count
    }

    var failedCount: Int {
        imageBatchItems.filter { $0.failure != nil }.count
    }
}

enum MediaFailure: Equatable {
    case noInput
    case noVideoTrack
    case sameOutput
    case unsupported
    case imageTooLarge
    case gifTooLong(maxSeconds: Int)
    case targetTooSmall
    case watermarkUnavailable
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
            try self?.processImagesWork(inputURLs: [inputURL],
                                        outputDirectory: outputURL.deletingLastPathComponent(),
                                        explicitOutputURL: outputURL,
                                        options: options,
                                        operationID: id,
                                        token: token)
        }
    }

    func processImages(inputURLs: [URL], outputDirectory: URL, options: MediaImageOptions) {
        run(.imageCompressor) { [weak self] id, token in
            try self?.processImagesWork(inputURLs: inputURLs,
                                        outputDirectory: outputDirectory,
                                        explicitOutputURL: nil,
                                        options: options,
                                        operationID: id,
                                        token: token)
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
        self.token?.cancel()
        self.activeProcess?.terminate()
        self.activeVisionRequest?.cancel()
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
        let stagedOutputURL = try stagedOutput(inputURL: inputURL, outputURL: outputURL)
        defer { MediaSupport.discardStagedOutput(stagedOutputURL) }
        let asset = AVURLAsset(url: inputURL)
        let metadata = try loadVideoMetadata(from: asset, includeGeometry: true, token: token)
        let trim = MediaSupport.sanitizedTrim(start: options.start,
                                              end: options.end,
                                              assetDuration: metadata.duration)
        guard trim.duration > 0 else { throw MediaFailureBox(.unsupported) }

        switch options.sizing {
        case .resolution:
            try convertVideo(inputURL: inputURL,
                             stagedOutputURL: stagedOutputURL,
                             trim: trim,
                             options: options,
                             displaySize: metadata.displaySize,
                             started: started,
                             operationID: operationID,
                             token: token)
        case .targetSize:
            try encodeVideoToTargetSize(asset: asset,
                                        geometry: metadata.geometry,
                                        stagedOutputURL: stagedOutputURL,
                                        trim: trim,
                                        targetBytes: options.targetBytes,
                                        operationID: operationID,
                                        token: token)
        }

        try commit(stagedOutputURL, at: outputURL, operationID: operationID, token: token)
        MediaSupport.makeVisibleIfNeeded(outputURL)
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

    private func convertVideo(inputURL: URL,
                              stagedOutputURL: URL,
                              trim: MediaTrimRange,
                              options: MediaVideoOptions,
                              displaySize: CGSize,
                              started: Date,
                              operationID: UUID,
                              token: MediaCancellationToken) throws {
        let outSize = MediaSupport.scaledVideoSize(source: displaySize,
                                                   maxDimension: options.maxDimension)
        let preset = avconvertPreset(codec: options.codec,
                                     maxDimension: max(Int(outSize.width), Int(outSize.height)),
                                     quality: options.quality)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/avconvert")
        process.arguments = [
            "--source", inputURL.path,
            "--preset", preset,
            "--output", stagedOutputURL.path,
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
        defer {
            pipe.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
        }
        try launch(process: process, operationID: operationID, token: token)
        while process.isRunning {
            try checkCancellation(token)
            let elapsed = Date().timeIntervalSince(started)
            let estimate = max(1, trim.duration * 0.75)
            publish(.running(progress: min(0.95, elapsed / estimate), message: "video"), operationID: operationID)
            Thread.sleep(forTimeInterval: 0.08)
        }
        if token.isCancelled {
            throw MediaFailureBox(.cancelled)
        }
        guard process.terminationStatus == 0 else {
            logLock.lock()
            let message = log.trimmingCharacters(in: .whitespacesAndNewlines)
            logLock.unlock()
            throw MediaFailureBox(.failed(message.isEmpty ? "avconvert failed." : message))
        }
    }

    private func encodeVideoToTargetSize(asset: AVAsset,
                                         geometry: VideoGeometry?,
                                         stagedOutputURL: URL,
                                         trim: MediaTrimRange,
                                         targetBytes: Int64,
                                         operationID: UUID,
                                         token: MediaCancellationToken) throws {
        guard let geometry else { throw MediaFailureBox(.noVideoTrack) }
        let source = MediaVideoTargetEncoder.Source(asset: asset,
                                                    videoTrack: geometry.videoTrack,
                                                    audioTracks: geometry.audioTracks,
                                                    naturalSize: geometry.naturalSize,
                                                    preferredTransform: geometry.preferredTransform,
                                                    frameRate: geometry.frameRate)
        var publishedPercent = -1
        do {
            _ = try MediaVideoTargetEncoder.encode(
                source: source,
                trim: trim,
                targetBytes: targetBytes,
                destination: stagedOutputURL,
                isCancelled: { token.isCancelled },
                progress: { value in
                    // The encoder reports every frame, which would put thousands
                    // of hops on the main queue for one conversion.
                    let percent = Int(value * 100)
                    guard percent != publishedPercent else { return }
                    publishedPercent = percent
                    self.publish(.running(progress: value, message: "video"),
                                 operationID: operationID)
                })
        } catch let error as MediaVideoTargetEncoder.EncodeError {
            throw MediaFailureBox(mediaFailure(for: error))
        }
    }

    private func mediaFailure(for error: MediaVideoTargetEncoder.EncodeError) -> MediaFailure {
        switch error {
        case .unsupported: return .unsupported
        case .targetTooSmall: return .targetTooSmall
        case .cancelled: return .cancelled
        case let .failed(message): return .failed(message)
        }
    }

    private func makeGIFWork(inputURL: URL, outputURL: URL, options: MediaGIFOptions,
                             operationID: UUID, token: MediaCancellationToken) throws {
        let started = Date()
        let stagedOutputURL = try stagedOutput(inputURL: inputURL, outputURL: outputURL)
        defer { MediaSupport.discardStagedOutput(stagedOutputURL) }
        let asset = AVURLAsset(url: inputURL)
        let targeted = options.sizing == .targetSize
        let metadata = try loadVideoMetadata(from: asset, includeGeometry: targeted, token: token)
        let trim = MediaSupport.sanitizedTrim(start: options.start,
                                              end: options.end,
                                              assetDuration: metadata.duration)
        guard trim.duration > 0 else { throw MediaFailureBox(.unsupported) }

        // A GIF has no bitrate to aim at, so a target size can only be reached
        // by measuring what a pass produced and shrinking what feeds the next
        // one. Aiming starts from the source itself rather than from the width
        // the resolution mode last used, so the result is the largest GIF that
        // fits instead of the one that happened to be configured.
        var width = targeted
            ? MediaSupport.targetGIFStartWidth(sourceWidth: metadata.displaySize.width)
            : options.width
        var fps = targeted
            ? MediaSupport.targetGIFStartFPS(duration: trim.duration)
            : MediaSupport.sanitizedFPS(options.fps, fallback: 12, maxFPS: 30)
        var pass = 0

        while true {
            try writeGIF(asset: asset,
                         stagedOutputURL: stagedOutputURL,
                         trim: trim,
                         width: width,
                         fps: fps,
                         options: options,
                         operationID: operationID,
                         token: token)
            guard targeted, fileSize(stagedOutputURL) > options.targetBytes else { break }
            pass += 1
            guard pass < MediaSupport.maximumTargetGIFPasses,
                  let plan = MediaSupport.gifSizePlan(width: width,
                                                      fps: fps,
                                                      actualBytes: fileSize(stagedOutputURL),
                                                      targetBytes: options.targetBytes)
            else { throw MediaFailureBox(.targetTooSmall) }
            width = plan.width
            fps = plan.fps
        }

        try commit(stagedOutputURL, at: outputURL, operationID: operationID, token: token)
        MediaSupport.makeVisibleIfNeeded(outputURL)
        let result = MediaResult(tool: .gifMaker,
                                 inputURL: inputURL,
                                 outputURL: outputURL,
                                 originalBytes: fileSize(inputURL),
                                 outputBytes: fileSize(outputURL),
                                 elapsed: Date().timeIntervalSince(started),
                                 text: nil)
        publish(.completed(result), operationID: operationID)
    }

    private func writeGIF(asset: AVAsset,
                          stagedOutputURL: URL,
                          trim: MediaTrimRange,
                          width: Int,
                          fps: Double,
                          options: MediaGIFOptions,
                          operationID: UUID,
                          token: MediaCancellationToken) throws {
        guard let frameCount = MediaSupport.safeGIFFrameCount(duration: trim.duration, fps: fps) else {
            throw MediaFailureBox(.gifTooLong(maxSeconds: MediaSupport.maximumGIFDuration(fps: fps)))
        }
        let delay = 1 / fps
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let maximumFrameDimension = CGFloat(max(1, width))
        generator.maximumSize = CGSize(width: maximumFrameDimension, height: maximumFrameDimension)

        try? FileManager.default.removeItem(at: stagedOutputURL)
        guard let destination = CGImageDestinationCreateWithURL(stagedOutputURL as CFURL,
                                                               UTType.gif.identifier as CFString,
                                                               frameCount,
                                                               nil) else {
            throw MediaFailureBox(.unsupported)
        }
        if let loopCount = MediaSupport.gifLoopCount(loops: options.loops) {
            CGImageDestinationSetProperties(destination, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFLoopCount: loopCount,
                ],
            ] as CFDictionary)
        }

        for index in 0..<frameCount {
            try checkCancellation(token)
            let second = min(trim.end, trim.start + Double(index) / fps)
            let image = try generateCGImage(from: generator, at: seconds(second), token: token)
            let resized = resize(image, maxDimension: width) ?? image
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
    }

    private func processImagesWork(inputURLs: [URL],
                                   outputDirectory: URL,
                                   explicitOutputURL: URL?,
                                   options: MediaImageOptions,
                                   operationID: UUID,
                                   token: MediaCancellationToken) throws {
        let started = Date()
        let inputs = inputURLs.filter { !$0.path.isEmpty }
        guard !inputs.isEmpty else { throw MediaFailureBox(.noInput) }
        if explicitOutputURL == nil {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }

        var itemResults: [MediaImageBatchItemResult] = []
        var outputURLs: [URL] = []
        var reservedOutputPaths = Set<String>()
        var originalBytes: Int64 = 0
        var outputBytes: Int64 = 0
        let watermarkLogo: CGImage?
        if options.watermark.usesLogo {
            guard let logo = MediaSupport.watermarkLogo(atPath: options.watermark.logoPath) else {
                throw MediaFailureBox(.watermarkUnavailable)
            }
            watermarkLogo = logo
        } else {
            watermarkLogo = nil
        }

        for (offset, inputURL) in inputs.enumerated() {
            try checkCancellation(token)
            let inputBytes = fileSize(inputURL)
            do {
                let prepared = try makeProcessedImage(inputURL: inputURL,
                                                      options: options,
                                                      watermarkLogo: watermarkLogo,
                                                      token: token)
                let outputURL = explicitOutputURL ?? MediaSupport.imageOutputURL(for: inputURL,
                                                                                 outputDirectory: outputDirectory,
                                                                                 options: options,
                                                                                 index: offset + 1,
                                                                                 outputSize: prepared.size,
                                                                                 reservedPaths: reservedOutputPaths)
                reservedOutputPaths.insert(outputURL.standardizedFileURL.path)
                let stagedOutputURL = try stagedOutput(inputURL: inputURL, outputURL: outputURL)
                defer { MediaSupport.discardStagedOutput(stagedOutputURL) }
                try writeImage(prepared.image,
                               properties: prepared.properties,
                               outputURL: stagedOutputURL,
                               options: options)
                try commit(stagedOutputURL, at: outputURL, operationID: operationID, token: token)
                MediaSupport.makeVisibleIfNeeded(outputURL)
                preserveModificationDateIfNeeded(from: inputURL, to: outputURL, options: options)
                let itemOutputBytes = fileSize(outputURL)
                originalBytes += inputBytes
                outputBytes += itemOutputBytes
                outputURLs.append(outputURL)
                itemResults.append(MediaImageBatchItemResult(inputURL: inputURL,
                                                             outputURL: outputURL,
                                                             originalBytes: inputBytes,
                                                             outputBytes: itemOutputBytes,
                                                             failure: nil))
            } catch let failure as MediaFailureBox {
                if inputs.count == 1 { throw failure }
                itemResults.append(MediaImageBatchItemResult(inputURL: inputURL,
                                                             outputURL: nil,
                                                             originalBytes: inputBytes,
                                                             outputBytes: 0,
                                                             failure: failure.failure))
            } catch {
                if inputs.count == 1 { throw error }
                itemResults.append(MediaImageBatchItemResult(inputURL: inputURL,
                                                             outputURL: nil,
                                                             originalBytes: inputBytes,
                                                             outputBytes: 0,
                                                             failure: .failed(error.localizedDescription)))
            }
            publish(.running(progress: Double(offset + 1) / Double(inputs.count), message: "image"),
                    operationID: operationID)
        }

        guard !outputURLs.isEmpty else {
            throw MediaFailureBox(itemResults.compactMap(\.failure).first ?? .unsupported)
        }

        let result = MediaResult(tool: .imageCompressor,
                                 inputURL: inputs[0],
                                 outputURL: outputURLs.first,
                                 outputURLs: outputURLs,
                                 originalBytes: originalBytes,
                                 outputBytes: outputBytes,
                                 elapsed: Date().timeIntervalSince(started),
                                 text: nil,
                                 imageBatchItems: itemResults)
        publish(.completed(result), operationID: operationID)
    }

    private struct PreparedImage {
        let image: CGImage
        let properties: [CFString: Any]
        let size: CGSize
    }

    private func makeProcessedImage(inputURL: URL,
                                    options: MediaImageOptions,
                                    watermarkLogo: CGImage?,
                                    token: MediaCancellationToken) throws -> PreparedImage {
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw MediaFailureBox(.unsupported)
        }
        try checkCancellation(token)
        guard let sourceSize = MediaSupport.imageDisplaySize(properties: properties) else {
            throw MediaFailureBox(.unsupported)
        }
        let expectedSize = options.resizeMode.targetSize(for: sourceSize)
        guard MediaSupport.imageRenderSizeIsSafe(expectedSize) else {
            throw MediaFailureBox(.imageTooLarge)
        }
        guard let maxPixel = MediaSupport.imageDecodeMaxPixel(sourceSize: sourceSize,
                                                              targetSize: expectedSize,
                                                              resizeMode: options.resizeMode) else {
            throw MediaFailureBox(.imageTooLarge)
        }
        let imageOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let sourceImage = CGImageSourceCreateThumbnailAtIndex(source, 0, imageOptions as CFDictionary) else {
            throw MediaFailureBox(.unsupported)
        }
        let targetSize = options.resizeMode.targetSize(
            for: CGSize(width: sourceImage.width, height: sourceImage.height)
        )
        guard MediaSupport.imageRenderSizeIsSafe(targetSize) else {
            throw MediaFailureBox(.imageTooLarge)
        }
        guard let image = renderImage(sourceImage,
                                      targetSize: targetSize,
                                      resizeMode: options.resizeMode,
                                      watermark: options.watermark,
                                      watermarkLogo: watermarkLogo,
                                      background: options.background,
                                      forceOpaque: options.format == .jpeg || options.format == .pdf) else {
            throw MediaFailureBox(.unsupported)
        }
        return PreparedImage(image: image,
                             properties: properties,
                             size: CGSize(width: image.width, height: image.height))
    }

    private func writeImage(_ image: CGImage,
                            properties: [CFString: Any],
                            outputURL: URL,
                            options: MediaImageOptions) throws {
        if options.format == .pdf {
            try writePDF(image: image, outputURL: outputURL,
                         quality: MediaSupport.sanitizedQuality(options.quality))
        } else {
            let type = typeIdentifier(for: options.format)
            guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, type as CFString, 1, nil) else {
                throw MediaFailureBox(.unsupported)
            }
            var outputProperties: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: MediaSupport.sanitizedQuality(options.quality),
            ]
            if !options.stripMetadata {
                outputProperties.merge(sanitizedImageProperties(properties, image: image)) { current, _ in current }
            }
            CGImageDestinationAddImage(destination, image, outputProperties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw MediaFailureBox(.unsupported) }
        }
    }

    private func extractTextWork(inputURL: URL, outputURL: URL?, options: MediaTextOptions,
                                 operationID: UUID, token: MediaCancellationToken) throws {
        let started = Date()
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let sourceSize = MediaSupport.imageDisplaySize(properties: properties) else {
            throw MediaFailureBox(.unsupported)
        }
        guard MediaSupport.imageRenderSizeIsSafe(sourceSize) else {
            throw MediaFailureBox(.imageTooLarge)
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, [
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
        try setActiveVisionRequest(request, operationID: operationID, token: token)
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        try checkCancellation(token)
        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        if let outputURL {
            let stagedOutputURL = try stagedOutput(inputURL: inputURL, outputURL: outputURL)
            defer { MediaSupport.discardStagedOutput(stagedOutputURL) }
            try text.write(to: stagedOutputURL, atomically: true, encoding: .utf8)
            try commit(stagedOutputURL, at: outputURL, operationID: operationID, token: token)
            MediaSupport.makeVisibleIfNeeded(outputURL)
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

    /// A dropped file that does not fit the selected tool: surface the same
    /// "unsupported" message a failed run would, instead of accepting it.
    func rejectUnsupportedInput() {
        state = .failed(.unsupported)
    }

    private func stagedOutput(inputURL: URL, outputURL: URL) throws -> URL {
        guard !MediaSupport.fileURLsReferToSameItem(inputURL, outputURL) else {
            throw MediaFailureBox(.sameOutput)
        }
        return try MediaSupport.temporaryOutputURL(for: outputURL)
    }

    private func commit(_ stagedURL: URL,
                        at outputURL: URL,
                        operationID: UUID,
                        token: MediaCancellationToken) throws {
        lock.lock()
        defer { lock.unlock() }
        guard self.operationID == operationID, !token.isCancelled else {
            throw MediaFailureBox(.cancelled)
        }
        try MediaSupport.installStagedOutput(stagedURL, at: outputURL)
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

    private func renderImage(_ image: CGImage,
                             targetSize: CGSize,
                             resizeMode: MediaImageResizeMode,
                             watermark: MediaImageWatermark,
                             watermarkLogo: CGImage?,
                             background: MediaImageBackground,
                             forceOpaque: Bool) -> CGImage? {
        let width = max(1, Int(targetSize.width.rounded()))
        let height = max(1, Int(targetSize.height.rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: width,
                                         pixelsHigh: height,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return nil
        }

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let size = NSSize(width: CGFloat(width), height: CGFloat(height))
        let rect = NSRect(origin: .zero, size: size)
        if let fill = backgroundColor(background, forceOpaque: forceOpaque) {
            fill.setFill()
            rect.fill()
        }
        let drawRect = imageDrawRect(sourceSize: CGSize(width: image.width, height: image.height),
                                     canvasSize: size,
                                     resizeMode: resizeMode)
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).draw(in: drawRect,
                                                 from: .zero,
                                                 operation: .sourceOver,
                                                 fraction: 1,
                                                 respectFlipped: false,
                                                 hints: [.interpolation: NSImageInterpolation.high.rawValue])
        drawWatermark(watermark, logo: watermarkLogo, canvasSize: size)
        NSGraphicsContext.current = previous
        return rep.cgImage
    }

    private func imageDrawRect(sourceSize: CGSize,
                               canvasSize: NSSize,
                               resizeMode: MediaImageResizeMode) -> NSRect {
        let canvasRect = NSRect(origin: .zero, size: canvasSize)
        guard resizeMode.kind == .exact, resizeMode.exactMode != .stretch else { return canvasRect }
        let sourceWidth = max(1, sourceSize.width)
        let sourceHeight = max(1, sourceSize.height)
        let scale: CGFloat
        switch resizeMode.exactMode {
        case .stretch:
            return canvasRect
        case .fit:
            scale = min(canvasSize.width / sourceWidth, canvasSize.height / sourceHeight)
        case .fill:
            scale = max(canvasSize.width / sourceWidth, canvasSize.height / sourceHeight)
        }
        let width = sourceWidth * scale
        let height = sourceHeight * scale
        return NSRect(x: (canvasSize.width - width) / 2,
                      y: (canvasSize.height - height) / 2,
                      width: width,
                      height: height)
    }

    private func backgroundColor(_ background: MediaImageBackground, forceOpaque: Bool) -> NSColor? {
        switch background {
        case .transparent:
            return forceOpaque ? .white : nil
        case .white:
            return .white
        case .black:
            return .black
        }
    }

    private func drawWatermark(_ watermark: MediaImageWatermark,
                               logo: CGImage?,
                               canvasSize: NSSize) {
        guard watermark.isEnabled, let context = NSGraphicsContext.current else { return }
        let side = max(1, min(canvasSize.width, canvasSize.height))
        let margin = CGFloat(watermark.margin)
        let gap = max(6, side * 0.015)
        var logoImage: NSImage?
        var logoSize = NSSize.zero
        if watermark.usesLogo, let logo {
            let image = NSImage(cgImage: logo,
                                size: NSSize(width: logo.width, height: logo.height))
            let maxLogoSide = max(12, side * CGFloat(watermark.scale))
            let scale = min(maxLogoSide / image.size.width, maxLogoSide / image.size.height)
            logoImage = image
            logoSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        }

        let text = watermark.usesText ? watermark.text.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        var attributedText: NSAttributedString?
        var textSize = NSSize.zero
        if !text.isEmpty {
            let fontSize = max(12, min(96, side * 0.045))
            let shadow = NSShadow()
            shadow.shadowBlurRadius = max(2, fontSize * 0.14)
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
            attributedText = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: NSColor.white,
                .shadow: shadow,
            ])
            textSize = attributedText?.size() ?? .zero
        }

        guard logoImage != nil || attributedText != nil else { return }
        let maxContentWidth = max(1, canvasSize.width - margin * 2)
        let rawContentWidth = logoSize.width + (logoImage != nil && attributedText != nil ? gap : 0) + textSize.width
        let shrink = rawContentWidth > maxContentWidth ? maxContentWidth / rawContentWidth : 1
        var resolvedText = attributedText
        if shrink < 1 {
            logoSize = NSSize(width: logoSize.width * shrink, height: logoSize.height * shrink)
            if let attributedText {
                let fontSize = max(8, (attributedText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 12)
                let shadow = NSShadow()
                shadow.shadowBlurRadius = max(1, fontSize * shrink * 0.14)
                shadow.shadowOffset = NSSize(width: 0, height: -1)
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
                let scaled = NSAttributedString(string: attributedText.string, attributes: [
                    .font: NSFont.systemFont(ofSize: max(8, fontSize * shrink), weight: .semibold),
                    .foregroundColor: NSColor.white,
                    .shadow: shadow,
                ])
                resolvedText = scaled
            }
        }
        textSize = resolvedText?.size() ?? .zero
        let contentWidth = logoSize.width + (logoImage != nil && resolvedText != nil ? gap : 0) + textSize.width
        let contentHeight = max(logoSize.height, textSize.height)
        let origin = watermarkOrigin(position: watermark.position,
                                     contentSize: NSSize(width: contentWidth, height: contentHeight),
                                     canvasSize: canvasSize,
                                     margin: margin)

        context.saveGraphicsState()
        context.cgContext.setAlpha(CGFloat(watermark.opacity))
        var cursorX = origin.x
        if let logoImage {
            let y = origin.y + (contentHeight - logoSize.height) / 2
            logoImage.draw(in: NSRect(x: cursorX, y: y, width: logoSize.width, height: logoSize.height),
                           from: .zero,
                           operation: .sourceOver,
                           fraction: 1)
            cursorX += logoSize.width + (resolvedText != nil ? gap : 0)
        }
        if let attributedText = resolvedText {
            let y = origin.y + (contentHeight - textSize.height) / 2
            attributedText.draw(at: NSPoint(x: cursorX, y: y))
        }
        context.restoreGraphicsState()
    }

    private func watermarkOrigin(position: MediaImageWatermarkPosition,
                                 contentSize: NSSize,
                                 canvasSize: NSSize,
                                 margin: CGFloat) -> NSPoint {
        let maxX = max(margin, canvasSize.width - contentSize.width - margin)
        let maxY = max(margin, canvasSize.height - contentSize.height - margin)
        switch position {
        case .topLeft:
            return NSPoint(x: margin, y: maxY)
        case .topRight:
            return NSPoint(x: maxX, y: maxY)
        case .center:
            return NSPoint(x: max(margin, (canvasSize.width - contentSize.width) / 2),
                           y: max(margin, (canvasSize.height - contentSize.height) / 2))
        case .bottomLeft:
            return NSPoint(x: margin, y: margin)
        case .bottomRight:
            return NSPoint(x: maxX, y: margin)
        }
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

    private struct VideoGeometry {
        let videoTrack: AVAssetTrack
        let audioTracks: [AVAssetTrack]
        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
        let frameRate: Double
    }

    private struct VideoMetadata {
        let duration: Double
        let displaySize: CGSize
        let geometry: VideoGeometry?
    }

    private func loadVideoMetadata(from asset: AVAsset,
                                   includeGeometry: Bool,
                                   token: MediaCancellationToken) throws -> VideoMetadata {
        try runAsync(token: token) {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { throw MediaFailureBox(.noVideoTrack) }

            let duration = try await asset.load(.duration).seconds
            guard includeGeometry else {
                return VideoMetadata(duration: duration, displaySize: .zero, geometry: nil)
            }

            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            let frameRate = Double(try await track.load(.nominalFrameRate))
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let transformed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
            let displaySize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
            return VideoMetadata(duration: duration,
                                 displaySize: displaySize,
                                 geometry: VideoGeometry(videoTrack: track,
                                                         audioTracks: audioTracks,
                                                         naturalSize: naturalSize,
                                                         preferredTransform: preferredTransform,
                                                         frameRate: frameRate))
        }
    }

    private func generateCGImage(from generator: AVAssetImageGenerator,
                                 at time: CMTime,
                                 token: MediaCancellationToken) throws -> CGImage {
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

        while semaphore.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            if token.isCancelled {
                generator.cancelAllCGImageGeneration()
                throw MediaFailureBox(.cancelled)
            }
        }
        try checkCancellation(token)
        guard let result else {
            throw MediaFailureBox(.failed("Video frame unavailable."))
        }
        return try result.get()
    }

    private func runAsync<T>(token: MediaCancellationToken,
                             _ operation: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?

        let task = Task {
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }

        while semaphore.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            if token.isCancelled {
                task.cancel()
                throw MediaFailureBox(.cancelled)
            }
        }
        try checkCancellation(token)
        guard let result else {
            throw MediaFailureBox(.failed("Video metadata unavailable."))
        }
        return try result.get()
    }

    private func sanitizedImageProperties(_ properties: [CFString: Any], image: CGImage) -> [CFString: Any] {
        var clean = properties
        clean.removeValue(forKey: kCGImagePropertyOrientation)
        clean[kCGImagePropertyPixelWidth] = image.width
        clean[kCGImagePropertyPixelHeight] = image.height
        return clean
    }

    /// CGImageDestination accepts com.adobe.pdf but ignores the lossy quality,
    /// embedding the bitmap losslessly. Re-encoding as JPEG at the chosen
    /// quality and drawing that image into a PDF context makes Quartz embed
    /// the JPEG stream as-is, so the quality slider keeps working for PDF.
    private func writePDF(image: CGImage, outputURL: URL, quality: Double) throws {
        let jpegData = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(jpegData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw MediaFailureBox(.unsupported)
        }
        CGImageDestinationAddImage(encoder, image, [
            kCGImageDestinationLossyCompressionQuality: quality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(encoder),
              let encodedSource = CGImageSourceCreateWithData(jpegData, nil),
              let encoded = CGImageSourceCreateImageAtIndex(encodedSource, 0, nil) else {
            throw MediaFailureBox(.unsupported)
        }
        var mediaBox = CGRect(x: 0, y: 0, width: CGFloat(encoded.width), height: CGFloat(encoded.height))
        guard let pdf = CGContext(outputURL as CFURL, mediaBox: &mediaBox, nil) else {
            throw MediaFailureBox(.unsupported)
        }
        pdf.beginPDFPage(nil)
        pdf.draw(encoded, in: mediaBox)
        pdf.endPDFPage()
        pdf.closePDF()
    }

    private func typeIdentifier(for format: MediaImageFormat) -> String {
        switch format {
        case .jpeg: return UTType.jpeg.identifier
        case .heic: return UTType.heic.identifier
        case .png: return UTType.png.identifier
        case .pdf: return UTType.pdf.identifier
        }
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func preserveModificationDateIfNeeded(from inputURL: URL,
                                                  to outputURL: URL,
                                                  options: MediaImageOptions) {
        guard options.preserveModificationDate,
              let date = try? inputURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return }
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: outputURL.path)
    }

    private func checkCancellation(_ token: MediaCancellationToken) throws {
        if token.isCancelled { throw MediaFailureBox(.cancelled) }
    }

    /// Launch and cancellation share one lock, so a process either starts and
    /// becomes cancellable before the lock is released, or never starts after
    /// its operation was replaced or cancelled.
    private func launch(process: Process,
                        operationID: UUID,
                        token: MediaCancellationToken) throws {
        lock.lock()
        defer { lock.unlock() }
        guard self.operationID == operationID, !token.isCancelled else {
            throw MediaFailureBox(.cancelled)
        }
        try process.run()
        activeProcess = process
    }

    private func setActiveVisionRequest(_ request: VNRequest,
                                        operationID: UUID,
                                        token: MediaCancellationToken) throws {
        lock.lock()
        defer { lock.unlock() }
        guard self.operationID == operationID, !token.isCancelled else {
            throw MediaFailureBox(.cancelled)
        }
        activeVisionRequest = request
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
