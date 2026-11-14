// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Decodes BetterDisplay OSD broadcasts as documented at
/// https://betterdisplay.pro/guide/integration/third-party-apps/. No
/// notification is posted and no display is touched.
enum BetterDisplayOSDTests {
    static func run(_ suite: TestSuite) {
        suite.expect(BetterDisplayOSD.notificationName.rawValue == "pro.betterdisplay.BetterDisplay.osd",
                     "observes the current prefix only, so a dual-prefix broadcast arrives once")

        for target in ["combinedBrightness", "hardwareBrightness", "softwareBrightness"] {
            let reading = BetterDisplayOSD.brightness(fromJSON:
                #"{"displayID":3,"systemIconID":1,"controlTarget":"\#(target)","value":0.625,"maxValue":1}"#)
            suite.expect(reading == .init(displayID: 3, level: 0.625), "\(target) reads as brightness")
        }

        let percent = BetterDisplayOSD.brightness(fromJSON:
            #"{"controlTarget":"hardwareBrightness","value":42,"maxValue":100}"#)
        suite.expectClose(percent?.level ?? -1, 0.42, "a maximum other than 1 scales the value")
        suite.expect(percent?.displayID == nil, "a missing display stays unknown")

        let iconOnly = BetterDisplayOSD.brightness(fromJSON: #"{"systemIconID":1,"value":8,"maxValue":16}"#)
        suite.expectClose(iconOnly?.level ?? -1, 0.5, "the brightness icon identifies an untargeted broadcast")

        let extra = BetterDisplayOSD.brightness(fromJSON:
            #"{"controlTarget":"combinedBrightness","value":1,"maxValue":1,"text":"100%","lock":false,"symbolFadeAfter":800}"#)
        suite.expect(extra?.level == 1, "unknown and presentation fields are ignored")

        suite.expect(BetterDisplayOSD.brightness(fromJSON:
            #"{"controlTarget":"combinedBrightness","value":1.5,"maxValue":1}"#)?.level == 1, "levels clamp to the top")
        suite.expect(BetterDisplayOSD.brightness(fromJSON:
            #"{"controlTarget":"combinedBrightness","value":-0.2,"maxValue":1}"#)?.level == 0, "levels clamp to the bottom")
        suite.expect(BetterDisplayOSD.brightness(fromJSON:
            #"{"displayID":0,"controlTarget":"combinedBrightness","value":0.5,"maxValue":1}"#)?.displayID == nil,
            "display 0 is not a display")

        let ignored: [(String, String)] = [
            (#"{"systemIconID":3,"controlTarget":"volume","value":0.5,"maxValue":1}"#, "volume"),
            (#"{"systemIconID":1,"controlTarget":"contrast","value":0.5,"maxValue":1}"#, "a non-brightness target wins over the icon"),
            (#"{"systemIconID":3,"value":0.5,"maxValue":1}"#, "an untargeted volume icon"),
            (#"{"controlTarget":"combinedBrightness","maxValue":1}"#, "a missing value"),
            (#"{"controlTarget":"combinedBrightness","value":0.5}"#, "a missing maximum"),
            (#"{"controlTarget":"combinedBrightness","value":0.5,"maxValue":0}"#, "a zero maximum"),
            (#"{"controlTarget":"combinedBrightness","value":0.5,"maxValue":-1}"#, "a negative maximum"),
            ("not json", "malformed text"),
        ]
        for (json, label) in ignored {
            suite.expect(BetterDisplayOSD.brightness(fromJSON: json) == nil, "ignores \(label)")
        }
    }
}
