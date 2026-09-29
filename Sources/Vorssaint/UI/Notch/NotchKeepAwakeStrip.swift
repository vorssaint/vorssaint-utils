// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The closed island while Keep Awake runs: the cup of its tile left of the
/// camera, in the tile's yellow, and on the right the time a timed session
/// has left, or infinity for one without an end. Both open Controls, where
/// the tile is. The wings are as wide as the wider side needs.
struct NotchKeepAwakeStrip: View {
    @ObservedObject var service: NotchService
    /// Another display's strip, when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        if let end = awake.endDate {
            // The reading changes once a minute, so the clock wakes only then.
            TimelineView(.periodic(from: NotchKeepAwakeSupport.tickStart(until: end, now: Date()), by: 60)) { context in
                strip(end: end, now: context.date)
            }
        } else {
            strip(end: nil, now: Date())
        }
    }

    private func strip(end: Date?, now: Date) -> some View {
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let height = geometry.compactActivityContentHeight
        let wing = geometry.compactActivityWingWidth
        let iconSize = NotchTimerSupport.stripIconSize(height: height)
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        return Button { service.openActivity(NotchCompactActivity.keepAwake.module) } label: {
            HStack(spacing: 0) {
                Group {
                    if wing >= 28 {
                        Image(systemName: NotchKeepAwakeSupport.symbol)
                            .font(.system(size: iconSize, weight: .medium))
                    }
                }
                .padding(.leading, geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2))
                .frame(width: wing, height: height, alignment: .leading)
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                Group {
                    if wing >= 42 {
                        if let end {
                            reading(NotchKeepAwakeSupport.compactText(
                                until: end, now: now, locale: Locale(identifier: l10n.language.rawValue)), size: textSize)
                        } else {
                            Image(systemName: NotchKeepAwakeSupport.openSymbol)
                                .font(.system(size: textSize, weight: .medium))
                        }
                    }
                }
                // Digits carry no descenders, so their ink is about the cap height.
                .padding(.trailing, geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0))
                .frame(width: wing, height: height, alignment: .trailing)
            }
            .foregroundStyle(.yellow)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.s.keepAwakeTitle)
        .accessibilityValue(Self.status(end: end, language: l10n.language))
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
        .accessibilityIdentifier("notch.keepAwake")
    }

    private func reading(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: .medium)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.65)
            // A reading that gains or loses a character, like 10m becoming
            // 9m, resizes the wings; the service measures the same reading.
            .onChange(of: NotchAgentSupport.readingShape(text)) { _, _ in
                DispatchQueue.main.async { service.refreshPresentation() }
            }
    }

    /// What the menu bar panel says about the session, read aloud.
    static func status(end: Date?, language: AppLanguage) -> String {
        let strings = Strings.localized(language)
        if let end { return "\(strings.keepAwakeEndsIn) \(KeepAwakeCard.remainingText(until: end))" }
        let awake = KeepAwakeManager.shared
        if awake.sessionTrigger == .automation {
            return FeatureStrings.keepAwakeAutomation(language).activeStatus(for: awake.activeAutomationConditions)
        }
        return strings.keepAwakeUntilDisabled
    }
}
