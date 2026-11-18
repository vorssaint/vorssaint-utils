// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// RainViewer's published radar frames, fetched only when the radar sheet asks
/// for them. Nothing polls and nothing loads at launch. A good reply stays in
/// memory for a few minutes so reopening the sheet does not ask again.
@MainActor
final class WeatherRadarService: ObservableObject {
    static let shared = WeatherRadarService()

    @Published private(set) var maps: WeatherRadarMaps?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let session: URLSession
    private let now: () -> Date
    private let cacheLifetime: TimeInterval
    private var cachedAt: Date?

    init(session: URLSession = WeatherRadarService.makeSession(),
         now: @escaping () -> Date = Date.init,
         cacheLifetime: TimeInterval = 5 * 60) {
        self.session = session
        self.now = now
        self.cacheLifetime = cacheLifetime
    }

    nonisolated static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Vorssaint/\(AppInfo.version) (https://github.com/vorssaint/vorssaint-utils)",
        ]
        return URLSession(configuration: configuration)
    }

    func load(force: Bool = false) async {
        if !force, maps != nil,
           let cachedAt, now().timeIntervalSince(cachedAt) < cacheLifetime {
            return
        }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let (data, response) = try? await session.data(from: WeatherRadarSupport.mapsURL),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let decoded = WeatherRadarSupport.decodeMaps(data)
        else {
            // The HTTP detail is for logs, never for the sheet: the generic
            // line and a retry say everything a person needs.
            guard !Task.isCancelled else { return }
            if let cachedAt, now().timeIntervalSince(cachedAt) >= cacheLifetime {
                maps = nil
            }
            if maps == nil { errorMessage = strings.loadFailed }
            return
        }
        guard !Task.isCancelled else { return }
        maps = decoded
        cachedAt = now()
    }

    private var strings: WeatherStrings { FeatureStrings.weather(L10n.shared.language) }
}
