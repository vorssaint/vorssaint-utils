// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One RainViewer radar frame. `path` is the tile directory the frame's images
/// live under, and it is also what names the frame.
struct WeatherRadarFrame: Equatable, Identifiable, Sendable {
    let time: Date
    let path: String

    var id: String { path }
}

/// The past radar frames RainViewer publishes, plus the tile host they are
/// served from. Pure values so the sheet renders them without a network.
struct WeatherRadarMaps: Equatable, Sendable {
    let host: String
    let frames: [WeatherRadarFrame]
    let generated: Date?
}

/// The RainViewer public endpoint, its tolerant decoding and the tile URL the
/// map overlay asks for. Pure Foundation so tests need no network or MapKit.
enum WeatherRadarSupport {
    static let mapsURL = URL(string: "https://api.rainviewer.com/public/weather-maps.json")!
    static let attributionURL = URL(string: "https://www.rainviewer.com/api.html")!
    /// RainViewer's free tiles stop here; the map overzooms the last level.
    static let maximumZoom = 7

    /// Reads `radar.past`, keeping the frames that carry both a time and a
    /// path. A reply without a tile host or one usable frame is not worth
    /// showing, so it decodes to nil instead of an empty map.
    static func decodeMaps(_ data: Data) -> WeatherRadarMaps? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let host = nonEmptyString(root["host"]),
              host.hasPrefix("https://"),
              let radar = root["radar"] as? [String: Any],
              let past = radar["past"] as? [Any]
        else { return nil }

        let frames = past.compactMap { entry -> WeatherRadarFrame? in
            guard let values = entry as? [String: Any],
                  let seconds = seconds(values["time"]),
                  let path = nonEmptyString(values["path"]),
                  path.hasPrefix("/")
            else { return nil }
            return WeatherRadarFrame(time: Date(timeIntervalSince1970: seconds), path: path)
        }.sorted { $0.time < $1.time }
        guard !frames.isEmpty else { return nil }

        return WeatherRadarMaps(
            host: host.hasSuffix("/") ? String(host.dropLast()) : host,
            frames: frames,
            generated: seconds(root["generated"]).map { Date(timeIntervalSince1970: $0) }
        )
    }

    /// `{host}{path}/256/{z}/{x}/{y}/2/1_1.png` — color scheme 2, smoothing on.
    static func tileURL(host: String, path: String, z: Int, x: Int, y: Int) -> URL? {
        guard !host.isEmpty, path.hasPrefix("/"),
              (0...maximumZoom).contains(z), x >= 0, y >= 0
        else { return nil }
        return URL(string: "\(host)\(path)/256/\(z)/\(x)/\(y)/2/1_1.png")
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return string
    }

    private static func seconds(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        return number.doubleValue
    }
}
