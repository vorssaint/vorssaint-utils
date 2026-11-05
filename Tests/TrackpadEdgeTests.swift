// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum TrackpadEdgeTests {
    static func run(_ suite: TestSuite) {
        configurationDefaults(suite)
        zones(suite)
        verticalSlide(suite)
        horizontalTrackSwipe(suite)
        inwardMovementIsPointerUse(suite)
        extraFingers(suite)
        lostTracking(suite)
        doubleTap(suite)
        slowOrMovingTaps(suite)
        tapClickRoles(suite)
        tapToSlide(suite)
        modifierGate(suite)
        preciseSteps(suite)
        levels(suite)
        mediaKeys(suite)
        catalog(suite)
    }

    private static func recognizer(_ adjust: (inout TrackpadEdgeConfiguration) -> Void = { _ in })
        -> TrackpadEdgeRecognizer {
        var configuration = TrackpadEdgeConfiguration.standard
        adjust(&configuration)
        return TrackpadEdgeRecognizer(configuration: configuration)
    }

    private static func contact(_ x: Float, _ y: Float, id: Int32 = 1) -> [TrackpadContact] {
        [TrackpadContact(id: id, x: x, y: y)]
    }

    private static func feed(_ recognizer: inout TrackpadEdgeRecognizer,
                             _ frames: [(contacts: [TrackpadContact], time: TimeInterval)],
                             allowed: Bool = true) -> [TrackpadEdgeEvent] {
        frames.flatMap { recognizer.process($0.contacts, at: $0.time, startAllowed: { allowed }) }
    }

    private static func steps(_ events: [TrackpadEdgeEvent]) -> [Int] {
        events.compactMap {
            if case .step(_, let direction) = $0 { return direction }
            return nil
        }
    }

    private static func configurationDefaults(_ suite: TestSuite) {
        let standard = TrackpadEdgeConfiguration.standard
        suite.expect(standard.slideAction(.left) == .brightness && standard.slideAction(.right) == .volume
                && standard.slideAction(.bottom) == .tracks && standard.slideAction(.top) == .keyboardBrightness,
               "display brightness on the left, volume on the right, keyboard brightness along the top and tracks along the bottom by default")
        suite.expect(standard.cornerAction(.topLeft) == .microphoneMute
                && standard.cornerAction(.topRight) == .outputMute
                && standard.cornerAction(.bottomLeft) == .off && standard.cornerAction(.bottomRight) == .off,
               "the top left corner mutes the microphone, the top right corner mutes the sound, and the bottom corners stay free for clicking")
        suite.expect(!standard.tapToSlide, "edges slide straight away unless a tap first is asked for")
        suite.expect(TrackpadEdgeConfiguration.sanitizedEdgeWidth(.nan) == TrackpadEdgeConfiguration.defaultEdgeWidth
                && TrackpadEdgeConfiguration.sanitizedEdgeWidth(0.5) == TrackpadEdgeConfiguration.edgeWidthRange.upperBound
                && TrackpadEdgeConfiguration.sanitizedEdgeWidth(0.01) == TrackpadEdgeConfiguration.edgeWidthRange.lowerBound,
               "a saved edge width outside the supported range is clamped")

        let suiteName = "vorss.tests.trackpad-edges"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            suite.expect(false, "temporary defaults are available")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("tracks", forKey: DefaultsKey.trackpadEdgeTopAction)
        defaults.set("microphoneVolume", forKey: DefaultsKey.trackpadEdgeLeftAction)
        defaults.set("bogus", forKey: DefaultsKey.trackpadEdgeRightAction)
        defaults.set("nextSoundOutput", forKey: DefaultsKey.trackpadCornerBottomLeftAction)
        defaults.set(0.9, forKey: DefaultsKey.trackpadEdgeWidth)
        let loaded = TrackpadEdgeConfiguration.load(from: defaults, isAvailable: { $0 != .mixer && $0 != .soundOutputSwitcher })
        suite.expect(loaded.slideAction(.top) == .tracks, "a saved edge choice is read back")
        suite.expect(loaded.slideAction(.right) == .volume,
               "an unknown saved edge choice falls back to the edge default")
        suite.expect(loaded.slideAction(.left) == .off,
               "an edge whose feature is uninstalled stays quiet instead of acting without it")
        suite.expect(loaded.cornerAction(.bottomLeft) == .off,
               "a corner whose feature is uninstalled stays quiet")
        suite.expect(loaded.edgeWidth == Float(TrackpadEdgeConfiguration.edgeWidthRange.upperBound),
               "a saved edge width is clamped when loaded")
        suite.expect(loaded.mediaStripTap, "the media strip tap is on unless switched off")
        suite.expect(!loaded.tapToSlide, "tap before sliding is off unless switched on")
        defaults.set(true, forKey: DefaultsKey.trackpadEdgeTapToSlide)
        suite.expect(TrackpadEdgeConfiguration.load(from: defaults).tapToSlide, "tap before sliding is read back")
    }

    private static func zones(_ suite: TestSuite) {
        let pad = recognizer()
        suite.expect(pad.zones(x: 0.98, y: 0.5).vertical == .right
                && pad.zones(x: 0.02, y: 0.5).vertical == .left,
               "the side bands map to the right and left edges")
        suite.expect(pad.zones(x: 0.5, y: 0.5).isEmpty, "the middle of the pad belongs to the pointer")
        suite.expect(pad.zones(x: 0.97, y: 0.97).tap == .corner(.topRight)
                && pad.zones(x: 0.97, y: 0.97).vertical == .right,
               "the top right corner is both a tap target and the top of the right edge")
        suite.expect(pad.zones(x: 0.97, y: 0.03).tap == .mediaStrip,
               "a corner without an action falls back to the media strip along the bottom")
        suite.expect(pad.zones(x: 0.5, y: 0.97).horizontal == .top,
               "the band along the top maps to the top edge")
        let quietTop = recognizer { $0.slideActions[.top] = .off }
        suite.expect(quietTop.zones(x: 0.5, y: 0.97).horizontal == nil,
               "the top edge does nothing while it has no action")
        var quarter = recognizer { $0.activeArea = .quarter }
        suite.expect(quarter.zones(x: 0.98, y: 0.6).vertical == nil
                && quarter.zones(x: 0.98, y: 0.2).vertical == .right,
               "a limited active area keeps the upper part of the side edges free")
        quarter.configuration.mediaStripTap = false
        suite.expect(quarter.zones(x: 0.5, y: 0.03).tap == nil,
               "switching the media strip tap off leaves the bottom edge to its slide only")
    }

    private static func verticalSlide(_ suite: TestSuite) {
        var pad = recognizer()
        let distance = pad.configuration.stepDistance
        var frames: [(contacts: [TrackpadContact], time: TimeInterval)] = [(contact(0.98, 0.3), 0)]
        var y: Float = 0.3
        for index in 1...8 {
            y += distance * 0.8
            frames.append((contact(0.98, y), Double(index) * 0.01))
        }
        let events = feed(&pad, frames)
        suite.expect(events.first == .slideBegan(.right, .volume),
               "sliding up the right edge starts its slide")
        let up = steps(events)
        suite.expect(!up.isEmpty && up.allSatisfy { $0 == 1 }, "moving up raises the level")
        suite.expect(up.count == 6, "one step for every step distance travelled")
        suite.expect(pad.isSliding, "the slide stays active while the finger is down")
        let down = feed(&pad, [(contact(0.98, y - distance * 2.5), 0.2)])
        suite.expect(steps(down) == [-1, -1], "moving back down lowers the level step by step")
        let end = feed(&pad, [([], 0.3)])
        suite.expect(end == [.slideEnded(.right)] && !pad.isSliding, "lifting the finger ends the slide")
    }

    private static func horizontalTrackSwipe(_ suite: TestSuite) {
        var pad = recognizer()
        let events = feed(&pad, [
            (contact(0.4, 0.03), 0),
            (contact(0.45, 0.035), 0.02),
            (contact(0.6, 0.04), 0.05),
            (contact(0.8, 0.04), 0.08),
        ])
        suite.expect(events == [.slideBegan(.bottom, .tracks), .trackSkip(direction: 1)],
               "one swipe right along the bottom skips forward exactly once")
        suite.expect(feed(&pad, [(contact(0.95, 0.04), 0.1)]).isEmpty,
               "the rest of the same swipe does not skip again")
        _ = feed(&pad, [([], 0.15)])
        let back = feed(&pad, [
            (contact(0.6, 0.03), 1),
            (contact(0.55, 0.03), 1.02),
            (contact(0.4, 0.03), 1.05),
        ])
        suite.expect(back.last == .trackSkip(direction: -1), "a swipe left goes to the previous track")
    }

    private static func inwardMovementIsPointerUse(_ suite: TestSuite) {
        var pad = recognizer()
        let events = feed(&pad, [
            (contact(0.98, 0.5), 0),
            (contact(0.95, 0.5), 0.02),
            (contact(0.9, 0.51), 0.04),
            (contact(0.8, 0.6), 0.08),
            (contact(0.7, 0.8), 0.12),
        ])
        suite.expect(events.isEmpty && pad.phase == .ignored,
               "a finger that leaves the edge toward the middle moves the pointer as usual")
        var middle = recognizer()
        _ = feed(&middle, [(contact(0.5, 0.5), 0), (contact(0.97, 0.5), 0.05), (contact(0.97, 0.9), 0.1)])
        suite.expect(middle.phase == .ignored,
               "a touch that started in the middle never turns into a slide when it reaches an edge")
    }

    private static func extraFingers(_ suite: TestSuite) {
        var pad = recognizer()
        let events = feed(&pad, [
            (contact(0.98, 0.3), 0),
            ([TrackpadContact(id: 1, x: 0.98, y: 0.3), TrackpadContact(id: 2, x: 0.7, y: 0.3)], 0.01),
            ([TrackpadContact(id: 1, x: 0.98, y: 0.6), TrackpadContact(id: 2, x: 0.7, y: 0.6)], 0.05),
        ])
        suite.expect(events.isEmpty && pad.phase == .ignored,
               "a second finger before the slide starts leaves two-finger scrolling alone")
        var sliding = recognizer()
        _ = feed(&sliding, [(contact(0.98, 0.3), 0), (contact(0.98, 0.4), 0.02)])
        let palm = feed(&sliding, [
            ([TrackpadContact(id: 1, x: 0.98, y: 0.5), TrackpadContact(id: 9, x: 0.2, y: 0.1)], 0.04),
        ])
        suite.expect(sliding.isSliding && !steps(palm).isEmpty,
               "a palm landing during a slide does not interrupt it")
    }

    private static func lostTracking(_ suite: TestSuite) {
        var pad = recognizer()
        _ = feed(&pad, [(contact(0.02, 0.3), 0), (contact(0.02, 0.4), 0.02)])
        let rebased = feed(&pad, [(contact(0.02, 0.45, id: 7), 0.04)])
        suite.expect(rebased.isEmpty && pad.isSliding,
               "a finger the pad renumbers mid-slide keeps the slide going without a jump")
        let next = feed(&pad, [(contact(0.02, 0.45 + pad.configuration.stepDistance * 1.2, id: 7), 0.06)])
        suite.expect(steps(next) == [1], "the renumbered finger keeps stepping from where it was picked up")
    }

    private static func doubleTap(_ suite: TestSuite) {
        var pad = recognizer()
        let first = feed(&pad, [(contact(0.96, 0.96), 0), ([], 0.08)])
        guard case .firstTap(.corner(.topRight), let generation)? = first.last else {
            suite.expect(false, "a quick tap in an armed corner is remembered as a first tap")
            return
        }
        let second = feed(&pad, [(contact(0.955, 0.965, id: 2), 0.2), ([], 0.27)])
        suite.expect(second == [.doubleTap(.corner(.topRight), generation: generation)],
               "a second quick tap in the same corner fires its action")
        let third = feed(&pad, [(contact(0.96, 0.96, id: 3), 0.4), ([], 0.45)])
        if case .firstTap? = third.last {
            suite.expect(true, "a third tap starts over instead of firing twice")
        } else {
            suite.expect(false, "a third tap starts over instead of firing twice")
        }

        var late = recognizer()
        _ = feed(&late, [(contact(0.96, 0.96), 0), ([], 0.08)])
        let tooLate = feed(&late, [(contact(0.96, 0.96, id: 2), 0.08 + TrackpadEdgeRecognizer.doubleTapGap + 0.05),
                                   ([], 0.6)])
        if case .firstTap? = tooLate.last {
            suite.expect(true, "taps further apart than the double-tap gap never fire")
        } else {
            suite.expect(false, "taps further apart than the double-tap gap never fire")
        }

        var elsewhere = recognizer()
        _ = feed(&elsewhere, [(contact(0.96, 0.96), 0), ([], 0.08)])
        let otherCorner = feed(&elsewhere, [(contact(0.04, 0.96, id: 2), 0.2), ([], 0.26)])
        suite.expect(!otherCorner.contains { if case .doubleTap = $0 { return true }; return false },
               "one tap in each of two corners is not a double tap")

        var strip = recognizer()
        let media = feed(&strip, [(contact(0.5, 0.03), 0), ([], 0.07),
                                  (contact(0.5, 0.03, id: 2), 0.18), ([], 0.24)])
        suite.expect(media.last.map { if case .doubleTap(.mediaStrip, _) = $0 { return true }; return false } == true,
               "a double tap on the bottom edge plays or pauses")
    }

    private static func slowOrMovingTaps(_ suite: TestSuite) {
        var slow = recognizer()
        let held = feed(&slow, [(contact(0.96, 0.96), 0), (contact(0.96, 0.96), 0.4), ([], 0.45)])
        suite.expect(held.isEmpty, "a finger resting in a corner is not a tap")
        var moving = recognizer { $0.slideActions[.right] = .off }
        let moved = feed(&moving, [(contact(0.96, 0.96), 0), (contact(0.92, 0.9), 0.05), ([], 0.08)])
        suite.expect(moved.isEmpty, "a finger that moves through a corner is not a tap")
    }

    private static func tapClickRoles(_ suite: TestSuite) {
        var pad = recognizer()
        suite.expect(pad.tapClickRole(at: 0) == .none, "nothing is held before any tap")
        let first = feed(&pad, [(contact(0.96, 0.96), 0), ([], 0.08)])
        guard case .firstTap(_, let generation)? = first.last else {
            suite.expect(false, "the first tap is reported")
            return
        }
        suite.expect(pad.tapClickRole(at: 0.1) == .firstTap(generation: generation),
               "the click a first tap produces is held back while a second tap may follow")
        suite.expect(pad.tapClickRole(at: 0.08 + TrackpadEdgeRecognizer.tapClickWindow + 0.01) == .none,
               "a click long after the tap passes untouched")
        _ = feed(&pad, [(contact(0.96, 0.96, id: 2), 0.2)])
        suite.expect(pad.isAwaitingSecondTap(generation: generation) && pad.tapClickRole(at: 0.21) == .secondTap,
               "while the second tap is down its click is dropped")
        _ = feed(&pad, [([], 0.26)])
        suite.expect(pad.tapClickRole(at: 0.3) == .secondTap && !pad.isAwaitingSecondTap(generation: generation),
               "the click right after a double tap is dropped, not replayed")
        var away = recognizer()
        _ = feed(&away, [(contact(0.5, 0.5), 0), ([], 0.05)])
        suite.expect(away.tapClickRole(at: 0.06) == .none, "a tap in the middle of the pad always clicks")
    }

    private static func tapToSlide(_ suite: TestSuite) {
        let guarded: (inout TrackpadEdgeConfiguration) -> Void = { $0.tapToSlide = true }
        var direct = recognizer(guarded)
        let untouched = feed(&direct, [(contact(0.98, 0.3), 0), (contact(0.98, 0.4), 0.03), (contact(0.98, 0.6), 0.08)])
        suite.expect(untouched.isEmpty && direct.phase == .ignored,
               "with tap before sliding, a finger moving along an edge leaves the level alone")

        var armed = recognizer(guarded)
        let tap = feed(&armed, [(contact(0.98, 0.3), 0), ([], 0.08)])
        guard case .firstTap(nil, let generation)? = tap.last else {
            suite.expect(false, "a quick tap on an edge arms it")
            return
        }
        suite.expect(armed.tapClickRole(at: 0.1) == .firstTap(generation: generation),
               "the click an arming tap produces is held back")
        _ = feed(&armed, [(contact(0.98, 0.31, id: 2), 0.2)])
        suite.expect(armed.isAwaitingSecondTap(generation: generation),
               "the held click waits while the finger is back on the armed edge")
        let slide = feed(&armed, [(contact(0.98, 0.4, id: 2), 0.23), (contact(0.98, 0.5, id: 2), 0.26)])
        suite.expect(slide.first == .slideBegan(.right, .volume) && !steps(slide).isEmpty,
               "touching the armed edge again and sliding changes the level")
        suite.expect(!armed.isAwaitingSecondTap(generation: generation),
               "once the slide starts the arming tap is used up")

        var late = recognizer(guarded)
        _ = feed(&late, [(contact(0.98, 0.3), 0), ([], 0.08)])
        let tooLate = feed(&late, [(contact(0.98, 0.3, id: 2), 0.08 + TrackpadEdgeRecognizer.doubleTapGap + 0.05),
                                   (contact(0.98, 0.45, id: 2), 0.6)])
        suite.expect(tooLate.isEmpty, "an arming tap expires after the double-tap gap")

        var otherEdge = recognizer(guarded)
        _ = feed(&otherEdge, [(contact(0.02, 0.3), 0), ([], 0.08)])
        let wrong = feed(&otherEdge, [(contact(0.98, 0.3, id: 2), 0.2), (contact(0.98, 0.45, id: 2), 0.25)])
        suite.expect(wrong.isEmpty, "a tap on one edge does not arm another")

        var corner = recognizer(guarded)
        let corners = feed(&corner, [(contact(0.96, 0.96), 0), ([], 0.08),
                                     (contact(0.96, 0.96, id: 2), 0.2), ([], 0.26)])
        suite.expect(corners.last.map { if case .doubleTap(.corner(.topRight), _) = $0 { return true }; return false } == true,
               "corner double taps work the same with tap before sliding")
    }

    private static func modifierGate(_ suite: TestSuite) {
        var pad = recognizer()
        let events = feed(&pad, [(contact(0.98, 0.3), 0), (contact(0.98, 0.6), 0.05)], allowed: false)
        suite.expect(events.isEmpty && pad.phase == .ignored,
               "without the required key held, edges leave the touch to the pointer")
        suite.expect(TrackpadEdgeModifier.none.isSatisfied(by: [])
                && TrackpadEdgeModifier.fn.isSatisfied(by: .maskSecondaryFn)
                && !TrackpadEdgeModifier.fn.isSatisfied(by: .maskAlternate)
                && TrackpadEdgeModifier.option.isSatisfied(by: [.maskAlternate, .maskShift]),
               "the required key is read from the current modifier flags")
    }

    private static func preciseSteps(_ suite: TestSuite) {
        let normal = TrackpadEdgeConfiguration.standard
        var precise = normal
        precise.precise = true
        suite.expect(normal.stepSize == 1.0 / 16 && precise.stepSize == 1.0 / 64,
               "fine steps move a quarter of a normal step, like the keyboard's Option-Shift steps")
        suite.expect(precise.stepDistance == normal.stepDistance / 2,
               "fine steps need less travel each, so the full range takes twice the slide")
        var fast = normal
        fast.sensitivity = .fast
        suite.expect(fast.stepDistance < normal.stepDistance, "a faster slide needs less travel per step")
    }

    private static func levels(_ suite: TestSuite) {
        suite.expectClose(TrackpadEdgeLevel.stepped(0.5, direction: 1, stepSize: 1.0 / 16), 0.5625, "one step up")
        suite.expect(TrackpadEdgeLevel.stepped(1, direction: 1, stepSize: 1.0 / 16) == 1
                && TrackpadEdgeLevel.stepped(0.02, direction: -1, stepSize: 1.0 / 16) == 0,
               "levels stop at the ends of the range")
    }

    private static func mediaKeys(_ suite: TestSuite) {
        let halves = TrackpadMediaKey.volumeUp.halves(fine: false)
        suite.expect(halves.map(\.data1) == [0x0A00, 0x0B00] && halves.map(\.flags) == [0x0A00, 0x0B00],
               "a volume key is a press and a release in the layout the keyboard sends")
        let fine = TrackpadMediaKey.brightnessDown.halves(fine: true)
        suite.expect(fine.map(\.data1) == [(3 << 16) | 0x0A00, (3 << 16) | 0x0B00]
                && fine.allSatisfy { $0.flags & TrackpadMediaKey.fineFlags == TrackpadMediaKey.fineFlags },
               "a fine step carries Option and Shift, the system's own quarter step")
        suite.expect(TrackpadMediaKey.nextTrack.rawValue == RadialMenuMediaKey.nextTrack.auxKeyType
                && TrackpadMediaKey.previousTrack.rawValue == RadialMenuMediaKey.previousTrack.auxKeyType
                && TrackpadMediaKey.playPause.rawValue == RadialMenuMediaKey.playPause.auxKeyType,
               "track keys match the ones the radial menu already sends")
        suite.expect(TrackpadMediaKey.volumeUp.rawValue == PreciseVolumeMediaKey.volumeUp.rawValue
                && TrackpadMediaKey.mute.rawValue == PreciseVolumeMediaKey.mute.rawValue,
               "volume keys match the ones the volume roller recognizes")
    }

    private static func catalog(_ suite: TestSuite) {
        let feature = AppFeature.trackpadEdges
        suite.expect(feature.group == .mouseKeyboard && feature.permissions == [.accessibility]
                && feature.enabledKeys == [DefaultsKey.trackpadEdgesEnabled],
               "trackpad edges sit with the input features and need only Accessibility")
        suite.expect(!feature.installedByDefault
                && (AppFeature.availabilityDefaults[feature.availabilityKey] as? Bool) == false,
               "trackpad edges are opt-in and never appear on their own after an update")
        suite.expect(feature.energyProfile == .mouse, "the hub labels trackpad edges as a pointer tap")
        let registered = Defaults.registeredDefaults
        suite.expect(registered[DefaultsKey.trackpadEdgesEnabled] as? Bool == false
                && registered[DefaultsKey.panelControlTrackpadEdges] as? Bool == true
                && registered[DefaultsKey.trackpadEdgeHaptics] as? Bool == true
                && registered[DefaultsKey.trackpadEdgeFreezeCursor] as? Bool == true,
               "trackpad edges start off, with haptics and a still pointer once switched on")
        let backup = SettingsBackupSupport.exportKeys()
        let keys = TrackpadEdge.allCases.map(\.defaultsKey) + TrackpadCorner.allCases.map(\.defaultsKey) + [
            DefaultsKey.trackpadEdgesEnabled, DefaultsKey.trackpadEdgeMediaStripTap, DefaultsKey.trackpadEdgeWidth,
            DefaultsKey.trackpadEdgeActiveArea, DefaultsKey.trackpadEdgeSensitivity, DefaultsKey.trackpadEdgePrecise,
            DefaultsKey.trackpadEdgeHaptics, DefaultsKey.trackpadEdgeFreezeCursor, DefaultsKey.trackpadEdgeModifier,
            DefaultsKey.panelControlTrackpadEdges,
        ]
        suite.expect(keys.allSatisfy(backup.contains), "every trackpad edge preference travels with the settings backup")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.trackpadEdges(language)
            let names = TrackpadSlideAction.allCases.map { strings.name($0) }
                + TrackpadCornerAction.allCases.map { strings.name($0) }
                + TrackpadEdge.allCases.map { strings.name($0) }
                + TrackpadCorner.allCases.map { strings.name($0) }
            suite.expect(!strings.pageTitle.isEmpty && names.allSatisfy { !$0.isEmpty }
                    && strings.microphoneLevel(0.42).contains("42"),
                   "trackpad edge strings are complete in \(language.rawValue)")
        }
    }
}
