// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import Foundation

enum DictationError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Serial, crash-isolated native inference. A warm worker keeps its model in
/// memory between utterances. Cancellation kills it without blocking the UI.
final class DictationEngine {
    struct Request {
        let audio: URL
        let model: URL
        let language: String
        let translate: Bool
        let vocabulary: [String]
        let cpu: Bool
        var temporaryDirectory: URL? = nil
    }
    struct Result: Decodable { let text: String?; let language: String?; let error: String?; let streaming: Bool? }
    private let queue = DispatchQueue(label: "com.vorssaint.dictation.engine", qos: .userInitiated)
    private let lock = NSLock()
    private var process: Process?
    private var lifetime = UUID()
    private var discardedLiveIDs: Set<UUID> = []
    private var input: FileHandle?
    private var output: FileHandle?
    private var pending = Data()
    // Accessed exclusively on queue. Every utterance has a separate identity;
    // a late microphone callback cannot feed the next utterance.
    private var liveID: UUID?
    private var liveLifetime: UUID?
    private var liveActive = false

    @discardableResult
    func beginLive(_ request: Request, ready: ((Bool) -> Void)? = nil) -> UUID {
        let id = UUID()
        lock.lock(); let token = lifetime; lock.unlock()
        queue.async {
            guard self.isCurrent(token) else { return }
            self.liveID = id; self.liveLifetime = token; self.liveActive = false
            do {
                try self.startWorker(token: token)
                var payload = Self.options(request)
                payload["command"] = "begin"
                let reply = try self.exchange(payload)
                self.liveActive = reply.streaming == true && reply.error == nil
            } catch { /* The complete recording remains available for batch retry. */ }
            let active = self.liveActive
            DispatchQueue.main.async { ready?(active) }
        }
        return id
    }

    func appendLive(_ data: Data?, id: UUID) {
        lock.lock(); let token = lifetime; lock.unlock()
        queue.async {
            guard self.isCurrent(token, liveID: id), self.liveID == id, self.liveLifetime == token, self.liveActive else { return }
            guard let data else { self.liveActive = false; return }
            do {
                let reply = try self.exchange(["command": "feed", "pcm": data.base64EncodedString()])
                if reply.error != nil { self.liveActive = false }
            } catch { self.liveActive = false }
        }
    }

    /// Discard a recording without evicting the loaded model. Revocation is
    /// immediate; already queued audio skips inference before the reset runs.
    func discardLive(_ id: UUID) {
        lock.lock(); let token = lifetime; discardedLiveIDs.insert(id); lock.unlock()
        queue.async {
            defer { self.lock.lock(); self.discardedLiveIDs.remove(id); self.lock.unlock() }
            guard self.isCurrent(token), self.liveID == id, self.liveLifetime == token else { return }
            self.liveActive = false; self.liveID = nil
            do { _ = try self.exchange(["command": "reset"]) }
            catch { if self.isCurrent(token) { self.cancel() } }
        }
    }

    private func isCurrent(_ token: UUID, liveID: UUID? = nil) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return lifetime == token && (liveID.map { !discardedLiveIDs.contains($0) } ?? true)
    }

    private static func options(_ request: Request) -> [String: Any] {
        ["model": request.model.path, "language": request.language, "translate": request.translate,
         "vocabulary": request.vocabulary, "cpu": request.cpu]
    }

    private func exchange(_ payload: [String: Any]) throws -> Result {
        var bytes = try JSONSerialization.data(withJSONObject: payload)
        bytes.append(10)
        guard let input else { throw DictationError.message("The speech engine is unavailable.") }
        try input.write(contentsOf: bytes)
        return try readReply()
    }

    func cancel() {
        lock.lock()
        lifetime = UUID()
        let active = process
        process = nil
        lock.unlock()
        if let active, active.isRunning {
            // SIGKILL also stops unresponsive native/GPU code. All state is private
            // to the worker; no in-process model is left in a half-cancelled state.
            kill(active.processIdentifier, SIGKILL)
        }
    }

    func transcribe(_ request: Request, finishingLive id: UUID? = nil,
                    completion: @escaping (Swift.Result<Result, Error>) -> Void) {
        lock.lock(); let token = lifetime; lock.unlock()
        queue.async {
            do {
                guard self.isCurrent(token) else { throw CancellationError() }
                var result: Result?
                if let id, self.liveID == id, self.liveLifetime == token, self.liveActive {
                    if let reply = try? self.exchange(["command": "finalize"]), reply.error == nil,
                       reply.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        result = reply
                    }
                }
                self.liveID = nil; self.liveActive = false
                if result == nil {
                    let pcm = try Self.convertAudio(request.audio, temporaryDirectory: request.temporaryDirectory)
                    defer { try? FileManager.default.removeItem(at: pcm) }
                    try self.startWorker(token: token)
                    var payload = Self.options(request)
                    payload["audio"] = pcm.path
                    let reply = try self.exchange(payload)
                    if let error = reply.error { throw DictationError.message("Transcription failed: \(error)") }
                    guard reply.text != nil else { throw DictationError.message("The dictation engine returned an invalid result.") }
                    result = reply
                }
                guard self.isCurrent(token), let result else { throw CancellationError() }
                DispatchQueue.main.async { completion(.success(result)) }
            } catch {
                if self.isCurrent(token) { self.cancel() }
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func startWorker(token: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        guard lifetime == token else { throw CancellationError() }
        if process?.isRunning == true { return }
        try? input?.close(); try? output?.close(); pending.removeAll()
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/VorssaintDictationWorker")
        let development = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("VorssaintDictationWorker")
        let executable = FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : development
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw DictationError.message("The local speech engine is missing. Rebuild Vorssaint with Tools/build-dictation-engine.sh.")
        }
        let worker = Process()
        let toWorker = Pipe(), fromWorker = Pipe()
        worker.executableURL = executable
        worker.standardInput = toWorker
        worker.standardOutput = fromWorker
        worker.standardError = FileHandle.nullDevice
        try worker.run()
        input = toWorker.fileHandleForWriting
        output = fromWorker.fileHandleForReading
        process = worker
    }

    private func readReply() throws -> Result {
        while true {
            if let newline = pending.firstIndex(of: 10) {
                let line = pending[..<newline]
                pending.removeSubrange(...newline)
                return try JSONDecoder().decode(Result.self, from: line)
            }
            guard pending.count < 16 * 1024 * 1024, let output else { throw DictationError.message("Invalid speech-engine response.") }
            let data = output.availableData
            guard !data.isEmpty else { throw DictationError.message("The speech engine stopped unexpectedly. Try CPU mode in Dictation settings.") }
            pending.append(data)
        }
    }

    /// AVFoundation decodes/resamples all supported imports into the engine's
    /// 16 kHz mono float32 format, with a bounded buffer and no shell commands.
    static func convertAudio(_ source: URL, temporaryDirectory: URL? = nil) throws -> URL {
        let file = try AVAudioFile(forReading: source)
        guard file.length > 0, Double(file.length) / file.processingFormat.sampleRate <= 3600,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 32768),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32768),
              let directory = temporaryDirectory ?? PrivateFileStore.containerURL?.appendingPathComponent("Dictation/Temporary", isDirectory: true),
              PrivateFileStore.createDirectory(at: directory) else {
            throw DictationError.message("Choose a nonempty audio file shorter than one hour.")
        }
        let target = directory.appendingPathComponent(UUID().uuidString + ".f32")
        guard FileManager.default.createFile(atPath: target.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw DictationError.message("Could not create temporary audio.")
        }
        do {
            let handle = try FileHandle(forWritingTo: target)
            defer { try? handle.close() }
            var readError: Error?
            while true {
                var conversionError: NSError?
                let status = converter.convert(to: output, error: &conversionError) { requested, state in
                    // Some CAF readers throw eofErr (-39) rather than returning
                    // an empty buffer on the next read. Signal EOF ourselves,
                    // after delivering the final partial buffer exactly once.
                    let remaining = file.length - file.framePosition
                    guard remaining > 0 else { state.pointee = .endOfStream; return nil }
                    do {
                        let count = AVAudioFrameCount(min(AVAudioFramePosition(min(requested, input.frameCapacity)), remaining))
                        try file.read(into: input, frameCount: count)
                        state.pointee = input.frameLength == 0 ? .endOfStream : .haveData
                        return input.frameLength == 0 ? nil : input
                    } catch { readError = error; state.pointee = .endOfStream; return nil }
                }
                if let readError { throw readError }
                if let conversionError { throw conversionError }
                if output.frameLength > 0, let samples = output.floatChannelData?[0] {
                    try handle.write(contentsOf: Data(bytes: samples, count: Int(output.frameLength) * MemoryLayout<Float>.size))
                }
                if status == .endOfStream { break }
                if status == .error { throw DictationError.message("Audio conversion failed.") }
            }
            return target
        } catch { try? FileManager.default.removeItem(at: target); throw error }
    }
}
