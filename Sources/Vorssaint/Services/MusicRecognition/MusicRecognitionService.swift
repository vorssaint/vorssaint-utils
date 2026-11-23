// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import ShazamKit

/// Names the song that is playing with several engines at once, and shows
/// whichever answers first, then sharpens the answer for a few seconds.
///
/// It listens to two sources: what this Mac itself plays (a film, a video, a
/// browser tab, a game) and what the microphone hears in the room. Each is
/// fingerprinted on the Mac, so the sound itself never leaves it:
/// - SongRec's port of Shazam's fingerprint, the default, asked of Shazam;
/// - Apple's ShazamKit, where this build may use it;
/// - AudD, only when an AudD key is set.
/// Every answer counts toward the song's score: more windows of sound and
/// more engines agreeing, and a cleaner alignment, give a higher percentage.
@MainActor
final class MusicRecognitionService: ObservableObject {
    static let shared = MusicRecognitionService()

    enum State: Equatable {
        case idle, listening
        case matched(RecognisedSong)
        case noMatch
        case failed(String)
        case microphoneDenied
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var artwork: NSImage?
    /// The shown song's score, 0–100.
    @Published private(set) var percent: Int?
    /// Up to three other songs close to what was heard.
    @Published private(set) var nearby: [NearbyMatch] = []
    /// Still listening after the first answer, to firm it up.
    @Published private(set) var refining = false

    /// How long it listens before saying it found nothing.
    static let listenLimit: TimeInterval = 15
    /// How long it keeps listening after the first answer.
    static let refineTime: TimeInterval = 5

    private var listeners: [MusicRecognitionListener] = []
    private var limit: DispatchWorkItem?
    private var refineWork: DispatchWorkItem?
    private var generation = 0
    private var scoring = MusicRecognitionScoring()
    private var shownKey: String?

    private init() {}

    func start() {
        stop()
        generation += 1
        let trip = generation
        artwork = nil
        percent = nil
        nearby = []
        refining = false
        scoring = MusicRecognitionScoring()
        shownKey = nil
        state = .listening
        let report: (String, RecognisedSong, Double?) -> Void = { [weak self] engine, song, skew in
            Task { @MainActor in self?.heard(song, engine: engine, skew: skew, trip: trip) }
        }
        // What the Mac itself plays: heard even while its volume is down.
        let system = MusicRecognitionListener(source: "mac", report: report)
        listeners.append(system)
        Task { _ = await system.startSystemAudio() }
        // And the room, when the microphone may be used.
        Task { [weak self] in
            guard let self else { return }
            let allowed = await Self.microphoneAllowed()
            guard self.generation == trip, self.state == .listening || self.refining else { return }
            if allowed {
                let microphone = MusicRecognitionListener(source: "room", report: report)
                self.listeners.append(microphone)
                microphone.startMicrophone()
            }
        }
        let work = DispatchWorkItem { [weak self] in self?.timedOut(trip: trip) }
        limit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.listenLimit, execute: work)
    }

    /// Any engine's answer. The first one shows at once; later ones firm up the score or replace it.
    private func heard(_ song: RecognisedSong, engine: String, skew: Double?, trip: Int) {
        guard trip == generation, state == .listening || refining else { return }
        scoring.add(song, engine: engine, skew: skew)
        guard let best = scoring.best else { return }
        if case .listening = state {
            limit?.cancel(); limit = nil
            refining = true
            let work = DispatchWorkItem { [weak self] in self?.finish(trip: trip) }
            refineWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.refineTime, execute: work)
        }
        show(best)
    }

    private func show(_ best: MusicRecognitionScoring.Candidate) {
        percent = best.percent
        nearby = scoring.others(than: best.song.id).prefix(3).map { NearbyMatch(song: $0.song, percent: $0.percent) }
        guard shownKey != best.song.id else { return }
        shownKey = best.song.id
        artwork = nil
        state = .matched(best.song)
        loadArtwork(for: best.song)
    }

    /// Lets one of the nearby songs take the main place, as a tap on it does.
    func choose(_ match: NearbyMatch) {
        guard case .matched(let current) = state, current != match.song else { return }
        let previousPercent = percent
        nearby = nearby.filter { $0 != match } + [NearbyMatch(song: current, percent: previousPercent)]
        percent = match.percent
        shownKey = match.song.id
        artwork = nil
        state = .matched(match.song)
        loadArtwork(for: match.song)
    }

    private func finish(trip: Int) {
        guard trip == generation, refining else { return }
        refining = false
        stopListeners()
        // Fewer than three heard: other versions of the song fill the row, as search finds them.
        guard nearby.count < 3, case .matched(let song) = state else { return }
        Task { [weak self] in
            let versions = await MusicRecognitionVersions.search(song)
            guard let self, self.generation == trip, case .matched(let shown) = self.state, shown == song else { return }
            let taken = Set(self.nearby.map(\.id) + [song.id])
            let extra = versions.filter { !taken.contains($0.id) }.prefix(3 - self.nearby.count)
            self.nearby += extra.map { NearbyMatch(song: $0, percent: nil) }
        }
    }

    private func timedOut(trip: Int) {
        guard trip == generation, state == .listening else { return }
        stopListeners()
        state = .noMatch
    }

    private func stopListeners() {
        limit?.cancel(); limit = nil
        refineWork?.cancel(); refineWork = nil
        listeners.forEach { $0.stop() }
        listeners.removeAll()
    }

    /// Stops listening at once; the microphone and the Mac's sound are let go with it.
    func stop() {
        generation += 1
        refining = false
        stopListeners()
        if state == .listening { state = .idle }
    }

    func reset() {
        stop()
        state = .idle
        artwork = nil
        percent = nil
        nearby = []
    }

    private func loadArtwork(for song: RecognisedSong) {
        guard let url = song.artworkURL else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            guard let self, self.state == .matched(song) else { return }
            self.artwork = image
        }
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    // MARK: Opening the song

    /// The Spotify app, on its search for the song; Spotify's web player when the app is not installed.
    static func openInSpotify(_ song: RecognisedSong) {
        let query = song.query
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client")
        if app != nil, let url = MusicRecognitionLinks.spotifyApp(query) {
            NSWorkspace.shared.open(url)
        } else if let url = MusicRecognitionLinks.spotifyWeb(query) {
            NSWorkspace.shared.open(url)
        }
    }

    /// YouTube's search for the song in Chrome, in the profile chosen in
    /// Settings, or the profile Chrome last used when none is chosen.
    static func openInYouTube(_ song: RecognisedSong) {
        guard let url = MusicRecognitionLinks.youTube(song.query) else { return }
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            NSWorkspace.shared.open(url)
            return
        }
        let wanted = UserDefaults.standard.string(forKey: DefaultsKey.musicRecognitionChromeProfile) ?? ""
        let directory = MusicRecognitionLinks.chromeProfileDirectory(matching: wanted, localState: chromeLocalState())
        var arguments = ["-na", chrome.path, "--args"]
        if let directory { arguments.append("--profile-directory=\(directory)") }
        arguments.append(url.absoluteString)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        do { try process.run() } catch { NSWorkspace.shared.open(url) }
    }

    private static func chromeLocalState() -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Google/Chrome/Local State")
        return try? Data(contentsOf: url)
    }
}

/// One source of sound: the Mac's own output or the microphone. Its sound is
/// streamed to ShazamKit, and kept as a rolling 16 kHz buffer that SongRec's
/// fingerprint, and AudD when set, are asked about every few seconds.
final class MusicRecognitionListener: NSObject, SHSessionDelegate, @unchecked Sendable {
    typealias Report = (String, RecognisedSong, Double?) -> Void

    private let source: String
    private let report: Report
    private let session = SHSession()
    private let lock = NSLock()
    private var stopped = false
    private var engine: AVAudioEngine?
    private var tap: RecorderSystemAudioTap?
    private var converters: [Double: (input: AVAudioFormat, converter: AVAudioConverter)] = [:]
    /// The last twelve seconds at 16 kHz, for the fingerprint.
    private var samples: [Float] = []
    private var heardSeconds: Double = 0
    private var nextAttempt = 0
    private var audDAsked = false
    private static let shazamKitFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100,
                                                       channels: 1, interleaved: false)!
    private static let songRecFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                                     channels: 1, interleaved: false)!
    /// When, in seconds of sound, SongRec is asked: early for speed, later for certainty.
    static let attempts: [Double] = [4, 7, 10, 13]
    static let maximumSeconds: Double = 12

    init(source: String, report: @escaping Report) {
        self.source = source
        self.report = report
        super.init()
        session.delegate = self
    }

    /// The Mac's own sound. False when the audio system gives no tap.
    func startSystemAudio() async -> Bool {
        guard let tap = await RecorderSystemAudioTap.make(hearing: nil) else { return false }
        let alreadyStopped = lock.withLock { () -> Bool in
            if !stopped { self.tap = tap }
            return stopped
        }
        guard !alreadyStopped else { return false }
        tap.onSample = { [weak self] sample in self?.receive(sample) }
        return await tap.start(synchronizingTo: CMClockGetHostTimeClock())
    }

    func startMicrophone() {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, _ in self?.receive(buffer) }
        do { try engine.start() } catch { return }
        lock.withLock { self.engine = engine }
    }

    func stop() {
        let (engine, tap) = lock.withLock { () -> (AVAudioEngine?, RecorderSystemAudioTap?) in
            stopped = true
            defer { self.engine = nil; self.tap = nil }
            return (self.engine, self.tap)
        }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        if let tap { Task { await tap.stop() } }
    }

    private var isStopped: Bool { lock.withLock { stopped } }

    private func receive(_ sample: CMSampleBuffer) {
        guard !isStopped, let description = CMSampleBufferGetFormatDescription(sample) else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames),
                                                           into: buffer.mutableAudioBufferList) == noErr else { return }
        receive(buffer)
    }

    private func receive(_ buffer: AVAudioPCMBuffer) {
        guard !isStopped else { return }
        if let forShazamKit = convert(buffer, to: Self.shazamKitFormat) {
            session.matchStreamingBuffer(forShazamKit, at: nil)
        }
        guard let mono = convert(buffer, to: Self.songRecFormat), let channel = mono.floatChannelData?[0] else { return }
        let fresh = Array(UnsafeBufferPointer(start: channel, count: Int(mono.frameLength)))
        let due: (window: [Float], seconds: Double)? = lock.withLock {
            samples.append(contentsOf: fresh)
            let keep = Int(Self.maximumSeconds) * 16_000
            if samples.count > keep { samples.removeFirst(samples.count - keep) }
            heardSeconds += Double(fresh.count) / 16_000
            guard nextAttempt < Self.attempts.count, heardSeconds >= Self.attempts[nextAttempt] else { return nil }
            nextAttempt += 1
            return (samples, heardSeconds)
        }
        guard let due, MusicRecognitionScoring.isAudible(due.window) else { return }
        let source = self.source, report = self.report
        Task.detached(priority: .userInitiated) {
            if let match = await SongRecEngine.recognise(due.window) {
                report("songrec-\(source)", RecognisedSong(title: match.title, artist: match.artist,
                                                          artworkURL: match.artworkURL), match.skew)
            }
        }
        let askAudD = lock.withLock { () -> Bool in
            guard !audDAsked, due.seconds >= 7, AudDEngine.isConfigured else { return false }
            audDAsked = true
            return true
        }
        if askAudD {
            Task.detached(priority: .userInitiated) {
                if let song = await AudDEngine.recognise(due.window) { report("audd-\(source)", song, nil) }
            }
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == target { return buffer }
        let converter: AVAudioConverter? = lock.withLock {
            if let existing = converters[target.sampleRate], existing.input == buffer.format { return existing.converter }
            guard let made = AVAudioConverter(from: buffer.format, to: target) else { return nil }
            converters[target.sampleRate] = (buffer.format, made)
            return made
        }
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var given = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }

    // MARK: SHSessionDelegate

    func session(_ session: SHSession, didFind match: SHMatch) {
        guard let item = match.mediaItems.first, let title = item.title else { return }
        report("shazamkit-\(source)", RecognisedSong(title: title, artist: item.artist ?? "", artworkURL: item.artworkURL), nil)
    }

    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {}
}

/// SongRec's way: the fingerprint made here, asked of Shazam's own service.
enum SongRecEngine {
    static func recognise(_ samples: [Float]) async -> ShazamMatch? {
        let signature = ShazamSignatureGenerator.signature(of: samples)
        guard signature.peakCount >= 20, let url = ShazamMatch.requestURL(),
              let body = ShazamMatch.requestBody(signature) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("en_US", forHTTPHeaderField: "Content-Language")
        request.setValue("Dalvik/2.1.0 (Linux; U; Android 5.0.2; VS980 4G Build/LRX22G)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return ShazamMatch.parse(data)
    }
}

/// AudD, used only when its key is set in Settings: a short clip of 16 kHz
/// mono sound is sent to it, as its service requires.
enum AudDEngine {
    static var key: String {
        (UserDefaults.standard.string(forKey: DefaultsKey.musicRecognitionAudDKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static var isConfigured: Bool { !key.isEmpty }

    static func recognise(_ samples: [Float]) async -> RecognisedSong? {
        guard isConfigured, let url = URL(string: "https://api.audd.io/") else { return nil }
        let boundary = "vorssaint-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("api_token", key)
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"clip.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(MusicRecognitionScoring.wav(samples))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let title = result["title"] as? String else { return nil }
        let artwork = ((result["spotify"] as? [String: Any])?["album"] as? [String: Any])
            .flatMap { ($0["images"] as? [[String: Any]])?.first?["url"] as? String }
        return RecognisedSong(title: title, artist: result["artist"] as? String ?? "", artworkURL: artwork.flatMap(URL.init(string:)))
    }
}

/// Other versions of a song from Apple's public iTunes Search, to fill the nearby row.
enum MusicRecognitionVersions {
    /// Searched by the song's bare title with its main artist, then by the title alone, so a remix
    /// finds its original and covers, and an original finds its remixes.
    static func search(_ song: RecognisedSong) async -> [RecognisedSong] {
        var found: [RecognisedSong] = []
        for term in MusicRecognitionScoring.searchTerms(for: song) {
            guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                  let url = URL(string: "https://itunes.apple.com/search?media=music&entity=song&limit=10&term=\(encoded)"),
                  let (data, _) = try? await URLSession.shared.data(from: url) else { continue }
            let taken = Set(found.map(\.id))
            found += MusicRecognitionScoring.versions(from: data, excluding: song).filter { !taken.contains($0.id) }
            if found.count >= 3 { break }
        }
        return found
    }
}
