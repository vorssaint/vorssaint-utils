// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

enum ScrollHorizontalModifier: String, CaseIterable {
    case shift, option, control, command

    init(storageValue: String?) {
        self = storageValue.flatMap(Self.init(rawValue:)) ?? .shift
    }

    var flag: CGEventFlags {
        switch self {
        case .shift: return .maskShift
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .command: return .maskCommand
        }
    }
}

enum ScrollZoomMode: String, CaseIterable {
    case keyboard, pinch
}

enum ScrollZoomModifier: String, CaseIterable {
    case none, shift, option, control, command

    init(storageValue: String?) {
        self = storageValue.flatMap(Self.init(rawValue:)) ?? .none
    }

    var modifier: ScrollHorizontalModifier? {
        ScrollHorizontalModifier(rawValue: rawValue)
    }
}

enum ScrollWheelAxis {
    case vertical, horizontal
}

enum ScrollZoomEffect {
    case zoom, pinch
}

struct ScrollZoomAction {
    let effect: ScrollZoomEffect
    let axis: ScrollWheelAxis
    let modifier: ScrollHorizontalModifier
    let delta: Double
}

struct ScrollZoomPreferences {
    let verticalZoom: ScrollHorizontalModifier?
    let horizontalZoom: ScrollHorizontalModifier?
    let pinchZoom: ScrollHorizontalModifier?

    var isEnabled: Bool {
        verticalZoom != nil || horizontalZoom != nil || pinchZoom != nil
    }

    init(isAvailable: Bool, boolFor: (String) -> Bool, stringFor: (String) -> String?) {
        func modifier(_ enabled: String, _ key: String) -> ScrollHorizontalModifier? {
            isAvailable && boolFor(enabled) ? ScrollZoomModifier(storageValue: stringFor(key)).modifier : nil
        }
        let candidates = [
            modifier(DefaultsKey.verticalZoomEnabled, DefaultsKey.verticalZoomModifier),
            modifier(DefaultsKey.horizontalZoomEnabled, DefaultsKey.horizontalZoomModifier),
            modifier(DefaultsKey.pinchZoomEnabled, DefaultsKey.pinchZoomModifier),
        ]
        var assigned: [ScrollHorizontalModifier] = []
        let unique = candidates.map { candidate -> ScrollHorizontalModifier? in
            guard let candidate, !assigned.contains(candidate) else { return nil }
            assigned.append(candidate)
            return candidate
        }
        verticalZoom = unique[0]
        horizontalZoom = unique[1]
        pinchZoom = unique[2]
    }

    func action(for event: CGEvent) -> ScrollZoomAction? {
        let choices: [(ScrollZoomEffect, ScrollWheelAxis, ScrollHorizontalModifier?)] = [
            (.zoom, .vertical, verticalZoom), (.zoom, .horizontal, horizontalZoom),
            (.pinch, .vertical, pinchZoom), (.pinch, .horizontal, pinchZoom),
        ]
        for (effect, axis, modifier) in choices {
            if let modifier, let delta = ScrollWheelSupport.zoomDelta(event, modifier: modifier, axis: axis) {
                return ScrollZoomAction(effect: effect, axis: axis, modifier: modifier, delta: delta)
            }
        }
        return nil
    }
}

/// Both independently installed direction features share one tap. Resolve their
/// effective settings once so raw and smoothed wheels honor removal identically.
struct ScrollDirectionPreferences {
    let invertVertical: Bool
    let invertHorizontal: Bool
    let horizontalModifier: ScrollHorizontalModifier?
    let zoom: ScrollZoomPreferences

    var isEnabled: Bool {
        invertVertical || invertHorizontal || horizontalModifier != nil || zoom.isEnabled
    }

    init(isAvailable: (AppFeature) -> Bool,
         boolFor: (String) -> Bool,
         stringFor: (String) -> String?) {
        invertVertical = isAvailable(.scrollInverter) && boolFor(DefaultsKey.scrollInverterEnabled)
        invertHorizontal = isAvailable(.scrollInverter) && boolFor(DefaultsKey.scrollInverterHorizontalEnabled)
        horizontalModifier = isAvailable(.scrollHorizontal) && boolFor(DefaultsKey.scrollHorizontalEnabled)
            ? ScrollHorizontalModifier(storageValue: stringFor(DefaultsKey.scrollHorizontalModifier)) : nil
        zoom = ScrollZoomPreferences(isAvailable: isAvailable(.scrollZoom),
                                     boolFor: boolFor, stringFor: stringFor)
    }

    init(defaults: UserDefaults = .standard) {
        self.init(isAvailable: { defaults.bool(forKey: $0.availabilityKey) },
                  boolFor: { defaults.bool(forKey: $0) },
                  stringFor: { defaults.string(forKey: $0) })
    }
}

struct ScrollWheelEventTraits: Equatable {
    let isContinuous: Bool
    let momentumPhase: Int64
    let scrollPhase: Int64
    let scrollCount: Int64
}

struct ScrollWheelInversionPlan: Equatable {
    let vertical: Bool
    let horizontal: Bool
}

/// Tells mouse wheels apart from touch devices, shared by the scroll
/// inverter and smooth scrolling so both features classify events the same
/// way: discrete events are wheels; events flagged continuous are wheels
/// only when they carry no gesture phase at all (how some mouse drivers
/// report their wheels).
enum ScrollWheelSupport {
    /// How long after a gesture-phased event a phaseless continuous event is
    /// still attributed to the same touch device.
    static let touchGestureGraceSeconds: TimeInterval = 1.0

    /// Marks the smooth glide so neither feature handles it twice. Events a
    /// process posts come back through that same process's taps (measured at
    /// every tap location), so without the mark the inverter would turn the
    /// glide around again and cancel the flip smooth scrolling already
    /// applied.
    static let syntheticTag: Int64 = 0x564F5253  // "VORS"
    /// A redirected vertical wheel is not a physical side wheel. The session
    /// tap uses this marker to leave it out of side-wheel shortcut matching.
    static let horizontalRedirectTag: Int64 = 0x564F5248  // "VORH"

    /// Points in one scroll line. The window server measures the fixed-point
    /// delta in lines, so an event that moved forty points reports four;
    /// replaying that number as pixels would travel a tenth of the distance.
    static let pointsPerLine: Double = 10

    /// Called only after wheel classification and the scroll-direction exception
    /// check. Consume the modifier so the receiving app cannot redirect or zoom
    /// the transformed event a second time. Other shortcut combinations keep
    /// their native meaning, as do wheels already supplying a horizontal axis.
    @discardableResult
    static func redirectVerticalScroll(_ event: CGEvent, modifier: ScrollHorizontalModifier,
                                       targetsOwnWindow: @autoclosure () -> Bool = false) -> Bool {
        let shortcutFlags: CGEventFlags = [.maskShift, .maskAlternate, .maskControl, .maskCommand]
        guard event.flags.intersection(shortcutFlags) == modifier.flag else { return false }

        guard isVerticalOnly(event) else { return false }
        // Our capture/editor windows use these same modifiers for their own
        // wheel gestures. Resolve the target only for a tick we would redirect.
        guard !targetsOwnWindow() else { return false }

        moveVerticalToHorizontal(event)
        event.flags.remove(modifier.flag)
        event.setIntegerValueField(.eventSourceUserData, value: horizontalRedirectTag)
        return true
    }

    /// Movement on the vertical axis only, as a plain mouse wheel sends it.
    static func isVerticalOnly(_ event: CGEvent) -> Bool {
        (event.getIntegerValueField(.scrollWheelEventDeltaAxis1) != 0
            || event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) != 0
            || event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) != 0)
            && event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 0
            && event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 0
            && event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) == 0
    }

    /// The signed distance from either wheel axis, but only while the selected
    /// modifier is the sole shortcut modifier. This keeps ordinary app
    /// shortcuts and native two-axis scrolling intact.
    static func zoomDelta(_ event: CGEvent, modifier: ScrollHorizontalModifier,
                          axis: ScrollWheelAxis) -> Double? {
        let shortcutFlags: CGEventFlags = [.maskShift, .maskAlternate, .maskControl, .maskCommand]
        guard event.flags.intersection(shortcutFlags) == modifier.flag else { return nil }
        let fields: (CGEventField, CGEventField, CGEventField) = axis == .vertical
            ? (.scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1)
            : (.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2)
        let line = event.getIntegerValueField(fields.0)
        let point = event.getDoubleValueField(fields.1)
        let fixed = event.getDoubleValueField(fields.2)
        return zoomDelta(point: point, fixed: fixed, line: line)
    }

    static func zoomDelta(point: Double, fixed: Double, line: Int64) -> Double? {
        if point != 0 { return point }
        if fixed != 0 { return fixed }
        return line == 0 ? nil : Double(line)
    }

    static func zoomDelta(_ delta: Double, axis: ScrollWheelAxis,
                          invertVertical: Bool, invertHorizontal: Bool) -> Double {
        switch axis {
        case .vertical: return invertVertical ? -delta : delta
        case .horizontal: return invertHorizontal ? -delta : delta
        }
    }

    /// Moves a vertical-only event to the horizontal axis, keeping its sign
    /// as Shift does.
    static func moveVerticalToHorizontal(_ event: CGEvent) {
        let line = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let point = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let fixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        // Line writes can rederive pixel fields; restore the captured precision
        // only after both line axes have been written.
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: line)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixed)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: point)
    }

    /// A mouse wheel only turns vertically, so a strip that scrolls only
    /// sideways could not be moved with one. The wheel moves the strip when
    /// nothing around it scrolls down; a list around it keeps the wheel.
    static func wheelMovesStripSideways(stripScrollsHorizontally: Bool, stripScrollsVertically: Bool,
                                        enclosingScrollsVertically: Bool) -> Bool {
        stripScrollsHorizontally && !stripScrollsVertically && !enclosingScrollsVertically
    }

    /// The raw wheel path uses the same redirection as smoothing, then applies
    /// inversion to the axis the user will actually scroll.
    static func applyDirection(to event: CGEvent, isContinuous: Bool,
                               invertVertical: Bool, invertHorizontal: Bool,
                               horizontalModifier: ScrollHorizontalModifier?,
                               targetsOwnWindow: @autoclosure () -> Bool = false) {
        let redirected = event.getIntegerValueField(.eventSourceUserData) == horizontalRedirectTag
            || (horizontalModifier.map {
                redirectVerticalScroll(event, modifier: $0, targetsOwnWindow: targetsOwnWindow())
            } ?? false)
        // Capture both axes before any set: writing a line delta makes the
        // system rederive its point and fixed-point fields.
        let verticalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let verticalPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let verticalFixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let horizontalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let horizontalPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let horizontalFixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        let hasVerticalMovement = verticalLine != 0 || verticalPoint != 0 || verticalFixedPoint != 0
        let hasHorizontalMovement = horizontalLine != 0
            || horizontalPoint != 0
            || horizontalFixedPoint != 0
        let plan = ScrollWheelSupport.inversionPlan(
            hasVerticalMovement: hasVerticalMovement,
            hasHorizontalMovement: hasHorizontalMovement,
            shiftRedirectsVertical: !isContinuous && event.flags.contains(.maskShift),
            invertVertical: invertVertical,
            invertHorizontal: invertHorizontal
        )
        if plan.vertical {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -verticalLine)
            if isContinuous || redirected {
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -verticalPoint)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -verticalFixedPoint)
            }
        }
        if plan.horizontal {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -horizontalLine)
            if isContinuous || redirected {
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -horizontalPoint)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -horizontalFixedPoint)
            }
        }
    }

    /// The list is front to back in Quartz coordinates. Do not restrict layers:
    /// capture overlays sit above ordinary windows. An external window in front
    /// must stop the search instead of exposing one of our windows behind it.
    static func targetsOwnWindow(in windows: [[String: Any]], at point: CGPoint,
                                 ownProcessID: Int32,
                                 clickThroughWindowIDs: Set<CGWindowID>) -> Bool {
        ScrollWheelTargetCache.windows(in: windows, ownProcessID: ownProcessID,
            clickThroughWindowIDs: clickThroughWindowIDs).first { $0.frame.contains(point) }?.isOwn ?? false
    }

    static func isMouseWheel(_ traits: ScrollWheelEventTraits,
                             secondsSinceLastGesturePhase: TimeInterval?) -> Bool {
        if !traits.isContinuous {
            return true
        }
        guard traits.momentumPhase == 0, traits.scrollPhase == 0 else {
            return false
        }
        // Trackpads/Magic Mouse can emit a phaseless transition event between
        // gesture end and momentum start that still carries the gesture's
        // scrollCount. Mouse wheels that report continuous never emit phases,
        // so only events right after a phased one are treated as touch.
        if traits.scrollCount != 0,
           let elapsed = secondsSinceLastGesturePhase,
           elapsed <= touchGestureGraceSeconds {
            return false
        }
        return true
    }

    /// Shift redirects a discrete vertical wheel tick sideways above the event tap.
    /// Select the setting for the direction the user will see, while leaving
    /// genuine two-axis events independent.
    static func inversionPlan(hasVerticalMovement: Bool,
                              hasHorizontalMovement: Bool,
                              shiftRedirectsVertical: Bool,
                              invertVertical: Bool,
                              invertHorizontal: Bool) -> ScrollWheelInversionPlan {
        let shiftRedirectsVertically = shiftRedirectsVertical
            && hasVerticalMovement
            && !hasHorizontalMovement
        return ScrollWheelInversionPlan(
            vertical: hasVerticalMovement
                && (shiftRedirectsVertically ? invertHorizontal : invertVertical),
            horizontal: hasHorizontalMovement && invertHorizontal
        )
    }
}

/// One bounded WindowServer snapshot. Re-hit-testing its front-to-back windows
/// avoids treating an overlapping front window as part of the last target's
/// rectangle. A stationary pointer still refreshes every half second.
final class ScrollWheelTargetCache {
    // Match per-app pointer exceptions without extending freshness on cache hits.
    private static let resolveLifetime: TimeInterval = 0.5

    struct OwnWindow: Equatable {
        let id: CGWindowID
        var frame: CGRect
        var visible: Bool
        var alpha: Double
        var ignoresMouseEvents: Bool
        var level: Int
    }

    struct Window {
        let frame: CGRect
        let isOwn: Bool
    }

    private struct Snapshot {
        let windows: [Window]
        let target: Int?
        let point: CGPoint
        let resolvedAt: TimeInterval

        func holds(_ point: CGPoint, now: TimeInterval) -> Bool {
            guard now >= resolvedAt, now - resolvedAt < ScrollWheelTargetCache.resolveLifetime else { return false }
            if point == self.point { return true }
            guard target != nil else { return false }
            return windows.firstIndex { $0.frame.contains(point) } == target
        }

        var isOwn: Bool { target.map { windows[$0].isOwn } ?? false }
    }

    private let lock = NSLock()
    private let ownProcessID: Int32
    private let now: () -> TimeInterval
    private let lookup: () -> [[String: Any]]
    private var enabled = false
    private var generation: UInt64 = 0
    private var ownWindows: [OwnWindow] = []
    private var orderedWindowIDs: [CGWindowID] = []
    private var snapshot: Snapshot?

    init(ownProcessID: Int32, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         lookup: @escaping () -> [[String: Any]] = WindowServerSupport.onScreenWindowInfo) {
        self.ownProcessID = ownProcessID
        self.now = now
        self.lookup = lookup
    }

    func setEnabled(_ enabled: Bool) {
        lock.withLock {
            guard self.enabled != enabled else { return }
            self.enabled = enabled
            generation &+= 1
            snapshot = nil
            if !enabled {
                ownWindows = []
                orderedWindowIDs = []
            }
        }
    }

    /// Publishing unchanged AppKit state must not flush a wheel burst's cache.
    func update(ownWindows: [OwnWindow], orderedWindowIDs: [CGWindowID]) {
        lock.withLock {
            guard enabled, self.ownWindows != ownWindows || self.orderedWindowIDs != orderedWindowIDs else { return }
            self.ownWindows = ownWindows
            self.orderedWindowIDs = orderedWindowIDs
            generation &+= 1
            snapshot = nil
        }
    }

    func contains(_ point: CGPoint) -> Bool {
        // WindowServer work happens outside the lock. Retry an invalidated read
        // once; continuous window changes leave this tick untouched rather than
        // publishing a stale target or making the tap wait for the main thread.
        for _ in 0..<2 {
            let time = now()
            let state = lock.withLock { () -> (answer: Bool?, generation: UInt64, clickThrough: Set<CGWindowID>) in
                guard enabled else { return (false, generation, []) }
                if let snapshot, snapshot.holds(point, now: time) { return (snapshot.isOwn, generation, []) }
                return (nil, generation, Set(ownWindows.filter(\.ignoresMouseEvents).map(\.id)))
            }
            if let answer = state.answer { return answer }
            let windows = Self.windows(in: lookup(), ownProcessID: ownProcessID,
                                       clickThroughWindowIDs: state.clickThrough)
            let resolved = Snapshot(windows: windows, target: windows.firstIndex { $0.frame.contains(point) },
                                    point: point, resolvedAt: time)
            let answer = lock.withLock { () -> Bool? in
                guard enabled else { return false }
                guard generation == state.generation else { return nil }
                snapshot = resolved
                return resolved.isOwn
            }
            if let answer { return answer }
        }
        return true
    }

    static func windows(in windows: [[String: Any]], ownProcessID: Int32,
                        clickThroughWindowIDs: Set<CGWindowID>) -> [Window] {
        windows.compactMap { window in
            guard let frame = WindowServerSupport.bounds(from: window),
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0 else { return nil }
            let isOwn = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == ownProcessID
            if isOwn, let number = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
               clickThroughWindowIDs.contains(number) { return nil }
            return Window(frame: frame, isOwn: isOwn)
        }
    }
}
