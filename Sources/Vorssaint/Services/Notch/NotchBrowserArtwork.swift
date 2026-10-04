// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import ImageIO

/// Finds a cover for a Firefox-family browser, which publishes none to Now
/// Playing, or a 60-pixel one for YouTube Music. The playing tab's YouTube
/// thumbnail comes first, found through the browser's saved session. YouTube
/// Music keeps playing while the tab shows another page, and then the session
/// holds no video, so Apple's catalog supplies the album art instead. Covers
/// stay in memory for the few most recent tracks, and nothing is written to
/// disk.
final class NotchBrowserArtwork {
    static let shared = NotchBrowserArtwork()

    /// Firefox saves the session up to fifteen seconds after a change, so a
    /// track that just started may not carry its title there yet.
    private static let attemptDelays: [TimeInterval] = [0, 2, 5, 10, 18, 30]
    /// A track whose tab never showed up is not looked up again for a while.
    private static let failureCooldown: TimeInterval = 60
    private static let rememberedCovers = 8

    private let queue = DispatchQueue(label: "com.vorssaint.notch-browser-artwork", qos: .utility)
    private let lock = NSLock()
    private var covers: [String: Data] = [:]
    private var coverOrder: [String] = []
    private var failedAt: [String: Date] = [:]
    private var wanted: String?
    private var inFlight: String?

    private struct Lookup {
        let key: String
        let bundle: String
        let title: String
        let artist: String?
        let found: () -> Void
    }

    private static func key(for playback: NotchPlayback) -> String? {
        guard let bundle = playback.track.appBundleIdentifier,
              NotchBrowserArtworkSupport.profileFolders[bundle] != nil,
              let title = playback.track.title,
              NotchBrowserArtworkSupport.needsCover(playback.track.artworkData) else { return nil }
        return bundle + "\n" + title
    }

    func artwork(for playback: NotchPlayback) -> Data? {
        guard let key = Self.key(for: playback) else { return nil }
        return lock.withLock { covers[key] }
    }

    /// Starts one lookup per track. `found` runs on the lookup queue once a
    /// cover is ready for `artwork(for:)`.
    func request(for playback: NotchPlayback, found: @escaping () -> Void) {
        guard let key = Self.key(for: playback), let bundle = playback.track.appBundleIdentifier,
              let title = playback.track.title else { return }
        let starts = lock.withLock { () -> Bool in
            wanted = key
            guard covers[key] == nil, inFlight != key,
                  failedAt[key].map({ Date().timeIntervalSince($0) >= Self.failureCooldown }) ?? true else { return false }
            inFlight = key
            return true
        }
        guard starts else { return }
        attempt(0, Lookup(key: key, bundle: bundle, title: title, artist: playback.track.artist, found: found))
    }

    private func attempt(_ index: Int, _ lookup: Lookup) {
        queue.asyncAfter(deadline: .now() + Self.attemptDelays[index]) { [self] in
            // A newer track took over. Its own request runs its own lookup.
            guard lock.withLock({ wanted == lookup.key }) else { return finish(lookup.key, failed: false) }
            let urls = latestSession(bundle: lookup.bundle).map {
                NotchBrowserArtworkSupport.artworkURLs(forTrack: lookup.title,
                                                       in: NotchBrowserArtworkSupport.openTabs(inSession: $0))
            } ?? []
            if !urls.isEmpty {
                download(urls) { [self] data in
                    if let data { store(data, for: lookup) } else { finish(lookup.key, failed: true) }
                }
                return
            }
            // The first miss asks Apple at once, since waiting on the session
            // only helps a tab that is about to open the song's own page.
            guard index == 0, let search = NotchBrowserArtworkSupport.appleMusicSearchURL(
                title: lookup.title, artist: lookup.artist,
                country: Locale.current.region?.identifier) else { return retry(index, lookup) }
            NotchBrowserArtworkDownload.load(search, accept: "application/json") { [self] reply in
                queue.async { [self] in
                    guard let reply, let cover = NotchBrowserArtworkSupport.appleMusicArtworkURL(
                        inSearch: reply, title: lookup.title, artist: lookup.artist) else { return retry(index, lookup) }
                    download([cover]) { [self] data in
                        if let data { store(data, for: lookup) } else { retry(index, lookup) }
                    }
                }
            }
        }
    }

    private func retry(_ index: Int, _ lookup: Lookup) {
        if index + 1 < Self.attemptDelays.count {
            attempt(index + 1, lookup)
        } else {
            finish(lookup.key, failed: true)
        }
    }

    private func store(_ data: Data, for lookup: Lookup) {
        lock.withLock {
            covers[lookup.key] = data
            coverOrder.removeAll { $0 == lookup.key }
            coverOrder.append(lookup.key)
            while coverOrder.count > Self.rememberedCovers { covers[coverOrder.removeFirst()] = nil }
        }
        finish(lookup.key, failed: false)
        lookup.found()
    }

    private func finish(_ key: String, failed: Bool) {
        lock.withLock {
            if inFlight == key { inFlight = nil }
            if failed { failedAt[key] = Date() }
        }
    }

    /// The running profile keeps rewriting its recovery file, so the newest
    /// file across the browser's profiles belongs to the window playing now.
    private func latestSession(bundle: String) -> Data? {
        guard let folder = NotchBrowserArtworkSupport.profileFolders[bundle],
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let profiles = (try? FileManager.default.contentsOfDirectory(
            at: support.appendingPathComponent(folder, isDirectory: true), includingPropertiesForKeys: nil)) ?? []
        let newest = profiles
            .flatMap { profile in NotchBrowserArtworkSupport.sessionFiles.map { profile.appendingPathComponent($0) } }
            .compactMap { file -> (URL, Date)? in
                guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let modified = values.contentModificationDate,
                      let size = values.fileSize, size <= NotchBrowserArtworkSupport.maximumSessionBytes else { return nil }
                return (file, modified)
            }
            .max { $0.1 < $1.1 }
        guard let file = newest?.0, let compressed = try? Data(contentsOf: file) else { return nil }
        return NotchBrowserArtworkSupport.decodeMozLZ4(compressed)
    }

    /// Tries each address in turn and keeps the first real image.
    private func download(_ urls: [URL], completion: @escaping (Data?) -> Void) {
        guard let url = urls.first else { return completion(nil) }
        NotchBrowserArtworkDownload.load(url, accept: "image/jpeg") { [self] data in
            queue.async {
                if let data, let square = Self.squareCover(data) {
                    completion(square)
                } else {
                    self.download(Array(urls.dropFirst()), completion: completion)
                }
            }
        }
    }

    /// The island shrinks a cover to 320 pixels on its long edge before it
    /// crops a square. A 16:9 thumbnail would keep only 180 pixels of height
    /// and blur when stretched, so the cover arrives as its centre square.
    /// For YouTube Music that square is the album art without the side bars.
    private static func squareCover(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let square = image.cropping(to: NotchBrowserArtworkSupport.centreSquare(
                  width: image.width, height: image.height)) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, square,
                                   [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

/// A single ephemeral request with no cookies or cache, bounded while bytes
/// arrive. The delegate refuses redirects, so a request only ever reaches the
/// host it names, whether YouTube's thumbnails, Apple's search or Apple's artwork.
private final class NotchBrowserArtworkDownload: NSObject, URLSessionDataDelegate {
    private var data = Data()
    private var accepted = false
    private let completion: (Data?) -> Void
    private init(completion: @escaping (Data?) -> Void) { self.completion = completion }

    static func load(_ url: URL, accept: String, completion: @escaping (Data?) -> Void) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = ["User-Agent": "Vorssaint", "Accept": accept]
        let delegate = NotchBrowserArtworkDownload(completion: completion)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        session.dataTask(with: url).resume()
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        accepted = (response as? HTTPURLResponse)?.statusCode == 200
            && response.expectedContentLength <= NotchBrowserArtworkSupport.maximumArtworkBytes
        completionHandler(accepted ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard accepted, chunk.count <= NotchBrowserArtworkSupport.maximumArtworkBytes - data.count else {
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
        completion(error == nil && accepted ? data : nil)
    }
}
