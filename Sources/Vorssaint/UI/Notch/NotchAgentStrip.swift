// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The closed island while an agent works: its mark on one side of the
/// camera, one reading the person chose on the other. The wings are as wide
/// as the reading, and both sit at the ends, where the island shows.
struct NotchAgentStrip: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchAgentsReadout) private var readout = NotchAgentReadout.elapsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue

    private var geometry: NotchGeometry { service.compactActivityGeometry }
    /// Height the strip can give away once both edges keep their gap.
    private var budget: CGFloat { geometry.compactActivityContentHeight - NotchLayout.compactEdgeGap * 2 }
    private var iconSize: CGFloat { min(working.count > 1 ? 11 : 14, max(8, budget - 4)) }
    private var textSize: CGFloat { NotchAgentSupport.stripTextSize(height: geometry.compactActivityContentHeight) }
    private var iconInset: CGFloat {
        guard !geometry.compactActivityUsesFooter else { return 0 }
        return geometry.compactActivityEdgeInset(boxHeight: iconSize + 4, radius: (iconSize + 4) / 2)
    }
    private var textInset: CGFloat {
        guard !geometry.compactActivityUsesFooter else { return 0 }
        // Digits carry no descenders, so their ink is about the cap height.
        return geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0)
    }

    private var live: [AgentLiveSession] { usage.snapshot.live }
    private var working: [AgentProvider] {
        AgentProvider.allCases.filter { provider in live.contains { $0.provider == provider } }
    }
    private var tint: Color { working.first?.tint ?? .white }

    var body: some View {
        HStack(spacing: 0) {
            Button { service.open(.agents) } label: {
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
            Button { service.open(.agents) } label: {
                Group {
                    if geometry.compactActivityWingWidth >= 42 {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let text = reading(at: context.date)
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
        .accessibilityAction { service.open(.agents) }
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }

    private func reading(at now: Date) -> String {
        NotchAgentSupport.stripReading(usage.snapshot, readout: NotchAgentReadout(rawValue: readout) ?? .elapsed,
                                       display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining, now: now)
    }
}

/// The resting island's wings: the allowance closest to running out, as a
/// ring and a number, or today's API value when no allowance is known.
struct NotchAgentRestingWing: View {
    let leading: Bool
    @ObservedObject private var usage = AgentUsageService.shared
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder private func content(now: Date) -> some View {
        let snapshot = usage.snapshot
        let candidates = snapshot.limits.compactMap { provider, limits in
            AgentLimitSupport.binding(limits, now: now).map { (provider: provider, window: $0) }
        }
        let focus = candidates.max {
            $0.window.usedPercent != $1.window.usedPercent ? $0.window.usedPercent < $1.window.usedPercent
                : $0.provider.rawValue > $1.provider.rawValue
        }
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
