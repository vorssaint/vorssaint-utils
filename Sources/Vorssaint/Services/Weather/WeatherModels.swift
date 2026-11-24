// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One place weather can be shown for. Coordinates are the identity a fetch
/// round trip and the cache rely on; the names are only for display.
struct WeatherLocation: Codable, Hashable, Identifiable {
    let name: String
    let admin1: String?
    let country: String?
    let latitude: Double
    let longitude: Double
    let timezoneIdentifier: String

    var id: String { "\(latitude),\(longitude)" }

    /// The line under the name in a location list, already trimmed.
    var detail: String? {
        let parts = [admin1, country]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != name }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// WMO weather interpretation codes, folded into the groups a person reads.
/// Open-Meteo returns the raw code; every surface asks this type instead.
enum WeatherCondition: String, Codable, CaseIterable {
    case clear, mainlyClear, partlyCloudy, overcast, fog, drizzle, rain, heavyRain,
         freezingRain, snow, snowShowers, thunderstorm, hail, unknown

    init(wmoCode: Int) {
        switch wmoCode {
        case 0: self = .clear
        case 1: self = .mainlyClear
        case 2: self = .partlyCloudy
        case 3: self = .overcast
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 56, 57, 66, 67: self = .freezingRain
        case 61, 63, 80, 81: self = .rain
        case 65, 82: self = .heavyRain
        case 71, 73, 75, 77: self = .snow
        case 85, 86: self = .snowShowers
        case 95, 97: self = .thunderstorm
        case 96, 99: self = .hail
        default: self = .unknown
        }
    }

    /// SF Symbol for the condition. Clear and partly cloudy have a night
    /// form; the rest read the same after dark.
    func symbolName(isDay: Bool) -> String {
        switch self {
        case .clear: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case .mainlyClear: return isDay ? "sun.min.fill" : "moon.fill"
        case .partlyCloudy: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .overcast: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .heavyRain: return "cloud.heavyrain.fill"
        case .freezingRain: return "cloud.sleet.fill"
        case .snow, .snowShowers: return "cloud.snow.fill"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        case .hail: return "cloud.hail.fill"
        case .unknown: return "cloud.fill"
        }
    }
}

struct WeatherCurrent: Codable, Hashable {
    let time: Date
    let temperature: Double
    let apparentTemperature: Double
    let relativeHumidity: Int
    let precipitation: Double
    let weatherCode: Int
    let cloudCover: Int?
    let pressureMSL: Double?
    let windSpeed: Double
    let windDirection: Int
    let windGust: Double?
    let uvIndex: Double?
    let isDay: Bool

    var condition: WeatherCondition { WeatherCondition(wmoCode: weatherCode) }
}

struct WeatherMinute: Codable, Hashable {
    let time: Date
    let precipitation: Double
    let precipitationProbability: Int?
}

struct WeatherHour: Codable, Hashable {
    let time: Date
    let temperature: Double
    let apparentTemperature: Double
    let precipitationProbability: Int
    let precipitation: Double
    let weatherCode: Int
    let windSpeed: Double
    let isDay: Bool
    let uvIndex: Double?
    let visibility: Double?

    var condition: WeatherCondition { WeatherCondition(wmoCode: weatherCode) }
}

struct WeatherDay: Codable, Hashable {
    let date: Date
    let weatherCode: Int
    let temperatureMax: Double
    let temperatureMin: Double
    let precipitationProbabilityMax: Int
    let precipitationSum: Double
    let sunrise: Date?
    let sunset: Date?
    let uvIndexMax: Double?
    let windSpeedMax: Double?

    var condition: WeatherCondition { WeatherCondition(wmoCode: weatherCode) }
}

struct WeatherAirQuality: Codable, Hashable {
    let time: Date
    let usAQI: Int?
    let europeanAQI: Int?
    let pm25: Double?
    let pm10: Double?
    let ozone: Double?
}

/// One successful forecast. The timezone travels with it because every date
/// inside is already resolved to it.
struct WeatherSnapshot: Codable, Hashable {
    let location: WeatherLocation
    let fetchedAt: Date
    let timezoneIdentifier: String
    let current: WeatherCurrent
    let minutely15: [WeatherMinute]
    let hourly: [WeatherHour]
    let daily: [WeatherDay]
    let airQuality: WeatherAirQuality?
}

/// What a panel or Settings row shows while the service works. `loaded` keeps
/// the last good snapshot visible and says whether it is being refreshed from
/// a stale cache after a failed fetch.
enum WeatherLoadState: Equatable {
    case idle
    case loading
    case loaded(stale: Bool)
    case failed(message: String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isStale: Bool {
        if case .loaded(stale: true) = self { return true }
        return false
    }
}

/// How the optional menu bar item renders. Values are persisted, so the raw
/// case names are stable.
enum WeatherMenuBarStyle: String, Codable, CaseIterable {
    case symbolOnly, temperatureOnly, symbolTemperature, highLow, precipitationChance

    static func sanitized(_ raw: String?) -> WeatherMenuBarStyle {
        raw.flatMap(WeatherMenuBarStyle.init(rawValue:)) ?? .symbolTemperature
    }
}

/// The resolved text the optional menu bar weather block shows. Pure values so
/// the renderer never reaches into the service and tests need no AppKit.
struct WeatherMenuBarReading: Equatable {
    /// The current condition's symbol, before the chosen style narrows it.
    let symbolName: String
    let temperature: String
    let highLow: String
    let precipitationChance: String
    let style: WeatherMenuBarStyle
    /// Empty unless the menu bar setting asks for `°C` or `°F`.
    let unitSuffix: String

    init(snapshot: WeatherSnapshot,
         preferences: WeatherUnitPreferences,
         defaults: UserDefaults = .standard) {
        let current = snapshot.current
        let showsUnit = defaults.bool(forKey: DefaultsKey.weatherMenuBarShowsUnit)
        let suffix = showsUnit ? "°\(preferences.temperatureUnitSymbol)" : ""
        unitSuffix = suffix
        symbolName = current.condition.symbolName(isDay: current.isDay)
        temperature = preferences.formattedTemperature(current.temperature) + (showsUnit ? preferences.temperatureUnitSymbol : "")

        if let today = snapshot.daily.first {
            let high = preferences.formattedTemperature(today.temperatureMax)
            let low = preferences.formattedTemperature(today.temperatureMin)
            // One shared degree sign keeps the pair inside its menu bar block.
            var pair = "\(high.replacingOccurrences(of: "°", with: ""))/\(low.replacingOccurrences(of: "°", with: ""))"
            if showsUnit {
                pair += "°\(preferences.temperatureUnitSymbol)"
            }
            highLow = pair
        } else {
            highLow = ""
        }

        // The next hour is the first slot at or after the current reading.
        let nextHour = snapshot.hourly.first { $0.time >= current.time } ?? snapshot.hourly.first
        precipitationChance = nextHour.map { "\($0.precipitationProbability)%" } ?? ""

        style = WeatherMenuBarStyle.sanitized(defaults.string(forKey: DefaultsKey.weatherMenuBarStyle))
    }

    /// The symbol the chosen style shows; temperature only has none.
    var menuBarSymbolName: String? {
        switch style {
        case .temperatureOnly: return nil
        case .symbolOnly, .symbolTemperature, .highLow: return symbolName
        case .precipitationChance: return WeatherCondition.rain.symbolName(isDay: true)
        }
    }

    /// The value text the chosen style shows; symbol only has none.
    var menuBarText: String? {
        switch style {
        case .symbolOnly: return nil
        case .temperatureOnly, .symbolTemperature: return temperature
        case .highLow: return highLow.isEmpty ? nil : highLow
        case .precipitationChance: return precipitationChance.isEmpty ? nil : precipitationChance
        }
    }

    /// Widest value the block reserves space for, matching `menuBarText`.
    var reservedValue: String {
        switch style {
        case .symbolOnly: return ""
        case .temperatureOnly, .symbolTemperature: return "-99\(unitSuffix)"
        case .highLow: return "-99/-99\(unitSuffix)"
        case .precipitationChance: return "100%"
        }
    }
}

/// User-facing units. Values are stored as these raw strings and every
/// conversion starts from the metric numbers Open-Meteo returns.
struct WeatherUnitPreferences: Codable, Hashable {
    enum TemperatureUnit: String, Codable, CaseIterable {
        case celsius, fahrenheit
    }

    enum WindUnit: String, Codable, CaseIterable {
        case kilometersPerHour = "kph", milesPerHour = "mph"
        case metersPerSecond = "mps", knots = "kn"
    }

    enum PrecipitationUnit: String, Codable, CaseIterable {
        case millimeters = "mm", inches = "in"
    }

    enum PressureUnit: String, Codable, CaseIterable {
        case hectopascals = "hPa", inchesOfMercury = "inHg"
    }

    enum DistanceUnit: String, Codable, CaseIterable {
        case kilometers = "km", miles = "mi"
    }

    var temperature: TemperatureUnit
    var wind: WindUnit
    var precipitation: PrecipitationUnit
    var pressure: PressureUnit
    var distance: DistanceUnit

    static let metric = WeatherUnitPreferences(
        temperature: .celsius,
        wind: .kilometersPerHour,
        precipitation: .millimeters,
        pressure: .hectopascals,
        distance: .kilometers
    )

    static let imperial = WeatherUnitPreferences(
        temperature: .fahrenheit,
        wind: .milesPerHour,
        precipitation: .inches,
        pressure: .inchesOfMercury,
        distance: .miles
    )

    init(temperature: TemperatureUnit,
         wind: WindUnit,
         precipitation: PrecipitationUnit,
         pressure: PressureUnit,
         distance: DistanceUnit) {
        self.temperature = temperature
        self.wind = wind
        self.precipitation = precipitation
        self.pressure = pressure
        self.distance = distance
    }

    /// Follows the region's measurement system, which is what a person
    /// already sees in the rest of the app.
    init(locale: Locale) {
        switch locale.measurementSystem {
        case .us: self = .imperial
        default: self = .metric
        }
    }

    static var localeDefault: WeatherUnitPreferences { WeatherUnitPreferences(locale: .current) }

    /// Stored raw values, each falling back to the locale default on its own so
    /// one missing key never resets the rest.
    init(temperatureUnit: String?,
         windUnit: String?,
         precipitationUnit: String?,
         pressureUnit: String?,
         distanceUnit: String?) {
        let fallback = WeatherUnitPreferences.localeDefault
        self.temperature = temperatureUnit.flatMap(TemperatureUnit.init(rawValue:)) ?? fallback.temperature
        self.wind = windUnit.flatMap(WindUnit.init(rawValue:)) ?? fallback.wind
        self.precipitation = precipitationUnit.flatMap(PrecipitationUnit.init(rawValue:)) ?? fallback.precipitation
        self.pressure = pressureUnit.flatMap(PressureUnit.init(rawValue:)) ?? fallback.pressure
        self.distance = distanceUnit.flatMap(DistanceUnit.init(rawValue:)) ?? fallback.distance
    }

    // MARK: Conversions

    var temperatureUnitSymbol: String {
        temperature == .celsius ? "C" : "F"
    }

    func temperatureValue(_ celsius: Double) -> Double {
        switch temperature {
        case .celsius: return celsius
        case .fahrenheit: return celsius * 9 / 5 + 32
        }
    }

    func windValue(_ kilometersPerHour: Double) -> Double {
        switch wind {
        case .kilometersPerHour: return kilometersPerHour
        case .milesPerHour: return kilometersPerHour * 0.621_371
        case .metersPerSecond: return kilometersPerHour / 3.6
        case .knots: return kilometersPerHour * 0.539_957
        }
    }

    func precipitationValue(_ millimeters: Double) -> Double {
        switch precipitation {
        case .millimeters: return millimeters
        case .inches: return millimeters / 25.4
        }
    }

    func pressureValue(_ hectopascals: Double) -> Double {
        switch pressure {
        case .hectopascals: return hectopascals
        case .inchesOfMercury: return hectopascals * 0.029_53
        }
    }

    func distanceValue(_ kilometers: Double) -> Double {
        switch distance {
        case .kilometers: return kilometers
        case .miles: return kilometers * 0.621_371
        }
    }
}
