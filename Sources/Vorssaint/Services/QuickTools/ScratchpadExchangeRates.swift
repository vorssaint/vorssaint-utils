// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// A checked response plus the moment it arrived. The provider's date says
/// which day the rates belong to; `fetchedAt` decides when another request is
/// due. Keeping them separate matters on a weekend, when a fresh download can
/// still carry Friday's date.
struct ScratchpadExchangeRateSnapshot: Codable, Equatable {
    let rates: ScratchpadCurrencyRates
    let fetchedAt: Date

    static let maximumAge: TimeInterval = 24 * 60 * 60

    func isFresh(now: Date, maximumAge: TimeInterval = Self.maximumAge) -> Bool {
        abs(now.timeIntervalSince(fetchedAt)) < maximumAge
    }
}

/// Frankfurter's public response, limited to the fields calculation mode uses.
struct ScratchpadExchangeRatePayload: Decodable {
    let base: String
    let date: String
    let rates: [String: Double]
}

enum ScratchpadExchangeRateParser {
    static let expectedBase = "USD"

    static func snapshot(from data: Data, fetchedAt: Date) -> ScratchpadExchangeRateSnapshot? {
        guard let payload = try? JSONDecoder().decode(ScratchpadExchangeRatePayload.self, from: data),
              payload.base.uppercased() == expectedBase,
              validDate(payload.date) else { return nil }
        let supported = ScratchpadCurrency.supportedSymbols
        var checked: [String: Double] = [:]
        for (rawSymbol, rate) in payload.rates {
            let symbol = rawSymbol.uppercased()
            guard supported.contains(symbol.lowercased()), rate.isFinite, rate > 0 else { continue }
            checked[symbol] = rate
        }
        guard !checked.isEmpty else { return nil }
        return ScratchpadExchangeRateSnapshot(
            rates: ScratchpadCurrencyRates(date: payload.date, base: expectedBase, rates: checked),
            fetchedAt: fetchedAt)
    }

    /// The provider writes ISO calendar dates. A malformed or impossible date
    /// fails the whole response rather than reaching the result column.
    static func validDate(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        parser.isLenient = false
        return parser.date(from: value) != nil
    }
}

enum ScratchpadExchangeRateCache {
    static var defaultURL: URL? {
        PrivateFileStore.containerURL?
            .appendingPathComponent("ScratchpadExchangeRates.json", isDirectory: false)
    }

    static func load(from url: URL) -> ScratchpadExchangeRateSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(ScratchpadExchangeRateSnapshot.self, from: data),
              !snapshot.rates.isBundled,
              snapshot.rates.base.uppercased() == ScratchpadExchangeRateParser.expectedBase,
              ScratchpadExchangeRateParser.validDate(snapshot.rates.date),
              snapshot.fetchedAt.timeIntervalSince1970.isFinite,
              !snapshot.rates.rates.isEmpty,
              snapshot.rates.rates.allSatisfy({ $0.key.count == 3 && $0.value.isFinite && $0.value > 0 })
        else { return nil }
        return snapshot
    }

    static func save(_ snapshot: ScratchpadExchangeRateSnapshot, to url: URL) -> Bool {
        guard PrivateFileStore.createDirectory(at: url.deletingLastPathComponent()),
              let data = try? JSONEncoder().encode(snapshot) else { return false }
        return PrivateFileStore.write(data, to: url)
    }
}

enum ScratchpadExchangeRateRedirect {
    static let host = "api.frankfurter.dev"

    /// The rate request may only hop within its own HTTPS host. A redirect to
    /// another address is treated as a failed download, never followed.
    static func allows(_ request: URLRequest) -> Bool {
        guard let url = request.url,
              url.scheme?.lowercased() == "https" else { return false }
        return url.host?.lowercased() == host
    }
}

enum ScratchpadExchangeRateHTTP {
    enum Failure: Error {
        case invalidResponse
        case tooLarge
    }

    static func load(_ request: URLRequest,
                     completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Developer"
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Vorssaint/\(version) (https://github.com/vorssaint/vorssaint-utils)",
            "Accept": "application/json",
        ]
        load(request, configuration: configuration, completion: completion)
    }

    static func load(_ request: URLRequest, configuration: URLSessionConfiguration,
                     completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
        let download = Download(completion: completion)
        let session = URLSession(configuration: configuration, delegate: download, delegateQueue: nil)
        session.dataTask(with: request).resume()
    }

    // URLSession delivers this delegate's callbacks on one serial queue.
    private final class Download: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private var data = Data()
        private var completion: ((Result<(Data, HTTPURLResponse), Error>) -> Void)?
        private let limit = 512 * 1024

        init(completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
            self.completion = completion
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                        didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            if response.expectedContentLength > limit {
                finish(.failure(Failure.tooLarge))
                completionHandler(.cancel)
            } else { completionHandler(.allow) }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
            guard chunk.count <= limit - data.count else {
                finish(.failure(Failure.tooLarge))
                dataTask.cancel()
                return
            }
            data.append(chunk)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            defer { session.finishTasksAndInvalidate() }
            if let error { finish(.failure(error)) }
            else if let response = task.response as? HTTPURLResponse { finish(.success((data, response))) }
            else { finish(.failure(Failure.invalidResponse)) }
        }

        private func finish(_ result: Result<(Data, HTTPURLResponse), Error>) {
            let callback = completion
            completion = nil
            callback?(result)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(ScratchpadExchangeRateRedirect.allows(request) ? request : nil)
        }
    }
}

/// Currency rates for calculation mode. The app ships with a usable table, so
/// no note ever needs the network to answer. A download happens only after the
/// person turns daily updates on or asks for one, at most once a day
/// automatically, and a failed download leaves the previous table in place.
final class ScratchpadExchangeRateService: ObservableObject {
    static let shared = ScratchpadExchangeRateService()

    typealias Loader = (URLRequest, @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) -> Void

    @Published private(set) var rates: ScratchpadCurrencyRates
    @Published private(set) var isRefreshing = false
    @Published private(set) var failed = false

    private let cacheURL: URL?
    private let loader: Loader
    private let now: () -> Date
    private var snapshot: ScratchpadExchangeRateSnapshot
    private var lastAttempt: Date?

    /// A failed automatic attempt waits before trying again, so opening notes
    /// while offline does not become a stream of requests. The explicit
    /// Update rates now action ignores this wait.
    private static let automaticRetryInterval: TimeInterval = 60 * 60

    init(cacheURL: URL? = ScratchpadExchangeRateCache.defaultURL,
         loader: @escaping Loader = ScratchpadExchangeRateHTTP.load,
         now: @escaping () -> Date = Date.init) {
        self.cacheURL = cacheURL
        self.loader = loader
        self.now = now
        let cached = cacheURL.flatMap(ScratchpadExchangeRateCache.load(from:))
        let starting = cached ?? ScratchpadExchangeRateSnapshot(
            rates: .bundled, fetchedAt: .distantPast)
        snapshot = starting
        rates = starting.rates
    }

    var hasCurrentRates: Bool {
        snapshot.isFresh(now: now())
    }

    private var retryIsDue: Bool {
        guard let lastAttempt else { return true }
        return abs(now().timeIntervalSince(lastAttempt)) >= Self.automaticRetryInterval
    }

    static var request: URLRequest {
        var components = URLComponents(string: "https://\(ScratchpadExchangeRateRedirect.host)/v1/latest")!
        let symbols = ScratchpadCurrency.supportedSymbols
            .subtracting([ScratchpadExchangeRateParser.expectedBase.lowercased()])
            .map { $0.uppercased() }
            .sorted()
            .joined(separator: ",")
        components.queryItems = [
            URLQueryItem(name: "from", value: ScratchpadExchangeRateParser.expectedBase),
            URLQueryItem(name: "to", value: symbols),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        return request
    }

    /// A daily refresh for the automatic path; `force` backs the explicit
    /// Update rates now action. The loader runs off the main thread and its
    /// result is applied on the main thread before any view reads it.
    func refreshIfNeeded(force: Bool = false) {
        guard !isRefreshing else { return }
        guard force || (retryIsDue && !snapshot.isFresh(now: now())) else { return }
        lastAttempt = now()
        isRefreshing = true
        failed = false
        loader(Self.request) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                switch result {
                case .success(let (data, response)):
                    guard response.statusCode == 200,
                          let next = ScratchpadExchangeRateParser.snapshot(from: data, fetchedAt: self.now())
                    else {
                        self.failed = true
                        return
                    }
                    self.snapshot = next
                    self.rates = next.rates
                    if let cacheURL = self.cacheURL {
                        _ = ScratchpadExchangeRateCache.save(next, to: cacheURL)
                    }
                case .failure:
                    self.failed = true
                }
            }
        }
    }
}
