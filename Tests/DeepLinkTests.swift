// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The vorssaint:// scheme is how things outside the app ask it to run one of
/// its own tools. The parser is the only gate on that door, so every rule
/// about what gets in and what stays out is pinned here.
enum DeepLinkTests {
    static func run(_ suite: TestSuite) {
        func link(_ string: String) -> DeepLinkSupport.Request? {
            guard let url = URL(string: string) else {
                suite.expect(false, "deep link test URL failed to parse itself: \(string)")
                return nil
            }
            return DeepLinkSupport.parse(url)
        }

        suite.expect(link("vorssaint://run/action.screenshot")?.stableKey == "action.screenshot",
                     "a plain run link carries its action id")
        suite.expect(link("VORSSAINT://Run/action.screenshot")?.stableKey == "action.screenshot",
                     "the scheme and the verb are case insensitive")
        suite.expect(link("vorssaint://run/action.soundOutput.ABC-012")?.stableKey == "action.soundOutput.ABC-012",
                     "an action id keeps its case, so device uid keys survive")
        suite.expect(link("vorssaint://run/action.brightness?v=40")
                         == DeepLinkSupport.Request(stableKey: "action.brightness", argument: 40),
                     "v arrives as the numeric argument")
        suite.expect(link("vorssaint://run/action.brightness?v=-30")?.argument == -30,
                     "a negative v parses")
        suite.expect(link("vorssaint://run/action.volume?other=1")
                         == DeepLinkSupport.Request(stableKey: "action.volume", argument: nil),
                     "a query key other than v is not an argument")
        suite.expect(link("vorssaint://run/action.brightness?v=abc")
                         == DeepLinkSupport.Request(stableKey: "action.brightness", argument: nil),
                     "garbage v counts as absent, so the row can still ask for a number itself")
        for rejected in ["https://run/action.screenshot", "vorssaint://settings/page",
                         "vorssaint://run", "vorssaint://run/action/screenshot"] {
            suite.expect(link(rejected) == nil, "\(rejected) is rejected")
        }
    }
}
