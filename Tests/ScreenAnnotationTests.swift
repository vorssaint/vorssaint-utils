// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ScreenAnnotationTests {
    static func run(_ suite: TestSuite) {
        let rawPoints = (0..<(ScreenAnnotationSupport.maxPointsPerStroke + 20))
            .map { AnnotationPoint(x: Double($0), y: Double($0)) }
        let boundedStroke = AnnotationStroke(tool: .pen, color: .red, width: 100, points: rawPoints)
        suite.expect(boundedStroke.points.count == ScreenAnnotationSupport.maxPointsPerStroke,
               "annotation strokes cap their point count")
        suite.expect(boundedStroke.width == 40 && boundedStroke.color == .red,
               "annotation stroke values are clamped without changing color")
        suite.expect(AnnotationColor.orange != AnnotationColor.yellow,
               "annotation orange and yellow remain distinct colors")
        suite.expect(ScreenAnnotationSupport.append(AnnotationPoint(x: 0.0001, y: 0.0001), to: [AnnotationPoint(x: 0, y: 0)]).count == 1,
               "annotation input ignores subpixel noise")
        suite.expect(ScreenAnnotationSupport.append(AnnotationPoint(x: 0.01, y: 0.01), to: [AnnotationPoint(x: 0, y: 0)]).count == 2,
               "annotation input records ordinary drawing movement")
        suite.expect(ScreenAnnotationSupport.undo([boundedStroke]).isEmpty,
               "annotation undo removes only the last stroke")
        suite.expect(ScreenAnnotationSupport.clear([boundedStroke]).isEmpty,
               "annotation clear is idempotent")
        suite.expect(!ScreenAnnotationSupport.canvasIgnoresMouseEvents(isDrawing: true)
                && ScreenAnnotationSupport.canvasIgnoresMouseEvents(isDrawing: false),
               "annotation canvas captures only while drawing")

        var session = ScreenAnnotationSessionState()
        let pointerDisplay = ScreenAnnotationDisplay(displayID: 2,
                                                      frame: CGRect(x: 1440, y: 0, width: 1440, height: 900))
        let otherDisplay = ScreenAnnotationDisplay(displayID: 1,
                                                   frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let firstPlacement = session.begin(on: pointerDisplay)
        suite.expect(firstPlacement == pointerDisplay,
                     "annotation starts an empty session on the pointer display")
        let preservedPlacement = session.begin(on: otherDisplay)
        suite.expect(preservedPlacement == pointerDisplay,
                     "annotation preserves the canvas display while strokes exist")
        session.resetAfterCanvasBecameEmpty()
        let nextPlacement = session.begin(on: otherDisplay)
        suite.expect(nextPlacement == otherDisplay,
                     "annotation chooses the pointer display after an empty session")

        var eraserSession = ScreenAnnotationSessionState()
        _ = eraserSession.begin(on: pointerDisplay)
        eraserSession.resetAfterMutation(strokes: [])
        suite.expect(eraserSession.begin(on: otherDisplay) == otherDisplay,
                     "annotation erasing the last stroke resets the next canvas display")

        var textSession = ScreenAnnotationSessionState()
        _ = textSession.begin(on: pointerDisplay)
        textSession.resetAfterMutation(strokes: [boundedStroke])
        suite.expect(textSession.begin(on: otherDisplay) == pointerDisplay,
                     "annotation keeps the canvas display while text editing leaves strokes")
        textSession.resetAfterMutation(strokes: [])
        suite.expect(textSession.begin(on: otherDisplay) == otherDisplay,
                     "annotation canceling empty text resets the next canvas display")

        var reconfiguredSession = ScreenAnnotationSessionState()
        _ = reconfiguredSession.begin(on: pointerDisplay)
        let movedPointerDisplay = ScreenAnnotationDisplay(
            displayID: pointerDisplay.displayID,
            frame: CGRect(x: 1680, y: 0, width: 1680, height: 1050))
        suite.expect(reconfiguredSession.refresh(on: [movedPointerDisplay], fallback: otherDisplay) == movedPointerDisplay,
                     "annotation refreshes the saved display frame after reconfiguration")
        suite.expect(reconfiguredSession.refresh(on: [otherDisplay], fallback: otherDisplay) == otherDisplay,
                     "annotation falls back to the pointer display when the saved display is gone")
    }
}
