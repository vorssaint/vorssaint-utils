// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The forecast on the island: a compact reading, the next day of hours and
/// the details. The page scrolls inside a short island, as the lists do.
struct WeatherNotchView: View {
    let size: CGSize
    @ObservedObject private var weather = WeatherService.shared
    @ObservedObject private var alerts = WeatherAlertsService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.weatherAlertsEnabled) private var alertsEnabled = false
    @AppStorage(DefaultsKey.weatherNotchHourly) private var showHourly = true
    @AppStorage(DefaultsKey.weatherNotchGraphs) private var showGraphs = true
    @AppStorage(DefaultsKey.weatherNotchDetails) private var showDetails = true
    @Environment(\.notchSettingsPreview) private var preview
    @State private var resolvingLocation = false
    @State private var locationError: String?

    private var text: WeatherStrings { FeatureStrings.weather(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }

    var body: some View {
        Group {
            if let snapshot = weather.snapshot {
                loaded(snapshot)
            } else if weather.state.isLoading || resolvingLocation {
                NotchEmptyView(symbol: "cloud.sun.fill", message: text.loading) {
                    ProgressView().controlSize(.small)
                }
            } else if case .failed = weather.state {
                failure
            } else {
                locationPrompt
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.locale, locale)
        .notchBand(trailing: { refreshControl })
    }

    // MARK: - States

    private var refreshControl: some View {
        Group {
            if !preview {
                NotchIconButton(symbol: "arrow.clockwise", title: text.refresh) { refresh() }
                    .disabled(weather.state.isLoading || resolvingLocation)
            }
        }
    }

    private var locationPrompt: some View {
        NotchEmptyView(symbol: "cloud.sun.fill", message: promptMessage) {
            if !preview {
                NotchPillButton(title: text.useCurrentLocation, prominent: true, action: useCurrentLocation)
            }
        }
    }

    private var failure: some View {
        NotchEmptyView(symbol: "exclamationmark.triangle", message: promptMessage) {
            if !preview {
                HStack(spacing: 8) {
                    if weather.manualLocation != nil {
                        NotchPillButton(title: text.retry, prominent: true) {
                            weather.refresh(force: true)
                        }
                    } else {
                        NotchPillButton(title: text.useCurrentLocation, prominent: true, action: useCurrentLocation)
                    }
                }
            }
        }
    }

    /// The state's own message, and why the location could not be found.
    private var promptMessage: String {
        var parts: [String] = []
        if case .failed(let message) = weather.state {
            parts.append(message)
        } else {
            parts.append(text.locationRequired)
        }
        if let locationError { parts.append(locationError) }
        return parts.joined(separator: "\n")
    }

    private func refresh() {
        locationError = nil
        weather.refresh(force: true)
    }

    private func useCurrentLocation() {
        guard !resolvingLocation else { return }
        resolvingLocation = true
        locationError = nil
        Task { @MainActor in
            do {
                try await weather.useCurrentLocation()
            } catch {
                locationError = error.localizedDescription
            }
            resolvingLocation = false
        }
    }

    // MARK: - Loaded

    private func loaded(_ snapshot: WeatherSnapshot) -> some View {
        let hourly = Array(snapshot.hourly.filter { $0.time >= snapshot.current.time }.prefix(24))
        let hourFormatter = formatter(snapshot.timezoneIdentifier, "j")
        let clockFormatter = formatter(snapshot.timezoneIdentifier, "jm")
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if weather.state.isStale { staleNotice }
                hero(snapshot)
                if alertsEnabled, let alert = alerts.alerts.first {
                    WeatherAlertBanner(alert: alert, strings: text, locale: locale, compact: true)
                }
                if showHourly, !hourly.isEmpty {
                    hourlyStrip(hourly, formatter: hourFormatter,
                                timeZoneIdentifier: snapshot.timezoneIdentifier,
                                now: snapshot.current.time)
                }
                if showGraphs, hourly.count >= 2 {
                    graphs(hourly, snapshot: snapshot)
                }
                if showDetails {
                    details(snapshot, formatter: clockFormatter)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .scrollIndicators(.automatic)
    }

    private var staleNotice: some View {
        Label(text.staleNotice, systemImage: "clock.arrow.circlepath")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.orange.opacity(0.9))
            .lineLimit(1)
            .accessibilityElement(children: .combine)
    }

    private func hero(_ snapshot: WeatherSnapshot) -> some View {
        let current = snapshot.current
        let today = snapshot.daily.first
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: current.condition.symbolName(isDay: current.isDay))
                .font(.system(size: 38, weight: .light))
                .frame(width: 46)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(temperature(current.temperature))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(text.name(for: current.condition))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(currentLocationLine(snapshot))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(text.feelsLike) \(temperature(current.apparentTemperature))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                if let today {
                    HStack(spacing: 5) {
                        Text("\(text.highLabel) \(temperature(today.temperatureMax))")
                        Text("\(text.lowLabel) \(temperature(today.temperatureMin))")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func currentLocationLine(_ snapshot: WeatherSnapshot) -> String {
        [snapshot.location.name, snapshot.location.detail].compactMap { $0 }.joined(separator: ", ")
    }

    private func hourlyStrip(_ hours: [WeatherHour], formatter: DateFormatter,
                             timeZoneIdentifier: String, now: Date) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(hours, id: \.time) { hour in
                    hourCell(hour, label: WeatherSupport.isCurrentHour(hour.time, now: now,
                                                                      timeZoneIdentifier: timeZoneIdentifier)
                             ? text.nowLabel : formatter.string(from: hour.time))
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel(text.hourlyTitle)
    }

    private func hourCell(_ hour: WeatherHour, label: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: hour.condition.symbolName(isDay: hour.isDay))
                .font(.system(size: 14))
            Text(temperature(hour.temperature))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("\(hour.precipitationProbability)%")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(hour.precipitationProbability > 0 ? Color.cyan : Color.white.opacity(0.55))
                .monospacedDigit()
        }
        .frame(width: 46, height: 64)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func graphs(_ hours: [WeatherHour], snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text.graphsTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            WeatherGraphView(hours: hours,
                             preferences: weather.preferences,
                             timeZoneIdentifier: snapshot.timezoneIdentifier,
                             locale: locale,
                             temperatureTitle: l10n.s.temperatures,
                             precipitationTitle: text.precipitationLabel,
                             windTitle: text.windLabel)
        }
        .padding(9)
        .modifier(NotchControlSurface(cornerRadius: 12, interactive: false))
    }

    private func details(_ snapshot: WeatherSnapshot, formatter: DateFormatter) -> some View {
        let current = snapshot.current
        let today = snapshot.daily.first
        let nextHour = snapshot.hourly.first { $0.time >= current.time }
        let airQuality = snapshot.airQuality?.usAQI
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], spacing: 8) {
            detailCard(symbol: "drop.fill", title: text.precipitationLabel,
                       value: weather.preferences.formattedPrecipitation(current.precipitation, locale: locale),
                       detail: nextHour.map { "\($0.precipitationProbability)%" })
            detailCard(symbol: "wind", title: text.windLabel,
                       value: weather.preferences.formattedWind(current.windSpeed, locale: locale),
                       detail: current.windGust.map { "\(text.gustsLabel) \(weather.preferences.formattedWind($0, locale: locale))" })
            detailCard(symbol: "humidity.fill", title: text.humidity,
                       value: "\(current.relativeHumidity)%", detail: nil)
            if let visibility = nextHour?.visibility {
                detailCard(symbol: "eye", title: text.visibilityLabel,
                           value: weather.preferences.formattedVisibility(visibility, locale: locale),
                           detail: nil)
            }
            detailCard(symbol: "sun.max.fill", title: text.uvIndexLabel,
                       value: current.uvIndex.map { decimal($0, digits: 1) } ?? "–",
                       detail: airQuality.map { "\(text.airQualityLabel) \($0)" })
            detailCard(symbol: "sunrise.fill", title: text.sunriseLabel,
                       value: today?.sunrise.map { formatter.string(from: $0) } ?? "–",
                       detail: today?.sunset.map { "\(text.sunsetLabel) \(formatter.string(from: $0))" })
        }
    }

    private func detailCard(symbol: String, title: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .modifier(NotchControlSurface(cornerRadius: 12, interactive: false))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Formatting

    private func temperature(_ celsius: Double) -> String {
        weather.preferences.formattedTemperature(celsius, locale: locale)
    }

    private func decimal(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", locale: locale, value)
    }

    private func formatter(_ timezone: String, _ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
