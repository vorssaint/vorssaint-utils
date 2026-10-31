// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// WeChat-style tool strip beside an adjustable capture selection. Tools drive
/// the shared `ScreenshotEditorModel`; Complete finishes Through After capture.
struct ScreenshotConfirmToolbar: View {
    @ObservedObject var model: ScreenshotEditorModel
    let strings: ScreenshotFeatureStrings
    let onComplete: () -> Void
    let onCancel: () -> Void
    let onPin: () -> Void
    let onOCR: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void

    private var tools: [ScreenshotSupport.Tool] {
        ScreenshotSupport.Tool.confirmAnnotateTools
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                ForEach(tools, id: \.self) { tool in
                    toolButton(tool)
                }

                chromeDivider

                actionIcon("arrow.uturn.backward", enabled: model.canUndo, help: "Undo") {
                    onUndo()
                }
                actionIcon("arrow.uturn.forward", enabled: model.canRedo, help: "Redo") {
                    onRedo()
                }

                chromeDivider

                actionIcon("text.viewfinder", enabled: true, help: strings.copyTextButton) {
                    onOCR()
                }
                actionIcon("pin", enabled: true, help: strings.pinButton) {
                    onPin()
                }

                chromeDivider

                actionIcon("xmark", enabled: true, help: strings.cancel) {
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

            if showsStyleStrip {
                styleStrip
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
    }

    private var showsStyleStrip: Bool {
        switch model.tool {
        case .select, .crop, .expandCanvas, .image:
            return false
        case .pixelate:
            return true
        default:
            return true
        }
    }

    private var styleStrip: some View {
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

            chromeDivider

            if model.tool == .text {
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
            } else {
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
        .padding(.leading, 2)
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

/// Inline text field hosted over a confirm-selection annotation.
struct ScreenshotConfirmTextEditor: View {
    let placeholder: String
    let color: Color
    let fontSize: CGFloat
    @Binding var text: String
    let onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(color)
            .focused($focused)
            .frame(minWidth: 120)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1)
            )
            .onAppear {
                DispatchQueue.main.async { focused = true }
            }
            .onSubmit(onSubmit)
            .onExitCommand(perform: onSubmit)
    }
}
