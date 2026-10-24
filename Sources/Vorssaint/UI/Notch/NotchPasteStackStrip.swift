// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The closed island while a paste stack runs: its mark left of the camera
/// and, on the right, how many cards are left to paste, in the clipboard's
/// blue. Both open the clipboard page, where the cards come from.
struct NotchPasteStackStrip: View {
    @ObservedObject var service: NotchService
    /// Where the island draws it: its own strip as of the last update, or
    /// another display's when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var history = ClipboardHistoryService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        // The last card pasted clears the stack before the strip has left.
        let count = history.pasteStackIDs.count
        NotchStripHold(count, shows: count > 0) { strip(count: $0) }
    }

    private func strip(count: Int) -> some View {
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let height = geometry.compactActivityContentHeight
        let wing = geometry.compactActivityWingWidth
        let iconSize = NotchTimerSupport.stripIconSize(height: height)
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        return Button { service.openActivity(NotchCompactActivity.pasteStack.module) } label: {
            HStack(spacing: 0) {
                Group {
                    if wing >= 28 {
                        Image(systemName: NotchPasteStackSupport.symbol)
                            .font(.system(size: iconSize, weight: .medium))
                            .symbolEffect(.bounce, value: count)
                    }
                }
                .padding(.leading, geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2))
                .frame(width: wing, height: height, alignment: .leading)
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                Group {
                    if wing >= 28 {
                        Text("\(count)")
                            .font(.system(size: textSize, weight: .semibold)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.65)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: count)
                            // 10 becoming 9 narrows the wings; the service measures the same.
                            .onChange(of: "\(count)".count) { _, _ in
                                DispatchQueue.main.async { service.refreshPresentation() }
                            }
                    }
                }
                // Digits carry no descenders, so their ink is about the cap height.
                .padding(.trailing, geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0))
                .frame(width: wing, height: height, alignment: .trailing)
            }
            .foregroundStyle(Color(nsColor: .systemBlue))
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FeatureStrings.clipboard(l10n.language).pasteStackTitle)
        .accessibilityValue(String(format: FeatureStrings.clipboard(l10n.language).pasteStackRemainingFormat, count))
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
        .accessibilityIdentifier("notch.pasteStack")
    }
}
