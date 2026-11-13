// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Weather settings page: switch the feature on, pick the place it
/// reports, its units and where the reading appears. The forecast itself
/// lives in the panel and the menu bar, so this page only chooses the place
/// and the format.
struct WeatherSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var weather = WeatherService.shared

    @AppStorage(DefaultsKey.weatherEnabled) private var enabled = true
    @AppStorage(DefaultsKey.weatherLocationMode) private var locationMode = "manual"
    @AppStorage(DefaultsKey.menuBarWeather) private var showInMenuBar = false
    @AppStorage(DefaultsKey.weatherMenuBarStyle) private var menuBarStyle =
        WeatherMenuBarStyle.symbolTemperature.rawValue
    @AppStorage(DefaultsKey.panelShowWeather) private var showInPanel = true

    @State private var query = ""
    @State private var results: [WeatherLocation] = []
    @State private var search: SearchState = .idle
    @State private var isLocating = false
    @State private var locationError: String?

    private var strings: WeatherStrings { FeatureStrings.weather(l10n.language) }

    private enum SearchState: Equatable {
        case idle, searching, empty, results
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                enableCard
                locationCard
                unitsCard
                menuBarCard
                panelCard
                dataCard
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .toggleStyle(.switch)
        .task(id: query) {
            await searchAfterTyping()
        }
    }

    // MARK: - Cards

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(strings.title)
                .font(.title2.bold())
            Text(strings.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var enableCard: some View {
        SettingsCard {
            SettingsFeatureSwitchRow(symbol: "cloud.sun.fill", title: strings.title,
                                     isOn: $enabled, feature: .weather)
                .onChange(of: enabled) { _, _ in
                    weather.syncWithFeatures()
                }
        }
    }

    private var locationCard: some View {
        SettingsCard(title: strings.location) {
            currentLocationRow
            Divider()
            TextField(strings.searchLocation, text: $query,
                      prompt: Text(strings.searchPrompt))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(strings.searchLocation)
            searchResults
            Divider()
            HStack(spacing: 10) {
                Button(strings.useCurrentLocation) {
                    locate()
                }
                .disabled(isLocating)
                if isLocating {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
            }
            if let locationError {
                Text(locationError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var currentLocationRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(place?.name ?? strings.noLocationTitle)
                if let detail = place?.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if place == nil {
                    Text(strings.locationRequired)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            if place != nil {
                if locationMode == "current" {
                    Text(strings.currentLocation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(l10n.s.actionRemove) {
                    weather.clearLocation()
                    locationError = nil
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        switch search {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(strings.loading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .empty:
            Text(strings.searchNoResults)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .results:
            VStack(spacing: 0) {
                ForEach(results) { location in
                    Button {
                        choose(location)
                    } label: {
                        resultRow(location)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel(for: location))
                    if location.id != results.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func resultRow(_ location: WeatherLocation) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(location.name)
                if let detail = location.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    /// Duplicate city names are common; the region and country make each
    /// search result distinguishable to a screen reader.
    private func accessibilityLabel(for location: WeatherLocation) -> String {
        [location.name, location.detail].compactMap { $0 }.joined(separator: ", ")
    }

    private var unitsCard: some View {
        SettingsCard(title: strings.unitsTitle) {
            SettingsChoiceRow(symbol: "thermometer.medium", title: l10n.s.temperatures,
                              selection: unitBinding(\.temperature)) {
                Text(strings.temperatureCelsius)
                    .tag(WeatherUnitPreferences.TemperatureUnit.celsius)
                Text(strings.temperatureFahrenheit)
                    .tag(WeatherUnitPreferences.TemperatureUnit.fahrenheit)
            }
            SettingsMenuRow(symbol: "wind", title: strings.windLabel,
                            selection: unitBinding(\.wind)) {
                ForEach(WeatherUnitPreferences.WindUnit.allCases, id: \.self) { unit in
                    Text(windName(unit)).tag(unit)
                }
            }
            SettingsMenuRow(symbol: "cloud.rain", title: strings.precipitationLabel,
                            selection: unitBinding(\.precipitation)) {
                ForEach(WeatherUnitPreferences.PrecipitationUnit.allCases, id: \.self) { unit in
                    Text(precipitationName(unit)).tag(unit)
                }
            }
            SettingsMenuRow(symbol: "gauge.with.dots.needle.50percent", title: strings.pressureLabel,
                            selection: unitBinding(\.pressure)) {
                ForEach(WeatherUnitPreferences.PressureUnit.allCases, id: \.self) { unit in
                    Text(pressureName(unit)).tag(unit)
                }
            }
            SettingsMenuRow(symbol: "eye", title: strings.visibilityLabel,
                            selection: unitBinding(\.distance)) {
                ForEach(WeatherUnitPreferences.DistanceUnit.allCases, id: \.self) { unit in
                    Text(distanceName(unit)).tag(unit)
                }
            }
        }
    }

    private var menuBarCard: some View {
        SettingsCard {
            SettingsRow(symbol: "menubar.rectangle", title: strings.showInMenuBar) {
                Toggle(strings.showInMenuBar, isOn: $showInMenuBar)
                    .labelsHidden()
            }
            SettingsMenuRow(symbol: "cloud.sun", title: strings.menuBarStyle,
                            selection: menuBarStyleBinding) {
                ForEach(WeatherMenuBarStyle.allCases, id: \.self) { style in
                    Text(strings.menuBarStyle(style)).tag(style)
                }
            }
            .disabled(!showInMenuBar)
            .opacity(showInMenuBar ? 1 : 0.45)
        }
    }

    private var panelCard: some View {
        SettingsCard {
            SettingsRow(symbol: "macwindow", title: strings.showInPanel) {
                Toggle(strings.showInPanel, isOn: $showInPanel)
                    .labelsHidden()
            }
        }
    }

    private var dataCard: some View {
        SettingsCard(title: strings.dataSourceTitle) {
            SettingsRow(symbol: "timer", title: l10n.s.monitorIntervalLabel) {
                Text(strings.refreshInterval)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let snapshot = weather.snapshot {
                Text(String(format: strings.updatedAtFormat,
                            snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if case .failed(let message) = weather.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Link(strings.attribution, destination: URL(string: "https://open-meteo.com/")!)
                .font(.callout)
            HStack(spacing: 10) {
                Button(strings.refresh) {
                    weather.refresh(force: true)
                }
                .disabled(weather.state.isLoading)
                if weather.state.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
            }
        }
    }

    // MARK: - State

    private var place: WeatherLocation? {
        weather.manualLocation ?? weather.snapshot?.location
    }

    private var menuBarStyleBinding: Binding<WeatherMenuBarStyle> {
        Binding(
            get: { WeatherMenuBarStyle.sanitized(menuBarStyle) },
            set: { menuBarStyle = $0.rawValue })
    }

    private func unitBinding<Value>(
        _ keyPath: WritableKeyPath<WeatherUnitPreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { weather.preferences[keyPath: keyPath] },
            set: { value in
                var preferences = weather.preferences
                preferences[keyPath: keyPath] = value
                weather.setUnitPreferences(preferences)
            })
    }

    private func windName(_ unit: WeatherUnitPreferences.WindUnit) -> String {
        switch unit {
        case .kilometersPerHour: return strings.windKph
        case .milesPerHour: return strings.windMph
        case .metersPerSecond: return strings.windMps
        case .knots: return strings.windKnots
        }
    }

    private func precipitationName(_ unit: WeatherUnitPreferences.PrecipitationUnit) -> String {
        switch unit {
        case .millimeters: return strings.precipitationMillimeters
        case .inches: return strings.precipitationInches
        }
    }

    private func pressureName(_ unit: WeatherUnitPreferences.PressureUnit) -> String {
        switch unit {
        case .hectopascals: return strings.pressureHectopascals
        case .inchesOfMercury: return strings.pressureInchesOfMercury
        }
    }

    private func distanceName(_ unit: WeatherUnitPreferences.DistanceUnit) -> String {
        switch unit {
        case .kilometers: return strings.distanceKilometers
        case .miles: return strings.distanceMiles
        }
    }

    private func choose(_ location: WeatherLocation) {
        weather.setLocation(location)
        query = ""
        results = []
        search = .idle
        locationError = nil
    }

    private func locate() {
        isLocating = true
        locationError = nil
        Task {
            do {
                try await weather.useCurrentLocation()
            } catch {
                locationError = error.localizedDescription
            }
            isLocating = false
        }
    }

    /// Debounced so typing a city makes one request, not one per keystroke.
    private func searchAfterTyping() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            results = []
            search = .idle
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(350))
        } catch {
            return
        }
        search = .searching
        do {
            let found = try await weather.searchLocations(query: text)
            guard !Task.isCancelled else { return }
            results = found
            search = found.isEmpty ? .empty : .results
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            search = .failed(error.localizedDescription)
        }
    }
}
