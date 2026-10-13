// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

struct WindowGestureResizeEdges: OptionSet, Equatable {
    let rawValue: Int

    static let left = WindowGestureResizeEdges(rawValue: 1 << 0)
    static let right = WindowGestureResizeEdges(rawValue: 1 << 1)
    static let top = WindowGestureResizeEdges(rawValue: 1 << 2)
    static let bottom = WindowGestureResizeEdges(rawValue: 1 << 3)
}

/// Whether a press is still undecided, already moving a window, or none of
/// the two.
enum WindowGestureState: Equatable {
    case idle
    case pending
    case active
}

/// What the pointer tap saw, reduced to the facts the decision needs.
/// `tracked` means the event belongs to the button that started the press.
enum WindowGestureInput: Equatable {
    case buttonDown(sameButton: Bool, chordMatched: Bool)
    case buttonDragged(tracked: Bool, pastSlop: Bool)
    case buttonUp(tracked: Bool)
    case otherEvent
    /// The system switched the tap off. Unlike every other input this one does
    /// not mean the press is still under way: while the tap was off its events
    /// went straight to the app, so whether the button is still down has to be
    /// asked separately.
    case tapDisabled(buttonStillDown: Bool)
    case accessibilityLost
}

/// What the tap does with the event it is holding.
enum WindowGestureDecision: Equatable {
    /// Hand the event back to the system untouched.
    case passThrough
    /// Take custody of the press while it is still undecided.
    case arm
    /// Keep the press: the pointer has not moved enough to mean a gesture.
    case hold
    /// The press became a window gesture.
    case promote
    /// Keep driving the window with this movement.
    case applyMove
    /// Last movement of the gesture.
    case applyFinish
    /// The press was only a click: give the held press back, then the release.
    case replayThenPass
    /// Give the held press back and let this event through as well.
    case flushThenPass
    /// Forget the gesture without giving anything back.
    case dropState
    /// A new press arrived over a stale one: forget it and judge this event
    /// as if nothing were pending.
    case restartAsIdle
    /// A second button went down while the first press was still held: give
    /// that press back, since its own release is still coming, then judge
    /// this event as if nothing were pending.
    case flushThenRestart
}

enum WindowGestureSupport {
    static let defaultModifiers: GlobalShortcutModifiers = [.control, .command]
    static let moveModifierMask: GlobalShortcutModifiers = [.control, .option, .command]

    /// How far the pointer may wander between press and release and still
    /// count as a plain click. Below it the press is handed back to the app
    /// untouched, so a modifier click keeps working everywhere; past it the
    /// press becomes a window gesture. Deliberately its own constant: tuning
    /// one pointer feature must never move another.
    static let dragSlop: CGFloat = 6

    static func exceedsDragSlop(from origin: CGPoint, to point: CGPoint) -> Bool {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        return (dx * dx + dy * dy).squareRoot() > dragSlop
    }

    /// The whole custody rule in one pure function, so every path that takes
    /// or returns a press is provable without Accessibility, a tap or a
    /// window. A press is only ever kept while it may still become a gesture,
    /// and a press that never became one is always given back exactly once.
    static func decide(state: WindowGestureState,
                       input: WindowGestureInput) -> WindowGestureDecision {
        switch state {
        case .idle:
            if case .buttonDown(_, let chordMatched) = input {
                return chordMatched ? .arm : .passThrough
            }
            return .passThrough

        case .pending:
            switch input {
            case .buttonDragged(let tracked, let pastSlop):
                guard tracked else { return .flushThenPass }
                return pastSlop ? .promote : .hold
            case .buttonUp(let tracked):
                return tracked ? .replayThenPass : .flushThenPass
            case .buttonDown(let sameButton, _):
                // Same button pressing again means its release never arrived.
                // The app never saw that press, so dropping it leaves nothing
                // half done, and replaying it here would click at a stale
                // spot. A different button means the first one is still held
                // and its release is still coming, so that press has to go
                // back or the app would get a release it never pressed.
                return sameButton ? .restartAsIdle : .flushThenRestart
            case .tapDisabled(let buttonStillDown):
                // Giving the press back only closes into a whole click if a
                // release is still coming. With the button already up, the
                // release went to the app while the tap was off, so handing
                // the press back now would leave it pressed with nothing to
                // lift it.
                return buttonStillDown ? .flushThenPass : .dropState
            case .otherEvent, .accessibilityLost:
                return .flushThenPass
            }

        case .active:
            switch input {
            case .buttonDragged(let tracked, _):
                return tracked ? .applyMove : .passThrough
            case .buttonUp(let tracked):
                return tracked ? .applyFinish : .passThrough
            case .buttonDown, .otherEvent:
                return .passThrough
            case .tapDisabled, .accessibilityLost:
                // The app never received the press that started the gesture,
                // so there is nothing to give back.
                return .dropState
            }
        }
    }

    static var defaultModifierStorageValue: String {
        storageValue(for: defaultModifiers)
    }

    /// Invalid or empty values fall back to a deliberate two-key gesture. A
    /// primary modifier is required so Shift by itself can never take over
    /// ordinary range selection and text dragging throughout the system.
    static func modifiers(from storedValue: String?) -> GlobalShortcutModifiers {
        guard let storedValue else { return defaultModifiers }
        var modifiers: GlobalShortcutModifiers = []
        for token in storedValue.split(separator: "+") {
            switch token {
            case "control": modifiers.insert(.control)
            case "option": modifiers.insert(.option)
            case "shift": modifiers.insert(.shift)
            case "command": modifiers.insert(.command)
            default: return defaultModifiers
            }
        }
        // Shift is reserved as the resize variant of the same primary drag,
        // which keeps the feature fully usable from a trackpad.
        modifiers.formIntersection(moveModifierMask)
        return modifiers.hasPrimaryModifier ? modifiers : defaultModifiers
    }

    static func storageValue(for modifiers: GlobalShortcutModifiers) -> String {
        let sanitized = modifiers.intersection(moveModifierMask)
        let resolved = sanitized.hasPrimaryModifier ? sanitized : defaultModifiers
        return resolved.storageTokens.joined(separator: "+")
    }

    static func resizeModifiers(from moveModifiers: GlobalShortcutModifiers) -> GlobalShortcutModifiers {
        moveModifiers.intersection(moveModifierMask).union(.shift)
    }

    static func modifiersMatch(eventFlags: CGEventFlags,
                               expected: GlobalShortcutModifiers) -> Bool {
        GlobalShortcutModifiers(cgFlags: eventFlags) == expected.intersection(.validMask)
    }

    static func movedOrigin(from original: CGPoint,
                            pointerStart: CGPoint,
                            pointerNow: CGPoint) -> CGPoint {
        CGPoint(x: original.x + pointerNow.x - pointerStart.x,
                y: original.y + pointerNow.y - pointerStart.y)
    }

    /// Divides the window into nine intuitive regions. Corners resize in two
    /// axes and edge regions in one. The center chooses its nearest edge, so
    /// resizing from anywhere in the window always has a visible result.
    static func resizeEdges(at point: CGPoint, in frame: CGRect) -> WindowGestureResizeEdges {
        guard frame.width > 0, frame.height > 0 else { return [] }
        let localX = min(max(point.x - frame.minX, 0), frame.width)
        let localY = min(max(point.y - frame.minY, 0), frame.height)
        var edges: WindowGestureResizeEdges = []

        if localX < frame.width / 3 {
            edges.insert(.left)
        } else if localX > frame.width * 2 / 3 {
            edges.insert(.right)
        }
        if localY < frame.height / 3 {
            edges.insert(.top)
        } else if localY > frame.height * 2 / 3 {
            edges.insert(.bottom)
        }

        guard edges.isEmpty else { return edges }
        let candidates: [(CGFloat, WindowGestureResizeEdges)] = [
            (localX, .left),
            (frame.width - localX, .right),
            (localY, .top),
            (frame.height - localY, .bottom),
        ]
        return candidates.min { $0.0 < $1.0 }?.1 ?? .right
    }

    /// AX window coordinates use a top-left origin. Resizing a top or left
    /// edge therefore moves the origin while keeping the opposite edge fixed.
    /// The minimum is only a safety floor; apps remain free to enforce a
    /// larger minimum through Accessibility.
    static func resizedFrame(from original: CGRect,
                             pointerStart: CGPoint,
                             pointerNow: CGPoint,
                             edges: WindowGestureResizeEdges,
                             minimumSize: CGSize = CGSize(width: 120, height: 80)) -> CGRect {
        let deltaX = pointerNow.x - pointerStart.x
        let deltaY = pointerNow.y - pointerStart.y
        var origin = original.origin
        var size = original.size

        if edges.contains(.left) {
            size.width = max(minimumSize.width, original.width - deltaX)
            origin.x = original.maxX - size.width
        } else if edges.contains(.right) {
            size.width = max(minimumSize.width, original.width + deltaX)
        }

        if edges.contains(.top) {
            size.height = max(minimumSize.height, original.height - deltaY)
            origin.y = original.maxY - size.height
        } else if edges.contains(.bottom) {
            size.height = max(minimumSize.height, original.height + deltaY)
        }

        return CGRect(origin: origin, size: size)
    }

    /// Reanchors the far edge after an app applies a larger minimum size than
    /// the requested frame. Right and bottom resizing keep the original origin;
    /// left and top resizing derive it from the size the app actually accepted.
    static func anchoredOrigin(original: CGRect,
                               requestedOrigin: CGPoint,
                               acceptedSize: CGSize,
                               edges: WindowGestureResizeEdges) -> CGPoint {
        var origin = requestedOrigin
        if edges.contains(.left) {
            origin.x = original.maxX - acceptedSize.width
        }
        if edges.contains(.top) {
            origin.y = original.maxY - acceptedSize.height
        }
        return origin
    }

    /// Returns no position mutation for the right and bottom edges. Keeping
    /// that distinction explicit prevents Accessibility from publishing an
    /// unnecessary intermediate frame during continuous resizing.
    static func anchoredOriginIfNeeded(original: CGRect,
                                       requestedOrigin: CGPoint,
                                       acceptedSize: CGSize,
                                       edges: WindowGestureResizeEdges) -> CGPoint? {
        guard edges.contains(.left) || edges.contains(.top) else { return nil }
        return anchoredOrigin(original: original,
                              requestedOrigin: requestedOrigin,
                              acceptedSize: acceptedSize,
                              edges: edges)
    }
}

/// Actions triggered by the hold-shortcut pointer wheel.
enum WindowDirectionalAction: Equatable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case maximize
    case minimize

    var layoutAction: WindowLayoutAction? {
        switch self {
        case .leftHalf: return .leftHalf
        case .rightHalf: return .rightHalf
        case .topHalf: return .topHalf
        case .bottomHalf: return .bottomHalf
        case .topLeft: return .topLeft
        case .topRight: return .topRight
        case .bottomLeft: return .bottomLeft
        case .bottomRight: return .bottomRight
        case .maximize: return .maximize
        case .minimize: return nil
        }
    }
}

/// Pure direction and special-action selection for the hold-shortcut pointer layout mode.
enum WindowDirectionalGestureSupport {
    static let activationDistance: CGFloat = 28

    static func appKitPoint(fromQuartz point: CGPoint, menuBarScreenTopY: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: menuBarScreenTopY - point.y)
    }

    static func action(from origin: CGPoint,
                       to point: CGPoint,
                       activationDistance: CGFloat = activationDistance) -> WindowDirectionalAction? {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        guard hypot(dx, dy) >= activationDistance else { return nil }

        // Standard 8-way angular division (45° per slice):
        var degrees = atan2(dy, dx) * 180.0 / .pi
        if degrees < 0 { degrees += 360.0 }

        if degrees >= 337.5 || degrees < 22.5 { return .rightHalf }
        if degrees >= 22.5 && degrees < 67.5 { return .topRight }
        if degrees >= 67.5 && degrees < 112.5 { return .topHalf }
        if degrees >= 112.5 && degrees < 157.5 { return .topLeft }
        if degrees >= 157.5 && degrees < 202.5 { return .leftHalf }
        if degrees >= 202.5 && degrees < 247.5 { return .bottomLeft }
        if degrees >= 247.5 && degrees < 292.5 { return .bottomHalf }
        return .bottomRight
    }

    /// Holding the ring open keeps keys auto-repeating. Those repeats must not
    /// force maximize/minimize, or the default ⌃⌥Space binding fights the
    /// pointer aim (#1566). The event is still swallowed so repeats do not
    /// leak to the front app.
    static func shouldApplyKeyboardManualOverride(isAutorepeat: Bool) -> Bool {
        !isAutorepeat
    }
}

enum WindowEdgeDragClassification: Equatable {
    case waiting
    case moving
    case resizing
    case unrelated
}

struct WindowEdgeSnapScreen: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
}

/// The eight drop zones around the screen: four corners and four edges, each
/// edge holding one or more areas. Raw values are persisted, so they stay
/// stable even if the visual arrangement changes later.
enum WindowEdgeSnapZone: String, CaseIterable {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight

    /// What the area does until someone picks another placement for it.
    var defaultAction: WindowLayoutAction {
        switch self {
        case .topLeft: return .topLeft
        case .top: return .maximize
        case .topRight: return .topRight
        case .left: return .leftHalf
        case .right: return .rightHalf
        case .bottomLeft: return .bottomLeft
        case .bottom: return .bottomHalf
        case .bottomRight: return .bottomRight
        }
    }

    /// The top and bottom edges split into areas side by side, the left and
    /// right edges into areas stacked from top to bottom. A corner is always
    /// one area.
    var isHorizontalEdge: Bool { self == .top || self == .bottom }
    var isVerticalEdge: Bool { self == .left || self == .right }

    var maximumParts: Int {
        isHorizontalEdge || isVerticalEdge ? WindowEdgeSnapLayout.maximumParts : 1
    }

    static let allEnabled = Set(allCases)

    static func disabledZones(from storedValue: String?) -> Set<WindowEdgeSnapZone> {
        guard let storedValue else { return [] }
        return Set(storedValue.split(separator: ",").compactMap {
            WindowEdgeSnapZone(rawValue: $0.trimmingCharacters(in: .whitespaces))
        })
    }

    static func disabledZonesStorageValue(_ zones: Set<WindowEdgeSnapZone>) -> String {
        allCases.filter(zones.contains).map(\.rawValue).joined(separator: ",")
    }

    static func enabledZones(from storedValue: String?) -> Set<WindowEdgeSnapZone> {
        allEnabled.subtracting(disabledZones(from: storedValue))
    }
}

/// The placements a drop area can use, in the families Settings lists them
/// in. Each one fills a fixed part of the screen, so a drag can preview it.
/// Center, full screen, restore and the display moves depend on the window or
/// leave the screen, so they are left out.
enum WindowEdgeSnapPlacementGroup: CaseIterable {
    case halves, thirds, quarterRows, quarterColumns, sixths, corners, other

    var actions: [WindowLayoutAction] {
        switch self {
        case .halves:
            return [.leftHalf, .rightHalf, .topHalf, .bottomHalf, .centerHalf]
        case .thirds:
            return [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds, .centerTwoThirds,
                    .topThird, .middleThird, .bottomThird, .topTwoThirds, .bottomTwoThirds]
        case .quarterRows:
            return [.topQuarter, .upperMiddleQuarter, .lowerMiddleQuarter, .bottomQuarter]
        case .quarterColumns:
            return [.leftQuarter, .leftMiddleQuarter, .rightMiddleQuarter, .rightQuarter]
        case .sixths:
            return [.topLeftSixth, .topCenterSixth, .topRightSixth,
                    .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth]
        case .corners:
            return [.topLeft, .topRight, .bottomLeft, .bottomRight]
        case .other:
            return [.maximize, .marginMaximize]
        }
    }

    func title(_ text: WindowLayoutFeatureStrings) -> String {
        switch self {
        case .halves: return text.halves
        case .thirds: return text.thirds
        case .quarterRows: return text.quarterRows
        case .quarterColumns: return text.quarterColumns
        case .sixths: return text.sixths
        case .corners: return text.corners
        case .other: return text.other
        }
    }

    static let placements = Set(allCases.flatMap(\.actions))
}

/// What each drop area does. A corner holds one placement, and a straight
/// edge holds one for each area it is split into, from left to right or from
/// top to bottom. Only areas changed from their default are stored, as
/// `zone=action` entries with `+` between the areas of a split edge.
struct WindowEdgeSnapLayout: Equatable {
    static let maximumParts = 4
    static let standard = WindowEdgeSnapLayout()

    private var changed: [WindowEdgeSnapZone: [WindowLayoutAction]] = [:]

    init() {}

    /// An entry with an unknown zone or placement, a placement an area cannot
    /// use or too many areas is dropped, so that zone keeps its default and a
    /// value written by a newer version never breaks the others.
    init(storageValue: String?) {
        for entry in (storageValue ?? "").split(separator: ",") {
            let pair = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2,
                  let zone = WindowEdgeSnapZone(rawValue: pair[0].trimmingCharacters(in: .whitespaces))
            else { continue }
            let names = pair[1].split(separator: "+", omittingEmptySubsequences: false)
            let actions = names.compactMap {
                WindowLayoutAction(rawValue: $0.trimmingCharacters(in: .whitespaces))
            }
            guard actions.count == names.count, Self.accepts(actions, for: zone) else { continue }
            set(actions, for: zone)
        }
    }

    var storageValue: String {
        WindowEdgeSnapZone.allCases.compactMap { zone in
            changed[zone].map { zone.rawValue + "=" + $0.map(\.rawValue).joined(separator: "+") }
        }.joined(separator: ",")
    }

    func actions(for zone: WindowEdgeSnapZone) -> [WindowLayoutAction] {
        changed[zone] ?? [zone.defaultAction]
    }

    /// The placement at a point along the edge between its corners, given as
    /// a fraction from its left or top end.
    func action(for zone: WindowEdgeSnapZone, along fraction: CGFloat) -> WindowLayoutAction {
        let actions = actions(for: zone)
        let position = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        let index = Int((position * CGFloat(actions.count)).rounded(.down))
        return actions[min(index, actions.count - 1)]
    }

    mutating func setAction(_ action: WindowLayoutAction, for zone: WindowEdgeSnapZone, part: Int) {
        var actions = actions(for: zone)
        guard actions.indices.contains(part) else { return }
        actions[part] = action
        guard Self.accepts(actions, for: zone) else { return }
        set(actions, for: zone)
    }

    /// A split edge starts with the screen's equal columns along the top or
    /// bottom, or its equal rows along a side, so each area places the window
    /// in the column or row it sits on. Going back to one area brings the
    /// default back, and picking the count an edge already has keeps its
    /// placements.
    mutating func setPartCount(_ count: Int, for zone: WindowEdgeSnapZone) {
        guard count != actions(for: zone).count else { return }
        let parts: [WindowLayoutAction]
        switch (count, zone.isHorizontalEdge) {
        case (1, _): parts = [zone.defaultAction]
        case (2, true): parts = [.leftHalf, .rightHalf]
        case (3, true): parts = [.leftThird, .centerThird, .rightThird]
        case (4, true): parts = [.leftQuarter, .leftMiddleQuarter, .rightMiddleQuarter, .rightQuarter]
        case (2, false): parts = [.topHalf, .bottomHalf]
        case (3, false): parts = [.topThird, .middleThird, .bottomThird]
        case (4, false): parts = [.topQuarter, .upperMiddleQuarter, .lowerMiddleQuarter, .bottomQuarter]
        default: return
        }
        guard parts.count <= zone.maximumParts else { return }
        set(parts, for: zone)
    }

    /// Where a placement puts a window on a 16:10 screen, as fractions of it
    /// measured from the top left, for the map in Settings to draw.
    static func previewRect(for action: WindowLayoutAction) -> CGRect {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let rect = WindowLayoutGeometry.rect(for: action, current: screen, visibleFrame: screen)
        return CGRect(x: rect.minX / screen.width,
                      y: (screen.maxY - rect.maxY) / screen.height,
                      width: rect.width / screen.width,
                      height: rect.height / screen.height)
    }

    private mutating func set(_ actions: [WindowLayoutAction], for zone: WindowEdgeSnapZone) {
        changed[zone] = actions == [zone.defaultAction] ? nil : actions
    }

    private static func accepts(_ actions: [WindowLayoutAction], for zone: WindowEdgeSnapZone) -> Bool {
        !actions.isEmpty && actions.count <= zone.maximumParts
            && actions.allSatisfy(WindowEdgeSnapPlacementGroup.placements.contains)
    }
}

struct WindowEdgeSnapTarget: Equatable {
    let zone: WindowEdgeSnapZone
    let action: WindowLayoutAction
    let frame: CGRect
    let visibleFrame: CGRect
}

/// The pointer's recent path during a drag, kept just long enough to tell
/// how fast it is moving. One event can follow another by a millisecond, so
/// speed is read over a short span rather than between two events.
struct WindowEdgeSnapPointerTrail {
    /// How far back the speed reaches.
    static let span: TimeInterval = 0.05
    /// The least time a reading divides by. A mouse can report every
    /// millisecond, and the point it nudges while its button comes up must
    /// not read as a crossing.
    static let minimumSpan: TimeInterval = 0.02
    /// A pointer with no event for this long has stopped, whatever its last
    /// speed was.
    static let stillAfter: TimeInterval = 0.1
    /// The most samples kept. The span ages samples out only while event
    /// times move on, and this covers it even at 8000 Hz polling.
    static let capacity = 512

    private var samples: [(time: TimeInterval, point: CGPoint)] = []

    /// When the newest sample was taken, or nil while the trail is empty.
    var lastTime: TimeInterval? { samples.last?.time }

    mutating func append(_ point: CGPoint, at time: TimeInterval) {
        if let last = samples.last {
            if time < last.time {
                samples.removeAll()
            } else if time - last.time >= Self.stillAfter {
                // After a pause the path starts again from where the pointer
                // rested, as if it set off within the shortest span, so the
                // stop is not averaged in and a flick out of it reads fast.
                samples = [(time - Self.minimumSpan, last.point)]
            }
        }
        samples.append((time, point))
        // One sample from before the span stays as its starting point.
        while samples.count > 2, time - samples[1].time >= Self.span {
            samples.removeFirst()
        }
        if samples.count > Self.capacity {
            samples.removeFirst(samples.count - Self.capacity)
        }
    }

    mutating func reset() {
        samples.removeAll()
    }

    /// Points per second, in the coordinates the points were given in.
    func velocity(at now: TimeInterval) -> CGVector {
        guard samples.count > 1, let last = samples.last, let first = samples.first,
              now - last.time < Self.stillAfter else { return .zero }
        let elapsed = max(last.time - first.time, Self.minimumSpan)
        return CGVector(dx: (last.point.x - first.point.x) / elapsed,
                        dy: (last.point.y - first.point.y) / elapsed)
    }
}

enum WindowEdgeSnapSupport {
    static let activationDistance: CGFloat = 12
    static let resizeCornerDistance: CGFloat = 12
    static let resizeEdgeDistance: CGFloat = 5
    /// Points per second across an edge, above which the pointer is passing
    /// rather than aiming. Tuned by hand against macOS tiling.
    static let crossingSpeed: CGFloat = 400
    static let desktopAndDockSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension"
    )!
    private static let systemTilingKeys = [
        "EnableTilingByEdgeDrag",
        "EnableTilingOptionAccelerator",
        "EnableTopTilingByEdgeDrag",
    ]
    private static let movementThreshold: CGFloat = 2
    private static let sizeTolerance: CGFloat = 2

    static var isSystemTilingEnabled: Bool {
        guard #available(macOS 15.0, *),
              let defaults = UserDefaults(suiteName: "com.apple.WindowManager") else { return false }
        return systemTilingEnabled(
            valueFor: { key in
                guard defaults.object(forKey: key) != nil else { return nil }
                return defaults.bool(forKey: key)
            },
            displaysSpan: displaysSpan(spacesPreference("spans-displays"))
        )
    }

    /// The system's edge tiling choices arrive enabled when their preference
    /// has never been written. Keeping this pure makes the conflict gate
    /// testable without changing somebody's desktop settings.
    ///
    /// When displays span (Separate Spaces off) those switches are greyed
    /// out and the system's own tiling is inert, even if a key was written
    /// as enabled. The warning's instruction is unreachable then (issue #1079).
    static func systemTilingEnabled(valueFor: (String) -> Bool?,
                                    displaysSpan: Bool = false) -> Bool {
        if displaysSpan { return false }
        return systemTilingKeys.contains { valueFor($0) ?? true }
    }

    /// Separate Spaces off is the only configuration where displays span.
    /// An absent preference is Apple's default: one Space per display.
    static func displaysSpan(_ value: Bool?) -> Bool {
        value ?? false
    }

    private static func spacesPreference(_ key: String) -> Bool? {
        guard let defaults = UserDefaults(suiteName: "com.apple.spaces") else { return nil }
        return defaults.object(forKey: key).map { _ in defaults.bool(forKey: key) }
    }

    static var isSystemTopWindowOverviewDragEnabled: Bool {
        guard #available(macOS 15.0, *) else { return true }
        guard let defaults = UserDefaults(suiteName: "com.apple.dock") else { return true }
        let key = "enterMissionControlByTopWindowDrag"
        let value = defaults.object(forKey: key).map { _ in defaults.bool(forKey: key) }
        return systemTopWindowOverviewDragEnabled(value: value)
    }

    /// The top-edge gesture also arrives enabled before its preference is
    /// written. The event tap keeps a confirmed window drag away from the
    /// physical top while edge snapping uses the menu bar's lower boundary.
    static func systemTopWindowOverviewDragEnabled(value: Bool?) -> Bool {
        value ?? true
    }

    /// Keeps a confirmed window drag one point inside the display while the
    /// pointer is pressed against its top edge. The snap target still sees the
    /// edge, but the system never receives the exact coordinate that opens its
    /// window overview. Callers must only use this after proving that a window,
    /// rather than content inside it, is moving.
    static func locationAvoidingSystemTopDrag(_ point: CGPoint,
                                              screenFrames: [CGRect],
                                              enabledZones: Set<WindowEdgeSnapZone> =
                                                  WindowEdgeSnapZone.allEnabled) -> CGPoint {
        guard let screen = screenFrames.first(where: {
            point.x >= $0.minX && point.x <= $0.maxX
                && abs(point.y - $0.minY) < 0.5
        }), enabledZones.contains(topZone(atX: point.x, in: screen)) else { return point }
        return CGPoint(x: point.x, y: screen.minY + 1)
    }

    static func startsAtResizeHandle(_ point: CGPoint,
                                     frame: CGRect) -> Bool {
        guard point.x >= frame.minX - resizeCornerDistance,
              point.x <= frame.maxX + resizeCornerDistance,
              point.y >= frame.minY - resizeCornerDistance,
              point.y <= frame.maxY + resizeCornerDistance else { return false }
        let nearVerticalCorner = abs(point.x - frame.minX) <= resizeCornerDistance
            || abs(point.x - frame.maxX) <= resizeCornerDistance
        let nearHorizontalCorner = abs(point.y - frame.minY) <= resizeCornerDistance
            || abs(point.y - frame.maxY) <= resizeCornerDistance
        let nearEdge = abs(point.x - frame.minX) <= resizeEdgeDistance
            || abs(point.x - frame.maxX) <= resizeEdgeDistance
            || abs(point.y - frame.minY) <= resizeEdgeDistance
            || abs(point.y - frame.maxY) <= resizeEdgeDistance
        return nearEdge || (nearVerticalCorner && nearHorizontalCorner)
    }

    /// A pointer drag is only a window move after the same window follows it.
    /// Content drags leave the frame still, while native resizing keeps at
    /// least two frame edges anchored. Neither may turn into a placement just
    /// because the pointer ends at a screen edge. A tiled window restoring its
    /// old size while it starts moving is still a move.
    static func classify(initialFrame: CGRect,
                         currentFrame: CGRect,
                         pointerStart: CGPoint,
                         pointerNow: CGPoint) -> WindowEdgeDragClassification {
        let sizeChanged = abs(currentFrame.width - initialFrame.width) > sizeTolerance
            || abs(currentFrame.height - initialFrame.height) > sizeTolerance
        if sizeChanged, sharesPerpendicularEdges(initialFrame, currentFrame) {
            return .resizing
        }

        let windowDelta = CGPoint(x: currentFrame.minX - initialFrame.minX,
                                  y: currentFrame.minY - initialFrame.minY)
        let pointerDelta = CGPoint(x: pointerNow.x - pointerStart.x,
                                   y: pointerNow.y - pointerStart.y)
        let windowDistance = hypot(windowDelta.x, windowDelta.y)
        guard windowDistance > movementThreshold else { return .waiting }

        let pointerDistance = hypot(pointerDelta.x, pointerDelta.y)
        guard pointerDistance > movementThreshold else { return .unrelated }
        let alignment = (windowDelta.x * pointerDelta.x + windowDelta.y * pointerDelta.y)
            / (windowDistance * pointerDistance)
        let ratio = windowDistance / pointerDistance
        return alignment >= 0.6 && ratio >= 0.2 && ratio <= 1.8 ? .moving : .unrelated
    }

    /// Resolves the hot zone under an AppKit-coordinate pointer. Screen frames
    /// choose the reachable edge; visible frames keep the result clear of the
    /// menu bar and Dock.
    ///
    /// A seam two displays share counts only while the pointer is slow across
    /// it, the way macOS tiling tells aiming from passing: a window dragged
    /// through at speed crosses to the next display, and one slowed down
    /// there tiles. An edge with nothing beyond it is a wall that stops the
    /// pointer, so it counts at any speed, and a window flung at it and let
    /// go at once still tiles. Speed along an edge never counts, so sliding
    /// from a half to a corner keeps the preview.
    ///
    /// An edge split into areas divides its length between the corners
    /// equally, the way the map in Settings draws it.
    static func target(at point: CGPoint,
                       screens: [WindowEdgeSnapScreen],
                       velocity: CGVector = .zero,
                       distance: CGFloat = activationDistance,
                       enabledZones: Set<WindowEdgeSnapZone> =
                           WindowEdgeSnapZone.allEnabled,
                       layout: WindowEdgeSnapLayout = .standard) -> WindowEdgeSnapTarget? {
        let settledAcross = abs(velocity.dx) <= crossingSpeed
        let settledUpDown = abs(velocity.dy) <= crossingSpeed
        let frames = screens.map(\.frame)
        let ordered = screens.enumerated().sorted {
            let first = distanceSquared(from: point, to: $0.element.frame)
            let second = distanceSquared(from: point, to: $1.element.frame)
            guard first == second else { return first < second }
            // On a seam both displays are at distance zero. The one holding
            // the pointer wins, and an otherwise equal pair keeps the order
            // the system gave, which sorting alone does not promise.
            let holdsFirst = holds($0.element.frame, point)
            guard holdsFirst == holds($1.element.frame, point) else { return holdsFirst }
            return $0.offset < $1.offset
        }
        for (_, screen) in ordered {
            let frame = screen.frame
            guard frame.width > 0, frame.height > 0,
                  screen.visibleFrame.width > 0, screen.visibleFrame.height > 0,
                  point.x >= frame.minX - distance,
                  point.x <= frame.maxX + distance,
                  point.y >= frame.minY - distance,
                  point.y <= frame.maxY + distance
            else { continue }

            // Just past each edge, level with the pointer: another display
            // there makes the edge a seam.
            let open = { (probe: CGPoint) in frames.contains { $0 != frame && $0.contains(probe) } }
            let nearLeft = abs(point.x - frame.minX) <= distance
                && (settledAcross || !open(CGPoint(x: frame.minX - 0.5, y: point.y)))
            let nearRight = abs(point.x - frame.maxX) <= distance
                && (settledAcross || !open(CGPoint(x: frame.maxX + 0.5, y: point.y)))
            let visibleTop = min(max(screen.visibleFrame.maxY, frame.minY), frame.maxY)
            let nearTop = point.y >= visibleTop - distance && point.y <= frame.maxY + distance
                && (settledUpDown || !open(CGPoint(x: point.x, y: frame.maxY + 0.5)))
            let nearBottom = abs(point.y - frame.minY) <= distance
                && (settledUpDown || !open(CGPoint(x: point.x, y: frame.minY - 0.5)))
            guard nearLeft || nearRight || nearTop || nearBottom else { continue }

            let horizontalCorner = horizontalCornerWidth(for: frame)
            let verticalCorner = min(max(frame.height * 0.18, 80), 160)
            let zone: WindowEdgeSnapZone
            if nearTop {
                if point.x <= frame.minX + horizontalCorner {
                    zone = .topLeft
                } else if point.x >= frame.maxX - horizontalCorner {
                    zone = .topRight
                } else {
                    zone = .top
                }
            } else if nearBottom {
                if point.x <= frame.minX + horizontalCorner {
                    zone = .bottomLeft
                } else if point.x >= frame.maxX - horizontalCorner {
                    zone = .bottomRight
                } else {
                    zone = .bottom
                }
            } else if nearLeft {
                if point.y >= frame.maxY - verticalCorner {
                    zone = .topLeft
                } else if point.y <= frame.minY + verticalCorner {
                    zone = .bottomLeft
                } else {
                    zone = .left
                }
            } else {
                if point.y >= frame.maxY - verticalCorner {
                    zone = .topRight
                } else if point.y <= frame.minY + verticalCorner {
                    zone = .bottomRight
                } else {
                    zone = .right
                }
            }
            guard enabledZones.contains(zone) else { return nil }

            let along: CGFloat
            if zone.isHorizontalEdge {
                along = (point.x - frame.minX - horizontalCorner)
                    / max(frame.width - 2 * horizontalCorner, 1)
            } else if zone.isVerticalEdge {
                along = (frame.maxY - verticalCorner - point.y)
                    / max(frame.height - 2 * verticalCorner, 1)
            } else {
                along = 0
            }
            let action = layout.action(for: zone, along: along)
            let targetFrame = WindowLayoutGeometry.rect(for: action,
                                                        current: screen.visibleFrame,
                                                        visibleFrame: screen.visibleFrame,
                                                        windowGap: WindowLayoutGaps.windowGap,
                                                        screenGap: WindowLayoutGaps.screenGap,
                                                        marginPercent: WindowLayoutMargin.percent)
            return WindowEdgeSnapTarget(zone: zone,
                                        action: action,
                                        frame: targetFrame.integral,
                                        visibleFrame: screen.visibleFrame)
        }
        return nil
    }

    private static func horizontalCornerWidth(for frame: CGRect) -> CGFloat {
        min(max(frame.width * 0.18, 96), 180)
    }

    private static func topZone(atX x: CGFloat, in frame: CGRect) -> WindowEdgeSnapZone {
        let cornerWidth = horizontalCornerWidth(for: frame)
        if x <= frame.minX + cornerWidth { return .topLeft }
        if x >= frame.maxX - cornerWidth { return .topRight }
        return .top
    }

    private static func sharesPerpendicularEdges(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let sharesVerticalEdge = abs(lhs.minX - rhs.minX) <= sizeTolerance
            || abs(lhs.maxX - rhs.maxX) <= sizeTolerance
        let sharesHorizontalEdge = abs(lhs.minY - rhs.minY) <= sizeTolerance
            || abs(lhs.maxY - rhs.maxY) <= sizeTolerance
        return sharesVerticalEdge && sharesHorizontalEdge
    }

    /// Which display an AppKit coordinate belongs to. The pointer lives in
    /// Quartz space, where each display owns its left and top rows, so a seam
    /// coordinate belongs to the display on its right or, once y is flipped,
    /// to the one below it.
    private static func holds(_ frame: CGRect, _ point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x < frame.maxX
            && point.y > frame.minY && point.y <= frame.maxY
    }

    private static func distanceSquared(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return dx * dx + dy * dy
    }
}

/// The pointer layout mode also accepts a held modifier chord. Ordinary global
/// shortcuts retain their key requirement and their existing storage format.
enum WindowDirectionalTrigger: Equatable {
    case key(GlobalShortcut)
    case modifiers(GlobalShortcutModifiers)

    init?(storageValue: String) {
        if storageValue.hasPrefix("modifiers:") {
            let tokens = storageValue.dropFirst("modifiers:".count).split(separator: "+", omittingEmptySubsequences: false)
            var modifiers: GlobalShortcutModifiers = []
            for token in tokens {
                switch token {
                case "control": modifiers.insert(.control)
                case "option": modifiers.insert(.option)
                case "shift": modifiers.insert(.shift)
                case "command": modifiers.insert(.command)
                default: return nil
                }
            }
            guard modifiers.isValidWindowDirectionalTrigger else { return nil }
            self = .modifiers(modifiers)
        } else {
            guard let shortcut = GlobalShortcut(storageValue: storageValue) else { return nil }
            self = .key(shortcut)
        }
    }

    var storageValue: String {
        switch self {
        case .key(let shortcut): return shortcut.storageValue
        case .modifiers(let modifiers): return "modifiers:" + modifiers.storageTokens.joined(separator: "+")
        }
    }

    var displayString: String {
        switch self {
        case .key(let shortcut): return shortcut.displayString
        case .modifiers(let modifiers): return modifiers.keyCaps.joined()
        }
    }
}

extension GlobalShortcutModifiers {
    /// A bare Command, Option or Control chord collides with ordinary app
    /// shortcuts and modifier-clicks. Shift may join a trigger, but it does
    /// not make a single primary modifier safe on its own.
    var isValidWindowDirectionalTrigger: Bool {
        intersection([.control, .option, .command]).rawValue.nonzeroBitCount >= 2
    }
}

/// Passive policy for the modifier chord that arms pointer layout. Modifier
/// changes and shortcut-cancelling keys are observed without holding the event
/// while the main queue looks up or places a window.
enum WindowDirectionalModifierTapSupport {
    static let options: CGEventTapOptions = .listenOnly
    static let eventMask: CGEventMask = {
        let events: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .leftMouseUp,
                                     .rightMouseDown, .rightMouseUp, .otherMouseDown,
                                     .otherMouseUp, .scrollWheel]
        return events.reduce(CGEventMask(0)) { mask, event in
            mask | (CGEventMask(1) << event.rawValue)
        }
    }()

    static func afterCallback(_ work: @escaping () -> Void) {
        DispatchQueue.main.async { work() }
    }
}

/// Native modifier-click, scroll and keyboard input always wins over a
/// modifier-only pointer layout. Kept pure so input custody stays covered
/// without manufacturing system-wide events in tests.
enum WindowDirectionalModifierInputPolicy {
    static func canBegin(mouseButtonPressed: Bool,
                         pointerInputSinceArm: Bool) -> Bool {
        !mouseButtonPressed && !pointerInputSinceArm
    }

    static func cancelsAndPassesThrough(_ type: CGEventType) -> Bool {
        switch type {
        case .scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown: return true
        default: return false
        }
    }
}

/// Button history follows the same passive stream as the chord. A button
/// released before a delayed callback still counts as held at the chord's press.
struct WindowDirectionalModifierButtons {
    private(set) var mask: UInt32 = 0
    var isPressed: Bool { mask != 0 }

    static func current() -> Self {
        var state = Self()
        for index in 0..<32 {
            if let button = CGMouseButton(rawValue: UInt32(index)),
               CGEventSource.buttonState(.combinedSessionState, button: button) {
                state.mask |= UInt32(1) << index
            }
        }
        return state
    }

    mutating func observe(_ type: CGEventType, buttonNumber: Int64) {
        let button: Int64
        let isDown: Bool
        switch type {
        case .leftMouseDown: (button, isDown) = (0, true)
        case .leftMouseUp: (button, isDown) = (0, false)
        case .rightMouseDown: (button, isDown) = (1, true)
        case .rightMouseUp: (button, isDown) = (1, false)
        case .otherMouseDown: (button, isDown) = (buttonNumber, true)
        case .otherMouseUp: (button, isDown) = (buttonNumber, false)
        default: return
        }
        guard (0..<32).contains(button) else { return }
        let bit = UInt32(1) << Int(button)
        if isDown { mask |= bit } else { mask &= ~bit }
    }
}

/// Event-source counters catch a quick click or scroll that completes while
/// the main queue is still waiting to start the deferred gesture. Reading the
/// counters also catches input that arrives during synchronous target lookup.
struct WindowDirectionalModifierPointerSnapshot: Equatable {
    let leftMouseDown: UInt32
    let rightMouseDown: UInt32
    let otherMouseDown: UInt32
    let scrollWheel: UInt32

    static func current() -> Self {
        Self(
            leftMouseDown: CGEventSource.counterForEventType(
                .combinedSessionState, eventType: .leftMouseDown),
            rightMouseDown: CGEventSource.counterForEventType(
                .combinedSessionState, eventType: .rightMouseDown),
            otherMouseDown: CGEventSource.counterForEventType(
                .combinedSessionState, eventType: .otherMouseDown),
            scrollWheel: CGEventSource.counterForEventType(
                .combinedSessionState, eventType: .scrollWheel)
        )
    }

    func hasPointerInput(since earlier: Self) -> Bool {
        self != earlier
    }
}

enum WindowDirectionalModifierStartupOutcome<Value> {
    case ready(Value)
    case cancelled
    case observationFailed
    case targetUnavailable
}

/// Orders the active observation and custody checks around target lookup. The
/// injected seams let tests introduce pointer input at either race boundary
/// without posting real system events.
enum WindowDirectionalModifierStartupGuard {
    static func resolve<Value>(
        armedAt: WindowDirectionalModifierPointerSnapshot?,
        currentSnapshot: () -> WindowDirectionalModifierPointerSnapshot,
        mouseButtonPressed: () -> Bool,
        startObserving: () -> Bool,
        isCurrent: () -> Bool = { true },
        lookupTarget: () -> Value?
    ) -> WindowDirectionalModifierStartupOutcome<Value> {
        func canContinue() -> Bool {
            guard isCurrent() else { return false }
            let pointerInputSinceArm = armedAt.map {
                currentSnapshot().hasPointerInput(since: $0)
            } ?? false
            return WindowDirectionalModifierInputPolicy.canBegin(
                mouseButtonPressed: mouseButtonPressed(),
                pointerInputSinceArm: pointerInputSinceArm)
        }

        guard canContinue() else { return .cancelled }
        guard startObserving() else { return .observationFailed }
        guard canContinue() else { return .cancelled }
        guard let target = lookupTarget() else { return .targetUnavailable }
        guard canContinue() else { return .cancelled }
        return .ready(target)
    }
}

/// A modifier chord starts once, finishes on its first required-key release,
/// and cannot restart until all its keys are up. Extra modifiers cancel it.
struct WindowDirectionalModifierOwnership: Equatable {
    let registrationID: UUID
    let generation: UInt64
}

struct WindowDirectionalModifierHold {
    enum Decision { case none, begin, finish, cancel }
    let expected: GlobalShortcutModifiers
    private let registrationID = UUID()
    var ownership: WindowDirectionalModifierOwnership {
        WindowDirectionalModifierOwnership(registrationID: registrationID, generation: generation)
    }
    private(set) var generation: UInt64 = 0
    private var active = false
    private var waitingForRelease: Bool
    private var held: GlobalShortcutModifiers

    init(expected: GlobalShortcutModifiers, initiallyHeld: GlobalShortcutModifiers = []) {
        self.expected = expected
        held = initiallyHeld
        waitingForRelease = !initiallyHeld.isEmpty
    }

    mutating func cancel() {
        generation &+= 1
        active = false
        waitingForRelease = true
    }

    mutating func cancelForKeyPress() -> Bool {
        cancelForInput()
    }

    mutating func cancelForInput() -> Bool {
        guard active || !held.isEmpty else { return false }
        cancel()
        return true
    }

    mutating func update(_ held: GlobalShortcutModifiers) -> Decision {
        self.held = held
        if active {
            guard held == expected else {
                let released = !held.isSuperset(of: expected)
                cancel()
                waitingForRelease = !held.isEmpty
                return released ? .finish : .cancel
            }
        } else if waitingForRelease {
            waitingForRelease = !held.isEmpty
        } else if !held.subtracting(expected).isEmpty {
            // Once an unrelated modifier joins this physical hold, releasing
            // it must not turn the remainder into a fresh trigger chord.
            cancel()
            waitingForRelease = !held.isEmpty
            return .cancel
        } else if held == expected {
            generation &+= 1
            active = true
            return .begin
        }
        return .none
    }
}

enum WindowDirectionalModifierCancellation {
    case cancelHold
    case preserveHold

    func applied(to hold: WindowDirectionalModifierHold) -> WindowDirectionalModifierHold {
        guard self == .cancelHold else { return hold }
        var cancelled = hold
        cancelled.cancel()
        return cancelled
    }
}
