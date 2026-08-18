// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The mouse behaviors that can be told to leave an app alone (issue #358).
/// Both scrolling behaviors intentionally share one list; unrelated mouse
/// actions keep their own lists.
enum MouseExceptionScope: String, CaseIterable {
    case smoothScroll
    case scrollDirection
    case navigation
    case buttonShortcuts
    case middleClick

    var defaultsKey: String {
        switch self {
        case .smoothScroll, .scrollDirection: return DefaultsKey.mouseScrollingExceptions
        case .navigation: return DefaultsKey.mouseNavigationExceptions
        case .buttonShortcuts: return DefaultsKey.mouseButtonExceptions
        case .middleClick: return DefaultsKey.middleClickExceptions
        }
    }

    /// The feature the list belongs to, so a list is only ever consulted (and
    /// only ever shown) while its feature is installed and on.
    var feature: AppFeature {
        switch self {
        case .smoothScroll: return .smoothScroll
        case .scrollDirection: return .scrollInverter
        case .navigation: return .mouseNavigation
        case .buttonShortcuts: return .mouseButtonShortcuts
        case .middleClick: return .middleClick
        }
    }
}

/// The pure half of the mouse exceptions: which window answers for the app
/// being used, and how long an answer may be reused before the window server
/// is asked again.
enum MouseAppExceptionSupport {
    /// One on-screen window, reduced to what the decision needs.
    struct Window: Equatable {
        let frame: CGRect
        let layer: Int
        let alpha: Double
        let processID: Int32

        init(frame: CGRect, layer: Int, alpha: Double = 1, processID: Int32) {
            self.frame = frame
            self.layer = layer
            self.alpha = alpha
            self.processID = processID
        }
    }

    /// Ordinary windows sit at layer 0 and an app's floating panels at 3;
    /// both belong to the app the user is working in. Above that is the
    /// system's own furniture (Dock, menu bar, notifications) and below it
    /// are windows that live under every real one, so neither ever gets the
    /// wheel while an app window is there to take it.
    static let appWindowLayers = 0...3

    /// How long a resolved window keeps answering without asking the window
    /// server again. Measured on this Mac: one lookup costs about 190 us
    /// while re-checking the rectangle it produced costs about 2 ns, so a
    /// wheel spinning inside a single window pays the lookup twice a second
    /// instead of on every event.
    static let resolveLifetime: TimeInterval = 0.5

    /// The window a click or a wheel would reach at `point`. The list arrives
    /// front to back, so the first window containing the point wins; the
    /// app's own windows are skipped because its panels sit above whatever
    /// the pointer is really over.
    static func pointerWindow(in windows: [Window],
                              at point: CGPoint,
                              ownProcessID: Int32) -> Window? {
        windows.first { window in
            window.alpha > 0
                && appWindowLayers.contains(window.layer)
                && window.processID != ownProcessID
                && window.frame.contains(point)
        }
    }

    /// Whether the previous answer still applies. A window answers while the
    /// pointer stays inside it; "no window here" only applies while the
    /// pointer has not moved at all, so a wheel over the desktop cannot pin a
    /// stale verdict to the whole screen. Both expire with `resolveLifetime`,
    /// which is what picks up a window that opened, closed or moved under a
    /// resting pointer.
    static func cacheHolds(region: CGRect?,
                           resolvedPoint: CGPoint,
                           resolvedAt: TimeInterval,
                           point: CGPoint,
                           now: TimeInterval) -> Bool {
        guard now >= resolvedAt, now - resolvedAt < resolveLifetime else { return false }
        guard let region else { return point == resolvedPoint }
        return region.contains(point)
    }

    static func isExcepted(_ bundleID: String?, exceptions: Set<String>) -> Bool {
        guard let bundleID, !exceptions.isEmpty else { return false }
        return exceptions.contains(bundleID)
    }

    static func sourceProcessID(_ rawValue: Int64) -> Int32? {
        guard rawValue > 0 else { return nil }
        return Int32(exactly: rawValue)
    }

    static func isExcepted(_ bundleIDs: [String], exceptions: Set<String>) -> Bool {
        bundleIDs.contains(where: exceptions.contains)
    }

    /// Immutable answer the scroll taps consult. Built under the exceptions
    /// lock so a dedicated tap thread never races the main-thread reload path.
    struct LookupSnapshot: Equatable {
        var lookups: [MouseExceptionScope: Set<String>]
        var sourceProcessIDs: [MouseExceptionScope: Set<Int32>]
        var allEmpty: Bool
        var cachedBundleID: String?
        var cachedRegion: CGRect?
        var cachedPoint: CGPoint
        var cachedAt: TimeInterval

        static let empty = LookupSnapshot(lookups: [:],
                                          sourceProcessIDs: [:],
                                          allEmpty: true,
                                          cachedBundleID: nil,
                                          cachedRegion: nil,
                                          cachedPoint: .zero,
                                          cachedAt: -1)
    }

    /// Resolves whether a scope excludes the pointer target using only the
    /// snapshot and already-known process identifiers — no window server.
    static func excludes(scope: MouseExceptionScope,
                         snapshot: LookupSnapshot,
                         sourceProcessID: Int64,
                         targetProcessID: Int64,
                         targetBundleID: String?,
                         pointerBundleID: String?) -> Bool {
        guard let exceptions = snapshot.lookups[scope], !exceptions.isEmpty else {
            return false
        }
        if let pid = Self.sourceProcessID(sourceProcessID),
           snapshot.sourceProcessIDs[scope]?.contains(pid) == true {
            return true
        }
        if let pid = Self.sourceProcessID(targetProcessID),
           snapshot.sourceProcessIDs[scope]?.contains(pid) == true {
            return true
        }
        if isExcepted(targetBundleID, exceptions: exceptions) {
            return true
        }
        return isExcepted(pointerBundleID, exceptions: exceptions)
    }
}
