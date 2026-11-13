// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure weather contracts: WMO mapping, request parameters, tolerant decoding,
/// unit conversion and the on-disk cache format. No network, timer or UI.
enum WeatherTests {
    static func run(_ suite: TestSuite) {
        let paris = WeatherLocation(
            name: "Paris",
            admin1: "Ile-de-France",
            country: "France",
            latitude: 48.8566,
            longitude: 2.3522,
            timezoneIdentifier: "Europe/Paris"
        )

        checkConditions(suite)
        checkURLs(suite, location: paris)
        checkForecastDecoding(suite, location: paris)
        checkAirQuality(suite, location: paris)
        checkGeocoding(suite)
        checkUnits(suite)
        checkFormatting(suite)
        checkHourLabels(suite)
        checkCache(suite, location: paris)
        checkFeatureGates(suite)
        checkMenuBarStyle(suite)
    }

    // MARK: Conditions

    private static func checkConditions(_ suite: TestSuite) {
        let mappings: [Int: WeatherCondition] = [
            0: .clear, 1: .mainlyClear, 2: .partlyCloudy, 3: .overcast,
            45: .fog, 48: .fog,
            51: .drizzle, 53: .drizzle, 55: .drizzle,
            56: .freezingRain, 57: .freezingRain,
            61: .rain, 63: .rain,
            65: .heavyRain,
            66: .freezingRain, 67: .freezingRain,
            71: .snow, 73: .snow, 75: .snow, 77: .snow,
            80: .rain, 81: .rain, 82: .heavyRain,
            85: .snowShowers, 86: .snowShowers,
            95: .thunderstorm,
            96: .hail, 97: .thunderstorm, 99: .hail,
        ]
        for (code, expected) in mappings.sorted(by: { $0.key < $1.key }) {
            suite.expect(WeatherCondition(wmoCode: code) == expected,
                         "WMO \(code) maps to \(expected.rawValue)")
        }
        suite.expect(WeatherCondition(wmoCode: -1) == .unknown
                        && WeatherCondition(wmoCode: 999) == .unknown,
                     "unlisted WMO codes fall back to unknown")
        suite.expect(WeatherCondition.clear.symbolName(isDay: true) != WeatherCondition.clear.symbolName(isDay: false),
                     "clear weather has a distinct night symbol")
        suite.expect(WeatherCondition.partlyCloudy.symbolName(isDay: true) != WeatherCondition.partlyCloudy.symbolName(isDay: false),
                     "partly cloudy weather has a distinct night symbol")
        suite.expect(WeatherCondition.allCases.allSatisfy {
            !$0.symbolName(isDay: true).isEmpty && !$0.symbolName(isDay: false).isEmpty
        }, "every condition has a day and night symbol")
        suite.expect(FeatureStrings.weather(.enUS).name(for: .heavyRain) == "Heavy rain",
                     "condition names come from the shared weather strings")
    }

    // MARK: URLs

    private static func checkURLs(_ suite: TestSuite, location: WeatherLocation) {
        func queryItems(_ url: URL?) -> [String: String] {
            guard let url,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let items = components.queryItems
            else { return [:] }
            return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        }

        let forecast = queryItems(WeatherSupport.forecastURL(location: location))
        suite.expect(forecast["latitude"] == "48.85660" && forecast["longitude"] == "2.35220",
                     "forecast URL carries the coordinates")
        suite.expect(forecast["timezone"] == "auto"
                        && forecast["forecast_days"] == "7"
                        && forecast["timeformat"] == "iso8601",
                     "forecast URL asks for the response timezone and a week of days")
        suite.expect(forecast["temperature_unit"] == "celsius"
                        && forecast["wind_speed_unit"] == "kmh"
                        && forecast["precipitation_unit"] == "mm",
                     "the models always receive canonical metric units")
        suite.expect(forecast["current"]?.contains("temperature_2m") == true
                        && forecast["current"]?.contains("weather_code") == true
                        && forecast["current"]?.contains("uv_index") == true,
                     "current conditions request the fields the model reads, UV included")
        suite.expect(forecast["hourly"]?.contains("precipitation_probability") == true
                        && forecast["hourly"]?.contains("visibility") == true
                        && forecast["daily"]?.contains("sunrise") == true
                        && forecast["minutely_15"]?.contains("precipitation") == true,
                     "hourly, daily and minutely requests include their model fields")

        let airQuality = queryItems(WeatherSupport.airQualityURL(location: location))
        suite.expect(airQuality["current"]?.contains("us_aqi") == true
                        && airQuality["timezone"] == "auto",
                     "air quality is a separate request for the same point")

        let search = queryItems(WeatherSupport.geocodingURL(query: "  New York  "))
        suite.expect(search["name"] == "New York" && search["count"] == "8"
                        && search["format"] == "json",
                     "geocoding trims the query and asks for a short list")
        suite.expect(WeatherSupport.geocodingURL(query: "   ") == nil,
                     "an empty place search builds no request")
    }

    // MARK: Forecast decoding

    private static func checkForecastDecoding(_ suite: TestSuite, location: WeatherLocation) {
        let json = """
        {
          "latitude": 48.8566,
          "longitude": 2.3522,
          "timezone": "Europe/Paris",
          "utc_offset_seconds": 3600,
          "current": {
            "time": "2026-11-13T09:30",
            "temperature_2m": 11.4,
            "apparent_temperature": 9.8,
            "relative_humidity_2m": 72,
            "precipitation": 0.0,
            "weather_code": 61,
            "cloud_cover": 80,
            "pressure_msl": 1012.3,
            "wind_speed_10m": 14.2,
            "wind_direction_10m": 210,
            "wind_gusts_10m": null,
            "uv_index": 3.4,
            "is_day": 1
          },
          "minutely_15": null,
          "hourly": {
            "time": ["2026-11-13T10:00", "2026-11-13T11:00"],
            "temperature_2m": [12.0, null],
            "apparent_temperature": [11.0, 12.5],
            "precipitation_probability": [10, null],
            "precipitation": [0.0, 0.4],
            "weather_code": [3, 61],
            "wind_speed_10m": [9.0, 15.0],
            "is_day": [1, 1],
            "uv_index": [null, 1.2],
            "visibility": [null, 8000]
          },
          "daily": {
            "time": ["2026-11-13", "2026-11-14"],
            "weather_code": [61, null],
            "temperature_2m_max": [13.0, 14.5],
            "temperature_2m_min": [7.0, 8.0],
            "precipitation_probability_max": [60, 30],
            "precipitation_sum": [2.4, 0.0],
            "sunrise": ["2026-11-13T07:41", null],
            "sunset": ["2026-11-13T17:12", null],
            "uv_index_max": [1.5, null],
            "wind_speed_10m_max": [20.0, 18.0]
          }
        }
        """.data(using: .utf8)!

        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        guard let snapshot = try? WeatherSupport.decodeForecast(json, location: location,
                                                                fetchedAt: fetchedAt) else {
            suite.expect(false, "a forecast with null arrays decodes")
            return
        }
        suite.expect(snapshot.location == location
                        && snapshot.fetchedAt == fetchedAt
                        && snapshot.timezoneIdentifier == "Europe/Paris",
                     "the snapshot keeps its location, fetch time and response timezone")
        suite.expect(snapshot.current.temperature == 11.4
                        && snapshot.current.apparentTemperature == 9.8
                        && snapshot.current.relativeHumidity == 72
                        && snapshot.current.pressureMSL == 1012.3
                        && snapshot.current.windDirection == 210
                        && snapshot.current.isDay
                        && snapshot.current.condition == .rain,
                     "current conditions decode every requested field")
        suite.expect(snapshot.current.windGust == nil && snapshot.current.uvIndex == 3.4,
                     "current optional values decode, and nulls stay nil")
        suite.expect(snapshot.minutely15.isEmpty,
                     "a null minutely array becomes an empty list")
        suite.expect(snapshot.hourly.count == 2
                        && snapshot.hourly[0].weatherCode == 3
                        && snapshot.hourly[0].precipitationProbability == 10
                        && snapshot.hourly[0].uvIndex == nil
                        && snapshot.hourly[0].visibility == nil
                        && snapshot.hourly[1].temperature == 0
                        && snapshot.hourly[1].precipitationProbability == 0
                        && snapshot.hourly[1].uvIndex == 1.2
                        && snapshot.hourly[1].visibility == 8000,
                     "hourly nulls fall back to safe numbers while real values survive")
        suite.expect(snapshot.daily.count == 2
                        && snapshot.daily[0].condition == .rain
                        && snapshot.daily[0].temperatureMax == 13
                        && snapshot.daily[0].precipitationProbabilityMax == 60
                        && snapshot.daily[0].sunrise != nil
                        && snapshot.daily[0].sunset != nil
                        && snapshot.daily[1].sunrise == nil
                        && snapshot.daily[1].uvIndexMax == nil,
                     "daily nulls are tolerated without losing the valid day")
        suite.expect(snapshot.daily[0].date == WeatherSupport.parseTime("2026-11-13", utcOffsetSeconds: 3600),
                     "daily dates use the response UTC offset")

        let minimal = """
        {"utc_offset_seconds": 0, "current": {"temperature_2m": 4, "weather_code": 0}}
        """.data(using: .utf8)!
        let sparse = try? WeatherSupport.decodeForecast(minimal, location: location)
        suite.expect(sparse?.hourly.isEmpty == true && sparse?.daily.isEmpty == true
                        && sparse?.minutely15.isEmpty == true && sparse?.airQuality == nil,
                     "a response without array blocks still yields current conditions")
        suite.expect(sparse?.current.condition == .clear && sparse?.current.isDay == true,
                     "missing current flags fall back to the day form")

        var invalidThrew = false
        do {
            _ = try WeatherSupport.decodeForecast(Data("{".utf8), location: location)
        } catch {
            invalidThrew = true
        }
        suite.expect(invalidThrew, "malformed JSON is rejected instead of guessed")
        var missingCurrentThrew = false
        do {
            _ = try WeatherSupport.decodeForecast(Data("{}".utf8), location: location)
        } catch {
            missingCurrentThrew = true
        }
        suite.expect(missingCurrentThrew, "a response without current conditions is an error")
    }

    // MARK: Air quality

    private static func checkAirQuality(_ suite: TestSuite, location: WeatherLocation) {
        let forecast = """
        {"utc_offset_seconds": 3600, "timezone": "Europe/Paris",
         "current": {"time": "2026-11-13T09:30", "temperature_2m": 11, "weather_code": 1}}
        """.data(using: .utf8)!
        let failure = try? WeatherSupport.decodeForecast(forecast, location: location,
                                                         airQualityData: Data("{".utf8))
        suite.expect(failure?.current.temperature == 11,
                     "a broken air-quality reply never blocks the forecast")

        let air = """
        {"utc_offset_seconds": 3600,
         "current": {"time": "2026-11-13T09:30", "us_aqi": 42, "european_aqi": 31,
                     "pm2_5": 12.5, "pm10": null, "ozone": 55.0}}
        """.data(using: .utf8)!
        let quality = try? WeatherSupport.decodeAirQuality(air)
        suite.expect(quality?.usAQI == 42 && quality?.europeanAQI == 31
                        && quality?.pm25 == 12.5 && quality?.pm10 == nil
                        && quality?.ozone == 55,
                     "air quality decodes its optional readings")
        let combined = try? WeatherSupport.decodeForecast(forecast, location: location,
                                                          airQualityData: air)
        suite.expect(combined?.airQuality?.usAQI == 42,
                     "a valid air-quality reply travels inside the snapshot")
    }

    // MARK: Geocoding

    private static func checkGeocoding(_ suite: TestSuite) {
        let json = """
        {"results": [
          {"name": "Portland", "admin1": "Oregon", "country": "United States",
           "latitude": 45.5231, "longitude": -122.6765, "timezone": "America/Los_Angeles"},
          {"name": "Portland", "admin1": null, "country": "Australia",
           "latitude": -38.3462, "longitude": 141.6026, "timezone": "Australia/Melbourne"},
          {"name": "", "latitude": 1, "longitude": 2}
        ]}
        """.data(using: .utf8)!
        let places = (try? WeatherSupport.decodeGeocoding(json)) ?? []
        suite.expect(places.count == 2, "nameless geocoding entries are dropped")
        suite.expect(places.first?.name == "Portland"
                        && places.first?.admin1 == "Oregon"
                        && places.first?.country == "United States"
                        && places.first?.latitude == 45.5231
                        && places.first?.timezoneIdentifier == "America/Los_Angeles",
                     "a geocoding result keeps its names, coordinates and timezone")
        suite.expect(places.last?.admin1 == nil && places.last?.detail == "Australia",
                     "a missing region leaves only the country in the detail line")
        suite.expect((try? WeatherSupport.decodeGeocoding(Data("{}".utf8)))?.isEmpty == true,
                     "a search without results decodes to an empty list")
    }

    // MARK: Units

    private static func checkUnits(_ suite: TestSuite) {
        let us = WeatherUnitPreferences(locale: Locale(identifier: "en_US"))
        let uk = WeatherUnitPreferences(locale: Locale(identifier: "en_GB"))
        suite.expect(us == .imperial, "the United States region starts in imperial units")
        suite.expect(uk == .metric, "a metric region starts in metric units")
        suite.expectClose(WeatherUnitPreferences.imperial.temperatureValue(0), 32, "0 C in F")
        suite.expectClose(WeatherUnitPreferences.imperial.temperatureValue(100), 212, "100 C in F")
        suite.expectClose(WeatherUnitPreferences.imperial.windValue(100), 62.1371, "100 kph in mph", tol: 0.01)
        let perSecondUnits = WeatherUnitPreferences(temperature: .celsius, wind: .metersPerSecond,
                                                    precipitation: .millimeters, pressure: .hectopascals,
                                                    distance: .kilometers)
        suite.expectClose(perSecondUnits.windValue(36), 10, "36 kph in m/s")
        let knots = WeatherUnitPreferences(temperature: .celsius, wind: .knots,
                                           precipitation: .millimeters, pressure: .hectopascals,
                                           distance: .kilometers)
        suite.expectClose(knots.windValue(100), 53.9957, "100 kph in knots", tol: 0.01)
        suite.expectClose(WeatherUnitPreferences.imperial.precipitationValue(25.4), 1, "25.4 mm in inches")
        suite.expectClose(WeatherUnitPreferences.imperial.pressureValue(1013.25), 29.92,
                          "1013.25 hPa in inHg", tol: 0.01)
        suite.expectClose(WeatherUnitPreferences.imperial.distanceValue(1.609344), 1,
                          "1.609344 km in miles", tol: 0.001)
        suite.expect(WeatherUnitPreferences(temperatureUnit: "kelvin", windUnit: "kph",
                                            precipitationUnit: "mm", pressureUnit: "hPa",
                                            distanceUnit: "km").temperature
                == WeatherUnitPreferences.localeDefault.temperature,
                     "an unknown stored unit falls back to the region default")
    }

    // MARK: Formatting

    private static func checkFormatting(_ suite: TestSuite) {
        let metric = WeatherUnitPreferences.metric
        let imperial = WeatherUnitPreferences.imperial
        let locale = Locale(identifier: "en_US_POSIX")
        suite.expect(metric.formattedTemperature(18.4, locale: locale) == "18°"
                        && imperial.formattedTemperature(20, locale: locale) == "68°",
                     "temperatures format with a degree sign in the chosen unit")
        suite.expect(metric.formattedWind(12.4, locale: locale) == "12 km/h"
                        && imperial.formattedWind(16.09, locale: locale) == "10 mph",
                     "wind formats with its unit symbol")
        let perSecond = WeatherUnitPreferences(temperature: .celsius, wind: .metersPerSecond,
                                               precipitation: .millimeters, pressure: .hectopascals,
                                               distance: .kilometers)
        suite.expect(perSecond.formattedWind(36, locale: locale) == "10.0 m/s",
                     "meters per second keeps one decimal")
        suite.expect(metric.formattedPrecipitation(1.2, locale: locale) == "1.2 mm"
                        && imperial.formattedPrecipitation(25.4, locale: locale) == "1.00 in",
                     "precipitation formats in millimeters or inches")
        suite.expect(metric.formattedPressure(1013, locale: locale) == "1013 hPa"
                        && imperial.formattedPressure(1013.25, locale: locale) == "29.92 inHg",
                     "pressure formats in hectopascals or inches of mercury")
        suite.expect(metric.formattedDistance(5, locale: locale) == "5.0 km"
                        && imperial.formattedDistance(5, locale: locale) == "3.1 mi",
                     "distance formats in kilometers or miles")
        suite.expect(metric.formattedVisibility(1500, locale: locale) == "1.5 km"
                        && imperial.formattedVisibility(1609.344, locale: locale) == "1.0 mi",
                     "visibility converts meters into the chosen distance unit")
        suite.expect(metric.temperatureSymbol == "°C" && metric.windSymbol == "km/h"
                        && imperial.pressureSymbol == "inHg",
                     "unit symbols name the stored units")
    }

    // MARK: Hour labels

    private static func checkHourLabels(_ suite: TestSuite) {
        let zone = "Europe/Paris"
        guard let current = WeatherSupport.parseTime("2026-11-13T09:30", utcOffsetSeconds: 3600),
              let sameHour = WeatherSupport.parseTime("2026-11-13T09:00", utcOffsetSeconds: 3600),
              let nextHour = WeatherSupport.parseTime("2026-11-13T10:00", utcOffsetSeconds: 3600)
        else {
            suite.expect(false, "hour label fixtures parse")
            return
        }
        suite.expect(WeatherSupport.isCurrentHour(sameHour, now: current, timeZoneIdentifier: zone),
                     "the current reading's own hour is labelled Now")
        suite.expect(!WeatherSupport.isCurrentHour(nextHour, now: current, timeZoneIdentifier: zone),
                     "a later hourly slot keeps its real hour instead of saying Now")
    }

    // MARK: Cache

    private static func checkCache(_ suite: TestSuite, location: WeatherLocation) {
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = WeatherSnapshot(
            location: location,
            fetchedAt: moment,
            timezoneIdentifier: "Europe/Paris",
            current: WeatherCurrent(
                time: moment, temperature: 11.4, apparentTemperature: 9.8,
                relativeHumidity: 72, precipitation: 0, weatherCode: 61,
                cloudCover: 80, pressureMSL: 1012.3, windSpeed: 14.2,
                windDirection: 210, windGust: nil, uvIndex: nil, isDay: true
            ),
            minutely15: [WeatherMinute(time: moment.addingTimeInterval(900),
                                       precipitation: 0.2,
                                       precipitationProbability: 40)],
            hourly: [WeatherHour(time: moment.addingTimeInterval(3600), temperature: 12,
                                 apparentTemperature: 11, precipitationProbability: 10,
                                 precipitation: 0, weatherCode: 3, windSpeed: 9,
                                 isDay: true, uvIndex: 1.2, visibility: 8000)],
            daily: [WeatherDay(date: moment, weatherCode: 61, temperatureMax: 13,
                               temperatureMin: 7, precipitationProbabilityMax: 60,
                               precipitationSum: 2.4, sunrise: moment, sunset: moment,
                               uvIndexMax: 1.5, windSpeedMax: 20)],
            airQuality: WeatherAirQuality(time: moment, usAQI: 42, europeanAQI: 31,
                                          pm25: 12.5, pm10: nil, ozone: 55)
        )
        guard let data = try? WeatherSupport.encodeCache(snapshot),
              let restored = try? WeatherSupport.decodeCache(data) else {
            suite.expect(false, "a snapshot round-trips through the cache format")
            return
        }
        suite.expect(restored == snapshot,
                     "the cache keeps every reading, including optional air quality")
        var corruptThrew = false
        do {
            _ = try WeatherSupport.decodeCache(Data("[]".utf8))
        } catch {
            corruptThrew = true
        }
        suite.expect(corruptThrew, "a corrupt cache file is rejected instead of half-read")

        let nearby = WeatherLocation(name: "Paris centre", admin1: nil, country: nil,
                                     latitude: 48.8567, longitude: 2.3523,
                                     timezoneIdentifier: "Europe/Paris")
        let lyon = WeatherLocation(name: "Lyon", admin1: nil, country: nil,
                                   latitude: 45.7640, longitude: 4.8357,
                                   timezoneIdentifier: "Europe/Paris")
        suite.expect(WeatherSupport.isSamePlace(location, nearby),
                     "a cached forecast within the coordinate tolerance belongs to the stored place")
        suite.expect(!WeatherSupport.isSamePlace(location, lyon),
                     "a forecast for another city is not loaded for the stored place")
    }

    // MARK: Feature gates

    private static func checkFeatureGates(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.weather-feature-gates"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }

        defaults.set(true, forKey: AppFeature.weather.availabilityKey)
        defaults.set(false, forKey: DefaultsKey.weatherEnabled)
        defaults.set(true, forKey: DefaultsKey.menuBarWeather)

        suite.expect(!WeatherSupport.isMenuBarWeatherEnabled(in: defaults),
                     "a weather menu bar block needs the feature switched on")
        suite.expect(!MenuPanelSectionGateContract.PanelSectionID.weather.isAvailable(in: defaults),
                     "the weather panel section leaves while the feature is off")
        suite.expect(!NotchModule.weather.isAvailable(in: defaults),
                     "the weather island module leaves while the feature is off")

        defaults.set(true, forKey: DefaultsKey.weatherEnabled)
        suite.expect(WeatherSupport.isMenuBarWeatherEnabled(in: defaults)
                        && MenuPanelSectionGateContract.PanelSectionID.weather.isAvailable(in: defaults)
                        && NotchModule.weather.isAvailable(in: defaults),
                     "switching the feature on brings every weather surface back")

        defaults.set(false, forKey: AppFeature.weather.availabilityKey)
        suite.expect(!MenuPanelSectionGateContract.PanelSectionID.weather.isAvailable(in: defaults)
                        && !NotchModule.weather.isAvailable(in: defaults)
                        && !WeatherSupport.isMenuBarWeatherEnabled(in: defaults),
                     "an uninstalled weather feature keeps every weather surface out")
    }

    // MARK: Menu bar style

    private static func checkMenuBarStyle(_ suite: TestSuite) {
        suite.expect(WeatherMenuBarStyle.sanitized("highLow") == .highLow,
                     "a stored menu bar style is honored")
        suite.expect(WeatherMenuBarStyle.sanitized("nonsense") == .symbolTemperature
                        && WeatherMenuBarStyle.sanitized(nil) == .symbolTemperature,
                     "an unknown menu bar style falls back to symbol and temperature")
        let strings = FeatureStrings.weather(.enUS)
        suite.expect(WeatherMenuBarStyle.allCases.allSatisfy { !strings.menuBarStyle($0).isEmpty },
                     "every menu bar style has its own label")
        checkMenuBarReading(suite)
    }

    // MARK: Menu bar reading

    private static func checkMenuBarReading(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.weather-menu-bar-reading"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }

        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        let location = WeatherLocation(name: "Paris", admin1: nil, country: "France",
                                       latitude: 48.8566, longitude: 2.3522,
                                       timezoneIdentifier: "Europe/Paris")
        func snapshot(weatherCode: Int = 61, isDay: Bool = true,
                      hourly: [WeatherHour] = [], daily: [WeatherDay] = []) -> WeatherSnapshot {
            WeatherSnapshot(
                location: location,
                fetchedAt: moment,
                timezoneIdentifier: "Europe/Paris",
                current: WeatherCurrent(
                    time: moment, temperature: 11.4, apparentTemperature: 9.8,
                    relativeHumidity: 72, precipitation: 0, weatherCode: weatherCode,
                    cloudCover: nil, pressureMSL: nil, windSpeed: 0, windDirection: 0,
                    windGust: nil, uvIndex: nil, isDay: isDay
                ),
                minutely15: [],
                hourly: hourly,
                daily: daily,
                airQuality: nil
            )
        }
        let nextHour = WeatherHour(time: moment.addingTimeInterval(3600), temperature: 12,
                                   apparentTemperature: 11, precipitationProbability: 40,
                                   precipitation: 0, weatherCode: 3, windSpeed: 0,
                                   isDay: true, uvIndex: nil, visibility: nil)
        let today = WeatherDay(date: moment, weatherCode: 61, temperatureMax: 13,
                               temperatureMin: 7, precipitationProbabilityMax: 60,
                               precipitationSum: 0, sunrise: nil, sunset: nil,
                               uvIndexMax: nil, windSpeedMax: nil)
        let forecast = snapshot(hourly: [nextHour], daily: [today])

        func reading(_ style: WeatherMenuBarStyle, of value: WeatherSnapshot) -> WeatherMenuBarReading {
            defaults.set(style.rawValue, forKey: DefaultsKey.weatherMenuBarStyle)
            return WeatherMenuBarReading(snapshot: value, preferences: .metric, defaults: defaults)
        }

        let rainSymbol = WeatherCondition.rain.symbolName(isDay: true)
        suite.expect(reading(.symbolOnly, of: forecast).menuBarSymbolName == rainSymbol
                        && reading(.symbolOnly, of: forecast).menuBarText == nil,
                     "symbol only shows the condition symbol")
        suite.expect(reading(.temperatureOnly, of: forecast).menuBarSymbolName == nil
                        && reading(.temperatureOnly, of: forecast).menuBarText == "11°",
                     "temperature only shows the reading without a symbol")
        suite.expect(reading(.symbolTemperature, of: forecast).menuBarSymbolName == rainSymbol
                        && reading(.symbolTemperature, of: forecast).menuBarText == "11°",
                     "symbol and temperature shows both")
        suite.expect(reading(.highLow, of: forecast).menuBarText == "13/7",
                     "high and low reads today's maximum and minimum")
        suite.expect(reading(.precipitationChance, of: forecast).menuBarSymbolName == rainSymbol
                        && reading(.precipitationChance, of: forecast).menuBarText == "40%",
                     "precipitation chance reads the next hour with a rain symbol")
        suite.expect(reading(.highLow, of: snapshot()).menuBarText == nil
                        && reading(.precipitationChance, of: snapshot()).menuBarText == nil,
                     "a forecast without daily or hourly slots leaves those styles empty")
        suite.expect(reading(.symbolTemperature, of: snapshot(weatherCode: 0, isDay: false)).menuBarSymbolName
                        == WeatherCondition.clear.symbolName(isDay: false),
                     "the menu bar symbol follows the day and night form")
        defaults.set("nonsense", forKey: DefaultsKey.weatherMenuBarStyle)
        suite.expect(WeatherMenuBarReading(snapshot: forecast, preferences: .metric, defaults: defaults).style
                        == .symbolTemperature,
                     "an unknown stored style falls back to symbol and temperature")
    }
}
