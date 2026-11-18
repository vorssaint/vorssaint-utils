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
    @ObservedObject private var inputs = AgentInputMonitor.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchAgentsReadout) private var readout = NotchAgentReadout.elapsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitFocus) private var focus = NotchAgentLimitFocus.mostUsed.rawValue

    private func working(_ live: [AgentLiveSession]) -> [AgentProvider] {
        AgentProvider.allCases.filter { provider in live.contains { $0.provider == provider } }
    }

    var body: some View {
        // The last agent stopping empties the list before the strip has left.
        // A session waiting on its person keeps the strip, even after its
        // turn went quiet long enough to stop counting as working.
        let waiting = NotchAgentSupport.waitingRequests(inputs.requests)
        NotchStripHold(usage.snapshot.live, shows: !usage.snapshot.live.isEmpty || !waiting.isEmpty) {
            strip(live: $0, waiting: waiting)
        }
    }

    @ViewBuilder private func strip(live: [AgentLiveSession], waiting: [AgentInputRequest]) -> some View {
        // Resolve layout once per presentation update. The timeline captures
        // these values, so ticking the clock never remeasures the island or
        // walks the preferences for every font, inset and frame.
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let working = working(live)
        let tint = waiting.isEmpty ? (working.first?.tint ?? .white) : AgentProvider.claude.tint
        let budget = geometry.compactActivityContentHeight - NotchLayout.compactEdgeGap * 2
        let iconSize = min(working.count > 1 ? 11.0 : 14.0, max(8, budget - 4))
        let textSize = NotchAgentSupport.agentStripTextSize(height: geometry.compactActivityContentHeight)
        let iconInset = !geometry.compactActivityUsesFooter
            ? geometry.compactActivityEdgeInset(boxHeight: iconSize + 4, radius: (iconSize + 4) / 2) : 0
        let textInset = !geometry.compactActivityUsesFooter
            ? geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0) : 0
        HStack(spacing: 0) {
            Button { service.openActivity(.agents) } label: {
                HStack(spacing: 1) {
                    if geometry.compactActivityWingWidth >= 28 {
                        // Waiting on the person takes the marks' place, so
                        // "needs you" reads at a glance from either side.
                        if waiting.isEmpty {
                            ForEach(working) { NotchAgentGlyph(provider: $0, size: iconSize) }
                        } else {
                            NotchAgentInputGlyph(tint: tint, size: iconSize)
                        }
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
                            let text = reading(at: date, live: live, waiting: waiting)
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
                                    DispatchQueue.main.async { service.fitAgentStrip() }
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
        .accessibilityLabel(waiting.isEmpty ? working.map(\.displayName).joined(separator: ", ")
                            : AgentProvider.claude.displayName)
        .accessibilityValue(reading(at: Date(), live: live, waiting: waiting))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { service.openActivity(.agents) }
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }

    private func reading(at now: Date, live: [AgentLiveSession], waiting: [AgentInputRequest]) -> String {
        var snapshot = usage.snapshot
        snapshot.live = live
        return NotchAgentSupport.liveReading(snapshot, waiting: waiting,
                                             readout: NotchAgentReadout(rawValue: readout) ?? .elapsed,
                                             display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining,
                                             focus: NotchAgentLimitFocus(rawValue: focus) ?? .mostUsed, now: now)
    }
}

/// A question mark in the agent's color that blinks gently while a session
/// waits on its person; steady when the person asked for reduced motion.
struct NotchAgentInputGlyph: View {
    let tint: Color
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Image(systemName: "questionmark")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: size * 1.45 + 1, height: size + 4)
            .opacity(dimmed ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { dimmed = true }
            }
            .accessibilityHidden(true)
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

/// The resting island's wings: the chosen allowance, by default the one
/// closest to running out, as a ring and a number, or today's API value when
/// no allowance is known.
struct NotchAgentRestingWing: View {
    let leading: Bool
    @ObservedObject private var usage = AgentUsageService.shared
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitFocus) private var focus = NotchAgentLimitFocus.mostUsed.rawValue

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder private func content(now: Date) -> some View {
        let snapshot = usage.snapshot
        let limit = NotchAgentSupport.restingLimit(snapshot, focus: NotchAgentLimitFocus(rawValue: focus) ?? .mostUsed, now: now)
        let used = display == NotchAgentLimitDisplay.used.rawValue
        if let limit {
            let tint = agentLimitTint(limit.provider, usedFraction: limit.window.usedFraction)
            if leading {
                NotchAgentRing(value: used ? limit.window.usedFraction : limit.window.remainingFraction,
                               tint: tint, lineWidth: 2)
                    .frame(width: 11, height: 11)
            } else {
                Text(AgentFormat.percent(used ? limit.window.usedFraction : limit.window.remainingFraction))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        } else if let provider = AgentProvider.allCases.first(where: snapshot.seen.contains) {
            if leading {
                NotchAgentMark(provider: provider, size: 10)
            } else {
                Text(AgentFormat.cost(snapshot.usage(.today).total.cost))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}
