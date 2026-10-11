// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import UniformTypeIdentifiers

final class NotchLyricsService: ObservableObject {
    static let shared = NotchLyricsService()
    enum State: Equatable { case idle, consent, loading, unavailable, failed, ready }
    @Published private(set) var state: State = .idle
    @Published private var memory = NotchLyricsMemory()
    var lyrics: NotchLyrics? { memory.lyrics }
    var offset: Double { memory.offset }
    private var track: NotchMusicIdentity? { memory.track }
    private var session: URLSession?
    private var generation = UUID()
    private var visible = false
    private var online = false
    private var importPanel: NSOpenPanel?
    var isImporting: Bool { importPanel != nil }

    private init() {}

    func update(playback: NotchPlayback?, visible: Bool) {
        guard NotchLyricsSupport.isEnabled() else { stop(); return }
        let next = playback.map(NotchMusicIdentity.init)
        let wanted = visible && next != nil
        let online = NotchLyricsSupport.onlineEnabled()
        let changedTrack = next != nil && next != track
        guard changedTrack || wanted != self.visible || online != self.online else { return }
        cancel()
        if changedTrack { memory.select(next) }
        self.visible = wanted
        self.online = online
        guard wanted, let track else { state = lyrics == nil ? .idle : .ready; return }
        if lyrics != nil { state = .ready; return }
        guard online else { state = .consent; return }
        load(track)
    }

    /// Called for actual adapter metadata, including an explicit empty snapshot.
    /// A hidden view supplies no such evidence and must not discard an import.
    func playbackChanged(_ playback: NotchPlayback?) {
        guard NotchLyricsSupport.isEnabled() else { stop(); return }
        let next = playback.map(NotchMusicIdentity.init)
        guard next != track else { return }
        let wasVisible = visible
        cancel()
        memory.select(next)
        visible = false
        state = .idle
        if let playback { update(playback: playback, visible: wasVisible) }
    }

    func retry() {
        guard visible, NotchLyricsSupport.onlineEnabled(), let track else { return }
        cancel()
        load(track)
    }

    func adjustOffset(by amount: Double) { memory.adjustOffset(by: amount) }
    func resetOffset() { memory.resetOffset() }

    func hide() {
        cancel()
        visible = false
        if !NotchLyricsSupport.isEnabled() { memory.clear() }
        state = lyrics == nil ? .idle : .ready
    }

    func stop() {
        cancel()
        visible = false
        online = false
        memory.clear()
        state = .idle
    }

    private func cancel() {
        generation = UUID()
        session?.invalidateAndCancel()
        session = nil
        importPanel?.cancel(nil)
        importPanel = nil
    }

    private func load(_ track: NotchMusicIdentity) {
        guard let url = NotchLyricsSupport.lookupURL(for: track) else { state = .unavailable; return }
        state = .loading
        let requested = generation
        session = NotchLyricsDownload.load(url) { [weak self] result in
            let lyrics = result.data.flatMap { NotchLyricsSupport.decode($0, for: track)
                ?? NotchLyricsSupport.decodeCatalogMatch($0, for: track) }
            DispatchQueue.main.async {
                guard let self, self.acceptsResult(for: track, generation: requested) else { return }
                self.session = nil
                if let lyrics { self.finish(lyrics, for: track, failed: false) }
                else if !result.canSearch { self.finish(nil, for: track, failed: true) }
                else {
                    self.search(track, urls: NotchLyricsSupport.searchURLs(for: track),
                                candidates: [], failed: result.failed, generation: requested)
                }
            }
        }
    }

    private func acceptsResult(for track: NotchMusicIdentity, generation requested: UUID) -> Bool {
        visible && generation == requested && self.track == track && NotchLyricsSupport.onlineEnabled()
    }

    private func finish(_ lyrics: NotchLyrics?, for track: NotchMusicIdentity, failed: Bool) {
        guard memory.replace(lyrics, for: track) else { return }
        state = lyrics != nil ? .ready : failed ? .failed : .unavailable
    }

    /// Sequential, bounded fallback on the same disclosed host. Each callback
    /// rechecks visibility, consent and song identity before issuing another request.
    private func search(_ track: NotchMusicIdentity, urls: [URL], candidates: [NotchLyricsSupport.Candidate],
                        failed: Bool, generation requested: UUID) {
        guard acceptsResult(for: track, generation: requested) else { return }
        guard let url = urls.first else {
            finish(NotchLyricsSupport.bestLyrics(in: candidates), for: track, failed: failed)
            return
        }
        session = NotchLyricsDownload.load(url, maximumBytes: NotchLyricsSupport.maximumSearchBytes) { [weak self] result in
            let found = result.data.map { NotchLyricsSupport.searchCandidates($0, for: track) } ?? []
            DispatchQueue.main.async {
                guard let self, self.acceptsResult(for: track, generation: requested) else { return }
                self.session = nil
                let accumulated = candidates + found
                if !result.canSearch {
                    self.finish(NotchLyricsSupport.bestLyrics(in: accumulated), for: track, failed: true)
                } else {
                    self.search(track, urls: Array(urls.dropFirst()), candidates: accumulated,
                                failed: failed || result.failed, generation: requested)
                }
            }
        }
    }

    func importLyrics() {
        guard visible, NotchLyricsSupport.isEnabled(), let track, importPanel == nil,
              let parent = NotchService.shared.presentationWindow,
              canReturnToLyrics(parent, track: track) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = FeatureStrings.notchMusicExtras(L10n.shared.language).importHint
        // An attached sheet moves/reskins a borderless island. Keep the chooser
        // independent and above its parent instead, without changing the pin.
        panel.level = NSWindow.Level(rawValue: parent.level.rawValue + 1)
        // Like the sheet it replaces, it stays up while another app is active.
        panel.hidesOnDeactivate = false
        importPanel = panel
        let requested = generation
        panel.begin { [weak self, weak panel, weak parent] response in
            guard let self, let panel, self.importPanel === panel else { return }
            let selectedURL = panel.url
            self.importPanel = nil
            guard let parent, self.generation == requested,
                  self.canReturnToLyrics(parent, track: track) else { return }
            defer {
                let returnGeneration = self.generation
                // Dismissal restores the old key window after this callback.
                DispatchQueue.main.async { [weak self, weak parent] in
                    guard let self, let parent, self.generation == returnGeneration,
                          self.importPanel == nil, self.canReturnToLyrics(parent, track: track) else { return }
                    NotchService.shared.open(.music, feedback: false)
                }
            }
            guard response == .OK, let url = selectedURL else { return }
            self.cancel()
            let importedGeneration = self.generation
            DispatchQueue.global(qos: .userInitiated).async {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                var lines: [NotchLyricLine] = []
                if let handle = try? FileHandle(forReadingFrom: url) {
                    defer { try? handle.close() }
                    if let data = try? handle.read(upToCount: NotchLyricsSupport.maximumBytes + 1),
                       data.count <= NotchLyricsSupport.maximumBytes,
                       let text = String(data: data, encoding: .utf8) {
                        lines = NotchLyricsSupport.parse(text, duration: track.duration)
                    }
                }
                let imported = lines
                DispatchQueue.main.async {
                    guard self.generation == importedGeneration, self.track == track, self.visible,
                          NotchLyricsSupport.isEnabled() else { return }
                    guard self.memory.replace(imported.isEmpty ? nil : NotchLyrics(lines: imported, plain: "", instrumental: false),
                                              for: track) else { return }
                    self.state = imported.isEmpty ? .failed : .ready
                }
            }
        }
        // isImporting keeps the music surface alive through activation and
        // pointer exit. Completion restores focus after native dismissal.
        NSApp.activate(ignoringOtherApps: true)
        // Activation alone can leave the nonactivating island holding focus.
        panel.makeKeyAndOrderFront(nil)
    }

    private func canReturnToLyrics(_ window: NSWindow, track expected: NotchMusicIdentity) -> Bool {
        let notch = NotchService.shared
        return visible && track == expected && NotchLyricsSupport.isEnabled()
            && notch.acceptsUserInteraction && notch.presentationWindow === window && window.isVisible
            && notch.expanded && notch.selected == .music && !notch.showingAppPanel
            && notch.selectedMetric == nil && notch.captureControls == nil
    }
}

/// An ephemeral request, bounded while bytes arrive. Redirects are refused
/// so track metadata can only reach the host disclosed by the opt-in control.
private final class NotchLyricsDownload: NSObject, URLSessionDataDelegate {
    private var data = Data()
    private var accepted = false
    private var status: Int?
    private let completion: (NotchLyricsDownloadResult) -> Void
    private let maximumBytes: Int
    private init(maximumBytes: Int, completion: @escaping (NotchLyricsDownloadResult) -> Void) {
        self.maximumBytes = maximumBytes
        self.completion = completion
    }

    static func load(_ url: URL, maximumBytes: Int = NotchLyricsSupport.maximumBytes, completion: @escaping (NotchLyricsDownloadResult) -> Void) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = ["User-Agent": "Vorssaint", "Accept": "application/json"]
        let delegate = NotchLyricsDownload(maximumBytes: maximumBytes, completion: completion)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        session.dataTask(with: url).resume()
        session.finishTasksAndInvalidate()
        return session
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        status = (response as? HTTPURLResponse)?.statusCode
        accepted = status == 200 && response.expectedContentLength <= maximumBytes
        completionHandler(accepted ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard accepted, chunk.count <= maximumBytes - data.count else {
            accepted = false
            dataTask.cancel()
            return
        }
        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error == nil && accepted { completion(.payload(data)) }
        else if status == 404 { completion(.missing) }
        else if let status, (500...599).contains(status) { completion(.serviceUnavailable) }
        else { completion(.failed) }
    }
}
