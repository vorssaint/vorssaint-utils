// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

enum NotchVolumeBannerTests {
    static func run(_ suite: TestSuite) {
        typealias Banner = NotchVolumeBannerSupport
        suite.expect(Banner.hides(showsVolume: true, identifier: "volume-system-banner"),
                     "the volume banner leaves while the island shows volume")
        suite.expect(!Banner.hides(showsVolume: false, identifier: "volume-system-banner"),
                     "the volume banner stays while the island cannot show volume")
        for other in ["listening-mode-system-banner", "battery-system-banner", "", nil] as [String?] {
            suite.expect(!Banner.hides(showsVolume: true, identifier: other),
                         "other menu bar windows stay where they are: \(other ?? "nil")")
        }
        var reads = 0
        _ = Banner.hides(showsVolume: false, identifier: { reads += 1; return "volume-system-banner" }())
        suite.expect(reads == 0, "a hidden island reads no window identifier")

        let builtIn = CGRect(x: 0, y: 0, width: 1710, height: 1107)
        let banner = CGRect(x: 1355, y: 34, width: 352, height: 153)
        let arrangements: [[CGRect]] = [
            [builtIn],
            [builtIn, CGRect(x: -2560, y: -1440, width: 2560, height: 1440)],
            [CGRect(x: 1710, y: 0, width: 1920, height: 1080), builtIn],
            [builtIn, CGRect(x: 0, y: -1080, width: 1920, height: 1080)]
        ]
        for screens in arrangements {
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
        suite.expect(!Banner.isOffScreen(banner, screens: [builtIn]), "a banner in place reads as shown")
        suite.expect(Banner.hiddenOrigin(for: banner, screens: []) == nil && !Banner.isOffScreen(banner, screens: []),
                     "without a readable display the banner is left alone")
    }
}
