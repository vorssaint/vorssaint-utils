// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Compute-unit preference for Core ML transcription inference.
enum ParakeetComputeMode: String, CaseIterable, Identifiable, Sendable {
    case auto
    case cpuAndGPU
    case cpuOnly

    var id: String { rawValue }
}

/// Model routing preference for local Core ML transcription & dictation.
/// `auto` probes the spoken language on each recording and
/// routes English to Parakeet Unified 0.6B and Hebrew to ivrit.ai Whisper
/// Large v3 Turbo.
enum TranscriptionModelChoice: String, CaseIterable, Identifiable, Sendable {
    case auto
    case parakeetEnglish
    case ivritHebrew

    var id: String { rawValue }
}

/// Global shortcut trigger behavior for system-wide voice dictation.
enum DictationTriggerMode: String, CaseIterable, Identifiable, Sendable {
    case toggle
    case holdToTalk

    var id: String { rawValue }
}

/// Pure manifest, token-merging, SentencePiece detokenization, and transcript
/// formatting helpers for NVIDIA Parakeet Unified English 0.6B (Core ML).
/// Kept free of AppKit and CoreML so unit tests pin every edge case.
enum AudioTranscriptionSupport {
    /// Exact Hugging Face repository for compiled Core ML Parakeet Unified 0.6B.
    static let modelDisplayName = "Parakeet Unified English 0.6B"
    static let modelRepoID = "FluidInference/parakeet-unified-en-0.6b-coreml"
    static let modelFolderName = "parakeet-unified-en-0.6b-coreml"
    static let sampleRate: Double = 16_000
    static let windowSeconds: Double = 15.0
    static let windowSamples = 240_000
    static let overlapSeconds: Double = 2.0
    static let overlapSamples = 32_000
    static let hopSamples = windowSamples - overlapSamples
    static let frameSamples = 1280 // 80 ms per encoder frame at 16 kHz (subsampling 8 * hop 160)
    static let melFrames = 1501
    static let melBins = 128
    static let encoderHiddenSize = 1024
    static let decoderHiddenSize = 640
    static let decoderLayers = 2
    static let blankTokenID = 1024

    struct ModelFileSpec: Equatable, Sendable {
        let relativePath: String
        let expectedBytes: Int64
    }

    /// The exact 18 files required for offline batch INT8 Core ML inference
    /// (~614.7 MB total: preprocessor + INT8 encoder + RNNT decoder + single-step joint + vocab + metadata).
    static let requiredModelFiles: [ModelFileSpec] = [
        ModelFileSpec(relativePath: "metadata.json", expectedBytes: 1_046),
        ModelFileSpec(relativePath: "vocab.json", expectedBytes: 15_088),
        ModelFileSpec(relativePath: "parakeet_unified_preprocessor.mlmodelc/analytics/coremldata.bin", expectedBytes: 243),
        ModelFileSpec(relativePath: "parakeet_unified_preprocessor.mlmodelc/coremldata.bin", expectedBytes: 495),
        ModelFileSpec(relativePath: "parakeet_unified_preprocessor.mlmodelc/model.mil", expectedBytes: 29_955),
        ModelFileSpec(relativePath: "parakeet_unified_preprocessor.mlmodelc/weights/weight.bin", expectedBytes: 592_384),
        ModelFileSpec(relativePath: "parakeet_unified_encoder_int8.mlmodelc/analytics/coremldata.bin", expectedBytes: 243),
        ModelFileSpec(relativePath: "parakeet_unified_encoder_int8.mlmodelc/coremldata.bin", expectedBytes: 492),
        ModelFileSpec(relativePath: "parakeet_unified_encoder_int8.mlmodelc/model.mil", expectedBytes: 1_110_902),
        ModelFileSpec(relativePath: "parakeet_unified_encoder_int8.mlmodelc/weights/weight.bin", expectedBytes: 595_051_904),
        ModelFileSpec(relativePath: "parakeet_unified_decoder.mlmodelc/analytics/coremldata.bin", expectedBytes: 243),
        ModelFileSpec(relativePath: "parakeet_unified_decoder.mlmodelc/coremldata.bin", expectedBytes: 560),
        ModelFileSpec(relativePath: "parakeet_unified_decoder.mlmodelc/model.mil", expectedBytes: 13_102),
        ModelFileSpec(relativePath: "parakeet_unified_decoder.mlmodelc/weights/weight.bin", expectedBytes: 14_429_952),
        ModelFileSpec(relativePath: "parakeet_unified_joint_decision_single_step.mlmodelc/analytics/coremldata.bin", expectedBytes: 243),
        ModelFileSpec(relativePath: "parakeet_unified_joint_decision_single_step.mlmodelc/coremldata.bin", expectedBytes: 556),
        ModelFileSpec(relativePath: "parakeet_unified_joint_decision_single_step.mlmodelc/model.mil", expectedBytes: 9_611),
        ModelFileSpec(relativePath: "parakeet_unified_joint_decision_single_step.mlmodelc/weights/weight.bin", expectedBytes: 3_446_978),
    ]

    static let totalExpectedModelBytes: Int64 = requiredModelFiles.reduce(0) { $0 + $1.expectedBytes }

    static func downloadURL(for relativePath: String) -> URL {
        URL(string: "https://huggingface.co/\(modelRepoID)/resolve/main/\(relativePath)")!
    }

    static func defaultModelDirectory(
        appSupportDirectory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    ) -> URL {
        let base = appSupportDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("Vorssaint", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(modelFolderName, isDirectory: true)
    }

    /// Returns true only when every required model artifact is present and
    /// plausibly complete (>= 90% of expected size so truncated downloads fail).
    static func isModelDirectoryReady(_ dir: URL, fileManager: FileManager = .default) -> Bool {
        for spec in requiredModelFiles {
            let url = dir.appendingPathComponent(spec.relativePath)
            guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? NSNumber else {
                return false
            }
            let minBytes = max(1, spec.expectedBytes * 9 / 10)
            if size.int64Value < minBytes { return false }
        }
        return true
    }

    static func directorySizeBytes(_ dir: URL, fileManager: FileManager = .default) -> Int64 {
        var total: Int64 = 0
        for spec in requiredModelFiles {
            let url = dir.appendingPathComponent(spec.relativePath)
            if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        return total
    }

    // MARK: - Supported Audio Files

    static let supportedExtensions: Set<String> = [
        "wav", "m4a", "mp3", "aiff", "aif", "caf", "flac", "aac", "mp4", "mov", "m4v", "ogg",
    ]

    static func isSupportedAudioURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Token Decoding & Window Merging

    struct EmittedToken: Equatable, Sendable {
        let id: Int
        let frame: Int
        let probability: Float
    }

    struct TranscriptSegment: Identifiable, Equatable, Sendable {
        let id: String
        let speaker: String?
        let text: String
        let startSeconds: Double
        let endSeconds: Double

        init(speaker: String? = nil, text: String, startSeconds: Double, endSeconds: Double) {
            self.id = "\(speaker ?? "")-\(Int((startSeconds * 100).rounded()))-\(text.hashValue)"
            self.speaker = speaker
            self.text = text
            self.startSeconds = startSeconds
            self.endSeconds = endSeconds
        }
    }

    /// Parses Hugging Face `vocab.json` (`{"0": "<unk>", "1": "▁t", ...}`).
    static func parseVocabulary(data: Data) throws -> [Int: String] {
        let raw = try JSONDecoder().decode([String: String].self, from: data)
        var vocab: [Int: String] = [:]
        vocab.reserveCapacity(raw.count)
        for (key, piece) in raw {
            if let id = Int(key) {
                vocab[id] = piece
            }
        }
        return vocab
    }

    /// Merges two consecutive overlapping 15-second windows (`overlapStartFrame`..`overlapEndFrame`).
    /// Prefers an exact multi-token anchor match inside the seam; falls back to
    /// splitting cleanly at the overlap midpoint and dropping duplicate boundary tokens.
    static func mergeWindowTokens(existing: [EmittedToken],
                                  incoming: [EmittedToken],
                                  overlapStartFrame: Int,
                                  overlapEndFrame: Int) -> [EmittedToken] {
        guard !existing.isEmpty else { return incoming }
        guard !incoming.isEmpty else { return existing }

        let leftTail = existing.enumerated().filter { $0.element.frame >= overlapStartFrame - 4 }
        let rightHead = incoming.enumerated().filter { $0.element.frame <= overlapEndFrame + 4 }

        // Look for the longest matching token-id run (length >= 2) in the seam.
        var bestLen = 0
        var bestLeftIdx = -1
        var bestRightIdx = -1
        for li in 0..<leftTail.count {
            for ri in 0..<rightHead.count {
                guard leftTail[li].element.id == rightHead[ri].element.id else { continue }
                // Require rough frame proximity (within 10 frames = 0.8s)
                guard abs(leftTail[li].element.frame - rightHead[ri].element.frame) <= 10 else { continue }
                var len = 0
                while li + len < leftTail.count,
                      ri + len < rightHead.count,
                      leftTail[li + len].element.id == rightHead[ri + len].element.id {
                    len += 1
                }
                if len > bestLen {
                    bestLen = len
                    bestLeftIdx = leftTail[li].offset
                    bestRightIdx = rightHead[ri].offset
                }
            }
        }

        if bestLen >= 2, bestLeftIdx >= 0, bestRightIdx >= 0 {
            return Array(existing[..<bestLeftIdx]) + Array(incoming[bestRightIdx...])
        }

        // Fallback: split cleanly at overlap midpoint.
        let midpoint = (overlapStartFrame + overlapEndFrame) / 2
        let leftKept = existing.filter { $0.frame <= midpoint }
        var rightKept = incoming.filter { $0.frame > midpoint }
        if let lastLeft = leftKept.last, let firstRight = rightKept.first,
           lastLeft.id == firstRight.id, abs(firstRight.frame - lastLeft.frame) <= 4 {
            rightKept.removeFirst()
        }
        return leftKept + rightKept
    }

    /// Converts SentencePiece tokens into clean sentence-level timestamped segments.
    static func segments(from tokens: [EmittedToken],
                         vocabulary: [Int: String],
                         speaker: String? = nil,
                         frameDurationSeconds: Double = Double(frameSamples) / sampleRate) -> [TranscriptSegment] {
        var result: [TranscriptSegment] = []
        var pieces: [String] = []
        var segStart: Double = 0
        var segEnd: Double = 0
        var lastFrame: Int?

        func flush() {
            let text = cleanDetokenizedText(pieces)
            if !text.isEmpty {
                result.append(TranscriptSegment(
                    speaker: speaker,
                    text: text,
                    startSeconds: segStart,
                    endSeconds: max(segStart, segEnd)
                ))
            }
            pieces.removeAll(keepingCapacity: true)
        }

        let validTokens = tokens.compactMap { token -> (token: EmittedToken, piece: String)? in
            guard token.id != blankTokenID,
                  let piece = vocabulary[token.id],
                  piece != "<unk>", piece != "<pad>", piece != "<s>", piece != "</s>" else {
                return nil
            }
            return (token, piece)
        }

        for (index, entry) in validTokens.enumerated() {
            let token = entry.token
            let piece = entry.piece
            let ts = Double(token.frame) * frameDurationSeconds
            let pause = lastFrame.map { Double(token.frame - $0) * frameDurationSeconds } ?? 0

            if pieces.isEmpty {
                segStart = ts
            } else if pause > 1.2 || (ts - segStart) > 15.0 {
                // Only break mid-sentence on pause/length if the new piece starts a word.
                if piece.hasPrefix("\u{2581}") || pause > 1.8 {
                    flush()
                    segStart = ts
                }
            }

            pieces.append(piece)
            segEnd = ts + frameDurationSeconds
            lastFrame = token.frame

            // Only split on sentence-ending punctuation when the next token
            // begins a new word (prevents splitting decimals like "0.6").
            let nextStartsWord = index + 1 >= validTokens.count
                || validTokens[index + 1].piece.hasPrefix("\u{2581}")
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            if nextStartsWord,
               let lastScalar = trimmed.unicodeScalars.last,
               CharacterSet(charactersIn: ".!?").contains(lastScalar),
               (ts - segStart) >= 1.0 {
                flush()
            }
        }
        flush()
        return result
    }

    static func cleanDetokenizedText(_ pieces: [String]) -> String {
        let joined = pieces.joined().replacingOccurrences(of: "\u{2581}", with: " ")
        let collapsed = joined
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Chronologically merges dual-track meeting transcripts (`You` + `Others`).
    static func mergeSpeakerSegments(systemSegments: [TranscriptSegment],
                                     micSegments: [TranscriptSegment]) -> [TranscriptSegment] {
        (systemSegments + micSegments).sorted { lhs, rhs in
            if abs(lhs.startSeconds - rhs.startSeconds) > 0.001 {
                return lhs.startSeconds < rhs.startSeconds
            }
            return (lhs.speaker ?? "") < (rhs.speaker ?? "")
        }
    }

    /// Formats segments as human-readable transcript text with optional `[M:SS]`
    /// timestamps and speaker prefixes.
    static func formatTranscript(segments: [TranscriptSegment], includeTimestamps: Bool) -> String {
        guard !segments.isEmpty else { return "" }
        if !includeTimestamps && segments.allSatisfy({ $0.speaker == nil }) {
            return segments.map(\.text).joined(separator: " ")
        }
        return segments.map { seg in
            var prefix = ""
            if includeTimestamps {
                prefix += "[\(MeetingRecorderSupport.elapsedLabel(seconds: Int(seg.startSeconds.rounded(.down))))] "
            }
            if let speaker = seg.speaker, !speaker.isEmpty {
                prefix += "\(speaker): "
            }
            return prefix + seg.text
        }.joined(separator: "\n")
    }

    static func transcriptFileURL(forAudioURL audioURL: URL) -> URL {
        let dir = audioURL.deletingLastPathComponent()
        let stem = audioURL.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(stem)-transcript.txt")
    }

    static func meetingTranscriptFileURL(stem: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(stem)-transcript.txt")
    }

    // MARK: - Summary Support

    static let defaultSummaryPrompt = "Summarize this transcript concisely with key points, decisions, and action items."

    static func resolvedSummaryPrompt(_ custom: String?) -> String {
        let trimmed = custom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultSummaryPrompt : trimmed
    }

    static func summaryFileURL(forAudioURL audioURL: URL) -> URL {
        let dir = audioURL.deletingLastPathComponent()
        let stem = audioURL.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(stem)-summary.md")
    }

    static func meetingSummaryFileURL(stem: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(stem)-summary.md")
    }

    /// Splits a long transcript into bounded chunks along newline or sentence
    /// boundaries so on-device models stay within their context window.
    static func summaryChunks(for transcript: String, maxCharacters: Int = 8_000) -> [String] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let limit = max(500, maxCharacters)
        if trimmed.count <= limit { return [trimmed] }

        var chunks: [String] = []
        var current = ""
        let lines = trimmed.components(separatedBy: .newlines)
        for line in lines {
            let piece = line.trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else { continue }
            if !current.isEmpty, current.count + piece.count + 1 > limit {
                chunks.append(current)
                current = ""
            }
            if piece.count > limit {
                if !current.isEmpty {
                    chunks.append(current)
                    current = ""
                }
                var start = piece.startIndex
                while start < piece.endIndex {
                    let end = piece.index(start, offsetBy: limit, limitedBy: piece.endIndex) ?? piece.endIndex
                    chunks.append(String(piece[start..<end]))
                    start = end
                }
            } else {
                current = current.isEmpty ? piece : (current + "\n" + piece)
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Deterministic local extractive fallback used when Apple Intelligence /
    /// FoundationModels is unavailable. Strips timestamps, scores sentences by
    /// keyword salience and prompt cues, and preserves chronological flow.
    static func fallbackExtractiveSummary(transcript: String, prompt: String) -> String {
        let strippedLines = transcript
            .components(separatedBy: .newlines)
            .map { line -> String in
                var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
                // Strip leading [M:SS] or [H:MM:SS] timestamp prefixes if present.
                if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
                    let after = text.index(after: close)
                    text = String(text[after...]).trimmingCharacters(in: .whitespaces)
                }
                return text
            }
            .filter { !$0.isEmpty }
        guard !strippedLines.isEmpty else { return "" }

        var sentences: [String] = []
        for line in strippedLines {
            var buffer = ""
            for ch in line {
                buffer.append(ch)
                if ch == "." || ch == "!" || ch == "?" {
                    let clean = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if clean.count >= 12 { sentences.append(clean) }
                    buffer = ""
                }
            }
            let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { sentences.append(tail) }
        }
        if sentences.isEmpty { sentences = strippedLines }

        let promptLower = resolvedSummaryPrompt(prompt).lowercased()
        let wantsBrief = promptLower.contains("brief") || promptLower.contains("short") || promptLower.contains("tldr") || promptLower.contains("tl;dr")
        let wantsBullets = !promptLower.contains("paragraph") && !promptLower.contains("prose")
        let maxPoints = wantsBrief ? 3 : min(6, max(3, Int(ceil(Double(sentences.count) * 0.3))))

        if sentences.count <= maxPoints {
            return wantsBullets
                ? sentences.map { "- \($0)" }.joined(separator: "\n")
                : sentences.joined(separator: " ")
        }

        let stopWords: Set<String> = [
            "the", "and", "for", "that", "this", "with", "from", "have", "were", "will",
            "would", "could", "should", "about", "there", "their", "they", "them", "been",
            "into", "just", "like", "your", "what", "when", "where", "which", "while",
            "also", "very", "more", "some", "than", "then", "only", "over", "such", "make",
            "you", "others", "yeah", "okay", "right", "well", "know", "think", "really",
        ]
        func words(in text: String) -> [String] {
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 && !stopWords.contains($0) }
        }

        var freq: [String: Int] = [:]
        for s in sentences {
            for w in words(in: s) { freq[w, default: 0] += 1 }
        }
        let promptKeywords = Set(words(in: promptLower))
        let actionCues = ["action", "todo", "follow up", "decide", "decided", "decision", "next", "deadline", "ship", "need to", "will "]

        let scored: [(index: Int, score: Double)] = sentences.enumerated().map { idx, s in
            let w = words(in: s)
            guard !w.isEmpty else { return (idx, 0) }
            let tfSum = w.reduce(0.0) { $0 + Double(freq[$1] ?? 1) }
            var score = tfSum / sqrt(Double(w.count))
            let lower = s.lowercased()
            if promptKeywords.contains(where: { lower.contains($0) }) { score *= 1.2 }
            if actionCues.contains(where: { lower.contains($0) }) { score *= 1.25 }
            if idx == 0 || idx == sentences.count - 1 { score *= 1.15 }
            return (idx, score)
        }

        let chosenIndices = Set(
            scored.sorted { $0.score > $1.score }
                .prefix(maxPoints)
                .map(\.index)
        )
        let selected = sentences.enumerated()
            .filter { chosenIndices.contains($0.offset) }
            .map(\.element)

        return wantsBullets
            ? selected.map { "- \($0)" }.joined(separator: "\n")
            : selected.joined(separator: " ")
    }

    // MARK: - Hebrew Specialist Model (ivrit.ai Whisper Large v3 Turbo Core ML)

    static let ivritModelDisplayName = "ivrit.ai Whisper Large v3 Turbo (Hebrew)"
    static let ivritModelRepoID = "eranshir/ivrit-ai-whisper-large-v3-turbo-coreml-int8"
    static let ivritModelFolderName = "ivrit-ai-whisper-large-v3-turbo-coreml-int8"
    static let whisperWindowSamples = 480_000 // 30 s @ 16 kHz
    static let whisperMaxTokens = 448
    static let whisperVocabSize = 51_866
    static let whisperEOTToken = 50_257
    static let whisperSOTToken = 50_258
    static let whisperEnglishToken = 50_259
    static let whisperHebrewToken = 50_279
    static let whisperTranscribeToken = 50_360
    static let whisperNoTimestampsToken = 50_364
    static let whisperFirstTimestampToken = 50_365
    static let whisperLanguageTokenRange = 50_259..<50_359

    /// Exact verified files for `eranshir/ivrit-ai-whisper-large-v3-turbo-coreml-int8`
    /// (~896 MB total: MelSpectrogram + 8-bit AudioEncoder + 8.5-bit KV-cached TextDecoder + vocab/config).
    static let ivritRequiredModelFiles: [ModelFileSpec] = [
        ModelFileSpec(relativePath: "config.json", expectedBytes: 1_230),
        ModelFileSpec(relativePath: "vocab.json", expectedBytes: 1_036_558),
        ModelFileSpec(relativePath: "MelSpectrogram.mlmodelc/analytics/coremldata.bin", expectedBytes: 243),
        ModelFileSpec(relativePath: "MelSpectrogram.mlmodelc/coremldata.bin", expectedBytes: 390),
        ModelFileSpec(relativePath: "MelSpectrogram.mlmodelc/metadata.json", expectedBytes: 1_949),
        ModelFileSpec(relativePath: "MelSpectrogram.mlmodelc/model.mil", expectedBytes: 10_143),
        ModelFileSpec(relativePath: "MelSpectrogram.mlmodelc/weights/weight.bin", expectedBytes: 373_376),
        ModelFileSpec(relativePath: "AudioEncoder.mlmodelc/analytics/coremldata.bin", expectedBytes: 243),
        ModelFileSpec(relativePath: "AudioEncoder.mlmodelc/coremldata.bin", expectedBytes: 409),
        ModelFileSpec(relativePath: "AudioEncoder.mlmodelc/metadata.json", expectedBytes: 2_020),
        ModelFileSpec(relativePath: "AudioEncoder.mlmodelc/model.mil", expectedBytes: 9_791_975),
        ModelFileSpec(relativePath: "AudioEncoder.mlmodelc/weights/weight.bin", expectedBytes: 639_533_824),
        ModelFileSpec(relativePath: "TextDecoder.mlmodelc/analytics/coremldata.bin", expectedBytes: 243),
        ModelFileSpec(relativePath: "TextDecoder.mlmodelc/coremldata.bin", expectedBytes: 694),
        ModelFileSpec(relativePath: "TextDecoder.mlmodelc/metadata.json", expectedBytes: 4_951),
        ModelFileSpec(relativePath: "TextDecoder.mlmodelc/model.mil", expectedBytes: 141_703),
        ModelFileSpec(relativePath: "TextDecoder.mlmodelc/weights/weight.bin", expectedBytes: 245_652_212),
    ]

    static let totalExpectedIvritModelBytes: Int64 = ivritRequiredModelFiles.reduce(0) { $0 + $1.expectedBytes }

    static func ivritDownloadURL(for relativePath: String) -> URL {
        URL(string: "https://huggingface.co/\(ivritModelRepoID)/resolve/main/\(relativePath)")!
    }

    static func defaultIvritModelDirectory(
        appSupportDirectory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    ) -> URL {
        let base = appSupportDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("Vorssaint", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(ivritModelFolderName, isDirectory: true)
    }

    static func isIvritModelDirectoryReady(_ directory: URL) -> Bool {
        let fm = FileManager.default
        for spec in ivritRequiredModelFiles {
            let fileURL = directory.appendingPathComponent(spec.relativePath)
            guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
                  let size = attrs[.size] as? Int64,
                  size > 0 else {
                return false
            }
            if spec.expectedBytes > 10_000, size < (spec.expectedBytes * 9) / 10 {
                return false
            }
        }
        return true
    }

    static func ivritDirectorySizeBytes(_ dir: URL, fileManager: FileManager = .default) -> Int64 {
        var total: Int64 = 0
        for spec in ivritRequiredModelFiles {
            let url = dir.appendingPathComponent(spec.relativePath)
            if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        return total
    }

    // MARK: - Language Routing & Hebrew Detection

    enum ResolvedEngine: Equatable, Sendable {
        case parakeetEnglish
        case ivritHebrew
    }

    /// Routes one recording to the best installed local model using
    /// confidence-gated specialist routing: Hebrew with confidence
    /// >= 0.6 goes to ivrit.ai Whisper Large v3 Turbo; English goes to Parakeet
    /// Unified 0.6B; falls back gracefully when only one model is installed.
    static func routeModel(choice: TranscriptionModelChoice,
                           detectedLanguage: String?,
                           confidence: Double,
                           parakeetReady: Bool,
                           ivritReady: Bool) -> ResolvedEngine? {
        switch choice {
        case .parakeetEnglish:
            return parakeetReady ? .parakeetEnglish : nil
        case .ivritHebrew:
            return ivritReady ? .ivritHebrew : nil
        case .auto:
            let code = detectedLanguage.map { String($0.prefix(2)).lowercased() }
            let isHebrew = (code == "he" || code == "iw") && confidence >= 0.6
            if isHebrew {
                if ivritReady { return .ivritHebrew }
                if parakeetReady { return .parakeetEnglish }
                return nil
            }
            if parakeetReady { return .parakeetEnglish }
            if ivritReady { return .ivritHebrew }
            return nil
        }
    }

    /// Mila-style RTL detection: true when `text` has more Hebrew letters
    /// (U+0590..U+05FF) than Latin letters (A-Z / a-z), so quoted English brand
    /// names embedded in a Hebrew sentence do not flip RTL layout.
    static func isPredominantlyHebrew(_ text: String) -> Bool {
        var hebrew = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if v >= 0x0590 && v <= 0x05FF {
                hebrew += 1
            } else if (v >= 0x0041 && v <= 0x005A) || (v >= 0x0061 && v <= 0x007A) {
                latin += 1
            }
        }
        return hebrew > latin
    }

    /// Recall-first energy VAD over 16 kHz mono samples so long
    /// silences are skipped before Whisper decoding (faster + prevents silence
    /// hallucinations).
    static func speechRegions(in samples: [Float], sampleRate: Double = sampleRate) -> [(startSec: Double, endSec: Double)] {
        let frame = Int(sampleRate * 0.02)
        guard samples.count >= frame * 10 else {
            return samples.isEmpty ? [] : [(0, Double(samples.count) / sampleRate)]
        }
        var levels: [Float] = []
        levels.reserveCapacity(samples.count / frame)
        var i = 0
        while i + frame <= samples.count {
            var sum: Float = 0
            for s in samples[i..<(i + frame)] { sum += s * s }
            levels.append(10 * log10(sum / Float(frame) + 1e-12))
            i += frame
        }
        let sorted = levels.sorted()
        let floor = sorted[max(0, sorted.count * 15 / 100)]
        let threshold = min(max(floor + 7, -58), -33)

        let frameSec = Double(frame) / sampleRate
        let pad = 0.35
        let mergeGap = 0.9
        let minLen = 0.25
        var regions: [(startSec: Double, endSec: Double)] = []
        var runStart: Int?

        func closeRun(endFrame: Int) {
            guard let s = runStart else { return }
            runStart = nil
            let start = Double(s) * frameSec
            let end = Double(endFrame) * frameSec
            guard end - start >= minLen else { return }
            let padded = (startSec: max(0, start - pad),
                          endSec: min(Double(samples.count) / sampleRate, end + pad))
            if let last = regions.last, padded.startSec - last.endSec < mergeGap {
                regions[regions.count - 1].endSec = padded.endSec
            } else {
                regions.append(padded)
            }
        }

        for (idx, level) in levels.enumerated() {
            if level > threshold {
                if runStart == nil { runStart = idx }
            } else {
                closeRun(endFrame: idx)
            }
        }
        closeRun(endFrame: levels.count)
        let duration = Double(samples.count) / sampleRate
        return regions.map { r in
            let len = r.endSec - r.startSec
            guard len < 1.5 else { return r }
            let grow = (1.5 - len) / 2
            return (startSec: max(0, r.startSec - grow), endSec: min(duration, r.endSec + grow))
        }
    }

    struct SpeechChunk: Equatable, Sendable {
        let startSec: Double
        let endSec: Double
    }

    /// Splits an audio clip into bounded VAD speech chunks (each <= `maxChunkSeconds`)
    /// so bilingual ("Heblish") recordings can probe language and route each speech
    /// segment independently to the best local engine.
    static func languageRoutingChunks(in samples: [Float],
                                      sampleRate: Double = sampleRate,
                                      maxChunkSeconds: Double = 28.0) -> [SpeechChunk] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }
        let duration = Double(samples.count) / sampleRate
        let regions = speechRegions(in: samples, sampleRate: sampleRate)
        let sourceRegions: [(startSec: Double, endSec: Double)] = regions.isEmpty
            ? [(startSec: 0, endSec: duration)]
            : regions

        let cap = max(4.0, maxChunkSeconds)
        var chunks: [SpeechChunk] = []
        for region in sourceRegions {
            var cursor = region.startSec
            while cursor < region.endSec - 0.15 {
                let end = min(region.endSec, cursor + cap)
                chunks.append(SpeechChunk(startSec: cursor, endSec: end))
                cursor = end
            }
        }
        if chunks.isEmpty {
            chunks.append(SpeechChunk(startSec: 0, endSec: duration))
        }
        return chunks
    }

    /// Shifts segment timestamps forward by `offsetSeconds` so per-chunk
    /// transcripts align accurately with the original recording timeline.
    static func shiftSegments(_ segments: [TranscriptSegment], by offsetSeconds: Double) -> [TranscriptSegment] {
        guard abs(offsetSeconds) > 0.0001 else { return segments }
        return segments.map { seg in
            TranscriptSegment(
                speaker: seg.speaker,
                text: seg.text,
                startSeconds: seg.startSeconds + offsetSeconds,
                endSeconds: seg.endSeconds + offsetSeconds
            )
        }
    }

    /// Summarizes per-segment detected language codes across a recording:
    /// returns `"mixed"` when both Hebrew and English segments were detected.
    static func summarizeDetectedLanguages(_ codes: [String]) -> String? {
        let normalized = Set(codes.compactMap { raw -> String? in
            let code = String(raw.prefix(2)).lowercased()
            if code == "he" || code == "iw" { return "he" }
            if code == "en" { return "en" }
            return nil
        })
        if normalized.contains("he") && normalized.contains("en") { return "mixed" }
        if normalized.contains("he") { return "he" }
        if normalized.contains("en") { return "en" }
        return nil
    }

    struct HallucinationCandidate: Equatable, Sendable {
        let text: String
        let startSec: Double
        let endSec: Double
        let avgProb: Double
    }

    /// Whisper hallucination filter: drops low-confidence noise
    /// decodes, classic Hebrew/English YouTube subtitle artifacts, low-density
    /// stretched lines, and 3+ consecutive duplicate loops.
    static func filterHallucinations(_ candidates: [HallucinationCandidate]) -> [HallucinationCandidate] {
        let junkExact: Set<String> = [
            "thankyou", "thankyouverymuch", "thanks", "thanksforwatching", "thankyouforwatching",
            "תודה", "תודהרבה", "תודהשצפיתם", "תודהשצפיתן",
            "спасибо", "спасибозапросмотр",
        ]
        let junkPrefixes = ["subsby", "subtitlesby", "translatedby", "כתוביותעלידי"]
        func norm(_ s: String) -> String {
            s.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        func isKnownJunk(_ key: String) -> Bool {
            junkExact.contains(key) || junkPrefixes.contains { key.hasPrefix($0) }
        }

        let dense = candidates.filter { c in
            let dur = c.endSec - c.startSec
            return !(dur > 8 && Double(norm(c.text).count) / dur < 1.0)
        }
        var out: [HallucinationCandidate] = []
        var i = 0
        while i < dense.count {
            let key = norm(dense[i].text)
            var j = i + 1
            while j < dense.count, norm(dense[j].text) == key { j += 1 }
            let run = dense[i..<j]
            let avgP = run.reduce(0.0) { $0 + $1.avgProb } / Double(run.count)
            if key.isEmpty || avgP < 0.45 {
                // Low-confidence noise decode — drop.
            } else if run.count >= 3 {
                if avgP >= 0.8, let first = run.first { out.append(first) }
            } else if isKnownJunk(key),
                      avgP < 0.8 || run.contains(where: { $0.endSec - $0.startSec > 4 }) {
                // Classic subtitle-artifact filler — drop.
            } else {
                out.append(contentsOf: run)
            }
            i = j
        }
        return out
    }

    /// Reversible GPT-2 byte-level BPE decoder table (maps Whisper `vocab.json`
    /// Unicode code points back to raw UTF-8 bytes so multi-byte Hebrew letters
    /// decode cleanly across token boundaries).
    static let gpt2UnicodeToByte: [Character: UInt8] = {
        var bytes: [UInt8] = Array(33...126) + Array(161...172) + Array(174...255)
        var codePoints: [UInt32] = bytes.map { UInt32($0) }
        var extra: UInt32 = 0
        for b in UInt16(0)...UInt16(255) {
            let byte = UInt8(b)
            if !bytes.contains(byte) {
                bytes.append(byte)
                codePoints.append(256 + extra)
                extra += 1
            }
        }
        var map: [Character: UInt8] = [:]
        for (byte, cp) in zip(bytes, codePoints) {
            if let scalar = UnicodeScalar(cp) {
                map[Character(scalar)] = byte
            }
        }
        return map
    }()

    /// Decodes a sequence of Whisper text token IDs using `vocab` (id → GPT-2
    /// byte-BPE string) into clean UTF-8 text (including Hebrew and English).
    static func decodeWhisperTokens(_ tokenIDs: [Int], vocab: [Int: String]) -> String {
        var rawBytes: [UInt8] = []
        rawBytes.reserveCapacity(tokenIDs.count * 4)
        for id in tokenIDs {
            guard id >= 0, id < whisperEOTToken, let token = vocab[id] else { continue }
            for ch in token {
                if let byte = gpt2UnicodeToByte[ch] {
                    rawBytes.append(byte)
                } else {
                    rawBytes.append(contentsOf: String(ch).utf8)
                }
            }
        }
        return String(decoding: rawBytes, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
