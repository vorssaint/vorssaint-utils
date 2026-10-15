// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreServices

/// Spotify's MediaRemote session can be stale and does not carry its cover.
/// Read the running player itself, only after the app's existing Automation
/// consent is granted. All Apple Events are PID addressed and never interact.
final class NotchSpotifyPlayback {
    struct State {
        let identifier: String
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let position: Double
        let playing: Bool
        let artworkURL: URL?

        /// Records fetched on either side of a track change must never be
        /// combined into a title from one song and position from another.
        static func read(get: (_ property: UInt32, _ track: Bool) -> NSAppleEventDescriptor?) -> State? {
            guard let track = get(0x70414C4C, true), let application = get(0x70414C4C, false),
                  let state = decode(track: track, application: application),
                  get(0x49442020, true)?.stringValue == state.identifier else { return nil }
            return state
        }

        static func decode(track: NSAppleEventDescriptor, application: NSAppleEventDescriptor) -> State? {
            guard let identifier = track.forKeyword(0x49442020)?.stringValue,
                  NotchPlaybackCommand.validIdentifier(identifier),
                  let title = track.forKeyword(0x706E616D)?.stringValue, !title.isEmpty,
                  let milliseconds = track.forKeyword(0x70447572)?.doubleValue,
                  milliseconds.isFinite, (0...604_800_000).contains(milliseconds),
                  let position = application.forKeyword(0x70506F73)?.doubleValue,
                  position.isFinite, (0...604_800).contains(position),
                  let state = application.forKeyword(0x70506C53)?.enumCodeValue,
                  [UInt32(0x6B505350), 0x6B505370, 0x6B505353].contains(state) else { return nil }
            return State(identifier: identifier, title: title,
                         artist: track.forKeyword(0x70417274)?.stringValue ?? "",
                         album: track.forKeyword(0x70416C62)?.stringValue ?? "",
                         duration: milliseconds / 1000, position: position, playing: state == 0x6B505350,
                         artworkURL: coverURL(track.forKeyword(0x6155726C)?.stringValue))
        }

        static func coverURL(_ value: String?) -> URL? {
            guard let value, value.utf8.count <= 2048, let url = URL(string: value),
                  url.scheme == "https", url.host == "i.scdn.co", url.port == nil,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  url.path.hasPrefix("/image/"), url.path.count > 7 else { return nil }
            return url
        }

        func playback(pid: Int32, revision: UUID, artwork: Data?, now: Date = Date()) -> NotchPlayback {
            let track = RadialNowPlayingSnapshot(title: title, artist: artist, album: album, artworkData: artwork,
                                                appBundleIdentifier: "com.spotify.client", appPID: pid)
            return NotchPlayback(track: track, isPlaying: playing, elapsed: position, duration: duration,
                                 rate: playing ? 1 : 0, sampledAt: now, canSeek: false,
                                 itemIdentifier: identifier, commandContext: .init(pid: pid, revision: revision))
        }
    }

    let target: NotchMusicAutomation.Target
    private(set) var playback: NotchPlayback?
    private let receive: (NotchPlayback?) -> Void
    private let queue = DispatchQueue(label: "com.vorssaint.spotify-playback", qos: .userInitiated)
    private var stopped = false
    private var work: DispatchWorkItem?
    private var reading = false
    private var refreshWanted = false
    private var observer: NSObjectProtocol?
    private var state: State?
    private var sampledAt = Date()
    private var revision = UUID()
    private var artwork: Data?
    private var artworkURL: URL?
    private var coverRequest: UUID?
    private var session: URLSession?
    private var nextCoverAttemptAt: TimeInterval = 0

    init(target: NotchMusicAutomation.Target, receive: @escaping (NotchPlayback?) -> Void) {
        self.target = target
        self.receive = receive
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func stop() {
        stopped = true
        work?.cancel(); work = nil
        session?.invalidateAndCancel(); session = nil
        coverRequest = nil
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        playback = nil
    }

    /// A notification or successful command requests an immediate read. The
    /// one-second backstop also catches seeks and missed Spotify notifications.
    func refresh() {
        guard !stopped else { return }
        work?.cancel(); work = nil
        guard !reading else { refreshWanted = true; return }
        reading = true
        let target = target
        queue.async { [weak self] in
            let next = Self.read(target)
            DispatchQueue.main.async {
                guard let self, !self.stopped else { return }
                self.reading = false
                self.accept(next)
                if self.refreshWanted {
                    self.refreshWanted = false
                    self.refresh()
                } else {
                    let work = DispatchWorkItem { [weak self] in self?.refresh() }
                    self.work = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + (next == nil ? 0.25 : 1), execute: work)
                }
            }
        }
    }

    func validate(_ context: NotchPlaybackContext, completion: @escaping (Bool) -> Void) {
        guard !stopped, playback?.commandContext == context, let identifier = state?.identifier else {
            completion(false); return
        }
        let target = target
        queue.async { [weak self] in
            let matches = Self.currentIdentifier(target) == identifier
            DispatchQueue.main.async {
                guard let self, !self.stopped else { return }
                completion(matches && self.playback?.commandContext == context)
            }
        }
    }

    private func accept(_ next: State?) {
        guard let next else {
            // Missing permission or a failed read is not fresh evidence of the
            // old recording. Keep native discovery, but withdraw this authority.
            playback = nil
            state = nil
            // Withdraw commands, but let the bounded cover request finish.
            // A mixed read during a track transition is not a cover change.
            receive(nil)
            return
        }
        if state?.identifier != next.identifier {
            revision = UUID()
        }
        if artworkURL != next.artworkURL {
            artworkURL = next.artworkURL
            artwork = nil
            session?.invalidateAndCancel(); session = nil
            coverRequest = nil
            nextCoverAttemptAt = 0
        }
        state = next
        sampledAt = Date()
        // Consecutive songs may report exactly the same album URL. Reuse its
        // cover or in-flight download, and retry transient failures at most
        // once every fifteen seconds while this source remains subscribed.
        if artwork == nil, session == nil, let url = next.artworkURL,
           ProcessInfo.processInfo.systemUptime >= nextCoverAttemptAt {
            nextCoverAttemptAt = ProcessInfo.processInfo.systemUptime + 15
            let request = UUID()
            coverRequest = request
            session = NotchSpotifyCoverDownload.load(url) { [weak self] data in
                DispatchQueue.main.async {
                    guard let self, !self.stopped, self.coverRequest == request,
                          self.artworkURL == url else { return }
                    self.session = nil
                    self.artwork = data
                    self.publish()
                }
            }
        }
        publish()
    }

    private func publish() {
        guard let state else { return }
        playback = state.playback(pid: target.pid, revision: revision, artwork: artwork, now: sampledAt)
        receive(playback)
    }

    /// Spotify rejects `properties` and a list of property specifiers. Read
    /// only the individual fields defined by its installed scripting dictionary.
    static func read(_ target: NotchMusicAutomation.Target) -> State? {
        guard target.bundleIdentifier == "com.spotify.client", target.isCurrent,
              NotchMusicAutomation.access(to: target) == .granted else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        let state = State.read { code, track in
            get(code, container: track ? property(0x7054726B) : .null(), target: target, deadline: deadline)
        }
        return target.isCurrent ? state : nil
    }

    private static func currentIdentifier(_ target: NotchMusicAutomation.Target) -> String? {
        guard target.isCurrent, NotchMusicAutomation.access(to: target) == .granted else { return nil }
        let result = get(0x49442020, container: property(0x7054726B), target: target,
                         deadline: ProcessInfo.processInfo.systemUptime + 0.5)?.stringValue
        return target.isCurrent ? result : nil
    }

    private static func property(_ code: UInt32, container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: typeProperty), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: OSType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code), forKeyword: AEKeyword(keyAEKeyData))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        return record.coerce(toDescriptorType: typeObjectSpecifier)!
    }

    private static func get(_ code: UInt32, container: NSAppleEventDescriptor = .null(),
                            target: NotchMusicAutomation.Target, deadline: TimeInterval) -> NSAppleEventDescriptor? {
        // pALL is an internal request for our small record, never sent to Spotify.
        if code == 0x70414C4C {
            let codes: [UInt32] = container.descriptorType == typeNull ? [0x70506F73, 0x70506C53]
                : [0x49442020, 0x706E616D, 0x70417274, 0x70416C62, 0x70447572, 0x6155726C]
            let record = NSAppleEventDescriptor.record()
            for key in codes {
                let value: NSAppleEventDescriptor
                if let fetched = get(key, container: container, target: target, deadline: deadline) { value = fetched }
                else if [UInt32(0x70417274), 0x70416C62, 0x6155726C].contains(key) { value = .null() }
                else { return nil }
                record.setDescriptor(value, forKeyword: key)
            }
            return record
        }
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0, target.isCurrent else { return nil }
        let event = NSAppleEventDescriptor(eventClass: kAECoreSuite, eventID: kAEGetData,
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: target.pid),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(property(code, container: container), forKeyword: keyDirectObject)
        guard let reply = try? event.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: min(0.5, remaining)),
              (reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0) == 0 else { return nil }
        return reply.paramDescriptor(forKeyword: keyDirectObject)
    }
}

/// Fetch only Spotify's reported image from its CDN. No search, cookies, disk
/// cache or redirects; a streamed byte cap bounds even chunked responses.
private final class NotchSpotifyCoverDownload: NSObject, URLSessionDataDelegate {
    static let maximumBytes = 4 * 1024 * 1024
    private var data = Data()
    private var accepted = false
    private let completion: (Data?) -> Void
    private init(completion: @escaping (Data?) -> Void) { self.completion = completion }

    static func load(_ url: URL, completion: @escaping (Data?) -> Void) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.urlCredentialStorage = nil; config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config, delegate: NotchSpotifyCoverDownload(completion: completion), delegateQueue: nil)
        session.dataTask(with: url).resume()
        session.finishTasksAndInvalidate()
        return session
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        accepted = (response as? HTTPURLResponse)?.statusCode == 200
            && response.expectedContentLength <= Self.maximumBytes
            && response.mimeType?.hasPrefix("image/") == true
        completionHandler(accepted ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard accepted, chunk.count <= Self.maximumBytes - data.count else {
            accepted = false; dataTask.cancel(); return
        }
        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        completion(error == nil && accepted ? data : nil)
    }
}
