// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The closed island while an agent works: its mark on one side of the
/// camera, one reading the person chose on the other. The wings are as wide
/// as the reading, and both sit at the ends, where the island shows.
struct NotchAgentStrip: View {
    @ObservedObject var service: NotchService
    /// Where the island draws it: its own strip as of the last update, or
    /// another display's when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchAgentsReadout) private var readout = NotchAgentReadout.elapsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitFocus) private var focus = NotchAgentLimitFocus.mostUsed.rawValue

    private func working(_ live: [AgentLiveSession]) -> [AgentProvider] {
        AgentProvider.allCases.filter { provider in live.contains { $0.provider == provider } }
    }

    var body: some View {
        // The last agent stopping empties the list before the strip has left.
        NotchStripHold(usage.snapshot.live, shows: !usage.snapshot.live.isEmpty) { strip(live: $0) }
    }

    @ViewBuilder private func strip(live: [AgentLiveSession]) -> some View {
        // Resolve layout once per presentation update. The timeline captures
        // these values, so ticking the clock never remeasures the island or
        // walks the preferences for every font, inset and frame.
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let working = working(live)
        let tint = working.first?.tint ?? .white
        let budget = geometry.compactActivityContentHeight - NotchLayout.compactEdgeGap * 2
        let iconSize = min(working.count > 1 ? 11.0 : 14.0, max(8, budget - 4))
        let textSize = NotchAgentSupport.stripTextSize(height: geometry.compactActivityContentHeight)
        let iconInset = !geometry.compactActivityUsesFooter
            ? geometry.compactActivityEdgeInset(boxHeight: iconSize + 4, radius: (iconSize + 4) / 2) : 0
        let textInset = !geometry.compactActivityUsesFooter
            ? geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0) : 0
        HStack(spacing: 0) {
            Button { service.openActivity(.agents) } label: {
                HStack(spacing: 1) {
                    if geometry.compactActivityWingWidth >= 28 {
                        ForEach(working) { NotchAgentGlyph(provider: $0, size: iconSize) }
                    }
                }
                .padding(.leading, iconInset)
                .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                       alignment: .leading)
                .contentShape(Rectangle())
            }
            Color.clear.frame(width: geometry.compactActivityCameraGap)
            Button { service.openActivity(.agents) } label: {
                Group {
                    if geometry.compactActivityWingWidth >= 42 {
                        NotchAgentReadoutTimeline(readout: NotchAgentReadout(rawValue: readout) ?? .elapsed) { date in
                            let text = reading(at: date, live: live)
                            Text(text)
                                .font(.system(size: textSize, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(tint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                // A reading that gains a digit, like an hour
                                // passing, needs wider wings; the service
                                // measures the same reading.
                                .onChange(of: NotchAgentSupport.readingShape(text)) { _, _ in
                                    DispatchQueue.main.async { service.refreshPresentation() }
                                }
                        }
                    }
                }
                .padding(.trailing, textInset)
                .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                       alignment: .trailing)
                .contentShape(Rectangle())
            }
        }
        .frame(height: geometry.compactActivityContentHeight)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(working.map(\.displayName).joined(separator: ", "))
        .accessibilityValue(reading(at: Date(), live: live))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { service.openActivity(.agents) }
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }

    private func reading(at now: Date, live: [AgentLiveSession]) -> String {
        var snapshot = usage.snapshot
        snapshot.live = live
        return NotchAgentSupport.stripReading(snapshot, readout: NotchAgentReadout(rawValue: readout) ?? .elapsed,
                                              display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining,
                                              focus: NotchAgentLimitFocus(rawValue: focus) ?? .mostUsed, now: now)
    }
}

/// Keep the original one-second cadence for time-dependent readings, but
/// install no clock at all for values updated by the observed usage snapshot.
struct NotchAgentReadoutTimeline<Content: View>: View {
    let readout: NotchAgentReadout
    @ViewBuilder var content: (Date) -> Content

    var body: some View {
        if readout.advancesWithClock {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(context.date)
            }
        } else {
            content(.now)
        }
    }
}

/// The resting island's AI preferences, read together by every piece that
/// draws or describes the meters.
struct NotchAgentRestingChoices: DynamicProperty {
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitFocus) private var focus = NotchAgentLimitFocus.mostUsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsRestingLayout) private var layoutValue = NotchAgentRestingLayout.single.rawValue
    @AppStorage(DefaultsKey.notchAgentsRestingSession) private var session = true
    @AppStorage(DefaultsKey.notchAgentsRestingWeekly) private var weekly = true
    @AppStorage(DefaultsKey.notchAgentsRestingHidden) private var hidden = ""

    var used: Bool { display == NotchAgentLimitDisplay.used.rawValue }
    var layout: NotchAgentRestingLayout { NotchAgentRestingLayout(rawValue: layoutValue) ?? .single }

    /// The meters the layout shows, in its order. The snapshot already
    /// holds only the agents switched on, in no particular order.
    func meters(_ snapshot: AgentUsageSnapshot, now: Date) -> [NotchAgentRestingMeter] {
        let shown = NotchAgentSupport.applyingSimulation(snapshot, NotchAgentSupport.simulatedRestingUsage())
        return NotchAgentSupport.restingSequence(shown, layout: layout, providers: AgentProvider.allCases,
                                                 hidden: NotchAgentSupport.parseRestingHidden(hidden),
                                                 session: session, weekly: weekly,
                                                 focus: NotchAgentLimitFocus(rawValue: focus) ?? .mostUsed, now: now)
    }

    /// The agent whose mark stands in while none reports a limit: the first
    /// seen, unless it is left out at rest.
    func fallbackProvider(_ snapshot: AgentUsageSnapshot) -> AgentProvider? {
        let left = NotchAgentSupport.parseRestingHidden(hidden)
        return AgentProvider.allCases.first { snapshot.seen.contains($0) && !left.contains($0) }
    }
}

/// Where a piece of the resting AI meters draws: a wing beside the camera,
/// or the capsule's one row.
enum NotchAgentRestingPlacement {
    case leading, trailing, row
}

/// The resting island's wings: each account's limits as a ring and a bar
/// with a number, laid out as the person chose, or today's API value when
/// no allowance is known.
struct NotchAgentRestingWing: View {
    let side: HorizontalEdge
    /// Example usage for the settings preview while none is known.
    var sample: AgentUsageSnapshot? = nil

    var body: some View {
        NotchAgentRestingContent(placement: side == .leading ? .leading : .trailing, sample: sample)
    }
}

/// The capsule's resting row: the same meters side by side.
struct NotchAgentRestingRow: View {
    var body: some View { NotchAgentRestingContent(placement: .row) }
}

private struct NotchAgentRestingContent: View {
    let placement: NotchAgentRestingPlacement
    var sample: AgentUsageSnapshot? = nil
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var choices = NotchAgentRestingChoices()

    init(placement: NotchAgentRestingPlacement, sample: AgentUsageSnapshot? = nil) {
        self.placement = placement
        self.sample = sample
    }

    /// Room for the number in a wing: what the ring leaves of the 44-point
    /// wing past its shoulder, or the whole wing's when alone there.
    private static let besideRing: CGFloat = 17.5
    private static let alone: CGFloat = 31
    private static let gap: CGFloat = 1.5

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder private func content(now: Date) -> some View {
        let snapshot = sample ?? usage.snapshot
        let meters = choices.meters(snapshot, now: now)
        if meters.isEmpty {
            fallback(snapshot)
        } else if choices.layout == .cycle, meters.count > 1, !reduceMotion {
            TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: NotchAgentSupport.restingCycle)) { tick in
                let meter = meters[NotchAgentSupport.restingCycleIndex(at: tick.date, count: meters.count)]
                ZStack {
                    one(meter).id(meter.id).transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.3), value: meter.id)
            }
        } else if choices.layout == .split, meters.count > 1 {
            split(meters[0], meters[1])
        } else {
            // Single, Rotate held still, or One per side with one account.
            one(meters[0])
        }
    }

    @ViewBuilder private func one(_ meter: NotchAgentRestingMeter) -> some View {
        switch placement {
        case .leading: gauge(meter)
        case .trailing: amount(meter, width: Self.alone, worded: true)
        case .row: HStack(spacing: Self.gap) { gauge(meter); amount(meter, width: Self.alone, worded: true) }
        }
    }

    /// The first account left of the camera, the second right of it, each
    /// with its meter at the outer edge. Beside a ring the wing holds only
    /// the bare number; the ring's fill and VoiceOver say left or used.
    @ViewBuilder private func split(_ first: NotchAgentRestingMeter, _ second: NotchAgentRestingMeter) -> some View {
        switch placement {
        case .leading:
            HStack(spacing: Self.gap) { gauge(first); amount(first, width: Self.besideRing, worded: false) }
        case .trailing:
            HStack(spacing: Self.gap) { amount(second, width: Self.besideRing, worded: false, gauge: .trailing); gauge(second) }
        case .row:
            HStack(spacing: NotchCapsuleLayout.groupSpacing) {
                HStack(spacing: Self.gap) { gauge(first); amount(first, width: Self.alone, worded: true) }
                HStack(spacing: Self.gap) { gauge(second); amount(second, width: Self.alone, worded: true) }
            }
        }
    }

    private func gauge(_ meter: NotchAgentRestingMeter) -> some View {
        NotchAgentRestingGauge(meter: meter, used: choices.used)
    }

    private func amount(_ meter: NotchAgentRestingMeter, width: CGFloat, worded: Bool,
                        gauge: HorizontalEdge = .leading) -> some View {
        let text = FeatureStrings.notchAgents(l10n.language)
        return NotchAgentRestingAmount(window: meter.amount, used: choices.used,
                                       word: worded ? (choices.used ? text.restingWordUsed : text.restingWordLeft) : nil,
                                       gauge: gauge, size: 12, width: width)
    }

    /// No account reports a limit: the first agent's mark and today's API
    /// value, as before the meters.
    @ViewBuilder private func fallback(_ snapshot: AgentUsageSnapshot) -> some View {
        if let provider = choices.fallbackProvider(snapshot) {
            let mark = NotchAgentMark(provider: provider, size: 10)
            let cost = Text(AgentFormat.cost(snapshot.usage(.today).total.cost))
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            switch placement {
            case .leading: mark
            case .trailing: cost
            case .row: HStack(spacing: 5) { mark; cost }
            }
        }
    }
}

/// The resting island read as one element: which layout, every meter it
/// stands for whatever Rotate shows now, and a word for a window running
/// low, so color is never the only sign. Anything else at rest stays hidden.
struct NotchAgentRestingAccessibility: ViewModifier {
    let service: NotchService
    let active: Bool
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var l10n = L10n.shared
    private var choices = NotchAgentRestingChoices()

    init(service: NotchService, active: Bool) {
        self.service = service
        self.active = active
    }

    func body(content: Content) -> some View {
        let meters = active ? choices.meters(usage.snapshot, now: Date()) : []
        // Empty wings, with nothing seen at all, say nothing either.
        if active, !meters.isEmpty || choices.fallbackProvider(usage.snapshot) != nil {
            let text = FeatureStrings.notchAgents(l10n.language)
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(meters.isEmpty ? text.restingTitle : text.restingLabel(choices.layout))
                .accessibilityValue(meters.isEmpty ? AgentFormat.cost(usage.snapshot.usage(.today).total.cost)
                                    : NotchAgentSupport.restingSpeech(meters, used: choices.used, text: text,
                                                                      locale: l10n.language.formattingLocale()))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { service.openActivity(.agents) }
                .accessibilityHint(FeatureStrings.notch(l10n.language).open)
        } else {
            content.accessibilityHidden(true)
        }
    }
}
