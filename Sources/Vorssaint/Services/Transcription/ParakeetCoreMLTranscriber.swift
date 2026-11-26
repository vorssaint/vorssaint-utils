// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import CoreML
import Foundation

/// Native Core ML inference engine and Hugging Face downloader for NVIDIA
/// Parakeet Unified English 0.6B (`FluidInference/parakeet-unified-en-0.6b-coreml`).
/// Zero external binaries or SwiftPM dependencies: runs purely on Apple Core ML
/// and AVFoundation, keeping all audio 100% local on the Mac.
final class ParakeetCoreMLTranscriber: @unchecked Sendable {
    enum TranscriberError: LocalizedError {
        case modelNotDownloaded
        case downloadFailed(String)
        case unreadableAudio(String)
        case emptyAudio
        case inferenceFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .modelNotDownloaded:
                return "Parakeet Unified English 0.6B model is not downloaded yet."
            case .downloadFailed(let detail):
                return "Model download failed: \(detail)"
            case .unreadableAudio(let detail):
                return "Could not read audio file: \(detail)"
            case .emptyAudio:
                return "Audio file contains no audio samples."
            case .inferenceFailed(let detail):
                return "Transcription inference failed: \(detail)"
            case .cancelled:
                return "Transcription was cancelled."
            }
        }
    }

    struct TranscriptionResult: Sendable {
        let segments: [AudioTranscriptionSupport.TranscriptSegment]
        let audioDurationSeconds: Double
        let elapsedSeconds: Double
    }

    // MARK: - Model Download

    static func downloadModel(to directory: URL,
                              progress: @escaping @Sendable (Double, Int64, Int64) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let specs = AudioTranscriptionSupport.requiredModelFiles
        let totalExpected = AudioTranscriptionSupport.totalExpectedModelBytes
        var completedBytes: Int64 = 0

        // Count already-complete files first so resumed downloads report accurate progress.
        for spec in specs {
            let dest = directory.appendingPathComponent(spec.relativePath)
            if let attrs = try? fm.attributesOfItem(atPath: dest.path),
               let size = attrs[.size] as? NSNumber,
               size.int64Value >= max(1, spec.expectedBytes * 9 / 10) {
                completedBytes += spec.expectedBytes
            }
        }
        progress(Double(completedBytes) / Double(max(1, totalExpected)), completedBytes, totalExpected)

        for spec in specs {
            try Task.checkCancellation()
            let dest = directory.appendingPathComponent(spec.relativePath)
            if let attrs = try? fm.attributesOfItem(atPath: dest.path),
               let size = attrs[.size] as? NSNumber,
               size.int64Value >= max(1, spec.expectedBytes * 9 / 10) {
                continue
            }

            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let partial = dest.appendingPathExtension("partial")
            try? fm.removeItem(at: partial)
            fm.createFile(atPath: partial.path, contents: nil)
            let handle = try FileHandle(forWritingTo: partial)
            var finishedFile = false
            defer {
                try? handle.close()
                if !finishedFile { try? fm.removeItem(at: partial) }
            }

            var request = URLRequest(url: AudioTranscriptionSupport.downloadURL(for: spec.relativePath))
            request.timeoutInterval = 3600
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw TranscriberError.downloadFailed("HTTP \(code) for \(spec.relativePath)")
            }

            var written: Int64 = 0
            var lastReported: Int64 = 0
            var chunk = Data()
            chunk.reserveCapacity(1 << 20)

            for try await byte in bytes {
                try Task.checkCancellation()
                chunk.append(byte)
                if chunk.count >= (1 << 20) {
                    try handle.write(contentsOf: chunk)
                    written += Int64(chunk.count)
                    chunk.removeAll(keepingCapacity: true)
                    if written - lastReported >= (4 << 20) {
                        lastReported = written
                        let aggregate = min(totalExpected, completedBytes + written)
                        progress(Double(aggregate) / Double(max(1, totalExpected)), aggregate, totalExpected)
                    }
                }
            }
            if !chunk.isEmpty {
                try handle.write(contentsOf: chunk)
                written += Int64(chunk.count)
            }
            try handle.close()

            let minSize = max(1, spec.expectedBytes * 9 / 10)
            guard written >= minSize else {
                throw TranscriberError.downloadFailed("Incomplete transfer for \(spec.relativePath)")
            }
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: partial, to: dest)
            finishedFile = true

            completedBytes = min(totalExpected, completedBytes + spec.expectedBytes)
            progress(Double(completedBytes) / Double(max(1, totalExpected)), completedBytes, totalExpected)
        }
    }

    // MARK: - Loaded Core ML Bundle Cache

    private struct LoadedModels {
        let modelDirectory: URL
        let computeMode: ParakeetComputeMode
        let preprocessor: MLModel
        let encoder: MLModel
        let decoder: MLModel
        let jointDecision: MLModel
        let vocabulary: [Int: String]
    }

    private let lock = NSLock()
    private var cached: LoadedModels?
    private var cacheGeneration = 0

    func evictCache() {
        lock.lock()
        cached = nil
        cacheGeneration += 1
        lock.unlock()
    }

    private func loadModelsIfNeeded(directory: URL, computeMode: ParakeetComputeMode) throws -> LoadedModels {
        lock.lock()
        if let existing = cached,
           existing.modelDirectory == directory,
           existing.computeMode == computeMode {
            cacheGeneration += 1
            let gen = cacheGeneration
            lock.unlock()
            scheduleIdleEviction(generation: gen)
            return existing
        }
        lock.unlock()

        guard AudioTranscriptionSupport.isModelDirectoryReady(directory) else {
            throw TranscriberError.modelNotDownloaded
        }

        let vocabData = try Data(contentsOf: directory.appendingPathComponent("vocab.json"))
        let vocab = try AudioTranscriptionSupport.parseVocabulary(data: vocabData)

        let encoderConfig = MLModelConfiguration()
        switch computeMode {
        case .auto:
            encoderConfig.computeUnits = .cpuAndNeuralEngine
        case .cpuAndGPU:
            encoderConfig.computeUnits = .cpuAndGPU
        case .cpuOnly:
            encoderConfig.computeUnits = .cpuOnly
        }

        // Preprocessor and tiny single-step RNNT decoder/joint run fastest with
        // minimal dispatch overhead on CPU.
        let cpuConfig = MLModelConfiguration()
        cpuConfig.computeUnits = .cpuOnly

        let preprocessor = try MLModel(
            contentsOf: directory.appendingPathComponent("parakeet_unified_preprocessor.mlmodelc"),
            configuration: cpuConfig
        )
        let encoder = try MLModel(
            contentsOf: directory.appendingPathComponent("parakeet_unified_encoder_int8.mlmodelc"),
            configuration: encoderConfig
        )
        let decoder = try MLModel(
            contentsOf: directory.appendingPathComponent("parakeet_unified_decoder.mlmodelc"),
            configuration: cpuConfig
        )
        let jointDecision = try MLModel(
            contentsOf: directory.appendingPathComponent("parakeet_unified_joint_decision_single_step.mlmodelc"),
            configuration: cpuConfig
        )

        let loaded = LoadedModels(
            modelDirectory: directory,
            computeMode: computeMode,
            preprocessor: preprocessor,
            encoder: encoder,
            decoder: decoder,
            jointDecision: jointDecision,
            vocabulary: vocab
        )
        lock.lock()
        cached = loaded
        cacheGeneration += 1
        let gen = cacheGeneration
        lock.unlock()
        scheduleIdleEviction(generation: gen)
        return loaded
    }

    private func scheduleIdleEviction(generation: Int) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 180) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            if self.cacheGeneration == generation {
                self.cached = nil
            }
            self.lock.unlock()
        }
    }

    // MARK: - Transcription

    func transcribe(audioURL: URL,
                    modelDirectory: URL = AudioTranscriptionSupport.defaultModelDirectory(),
                    computeMode: ParakeetComputeMode = .auto,
                    speaker: String? = nil,
                    progress: (@Sendable (Double) -> Void)? = nil) async throws -> TranscriptionResult {
        try Task.checkCancellation()
        let startTime = Date()
        let samples = try await Self.load16kMonoSamples(from: audioURL)
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        let duration = Double(samples.count) / AudioTranscriptionSupport.sampleRate
        try Task.checkCancellation()

        let models = try loadModelsIfNeeded(directory: modelDirectory, computeMode: computeMode)
        try Task.checkCancellation()

        let resultTokens: [AudioTranscriptionSupport.EmittedToken] = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let tokens = try Self.runSlidingWindows(
                        samples: samples,
                        models: models,
                        progress: progress
                    )
                    cont.resume(returning: tokens)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }

        let segments = AudioTranscriptionSupport.segments(
            from: resultTokens,
            vocabulary: models.vocabulary,
            speaker: speaker
        )
        return TranscriptionResult(
            segments: segments,
            audioDurationSeconds: duration,
            elapsedSeconds: Date().timeIntervalSince(startTime)
        )
    }

    private static func runSlidingWindows(samples: [Float],
                                          models: LoadedModels,
                                          progress: (@Sendable (Double) -> Void)?) throws -> [AudioTranscriptionSupport.EmittedToken] {
        let winSize = AudioTranscriptionSupport.windowSamples
        let hop = AudioTranscriptionSupport.hopSamples
        let overlapFrames = AudioTranscriptionSupport.overlapSamples / AudioTranscriptionSupport.frameSamples

        var starts: [Int] = []
        var pos = 0
        while pos < samples.count {
            starts.append(pos)
            if pos + winSize >= samples.count { break }
            pos += hop
        }

        let decoderRunner = try RNNTDecoderRunner(
            decoderModel: models.decoder,
            jointModel: models.jointDecision
        )
        let audioArray = try MLMultiArray(shape: [1, NSNumber(value: winSize)], dataType: .float32)
        let audioLenArray = try MLMultiArray(shape: [1], dataType: .int32)
        let melPadded = try MLMultiArray(
            shape: [1, NSNumber(value: AudioTranscriptionSupport.melBins), NSNumber(value: AudioTranscriptionSupport.melFrames)],
            dataType: .float32
        )
        let melLenArray = try MLMultiArray(shape: [1], dataType: .int32)

        var merged: [AudioTranscriptionSupport.EmittedToken] = []
        progress?(0)

        for (index, chunkStart) in starts.enumerated() {
            if Task.isCancelled { throw TranscriberError.cancelled }

            let chunkEnd = min(chunkStart + winSize, samples.count)
            let validCount = chunkEnd - chunkStart
            guard validCount > 0 else { continue }

            // Fill 15s input buffer (zero-padded for tail window).
            let audioPtr = audioArray.dataPointer.bindMemory(to: Float.self, capacity: winSize)
            samples.withUnsafeBufferPointer { src in
                audioPtr.update(from: src.baseAddress! + chunkStart, count: validCount)
            }
            if validCount < winSize {
                memset(audioPtr + validCount, 0, (winSize - validCount) * MemoryLayout<Float>.size)
            }
            audioLenArray.dataPointer.bindMemory(to: Int32.self, capacity: 1)[0] = Int32(validCount)

            let preInput = try MLDictionaryFeatureProvider(dictionary: [
                "audio_signal": MLFeatureValue(multiArray: audioArray),
                "audio_length": MLFeatureValue(multiArray: audioLenArray),
            ])
            let preOut = try models.preprocessor.prediction(from: preInput)
            guard let rawMel = preOut.featureValue(for: "mel")?.multiArrayValue,
                  let rawMelLen = preOut.featureValue(for: "mel_length")?.multiArrayValue else {
                throw TranscriberError.inferenceFailed("Preprocessor returned no mel spectrogram.")
            }

            let melForEncoder: MLMultiArray
            let targetFrames = AudioTranscriptionSupport.melFrames
            let rawFrames = rawMel.shape[2].intValue
            if rawFrames == targetFrames {
                melForEncoder = rawMel
            } else {
                try Self.copyMel(rawMel, intoFixedWidth: melPadded, maxFrames: targetFrames)
                melForEncoder = melPadded
            }
            let clampedMelLen = min(rawMelLen[0].intValue, targetFrames)
            melLenArray.dataPointer.bindMemory(to: Int32.self, capacity: 1)[0] = Int32(clampedMelLen)

            let encInput = try MLDictionaryFeatureProvider(dictionary: [
                "mel": MLFeatureValue(multiArray: melForEncoder),
                "mel_length": MLFeatureValue(multiArray: melLenArray),
            ])
            let encOut = try models.encoder.prediction(from: encInput)
            guard let encoded = encOut.featureValue(for: "encoder")?.multiArrayValue,
                  let encodedLen = encOut.featureValue(for: "encoder_length")?.multiArrayValue else {
                throw TranscriberError.inferenceFailed("Encoder returned no hidden states.")
            }

            let validEncoderFrames = min(encodedLen[0].intValue, encoded.shape[2].intValue)
            let globalFrameOffset = chunkStart / AudioTranscriptionSupport.frameSamples
            let windowTokens = try decoderRunner.decodeWindow(
                encoded: encoded,
                frameCount: validEncoderFrames,
                globalFrameOffset: globalFrameOffset
            )

            if merged.isEmpty {
                merged = windowTokens
            } else {
                merged = AudioTranscriptionSupport.mergeWindowTokens(
                    existing: merged,
                    incoming: windowTokens,
                    overlapStartFrame: globalFrameOffset,
                    overlapEndFrame: globalFrameOffset + overlapFrames
                )
            }

            progress?(Double(index + 1) / Double(max(1, starts.count)))
        }

        return merged
    }

    private static func copyMel(_ src: MLMultiArray, intoFixedWidth dst: MLMultiArray, maxFrames: Int) throws {
        let bins = AudioTranscriptionSupport.melBins
        let srcFrames = min(src.shape[2].intValue, maxFrames)
        let dstPtr = dst.dataPointer.bindMemory(to: Float.self, capacity: dst.count)
        memset(dstPtr, 0, dst.count * MemoryLayout<Float>.size)

        let srcPtr = src.dataPointer.bindMemory(to: Float.self, capacity: src.count)
        let s1 = src.strides[1].intValue
        let s2 = src.strides[2].intValue
        let d1 = dst.strides[1].intValue
        let d2 = dst.strides[2].intValue

        for b in 0..<bins {
            let srcRow = b * s1
            let dstRow = b * d1
            for t in 0..<srcFrames {
                dstPtr[dstRow + t * d2] = srcPtr[srcRow + t * s2]
            }
        }
    }

    // MARK: - Greedy RNN-T Decoder

    private final class RNNTDecoderRunner {
        private let decoderModel: MLModel
        private let jointModel: MLModel
        private let blankID = Int32(AudioTranscriptionSupport.blankTokenID)
        private let hiddenDim = AudioTranscriptionSupport.decoderHiddenSize
        private let layers = AudioTranscriptionSupport.decoderLayers
        private let encoderDim = AudioTranscriptionSupport.encoderHiddenSize

        private let targets: MLMultiArray
        private let targetLength: MLMultiArray
        private let hIn: MLMultiArray
        private let cIn: MLMultiArray
        private let encoderStep: MLMultiArray

        init(decoderModel: MLModel, jointModel: MLModel) throws {
            self.decoderModel = decoderModel
            self.jointModel = jointModel
            targets = try MLMultiArray(shape: [1, 1], dataType: .int32)
            targetLength = try MLMultiArray(shape: [1], dataType: .int32)
            targetLength.dataPointer.bindMemory(to: Int32.self, capacity: 1)[0] = 1
            hIn = try MLMultiArray(shape: [NSNumber(value: layers), 1, NSNumber(value: hiddenDim)], dataType: .float32)
            cIn = try MLMultiArray(shape: [NSNumber(value: layers), 1, NSNumber(value: hiddenDim)], dataType: .float32)
            encoderStep = try MLMultiArray(shape: [1, NSNumber(value: encoderDim), 1], dataType: .float32)
        }

        func decodeWindow(encoded: MLMultiArray,
                          frameCount: Int,
                          globalFrameOffset: Int,
                          maxSymbolsPerStep: Int = 10) throws -> [AudioTranscriptionSupport.EmittedToken] {
            guard frameCount > 0 else { return [] }
            zero(hIn)
            zero(cIn)

            var currentToken = blankID
            var dec = try runDecoder(token: currentToken)
            var emissions: [AudioTranscriptionSupport.EmittedToken] = []

            let encPtr = encoded.dataPointer.bindMemory(to: Float.self, capacity: encoded.count)
            let encStride1 = encoded.strides[1].intValue
            let encStride2 = encoded.strides[2].intValue
            let stepPtr = encoderStep.dataPointer.bindMemory(to: Float.self, capacity: encoderDim)

            for t in 0..<frameCount {
                for c in 0..<encoderDim {
                    stepPtr[c] = encPtr[c * encStride1 + t * encStride2]
                }

                var emittedThisFrame = 0
                while emittedThisFrame < maxSymbolsPerStep {
                    let jointInput = try MLDictionaryFeatureProvider(dictionary: [
                        "encoder_step": MLFeatureValue(multiArray: encoderStep),
                        "decoder_step": MLFeatureValue(multiArray: dec.output),
                    ])
                    let jointOut = try jointModel.prediction(from: jointInput)
                    guard let tokenArray = jointOut.featureValue(for: "token_id")?.multiArrayValue,
                          let probArray = jointOut.featureValue(for: "token_prob")?.multiArrayValue else {
                        throw TranscriberError.inferenceFailed("Joint decision returned no token.")
                    }
                    let tokenID = tokenArray.dataType == .int32
                        ? tokenArray.dataPointer.load(as: Int32.self)
                        : tokenArray[0].int32Value
                    if tokenID == blankID {
                        break
                    }
                    let prob = probArray.dataType == .float32
                        ? probArray.dataPointer.load(as: Float.self)
                        : probArray[0].floatValue
                    emissions.append(AudioTranscriptionSupport.EmittedToken(
                        id: Int(tokenID),
                        frame: globalFrameOffset + t,
                        probability: prob
                    ))
                    // Accept LSTM state only when a non-blank token is emitted.
                    copyFloat32(from: dec.h, to: hIn)
                    copyFloat32(from: dec.c, to: cIn)
                    currentToken = tokenID
                    dec = try runDecoder(token: currentToken)
                    emittedThisFrame += 1
                }
            }
            return emissions
        }

        private func runDecoder(token: Int32) throws -> (output: MLMultiArray, h: MLMultiArray, c: MLMultiArray) {
            targets.dataPointer.bindMemory(to: Int32.self, capacity: 1)[0] = token
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "targets": MLFeatureValue(multiArray: targets),
                "target_length": MLFeatureValue(multiArray: targetLength),
                "h_in": MLFeatureValue(multiArray: hIn),
                "c_in": MLFeatureValue(multiArray: cIn),
            ])
            let out = try decoderModel.prediction(from: input)
            guard let decOut = out.featureValue(for: "decoder")?.multiArrayValue,
                  let hOut = out.featureValue(for: "h_out")?.multiArrayValue,
                  let cOut = out.featureValue(for: "c_out")?.multiArrayValue else {
                throw TranscriberError.inferenceFailed("Decoder returned invalid state.")
            }
            return (decOut, hOut, cOut)
        }

        private func zero(_ array: MLMultiArray) {
            memset(array.dataPointer, 0, array.count * MemoryLayout<Float>.size)
        }

        private func copyFloat32(from src: MLMultiArray, to dst: MLMultiArray) {
            let count = min(src.count, dst.count)
            let srcStrides = src.strides.map(\.intValue)
            let dstStrides = dst.strides.map(\.intValue)
            let shape = src.shape.map(\.intValue)
            var expected = 1
            var contiguous = true
            for axis in (0..<shape.count).reversed() {
                if shape[axis] > 1 && (srcStrides[axis] != expected || dstStrides[axis] != expected) {
                    contiguous = false
                    break
                }
                expected *= shape[axis]
            }
            let srcPtr = src.dataPointer.bindMemory(to: Float.self, capacity: src.count)
            let dstPtr = dst.dataPointer.bindMemory(to: Float.self, capacity: dst.count)
            if contiguous {
                dstPtr.update(from: srcPtr, count: count)
                return
            }
            var idx = [Int](repeating: 0, count: shape.count)
            for _ in 0..<count {
                var sOff = 0
                var dOff = 0
                for a in 0..<shape.count {
                    sOff += idx[a] * srcStrides[a]
                    dOff += idx[a] * dstStrides[a]
                }
                dstPtr[dOff] = srcPtr[sOff]
                var a = shape.count - 1
                while a >= 0 {
                    idx[a] += 1
                    if idx[a] < shape[a] { break }
                    idx[a] = 0
                    a -= 1
                }
            }
        }
    }

    // MARK: - Audio Loading & 16 kHz Mono Resampling

    /// Loads any macOS-supported audio or video container (WAV, M4A, MP3, AIFF,
    /// CAF, FLAC, AAC, MP4, MOV) as 16 kHz mono Float32 samples.
    static func load16kMonoSamples(from url: URL) async throws -> [Float] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TranscriberError.unreadableAudio("File not found.")
        }
        if let samples = try? readViaAVAudioFile(url), !samples.isEmpty {
            return samples
        }
        return try await readViaAVAssetReader(url)
    }

    private static func readViaAVAudioFile(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let srcFormat = file.processingFormat
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioTranscriptionSupport.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw TranscriberError.unreadableAudio("Could not create 16 kHz target format.")
        }

        let chunkFrames: AVAudioFrameCount = 32_768
        guard let readBuf = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: chunkFrames) else {
            throw TranscriberError.unreadableAudio("Buffer allocation failed.")
        }

        var output: [Float] = []
        let expected = Int(Double(file.length) * (AudioTranscriptionSupport.sampleRate / max(1, srcFormat.sampleRate))) + 1024
        output.reserveCapacity(max(0, expected))

        if srcFormat.sampleRate == targetFormat.sampleRate, srcFormat.channelCount == 1, !srcFormat.isInterleaved {
            while file.framePosition < file.length {
                try file.read(into: readBuf, frameCount: chunkFrames)
                if readBuf.frameLength == 0 { break }
                if let ptr = readBuf.floatChannelData?[0] {
                    output.append(contentsOf: UnsafeBufferPointer(start: ptr, count: Int(readBuf.frameLength)))
                }
            }
            return output
        }

        guard let converter = AVAudioConverter(from: srcFormat, to: targetFormat) else {
            throw TranscriberError.unreadableAudio("Unsupported audio format.")
        }
        let ratio = targetFormat.sampleRate / max(1, srcFormat.sampleRate)
        let outCap = AVAudioFrameCount(Double(chunkFrames) * ratio) + 256
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCap) else {
            throw TranscriberError.unreadableAudio("Output buffer allocation failed.")
        }

        var eof = false
        while !eof {
            var convError: NSError?
            let status = converter.convert(to: outBuf, error: &convError) { _, outStatus in
                if file.framePosition >= file.length {
                    eof = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: readBuf, frameCount: chunkFrames)
                    if readBuf.frameLength == 0 {
                        eof = true
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    outStatus.pointee = .haveData
                    return readBuf
                } catch {
                    eof = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
            }
            if status == .error {
                throw TranscriberError.unreadableAudio(convError?.localizedDescription ?? "Conversion error.")
            }
            if outBuf.frameLength > 0, let ptr = outBuf.floatChannelData?[0] {
                output.append(contentsOf: UnsafeBufferPointer(start: ptr, count: Int(outBuf.frameLength)))
            }
            if status == .endOfStream { break }
        }
        return output
    }

    private static func readViaAVAssetReader(_ url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw TranscriberError.unreadableAudio("No audio track found in file.")
        }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: AudioTranscriptionSupport.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw TranscriberError.unreadableAudio("Could not configure audio reader.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw TranscriberError.unreadableAudio(reader.error?.localizedDescription ?? "Reader failed to start.")
        }

        var samples: [Float] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var length = 0
            var dataPtr: UnsafeMutablePointer<CChar>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                              totalLengthOut: &length, dataPointerOut: &dataPtr) == kCMBlockBufferNoErr,
                  let dataPtr, length >= MemoryLayout<Float>.size else { continue }
            let count = length / MemoryLayout<Float>.size
            dataPtr.withMemoryRebound(to: Float.self, capacity: count) { floatPtr in
                samples.append(contentsOf: UnsafeBufferPointer(start: floatPtr, count: count))
            }
        }
        if reader.status == .failed {
            throw TranscriberError.unreadableAudio(reader.error?.localizedDescription ?? "Reader failed.")
        }
        return samples
    }
}
