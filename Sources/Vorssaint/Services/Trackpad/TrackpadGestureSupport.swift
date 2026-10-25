// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What a finished multi-finger touch did on the trackpad. Raw values are part
/// of the persisted mapping keys; never rename them.
enum TrackpadGestureKind: String, CaseIterable {
    case tap
    case swipeLeft = "swipe-left"
    case swipeRight = "swipe-right"
    case swipeUp = "swipe-up"
    case swipeDown = "swipe-down"
    case pinchIn = "pinch-in"
    case pinchOut = "pinch-out"

    var symbolName: String {
        switch self {
        case .tap: return "hand.tap"
        case .swipeLeft: return "arrow.left"
        case .swipeRight: return "arrow.right"
        case .swipeUp: return "arrow.up"
        case .swipeDown: return "arrow.down"
        case .pinchIn: return "arrow.down.right.and.arrow.up.left"
        case .pinchOut: return "arrow.up.left.and.arrow.down.right"
        }
    }

    /// The finger counts each kind is offered with. Nobody pinches reliably
    /// with three fingers, so pinches start at four.
    var fingerCounts: [Int] {
        switch self {
        case .pinchIn, .pinchOut: return [4, 5]
        case .tap, .swipeLeft, .swipeRight, .swipeUp, .swipeDown: return [3, 4, 5]
        }
    }
}

/// One mappable gesture: a kind performed with a number of fingers.
struct TrackpadGesture: Hashable {
    let kind: TrackpadGestureKind
    let fingers: Int

    init?(kind: TrackpadGestureKind, fingers: Int) {
        guard kind.fingerCounts.contains(fingers) else { return nil }
        self.kind = kind
        self.fingers = fingers
    }

    /// The stable identity persisted as a mapping key, such as `swipe-left-4`.
    var key: String { "\(kind.rawValue)-\(fingers)" }

    init?(key: String) {
        guard let dash = key.lastIndex(of: "-"),
              let fingers = Int(key[key.index(after: dash)...]),
              let kind = TrackpadGestureKind(rawValue: String(key[..<dash])) else { return nil }
        self.init(kind: kind, fingers: fingers)
    }

    /// Every gesture, grouped by finger count and then by kind, the order
    /// Settings lists them in.
    static let all: [TrackpadGesture] = (3...5).flatMap { fingers in
        TrackpadGestureKind.allCases.compactMap { TrackpadGesture(kind: $0, fingers: fingers) }
    }
}

/// Who answers a tap that another feature already owns. The middle click's
/// tap and the radial menu's four-finger tap predate gestures and keep their
/// meaning; a mapping on the same tap never fires on top of them.
enum TrackpadTapOwner: Equatable {
    case middleClick
    case radialMenu
}

/// Where a recognized gesture goes.
enum TrackpadGestureRoute: Equatable {
    case middleClick
    case radialMenu
    case mapping
    /// Owned by the middle click, but macOS's three-finger drag owns three
    /// fingers and synthesizes its own clicks, so nothing fires.
    case dropped
}

/// What macOS does with a gesture set in Trackpad, More Gestures.
enum TrackpadSystemAction: Equatable {
    case spaces, missionControl, appExpose, launchpad, showDesktop
}

/// Where in System Settings a gesture macOS already uses can be freed.
enum TrackpadSystemClaim: Equatable {
    /// Trackpad, More Gestures, and what macOS does with the gesture.
    case moreGestures(TrackpadSystemAction)
    /// Trackpad, Point & Click, Look up & data detectors.
    case lookUp
    /// Accessibility, Pointer Control, Trackpad Options, dragging style.
    case threeFingerDrag
}

/// The system's own trackpad gesture settings, as far as they decide which
/// gestures macOS consumes. Nil means the preference was never written.
struct TrackpadSystemGestureSettings: Equatable {
    var threeFingerHorizontalSwipe: Int?
    var fourFingerHorizontalSwipe: Int?
    var threeFingerVerticalSwipe: Int?
    var fourFingerVerticalSwipe: Int?
    var fourFingerPinch: Int?
    var fiveFingerPinch: Int?
    var threeFingerTap: Int?
    var threeFingerDrag: Bool?
    var missionControlGesture: Bool?
    var appExposeGesture: Bool?
    var launchpadGesture: Bool?
    var showDesktopGesture: Bool?

    /// Trackpad preference names, read from both the built-in and the
    /// Bluetooth trackpad domains.
    static let trackpadKeys = [
        "TrackpadThreeFingerHorizSwipeGesture", "TrackpadFourFingerHorizSwipeGesture",
        "TrackpadThreeFingerVertSwipeGesture", "TrackpadFourFingerVertSwipeGesture",
        "TrackpadFourFingerPinchGesture", "TrackpadFiveFingerPinchGesture",
        "TrackpadThreeFingerTapGesture", "TrackpadThreeFingerDrag",
    ]

    /// Dock preference names that switch the overviews' gestures on and off.
    static let dockKeys = [
        "showMissionControlGestureEnabled", "showAppExposeGestureEnabled",
        "showLaunchpadGestureEnabled", "showDesktopGestureEnabled",
    ]

    init(threeFingerHorizontalSwipe: Int? = nil, fourFingerHorizontalSwipe: Int? = nil,
         threeFingerVerticalSwipe: Int? = nil, fourFingerVerticalSwipe: Int? = nil,
         fourFingerPinch: Int? = nil, fiveFingerPinch: Int? = nil, threeFingerTap: Int? = nil,
         threeFingerDrag: Bool? = nil, missionControlGesture: Bool? = nil,
         appExposeGesture: Bool? = nil, launchpadGesture: Bool? = nil,
         showDesktopGesture: Bool? = nil) {
        self.threeFingerHorizontalSwipe = threeFingerHorizontalSwipe
        self.fourFingerHorizontalSwipe = fourFingerHorizontalSwipe
        self.threeFingerVerticalSwipe = threeFingerVerticalSwipe
        self.fourFingerVerticalSwipe = fourFingerVerticalSwipe
        self.fourFingerPinch = fourFingerPinch
        self.fiveFingerPinch = fiveFingerPinch
        self.threeFingerTap = threeFingerTap
        self.threeFingerDrag = threeFingerDrag
        self.missionControlGesture = missionControlGesture
        self.appExposeGesture = appExposeGesture
        self.launchpadGesture = launchpadGesture
        self.showDesktopGesture = showDesktopGesture
    }

    /// Builds the settings from raw preference values. `trackpad` answers a
    /// trackpad key from either domain, `dock` a Dock key.
    init(trackpad: (String) -> Int?, dock: (String) -> Bool?) {
        self.init(threeFingerHorizontalSwipe: trackpad("TrackpadThreeFingerHorizSwipeGesture"),
                  fourFingerHorizontalSwipe: trackpad("TrackpadFourFingerHorizSwipeGesture"),
                  threeFingerVerticalSwipe: trackpad("TrackpadThreeFingerVertSwipeGesture"),
                  fourFingerVerticalSwipe: trackpad("TrackpadFourFingerVertSwipeGesture"),
                  fourFingerPinch: trackpad("TrackpadFourFingerPinchGesture"),
                  fiveFingerPinch: trackpad("TrackpadFiveFingerPinchGesture"),
                  threeFingerTap: trackpad("TrackpadThreeFingerTapGesture"),
                  threeFingerDrag: trackpad("TrackpadThreeFingerDrag").map { $0 != 0 },
                  missionControlGesture: dock("showMissionControlGestureEnabled"),
                  appExposeGesture: dock("showAppExposeGestureEnabled"),
                  launchpadGesture: dock("showLaunchpadGestureEnabled"),
                  showDesktopGesture: dock("showDesktopGestureEnabled"))
    }

    /// Merges the same key read from the built-in and the Bluetooth trackpad
    /// domains: either one switching a gesture on means macOS uses it.
    static func merged(_ values: [Int?]) -> Int? {
        let present = values.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        return present.first(where: { $0 != 0 }) ?? 0
    }
}

/// The pure half of trackpad gestures: how a stream of contact frames becomes
/// one gesture, which feature a gesture belongs to, and which gestures macOS
/// already uses. Nothing here reads a device or a preference, so every rule is
/// provable without a trackpad.
enum TrackpadGestureSupport {
    // MARK: - Calibration
    //
    // The tap thresholds are the middle click's, which a real hand already
    // tuned. The swipe and pinch thresholds are in normalized trackpad units
    // (0...1 across the pad) and come from about 140 touches measured on a
    // MacBook Pro's built-in trackpad; they live together so tuning never
    // means hunting.

    static let tapMaxDuration = MiddleClickSupport.tapMaxDuration
    static let tapMovementLimit = MiddleClickSupport.tapMovementLimit
    static let tapSpreadChangeLimit = MiddleClickSupport.tapSpreadChangeLimit
    static let keyboardIdle = MiddleClickSupport.tapKeyboardIdle

    /// How far the fingers' average position must travel along one axis for
    /// the touch to count as a swipe. Quick natural swipes measured 0.10 to
    /// 0.29 (median 0.15); taps stay under 0.03.
    static let swipeMovementThreshold: Float = 0.08

    /// How much the fingers' spread must change for the touch to count as a
    /// pinch. Pinches measured 0.056 to 0.165 (median 0.10); a tap's spread
    /// stays under `tapSpreadChangeLimit`.
    static let pinchSpreadThreshold: Float = 0.05

    /// How much longer a swipe's travel must be than its change of spread.
    /// A sliding hand closes or fans out a little (up to 0.38 of its travel,
    /// measured) and a pinch drags the average position along (up to 0.9 of
    /// its change of spread), so the two are told apart by which one
    /// outweighs the other, not by either threshold alone: a swipe travels
    /// at least this many times its spread change, a pinch changes its spread
    /// by at least its travel, and a touch in between fires nothing.
    static let swipeOverPinchDominance: Float = 2

    /// How much longer the main axis of a swipe must be than the other one.
    /// A diagonal stroke is ambiguous and fires nothing.
    static let axisDominance: Float = 1.5

    /// A touch that lasts longer than this was resting fingers, not a gesture.
    static let maxGestureDuration: TimeInterval = 1.5

    /// Own shortcuts never erase a physical press, even when the two arrive
    /// together. A changed system counter falls back to treating an unseen
    /// key as typing rather than trusting an older own event.
    struct TypingState {
        private var lastTypingUptime: TimeInterval
        private var ownKeyDownCounter: UInt32?

        init(now: TimeInterval = 0, sinceLastKeyDown: TimeInterval = .infinity) {
            lastTypingUptime = now - sinceLastKeyDown
        }

        mutating func keyDown(isOwn: Bool, now: TimeInterval, counter: UInt32) {
            ownKeyDownCounter = isOwn ? counter : nil
            if !isOwn { lastTypingUptime = max(lastTypingUptime, now) }
        }

        mutating func secondsSinceTyping(now: TimeInterval, sinceLastKeyDown: TimeInterval,
                                         counter: UInt32, canObserveTyping: Bool) -> TimeInterval {
            if !canObserveTyping || ownKeyDownCounter != counter {
                lastTypingUptime = max(lastTypingUptime, now - sinceLastKeyDown)
            }
            return max(0, now - lastTypingUptime)
        }
    }

    // MARK: - Contacts

    /// Average position and spread of the touching fingers, in normalized
    /// trackpad units. Y grows upward, as MultitouchSupport reports it.
    struct Geometry: Equatable {
        var x: Float
        var y: Float
        var spread: Float
    }

    /// A finished touch, reduced to what the decision needs.
    struct Contact: Equatable {
        /// The most fingers that were down together.
        var fingers: Int
        /// Seconds from the moment that many fingers were down to the lift.
        var duration: TimeInterval
        /// Seconds from the first finger down to the lift.
        var contactDuration: TimeInterval
        /// Largest travel of the average position along either axis.
        var maxMovement: Float
        /// Travel of the average position between the first and the last
        /// frame with every finger down.
        var deltaX: Float
        var deltaY: Float
        /// Largest change of the spread, and its change over the gesture.
        var maxSpreadChange: Float
        var spreadDelta: Float
        /// A finger joined a gesture already in motion, or positions could
        /// not be read: the touch means nothing reliable.
        var cancelled: Bool
        /// A physical click happened while the fingers were down.
        var buttonPressed: Bool = false
        var secondsSinceLastKeyDown: TimeInterval = .infinity
    }

    /// Decides which gesture a finished touch was, or none.
    static func judge(_ contact: Contact) -> TrackpadGesture? {
        guard contact.fingers >= 3, contact.fingers <= 5,
              !contact.cancelled, !contact.buttonPressed,
              contact.secondsSinceLastKeyDown >= keyboardIdle,
              contact.duration > 0 else { return nil }
        if contact.duration <= tapMaxDuration,
           contact.maxMovement <= tapMovementLimit,
           contact.maxSpreadChange <= tapSpreadChangeLimit {
            return TrackpadGesture(kind: .tap, fingers: contact.fingers)
        }
        guard contact.duration <= maxGestureDuration else { return nil }
        let horizontal = abs(contact.deltaX)
        let vertical = abs(contact.deltaY)
        let travel = max(horizontal, vertical)
        let spreadChange = abs(contact.spreadDelta)
        if travel >= swipeMovementThreshold, travel >= spreadChange * swipeOverPinchDominance {
            if horizontal >= vertical * axisDominance {
                return TrackpadGesture(kind: contact.deltaX > 0 ? .swipeRight : .swipeLeft,
                                       fingers: contact.fingers)
            }
            if vertical >= horizontal * axisDominance {
                return TrackpadGesture(kind: contact.deltaY > 0 ? .swipeUp : .swipeDown,
                                       fingers: contact.fingers)
            }
            return nil
        }
        if spreadChange >= pinchSpreadThreshold, spreadChange >= travel {
            return TrackpadGesture(kind: contact.spreadDelta < 0 ? .pinchIn : .pinchOut,
                                   fingers: contact.fingers)
        }
        return nil
    }

    // MARK: - Ownership

    /// Taps that already belong to another feature, by finger count. The
    /// middle click's own tap wins a tie, as it always has.
    static func tapReservations(middleClickTapFingers: Int,
                                radialMenuTapFingers: Int) -> [Int: TrackpadTapOwner] {
        var owners: [Int: TrackpadTapOwner] = [:]
        if middleClickTapFingers == 3 || middleClickTapFingers == 4 {
            owners[middleClickTapFingers] = .middleClick
        }
        if radialMenuTapFingers == 4, owners[4] == nil {
            owners[4] = .radialMenu
        }
        return owners
    }

    /// Where a recognized gesture goes. A reserved tap answers its owner and
    /// never a mapping, so turning gestures on changes neither feature.
    static func route(_ gesture: TrackpadGesture,
                      reservations: [Int: TrackpadTapOwner],
                      systemDragGestureEnabled: Bool) -> TrackpadGestureRoute {
        guard gesture.kind == .tap, let owner = reservations[gesture.fingers] else { return .mapping }
        switch owner {
        case .middleClick:
            return gesture.fingers == 3 && systemDragGestureEnabled ? .dropped : .middleClick
        case .radialMenu:
            return .radialMenu
        }
    }

    // MARK: - System gestures

    /// The gestures macOS acts on as well, and where each can be freed. A
    /// preference that was never written is read as its macOS default: swipes,
    /// pinches and Mission Control on, App Exposé, Look Up by tap and
    /// three-finger drag off. macOS has no five-finger swipe setting: it
    /// answers its four-finger swipes with five fingers as well.
    static func systemClaims(_ settings: TrackpadSystemGestureSettings) -> [TrackpadGesture: TrackpadSystemClaim] {
        var claims: [TrackpadGesture: TrackpadSystemClaim] = [:]
        func claim(_ kind: TrackpadGestureKind, _ fingers: Int, _ value: Int?,
                   _ action: TrackpadSystemAction, when enabled: Bool = true) {
            guard enabled, (value ?? 2) != 0,
                  let gesture = TrackpadGesture(kind: kind, fingers: fingers) else { return }
            claims[gesture] = .moreGestures(action)
        }
        let missionControl = settings.missionControlGesture ?? true
        let appExpose = settings.appExposeGesture ?? false
        let launchpad = settings.launchpadGesture ?? true
        let showDesktop = settings.showDesktopGesture ?? true
        for (fingers, horizontal, vertical) in [
            (3, settings.threeFingerHorizontalSwipe, settings.threeFingerVerticalSwipe),
            (4, settings.fourFingerHorizontalSwipe, settings.fourFingerVerticalSwipe),
            (5, settings.fourFingerHorizontalSwipe, settings.fourFingerVerticalSwipe),
        ] {
            claim(.swipeLeft, fingers, horizontal, .spaces)
            claim(.swipeRight, fingers, horizontal, .spaces)
            claim(.swipeUp, fingers, vertical, .missionControl, when: missionControl)
            claim(.swipeDown, fingers, vertical, .appExpose, when: appExpose)
        }
        for (fingers, pinch) in [(4, settings.fourFingerPinch), (5, settings.fiveFingerPinch)] {
            claim(.pinchIn, fingers, pinch, .launchpad, when: launchpad)
            claim(.pinchOut, fingers, pinch, .showDesktop, when: showDesktop)
        }
        if (settings.threeFingerTap ?? 0) != 0, let tap = TrackpadGesture(kind: .tap, fingers: 3) {
            claims[tap] = .lookUp
        }
        if settings.threeFingerDrag ?? false {
            for gesture in TrackpadGesture.all where gesture.fingers == 3 {
                claims[gesture] = .threeFingerDrag
            }
        }
        return claims
    }
}

/// Turns the stream of contact frames into finished touches. A value type fed
/// under its owner's lock on the multitouch thread; it never reads the clock,
/// a device or a preference itself.
struct TrackpadGestureRecognizer {
    private var fingers = 0
    private var contactStart: TimeInterval?
    private var candidateStart: TimeInterval = 0
    private var start: TrackpadGestureSupport.Geometry?
    private var last: TrackpadGestureSupport.Geometry?
    private var maxMovement: Float = 0
    private var maxSpreadChange: Float = 0
    private var cancelled = false

    /// Whether a touch is in progress.
    var isTracking: Bool { contactStart != nil }

    /// Feeds one frame: how many fingers touch, where (nil when positions are
    /// unreadable) and when. Returns the finished touch once every finger has
    /// lifted; the caller adds what it knows about clicks and typing and asks
    /// `TrackpadGestureSupport.judge`.
    mutating func feed(count: Int,
                       geometry: TrackpadGestureSupport.Geometry?,
                       now: TimeInterval) -> TrackpadGestureSupport.Contact? {
        if count <= 0 {
            defer { self = TrackpadGestureRecognizer() }
            guard let contactStart, fingers > 0 else { return nil }
            let first = start ?? TrackpadGestureSupport.Geometry(x: 0, y: 0, spread: 0)
            let final = last ?? first
            return TrackpadGestureSupport.Contact(
                fingers: fingers,
                duration: now - candidateStart,
                contactDuration: now - contactStart,
                maxMovement: maxMovement,
                deltaX: final.x - first.x,
                deltaY: final.y - first.y,
                maxSpreadChange: maxSpreadChange,
                spreadDelta: final.spread - first.spread,
                cancelled: cancelled)
        }
        if contactStart == nil { contactStart = now }
        if cancelled { return nil }
        guard let geometry else {
            cancelled = true
            return nil
        }
        if count > fingers {
            // Fingers rarely land together: a larger count takes over while
            // the hand is still, but a finger joining a multi-finger gesture
            // already in motion makes the whole touch ambiguous. One or two
            // fingers moving first are pointing or scrolling, as before.
            if fingers >= 3, maxMovement > TrackpadGestureSupport.tapMovementLimit
                || maxSpreadChange > TrackpadGestureSupport.tapSpreadChangeLimit {
                cancelled = true
                return nil
            }
            fingers = count
            candidateStart = now
            start = geometry
            last = geometry
            maxMovement = 0
            maxSpreadChange = 0
            return nil
        }
        // Fingers lifting at the end move the average position; only frames
        // with every finger down describe the gesture.
        guard count == fingers, let start else { return nil }
        maxMovement = max(maxMovement, max(abs(geometry.x - start.x), abs(geometry.y - start.y)))
        maxSpreadChange = max(maxSpreadChange, abs(geometry.spread - start.spread))
        last = geometry
        return nil
    }
}
