// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

final class NotchMusicService: ObservableObject {
    static let shared = NotchMusicService()
    @Published private(set) var playback: NotchPlayback?
    @Published private(set) var sources: [NotchPlaybackSource] = []
    @Published private(set) var sourceIsAutomatic = true
    /// The chosen source, which the automatic player can stand in for while
    /// it waits for its next track.
    @Published private(set) var selectedSourcePID: Int32?
    /// True from the first request until the adapter's first reply. Until then
    /// a missing playback is unknown, not "nothing playing".
    @Published private(set) var awaitingPlayback = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var artworkTint: NotchArtworkTint?
    @Published private(set) var commandFailed = false
    @Published private(set) var commandPending = false
    @Published private(set) var automationAvailability: NotchMusicAutomation.Availability?
    @Published private(set) var requestingAutomation = false
    @Published private(set) var upcoming: NotchQueueSnapshot? {
        didSet {
            guard upcoming != oldValue else { return }
            queueCovers.update(upcoming, decode: NSImage.init(data:))
            upcomingArtwork = queueCovers.images
        }
    }
    @Published private(set) var upcomingArtwork: [String: NSImage] = [:]
    private var queueCovers = NotchQueueCovers<NSImage>()
    @Published private(set) var queueLoading = false
    @Published private(set) var queueActionPending = false
    @Published private(set) var queueActionFailed = false
    /// A player moved on to another song; see NotchTrackChange. Sent before
    /// the song is published, while every surface still shows the old one.
    let trackChanges = PassthroughSubject<Void, Never>()
    /// The song shown stops, and no other plays yet: a gap between songs
    /// outlasted its grace period, or another player's paused song took over
    /// from a pause. Sent before that reading is published.
    let trackEnds = PassthroughSubject<Void, Never>()
    /// Immediate visual acknowledgement of an accepted swipe, before metadata arrives.
    let gestureSkips = PassthroughSubject<Bool, Never>()
    private var trackChange = NotchTrackChange()
    private struct Reading {
        let playback: NotchPlayback?
        let artwork: NSImage?
        let tint: NotchArtworkTint?
        let sources: [NotchPlaybackSource]
        let automatic: Bool?
        let selectedPID: Int32?
    }
    /// An empty reading waiting out a gap between songs; see receive(_:).
    private var gapReading: Reading?
    private var gapWork: DispatchWorkItem?
    private var queueVisible = false
    private var queueRequest: UUID?
    private var queueReply: [String: Any]?
    private var process: Process?
    private var output: Pipe?
    private var input: Pipe?
    private var generation = UUID()
    private var wantsPlayback = false
    private var includeOtherPlayers = false
    private var restartCount = 0
    private var restartWork: DispatchWorkItem?
    private var launchedAt: TimeInterval?
    /// The adapter keeps an explicit choice only while it runs, and it stops
    /// on lock, sleep or when the page closes. Tied to a process, so it is
    /// never saved across launches of the app.
    private var chosenSource: NotchPlaybackSource.Selection?
    private var restoringSource = false
    private var artworkCache = NotchArtworkCache<(image: NSImage, tint: NotchArtworkTint?)>()
    private var artworkWork: DispatchWorkItem?
    private var automationTarget: NotchMusicAutomation.Target?
    private var automationDiscovery = DispatchWorkItem {}
    private var automationCancellation = DispatchWorkItem {}
    private var automationConsentCancellation = DispatchWorkItem {}
    private var automationTimeout: DispatchWorkItem?
    private struct AutomationAction {
        let id = UUID()
        let command: Command
        let playback: NotchPlayback
        let availability: NotchMusicAutomation.Availability
    }
    private var automationAction: AutomationAction?
    private var spotify: NotchSpotifyPlayback?
    private var nativeReading: Reading?
    private var awaitingAutomationValidation = false
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
        let includeOtherPlayers = UserDefaults.standard.bool(forKey: DefaultsKey.notchIncludeOtherPlayers)
        if wantsPlayback {
            guard self.includeOtherPlayers != includeOtherPlayers else { return }
            stop()
        }
        self.includeOtherPlayers = includeOtherPlayers
        wantsPlayback = true
        awaitingPlayback = true
        restartCount = 0
        launch()
    }

    private func launch() {
        guard wantsPlayback, process == nil else { return }
        guard let arguments = Self.adapter else { connectionEnded(); return }
        let process = Process()
        let output = Pipe()
        let input = Pipe()
        // A child can exit between checking isRunning and writing a command.
        // Keep that race an error, never a SIGPIPE that terminates the app.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { connectionEnded(); return }
        let requested = UUID()
        generation = requested
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = arguments + [includeOtherPlayers ? "watch_all" : "watch"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = input
        var cachedArtwork: Data?
        var cachedImage: NSImage?
        var cachedTint: NotchArtworkTint?
        let reader = NotchMusicPipeReader { [weak self] data in
            let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let reply, reply["validationRequest"] != nil {
                DispatchQueue.main.async {
                    guard let self, self.generation == requested else { return }
                    self.receiveValidation(reply)
                }
                return
            }
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
            let next = NotchPlayback.decode(data, previousArtwork: cachedArtwork,
                                           commandContext: reply.flatMap(NotchPlaybackContext.init(reply:)),
                                           canSendCommandsDirectly: reply?["canSendCommandsDirectly"] as? Bool == true)
            if cachedArtwork != next?.track.artworkData {
                cachedArtwork = next?.track.artworkData
                cachedImage = cachedArtwork.flatMap { ImageThumbnailer.thumbnail(data: $0, pointSize: 160, scale: 2) }
                cachedTint = cachedImage.flatMap(NotchMusicService.artworkTint(of:))
            }
            let image = cachedImage
            let tint = cachedTint
            let automatic = reply?["sourceIsAutomatic"] as? Bool
            let selectedPID = automatic == false ? NotchPlaybackSource.decodePID(reply?["selectedPID"]) : nil
            let sources = NotchPlaybackSource.decode(reply?["sources"], selectedPID: selectedPID)
            DispatchQueue.main.async {
                guard let self, self.generation == requested,
                      self.acceptsSourceReply(automatic: automatic, sources: sources) else { return }
                self.receive(Reading(playback: next, artwork: image, tint: tint, sources: sources,
                                     automatic: automatic, selectedPID: selectedPID))
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
                self.connectionEnded()
            }
        }
        do {
            try process.run()
            commandWriter.start()
            self.process = process
            self.output = output
            self.input = input
            launchedAt = ProcessInfo.processInfo.systemUptime
            restoreSource()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            connectionEnded()
        }
    }

    /// A new adapter starts in Automatic. It finishes its first discovery
    /// before reading any command, so it checks the choice against fresh sources.
    private func restoreSource() {
        guard let chosenSource else { restoringSource = false; return }
        restoringSource = send(.source(chosenSource))
    }

    /// A restarted adapter reads once in Automatic before the restored choice
    /// reaches it. That reading is not shown, so the automatic player does not
    /// flash. A choice the adapter reports gone is forgotten.
    private func acceptsSourceReply(automatic: Bool?, sources: [NotchPlaybackSource]) -> Bool {
        let restoring = restoringSource
        restoringSource = false
        guard automatic == true, let chosenSource else { return true }
        guard sources.contains(where: { $0.selection == chosenSource }) else {
            self.chosenSource = nil
            return true
        }
        return !restoring
    }

    /// A player moving on to its next song can clear its metadata for a
    /// moment, which reads as nothing playing or as another player's paused
    /// song standing in, or report the next song paused before it starts. The
    /// page would empty or change and shrink, and the compact strip leave,
    /// until the next song plays. The last song stays through such a gap and
    /// the next reading replaces it at once. Later readings of the gap never
    /// extend the grace period.
    private func receive(_ reading: Reading) {
        // A player that still lists a song when another player's paused song
        // takes its place was paused. During a gap it had left, the song it
        // lists again can be its next one, still loading.
        let listing = gapWork == nil ? reading.sources : []
        if let current = playback, !awaitingPlayback,
           NotchTrackChange.isBetweenSongs(reading.playback, after: current, sources: listing) {
            gapReading = reading
            guard gapWork == nil else { return }
            let requested = generation
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.generation == requested, let reading = self.gapReading else { return }
                self.endPlaybackGap()
                self.apply(reading)
            }
            gapWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchPlayback.gapGracePeriod, execute: work)
            return
        }
        endPlaybackGap()
        apply(reading)
    }

    private func endPlaybackGap() {
        gapWork?.cancel()
        gapWork = nil
        gapReading = nil
    }

    private func apply(_ reading: Reading) {
        let reading = spotifyReading(reading)
        publishReading(reading)
        syncSpotify()
    }

    private func publishReading(_ reading: Reading) {
        let first = awaitingPlayback
        if trackChange.isNewSong(reading.playback, first: first) { trackChanges.send() }
        else if !first, let current = playback, NotchTrackChange.isBetweenSongs(reading.playback, after: current) {
            trackEnds.send()
        }
        updateArtwork(reading.artwork, tint: reading.tint, playback: reading.playback)
        playback = reading.playback
        sources = reading.sources
        sourceIsAutomatic = reading.automatic ?? true
        selectedSourcePID = reading.selectedPID
        awaitingPlayback = false
        updateAutomation(for: reading.playback)
        NotchLyricsService.shared.playbackChanged(reading.playback)
        updateQueue()
    }

    private func spotifyReading(_ reading: Reading) -> Reading {
        nativeReading = reading
        if reading.playback?.track.appPID != spotify?.target.pid {
            spotify?.stop(); spotify = nil
        }
        guard let fresh = spotify?.playback else {
            // A rejected transition snapshot must not briefly replace verified
            // Spotify artwork with the native session's stale cover or nil.
            // Commands still require the reader's fresh command context.
            if spotify != nil, let held = playback, held.commandContext != nil,
               Date().timeIntervalSince(held.sampledAt) < NotchPlayback.gapGracePeriod {
                return readingWithSpotify(held, native: reading)
            }
            return reading
        }
        return readingWithSpotify(fresh, native: reading)
    }

    private func readingWithSpotify(_ fresh: NotchPlayback, native: Reading) -> Reading {
        let image = fresh.track.artworkData.flatMap { ImageThumbnailer.thumbnail(data: $0, pointSize: 160, scale: 2) }
        let sources = native.sources.map { source in
            guard source.pid == fresh.track.appPID else { return source }
            return NotchPlaybackSource(pid: source.pid, bundleIdentifier: source.bundleIdentifier,
                isMusicApp: source.isMusicApp, isPlaying: fresh.isPlaying, hasTrack: true, displayName: source.displayName)
        }
        return Reading(playback: fresh, artwork: image, tint: image.flatMap(Self.artworkTint(of:)),
                       sources: sources, automatic: native.automatic, selectedPID: native.selectedPID)
    }

    private func syncSpotify() {
        guard let available = automationAvailability, available.access == .granted,
              available.target.bundleIdentifier == "com.spotify.client",
              playback?.track.appPID == available.target.pid else {
            spotify?.stop(); spotify = nil
            return
        }
        guard spotify?.target != available.target else { return }
        spotify?.stop()
        let target = available.target
        spotify = NotchSpotifyPlayback(target: target) { [weak self] fresh in
            guard let self, self.spotify?.target == target, let native = self.nativeReading,
                  native.playback?.track.appPID == target.pid else { return }
            // Do not feed the authoritative reading back as native discovery.
            let reading = fresh.map { self.readingWithSpotify($0, native: native) } ?? self.spotifyReading(native)
            if fresh != nil { self.endPlaybackGap() }
            self.publishReading(reading)
            if fresh == nil { self.refreshAutomation() }
        }
    }

    private func connectionEnded() {
        // An adapter that ran for over a minute is not crash looping, so its
        // exit gets a fresh budget instead of leaving music off until a restart.
        if let launchedAt, ProcessInfo.processInfo.systemUptime - launchedAt > 60 { restartCount = 0 }
        launchedAt = nil
        disconnect()
        guard wantsPlayback, restartCount < 2 else { awaitingPlayback = false; return }
        restartCount += 1
        let requested = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wantsPlayback, self.generation == requested else { return }
            self.restartWork = nil
            self.launch()
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(restartCount), execute: work)
    }

    private func updateArtwork(_ image: NSImage?, tint: NotchArtworkTint?, playback: NotchPlayback?) {
        artworkWork?.cancel()
        artworkWork = nil
        artworkCache.update(image.map { (image: $0, tint: tint) }, for: playback)
        artwork = artworkCache.artwork?.image
        artworkTint = artworkCache.artwork?.tint
        guard let deadline = artworkCache.expiresAt else { return }
        let requested = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == requested, self.artworkCache.expiresAt == deadline else { return }
            self.artworkCache.expire(at: deadline)
            self.artwork = self.artworkCache.artwork?.image
            self.artworkTint = self.artworkCache.artwork?.tint
            self.artworkWork = nil
        }
        artworkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline.timeIntervalSinceNow), execute: work)
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
        wantsPlayback = false
        awaitingPlayback = false
        restartWork?.cancel()
        restartWork = nil
        restartCount = 0
        trackChange.reset()
        disconnect()
    }

    private func disconnect() {
        spotify?.stop(); spotify = nil
        nativeReading = nil
        endPlaybackGap()
        artworkWork?.cancel()
        artworkWork = nil
        artworkCache = .init()
        automationDiscovery.cancel()
        automationConsentCancellation.cancel()
        automationTarget = nil
        automationAvailability = nil
        cancelAutomationAction()
        commandWriter.stop()
        queueVisible = false
        NotchLyricsService.shared.hide()
        queueRequest = nil
        queueReply = nil
        upcoming = nil
        queueCovers = .init()
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
        sources = []
        sourceIsAutomatic = true
        selectedSourcePID = nil
        artwork = nil
        artworkTint = nil
        commandFailed = false
    }

    typealias Command = NotchPlaybackCommand

    func selectSource(_ selection: NotchPlaybackSource.Selection?) {
        // Choosing what is already in effect changes nothing in the adapter,
        // so the page, its lyrics and the island's size stay as they are. A
        // choice stays in effect while the automatic player fills its gap.
        if selection == nil ? sourceIsAutomatic
            : !sourceIsAutomatic && selectedSourcePID == selection?.pid { return }
        guard selection == nil || sources.contains(where: { $0.selection == selection }),
              send(.source(selection)) else { return }
        spotify?.stop(); spotify = nil
        nativeReading = nil
        chosenSource = selection
        cancelAutomationAction()
        setQueueVisible(false)
        // Remove the old controls while the adapter validates and reads the
        // new source. No gesture can borrow the previous player's context.
        endPlaybackGap()
        playback = nil
        artwork = nil
        artworkTint = nil
        awaitingPlayback = true
        updateAutomation(for: nil)
        NotchLyricsService.shared.playbackChanged(nil)
    }

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
        guard !NotchQueueSupport.isEnabled() else { return }
        setQueueVisible(false)
        queueCovers = .init()
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

    var upcomingIsHeld: Bool {
        guard let upcoming else { return false }
        return upcoming.currentIdentifier != playback?.itemIdentifier || upcoming.pid != playback?.track.appPID
    }

    var upcomingRows: [NotchQueueItem] {
        upcoming?.items.filter { $0.id != playback?.itemIdentifier } ?? []
    }

    func playQueued(_ item: NotchQueueItem) {
        guard queueVisible, NotchQueueSupport.isEnabled(), let request = queueRequest, let upcoming,
              let playback, upcoming.currentIdentifier == playback.itemIdentifier,
              upcoming.pid == playback.track.appPID, upcoming.canPlay,
              upcoming.items.contains(where: { $0.id == item.id && $0.offset == item.offset }),
              !queueActionPending else { return }
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
        let next = NotchQueueSupport.decode(queueReply, requestID: request, playback: playback)
        if next == nil, upcoming != nil,
           NotchQueueSupport.awaitsSongQueue(queueReply, requestID: request, playback: playback) { return }
        upcoming = next
    }

    func seek(to position: Double, in track: RadialNowPlayingSnapshot, context: NotchPlaybackContext?) {
        guard let playback, playback.track == track,
              let context, context == playback.commandContext,
              let position = playback.seekPosition(position, allowed: canSeek) else { return }
        send(.seek(position), context: context)
    }

    @discardableResult
    func send(_ command: Command) -> Bool {
        send(command, context: playback?.commandContext)
    }

    func skipFromGesture(forward: Bool) {
        let command: Command = forward ? .next : .previous
        guard canPerform(command), send(command) else { return }
        gestureSkips.send(forward)
    }

    @discardableResult
    func send(_ command: Command, context: NotchPlaybackContext?) -> Bool {
        switch command {
        case .queue, .queuePlay: guard queueVisible, NotchQueueSupport.isEnabled() else { return false }
        default: break
        }
        switch command {
        case .source, .queueStop: break
        default: guard playback != nil else { return false }
        }
        guard process?.isRunning == true, let input else { return false }
        if command.requiresPlaybackContext {
            // A song held through a gap has no player left to reach, and a
            // command would come back as a failure.
            guard gapWork == nil, let context, context == playback?.commandContext else { return false }
            guard !commandPending, let playback else { return false }
            if !playback.canSendCommandsDirectly { return beginAutomation(command, playback: playback) }
        }
        let requested = generation
        let requestedQueue = command.queueRequest
        commandFailed = false
        return commandWriter.submit(command, context: context, write: { data in
            try input.fileHandleForWriting.write(contentsOf: data)
        }, failed: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.generation == requested,
                      requestedQueue == nil || self.queueRequest == requestedQueue else { return }
                self.commandFailed = true
                self.cancelAutomationAction()
                self.queueLoading = false
                self.queueActionPending = false
                self.queueActionFailed = self.queueRequest != nil
            }
        })
    }

    var playbackControlsBusy: Bool {
        commandPending || (spotify != nil && spotify?.playback == nil)
    }

    /// Layout follows the player's declared capability, not the transient
    /// validity of the current recording. A stale slider remains disabled.
    var showsSeekControl: Bool {
        guard let playback, playback.hasPosition, playback.duration > 0 else { return false }
        return playback.canSendCommandsDirectly ? playback.canSeek
            : automationAvailability?.access == .granted && automationAvailability?.capabilities.position != nil
    }

    var canSeek: Bool {
        guard let playback, playback.hasPosition, playback.duration > 0 else { return false }
        if playback.track.appBundleIdentifier == "com.spotify.client" {
            guard let context = playback.commandContext, spotify?.playback?.commandContext == context else { return false }
        }
        return playback.canSendCommandsDirectly ? playback.canSeek
            : automationAvailability?.access == .granted && automationAvailability?.capabilities.position != nil
    }

    func canPerform(_ command: Command) -> Bool {
        guard let playback, playback.commandContext != nil, !commandPending else { return false }
        if playback.track.appBundleIdentifier == "com.spotify.client",
           spotify?.playback?.commandContext != playback.commandContext { return false }
        if case .seek = command { return canSeek }
        if playback.canSendCommandsDirectly { return !lacksTrackSkipping(command) }
        guard let available = automationAvailability, available.access == .granted else { return false }
        if command == .toggle { return available.capabilities.canToggle }
        return available.capabilities.event(for: command, isPlaying: playback.isPlaying) != nil
    }

    /// The player itself says it cannot skip this way, so the button is hidden.
    func lacksTrackSkipping(_ command: Command) -> Bool {
        guard let playback, playback.canSendCommandsDirectly else { return false }
        switch command {
        case .next: return playback.canSkipNext == false
        case .previous: return playback.canSkipPrevious == false
        default: return false
        }
    }

    func refreshAutomation() {
        automationTarget = nil
        updateAutomation(for: playback)
    }

    private func updateAutomation(for playback: NotchPlayback?) {
        if let action = automationAction, action.playback.commandContext != playback?.commandContext { cancelAutomationAction() }
        guard let playback, !playback.canSendCommandsDirectly, let target = NotchMusicAutomation.Target(playback) else {
            automationDiscovery.cancel()
            automationConsentCancellation.cancel()
            automationTarget = nil
            automationAvailability = nil
            cancelAutomationAction()
            return
        }
        guard target != automationTarget else { return }
        automationConsentCancellation.cancel()
        automationDiscovery.cancel()
        let cancellation = DispatchWorkItem {}
        automationDiscovery = cancellation
        automationTarget = target
        // Every page that shows the controls asks for a fresh look at the
        // same player. Its last answer stays on screen until the new one
        // lands, instead of the fallback row flashing on each open; sending
        // checks access again anyway. Another player starts from nothing.
        if automationAvailability?.target != target { automationAvailability = nil }
        let requested = generation
        queue.async { [weak self] in
            guard !cancellation.isCancelled else { return }
            let available = NotchMusicAutomation.inspect(target)
            DispatchQueue.main.async {
                guard let self, self.generation == requested, self.automationTarget == target,
                      !cancellation.isCancelled else { return }
                self.automationAvailability = available
                self.syncSpotify()
            }
        }
    }

    /// Consent never queues the old gesture. The next press supplies a fresh
    /// recording context, which is re-read again before any Apple Event is sent.
    func requestAutomationAccess() {
        guard !requestingAutomation, let available = automationAvailability,
              available.access == .consent, available.target.isCurrent else { return }
        requestingAutomation = true
        let requested = generation
        let context = playback?.commandContext
        let cancellation = DispatchWorkItem {}
        automationConsentCancellation = cancellation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if !cancellation.isCancelled, available.target.isCurrent {
                _ = AppleScriptRunner.consentToAutomate(bundleID: available.target.bundleIdentifier)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestingAutomation = false
                guard !cancellation.isCancelled, self.generation == requested, self.playback?.commandContext == context,
                      self.automationTarget == available.target else { return }
                self.refreshAutomation()
            }
        }
    }

    private func beginAutomation(_ command: Command, playback: NotchPlayback) -> Bool {
        guard canPerform(command), let context = playback.commandContext,
              let available = automationAvailability, available.target.isCurrent else { return false }
        let action = AutomationAction(command: command, playback: playback, availability: available)
        automationAction = action
        awaitingAutomationValidation = true
        automationCancellation = DispatchWorkItem {}
        commandPending = true
        commandFailed = false
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.automationAction?.id == action.id else { return }
            self.cancelAutomationAction()
            self.commandFailed = true
        }
        automationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
        guard validateAutomation(action.id, context: context) else {
            cancelAutomationAction(); commandFailed = true; return false
        }
        return true
    }

    private func validateAutomation(_ id: UUID, context: NotchPlaybackContext) -> Bool {
        guard let spotify, spotify.playback?.commandContext == context else {
            return send(.validate(id, context))
        }
        spotify.validate(context) { [weak self] valid in
            self?.receiveValidation(["validationRequest": id.uuidString, "validationOK": valid])
        }
        return true
    }

    private func receiveValidation(_ reply: [String: Any]) {
        guard awaitingAutomationValidation, let action = automationAction,
              reply["validationRequest"] as? String == action.id.uuidString else { return }
        awaitingAutomationValidation = false
        guard reply["validationOK"] as? Bool == true, playback?.commandContext == action.playback.commandContext else {
            cancelAutomationAction(); commandFailed = true; return
        }
        automationTimeout?.cancel(); automationTimeout = nil
        let cancellation = automationCancellation
        let validatedAt = ProcessInfo.processInfo.systemUptime
        queue.async { [weak self] in
            let succeeded = NotchMusicAutomation.send(action.command, playback: action.playback,
                availability: action.availability, cancellation: cancellation, validatedAt: validatedAt)
            DispatchQueue.main.async {
                guard let self, !cancellation.isCancelled, self.automationAction?.id == action.id else { return }
                self.cancelAutomationAction()
                self.commandFailed = !succeeded
                self.spotify?.refresh()
                if !succeeded { self.refreshAutomation() }
            }
        }
    }

    private func cancelAutomationAction() {
        automationCancellation.cancel()
        automationTimeout?.cancel(); automationTimeout = nil
        automationAction = nil
        awaitingAutomationValidation = false
        commandPending = false
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
