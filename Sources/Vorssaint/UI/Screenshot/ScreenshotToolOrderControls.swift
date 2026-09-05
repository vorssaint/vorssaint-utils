// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Reusable controls for screenshot tool order and number assignments.
struct ScreenshotToolOrderControls: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var orderRaw: String
    /// Kept as two independent bindings, matching the two independent
    /// defaults keys behind them (`screenshotToolShortcutsEnabled` and
    /// `screenshotToolShortcutStyle`) — see `DisplayMode` below for the
    /// combined 3-way UI built on top of them.
    @Binding var enabled: Bool
    @Binding var style: ScreenshotSupport.ShortcutStyle
    var showsTitle = true
    /// The full-width segmented control reads fine in the Settings pane,
    /// but overflows the narrow in-editor popover once translated mode
    /// names run long (German, Turkish); that popover opts into the
    /// compact menu instead.
    var usesCompactModePicker = false

    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(l10n.language)
    }

    private var movementStrings: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    private var orderedTools: [ScreenshotSupport.Tool] {
        ScreenshotSupport.Tool.ordered(from: orderRaw)
    }

    /// The 3 choices shown to the user. Purely a display-layer convenience:
    /// "off" is `enabled == false`, and "number"/"letter" are `style` —
    /// the two stored values never need a case of their own that mirrors
    /// this type.
    private enum DisplayMode: Hashable {
        case off, number, letter
    }

    private var displayMode: Binding<DisplayMode> {
        Binding(
            get: {
                guard enabled else { return .off }
                return style == .letter ? .letter : .number
            },
            set: { newValue in
                switch newValue {
                case .off:
                    enabled = false
                case .number:
                    enabled = true
                    style = .number
                case .letter:
                    enabled = true
                    style = .letter
                }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTitle {
                Text(strings.toolShortcutsTitle)
                    .font(.headline)
            }

            if usesCompactModePicker {
                modeMenu
            } else {
                Picker("", selection: displayMode) {
                    Text(strings.toolShortcutsModeOff).tag(DisplayMode.off)
                    Text(strings.toolShortcutsModeNumber).tag(DisplayMode.number)
                    Text(strings.toolShortcutsModeLetter).tag(DisplayMode.letter)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
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

        return HStack(spacing: 7) {
            Image(systemName: tool.screenshotSymbolName)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(tool.screenshotTitle(strings))
                .lineLimit(1)
            Spacer(minLength: 4)

            shortcutControl(for: tool)

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

    /// A menu rather than a segmented control, since the translated mode
    /// names run far longer than English in several locales (German,
    /// Turkish) and would overflow a fixed-width segmented control.
    private var modeMenu: some View {
        Menu {
            ForEach([DisplayMode.off, .number, .letter], id: \.self) { option in
                Button {
                    displayMode.wrappedValue = option
                } label: {
                    if displayMode.wrappedValue == option {
                        Label(modeLabel(for: option), systemImage: "checkmark")
                    } else {
                        Text(modeLabel(for: option))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(modeLabel(for: displayMode.wrappedValue))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(.quaternary,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func modeLabel(for mode: DisplayMode) -> String {
        switch mode {
        case .off: return strings.toolShortcutsModeOff
        case .number: return strings.toolShortcutsModeNumber
        case .letter: return strings.toolShortcutsModeLetter
        }
    }

    /// Dimmed rather than removed while off, matching how this control has
    /// always behaved: assigning a number doesn't require shortcuts to be
    /// on, so a user can lay out the rail before switching them on.
    @ViewBuilder
    private func shortcutControl(for tool: ScreenshotSupport.Tool) -> some View {
        Group {
            switch style {
            case .number:
                shortcutMenu(for: tool,
                            assignedNumber: ScreenshotSupport.Tool.shortcutNumber(
                                for: tool, orderRaw: orderRaw))
            case .letter:
                // Fixed per-tool mnemonic, not reassignable in this version.
                badge(String(tool.shortcutLetter).uppercased())
            }
        }
        .opacity(enabled ? 1 : 0.48)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .frame(width: 62, height: 22)
            .background(.quaternary,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
