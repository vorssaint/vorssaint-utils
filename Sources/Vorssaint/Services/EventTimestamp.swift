// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin

/// Reads a Quartz event timestamp as nanoseconds of uptime.
///
/// `CGEventTimestamp` is documented as nanoseconds, and that is what a session
/// tap sees. A tap at the HID stage sees hardware events stamped in mach
/// absolute time instead, which on Apple Silicon advances once every 125/3 ns,
/// while events posted by software still arrive there in nanoseconds (#1689).
/// Because one HID tap sees both kinds, the unit is decided per event: of the
/// two readings, the one nearer the current uptime is the unit it carries.
enum EventTimestamp {
    struct Timebase: Equatable {
        let numer: UInt64
        let denom: UInt64
    }

    static let machTimebase: Timebase = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.numer > 0, info.denom > 0 else {
            return Timebase(numer: 1, denom: 1)
        }
        return Timebase(numer: UInt64(info.numer), denom: UInt64(info.denom))
    }()

    /// The event's timestamp in nanoseconds of uptime, the clock
    /// `clock_gettime_nsec_np(CLOCK_UPTIME_RAW)` reads.
    static func nanoseconds(of event: CGEvent) -> UInt64 {
        nanoseconds(raw: event.timestamp, nowTicks: mach_absolute_time(), timebase: machTimebase)
    }

    static func nanoseconds(raw: UInt64, nowTicks: UInt64, timebase: Timebase) -> UInt64 {
        guard timebase.numer != timebase.denom, timebase.denom > 0 else { return raw }
        let fromTicks = nanoseconds(ticks: raw, timebase: timebase)
        let now = nanoseconds(ticks: nowTicks, timebase: timebase)
        return distance(raw, now) <= distance(fromTicks, now) ? raw : fromTicks
    }

    /// `ticks * numer / denom`, rounded down like the system's own conversion
    /// and saturating instead of trapping on a nonsense timestamp.
    static func nanoseconds(ticks: UInt64, timebase: Timebase) -> UInt64 {
        guard timebase.denom > 0 else { return ticks }
        let whole = (ticks / timebase.denom).multipliedReportingOverflow(by: timebase.numer)
        let part = (ticks % timebase.denom).multipliedReportingOverflow(by: timebase.numer)
        guard !whole.overflow, !part.overflow else { return .max }
        let sum = whole.partialValue.addingReportingOverflow(part.partialValue / timebase.denom)
        return sum.overflow ? .max : sum.partialValue
    }

    private static func distance(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        lhs >= rhs ? lhs - rhs : rhs - lhs
    }
}
