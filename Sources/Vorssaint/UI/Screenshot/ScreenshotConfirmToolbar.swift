// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// WeChat-style tool strip beside an adjustable capture selection. Tools drive
/// the shared `ScreenshotEditorModel`; Complete finishes Through After capture.
struct ScreenshotConfirmToolbar: View {
    @ObservedObject var model: ScreenshotEditorModel
    let strings: ScreenshotFeatureStrings
    /// Host clamps the bar to the display; the strip reflows instead of clipping.
    var availableWidth: CGFloat = 480
    let onComplete: () -> Void
    let onCancel: () -> Void
    let onRetake: () -> Void
    let onPin: () -> Void
    let onOCR: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void

    private var tools: [ScreenshotSupport.Tool] {
        ScreenshotSupport.Tool.confirmAnnotateTools
    }

    var body: some View {
        let budget = max(200, availableWidth - 16)
        return VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                toolsRow(compact: false)
                toolsRow(compact: true)
            }

            if showsStyleStrip {
                styleStrip
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: budget, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
    }

    @ViewBuilder
    private func toolsRow(compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(tools, id: \.self) { tool in
                        toolButton(tool)
                    }
                }
                HStack(spacing: 2) {
                    actionCluster
                    Spacer(minLength: 0)
                    confirmCluster
                }
            }
        } else {
            HStack(spacing: 2) {
                ForEach(tools, id: \.self) { tool in
                    toolButton(tool)
                }
                chromeDivider
                actionCluster
                chromeDivider
                confirmCluster
            }
        }
    }

    @ViewBuilder
    private var actionCluster: some View {
        actionIcon("arrow.uturn.backward", enabled: model.canUndo, help: "Undo (⌘Z)") {
            onUndo()
        }
        actionIcon("arrow.uturn.forward", enabled: model.canRedo, help: "Redo (⇧⌘Z)") {
            onRedo()
        }
        chromeDivider
        actionIcon("text.viewfinder",
                   enabled: true,
                   help: "Recognize text — click or drag words to copy") {
            onOCR()
        }
        actionIcon("pin", enabled: true, help: strings.pinButton) {
            onPin()
        }
        actionIcon("camera.viewfinder",
                   enabled: true,
                   help: "Retake — discard marks and pick a new area") {
            onRetake()
        }
    }

    @ViewBuilder
    private var confirmCluster: some View {
        actionIcon("xmark", enabled: true, help: strings.cancel + " (Esc)") {
            onCancel()
        }
        Button(action: onComplete) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color(red: 0.15, green: 0.78, blue: 0.35)))
        }
        .buttonStyle(.plain)
        .help(strings.copyButton + " / " + strings.saveButton)
        .accessibilityLabel(strings.copyButton)
    }

    private var showsStyleStrip: Bool {
        if model.editingTextID != nil { return true }
        switch model.tool {
        case .select, .crop, .expandCanvas, .image:
            return false
        default:
            return true
        }
    }

    private var isEditingOrUsingText: Bool {
        model.tool == .text || model.editingTextID != nil
    }

    @ViewBuilder
    private var styleStrip: some View {
        // Horizontal scroll so the last chips (esp. 编号) stay reachable when
        // the tools row is narrower than color+stroke+styles.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if isEditingOrUsingText {
                    colorStrip
                    chromeDivider
                    textSizeStrip
                } else {
                    switch model.tool {
                    case .pixelate:
                        // Mosaic only needs strength — no color chips (CleanShot / WeChat).
                        blurLevelStrip
                    case .arrow:
                        colorStrip
                        chromeDivider
                        strokeStrip
                        chromeDivider
                        arrowStyleStrip
                    default:
                        colorStrip
                        chromeDivider
                        strokeStrip
                    }
                }
            }
            .padding(.leading, 2)
        }
    }

    private var colorStrip: some View {
        HStack(spacing: 6) {
            ForEach(ScreenshotSupport.ColorID.allCases, id: \.self) { color in
                let selected = model.color == color
                Button {
                    model.color = color
                } label: {
                    Circle()
                        .fill(Color(red: color.components.red,
                                    green: color.components.green,
                                    blue: color.components.blue))
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(selected ? 1 : 0.35),
                                              lineWidth: selected ? 2 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var strokeStrip: some View {
        HStack(spacing: 6) {
            ForEach(ScreenshotSupport.StrokeID.allCases, id: \.self) { stroke in
                let selected = model.stroke == stroke
                Button {
                    model.stroke = stroke
                } label: {
                    Capsule()
                        .fill(Color.primary.opacity(selected ? 0.9 : 0.35))
                        .frame(width: 18, height: stroke.width)
                }
                .buttonStyle(.plain)
                .help(stroke.rawValue)
            }
        }
    }

    private var textSizeStrip: some View {
        HStack(spacing: 4) {
            ForEach(ScreenshotSupport.textSizes.filter { [14, 19, 24, 36].contains($0) },
                    id: \.self) { size in
                let selected = model.textSize == size
                Button {
                    model.textSize = size
                } label: {
                    Text("A")
                        .font(.system(size: max(9, CGFloat(size) * 0.45), weight: .bold))
                        .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.7))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(strings.fontSizeLabel)
            }
        }
    }

    private var arrowStyleStrip: some View {
        // Short glyphs keep every style (especially Numbered) on-screen after
        // the toolbar lost width when the crop lock moved to the selection.
        HStack(spacing: 2) {
            ForEach(ScreenshotSupport.ArrowStyleID.allCases, id: \.self) { style in
                arrowStyleChip(style)
            }
        }
    }

    private func arrowStyleChip(_ style: ScreenshotSupport.ArrowStyleID) -> some View {
        let selected = model.arrowStyle == style
        return Button {
            model.arrowStyle = style
        } label: {
            Text(Self.arrowStyleGlyph(style))
                .font(.system(size: style == .numbered ? 11 : 10,
                              weight: selected ? .bold : .medium,
                              design: .rounded))
                .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.8))
                .frame(minWidth: 22, minHeight: 22)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.18) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(strings.arrowStyleTitle(style))
        .accessibilityLabel(strings.arrowStyleTitle(style))
    }

    private static func arrowStyleGlyph(_ style: ScreenshotSupport.ArrowStyleID) -> String {
        switch style {
        case .filled: return "▶"
        case .outline: return "▷"
        case .open: return "➔"
        case .doubleEnded: return "↔"
        case .scribbly: return "≈"
        case .numbered: return "1"
        }
    }

    private var blurLevelStrip: some View {
        let levels = Array(ScreenshotSupport.BlurStrength.levels)
        return HStack(spacing: 4) {
            Image(systemName: "aqi.low")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            ForEach(levels, id: \.self) { level in
                let selected = model.blurLevel == level
                Button {
                    model.blurLevel = level
                } label: {
                    Capsule()
                        .fill(Color.primary.opacity(selected ? 0.9 : 0.3))
                        .frame(width: 10 + CGFloat(level) * 3, height: 6 + CGFloat(level))
                }
                .buttonStyle(.plain)
                .help(strings.blurStrengthLabel)
            }
            Image(systemName: "aqi.high")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var chromeDivider: some View {
        Divider()
            .frame(height: 16)
            .padding(.horizontal, 4)
    }

    private func toolButton(_ tool: ScreenshotSupport.Tool) -> some View {
        let selected = model.tool == tool
        return Button {
            model.tool = tool
        } label: {
            Image(systemName: tool.screenshotSymbolName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.85))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.22) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(tool.screenshotTitle(strings))
        .accessibilityLabel(tool.screenshotTitle(strings))
    }

    private func actionIcon(_ systemName: String,
                            enabled: Bool,
                            help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(enabled ? Color.primary.opacity(0.85) : Color.secondary.opacity(0.35))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }
}
