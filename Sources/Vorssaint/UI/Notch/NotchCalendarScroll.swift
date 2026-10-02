// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

final class NotchCalendarTileSelection: ObservableObject {
    @Published private(set) var selected = false
    func setSelected(_ value: Bool) { if selected != value { selected = value } }
}

struct NotchCalendarCarouselContentState: Equatable {
    let events: [NotchCalendarEvent]
    let selectedDay: Date?
    let today: Date
}

private final class CalendarCarouselDocument: NSView {
    override var isFlipped: Bool { true }
}

/// A rolling native document, rather than a transition between disconnected pages.
/// Recentring replaces only offscreen dates and preserves the visible fractional offset.
struct NotchCalendarCarousel<Content: View>: NSViewRepresentable {
    let date: Date
    let component: Calendar.Component
    let visibleCount: Int
    let browse: (Date) -> Void
    var settled: (Date) -> Void = { _ in }
    var scrollSensitivity: CGFloat = 1
    var monthAlignmentTolerance: CGFloat = 0
    var coastsMonths = false
    var contentState: NotchCalendarCarouselContentState? = nil
    @ViewBuilder let content: (Date) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CalendarCarouselScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 196, height: proposal.height ?? 52)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> CalendarCarouselScrollView {
        let scroll = CalendarCarouselScrollView()
        context.coordinator.attach(scroll)
        return scroll
    }
    func updateNSView(_ scroll: CalendarCarouselScrollView, context: Context) {
        context.coordinator.update(self)
    }
    static func dismantleNSView(_ scroll: CalendarCarouselScrollView, coordinator: Coordinator) {
        coordinator.stop()
        scroll.stop()
    }

    final class Coordinator {
        var parent: NotchCalendarCarousel
        weak var scroll: CalendarCarouselScrollView?
        private let document = CalendarCarouselDocument()
        private var tiles: [Date: NSHostingView<AnyView>] = [:]
        private var selections: [Date: NotchCalendarTileSelection] = [:]
        private var renderedState: NotchCalendarCarouselContentState?
        private var renderedLocale: String?
        private var renderedViewport = CGSize.zero
        private(set) var renderedCellUpdates = 0
        private var observer: NSObjectProtocol?
        private var anchor: Date
        private var lastBrowsed: Date?
        private var lastInput: Date
        private var liveReadback: Date?
        private var highlightedDay: Date?
        private var centeredCache: (anchor: Date, offset: Int, date: Date)?
        private var viewport = CGSize.zero
        private var updating = false
        private var reportGeneration = 0
        private var radius: Int { parent.component == .day ? 14 : 4 }
        // One month at a time avoids batching incoming layouts in one frame.
        private var rebaseRadius: Int { parent.component == .month ? 2 : radius }
        private var pitch: CGFloat {
            viewport.width / CGFloat(parent.visibleCount)
        }

        init(_ parent: NotchCalendarCarousel) {
            self.parent = parent
            lastInput = parent.date
            anchor = parent.component == .day
                ? Calendar.current.date(byAdding: .day, value: -(parent.visibleCount / 2),
                                        to: Calendar.current.startOfDay(for: parent.date)) ?? parent.date
                : Calendar.current.dateInterval(of: .month, for: parent.date)?.start ?? parent.date
        }
        func attach(_ scroll: CalendarCarouselScrollView) {
            self.scroll = scroll
            configure(scroll)
            scroll.documentView = document
            scroll.didSettle = { [weak self] in self?.settled() }
            scroll.applyScrollDelta = { [weak self] delta in self?.move(by: delta) }
            scroll.contentView.postsBoundsChangedNotifications = true
            scroll.viewportChanged = { [weak self] in self?.layout() }
            observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                               object: scroll.contentView, queue: .main) { [weak self] _ in
                self?.scrolled()
            }
        }
        private func configure(_ scroll: CalendarCarouselScrollView) {
            scroll.snapsDays = parent.component == .day
            scroll.scrollSensitivity = parent.scrollSensitivity
            scroll.monthAlignmentTolerance = parent.monthAlignmentTolerance
            scroll.coastsMonths = parent.coastsMonths
            scroll.reduceMotion = parent.reduceMotion
        }
        func update(_ parent: NotchCalendarCarousel) {
            self.parent = parent
            if let scroll { configure(scroll) }
            layout()
            guard let scroll, pitch > 0 else { return }
            let requested = Calendar.current.startOfDay(for: parent.date)
            if !Calendar.current.isDate(requested, inSameDayAs: lastInput) {
                lastInput = requested
                if liveReadback.map({ Calendar.current.isDate(requested, inSameDayAs: $0) }) == true {
                    rebuild()
                    return
                }
                liveReadback = nil
                reportGeneration += 1
                scroll.cancelMomentum()
                let distance = Calendar.current.dateComponents([parent.component], from: anchor, to: requested)
                    .value(for: parent.component) ?? 0
                let centeredDistance = distance - (parent.component == .day ? parent.visibleCount / 2 : 0)
                if abs(centeredDistance) <= radius / 2 {
                    scroll.setPosition(CGFloat(radius + centeredDistance) * pitch, animated: !parent.reduceMotion)
                } else {
                    updating = true
                    anchor = parent.component == .month
                        ? Calendar.current.dateInterval(of: .month, for: requested)?.start ?? requested
                        : Calendar.current.date(byAdding: .day, value: -(parent.visibleCount / 2), to: requested) ?? requested
                    rebuild()
                    scroll.setPosition(CGFloat(radius) * pitch, animated: false)
                    updating = false
                }
            }
            rebuild()
        }
        private var position: CGFloat {
            guard let scroll, pitch > 0 else { return 0 }
            return scroll.contentView.bounds.minX / pitch
        }
        private func date(at offset: Int) -> Date {
            Calendar.current.date(byAdding: parent.component, value: offset, to: anchor) ?? anchor
        }
        private func layout() {
            guard let scroll, !updating else { return }
            let size = scroll.contentView.bounds.size
            guard size.width > 0, size.height > 0, size != viewport else { return }
            updating = true
            let relative = pitch > 0 ? position - CGFloat(radius) : 0
            viewport = size
            scroll.cellWidth = pitch
            rebuild()
            scroll.setPosition((CGFloat(radius) + relative) * pitch, animated: false)
            updating = false
        }
        private func rebuild(selectedDay: Date? = nil) {
            guard let scroll, pitch > 0 else { return }
            let dates = (-radius..<(radius + parent.visibleCount)).map { date(at: $0) }
            let width = pitch
            let height = viewport.height
            let selectionOnly = parent.component == .day && parent.contentState?.events == renderedState?.events
                && parent.contentState?.today == renderedState?.today
            let contentChanged = parent.contentState == nil || (!selectionOnly && parent.contentState != renderedState)
                || parent.locale.identifier != renderedLocale || viewport != renderedViewport
            // Keep visible hosting views alive while recycling offscreen cells.
            // Their native frames and the clip offset move in the same transaction.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let visibleDates = Set(dates)
            var recycled: [NSHostingView<AnyView>] = []
            for date in Array(tiles.keys) where !visibleDates.contains(date) {
                if let tile = tiles.removeValue(forKey: date) { recycled.append(tile) }
                selections.removeValue(forKey: date)
            }
            document.frame = CGRect(origin: .zero, size: CGSize(width: pitch * CGFloat(dates.count), height: viewport.height))
            for (index, date) in dates.enumerated() {
                let existing = tiles[date]
                let tile = existing ?? recycled.popLast() ?? NSHostingView(rootView: AnyView(EmptyView()))
                tile.sizingOptions = []
                let selection = selections[date] ?? NotchCalendarTileSelection()
                selections[date] = selection
                if existing == nil || (contentChanged && !scroll.scrolling) || viewport != renderedViewport {
                    tile.rootView = AnyView(parent.content(date).id(date)
                        .frame(width: width, height: height, alignment: .topLeading)
                        .environment(\.locale, parent.locale)
                        .environmentObject(selection))
                    renderedCellUpdates += 1
                }
                tile.frame = CGRect(x: CGFloat(index) * pitch, y: 0, width: width, height: height)
                if tile.superview == nil { document.addSubview(tile) }
                tiles[date] = tile
            }
            for tile in recycled { tile.removeFromSuperview() }
            CATransaction.commit()
            if !scroll.scrolling {
                renderedState = parent.contentState
                renderedLocale = parent.locale.identifier
            }
            renderedViewport = viewport
            if parent.component == .day {
                updateSelection(selectedDay ?? (scroll.scrolling ? centeredDate : parent.contentState?.selectedDay ?? parent.date))
            }
        }
        var highlightedDates: [Date] { selections.filter { $0.value.selected }.map(\.key) }
        private func updateSelection(_ selected: Date) {
            let day = Calendar.current.startOfDay(for: selected)
            guard day != highlightedDay || selections[day]?.selected == false else { return }
            if let highlightedDay { selections[highlightedDay]?.setSelected(false) }
            selections[day]?.setSelected(true)
            highlightedDay = day
        }
        var centeredDate: Date {
            let center = parent.component == .day ? CGFloat(parent.visibleCount / 2) : 0
            let offset = Int((position - CGFloat(radius) + center).rounded())
            if let centeredCache, centeredCache.anchor == anchor, centeredCache.offset == offset { return centeredCache.date }
            let result = date(at: offset)
            centeredCache = (anchor, offset, result)
            return result
        }
        private func settled() {
            guard let scroll, !scroll.scrolling, !scroll.programmatic, pitch > 0 else { return }
            reportGeneration += 1
            let selected = centeredDate
            lastInput = selected
            rebuild(selectedDay: selected)
            parent.settled(selected)
        }
        private func move(by delta: CGFloat) {
            guard let scroll, pitch > 0, delta.isFinite else { return }
            // Rebase the intended position before NSClipView can clamp a fast
            // gesture to the finite buffer's edge and discard its remaining travel.
            let relative = position - CGFloat(radius) + delta / pitch
            let rebase = NotchCalendarScrollSupport.rebase(position: Double(relative),
                                                           radius: rebaseRadius)
            updating = true
            if rebase.shift != 0 {
                anchor = date(at: rebase.shift)
                rebuild()
            }
            scroll.setPosition((CGFloat(radius) + CGFloat(rebase.remainder)) * pitch, animated: false)
            updating = false
            reportVisibleDate()
        }
        private func scrolled() {
            guard let scroll, !updating, !scroll.programmatic, pitch > 0 else { return }
            let relative = position - CGFloat(radius)
            if abs(relative) > CGFloat(rebaseRadius) / 2 { move(by: 0) }
            else { reportVisibleDate() }
        }
        private func reportVisibleDate() {
            let visible = centeredDate
            if parent.component == .day { updateSelection(visible) }
            guard lastBrowsed.map({ Calendar.current.isDate(visible, inSameDayAs: $0) }) != true else { return }
            reportGeneration += 1
            let generation = reportGeneration
            // AppKit layout/scroll callbacks can run during a SwiftUI update.
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.reportGeneration else { return }
                self.lastBrowsed = visible
                // The live day callback feeds selection back through SwiftUI.
                // It is readback, not a request to animate to a new date.
                if self.parent.component == .day { self.liveReadback = visible }
                self.parent.browse(visible)
            }
        }
        func stop() {
            reportGeneration += 1
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            scroll?.viewportChanged = nil
            scroll?.didSettle = nil
            scroll?.applyScrollDelta = nil
        }
    }
}

final class CalendarCarouselScrollView: NSScrollView {
    var snapsDays = false
    var scrollSensitivity: CGFloat = 1
    var monthAlignmentTolerance: CGFloat = 0
    var coastsMonths = false
    var reduceMotion = false
    var cellWidth: CGFloat = 0
    var viewportChanged: (() -> Void)?
    var didSettle: (() -> Void)?
    var applyScrollDelta: ((CGFloat) -> Void)?
    private(set) var scrolling = false
    private(set) var programmatic = false
    private var settle: DispatchWorkItem?
    private var horizontalInput: Bool?
    private var pendingX: CGFloat = 0
    private var pendingY: CGFloat = 0
    private var animationGeneration = 0
    private var momentum = NotchCalendarMomentum()
    private var ownsMomentum = false
    private var coast: Timer?
    private var coastVelocity = 0.0
    private var lastCoastTick = 0.0
    var isCoasting: Bool { coast != nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = false
        hasHorizontalScroller = false
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .none
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        viewportChanged?()
    }
    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            super.scrollWheel(with: event)
            return
        }
        // The monthly release has one momentum source. Adding AppKit's
        // momentum deltas to the custom coast would accelerate it twice.
        if ownsMomentum && !event.momentumPhase.isEmpty { return }
        cancelCoast()
        settle?.cancel()
        animationGeneration += 1
        if programmatic {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                contentView.animator().setBoundsOrigin(contentView.bounds.origin)
            }
        }
        scrolling = true
        programmatic = false
        let unphased = event.phase.isEmpty && event.momentumPhase.isEmpty
        if event.phase.contains(.began) || unphased {
            horizontalInput = nil
            pendingX = 0
            pendingY = 0
            momentum = NotchCalendarMomentum()
            ownsMomentum = coastsMonths && !reduceMotion && event.hasPreciseScrollingDeltas && !unphased
        }
        let x = event.scrollingDeltaX, y = event.scrollingDeltaY
        var delta: CGFloat = 0
        if horizontalInput == nil {
            pendingX += x
            pendingY += y
            let largest = max(abs(pendingX), abs(pendingY))
            let smallest = min(abs(pendingX), abs(pendingY))
            if unphased || (largest >= 3 && (largest >= smallest * 1.25 || largest >= 8)) {
                horizontalInput = abs(pendingX) > abs(pendingY)
                delta = horizontalInput == true ? pendingX : pendingY
                pendingX = 0
                pendingY = 0
            }
        } else {
            delta = horizontalInput == true ? x : y
        }
        // Apply the same response to finger travel and system momentum, so
        // lifting or reversing direction does not introduce a speed change.
        delta *= (event.hasPreciseScrollingDeltas ? 1 : 12) * scrollSensitivity
        if ownsMomentum { momentum.record(delta: Double(-delta), timestamp: event.timestamp) }
        if delta.isFinite && delta != 0 { move(by: -delta) }
        let cancelled = event.phase.contains(.cancelled)
        // A finger pause is still an active gesture. Only unphased wheels use
        // inactivity; trackpads settle after lift/momentum end, never mid-swipe.
        let ended = event.phase.contains(.ended) || cancelled || event.momentumPhase.contains(.ended)
        guard unphased || ended else { return }
        if ownsMomentum && !cancelled {
            let velocity = momentum.released(at: event.timestamp, limit: Double(cellWidth * 7))
            if abs(velocity) >= 40 {
                startCoast(velocity: velocity)
                return
            }
        }
        let work = DispatchWorkItem { [weak self] in self?.finishScrolling() }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
        if cancelled || event.momentumPhase.contains(.ended) { horizontalInput = nil }
    }
    private func startCoast(velocity: Double) {
        coastVelocity = velocity
        lastCoastTick = CACurrentMediaTime()
        let fps = max(60, window?.screen?.maximumFramesPerSecond ?? 60)
        let timer = Timer(timeInterval: 1 / Double(fps), repeats: true) { [weak self] _ in self?.coastTick() }
        coast = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func coastTick() {
        let now = CACurrentMediaTime()
        let step = NotchCalendarMomentum.step(velocity: coastVelocity, elapsed: now - lastCoastTick)
        lastCoastTick = now
        coastVelocity = step.velocity
        move(by: CGFloat(step.distance))
        if abs(coastVelocity) < 8 {
            cancelCoast()
            finishScrolling()
        }
    }
    private func finishScrolling() {
        scrolling = false
        if cellWidth > 0 {
            let position = contentView.bounds.minX / cellWidth
            let target = position.rounded()
            let nearMonth = monthAlignmentTolerance > 0 && abs(position - target) <= monthAlignmentTolerance
            if snapsDays || nearMonth {
                if abs(position - target) > 0.0001 {
                    setPosition(target * cellWidth, animated: !reduceMotion,
                                duration: snapsDays ? 0.24 : 0.32,
                                timing: snapsDays ? .easeOut : .easeInEaseOut)
                    if reduceMotion { didSettle?() }
                    return
                }
            }
        }
        didSettle?()
    }
    private func cancelCoast() { coast?.invalidate(); coast = nil; coastVelocity = 0 }
    private func move(by delta: CGFloat) {
        if let applyScrollDelta { applyScrollDelta(delta) }
        else { setPosition(contentView.bounds.minX + delta, animated: false) }
    }
    func cancelMomentum() {
        cancelCoast()
        settle?.cancel()
        scrolling = false
        momentum = NotchCalendarMomentum()
    }
    func setPosition(_ offset: CGFloat, animated: Bool, duration: TimeInterval = 0.24,
                     timing: CAMediaTimingFunctionName = .easeOut) {
        let point = NSPoint(x: offset, y: 0)
        if animated {
            cancelMomentum()
            animationGeneration += 1
            let generation = animationGeneration
            programmatic = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: timing)
                contentView.animator().setBoundsOrigin(point)
            } completionHandler: { [weak self] in
                guard let self, self.animationGeneration == generation else { return }
                self.programmatic = false
                self.reflectScrolledClipView(self.contentView)
                NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: self.contentView)
                self.didSettle?()
            }
        } else {
            contentView.scroll(to: point)
            reflectScrolledClipView(contentView)
        }
    }
    func stop() { cancelMomentum(); settle = nil; viewportChanged = nil; didSettle = nil; applyScrollDelta = nil }
}
