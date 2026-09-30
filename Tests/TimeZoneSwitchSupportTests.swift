// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum TimeZoneSwitchSupportTests {
    static func run(_ suite: TestSuite) {
        suite.expect(TimeZoneSwitchSupport.isKnownIdentifier("America/New_York"),
               "a real IANA identifier is recognized")
        suite.expect(!TimeZoneSwitchSupport.isKnownIdentifier("Not/AZone"),
               "a made-up identifier is never accepted")
        suite.expect(!TimeZoneSwitchSupport.isKnownIdentifier(""),
               "an empty string is never a known zone")

        suite.expect(TimeZoneSwitchSupport.displayName(for: "America/New_York") == "New York",
               "the city is the last path component, underscores turned to spaces")
        suite.expect(TimeZoneSwitchSupport.displayName(for: "UTC") == "UTC",
               "a bare zone shows its own name as the city")
        suite.expect(TimeZoneSwitchSupport.regionName(for: "America/Argentina/Buenos_Aires") == "America / Argentina",
               "the region is every path component before the city")
        suite.expect(TimeZoneSwitchSupport.regionName(for: "UTC").isEmpty,
               "a bare zone has no region line")

        suite.expect(TimeZoneSwitchSupport.offsetLabel(for: "Not/AZone") == nil,
               "an unknown identifier has no offset")
        suite.expect(TimeZoneSwitchSupport.offsetLabel(for: "UTC") == "UTC+0",
               "UTC itself reports a zero offset")
        let kolkataDate = Date(timeIntervalSince1970: 0)
        suite.expect(TimeZoneSwitchSupport.offsetLabel(for: "Asia/Kolkata", at: kolkataDate) == "UTC+5:30",
               "a half-hour offset prints its minutes")

        suite.expect(TimeZoneSwitchSupport.matches("America/New_York", query: "new york"),
               "a query matches the city regardless of underscores or case")
        suite.expect(TimeZoneSwitchSupport.matches("America/Argentina/Buenos_Aires", query: "argentina"),
               "a query also matches the region")
        suite.expect(!TimeZoneSwitchSupport.matches("America/New_York", query: "tokyo"),
               "an unrelated query matches nothing")
        suite.expect(TimeZoneSwitchSupport.matches("America/New_York", query: ""),
               "an empty query matches everything")

        let identifiers = ["Region/Downew", "Region/Newport", "Asia/Tokyo"]
        suite.expect(TimeZoneSwitchSupport.search("new", in: identifiers) == ["Region/Newport", "Region/Downew"],
               "a city that starts with the query outranks one that only contains it")
        suite.expect(TimeZoneSwitchSupport.search("tokyo", in: identifiers) == ["Asia/Tokyo"],
               "search finds a single matching city")
        suite.expect(TimeZoneSwitchSupport.search("nowhere", in: identifiers).isEmpty,
               "search returns nothing for an unmatched query")
        suite.expect(TimeZoneSwitchSupport.search("", in: identifiers, limit: 2).count == 2,
               "an empty query still respects the result limit")

        suite.expect(TimeZoneSwitchSupport.addingFavorite("America/New_York", to: []) == ["America/New_York"],
               "a known identifier is added")
        suite.expect(TimeZoneSwitchSupport.addingFavorite("America/New_York", to: ["America/New_York"])
                == ["America/New_York"],
               "adding an existing favorite does not duplicate it")
        suite.expect(TimeZoneSwitchSupport.addingFavorite("Not/AZone", to: []).isEmpty,
               "an unknown identifier is never added")
        suite.expect(TimeZoneSwitchSupport.removingFavorite("America/New_York",
                                                            from: ["America/New_York", "Asia/Tokyo"])
                == ["Asia/Tokyo"],
               "removing a favorite leaves the rest untouched")

        let reordered = TimeZoneSwitchSupport.movingFavorites(["Asia/Tokyo", "America/New_York", "UTC"],
                                                              fromOffsets: [2], toOffset: 0)
        suite.expect(reordered == ["UTC", "Asia/Tokyo", "America/New_York"],
               "favorites move the same way SwiftUI's onMove expresses it")
    }
}
