// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ScreenshotShareDuration: Int, CaseIterable, Codable, Identifiable {
    case oneHour = 3_600
    case sixHours = 21_600
    case twentyFourHours = 86_400

    var id: Int { rawValue }

    func title(_ strings: ScreenshotFeatureStrings) -> String {
        switch self {
        case .oneHour: strings.shareOneHour
        case .sixHours: strings.shareSixHours
        case .twentyFourHours: strings.shareTwentyFourHours
        }
    }
}

struct ScreenshotShareRecord: Codable, Equatable, Identifiable {
    let id: String
    let endpoint: URL
    let expiresAt: Date
    let deleteToken: String

    var url: URL {
        endpoint.appendingPathComponent("s", isDirectory: true)
            .appendingPathComponent(id, isDirectory: false)
    }
}

struct ScreenshotShareResponse: Decodable {
    let id: String
    let viewPath: String
    let expiresAt: String
    let deleteToken: String
}

enum ScreenshotSharingSupport {
    static let productionEndpoint = URL(string: "https://screenshots.vorssaint.com")!
    static let developerBundleIdentifier = "com.vorssaint.utils.dev"
    static let maximumUploadBytes = 25 * 1_024 * 1_024

    static func endpoint(bundleIdentifier: String?, developerOverride: String?) -> URL {
        guard bundleIdentifier == developerBundleIdentifier,
              let developerOverride,
              let candidate = sanitizedEndpoint(developerOverride)
        else { return productionEndpoint }
        return candidate
    }

    static func sanitizedEndpoint(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else { return nil }
        components.scheme = "https"
        components.path = ""
        return components.url
    }

    static func uploadURL(endpoint: URL, duration: ScreenshotShareDuration) -> URL? {
        let base = endpoint.appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent("screenshots", isDirectory: false)
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "expiresIn",
                                               value: String(duration.rawValue))]
        return components.url
    }

    static func record(response: ScreenshotShareResponse,
                       endpoint: URL,
                       now: Date = Date()) -> ScreenshotShareRecord? {
        guard let expiresAt = expirationDate(response.expiresAt) else { return nil }
        guard response.id.range(of: "^[A-Za-z0-9_-]{32}$",
                                options: .regularExpression) != nil,
              response.deleteToken.range(of: "^[A-Za-z0-9_-]{43}$",
                                         options: .regularExpression) != nil,
              response.viewPath == "/s/\(response.id)",
              expiresAt > now,
              expiresAt <= now.addingTimeInterval(24 * 60 * 60 + 5 * 60)
        else { return nil }
        return ScreenshotShareRecord(id: response.id,
                                     endpoint: endpoint,
                                     expiresAt: expiresAt,
                                     deleteToken: response.deleteToken)
    }

    static func expirationDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
