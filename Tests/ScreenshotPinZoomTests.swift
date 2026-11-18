// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

/// Scrolling over a pinned capture resizes it around the pointer.
enum ScreenshotPinZoomTests {
    static func run(_ suite: TestSuite) {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 100)
        let anchor = CGPoint(x: 150, y: 150)
        let roomy = CGSize(width: 2000, height: 2000)
        let grown = ScreenshotPinSupport.zoomedFrame(frame, scrollDelta: 4, anchor: anchor,
                                                     minimumSize: CGSize(width: 90, height: 60),
                                                     maximumSize: roomy)
        suite.expect(grown.width > frame.width && abs(grown.width / grown.height - 2) < 0.03,
                     "scrolling up grows a pin in proportion")
        suite.expect(abs((anchor.x - grown.minX) / grown.width - 0.25) < 0.02
                     && abs((anchor.y - grown.minY) / grown.height - 0.5) < 0.02,
                     "the point under the pointer stays under it")
        let shrunk = ScreenshotPinSupport.zoomedFrame(frame, scrollDelta: -4, anchor: anchor,
                                                      minimumSize: CGSize(width: 90, height: 60),
                                                      maximumSize: roomy)
        suite.expect(shrunk.width < frame.width, "scrolling down shrinks a pin")
        let floor = ScreenshotPinSupport.zoomedFrame(frame, scrollDelta: -12, anchor: anchor,
                                                     minimumSize: CGSize(width: 190, height: 95),
                                                     maximumSize: roomy)
        suite.expect(floor.width >= 190 && floor.height >= 95, "a pin never shrinks below its smallest size")
        let capped = ScreenshotPinSupport.zoomedFrame(frame, scrollDelta: 12, anchor: anchor,
                                                      minimumSize: CGSize(width: 90, height: 60),
                                                      maximumSize: CGSize(width: 210, height: 2000))
        suite.expect(capped.width <= 211, "a pin never grows past its screen")
        suite.expect(ScreenshotPinSupport.zoomedFrame(frame, scrollDelta: 0, anchor: anchor,
                                                      minimumSize: .zero, maximumSize: roomy) == frame
                     && ScreenshotPinSupport.zoomedFrame(frame, scrollDelta: .nan, anchor: anchor,
                                                         minimumSize: .zero, maximumSize: roomy) == frame,
                     "no scroll, or an unreadable one, leaves a pin alone")
        let wild = ScreenshotPinSupport.zoomedFrame(frame, scrollDelta: 500, anchor: anchor,
                                                    minimumSize: .zero, maximumSize: roomy)
        suite.expect(wild.width <= frame.width * 1.31, "one huge scroll step is limited")
        suite.expect(ScreenshotPinSupport.wheelLines(40, precise: true) == 10
                     && ScreenshotPinSupport.wheelLines(3, precise: false) == 3,
                     "trackpad pixels zoom at the pace of wheel lines")
    }
}
