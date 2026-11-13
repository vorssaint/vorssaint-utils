// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

// The editor's readouts for measuring and colors. Each observes only the
// inspector, so the pointer moving redraws these small views and leaves
// the canvas alone.

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

/// Points or pixels, for the ruler and the selection size alike (P).
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

/// The color under the pointer, in the color picker's copy format, with
/// the keys that copy it.
struct ScreenshotPointerColorChip: View {
    @ObservedObject var inspector: ScreenshotEditorInspector
    let hint: String

    var body: some View {
        if let color = inspector.pointerColor, color.alpha > 0 {
            let swatch = ScreenshotEditorInspector.nsColor(color)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: swatch))
                    .frame(width: 14, height: 14)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                Text(ColorSamplerService.shared.formattedValue(swatch) ?? color.hex)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                Text("⇥")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .screenshotSafeHelp(hint)
            .accessibilityElement(children: .combine)
            .accessibilityHint(hint)
        }
    }
}

/// What the crop selection measures and holds: its size, its average color
/// (C copies it) and the contrast of its text on its background.
struct ScreenshotSelectionReadout: View {
    @ObservedObject var inspector: ScreenshotEditorInspector
    let scale: CGFloat
    let strings: ScreenshotInspectorStrings
    let copy: (ScreenshotInspectionSupport.RGBA) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let reading = inspector.selection {
                Text(ScreenshotInspectionSupport.sizeLabel(reading.size, scale: scale, unit: inspector.unit))
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                if let average = reading.average {
                    Divider().frame(height: 16)
                    Button {
                        copy(average)
                    } label: {
                        HStack(spacing: 5) {
                            swatch(average)
                            Text(average.hex)
                                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                            Text("C")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .screenshotSafeHelp(strings.averageColorLabel + "  (C)")
                    .accessibilityLabel(strings.averageColorLabel)
                    .accessibilityValue(average.hex)
                }
                if let pair = reading.pair {
                    Divider().frame(height: 16)
                    contrast(pair)
                }
            }
        }
    }

    private func contrast(_ pair: ScreenshotInspectionSupport.ColorPair) -> some View {
        let ratio = ScreenshotInspectionSupport.contrastRatio(pair.foreground, pair.background)
        let level = ScreenshotInspectionSupport.ContrastLevel(ratio: ratio)
        let lightness = ScreenshotInspectionSupport.apcaContrast(text: pair.foreground,
                                                                background: pair.background)
        let ratioText = String(format: "%.2f:1", locale: ScreenshotInspectionSupport.technicalLocale, ratio)
        let lightnessText = "Lc " + String(Int(lightness.rounded()))
        return HStack(spacing: 5) {
            ZStack(alignment: .bottomTrailing) {
                swatch(pair.background)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(nsColor: ScreenshotEditorInspector.nsColor(pair.foreground)))
                    .frame(width: 7, height: 7)
                    .offset(x: -2, y: -2)
            }
            Text(ratioText)
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
            Text(level.label)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(level == .fail ? Color.red.opacity(0.28) : Color.green.opacity(0.24),
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(lightnessText)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .fixedSize()
        .screenshotSafeHelp(strings.contrastHelp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(strings.contrastLabel)
        .accessibilityValue("\(ratioText), \(level.label), \(lightnessText)")
    }

    private func swatch(_ color: ScreenshotInspectionSupport.RGBA) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color(nsColor: ScreenshotEditorInspector.nsColor(color)))
            .frame(width: 16, height: 16)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
    }
}
