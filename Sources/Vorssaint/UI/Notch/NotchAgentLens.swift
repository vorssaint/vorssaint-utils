// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Whose use a chart on the AI page shows. A two-finger swipe over the chart steps
/// from every agent together to each agent that has history, then to Kilo Code.
enum NotchAgentLens: Hashable {
    case all
    case provider(AgentProvider)
    case kilo

    /// The lenses a chart offers, in swipe order: everyone first, then each agent
    /// with recorded use, then Kilo Code when its database has any.
    static func available(snapshot: AgentUsageSnapshot, providers: [AgentProvider], kiloDays: [AgentBucket]) -> [NotchAgentLens] {
        var lenses: [NotchAgentLens] = [.all]
        for provider in providers where snapshot.days.contains(where: { ($0.byProvider[provider]?.requests ?? 0) > 0
            || ($0.byProvider[provider]?.tokens.total ?? 0) > 0 || ($0.observedCursorActivity && provider == .cursor) }) {
            lenses.append(.provider(provider))
        }
        if kiloDays.contains(where: { ($0.byProvider[.opencode]?.tokens.total ?? 0) > 0 }) { lenses.append(.kilo) }
        // One agent alone gives nothing to swipe to.
        return lenses.count > 2 ? lenses : [.all]
    }

    /// The providers a chart stacks for this lens.
    func providers(all: [AgentProvider]) -> [AgentProvider] {
        switch self {
        case .all: return all
        case .provider(let provider): return [provider]
        case .kilo: return [.opencode]
        }
    }

    func name(kilo: String) -> String? {
        switch self {
        case .all: return nil
        case .provider(let provider): return provider.displayName
        case .kilo: return kilo
        }
    }

    var tint: Color? {
        switch self {
        case .all: return nil
        case .provider(let provider): return provider.tint
        case .kilo: return Color(red: 0.96, green: 0.84, blue: 0.2)
        }
    }

    /// The snapshot the chart reads: the same history cut to one agent, or Kilo's own.
    func snapshot(from base: AgentUsageSnapshot, kiloDays: [AgentBucket], kiloHours: [AgentBucket]) -> AgentUsageSnapshot {
        switch self {
        case .all:
            return base
        case .provider(let provider):
            var cut = base
            func only(_ bucket: AgentBucket) -> AgentBucket {
                var kept = AgentBucket(start: bucket.start)
                kept.byProvider = bucket.byProvider.filter { $0.key == provider }
                kept.observedCursorActivity = bucket.observedCursorActivity && provider == .cursor
                return kept
            }
            cut.days = base.days.map(only)
            cut.hours = base.hours.map(only)
            cut.periods = base.periods.mapValues { usage in
                var kept = AgentPeriodUsage()
                kept.total = usage.byProvider[provider] ?? AgentTotals()
                kept.byProvider = usage.byProvider.filter { $0.key == provider }
                kept.models = usage.models.filter { $0.provider == provider }
                kept.projects = usage.projects.filter { $0.provider == provider }
                return kept
            }
            return cut
        case .kilo:
            var cut = base
            cut.days = kiloDays
            cut.hours = kiloHours
            cut.seen = [.opencode]
            cut.periods = Dictionary(uniqueKeysWithValues: AgentPeriod.allCases.map { period in
                var kept = AgentPeriodUsage()
                let buckets = period == .today ? kiloHours : Array(kiloDays.suffix(period.days))
                for bucket in buckets {
                    guard let totals = bucket.byProvider[.opencode] else { continue }
                    kept.total += totals
                    kept.byProvider[.opencode, default: AgentTotals()] += totals
                }
                return (period, kept)
            })
            return cut
        }
    }
}

/// A row of dots under a chart's title, one per lens, the current one lit.
struct NotchAgentLensDots: View {
    let count: Int
    let current: Int

    var body: some View {
        if count > 1 {
            HStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { index in
                    Circle().fill(.white.opacity(index == current ? 0.85 : 0.25)).frame(width: 4, height: 4)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// Reports a horizontal two-finger swipe made over the view it is placed behind.
/// It never takes a click and passes every event it does not use.
struct NotchAgentSwipe: NSViewRepresentable {
    /// -1 for a swipe toward the next lens (fingers moving left), 1 for the previous.
    let step: (Int) -> Void

    func makeNSView(context: Context) -> SwipeView {
        let view = SwipeView()
        view.step = step
        return view
    }

    func updateNSView(_ view: SwipeView, context: Context) { view.step = step }

    final class SwipeView: NSView {
        var step: ((Int) -> Void)?
        private var monitor: Any?
        private var travelled = 0.0
        private var fired = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window, event.hasPreciseScrollingDeltas else { return event }
            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point) else { return event }
            if event.phase.contains(.began) { travelled = 0; fired = false }
            let x = Double(event.scrollingDeltaX), y = Double(event.scrollingDeltaY)
            // Mostly sideways: this is the card's swipe, not a scroll of the page.
            guard abs(x) > abs(y) || fired else { return event }
            if !event.momentumPhase.isEmpty { return fired ? nil : event }
            travelled += x
            if !fired, abs(travelled) >= 36 {
                fired = true
                // Fingers moving left carry the next lens in, whichever way the pad scrolls.
                let left = (travelled < 0) == event.isDirectionInvertedFromDevice
                step?(left ? -1 : 1)
            }
            return nil
        }
    }
}
