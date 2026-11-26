// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreML
import Foundation

/// Pure Swift + Core ML inference engine for `ivrit-ai/whisper-large-v3-turbo`
/// (`eranshir/ivrit-ai-whisper-large-v3-turbo-coreml-int8`), delivering
/// Hebrew speech recognition + native Whisper acoustic
/// language probing directly on Apple Neural Engine / GPU with zero C++
/// dependencies.
final class WhisperCoreMLTranscriber: @unchecked Sendable {
    enum TranscriberError: LocalizedError {
        case modelNotDownloaded
        case invalidVocabulary
        case emptyAudio
        case downloadFailed(String)
        case inferenceFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .modelNotDownloaded:
                return "ivrit.ai Hebrew Whisper model is not downloaded yet."
            case .invalidVocabulary:
                return "Could not read Whisper vocabulary file."
            case .emptyAudio:
                return "No decodable audio samples found."
            case .downloadFailed(let detail):
                return "Hebrew model download failed: \(detail)"
            case .inferenceFailed(let detail):
                return "Whisper Core ML inference failed: \(detail)"
            case .cancelled:
                return "Transcription cancelled."
            }
        }
    }

    struct LanguageProbeResult: Equatable, Sendable {
        let topLanguageCode: String
        let topConfidence: Double
        let hebrewProbability: Double
        let englishProbability: Double
    }

    private struct LoadedModels {
        let mel: MLModel
        let encoder: MLModel
        let decoder: MLModel
        let vocabulary: [Int: String]
        let computeMode: ParakeetComputeMode
        let directory: URL
    }

    private let cacheLock = NSLock()
    private var cachedModels: LoadedModels?

    // MARK: - Model Download

    static func downloadModel(to directory: URL = AudioTranscriptionSupport.defaultIvritModelDirectory(),
                              progress: @escaping @Sendable (_ fraction: Double, _ completedBytes: Int64, _ totalBytes: Int64) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let specs = AudioTranscriptionSupport.ivritRequiredModelFiles
        let totalExpected = AudioTranscriptionSupport.totalExpectedIvritModelBytes
        var completedBytes: Int64 = 0

        // Count already-complete files first so resumed downloads report accurate progress.
        for spec in specs {
            let destURL = directory.appendingPathComponent(spec.relativePath)
            let minSize = spec.expectedBytes > 10_000 ? max(1, (spec.expectedBytes * 9) / 10) : 1
            if let attrs = try? fm.attributesOfItem(atPath: destURL.path),
               let existingSize = attrs[.size] as? Int64,
               existingSize >= minSize {
                completedBytes += spec.expectedBytes
            }
        }
        progress(min(1.0, Double(completedBytes) / Double(max(1, totalExpected))), completedBytes, totalExpected)

        for spec in specs {
            try Task.checkCancellation()
            let destURL = directory.appendingPathComponent(spec.relativePath)
            let minSize = spec.expectedBytes > 10_000 ? max(1, (spec.expectedBytes * 9) / 10) : 1

            if let attrs = try? fm.attributesOfItem(atPath: destURL.path),
               let existingSize = attrs[.size] as? Int64,
               existingSize >= minSize {
                continue
            }

            let baseDone = completedBytes
            let remoteURL = AudioTranscriptionSupport.ivritDownloadURL(for: spec.relativePath)
            do {
                _ = try await ModelFileDownloader.download(
                    from: remoteURL,
                    to: destURL,
                    label: spec.relativePath,
                    minExpectedBytes: minSize
                ) { fileBytes in
                    let totalSoFar = min(totalExpected, baseDone + min(fileBytes, spec.expectedBytes))
                    let frac = min(0.999, Double(totalSoFar) / Double(max(1, totalExpected)))
                    progress(frac, totalSoFar, totalExpected)
                }
            } catch is CancellationError {
                throw TranscriberError.cancelled
            } catch {
                throw TranscriberError.downloadFailed(error.localizedDescription)
            }

            completedBytes = min(totalExpected, completedBytes + spec.expectedBytes)
            let frac = min(1.0, Double(completedBytes) / Double(max(1, totalExpected)))
            progress(frac, completedBytes, totalExpected)
        }
    }

    // MARK: - Model Loading & Caching

    func evictCache() {
        cacheLock.lock()
        cachedModels = nil
        cacheLock.unlock()
    }

    private func loadModelsIfNeeded(directory: URL, computeMode: ParakeetComputeMode) throws -> LoadedModels {
        cacheLock.lock()
        if let existing = cachedModels,
           existing.directory == directory,
           existing.computeMode == computeMode {
            cacheLock.unlock()
            return existing
        }
        cacheLock.unlock()

        guard AudioTranscriptionSupport.isIvritModelDirectoryReady(directory) else {
            throw TranscriberError.modelNotDownloaded
        }

        let vocabURL = directory.appendingPathComponent("vocab.json")
        let vocabData = try Data(contentsOf: vocabURL)
        guard let rawVocab = try JSONSerialization.jsonObject(with: vocabData) as? [String: Int] else {
            throw TranscriberError.invalidVocabulary
        }
        var vocabulary: [Int: String] = [:]
        vocabulary.reserveCapacity(rawVocab.count)
        for (token, id) in rawVocab {
            vocabulary[id] = token
        }

        let units: MLComputeUnits = switch computeMode {
        case .auto: .all
        case .cpuAndGPU: .cpuAndGPU
        case .cpuOnly: .cpuOnly
        }
        let config = MLModelConfiguration()
        config.computeUnits = units

        let mel = try MLModel(contentsOf: directory.appendingPathComponent("MelSpectrogram.mlmodelc"),
                              configuration: config)
        let encoder = try MLModel(contentsOf: directory.appendingPathComponent("AudioEncoder.mlmodelc"),
                                  configuration: config)
        let decoder = try MLModel(contentsOf: directory.appendingPathComponent("TextDecoder.mlmodelc"),
                                  configuration: config)

        let loaded = LoadedModels(
            mel: mel,
            encoder: encoder,
            decoder: decoder,
            vocabulary: vocabulary,
            computeMode: computeMode,
            directory: directory
        )
        cacheLock.lock()
        cachedModels = loaded
        cacheLock.unlock()
        return loaded
    }

    // MARK: - Acoustic Language Probe (1-step Whisper Encoder + Decoder on <|startoftranscript|>)

    func detectLanguage(samples: [Float],
                        modelDirectory: URL = AudioTranscriptionSupport.defaultIvritModelDirectory(),
                        computeMode: ParakeetComputeMode = .auto) async throws -> LanguageProbeResult? {
        guard samples.count >= Int(AudioTranscriptionSupport.sampleRate * 0.4) else { return nil }
        let models = try loadModelsIfNeeded(directory: modelDirectory, computeMode: computeMode)

        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Self.runLanguageProbe(samples: samples, models: models)
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private static func runLanguageProbe(samples: [Float], models: LoadedModels) throws -> LanguageProbeResult? {
        let encoderOutput = try encodeChunk(samples, models: models)
        let maxSeq = AudioTranscriptionSupport.whisperMaxTokens
        let kvDim = 5_120 // 4 decoder layers * 1280 d_model

        let inputIds = try MLMultiArray(shape: [1], dataType: .int32)
        inputIds[0] = NSNumber(value: Int32(AudioTranscriptionSupport.whisperSOTToken))
        let cacheLength = try MLMultiArray(shape: [1], dataType: .int32)
        cacheLength[0] = 0
        let keyCache = try MLMultiArray(shape: [1, NSNumber(value: kvDim), 1, NSNumber(value: maxSeq)], dataType: .float16)
        let valueCache = try MLMultiArray(shape: [1, NSNumber(value: kvDim), 1, NSNumber(value: maxSeq)], dataType: .float16)
        zeroFill(keyCache)
        zeroFill(valueCache)

        let updateMask = try MLMultiArray(shape: [1, NSNumber(value: maxSeq)], dataType: .float16)
        zeroFill(updateMask)
        setFloat16(updateMask, at: 0, value: 1.0)

        let paddingMask = try MLMultiArray(shape: [1, NSNumber(value: maxSeq)], dataType: .float16)
        fillFloat16(paddingMask, value: -10_000.0)
        setFloat16(paddingMask, at: 0, value: 0.0)

        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIds),
            "cache_length": MLFeatureValue(multiArray: cacheLength),
            "key_cache": MLFeatureValue(multiArray: keyCache),
            "value_cache": MLFeatureValue(multiArray: valueCache),
            "kv_cache_update_mask": MLFeatureValue(multiArray: updateMask),
            "encoder_output_embeds": MLFeatureValue(multiArray: encoderOutput),
            "decoder_key_padding_mask": MLFeatureValue(multiArray: paddingMask),
        ])
        let output = try models.decoder.prediction(from: provider)
        guard let logits = output.featureValue(for: "logits")?.multiArrayValue else { return nil }

        let langRange = AudioTranscriptionSupport.whisperLanguageTokenRange
        var maxLogit = -Float.infinity
        var langLogits: [Float] = []
        langLogits.reserveCapacity(langRange.count)
        for tokenID in langRange {
            let v = readFloat16(logits, at: tokenID)
            langLogits.append(v)
            if v > maxLogit { maxLogit = v }
        }
        guard maxLogit.isFinite else { return nil }
        var expSum: Double = 0
        let exps = langLogits.map { v -> Double in
            let e = exp(Double(v - maxLogit))
            expSum += e
            return e
        }
        guard expSum > 0 else { return nil }

        var bestOffset = 0
        var bestProb: Double = 0
        for (idx, e) in exps.enumerated() {
            let p = e / expSum
            if p > bestProb {
                bestProb = p
                bestOffset = idx
            }
        }
        let bestToken = langRange.lowerBound + bestOffset
        let heProb = exps[AudioTranscriptionSupport.whisperHebrewToken - langRange.lowerBound] / expSum
        let enProb = exps[AudioTranscriptionSupport.whisperEnglishToken - langRange.lowerBound] / expSum
        let topCode: String
        if bestToken == AudioTranscriptionSupport.whisperHebrewToken {
            topCode = "he"
        } else if bestToken == AudioTranscriptionSupport.whisperEnglishToken {
            topCode = "en"
        } else {
            topCode = "other"
        }
        return LanguageProbeResult(
            topLanguageCode: topCode,
            topConfidence: bestProb,
            hebrewProbability: heProb,
            englishProbability: enProb
        )
    }

    // MARK: - Transcription

    func transcribe(samples: [Float],
                    modelDirectory: URL = AudioTranscriptionSupport.defaultIvritModelDirectory(),
                    computeMode: ParakeetComputeMode = .auto,
                    languageTokenID: Int = AudioTranscriptionSupport.whisperHebrewToken,
                    speaker: String? = nil,
                    progress: (@Sendable (Double) -> Void)? = nil) async throws -> ParakeetCoreMLTranscriber.TranscriptionResult {
        try Task.checkCancellation()
        let startTime = Date()
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        let duration = Double(samples.count) / AudioTranscriptionSupport.sampleRate
        let models = try loadModelsIfNeeded(directory: modelDirectory, computeMode: computeMode)
        try Task.checkCancellation()

        // Energy VAD: decode only active speech regions so silent meeting
        // intervals run instantaneously and cannot trigger Whisper hallucinations.
        var regions = AudioTranscriptionSupport.speechRegions(in: samples)
        let speechSeconds = regions.reduce(0.0) { $0 + ($1.endSec - $1.startSec) }
        if regions.isEmpty || speechSeconds > duration * 0.85 {
            regions = [(startSec: 0, endSec: duration)]
        }

        // Split any long speech region into <= 28 s chunks inside Whisper's 30 s window.
        var chunks: [(startSec: Double, endSec: Double)] = []
        let maxChunkSeconds = 28.0
        for region in regions {
            var cursor = region.startSec
            while cursor < region.endSec - 0.15 {
                let end = min(region.endSec, cursor + maxChunkSeconds)
                chunks.append((startSec: cursor, endSec: end))
                cursor = end
            }
        }
        guard !chunks.isEmpty else {
            return ParakeetCoreMLTranscriber.TranscriptionResult(
                segments: [],
                audioDurationSeconds: duration,
                elapsedSeconds: Date().timeIntervalSince(startTime)
            )
        }

        let candidates: [AudioTranscriptionSupport.HallucinationCandidate] = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var collected: [AudioTranscriptionSupport.HallucinationCandidate] = []
                    let sr = AudioTranscriptionSupport.sampleRate
                    for (idx, chunk) in chunks.enumerated() {
                        if Task.isCancelled { throw TranscriberError.cancelled }
                        let lo = max(0, Int(chunk.startSec * sr))
                        let hi = min(samples.count, Int(chunk.endSec * sr))
                        guard hi - lo >= Int(sr * 0.2) else { continue }
                        let slice = Array(samples[lo..<hi])
                        let decoded = try Self.decodeChunk(
                            slice,
                            models: models,
                            languageTokenID: languageTokenID
                        )
                        if !decoded.text.isEmpty {
                            collected.append(AudioTranscriptionSupport.HallucinationCandidate(
                                text: decoded.text,
                                startSec: chunk.startSec,
                                endSec: chunk.endSec,
                                avgProb: decoded.avgProb
                            ))
                        }
                        progress?(Double(idx + 1) / Double(chunks.count))
                    }
                    cont.resume(returning: collected)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }

        let kept = AudioTranscriptionSupport.filterHallucinations(candidates)
        let segments = kept.map { item in
            AudioTranscriptionSupport.TranscriptSegment(
                speaker: speaker,
                text: item.text,
                startSeconds: item.startSec,
                endSeconds: item.endSec
            )
        }
        return ParakeetCoreMLTranscriber.TranscriptionResult(
            segments: segments,
            audioDurationSeconds: duration,
            elapsedSeconds: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Core ML Chunk Encoding & KV-Cached Autoregressive Decoding

    private static func encodeChunk(_ samples: [Float], models: LoadedModels) throws -> MLMultiArray {
        let count = AudioTranscriptionSupport.whisperWindowSamples
        let audioArray = try MLMultiArray(shape: [NSNumber(value: count)], dataType: .float16)
        let copyCount = min(samples.count, count)
        audioArray.withUnsafeMutableBytes { raw, _ in
            let ptr = raw.bindMemory(to: Float16.self)
            for i in 0..<copyCount {
                ptr[i] = Float16(samples[i])
            }
            if copyCount < count {
                for i in copyCount..<count {
                    ptr[i] = 0
                }
            }
        }

        let melInput = try MLDictionaryFeatureProvider(dictionary: [
            "audio": MLFeatureValue(multiArray: audioArray),
        ])
        let melOut = try models.mel.prediction(from: melInput)
        guard let melFeatures = melOut.featureValue(for: "melspectrogram_features")?.multiArrayValue else {
            throw TranscriberError.inferenceFailed("MelSpectrogram did not return melspectrogram_features")
        }

        let encInput = try MLDictionaryFeatureProvider(dictionary: [
            "melspectrogram_features": MLFeatureValue(multiArray: melFeatures),
        ])
        let encOut = try models.encoder.prediction(from: encInput)
        guard let embeds = encOut.featureValue(for: "encoder_output_embeds")?.multiArrayValue else {
            throw TranscriberError.inferenceFailed("AudioEncoder did not return encoder_output_embeds")
        }
        return embeds
    }

    private static func decodeChunk(_ samples: [Float],
                                    models: LoadedModels,
                                    languageTokenID: Int) throws -> (text: String, avgProb: Double) {
        let encoderOutput = try encodeChunk(samples, models: models)
        let maxSeq = AudioTranscriptionSupport.whisperMaxTokens
        let kvDim = 5_120
        let vocabSize = AudioTranscriptionSupport.whisperVocabSize

        let inputIds = try MLMultiArray(shape: [1], dataType: .int32)
        let cacheLength = try MLMultiArray(shape: [1], dataType: .int32)
        let keyCache = try MLMultiArray(shape: [1, NSNumber(value: kvDim), 1, NSNumber(value: maxSeq)], dataType: .float16)
        let valueCache = try MLMultiArray(shape: [1, NSNumber(value: kvDim), 1, NSNumber(value: maxSeq)], dataType: .float16)
        let updateMask = try MLMultiArray(shape: [1, NSNumber(value: maxSeq)], dataType: .float16)
        let paddingMask = try MLMultiArray(shape: [1, NSNumber(value: maxSeq)], dataType: .float16)

        zeroFill(keyCache)
        zeroFill(valueCache)
        zeroFill(updateMask)
        fillFloat16(paddingMask, value: -10_000.0)

        let prefill = [
            AudioTranscriptionSupport.whisperSOTToken,
            languageTokenID,
            AudioTranscriptionSupport.whisperTranscribeToken,
            AudioTranscriptionSupport.whisperNoTimestampsToken,
        ]

        var emittedTokens: [Int] = []
        var probSum: Double = 0
        var probCount = 0
        var nextToken = prefill[0]
        let maxSteps = min(224, maxSeq - 1)

        // Simple repeat-loop breaker so greedy decoding can never stall on a single token.
        var lastToken = -1
        var sameTokenRun = 0

        for step in 0..<maxSteps {
            if step < prefill.count {
                nextToken = prefill[step]
            }

            inputIds[0] = NSNumber(value: Int32(nextToken))
            cacheLength[0] = NSNumber(value: Int32(step))
            if step > 0 { setFloat16(updateMask, at: step - 1, value: 0.0) }
            setFloat16(updateMask, at: step, value: 1.0)
            setFloat16(paddingMask, at: step, value: 0.0)

            let provider = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": MLFeatureValue(multiArray: inputIds),
                "cache_length": MLFeatureValue(multiArray: cacheLength),
                "key_cache": MLFeatureValue(multiArray: keyCache),
                "value_cache": MLFeatureValue(multiArray: valueCache),
                "kv_cache_update_mask": MLFeatureValue(multiArray: updateMask),
                "encoder_output_embeds": MLFeatureValue(multiArray: encoderOutput),
                "decoder_key_padding_mask": MLFeatureValue(multiArray: paddingMask),
            ])
            let output = try models.decoder.prediction(from: provider)
            guard let logits = output.featureValue(for: "logits")?.multiArrayValue,
                  let keyUpdate = output.featureValue(for: "key_cache_updates")?.multiArrayValue,
                  let valUpdate = output.featureValue(for: "value_cache_updates")?.multiArrayValue else {
                throw TranscriberError.inferenceFailed("TextDecoder missing expected outputs")
            }

            updateKVCache(keyCache: keyCache, keyUpdate: keyUpdate,
                          valueCache: valueCache, valueUpdate: valUpdate,
                          at: step)

            guard step >= prefill.count - 1 else { continue }

            // Greedy argmax over valid text + EOT tokens (suppress special tokens > EOT,
            // and suppress blank/space token 220 on the very first generated token).
            let suppressBlankFirst = emittedTokens.isEmpty
            let (chosenID, chosenProb) = argmaxWithProbability(
                logits: logits,
                vocabSize: vocabSize,
                suppressBlank: suppressBlankFirst
            )

            if chosenID == AudioTranscriptionSupport.whisperEOTToken {
                break
            }
            if chosenID == lastToken {
                sameTokenRun += 1
                if sameTokenRun >= 6 { break }
            } else {
                lastToken = chosenID
                sameTokenRun = 1
            }

            if chosenID < AudioTranscriptionSupport.whisperEOTToken {
                emittedTokens.append(chosenID)
                probSum += chosenProb
                probCount += 1
            }
            nextToken = chosenID
        }

        let text = AudioTranscriptionSupport.decodeWhisperTokens(emittedTokens, vocab: models.vocabulary)
        let avgProb = probCount > 0 ? probSum / Double(probCount) : 0
        return (text, avgProb)
    }

    // MARK: - Low-Level Float16 Tensor Helpers

    private static func zeroFill(_ array: MLMultiArray) {
        array.withUnsafeMutableBytes { raw, _ in
            if let base = raw.baseAddress {
                memset(base, 0, raw.count)
            }
        }
    }

    private static func fillFloat16(_ array: MLMultiArray, value: Float) {
        let f16 = Float16(value)
        array.withUnsafeMutableBytes { raw, _ in
            let ptr = raw.bindMemory(to: Float16.self)
            for i in 0..<ptr.count { ptr[i] = f16 }
        }
    }

    private static func setFloat16(_ array: MLMultiArray, at index: Int, value: Float) {
        array.withUnsafeMutableBytes { raw, _ in
            let ptr = raw.bindMemory(to: Float16.self)
            if index >= 0, index < ptr.count {
                ptr[index] = Float16(value)
            }
        }
    }

    private static func readFloat16(_ array: MLMultiArray, at index: Int) -> Float {
        array.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: Float16.self)
            guard index >= 0, index < ptr.count else { return -.infinity }
            return Float(ptr[index])
        }
    }

    private static func updateKVCache(keyCache: MLMultiArray,
                                      keyUpdate: MLMultiArray,
                                      valueCache: MLMultiArray,
                                      valueUpdate: MLMultiArray,
                                      at step: Int) {
        let dim = keyCache.shape[1].intValue
        let kDestStride1 = keyCache.strides[1].intValue
        let kDestStride3 = keyCache.strides[3].intValue
        let kSrcStride1 = keyUpdate.strides[1].intValue
        let vDestStride1 = valueCache.strides[1].intValue
        let vDestStride3 = valueCache.strides[3].intValue
        let vSrcStride1 = valueUpdate.strides[1].intValue

        keyCache.withUnsafeMutableBytes { kDestRaw, _ in
            keyUpdate.withUnsafeBytes { kSrcRaw in
                valueCache.withUnsafeMutableBytes { vDestRaw, _ in
                    valueUpdate.withUnsafeBytes { vSrcRaw in
                        let kDest = kDestRaw.bindMemory(to: Float16.self)
                        let kSrc = kSrcRaw.bindMemory(to: Float16.self)
                        let vDest = vDestRaw.bindMemory(to: Float16.self)
                        let vSrc = vSrcRaw.bindMemory(to: Float16.self)
                        let kColOffset = step * kDestStride3
                        let vColOffset = step * vDestStride3
                        for j in 0..<dim {
                            kDest[j * kDestStride1 + kColOffset] = kSrc[j * kSrcStride1]
                            vDest[j * vDestStride1 + vColOffset] = vSrc[j * vSrcStride1]
                        }
                    }
                }
            }
        }
    }

    private static func argmaxWithProbability(logits: MLMultiArray,
                                              vocabSize: Int,
                                              suppressBlank: Bool) -> (tokenID: Int, probability: Double) {
        logits.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: Float16.self)
            let limit = min(vocabSize, ptr.count)
            let maxCandidate = min(AudioTranscriptionSupport.whisperEOTToken + 1, limit)
            var bestID = AudioTranscriptionSupport.whisperEOTToken
            var bestVal: Float = -.infinity
            for id in 0..<maxCandidate {
                if suppressBlank, id == 220 { continue }
                let v = Float(ptr[id])
                if v > bestVal {
                    bestVal = v
                    bestID = id
                }
            }
            guard bestVal.isFinite else { return (AudioTranscriptionSupport.whisperEOTToken, 0) }
            // Compute softmax denominator over candidate tokens for segment confidence.
            var expSum: Double = 0
            for id in 0..<maxCandidate {
                if suppressBlank, id == 220 { continue }
                let diff = Float(ptr[id]) - bestVal
                if diff > -20 {
                    expSum += exp(Double(diff))
                }
            }
            let prob = expSum > 0 ? 1.0 / expSum : 0
            return (bestID, prob)
        }
    }
}
