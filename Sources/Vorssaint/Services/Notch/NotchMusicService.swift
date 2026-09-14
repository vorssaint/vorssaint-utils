// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

final class NotchMusicService: ObservableObject {
    static let shared = NotchMusicService()
    @Published private(set) var playback: NotchPlayback?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var artworkTint: NotchArtworkTint?
    @Published private(set) var commandFailed = false
    @Published private(set) var upcoming: NotchQueueSnapshot?
    @Published private(set) var queueLoading = false
    @Published private(set) var queueActionPending = false
    @Published private(set) var queueActionFailed = false
    private var queueVisible = false
    private var queueRequest: UUID?
    private var queueReply: [String: Any]?
    private var process: Process?
    private var output: Pipe?
    private var input: Pipe?
    private var generation = UUID()
    private let queue = DispatchQueue(label: "com.vorssaint.notch-music", qos: .utility)
    private lazy var commandWriter = NotchMusicCommandWriter { [queue = self.queue] action in queue.async(execute: action) }

    private init() {}

    private static var adapter: [String]? {
        guard let script = Bundle.main.url(forResource: "now-playing", withExtension: "pl"),
              let library = Bundle.main.privateFrameworksURL?.appendingPathComponent("libVorssaintNowPlaying.dylib"),
              FileManager.default.fileExists(atPath: library.path) else { return nil }
        return [script.path, library.path]
    }

    func start() {
        guard process == nil, let arguments = Self.adapter else { return }
        let process = Process()
        let output = Pipe()
        let input = Pipe()
        // A child can exit between checking isRunning and writing a command.
        // Keep that race an error, never a SIGPIPE that terminates the app.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { return }
        let requested = UUID()
        generation = requested
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = arguments + ["watch"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = input
        var cachedArtwork: Data?
        var cachedImage: NSImage?
        var cachedTint: NotchArtworkTint?
        let reader = NotchMusicPipeReader { [weak self] data in
            let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let reply,
               reply["queueRequest"] != nil || reply["queueAction"] != nil {
                DispatchQueue.main.async {
                    guard let self, self.generation == requested else { return }
                    self.receiveQueue(reply)
                }
                return
            }
            if let sent = reply?["sent"] as? Bool {
                DispatchQueue.main.async {
                    guard let self, self.generation == requested else { return }
                    self.commandFailed = !sent
                }
                return
            }
            let next = NotchPlayback.decode(data, previousArtwork: cachedArtwork)
            if cachedArtwork != next?.track.artworkData {
                cachedArtwork = next?.track.artworkData
                cachedImage = cachedArtwork.flatMap { ImageThumbnailer.thumbnail(data: $0, pointSize: 160, scale: 2) }
                cachedTint = cachedImage.flatMap(NotchMusicService.artworkTint(of:))
            }
            let image = cachedImage
            let tint = cachedTint
            DispatchQueue.main.async {
                guard let self, self.generation == requested else { return }
                self.artwork = image
                self.artworkTint = tint
                self.playback = next
                NotchLyricsService.shared.playbackChanged(next)
                self.updateQueue()
            }
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            else { reader.append(data) }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == requested else { return }
                self.stop()
            }
        }
        do {
            try process.run()
            commandWriter.start()
            self.process = process
            self.output = output
            self.input = input
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
        }
    }

    /// One averaged pixel is all a halo needs, and it costs nothing next to
    /// decoding the cover itself. Runs on the reader's queue, once per cover.
    private static func artworkTint(of image: NSImage) -> NotchArtworkTint? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return NotchArtworkTint.from(red: Double(pixel[0]) / 255,
                                     green: Double(pixel[1]) / 255,
                                     blue: Double(pixel[2]) / 255)
    }

    func stop() {
        commandWriter.stop()
        queueVisible = false
        NotchLyricsService.shared.hide()
        queueRequest = nil
        queueReply = nil
        upcoming = nil
        queueLoading = false
        queueActionPending = false
        queueActionFailed = false
        generation = UUID()
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        if let process, process.isRunning {
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        process = nil
        input = nil
        output = nil
        playback = nil
        artwork = nil
        artworkTint = nil
        commandFailed = false
    }

    typealias Command = NotchPlaybackCommand

    func setQueueVisible(_ visible: Bool) {
        queueVisible = visible && NotchQueueSupport.isEnabled() && playback != nil
        guard queueVisible else {
            commandWriter.setQueueRequest(nil)
            if queueRequest != nil { send(.queueStop) }
            queueRequest = nil
            queueReply = nil
            upcoming = nil
            queueLoading = false
            queueActionPending = false
            queueActionFailed = false
            return
        }
        guard queueRequest == nil else { return }
        refreshQueue()
    }

    func syncQueuePreference() {
        if !NotchQueueSupport.isEnabled() { setQueueVisible(false) }
    }

    func refreshQueue() {
        guard queueVisible, NotchQueueSupport.isEnabled(), playback != nil else { return }
        let request = UUID()
        queueRequest = request
        commandWriter.setQueueRequest(request)
        queueReply = nil
        upcoming = nil
        queueLoading = true
        queueActionFailed = false
        queueActionPending = false
        if !send(.queue(request)) { queueLoading = false; queueActionFailed = true }
    }

    func playQueued(_ item: NotchQueueItem) {
        guard queueVisible, NotchQueueSupport.isEnabled(), let request = queueRequest, let upcoming,
              let playback, upcoming.currentIdentifier == playback.itemIdentifier,
              upcoming.pid == playback.track.appPID, upcoming.canPlay,
              upcoming.items.contains(item), !queueActionPending else { return }
        queueActionFailed = false
        queueActionPending = true
        let selected = NotchQueueSelection(requestID: request, pid: upcoming.pid,
            currentIdentifier: upcoming.currentIdentifier, itemIdentifier: item.id, offset: item.offset)
        if !send(.queuePlay(selected)) { queueActionPending = false; queueActionFailed = true }
    }

    private func receiveQueue(_ reply: [String: Any]) {
        guard let request = queueRequest, NotchQueueSupport.isEnabled() else { return }
        if reply["queueAction"] as? String == request.uuidString {
            queueActionPending = false
            queueActionFailed = reply["queueActionOK"] as? Bool != true
        } else if reply["queueRequest"] as? String == request.uuidString {
            queueLoading = false
            queueReply = reply
            updateQueue()
        }
    }

    private func updateQueue() {
        guard let request = queueRequest, let playback, let queueReply, NotchQueueSupport.isEnabled() else {
            upcoming = nil
            return
        }
        upcoming = NotchQueueSupport.decode(queueReply, requestID: request, playback: playback)
    }

    func seek(to position: Double, in track: RadialNowPlayingSnapshot) {
        guard let playback, playback.track == track,
              let position = playback.seekPosition(position) else { return }
        send(.seek(position))
    }

    @discardableResult
    func send(_ command: Command) -> Bool {
        switch command {
        case .queue, .queuePlay: guard queueVisible, NotchQueueSupport.isEnabled() else { return false }
        default: break
        }
        guard (playback != nil || command == .queueStop), process?.isRunning == true, let input else { return false }
        let requested = generation
        let requestedQueue = command.queueRequest
        commandFailed = false
        return commandWriter.submit(command, write: { data in
            try input.fileHandleForWriting.write(contentsOf: data)
        }, failed: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.generation == requested,
                      requestedQueue == nil || self.queueRequest == requestedQueue else { return }
                self.commandFailed = true
                self.queueLoading = false
                self.queueActionPending = false
                self.queueActionFailed = self.queueRequest != nil
            }
        })
    }

}

/// Pipe callbacks may split a UTF-8 character or join several replies. Parsing
/// stays serial and bounded before any metadata reaches the main thread.
private final class NotchMusicPipeReader {
    private let queue = DispatchQueue(label: "com.vorssaint.notch-music-reader", qos: .utility)
    private var buffer = Data()
    private let receive: (Data) -> Void
    init(receive: @escaping (Data) -> Void) { self.receive = receive }

    func append(_ data: Data) {
        // Backpressure keeps native metadata bursts from queuing unbounded
        // buffers. The pipe invokes this off-main and delivery never waits on UI.
        queue.sync {
            self.buffer.append(data)
            if self.buffer.count > RadialNowPlayingSupport.maximumAdapterReplyBytes {
                self.buffer.removeAll(keepingCapacity: false)
                return
            }
            while let end = self.buffer.firstIndex(of: 0x0A) {
                let line = Data(self.buffer[..<end])
                self.buffer.removeSubrange(...end)
                self.receive(line)
            }
        }
    }
}
