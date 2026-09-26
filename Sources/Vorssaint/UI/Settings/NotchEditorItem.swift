// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchEditorItem: View {
    let symbol: String
    let title: String
    @Binding var included: Bool
    var selected = false
    var available = true
    var unavailableReason: String? = nil
    var unavailableAction: (() -> Void)? = nil
    /// Keeps a card as tall as a neighbour that explains why it is off.
    var reservesReason = false
    let select: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                if available { select() } else { unavailableAction?() }
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                        .foregroundStyle(included && available ? Color.accentColor : .secondary)
                    Text(title).font(.system(size: 11, weight: .medium)).lineLimit(2)
                        .multilineTextAlignment(.center).frame(height: 28)
                    if unavailableReason != nil || reservesReason {
                        // A fixed area leaves every card in a row the same height;
                        // the full reason is also in the tooltip.
                        Text(unavailableReason ?? " ").font(.caption2)
                            .foregroundStyle(unavailableAction == nil ? Color.secondary : Color.accentColor)
                            .multilineTextAlignment(.center).lineLimit(3, reservesSpace: true)
                            .accessibilityHidden(unavailableReason == nil)
                    }
                }.frame(maxWidth: .infinity, minHeight: 76).padding(10)
                    .background(selected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1) }
            }.buttonStyle(.plain).disabled(!available && unavailableAction == nil)
                .accessibilityAddTraits(selected ? .isSelected : [])
            Button {
                if available { included.toggle() } else { unavailableAction?() }
            } label: {
                Image(systemName: !available ? (unavailableAction == nil ? "minus.circle" : "arrow.up.right.circle")
                      : included ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 15)).foregroundStyle(included && available ? Color.accentColor : .secondary)
                    .frame(width: 28, height: 28).contentShape(Circle())
            }.buttonStyle(.plain).disabled(!available && unavailableAction == nil)
                .accessibilityLabel(!available ? unavailableReason ?? title : title)
                .accessibilityAddTraits(included && available ? .isSelected : [])
        }.help(unavailableReason ?? title)
    }
}
