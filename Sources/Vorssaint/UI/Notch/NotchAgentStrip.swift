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
    @ObservedObject private var t3 = T3CodeActivityService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var tracksCompletionFlash = false
    @AppStorage(DefaultsKey.notchAgentsReadout) private var readout = NotchAgentReadout.elapsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitFocus) private var focus = NotchAgentLimitFocus.mostUsed.rawValue

    private struct Activity: Equatable {
        let live: [AgentLiveSession]
        let summary: T3CompactActivitySummary?

        var shows: Bool { !live.isEmpty || summary != nil }
    }

    private func working(_ live: [AgentLiveSession]) -> [AgentProvider] {
        AgentProvider.allCases.filter { provider in live.contains { $0.provider == provider } }
    }

    var body: some View {
        Group {
            if tracksCompletionFlash {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    activityStrip(now: context.date)
                }
            } else {
                activityStrip(now: .now)
            }
        }
        .onAppear { updateCompletionTracking() }
        .onChange(of: t3.activities) { _, _ in
            updateCompletionTracking()
            DispatchQueue.main.async { service.refreshPresentation() }
        }
    }

    private func activityStrip(now: Date) -> some View {
        let activity = Activity(live: usage.snapshot.live,
                                summary: T3ActivityPresentation.compactSummary(t3.activities, now: now))
        // A completed T3 thread keeps the strip visible just long enough for its green check to register.
        return NotchStripHold(activity, shows: activity.shows) { strip($0) }
            .onChange(of: activity.summary) { _, _ in
                DispatchQueue.main.async {
                    if activity.summary?.state != .completed { tracksCompletionFlash = false }
                    service.refreshPresentation()
                }
            }
    }

    private func updateCompletionTracking() {
        tracksCompletionFlash = T3ActivityPresentation.compactSummary(t3.activities)?.state == .completed
    }

    @ViewBuilder private func strip(_ activity: Activity) -> some View {
        // Resolve layout once per presentation update. The timeline captures
        // these values, so ticking the clock never remeasures the island or
        // walks the preferences for every font, inset and frame.
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let live = activity.live
        let summary = activity.summary
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
                    if geometry.compactActivityWingWidth >= 28, let summary {
                        Image(systemName: summary.state == .waitingForApproval ? "exclamationmark.triangle.fill"
                              : summary.state == .waitingForInput ? "questionmark.circle.fill"
                              : summary.state == .completed ? "checkmark.circle.fill"
                              : summary.state == .waiting ? "pause.circle.fill" : "circle.fill")
                            .font(.system(size: iconSize, weight: .semibold))
                            .foregroundStyle(summary.state == .waitingForApproval || summary.state == .waitingForInput
                                             ? Color.orange : summary.state == .completed ? Color.green
                                             : summary.state == .waiting ? Color.secondary : .white)
                    } else if geometry.compactActivityWingWidth >= 28 {
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
                        if let summary {
                            compactReadout(summary.compactReadout,
                                           textSize: textSize,
                                           tint: summary.state == .waitingForApproval || summary.state == .waitingForInput
                                               ? .orange : summary.state == .completed ? .green
                                               : summary.state == .waiting ? .secondary : tint)
                        } else {
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
        .accessibilityLabel(summary == nil ? working.map(\.displayName).joined(separator: ", ")
                             : T3CodeStrings(l10n.language).source)
        .accessibilityValue(summary.map { $0.accessibilityReadout(language: l10n.language) }
                            ?? reading(at: Date(), live: live))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { service.openActivity(.agents) }
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }

    private func compactReadout(_ value: String, textSize: CGFloat, tint: Color) -> some View {
        Text(value)
            .font(.system(size: textSize, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
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
