// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Emre Aribulan
import AppKit
import Combine
import ImageIO

/// Icons remain local; no third-party favicon API, browser cookies or saved credentials.
final class WebsiteShortcutIconService: ObservableObject {
    static let shared = WebsiteShortcutIconService()
    @Published private(set) var icons: [UUID: NSImage] = [:]
    @Published private(set) var darkIcons: Set<UUID> = []
    @Published private(set) var loading: Set<UUID> = []
    @Published private(set) var failed: Set<UUID> = []
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory =
            directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.vorssaint.utils", isDirectory: true)
            .appendingPathComponent("notch/website-icons", isDirectory: true)
    }

    func load(_ entry: IslandLauncherEntry, refresh: Bool = false) {
        guard let url = entry.websiteURL, tasks[entry.id] == nil else { return }
        let file = directory.appendingPathComponent(entry.id.uuidString + ".png")
        if !refresh {
            if icons[entry.id] != nil || failed.contains(entry.id) { return }
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_097_152,
                let data = try? Data(contentsOf: file), let png = WebsiteIconFetcher.rasterIcon(data),
                let image = NSImage(data: png)
            {
                store(image, data: png, id: entry.id)
                return
            }
        }
        loading.insert(entry.id)
        failed.remove(entry.id)
        tasks[entry.id] = Task { @MainActor [weak self] in
            let data = await WebsiteIconFetcher.icon(for: url)
            guard let self, !Task.isCancelled else { return }
            if let data, let image = NSImage(data: data) {
                self.store(image, data: data, id: entry.id)
                try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
                try? data.write(to: file, options: .atomic)
            } else {
                self.failed.insert(entry.id)
            }
            self.loading.remove(entry.id)
            self.tasks[entry.id] = nil
        }
    }

    private func store(_ image: NSImage, data: Data, id: UUID) {
        if WebsiteIconFetcher.needsLightBackground(data) { darkIcons.insert(id) } else { darkIcons.remove(id) }
        icons[id] = image
    }

    func remove(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        icons[id] = nil
        darkIcons.remove(id)
        loading.remove(id)
        failed.remove(id)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(id.uuidString + ".png"))
    }
}

enum WebsiteIconFetcher {
    /// Transparent dark marks (for example GitHub) need a light backing in the island.
    static func needsLightBackground(_ data: Data) -> Bool {
        guard let bitmap = NSBitmapImageRep(data: data), bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else {
            return true
        }
        var luminance = 0.0
        var weight = 0.0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: max(1, bitmap.pixelsHigh / 8)) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: max(1, bitmap.pixelsWide / 8)) {
                guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let alpha = colour.alphaComponent
                luminance +=
                    alpha
                    * (0.2126 * colour.redComponent + 0.7152 * colour.greenComponent + 0.0722 * colour.blueComponent)
                weight += alpha
            }
        }
        return weight == 0 || luminance / weight < 0.55
    }

    static func icon(for destination: URL) async -> Data? {
        // Icon discovery needs only the origin, never a saved page's private path/query.
        guard let origin = WebsiteShortcutSupport.origin(of: destination) else { return nil }
        let page = await WebsiteIconRequest.fetch(origin, limit: 524_288)
        let html =
            page.flatMap { String(data: $0.data, encoding: .utf8) ?? String(data: $0.data, encoding: .isoLatin1) } ?? ""
        let candidates = WebsiteShortcutSupport.iconCandidates(html: html, pageURL: page?.url ?? origin)
        for candidate in candidates {
            if Task.isCancelled { return nil }
            if let response = await WebsiteIconRequest.fetch(candidate, limit: 2_097_152),
                let png = rasterIcon(response.data)
            {
                return png
            }
        }
        return nil
    }

    /// Decode a bounded raster and cache a small PNG, preserving its colour/alpha.
    static func rasterIcon(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            (1...4096).contains(width), (1...4096).contains(height),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 128,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(writer, image, nil)
        return CGImageDestinationFinalize(writer) ? output as Data : nil
    }
}

/// A fresh, bounded request. Delegate callbacks share a serial queue.
final class WebsiteIconRequest: NSObject, URLSessionDataDelegate {
    struct Response {
        let data: Data
        let url: URL
    }
    private let limit: Int
    private var bytes = Data()
    private var session: URLSession?
    private var continuation: CheckedContinuation<Response?, Never>?
    private var redirects = 0
    private let lock = NSLock()
    private var cancelled = false
    private var task: URLSessionDataTask?

    private init(limit: Int) { self.limit = limit }

    static func fetch(_ url: URL, limit: Int) async -> Response? {
        guard IslandLauncherSupport.websiteURL(url.absoluteString) != nil else { return nil }
        let request = WebsiteIconRequest(limit: limit)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { request.start(url, continuation: $0) }
        } onCancel: {
            request.cancel()
        }
    }

    private func start(_ url: URL, continuation: CheckedContinuation<Response?, Never>) {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            continuation.resume(returning: nil)
            return
        }
        self.continuation = continuation
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        self.session = session
        var resource = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        resource.setValue("Vorssaint-Website-Icon", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: resource)
        self.task = task
        task.resume()
        lock.unlock()
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            response.expectedContentLength <= Int64(limit)
        else {
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard bytes.count + data.count <= limit else {
            dataTask.cancel()
            return
        }
        bytes.append(data)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirects += 1
        guard redirects <= 5, let url = request.url, IslandLauncherSupport.websiteURL(url.absoluteString) != nil,
            !(response.url?.scheme == "https" && url.scheme == "http")
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        let cancelled = cancelled
        self.task = nil
        self.session = nil
        lock.unlock()
        let response: Response?
        if !cancelled, error == nil, let http = task.response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode), let url = http.url
        {
            response = Response(data: bytes, url: url)
        } else {
            response = nil
        }
        continuation?.resume(returning: response)
        session.invalidateAndCancel()
    }
}
