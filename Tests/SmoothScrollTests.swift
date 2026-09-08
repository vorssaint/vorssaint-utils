// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

enum SmoothScrollTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Smooth scrolling

        expect(SmoothScrollSupport.ticks(line: 1, fixedPoint: 1.0) == 1.0,
               "a classic wheel tick reads the same from either delta field")
        expect(SmoothScrollSupport.ticks(line: 0, fixedPoint: 0.25) == 0.25,
               "high-resolution wheels keep their fractional ticks when the integer field truncates to zero")
        expect(SmoothScrollSupport.ticks(line: -2, fixedPoint: 0) == -2,
               "a zero fixed-point field falls back to the integer line delta")
        var smoothEngine = SmoothScrollSupport.Engine()
        smoothEngine.add(vertical: 40, horizontal: 0)
        expect(smoothEngine.remainingVertical == 40,
               "one wheel tick queues one step of glide")
        smoothEngine.add(vertical: 80, horizontal: 20)
        expect(smoothEngine.remainingVertical == 120 && smoothEngine.remainingHorizontal == 20,
               "same-direction input adds to what is left on each axis")
        smoothEngine.add(vertical: -40, horizontal: 0)
        expect(smoothEngine.remainingVertical == -40 && smoothEngine.remainingHorizontal == 20,
               "reversing one axis abandons only that axis's old tail")
        let reversedFrame = smoothEngine.advance(
            elapsed: SmoothScrollSupport.frameInterval,
            response: SmoothScrollSupport.defaultResponse
        )
        expect(reversedFrame.vertical < 0 && reversedFrame.horizontal > 0,
               "the first frame after a reversal moves in the new direction immediately")
        // Measured against a scroll view: a one-line tick with Shift moves the
        // content the same way a horizontal delta of the SAME sign does, so
        // the redirect must not flip the tick.
        expect(SmoothScrollSupport.axes(vertical: 2, horizontal: 0, shiftPressed: true)
               == SmoothScrollSupport.Axes(vertical: 0, horizontal: 2),
               "Shift routes a vertical wheel tick sideways keeping its sign")
        expect(SmoothScrollSupport.axes(vertical: -2, horizontal: 0, shiftPressed: true)
               == SmoothScrollSupport.Axes(vertical: 0, horizontal: -2),
               "the Shift redirect keeps the sign in the other direction too")
        expect(SmoothScrollSupport.axes(vertical: 2, horizontal: 0, shiftPressed: false)
               == SmoothScrollSupport.Axes(vertical: 2, horizontal: 0),
               "a wheel tick without Shift keeps its vertical axis")
        expect(SmoothScrollSupport.axes(vertical: 2, horizontal: -1, shiftPressed: true)
               == SmoothScrollSupport.Axes(vertical: 2, horizontal: -1),
               "Shift preserves a wheel event that already carries horizontal movement")
        let defaultFrameDelta = SmoothScrollSupport.frameDelta(
            remaining: 100,
            elapsed: SmoothScrollSupport.frameInterval,
            response: SmoothScrollSupport.defaultResponse
        )
        expect(abs(defaultFrameDelta - 18) < 0.5,
               "the registered response keeps the former default's initial movement")
        expect(SmoothScrollSupport.frameDelta(
            remaining: -100,
            elapsed: SmoothScrollSupport.frameInterval,
            response: SmoothScrollSupport.defaultResponse
        ) < 0,
               "negative glides emit negative frames")
        expect(SmoothScrollSupport.frameDelta(
            remaining: 0.8,
            elapsed: SmoothScrollSupport.frameInterval,
            response: SmoothScrollSupport.defaultResponse
        ) == 0.8,
               "small leftovers flush in one final frame")
        expect(SmoothScrollSupport.frameDelta(
            remaining: 3,
            elapsed: SmoothScrollSupport.frameInterval,
            response: SmoothScrollSupport.defaultResponse
        ) == 1
                && SmoothScrollSupport.frameDelta(
                    remaining: 3,
                    elapsed: SmoothScrollSupport.frameInterval / 2,
                    response: SmoothScrollSupport.defaultResponse
                ) == 0.5,
               "the time-based tail keeps moving at the former default cadence")
        expect(SmoothScrollSupport.frameDelta(
            remaining: 100,
            elapsed: SmoothScrollSupport.frameInterval,
            response: SmoothScrollSupport.responseRange.upperBound
        ) > defaultFrameDelta
                && SmoothScrollSupport.frameDelta(
                    remaining: 100,
                    elapsed: SmoothScrollSupport.frameInterval,
                    response: SmoothScrollSupport.responseRange.lowerBound
                ) < defaultFrameDelta,
               "response changes how quickly the glide follows the wheel")
        expect(SmoothScrollSupport.frameDelta(
            remaining: 100,
            elapsed: 1,
            response: SmoothScrollSupport.defaultResponse
        ) == SmoothScrollSupport.frameDelta(
            remaining: 100,
            elapsed: SmoothScrollSupport.maximumFrameInterval,
            response: SmoothScrollSupport.defaultResponse
        ),
               "a stalled run loop cannot dump the entire tail in one frame")
        expect(SmoothScrollSupport.frameDelta(
            remaining: 0,
            elapsed: SmoothScrollSupport.frameInterval,
            response: SmoothScrollSupport.defaultResponse
        ) == 0,
               "no remaining distance emits nothing")
        expect(SmoothScrollSupport.frameDelta(
            remaining: 40,
            elapsed: .nan,
            response: SmoothScrollSupport.defaultResponse
        ) == 0,
               "an invalid elapsed time cannot corrupt the glide")
        expect(SmoothScrollSupport.sanitizedStep(0) == 40,
               "an unset step falls back to the default")
        expect(SmoothScrollSupport.sanitizedStep(500) == 100,
               "the step clamps to its range")
        expect(SmoothScrollSupport.sanitizedResponse(-1) == SmoothScrollSupport.responseRange.lowerBound
                && SmoothScrollSupport.sanitizedResponse(500) == SmoothScrollSupport.responseRange.upperBound,
               "response clamps damaged preferences to its range")
        expect(Defaults.registeredDefaults[DefaultsKey.smoothScrollEnabled] as? Bool == false,
               "smooth scrolling ships off by default")
        expect(Defaults.registeredDefaults[DefaultsKey.scrollInverterHorizontalEnabled] as? Bool == false,
               "horizontal scroll inversion ships off by default")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.scrollInverterHorizontalEnabled),
               "horizontal scroll direction follows settings backups")
        expect(Defaults.registeredDefaults[DefaultsKey.smoothScrollStep] as? Int == 40,
               "smooth scrolling step registers its default")
        expect(Defaults.registeredDefaults[DefaultsKey.smoothScrollResponse] as? Int
                == SmoothScrollSupport.defaultResponse
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.smoothScrollResponse),
               "smooth scrolling response registers its default and follows settings backups")

        var sixtyHertzEngine = SmoothScrollSupport.Engine()
        var oneTwentyHertzEngine = SmoothScrollSupport.Engine()
        sixtyHertzEngine.add(vertical: 80, horizontal: -80)
        oneTwentyHertzEngine.add(vertical: 80, horizontal: -80)
        var sixtyHertzDistance = SmoothScrollSupport.Axes(vertical: 0, horizontal: 0)
        var oneTwentyHertzDistance = SmoothScrollSupport.Axes(vertical: 0, horizontal: 0)
        for _ in 0..<12 {
            let frame = sixtyHertzEngine.advance(
                elapsed: 1.0 / 60.0,
                response: SmoothScrollSupport.defaultResponse
            )
            sixtyHertzDistance = SmoothScrollSupport.Axes(
                vertical: sixtyHertzDistance.vertical + frame.vertical,
                horizontal: sixtyHertzDistance.horizontal + frame.horizontal
            )
        }
        for _ in 0..<24 {
            let frame = oneTwentyHertzEngine.advance(
                elapsed: 1.0 / 120.0,
                response: SmoothScrollSupport.defaultResponse
            )
            oneTwentyHertzDistance = SmoothScrollSupport.Axes(
                vertical: oneTwentyHertzDistance.vertical + frame.vertical,
                horizontal: oneTwentyHertzDistance.horizontal + frame.horizontal
            )
        }
        expect(abs(sixtyHertzDistance.vertical - oneTwentyHertzDistance.vertical) < 0.000001
                && abs(sixtyHertzDistance.horizontal - oneTwentyHertzDistance.horizontal) < 0.000001
                && abs(sixtyHertzEngine.remainingVertical - oneTwentyHertzEngine.remainingVertical) < 0.000001
                && abs(sixtyHertzEngine.remainingHorizontal - oneTwentyHertzEngine.remainingHorizontal) < 0.000001,
               "equal elapsed time produces the same glide at 60 and 120 Hz")

        expect(FocusFollowsMouseSupport.sanitizedDelay(0)
                == FocusFollowsMouseSupport.delayRange.lowerBound
                && FocusFollowsMouseSupport.sanitizedDelay(2_000)
                == FocusFollowsMouseSupport.delayRange.upperBound,
               "focus follows mouse clamps a damaged delay preference")
        expect(!FocusFollowsMouseSupport.shouldActivate(
            targetWindowID: 42, focusedWindowID: nil, targetAppIsFrontmost: true),
               "hover leaves the active app alone when its focused window cannot be read")
        expect(!FocusFollowsMouseSupport.shouldActivate(
            targetWindowID: 42, focusedWindowID: 42, targetAppIsFrontmost: true),
               "hover does not reactivate the app's focused window")
        expect(FocusFollowsMouseSupport.shouldActivate(
            targetWindowID: 42, focusedWindowID: 43, targetAppIsFrontmost: true),
               "hover can still switch to another window within the active app")
        for focusedWindowID: CGWindowID? in [nil, 42, 43] {
            expect(FocusFollowsMouseSupport.shouldActivate(
                targetWindowID: 42, focusedWindowID: focusedWindowID, targetAppIsFrontmost: false),
                   "hover can activate a background app regardless of its last focused window")
        }
        var focusFollowsMouseState = FocusFollowsMouseState()
        expect(!focusFollowsMouseState.hasPendingEvaluation,
               "focus follows mouse starts without work to poll")
        focusFollowsMouseState.recordMovement(to: CGPoint(x: 40, y: 70), at: 10)
        expect(focusFollowsMouseState.nextEvaluation(at: 10.20, delayMilliseconds: 250) == nil
                && focusFollowsMouseState.hasPendingEvaluation,
               "focus follows mouse waits for the pointer to settle")
        let settledFocus = focusFollowsMouseState.nextEvaluation(at: 10.25, delayMilliseconds: 250)
        expect(settledFocus?.point == CGPoint(x: 40, y: 70)
                && settledFocus.map(focusFollowsMouseState.isCurrent) == true,
               "focus follows mouse evaluates the settled pointer once")
        expect(focusFollowsMouseState.nextEvaluation(at: 11, delayMilliseconds: 250) == nil,
               "focus follows mouse does not refocus without new movement")
        expect(!focusFollowsMouseState.hasPendingEvaluation,
               "a consumed focus evaluation leaves no work to poll while its lookup finishes")
        focusFollowsMouseState.recordMovement(to: CGPoint(x: 90, y: 20), at: 12)
        expect(settledFocus.map(focusFollowsMouseState.isCurrent) == false
                && focusFollowsMouseState.hasPendingEvaluation,
               "a stale window lookup cannot focus after the pointer moves")
        focusFollowsMouseState.recordMovement(to: CGPoint(x: 100, y: 20), at: 12.2)
        expect(focusFollowsMouseState.nextEvaluation(at: 12.25, delayMilliseconds: 250) == nil
                && focusFollowsMouseState.hasPendingEvaluation,
               "new movement restarts the settling delay without dropping pending work")
        expect(focusFollowsMouseState.nextEvaluation(at: 13, delayMilliseconds: 250)?.point
                == CGPoint(x: 100, y: 20),
               "a deferred focus check can consume the settled target after input protections lift")
        focusFollowsMouseState.recordMovement(to: CGPoint(x: 110, y: 20), at: 14)
        focusFollowsMouseState.reset()
        expect(focusFollowsMouseState.point == nil && !focusFollowsMouseState.hasPendingEvaluation,
               "space and wake resets discard the old pointer target")
        expect(Defaults.registeredDefaults[DefaultsKey.focusFollowsMouseEnabled] as? Bool == false
                && Defaults.registeredDefaults[DefaultsKey.focusFollowsMouseDelay] as? Int
                    == FocusFollowsMouseSupport.defaultDelayMilliseconds,
               "focus follows mouse ships off with a safe delay")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.focusFollowsMouseDelay),
               "focus follows mouse preferences follow settings backups")
        let focusFollowsMouseServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/FocusFollowsMouse/FocusFollowsMouseService.swift",
            encoding: .utf8)) ?? ""
        expect(focusFollowsMouseServiceSource.contains(".leftMouseDragged")
                && focusFollowsMouseServiceSource.contains(".rightMouseDragged")
                && focusFollowsMouseServiceSource.contains(".otherMouseDragged")
                && focusFollowsMouseServiceSource.contains("NSEvent.pressedMouseButtons == 0"),
               "focus follows mouse tracks drags and checks every held mouse button")
        expect(focusFollowsMouseServiceSource.contains("excludesPointerTarget(")
                && focusFollowsMouseServiceSource.contains(
                    ".focusFollowsMouse, at: evaluation.point"),
               "focus follows mouse leaves selected apps alone before querying Accessibility")
        expect(focusFollowsMouseServiceSource.contains("SessionActivity.shared.onChange")
                && focusFollowsMouseServiceSource.contains(
                    "sessionIsActive: SessionActivity.shared.isActive")
                && focusFollowsMouseServiceSource.contains("AXIsProcessTrusted()"),
               "focus follows mouse owns no monitor or timer in a switched-away or untrusted session")
        expect(!focusFollowsMouseServiceSource.isEmpty
                && !focusFollowsMouseServiceSource.contains("AXUIElementCreateSystemWide"),
               "focus follows mouse cannot re-enter its own Accessibility tree through a global hit test")

        // A wheel that reports continuously already measures in points, and
        // that field is the one to trust; the line field only fills in for a
        // movement too small to register as a whole point.
        expect(ScrollWheelSupport.pointsPerLine == 10,
               "one scroll line spans ten points")
        expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 4.0, pointDelta: 40, step: 40) == 40,
               "the default step travels the same distance the event asked for")
        expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 4.0, pointDelta: 12, step: 40) == 12,
               "the point field wins, so no assumption about points per line is made")
        expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 4.0, pointDelta: 40, step: 20) == 20,
               "a shorter step halves the distance of a continuous wheel")
        expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 4.0, pointDelta: 40, step: 100) == 100,
               "a longer step stretches the distance of a continuous wheel")
        expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: -0.5, pointDelta: -5, step: 40) == -5,
               "direction survives the conversion")
        expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 0.35, pointDelta: 0, step: 40) == 3.5,
               "a movement below one whole point still glides")
        expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 0, pointDelta: 12, step: 40) == 12,
               "a driver that fills in only whole points still glides")
        expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 0, pointDelta: 0, step: 40) == 0,
               "an empty event asks for no distance")
        expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: .nan, pointDelta: 0, step: 40) == 0,
               "a nonsense delta asks for no distance")

        // The continuous path scales by the step itself and then hands the
        // budget a step of one. Scaling in both places would square the
        // setting, so pin that the budget equals the distance.
        for continuousStep in [20.0, 40.0, 100.0] {
            let distance = SmoothScrollSupport.continuousDistance(
                fixedPointDelta: 4.0, pointDelta: 40, step: continuousStep)
            var engine = SmoothScrollSupport.Engine()
            engine.add(vertical: distance, horizontal: 0)
            expect(engine.remainingVertical == distance,
                   "the step scales a continuous wheel exactly once")
        }

        var exactDistanceEngine = SmoothScrollSupport.Engine()
        exactDistanceEngine.add(vertical: 40.4, horizontal: -17.3)
        var exactVertical = 0.0
        var exactHorizontal = 0.0
        for _ in 0..<600 {
            if !exactDistanceEngine.isActive { break }
            let frame = exactDistanceEngine.advance(
                elapsed: 1.0 / 120.0,
                response: SmoothScrollSupport.responseRange.lowerBound
            )
            exactVertical += frame.vertical
            exactHorizontal += frame.horizontal
        }
        expect(!exactDistanceEngine.isActive
                && abs(exactVertical - 40.4) < 0.000001
                && abs(exactHorizontal + 17.3) < 0.000001,
               "the engine spends the exact distance on both axes")

        // Fractions are carried instead of rounded away, so the glide
        // delivers the whole distance it was given.
        var carriedTotal: Double = 0
        var carry: Double = 0
        for _ in 0..<10 {
            let frame = SmoothScrollSupport.wholePixels(0.6, carry: carry)
            carriedTotal += frame.pixels
            carry = frame.carry
        }
        expect(abs(carriedTotal + carry - 6) < 0.000001,
               "ten six-tenths of a pixel are all still there, posted or waiting")
        expect(carriedTotal >= 5,
               "never more than one pixel is left waiting")
        expect(SmoothScrollSupport.wholePixels(0.4, carry: 0).pixels == 0,
               "a fraction alone posts nothing yet")
        expect(SmoothScrollSupport.wholePixels(0.4, carry: 0).carry == 0.4,
               "the fraction is kept for the next frame")
        expect(SmoothScrollSupport.wholePixels(-1.5, carry: 0).pixels == -1,
               "negative frames keep their whole pixels")
        expect(SmoothScrollSupport.wholePixels(-1.5, carry: 0).carry == -0.5,
               "negative frames carry their fraction")
        expect(SmoothScrollSupport.wholePixels(.infinity, carry: 0).pixels == 0,
               "an impossible frame posts nothing")
        expect(SmoothScrollSupport.finalPixels(0.4, carry: 0.3) == 1,
               "the landing frame spends the leftover instead of dropping it")
        expect(SmoothScrollSupport.finalPixels(-0.4, carry: -0.3) == -1,
               "the landing frame spends it in either direction")
        expect(SmoothScrollSupport.finalPixels(0.2, carry: 0) == 0,
               "a landing frame with almost nothing left posts nothing")
        expect(SmoothScrollSupport.finalPixels(.infinity, carry: 0) == 0,
               "an impossible landing frame posts nothing")
        expect(SmoothScrollSupport.carry(0.6, continuing: 5) == 0.6,
               "leftovers survive while the direction holds")
        expect(SmoothScrollSupport.carry(0.6, continuing: -5) == 0,
               "reversing direction drops the leftovers")
        expect(SmoothScrollSupport.carry(0.6, continuing: 0) == 0.6,
               "an empty event leaves the leftovers alone")
        var roundedEngine = SmoothScrollSupport.Engine()
        roundedEngine.add(vertical: 40.4, horizontal: 0)
        var roundedCarry = 0.0
        var roundedDistance = 0.0
        for _ in 0..<600 {
            if !roundedEngine.isActive { break }
            let frame = roundedEngine.advance(
                elapsed: 1.0 / 120.0,
                response: SmoothScrollSupport.defaultResponse
            )
            if frame.finished {
                roundedDistance += SmoothScrollSupport.finalPixels(frame.vertical, carry: roundedCarry)
                roundedCarry = 0
            } else {
                let output = SmoothScrollSupport.wholePixels(frame.vertical, carry: roundedCarry)
                roundedDistance += output.pixels
                roundedCarry = output.carry
            }
        }
        expect(abs(roundedDistance - 40.4) <= 0.5,
               "posted whole-point frames land within half a point of the requested distance")
    }
}
