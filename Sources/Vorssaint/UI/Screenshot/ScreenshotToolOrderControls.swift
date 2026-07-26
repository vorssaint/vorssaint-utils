// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Reusable controls for screenshot tool order and number assignments.
struct ScreenshotToolOrderControls: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var orderRaw: String
    @Binding var shortcutsEnabled: Bool
    var showsTitle = true

    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(l10n.language)
    }

    private var movementStrings: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    private var orderedTools: [ScreenshotSupport.Tool] {
        ScreenshotSupport.Tool.ordered(from: orderRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTitle {
                Text(strings.toolShortcutsTitle)
                    .font(.headline)
            }

            Toggle(strings.toolShortcutsToggle, isOn: $shortcutsEnabled)
            Text(strings.toolShortcutsCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 2) {
                ForEach(orderedTools, id: \.self) { tool in
                    toolRow(tool)
                    if tool != orderedTools.last {
                        Divider().padding(.leading, 28)
                    }
                }
            }

            HStack {
                Spacer()
                Button(l10n.s.shortcutReset) {
                    orderRaw = ScreenshotSupport.Tool.defaultOrderStorage
                }
                .disabled(orderRaw == ScreenshotSupport.Tool.defaultOrderStorage)
            }
        }
    }

    private func toolRow(_ tool: ScreenshotSupport.Tool) -> some View {
        let index = orderedTools.firstIndex(of: tool) ?? 0
        let assignedNumber = ScreenshotSupport.Tool.shortcutNumber(
            for: tool,
            orderRaw: orderRaw,
            enabled: true)

        return HStack(spacing: 7) {
            Image(systemName: tool.screenshotSymbolName)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(tool.screenshotTitle(strings))
                .lineLimit(1)
            Spacer(minLength: 4)

            shortcutMenu(for: tool, assignedNumber: assignedNumber)
                .opacity(shortcutsEnabled ? 1 : 0.48)

            Button {
                move(tool, by: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 20, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .accessibilityLabel(movementStrings.moveUp)

            Button {
                move(tool, by: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 20, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(index == orderedTools.count - 1)
            .accessibilityLabel(movementStrings.moveDown)
        }
        .frame(minHeight: 26)
        .contentShape(Rectangle())
    }

    private func shortcutMenu(for tool: ScreenshotSupport.Tool,
                              assignedNumber: Int?) -> some View {
        Menu {
            Button {
                assign(nil, to: tool)
            } label: {
                if assignedNumber == nil {
                    Label(l10n.s.shortcutNone, systemImage: "checkmark")
                } else {
                    Text(l10n.s.shortcutNone)
                }
            }
            Divider()
            ForEach(1...ScreenshotSupport.Tool.shortcutLimit, id: \.self) { number in
                Button {
                    assign(number, to: tool)
                } label: {
                    if assignedNumber == number {
                        Label("\(number)", systemImage: "checkmark")
                    } else {
                        Text("\(number)")
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(assignedNumber.map(String.init) ?? l10n.s.shortcutNone)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .frame(width: 62, height: 22)
            .background(.quaternary,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func move(_ tool: ScreenshotSupport.Tool, by offset: Int) {
        var order = orderedTools
        guard let index = order.firstIndex(of: tool) else { return }
        let destination = index + offset
        guard order.indices.contains(destination) else { return }
        withAnimation(.easeInOut(duration: 0.14)) {
            order.swapAt(index, destination)
            persist(order)
        }
    }

    private func assign(_ number: Int?, to tool: ScreenshotSupport.Tool) {
        withAnimation(.easeInOut(duration: 0.14)) {
            persist(ScreenshotSupport.Tool.assigningShortcut(
                number,
                to: tool,
                orderRaw: orderRaw))
        }
    }

    private func persist(_ order: [ScreenshotSupport.Tool]) {
        orderRaw = order.map(\.rawValue).joined(separator: ",")
    }
}
