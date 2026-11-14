// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Active US weather alerts for the chosen place, read from the National
/// Weather Service. Requested only after a good forecast for a US point, and
/// cleared whenever the feature, the alert switch or the place stops applying.
/// Every failure stays silent: alerts are an extra, never a blocker.
@MainActor
final class WeatherAlertsService: ObservableObject {
    static let shared = WeatherAlertsService()

    @Published private(set) var alerts: [WeatherAlert] = []

    private let defaults: UserDefaults
    private let session: URLSession

    private var refreshTask: Task<[WeatherAlert]?, Never>?
    /// The point the current list belongs to, so a place change clears what
    /// the previous place left behind.
    private var point: String?

    init(defaults: UserDefaults = .standard,
         session: URLSession = WeatherAlertsService.makeSession()) {
        self.defaults = defaults
        self.session = session
    }

    nonisolated static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Vorssaint/\(AppInfo.version) (https://github.com/vorssaint/vorssaint-utils)",
            "Accept": WeatherAlertSupport.acceptHeader,
        ]
        return URLSession(configuration: configuration)
    }

    private var isEnabled: Bool {
        AppFeature.weather.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.weatherEnabled)
            && defaults.bool(forKey: DefaultsKey.weatherAlertsEnabled)
    }

    /// Called when the feature is installed, uninstalled or its switches move.
    /// Nothing is kept while alerts are off.
    func syncWithFeatures() {
        guard !isEnabled else { return }
        clear()
    }

    /// Fetches the active alerts for `location`, replacing the list. A nil or
    /// non-US location clears instead of requesting.
    func refresh(location: WeatherLocation?) async {
        guard isEnabled,
              let location,
              WeatherAlertSupport.isUSCoordinate(latitude: location.latitude,
                                                 longitude: location.longitude)
        else {
            clear()
            return
        }
        let point = "\(location.latitude),\(location.longitude)"
        if point != self.point {
            alerts = []
            self.point = point
        }
        guard let url = WeatherAlertSupport.activeURL(latitude: location.latitude,
                                                      longitude: location.longitude)
        else { return }

        refreshTask?.cancel()
        let task = Task { [weak self] () -> [WeatherAlert]? in
            guard let self else { return nil }
            guard let (data, response) = try? await self.session.data(from: url),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  !Task.isCancelled
            else { return nil }
            return WeatherAlertSupport.decodeAlerts(data)
        }
        refreshTask = task
        let decoded = await task.value
        guard !task.isCancelled, let decoded, isEnabled, point == self.point else { return }
        refreshTask = nil
        let now = Date()
        alerts = WeatherAlertSupport.sorted(decoded.filter { alert in
            guard let expiry = alert.expires ?? alert.ends else { return true }
            return expiry > now
        })
    }

    private func clear() {
        refreshTask?.cancel()
        refreshTask = nil
        point = nil
        if !alerts.isEmpty { alerts = [] }
    }
}
