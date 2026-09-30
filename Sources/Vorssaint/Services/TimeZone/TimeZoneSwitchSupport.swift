// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure logic behind the time zone switcher: identifier validation, search
/// and the favorites list. No system call and no UserDefaults access, so the
/// harness can pin every rule down without touching the real clock.
enum TimeZoneSwitchSupport {
    /// The full set macOS itself ships, read once: every identifier this
    /// feature will ever offer or accept comes from here, never from what
    /// someone typed.
    static let knownIdentifiers = Set(TimeZone.knownTimeZoneIdentifiers)

    static func isKnownIdentifier(_ identifier: String) -> Bool {
        knownIdentifiers.contains(identifier)
    }

    /// The city (or the last path component) an identifier ends in, the part
    /// worth searching and showing first: "America/Argentina/Buenos_Aires"
    /// reads as "Buenos Aires", not the country that contains it.
    static func displayName(for identifier: String) -> String {
        let city = identifier.split(separator: "/").last ?? Substring(identifier)
        return city.replacingOccurrences(of: "_", with: " ")
    }

    /// Everything before the city, for a secondary line: "America/Argentina"
    /// for Buenos Aires, empty for a bare zone like "UTC".
    static func regionName(for identifier: String) -> String {
        let parts = identifier.split(separator: "/").dropLast()
        guard !parts.isEmpty else { return "" }
        return parts.joined(separator: " / ").replacingOccurrences(of: "_", with: " ")
    }

    /// "UTC+9", "UTC-3:30" — the sign and the half-hour offsets some zones
    /// use, formatted the way a person reads a difference, not a raw second
    /// count.
    static func offsetLabel(for identifier: String, at date: Date = Date()) -> String? {
        guard let zone = TimeZone(identifier: identifier) else { return nil }
        let seconds = zone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let minutes = abs(seconds) / 60
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0
            ? "UTC\(sign)\(hours)"
            : String(format: "UTC%@%d:%02d", sign, hours, remainder)
    }

    /// Whether a query matches an identifier's city, its full path or its
    /// region, ignoring underscores and case: "new york", "america/new_york"
    /// and "argentina" all find their zone.
    static func matches(_ identifier: String, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let needle = query.lowercased()
        let haystacks = [identifier, displayName(for: identifier), regionName(for: identifier)]
        return haystacks.contains { $0.lowercased().replacingOccurrences(of: "_", with: " ").contains(needle) }
    }

    /// Search results ranked city-first: a match at the start of the city
    /// name outranks one found only in the region or the raw identifier, and
    /// ties break alphabetically so the list stays stable as someone types.
    static func search(_ query: String,
                       in identifiers: [String] = TimeZone.knownTimeZoneIdentifiers,
                       limit: Int = 30) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Array(identifiers.sorted { displayName(for: $0) < displayName(for: $1) }.prefix(limit))
        }
        let needle = trimmed.lowercased()
        let matched = identifiers.filter { matches($0, query: trimmed) }
        return Array(matched.sorted { lhs, rhs in
            let lhsCity = displayName(for: lhs).lowercased()
            let rhsCity = displayName(for: rhs).lowercased()
            let lhsStarts = lhsCity.hasPrefix(needle)
            let rhsStarts = rhsCity.hasPrefix(needle)
            if lhsStarts != rhsStarts { return lhsStarts }
            return lhsCity == rhsCity ? lhs < rhs : lhsCity < rhsCity
        }.prefix(limit))
    }

    static func addingFavorite(_ identifier: String, to favorites: [String]) -> [String] {
        guard isKnownIdentifier(identifier), !favorites.contains(identifier) else { return favorites }
        return favorites + [identifier]
    }

    static func removingFavorite(_ identifier: String, from favorites: [String]) -> [String] {
        favorites.filter { $0 != identifier }
    }

    static func movingFavorites(_ favorites: [String], fromOffsets: IndexSet, toOffset: Int) -> [String] {
        var copy = favorites
        copy.move(fromOffsets: fromOffsets, toOffset: toOffset)
        return copy
    }
}
