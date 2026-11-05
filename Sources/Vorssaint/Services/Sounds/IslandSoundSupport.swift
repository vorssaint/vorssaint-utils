// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// When the island's own moments sound: a download landing, an event about
/// to start.
enum IslandSoundSupport {
    /// How long before a timed event starts its sound plays. The island's
    /// countdown opens an hour ahead, too early for a call to get up.
    static let calendarLeadTime: TimeInterval = 5 * 60

    /// The island's Downloads page is watching its folder.
    static func downloadsOn(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults)
            && AppFeature.notchDownloads.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchDownloadsEnabled)
            && NotchSupport.modules(in: defaults).contains(.downloads)
    }

    /// An installed moment of the group waits on its island page.
    static func waitsOnIsland(in defaults: UserDefaults = .standard,
                              isAvailable: (AppFeature) -> Bool = { $0.isAvailable }) -> Bool {
        (isAvailable(.notchDownloads) && !downloadsOn(in: defaults))
            || (isAvailable(.notchCalendar) && !NotchCalendarSupport.isEnabled(in: defaults))
    }

    /// The events to sound for now: timed, not yet begun, inside the lead
    /// time and not heard before. An event under way when first read, as at
    /// launch or after sleep, has passed its moment.
    static func dueEvents(_ events: [NotchCalendarEvent], now: Date,
                          heard: [String: Date]) -> [NotchCalendarEvent] {
        events.filter {
            !$0.allDay && $0.start > now && $0.start.timeIntervalSince(now) <= calendarLeadTime
                && heard[$0.id] == nil
        }
    }

    /// Events heard, by id with their start, until they begin. A moved event
    /// has a new id and sounds again for its new start.
    static func heard(_ heard: [String: Date], adding due: [NotchCalendarEvent], now: Date) -> [String: Date] {
        var updated = heard.filter { $0.value > now }
        for event in due { updated[event.id] = event.start }
        return updated
    }

    /// When the next event's sound falls due, so the reader wakes for it.
    static func nextSound(_ events: [NotchCalendarEvent], now: Date) -> Date? {
        events.filter { !$0.allDay }.map { $0.start.addingTimeInterval(-calendarLeadTime) }
            .filter { $0 > now }.min()
    }
}
