// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

struct CameraPreviewWindowSizeTests {
    /// A defaults suite of its own, so the machine's real mirror size never
    /// leaks into the checks.
    private static let suiteName = "com.vorssaint.tests.camera-preview-window-size"
    private static var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    static func run(_ suite: TestSuite) {
        suite.expect(CameraPreviewWindowSize.allCases.count == 3, "three mirror sizes are offered")
        suite.expect(CameraPreviewWindowSize.medium.pixelSize == CGSize(width: 320, height: 240),
                     "the medium mirror keeps the original 320 by 240 size")
        for choice in CameraPreviewWindowSize.allCases {
            suite.expect(choice.pixelSize.width * 3 == choice.pixelSize.height * 4,
                         "the \(choice.rawValue) mirror keeps the 4 to 3 shape")
        }

        defaults.removePersistentDomain(forName: suiteName)
        suite.expect(CameraPreviewWindowSize.saved(in: defaults) == .medium,
                     "a fresh install opens the medium mirror")
        CameraPreviewWindowSize.large.save(in: defaults)
        suite.expect(CameraPreviewWindowSize.saved(in: defaults) == .large,
                     "the saved mirror size comes back")
        defaults.set("huge", forKey: DefaultsKey.cameraPreviewWindowSize)
        suite.expect(CameraPreviewWindowSize.saved(in: defaults) == .medium,
                     "an unknown saved value falls back to the medium mirror")
        defaults.removePersistentDomain(forName: suiteName)

        suite.expect(CameraPreviewWindowSize.medium.menuTitle(.enUS) == "Medium"
                     && CameraPreviewWindowSize.large.menuTitle(.enUS) == "Large",
                     "menu titles come from the camera preview strings")

        let screen = CGRect(x: 0, y: 25, width: 1512, height: 920)
        let medium = CGRect(x: 596, y: 655, width: 320, height: 240)
        let grown = CameraPreviewWindowSize.adjustedFrame(from: medium, to: CameraPreviewWindowSize.large.pixelSize,
                                                          in: screen)
        suite.expect(grown.maxY == medium.maxY && grown.midX == medium.midX,
                     "a bigger mirror keeps the top edge and the horizontal center")
        suite.expect(grown == CGRect(x: 516, y: 535, width: 480, height: 360),
                     "a bigger mirror grows downward around the same center")

        let atRightEdge = CameraPreviewWindowSize.adjustedFrame(
            from: CGRect(x: 1300, y: 500, width: 200, height: 200),
            to: CameraPreviewWindowSize.large.pixelSize, in: screen)
        suite.expect(atRightEdge.minX == screen.maxX - 480 - 16,
                     "a mirror near the right screen edge stays inside it")

        let atLeftEdge = CameraPreviewWindowSize.adjustedFrame(
            from: CGRect(x: -50, y: 500, width: 320, height: 240),
            to: CameraPreviewWindowSize.large.pixelSize, in: screen)
        suite.expect(atLeftEdge.minX == screen.minX + 16,
                     "a mirror past the left screen edge is pulled back inside it")

        let lowMirror = CameraPreviewWindowSize.adjustedFrame(
            from: CGRect(x: 596, y: 100, width: 320, height: 240),
            to: CameraPreviewWindowSize.large.pixelSize, in: screen)
        suite.expect(lowMirror.minY == screen.minY + 16,
                     "a bigger mirror that would slide below the screen stays above its bottom edge")

        let shrunk = CameraPreviewWindowSize.adjustedFrame(from: grown, to: CameraPreviewWindowSize.small.pixelSize,
                                                           in: screen)
        suite.expect(shrunk.maxY == grown.maxY && shrunk.midX == grown.midX,
                     "a smaller mirror also keeps the top edge and the horizontal center")
    }
}
