// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum AutoRaisePauseModifier: String, CaseIterable {
    case control, option, disabled

    static func sanitized(_ raw: String?) -> Self {
        Self(rawValue: raw ?? "") ?? .control
    }
}

struct AutoRaiseConfiguration: Equatable {
    static let delayRange = 0...2_000
    static let pollRange = 20...250
    static let movementRange = 0.0...20.0

    var delayMilliseconds: Int
    var pollMilliseconds: Int
    var requireMouseStop: Bool
    var movementThreshold: Double
    var pauseModifier: AutoRaisePauseModifier
    var invertPauseModifier: Bool
    var ignoreAfterSpaceChange: Bool
    var includeOnlyApps: Bool
    var appBundleIDs: Set<String>
    var ignoredTitlePatterns: [String]
    var stayFocusedBundleIDs: Set<String>
    var warpAfterTaskSwitch: Bool
    var warpX: Double
    var warpY: Double

    static func sanitized(delay: Int, poll: Int, requireMouseStop: Bool,
                          movementThreshold: Double, pauseModifier: String?,
                          invertPauseModifier: Bool, ignoreAfterSpaceChange: Bool,
                          includeOnlyApps: Bool, appBundleIDs: [String],
                          ignoredTitlePatterns: [String], stayFocusedBundleIDs: [String],
                          warpAfterTaskSwitch: Bool, warpX: Double, warpY: Double) -> Self {
        Self(delayMilliseconds: min(max(delay, delayRange.lowerBound), delayRange.upperBound),
             pollMilliseconds: min(max(poll, pollRange.lowerBound), pollRange.upperBound),
             requireMouseStop: requireMouseStop,
             movementThreshold: min(max(movementThreshold, movementRange.lowerBound), movementRange.upperBound),
             pauseModifier: .sanitized(pauseModifier),
             invertPauseModifier: invertPauseModifier,
             ignoreAfterSpaceChange: ignoreAfterSpaceChange,
             includeOnlyApps: includeOnlyApps,
             appBundleIDs: Set(appBundleIDs.filter { !$0.isEmpty }),
             ignoredTitlePatterns: ignoredTitlePatterns.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
             stayFocusedBundleIDs: Set(stayFocusedBundleIDs.filter { !$0.isEmpty }),
             warpAfterTaskSwitch: warpAfterTaskSwitch,
             warpX: min(max(warpX, 0), 1),
             warpY: min(max(warpY, 0), 1))
    }

    func allows(bundleID: String?) -> Bool {
        guard !appBundleIDs.isEmpty else { return !includeOnlyApps }
        guard let bundleID else { return !includeOnlyApps }
        let listed = appBundleIDs.contains(bundleID)
        return includeOnlyApps ? listed : !listed
    }

    func ignores(title: String?) -> Bool {
        guard let title else { return false }
        return ignoredTitlePatterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern,
                                                       options: [.caseInsensitive]) else { return false }
            let range = NSRange(title.startIndex..., in: title)
            return regex.firstMatch(in: title, range: range) != nil
        }
    }

    static func invalidPatterns(_ patterns: [String]) -> [String] {
        patterns.filter { (try? NSRegularExpression(pattern: $0)) == nil }
    }

    func warpPoint(in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + frame.width * warpX,
                y: frame.minY + frame.height * warpY)
    }
}

struct AutoRaiseHoverState: Equatable {
    private(set) var candidateWindowID: CGWindowID?
    private(set) var settledMilliseconds = 0

    mutating func reset() {
        candidateWindowID = nil
        settledMilliseconds = 0
    }

    /// Returns true exactly once when this candidate reaches its hover delay.
    mutating func sample(windowID: CGWindowID?, mouseMoved: Bool,
                         configuration: AutoRaiseConfiguration) -> Bool {
        guard let windowID else {
            reset()
            return false
        }
        if candidateWindowID != windowID {
            candidateWindowID = windowID
            settledMilliseconds = 0
        }
        if configuration.requireMouseStop, mouseMoved {
            settledMilliseconds = 0
            return false
        }
        if settledMilliseconds > configuration.delayMilliseconds { return false }
        settledMilliseconds += configuration.pollMilliseconds
        if settledMilliseconds >= configuration.delayMilliseconds {
            settledMilliseconds = configuration.delayMilliseconds + 1
            return true
        }
        return false
    }
}
