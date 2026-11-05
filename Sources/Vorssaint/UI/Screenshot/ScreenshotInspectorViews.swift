// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

// The editor's readouts for measuring. Each observes only the inspector, so
// the pointer moving redraws these small views and leaves the canvas alone.

/// The measurement or guide that follows the pointer, drawn exactly as a
/// click would leave it on the capture.
struct ScreenshotLiveMeasureOverlay: View {
    @ObservedObject var inspector: ScreenshotEditorInspector
    let color: ScreenshotSupport.ColorID
    let stroke: ScreenshotSupport.StrokeID
    let zoom: CGFloat
    let padding: CGFloat
    let scale: CGFloat

    var body: some View {
        Canvas { context, _ in
            guard let mode = inspector.liveMode, let span = inspector.liveSpan else { return }
            context.withCGContext { cg in
                cg.scaleBy(x: zoom, y: zoom)
                cg.translateBy(x: padding, y: padding)
                var mark = ScreenshotSupport.Annotation(tool: .ruler, points: [span.start, span.end],
                                                        text: inspector.unit.rawValue,
                                                        color: color, stroke: stroke)
                if case .guide = mode {
                    mark.tool = .guide
                    ScreenshotRenderer.drawGuide(mark, in: cg, scale: scale)
                } else {
                    ScreenshotRenderer.drawRuler(mark, in: cg, imageSize: inspector.imageSize,
                                                 scale: scale, shadowsEnabled: false)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A line of help above the canvas while measuring. Tooltips are off on
/// macOS 27, so the keys are spelled out where they are used.
struct ScreenshotMeasureHint: View {
    @ObservedObject var inspector: ScreenshotEditorInspector
    let rulerActive: Bool
    let strings: ScreenshotInspectorStrings

    var body: some View {
        if rulerActive || inspector.liveMode != nil {
            HStack(spacing: 8) {
                Image(systemName: "ruler")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(strings.measureHint)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                ScreenshotMeasureUnitControl(inspector: inspector, label: strings.measureUnitLabel)
                if inspector.liveMode != nil {
                    // Escape ends a measurement that follows the pointer.
                    Text("esc")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 0.5))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: 620)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

/// Points or pixels for the ruler (P).
struct ScreenshotMeasureUnitControl: View {
    @ObservedObject var inspector: ScreenshotEditorInspector
    let label: String

    var body: some View {
        Picker(label, selection: $inspector.unit) {
            Text("pt").tag(ScreenshotInspectionSupport.MeasureUnit.points)
            Text("px").tag(ScreenshotInspectionSupport.MeasureUnit.pixels)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .screenshotSafeHelp(label + "  (P)")
        .accessibilityLabel(label)
    }
}
