// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

enum WindowStageManagerTests {
    static func run(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 0, y: 48, width: 1440, height: 827)
        let strip = CGRect(x: 8, y: 200, width: 120, height: 400)
        var reads = 0
        func frames() -> [CGRect] { reads += 1; return [strip] }
        for (enabled, active, hidden): (Bool, Bool, Bool?) in [
            (false, true, false), (true, false, false), (true, true, true), (true, true, nil)
        ] {
            let unchanged = WindowStageManagerSupport.adjustedFrame(
                visibleFrame: visible, screenFrame: screen, enabled: enabled,
                stageManagerEnabled: active, autoHide: hidden, dockPosition: nil,
                stripFrames: frames())
            suite.expect(unchanged == visible && reads == 0,
                         "Stage Manager off, hidden or unknown preserves the frame without reading windows")
        }
        func adjusted(_ rects: [CGRect], dock: String? = nil, rtl: Bool = false,
                      screenFrame: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900),
                      visibleFrame: CGRect = CGRect(x: 0, y: 48, width: 1440, height: 827)) -> CGRect {
            WindowStageManagerSupport.adjustedFrame(
                visibleFrame: visibleFrame, screenFrame: screenFrame, enabled: true,
                stageManagerEnabled: true, autoHide: false, dockPosition: dock,
                rightToLeft: rtl, stripFrames: rects)
        }
        let reserved = adjusted([strip])
        suite.expect(reserved == CGRect(x: 136, y: 48, width: 1304, height: 827),
                     "measured strip bounds reserve one side while retaining the Dock and menu bar exclusions")
        suite.expect(adjusted([CGRect(x: 8, y: 200, width: 172, height: 400)]).minX == 188,
                     "the reserved width follows the strip artwork instead of a fixed margin")
        let rightStrip = CGRect(x: 1312, y: 200, width: 120, height: 400)
        let leftDock = CGRect(x: 60, y: 0, width: 1380, height: 875)
        suite.expect(adjusted([rightStrip], dock: "left", visibleFrame: leftDock)
            == CGRect(x: 60, y: 0, width: 1244, height: 875),
            "a left Dock keeps its exclusion and reserves the strip on the right")
        suite.expect(adjusted([rightStrip], rtl: true).maxX == 1304
                && adjusted([strip], dock: "right", rtl: true).minX == 136,
                     "right-to-left desktops use the right strip unless the Dock occupies that side")
        let fallback = CGRect(x: 75, y: 48, width: 1365, height: 827)
        suite.expect(adjusted([]) == fallback,
                     "a covered or unavailable strip leaves room to reveal recent apps on the first placement")
        suite.expect(adjusted([screen, CGRect(x: 400, y: 200, width: 120, height: 400),
                               CGRect(x: 8, y: 200, width: 12, height: 12)]) == fallback,
                     "desktop overlays, dragged windows away from the edge and tiny icons cannot define a strip")
        let neighbour = screen.offsetBy(dx: -1920, dy: 1080)
        let neighbourVisible = visible.offsetBy(dx: -1920, dy: 1080)
        let neighbourStrip = strip.offsetBy(dx: -1920, dy: 1080)
        suite.expect(adjusted([strip, neighbourStrip], screenFrame: neighbour, visibleFrame: neighbourVisible)
            == reserved.offsetBy(dx: -1920, dy: 1080),
            "each display measures its own strip with negative origins and vertical offsets")
        suite.expect(adjusted([strip.offsetBy(dx: 0, dy: 1080)]) == fallback,
                     "a vertically adjacent display never supplies this display's strip")
        let alreadyInset = CGRect(x: 100, y: 48, width: 1340, height: 827)
        suite.expect(adjusted([], visibleFrame: alreadyInset) == alreadyInset,
                     "an existing system inset is not charged twice")
        let narrow = CGRect(x: 0, y: 0, width: 100, height: 200)
        suite.expect(adjusted([], screenFrame: narrow, visibleFrame: narrow).width == 80,
                     "fallback reservation never leaves less than the minimum layout width")

        func window(owner: String = "WindowManager", alpha: Double = 1) -> [String: Any] {
            [kCGWindowOwnerName as String: owner, kCGWindowAlpha as String: alpha,
             kCGWindowBounds as String: CGRect(x: -1912, y: -780, width: 120, height: 400)
                .dictionaryRepresentation]
        }
        let measured = WindowStageManagerSupport.stripFrames(
            from: [window(), window(owner: "Finder"), window(alpha: 0),
                   [kCGWindowOwnerName as String: "WindowManager"]], screenTop: 900)
        suite.expect(measured == [neighbourStrip],
                     "only visible WindowManager bounds are converted from Quartz into AppKit points")

        suite.expect(WindowLayoutGeometry.rect(for: .maximize, current: screen, visibleFrame: reserved) == reserved,
                     "keyboard maximize fills all remaining space beside Stage Manager")
        let left = WindowLayoutGeometry.rect(for: .leftHalf, current: screen, visibleFrame: reserved)
        let right = WindowLayoutGeometry.rect(for: .rightHalf, current: screen, visibleFrame: reserved)
        suite.expect(left.minX == reserved.minX && left.maxX == right.minX && right.maxX == visible.maxX,
                     "two halves tile the reduced frame without padding the opposite edge")
        let gapped = WindowLayoutGeometry.rect(for: .maximize, current: screen,
                                               visibleFrame: reserved, screenGap: 10)
        suite.expect(gapped == reserved.insetBy(dx: 10, dy: 10),
                     "existing screen gaps are applied after reserving Stage Manager")
        suite.expect(WindowLayoutGeometry.rect(for: .restore, current: screen, visibleFrame: reserved) == screen
                && WindowLayoutGeometry.rect(for: .fullScreen, current: screen, visibleFrame: reserved) == screen,
                     "Restore and native full screen retain their existing pass-through geometry")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.windowReserveStageManagerSpace] as? Bool == false,
                     "Stage Manager reservation is opt-in")
    }
}
