// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A month is one cached drawing rather than 42 SwiftUI buttons and layout trees.
/// Native hit testing and accessibility keep each date independently actionable.
struct NotchCalendarMonthCanvas: NSViewRepresentable {
    let month: Date
    let selectedDay: Date?
    let now: Date
    let events: [NotchCalendarEvent]
    let text: NotchCalendarStrings
    let rowHeight: CGFloat
    let weekdayHeight: CGFloat
    let spacing: CGFloat
    let circle: CGFloat
    let dotGap: CGFloat
    let select: (Date) -> Void
    /// Each side contributes half of the gap between adjacent months.
    var horizontalPadding: CGFloat = 0
    var weekNumbers = false
    @Environment(\.locale) private var locale

    var height: CGFloat { weekdayHeight + 6 * rowHeight + 6 * spacing }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CalendarMonthCanvasView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 196, height: height)
    }
    func makeNSView(context: Context) -> CalendarMonthCanvasView { CalendarMonthCanvasView() }
    func updateNSView(_ view: CalendarMonthCanvasView, context: Context) {
        view.configure(self, locale: locale)
    }
}

final class CalendarMonthCanvasView: NSView {
    private struct Week {
        let number: String
        let label: String
    }
    private struct Day {
        let date: Date
        let number: String
        let label: String
        let today: Bool
        let selected: Bool
        let inMonth: Bool
        let colors: [NotchCalendarColor]
    }
    private var configuration: NotchCalendarMonthCanvas?
    private var localeID = ""
    private var days: [Day] = []
    private var weekdays: [String] = []
    private var weeks: [Week] = []
    private var renderedEvents: [NotchCalendarEvent] = []
    private let labelFormatter = DateFormatter()
    private var image: NSImage?
    private var imageSize = CGSize.zero
    private var hover: Int?
    private var tracking: NSTrackingArea?
    private var elements: [CalendarMonthDayAccessibility] = []
    private var weekElements: [NSAccessibilityElement] = []
    private static let weekNumberWidth: CGFloat = 18
    private(set) var imageBuildCount = 0
    private let accent = NSColor(srgbRed: 1, green: 0.36, blue: 0.39, alpha: 1)
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure(_ value: NotchCalendarMonthCanvas, locale: Locale) {
        let old = configuration
        configuration = value
        let calendar = Calendar.current
        let dates = old?.month == value.month ? days.map(\.date)
            : NotchCalendarSupport.monthDays(containing: value.month)
        let end = dates.last.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
        let events = value.events.filter { event in
            guard let first = dates.first, let end else { return false }
            return event.start < end && event.end > first
        }
        func visibleSelection(_ selected: Date?) -> Date? {
            guard let selected, let first = dates.first, let end else { return nil }
            let day = calendar.startOfDay(for: selected)
            return day >= first && day < end ? day : nil
        }
        let selected = visibleSelection(value.selectedDay)
        let contentChanged = old.map {
            $0.month != value.month || visibleSelection($0.selectedDay) != selected
                || !calendar.isDate($0.now, inSameDayAs: value.now) || events != renderedEvents
                || $0.text.today != value.text.today || $0.text.hasEvents != value.text.hasEvents
                || $0.weekNumbers != value.weekNumbers || $0.text.weekNumber != value.text.weekNumber
                || localeID != locale.identifier
        } ?? true
        let layoutChanged = old.map {
            $0.rowHeight != value.rowHeight || $0.weekdayHeight != value.weekdayHeight
                || $0.spacing != value.spacing || $0.circle != value.circle
                || $0.dotGap != value.dotGap || $0.horizontalPadding != value.horizontalPadding
        } ?? true
        guard contentChanged || layoutChanged else { return }

        if contentChanged {
            setAccessibilityElement(true)
            setAccessibilityLabel(value.month.formatted(.dateTime.month(.wide).year().locale(locale)))
            if localeID != locale.identifier || old == nil {
                labelFormatter.locale = locale
                labelFormatter.calendar = calendar
                labelFormatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM yyyy")
            }
            localeID = locale.identifier
            renderedEvents = events
            var localizedCalendar = calendar
            localizedCalendar.locale = locale
            let symbols = localizedCalendar.veryShortStandaloneWeekdaySymbols
            weekdays = (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
            let today = calendar.startOfDay(for: value.now)
            let month = calendar.dateInterval(of: .month, for: value.month)
            let colors = NotchCalendarSupport.colors(events, on: dates, calendar: calendar)
            days = dates.enumerated().map { index, date in
                Day(date: date, number: NotchCalendarSupport.dayNumber(date, locale: locale, calendar: calendar),
                    label: labelFormatter.string(from: date),
                    today: date == today, selected: date == selected,
                    inMonth: month.map { date >= $0.start && date < $0.end } ?? false, colors: colors[index])
            }
            weeks = value.weekNumbers ? stride(from: 0, to: dates.count, by: 7).map { index in
                let date = dates[index]
                return Week(number: NotchCalendarSupport.weekNumber(of: date).formatted(.number.locale(locale)),
                            label: NotchCalendarSupport.weekNumberLabel(of: date, text: value.text))
            } : []
            weekElements = weeks.map { week in
                let element = NSAccessibilityElement()
                element.setAccessibilityRole(.staticText)
                element.setAccessibilityParent(self)
                element.setAccessibilityLabel(week.label)
                return element
            }
            elements = days.enumerated().map { index, day in
                let element = CalendarMonthDayAccessibility()
                element.setAccessibilityRole(.button)
                element.setAccessibilityParent(self)
                element.setAccessibilityLabel(day.label)
                element.setAccessibilityValue([day.today ? value.text.today : "", day.colors.isEmpty ? "" : value.text.hasEvents]
                    .filter { !$0.isEmpty }.joined(separator: ", "))
                element.setAccessibilitySelected(day.selected)
                element.press = { [weak self] in self?.choose(index) }
                return element
            }
        }
        invalidateImage()
    }
    override func layout() {
        super.layout()
        if imageSize != bounds.size { invalidateImage() }
    }
    private func invalidateImage() {
        image = nil
        imageSize = bounds.size
        removeAllToolTips()
        if bounds.width > 2 * (configuration?.horizontalPadding ?? 0) {
            for index in days.indices { addToolTip(rect(index), owner: self, userData: UnsafeMutableRawPointer(bitPattern: index + 1)) }
        }
        needsDisplay = true
    }
    private func rect(_ index: Int) -> CGRect {
        guard let configuration else { return .zero }
        let inset: CGFloat = configuration.horizontalPadding
        let gutter = configuration.weekNumbers ? Self.weekNumberWidth : 0
        let width = (bounds.width - 2 * inset - gutter) / 7
        guard width > 0 else { return .zero }
        return CGRect(x: inset + gutter + CGFloat(index % 7) * width,
                      y: configuration.weekdayHeight + configuration.spacing
                        + CGFloat(index / 7) * (configuration.rowHeight + configuration.spacing),
                      width: width, height: configuration.rowHeight)
    }
    private func weekRect(_ row: Int) -> CGRect {
        guard let configuration else { return .zero }
        return CGRect(x: configuration.horizontalPadding,
                      y: configuration.weekdayHeight + configuration.spacing
                        + CGFloat(row) * (configuration.rowHeight + configuration.spacing),
                      width: Self.weekNumberWidth, height: configuration.rowHeight)
    }
    private func index(at point: NSPoint) -> Int? {
        guard bounds.contains(point), let configuration, bounds.width > 0 else { return nil }
        let start = configuration.horizontalPadding + (configuration.weekNumbers ? Self.weekNumberWidth : 0)
        let width = bounds.width - configuration.horizontalPadding - start
        guard width > 0, point.x >= start, point.x < bounds.width - configuration.horizontalPadding else { return nil }
        let row = Int(floor((point.y - configuration.weekdayHeight - configuration.spacing)
                            / (configuration.rowHeight + configuration.spacing)))
        guard (0..<6).contains(row) else { return nil }
        let index = row * 7 + min(6, Int((point.x - start) / (width / 7)))
        return days.indices.contains(index) && rect(index).contains(point) ? index : nil
    }
    private func choose(_ index: Int) {
        guard days.indices.contains(index) else { return }
        configuration?.select(days[index].date)
    }
    func date(at point: NSPoint) -> Date? { index(at: point).map { days[$0].date } }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if let index = index(at: convert(event.locationInWindow, from: nil)) { choose(index) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        tracking = area
        addTrackingArea(area)
    }
    override func mouseMoved(with event: NSEvent) {
        let new = index(at: convert(event.locationInWindow, from: nil))
        if new != hover { hover = new; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { hover = nil; needsDisplay = true }
    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        let index = data.map { Int(bitPattern: $0) - 1 } ?? -1
        return days.indices.contains(index) ? days[index].label : ""
    }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityChildren() -> [Any]? {
        var children: [NSAccessibilityElement] = []
        for (index, element) in elements.enumerated() {
            if index % 7 == 0, weekElements.indices.contains(index / 7) {
                let week = weekElements[index / 7]
                week.setAccessibilityFrame(window?.convertToScreen(convert(weekRect(index / 7), to: nil)) ?? .zero)
                children.append(week)
            }
            element.setAccessibilityFrame(window?.convertToScreen(convert(rect(index), to: nil)) ?? .zero)
            children.append(element)
        }
        return children
    }
    override func keyDown(with event: NSEvent) {
        var index = hover ?? days.firstIndex(where: { $0.selected }) ?? days.firstIndex(where: { $0.today }) ?? 0
        switch event.keyCode {
        case 123: index -= 1
        case 124: index += 1
        case 125: index += 7
        case 126: index -= 7
        case 36, 49: choose(index); return
        default: super.keyDown(with: event); return
        }
        hover = min(max(0, index), max(0, days.count - 1))
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let configuration, bounds.width > 2 * configuration.horizontalPadding else { return }
        if image == nil {
            imageBuildCount += 1
            // Capture immutable drawing data, so the cache never retains this view.
            let days = days, weekdays = weekdays, weeks = weeks, size = bounds.size, accent = accent
            let rowHeight = configuration.rowHeight, weekdayHeight = configuration.weekdayHeight
            let spacing = configuration.spacing, circleSize = configuration.circle, dotGap = configuration.dotGap
            let inset = configuration.horizontalPadding
            let gutter = configuration.weekNumbers ? Self.weekNumberWidth : 0
            image = NSImage(size: size, flipped: true) { _ in
                let width = (size.width - 2 * inset - gutter) / 7
                let renderedCircleSize = min(circleSize, width - 3)
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                func text(_ value: String, rect: CGRect, font: NSFont, color: NSColor) {
                    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
                    let height = (value as NSString).size(withAttributes: attributes).height
                    (value as NSString).draw(in: CGRect(x: rect.minX, y: rect.midY - height / 2,
                                                        width: rect.width, height: height), withAttributes: attributes)
                }
                for (column, weekday) in weekdays.enumerated() {
                    text(weekday, rect: CGRect(x: inset + gutter + CGFloat(column) * width, y: 0, width: width, height: weekdayHeight),
                         font: .systemFont(ofSize: 9, weight: .medium), color: .white.withAlphaComponent(0.45))
                }
                for (index, day) in days.enumerated() {
                    let rowY = weekdayHeight + spacing + CGFloat(index / 7) * (rowHeight + spacing)
                    let centerX = inset + gutter + (CGFloat(index % 7) + 0.5) * width
                    let circle = CGRect(x: centerX - renderedCircleSize / 2,
                                        y: rowY + (rowHeight - renderedCircleSize - 3 - dotGap) / 2,
                                        width: renderedCircleSize, height: renderedCircleSize)
                    if index % 7 == 0, weeks.indices.contains(index / 7) {
                        text(weeks[index / 7].number,
                             rect: CGRect(x: inset, y: circle.minY, width: gutter, height: renderedCircleSize),
                             font: .monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                             color: .white.withAlphaComponent(0.45))
                    }
                    if day.today || day.selected {
                        (day.today ? accent : NSColor.white).setFill()
                        NSBezierPath(ovalIn: circle).fill()
                    }
                    if day.today && day.selected {
                        NSColor.white.withAlphaComponent(0.8).setStroke()
                        let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 0.75, dy: 0.75))
                        ring.lineWidth = 1.5
                        ring.stroke()
                    }
                    let font = NSFont.systemFont(ofSize: min(11, renderedCircleSize * 0.62), weight: day.today || day.selected ? .bold : .medium)
                    let color = day.selected && !day.today ? NSColor.black
                        : NSColor(white: day.today || day.inMonth ? 1 : 0.4, alpha: 1)
                    text(day.number, rect: circle, font: font, color: color)
                    for (dot, color) in day.colors.enumerated() {
                        NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1).setFill()
                        let totalWidth = CGFloat(day.colors.count * 5 - 2)
                        NSBezierPath(ovalIn: CGRect(x: centerX - totalWidth / 2 + CGFloat(dot * 5),
                                                    y: circle.maxY + dotGap, width: 3, height: 3)).fill()
                    }
                }
                return true
            }
        }
        if let hover {
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: rect(hover), xRadius: 6, yRadius: 6).fill()
        }
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

private final class CalendarMonthDayAccessibility: NSAccessibilityElement {
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { press?(); return press != nil }
}
