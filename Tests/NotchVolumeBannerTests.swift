// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

enum NotchVolumeBannerTests {
    static func run(_ suite: TestSuite) {
        typealias Banner = NotchVolumeBannerSupport
        suite.expect(Banner.identifier == "volume-system-banner", "the volume banner is recognized")

        let builtIn = CGRect(x: 0, y: 0, width: 1710, height: 1107)
        let banner = CGRect(x: 1355, y: 34, width: 352, height: 153)
        let arrangements: [[CGRect]] = [
            [builtIn],
            [builtIn, CGRect(x: -2560, y: -1440, width: 2560, height: 1440)],
            [CGRect(x: 1710, y: 0, width: 1920, height: 1080), builtIn],
            [builtIn, CGRect(x: 0, y: -1080, width: 1920, height: 1080)],
            [builtIn, CGRect(x: -1920, y: 0, width: 1920, height: 1080), CGRect(x: 1710, y: -400, width: 1080, height: 1920)],
            [builtIn, CGRect(x: 200, y: 1107, width: 2560, height: 1440)]
        ]
        for screens in arrangements {
            // The banner shows under the menu bar of whichever display is active.
            let shown = screens.map { CGRect(x: $0.maxX - 355, y: $0.minY + 34, width: 352, height: 153) }
            for banner in [banner] + shown {
                guard let origin = Banner.hiddenOrigin(for: banner, screens: screens) else {
                    suite.expect(false, "a banner on a display has somewhere to go: \(screens)")
                    continue
                }
                let moved = CGRect(origin: origin, size: banner.size)
                suite.expect(screens.allSatisfy { !moved.intersects($0) }, "the moved banner is on no display: \(screens)")
                suite.expect(Banner.isOffScreen(moved, screens: screens), "the moved banner reads as hidden: \(screens)")
                suite.expect(Banner.hiddenOrigin(for: moved, screens: screens) == nil,
                             "a hidden banner is not moved again: \(screens)")
            }
        }
        suite.expect(!Banner.isOffScreen(banner, screens: [builtIn]), "a banner in place reads as shown")
        suite.expect(Banner.hiddenOrigin(for: banner, screens: []) == nil && !Banner.isOffScreen(banner, screens: []),
                     "without a readable display the banner is left alone")
    }
}
