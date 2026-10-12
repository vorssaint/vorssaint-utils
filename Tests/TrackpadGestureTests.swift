// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Gesture recognition, routing and system-gesture claims, fed with synthetic
/// contact frames so every rule runs without a trackpad.
enum TrackpadGestureTests {
    typealias Geometry = TrackpadGestureSupport.Geometry

    /// Lands `fingers` fingers in staggered frames, moves the average position
    /// and spread linearly over `duration`, then lifts them one by one.
    static func contact(fingers: Int,
                        duration: TimeInterval = 0.2,
                        dx: Float = 0, dy: Float = 0, spreadChange: Float = 0,
                        startSpread: Float = 0.2,
                        frames: Int = 20,
                        unreadableAt: Int? = nil) -> TrackpadGestureSupport.Contact? {
        var recognizer = TrackpadGestureRecognizer()
        var now: TimeInterval = 100
        let origin = Geometry(x: 0.5, y: 0.5, spread: startSpread)
        for landing in 1...fingers {
            _ = recognizer.feed(count: landing, geometry: origin, now: now)
            now += 0.005
        }
        for frame in 0...frames {
            let progress = Float(frame) / Float(frames)
            let geometry = frame == unreadableAt ? nil : Geometry(x: origin.x + dx * progress,
                                                                  y: origin.y + dy * progress,
                                                                  spread: origin.spread + spreadChange * progress)
            _ = recognizer.feed(count: fingers, geometry: geometry, now: now)
            now += duration / Double(frames)
        }
        // Lifting fingers shift the average position; it must not count.
        for lifting in stride(from: fingers - 1, through: 1, by: -1) {
            _ = recognizer.feed(count: lifting, geometry: Geometry(x: 0.9, y: 0.1, spread: 0), now: now)
            now += 0.005
        }
        return recognizer.feed(count: 0, geometry: nil, now: now)
    }

    static func gesture(_ contact: TrackpadGestureSupport.Contact?) -> String? {
        contact.flatMap(TrackpadGestureSupport.judge)?.key
    }

    static func run(_ suite: TestSuite) {
        // MARK: Catalog and keys
        suite.expect(TrackpadGesture.all.count == 19,
                     "taps and swipes for three to five fingers plus four and five finger pinches")
        suite.expect(Set(TrackpadGesture.all.map(\.key)).count == TrackpadGesture.all.count,
                     "every gesture has its own key")
        suite.expect(TrackpadGesture.all.allSatisfy { TrackpadGesture(key: $0.key) == $0 },
                     "every key reads back as its gesture")
        suite.expect(TrackpadGesture(key: "swipe-left-4") == TrackpadGesture(kind: .swipeLeft, fingers: 4),
                     "keys spell kind then finger count")
        suite.expect(TrackpadGesture(key: "pinch-in-3") == nil && TrackpadGesture(key: "tap-2") == nil
                        && TrackpadGesture(key: "wave-3") == nil && TrackpadGesture(key: "tap") == nil,
                     "unknown kinds and unoffered finger counts are rejected")
        suite.expect(TrackpadGesture.all.first?.key == "tap-3" && TrackpadGesture.all.last?.key == "pinch-out-5",
                     "Settings lists gestures by finger count, taps first")

        // MARK: Recognition
        let gestureTap3Fixture = TrackpadGesture(kind: .tap, fingers: 3)!
        for fingers in 3...5 {
            suite.expect(gesture(contact(fingers: fingers)) == "tap-\(fingers)",
                         "a brief still touch of \(fingers) fingers is a tap")
        }
        suite.expect(gesture(contact(fingers: 2)) == nil && gesture(contact(fingers: 6)) == nil,
                     "two fingers and a resting palm are never gestures")
        suite.expect(gesture(contact(fingers: 3, dx: 0.3)) == "swipe-right-3"
                        && gesture(contact(fingers: 4, dx: -0.3)) == "swipe-left-4"
                        && gesture(contact(fingers: 5, dy: 0.25)) == "swipe-up-5"
                        && gesture(contact(fingers: 3, dy: -0.25)) == "swipe-down-3",
                     "a swipe follows the fingers' direction, with y growing upward")
        suite.expect(gesture(contact(fingers: 4, duration: 0.6, dx: 0.3)) == "swipe-right-4",
                     "a deliberate swipe longer than a tap still fires")
        suite.expect(gesture(contact(fingers: 3, dx: 0.2, dy: 0.18)) == nil,
                     "a diagonal stroke with no dominant axis fires nothing")
        suite.expect(gesture(contact(fingers: 3, dx: 0.06)) == nil,
                     "a short slide is neither a tap nor a swipe")
        suite.expect(gesture(contact(fingers: 4, spreadChange: -0.12)) == "pinch-in-4"
                        && gesture(contact(fingers: 5, spreadChange: 0.12)) == "pinch-out-5",
                     "fingers closing or spreading around a still center are a pinch")
        suite.expect(gesture(contact(fingers: 3, spreadChange: -0.12)) == nil,
                     "three fingers have no pinch")
        suite.expect(gesture(contact(fingers: 4, dx: 0.3, spreadChange: 0.12)) == nil,
                     "a touch that is both a swipe and a pinch is ambiguous and fires nothing")
        suite.expect(gesture(contact(fingers: 4, duration: 2.0, dx: 0.3)) == nil,
                     "fingers resting long before moving are not a gesture")
        suite.expect(gesture(contact(fingers: 4, unreadableAt: 5)) == nil,
                     "unreadable positions drop the touch instead of guessing")

        if var contact = contact(fingers: 4) {
            contact.buttonPressed = true
            suite.expect(TrackpadGestureSupport.judge(contact) == nil,
                         "a physical click during the touch is a click, not a gesture")
            contact.buttonPressed = false
            contact.secondsSinceLastKeyDown = 0.2
            suite.expect(TrackpadGestureSupport.judge(contact) == nil,
                         "contact right after typing is ignored")
            contact.secondsSinceLastKeyDown = TrackpadGestureSupport.keyboardIdle
            suite.expect(TrackpadGestureSupport.judge(contact)?.key == "tap-4",
                         "the keyboard pause ends at the same delay as the middle-click tap")
        } else {
            suite.expect(false, "a four-finger touch produces a contact")
        }

        // MARK: Middle click tap (issue #161), now judged here
        func still(fingers: Int = 3, duration: TimeInterval = 0.15, movement: Float = 0.01,
                   spread: Float = 0.01, keyDown: TimeInterval = .infinity,
                   button: Bool = false, unreadable: Bool = false) -> String? {
            TrackpadGestureSupport.judge(TrackpadGestureSupport.Contact(
                fingers: fingers, duration: duration, contactDuration: duration + 0.02,
                maxMovement: movement, deltaX: movement, deltaY: 0,
                maxSpreadChange: spread, spreadDelta: spread, cancelled: unreadable,
                buttonPressed: button, secondsSinceLastKeyDown: keyDown))?.key
        }
        let middleTap = [3: TrackpadTapOwner.middleClick]
        suite.expect(still() == "tap-3"
                        && TrackpadGestureSupport.route(gestureTap3Fixture, reservations: middleTap,
                                                        systemDragGestureEnabled: false) == .middleClick,
                     "a quick still three-finger tap fires")
        suite.expect(still(keyDown: 0.1) == nil, "stray trackpad contact while typing never fires a middle click")
        suite.expect(still(keyDown: 1.0) == "tap-3", "tap to middle click resumes after keyboard activity settles")
        suite.expect(still(movement: 0.2) != "tap-3", "a swipe never fires the tap")
        suite.expect(still(duration: 0.8) == nil, "resting fingers never fire the tap")
        suite.expect(still(button: true) == nil, "a physical click during the touch belongs to the press path")
        suite.expect(still(fingers: 4) != "tap-3",
                     "a fourth finger makes a four-finger tap, never the three-finger middle click")
        suite.expect(still(unreadable: true) == nil, "unreadable touch positions stand the tap down")
        suite.expect(TrackpadGestureSupport.route(TrackpadGesture(kind: .tap, fingers: 4)!,
                                                  reservations: [4: .middleClick],
                                                  systemDragGestureEnabled: true) == .middleClick,
                     "four-finger tap stays available alongside the system drag gesture")
        suite.expect(still(fingers: 4, spread: 0.2) != "tap-4",
                     "a pinch or spread never fires the tap even with a still centroid")

        // Staggered landing versus a finger joining a moving gesture.
        var staggered = TrackpadGestureRecognizer()
        let stillPose = Geometry(x: 0.5, y: 0.5, spread: 0.2)
        _ = staggered.feed(count: 3, geometry: stillPose, now: 0)
        _ = staggered.feed(count: 3, geometry: stillPose, now: 0.02)
        _ = staggered.feed(count: 4, geometry: stillPose, now: 0.04)
        _ = staggered.feed(count: 4, geometry: stillPose, now: 0.15)
        suite.expect(staggered.feed(count: 0, geometry: nil, now: 0.2).flatMap(TrackpadGestureSupport.judge)?.key == "tap-4",
                     "a fourth finger landing while the hand is still makes a four-finger tap")
        var joined = TrackpadGestureRecognizer()
        _ = joined.feed(count: 3, geometry: stillPose, now: 0)
        _ = joined.feed(count: 3, geometry: Geometry(x: 0.7, y: 0.5, spread: 0.2), now: 0.1)
        _ = joined.feed(count: 4, geometry: Geometry(x: 0.75, y: 0.5, spread: 0.2), now: 0.15)
        _ = joined.feed(count: 4, geometry: Geometry(x: 0.9, y: 0.5, spread: 0.2), now: 0.25)
        suite.expect(joined.feed(count: 0, geometry: nil, now: 0.3).flatMap(TrackpadGestureSupport.judge) == nil,
                     "a finger joining a swipe in motion makes the touch ambiguous")
        var pointing = TrackpadGestureRecognizer()
        _ = pointing.feed(count: 1, geometry: stillPose, now: 0)
        _ = pointing.feed(count: 1, geometry: Geometry(x: 0.8, y: 0.2, spread: 0), now: 0.1)
        _ = pointing.feed(count: 3, geometry: stillPose, now: 0.2)
        _ = pointing.feed(count: 3, geometry: stillPose, now: 0.3)
        suite.expect(pointing.feed(count: 0, geometry: nil, now: 0.35).flatMap(TrackpadGestureSupport.judge)?.key == "tap-3",
                     "pointing with one finger before the tap does not cancel it, as for the middle-click tap")
        var empty = TrackpadGestureRecognizer()
        suite.expect(empty.feed(count: 0, geometry: nil, now: 1) == nil && !empty.isTracking,
                     "an empty frame with nothing tracked reports nothing")
        var reused = TrackpadGestureRecognizer()
        _ = reused.feed(count: 4, geometry: stillPose, now: 0)
        _ = reused.feed(count: 0, geometry: nil, now: 0.1)
        suite.expect(!reused.isTracking, "each lift starts the next touch from scratch")

        // MARK: Routing
        let gestureTap3 = TrackpadGesture(kind: .tap, fingers: 3)!
        let gestureTap4 = TrackpadGesture(kind: .tap, fingers: 4)!
        let swipe3 = TrackpadGesture(kind: .swipeLeft, fingers: 3)!
        let bothTaps = TrackpadGestureSupport.tapReservations(middleClickTapFingers: 3, radialMenuTapFingers: 4)
        suite.expect(bothTaps == [3: .middleClick, 4: .radialMenu],
                     "the middle-click tap and the radial menu tap keep their finger counts")
        suite.expect(TrackpadGestureSupport.tapReservations(middleClickTapFingers: 4, radialMenuTapFingers: 4) == [4: .middleClick],
                     "the middle click keeps a four-finger tap it already had")
        suite.expect(TrackpadGestureSupport.tapReservations(middleClickTapFingers: 0, radialMenuTapFingers: 0).isEmpty
                        && TrackpadGestureSupport.tapReservations(middleClickTapFingers: 5, radialMenuTapFingers: 3).isEmpty,
                     "with neither tap on, every tap is free for gestures")
        suite.expect(TrackpadGestureSupport.route(gestureTap3, reservations: bothTaps, systemDragGestureEnabled: false) == .middleClick
                        && TrackpadGestureSupport.route(gestureTap4, reservations: bothTaps, systemDragGestureEnabled: false) == .radialMenu,
                     "a reserved tap answers its owner instead of a mapping")
        suite.expect(TrackpadGestureSupport.route(gestureTap3, reservations: bothTaps, systemDragGestureEnabled: true) == .dropped,
                     "three-finger drag still silences the three-finger middle-click tap")
        suite.expect(TrackpadGestureSupport.route(swipe3, reservations: bothTaps, systemDragGestureEnabled: false) == .mapping
                        && TrackpadGestureSupport.route(gestureTap3, reservations: [:], systemDragGestureEnabled: false) == .mapping,
                     "swipes and free taps go to the mappings")
        suite.expect(MiddleClickSupport.radialMenuTapFingers(radialMenuWantsTap: true, middleClickTapFingers: 4) == 0,
                     "the radial menu still yields the four-finger tap to the middle click")

        // MARK: System claims
        func claim(_ key: String, _ settings: TrackpadSystemGestureSettings) -> TrackpadSystemClaim? {
            TrackpadGestureSupport.systemClaims(settings)[TrackpadGesture(key: key)!]
        }
        let unwritten = TrackpadSystemGestureSettings()
        suite.expect(claim("swipe-left-3", unwritten) == .moreGestures && claim("swipe-up-4", unwritten) == .moreGestures
                        && claim("pinch-in-4", unwritten) == .moreGestures,
                     "unwritten preferences are read as macOS defaults, which use swipes and pinches")
        suite.expect(claim("swipe-down-3", unwritten) == nil && claim("tap-3", unwritten) == nil,
                     "App Exposé and Look Up by tap are off by default")
        suite.expect(claim("tap-4", unwritten) == nil && claim("tap-5", unwritten) == nil
                        && claim("swipe-right-5", unwritten) == nil,
                     "four and five finger taps and five-finger swipes are always free")
        let fourFingerSpaces = TrackpadSystemGestureSettings(
            threeFingerHorizontalSwipe: 0, fourFingerHorizontalSwipe: 2,
            threeFingerVerticalSwipe: 0, fourFingerVerticalSwipe: 2,
            fourFingerPinch: 0, fiveFingerPinch: 0, threeFingerTap: 2, threeFingerDrag: false,
            missionControlGesture: true, appExposeGesture: true)
        suite.expect(claim("swipe-left-3", fourFingerSpaces) == nil && claim("swipe-right-4", fourFingerSpaces) == .moreGestures,
                     "moving Spaces to four fingers frees three-finger swipes")
        suite.expect(claim("swipe-down-4", fourFingerSpaces) == .moreGestures,
                     "App Exposé switched on claims the downward swipe")
        suite.expect(claim("pinch-in-4", fourFingerSpaces) == nil && claim("pinch-out-5", fourFingerSpaces) == nil,
                     "pinches switched off are free")
        suite.expect(claim("tap-3", fourFingerSpaces) == .lookUp, "Look Up by three-finger tap claims that tap")
        let noMissionControl = TrackpadSystemGestureSettings(fourFingerVerticalSwipe: 2, missionControlGesture: false)
        suite.expect(claim("swipe-up-4", noMissionControl) == nil,
                     "a vertical swipe whose overview is off is free")
        let drag = TrackpadSystemGestureSettings(threeFingerHorizontalSwipe: 0, threeFingerTap: 0, threeFingerDrag: true)
        suite.expect(TrackpadGesture.all.filter { $0.fingers == 3 }.allSatisfy { claim($0.key, drag) == .threeFingerDrag },
                     "three-finger drag claims every three-finger gesture and says where to change it")
        let read = TrackpadSystemGestureSettings(
            trackpad: ["TrackpadThreeFingerDrag": 1, "TrackpadFourFingerPinchGesture": 0].__lookup,
            dock: ["showAppExposeGestureEnabled": true].__lookup)
        suite.expect(read.threeFingerDrag == true && read.fourFingerPinch == 0 && read.appExposeGesture == true
                        && read.fiveFingerPinch == nil && read.missionControlGesture == nil,
                     "raw preference values map onto the settings, absent ones stay unwritten")
        suite.expect(TrackpadSystemGestureSettings.merged([nil, nil]) == nil
                        && TrackpadSystemGestureSettings.merged([0, nil]) == 0
                        && TrackpadSystemGestureSettings.merged([0, 2]) == 2,
                     "either trackpad domain switching a gesture on means macOS uses it")
    }
}

private extension Dictionary where Key == String {
    var __lookup: (String) -> Value? { { self[$0] } }
}
