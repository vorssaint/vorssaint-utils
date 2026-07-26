// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct WindowGestureModifierPicker: View {
    @Binding var storageValue: String
    var title: String?
    var compact = false

    private struct ModifierChoice: Identifiable {
        let modifier: GlobalShortcutModifiers
        let symbol: String
        let name: String
        var id: String { name }
    }

    private let choices: [ModifierChoice] = [
        ModifierChoice(modifier: .control, symbol: "⌃", name: "Control"),
        ModifierChoice(modifier: .option, symbol: "⌥", name: "Option"),
        ModifierChoice(modifier: .command, symbol: "⌘", name: "Command"),
    ]

    var body: some View {
        HStack(spacing: compact ? 5 : 7) {
            if let title {
                Text(title)
                    .font(compact ? .system(size: 10, weight: .medium) : .body)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
            }
            ForEach(choices) { choice in
                let selected = modifiers.contains(choice.modifier)
                Button {
                    toggle(choice.modifier)
                } label: {
                    Text(choice.symbol)
                        .font(.system(size: compact ? 12 : 14, weight: .semibold, design: .rounded))
                        .frame(width: compact ? 25 : 30, height: compact ? 22 : 25)
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(selected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.1),
                                        lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(selected && !canRemove(choice.modifier))
                .help(choice.name)
                .accessibilityLabel(choice.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var modifiers: GlobalShortcutModifiers {
        WindowGestureSupport.modifiers(from: storageValue)
    }

    private func toggle(_ modifier: GlobalShortcutModifiers) {
        var next = modifiers
        if next.contains(modifier) {
            next.remove(modifier)
        } else {
            next.insert(modifier)
        }
        // At least one deliberate modifier stays selected. Shift is reserved
        // for the resize variant and is shown in the action hint below.
        guard next.hasPrimaryModifier else { return }
        storageValue = WindowGestureSupport.storageValue(for: next)
    }

    private func canRemove(_ modifier: GlobalShortcutModifiers) -> Bool {
        var remaining = modifiers
        remaining.remove(modifier)
        return remaining.hasPrimaryModifier
    }
}

struct WindowGestureHints: View {
    let modifierStorage: String
    let moveText: String
    let resizeText: String
    var compact = false

    @ViewBuilder
    var body: some View {
        if compact {
            VStack(spacing: 4) {
                hint(moveText, isMove: true)
                hint(resizeText, isMove: false)
            }
        } else {
            HStack(spacing: 9) {
                hint(moveText, isMove: true)
                hint(resizeText, isMove: false)
            }
        }
    }

    private var chord: String {
        WindowGestureSupport.modifiers(from: modifierStorage).keyCaps.joined()
    }

    private var resizeChord: String {
        WindowGestureSupport.resizeModifiers(
            from: WindowGestureSupport.modifiers(from: modifierStorage)
        ).keyCaps.joined()
    }

    private func hint(_ text: String, isMove: Bool) -> some View {
        HStack(spacing: compact ? 3 : 5) {
            Text(isMove ? chord : resizeChord)
                .font(.system(size: compact ? 9.5 : 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Image(systemName: isMove
                    ? "arrow.up.and.down.and.arrow.left.and.right"
                    : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: compact ? 15 : 17, height: compact ? 15 : 17)
                .accessibilityHidden(true)
            Text(text)
                .font(compact ? .system(size: 9.5, weight: .medium) : .caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 4 : 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .accessibilityElement(children: .combine)
    }
}
