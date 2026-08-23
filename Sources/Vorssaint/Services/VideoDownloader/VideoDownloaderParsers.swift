// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum VideoDownloaderRateLimitSupport {
    static func isRateLimited(stderr: Data) -> Bool {
        isRateLimited(String(decoding: stderr, as: UTF8.self))
    }

    static func isRateLimited(_ message: String) -> Bool {
        let normalized = message.lowercased()
        let rateLimitSignals = [
            "http error 429",
            "http 429",
            "http status 429",
            "status code 429",
            "status code: 429",
            "429 too many requests",
            "too many requests",
            "rate limit exceeded",
            "rate-limited",
            "rate limited",
            "ratelimit",
        ]
        let antiBotSignals = [
            "cloudflare",
            "captcha",
            "verify you are human",
            "automated requests",
        ]
        let hasRateLimitSignal = rateLimitSignals.contains(where: normalized.contains)
        let hasAntiBotSignal = antiBotSignals.contains(where: normalized.contains)
        return hasRateLimitSignal || hasAntiBotSignal
    }

    /// Distinguish anti-bot challenges (Cloudflare, CAPTCHAs, 429s) from generic errors so we can
    /// guide the user to solve the challenge in their browser and forward cookies.
    static func shouldSuggestRateLimitHelp(_ message: String) -> Bool {
        let normalized = message.lowercased()
        let forbiddenSignals = [
            "http error 403",
            "http 403",
            "http status 403",
            "status code 403",
            "403 forbidden",
        ]
        return isRateLimited(normalized) || forbiddenSignals.contains(where: normalized.contains)
    }
}

enum VideoDownloaderURLValidator {
    static let maximumUTF8Bytes = 16 * 1024

    static func validate(_ input: String) throws -> ValidatedVideoURL {
        guard input.utf8.count <= maximumUTF8Bytes else { throw VideoURLValidationError.tooLong }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw VideoURLValidationError.controlCharacter
        }
        guard !trimmed.isEmpty else { throw VideoURLValidationError.empty }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased() else {
            throw VideoURLValidationError.malformed
        }
        guard scheme == "http" || scheme == "https" else {
            throw VideoURLValidationError.unsupportedScheme
        }
        guard let host = components.host, !host.isEmpty else {
            throw VideoURLValidationError.missingHost
        }
        guard components.user == nil, components.password == nil else {
            throw VideoURLValidationError.credentials
        }
        guard let url = components.url else { throw VideoURLValidationError.malformed }
        return ValidatedVideoURL(value: url, string: url.absoluteString)
    }
}

/// Prevent SSRF (Server-Side Request Forgery) attacks where a malicious site returns
/// loopback (127.0.0.1) or LAN addresses as thumbnails to probe local services.
enum VideoDownloaderThumbnailURLPolicy {
    static let maximumURLBytes = 4 * 1024
    static let maximumResponseBytes = 4 * 1024 * 1024
    static let maximumPixelDimension = 4_096

    static func sanitizedURL(_ url: URL?) -> URL? {
        guard let url,
              url.absoluteString.utf8.count <= maximumURLBytes,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https",
              let host = parts.host?.lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
              !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443,
              !isBlockedHostname(host),
              !isRestrictedLiteral(host) else { return nil }
        return parts.url
    }

    /// Defend against DNS rebinding where a domain resolves to both public and internal IPs.
    /// Rejecting mixed results prevents URLSession from accidentally connecting to LAN endpoints.
    static func resolvesToPublicEndpoint(_ url: URL) -> Bool {
        guard let rawHost = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host else {
            return false
        }
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if isRestrictedLiteral(host) { return false }

        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_flags = AI_ADDRCONFIG
        var first: UnsafeMutablePointer<addrinfo>?
        let status = host.withCString { getaddrinfo($0, nil, &hints, &first) }
        guard status == 0, let first else { return false }
        defer { freeaddrinfo(first) }

        var sawAddress = false
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let entry = current {
            let info = entry.pointee
            if info.ai_family == AF_INET, let rawAddress = info.ai_addr {
                sawAddress = true
                let restricted = rawAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    isRestrictedIPv4($0.pointee.sin_addr)
                }
                if restricted { return false }
            } else if info.ai_family == AF_INET6, let rawAddress = info.ai_addr {
                sawAddress = true
                let restricted = rawAddress.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                    isRestrictedIPv6($0.pointee.sin6_addr)
                }
                if restricted { return false }
            }
            current = info.ai_next
        }
        return sawAddress
    }

    static func isPublicAddress(_ value: String) -> Bool {
        let host = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !host.isEmpty else { return false }
        var ipv4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            return !isRestrictedIPv4(ipv4)
        }
        var ipv6 = in6_addr()
        if host.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
            return !isRestrictedIPv6(ipv6)
        }
        return false
    }

    private static func isBlockedHostname(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !normalized.isEmpty else { return true }
        if ["localhost", "localhost.localdomain", "broadcasthost"].contains(normalized) {
            return true
        }
        return [".localhost", ".local", ".internal", ".lan", ".home", ".test",
                ".invalid", ".example"].contains { normalized.hasSuffix($0) }
    }

    private static func isRestrictedLiteral(_ host: String) -> Bool {
        var ipv4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            return isRestrictedIPv4(ipv4)
        }
        var ipv6 = in6_addr()
        if host.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
            return isRestrictedIPv6(ipv6)
        }
        return false
    }

    private static func isRestrictedIPv4(_ address: in_addr) -> Bool {
        withUnsafeBytes(of: address.s_addr) { isRestrictedIPv4($0) }
    }

    private static func isRestrictedIPv4(_ bytes: UnsafeRawBufferPointer) -> Bool {
        guard bytes.count == 4 else { return true }
        let first = bytes[0]
        let second = bytes[1]
        if first == 0 || first == 10 || first == 127 || first >= 224 { return true }
        if first == 100 && (64...127).contains(second) { return true }
        if first == 169 && second == 254 { return true }
        if first == 172 && (16...31).contains(second) { return true }
        if first == 192 && (second == 0 || second == 2 || second == 168) { return true }
        if first == 192 && second == 88 && bytes[2] == 99 { return true }
        if first == 198 && (second == 18 || second == 19 || second == 51) { return true }
        if first == 203 && second == 0 && bytes[2] == 113 { return true }
        return false
    }

    private static func isRestrictedIPv6(_ address: in6_addr) -> Bool {
        withUnsafeBytes(of: address) { bytes in
            guard bytes.count == 16 else { return true }
            if bytes.allSatisfy({ $0 == 0 }) || (bytes[15] == 1 && bytes.prefix(15).allSatisfy({ $0 == 0 })) {
                return true
            }
            if bytes[0] & 0xfe == 0xfc || (bytes[0] & 0xfe == 0xfe && bytes[1] & 0xc0 == 0x80)
                || bytes[0] == 0xff {
                return true
            }
            if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8 {
                return true
            }
            if bytes.prefix(10).allSatisfy({ $0 == 0 }) && bytes[10] == 0xff && bytes[11] == 0xff {
                let v4Slice = UnsafeRawBufferPointer(rebasing: bytes[12..<16])
                return isRestrictedIPv4(v4Slice)
            }
            return false
        }
    }
}

/// Keep thumbnail preview and artwork embedding on the exact same security sandbox
/// (ephemeral cache, byte caps, and public IP verification).
final class VideoDownloaderImageFetcher: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    typealias Completion = (Data?) -> Void

    private let lock = NSLock()
    private let url: URL
    private let timeout: TimeInterval
    private let endpointValidator: (URL) -> Bool
    private let configurationProvider: () -> URLSessionConfiguration
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var completion: Completion?
    private var data = Data()
    private var acceptedResponse = false
    private var unsafeRemoteAddress = false
    private var redirects = 0
    private var finished = false

    init(url: URL,
         timeout: TimeInterval,
         endpointValidator: @escaping (URL) -> Bool = {
             VideoDownloaderThumbnailURLPolicy.resolvesToPublicEndpoint($0)
         },
         configurationProvider: @escaping () -> URLSessionConfiguration = { .ephemeral }) {
        self.url = url
        self.timeout = max(timeout, 0.1)
        self.endpointValidator = endpointValidator
        self.configurationProvider = configurationProvider
    }

    func start(completion: @escaping Completion) {
        guard let safeURL = VideoDownloaderThumbnailURLPolicy.sanitizedURL(url) else {
            completion(nil)
            return
        }

        lock.lock()
        guard !finished else {
            lock.unlock()
            completion(nil)
            return
        }
        self.completion = completion
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            guard self.endpointValidator(safeURL) else {
                self.finish(nil)
                return
            }
            self.startRequest(safeURL)
        }
    }

    private func startRequest(_ safeURL: URL) {
        // Close the TOCTOU (time-of-check to time-of-use) race window between DNS validation
        // and opening the actual URLSession connection.
        guard endpointValidator(safeURL) else {
            finish(nil)
            return
        }

        let configuration = configurationProvider()
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration,
                                  delegate: self,
                                  delegateQueue: queue)
        var request = URLRequest(url: safeURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = false
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let task = session.dataTask(with: request)

        lock.lock()
        guard !finished else {
            lock.unlock()
            session.invalidateAndCancel()
            return
        }
        self.session = session
        self.task = task
        self.data.removeAll(keepingCapacity: true)
        self.acceptedResponse = false
        self.unsafeRemoteAddress = false
        self.redirects = 0
        lock.unlock()
        task.resume()
    }

    func cancel() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let task = self.task
        let session = self.session
        let completion = self.completion
        self.task = nil
        self.session = nil
        self.completion = nil
        lock.unlock()

        task?.cancel()
        session?.invalidateAndCancel()
        completion?(nil)
    }

    static func fetchData(url: URL,
                          timeout: TimeInterval,
                          isCancelled: () -> Bool) -> Data? {
        guard !isCancelled() else { return nil }
        let fetcher = VideoDownloaderImageFetcher(url: url, timeout: timeout)
        let condition = NSCondition()
        var completed = false
        var result: Data?

        fetcher.start { data in
            condition.lock()
            result = data
            completed = true
            condition.broadcast()
            condition.unlock()
        }

        let deadline = Date().addingTimeInterval(max(timeout, 0.1))
        condition.lock()
        while !completed && !isCancelled() && Date() < deadline {
            condition.wait(until: Date().addingTimeInterval(0.05))
        }
        let outcome = isCancelled() ? nil : result
        condition.unlock()

        if outcome == nil { fetcher.cancel() }
        return outcome
    }

    private func finish(_ result: Data?) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let session = self.session
        let completion = self.completion
        self.task = nil
        self.session = nil
        self.completion = nil
        lock.unlock()

        session?.finishTasksAndInvalidate()
        completion?(result)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didFinishCollecting metrics: URLSessionTaskMetrics) {
        let networkMetrics = metrics.transactionMetrics.filter {
            $0.resourceFetchType == .networkLoad
        }
        guard networkMetrics.contains(where: { metric in
            // Proxies mask the destination server's real IP, making safety checks unverifiable.
            guard !metric.isProxyConnection, let remoteAddress = metric.remoteAddress else {
                return true
            }
            return !VideoDownloaderThumbnailURLPolicy.isPublicAddress(remoteAddress)
        }) else { return }
        lock.lock()
        let shouldCancel = self.session === session && self.task === task && !finished
        if shouldCancel { unsafeRemoteAddress = true }
        lock.unlock()
        if shouldCancel {
            task.cancel()
            finish(nil)
        }
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard isActive(session, task: dataTask),
              let http = response as? HTTPURLResponse,
              let responseURL = response.url,
              let safeResponseURL = VideoDownloaderThumbnailURLPolicy.sanitizedURL(responseURL),
              endpointValidator(safeResponseURL),
              (200...299).contains(http.statusCode),
              response.mimeType?.lowercased().hasPrefix("image/") == true,
              (response.expectedContentLength == NSURLSessionTransferSizeUnknown
                || response.expectedContentLength <= Int64(VideoDownloaderThumbnailURLPolicy.maximumResponseBytes)) else {
            completionHandler(.cancel)
            finish(nil)
            return
        }

        lock.lock()
        acceptedResponse = true
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive chunk: Data) {
        lock.lock()
        let active = self.session === session && self.task === dataTask && !finished
        let withinLimit = active
            && data.count + chunk.count <= VideoDownloaderThumbnailURLPolicy.maximumResponseBytes
        if withinLimit { data.append(chunk) }
        lock.unlock()
        guard withinLimit else {
            dataTask.cancel()
            finish(nil)
            return
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock()
        guard self.session === session, self.task === task, !finished, redirects < 3 else {
            lock.unlock()
            completionHandler(nil)
            finish(nil)
            return
        }
        redirects += 1
        lock.unlock()

        guard let redirected = request.url,
              let safeURL = VideoDownloaderThumbnailURLPolicy.sanitizedURL(redirected),
              endpointValidator(safeURL) else {
            completionHandler(nil)
            finish(nil)
            return
        }
        var safeRequest = request
        safeRequest.url = safeURL
        safeRequest.httpShouldHandleCookies = false
        safeRequest.setValue("image/*", forHTTPHeaderField: "Accept")
        completionHandler(safeRequest)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        lock.lock()
        let result = error == nil && acceptedResponse && !unsafeRemoteAddress && !data.isEmpty ? data : nil
        lock.unlock()
        finish(result)
    }

    private func isActive(_ session: URLSession, task: URLSessionTask) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return self.session === session && self.task === task && !finished
    }
}

enum VideoDownloaderInspectionParser {
    static let maximumJSONBytes = 8 * 1024 * 1024

    static func parse(_ data: Data,
                      maximumBytes: Int = maximumJSONBytes,
                      allowAuthenticatedContent: Bool = false) throws -> VideoDownloaderMedia {
        guard data.count <= maximumBytes else { throw VideoDownloaderFailure.inspectionTooLarge }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VideoDownloaderFailure.malformedInspection
        }
        let type = string(json["_type"])?.lowercased()
        if type == "playlist" || type == "multi_video" || json["entries"] != nil {
            throw VideoDownloaderFailure.playlist
        }
        let liveStatus = string(json["live_status"])?.lowercased()
        if bool(json["is_live"]) == true
            || ["is_live", "is_upcoming", "post_live"].contains(liveStatus ?? "") {
            throw VideoDownloaderFailure.live
        }
        let availability = string(json["availability"])?.lowercased()
        if let availability,
           !["public", "unlisted"].contains(availability),
           !allowAuthenticatedContent {
            throw VideoDownloaderFailure.restricted
        }
        let formats = json["formats"] as? [[String: Any]] ?? []
        // yt-dlp's internal format selectors are smarter than our basic UI inspector. We extract
        // what we can for the UI picker, but never reject unfamiliar format lists.
        let remoteFormats = formats.filter(isUsableMediaFormat)
        let usableFormats = remoteFormats.filter { bool($0["has_drm"]) != true }
        // A video might list DRM-protected 4K streams alongside public 1080p streams. We only
        // fail inspection if zero playable public streams remain.
        if usableFormats.isEmpty,
           bool(json["has_drm"]) == true || bool(json["_has_drm"]) == true
            || remoteFormats.contains(where: { bool($0["has_drm"]) == true }) {
            throw VideoDownloaderFailure.drm
        }
        let videoFormats = usableFormats.filter {
            codecAvailability($0["vcodec"], extensionValue: $0["video_ext"]) != .unavailable
                && positiveInt($0["height"]) != nil
        }
        let videoAvailability = streamAvailability(in: usableFormats,
                                                   codecKey: "vcodec",
                                                   extensionKey: "video_ext")
        let audioAvailability = streamAvailability(in: usableFormats,
                                                   codecKey: "acodec",
                                                   extensionKey: "audio_ext")
        guard let title = string(json["title"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            throw VideoDownloaderFailure.malformedInspection
        }

        let duration = positiveDouble(json["duration"])
        let heights = Array(Set(videoFormats.compactMap { positiveInt($0["height"]) })).sorted(by: >)
        let audioFormats = usableFormats.filter {
            codecAvailability($0["acodec"], extensionValue: $0["audio_ext"]) == .available
        }
        try validateSizeMetadata(in: usableFormats, topLevel: json, duration: duration)
        let targetAudioSize = try preferredAudioStreamSize(in: audioFormats, duration: duration)
        let topLevelSize = try int64(json["filesize"]) ?? (try int64(json["filesize_approx"]))
        let estimatedAudioSize = targetAudioSize ?? (audioAvailability == .available ? topLevelSize : nil)

        var estimatedSizes: [Int: Int64] = [:]
        for height in heights {
            let heightFormats = usableFormats.filter { positiveInt($0["height"]) == height }
            if let size = try preferredVideoStreamSize(in: heightFormats,
                                                       audioSize: targetAudioSize,
                                                       duration: duration) {
                estimatedSizes[height] = size
            }
        }
        if heights.count == 1, let singleHeight = heights.first, estimatedSizes[singleHeight] == nil {
            if let topLevelSize {
                estimatedSizes[singleHeight] = topLevelSize
            }
        }

        let subtitles = tracks(json["subtitles"], source: .manual)
            + tracks(json["automatic_captions"], source: .automatic)
        return VideoDownloaderMedia(
            title: title,
            uploader: string(json["uploader"]) ?? string(json["channel"]),
            duration: VideoDownloaderNumericPolicy.timeInterval(duration),
            thumbnailURL: bestThumbnail(in: json),
            previewThumbnailURL: previewThumbnail(in: json),
            heights: heights,
            estimatedSizes: estimatedSizes,
            estimatedAudioSize: estimatedAudioSize,
            videoAvailability: videoAvailability,
            audioAvailability: audioAvailability,
            subtitles: subtitles,
            hasChapters: !(json["chapters"] as? [[String: Any]] ?? []).isEmpty
        )
    }

    private static func int64(_ value: Any?) throws -> Int64? {
        if let value = value as? NSNumber {
            switch String(cString: value.objCType) {
            case "C", "S", "I", "L", "Q":
                let unsignedValue = value.uint64Value
                guard unsignedValue <= UInt64(Int64.max) else {
                    throw VideoDownloaderFailure.malformedInspection
                }
                return unsignedValue > 0 ? Int64(unsignedValue) : nil
            case "c", "s", "i", "l", "q":
                let signedValue = value.int64Value
                return signedValue > 0 ? signedValue : nil
            default:
                return try checkedInt64(value.doubleValue)
            }
        }
        if let value = value as? Double { return try checkedInt64(value) }
        if let value = value as? String {
            if let integerValue = Int64(value), integerValue > 0 { return integerValue }
            if let doubleValue = Double(value) { return try checkedInt64(doubleValue) }
        }
        return nil
    }

    private static func checkedInt64(_ value: Double) throws -> Int64? {
        guard value.isFinite, value > 0 else { return nil }
        guard value < Double(Int64.max) else {
            throw VideoDownloaderFailure.malformedInspection
        }
        return Int64(value)
    }

    private static func validateSizeMetadata(in formats: [[String: Any]],
                                             topLevel: [String: Any],
                                             duration: Double?) throws {
        _ = try int64(topLevel["filesize"])
        _ = try int64(topLevel["filesize_approx"])
        for format in formats {
            _ = try int64(format["filesize"])
            _ = try int64(format["filesize_approx"])
            _ = try formatSize(format, duration: duration)
        }
    }

    private static func formatSize(_ format: [String: Any], duration: Double? = nil) throws -> Int64? {
        if let exact = try int64(format["filesize"]) {
            return exact
        }
        if let approx = try int64(format["filesize_approx"]) {
            return approx
        }
        if let duration, duration > 0 {
            let bitrate = positiveDouble(format["tbr"])
                ?? positiveDouble(format["vbr"])
                ?? positiveDouble(format["abr"])
            if let bitrate, bitrate > 0 {
                // yt-dlp bitrate is in kbit/s (1000 bits/s)
                let bytes = (bitrate * 1000.0 / 8.0) * duration
                guard bytes.isFinite else { throw VideoDownloaderFailure.malformedInspection }
                guard bytes > 0 else { return nil }
                return try checkedInt64(bytes)
            }
        }
        return nil
    }

    private static func vcodecScore(_ codec: String?) -> Double {
        guard let codec = codec?.lowercased() else { return 0 }
        if codec.starts(with: "av01") || codec.starts(with: "av1") { return 9.0 }
        if codec.starts(with: "vp09.02") || codec.starts(with: "vp9.2") { return 8.5 }
        if codec.starts(with: "vp09") || codec.starts(with: "vp9") { return 8.0 }
        if codec.starts(with: "h265") || codec.starts(with: "hevc") || codec.starts(with: "hev1") || codec.starts(with: "hvc1") { return 7.0 }
        if codec.starts(with: "h264") || codec.starts(with: "avc1") || codec.starts(with: "avc") { return 6.0 }
        if codec != "none" { return 5.0 }
        return 0
    }

    private static func acodecScore(_ codec: String?) -> Double {
        guard let codec = codec?.lowercased() else { return 0 }
        if codec.starts(with: "flac") || codec.starts(with: "alac") || codec.starts(with: "wav") { return 10.0 }
        if codec.starts(with: "opus") { return 8.0 }
        if codec.starts(with: "vorbis") { return 7.0 }
        if codec.starts(with: "mp4a") || codec.starts(with: "aac") { return 6.0 }
        if codec.starts(with: "mp3") { return 5.0 }
        if codec.starts(with: "eac3") || codec.starts(with: "ac3") || codec.starts(with: "ac-3") { return 4.0 }
        if codec != "none" { return 3.0 }
        return 0
    }

    private static func videoRank(_ format: [String: Any], duration: Double?) throws -> (Double, Double, Double) {
        let vscore = vcodecScore(string(format["vcodec"]))
        let fps = positiveDouble(format["fps"]) ?? 0
        let bitrateOrSize = try (positiveDouble(format["vbr"])
            ?? positiveDouble(format["tbr"])
            ?? (formatSize(format, duration: duration).map(Double.init) ?? 0))
        return (vscore, fps, bitrateOrSize)
    }

    private static func isVideoRankBetter(_ lhs: [String: Any], than rhs: [String: Any], duration: Double?) throws -> Bool {
        let l = try videoRank(lhs, duration: duration)
        let r = try videoRank(rhs, duration: duration)
        if l.0 != r.0 { return l.0 < r.0 }
        if l.1 != r.1 { return l.1 < r.1 }
        return l.2 < r.2
    }

    private static func audioRank(_ format: [String: Any], duration: Double?) throws -> (Double, Double, Double) {
        let ascore = acodecScore(string(format["acodec"]))
        let bitrateOrSize = try (positiveDouble(format["abr"])
            ?? positiveDouble(format["tbr"])
            ?? (formatSize(format, duration: duration).map(Double.init) ?? 0))
        let asr = positiveDouble(format["asr"]) ?? 0
        return (ascore, bitrateOrSize, asr)
    }

    private static func isAudioRankBetter(_ lhs: [String: Any], than rhs: [String: Any], duration: Double?) throws -> Bool {
        let l = try audioRank(lhs, duration: duration)
        let r = try audioRank(rhs, duration: duration)
        if l.0 != r.0 { return l.0 < r.0 }
        if l.1 != r.1 { return l.1 < r.1 }
        return l.2 < r.2
    }

    /// Mirrors yt-dlp's ba[ext=m4a]/ba audio selector to pick the expected standard audio track size.
    private static func preferredAudioStreamSize(in formats: [[String: Any]], duration: Double?) throws -> Int64? {
        let m4aFormats = formats.filter {
            let ext = (string($0["ext"]) ?? string($0["audio_ext"]))?.lowercased()
            return ext == "m4a" && codecAvailability($0["acodec"], extensionValue: $0["audio_ext"]) == .available
        }
        let pool = m4aFormats.isEmpty ? formats.filter {
            codecAvailability($0["acodec"], extensionValue: $0["audio_ext"]) == .available
        } : m4aFormats
        guard let best = try pool.max(by: { try isAudioRankBetter($0, than: $1, duration: duration) }) else { return nil }
        return try formatSize(best, duration: duration)
    }

    /// Mirrors yt-dlp's bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b selector hierarchy.
    private static func preferredVideoStreamSize(in formats: [[String: Any]],
                                                 audioSize: Int64?,
                                                 duration: Double?) throws -> Int64? {
        // Tier 1: bv*[ext=mp4] + ba[ext=m4a]
        let mp4VideoOnly = formats.filter {
            codecAvailability($0["vcodec"], extensionValue: $0["video_ext"]) == .available
                && codecAvailability($0["acodec"], extensionValue: $0["audio_ext"]) == .unavailable
                && (string($0["ext"]) ?? string($0["video_ext"]))?.lowercased() == "mp4"
        }
        if let bestVideo = try mp4VideoOnly.max(by: { try isVideoRankBetter($0, than: $1, duration: duration) }),
           let videoSize = try formatSize(bestVideo, duration: duration) {
            return try checkedAdd(videoSize, audioSize ?? 0)
        }

        // Tier 2: b[ext=mp4] (combined)
        let mp4Combined = formats.filter {
            codecAvailability($0["vcodec"], extensionValue: $0["video_ext"]) == .available
                && codecAvailability($0["acodec"], extensionValue: $0["audio_ext"]) == .available
                && (string($0["ext"]) ?? string($0["video_ext"]))?.lowercased() == "mp4"
        }
        if let bestCombined = try mp4Combined.max(by: { try isVideoRankBetter($0, than: $1, duration: duration) }),
           let combinedSize = try formatSize(bestCombined, duration: duration) {
            return combinedSize
        }

        // Tier 3: bv* + ba (any extension, e.g. webm/mkv)
        let anyVideoOnly = formats.filter {
            codecAvailability($0["vcodec"], extensionValue: $0["video_ext"]) == .available
                && codecAvailability($0["acodec"], extensionValue: $0["audio_ext"]) == .unavailable
        }
        if let bestVideo = try anyVideoOnly.max(by: { try isVideoRankBetter($0, than: $1, duration: duration) }),
           let videoSize = try formatSize(bestVideo, duration: duration) {
            return try checkedAdd(videoSize, audioSize ?? 0)
        }

        // Tier 4: b (any combined)
        let anyCombined = formats.filter {
            codecAvailability($0["vcodec"], extensionValue: $0["video_ext"]) == .available
                && codecAvailability($0["acodec"], extensionValue: $0["audio_ext"]) == .available
        }
        if let bestCombined = try anyCombined.max(by: { try isVideoRankBetter($0, than: $1, duration: duration) }),
           let combinedSize = try formatSize(bestCombined, duration: duration) {
            return combinedSize
        }

        return nil
    }

    private static func checkedAdd(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw VideoDownloaderFailure.malformedInspection }
        return result
    }

    private static func tracks(_ value: Any?,
                               source: VideoDownloaderSubtitleSource) -> [VideoDownloaderSubtitleTrack] {
        guard let values = value as? [String: Any] else { return [] }
        return values.compactMap { code, raw -> VideoDownloaderSubtitleTrack? in
            guard validSubtitleCode(code), code.lowercased() != "live_chat",
                  let entries = raw as? [[String: Any]], !entries.isEmpty else { return nil }
            let name = entries.compactMap { string($0["name"]) }.first
            return VideoDownloaderSubtitleTrack(code: code, source: source, name: name)
        }.sorted {
            if $0.code != $1.code { return $0.code.localizedStandardCompare($1.code) == .orderedAscending }
            return $0.source.rawValue < $1.source.rawValue
        }
    }

    static func validSubtitleCode(_ code: String) -> Bool {
        guard !code.isEmpty, code.utf8.count <= 64 else { return false }
        // yt-dlp treats `--sub-langs` as regex. Restricting to standard alphanumeric codes
        // avoids unintended partial matches or regex injection.
        return code.range(of: #"^[A-Za-z0-9][A-Za-z0-9_@-]*$"#,
                          options: .regularExpression) != nil
    }

    private static func isUsableMediaFormat(_ format: [String: Any]) -> Bool {
        let protocolName = string(format["protocol"])?.lowercased() ?? ""
        guard !["mhtml", "images", "storyboard"].contains(protocolName) else { return false }
        return ["url", "manifest_url"].contains { key in
            guard let rawURL = string(format[key]),
                  let components = URLComponents(string: rawURL),
                  ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
                  components.host?.isEmpty == false else { return false }
            return true
        }
    }

    private static func streamAvailability(in formats: [[String: Any]],
                                           codecKey: String,
                                           extensionKey: String) -> VideoDownloaderStreamAvailability {
        guard !formats.isEmpty else { return .unknown }
        let values = formats.map {
            codecAvailability($0[codecKey], extensionValue: $0[extensionKey])
        }
        if values.contains(.available) { return .available }
        if values.allSatisfy({ $0 == .unavailable }) { return .unavailable }
        return .unknown
    }

    private static func codecAvailability(_ value: Any?,
                                          extensionValue: Any? = nil)
        -> VideoDownloaderStreamAvailability {
        if let value = string(value)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !value.isEmpty {
            return value == "none" ? .unavailable : .available
        }
        // Direct/generic extractors often omit codec names but still specify stream extensions
        // (e.g. video-only MKV files report acodec=null and audio_ext=none).
        if let extensionValue = string(extensionValue)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !extensionValue.isEmpty {
            return extensionValue == "none" ? .unavailable : .available
        }
        return .unknown
    }

    private struct ThumbnailCandidate {
        let url: URL
        let score: Double
        let width: Double
        let height: Double

        var pixelCount: Double { width * height }
    }

    private static func bestThumbnail(in json: [String: Any]) -> URL? {
        thumbnailCandidates(in: json).max(by: { $0.score < $1.score })?.url
    }

    private static func previewThumbnail(in json: [String: Any]) -> URL? {
        let candidates = thumbnailCandidates(in: json).filter { $0.width > 0 && $0.height > 0 }
        let displaySized = candidates.filter { $0.width >= 320 && $0.height >= 180 }
        if let candidate = displaySized.min(by: { lhs, rhs in
            if lhs.pixelCount != rhs.pixelCount { return lhs.pixelCount < rhs.pixelCount }
            return lhs.score < rhs.score
        }) {
            return candidate.url
        }
        return candidates.max(by: { $0.pixelCount < $1.pixelCount })?.url
            ?? bestThumbnail(in: json)
    }

    private static func thumbnailCandidates(in json: [String: Any]) -> [ThumbnailCandidate] {
        var candidates: [ThumbnailCandidate] = []
        if let value = remoteURL(string(json["thumbnail"])) {
            candidates.append(ThumbnailCandidate(url: value, score: 1, width: 0, height: 0))
        }
        for (index, item) in (json["thumbnails"] as? [[String: Any]] ?? []).enumerated() {
            guard let value = remoteURL(string(item["url"])) else { continue }
            let width = positiveDouble(item["width"]) ?? 0
            let height = positiveDouble(item["height"]) ?? 0
            let preference = double(item["preference"]) ?? 0
            candidates.append(ThumbnailCandidate(url: value,
                                                  score: width * height + preference * 1_000 + Double(index),
                                                  width: width,
                                                  height: height))
        }
        return candidates
    }

    private static func remoteURL(_ raw: String?) -> URL? {
        VideoDownloaderThumbnailURLPolicy.sanitizedURL(raw.flatMap(URL.init(string:)))
    }

    private static func string(_ value: Any?) -> String? { value as? String }
    private static func bool(_ value: Any?) -> Bool? { value as? Bool }

    private static func double(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func positiveDouble(_ value: Any?) -> Double? {
        guard let value = double(value), value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        guard let value = positiveDouble(value), value <= 16_384 else { return nil }
        return Int(value.rounded())
    }
}

enum VideoDownloaderSubtitleSelection {
    static func pickerTracks(in tracks: [VideoDownloaderSubtitleTrack]) -> [VideoDownloaderSubtitleTrack] {
        var options: [VideoDownloaderSubtitleTrack] = []

        for track in tracks {
            let key = pickerKey(for: track.code)
            if let index = options.firstIndex(where: { pickerKey(for: $0.code) == key }) {
                if isPreferred(track, over: options[index]) {
                    options[index] = track
                }
            } else {
                options.append(track)
            }
        }
        return options
    }

    static func defaultTrack(in tracks: [VideoDownloaderSubtitleTrack],
                             appLanguage: AppLanguage) -> VideoDownloaderSubtitleTrack? {
        let exact = normalized(appLanguage.rawValue)
        let language = primary(exact)
        let priorities: [(VideoDownloaderSubtitleSource, (VideoDownloaderSubtitleTrack) -> Bool)] = [
            (.manual, { normalized($0.code) == exact }),
            (.manual, { primary($0.code) == language }),
            (.manual, { primary($0.code) == "en" }),
            // YouTube's translated captions often hit HTTP 429 rate limits, whereas the original
            // source track (`*-orig`) remains accessible. We prioritize the reliable source track.
            (.automatic, { normalized($0.code).hasSuffix("-orig") }),
            (.automatic, { normalized($0.code) == exact }),
            (.automatic, { primary($0.code) == language }),
            (.automatic, { primary($0.code) == "en" }),
        ]
        for (source, matches) in priorities {
            if let track = tracks.first(where: { $0.source == source && matches($0) }) {
                return track
            }
        }
        // Stick to tracks that actually exist in the inspected metadata so the user
        // never selects an invalid language option.
        return tracks.first(where: { $0.source == .manual }) ?? tracks.first
    }

    static func localizedName(for track: VideoDownloaderSubtitleTrack,
                              appLanguage: AppLanguage) -> String {
        let locale = Locale(identifier: appLanguage.rawValue)
        let primaryCode = primary(track.code)
        return locale.localizedString(forLanguageCode: track.code)
            ?? locale.localizedString(forLanguageCode: primaryCode)
            ?? track.name
            ?? track.code
    }

    private static func primary(_ code: String) -> String {
        normalized(code).split(separator: "-").first.map(String.init) ?? normalized(code)
    }

    private static func normalized(_ code: String) -> String {
        code.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func pickerKey(for code: String) -> String {
        let value = normalized(code)
        return value.hasSuffix("-orig") ? String(value.dropLast(5)) : value
    }

    private static func isPreferred(_ candidate: VideoDownloaderSubtitleTrack,
                                    over existing: VideoDownloaderSubtitleTrack) -> Bool {
        if candidate.source != existing.source {
            return candidate.source == .manual
        }
        if candidate.source == .automatic {
            let candidateIsOriginal = normalized(candidate.code).hasSuffix("-orig")
            let existingIsOriginal = normalized(existing.code).hasSuffix("-orig")
            if candidateIsOriginal != existingIsOriginal {
                return candidateIsOriginal
            }
        }
        return false
    }
}

/// Detect extractor messages for private or age-gated media so videos that bypass
/// inspection via fallback still produce friendly login reminders instead of crashes.
enum VideoDownloaderRestrictedContentSupport {
    static func isRestricted(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return [
            "this video is private",
            "private video",
            "this video is only available to members",
            "members-only",
            "sign in to watch",
            "sign in to confirm your age",
        ].contains(where: normalized.contains)
    }
}

/// When yt-dlp fails to download its challenge-solver script from GitHub, it reports an
/// internal solver error. We detect this to clearly explain the GitHub connectivity issue.
enum VideoDownloaderEJSComponentSupport {
    static func isFailure(_ message: String) -> Bool {
        let normalized = message.lowercased()
        guard normalized.contains("ejs") || normalized.contains("challenge solver") else { return false }
        let failureSignals = ["unable", "could not", "failed", "error", "not found", "download",
                              "network", "connection", "timed out", "unreachable", "refused",
                              "403", "429"]
        return failureSignals.contains(where: normalized.contains)
    }
}

/// Builds the raw extractor failure shown when yt-dlp fails in a way the app
/// does not recognize. The message is trimmed so a huge stderr dump stays
/// readable in the popover; an empty message falls back to the generic error.
enum VideoDownloaderExtractorErrorSupport {
    static let maximumMessageLength = 2_000

    static func failure(from stderr: Data, fallback: VideoDownloaderFailure) -> VideoDownloaderFailure {
        let message = String(decoding: stderr, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return fallback }
        // When we terminate a process on timeout or cancel, macOS writes "Terminated: 15" to stderr.
        // Filter this out so we don't display our own cancellation signals as remote site errors.
        if message.lowercased().range(of: #"^(?:terminated|killed): \d+$"#,
                                       options: .regularExpression) != nil {
            return fallback
        }
        let limited = message.count > maximumMessageLength
            ? String(message.suffix(maximumMessageLength))
            : message
        return .extractorError(limited)
    }
}

/// The one failure classifier shared by inspection and download. Both paths
/// run the same ordered checks (cookies, rate limit, DRM, restricted, EJS,
/// raw extractor text); a path-specific check slots in before the raw
/// fallback via `extraChecks`.
enum VideoDownloaderFailureClassifier {
    static func failure(stderr: Data,
                        cookiesFromBrowser: String? = nil,
                        fallback: VideoDownloaderFailure = .inspectionFailed,
                        extraChecks: ((String) -> VideoDownloaderFailure?)? = nil) -> VideoDownloaderFailure {
        let rawMessage = String(decoding: stderr, as: UTF8.self)
        let message = rawMessage.lowercased()
        if VideoDownloaderCookiesSupport.isAccessDenied(message,
                                                         cookiesFromBrowser: cookiesFromBrowser) {
            return .cookiesPermission
        }
        if VideoDownloaderRateLimitSupport.isRateLimited(message) {
            return .rateLimited
        }
        if isDRM(message) {
            return .drm
        }
        if VideoDownloaderRestrictedContentSupport.isRestricted(message) {
            return .restricted
        }
        if let extra = extraChecks?(message) {
            return extra
        }
        if VideoDownloaderEJSComponentSupport.isFailure(message) {
            return .ejsComponentFailure
        }
        return VideoDownloaderExtractorErrorSupport.failure(from: stderr, fallback: fallback)
    }

    // yt-dlp logs informational messages about DRM formats it discarded. Only treat it as an
    // error if DRM protection actually blocked the entire download.
    static func isDRM(_ message: String) -> Bool {
        message.contains("drm protected")
            || message.contains("drm-protected")
            || message.contains("protected by drm")
            || message.contains("drm protection")
            || message.contains("digital rights management")
    }
}

/// Browser cookie access requires macOS Full Disk Access. We keep this strictly opt-in so
/// standard downloads don't prompt for sensitive system permissions.
enum VideoDownloaderCookiesSupport {
    /// Browser names exactly as yt-dlp's --cookies-from-browser accepts them.
    static let supportedBrowsers = ["safari", "chrome", "chromium", "edge",
                                    "firefox", "brave", "opera", "vivaldi"]

    static func selectedBrowser(defaults: UserDefaults = .standard) -> String? {
        guard defaults.bool(forKey: DefaultsKey.videoDownloaderUseBrowserCookies) else { return nil }
        let browser = defaults.string(forKey: DefaultsKey.videoDownloaderCookiesBrowser) ?? ""
        let trimmed = browser.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return supportedBrowsers.contains(trimmed) ? trimmed : nil
    }

    // Full Disk Access permission denials only matter when the user explicitly enabled browser cookies;
    // otherwise, generic filesystem errors shouldn't prompt for cookie permissions.
    static func isAccessDenied(_ message: String,
                               cookiesFromBrowser: String?) -> Bool {
        guard cookiesFromBrowser != nil else { return false }
        let normalized = message.lowercased()
        let accessSignals = [
            "operation not permitted",
            "permission denied",
            "access denied",
            "not permitted",
            "could not copy",
            "unable to open",
            "could not open",
        ]
        guard accessSignals.contains(where: normalized.contains) else { return false }
        let cookieStoreSignals = [
            "cookie", "cookies", "keychain", "keyring", "/library/safari",
            "safari", "chrome", "chromium", "firefox", "brave", "edge",
            "opera", "vivaldi",
        ]
        return cookieStoreSignals.contains(where: normalized.contains)
    }

    static func isAccessDenied(stderr: Data,
                               cookiesFromBrowser: String?) -> Bool {
        isAccessDenied(String(decoding: stderr, as: UTF8.self),
                       cookiesFromBrowser: cookiesFromBrowser)
    }
}

enum VideoDownloaderEmbeddedDataParser {
    static let maximumJSONBytes = 512 * 1024

    static func parse(_ data: Data) -> VideoDownloaderEmbeddedDataInspection? {
        guard !data.isEmpty, data.count <= maximumJSONBytes,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let streams = root["streams"] as? [[String: Any]] ?? []
        let hasVideo = streams.contains { stream in
            guard string(stream["codec_type"]) == "video" else { return false }
            let disposition = stream["disposition"] as? [String: Any]
            return !flag(disposition?["attached_pic"])
        }
        let hasAudio = streams.contains { string($0["codec_type"]) == "audio" }
        let hasSubtitle = streams.contains { string($0["codec_type"]) == "subtitle" }
        let hasArtwork = streams.contains { stream in
            guard string(stream["codec_type"]) == "video",
                  let disposition = stream["disposition"] as? [String: Any] else { return false }
            return flag(disposition["attached_pic"])
        }
        let hasChapters = !(root["chapters"] as? [[String: Any]] ?? []).isEmpty
        let format = root["format"] as? [String: Any]
        let container = mediaContainer(formatName: string(format?["format_name"]), hasVideo: hasVideo)
        let tags = normalizedTags(format?["tags"])
        let metadataKeys = ["title", "artist", "album", "description", "comment"]
        return VideoDownloaderEmbeddedDataInspection(
            hasVideo: hasVideo,
            hasAudio: hasAudio,
            hasSubtitle: hasSubtitle,
            hasArtwork: hasArtwork,
            hasChapters: hasChapters,
            hasMetadata: metadataKeys.contains { nonempty(tags[$0]) },
            container: container
        )
    }

    private static func mediaContainer(formatName: String?, hasVideo: Bool) -> VideoDownloaderMediaContainer? {
        let names = Set((formatName ?? "").split(separator: ",").map(String.init))
        if names.contains("matroska") { return .mkv }
        if names.contains("mp4") || names.contains("mov") || names.contains("m4a") || names.contains("ipod") {
            return hasVideo ? .mp4 : .m4a
        }
        return nil
    }

    private static func normalizedTags(_ value: Any?) -> [String: Any] {
        guard let tags = value as? [String: Any] else { return [:] }
        return tags.reduce(into: [String: Any]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }
    }

    private static func string(_ value: Any?) -> String? {
        (value as? String)?.lowercased()
    }

    private static func flag(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.intValue == 1 }
        return false
    }

    private static func nonempty(_ value: Any?) -> Bool {
        guard let value = value as? String else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum VideoDownloaderEmbeddedDataVerifier {
    static func failure(in inspection: VideoDownloaderEmbeddedDataInspection,
                        for request: VideoDownloaderRequest) -> VideoDownloaderFailure? {
        if request.mode == .video {
            guard inspection.hasVideo,
                  inspection.container == .mp4 || inspection.container == .mkv else {
                return .fileSafety
            }
            if request.media.audioAvailability == .available, !inspection.hasAudio {
                return .fileSafety
            }
        } else if !inspection.hasAudio || inspection.hasVideo || (inspection.container != .m4a && inspection.container != .mp4) {
            return .fileSafety
        }
        return nil
    }

    static func warnings(in inspection: VideoDownloaderEmbeddedDataInspection,
                         for request: VideoDownloaderRequest,
                         includeSubtitleWarning: Bool = true) -> [VideoDownloaderWarning] {
        var warnings: [VideoDownloaderWarning] = []
        if request.mode == .video, request.subtitle != nil,
           includeSubtitleWarning, !inspection.hasSubtitle {
            warnings.append(.subtitle)
        }
        if request.media.thumbnailURL != nil, !inspection.hasArtwork {
            warnings.append(.artwork)
        }
        if !inspection.hasMetadata {
            warnings.append(.metadata)
        }
        if request.media.hasChapters,
           !inspection.hasChapters {
            warnings.append(.chapters)
        }
        return warnings
    }
}

enum VideoDownloaderProtocolParser {
    static func parse(line: String) -> VideoDownloaderParsedEvent? {
        if line.hasPrefix(VideoDownloaderCommandBuilder.progressPrefix) {
            let payload = String(line.dropFirst(VideoDownloaderCommandBuilder.progressPrefix.count))
            guard let json = progressFields(payload) else { return nil }
            let downloaded = finite(json["downloaded"])
            let total = finite(json["total"])
            let percent = percentage(json["percent"])
            let elapsed = positive(json["elapsed"])
            let fraction: Double?
            if let percent {
                fraction = min(max(percent / 100, 0), 1)
            } else if let downloaded, let total, total > 0 {
                fraction = min(max(downloaded / total, 0), 1)
            } else if let fragmentIndex = finite(json["fragment_index"]),
                      let fragmentCount = positive(json["fragment_count"]) {
                fraction = min(max(fragmentIndex / fragmentCount, 0), 1)
            } else {
                fraction = nil
            }
            let speed = positive(json["speed"])
                ?? derivedSpeed(downloaded: downloaded, elapsed: elapsed)
            let eta = VideoDownloaderNumericPolicy.timeInterval(positive(json["eta"]))
                ?? VideoDownloaderNumericPolicy.timeInterval(derivedETA(fraction: fraction, elapsed: elapsed))
            let fileExtension = json["extension"] as? String
            let formatID = json["format_id"] as? String
            let hasMediaFormat = formatID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let hasVideoCodec = isAvailableStream(json["vcodec"])
                || isAvailableStream(json["video_ext"])
            let hasAudioCodec = isAvailableStream(json["acodec"])
                || isAvailableStream(json["audio_ext"])
            // Distinguish auxiliary sidecars (captions/art) from actual media streams by extension so progress tracking doesn't stall.
            let isAuxiliary = isAuxiliaryProgressExtension(fileExtension)
            return .progress(VideoDownloaderRawProgress(
                fraction: fraction,
                speedBytesPerSecond: speed,
                etaSeconds: eta,
                isAuxiliary: isAuxiliary,
                isCombinedMedia: hasMediaFormat && hasVideoCodec && hasAudioCodec
            ))
        }
        if line.hasPrefix(VideoDownloaderCommandBuilder.titlePrefix) {
            return jsonString(String(line.dropFirst(VideoDownloaderCommandBuilder.titlePrefix.count))).map {
                .title($0)
            }
        }
        if line.hasPrefix(VideoDownloaderCommandBuilder.qualityPrefix) {
            let payload = String(line.dropFirst(VideoDownloaderCommandBuilder.qualityPrefix.count))
            guard let data = payload.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                return nil
            }
            if value is NSNull { return .selectedVideoHeight(nil) }
            guard let height = finite(value), height > 0, height <= Double(Int.max),
                  height.rounded(.towardZero) == height else { return nil }
            return .selectedVideoHeight(Int(height))
        }
        if line.hasPrefix(VideoDownloaderCommandBuilder.pathPrefix) {
            return jsonString(String(line.dropFirst(VideoDownloaderCommandBuilder.pathPrefix.count))).map {
                .path($0)
            }
        }
        return nil
    }

    private static func progressFields(_ payload: String) -> [String: Any]? {
        if let data = payload.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return nil }

        let pattern = #"\"([a-zA-Z0-9_]+)\"\s*:\s*(\"[^\"]*\"|[^,}\s]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsString = trimmed as NSString
        let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else { return nil }

        var result: [String: Any] = [:]
        for match in matches where match.numberOfRanges == 3 {
            let key = nsString.substring(with: match.range(at: 1))
            let rawValue = nsString.substring(with: match.range(at: 2))
            if rawValue == "null" || rawValue == "NA" || rawValue == "N/A" || rawValue == "None" {
                result[key] = NSNull()
            } else if let data = "[\(rawValue)]".data(using: .utf8),
                      let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
                      let value = array.first {
                result[key] = value
            } else if rawValue.hasPrefix("\""), rawValue.hasSuffix("\""), rawValue.count >= 2 {
                result[key] = String(rawValue.dropFirst().dropLast())
            } else {
                result[key] = rawValue
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func isAuxiliaryProgressExtension(_ fileExtension: String?) -> Bool {
        guard let fileExtension else { return false }
        return ["ass", "avif", "dfxp", "gif", "jpe", "jpg", "jpeg", "json3", "lrc",
                "png", "srt", "ssa", "srv1", "srv2", "srv3", "ttml", "vtt", "webp"]
            .contains(fileExtension.lowercased())
    }

    private static func isAvailableStream(_ value: Any?) -> Bool {
        guard let value = value as? String else { return false }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.isEmpty && normalized != "none" && normalized != "null"
    }

    private static func derivedSpeed(downloaded: Double?, elapsed: Double?) -> Double? {
        guard let downloaded, downloaded > 0, let elapsed, elapsed > 0 else { return nil }
        let value = downloaded / elapsed
        return value.isFinite && value > 0 ? value : nil
    }

    private static func derivedETA(fraction: Double?, elapsed: Double?) -> Double? {
        guard let fraction, fraction > 0, fraction < 1,
              let elapsed, elapsed > 0 else { return nil }
        let value = elapsed * (1 - fraction) / fraction
        return value.isFinite && value > 0 ? value : nil
    }

    private static func percentage(_ value: Any?) -> Double? {
        if let number = finite(value) { return number }
        guard var value = value as? String else { return nil }
        value = value.replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(value).flatMap { $0.isFinite ? $0 : nil }
    }

    private static func positive(_ value: Any?) -> Double? {
        guard let value = finite(value), value > 0 else { return nil }
        return value
    }

    private static func finite(_ value: Any?) -> Double? {
        let number: Double?
        if let value = value as? NSNumber { number = value.doubleValue }
        else if let value = value as? String { number = Double(value) }
        else { number = nil }
        guard let number, number.isFinite else { return nil }
        return number
    }

    private static func jsonString(_ value: String) -> String? {
        guard let data = value.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data,
                                                               options: [.fragmentsAllowed]) as? String else { return nil }
        return decoded
    }
}

struct VideoDownloaderLineDecoder {
    private var buffer = Data()
    private let maximumBufferedBytes: Int

    init(maximumBufferedBytes: Int = 256 * 1024) {
        self.maximumBufferedBytes = maximumBufferedBytes
    }

    mutating func append(_ data: Data) -> [String] {
        buffer.append(data)
        if buffer.count > maximumBufferedBytes, !buffer.contains(0x0A) {
            buffer.removeFirst(buffer.count - maximumBufferedBytes)
        }
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = buffer.prefix(upTo: newline)
            if line.last == 0x0D { line = line.dropLast() }
            lines.append(String(decoding: line, as: UTF8.self))
            buffer.removeSubrange(...newline)
        }
        return lines
    }

    mutating func finish() -> String? {
        guard !buffer.isEmpty else { return nil }
        var line = buffer[...]
        if line.last == 0x0D { line = line.dropLast() }
        buffer.removeAll(keepingCapacity: false)
        return String(decoding: line, as: UTF8.self)
    }
}
