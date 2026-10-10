// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if VORSSAINT_DEVELOPMENT
import AppKit
import SwiftUI
import QuartzCore

/// Uses production calendar cells and native scroll events in a hidden window.
/// No EventKit reads or desktop input; the same synthetic events run every time.
enum NotchCalendarPerformanceProbe {
    static func runAndExit() -> Never {
        _ = NSApplication.shared
        let calendar = Calendar(identifier: .gregorian)
        let initial = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let events = (0..<256).map { index in
            let start = calendar.date(byAdding: .day, value: index % 90 - 30, to: initial)!
            return NotchCalendarEvent(id: "fixture-\(index)", title: "Appointment", calendar: "Fixture",
                                      start: start, end: start.addingTimeInterval(3600), allDay: false, location: "")
        }
        let week = CommandLine.arguments.contains("--calendar-week")
        let content = week ? AnyView(CalendarWeekProbeFixture(initial: initial, events: events))
            : AnyView(CalendarProbeFixture(initial: initial, events: events))
        let host = NSHostingView(rootView: content
            .environment(\.locale, Locale(identifier: "en_US"))
            .frame(width: 540, height: 220).background(.black))
        host.sizingOptions = []
        host.frame = CGRect(x: 0, y: 0, width: 540, height: 220)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = host
        let start = CACurrentMediaTime()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        host.layoutSubtreeIfNeeded()
        func findScroll(_ view: NSView) -> CalendarCarouselScrollView? {
            if let scroll = view as? CalendarCarouselScrollView { return scroll }
            return view.subviews.lazy.compactMap { findScroll($0) }.first
        }
        guard let scroll = findScroll(host) else { fatalError("Calendar date viewport missing") }
        CATransaction.flush()
        let initialMS = (CACurrentMediaTime() - start) * 1000
        if CommandLine.arguments.contains("--calendar-coast-benchmark") {
            let began = CACurrentMediaTime()
            func feed(_ points: Int32, phase: Int64, timestamp: Double) {
                let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                    wheel1: 0, wheel2: -points, wheel3: 0)!
                event.timestamp = UInt64(timestamp * 1_000_000_000)
                event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
                scroll.scrollWheel(with: NSEvent(cgEvent: event)!)
            }
            feed(0, phase: 1, timestamp: began)
            for index in 1...5 { feed(24, phase: 2, timestamp: began + Double(index) / 60) }
            feed(0, phase: 4, timestamp: began + 5.0 / 60)
            let released = scroll.contentView.bounds.minX
            var movement: [Double] = []
            var previous = released
            var samples: [Double] = []
            while scroll.isCoasting {
                RunLoop.main.run(until: Date().addingTimeInterval(1 / 60))
                let start = CACurrentMediaTime()
                host.layoutSubtreeIfNeeded()
                CATransaction.flush()
                samples.append((CACurrentMediaTime() - start) * 1000)
                let position = scroll.contentView.bounds.minX
                movement.append(Double(position - previous))
                previous = position
            }
            guard !movement.isEmpty, movement.first! > movement.last!, movement.allSatisfy({ $0 >= 0 }),
                  previous - released > 250 else { fatalError("Production month coast failed to decelerate") }
            print(String(format: "calendar-coast: frames=%d distance=%.2fpt firstFrame=%.2fpt lastFrame=%.2fpt maxLayout=%.2fms",
                         locale: Locale(identifier: "en_US_POSIX"), movement.count, previous - released,
                         movement.first!, movement.last!, samples.max()!))
            scroll.stop()
            exit(0)
        }
        let betweenMonths = CommandLine.arguments.contains("--calendar-between-months")
        let afterScroll = CommandLine.arguments.contains("--calendar-after-fast-scroll") || betweenMonths
        if afterScroll {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                wheel1: 0, wheel2: -Int32(scroll.cellWidth * (betweenMonths ? 2 / 3 : 30.625)), wheel3: 0)!
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            scroll.scrollWheel(with: NSEvent(cgEvent: event)!)
            RunLoop.main.run(until: Date().addingTimeInterval(0.7))
            host.layoutSubtreeIfNeeded()
        }
        if CommandLine.arguments.contains("--calendar-month-snapshot"),
           let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = NSImage(size: host.bounds.size)
            image.lockFocus()
            NSColor.black.setFill()
            host.bounds.fill()
            let foreground = NSImage(size: host.bounds.size)
            foreground.addRepresentation(bitmap)
            foreground.draw(in: host.bounds, from: .zero, operation: .sourceOver, fraction: 1)
            image.unlockFocus()
            if let tiff = image.tiffRepresentation, let output = NSBitmapImageRep(data: tiff),
               let data = output.representation(using: .png, properties: [:]) {
                let name = week ? "week" : "month"
                let suffix = afterScroll ? "-after-scroll" : ""
                try? data.write(to: URL(fileURLWithPath: "/tmp/vorssaint-calendar-\(name)\(suffix).png"))
            }
            exit(0)
        }
        var samples: [Double] = []
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                            wheel1: 0, wheel2: -32, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let native = NSEvent(cgEvent: event)!
        for _ in 0..<240 {
            let start = CACurrentMediaTime()
            autoreleasepool {
                scroll.scrollWheel(with: native)
                window.contentView?.layoutSubtreeIfNeeded()
                CATransaction.flush()
            }
            samples.append((CACurrentMediaTime() - start) * 1000)
        }
        let sorted = samples.sorted()
        print(String(format: "calendar-scroll: initial=%.2fms median=%.2fms p95=%.2fms max=%.2fms framesOver16ms=%d",
                     locale: Locale(identifier: "en_US_POSIX"), initialMS, sorted[sorted.count / 2],
                     sorted[Int(Double(sorted.count - 1) * 0.95)],
                     sorted.last!, samples.filter { $0 > 16.67 }.count))
        scroll.stop()
        exit(0)
    }
}

private struct CalendarProbeFixture: View {
    let initial: Date
    let events: [NotchCalendarEvent]
    @State private var focus: Date
    init(initial: Date, events: [NotchCalendarEvent]) {
        self.initial = initial
        self.events = events
        _focus = State(initialValue: initial)
    }
    var body: some View {
        NotchCalendarMonthGrid(month: focus, selectedDay: focus, now: initial, height: 220,
                               events: events, text: FeatureStrings.notchCalendar(.enUS),
                               select: { focus = $0 }, move: { _ in }, today: {}, open: {}, week: {},
                               settled: { focus = $0 })
    }
}

private struct CalendarWeekProbeFixture: View {
    let initial: Date
    let events: [NotchCalendarEvent]
    @State private var focus: Date
    init(initial: Date, events: [NotchCalendarEvent]) {
        self.initial = initial
        self.events = events
        _focus = State(initialValue: initial)
    }
    var body: some View {
        VStack(spacing: 12) {
            NotchCalendarWeekStrip(width: 540, focus: focus, selectedDay: focus, now: initial,
                                   events: events, text: FeatureStrings.notchCalendar(.enUS),
                                   select: { focus = $0 }, move: { _ in }, today: {}, week: {}, month: {}, open: {},
                                   browse: { focus = $0 })
            Text(focus, format: .dateTime.weekday(.wide).day().month(.wide).year())
                .font(.system(size: 12)).foregroundStyle(.white)
        }
    }
}
#endif
