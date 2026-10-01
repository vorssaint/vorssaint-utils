// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The closed island while an agent works: its mark on one side of the
/// camera, one reading the person chose on the other. The wings are as wide
/// as the reading, and both sit at the ends, where the island shows.
struct NotchAgentStrip: View {
    @ObservedObject var service: NotchService
    /// Another display's strip, when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var waitWatcher = AgentWaitWatcher.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchAgentsReadout) private var readout = NotchAgentReadout.elapsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue

    private var live: [AgentLiveSession] { usage.snapshot.live }
    private var working: [AgentProvider] {
        AgentProvider.allCases.filter { provider in live.contains { $0.provider == provider } }
    }

    var body: some View {
        // Resolve layout once per presentation update. The timeline captures
        // these values, so ticking the clock never remeasures the island or
        // walks the preferences for every font, inset and frame.
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let working = working
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
                        ForEach(working) { provider in
                            NotchAgentGlyph(provider: provider, size: iconSize,
                                            waiting: provider == .claude && !waitWatcher.waiting.isEmpty)
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
                            let text = reading(at: date)
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
        .accessibilityValue(reading(at: Date()))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { service.openActivity(.agents) }
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }

    private func reading(at now: Date) -> String {
        NotchAgentSupport.stripReading(usage.snapshot, readout: NotchAgentReadout(rawValue: readout) ?? .elapsed,
                                       display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining, now: now)
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

/// The resting island's wings: the allowance closest to running out, as a
/// ring and a number, or today's API value when no allowance is known.
struct NotchAgentRestingWing: View {
    let leading: Bool
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var waitWatcher = AgentWaitWatcher.shared
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let focus = focus(now: context.date)
            // Claude's own signal, not whichever provider this side
            // happens to show — Codex's ring sitting closest to its limit
            // must not read as Claude waiting. Yellow: not a color the
            // limit ring or either agent's own tint already carries.
            let waiting = leading && (focus?.provider ?? fallbackProvider) == .claude && !waitWatcher.waiting.isEmpty
            content(focus: focus, now: context.date)
                .overlay(alignment: .topTrailing) {
                    // No outward offset: the icon this sits on is only
                    // 10-11pt itself, and the pill around it clips tightly
                    // to its measured content, so a badge pushed past the
                    // corner was being cut off instead of shown.
                    if waiting {
                        Circle().fill(.yellow).frame(width: 6, height: 6)
                    }
                }
        }
    }

    private func focus(now: Date) -> (provider: AgentProvider, window: AgentLimitWindow)? {
        let candidates = usage.snapshot.limits.compactMap { provider, limits in
            AgentLimitSupport.binding(limits, now: now).map { (provider: provider, window: $0) }
        }
        return candidates.max {
            $0.window.usedPercent != $1.window.usedPercent ? $0.window.usedPercent < $1.window.usedPercent
                : $0.provider.rawValue > $1.provider.rawValue
        }
    }

    private var fallbackProvider: AgentProvider? {
        AgentProvider.allCases.first(where: usage.snapshot.seen.contains)
    }

    @ViewBuilder private func content(focus: (provider: AgentProvider, window: AgentLimitWindow)?, now: Date) -> some View {
        let snapshot = usage.snapshot
        let used = display == NotchAgentLimitDisplay.used.rawValue
        if let focus {
            let tint = agentLimitTint(focus.provider, usedFraction: focus.window.usedFraction)
            if leading {
                NotchAgentRing(value: used ? focus.window.usedFraction : focus.window.remainingFraction,
                               tint: tint, lineWidth: 2)
                    .frame(width: 11, height: 11)
            } else {
                Text(AgentFormat.percent(used ? focus.window.usedFraction : focus.window.remainingFraction))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        } else if let provider = fallbackProvider {
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
