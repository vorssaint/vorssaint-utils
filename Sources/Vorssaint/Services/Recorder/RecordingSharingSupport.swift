// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum RecordingShareDuration: Int, CaseIterable, Codable, Identifiable {
    case oneHour = 3_600
    case sixHours = 21_600

    var id: Int { rawValue }

    func title(_ strings: ScreenshotFeatureStrings) -> String {
        switch self {
        case .oneHour: strings.shareOneHour
        case .sixHours: strings.shareSixHours
        }
    }
}

struct RecordingShareRecord: Codable, Equatable, Identifiable {
    let id: String
    let endpoint: URL
    let expiresAt: Date
    let deleteToken: String

    var url: URL {
        endpoint.appendingPathComponent("s", isDirectory: true)
            .appendingPathComponent(id, isDirectory: false)
    }
}

struct RecordingShareResponse: Decodable {
    let id: String
    let viewPath: String
    let expiresAt: String
    let deleteToken: String
}

enum RecordingSharingSupport {
    struct EncodingPlan: Equatable {
        let size: CGSize
        let frameRate: Int
        let videoBitRate: Int
        let audioBitRate: Int
    }

    static let productionEndpoint = URL(string: "https://screenshots.vorssaint.com")!
    static let developerBundleIdentifier = "com.vorssaint.utils.dev"
    /// Leaves transport headroom below the public 100 MB request ceiling.
    static let maximumUploadBytes = 96_000_000
    static let targetUploadBytes = 90_000_000
    static let maximumEdge: CGFloat = 1_920
    static let minimumVideoBitRate = 350_000
    static let audioBitRate = 128_000

    static func endpoint(bundleIdentifier: String?, developerOverride: String?) -> URL {
        guard bundleIdentifier == developerBundleIdentifier,
              let developerOverride,
              let candidate = ScreenshotSharingSupport.sanitizedEndpoint(developerOverride)
        else { return productionEndpoint }
        return candidate
    }

    static func uploadURL(endpoint: URL, duration: RecordingShareDuration) -> URL? {
        let base = endpoint.appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: false)
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "expiresIn",
                                               value: String(duration.rawValue))]
        return components.url
    }

    static func record(response: RecordingShareResponse,
                       endpoint: URL,
                       now: Date = Date()) -> RecordingShareRecord? {
        guard let expiresAt = ScreenshotSharingSupport.expirationDate(response.expiresAt),
              response.id.range(of: "^[A-Za-z0-9_-]{32}$",
                                options: .regularExpression) != nil,
              response.deleteToken.range(of: "^[A-Za-z0-9_-]{43}$",
                                         options: .regularExpression) != nil,
              response.viewPath == "/s/\(response.id)",
              expiresAt > now,
              expiresAt <= now.addingTimeInterval(6 * 60 * 60 + 5 * 60)
        else { return nil }
        return RecordingShareRecord(id: response.id,
                                    endpoint: endpoint,
                                    expiresAt: expiresAt,
                                    deleteToken: response.deleteToken)
    }

    static func encodingPlan(duration: Double,
                             baseSize: CGSize,
                             sourceFrameRate: Int,
                             hasAudio: Bool,
                             bitRateScale: Double = 1) -> EncodingPlan? {
        guard duration.isFinite, duration > 0,
              baseSize.width.isFinite, baseSize.height.isFinite,
              baseSize.width > 0, baseSize.height > 0,
              bitRateScale.isFinite, bitRateScale > 0
        else { return nil }

        let frameRate = min(30, max(1, sourceFrameRate))
        let bounded = limitedSize(baseSize, maximumEdge: maximumEdge)
        let audio = hasAudio ? audioBitRate : 0
        let available = Int((Double(targetUploadBytes) * 8 * 0.94 / duration).rounded(.down))
            - audio
        let qualityCeiling = Int((Double(bounded.width * bounded.height)
            * Double(frameRate) * 0.085).rounded())
        let video = Int(Double(min(available, max(800_000, qualityCeiling)))
            * min(1, bitRateScale))
        guard video >= minimumVideoBitRate else { return nil }

        let qualityPixels = Double(video) / (Double(frameRate) * 0.055)
        let currentPixels = Double(bounded.width * bounded.height)
        let scale = min(1, sqrt(qualityPixels / max(1, currentPixels)))
        let minimumScale = min(1, 640 / max(bounded.width, bounded.height))
        let size = RecorderSupport.evenSize(CGSize(width: bounded.width * max(scale, minimumScale),
                                                   height: bounded.height * max(scale, minimumScale)))
        return EncodingPlan(size: size,
                            frameRate: frameRate,
                            videoBitRate: video,
                            audioBitRate: audio)
    }

    static func retryScale(current: Double, actualBytes: Int) -> Double? {
        guard current.isFinite, current > 0, actualBytes > maximumUploadBytes else { return nil }
        let next = current * Double(targetUploadBytes) / Double(actualBytes) * 0.94
        return next.isFinite && next > 0 ? min(current * 0.9, next) : nil
    }

    private static func limitedSize(_ size: CGSize, maximumEdge: CGFloat) -> CGSize {
        let edge = max(size.width, size.height)
        guard edge > maximumEdge else { return RecorderSupport.evenSize(size) }
        let scale = maximumEdge / edge
        return RecorderSupport.evenSize(CGSize(width: size.width * scale,
                                               height: size.height * scale))
    }
}
