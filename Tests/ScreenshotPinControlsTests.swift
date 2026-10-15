// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum ScreenshotPinControlsTests {
    @MainActor static func run(_ suite: TestSuite) {
        let feedback = ScreenshotPinFeedbackView(frame: CGRect(x: 0, y: 0, width: 76, height: 28))
        feedback.show("0.7x")
        suite.expect(feedback.message == "0.7x" && feedback.isPresented,
                     "zoom feedback becomes visible immediately")
        feedback.show("90%")
        suite.expect(feedback.message == "90%" && feedback.isPresented,
                     "opacity replaces zoom in the same feedback pill")
        RunLoop.main.run(until: Date().addingTimeInterval(0.65))
        feedback.show("1.6x")
        RunLoop.main.run(until: Date().addingTimeInterval(0.65))
        suite.expect(feedback.isPresented && feedback.message == "1.6x",
                     "switching back to zoom cancels the old fade deadline")
        RunLoop.main.run(until: Date().addingTimeInterval(0.65))
        suite.expect(!feedback.isPresented, "feedback fades after the value stops changing")
        feedback.show("100%")
        suite.expect(feedback.isPresented, "new feedback becomes opaque after a previous fade")
        feedback.dismiss()
        ScreenshotPinWindowTests.run(suite)
    }
}
