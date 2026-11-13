// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Text for the Weather feature, its hub row and the surfaces built on it.
/// Each language lives in its own WeatherStrings+<language>.swift file and
/// starts from the English copy, overriding every user-facing field.
struct WeatherStrings {
    // Feature and hub
    var title: String
    var description: String
    var groupTitle: String
    var sectionTitle: String

    // Conditions
    var conditionClear: String
    var conditionMainlyClear: String
    var conditionPartlyCloudy: String
    var conditionOvercast: String
    var conditionFog: String
    var conditionDrizzle: String
    var conditionRain: String
    var conditionHeavyRain: String
    var conditionFreezingRain: String
    var conditionSnow: String
    var conditionSnowShowers: String
    var conditionThunderstorm: String
    var conditionHail: String
    var conditionUnknown: String

    // Units
    var temperatureCelsius: String
    var temperatureFahrenheit: String
    var windKph: String
    var windMph: String
    var windMps: String
    var windKnots: String
    var precipitationMillimeters: String
    var precipitationInches: String
    var pressureHectopascals: String
    var pressureInchesOfMercury: String
    var distanceKilometers: String
    var distanceMiles: String

    // Load state and attribution
    var loading: String
    var loadFailed: String
    var staleNotice: String
    var locationRequired: String
    var updatedAtFormat: String      // "Updated %@"
    var attribution: String

    // Locations
    var location: String
    var currentLocation: String
    var useCurrentLocation: String
    var searchLocation: String
    var searchPrompt: String
    var searchNoResults: String

    // Detail labels
    var feelsLike: String
    var humidity: String
    var windLabel: String
    var precipitationLabel: String
    var pressureLabel: String
    var uvIndexLabel: String
    var sunriseLabel: String
    var sunsetLabel: String
    var airQualityLabel: String
    var highLabel: String
    var lowLabel: String

    // Menu bar styles
    var menuBarSymbolOnly: String
    var menuBarTemperatureOnly: String
    var menuBarSymbolTemperature: String
    var menuBarHighLow: String
    var menuBarPrecipitationChance: String

    // Surface headings and actions. Defaults keep older call sites source
    // compatible while the localization pass fills each language.
    var hourlyTitle = "Next 24 hours"
    var dailyTitle = "7-day forecast"
    var detailsTitle = "Details"
    var graphsTitle = "Graphs"
    var radarTitle = "Radar"
    var refresh = "Refresh"
    var retry = "Try again"
    var showInPanel = "Show in panel"
    var showInNotch = "Show in Dynamic Island"
    var showInMenuBar = "Show in menu bar"
    var menuBarStyle = "Menu bar style"
    var unitsTitle = "Units"
    var gustsLabel = "Gusts"
    var cloudCoverLabel = "Cloud cover"
    var visibilityLabel = "Visibility"
    var dewPointLabel = "Dew point"
    var precipitationChanceLabel = "Chance of precipitation"
    var todayLabel = "Today"
    var nowLabel = "Now"
    var noLocationTitle = "Choose a location"
    var searchResultsTitle = "Matching places"
    var dataSourceTitle = "Data source"
    var radarUnavailable = "Radar is not available yet"
    var refreshInterval = "Every 15 minutes"
    var locationDenied = "Location access is not available"
    var locationTimedOut = "Location took too long to respond"
    var locationInProgress = "Finding the current location is already in progress"
    var alertsTitle = "Weather alerts"
    var alertsUSOnly = "US only. Provided by the National Weather Service."
    var alertsEnable = "Show US weather alerts"
    var alertsExpiresFormat = "Until %@"

    func name(for condition: WeatherCondition) -> String {
        switch condition {
        case .clear: return conditionClear
        case .mainlyClear: return conditionMainlyClear
        case .partlyCloudy: return conditionPartlyCloudy
        case .overcast: return conditionOvercast
        case .fog: return conditionFog
        case .drizzle: return conditionDrizzle
        case .rain: return conditionRain
        case .heavyRain: return conditionHeavyRain
        case .freezingRain: return conditionFreezingRain
        case .snow: return conditionSnow
        case .snowShowers: return conditionSnowShowers
        case .thunderstorm: return conditionThunderstorm
        case .hail: return conditionHail
        case .unknown: return conditionUnknown
        }
    }

    func menuBarStyle(_ style: WeatherMenuBarStyle) -> String {
        switch style {
        case .symbolOnly: return menuBarSymbolOnly
        case .temperatureOnly: return menuBarTemperatureOnly
        case .symbolTemperature: return menuBarSymbolTemperature
        case .highLow: return menuBarHighLow
        case .precipitationChance: return menuBarPrecipitationChance
        }
    }
}

extension FeatureStrings {
    static func weather(_ language: AppLanguage) -> WeatherStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension WeatherStrings {
    static let enUS = WeatherStrings(
        title: "Weather",
        description: "Current conditions and the forecast, in the menu bar and the panel",
        groupTitle: "Weather",
        sectionTitle: "Forecast",
        conditionClear: "Clear",
        conditionMainlyClear: "Mainly clear",
        conditionPartlyCloudy: "Partly cloudy",
        conditionOvercast: "Overcast",
        conditionFog: "Fog",
        conditionDrizzle: "Drizzle",
        conditionRain: "Rain",
        conditionHeavyRain: "Heavy rain",
        conditionFreezingRain: "Freezing rain",
        conditionSnow: "Snow",
        conditionSnowShowers: "Snow showers",
        conditionThunderstorm: "Thunderstorm",
        conditionHail: "Hail",
        conditionUnknown: "Unknown",
        temperatureCelsius: "Celsius",
        temperatureFahrenheit: "Fahrenheit",
        windKph: "Kilometers per hour",
        windMph: "Miles per hour",
        windMps: "Meters per second",
        windKnots: "Knots",
        precipitationMillimeters: "Millimeters",
        precipitationInches: "Inches",
        pressureHectopascals: "Hectopascals",
        pressureInchesOfMercury: "Inches of mercury",
        distanceKilometers: "Kilometers",
        distanceMiles: "Miles",
        loading: "Loading weather",
        loadFailed: "Weather could not be loaded",
        staleNotice: "Showing the last saved forecast",
        locationRequired: "Choose a location to see the weather",
        updatedAtFormat: "Updated %@",
        attribution: "Weather data by Open-Meteo",
        location: "Location",
        currentLocation: "Current location",
        useCurrentLocation: "Use current location",
        searchLocation: "Search for a city",
        searchPrompt: "City or postal code",
        searchNoResults: "No matching places",
        feelsLike: "Feels like",
        humidity: "Humidity",
        windLabel: "Wind",
        precipitationLabel: "Precipitation",
        pressureLabel: "Pressure",
        uvIndexLabel: "UV index",
        sunriseLabel: "Sunrise",
        sunsetLabel: "Sunset",
        airQualityLabel: "Air quality",
        highLabel: "High",
        lowLabel: "Low",
        menuBarSymbolOnly: "Symbol only",
        menuBarTemperatureOnly: "Temperature only",
        menuBarSymbolTemperature: "Symbol and temperature",
        menuBarHighLow: "High and low",
        menuBarPrecipitationChance: "Precipitation chance"
    )
}
