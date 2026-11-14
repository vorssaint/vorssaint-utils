// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The public Open-Meteo endpoints, request fields and decoding the weather
/// service uses. Everything here is pure Foundation so tests can feed recorded
/// JSON without a network or a timer.
enum WeatherSupport {
    // MARK: Endpoints

    static let forecastBaseURL = "https://api.open-meteo.com/v1/forecast"
    static let airQualityBaseURL = "https://air-quality-api.open-meteo.com/v1/air-quality"
    static let geocodingBaseURL = "https://geocoding-api.open-meteo.com/v1/search"

    /// Canonical units the models always keep. The person's units are applied
    /// only when a value is formatted.
    static let requestTemperatureUnit = "celsius"
    static let requestWindSpeedUnit = "kmh"
    static let requestPrecipitationUnit = "mm"
    static let requestForecastDays = 7
    static let requestGeocodingCount = 8

    static let currentFields = [
        "temperature_2m", "relative_humidity_2m", "apparent_temperature", "is_day",
        "precipitation", "weather_code", "cloud_cover", "pressure_msl",
        "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m", "uv_index",
    ]

    static let minutelyFields = ["precipitation", "precipitation_probability"]

    static let hourlyFields = [
        "temperature_2m", "apparent_temperature", "precipitation_probability",
        "precipitation", "weather_code", "wind_speed_10m", "is_day", "uv_index",
        "visibility",
    ]

    static let dailyFields = [
        "weather_code", "temperature_2m_max", "temperature_2m_min",
        "precipitation_probability_max", "precipitation_sum",
        "sunrise", "sunset", "uv_index_max", "wind_speed_10m_max",
    ]

    static let airQualityFields = ["us_aqi", "european_aqi", "pm2_5", "pm10", "ozone"]

    // MARK: Feature gate

    /// The menu bar block is a Weather surface like the panel and the island:
    /// the hub install alone is not enough, the feature must be switched on.
    static func isMenuBarWeatherEnabled(in defaults: UserDefaults) -> Bool {
        AppFeature.weather.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.weatherEnabled)
    }

    // MARK: URLs

    static func forecastURL(location: WeatherLocation,
                            forecastDays: Int = requestForecastDays) -> URL? {
        url(base: forecastBaseURL, items: [
            ("latitude", coordinate(location.latitude)),
            ("longitude", coordinate(location.longitude)),
            ("current", currentFields.joined(separator: ",")),
            ("minutely_15", minutelyFields.joined(separator: ",")),
            ("hourly", hourlyFields.joined(separator: ",")),
            ("daily", dailyFields.joined(separator: ",")),
            ("timezone", "auto"),
            ("forecast_days", String(forecastDays)),
            ("temperature_unit", requestTemperatureUnit),
            ("wind_speed_unit", requestWindSpeedUnit),
            ("precipitation_unit", requestPrecipitationUnit),
            ("timeformat", "iso8601"),
        ])
    }

    static func airQualityURL(location: WeatherLocation) -> URL? {
        url(base: airQualityBaseURL, items: [
            ("latitude", coordinate(location.latitude)),
            ("longitude", coordinate(location.longitude)),
            ("current", airQualityFields.joined(separator: ",")),
            ("timezone", "auto"),
            ("timeformat", "iso8601"),
        ])
    }

    static func geocodingURL(query: String,
                             count: Int = requestGeocodingCount,
                             language: String = "en") -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return url(base: geocodingBaseURL, items: [
            ("name", trimmed),
            ("count", String(count)),
            ("language", language),
            ("format", "json"),
        ])
    }

    private static func url(base: String, items: [(String, String)]) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.url
    }

    private static func coordinate(_ value: Double) -> String {
        // A URL is a wire format, not on-screen text: its point decimal must
        // never follow a region's comma.
        String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    // MARK: Forecast decoding

    /// Decodes a forecast response. A failed or malformed air-quality reply is
    /// discarded rather than thrown, so weather still loads without it.
    static func decodeForecast(_ data: Data,
                               location: WeatherLocation,
                               fetchedAt: Date = Date(),
                               airQualityData: Data? = nil) throws -> WeatherSnapshot {
        guard let root = jsonObject(data) else { throw WeatherSupportError.invalidJSON }
        guard let currentObject = root["current"] as? [String: Any] else {
            throw WeatherSupportError.missingCurrentConditions
        }

        let offset = integer(root["utc_offset_seconds"]) ?? 0
        let timezone = string(root["timezone"]).flatMap { $0.isEmpty ? nil : $0 }
            ?? location.timezoneIdentifier

        func time(_ value: Any?) -> Date? {
            string(value).flatMap { parseTime($0, utcOffsetSeconds: offset) }
        }

        let current = WeatherCurrent(
            time: time(currentObject["time"]) ?? fetchedAt,
            temperature: double(currentObject["temperature_2m"]) ?? 0,
            apparentTemperature: double(currentObject["apparent_temperature"])
                ?? double(currentObject["temperature_2m"]) ?? 0,
            relativeHumidity: integer(currentObject["relative_humidity_2m"]) ?? 0,
            precipitation: double(currentObject["precipitation"]) ?? 0,
            weatherCode: integer(currentObject["weather_code"]) ?? 0,
            cloudCover: integer(currentObject["cloud_cover"]),
            pressureMSL: double(currentObject["pressure_msl"]),
            windSpeed: double(currentObject["wind_speed_10m"]) ?? 0,
            windDirection: integer(currentObject["wind_direction_10m"]) ?? 0,
            windGust: double(currentObject["wind_gusts_10m"]),
            uvIndex: double(currentObject["uv_index"]),
            isDay: integer(currentObject["is_day"]) != 0
        )

        let minutely = decodeMinutely(root["minutely_15"], offset: offset)
        let hourly = decodeHourly(root["hourly"], offset: offset)
        let daily = decodeDaily(root["daily"], offset: offset)
        let airQuality = airQualityData.flatMap { try? decodeAirQuality($0) }

        return WeatherSnapshot(
            location: location,
            fetchedAt: fetchedAt,
            timezoneIdentifier: timezone,
            current: current,
            minutely15: minutely,
            hourly: hourly,
            daily: daily,
            airQuality: airQuality
        )
    }

    private static func decodeMinutely(_ object: Any?, offset: Int) -> [WeatherMinute] {
        guard let values = object as? [String: Any],
              let times = values["time"] as? [Any]
        else { return [] }
        return times.indices.compactMap { index in
            guard let raw = string(times[index]),
                  let time = parseTime(raw, utcOffsetSeconds: offset)
            else { return nil }
            return WeatherMinute(
                time: time,
                precipitation: number(values["precipitation"], index) ?? 0,
                precipitationProbability: integer(values["precipitation_probability"], index)
            )
        }
    }

    private static func decodeHourly(_ object: Any?, offset: Int) -> [WeatherHour] {
        guard let values = object as? [String: Any],
              let times = values["time"] as? [Any]
        else { return [] }
        return times.indices.compactMap { index in
            guard let raw = string(times[index]),
                  let time = parseTime(raw, utcOffsetSeconds: offset)
            else { return nil }
            return WeatherHour(
                time: time,
                temperature: number(values["temperature_2m"], index) ?? 0,
                apparentTemperature: number(values["apparent_temperature"], index)
                    ?? number(values["temperature_2m"], index) ?? 0,
                precipitationProbability: integer(values["precipitation_probability"], index) ?? 0,
                precipitation: number(values["precipitation"], index) ?? 0,
                weatherCode: integer(values["weather_code"], index) ?? 0,
                windSpeed: number(values["wind_speed_10m"], index) ?? 0,
                isDay: (integer(values["is_day"], index) ?? 1) != 0,
                uvIndex: number(values["uv_index"], index),
                visibility: number(values["visibility"], index)
            )
        }
    }

    private static func decodeDaily(_ object: Any?, offset: Int) -> [WeatherDay] {
        guard let values = object as? [String: Any],
              let times = values["time"] as? [Any]
        else { return [] }
        return times.indices.compactMap { index in
            guard let raw = string(times[index]),
                  let date = parseTime(raw, utcOffsetSeconds: offset)
            else { return nil }
            func dayTime(_ key: String) -> Date? {
                string(values[key], index).flatMap { parseTime($0, utcOffsetSeconds: offset) }
            }
            return WeatherDay(
                date: date,
                weatherCode: integer(values["weather_code"], index) ?? 0,
                temperatureMax: number(values["temperature_2m_max"], index) ?? 0,
                temperatureMin: number(values["temperature_2m_min"], index) ?? 0,
                precipitationProbabilityMax: integer(values["precipitation_probability_max"], index) ?? 0,
                precipitationSum: number(values["precipitation_sum"], index) ?? 0,
                sunrise: dayTime("sunrise"),
                sunset: dayTime("sunset"),
                uvIndexMax: number(values["uv_index_max"], index),
                windSpeedMax: number(values["wind_speed_10m_max"], index)
            )
        }
    }

    // MARK: Air quality decoding

    static func decodeAirQuality(_ data: Data) throws -> WeatherAirQuality {
        guard let root = jsonObject(data) else { throw WeatherSupportError.invalidJSON }
        guard let current = root["current"] as? [String: Any] else {
            throw WeatherSupportError.missingCurrentConditions
        }
        let offset = integer(root["utc_offset_seconds"]) ?? 0
        let time = string(current["time"]).flatMap { parseTime($0, utcOffsetSeconds: offset) }
            ?? Date()
        return WeatherAirQuality(
            time: time,
            usAQI: integer(current["us_aqi"]),
            europeanAQI: integer(current["european_aqi"]),
            pm25: double(current["pm2_5"]),
            pm10: double(current["pm10"]),
            ozone: double(current["ozone"])
        )
    }

    // MARK: Geocoding decoding

    static func decodeGeocoding(_ data: Data) throws -> [WeatherLocation] {
        guard let root = jsonObject(data) else { throw WeatherSupportError.invalidJSON }
        guard let results = root["results"] as? [Any] else { return [] }
        return results.compactMap { entry in
            guard let values = entry as? [String: Any],
                  let name = string(values["name"]), !name.isEmpty,
                  let latitude = double(values["latitude"]),
                  let longitude = double(values["longitude"])
            else { return nil }
            let timezone = string(values["timezone"]).flatMap { $0.isEmpty ? nil : $0 } ?? "UTC"
            return WeatherLocation(
                name: name,
                admin1: nonEmpty(string(values["admin1"])),
                country: nonEmpty(string(values["country"])),
                latitude: latitude,
                longitude: longitude,
                timezoneIdentifier: timezone
            )
        }
    }

    // MARK: Cache

    static func encodeCache(_ snapshot: WeatherSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    static func decodeCache(_ data: Data) throws -> WeatherSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WeatherSnapshot.self, from: data)
    }

    /// Whether two locations are the same place for cache purposes. Named for
    /// what it decides: a saved forecast belongs to the stored point, so a
    /// city change never shows the previous city's weather under the new name.
    static func isSamePlace(_ lhs: WeatherLocation,
                            _ rhs: WeatherLocation,
                            tolerance: Double = 0.01) -> Bool {
        abs(lhs.latitude - rhs.latitude) <= tolerance
            && abs(lhs.longitude - rhs.longitude) <= tolerance
    }

    // MARK: Dates

    /// Open-Meteo returns local wall-clock strings once `timezone=auto`, so
    /// the response's own UTC offset is the only clock they can be read with.
    /// Accepts both `2026-11-13T03:00` and the daily `2026-11-13`.
    static func parseTime(_ raw: String, utcOffsetSeconds: Int) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let timePart = trimmed.split(separator: "T", maxSplits: 1, omittingEmptySubsequences: false)
        let datePieces = timePart[0].split(separator: "-", omittingEmptySubsequences: false)
        guard datePieces.count == 3,
              let year = Int(datePieces[0]),
              let month = Int(datePieces[1]),
              let day = Int(datePieces[2])
        else { return nil }

        var hour = 0
        var minute = 0
        if timePart.count == 2 {
            let clock = timePart[1].split(separator: ":", omittingEmptySubsequences: false)
            guard clock.count >= 2, let parsedHour = Int(clock[0]), let parsedMinute = Int(clock[1])
            else { return nil }
            hour = parsedHour
            minute = parsedMinute
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds) ?? TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }

    /// Whether an hourly slot is the clock hour the current reading falls in.
    /// Both dates are already resolved to the forecast's timezone, so the
    /// comparison uses that same zone rather than the Mac's.
    static func isCurrentHour(_ hour: Date, now: Date, timeZoneIdentifier: String) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar.isDate(hour, equalTo: now, toGranularity: .hour)
    }

    // MARK: JSON helpers

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        return number.doubleValue
    }

    private static func double(_ value: Any?) -> Double? { number(value) }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        return number.intValue
    }

    private static func number(_ array: Any?, _ index: Int) -> Double? {
        guard let array = array as? [Any], index < array.count else { return nil }
        return number(array[index])
    }

    private static func integer(_ array: Any?, _ index: Int) -> Int? {
        guard let array = array as? [Any], index < array.count else { return nil }
        return integer(array[index])
    }

    private static func string(_ array: Any?, _ index: Int) -> String? {
        guard let array = array as? [Any], index < array.count else { return nil }
        return string(array[index])
    }
}

enum WeatherSupportError: Error, LocalizedError {
    case invalidJSON
    case missingCurrentConditions

    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "The weather response could not be read."
        case .missingCurrentConditions: return "The weather response had no current conditions."
        }
    }
}

// MARK: - Unit formatting

extension WeatherUnitPreferences {
    var temperatureSymbol: String {
        switch temperature {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    var windSymbol: String {
        switch wind {
        case .kilometersPerHour: return "km/h"
        case .milesPerHour: return "mph"
        case .metersPerSecond: return "m/s"
        case .knots: return "kn"
        }
    }

    var precipitationSymbol: String {
        switch precipitation {
        case .millimeters: return "mm"
        case .inches: return "in"
        }
    }

    var pressureSymbol: String {
        switch pressure {
        case .hectopascals: return "hPa"
        case .inchesOfMercury: return "inHg"
        }
    }

    var distanceSymbol: String {
        switch distance {
        case .kilometers: return "km"
        case .miles: return "mi"
        }
    }

    func formattedTemperature(_ celsius: Double, fractionDigits: Int = 0,
                              locale: Locale = .current) -> String {
        "\(decimal(temperatureValue(celsius), fractionDigits, locale: locale))°"
    }

    func formattedWind(_ kilometersPerHour: Double, locale: Locale = .current) -> String {
        let digits = wind == .metersPerSecond ? 1 : 0
        return "\(decimal(windValue(kilometersPerHour), digits, locale: locale)) \(windSymbol)"
    }

    func formattedPrecipitation(_ millimeters: Double, locale: Locale = .current) -> String {
        let digits = precipitation == .inches ? 2 : 1
        return "\(decimal(precipitationValue(millimeters), digits, locale: locale)) \(precipitationSymbol)"
    }

    func formattedPressure(_ hectopascals: Double, locale: Locale = .current) -> String {
        let digits = pressure == .inchesOfMercury ? 2 : 0
        return "\(decimal(pressureValue(hectopascals), digits, locale: locale)) \(pressureSymbol)"
    }

    func formattedDistance(_ kilometers: Double, locale: Locale = .current) -> String {
        "\(decimal(distanceValue(kilometers), 1, locale: locale)) \(distanceSymbol)"
    }

    /// Visibility arrives in meters, the unit Open-Meteo uses for it; the
    /// chosen distance unit still applies.
    func formattedVisibility(_ meters: Double, locale: Locale = .current) -> String {
        formattedDistance(meters / 1000, locale: locale)
    }

    private func decimal(_ value: Double, _ digits: Int, locale: Locale) -> String {
        String(format: "%.\(digits)f", locale: locale, value)
    }
}
