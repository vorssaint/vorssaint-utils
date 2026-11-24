// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Outlives the outgoing page, so one physical swipe cannot change several
/// pages while the first page is being replaced.
final class HomeAssistantPagingSession: ObservableObject {
    var swipe = HomeAssistantPageSwipe()
    var rows = NotchSectionScroll()
}

/// Uses Explore's row paging, indicator, clipping and spring. Horizontal input
/// changes named pages; vertical input only steps the rows of the current page.
struct NotchHomeAssistantGallery<Tile: View>: View {
    let ids: [String]
    let columns: Int
    let fillLastRow: Bool
    let layout: NotchHomeAssistantLayout
    let availableHeight: CGFloat
    let pageID: String
    let preview: Bool
    let empty: String
    let session: HomeAssistantPagingSession
    let changePage: (Int) -> Void
    let tile: (String, Int) -> Tile
    @State private var first = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    private var visible: Int {
        min(layout.visibleRows, max(1, Int((availableHeight + NotchHomeAssistantLayout.spacing)
                                         / (layout.cardHeight + NotchHomeAssistantLayout.spacing))))
    }
    private var positions: Int { NotchSectionPaging.positions(rows: layout.rows, visible: visible) }

    var body: some View {
        Group {
            if ids.isEmpty {
                NotchEmptyView(symbol: "house", message: empty)
            } else if availableHeight < layout.cardHeight {
                // An unusually short display still exposes the bottom of a card.
                ScrollView(.vertical) { rows(first: 0, visible: layout.rows) }
                    .scrollBounceBehavior(.basedOnSize)
            } else {
                HStack(spacing: 0) {
                    let start = NotchSectionPaging.clamped(first, rows: layout.rows, visible: visible)
                    rows(first: start, visible: visible)
                        .offset(y: -CGFloat(start) * (layout.cardHeight + NotchHomeAssistantLayout.spacing))
                        .frame(height: CGFloat(visible) * layout.cardHeight
                               + CGFloat(max(0, visible - 1)) * NotchHomeAssistantLayout.spacing, alignment: .top)
                        .clipped()
                        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0), value: start)
                    indicator(current: start)
                        .frame(width: NotchLayout.sectionIndicatorWidth, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(HomeAssistantPagingCapture(pageID: pageID, enabled: !preview, session: session,
                                              stepRows: availableHeight < layout.cardHeight ? nil : stepRows,
                                              changePage: changePage))
        .accessibilityScrollAction { edge in
            switch edge {
            case .bottom: stepRows(1)
            case .top: stepRows(-1)
            case .trailing: changePage(1)
            case .leading: changePage(-1)
            }
        }
        .onChange(of: ids) { first = NotchSectionPaging.clamped(first, rows: layout.rows, visible: visible) }
        .onChange(of: columns) { first = 0 }
    }
    private func rows(first: Int, visible: Int) -> some View {
        VStack(spacing: NotchHomeAssistantLayout.spacing) {
            ForEach(0..<layout.rows, id: \.self) { row in
                let slots = layout.slots(in: row, fillLastRow: fillLastRow)
                HStack(spacing: columns >= 6 ? 4 : 8) {
                    ForEach(0..<slots, id: \.self) { column in
                        let index = row * columns + column
                        if index < ids.count {
                            tile(ids[index], slots)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: layout.cardHeight)
                        }
                    }
                }
                .allowsHitTesting((first..<(first + visible)).contains(row))
                .environment(\.homeAssistantCardVisible, (first..<(first + visible)).contains(row))
                .accessibilityHidden(!(first..<(first + visible)).contains(row))
            }
        }
    }
    @ViewBuilder private func indicator(current: Int) -> some View {
        if positions > 1 {
            ScrollViewReader { reader in
                ScrollView(.vertical) {
                    VStack(spacing: 5) {
                        ForEach(0..<positions, id: \.self) { position in
                            Button { first = position } label: {
                                Circle().fill(.white.opacity(position == current ? 0.9 : contrast == .increased ? 0.5 : 0.28))
                                    .frame(width: 6, height: 6).frame(width: 12, height: 12).contentShape(Rectangle())
                            }.buttonStyle(.plain).id(position)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(height: min(CGFloat(positions) * 17 - 5,
                                   CGFloat(visible) * layout.cardHeight + CGFloat(max(0, visible - 1)) * NotchHomeAssistantLayout.spacing))
                .onChange(of: current) { reader.scrollTo(current, anchor: .center) }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: current)
            .accessibilityHidden(true)
        } else { Color.clear }
    }
    private func stepRows(_ offset: Int) {
        first = NotchSectionPaging.clamped(first + offset, rows: layout.rows, visible: visible)
    }
}

/// A window-local monitor, mounted only on the gallery. It leaves native
/// sliders, text controls, modified input and events outside the page alone.
private struct HomeAssistantPagingCapture: NSViewRepresentable {
    let pageID: String
    let enabled: Bool
    let session: HomeAssistantPagingSession
    let stepRows: ((Int) -> Void)?
    let changePage: (Int) -> Void
    func makeNSView(context: Context) -> Capture { Capture(session: session) }
    func updateNSView(_ view: Capture, context: Context) {
        view.pageID = pageID; view.enabled = enabled
        view.stepRows = stepRows; view.changePage = changePage
    }
    static func dismantleNSView(_ view: Capture, coordinator: ()) { view.stop() }

    final class Capture: NSView {
        var pageID = ""
        var enabled = false
        var stepRows: ((Int) -> Void)?
        var changePage: ((Int) -> Void)?
        private var monitor: Any?
        private let session: HomeAssistantPagingSession
        init(session: HomeAssistantPagingSession) { self.session = session; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.enabled, let window = self.window, event.window === window,
                      !self.isHiddenOrHasHiddenAncestor, self.bounds.contains(self.convert(event.locationInWindow, from: nil)),
                      HomeAssistantService.shared.activePageID == self.pageID,
                      event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return event }
                var hit = window.contentView?.hitTest(event.locationInWindow)
                while let view = hit {
                    if view is NSSlider || view is NSTextField || view is NSTextView {
                        self.session.swipe = HomeAssistantPageSwipe(); self.session.rows = NotchSectionScroll(); return event
                    }
                    hit = view.superview
                }
                let result = self.session.swipe.handle(
                    x: NotchGestureSupport.movement(Double(event.scrollingDeltaX), precise: event.hasPreciseScrollingDeltas,
                                                   inverted: event.isDirectionInvertedFromDevice),
                    y: NotchGestureSupport.movement(Double(event.scrollingDeltaY), precise: event.hasPreciseScrollingDeltas,
                                                   inverted: event.isDirectionInvertedFromDevice),
                    timestamp: event.timestamp, precise: event.hasPreciseScrollingDeltas,
                    began: event.phase.contains(.began), ended: !event.phase.intersection([.ended, .cancelled]).isEmpty,
                    momentum: !event.momentumPhase.isEmpty, hasPhase: !event.phase.isEmpty)
                switch result {
                case .change(let offset): self.changePage?(offset); return nil
                case .consume: return nil
                case .passThrough:
                    guard let step = self.stepRows,
                          !event.hasPreciseScrollingDeltas || self.session.swipe.isVertical else { return event }
                    let count = self.session.rows.steps(deltaY: Double(event.scrollingDeltaY), timestamp: event.timestamp,
                                                precise: event.hasPreciseScrollingDeltas, hasPhase: !event.phase.isEmpty,
                                                began: event.phase.contains(.began),
                                                ended: !event.phase.intersection([.ended, .cancelled]).isEmpty,
                                                momentum: !event.momentumPhase.isEmpty)
                    if count != 0 { step(count) }
                    return nil
                }
            }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        deinit { stop() }
    }
}
