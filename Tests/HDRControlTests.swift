// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The HDR switches' pure rules: what the one Quick Toggles tile does across
/// several displays, when a switch counts as done, and how rows are ordered.
/// Nothing here calls SkyLight.
enum HDRControlTests {
    static func run(_ suite: TestSuite) {
        typealias Support = HDRControlSupport
        let ultrawide = HDRDisplay(id: 3, name: "AW3423DW", isEnabled: false)
        let second = HDRDisplay(id: 7, name: "LG UltraFine", isEnabled: true)

        suite.expect(Support.quickToggleTarget([ultrawide]) == true
                && Support.quickToggleTarget([HDRDisplay(id: 3, name: "AW3423DW", isEnabled: true)]) == false,
               "the tile turns a single display's HDR the other way")
        suite.expect(Support.quickToggleTarget([ultrawide, second]) == false
                && Support.quickToggleIsOn([ultrawide, second]),
               "with any display in HDR the tile reads on and turns HDR off everywhere")
        suite.expect(!Support.quickToggleIsOn([]) && Support.quickToggleCaption([]).isEmpty,
               "no HDR display means an off tile with nothing to name")
        suite.expect(Support.quickToggleCaption([ultrawide, second]) == "AW3423DW, LG UltraFine",
               "the tile names every display it switches")

        suite.expect(Support.didSettle(requested: true, reported: true)
                && !Support.didSettle(requested: true, reported: false)
                && !Support.didSettle(requested: false, reported: nil),
               "a switch counts only once the display reports the requested state")

        let ordered = Support.ordered([second, ultrawide, HDRDisplay(id: 1, name: "A", isEnabled: false)],
                                      mainID: 7)
        suite.expect(ordered.map(\.id) == [7, 1, 3], "the main display leads, the rest follow by ID")

        suite.expect(Support.displayName("  AW3423DW ", fallback: "Display") == "AW3423DW"
                && Support.displayName("  ", fallback: "Display") == "Display"
                && Support.displayName(nil, fallback: "Display") == "Display",
               "a display without a name gets the fallback")

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.hdrControl(language)
            let values = [strings.pageTitle, strings.hubDescription, strings.enable, strings.enableCaption,
                          strings.noDisplays, strings.unsupported, strings.unnamedDisplay,
                          strings.displayCaption, strings.failedNote, strings.tileTitle]
            suite.expect(values.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                   "every HDR string is filled in for \(language.rawValue)")
        }
    }
}
