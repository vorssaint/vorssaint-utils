// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MiddleClickTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Middle click tap (issue #161)

        expect(Defaults.sanitizedMiddleClickTapFingers(3) == 3
                   && Defaults.sanitizedMiddleClickTapFingers(4) == 4,
               "tap to middle click accepts three or four fingers")
        expect(Defaults.sanitizedMiddleClickTapFingers(0) == 0
                   && Defaults.sanitizedMiddleClickTapFingers(2) == 0
                   && Defaults.sanitizedMiddleClickTapFingers(-1) == 0,
               "any other tap finger count means off")
        expect(MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                exceededFingerCount: false, buttonPressedDuring: false,
                                                positionUnavailable: false, systemDragGestureEnabled: false,
                                                tapFingers: 3),
               "a quick still three-finger tap fires")
        expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                 exceededFingerCount: false, buttonPressedDuring: false,
                                                 positionUnavailable: false, systemDragGestureEnabled: false,
                                                 tapFingers: 3, secondsSinceLastKeyDown: 0.1),
               "stray trackpad contact while typing never fires a middle click")
        expect(MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                exceededFingerCount: false, buttonPressedDuring: false,
                                                positionUnavailable: false, systemDragGestureEnabled: false,
                                                tapFingers: 3, secondsSinceLastKeyDown: 1.0),
               "tap to middle click resumes after keyboard activity settles")
        expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.2, maxSpreadChange: 0.01,
                                                 exceededFingerCount: false, buttonPressedDuring: false,
                                                 positionUnavailable: false, systemDragGestureEnabled: false,
                                                 tapFingers: 3),
               "a swipe never fires the tap")
        expect(!MiddleClickSupport.tapShouldFire(duration: 0.8, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                 exceededFingerCount: false, buttonPressedDuring: false,
                                                 positionUnavailable: false, systemDragGestureEnabled: false,
                                                 tapFingers: 3),
               "resting fingers never fire the tap")
        expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                 exceededFingerCount: false, buttonPressedDuring: true,
                                                 positionUnavailable: false, systemDragGestureEnabled: false,
                                                 tapFingers: 3),
               "a physical click during the touch belongs to the press path")
        expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                 exceededFingerCount: true, buttonPressedDuring: false,
                                                 positionUnavailable: false, systemDragGestureEnabled: false,
                                                 tapFingers: 3),
               "extra fingers cancel the tap")
        expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                 exceededFingerCount: false, buttonPressedDuring: false,
                                                 positionUnavailable: true, systemDragGestureEnabled: false,
                                                 tapFingers: 3),
               "unreadable touch positions stand the tap down")
        expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                 exceededFingerCount: false, buttonPressedDuring: false,
                                                 positionUnavailable: false, systemDragGestureEnabled: true,
                                                 tapFingers: 3),
               "three-finger tap stands down while the system drag gesture owns it")
        expect(MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                exceededFingerCount: false, buttonPressedDuring: false,
                                                positionUnavailable: false, systemDragGestureEnabled: true,
                                                tapFingers: 4),
               "four-finger tap stays available alongside the system drag gesture")
        expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.2,
                                                 exceededFingerCount: false, buttonPressedDuring: false,
                                                 positionUnavailable: false, systemDragGestureEnabled: false,
                                                 tapFingers: 4),
               "a pinch or spread never fires the tap even with a still centroid")
    }

    static func runTransforms(expect: (Bool, String) -> Void) {
        expect(MiddleClickSupport.actionForClick(fingerCount: 3, frameAge: 0.05, settledFor: 0.2,
                                                 sinceLastTransformEnd: nil,
                                                 systemDragGestureEnabled: false) == .transform,
               "middle click transforms a settled three-finger press")
        expect(MiddleClickSupport.actionForClick(fingerCount: 2, frameAge: 0.05, settledFor: 0.2,
                                                 sinceLastTransformEnd: nil,
                                                 systemDragGestureEnabled: false) == .passThrough,
               "middle click leaves two-finger clicks alone")
        expect(MiddleClickSupport.actionForClick(fingerCount: 4, frameAge: 0.05, settledFor: 0.2,
                                                 sinceLastTransformEnd: nil,
                                                 systemDragGestureEnabled: false) == .passThrough,
               "middle click leaves four-finger clicks alone")
        expect(MiddleClickSupport.actionForClick(fingerCount: 3, frameAge: 1.0, settledFor: 0.2,
                                                 sinceLastTransformEnd: nil,
                                                 systemDragGestureEnabled: false) == .passThrough,
               "middle click ignores stale contact frames (fingers already lifted)")
        expect(MiddleClickSupport.actionForClick(fingerCount: 3, frameAge: 0.05, settledFor: 0.01,
                                                 sinceLastTransformEnd: nil,
                                                 systemDragGestureEnabled: false) == .passThrough,
               "middle click rejects a click arriving with the third finger's touchdown")
        expect(MiddleClickSupport.actionForClick(fingerCount: 3, frameAge: 0.05, settledFor: 0.2,
                                                 sinceLastTransformEnd: 0.1,
                                                 systemDragGestureEnabled: false) == .swallow,
               "middle click drops the tap-to-click bounce right after a transform")
        expect(MiddleClickSupport.actionForClick(fingerCount: 3, frameAge: 0.05, settledFor: 0.2,
                                                 sinceLastTransformEnd: 0.5,
                                                 systemDragGestureEnabled: false) == .transform,
               "middle click accepts a deliberate second press after the guard window")
        expect(MiddleClickSupport.actionForClick(fingerCount: 1, frameAge: 0.05, settledFor: 0,
                                                 sinceLastTransformEnd: 0.1,
                                                 systemDragGestureEnabled: false) == .passThrough,
               "middle click never swallows ordinary one-finger clicks")
        expect(MiddleClickSupport.actionForClick(fingerCount: 3, frameAge: 0.05, settledFor: 0.2,
                                                 sinceLastTransformEnd: nil,
                                                 systemDragGestureEnabled: true) == .passThrough,
               "middle click stands down while the system three-finger drag owns the gesture")
    }
}
