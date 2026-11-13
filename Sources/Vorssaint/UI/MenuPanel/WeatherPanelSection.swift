// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The "Weather" card: current conditions, the next day, a small graph and the
/// week ahead. It renders whatever `WeatherService` already has, so the panel
/// opens instantly from the cached forecast and fills in when a refresh lands.
struct WeatherPanelSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var weather = WeatherService.shared
    @ObservedObject private var alerts = WeatherAlertsService.shared
    @AppStorage(DefaultsKey.weatherAlertsEnabled) private var alertsEnabled = false
    @State private var radarLocation: WeatherLocation?
    var collapsible = true

    private var strings: WeatherStrings { FeatureStrings.weather(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }

    var body: some View {
        PanelSection(.weather, title: strings.sectionTitle, collapsible: collapsible) {
            Group {
                if let snapshot = weather.snapshot {
                    loaded(snapshot)
                } else if weather.state.isLoading {
                    loading
                } else if case .failed(let message) = weather.state,
                          message != strings.locationRequired {
                    failure(message)
                } else {
                    noLocation
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelCard()
        }
        .sheet(item: $radarLocation) { location in
            WeatherRadarSheet(location: location)
        }
    }

    // MARK: States

    private var loading: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(strings.loading)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(height: 30)
    }

    private var noLocation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(strings.noLocationTitle, systemImage: "mappin.and.ellipse")
                .font(.system(size: 11, weight: .semibold))
            Text(strings.locationRequired)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: openWeatherSettings) {
                Label(strings.searchLocation, systemImage: "gearshape")
                    .font(.system(size: 10.5))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(strings.loadFailed, systemImage: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .semibold))
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Button(strings.retry) {
                weather.refresh(force: true)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func openWeatherSettings() {
        SettingsRouter.shared.request(AppFeature.weather.settingsDestination,
                                      targetFeature: .weather)
        appDelegate()?.openSettingsWindow()
    }

    // MARK: Loaded

    private func loaded(_ snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            hero(snapshot)
            alertsSection
            Divider()
            hourly(snapshot)
            Divider()
            graphs(snapshot)
            Divider()
            radarCard(snapshot.location)
            Divider()
            details(snapshot)
            Divider()
            daily(snapshot)
            attribution
        }
    }

    /// Only the highest-severity alert gets the banner; the next three stay as
    /// compact lines so the rest of the card keeps its room.
    @ViewBuilder
    private var alertsSection: some View {
        if alertsEnabled, let first = alerts.alerts.first {
            VStack(alignment: .leading, spacing: 4) {
                WeatherAlertBanner(alert: first, strings: strings, locale: locale)
                ForEach(Array(alerts.alerts.dropFirst().prefix(3))) { alert in
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(alert.severity.tint)
                            .accessibilityHidden(true)
                        Text(alert.event)
                            .font(.system(size: 9.5, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let expiry = alert.expires ?? alert.ends {
                            Text(expiryLine(expiry))
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private func expiryLine(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return String(format: strings.alertsExpiresFormat, formatter.string(from: date))
    }

    private func hero(_ snapshot: WeatherSnapshot) -> some View {
        let current = snapshot.current
        let preferences = weather.preferences
        let today = snapshot.daily.first
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: current.condition.symbolName(isDay: current.isDay))
                    .font(.system(size: 28, weight: .medium))
                    .symbolRenderingMode(.multicolor)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(preferences.formattedTemperature(current.temperature))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        if let today {
                            Text("\(preferences.formattedTemperature(today.temperatureMax)) / \(preferences.formattedTemperature(today.temperatureMin))")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(strings.name(for: current.condition))
                        .font(.system(size: 11.5, weight: .medium))
                    Text(locationLine(snapshot))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    weather.refresh(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(strings.refresh)
                .accessibilityLabel(strings.refresh)
            }
            HStack(spacing: 6) {
                Text("\(strings.feelsLike) \(preferences.formattedTemperature(current.apparentTemperature))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if weather.state.isStale {
                    Text(strings.staleNotice)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func locationLine(_ snapshot: WeatherSnapshot) -> String {
        [snapshot.location.name, snapshot.location.detail ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func hourly(_ snapshot: WeatherSnapshot) -> some View {
        let preferences = weather.preferences
        let hours = upcomingHours(snapshot)
        return VStack(alignment: .leading, spacing: 6) {
            subsectionLabel(strings.hourlyTitle)
            if hours.isEmpty {
                Text("—")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(hours, id: \.time) { hour in
                            VStack(spacing: 3) {
                                Text(hourLabel(hour.time, in: snapshot))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Image(systemName: hour.condition.symbolName(isDay: hour.isDay))
                                    .font(.system(size: 13))
                                    .symbolRenderingMode(.multicolor)
                                    .frame(height: 16)
                                Text(preferences.formattedTemperature(hour.temperature))
                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                Text("\(hour.precipitationProbability)%")
                                    .font(.system(size: 8.5))
                                    .monospacedDigit()
                                    .foregroundStyle(hour.precipitationProbability > 0
                                                     ? Color.accentColor : Color.secondary.opacity(0.7))
                            }
                            .frame(width: 34)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func graphs(_ snapshot: WeatherSnapshot) -> some View {
        let hours = upcomingHours(snapshot)
        return VStack(alignment: .leading, spacing: 6) {
            subsectionLabel(strings.graphsTitle)
            if hours.count >= 2 {
                WeatherGraphView(hours: hours,
                                 preferences: weather.preferences,
                                 timeZoneIdentifier: snapshot.timezoneIdentifier,
                                 locale: locale,
                                 temperatureTitle: l10n.s.temperatures,
                                 precipitationTitle: strings.precipitationLabel,
                                 windTitle: strings.windLabel)
            } else {
                Text("—")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// One compact row; the sheet itself is where the map lives.
    private func radarCard(_ location: WeatherLocation) -> some View {
        Button {
            radarLocation = location
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(strings.radarTitle)
                    .font(.system(size: 10.5, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func details(_ snapshot: WeatherSnapshot) -> some View {
        let preferences = weather.preferences
        let current = snapshot.current
        let hour = currentHour(snapshot)
        var items: [DetailItem] = [
            DetailItem(label: strings.precipitationLabel,
                       value: "\(hour?.precipitationProbability ?? 0)% · \(preferences.formattedPrecipitation(current.precipitation))",
                       symbol: "drop.fill"),
            DetailItem(label: "\(strings.windLabel) · \(strings.gustsLabel)",
                       value: windLine(snapshot),
                       symbol: "wind"),
            DetailItem(label: strings.humidity,
                       value: "\(current.relativeHumidity)%",
                       symbol: "humidity.fill"),
            DetailItem(label: strings.uvIndexLabel,
                       value: current.uvIndex.map { number($0, digits: 1) } ?? "—",
                       symbol: "sun.max.fill"),
            DetailItem(label: strings.pressureLabel,
                       value: current.pressureMSL.map { preferences.formattedPressure($0) } ?? "—",
                       symbol: "gauge.with.dots.needle.50percent"),
        ]
        if let visibility = hour?.visibility {
            items.append(DetailItem(label: strings.visibilityLabel,
                                    value: preferences.formattedVisibility(visibility),
                                    symbol: "eye"))
        }
        if let aqi = snapshot.airQuality?.usAQI {
            items.append(DetailItem(label: strings.airQualityLabel,
                                    value: "\(aqi) AQI",
                                    symbol: "aqi.medium"))
        }
        if let cloudCover = current.cloudCover {
            items.append(DetailItem(label: strings.cloudCoverLabel,
                                    value: "\(cloudCover)%",
                                    symbol: "cloud.fill"))
        }
        if let sun = sunLine(snapshot) {
            items.append(DetailItem(label: "\(strings.sunriseLabel) / \(strings.sunsetLabel)",
                                    value: sun,
                                    symbol: "sunrise.fill"))
        }
        return VStack(alignment: .leading, spacing: 6) {
            subsectionLabel(strings.detailsTitle)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6),
                                GridItem(.flexible())], spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    detailCell(item)
                }
            }
        }
    }

    private func detailCell(_ item: DetailItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: item.symbol)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
                Text(item.label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(item.value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private func daily(_ snapshot: WeatherSnapshot) -> some View {
        let preferences = weather.preferences
        let days = Array(snapshot.daily.prefix(7))
        let scaleLow = days.map(\.temperatureMin).min() ?? 0
        let scaleHigh = days.map(\.temperatureMax).max() ?? 1
        return VStack(alignment: .leading, spacing: 5) {
            subsectionLabel(strings.dailyTitle)
            ForEach(days.indices, id: \.self) { index in
                let day = days[index]
                HStack(spacing: 6) {
                    Text(dayLabel(day.date, index: index, in: snapshot))
                        .font(.system(size: 10, weight: index == 0 ? .semibold : .medium))
                        .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 30, alignment: .leading)
                    Image(systemName: day.condition.symbolName(isDay: true))
                        .font(.system(size: 11))
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 16)
                    Text("\(day.precipitationProbabilityMax)%")
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                    WeatherTemperatureRangeBar(low: day.temperatureMin,
                                               high: day.temperatureMax,
                                               scaleLow: scaleLow,
                                               scaleHigh: scaleHigh)
                        .frame(height: 4)
                    Text(preferences.formattedTemperature(day.temperatureMin))
                        .font(.system(size: 10, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .trailing)
                    Text(preferences.formattedTemperature(day.temperatureMax))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
    }

    private var attribution: some View {
        HStack(spacing: 4) {
            Text(strings.dataSourceTitle)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Link(strings.attribution, destination: URL(string: "https://open-meteo.com/")!)
                .font(.system(size: 9))
        }
    }

    // MARK: Formatting

    private func subsectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func upcomingHours(_ snapshot: WeatherSnapshot) -> [WeatherHour] {
        let start = snapshot.hourly.firstIndex { $0.time >= snapshot.current.time }
            ?? snapshot.hourly.startIndex
        let hours = Array(snapshot.hourly.dropFirst(start).prefix(24))
        return hours.isEmpty ? Array(snapshot.hourly.prefix(24)) : hours
    }

    private func currentHour(_ snapshot: WeatherSnapshot) -> WeatherHour? {
        snapshot.hourly.first { $0.time >= snapshot.current.time } ?? snapshot.hourly.last
    }

    private func windLine(_ snapshot: WeatherSnapshot) -> String {
        let preferences = weather.preferences
        let wind = preferences.formattedWind(snapshot.current.windSpeed)
        guard let gust = snapshot.current.windGust else { return wind }
        return "\(wind) · \(preferences.formattedWind(gust))"
    }

    private func sunLine(_ snapshot: WeatherSnapshot) -> String? {
        guard let today = snapshot.daily.first else { return nil }
        let sunrise = today.sunrise.map { timeLabel($0, template: "j:mm", in: snapshot) }
        let sunset = today.sunset.map { timeLabel($0, template: "j:mm", in: snapshot) }
        switch (sunrise, sunset) {
        case let (rise?, set?): return "\(rise) · \(set)"
        case let (rise?, nil): return rise
        case let (nil, set?): return set
        case (nil, nil): return nil
        }
    }

    private func hourLabel(_ date: Date, in snapshot: WeatherSnapshot) -> String {
        // "Now" only names the clock hour the reading belongs to; a forecast
        // whose first slot is still ahead keeps its real hour.
        if WeatherSupport.isCurrentHour(date, now: snapshot.current.time,
                                        timeZoneIdentifier: snapshot.timezoneIdentifier) {
            return strings.nowLabel
        }
        return timeLabel(date, template: "j", in: snapshot)
    }

    private func dayLabel(_ date: Date, index: Int, in snapshot: WeatherSnapshot) -> String {
        index == 0 ? strings.todayLabel : timeLabel(date, template: "EEE", in: snapshot)
    }

    /// Times are absolute; they must read in the forecast's own zone, not the
    /// Mac's, so a place on the other side of the world still shows its clock.
    private func timeLabel(_ date: Date, template: String, in snapshot: WeatherSnapshot) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: snapshot.timezoneIdentifier) ?? .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private func number(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", locale: MetricFormat.locale, value)
    }

    private struct DetailItem {
        let label: String
        let value: String
        let symbol: String
    }
}

/// The daily high/low bar, positioned on the week's shared range so the days
/// compare to each other at a glance.
private struct WeatherTemperatureRangeBar: View {
    let low: Double
    let high: Double
    let scaleLow: Double
    let scaleHigh: Double

    var body: some View {
        GeometryReader { proxy in
            let span = max(scaleHigh - scaleLow, 0.1)
            let start = min(max((low - scaleLow) / span, 0), 1)
            let end = min(max((high - scaleLow) / span, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(colors: [.cyan.opacity(0.55), .orange.opacity(0.7)],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )
                    .frame(width: max(4, proxy.size.width * (end - start)))
                    .offset(x: proxy.size.width * start)
            }
        }
    }
}
