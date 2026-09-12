// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

enum BrightnessOSD {
    private static let overlay = TransientOSD<BrightnessOSDView>()

    static func show(displayID: CGDirectDisplayID, brightness: Double) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { show(displayID: displayID, brightness: brightness) }
            return
        }
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == displayID
        }) else { return }
        overlay.show(BrightnessOSDView(brightness: brightness), on: screen)
    }

    static func teardown() { overlay.teardown() }
    static func dismiss() { overlay.dismiss() }
}

/// Kept separate from the transient panel so the mandatory UI preview can
/// host and inspect the exact shipped surface.
struct BrightnessOSDView: View {
    let brightness: Double

    private var percentage: Int {
        BrightnessSupport.wholePercent(brightness)
    }

    private var filledSegments: Int {
        BrightnessSupport.filledBrightnessSegments(brightness)
    }

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 39, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white.opacity(0.82))
                .frame(height: 44)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(percentage)")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.52))
            }
            .frame(height: 36)

            HStack(spacing: 2) {
                ForEach(0..<16, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(index < filledSegments
                              ? Color.white.opacity(0.70)
                              : Color.white.opacity(0.12))
                }
            }
            .frame(width: 152, height: 7)
        }
        .frame(width: 196, height: 154)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(percentage)%")
        .accessibilityValue("\(percentage)%")
    }
}
