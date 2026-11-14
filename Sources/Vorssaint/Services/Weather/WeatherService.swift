// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import CoreLocation
import Foundation

/// Keeps one forecast for the chosen place, refreshes it every fifteen
/// minutes while the feature is installed and switched on, and keeps the last
/// good result on disk so the panel never opens empty after a relaunch.
///
/// Manual location is the default. CoreLocation starts only when
/// `useCurrentLocation()` is called, so no permission prompt appears just
/// because the feature is installed.
@MainActor
final class WeatherService: NSObject, ObservableObject {
    static let shared = WeatherService()

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var state: WeatherLoadState = .idle
    @Published private(set) var preferences: WeatherUnitPreferences
    @Published private(set) var manualLocation: WeatherLocation?

    private let defaults: UserDefaults
    private let session: URLSession
    private let cacheURL: URL?
    private let pollingInterval: TimeInterval
    private let now: () -> Date

    private var currentLocation: WeatherLocation?
    private var pollTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var isRefreshing = false
    private var fetchGeneration = 0

    private var locationManager: CLLocationManager?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authorizationContinuation: CheckedContinuation<Void, Error>?
    private var authorizationTimeoutTask: Task<Void, Never>?
    private var locationTimeoutTask: Task<Void, Never>?
    private var isResolvingCurrentLocation = false
    /// A permission prompt the person ignores must not leave the weather page
    /// spinning forever, so each CoreLocation await gives up after this long.
    private static let locationRequestTimeout: Duration = .seconds(15)

    init(defaults: UserDefaults = .standard,
         session: URLSession = WeatherService.makeSession(),
         cacheURL: URL? = WeatherService.defaultCacheURL,
         pollingInterval: TimeInterval = 15 * 60,
         now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.session = session
        self.cacheURL = cacheURL
        self.pollingInterval = pollingInterval
        self.now = now
        self.preferences = WeatherUnitPreferences(
            temperatureUnit: defaults.string(forKey: DefaultsKey.weatherTemperatureUnit),
            windUnit: defaults.string(forKey: DefaultsKey.weatherWindUnit),
            precipitationUnit: defaults.string(forKey: DefaultsKey.weatherPrecipitationUnit),
            pressureUnit: defaults.string(forKey: DefaultsKey.weatherPressureUnit),
            distanceUnit: defaults.string(forKey: DefaultsKey.weatherDistanceUnit)
        )
        super.init()
        loadCachedState()
    }

    nonisolated static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    nonisolated static var defaultCacheURL: URL? {
        PrivateFileStore.containerURL?
            .appendingPathComponent("Weather", isDirectory: true)
            .appendingPathComponent("weather-cache.json")
    }

    // MARK: - Lifecycle

    /// Called by `FeatureRuntime` when the feature is installed, uninstalled
    /// or the app launches. Nothing polls while the feature is off.
    func syncWithFeatures() {
        WeatherAlertsService.shared.syncWithFeatures()
        guard isFeatureActive else {
            stopPolling()
            cancelRefresh()
            return
        }
        startPolling()
        refresh()
        // A fresh cache skips the network forecast, but alerts still need a
        // fetch on launch when their switch is on.
        if let location = activeLocation {
            Task { await WeatherAlertsService.shared.refresh(location: location) }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        // Alerts belong to the forecast's place and switch, so they leave with it.
        WeatherAlertsService.shared.syncWithFeatures()
    }

    private var isFeatureActive: Bool {
        AppFeature.weather.isAvailable && defaults.bool(forKey: DefaultsKey.weatherEnabled)
    }

    private var activeLocation: WeatherLocation? {
        manualLocation ?? currentLocation
    }

    private var strings: WeatherStrings { FeatureStrings.weather(L10n.shared.language) }

    private func startPolling() {
        guard pollTimer == nil else { return }
        // A block timer takes its target weakly, so the service is never held
        // alive by the run loop merely because it started polling once.
        let timer = Timer(timeInterval: pollingInterval, repeats: true) { [weak self] _ in
            // The timer is registered on the main run loop, so this callback
            // is already on the actor the service lives on.
            MainActor.assumeIsolated { self?.pollTimerFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func pollTimerFired() {
        guard isFeatureActive else {
            stopPolling()
            return
        }
        refresh()
    }

    // MARK: - Refreshing

    /// Fetches unless the snapshot is still fresh. `force` skips that check
    /// after a location change or a manual refresh.
    func refresh(force: Bool = false) {
        guard isFeatureActive else {
            stopPolling()
            return
        }
        if isRefreshing {
            guard force else { return }
            refreshTask?.cancel()
            refreshTask = nil
            isRefreshing = false
        }
        guard let location = activeLocation else {
            state = .failed(message: strings.locationRequired)
            return
        }
        // A snapshot already marked stale (cache loaded or a failed refresh
        // after a good one) is worth fetching again even before its age says
        // so, since the state is the more precise signal.
        if !force, !state.isStale, let fetchedAt = snapshot?.fetchedAt,
           now().timeIntervalSince(fetchedAt) < pollingInterval {
            return
        }

        isRefreshing = true
        fetchGeneration += 1
        let generation = fetchGeneration
        if snapshot == nil { state = .loading }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await self.fetchSnapshot(for: location)
                self.apply(snapshot, generation: generation)
                guard generation == self.fetchGeneration else { return }
                await self.refreshAlerts(for: location)
            } catch {
                self.applyFailure(error, generation: generation)
            }
        }
    }

    /// Drops any work in flight and makes its late result arrive stale.
    private func cancelRefresh() {
        fetchGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
    }

    private func fetchSnapshot(for location: WeatherLocation) async throws -> WeatherSnapshot {
        guard let url = WeatherSupport.forecastURL(location: location) else {
            throw WeatherServiceError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        try Self.validate(response)
        let airQualityData = await fetchAirQualityData(for: location)
        return try WeatherSupport.decodeForecast(data, location: location, airQualityData: airQualityData)
    }

    /// Air quality is a separate service and an optional extra: any failure
    /// leaves the forecast intact without it.
    private func fetchAirQualityData(for location: WeatherLocation) async -> Data? {
        guard let url = WeatherSupport.airQualityURL(location: location) else { return nil }
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else { return nil }
        return data
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            throw WeatherServiceError.httpStatus(http.statusCode)
        }
    }

    /// Alerts follow a good forecast and only when their own switch is on.
    /// Their service swallows every failure, so the forecast is never affected.
    private func refreshAlerts(for location: WeatherLocation) async {
        guard defaults.bool(forKey: DefaultsKey.weatherAlertsEnabled) else { return }
        await WeatherAlertsService.shared.refresh(location: location)
    }

    private func apply(_ snapshot: WeatherSnapshot, generation: Int) {
        guard generation == fetchGeneration, isFeatureActive else { return }
        isRefreshing = false
        refreshTask = nil
        self.snapshot = snapshot
        state = .loaded(stale: false)
        persist(snapshot)
    }

    private func applyFailure(_ error: Error, generation: Int) {
        guard generation == fetchGeneration, isFeatureActive else { return }
        isRefreshing = false
        refreshTask = nil
        if snapshot != nil {
            state = .loaded(stale: true)
        } else {
            let reason = error.localizedDescription
            state = .failed(message: reason.isEmpty
                ? strings.loadFailed
                : "\(strings.loadFailed). \(reason)")
        }
    }

    // MARK: - Locations

    func searchLocations(query: String) async throws -> [WeatherLocation] {
        guard let url = WeatherSupport.geocodingURL(query: query, language: searchLanguage) else {
            return []
        }
        let (data, response) = try await session.data(from: url)
        try Self.validate(response)
        return try WeatherSupport.decodeGeocoding(data)
    }

    private var searchLanguage: String {
        String(L10n.shared.language.rawValue.split(separator: "-").first ?? "en")
    }

    func setLocation(_ location: WeatherLocation) {
        beginLocationSwitch()
        manualLocation = location
        currentLocation = nil
        defaults.set("manual", forKey: DefaultsKey.weatherLocationMode)
        store(location)
        refresh(force: true)
    }

    /// Resolves the Mac's position, names it, and switches the feature to
    /// current-location mode. The permission prompt appears here and only
    /// here.
    func useCurrentLocation() async throws {
        // A second request must not overwrite the continuations of the one
        // already waiting on CoreLocation; the first answer would be lost.
        guard !isResolvingCurrentLocation else {
            throw WeatherServiceError.locationRequestInProgress
        }
        isResolvingCurrentLocation = true
        defer { isResolvingCurrentLocation = false }

        let manager = locationManager ?? makeLocationManager()
        try await requestAuthorization(manager)
        let location = try await requestOneShotLocation(manager)
        let resolved = try await resolve(location)
        beginLocationSwitch()
        manualLocation = nil
        currentLocation = resolved
        defaults.set("current", forKey: DefaultsKey.weatherLocationMode)
        store(resolved)
        refresh(force: true)
    }

    /// Drops the previous place's reading before the new one is fetched, so
    /// the panel never shows the old city under the new name.
    private func beginLocationSwitch() {
        cancelRefresh()
        snapshot = nil
        state = .loading
    }

    func clearLocation() {
        cancelRefresh()
        manualLocation = nil
        currentLocation = nil
        snapshot = nil
        state = .idle
        defaults.set("manual", forKey: DefaultsKey.weatherLocationMode)
        for key in [DefaultsKey.weatherLocationName, DefaultsKey.weatherLatitude,
                    DefaultsKey.weatherLongitude, DefaultsKey.weatherTimezone] {
            defaults.removeObject(forKey: key)
        }
        if let cacheURL {
            try? FileManager.default.removeItem(at: cacheURL)
        }
        Task { await WeatherAlertsService.shared.refresh(location: nil) }
    }

    func setUnitPreferences(_ preferences: WeatherUnitPreferences) {
        guard preferences != self.preferences else { return }
        self.preferences = preferences
        defaults.set(preferences.temperature.rawValue, forKey: DefaultsKey.weatherTemperatureUnit)
        defaults.set(preferences.wind.rawValue, forKey: DefaultsKey.weatherWindUnit)
        defaults.set(preferences.precipitation.rawValue, forKey: DefaultsKey.weatherPrecipitationUnit)
        defaults.set(preferences.pressure.rawValue, forKey: DefaultsKey.weatherPressureUnit)
        defaults.set(preferences.distance.rawValue, forKey: DefaultsKey.weatherDistanceUnit)
    }

    // MARK: - Current location

    private func makeLocationManager() -> CLLocationManager {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager = manager
        return manager
    }

    private func requestAuthorization(_ manager: CLLocationManager) async throws {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return
        case .denied, .restricted:
            throw WeatherServiceError.locationDenied
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            try await withCheckedThrowingContinuation { continuation in
                authorizationContinuation = continuation
                authorizationTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: Self.locationRequestTimeout)
                    guard !Task.isCancelled else { return }
                    self?.finishAuthorization(.failure(WeatherServiceError.locationTimedOut))
                }
            }
        @unknown default:
            throw WeatherServiceError.locationDenied
        }
    }

    private func requestOneShotLocation(_ manager: CLLocationManager) async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
            locationTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Self.locationRequestTimeout)
                guard !Task.isCancelled else { return }
                self?.finishLocationRequest(.failure(WeatherServiceError.locationTimedOut))
            }
        }
    }

    private func resolveAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            finishAuthorization(.success(()))
        case .denied, .restricted:
            finishAuthorization(.failure(WeatherServiceError.locationDenied))
        case .notDetermined:
            break
        @unknown default:
            finishAuthorization(.failure(WeatherServiceError.locationDenied))
        }
    }

    private func finishAuthorization(_ result: Result<Void, Error>) {
        authorizationTimeoutTask?.cancel()
        authorizationTimeoutTask = nil
        guard let continuation = authorizationContinuation else { return }
        authorizationContinuation = nil
        continuation.resume(with: result)
    }

    private func finishLocationRequest(_ result: Result<CLLocation, Error>) {
        locationTimeoutTask?.cancel()
        locationTimeoutTask = nil
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(with: result)
    }

    private func resolve(_ location: CLLocation) async throws -> WeatherLocation {
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let name = placemark?.locality
            ?? placemark?.subAdministrativeArea
            ?? placemark?.administrativeArea
            ?? placemark?.name
            ?? strings.currentLocation
        return WeatherLocation(
            name: name,
            admin1: placemark?.administrativeArea,
            country: placemark?.country,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timezoneIdentifier: placemark?.timeZone?.identifier ?? TimeZone.current.identifier
        )
    }

    // MARK: - Persistence

    private func loadCachedState() {
        readStoredLocation()
        guard let cacheURL,
              let data = try? Data(contentsOf: cacheURL),
              let cached = try? WeatherSupport.decodeCache(data)
        else { return }
        if let activeLocation, !WeatherSupport.isSamePlace(cached.location, activeLocation) {
            return
        }
        snapshot = cached
        state = .loaded(stale: now().timeIntervalSince(cached.fetchedAt) >= pollingInterval)
        if activeLocation == nil { manualLocation = cached.location }
    }

    private func readStoredLocation() {
        let name = defaults.string(forKey: DefaultsKey.weatherLocationName) ?? ""
        let timezone = defaults.string(forKey: DefaultsKey.weatherTimezone) ?? ""
        guard !name.isEmpty, !timezone.isEmpty else { return }
        let location = WeatherLocation(
            name: name,
            admin1: nil,
            country: nil,
            latitude: defaults.double(forKey: DefaultsKey.weatherLatitude),
            longitude: defaults.double(forKey: DefaultsKey.weatherLongitude),
            timezoneIdentifier: timezone
        )
        if defaults.string(forKey: DefaultsKey.weatherLocationMode) == "current" {
            currentLocation = location
        } else {
            manualLocation = location
        }
    }

    private func store(_ location: WeatherLocation) {
        defaults.set(location.name, forKey: DefaultsKey.weatherLocationName)
        defaults.set(location.latitude, forKey: DefaultsKey.weatherLatitude)
        defaults.set(location.longitude, forKey: DefaultsKey.weatherLongitude)
        defaults.set(location.timezoneIdentifier, forKey: DefaultsKey.weatherTimezone)
    }

    private func persist(_ snapshot: WeatherSnapshot) {
        guard let cacheURL,
              let data = try? WeatherSupport.encodeCache(snapshot),
              PrivateFileStore.createDirectory(at: cacheURL.deletingLastPathComponent())
        else { return }
        PrivateFileStore.write(data, to: cacheURL)
    }
}

// MARK: - CLLocationManagerDelegate

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            resolveAuthorization(manager.authorizationStatus)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated {
            finishLocationRequest(.success(location))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            finishLocationRequest(.failure(error))
        }
    }
}

enum WeatherServiceError: Error, LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case locationDenied
    case locationTimedOut
    case locationRequestInProgress

    var errorDescription: String? {
        let strings = FeatureStrings.weather(L10n.shared.language)
        switch self {
        // The status number is for logs, not the person; the generic line
        // says what happened and the panel offers a retry.
        case .invalidURL, .httpStatus: return strings.loadFailed
        case .locationDenied: return strings.locationDenied
        case .locationTimedOut: return strings.locationTimedOut
        case .locationRequestInProgress: return strings.locationInProgress
        }
    }
}
