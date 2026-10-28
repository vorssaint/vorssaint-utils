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

enum ScrollZoomModifier: String, CaseIterable {
    case none, option, control, command

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

struct ScrollZoomPreferences: Equatable {
    let verticalZoom: ScrollHorizontalModifier?
    let pinchZoom: ScrollHorizontalModifier?

    var isEnabled: Bool {
        verticalZoom != nil || pinchZoom != nil
    }

    init(isAvailable: Bool, boolFor: (String) -> Bool, stringFor: (String) -> String?) {
        func modifier(_ enabled: String, _ key: String) -> ScrollHorizontalModifier? {
            isAvailable && boolFor(enabled) ? ScrollZoomModifier(storageValue: stringFor(key)).modifier : nil
        }
        verticalZoom = modifier(DefaultsKey.verticalZoomEnabled, DefaultsKey.verticalZoomModifier)
        let pinch = modifier(DefaultsKey.pinchZoomEnabled, DefaultsKey.pinchZoomModifier)
        pinchZoom = pinch == verticalZoom ? nil : pinch
    }

    func action(for event: CGEvent) -> ScrollZoomAction? {
        let choices: [(ScrollZoomEffect, ScrollWheelAxis, ScrollHorizontalModifier?)] = [
            (.zoom, .vertical, verticalZoom),
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

struct ScrollZoomGestureState {
    private(set) var preferences: ScrollZoomPreferences?
    private(set) var pinchModifier: ScrollHorizontalModifier?
    private(set) var pinchLocation: CGPoint?
    private var acceptsEvents = false

    mutating func update(_ preferences: ScrollZoomPreferences) -> Bool {
        guard self.preferences != preferences else { return false }
        self.preferences = preferences
        acceptsEvents = false
        return endPinch()
    }

    mutating func start() { acceptsEvents = preferences?.isEnabled == true }

    mutating func stop() -> Bool {
        acceptsEvents = false
        preferences = nil
        return endPinch()
    }

    func accepts(_ preferences: ScrollZoomPreferences) -> Bool {
        acceptsEvents && self.preferences == preferences
    }

    mutating func beginPinch(_ modifier: ScrollHorizontalModifier, at point: CGPoint) -> (endPrevious: Bool, begin: Bool) {
        // AppKit latches a gesture to its starting view. A moved pointer may
        // be over another view even inside the same window.
        let changed = pinchModifier != modifier || pinchLocation != point
        let endPrevious = changed && pinchModifier != nil
        pinchModifier = modifier
        pinchLocation = point
        return (endPrevious, changed)
    }

    mutating func endPinch() -> Bool {
        guard pinchModifier != nil else { return false }
        pinchModifier = nil
        pinchLocation = nil
        return true
    }
}

struct ScrollZoomStepLimiter {
    private var lastStep: (timestamp: UInt64, positive: Bool)?

    mutating func allows(_ delta: Double, at timestamp: UInt64) -> Bool {
        let positive = delta > 0
        if let lastStep, lastStep.positive == positive,
           timestamp >= lastStep.timestamp,
           timestamp - lastStep.timestamp < 100_000_000 { return false }
        lastStep = (timestamp, positive)
        return true
    }

    mutating func reset() { lastStep = nil }
}

struct ScrollZoomTargetSnapshot {
    let windows: [ScrollWheelTargetCache.Window]
    let modifier: ScrollHorizontalModifier
    let resolvedAt: TimeInterval

    func target(at point: CGPoint, modifier: ScrollHorizontalModifier, now: TimeInterval) -> WindowServerWindowCandidate? {
        guard self.modifier == modifier, now >= resolvedAt, now - resolvedAt < 0.5 else { return nil }
        return windows.first { $0.frame.contains(point) }?.zoomTarget
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

/// The three delta fields a scroll event carries per axis: the line count,
/// the point count and the fixed-point line count.
struct ScrollWheelAxisDelta: Equatable {
    var line: Int64
    var point: Int64
    var fixedPoint: Double

    var hasMovement: Bool { line != 0 || point != 0 || fixedPoint != 0 }
}

/// Tells mouse wheels apart from touch devices, shared by the scroll
/// inverter and smooth scrolling so both features classify events the same
/// way: discrete events are wheels; events flagged continuous are wheels
/// only when they carry no gesture phase at all (how some mouse drivers
/// report their wheels).
enum ScrollWheelSupport {
    /// Both wheel taps share a stage and retain their head/tail ordering.
    /// At this stage the event has its target process and window, which a
    /// smooth glide must retain when posting directly to the receiving app.
    /// It also sees remote screens' scroll, which both taps leave alone
    /// (`ScrollWheelHIDStageLedger`).
    static let tapLocation: CGEventTapLocation = .cgAnnotatedSessionEventTap

    /// How long after a gesture-phased event a phaseless continuous event is
    /// still attributed to the same touch device.
    static let touchGestureGraceSeconds: TimeInterval = 1.0

    /// Marks a smooth glide so neither feature handles it twice if another
    /// input tool reinjects the targeted frame into the global event stream.
    /// Its direction and linear cap have already been applied.
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
            // A zero whole-line field cannot reconstruct a high-resolution tick.
            if isContinuous || redirected || verticalLine == 0 {
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -verticalPoint)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -verticalFixedPoint)
            }
        }
        if plan.horizontal {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -horizontalLine)
            if isContinuous || redirected || horizontalLine == 0 {
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

// MARK: - Linear scrolling

/// Every notch of a mouse wheel worth the same distance, however fast the
/// wheel spins. macOS keeps its wheel acceleration inside the delta itself,
/// so a fast spin arrives as several lines in one event; capping an event at
/// one notch is what takes it out again. Shared by both wheel taps, so the
/// glide and the raw wheel agree on what a notch is worth.
extension ScrollWheelSupport {
    /// Lines one notch scrolls. The default of three moves a few lines of
    /// text per notch: a long page still goes by quickly, and the line being
    /// read stays on screen.
    static let linesPerNotchRange = 1...10
    static let defaultLinesPerNotch = 3

    /// Lines per notch while linear scrolling applies to this event, or nil
    /// when it is off, uninstalled or the app under the pointer is on its own
    /// exception list. Both wheel taps ask it the same way; the exception
    /// list is only consulted while the feature is on.
    static func linearLinesPerNotch(defaults: UserDefaults, isAvailable: Bool,
                                    isExcepted: () -> Bool) -> Int? {
        guard isAvailable, defaults.bool(forKey: DefaultsKey.linearScrollEnabled), !isExcepted() else {
            return nil
        }
        return sanitizedLinesPerNotch(defaults.integer(forKey: DefaultsKey.linearScrollLines))
    }

    /// Clamps the persisted value to its allowed range (0 or garbage falls
    /// back to the default).
    static func sanitizedLinesPerNotch(_ value: Int) -> Int {
        guard value != 0 else { return defaultLinesPerNotch }
        return min(max(value, linesPerNotchRange.lowerBound), linesPerNotchRange.upperBound)
    }

    /// The notch count of a discrete wheel event. macOS scales every notch by
    /// how fast the wheel turns, in both directions: a slow notch can arrive as
    /// a tenth of a line while its line count still reads one. Any event whose
    /// line count moves is therefore one whole notch; only a high-resolution
    /// wheel's fraction, which leaves the line count at zero, stays a fraction.
    /// Some drivers provide only points, so use those when both line fields
    /// are empty rather than dropping a real wheel event.
    static func discreteTicks(line: Int64, fixedPoint: Double, point: Int64) -> Double {
        if line != 0 { return line > 0 ? 1 : -1 }
        if fixedPoint.isFinite, fixedPoint != 0 { return fixedPoint }
        return Double(point) / pointsPerLine
    }

    /// The notch count of a continuous wheel event, in lines. The point field
    /// is what apps read, so it wins; the fixed-point field already counts
    /// lines and only stands in when the driver left the points empty.
    static func continuousTicks(fixedPointDelta: Double, pointDelta: Double) -> Double {
        guard fixedPointDelta.isFinite, pointDelta.isFinite else { return 0 }
        return pointDelta != 0 ? pointDelta / pointsPerLine : fixedPointDelta
    }

    /// The lines an event scrolls under linear scrolling: at most one notch,
    /// multiplied out. A high-resolution wheel's fraction of a notch stays a
    /// fraction, and the sign is untouched.
    static func linearLines(ticks: Double, linesPerNotch: Int) -> Double {
        guard ticks.isFinite, ticks != 0 else { return 0 }
        let lines = min(abs(ticks), 1) * Double(sanitizedLinesPerNotch(linesPerNotch))
        return ticks < 0 ? -lines : lines
    }

    /// The fields to write back into a wheel event under linear scrolling,
    /// plus the fraction of a line to carry into the next event. A discrete
    /// event gets only its line count, since the system rederives the other
    /// two fields from it; a continuous event gets all three, with the point
    /// count kept whole. The carry keeps sub-notch events from being lost and
    /// is dropped on a reversal, like the glide's.
    static func linearDelta(_ delta: ScrollWheelAxisDelta,
                            isContinuous: Bool,
                            linesPerNotch: Int,
                            carry: Double) -> (delta: ScrollWheelAxisDelta, carry: Double) {
        let ticks = isContinuous
            ? continuousTicks(fixedPointDelta: delta.fixedPoint, pointDelta: Double(delta.point))
            : discreteTicks(line: delta.line, fixedPoint: delta.fixedPoint, point: delta.point)
        let lines = linearLines(ticks: ticks, linesPerNotch: linesPerNotch)
        let kept = SmoothScrollSupport.carry(carry, continuing: lines)
        if isContinuous {
            let points = SmoothScrollSupport.wholePixels(lines * pointsPerLine,
                                                         carry: kept * pointsPerLine)
            let wholeLines = points.pixels / pointsPerLine
            return (ScrollWheelAxisDelta(line: Int64(wholeLines.rounded(.towardZero)),
                                         point: Int64(points.pixels),
                                         fixedPoint: wholeLines),
                    points.carry / pointsPerLine)
        }
        let wholeLines = SmoothScrollSupport.wholePixels(lines, carry: kept)
        return (ScrollWheelAxisDelta(line: Int64(wholeLines.pixels), point: 0, fixedPoint: 0),
                wholeLines.carry)
    }

    /// Writes linear scrolling's fields into a wheel event; an axis passed as
    /// nil did not move and is left alone. Both line counts go in first,
    /// since a line write can rederive the pixel fields; a continuous event's
    /// point and fixed-point counts follow once both lines are set.
    static func writeLinear(vertical: ScrollWheelAxisDelta?, horizontal: ScrollWheelAxisDelta?,
                            to event: CGEvent, isContinuous: Bool) {
        if let vertical { event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: vertical.line) }
        if let horizontal { event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: horizontal.line) }
        guard isContinuous else { return }
        if let vertical {
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: vertical.point)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: vertical.fixedPoint)
        }
        if let horizontal {
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: horizontal.point)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: horizontal.fixedPoint)
        }
    }
}

// MARK: - HID stage

/// The wheel events that came in at the HID stage, told apart from those
/// posted further down the event path.
///
/// Both wheel taps sit at the annotated stage, which also sees scroll posted
/// at the session tap. That is where Screen Sharing, Apple Remote Desktop and
/// VNC post the controlling computer's scrolling, trackpad included, as
/// phaseless pixel events that read as a mouse wheel. Taps at the HID stage
/// never saw them, so they were never turned, capped or smoothed here; the
/// controlling computer already scrolled them its own way.
///
/// A hardware event carries source process id 0 and can only come in at the
/// HID stage, so it always counts. A posted one counts when the HID tap noted
/// its timestamp, which it keeps on its way down. Both readings are compared
/// as nanoseconds: at the HID stage a hardware event reads in mach ticks, a
/// posted one in nanoseconds (`EventTimestamp`, #1689). Events overtake one
/// another between the stages, so the last few hundred are kept rather than
/// only the newest.
struct ScrollWheelHIDStageLedger {
    static let capacity = 256
    /// A posted event reads the same at both stages; the slack only covers
    /// a rounding the system might do differently, and is far below the
    /// time between two wheel events.
    static let tolerance: UInt64 = 1_000

    /// False while no HID tap is noting anything. Every event then counts as
    /// having come through, so a tap that could not be created leaves the
    /// wheel features working for local input rather than off.
    var isWatching = false
    private var timestamps = [UInt64](repeating: 0, count: capacity)
    private var next = 0

    /// `raw` is the timestamp as the tap reads it, in either unit.
    mutating func note(_ raw: UInt64, nowTicks: UInt64 = mach_absolute_time(),
                       timebase: EventTimestamp.Timebase = EventTimestamp.machTimebase) {
        timestamps[next] = EventTimestamp.nanoseconds(raw: raw, nowTicks: nowTicks, timebase: timebase)
        next = (next + 1) % Self.capacity
    }

    func passed(_ raw: UInt64, sourceProcessID: Int64, nowTicks: UInt64 = mach_absolute_time(),
                timebase: EventTimestamp.Timebase = EventTimestamp.machTimebase) -> Bool {
        guard isWatching else { return true }
        guard sourceProcessID != 0 else { return true }
        guard raw != 0 else { return false }
        let nanoseconds = EventTimestamp.nanoseconds(raw: raw, nowTicks: nowTicks, timebase: timebase)
        return timestamps.contains { noted in
            noted != 0 && (noted >= nanoseconds ? noted - nanoseconds : nanoseconds - noted) <= Self.tolerance
        }
    }

    mutating func reset() {
        isWatching = false
        timestamps = [UInt64](repeating: 0, count: Self.capacity)
        next = 0
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
        let zoomTarget: WindowServerWindowCandidate?
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

    var clickThroughWindowIDs: Set<CGWindowID> {
        lock.withLock { Set(ownWindows.filter(\.ignoresMouseEvents).map(\.id)) }
    }

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
            let target: WindowServerWindowCandidate?
            if !isOwn, (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
               let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid > 0,
               let id = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value {
                target = WindowServerWindowCandidate(pid: pid, windowID: id, frame: frame)
            } else {
                target = nil
            }
            return Window(frame: frame, isOwn: isOwn, zoomTarget: target)
        }
    }
}
