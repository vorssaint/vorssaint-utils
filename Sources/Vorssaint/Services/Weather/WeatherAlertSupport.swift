// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One active National Weather Service alert for a point in the United States.
/// The fields a banner shows are kept; the raw payload can omit most of them.
struct WeatherAlert: Codable, Equatable, Identifiable {
    let id: String
    let event: String
    let severity: WeatherAlertSeverity
    let headline: String
    let description: String
    let instruction: String?
    let onset: Date?
    let ends: Date?
    let expires: Date?
    let area: String
    let url: URL?
}

/// The NWS severity ladder, ranked as the service words it. An unrecognised
/// value sorts below every known one instead of being dropped.
enum WeatherAlertSeverity: String, Codable, CaseIterable {
    case extreme, severe, moderate, minor, unknown

    init(rawValue: String?) {
        switch rawValue?.lowercased() {
        case "extreme": self = .extreme
        case "severe": self = .severe
        case "moderate": self = .moderate
        case "minor": self = .minor
        default: self = .unknown
        }
    }

    var rank: Int {
        switch self {
        case .extreme: return 4
        case .severe: return 3
        case .moderate: return 2
        case .minor: return 1
        case .unknown: return 0
        }
    }
}

extension WeatherAlertSeverity: Comparable {
    static func < (lhs: WeatherAlertSeverity, rhs: WeatherAlertSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// The NWS active-alert request, its GeoJSON decoding and the US coordinate
/// test the service gates on. Pure Foundation so tests need no network.
enum WeatherAlertSupport {
    static let activeBaseURL = "https://api.weather.gov/alerts/active"
    static let acceptHeader = "application/geo+json"

    /// `https://api.weather.gov/alerts/active?point=lat,lon`
    static func activeURL(latitude: Double, longitude: Double) -> URL? {
        guard var components = URLComponents(string: activeBaseURL) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "point", value: "\(coordinate(latitude)),\(coordinate(longitude))"),
        ]
        return components.url
    }

    /// A URL is a wire format, not on-screen text: its decimal point must never
    /// follow a region's comma.
    private static func coordinate(_ value: Double) -> String {
        String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    // MARK: Decoding

    /// Reads the `features[].properties` objects of an NWS GeoJSON reply.
    /// Features without an id or event are skipped; a missing headline falls
    /// back to the event. A payload that cannot be read yields no alerts.
    static func decodeAlerts(_ data: Data) -> [WeatherAlert] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let features = root["features"] as? [Any]
        else { return [] }
        return features.compactMap { feature in
            guard let feature = feature as? [String: Any],
                  let properties = feature["properties"] as? [String: Any]
            else { return nil }
            guard let id = nonEmpty(string(properties["id"])),
                  let event = nonEmpty(string(properties["event"]))
            else { return nil }
            return WeatherAlert(
                id: id,
                event: event,
                severity: WeatherAlertSeverity(rawValue: string(properties["severity"])),
                headline: nonEmpty(string(properties["headline"])) ?? event,
                description: string(properties["description"]) ?? "",
                instruction: nonEmpty(string(properties["instruction"])),
                onset: date(properties["onset"]),
                ends: date(properties["ends"]),
                expires: date(properties["expires"]),
                area: string(properties["areaDesc"]) ?? "",
                url: nonEmpty(string(feature["id"])).flatMap(URL.init(string:))
                    ?? nonEmpty(string(properties["@id"])).flatMap(URL.init(string:))
            )
        }
    }

    /// Highest severity first, then the soonest onset; an alert without a start
    /// time sorts after the ones that have one.
    static func sorted(_ alerts: [WeatherAlert]) -> [WeatherAlert] {
        alerts.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            switch (lhs.onset, rhs.onset) {
            case let (left?, right?): return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return false
            }
        }
    }

    // MARK: Region

    /// Whether an NWS alert is worth asking for. Bounding boxes cover the
    /// contiguous states, Alaska, Hawaii and Puerto Rico.
    // shortcut: boxes, so a few Canadian and Mexican border cities count as US;
    // upgrade to a polygon if a wrong-region request ever matters.
    static func isUSCoordinate(latitude: Double, longitude: Double) -> Bool {
        regions.contains { region in
            region.latitude.contains(latitude) && region.longitude.contains(longitude)
        }
    }

    private static let regions: [(latitude: ClosedRange<Double>, longitude: ClosedRange<Double>)] = [
        (24.0...49.5, -125.0 ... -66.5),   // contiguous United States
        (51.0...72.0, -170.0 ... -129.0),  // Alaska
        (18.8...22.6, -160.5 ... -154.5),  // Hawaii
        (17.8...18.7, -67.4 ... -65.1),    // Puerto Rico
    ]

    // MARK: Dates

    private static let iso8601 = ISO8601DateFormatter()
    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func date(_ value: Any?) -> Date? {
        guard let raw = nonEmpty(string(value)) else { return nil }
        return iso8601.date(from: raw) ?? iso8601Fractional.date(from: raw)
    }

    // MARK: JSON helpers

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}
